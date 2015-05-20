#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:et:sw=4
# $Id: pod-spelling.t 8606 2013-02-06 08:44:02Z rousse $

use strict;
use warnings;

use lib 'src/lib';

use English qw(-no_match_vars);
use Test::More;

plan(skip_all => 'Author test, set $ENV{TEST_AUTHOR} to a true value to run')
    if !$ENV{TEST_AUTHOR};

eval {
    require Test::Pod;
    Test::Pod->import();
};
plan(skip_all => 'Test::Pod required') if $EVAL_ERROR;

eval {
    require Test::Pod::Spelling::CommonMistakes;
    Test::Pod::Spelling::CommonMistakes->import();
};
plan(skip_all => 'Test::Pod::Spelling::CommonMistakes required') if $EVAL_ERROR;

my @files = all_pod_files('src/lib');

all_pod_files_ok(@files);
