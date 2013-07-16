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
# along with this program; if not, write to the Free Softwarec
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Datasource::SQL::PostgreSQL - PostgreSQL data source object

=head1 DESCRIPTION

This class implements a PotsgreSQL data source.

=cut

package Sympa::Datasource::SQL::PostgreSQL;

use strict;
use base qw(Sympa::Datasource::SQL);

use Carp;

sub new {
	my ($class, %params) = @_;

	croak "missing db_host parameter" unless $params{db_host};
	croak "missing db_user parameter" unless $params{db_user};

	return $class->SUPER::new(%params, db_type => 'pg');
}

sub connect {
	my ($self, %params) = @_;

	my $result = $self->SUPER::connect(%params);
	return unless $result;
	
	$self->{dbh}->do("SET DATESTYLE TO 'ISO'");
	$self->{dbh}->do("SET NAMES 'utf8'");

	return 1;
}


sub get_connect_string{
	my ($self) = @_;

	return "DBI:Pg:dbname=$self->{db_name};host=$self->{db_host}";
}

1;
