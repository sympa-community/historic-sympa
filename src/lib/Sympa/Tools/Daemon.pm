# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997-2011 Comite Reseau des Universites
# Copyright (c) 2011-2014 GIP RENATER
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=encoding utf-8

=head1 NAME

Sympa::Tools::Daemon - Daemon-related functions

=head1 DESCRIPTION

This package provides daemon-related functions.

=cut

package Sympa::Tools::Daemon;

use strict;
use warnings;

use Carp qw(croak);
use English qw(-no_match_vars);
use POSIX qw();
use Proc::ProcessTable;

use Sympa::Language;
use Sympa::LockedFile;
use Sympa::Logger;
use Sympa::Tools::File;

# Language context
my $language = Sympa::Language->instance;

=head1 FUNCTIONS

=over

=item remove_pid(%parameters)

Remove a PID from the process PID file.

Parameters:

=over

=item * I<name>: process name

=item * I<pid>: process PID (default: current PID)

=item * I<piddir>: PID file directory

=item * I<tmpdir>: STDERR file directory

=item * I<multiple_process>: allows multiple PIDs in the same file

=back

Raise an exception in case of failure.

=cut

sub remove_pid {
    my (%params) = @_;

    my $name             = $params{name};
    my $pid              = $params{pid} || $PID;
    my $piddir           = $params{piddir};
    my $tmpdir           = $params{tmpdir};
    my $multiple_process = $params{multiple_process};

    my $pidfile = _get_pid_file(dir => $piddir, name => $name);

    my @pids;

    # Lock pid file
    my $lock_fh = Sympa::LockedFile->new($pidfile, 5, '+<');
    croak "Unable to lock $pidfile file in write mode\n"
        unless $lock_fh;

    ## If in multi_process mode (bulk.pl for instance can have child
    ## processes) then the PID file contains a list of space-separated PIDs
    ## on a single line
    if ($multiple_process) {

        # Read pid file
        seek $lock_fh, 0, 0;
        my $l = <$lock_fh>;
        @pids = grep { /^[0-9]+$/ and $_ != $pid } split(/\s+/, $l);

        ## If no PID left, then remove the file
        unless (@pids) {
            ## Release the lock
            unless (unlink $pidfile) {
                $main::logger->do_log(Sympa::Logger::ERR, "Failed to remove %s: %s",
                    $pidfile, $ERRNO);
                $lock_fh->close;
                return undef;
            }
        } else {
            seek $lock_fh, 0, 0;
            truncate $lock_fh, 0;
            print $lock_fh join(' ', @pids) . "\n";
        }
    } else {
        unless (unlink $pidfile) {
            $main::logger->do_log(Sympa::Logger::ERR, "Failed to remove %s: %s", $pidfile,
                $ERRNO);
            $lock_fh->close;
            return undef;
        }
        my $err_file = _get_error_file(dir => $tmpdir, pid => $pid);
        if (-f $err_file) {
            unless (unlink $err_file) {
                $main::logger->do_log(Sympa::Logger::ERR, "Failed to remove %s: %s",
                    $err_file, $ERRNO);
                $lock_fh->close;
                return undef;
            }
        }
    }

    $lock_fh->close;
    return 1;
}

=item check_old_pid_file(%parameters)

The previous process died suddenly, without pidfile cleanup
Send a notice to listmaster with STDERR of the previous process

=cut


sub check_old_pid_file {
    my (%params) = @_;

    my $name   = $params{name};
    my $piddir = $params{piddir};
    my $tmpdir = $params{tmpdir};

    my $pids = get_pids_from_pid_file(%params);
    return unless $pids;

    my $pid = $pids->[0];

    $main::logger->do_log(
        Sympa::Logger::NOTICE,
        "Previous process %s died suddenly ; notifying listmaster",
        $pid
    );

    send_crash_report(
        pid    => $pid,
        pname  => $name,
        tmpdir => $tmpdir
    );
}

=item write_pid(%parameters)

Add a PID in process PID file.

Parameters:

=over

=item * I<name>: process name

=item * I<pid>: process PID (default: current PID)

=item * I<piddir>: PID file directory

=item * I<user>: PID file user

=item * I<group>: PID file group

=item * I<tmpdir>: STDERR file directory

=item * I<multiple_process>: allows multiple PIDs in the same file

=back

Raise an exception in case of failure.

=cut

