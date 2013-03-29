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

Sympa::Lock - File lock object

=head1 DESCRIPTION

This class implements a file lock.

=cut

package Sympa::Lock;

use strict;

use Carp;
use English qw(-no_match_vars);
use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN);
use FileHandle;

use Sympa::Log::Syslog;
use Sympa::Tools::File;

my %list_of_locks;
my $default_timeout = 60 * 20; # After this period a lock can be stolen

=head1 CLASS METHODS

=head2 Sympa::Lock->new(%parameters)

Creates a new L<Sympa::Lock> object.

=head3 Parameters

=over

=item * I<path>: FIXME

=item * I<method>: FIXME

=item * I<user>: FIXME

=item * I<group>: FIXME

=back

=head3 Return value

A new L<Sympa::Lock> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	croak "missing filepath parameter" unless $params{path};
	croak "missing method parameter" unless $params{method};

	Sympa::Log::Syslog::do_log('debug', '(%s)', $params{path});

	my $lock_filename = $params{path}.'.lock';
	my $self = {
		'lock_filename' => $lock_filename,
		'method'        => $params{method}
	};

	# Create include.lock if needed
	my $fh;
	unless (-f $lock_filename) {
		unless (open $fh, ">>$lock_filename") {
			Sympa::Log::Syslog::do_log('err', 'Cannot open %s: %s', $lock_filename, $ERRNO);
			return undef;
		}
		close $fh;
	}

	unless(Sympa::Tools::File::set_file_rights(
			file  => $lock_filename,
			user  => $params{user},
			group => $params{group},
		)) {
		Sympa::Log::Syslog::do_log('err', 'Unable to set rights on %s', $lock_filename);
		return;
	}

	bless $self, $class;

	return $self;
}

=head1 INSTANCE METHODS

=head2 $lock->set_timeout($timeout)

=head3 Parameters

=over

=item * I<$timeout>

=back

=head3 Return value

A true value on sucess, I<undef> otherwise.

=cut

sub set_timeout {
	my ($self, $delay) = @_;

	return undef unless (defined $delay);

	$list_of_locks{$self->{'lock_filename'}}{'timeout'} = $delay;

	return 1;
}

=head1 CLASS METHODS

=head2 Sympa::Lock->get_lock_count()

=cut

sub get_lock_count {
	my ($self) = @_;

	return $#{$list_of_locks{$self->{'lock_filename'}}{'states_list'}} +1;
}

=head2 Sympa::Lock->get_file_handle()

=cut

sub get_file_handle {
	my ($self) = @_;

	return $list_of_locks{$self->{'lock_filename'}}{'fh'};
}

=head1 INSTANCE METHODS

=head2 $lock->lock($mode)

=head3 Parameters

=over

=item * I<$mode>: read | write

=back

=head3 Return value

A true value on sucess, I<undef> otherwise.

=cut

