#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Shutter::Screenshot::Wayland;

# Exercise portal responses without a desktop session or image files.
{
    package WaylandTest::Object;
    use strict;
    use warnings;
    sub new { bless {}, shift }
    sub get_gettext { shift }
    sub get { $_[1] }
    sub get_debug { 0 }
    sub get_unique_name { ':1.42' }
    sub get_service { shift }
    sub get_object { shift }
    sub get_object_path { '/request/test' }
    sub connect_to_signal { $_[0]->{callback} = $_[2]; 1 }
    sub disconnect_from_signal { delete $_[0]->{callback} }
    sub Screenshot {
        $_[0]->{options} = $_[2];
        die "Portal unavailable\n" if $_[0]->{throw};
        return '/request/test';
    }
    sub run { $_[0]->{callback}->($_[0]->{response}, $_[0]->{output}) }
    sub shutdown { }
    sub get_path { '/test/screenshot.png' }
    sub delete { $_[0]->{deleted}++ }
    sub get_width { 640 }
    sub get_height { 480 }
    sub get_monitor_plug_name { 'test-monitor' }
}

my $portal = WaylandTest::Object->new;
my $file = WaylandTest::Object->new;
my $pixbuf = WaylandTest::Object->new;
my $decode_error;
my $crop_calls = 0;
{
    no warnings qw/redefine once/;
    local *Net::DBus::find = sub { $portal };
    local *Net::DBus::Reactor::main = sub { $portal };
    local *Glib::IO::File::new_for_uri = sub { $file };
    local *Gtk3::Gdk::Pixbuf::new_from_file = sub {
        die "Invalid image\n" if $decode_error;
        return $pixbuf;
    };
    local *Shutter::Screenshot::Wayland::crop_to_monitor = sub {
        $crop_calls++;
        return $_[0];
    };

    for my $target (1, 2, 4, 8) {
        subtest "target $target" => sub {
            my $capture = bless {
                _sc => WaylandTest::Object->new,
                _target => $target, _interactive => 1,
                _monitor => 0, _gdk_screen => WaylandTest::Object->new,
            }, 'Shutter::Screenshot::Wayland';
            $portal->{response} = 1;
            $portal->{output} = {};
            my $before = $crop_calls;
            is($capture->xdg_portal, 5, 'cancellation is an abort');
            is($crop_calls, $before, 'cancelled image is not cropped');
            ok(!defined $capture->get_history, 'cancel does not create history');
            is($capture->redo_capture, 3, 'cannot redo an unsuccessful first capture');

            $portal->{response} = 2;
            is($capture->xdg_portal, 9, 'portal failure is an error');
            like($capture->get_error_text, qr/Response 2/, 'response error preserved');
            ok(!defined $capture->get_history, 'failure does not create history');

            $portal->{response} = undef;
            is($capture->xdg_portal, 9, 'missing response is an error');
            like($capture->get_error_text, qr/timeout/, 'missing response has details');

            $portal->{response} = 0;
            is($capture->xdg_portal, 9, 'missing URI is an error');
            like($capture->get_error_text, qr/no screenshot URI/, 'missing URI has details');

            $portal->{throw} = 1;
            is($capture->xdg_portal, 9, 'D-Bus exception is an error');
            like($capture->get_error_text, qr/Portal unavailable/, 'exception preserved');
            $portal->{throw} = 0;

            $portal->{output} = { uri => 'file:///test/screenshot.png' };
            $decode_error = 1;
            is($capture->xdg_portal, 9, 'image decoding failure is an error');
            like($capture->get_error_text, qr/Invalid image/, 'decode error preserved');
            is($crop_calls, $before, 'no error path reaches cropping');
            ok(!defined $capture->get_history, 'no error path records history');
            $decode_error = 0;

            is($capture->xdg_portal, $pixbuf, 'success returns decoded image');
            is($crop_calls, $before + 1, 'successful image is cropped');
            ok(defined $capture->get_history, 'success records history');
            ok(!defined $capture->get_error_text, 'success clears previous error');
            ok($file->{deleted}, 'temporary screenshot is deleted');
            is($capture->redo_capture, $pixbuf, 'successful capture can be repeated');

            my $history = $capture->get_history;
            $portal->{response} = 1;
            is($capture->redo_capture, 5, 'redo can be cancelled');
            is($capture->get_history, $history, 'cancel preserves previous history');
        };
    }
    for my $mode ('menu', 'tray_menu', 'tooltip', 'tray_tooltip') {
        subtest $mode => sub {
            my $popup = Shutter::Screenshot::Wayland::popup_mode($mode);
            like($popup, qr/^(menu|tooltip)$/, 'popup mode normalized');
            my $capture = bless {
                _sc => WaylandTest::Object->new, _target => 1,
                _interactive => 1, _popup_mode => $popup, _repeat_delay => 10,
            }, 'Shutter::Screenshot::Wayland';
            my ($selected, $waited) = (0, 0);
            my $cancel_selection;
            local *Shutter::Screenshot::Wayland::select_popup = sub {
                is($_[1], $pixbuf, 'selector receives the captured image');
                $selected++;
                return $cancel_selection ? undef : $pixbuf;
            };
            local *Shutter::Screenshot::Wayland::wait_for_popup = sub { $waited++ };
            $portal->{response} = 0;
            $portal->{output} = {uri => 'file:///test/screenshot.png'};
            is($capture->xdg_portal, $pixbuf, 'popup captured and selected');
            is($waited, 1, 'initial capture waits for the popup to be opened');
            is_deeply($portal->{options}->{interactive}, Net::DBus::dbus_boolean(0), 'no live chooser before capture');
            ok(!exists $portal->{options}->{target}, 'legacy portal does not receive unsupported target option');
            is($capture->get_action_name, $popup eq 'menu' ? 'Menu' : 'Tooltip', 'popup action named correctly');
            is($selected, 1, 'selector shown exactly once');
            my $history = $capture->get_history;
            $cancel_selection = 1;
            is($capture->redo_capture, 5, 'cancelling crop aborts repeat');
            is($waited, 2, 'repeat waits for the popup to be reopened');
            is($capture->get_history, $history, 'crop cancellation preserves history');
            $portal->{response} = 1;
            is($capture->xdg_portal, 5, 'portal cancellation is an abort');
            is($selected, 2, 'portal cancellation never opens selector');
            $portal->{response} = 2;
            is($capture->xdg_portal, 9, 'portal failure is an error');
            is($selected, 2, 'portal failure never opens selector');
            $capture->{_interactive} = 0;
            $portal->{response} = 0;
            $cancel_selection = 0;
            is($capture->xdg_portal, $pixbuf, 'popup works with target-aware portal');
            is_deeply($portal->{options}->{target}, Net::DBus::dbus_uint32(1), 'target-aware portal receives desktop target');
            is_deeply($portal->{options}->{interactive}, Net::DBus::dbus_boolean(0), 'target-aware portal is also non-interactive');
        };
    }
    ok(!defined Shutter::Screenshot::Wayland::popup_mode('window'), 'ordinary capture is not a popup');

}

done_testing;
