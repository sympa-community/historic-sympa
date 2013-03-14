#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;

use Sympa::Spool;

plan tests => 4;

my $spool;

$spool = Sympa::Spool->new();
ok(!$spool, 'no name parameter');

$spool = Sympa::Spool->new(name => 'foo');
ok(!$spool, 'invalid name parameter');

$spool = Sympa::Spool->new(name => 'bounce');
ok($spool, 'valid name parameter');
isa_ok($spool, 'Sympa::Spool');
