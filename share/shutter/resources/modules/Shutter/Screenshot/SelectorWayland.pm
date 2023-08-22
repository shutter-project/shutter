use utf8;
use strict;
use warnings;
use Net::DBus;
use Net::DBus::Reactor;
use Class::Struct;
use Data::Dumper;

package Shutter::Screenshot::SelectorWayland;

sub xdg_portal {
	my $screenshooter = shift;
	my $reactor = Net::DBus::Reactor->main;
	my $bus = Net::DBus->find;
	my $me = $bus->get_unique_name;
	$me =~ s/\./_/g;
	$me =~ s/^://g;

	my $pixbuf;
	my $output;

	#eval {
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
		if ($num != 0) {
			$screenshooter->{_error_text} = "Response $num from XDG portal";
			return 9;
		}
		my $giofile = Glib::IO::File::new_for_uri($output->{uri});
		print "xdg portal: got file ".$giofile->get_path."\n";
		$pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($giofile->get_path);
		my $slurpoutput = `slurp`;
		my ($x, $y, $width, $height) = split /[,x ]/, $slurpoutput;
		my $s = {
			'y' 		=> $y,
			'width' 	=> $width,
			'height'	=> $height,
			'x'			=> $x
		};

		$output = take_screenshot($s, $pixbuf);
		$giofile->delete;
	#};
	if ($@) {
		$screenshooter->{_error_text} = $@;
		return 9;
	};

	return $output;
}

sub take_screenshot {
	#my $self         = shift;
	my $s            = shift;
	my $clean_pixbuf = shift;

	#my $d = $self->{_sc}->get_gettext;

	my $output;

	#no delay? then we take a subsection of the pixbuf in memory
	if ($s && $clean_pixbuf ) {

		$output = $clean_pixbuf->new_subpixbuf($s->{x}, $s->{y}, $s->{width}, $s->{height});

		print "DEBUG OUTPUT=" . $output . "\n";

		#if there is a delay != 0 set, we have to wait and get a new pixbuf from the root window
	} else {
		$output = 0;
	}

	return $output;
}

1;
