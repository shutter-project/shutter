use utf8;
use strict;
use warnings;
use Net::DBus;
use Net::DBus::Reactor;

package Shutter::Screenshot::Wayland;

use Shutter::Screenshot::History;

#Object wrapper around the portal so full/monitor captures can be repeated
#(e.g. via the redoshot/F5 shortcut) just like the X11 screenshooters.
sub new {
	my $class = shift;
	my $self = {
		_sc      => shift,
		_monitor => shift,    #undef captures the whole desktop
	};
	$self->{_gdk_screen} = Gtk3::Gdk::Screen::get_default();
	bless $self, $class;
	return $self;
}

sub capture {
	my $self = shift;

	my $pixbuf = xdg_portal($self);
	return $pixbuf unless ref($pixbuf) && $pixbuf->isa('Gtk3::Gdk::Pixbuf');

	if (defined $self->{_monitor}) {
		$pixbuf = crop_to_monitor($pixbuf, $self->{_gdk_screen}, $self->{_monitor});
	}

	#a history marker makes this capture repeatable through redoshot
	$self->{_history} = Shutter::Screenshot::History->new($self->{_sc});
	return $pixbuf;
}

sub redo_capture {
	my $self = shift;
	return 3 unless defined $self->{_history};
	return $self->capture;
}

sub get_history {
	my $self = shift;
	return $self->{_history};
}

sub get_error_text {
	my $self = shift;
	return $self->{_error_text};
}

sub xdg_portal {
	my $screenshooter = shift;
	my $reactor = Net::DBus::Reactor->main;
	my $bus = Net::DBus->find;
	my $me = $bus->get_unique_name;
	$me =~ s/\./_/g;
	$me =~ s/^://g;

	my $pixbuf;
	my $portal_error;

	eval {
		my $portal_service = $bus->get_service('org.freedesktop.portal.Desktop');
		my $portal = $portal_service->get_object('/org/freedesktop/portal/desktop', 'org.freedesktop.portal.Screenshot');

		my $num;
		my $output;
		my $cb = sub {
			($num, $output) = @_;
			$reactor->shutdown;
		};

		my $token = 'shutter' . rand;
		$token =~ s/\.//g;
		my $request = $portal_service->get_object("/org/freedesktop/portal/desktop/request/$me/$token", 'org.freedesktop.portal.Request');
		my $conn = $request->connect_to_signal(Response => $cb);
		my $request_path = $portal->Screenshot('', {handle_token=>$token});
		if ($request->get_object_path ne $request_path) {
			$request->disconnect_from_signal(Response => $conn);
			$request = $portal_service->get_object($request_path, 'org.freedesktop.portal.Request');
			$conn = $request->connect_to_signal(Response => $cb);
		}
		$reactor->run;
		$request->disconnect_from_signal(Response => $conn);

		#a "return" here would only exit the eval and leave the caller with an
		#undef pixbuf, so record the failure and bail out after the eval instead
		if (!defined $num || $num != 0) {
			$portal_error = "Response " . (defined $num ? $num : "timeout") . " from XDG portal";
			return;
		}
		unless (defined $output && defined $output->{uri}) {
			$portal_error = "XDG portal returned no screenshot URI";
			return;
		}
		my $giofile = Glib::IO::File::new_for_uri($output->{uri});
		print "xdg portal: got file ".$giofile->get_path."\n";
		$pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($giofile->get_path);
		$giofile->delete;
	};
	if ($@) {
		$screenshooter->{_error_text} = $@;
		return 9;
	}
	if (defined $portal_error) {
		$screenshooter->{_error_text} = $portal_error;
		return 9;
	}

	return $pixbuf;
}

#The XDG portal always returns the whole desktop spanning every monitor. Crop
#that pixbuf down to a single monitor's area so users can capture just one.
sub crop_to_monitor {
	my ($pixbuf, $gdk_screen, $monitor) = @_;

	return $pixbuf unless defined $pixbuf && defined $gdk_screen && defined $monitor;

	my $geo = $gdk_screen->get_monitor_geometry($monitor);
	return $pixbuf unless $geo;

	#Monitor geometry is in logical pixels while the portal captures device
	#pixels; derive the scale from the full desktop size to stay correct on HiDPI.
	my $screen_w = $gdk_screen->get_width  || $pixbuf->get_width;
	my $screen_h = $gdk_screen->get_height || $pixbuf->get_height;
	my $scale_x  = $pixbuf->get_width  / $screen_w;
	my $scale_y  = $pixbuf->get_height / $screen_h;

	my $x = int($geo->{x} * $scale_x);
	my $y = int($geo->{y} * $scale_y);
	my $w = int($geo->{width}  * $scale_x);
	my $h = int($geo->{height} * $scale_y);

	#clamp to the captured area
	$x = 0 if $x < 0;
	$y = 0 if $y < 0;
	$w = $pixbuf->get_width  - $x if $x + $w > $pixbuf->get_width;
	$h = $pixbuf->get_height - $y if $y + $h > $pixbuf->get_height;
	return $pixbuf if $w <= 0 || $h <= 0;

	my $cropped = Gtk3::Gdk::Pixbuf->new('rgb', $pixbuf->get_has_alpha, 8, $w, $h);
	$pixbuf->copy_area($x, $y, $w, $h, $cropped, 0, 0);
	return $cropped;
}

1;