sub write_pid {
    my (%params) = @_;

    my $name             = $params{name};
    my $pid              = $params{pid} || $PID;
    my $piddir           = $params{piddir};
    my $user             = $params{user};
    my $group            = $params{group};
    my $multiple_process = $params{multiple_process};

    my $pidfile = _get_pid_file(dir => $piddir, name => $name);

    ## Create piddir
    mkdir($piddir, 0755) unless (-d $piddir);

    unless (
        Sympa::Tools::File::set_file_rights(
            file  => $piddir,
            user  => $user,
            group => $group,
        )
        ) {
        croak "Unable to set rights on $piddir\n";
    }

    my @pids;

    # Lock pid file
    my $lock_fh = Sympa::LockedFile->new($pidfile, 5, '+>>');
    croak "Unable to lock $pidfile file in write mode\n"
        unless $lock_fh;

    ## If pidfile exists, read the PIDs
    if (-s $pidfile) {

        # Read pid file
        seek $lock_fh, 0, 0;
        my $l = <$lock_fh>;
        @pids = grep {/^[0-9]+$/} split(/\s+/, $l);
    }

    ## If we can have multiple instances for the process.
    ## Print other pids + this one
    if ($multiple_process) {
        ## Print other pids + this one
        push(@pids, $pid);

        seek $lock_fh, 0, 0;
        truncate $lock_fh, 0;
        print $lock_fh join(' ', @pids) . "\n";
    } else {
        seek $lock_fh, 0, 0;
        unless (truncate $lock_fh, 0) {
            ## Unlock pid file
            $lock_fh->close();
            croak "Could not truncate $pidfile\n";
        }

        print $lock_fh $pid . "\n";
    }

    unless (
        Sympa::Tools::File::set_file_rights(
            file  => $pidfile,
            user  => $user,
            group => $group,
        )
        ) {
        ## Unlock pid file
        $lock_fh->close();
        croak "Unable to set rights on $pidfile\n";
    }
    ## Unlock pid file
    $lock_fh->close();

    return 1;
}

=item direct_stderr_to_file(%parameters)

Redirect STDERR output of current process into a file, whose name is based on
current PID. If the process crash, its content can be used for analysis.

Parameters:

=over

=item * I<tmpdir>: STDERR file directory

=item * I<user>: STDERR file user

=item * I<group>: STDERR file group

=back

=cut

sub direct_stderr_to_file {
    my (%params) = @_;

    my $tmpdir = $params{tmpdir};
    my $user   = $params{user};
    my $group  = $params{group};

    my $err_file = _get_error_file(dir => $tmpdir, pid => $PID);

    open(STDERR, '>>', $err_file);
    unless (
        Sympa::Tools::File::set_file_rights(
            file  => $err_file,
            user  => $user,
            group => $group,
        )
        ) {
        $main::logger->do_log(
            Sympa::Logger::ERR,
            'Unable to set rights on %s',
            $err_file
        );
        return undef;
    }
    return 1;
}

=item send_crash_report(%parameters)

Send a crash report to listmaster, using crashed process stderr file.

Parameters:

=over

=item * I<pid>: crashed process PID

=item * I<pname>: crashed process name

=item * I<tmpdir>: STDERR file directory

=back

=cut

sub send_crash_report {
    my (%params) = @_;

    my $pid    = $params{pid};
    my $pname  = $params{pname};
    my $tmpdir = $params{tmpdir};

    $main::logger->do_log(
        Sympa::Logger::DEBUG, 'Sending crash report for process %s', $pid
    );
    my $err_file = _get_error_file(dir => $tmpdir, pid => $pid);

    my (@err_output, $err_date);
    if (-f $err_file) {
        open ERR, '<', $err_file;
        @err_output = map { chomp $_; $_; } <ERR>;
        close ERR;
        $err_date = $language->gettext_strftime(
            "%d %b %Y  %H:%M", localtime((stat($err_file))[9])
        );
    }
    Sympa::Site->send_notify_to_listmaster(
        'crash',
        {   'crashed_process' => $pname,
            'crash_err'       => \@err_output,
            'crash_date'      => $err_date,
            'pid'             => $pid
        }
    );
}

=item get_lockname()

Returns a name for current process, suitable for locking.

This name is based on hostname and PID, and is limited to 30 characters.

=cut

sub get_lockname () {
    return substr(substr(hostname(), 0, 20) . $PID, 0, 30);
}

=item get_pids_in_pid_file(%parameters)

Returns the list of PID in the PID file.

Parameters:

=over

=item * I<name>: process name

=item * I<piddir>: PID file directory

=back

=cut

sub get_pids_in_pid_file {
    my (%params) = @_;

    my $name             = $params{name};
    my $piddir           = $params{piddir};

    my $pidfile = _get_pid_file(dir => $piddir, name => $name);

    my $lock_fh = Sympa::LockedFile->new($pidfile, 5, '<');
    unless ($lock_fh) {
        $main::logger->do_log(Sympa::Logger::ERR, "unable to open pidfile %s:%s",
            $pidfile, $ERRNO);
        return undef;
    }
    my $l = <$lock_fh>;
    my @pids = grep {/^[0-9]+$/} split(/\s+/, $l);
    $lock_fh->close;
    return \@pids;
}

