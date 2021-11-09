use 5.010;
use strict;
use warnings;

use Test::More;
use Glib qw/ TRUE /;
use File::Temp qw/ tempfile tempdir /;

require_ok("Shutter::App::Directories");

subtest "create_if_not_exists" => sub {
    my $dir = tempdir( CLEANUP => 1 ) . "/foo";
    ok( !-d $dir && !-r $dir, "dir doesn't exist" );
    is( Shutter::App::Directories::create_if_not_exists($dir), $dir, "name of directories are the same" );
    ok( -d $dir && -r $dir, "dir exists" );
};

subtest "get_root_dir" => sub {
    plan skip_all => "Later";
    # ..
};

done_testing();
