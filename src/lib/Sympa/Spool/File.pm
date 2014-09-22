# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
# Copyrigh (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
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
# along with this program.  If not, see <http://www.gnu.org/licenses>.

=head1 NAME

Sympa::Spool::File - File-based spool

=head1 DESCRIPTION

This class implements a spool based on filesystem.

=cut

package Sympa::Spool::File;

use strict;
use warnings;

use Carp qw(croak);
use English qw(-no_match_vars);
use File::Copy;
use File::Path qw(make_path);

use Sympa::Constants;
use Sympa::Tools;
use Sympa::Tools::File;

our $filename_regexp = '^(\S+)\.(\d+)\.\w+$';

our %classes = (
    'msg'  => 'Sympa::Spool::File::Message',
    'task' => 'Sympa::Spool::File::Task',
    'mod'  => 'Sympa::Spool::File::Key',
);

=head1 CLASS METHODS

=over 4

=item new ( NAME, STATUS, OPTIONS... )

I<Constructor>.
Creates a new L<Sympa::Spool::File> object.

XXX @todo doc

=back

=cut

## Creates an object.
sub new {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, %s, %s, ...)', @_);
    my ($pkg, $spoolname, $dir, $selection_status, %opts) = @_;

    my $self;

    if (!$dir) {
        $main::logger->do_log(
            Sympa::Logger::ERR, 'Missing directory parameter'
        );
        return undef;
    }
    if ($selection_status and $selection_status eq 'bad') {
        $dir .= '/bad';
    }

    $self = bless {
        'spoolname'        => $spoolname,
        'selection_status' => $selection_status,
        'dir'              => $dir,
    } => $pkg;
    $self->{'selector'} = $opts{'selector'} if $opts{'selector'};
    $self->{'sortby'}   = $opts{'sortby'}   if $opts{'sortby'};
    $self->{'way'}      = $opts{'way'}      if $opts{'way'};

    $main::logger->do_log(Sympa::Logger::DEBUG3, 'Spool to scan "%s"', $dir);

    $self->create_spool_dir;

    return $self;
}