=item get_children_processes_list()

Returns the list of PID for childrend of the current process.

=cut

sub get_children_processes_list {
    $main::logger->do_log(Sympa::Logger::DEBUG3, '');
    my @children;
    for my $p (@{Proc::ProcessTable->new()->table()}) {
        if ($p->ppid == $PID) {
            push @children, $p->pid;
        }
    }
    return @children;
}

=item drop_privileges(%parameters)

Set effective UID and GID for the current process.

Parameters:

=over

=item * I<user>: the target user

=item * I<group>: the target group

=back

=cut

sub drop_privileges {
    my (%params) = @_;

    my $uid = (getpwnam($params{user}))[2];
    croak "no such user $params{user}\n" unless defined $uid;
    my $gid = (getpwnam($params{group}))[2];
    croak "no such group $params{group}\n" unless defined $gid;

    # Set the User ID & Group ID for the process
    $UID = $EUID = $uid;
    $GID = $EGID = $gid;

    # Required on FreeBSD to change ALL IDs:
    # effective UID + real UID + saved UID
    POSIX::setuid($uid);
    POSIX::setgid($gid);

    ## Check if the UID has correctly been set (useful on OS X)
    croak "Failed to change process user ID and group ID. Note that on some OS Perl scripts can't change their real UID. In such circumstances Sympa should be run via sudo."
        unless $UID == $uid && $GID == $gid;
}

=item daemonize(%parameters)

Detach the current process from its terminal, fork it, and terminate the parent.

Parameters:

=over

=item * I<name>: daemon name

=back

=cut

sub daemonize {
    my (%params) = @_;

    my $name = $params{name};

    open(STDERR, ">> /dev/null");
    open(STDOUT, ">> /dev/null");

    if (open(TTY, "/dev/tty")) {
        ioctl(TTY, 0x20007471, 0);    #  s/b &TIOCNOTTY
        close(TTY);
    }

    setpgrp(0, 0);

    my $pid = fork();

    if ($pid) {
        # parent
        $main::logger->do_log(
            Sympa::Logger::INFO,
            'Server %s started as a daemon, with PID %s', $name, $pid
        );
        exit(0);
    }
}

sub _get_error_file {
    my (%params) = @_;

    return $params{dir} . '/' . $params{pid} . '.stderr';
}

sub _get_pid_file {
    my (%params) = @_;

    return $params{dir} . '/' . $params{name} . '.pid';
}

=item terminate_on_expected_error($message, @args)

Notify the error, free resources, and terminate current process.

Parameters:

=over

=item * I<$message>: error message, as sprintf format

=item * I<@args>: values to substitute in the precedent string

=back

=cut

sub terminate_on_expected_error {
    my ($message, @args) = @_;

    # notify
    my $full_message = sprintf $message, @args;
    $main::logger->do_log(Sympa::Logger::ERR, $full_message);
    Sympa::Site->send_notify_to_listmaster('sympa_died', [$full_message]);
    print STDERR $full_message . "\n"; 

    # free resources
    eval { Sympa::Site->send_notify_to_listmaster(undef, undef, undef, 1); };
    eval { Sympa::DatabaseManager::db_disconnect(); };    # unlock database

    exit(1);
}

=item terminate_on_unexpected_error($message)

Notify the error, free resources, and terminate current process.

Parameters:

=over

=item * I<$message>: error message

=back

=cut

sub terminate_on_unexpected_error {
    my ($message) = @_;

    # notify
    chomp $message;
    my $full_message = sprintf('DIED: %s', $message);

    $main::logger->do_log(Sympa::Logger::ERR, $full_message);

    ## gather traceback information
    my @calls;
    my @f;
    $_[0] =~ /.+ at (.+? line \d+\.)\n$/s;
    @calls = ($1) if $1;
    for (my $i = 1; @f = caller($i); $i++) {
        $calls[0] = "In $f[3] at $calls[0]" if @calls;
        unshift @calls, "$f[1] line $f[2].";
    }
    $calls[0] = "In (top-level) at $calls[0]";

    print STDERR $full_message . "\n";
    print STDERR join "\n", @calls;
    print STDERR "\n";
    
    # free resources
    eval { Sympa::Site->send_notify_to_listmaster(undef, undef, undef, 1); };
    eval { Sympa::DatabaseManager::db_disconnect(); };    # unlock database

    exit 255;
}

=back

=cut

1;
