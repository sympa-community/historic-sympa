# tools.pl - This module provides various tools for Sympa
# RCS Identication ; $Revision: 7745 $ ; $Date: 2012-10-15 18:08:04 +0200 (lun. 15 oct. 2012) $ 
#
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

package Sympa::Tools::Daemon;

use strict;

use Proc::ProcessTable;
use Sys::Hostname;

use Lock;
use Log;
use Sympa::Tools::File;

## Remove PID file and STDERR output
sub remove_pid {
	my ($pidfile, $pid, $options, $tmpdir) = @_;
	
	## If in multi_process mode (bulk.pl for instance can have child processes)
	## Then the pidfile contains a list of space-separated PIDs on a single line
	if($options->{'multiple_process'}) {
		unless(open(PFILE, $pidfile)) {
			# fatal_err('Could not open %s, exiting', $pidfile);
			&Log::do_log('err','Could not open %s to remove pid %s', $pidfile, $pid);
			return undef;
		}
		my $l = <PFILE>;
		close PFILE;	
		my @pids = grep {/[0-9]+/} split(/\s+/, $l);
		@pids = grep {!/^$pid$/} @pids;
		
		## If no PID left, then remove the file
		if($#pids < 0) {
			## Release the lock
			unless(unlink $pidfile) {
				&Log::do_log('err', "Failed to remove $pidfile: %s", $!);
				return undef;
			}
		}else{
			if(-f $pidfile) {
				unless(open(PFILE, '> '.$pidfile)) {
					&Log::do_log('err', "Failed to open $pidfile: %s", $!);
					return undef;
				}
				print PFILE join(' ', @pids)."\n";
				close(PFILE);
			}else{
				&Log::do_log('notice', 'pidfile %s does not exist. Nothing to do.', $pidfile);
			}
		}
	}else{
		unless(unlink $pidfile) {
			&Log::do_log('err', "Failed to remove $pidfile: %s", $!);
			return undef;
		}
		my $err_file = $tmpdir.'/'.$pid.'.stderr';
		if(-f $err_file) {
			unless(unlink $err_file) {
				&Log::do_log('err', "Failed to remove $err_file: %s", $!);
				return undef;
			}
		}
	}
	return 1;
}

sub write_pid {
    my ($pidfile, $pid, $options) = @_;

    my $piddir = $pidfile;
    $piddir =~ s/\/[^\/]+$//;

    ## Create piddir
    mkdir($piddir, 0755) unless(-d $piddir);

    unless(Sympa::Tools::File::set_file_rights(
	file => $piddir,
	user  => Sympa::Constants::USER,
	group => Sympa::Constants::GROUP,
    )) {
	&Log::fatal_err('Unable to set rights on %s. Exiting.', $piddir);
    }

    my @pids;

    # Lock pid file
    my $lock = new Lock ($pidfile);
    unless (defined $lock) {
	&Log::fatal_err('Lock could not be created. Exiting.');
    }
    $lock->set_timeout(5); 
    unless ($lock->lock('write')) {
	&Log::fatal_err('Unable to lock %s file in write mode. Exiting.',$pidfile);
    }
    ## If pidfile exists, read the PIDs
    if(-f $pidfile) {
	# Read pid file
	open(PFILE, $pidfile);
	my $l = <PFILE>;
	close PFILE;	
	@pids = grep {/[0-9]+/} split(/\s+/, $l);
    }

    ## If we can have multiple instances for the process.
    ## Print other pids + this one
    if($options->{'multiple_process'}) {
	unless(open(PIDFILE, '> '.$pidfile)) {
	    ## Unlock pid file
	    $lock->unlock();
	    &Log::fatal_err('Could not open %s, exiting: %s', $pidfile,$!);
	}
	## Print other pids + this one
	push(@pids, $pid);
	print PIDFILE join(' ', @pids)."\n";
	close(PIDFILE);
    }else{
	## Create and write the pidfile
	unless(open(PIDFILE, '+>> '.$pidfile)) {
	    ## Unlock pid file
	    $lock->unlock();
	    &Log::fatal_err('Could not open %s, exiting: %s', $pidfile);
	}
	## The previous process died suddenly, without pidfile cleanup
	## Send a notice to listmaster with STDERR of the previous process
	if($#pids >= 0) {
	    my $other_pid = $pids[0];
	    &Log::do_log('notice', "Previous process %s died suddenly ; notifying listmaster", $other_pid);
	    my $pname = $0;
	    $pname =~ s/.*\/(\w+)/$1/;
	    &send_crash_report(('pid'=>$other_pid,'pname'=>$pname));
	}
	
	unless(open(PIDFILE, '> '.$pidfile)) {
	    ## Unlock pid file
	    $lock->unlock();
	    &Log::fatal_err('Could not open %s, exiting', $pidfile);
	}
	unless(truncate(PIDFILE, 0)) {
	    ## Unlock pid file
	    $lock->unlock();
	    &Log::fatal_err('Could not truncate %s, exiting.', $pidfile);
	}
	
	print PIDFILE $pid."\n";
	close(PIDFILE);
    }

    unless(Sympa::Tools::File::set_file_rights(
	file => $pidfile,
	user  => Sympa::Constants::USER,
	group => Sympa::Constants::GROUP,
    )) {
	## Unlock pid file
	$lock->unlock();
	&Log::fatal_err('Unable to set rights on %s', $pidfile);
    }
    ## Unlock pid file
    $lock->unlock();

    return 1;
}

sub direct_stderr_to_file {
    my %data = @_;
    ## Error output is stored in a file with PID-based name
    ## Usefull if process crashes
    open(STDERR, '>>', $data{'tmpdir'}.'/'.$data{'pid'}.'.stderr');
    unless(Tools::Sympa::File::set_file_rights(
	file => $data{'tmpdir'}.'/'.$data{'pid'}.'.stderr',
	user  => Sympa::Constants::USER,
	group => Sympa::Constants::GROUP,
    )) {
	&Log::do_log('err','Unable to set rights on %s', $data{'tmpdir'}.'/'.$data{'pid'}.'.stderr');
	return undef;
    }
    return 1;
}

# Send content of $pid.stderr to listmaster for process whose pid is $pid.
sub send_crash_report {
    my %data = @_;
    &Log::do_log('debug','Sending crash report for process %s',$data{'pid'}),
    my $err_file = $data{'tmpdir'}.'/'.$data{'pid'}.'.stderr';
    my (@err_output, $err_date);
    if(-f $err_file) {
	open(ERR, $err_file);
	@err_output = <ERR>;
	close ERR;
	$err_date = strftime("%d %b %Y  %H:%M", localtime((stat($err_file))[9]));
    }
    &List::send_notify_to_listmaster('crash', $data{'domain'}, {'crashed_process' => $data{'pname'}, 'crash_err' => \@err_output, 'crash_date' => $err_date, 'pid' => $data{'pid'}});
}

## Returns the list of pid identifiers in the pid file.
sub get_pids_in_pid_file {
	my $pidfile = shift;
	unless (open(PFILE, $pidfile)) {
		&Log::do_log('err', "unable to open pidfile %s:%s",$pidfile,$!);
		return undef;
	}
	my $l = <PFILE>;
	close PFILE;
	my @pids = grep {/[0-9]+/} split(/\s+/, $l);
	return \@pids;
}

sub get_children_processes_list {
    &Log::do_log('debug3','');
    my @children;
    for my $p (@{new Proc::ProcessTable->table}){
	if($p->ppid == $$) {
	    push @children, $p->pid;
	}
    }
    return @children;
}

1;