sub lock {
	my ($self, $mode) = @_;
	Sympa::Log::Syslog::do_log('debug', 'Trying to put a lock on %s in mode %s',$self->{'lock_filename'}, $mode);

	# If file was already locked by this process, we will add a new lock.
	# We will need to create a new lock if the state must change.
	if ($list_of_locks{$self->{'lock_filename'}}{'fh'}) {

		# If the mode for the new lock is 'write' and was previously
		# 'read' then we unlock and redo a lock
		if ($mode eq 'write' && $list_of_locks{$self->{'lock_filename'}}{'mode'} eq 'read') {
			Sympa::Log::Syslog::do_log('debug', "Need to unlock and redo locking on %s", $self->{'lock_filename'});
			# First release previous lock
			return undef unless ($self->_remove_lock());
			# Next, lock in write mode
			# WARNING!!! This exact point of the code is a
			# critical point, as any file lock this process could
			# have is currently released. However, we are supposed
			# to have a 'read' lock! If any OTHER process has a
			# read lock on the file, we won't be able to add the
			# new lock. While waiting, the other process can
			# perfectly switch to 'write' mode and start writing
			# in the file THAT OTHER PARTS OF THIS PROCESS ARE
			# CURRENTLY READING. Consequently, if add_lock can't
			# create a lock at its first attempt, it will first
			# try to put a read lock instead. failing that, it
			# will return undef for lock conflicts reasons.
			if ($self->_add_lock($mode,-1)) {
				push @{$list_of_locks{$self->{'lock_filename'}}{'states_list'}}, $mode;
			}
			else {
				return undef unless ($self->_add_lock('read',-1));
			}
			return 1;
		}
		# Otherwise, the previous lock was probably a 'read' lock, so
		# no worries, just increase the locks count.
		Sympa::Log::Syslog::do_log('debug', "No need to change filesystem or NFS lock for %s. Just increasing count.", $self->{'lock_filename'});
		push @{$list_of_locks{$self->{'lock_filename'}}{'states_list'}}, 'read';
		Sympa::Log::Syslog::do_log('debug', "Locked %s again; total locks: %d", $self->{'lock_filename'}, $#{$list_of_locks{$self->{'lock_filename'}}{'states_list'}} +1);
		return 1;
	}

	# If file was not locked by this process, just *create* the lock.
	else {
		if ($self->_add_lock($mode)) {
			push @{$list_of_locks{$self->{'lock_filename'}}{'states_list'}}, $mode;
		}
		else {
			return undef;
		}
	}
	return 1;
}

=head2 $lock->unlock()

=head3 Parameters

None.

=head3 Return value

A true value on sucess, I<undef> otherwise.

=cut

sub unlock {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug', 'Removing lock on %s',$self->{'lock_filename'});

	unless (defined $list_of_locks{$self->{'lock_filename'}}) {
		Sympa::Log::Syslog::do_log('err', "Failed to unlock file %s ; file is not locked", $self->{'lock_filename'});
		return undef;
	}
	my $previous_mode;
	my $current_mode;

	# If it is not the last lock on the file, we revert the lock state to
	# the previous lock.
	if ($#{$list_of_locks{$self->{'lock_filename'}}{'states_list'}} > 0) {
		$previous_mode = pop @{$list_of_locks{$self->{'lock_filename'}}{'states_list'}};
		$current_mode = @{$list_of_locks{$self->{'lock_filename'}}{'states_list'}}[$#{$list_of_locks{$self->{'lock_filename'}}{'states_list'}}];

		# If the new lock mode is different from the one we just
		# removed, we need to create a new file lock.
		if ($previous_mode eq 'write' && $current_mode eq 'read') {
			Sympa::Log::Syslog::do_log('debug3', "Need to unlock and redo locking on %s", $self->{'lock_filename'});

			# First release previous lock
			return undef unless($self->_remove_lock());

			# Next, lock in write mode
			# WARNING!!! This exact point of the code is a
			# critical point, as any file lock this process could
			# have is currently released. However, we are supposed
			# to have a 'read' lock! If any OTHER process has a
			# read lock on the file, we won't be able to add the
			# new lock. While waiting, the other process can
			# perfectly switch to 'write' mode and start writing
			# in the file THAT OTHER PARTS OF THIS PROCESS ARE
			# CURRENTLY READING. Consequently, if add_lock can't
			# create a lock at its first attempt, it will first
			# try to put a read lock instead. failing that, it
			# will return undef for lock conflicts reasons.
			return undef unless ($self->_add_lock($current_mode,-1));
		}
	}
	# Otherwise, just delete the last lock.
	else {
		return undef unless($self->_remove_lock());
		$previous_mode = pop @{$list_of_locks{$self->{'lock_filename'}}{'states_list'}};
		unlink $self->{'lock_filename'};
	}
	return 1;
}

# Called by lock() or unlock() when these function need to add a lock (i.e. on
# the file system or NFS).
sub _add_lock {
	my ($self, $mode, $timeout) = @_;

	# If the $timeout value is -1, it means that we will try to put a lock
	# only once. This is to be used when we are changing the lock mode
	# (from write to read and reverse) and we then  release the file lock
	# to create a new one AND we have previous locks pending in the same
	# process on the same file.
	unless($timeout) {
		$timeout = $list_of_locks{$self->{'lock_filename'}}{'timeout'} || $default_timeout;
	}
	Sympa::Log::Syslog::do_log('debug3', 'Adding lock to file %s in mode %s with a timeout of: %s',$self->{'lock_filename'}, $mode, $timeout);
	my ($fh, $nfs_lock);
	if ($self->{'method'} eq 'nfs') {
		($fh, $nfs_lock) = _lock_nfs($self->{'lock_filename'}, $mode, $timeout);
		return undef unless (defined $fh && defined $nfs_lock);
		$list_of_locks{$self->{'lock_filename'}}{'fh'} = $fh;
		$list_of_locks{$self->{'lock_filename'}}{'mode'} = $mode;
		$list_of_locks{$self->{'lock_filename'}}{'nfs_lock'} = $nfs_lock;
	}else {
		$fh = _lock_file($self->{'lock_filename'}, $mode, $timeout);
		return undef unless (defined $fh);
		$list_of_locks{$self->{'lock_filename'}}{'fh'} = $fh;
		$list_of_locks{$self->{'lock_filename'}}{'mode'} = $mode;
		$list_of_locks{$self->{'lock_filename'}}{'nfs_lock'} = $nfs_lock;
	}
	return 1;
}

# Called by lock() or unlock() when these function need to remove a lock (i.e.
# on the file system or NFS).
sub _remove_lock {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug3', 'Removing lock from file %s',$self->{'lock_filename'});

	my $fh = $list_of_locks{$self->{'lock_filename'}}{'fh'};

	if ($self->{'method'} eq 'nfs') {
		my $nfs_lock = $list_of_locks{$self->{'lock_filename'}}{'nfs_lock'};
		unless (defined $fh && defined $nfs_lock && _unlock_nfs($self->{'lock_filename'}, $fh, $nfs_lock)) {
			Sympa::Log::Syslog::do_log('err', 'Failed to unlock %s', $self->{'lock_filename'});
			# Clean the list of locks anyway
			$list_of_locks{$self->{'lock_filename'}} = undef;
			return undef;
		}
	}else {
		unless (defined $fh && _unlock_file($self->{'lock_filename'}, $fh)) {
			Sympa::Log::Syslog::do_log('err', 'Failed to unlock %s', $self->{'lock_filename'});
			# Clean the list of locks anyway
			$list_of_locks{$self->{'lock_filename'}} = undef;
			return undef;
		}
	}
	$list_of_locks{$self->{'lock_filename'}}{'fh'} = undef;
	return 1
}

# Locks a file - pure interface with the filesystem
sub _lock_file {
	my ($lock_file, $mode, $timeout) = @_;
	Sympa::Log::Syslog::do_log('debug3', '(%s,%s,%d)',$lock_file, $mode,$timeout);

	my $operation;
	my $open_mode;

	if ($mode eq 'read') {
		$operation = LOCK_SH;
	}else {
		$operation = LOCK_EX;
		$open_mode = '>';
	}

	# Read access to prevent "Bad file number" error on Solaris
	my $fh;
	my $untainted_lock_mode = sprintf("%s%s",$open_mode,$lock_file);
	unless (open $fh, $untainted_lock_mode) {
		Sympa::Log::Syslog::do_log('err', 'Cannot open %s: %s', $lock_file, $ERRNO);
		return undef;
	}

	my $got_lock = 1;
	unless (flock ($fh, $operation | LOCK_NB)) {
		if ($timeout == -1) {
			Sympa::Log::Syslog::do_log('err','Unable to get a new lock and other locks pending in this process. Cancelling.');
			return undef;
		}
		Sympa::Log::Syslog::do_log('notice','Waiting for %s lock on %s', $mode, $lock_file);

		# If lock was obtained more than 20 minutes ago, then force
		# the lock
		if ( (time - (stat($lock_file))[9] ) >= $timeout) {
			Sympa::Log::Syslog::do_log('debug3','Removing lock file %s', $lock_file);
			unless (unlink $lock_file) {
				Sympa::Log::Syslog::do_log('err', 'Cannot remove %s: %s', $lock_file, $ERRNO);
				return undef;
			}

			unless (open $fh, ">$lock_file") {
				Sympa::Log::Syslog::do_log('err', 'Cannot open %s: %s', $lock_file, $ERRNO);
				return undef;
			}
		}

		$got_lock = undef;
		my $max = 10;
		$max = 2 if ($ENV{'HTTP_HOST'}); # Web context
		for (my $i = 1; $i < $max; $i++) {
			sleep (10 * $i);
			if (flock ($fh, $operation | LOCK_NB)) {
				$got_lock = 1;
				last;
			}
			Sympa::Log::Syslog::do_log('debug3','Waiting for %s lock on %s', $mode, $lock_file);
		}
	}

	if ($got_lock) {
		Sympa::Log::Syslog::do_log('debug3', 'Got lock for %s on %s', $mode, $lock_file);

		# Keep track of the locking PID
		if ($mode eq 'write') {
			print $fh "$PID\n";
		}
	}else {
		Sympa::Log::Syslog::do_log('err', 'Failed locking %s: %s', $lock_file, $ERRNO);
		return undef;
	}

	return $fh;
}

# Unlocks a file - pure interface with the filesystem
sub _unlock_file {
	my ($lock_file, $fh) = @_;
	Sympa::Log::Syslog::do_log('debug3', '(%s)',$lock_file);

	unless (flock($fh,LOCK_UN)) {
		Sympa::Log::Syslog::do_log('err', 'Failed UNlocking %s: %s', $lock_file, $ERRNO);
		return undef;
	}
	close $fh;
	Sympa::Log::Syslog::do_log('debug3', 'Release lock on %s', $lock_file);

	return 1;
}

# Locks on NFS - pure interface with NFS
sub _lock_nfs {
	my ($lock_file, $mode, $timeout) = @_;
	Sympa::Log::Syslog::do_log('debug3', "($lock_file, $mode, $timeout)");

	# TODO should become a configuration parameter, used with or without
	# NFS
	my $hold = 30;
	my ($open_mode, $operation);

	if ($mode eq 'read') {
		$operation = LOCK_SH;
	}else {
		$operation = LOCK_EX;
		$open_mode = '>>';
	}

	my $nfs_lock = undef;
	my $FH = undef;

	if ($nfs_lock = File::NFSLock->new( {
				file      => $lock_file,
				lock_type => $operation|LOCK_NB,
				blocking_timeout   => $hold,
				stale_lock_timeout => $timeout,
			})) {
		# Read access to prevent "Bad file number" error on Solaris
		$FH = FileHandle->new();
		unless (open $FH, $open_mode.$lock_file) {
			Sympa::Log::Syslog::do_log('err', 'Cannot open %s: %s', $lock_file, $ERRNO);
			return undef;
		}

		Sympa::Log::Syslog::do_log('debug3', 'Got lock for %s on %s', $mode, $lock_file);
		return ($FH, $nfs_lock);
	} else {
		Sympa::Log::Syslog::do_log('err', 'Failed locking %s: %s', $lock_file, $ERRNO);
		return undef;
	}

	return undef;
}

# Unlocks on NFS - pure interface with NFS
sub _unlock_nfs {
	my ($lock_file, $fh, $nfs_lock) = @_;
	Sympa::Log::Syslog::do_log('debug3', "($lock_file, $fh)");

	unless (defined $nfs_lock and $nfs_lock->unlock()) {
		Sympa::Log::Syslog::do_log('err', 'Failed UNlocking %s: %s', $lock_file, $ERRNO);
		return undef;
	}
	close $fh;

	Sympa::Log::Syslog::do_log('debug3', 'Release lock on %s', $lock_file);

	return 1;
}

1;
