package Test::Common;

use 5.010;
use strict;
use warnings;
use English;

use Shutter::App::Common;

sub get_common_object {
    my $root     = $ENV{TEST_APP_SHUTTER_PATH} or die "env TEST_APP_SHUTTER_PATH has to be set";
    my $name     = "shutter";
    my $version  = 0.544;
    my $revision = 1234;

    return Shutter::App::Common->new(
        shutter_root => $root,
        main_window  => undef,
        appname      => $name,
        version      => $version,
        rev          => $revision,
        pid          => $PID
    );
}

1;
