#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id$

use strict;
use warnings;
use lib 'src/lib';

use English qw(-no_match_vars);
use Test::More;

plan(skip_all => 'Author test, set $ENV{TEST_AUTHOR} to a true value to run')
    if !$ENV{TEST_AUTHOR};

eval {
    require Test::TrailingSpace;
    Test::TrailingSpace->import();
};
plan(skip_all => 'Test::TrailingSpace required') if $EVAL_ERROR;

plan tests => 2;
           
my $finder;

$finder = Test::TrailingSpace->new({
    root           => 'src/lib',
    filename_regex => qr/\.pm$/,
});

$finder->no_trailing_space("No trailing space was found.");

$finder = Test::TrailingSpace->new({
    root           => 'src/sbin',
    filename_regex => qr/\.pl\.in$/,
});

$finder->no_trailing_space("No trailing space was found.");
