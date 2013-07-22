#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: sql.t 9585 2013-07-22 11:58:25Z rousse $

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use Test::More;
use Test::Exception;

use Sympa::Spool::File;

plan tests => 2;

my $spool = Sympa::Spool::File->new();
ok(defined $spool, 'spool is defined');
isa_ok($spool, 'Sympa::Spool::File');
