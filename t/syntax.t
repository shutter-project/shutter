#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Strict;

use FindBin qw/$Bin/;

# Check syntax, use strict and use warnings on all perl files

local $Test::Strict::TEST_WARNINGS = 1;

my @dirs  = ('t', 'bin', "$Bin/../share/shutter/resources/modules/");

all_perl_files_ok(@dirs);

done_testing;
