package Shutter::Screenshot::Popup;

use utf8;
use strict;
use warnings;
use Gtk3;
use Gtk3::ImageView;

# Coordinates come from ImageView in source-image pixels, even when the
# preview is scaled to fit. Never capture the desktop again after selection.
sub crop_region {
	my ($pixbuf, $region) = @_;
	return unless defined $region;
	my ($x, $y, $w, $h) = @{$region}{qw/x y width height/};
	return unless defined $x && defined $y && defined $w && defined $h;
	if ($x < 0) { $w += $x; $x = 0; }
	if ($y < 0) { $h += $y; $y = 0; }
	$w = $pixbuf->get_width - $x if $x + $w > $pixbuf->get_width;
	$h = $pixbuf->get_height - $y if $y + $h > $pixbuf->get_height;
	return if $w <= 0 || $h <= 0;
	return $pixbuf->new_subpixbuf($x, $y, $w, $h)->copy;
}

sub select_region {
	my ($sc, $pixbuf) = @_;
	my $d = $sc->get_gettext;
	my $dialog = Gtk3::Dialog->new(
		$d->get("Select the menu or tooltip"), $sc->get_mainwindow,
		['modal', 'destroy-with-parent'], 'gtk-cancel' => 'cancel', 'gtk-ok' => 'ok');
	$dialog->set_default_size(900, 650);
	$dialog->set_default_response('ok');
	$dialog->set_response_sensitive('ok', 0);

	my $content = $dialog->get_content_area;
	my $label = Gtk3::Label->new($d->get("Drag a selection rectangle to choose the menu or tooltip, then confirm."));
	$label->set_line_wrap(1);
	$content->pack_start($label, 0, 0, 8);
	my $view = Gtk3::ImageView->new;
	$view->set_tool(Gtk3::ImageView::Tool::Selector->new($view));
	$view->set_pixbuf($pixbuf);
	# Fit only after GTK allocates the preview; fitting a 1-pixel placeholder
	# can request a zoom below ImageView's supported minimum on large screens.
	my $fitted;
	$view->signal_connect('size-allocate' => sub {
		my ($widget, $allocation) = @_;
		if (!$fitted && $allocation->{width} > 1 && $allocation->{height} > 1) {
			$fitted = 1;
			$widget->set_zoom_to_fit(1);
		}
	});
	$content->pack_start($view, 1, 1, 0);
	$view->signal_connect('selection-changed' => sub {
		my $region = $view->get_selection;
		$dialog->set_response_sensitive('ok', defined $region && $region->{width} > 0 && $region->{height} > 0);
	});

	my $output;
	eval {
		$dialog->show_all;
		$view->grab_focus;
		while ($dialog->run eq 'ok') {
			$output = crop_region($pixbuf, $view->get_selection);
			last if defined $output;
		}
	};
	my $error = $@;
	$dialog->destroy;
	die $error if $error;
	return $output;
}

1;
