# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:et:sw=4:textwidth=78
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=encoding utf-8

=head1 NAME

Sympa::LDAP - LDAP functions

=head1 DESCRIPTION

This module provides LDAP-related functions.

=cut

package Sympa::LDAP;

use strict;

use English qw(-no_match_vars);

use Sympa::Log::Syslog;

my @valid_options = qw(host suffix filter scope bind_dn bind_password);
my  @required_options = qw(host suffix filter);

my %valid_options = ();
map { $valid_options{$_}++; } @valid_options;

my %required_options = ();
map { $required_options{$_}++; } @required_options;

my %Default_Conf = (
    'host'          => undef,
    'suffix'        => undef,
    'filter'        => undef,
    'scope'         => 'sub',
    'bind_dn'       => undef,
    'bind_password' => undef
);

my %Ldap = ();

=head1 FUNCTIONS

=over

=item load($config)

Loads and parses the configuration file. Reports errors if any.

Parameters:

=over

=item string

The configuration file.

=back

Return value:

The configuration, as an hash.

=cut

sub load {
    my ($config) = @_;
    Sympa::Log::Syslog::do_log('debug3', '(%s)', $config);

    my $line_num = 0;
    my $config_err = 0;
    my($i, %o);

    ## Open the configuration file or return and read the lines.
    unless (open(IN, $config)) {
        Sympa::Log::Syslog::do_log('err','Unable to open %s: %s', $config, $ERRNO);
        return undef;
    }

    my $folded_line;
    while (my $current_line = <IN>) {
        $line_num++;
        next if ($current_line =~ /^\s*$/o || $current_line =~ /^[\#\;]/o);

        ## Cope with folded line (ending with '\')
        if ($current_line =~ /\\\s*$/) {
            $current_line =~ s/\\\s*$//; ## remove trailing \
            chomp $current_line;
            $folded_line .= $current_line;
            next;
        } elsif (defined $folded_line) {
            $current_line = $folded_line.$current_line;
            $folded_line = undef;
        }

        if ($current_line =~ /^(\S+)\s+(.+)$/io) {
            my($keyword, $value) = ($1, $2);
            $value =~ s/\s*$//;

            $o{$keyword} = [ $value, $line_num ];
        } else {
#	    printf STDERR Msg(1, 3, "Malformed line %d: %s"), $config, $_;
            $config_err++;
        }
    }
    close(IN);


    ## Check if we have unknown values.
    foreach $i (sort keys %o) {
        $Ldap{$i} = $o{$i}[0] || $Default_Conf{$i};

        unless ($valid_options{$i}) {
            Sympa::Log::Syslog::do_log('err',"Line %d, unknown field: %s \n", $o{$i}[1], $i);
            $config_err++;
        }
    }
    ## Do we have all required values ?
    foreach $i (keys %required_options) {
        unless (defined $o{$i} or defined $Default_Conf{$i}) {
            Sympa::Log::Syslog::do_log('err',"Required field not found : %s\n", $i);
            $config_err++;
            next;
        }
    }
    return %Ldap;
}

=back

=cut

1;
