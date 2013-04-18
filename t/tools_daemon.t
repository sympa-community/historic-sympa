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

my $directory = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
my $daemon    = 'test';
my $pidfile = Sympa::Tools::Daemon::_get_pid_file(
	directory => $directory,
	daemon    => $daemon
);

ok(
	Sympa::Tools::Daemon::write_pid(
		directory => $directory,
		daemon    => $daemon,
		pid       => 666,
		method    => 'flock'
	),
	'new pid file',
);

ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '666', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(
		directory => $directory,
		daemon    => $daemon
	),
	[666],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::write_pid(
		directory => $directory,
		daemon    => $daemon,
		pid       => 667,
		method    => 'flock'
	),
	'pid file overwrite',
);

ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(
		directory => $directory,
		daemon    => $daemon
	),
	[667],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::write_pid(
		directory        => $directory,
		daemon           => $daemon,
		pid              => 668,
		method           => 'flock',
		multiple_process => 1
	),
	'pid file appending',
);
ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667 668', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(
		directory => $directory,
		daemon    => $daemon
	),
	[667, 668],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::remove_pid(
		directory        => $directory,
		daemon           => $daemon,
		pid              => 668,
		method           => 'flock',
		multiple_process => 1
	),
	'pid removal, existing pid',
);
ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(
		directory => $directory,
		daemon    => $daemon
	),
	[667],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::remove_pid(
		directory        => $directory,
		daemon           => $daemon,
		pid              => 668,
		method           => 'flock',
		multiple_process => 1
	),
	'pid removal, unexisting pid',
);
ok(-f $pidfile, 'pid file presence');
is(slurp_file($pidfile), '667', 'pid file content');
is_deeply(
	Sympa::Tools::Daemon::read_pids(
		directory => $directory,
		daemon    => $daemon
	),
	[667],
	'pids list'
);

ok(
	Sympa::Tools::Daemon::remove_pid(
		directory        => $directory,
		daemon           => $daemon,
		pid              => 667,
		method           => 'flock',
		multiple_process => 1
	),
	'pid removal, last pid',
);
ok(!-f $pidfile, 'pid file presence');
is_deeply(
	Sympa::Tools::Daemon::read_pids(
		directory => $directory,
		daemon    => $daemon
	),
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
