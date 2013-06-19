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

Sympa::Datasource::SQL::MySQL - MySQL data source object

=head1 DESCRIPTION

This class implements a MySQL data source.

=cut

package Sympa::Datasource::SQL::MySQL;

use strict;
use base qw(Sympa::Datasource::SQL);

use Sympa::Log::Syslog;

sub new {
	my ($class, %params) = @_;

	return $class->SUPER::new(%params, db_type => 'mysql');
}

sub build_connect_string {
	my ($self) = @_;

	$self->{'connect_string'} =
		"DBI:mysql:$self->{'db_name'}:$self->{'db_host'}";
}

sub get_substring_clause {
	my ($self, %params) = @_;

	return sprintf
		"REVERSE(SUBSTRING(%s FROM position('%s' IN %s) FOR %s))",
		$params{'source_field'},
		$params{'separator'},
		$params{'source_field'},
		$params{'substring_length'};
}

sub get_limit_clause {
	my ($self, %params) = @_;

	if ($params{'offset'}) {
		return sprintf "LIMIT %s,%s",
			$params{'offset'},
			$params{'rows_count'};
	} else {
		return sprintf "LIMIT %s",
			$params{'rows_count'};
	}
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

sub is_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Checking whether field %s.%s is autoincremental',
		$params{'field'},
		$params{'table'}
	);

	my $query = 
		"SHOW FIELDS "                 .
		"FROM $params{table} "         .
		"WHERE Extra = ? AND Field = ?";
	my $row = $self->{dbh}->selectrow_hashref(
		$query,
		undef,
		'auto_increment',
		$params{'field'}
	);
	unless ($row) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to gather autoincrement field named %s for table %s',
			$params{'field'},
			$params{'table'}
		);
		return undef;
	}
	return $row->{'field'} eq $params{'field'};
}

sub set_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Setting field %s.%s as autoincremental',
		$params{'field'},
		$params{'table'}
	);

	my $field_type = defined ($params{'field_type'}) ? $params{'field_type'} : 'BIGINT( 20 )';
	my $query = 
		"ALTER TABLE $params{table} CHANGE $params{field} " .
		"$params{field} $field_type NOT NULL AUTO_INCREMENT";
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to set field %s in table %s as autoincrement',
			$params{'field'},
			$params{'table'}
		);
		return undef;
	}

	return 1;
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Retrieving all tables in database %s',
		$self->{'db_name'}
	);
	my @tables = $self->{'dbh'}->tables();

	foreach my $table (@tables) {
		$table =~ s/^\`[^\`]+\`\.//; # drop db name prefix
		$table =~ s/^\`(.+)\`$/$1/;  # drop quotes
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
		"CREATE TABLE $params{table} (" . join(',', @clauses) . ") " .
		"DEFAULT CHARACTER SET utf8";

	return $query;
}

sub _get_field_clause {
	my ($self, %params) = @_;

	my $clause = "$params{name} $params{type}";
	$clause .= ' NOT NULL'       if $params{notnull};
	$clause .= ' AUTO_INCREMENT' if $params{autoincrement};

	return $clause;
}

sub _get_native_type {
	my ($self, $type) = @_;

	return $type;
}

sub get_fields {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting fields list from table %s in database %s',
		$params{'table'},
		$self->{'db_name'}
	);

	my $query = "SHOW FIELDS FROM $params{table}";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get the list of fields from table %s in database %s',
			$params{'table'},
			$self->{'db_name'}
		);
		return undef;
	}
	$sth->execute();

	my %result;
	while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
		$result{$row->{'field'}} = $row->{'type'};
	}
	return \%result;
}

sub get_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting primary key for table %s',
		$params{'table'}
	);

	my $query = "SHOW COLUMNS FROM $params{table}";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get field list from table %s in database %s',
			$params{'table'},
			$self->{'db_name'}
		);
		return undef;
	}
	$sth->execute();

	my @fields;
	while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
		push @fields, $row->{field} if $row->{key} eq 'PRI';
	}

	return \@fields;
}

sub get_indexes {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Looking for indexes in %s',
		$params{'table'}
	);

	my $query = "SHOW INDEX FROM $params{table}";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get the list of indexes from table %s in database %s',
			$params{'table'},
			$self->{'db_name'}
		);
		return undef;
	}
	$sth->execute();

	my %indexes;
	while(my $row = $sth->fetchrow_hashref('NAME_lc')) {
		next if $row->{'key_name'} eq "PRIMARY";
		$indexes{$row->{'key_name'}}->{$row->{'column_name'}} = 1;
	}

	return \%indexes;
}

1;
