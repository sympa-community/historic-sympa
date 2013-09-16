# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
# Copyright (c) 1997,1998, 1999 Institut Pasteur & Christophe Wolfhugel
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Tools::Daemon - Daemon-related functions

=head1 DESCRIPTION

This module provides various functions for managing daemons.

=cut

package Sympa::Tools::Daemon;

use strict;

use English qw(-no_match_vars);
use File::Spec;
use Proc::ProcessTable;
use Sys::Hostname;

use Sympa::Lock;
use Sympa::Log::Syslog;
use Sympa::Tools::File;

=head1 FUNCTIONS

=over

=item get_daemon_name()

Get the current program name.

Parameters:

None.

Return value:

A sane daemon name.

=cut

sub get_daemon_name {
	return (File::Spec->splitpath($0))[2];
}

=item write_pid(%parameters)

Parameters:

=over

=item C<directory> => path

The PID file directory.

=item C<daemon> => string

The daemon name.

=item C<pid> => string

The daemon PID.

=item C<multiple_process> => boolean

FIXME

=item C<method> => string

The PID file locking method.

=item C<user> => string

The PID file user.

=item C<group> => string

The PID file group.

=back

=cut

sub write_pid {
	my (%params) = @_;

	## Create piddir
	mkdir($params{directory}, 0755) unless(-d $params{directory});

	unless(Sympa::Tools::File::set_file_rights(
			file  => $params{directory},
			user  => $params{user},
			group => $params{group},
		)) {
		Sympa::Log::Syslog::do_log('err','Unable to set rights on %s', $params{directory});
		return undef;
	}

	my $pid_file = _get_pid_file(%params);

	my @pids;

	# Lock pid file
	my $lock = Sympa::Lock->new(
		path   => $pid_file,
		method => $params{method},
		user   => $params{user},
		group  => $params{group},
	);
	unless (defined $lock) {
		Sympa::Log::Syslog::do_log('err', 'Lock could not be created.');
		return;
	}
	$lock->set_timeout(5);
	unless ($lock->lock('write')) {
		Sympa::Log::Syslog::do_log('err', 'Unable to lock %s file in write mode.',$pid_file);
		return;
	}
	## If pidfile exists, read the PIDs
	if(-f $pid_file) {
		# Read pid file
		open(PFILE, '<', $pid_file);
		my $l = <PFILE>;
		close PFILE;
		@pids = grep {/[0-9]+/} split(/\s+/, $l);
	}

	## If we can have multiple instances for the process.
	## Print other pids + this one
	if($params{multiple_process}) {
		unless(open(PIDFILE, '>', $pid_file)) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not open %s: %s', $pid_file,$ERRNO);
			return;
		}
		## Print other pids + this one
		push(@pids, $params{pid});
		print PIDFILE join(' ', @pids)."\n";
		close(PIDFILE);
	} else {
		## Create and write the pidfile
		unless(open(PIDFILE, '+>>', $pid_file)) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not open %s: %s', $pid_file);
			return;
		}
		## The previous process died suddenly, without pidfile cleanup
		## Send a notice to listmaster with STDERR of the previous process
		if($#pids >= 0) {
			my $other_pid = $pids[0];
			Sympa::Log::Syslog::do_log('notice', "Previous process %s died suddenly ; notifying listmaster", $other_pid);
			send_crash_report(
				directory => $params{directory},
				daemon    => $params{daemon},
				pid       => $other_pid,
			);
		}

		unless(open(PIDFILE, '>', $pid_file)) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not open %s', $pid_file);
			return;
		}
		unless(truncate(PIDFILE, 0)) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not truncate %s.', $pid_file);
			return;
		}

		print PIDFILE $params{pid}."\n";
		close(PIDFILE);
	}

	unless(Sympa::Tools::File::set_file_rights(
			file  => $pid_file,
			user  => $params{user},
			group => $params{group}
		)) {
		## Unlock pid file
		$lock->unlock();
		Sympa::Log::Syslog::do_log('err', 'Unable to set rights on %s', $pid_file);
		return;
	}
	## Unlock pid file
	$lock->unlock();

	return 1;
}

=item remove_pid(%parameters)

Remove PID file and STDERR output.

Parameters:

=over

=item C<directory> => path

The PID file directory.

=item C<daemon> => string

The daemon name.

=item C<pid> => number

The daemon PID.

=item C<multiple_process> => boolean

FIXME

=back

=cut

