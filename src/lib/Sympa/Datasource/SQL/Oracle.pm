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

Sympa::Datasource::SQL::Oracle - Oracle data source object

=head1 DESCRIPTION

This class implements an Oracle data source.

=cut

package Sympa::Datasource::SQL::Oracle;

use strict;
use base qw(Sympa::Datasource::SQL);

use Carp;

sub new {
	my ($class, %params) = @_;

	croak "missing db_host parameter" unless $params{db_host};
	croak "missing db_user parameter" unless $params{db_user};

	return $class->SUPER::new(%params, db_type => 'oracle');
}

sub connect {
	my ($self, %params) = @_;

	my $result = $self->SUPER::connect(%params);
	return unless $result;
	
	$ENV{'NLS_LANG'} = 'UTF8';

	return 1;
}

sub get_connect_string {
	my ($self) = @_;

	my $string = "DBI:Oracle:";
	if ($self->{db_host} && $self->{db_name}) {
		$string .= "host=$self->{db_host};sid=$self->{db_name}";
	}

	return $string;
}

1;
