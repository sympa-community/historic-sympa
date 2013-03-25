#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use File::Temp;
use Test::More;

use Sympa::Tools::Daemon;

plan tests => 3;

my $piddir  = File::Temp->newdir();
my $pidfile = $piddir . '/test.pid';

ok(
	Sympa::Tools::Daemon::write_pid(
		file   => $pidfile,
		pid    => 666,
		method => 'anything'
	),
	'function success',
);

ok(-f $pidfile, 'pid file presence');
cmp_ok(slurp_file($pidfile), '==', 666, 'pid file content');

sub slurp_file {
	my ($file) = @_;

	open(my $handle, '<', $file) or die "can't open $file: $ERRNO";
	local $/;
	my $content = <$handle>;
	close ($handle);

	return $content;
}
