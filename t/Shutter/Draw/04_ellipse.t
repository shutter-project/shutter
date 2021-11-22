use 5.010;
use strict;
use warnings;

use Gtk3;    # to escape warnings "Too late to run INIT block"
use Test::More;

require Shutter::App::Common;

require_ok("Shutter::Draw::UIManager");

done_testing();
