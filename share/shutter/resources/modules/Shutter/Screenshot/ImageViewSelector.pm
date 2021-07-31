package Shutter::Screenshot::ImageViewSelector;
use base 'Gtk3::ImageView::Tool::Selector';

use strict;
use warnings;
use Glib qw(TRUE FALSE);
use Readonly;
use List::Util qw(min);
Readonly my $RIGHT_BUTTON  => 3;
Readonly my $EDGE_WIDTH => 5 * ($ENV{GDK_SCALE} // 1);

sub new {
	my $self = &Gtk3::ImageView::Tool::new;
	$self->{dragging} = undef;  # cursor type during drag to determine the type of the drag: edge, corner, etc
	return $self;
}

sub button_pressed {
	my ($self, $event) = @_;
	if ($event->button == $RIGHT_BUTTON) {
		return FALSE;
	}
	my $type = $self->cursor_type_at_point($event->x, $event->y);
	if ($type eq 'grab') {
		$type = 'grabbing';
		$self->{drag_start_x} = $event->x;
		$self->{drag_start_y} = $event->y;
	}
	$self->{dragging} = $type;
	$self->_update_selection($event->x, $event->y);
	return FALSE;
}

sub button_released {
	my ($self, $event) = @_;
	if ($event->button == $RIGHT_BUTTON) {
		return FALSE;
	}
	if ($self->{dragging}) {
		$self->_update_selection($event->x, $event->y);
	}
	$self->{dragging} = undef;
	$self->view->update_cursor($event->x, $event->y);
	return FALSE;
}

sub motion {
	my ($self, $event) = @_;
	if ($self->{dragging}) {
		$self->_update_selection($event->x, $event->y);
	}
	return FALSE;
}

sub cursor_type_at_point {
	my ($self, $x, $y) = @_;
	if ($self->{dragging}) {
		return $self->{dragging};
	}
	my $selection = $self->view->get_selection;
	if (!defined $selection) {
		return 'crosshair';
	}
	my ($sx1, $sy1) = $self->view->to_widget_coords($selection->{x}, $selection->{y});
	my ($sx2, $sy2) = $self->view->to_widget_coords($selection->{x} + $selection->{width}, $selection->{y} + $selection->{height});
	if ($x < $sx1 - $EDGE_WIDTH || $x > $sx2 + $EDGE_WIDTH || $y < $sy1 - $EDGE_WIDTH || $y > $sy2 + $EDGE_WIDTH) {
		return 'crosshair';
	}
	if ($x > $sx1 + $EDGE_WIDTH && $x < $sx2 - $EDGE_WIDTH && $y > $sy1 + $EDGE_WIDTH && $y < $sy2 - $EDGE_WIDTH) {
		return 'grab';
	}
	# This makes it possible for the selection to be smaller than EDGE_WIDTH and still be resizeable in all directions
	my $leftish = $x < ($sx1 + $sx2) / 2;
	my $topish = $y < ($sy1 + $sy2) / 2;
	if ($y > $sy1 + $EDGE_WIDTH && $y < $sy2 - $EDGE_WIDTH) {
		if ($leftish) {
			return 'w-resize';
		} else {
			return 'e-resize';
		}
	}
	if ($x > $sx1 + $EDGE_WIDTH && $x < $sx2 - $EDGE_WIDTH) {
		if ($topish) {
			return 'n-resize';
		} else {
			return 's-resize';
		}
	}
	if ($leftish) {
		if ($topish) {
			return 'nw-resize';
		} else {
			return 'sw-resize';
		}
	} else {
		if ($topish) {
			return 'ne-resize';
		} else {
			return 'se-resize';
		}
	}
}

sub _update_selection {
	my ($self, $x, $y) = @_;
	my $selection = $self->view->get_selection // {
		x => 0,
		y => 0,
		width => 0,
		height => 0,
	};
	my ($sel_x1, $sel_y1) = $self->view->to_widget_coords(
		$selection->{x},
		$selection->{y});
	my ($sel_x2, $sel_y2) = $self->view->to_widget_coords(
		$selection->{x} + $selection->{width},
		$selection->{y} + $selection->{height});
	my $type = $self->{dragging};
	if ($type eq 'grabbing') {
		my $off_x = $x - $self->{drag_start_x};
		my $off_y = $y - $self->{drag_start_y};
		$sel_x1 += $off_x;
		$sel_x2 += $off_x;
		$sel_y1 += $off_y;
		$sel_y2 += $off_y;
		$self->{drag_start_x} = $x;
		$self->{drag_start_y} = $y;
	}
	if ($type eq 'crosshair') {
		$sel_x1 = $x;
		$sel_x2 = $x;
		$sel_y1 = $y;
		$sel_y2 = $y;
		$type = 'se-resize';
	}
	my $flip_we = 0;
	my $flip_ns = 0;
	if ($type =~ /w-resize/) {
		$sel_x1 = $x;
		$flip_we = 'e' if ($x > $sel_x2);
	}
	if ($type =~ /e-resize/) {
		$sel_x2 = $x;
		$flip_we = 'w' if ($x < $sel_x1);
	}
	if ($type =~ /n.?-resize/) {
		$sel_y1 = $y;
		$flip_ns = 's' if ($y > $sel_y2);
	}
	if ($type =~ /s.?-resize/) {
		$sel_y2 = $y;
		$flip_ns = 'n' if ($y < $sel_y1);
	}
	my ($w, $h) = $self->view->to_image_distance(abs($sel_x2 - $sel_x1), abs($sel_y2 - $sel_y1));
	my ($img_x, $img_y) = $self->view->to_image_coords(min($sel_x1, $sel_x2), min($sel_y1, $sel_y2));
	$self->view->set_selection({
		x => int($img_x + 0.5),
		y => int($img_y + 0.5),
		width => int($w + 0.5),
		height => int($h + 0.5),
	});
	# Prepare for next mouse event
	# If we are dragging, a corner cursor must stay as a corner cursor,
	# a left/right cursor must stay as left/right,
	# and a top/bottom cursor must stay as top/bottom
	if ($flip_we) {
		$type =~ s/[we]-/$flip_we-/;
	}
	if ($flip_ns) {
		$type =~ s/^[ns]/$flip_ns/;
	}
	$self->{dragging} = $type;
	$self->view->update_cursor($x, $y);
}

1;
