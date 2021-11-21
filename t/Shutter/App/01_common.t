use 5.010;
use strict;
use warnings;

use Gtk3;    # to escape warnings "Too late to run INIT block"
use Locale::gettext;
use Test::More tests => 3;
use Glib qw/ TRUE FALSE /;

use constant MOCKED_ICONTHEME_VALUE => "FOO BAR BAZ";

require Test::Window;

require_ok("Shutter::App::Common");

subtest "Create common object" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w = Test::Window::simple_window();

    my $root     = $ENV{TEST_APP_SHUTTER_PATH};
    my $name     = "shutter";
    my $version  = 0.544;
    my $revision = 1234;
    my $pid      = 100500;

    my $sc = _get_common_object( $root, undef, $name, $version, $revision, $pid );

    ok( defined $sc, "Object defined" );
    isa_ok( $sc, "Shutter::App::Common" );
    ok( exists $ENV{SHUTTER_INTL}, "defined SHUTTER_INTL" );
    is( $ENV{SHUTTER_INTL}, $sc->get_root . "/share/locale", '$ENV{SHUTTER_INTL} has a right value' );
};

subtest "Getters and setters" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w = Test::Window::simple_window();

    my $root     = $ENV{TEST_APP_SHUTTER_PATH};
    my $name     = "shutter";
    my $version  = 0.544;
    my $revision = 1234;
    my $pid      = 100500;

    my $sc = _get_common_object( $root, undef, $name, $version, $revision, $pid );

    isa_ok( $sc, "Shutter::App::Common" );

    is( $sc->get_root,    $root,     "get_root" );
    is( $sc->get_appname, $name,     "get_appname" );
    is( $sc->get_version, $version,  "get_version" );
    is( $sc->get_rev,     $revision, "get_rev" );

    subtest "main_window" => sub {
        is( $sc->get_mainwindow, undef, "main_window is null" );
        $sc->set_mainwindow("AAAA");
        is( $sc->get_mainwindow, "AAAA", "main_window is filed" );
    };

    subtest "icontheme" => sub {
        ok( defined $sc->icontheme, "icontheme defined" );
        isa_ok( $sc->icontheme, "Gtk3::IconTheme" );
        ok ( $sc->icontheme->has_icon("shutter"), "has icon 'shutter'" );
    };

    subtest "gettext_object" => sub {
        ok( defined $sc->get_gettext );
        isa_ok( $sc->get_gettext, "Locale::gettext" );
    };

    subtest "notification_object" => sub {
        is( $sc->get_notification_object, undef, "notification_object is null" );
        $sc->set_notification_object(1);
        is( $sc->get_notification_object, 1, "notification_object is filled" );
    };

    subtest "globalsettings_object" => sub {
        is( $sc->get_globalsettings_object, undef, "globalsettings_object is null" );
        $sc->set_globalsettings_object( { foo => 1, bar => 2 } );
        ok( defined $sc->get_globalsettings_object,       "globalsettings_object is filled" );
        ok( ref $sc->get_globalsettings_object eq "HASH", "globalsettings_object is filled by proper structure" );
        ok( $sc->get_globalsettings_object->{foo} == 1,   "check first parameter" );
        ok( $sc->get_globalsettings_object->{bar} == 2,   "check second parameter" );
    };

    subtest "rusf" => sub {
        is( $sc->get_rusf, undef, "rusf is null" );
        $sc->set_rusf(1);
        is( $sc->get_rusf, 1, "rusf is filled" );
    };

    subtest "ruof" => sub {
        is( $sc->get_ruof, undef, "ruof is null" );
        $sc->set_ruof(0);
        is( $sc->get_ruof, 0, "ruof is filled" );
    };

    subtest "ruu_tab" => sub {
        is( $sc->get_ruu_tab, 0, "ruu_tab is zero" );
        $sc->set_ruu_tab(1);
        is( $sc->get_ruu_tab, 1, "ruu_tab is changed" );
    };

    subtest "ruu_hosting" => sub {
        is( $sc->get_ruu_hosting, 0, "ruu_hosting is zero" );
        $sc->set_ruu_hosting(1);
        is( $sc->get_ruu_hosting, 1, "ruu_hosting is changed" );
    };

    subtest "ruu_places" => sub {
        is( $sc->get_ruu_places, 0, "ruu_places is zero" );
        $sc->set_ruu_places(1);
        is( $sc->get_ruu_places, 1, "ruu_places is changed" );
    };

    subtest "debug" => sub {
        is( $sc->get_debug, TRUE, "debug is enabled by default" );
        $sc->set_debug(FALSE);
        is( $sc->get_debug, FALSE, "debug is disabled" );
    };

    subtest "clear_cache" => sub {
        is( $sc->get_clear_cache, FALSE, "clear_cache is disabled by default" );
        $sc->set_clear_cache(TRUE);
        is( $sc->get_clear_cache, TRUE, "clear_cache is enabled" );
    };

    subtest "min" => sub {
        is( $sc->get_min, FALSE, "min is disabled by default" );
        $sc->set_min(TRUE);
        is( $sc->get_min, TRUE, "min is enabled" );
    };

    subtest "disable_systray" => sub {
        is( $sc->get_disable_systray, FALSE, "disable_systray is disabled by default" );
        $sc->set_disable_systray(TRUE);
        is( $sc->get_disable_systray, TRUE, "disable_systray is enabled" );
    };

    subtest "exit_after_capture" => sub {
        is( $sc->get_exit_after_capture, FALSE, "exit_after_capture is disabled by default" );
        $sc->set_exit_after_capture(TRUE);
        is( $sc->get_exit_after_capture, TRUE, "exit_after_capture is enabled" );
    };

    subtest "no_session" => sub {
        is( $sc->get_no_session, FALSE, "no_session is disabled by default" );
        $sc->set_no_session(TRUE);
        is( $sc->get_no_session, TRUE, "no_session is enabled" );
    };

    subtest "start_with" => sub {
        my ( $start_with, $start_with_extra ) = $sc->get_start_with;

        is( $start_with,       undef, "start_with is null" );
        is( $start_with_extra, undef, "start_with_extra is null" );

        $sc->set_start_with( "foo", "bar" );

        ( $start_with, $start_with_extra ) = $sc->get_start_with;

        is( $start_with,       "foo", "start_with is filled" );
        is( $start_with_extra, "bar", "start_with_extra is filled" );
    };

    subtest "profile_to_start_with" => sub {
        is( $sc->get_profile_to_start_with, undef, "profile_to_start_with is null" );
        $sc->set_profile_to_start_with("foo");
        is( $sc->get_profile_to_start_with, "foo", "profile_to_start_with is filled" );
    };

    subtest "export_filename" => sub {
        is( $sc->get_export_filename, undef, "export_filename is null" );
        $sc->set_export_filename("foo");
        is( $sc->get_export_filename, "foo", "export_filename is filled" );
    };

    subtest "include_cursor" => sub {
        is( $sc->get_include_cursor, undef, "include_cursor is null" );
        $sc->set_include_cursor(TRUE);
        is( $sc->get_include_cursor, TRUE, "include_cursor is filled" );
    };

    subtest "remove_cursor" => sub {
        is( $sc->get_remove_cursor, undef, "remove_cursor is null" );
        $sc->set_remove_cursor(FALSE);
        is( $sc->get_remove_cursor, FALSE, "remove_cursor is filled" );
    };

    subtest "delay" => sub {
        is( $sc->get_delay, undef, "delay is null" );
        $sc->set_delay(15);
        is( $sc->get_delay, 15, "delay is filled" );
    };

    subtest "get_current_monitor" => sub {
        my $mon = $sc->get_current_monitor;

        ok( defined $mon, "found current monitor" );
        for my $attribute ( qw/ x y width height / ) {
            ok( exists $mon->{$attribute}, "attribute '$attribute' exists" );
        }
    };
};

done_testing();

sub _get_common_object {
    my ( $root, $main_window, $name, $version, $revision, $pid ) = @_;

    return Shutter::App::Common->new(
        shutter_root => $root,
        main_window  => $main_window,
        appname      => $name,
        version      => $version,
        rev          => $revision,
        pid          => $pid
    );
}

