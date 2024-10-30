#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Strict;
use Test2::AsyncSubtest;

use FindBin qw/$Bin/;
use POSIX qw( waitpid WNOHANG );
use Time::HiRes qw( sleep );

local $Test::Strict::TEST_WARNINGS = 1;

my @dirs  = ('t', 'bin', "$Bin/../share/shutter/resources/modules/");
my @files = Test::Strict::_all_perl_files(@dirs);

run_parallel_tests(
  4,
  [
    map {
      my $file = $_;
      sub { all_perl_files_ok($file); };
    } @files
  ],
  "Syntax and strict checks for @dirs"
);

sub run_parallel_tests {
  my ($MAX_JOBS, $tests, $name) = @_;

  my $ast = Test2::AsyncSubtest->new(name => $name);

  my @tests = @{$tests || []};

  my %children;

  while (@tests) {
    if (keys %children < $MAX_JOBS) {
      my $pid = $ast->run_fork(shift @tests);
      $children{$pid}++;
    }
    waitpid($_, WNOHANG) && delete $children{$_} for keys %children;

    last if !@tests;
    sleep 0.01;
  }
  $ast->finish;
}

done_testing;