# total spool_table count : not object oriented, just a subroutine
sub global_count {
    my @files          = <Sympa::Constants::SPOOLDIR/*>;
    my $count          = @files;

    return $count;
}

sub count {
    my $self = shift;
    return ($self->get_content({'selection' => 'count'}));
}

=over 4

=item get_content ( OPTIONS... )

I<Instance method>.
XXX @todo doc

=back

=cut

#######################
#
#  get_content return the content an array of hash describing the spool
#  content
#
sub get_content {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, %s)', @_);
    my $self = shift;
    my $param = shift || {};
    my $perlselector =
           _perlselector($param->{'selector'})
        || _perlselector($self->{'selector'})
        || '1';
    my $perlcomparator = _perlcomparator($param->{'sortby'}, $param->{'way'})
        || _perlcomparator($self->{'sortby'}, $self->{'way'});
    my $offset = $param->{'offset'} || 0;
    my $page_size = $param->{'page_size'};

    # the fields to select. possible values are :
    #    -  '*'  is the default .
    #    -  '*_but_message' mean any field except message which may be huge
    #       and unuseful while listing spools
    #    - 'count' mean the selection is just a count.
    # should be used mainly to select only metadata that may be huge and
    # may be unuseful
    my $selection = $param->{'selection'} || '*';

    my @messages;
    foreach my $key ($self->get_files_in_spool) {
        next unless $self->is_readable($key);
        my $item = $self->parse_filename($key);

        # We don't decide moving erroneous file to bad spool here, since it
        # may be a temporary file "T.xxx" and so on.
        next unless $item;

        # Get additional details from spool file, likely to be used in
        # queries.
        unless ($self->get_additional_details($item->{'messagekey'}, $item)) {
            $self->move_to_bad($item->{'messagekey'});
            next;
        }
        my $cmp = eval $perlselector;
        if ($EVAL_ERROR) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Failed to evaluate selector: %s', $EVAL_ERROR);
            return undef;
        }
        next unless $cmp;
        push @messages, $item;
    }

    # Sorting
    if ($perlcomparator) {
        my @sorted = eval sprintf 'sort { %s } @messages', $perlcomparator;
        if ($EVAL_ERROR) {
            $main::logger->do_log(Sympa::Logger::ERR, 'Could not sort messages: %s',
                $EVAL_ERROR);
        } else {
            @messages = @sorted;
        }
    }

    # Paging
    my $end;
    if ($page_size) {
        $end = $offset + $page_size;
        $end = scalar @messages if $end > scalar @messages;
    } else {
        $end = scalar @messages;
    }

    # Field selection
    if ($selection eq '*_but_message') {
        return () if $offset >= scalar @messages;
        return (splice @messages, $offset, $end - $offset);
    } elsif ($selection eq 'count') {
        return 0 if $offset >= scalar @messages;
        my @retained_messages = splice @messages, $offset, $end - $offset;
        return scalar(scalar @retained_messages);
    }

    # Extract subset
    my @ret = ();
    my $i   = 0;
    foreach my $item (@messages) {
        last if $end <= $i;
        unless ($self->parse_file_content($item->{'messagekey'}, $item)) {
            $self->move_to_bad($item->{'messagekey'});
            next;
        }
        push @ret, $item
            if $offset <= $i;
        $i++;
    }
    return @ret;
}

sub get_count {
    my $self     = shift;
    my $param    = shift;
    my @messages = $self->get_content($param);
    return $#messages + 1;
}

# Returns the single file corresponding to the selector.
sub get_file_key {
    my $self     = shift;
    my $selector = shift;
    my $message;
    unless ($message = $self->get_message($selector)) {
        return undef;
    }
    return $message->{'messagekey'};
}

=over 4

=item next ( )

I<Instance method>.
XXX @todo doc

=back

=cut

#######################
#
#  next : return next spool entry ordered by priority next lock the
#  message_in_spool that is returned
#  returns 0 if no file found
#  returns undef if problem scanning spool
sub next {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);
    my $self = shift;

    my $data;

    unless ($self->refresh_spool_files_list) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to refresh spool %s files list', $self);
        return undef;
    }
    return 0 unless ($#{$self->{'spool_files_list'}} > -1);
    return 0 unless $data = $self->get_next_file_to_process;
    unless ($self->parse_file_content($data->{'messagekey'}, $data)) {
        $self->move_to_bad($data->{'messagekey'});
        return undef;
    }
    return $data;
}

#FIXME: This would be replaced by Sympa::Message::new().
sub parse_filename {
    my $self = shift;
    my $key  = shift;

    unless ($key) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to find out which file to process');
        return undef;
    }

    my $data = {
        'file'       => $self->{'dir'} . '/' . $key,
        'messagekey' => $key,
    };

    unless ($self->is_relevant($key)) {
        return undef;
    }
    unless ($self->analyze_file_name($key, $data)) {
        return undef;
    }
    return $data;
}

#FIXME: This would be replaced by Sympa::Message::load().
sub parse_file_content {
    my $self = shift;
    my $key  = shift;
    my $data = shift;

    unless ($key) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to find out which file to process');
        return undef;
    }

    $data->{'messageasstring'} = $self->get_file_content($key);
    unless (defined $data->{'messageasstring'}) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to gather content from file %s', $key);
        return undef;
    }
    return $data;
}

# Placeholder: overriden in inheriting classes to get additionnal details from
# the file content.
sub get_additional_details {
    my $self = shift;
    my $key  = shift;
    my $data = shift;
    return 1;
}

sub get_next_file_to_process {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);
    my $self = shift;

    my $perlselector = _perlselector($self->{'selector'}) || '1';
    my $perlcomparator = _perlcomparator($self->{'sortby'}, $self->{'way'});

    my $data = undef;
    my $cmp;
    foreach my $key (@{$self->{'spool_files_list'}}) {
        next unless $self->is_readable($key);
        my $item = $self->parse_filename($key);
        next unless $item;

        $cmp = eval $perlselector;
        if ($EVAL_ERROR) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Failed to evaluate selector: %s', $EVAL_ERROR);
            return undef;
        }
        next unless $cmp;

        unless ($data) {
            $data = $item;
            next;
        }
        my ($a, $b) = ($data, $item);
        $cmp = eval $perlcomparator;
        if ($EVAL_ERROR) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Could not compare messages: %s', $EVAL_ERROR);
            return $data;
        }
        if ($cmp > 0) {
            $data = $item;
        }
    }
    return $data;
}

sub is_relevant {
    return 1;
}

sub is_readable {
    my $self = shift;
    my $key  = shift;

    if (-f "$self->{'dir'}/$key" && -r _) {
        return 1;
    } else {
        return 0;
    }
}

sub get_file_content {
    $main::logger->do_log(Sympa::Logger::DEBUG3, '(%s, %s)', @_);
    my $self = shift;
    my $key  = shift;

    my $fh;
    unless (open $fh, $self->{'dir'} . '/' . $key) {
        $main::logger->do_log(
            Sympa::Logger::ERR,
            'Unable to open file %s: %s',
            $self->{'dir'} . '/' . $key, $ERRNO
        );
        return undef;
    }
    local $RS;
    my $messageasstring = <$fh>;
    close $fh;
    return $messageasstring;
}

sub lock_message {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, %s)', @_);
    my $self = shift;
    my $key  = shift;

    $self->{'lock'} = Sympa::Lock->new($key);
    $self->{'lock'}->set_timeout(-1);
    unless ($self->{'lock'}->lock('write')) {
        $main::logger->do_log(Sympa::Logger::ERR, 'Unable to put a lock on file %s',
            $key);
        delete $self->{'lock'};
        return undef;
    }
    return 1;
}

sub unlock_message {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, %s)', @_);
    my $self = shift;
    my $key  = shift;

    unless (ref($self->{'lock'}) and $self->{'lock'}->isa('Sympa::Lock')) {
        delete $self->{'lock'};
        return undef;
    }
    unless ($self->{'lock'}->unlock()) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to remove lock from file %s', $key);
        delete $self->{'lock'};
        return undef;
    }
    return 1;
}

sub get_files_in_spool {
    my $self = shift;
    return undef unless ($self->refresh_spool_files_list);
    return @{$self->{'spool_files_list'}};
}

sub get_dirs_in_spool {
    my $self = shift;
    return undef unless ($self->refresh_spool_dirs_list);
    return @{$self->{'spool_dirs_list'}};
}

sub refresh_spool_files_list {
    my $self = shift;
    $main::logger->do_log(Sympa::Logger::DEBUG2, '%s', $self->get_id);
    unless (-d $self->{'dir'}) {
        $self->create_spool_dir;
    }
    unless (opendir SPOOLDIR, $self->{'dir'}) {
        $main::logger->do_log(
            Sympa::Logger::ERR,
            'Unable to access %s spool. Please check proper rights are set;',
            $self->{'dir'}
        );
        return undef;
    }
    my @qfile =
        sort Sympa::Tools::by_date grep { !/^\./ && -f "$self->{'dir'}/$_" }
        readdir(SPOOLDIR);
    closedir(SPOOLDIR);
    $self->{'spool_files_list'} = \@qfile;
    return 1;
}

sub refresh_spool_dirs_list {
    my $self = shift;
    $main::logger->do_log(Sympa::Logger::DEBUG2, '%s', $self->get_id);
    unless (-d $self->{'dir'}) {
        $self->create_spool_dir;
    }
    unless (opendir SPOOLDIR, $self->{'dir'}) {
        $main::logger->do_log(
            Sympa::Logger::ERR,
            'Unable to access %s spool. Please check proper rights are set;',
            $self->{'dir'}
        );
        return undef;
    }
    my @qdir =
        sort Sympa::Tools::by_date grep { !/^(\.\.|\.)$/ && -d "$self->{'dir'}/$_" }
        readdir(SPOOLDIR);
    closedir(SPOOLDIR);
    $self->{'spool_dirs_list'} = \@qdir;
    return 1;
}

sub create_spool_dir {
    my $self = shift;
    $main::logger->do_log(Sympa::Logger::DEBUG, '%s', $self->get_id);
    unless (-d $self->{'dir'}) {
        make_path($self->{'dir'});
    }
}

=over 4

=item move_to_bad ( OPTIONS... )

I<Instance method>.
XXX @todo doc

=back

=cut

sub move_to_bad {
    $main::logger->do_log(Sympa::Logger::DEBUG3, '(%s, %s)', @_);
    my $self = shift;
    my $key  = shift;

    unless (-d $self->{'dir'} . '/bad') {
        make_path($self->{'dir'} . '/bad');
    }
    unless (
        File::Copy::copy(
            $self->{'dir'} . '/' . $key,
            $self->{'dir'} . '/bad/' . $key
        )
        ) {
        $main::logger->do_log(
            Sympa::Logger::ERR,
            'Could not move file %s to spool bad %s: %s',
            $self->{'dir'} . '/' . $key,
            $self->{'dir'} . '/bad', $ERRNO
        );
        return undef;
    }
    unless (unlink($self->{'dir'} . '/' . $key)) {
        $main::logger->do_log(Sympa::Logger::ERR,
            "Could not unlink message %s/%s . Exiting",
            $self->{'dir'}, $key);
    }
    $self->unlock_message($key);
    return 1;
}

=over 4

=item get_message ( OPTIONS... )

I<Instance method>.
XXX @todo doc

=back

=cut

#################"
# return one message from related spool using a specified selector
# returns undef if message was not found.
#
sub get_message {
    my $self     = shift;
    my $selector = shift;
    my @messages;
    return undef
        unless @messages = $self->get_content({'selector' => $selector});
    return $messages[0];
}

#################"
# lock one message from related spool using a specified selector
#
#sub unlock_message {
#
#    my $self = shift;
#    my $messagekey = shift;
#
#    $main::logger->do_log(Sympa::Logger::DEBUG, 'Spool::unlock_message(%s,%s)',$self->{'spoolname'}, $messagekey);
#    return ( $self->update({'messagekey' => $messagekey},
#			   {'messagelock' => 'NULL'}));
#}

sub move_to {
    my $self         = shift;
    my $param        = shift;
    my $target       = shift;
    my $file_to_move = $self->get_message($param);
    my $new_spool    = Sympa::Spool::File->new($target);
    if ($classes{$target}) {
        bless $new_spool, $target;
    }
    $new_spool->store($file_to_move);
    $self->remove_message("$file_to_move->{'messagekey'}");
    return 1;
}

sub update {
    croak 'Not implemented yet';
}

=over 4

=item store ( OPTIONS... )

I<Instance method>.
XXX @todo doc

=back

=cut

################"
# store a message in spool
#
sub store {
    my $self            = shift;
    my $messageasstring = shift;
    my $param           = shift;
    my $target_file     = $param->{'filename'};
    $target_file ||= $self->get_storage_name($param);
    my $fh;
    unless (open $fh, ">", "$self->{'dir'}/$target_file") {
        $main::logger->do_log(Sympa::Logger::ERR, 'Unable to write file to spool %s',
            $self->{'dir'});
        return undef;
    }
    print $fh $messageasstring;
    close $fh;
    return 1;
}

=over 4

=item remove_message ( OPTIONS... )

I<Instance method>.
XXX @todo doc

=back

=cut

################"
# remove a message in database spool using (messagekey,list,robot) which are a
# unique id in the spool
#
sub remove_message {
    my $self = shift;
    my $key  = shift;

    unless (unlink $self->{'dir'} . '/' . $key) {
        $main::logger->do_log(
            Sympa::Logger::ERR,
            'Unable to remove file %s: %s',
            $self->{'dir'} . '/' . $key, $ERRNO
        );
        return undef;
    }
    return 1;
}

=over 4

=item clean ( OPTIONS... )

I<Instance method>.
XXX @todo doc

=back

=cut

################"
# Clean a spool by removing old messages
#

sub clean {
    my $self   = shift;
    my $filter = shift;
    $main::logger->do_log(
        Sympa::Logger::DEBUG, 'Cleaning spool %s (%s), delay: %s',
        $self->{'spoolname'}, $self->{'selection_status'},
        $filter->{'delay'}
    );

    return undef unless $self->{'spoolname'};
    return undef unless $filter->{'delay'};

    my $freshness_date = time - ($filter->{'delay'} * 60 * 60 * 24);
    my $deleted = 0;

    my @to_kill = $self->get_files_in_spool;
    foreach my $f (@to_kill) {
        if ((stat "$self->{'dir'}/$f")[9] < $freshness_date) {
            if (unlink("$self->{'dir'}/$f")) {
                $deleted++;
                $main::logger->do_log(Sympa::Logger::NOTICE, 'Deleting old file %s',
                    "$self->{'dir'}/$f");
            } else {
                $main::logger->do_log(Sympa::Logger::NOTICE,
                    'unable to delete old file %s: %s',
                    "$self->{'dir'}/$f", $ERRNO);
            }
        } else {
            last;
        }
    }
    @to_kill = $self->get_dirs_in_spool;
    foreach my $d (@to_kill) {
        if ((stat "$self->{'dir'}/$d")[9] < $freshness_date) {
            if (Sympa::Tools::File::remove_dir("$self->{'dir'}/$d")) {
                $deleted++;
                $main::logger->do_log(Sympa::Logger::NOTICE, 'Deleting old file %s',
                    "$self->{'dir'}/$d");
            } else {
                $main::logger->do_log(Sympa::Logger::NOTICE,
                    'unable to delete old file %s: %s',
                    "$self->{'dir'}/$d", $ERRNO);
            }
        } else {
            last;
        }
    }

    $main::logger->do_log(Sympa::Logger::DEBUG,
        "%s entries older than %s days removed from spool %s",
        $deleted, $filter->{'delay'}, $self->{'spoolname'});
    return 1;
}

sub _perlselector {
    my $selector = shift || {};

    my ($comparator, $value, $perl_key);

    my @perl_clause = ();
    foreach my $criterium (keys %{$selector}) {
        if (ref($selector->{$criterium}) eq 'ARRAY') {
            ($value, $comparator) = @{$selector->{$criterium}};
            $comparator = 'eq' unless $comparator and $comparator eq 'ne';
        } else {
            ($value, $comparator) = ($selector->{$criterium}, 'eq');
        }

        $perl_key = sprintf '$item->{"%s"}', $criterium;

        push @perl_clause,
            sprintf '%s %s "%s"', $perl_key, $comparator, quotemeta $value;
    }

    return join ' and ', @perl_clause;
}

sub _perlcomparator {
    my $orderby = shift;
    my $way     = shift;

    return undef unless $orderby;

    if ($orderby eq 'date' or $orderby eq 'size') {
        if ($way and $way eq 'desc') {
            return sprintf '$b->{"%s"} <=> $a->{"%s"}', $orderby, $orderby;
        } else {
            return sprintf '$a->{"%s"} <=> $b->{"%s"}', $orderby, $orderby;
        }
    } else {
        if ($way and $way eq 'desc') {
            return sprintf '$b->{"%s"} cmp $a->{"%s"}', $orderby, $orderby;
        } else {
            return sprintf '$a->{"%s"} cmp $b->{"%s"}', $orderby, $orderby;
        }
    }
}

## Get unique ID
sub get_id {
    my $self = shift;
    return sprintf '%s/%s',
        $self->{'spoolname'}, ($self->{'selection_status'} || 'ok');
}

1;
