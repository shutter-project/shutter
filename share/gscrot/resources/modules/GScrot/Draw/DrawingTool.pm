###################################################
#
#  Copyright (C) Mario Kemper 2008 <mario.kemper@googlemail.com>
#
#  This file is part of GScrot.
#
#  GScrot is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  GScrot is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with GScrot; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###################################################

package GScrot::Draw::DrawingTool;

our ( @ISA, @EXPORT );
@ISA    = qw(Exporter);
@EXPORT = qw(&fct_start_drawing);

#modules
#--------------------------------------
use utf8;
use strict;
use Exporter;
use Goo::Canvas;

#--------------------------------------

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { _gscrot_common => shift };

	$self->{_factory} = undef;

	$self->{_canvas} = undef;

	$self->{_current_mode} = 10;

	bless $self, $class;

	return $self;
}

sub show {
	my $self     = shift;
	my $filename = shift;
	my $filetype = shift;

	my $d = $self->{_gscrot_common}->get_gettext;

	$self->{_drawing_window} = Gtk2::Window->new('toplevel');
	$self->{_drawing_window}->set_title($filename);
	$self->{_drawing_window}->set_modal(1);
	$self->{_drawing_window}->signal_connect( 'destroy', \&quit );
	$self->{_drawing_window}
		->signal_connect( 'delete_event', sub { $self->{_drawing_window}->destroy() } );

	#load file
	$self->{_drawing_pixbuf} = Gtk2::Gdk::Pixbuf->new_from_file($filename);

	#create canvas
	$self->{_canvas} = Goo::Canvas->new();
	$self->{_canvas}->set_size_request( 640, 480 );

	$self->{_canvas}->modify_bg( 'normal', Gtk2::Gdk::Color->new( 0xFFFF, 0xFFFF, 0xFFFF ) );

	$self->{_canvas}->set_bounds(
		0, 0,
		$self->{_drawing_pixbuf}->get_width,
		$self->{_drawing_pixbuf}->get_height
	);
	my $root = $self->{_canvas}->get_root_item;
	$root->signal_connect( 'button_press_event', \&event_on_background_button_press );

	$self->{_canvas_bg} = Goo::Canvas::Image->new( $root, $self->{_drawing_pixbuf}, 0, 0 );

	#define own icons
	my $dicons = $self->{_gscrot_common}->get_root . "/share/gscrot/resources/icons/drawing_tool";
	$self->{_factory} = Gtk2::IconFactory->new();
  	$self->{_factory}->add('gscrot-ellipse', Gtk2::IconSet->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-ellipse.png")));
  	$self->{_factory}->add('gscrot-eraser', Gtk2::IconSet->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-eraser.png")));
  	$self->{_factory}->add('gscrot-freehand', Gtk2::IconSet->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-freehand.png")));
  	$self->{_factory}->add('gscrot-pointer', Gtk2::IconSet->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-pointer.png")));
  	$self->{_factory}->add('gscrot-rectangle', Gtk2::IconSet->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-rectangle.png")));
  	$self->{_factory}->add('gscrot-star', Gtk2::IconSet->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-star.png")));
  	$self->{_factory}->add('gscrot-text', Gtk2::IconSet->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-text.png")));
	$self->{_factory}->add_default();

	my @toolbar_actions = (
		[ "Quit",    'gtk-quit',     undef, undef,            undef, sub { &quit($self) } ],
		[ "Save",    'gtk-save',     undef, "<control>S",     undef, sub { &save($self) } ],
		[ "ZoomIn",  'gtk-zoom-in',  undef, "<control>plus",  undef, sub { &zoom_in_cb($self) } ],
		[ "ZoomOut", 'gtk-zoom-out', undef, "<control>minus", undef, sub { &zoom_out_cb($self) } ],
		[   "ZoomNormal", 'gtk-zoom-100', undef, "<control>0", undef, sub { &zoom_normal_cb($self) }
		]
	);

	my @toolbar_drawing_actions = (
		[ "Select", 'gscrot-pointer',  $d->get("Select item"),  undef,  $d->get("Select item to move or resize it"),  10 ],
		[   "Line", 'gscrot-freehand', $d->get("Draw a simple freehand line"), undef,
			$d->get("Draw a line using the freehand tool"), 20
		],
		[   "Rect", 'gscrot-rectangle', "_Normal Size", "<control>0",
			"Set zoom to natural size of the image", 30
		],
		[ "Ellips", 'gscrot-ellipse',   "Best _Fit", undef, "Adapt zoom to fit image",  40 ],
		[ "Image",  'gscrot-star',   "Best _Fit", undef, "Adapt zoom to fit image",  50 ],
		[ "Text",   'gscrot-text', undef,       "F11", "View image in fullscreen", 60 ],
		[ "Clear",  'gscrot-eraser',      undef,       "F11", undef,                      70 ]
	);

	my $uimanager = Gtk2::UIManager->new();

	# Setup the image group.
	my $toolbar_group = Gtk2::ActionGroup->new("image");
	$toolbar_group->add_actions( \@toolbar_actions );

	$uimanager->insert_action_group( $toolbar_group, 0 );

	# Setup the drawing group.
	my $toolbar_drawing_group = Gtk2::ActionGroup->new("drawing");
	$toolbar_drawing_group->add_radio_actions( \@toolbar_drawing_actions, 10,
		sub { my $action = shift; &change_drawing_tool_cb( $self, $action ); } );

	$uimanager->insert_action_group( $toolbar_drawing_group, 0 );

	my $ui_info = "
<ui>
  <toolbar name = 'ToolBar'>
    <toolitem action='Quit'/>
    <toolitem action='Save'/>
    <separator/>
    <toolitem action='ZoomIn'/>
    <toolitem action='ZoomOut'/>
    <toolitem action='ZoomNormal'/>
  </toolbar>
  <toolbar name = 'ToolBarDrawing'>
    <separator/>
    <toolitem action='Select'/>
    <separator/>
    <toolitem action='Line'/>
    <toolitem action='Rect'/>
    <toolitem action='Ellips'/>
    <toolitem action='Text'/>
    <toolitem action='Image'/>
    <separator/>
    <toolitem action='Clear'/>
  </toolbar>  
</ui>";

	eval { $uimanager->add_ui_from_string($ui_info) };

	if ($@) {
		die "Unable to create menus: $@\n";
	}

	# Width
	my $width_label = Gtk2::Label->new( $self->{_gscrot_common}->get_gettext->get("Width:") );
	my $sb_width = Gtk2::SpinButton->new_with_range( 1, 20, 1 );
	$sb_width->set_value(3);

	# create a color button
	my $col_label = Gtk2::Label->new( $self->{_gscrot_common}->get_gettext->get("Color:") );
	my $colbut1   = Gtk2::ColorButton->new();
	$colbut1->set_color( Gtk2::Gdk::Color->new( 0xFFFF, 0, 0 ) );

	# a save button
	my $save_button = Gtk2::Button->new_from_stock('gtk-save');

	# .. And a quit button
	my $quit_button = Gtk2::Button->new_from_stock('gtk-close');
	$quit_button->signal_connect( clicked => sub { $self->{_drawing_window}->destroy() } );

	my @stipple_data = ( 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255 );
	my $pattern = create_stipple( 'cadetblue', \@stipple_data );
	my $ellipse3 = Goo::Canvas::Ellipse->new(
		$root, 245, 110, 35, 30,
		'fill-pattern' => $pattern,
		'stroke-color' => 'black',
		'line-width'   => 1,
	);
	setup_item_signals($ellipse3);

	#packing
	my $scrolled_drawing_window = Gtk2::ScrolledWindow->new;
	$scrolled_drawing_window->set_policy( 'automatic', 'automatic' );
	$scrolled_drawing_window->add( $self->{_canvas} );

	my $drawing_vbox = Gtk2::VBox->new( FALSE, 0 );

	#	my $drawing_box_buttons = Gtk2::HBox->new( FALSE, 0 );
	my $drawing_hbox = Gtk2::HBox->new( FALSE, 0 );

	$self->{_drawing_window}->add($drawing_vbox);

	#	my $halign = Gtk2::Alignment->new( 1, 0, 0, 0 );
	#	$drawing_box_buttons->add($halign);
	#	$drawing_box_buttons->pack_start( $width_label, FALSE, FALSE, 0 );
	#	$drawing_box_buttons->pack_start( $sb_width,    FALSE, FALSE, 5 );
	#	$drawing_box_buttons->pack_start( $col_label,   FALSE, FALSE, 0 );
	#	$drawing_box_buttons->pack_start( $colbut1,     FALSE, FALSE, 5 );
	#	$drawing_box_buttons->pack_start( $zoom_label,  FALSE, FALSE, 0 );
	#	$drawing_box_buttons->pack_start( $sb_zoom,     FALSE, FALSE, 5 );
	#	$drawing_box_buttons->pack_start( $save_button, FALSE, FALSE, 5 );
	#	$drawing_box_buttons->pack_start( $quit_button, FALSE, FALSE, 5 );

	my $toolbar_drawing = $uimanager->get_widget("/ToolBarDrawing");
	$toolbar_drawing->set_orientation('vertical');
	$drawing_hbox->pack_start( $toolbar_drawing,         FALSE, FALSE, 0 );
	$drawing_hbox->pack_start( $scrolled_drawing_window, FALSE, FALSE, 0 );

	#	$drawing_boxh->pack_start( $drawing_box_buttons,     FALSE, FALSE, 5 );

	my $toolbar = $uimanager->get_widget("/ToolBar");
	$drawing_vbox->pack_start( $uimanager->get_widget("/ToolBar"), FALSE, FALSE, 0 );

	my $drawing_statusbar = Gtk2::Statusbar->new;
	$drawing_vbox->pack_start( $drawing_hbox,      FALSE, FALSE, 0 );
	$drawing_vbox->pack_start( $drawing_statusbar, FALSE, FALSE, 0 );

	$self->{_drawing_window}->show_all();

	setup_main_window();

	Gtk2->main;

	return TRUE;
}

sub setup_main_window {

	return TRUE;
}

sub change_drawing_tool_cb {
	my $self   = shift;
	my $action = shift;

	$self->{_current_mode}->{value} = $action->get_current_value;

	if ( $self->{_current_mode}->{value} == 10 ) {
		$self->{_current_mode}->{descr} = "select";
	} elsif ( $self->{_current_mode}->{value} == 20 ) {
		$self->{_current_mode}->{descr} = "drag";
	} elsif ( $self->{_current_mode}->{value} == 30 ) {
		$self->{_current_mode}->{descr} = "line";
	} elsif ( $self->{_current_mode}->{value} == 40 ) {
		$self->{_current_mode}->{descr} = "rect";
	} elsif ( $self->{_current_mode}->{value} == 50 ) {
		$self->{_current_mode}->{descr} = "ellips";
	} elsif ( $self->{_current_mode}->{value} == 60 ) {
		$self->{_current_mode}->{descr} = "image";
	} elsif ( $self->{_current_mode}->{value} == 70 ) {
		$self->{_current_mode}->{descr} = "text";
	} elsif ( $self->{_current_mode}->{value} == 80 ) {
		$self->{_current_mode}->{descr} = "clear";
	}

	return TRUE;
}

#sub event_drawing_handler {
#	my ( $widget, $event ) = @_;
#	my $scale = $adj_zoom->get_value;
#	if ( $event->type eq "button-press" ) {
#		$draw_flag = 1;
#
#		#start a new line curve
#		$count++;
#		my ( $x, $y ) = ( $event->x, $event->y );
#
#		$lines{$count}{'points'}
#			= [ $x / $scale, $y / $scale, $x / $scale, $y / $scale ];    #need at least 2 points
#
#		#		$lines{$count}{'line'} = Goo::Canvas::Polyline->new_line(
#		#			$root,                       $lines{$count}{'points'}[0], $lines{$count}{'points'}[1],
#		#			$lines{$count}{'points'}[2], $lines{$count}{'points'}[3]
#		#		);
#
#		#		$lines{$count}{'line'} = Goo::Canvas::Rect->new(
#		#			$root,                       $lines{$count}{'points'}[0], $lines{$count}{'points'}[1],
#		#			$lines{$count}{'points'}[2], $lines{$count}{'points'}[3]
#		#		);
#
#	}
#	if ( $event->type eq "button-release" ) {
#		$draw_flag = 0;
#	}
#
#	if ( $event->type eq "focus-change" ) {
#		return 0;
#	}
#
#	if ( $event->type eq "expose" ) {
#		return 0;
#	}
#
#	if ($draw_flag) {
#
#		#left with motion-notify
#		if ( $event->type eq "motion-notify" ) {
#			my ( $x, $y ) = ( $event->x, $event->y );
#			push @{ $lines{$count}{'points'} }, $x / $scale, $y / $scale;
#			$lines{$count}{'line'}
#				->set( points => Goo::Canvas::Points->new( $lines{$count}{'points'} ) );
#
#		}
#	}
#}

sub zoom_in_cb {
	my $self = shift;
	$self->{_canvas}->set_scale( $self->{_canvas}->get_scale + 0.5 );
	return TRUE;
}

sub zoom_out_cb {
	my $self      = shift;
	my $new_scale = $self->{_canvas}->get_scale - 0.5;
	if ( $new_scale > 1 ) {
		$self->{_canvas}->set_scale($new_scale);
	} else {
		$self->{_canvas}->set_scale(1);
	}
	return TRUE;
}

sub zoom_normal_cb {
	my $self = shift;
	$self->{_canvas}->set_scale(1);
	return TRUE;
}

sub quit {
	my $self = shift;
	$self->{_drawing_window}->destroy if $self->{_drawing_window};
	Gtk2->main_quit();
	return TRUE;
}

sub save {
	my $self = shift;

	#enter routine to save here
	return TRUE;
}

#handle events here
sub event_on_background_button_press {
	return TRUE;
}

#ITEM SIGNALS
sub setup_item_signals {
	my $item = shift;
	$item->signal_connect( 'motion_notify_event',  \&event_item_on_motion_notify );
	$item->signal_connect( 'button_press_event',   \&event_item_on_button_press );
	$item->signal_connect( 'button_release_event', \&event_item_on_button_release );
}

sub event_item_on_motion_notify {
	my ( $item, $target, $ev ) = @_;

	#	print "Ev state: ", $ev->state, "\n";
	if ( $item->{dragging} && $ev->state >= 'button1-mask' ) {

		#        $item->translate($ev->x - $item->{drag_x},
		#                         $ev->y - $item->{drag_y});

#		my ($evtx_canv, $evty_canv) = $self->{_canvas}->convert_from_pixels($ev->x, $ev->y);
#		($evtx_canv, $evty_canv) = $self->{_canvas}->convert_to_item_space($item, $evtx_canv, $evty_canv);

		my $new_x = abs( $ev->x - $item->get('center-x') );
		my $new_y = abs( $ev->y - $item->get('center-y') );

		$item->set(
			'radius-x' => $new_x,
			'radius-y' => $new_y,
		);

	}
	return TRUE;
}

sub event_item_on_button_press {
	my ( $item, $target, $ev ) = @_;
	if ( $ev->button == 1 ) {
		if ( $ev->state >= 'shift-mask' ) {
			my $parent = $item->get_parent;
			$parent->remove_child( $parent->find_child($item) );
		} else {
			$item->{drag_x} = $ev->x;
			$item->{drag_y} = $ev->y;
			my $fleur = Gtk2::Gdk::Cursor->new('fleur');
			my $self->{_canvas} = $item->get_canvas;
			$self->{_canvas}->pointer_grab( $item, [ 'pointer-motion-mask', 'button-release-mask' ],
				$fleur, $ev->time );
			$item->{dragging} = TRUE;

		}
	} elsif ( $ev->button == 2 ) {
		$item->lower;
	} elsif ( $ev->button == 3 ) {
		$item->raise;
	}
	return TRUE;
}

sub event_item_on_button_release {
	my ( $item, $target, $ev ) = @_;
	my $self->{_canvas} = $item->get_canvas;
	$self->{_canvas}->pointer_ungrab( $item, $ev->time );
	$item->{dragging} = FALSE;
	return TRUE;
}

sub create_stipple {
	our @stipples;
	my ( $color_name, $stipple_data ) = @_;
	my $color = Gtk2::Gdk::Color->parse($color_name);
	$stipple_data->[2] = $stipple_data->[14] = $color->red >> 8;
	$stipple_data->[1] = $stipple_data->[13] = $color->green >> 8;
	$stipple_data->[0] = $stipple_data->[12] = $color->blue >> 8;
	my $stipple_str = join( '', map {chr} @$stipple_data );
	push @stipples, \$stipple_str;    # make $stipple_str refcnt increase
	my $surface = Cairo::ImageSurface->create_for_data( $stipple_str, 'argb32', 2, 2, 8 );
	my $pattern = Cairo::SurfacePattern->create($surface);
	$pattern->set_extend('repeat');
	return Goo::Cairo::Pattern->new($pattern);
}

1;
