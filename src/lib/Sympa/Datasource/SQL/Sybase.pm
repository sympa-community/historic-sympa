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

Sympa::Datasource::SQL::Sybase - Sybase data source object

=head1 DESCRIPTION

This class implements a Sybase data source.

=cut

package Sympa::Datasource::SQL::Sybase;

use strict;
use base qw(Sympa::Datasource::SQL);

use Carp;

use Sympa::Log::Syslog;

our %date_format = (
	'read' => {
		'Sybase' => 'datediff(second, \'01/01/1970\',%s)',
	},
	'write' => {
		'Sybase' => 'dateadd(second,%s,\'01/01/1970\')',
	}
);

sub new {
	my ($class, %params) = @_;

	return $class->SUPER::new(%params, db_type => 'sybase');
}


sub get_connect_string{
	my ($self) = @_;

	return
		"DBI:Sybase:database=$self->{'db_name'};server=$self->{'db_host'}";
}

sub get_substring_clause {
	my ($self, %params) = @_;

	return sprintf
		"substring(%s,charindex('%s',%s)+1,%s)",
		$params{'source_field'},
		$params{'separator'},
		$params{'source_field'},
		$params{'substring_length'};
}

sub get_limit_clause {
	my ($self, %params) = @_;

	return "";
}

sub get_formatted_date {
	my ($self, %params) = @_;

	my $mode = lc($params{'mode'});
	if ($mode eq 'read') {
		return sprintf 'UNIX_TIMESTAMP(%s)',$params{'target'};
	} elsif ($mode eq 'write') {
		return sprintf 'FROM_UNIXTIME(%d)',$params{'target'};
	} else {
		Sympa::Log::Syslog::do_log(
			'err',
			"Unknown date format mode %s",
			$params{'mode'}
		);
		return undef;
	}
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting tables list',
	);

	my $query =
		"SELECT name FROM $self->{db_name}..sysobjects WHERE type='U'";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to get tables list'
		);
		return undef;
	}
	$sth->execute();

	my @tables;
	while (my $row = $sth->fetchrow_arrayref()) {
		push @tables, lc($row->[0]);
	}

	return @tables;
}

sub _get_table_query {
	my ($self, %params) = @_;

	my @clauses =
		map { $self->_get_field_clause(%$_) }
		@{$params{fields}};
	push @clauses, $self->_get_primary_key_clause(@{$params{key}})
		if $params{key};

	my $query =
		"CREATE TABLE $params{table} (" . join(',', @clauses) . ")";
	return $query;
}

sub _get_native_type {
	my ($self, $type) = @_;

	return 'numeric'      if $type =~ /^int/;
	return 'numeric'      if $type =~ /^smallint/;
	return 'numeric'      if $type =~ /^bigint/;
	return 'varchar(500)' if $type =~ /^text/;
	return 'text'         if $type =~ /^longtext/;
	return 'varchar(15)'  if $type =~ /^enum/;
	return $type
}

1;
