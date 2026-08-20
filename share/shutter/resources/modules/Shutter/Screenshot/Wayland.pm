use utf8;
use strict;
use warnings;
use Net::DBus::Reactor;
use Net::DBus;

package Shutter::Screenshot::Wayland;

use Shutter::Screenshot::History;

#Object wrapper around the portal so full/monitor captures can be repeated
#(e.g. via the redoshot/F5 shortcut) just like the X11 screenshooters.
sub new {
	my $class = shift;
	my $self = {
		_sc     		=> shift,
		_interactive 	=> shift,	# whether to use the desktop environment's GUI (only for the time till DEs support non-interactive calls)
		_target  		=> shift,	# screenshot mode (full, select, window, awindow) to send to xdg-portal
		_monitor		=> shift,  	# undef captures the whole desktop
		};
	$self->{_gdk_screen} = Gtk3::Gdk::Screen::get_default();
	bless $self, $class;
	return $self;
}

sub redo_capture {
	my $self = shift;
	return 3 unless defined $self->{_history};
	return $self->xdg_portal;
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
	my $self = shift;
	my $d = $self->{_sc}->get_gettext;
	# Fall back to fullscreen
	$self->{_target} = 1 unless defined $self->{_target};

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

		my %options = (handle_token => $token);

		# set the interactive flag unless xdg-portal doesn't support non-interactive calls and we want full-screen capture
		$options{interactive} = Net::DBus::dbus_boolean($self->{_interactive}) unless $self->{_interactive} eq 1 && $self->{_target} eq 1;

		# only define a target if xdg-portal supports non-interactive calls
		$options{target} = Net::DBus::dbus_uint32($self->{_target}) if $self->{_interactive} ne 1;

		my $request_path = $portal->Screenshot('', \%options);

		if ($request->get_object_path ne $request_path) {
			$request->disconnect_from_signal(Response => $conn);
			$request = $portal_service->get_object($request_path, 'org.freedesktop.portal.Request');
			$conn = $request->connect_to_signal(Response => $cb);
		}

		$reactor->run;

		$request->disconnect_from_signal(Response => $conn);
		if (!defined $num || $num != 0) {
            if (defined $num && $num == 1) {
                # portal Response: 1 = user cancelled -> treat as abort (code 5), not error
                return 5;
            }
            $portal_error = "Response " . (defined $num ? $num : "timeout") . " from XDG portal";
            return;
        }
        unless (defined $output && defined $output->{uri}) {
            $portal_error = "XDG portal returned no screenshot URI";
            return;
        }
		my $giofile = Glib::IO::File::new_for_uri($output->{uri});
		print "xdg portal: got temp file ".$giofile->get_path."\n" if $self->{_sc}->get_debug;
		$pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($giofile->get_path);

		$giofile->delete;
	};
	if (defined $self->{_monitor}) {
		$pixbuf = crop_to_monitor($pixbuf, $self->{_gdk_screen}, $self->{_monitor});
	}

	#a history marker makes this capture repeatable through redoshot
	$self->{_history} = Shutter::Screenshot::History->new($self->{_sc});
	if ($@) {
		$self->{_error_text} = $@;
		return 9;
	}
	if (defined $portal_error) {
		$self->{_error_text} = $portal_error;
		return 9;
	}

	# get name
	if ($self->{_target} eq 1) {
		if (defined $self->{_monitor}) {
			$self->{_action_name} = $self->{_gdk_screen}->get_monitor_plug_name($self->{_monitor});
		} else {
			$self->{_action_name} = $d->get("Workspaces");
		}
	} elsif ($self->{_target} eq 2 || $self->{_target} eq 8) {
		$self->{_action_name} = $d->get("Window");
	} elsif ($self->{_target} eq 4) {
		my $selection_text = $d->get("Selection");
		my $swidth  = $pixbuf->get_width;
		my $sheight = $pixbuf->get_height;
		if (defined $swidth && defined $sheight) {
			$self->{_action_name} = "${selection_text}_${swidth}x${sheight}";
		} else {
			$self->{_action_name} = $selection_text;
		}
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

sub get_action_name {
	my $self = shift;
	return $self->{_action_name};
}

1;
