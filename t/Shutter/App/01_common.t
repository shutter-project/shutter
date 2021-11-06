use 5.010;
use strict;
use warnings;

use Locale::gettext;
use Test::More;
use Test::MockModule;

require_ok( _get_package() );

subtest "Create common object" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found"
        unless $ENV{TEST_APP_SHUTTER_PATH};

    my $mock = Test::MockModule->new( _get_package() );
    $mock->mock( "_setup_icontheme", sub { } );

    my $root     = $ENV{TEST_APP_SHUTTER_PATH};
    my $name     = "shutter";
    my $version  = 0.544;
    my $revision = 1234;
    my $pid      = 100500;

    my $sc = _get_common_object( $root, undef, $name, $version, $revision, $pid );

    ok( defined $sc, "Object defined" );
    isa_ok( $sc, _get_package() );
};

subtest "Test getters and setters" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found"
        unless $ENV{TEST_APP_SHUTTER_PATH};

    my $mock = Test::MockModule->new( _get_package() );
    $mock->mock( "_setup_icontheme", sub { my $self = shift; $self->{_icontheme} = "foo bar baz" } );

    my $root     = $ENV{TEST_APP_SHUTTER_PATH};
    my $name     = "shutter";
    my $version  = 0.544;
    my $revision = 1234;
    my $pid      = 100500;

    my $sc = _get_common_object( $root, undef, $name, $version, $revision, $pid );

    isa_ok( $sc, _get_package() );

    is( $sc->get_root,    $root,     "get_root" );
    is( $sc->get_appname, $name,     "get_appname" );
    is( $sc->get_version, $version,  "get_version" );
    is( $sc->get_rev,     $revision, "get_rev" );

    subtest "main_window" => sub {
        is( $sc->get_mainwindow, undef, "main_window is null" );
        $sc->set_mainwindow("AAAA");
        is( $sc->get_mainwindow, "AAAA", "main_window is filed" );
    };

    subtest "gettext_object" => sub {
        plan skip_all => "Later";
    };

    subtest "notification_object" => sub {
        is( $sc->get_notification_object, undef, "notification_object is null" );
        $sc->set_notification_object(1);
        is( $sc->get_notification_object, 1, "notification_object is filled" );
    };
};

done_testing();

sub _get_package {
    return $ENV{TEST_APP_NEW_COMMON} ? "Shutter::App::NewCommon" : "Shutter::App::Common";
}

sub _get_common_object {
    my ( $root, $main_window, $name, $version, $revision, $pid ) = @_;

    if ( $ENV{TEST_APP_NEW_COMMON} ) {
        return Shutter::App::NewCommon->new(
            shutter_root => $root,
            main_window  => $main_window,
            appname      => $name,
            version      => $version,
            rev          => $revision,
            pid          => $pid
        );
    }

    return Shutter::App::Common->new( $root, $main_window, $name, $version, $revision, $pid );
}
