#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;
use File::Temp;

use Sympa::Tools::Daemon;

plan tests => 1;

my $piddir  = File::Temp->newdir();
my $pidfile = $piddir . '/test.pid';

ok(
	Sympa::Tools::Daemon::write_pid(
		file   => $pidfile,
		pid    => 666,
		method => 'anything'
	)
);
