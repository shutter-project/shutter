use 5.010;
use strict;
use warnings;

use Test::More tests => 9;
use Test::MockModule;
use Glib qw/ TRUE FALSE /;
use File::Temp qw/ tempdir /;

require_ok("Shutter::App::Directories");

{
    # do not pollute /home with these tests
    my $local_home = tempdir( CLEANUP => 1 );
    local $ENV{HOME} = $local_home;

    subtest "create_if_not_exists" => sub {
        my $dir = tempdir( CLEANUP => 1 ) . "/foo";
        ok( !-d $dir && !-r $dir, "dir doesn't exist" );
        is( Shutter::App::Directories::create_if_not_exists($dir), $dir, "name of directories are the same" );
        ok( -d $dir && -r $dir, "dir exists" );
    };

    subtest "get_root_dir" => sub {
        my $expected_dir = Glib::get_user_cache_dir . "/" . Shutter::App::Directories->SHUTTER_DIR;

        subtest "invoke create_if_not_exists" =>
            invoke_create_if_not_exists->( $expected_dir, \&Shutter::App::Directories::get_root_dir );

        is( Shutter::App::Directories::get_root_dir(), $expected_dir, "root dir" );
    };

    subtest "get_cache_dir" => sub {
        my $expected_dir
            = Glib::get_user_cache_dir . "/"
            . Shutter::App::Directories->SHUTTER_DIR . "/"
            . Shutter::App::Directories->UNSAVED_DIR;

        subtest "invoke create_if_not_exists" =>
            invoke_create_if_not_exists->( $expected_dir, \&Shutter::App::Directories::get_cache_dir );

        is( Shutter::App::Directories::get_cache_dir(), $expected_dir, "cache dir" );
    };

    subtest "get_temp_dir" => sub {
        my $expected_dir
            = Glib::get_user_cache_dir . "/"
            . Shutter::App::Directories->SHUTTER_DIR . "/"
            . Shutter::App::Directories->TEMP_DIR;

        subtest "invoke create_if_not_exists" =>
            invoke_create_if_not_exists->( $expected_dir, \&Shutter::App::Directories::get_temp_dir );

        is( Shutter::App::Directories::get_temp_dir(), $expected_dir, "temp dir" );
    };

    subtest "get_autostart_dir" => sub {
        my $expected_dir = Glib::get_user_config_dir . "/" . Shutter::App::Directories->AUTOSTART_DIR;

        subtest "invoke create_if_not_exists" =>
            invoke_create_if_not_exists->( $expected_dir, \&Shutter::App::Directories::get_autostart_dir );

        is( Shutter::App::Directories::get_autostart_dir(), $expected_dir, "autostart dir" );
    };

    subtest "get_home_dir" => sub {
        is( Shutter::App::Directories::get_home_dir(), Glib::get_home_dir, "home dir" );
    };

    subtest "get_config_dir" => sub {
        is( Shutter::App::Directories::get_config_dir(), Glib::get_user_config_dir, "config dir" );
    };

    subtest "create_hidden_home_dir_if_not_exist" => sub {
        my $hidden_dir   = $ENV{HOME} . "/" . Shutter::App::Directories->HIDDEN_SHUTTER_DIR;
        my $profiles_dir = $hidden_dir . "/" . Shutter::App::Directories->PROFILES_DIR;

        ok( !-d $hidden_dir,   "hidden dir doesn't exist" );
        ok( !-d $profiles_dir, "profiles dir doesn't exist" );

        Shutter::App::Directories::create_hidden_home_dir_if_not_exist();

        ok( -d $hidden_dir,   "now hidden dir exists" );
        ok( -d $profiles_dir, "now profiles dir exists" );
    };
};

sub invoke_create_if_not_exists {
    my ( $expected_dir, $running_function ) = @_;

    return sub {
        my $invoked      = FALSE;
        my $obtained_dir = undef;
        my $mock         = Test::MockModule->new("Shutter::App::Directories");
        $mock->mock(
            "create_if_not_exists",
            sub {
                $obtained_dir = shift;
                $invoked      = TRUE;
                return $obtained_dir;
            } );

        $running_function->();

        is( $invoked,      TRUE,          "create_if_not_exists has been invoked" );
        is( $obtained_dir, $expected_dir, "got expected dir '$expected_dir'" );
    }
}

done_testing();
