# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014, 2015 GIP RENATER
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

Sympa::Tools::Time - Time-related functions

=head1 DESCRIPTION

This package provides some time-related functions.

=cut

package Sympa::Tools::Time;

use strict;
use warnings;
use DateTime;
use Time::Local qw();

## subroutines for epoch and human format date processings

## convert an epoch date into a readable date scalar
# DEPRECATED: No longer used.
#sub adate($epoch);

=item get_midnight_time($timestamp)

Return the date, as a timestamp, corresponding to the last midnight before the given date.

Parameters:

=over

=item * I<$timestamp>: the date, as a timestamp

=back

=cut

# Note: This is used only once.
sub get_midnight_time {
    my $epoch = $_[0];
    my @date  = localtime($epoch);
    return $epoch - $date[0] - $date[1] * 60 - $date[2] * 3600;
}

=item epoch_conv($a, $b)

FIXME.

=cut

sub epoch_conv {
    my $arg = $_[0];             # argument date to convert
    my $time = $_[1] || time;    # the epoch current date

    my $result;

    # decomposition of the argument date
    my $date;
    my $duration;
    my $op;

    if ($arg =~ /^(.+)(\+|\-)(.+)$/) {
        $date     = $1;
        $duration = $3;
        $op       = $2;
    } else {
        $date     = $arg;
        $duration = '';
        $op       = '+';
    }

    #conversion
    $date = date_conv($date, $time);
    $duration = duration_conv($duration, $date);

    if   ($op eq '+') { $result = $date + $duration; }
    else              { $result = $date - $duration; }

    return $result;
}

=item date_conv($a)

FIXME.

=cut

sub date_conv {
    my $arg = shift;

    if ($arg eq 'execution_date') {    # execution date
        return time;
    }

    if ($arg =~ /^\d+$/) {             # already an epoch date
        return $arg;
    }

    if ($arg =~ /^(\d\d\d\dy)(\d+m)?(\d+d)?(\d+h)?(\d+min)?(\d+sec)?$/) {
        # absolute date

        my @date = ($6, $5, $4, $3, $2, $1);
        foreach my $part (@date) {
            $part =~ s/[a-z]+$// if $part;
            $part ||= 0;
            $part += 0;
        }
        $date[3] = 1 if $date[3] == 0;
        $date[4]-- if $date[4] != 0;
        $date[5] -= 1900;

        return Time::Local::timelocal(@date);
    }

    return time;
}

=item duration_conv($a, $b)

FIXME.

=cut

sub duration_conv {

    my $arg        = $_[0];
    my $start_date = $_[1];

    return 0 unless $arg;

    my @date =
        ($arg =~ /(\d+y)?(\d+m)?(\d+w)?(\d+d)?(\d+h)?(\d+min)?(\d+sec)?$/i);
    foreach my $part (@date) {
        $part =~ s/[a-z]+$// if $part;    ## Remove trailing units
        $part ||= 0;
    }

    my $duration =
        $seconds +
        $minutes * 60 +
        $hours   * 60  * 60 +
        $days    * 24  * 60 * 60 +
        $weeks   * 7   * 24 * 60 * 60 +
        $years   * 365 * 24 * 60 * 60;

    # specific processing for the months because their duration varies
    my @months = (
        31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
        31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
    );
    my $start = (defined $start_date) ? (localtime($start_date))[4] : 0;
    for (my $i = 0; $i < $date[1]; $i++) {
        $duration += $months[$start + $i] * 60 * 60 * 24;
    }

    return $duration;
}

=back

=cut

1;
