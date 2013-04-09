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

plan tests => 23;

my $piddir  = File::Temp->newdir();
my $pidfile = $piddir . '/test.pid';

ok(
	Sympa::Tools::Daemon::write_pid(
		file   => $pidfile,
		pid    => 666,
		method => 'anything'
	),
	'new pid file',
);

ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '666', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(file => $pidfile),
	[666],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::write_pid(
		file   => $pidfile,
		pid    => 667,
		method => 'anything'
	),
	'pid file overwrite',
);

ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(file => $pidfile),
	[667],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::write_pid(
		file    => $pidfile,
		pid     => 668,
		method  => 'anything',
		options => {
			multiple_process => 1
		}
	),
	'pid file appending',
);
ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667 668', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(file => $pidfile),
	[667, 668],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::remove_pid(
		file    => $pidfile,
		pid     => 668,
		method  => 'anything',
		options => {
			multiple_process => 1
		}
	),
	'pid removal, existing pid',
);
ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(file => $pidfile),
	[667],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::remove_pid(
		file    => $pidfile,
		pid     => 668,
		method  => 'anything',
		options => {
			multiple_process => 1
		}
	),
	'pid removal, unexisting pid',
);
ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(file => $pidfile),
	[667],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::remove_pid(
		file    => $pidfile,
		pid     => 667,
		method  => 'anything',
		options => {
			multiple_process => 1
		}
	),
	'pid removal, last pid',
);
ok(!-f $pidfile, 'pid file presence');
is_deeply(
	Sympa::Tools::Daemon::read_pids(file => $pidfile),
	undef,
	'pids list'
);

sub slurp_file {
	my ($file) = @_;

	open(my $handle, '<', $file) or die "can't open $file: $ERRNO";
	my $content = <$handle>;
	close ($handle);

	chomp $content;
	return $content;
}
