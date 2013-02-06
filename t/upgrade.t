#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;

use Sympa::Upgrade;

my @lower_version_ok_tests = (
    [ [ qw/1.0  2.0 / ] ],
    [ [ qw/2.0  2.1 / ] ],
    [ [ qw/2.1  2.10/ ] ],
    [ [ qw/1.0a 1.0 / ] ],
    [ [ qw/1.0b 1.0 / ] ],
    [ [ qw/1.0a 1.0b/ ] ],
);

my @lower_version_nok_tests = (
    [ [ qw/2.0  1.0 / ] ],
    [ [ qw/2.1  2.0 / ] ],
    [ [ qw/2.10 2.1 / ] ],
    [ [ qw/1.0  1.0a/ ] ],
    [ [ qw/1.0  1.0b/ ] ],
    [ [ qw/1.0b 1.0a/ ] ],
    [ [ qw/1.0  1.0 / ] ],
);

plan tests =>
    @lower_version_ok_tests        +
    @lower_version_nok_tests       ;


foreach my $test (@lower_version_ok_tests) {
    ok(
        Sympa::Upgrade::lower_version(@{$test->[0]}),
        "lower_version $test->[0]->[0], $test->[0]->[1]"
    );
}

foreach my $test (@lower_version_nok_tests) {
    ok(
        !Sympa::Upgrade::lower_version(@{$test->[0]}),
        "!lower_version $test->[0]->[0], $test->[0]->[1]"
    );
}
