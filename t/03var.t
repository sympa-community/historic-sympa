#!/usr/bin/perl

use strict;
use warnings;

use English qw(-no_match_vars);
use Test::More;

plan(skip_all => 'Author test, set $ENV{TEST_AUTHOR} to a true value to run')
    if !$ENV{TEST_AUTHOR};

eval {
    require Test::Compile;
    Test::Compile->import();
};
plan(skip_all => 'Test::Compile required') if $EVAL_ERROR;

eval {
    require Test::Vars;
    Test::Vars->import();
};
plan(skip_all => 'Test::Vars required') if $EVAL_ERROR;

my @files = all_pm_files('src/lib');

plan tests => scalar @files;

foreach my $file (@files) {
    vars_ok($file);
}
