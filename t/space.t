#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use Test::More;

plan(skip_all => 'Author test, set $ENV{TEST_AUTHOR} to a true value to run')
    if !$ENV{TEST_AUTHOR};

eval {
    require Test::TrailingSpace;
    Test::TrailingSpace->import();
};
plan(skip_all => 'Test::TrailingSpace required') if $EVAL_ERROR;

plan tests => 4;

chdir "$Bin/..";
           
my $finder;

$finder = Test::TrailingSpace->new({
    root           => 'src/lib',
    filename_regex => qr/\.pm$/,
});

$finder->no_trailing_space("No trailing space was found in libraries");

$finder = Test::TrailingSpace->new({
    root           => 'src/sbin',
    filename_regex => qr/\.pl\.in$/,
});

$finder->no_trailing_space("No trailing space was found in main executables");

$finder = Test::TrailingSpace->new({
    root           => 'src/cgi',
    filename_regex => qr/\.(pl|fcgi)\.in$/,
});

$finder->no_trailing_space("No trailing space was found in CGI executables");

$finder = Test::TrailingSpace->new({
    root           => 'src/bin',
    filename_regex => qr/\.pl\.in$/,
});

$finder->no_trailing_space("No trailing space was found in other executables");
