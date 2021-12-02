use 5.010;
use strict;
use warnings;

use Gtk3;    # to escape warnings "Too late to run INIT block"

use Test::More;

use_ok("Shutter::Draw::Utils");

subtest "points_to_canvas_points" => sub {
    can_ok( "Shutter::Draw::Utils", "points_to_canvas_points" );

    # ..
};

done_testing;
