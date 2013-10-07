# -*- indent-tabs-mode: nil; -*-
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

Sympa::Datasource::SQL::SQLite - SQLite data source object

=head1 DESCRIPTION

This class implements an SQLite data source.

=cut

package Sympa::Datasource::SQL::SQLite;

use strict;
use base qw(Sympa::Datasource::SQL);

use Carp;

sub new {
    my ($class, %params) = @_;

    return $class->SUPER::new(%params, db_type => 'sqlite');
}

sub connect {
    my ($self, %params) = @_;

    my $result = $self->SUPER::connect(%params);
    return unless $result;

    $self->{dbh}->func(
        'func_index',
        -1,
        sub { return index($_[0], $_[1]) },
        'create_function'
    );

    if (defined $self->{db_timeout}) {
        $self->{dbh}->func($self->{db_timeout}, 'busy_timeout' );
    } else {
        $self->{dbh}->func(5000, 'busy_timeout');
    }

    return 1;
}

sub get_connect_string{
    my ($self, %params) = @_;

    return "DBI:SQLite:dbname=$self->{db_name}";
}

1;
