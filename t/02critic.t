#!/usr/bin/perl

use strict;
use warnings;
use lib 'src/lib';

use English qw(-no_match_vars);
use Test::More;

plan(skip_all => 'Author test, set $ENV{TEST_AUTHOR} to a true value to run')
    if !$ENV{TEST_AUTHOR};

eval {
    require Test::Perl::Critic;
    Test::Perl::Critic->import();
};
plan(skip_all => 'Test::Perl::Critic required') if $EVAL_ERROR;

all_critic_ok('src/lib');