sub remove_pid {
	my (%params) = @_;

	my $pid_file = _get_pid_file(%params);

	## If in multi_process mode (bulk.pl for instance can have child processes)
	## Then the pidfile contains a list of space-separated PIDs on a single line
	if($params{multiple_process}) {
		unless(open(PFILE, '<', $pid_file)) {
			Sympa::Log::Syslog::do_log('err','Could not open %s to remove pid %s', $pid_file, $params{pid});
			return undef;
		}
		my $l = <PFILE>;
		close PFILE;
		my @pids = grep {/[0-9]+/} split(/\s+/, $l);
		@pids = grep {!/^$params{pid}$/} @pids;

		## If no PID left, then remove the file
		if($#pids < 0) {
			## Release the lock
			unless(unlink $pid_file) {
				Sympa::Log::Syslog::do_log('err', "Failed to remove $pid_file: %s", $ERRNO);
				return undef;
			}
		} else {
			if(-f $pid_file) {
				unless(open(PFILE, '>', $pid_file)) {
					Sympa::Log::Syslog::do_log('err', "Failed to open $pid_file: %s", $ERRNO);
					return undef;
				}
				print PFILE join(' ', @pids)."\n";
				close(PFILE);
			} else {
				Sympa::Log::Syslog::do_log('notice', 'pidfile %s does not exist. Nothing to do.', $pid_file);
			}
		}
	} else {
		unless(unlink $pid_file) {
			Sympa::Log::Syslog::do_log('err', "Failed to remove $pid_file: %s", $ERRNO);
			return undef;
		}
		my $err_file = _get_error_file(%params);
		if (-f $err_file) {
			unless(unlink $err_file) {
				Sympa::Log::Syslog::do_log('err', "Failed to remove $err_file: %s", $ERRNO);
				return undef;
			}
		}
	}
	return 1;
}

=item read_pids(%parameters)

Returns the list of pid in the pid file.

Parameters:

=over

=item C<directory> => path

The PID file directory.

=item C<daemon> => string

The daemon name.

=back

=cut

sub read_pids {
	my (%params) = @_;

	my $pid_file = _get_pid_file(%params);

	unless (open(PFILE, '<', $pid_file)) {
		Sympa::Log::Syslog::do_log('err', "unable to open pidfile %s:%s",$pid_file,$ERRNO);
		return undef;
	}
	my $l = <PFILE>;
	close PFILE;
	my @pids = grep {/[0-9]+/} split(/\s+/, $l);
	return \@pids;
}

=item direct_stderr_to_file(%parameters)

Parameters:

=over

=item C<directory> => path

The error file directory.

=item C<pid> => number

The daemon PID.

=item C<user> => string

The error file user.

=item C<group> => string

The error file group.

=back

=cut

sub direct_stderr_to_file {
	my (%params) = @_;

	## Error output is stored in a file with PID-based name
	## Usefull if process crashes
	my $err_file = _get_error_file(%params);
	open(STDERR, '>>', $err_file);
	unless(Tools::Sympa::File::set_file_rights(
			file  => $err_file,
			user  => $params{user},
			group => $params{group}
		)) {
		Sympa::Log::Syslog::do_log(
			'err','Unable to set rights on %s', $err_file
		);
		return undef;
	}
	return 1;
}

=item send_crash_report(%parameters)

Send error file content to listmaster.

Parameters:

=over

=item C<directory> => path

The error file directory.

=item C<pid> => number

The crashed daemon PID.

=item C<daemon> => string

The crashed daemon name.

=item C<domain> => string

=back

=cut

sub send_crash_report {
	my (%params) = @_;
	Sympa::Log::Syslog::do_log('debug','Sending crash report for process %s',$params{'pid'}),

	my $err_file = _get_error_file(%params);
	my (@err_output, $err_date);
	if(-f $err_file) {
		open(ERR, '<', $err_file);
		@err_output = <ERR>;
		close ERR;
		$err_date = strftime("%d %b %Y  %H:%M", localtime((stat($err_file))[9]));
	}
	# TODO: remove dependency on Sympa::List
	require Sympa::List;
	Sympa::List::send_notify_to_listmaster(
		'crash',
		$params{domain},
		{
			crashed_process => $params{daemon},
			crash_err       => \@err_output,
			crash_date      => $err_date,
			pid             => $params{pid}
		}
	);
}

=item get_children_processes_list()

Returns the list of pid of current process children.

=cut

sub get_children_processes_list {
	Sympa::Log::Syslog::do_log('debug3','');

	my @children;
	for my $p (@{Proc::ProcessTable->new()->table}){
		if($p->ppid == $PID) {
			push @children, $p->pid;
		}
	}
	return @children;
}

sub _get_error_file {
	my (%params) = @_;

	return $params{directory} . '/' . $params{pid} . '.stderr';
}

sub _get_pid_file {
	my (%params) = @_;

	return $params{directory} . '/' . $params{daemon} . '.pid';
}

=back

=cut

1;
