#!/usr/bin/perl

use strict;
use warnings;

use English qw(-no_match_vars);
use Test::More;

eval {
    require Test::Compile;
    Test::Compile->import();
};
if ($EVAL_ERROR) {
    my $msg = 'Test::Compile required';
    plan(skip_all => $msg);
}

my @files = all_pm_files('src/lib');

all_pm_files_ok(@files);
