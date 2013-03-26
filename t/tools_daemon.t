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

plan tests => 9;

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
is(slurp_file($pidfile), '666', 'pid file content');

ok(
	Sympa::Tools::Daemon::write_pid(
		file   => $pidfile,
		pid    => 667,
		method => 'anything'
	),
	'function success',
);

ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667', 'pid file content');

ok(
	Sympa::Tools::Daemon::write_pid(
		file    => $pidfile,
		pid     => 668,
		method  => 'anything',
		options => {
			multiple_process => 1
		}
	),
	'function success',
);

ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667 668', 'pid file content');

is(get_pids_in_pid_file(), [667, 668], );

sub slurp_file {
	my ($file) = @_;

	open(my $handle, '<', $file) or die "can't open $file: $ERRNO";
	my $content = <$handle>;
	close ($handle);

	chomp $content;
	return $content;
}
