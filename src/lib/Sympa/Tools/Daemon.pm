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
use Proc::ProcessTable;
use Sys::Hostname;

use Sympa::Lock;
use Sympa::List;
use Sympa::Log::Syslog;
use Sympa::Tools::File;

=head1 FUNCTIONS

=over

=item write_pid(%parameters)

Parameters:

=over

=item C<file> => FIXME

=item C<method> => FIXME

=item C<pid> => FIXEM

=item C<options> => FIXME

=item C<user> => FIXME

=item C<group> => FIXME

=back

=cut

sub write_pid {
	my (%params) = @_;

	my $piddir = $params{file};
	$piddir =~ s/\/[^\/]+$//;

	## Create piddir
	mkdir($piddir, 0755) unless(-d $piddir);

	unless(Sympa::Tools::File::set_file_rights(
			file  => $piddir,
			user  => $params{user},
			group => $params{group},
		)) {
		Sympa::Log::Syslog::do_log('err','Unable to set rights on %s', $piddir);
		return undef;
	}

	my @pids;

	# Lock pid file
	my $lock = Sympa::Lock->new(
		path   => $params{file},
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
		Sympa::Log::Syslog::do_log('err', 'Unable to lock %s file in write mode.',$params{file});
		return;
	}
	## If pidfile exists, read the PIDs
	if(-f $params{file}) {
		# Read pid file
		open(PFILE, $params{file});
		my $l = <PFILE>;
		close PFILE;
		@pids = grep {/[0-9]+/} split(/\s+/, $l);
	}

	## If we can have multiple instances for the process.
	## Print other pids + this one
	if($params{options}->{'multiple_process'}) {
		unless(open(PIDFILE, '> '.$params{file})) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not open %s: %s', $params{file},$ERRNO);
			return;
		}
		## Print other pids + this one
		push(@pids, $params{pid});
		print PIDFILE join(' ', @pids)."\n";
		close(PIDFILE);
	}else{
		## Create and write the pidfile
		unless(open(PIDFILE, '+>> '.$params{file})) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not open %s: %s', $params{file});
			return;
		}
		## The previous process died suddenly, without pidfile cleanup
		## Send a notice to listmaster with STDERR of the previous process
		if($#pids >= 0) {
			my $other_pid = $pids[0];
			Sympa::Log::Syslog::do_log('notice', "Previous process %s died suddenly ; notifying listmaster", $other_pid);
			my $pname = $0;
			$pname =~ s/.*\/(\w+)/$1/;
			send_crash_report(('pid'=>$other_pid,'pname'=>$pname));
		}

		unless(open(PIDFILE, '> '.$params{file})) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not open %s', $params{file});
			return;
		}
		unless(truncate(PIDFILE, 0)) {
			## Unlock pid file
			$lock->unlock();
			Sympa::Log::Syslog::do_log('err', 'Could not truncate %s.', $params{file});
			return;
		}

		print PIDFILE $params{pid}."\n";
		close(PIDFILE);
	}

	unless(Sympa::Tools::File::set_file_rights(
			file  => $params{file},
			user  => $params{user},
			group => $params{group}
		)) {
		## Unlock pid file
		$lock->unlock();
		Sympa::Log::Syslog::do_log('err', 'Unable to set rights on %s', $params{file});
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

=item C<file> => FIXME

=item C<pid> => FIXME

=item C<options> => FIXME

=item C<tmpdir> => FIXME

=back

=cut

sub remove_pid {
	my (%params) = @_;

	## If in multi_process mode (bulk.pl for instance can have child processes)
	## Then the pidfile contains a list of space-separated PIDs on a single line
	if($params{options}->{'multiple_process'}) {
		unless(open(PFILE, $params{file})) {
			Sympa::Log::Syslog::do_log('err','Could not open %s to remove pid %s', $params{file}, $params{pid});
			return undef;
		}
		my $l = <PFILE>;
		close PFILE;
		my @pids = grep {/[0-9]+/} split(/\s+/, $l);
		@pids = grep {!/^$params{pid}$/} @pids;

		## If no PID left, then remove the file
		if($#pids < 0) {
			## Release the lock
			unless(unlink $params{file}) {
				Sympa::Log::Syslog::do_log('err', "Failed to remove $params{file}: %s", $ERRNO);
				return undef;
			}
		}else{
			if(-f $params{file}) {
				unless(open(PFILE, '> '.$params{file})) {
					Sympa::Log::Syslog::do_log('err', "Failed to open $params{file}: %s", $ERRNO);
					return undef;
				}
				print PFILE join(' ', @pids)."\n";
				close(PFILE);
			}else{
				Sympa::Log::Syslog::do_log('notice', 'pidfile %s does not exist. Nothing to do.', $params{file});
			}
		}
	}else{
		unless(unlink $params{file}) {
			Sympa::Log::Syslog::do_log('err', "Failed to remove $params{file}: %s", $ERRNO);
			return undef;
		}
		my $err_file = $params{tmpdir}.'/'.$params{pid}.'.stderr';
		if(-f $err_file) {
			unless(unlink $err_file) {
				Sympa::Log::Syslog::do_log('err', "Failed to remove $err_file: %s", $ERRNO);
				return undef;
			}
		}
	}
	return 1;
}

=item get_pids_in_pid_file($pidfile)

Returns the list of pid in the pid file.

=cut

sub get_pids_in_pid_file {
	my ($pidfile) = @_;

	unless (open(PFILE, $pidfile)) {
		Sympa::Log::Syslog::do_log('err', "unable to open pidfile %s:%s",$pidfile,$ERRNO);
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

=item C<tmpdir> => FIXME

=item C<pid> => FIXME

=item C<user> => FIXME

=item C<group> => FIXME

=back

=cut

sub direct_stderr_to_file {
	my (%params) = @_;

	## Error output is stored in a file with PID-based name
	## Usefull if process crashes
	open(STDERR, '>>', $params{tmpdir}.'/'.$params{pid}.'.stderr');
	unless(Tools::Sympa::File::set_file_rights(
			file  => $params{tmpdir}.'/'.$params{pid}.'.stderr',
			user  => $params{user},
			group => $params{group}
		)) {
		Sympa::Log::Syslog::do_log('err','Unable to set rights on %s', $params{tmpdir}.'/'.$params{pid}.'.stderr');
		return undef;
	}
	return 1;
}

=item send_crash_report(%parameters)

Send content of $pid.stderr to listmaster for process whose pid is $pid.

=cut

sub send_crash_report {
	my (%params) = @_;
	Sympa::Log::Syslog::do_log('debug','Sending crash report for process %s',$params{'pid'}),

	my $err_file = $params{'tmpdir'}.'/'.$params{'pid'}.'.stderr';
	my (@err_output, $err_date);
	if(-f $err_file) {
		open(ERR, $err_file);
		@err_output = <ERR>;
		close ERR;
		$err_date = strftime("%d %b %Y  %H:%M", localtime((stat($err_file))[9]));
	}
	Sympa::List::send_notify_to_listmaster('crash', $params{'domain'}, {'crashed_process' => $params{'pname'}, 'crash_err' => \@err_output, 'crash_date' => $err_date, 'pid' => $params{'pid'}});
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

1;