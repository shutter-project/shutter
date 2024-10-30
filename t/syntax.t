#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Strict;
use Test2::AsyncSubtest;

use FindBin qw/$Bin/;
use POSIX qw( waitpid WNOHANG );
use Time::HiRes qw( sleep );

# Check syntax, use strict and use warnings on all perl files

local $Test::Strict::TEST_WARNINGS = 1;

my @dirs  = ('t', 'bin', "$Bin/../share/shutter/resources/modules/");

all_perl_files_ok(@dirs);

done_testing;
