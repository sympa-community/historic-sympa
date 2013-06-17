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


sub build_connect_string{
	my ($self) = @_;

	$self->{'connect_string'} =
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
		Sympa::Log::Syslog::do_log('err',"Unknown date format mode %s", $params{'mode'});
		return undef;
	}
}

sub is_autoinc {
	my ($self, %params) = @_;
	croak "not implemented";
}

sub set_autoinc {
	my ($self, %params) = @_;
	croak "not implemented";
}

sub get_tables {
	my ($self) = @_;

	my @raw_tables;
	my $sth = $self->do_query(
		"SELECT name FROM %s..sysobjects WHERE type='U'",
		$self->{'db_name'}
	);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve the list of tables from database %s',$self->{'db_name'});
		return undef;
	}
	while (my $table= $sth->fetchrow()) {
		push @raw_tables, lc ($table);
	}
	return @raw_tables;
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

sub get_fields {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Getting fields list from table %s in database %s',$params{'table'},$self->{'db_name'});
	my $sth = $self->do_query(
		"SHOW FIELDS FROM %s",
		$params{'table'}
	);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the list of fields from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my %result;
	while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
		$result{$ref->{'field'}} = $ref->{'type'};
	}
	return \%result;
}

sub update_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Updating field %s in table %s (%s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'});
	my $options;
	if ($params{'notnull'}) {
		$options .= ' NOT NULL ';
	}
	my $report = sprintf("ALTER TABLE %s CHANGE %s %s %s %s",$params{'table'},$params{'field'},$params{'field'},$params{'type'},$options);
	Sympa::Log::Syslog::do_log('notice', "ALTER TABLE %s CHANGE %s %s %s %s",$params{'table'},$params{'field'},$params{'field'},$params{'type'},$options);
	unless ($self->do_query("ALTER TABLE %s CHANGE %s %s %s %s",$params{'table'},$params{'field'},$params{'field'},$params{'type'},$options)) {
		Sympa::Log::Syslog::do_log('err', 'Could not change field \'%s\' in table\'%s\'.',$params{'field'}, $params{'table'});
		return undef;
	}
	$report .= sprintf('\nField %s in table %s, structure updated', $params{'field'}, $params{'table'});
	Sympa::Log::Syslog::do_log('info', 'Field %s in table %s, structure updated', $params{'field'}, $params{'table'});
	return $report;
}

sub add_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Adding field %s in table %s (%s, %s, %s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'},$params{'autoinc'},$params{'primary'});
	my $options;
	# To prevent "Cannot add a NOT NULL column with default value NULL" errors
	if ($params{'notnull'}) {
		$options .= 'NOT NULL ';
	}
	if ( $params{'autoinc'}) {
		$options .= ' AUTO_INCREMENT ';
	}
	if ( $params{'primary'}) {
		$options .= ' PRIMARY KEY ';
	}
	unless ($self->do_query("ALTER TABLE %s ADD %s %s %s",$params{'table'},$params{'field'},$params{'type'},$options)) {
		Sympa::Log::Syslog::do_log('err', 'Could not add field %s to table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf('Field %s added to table %s (options : %s)', $params{'field'}, $params{'table'}, $options);
	Sympa::Log::Syslog::do_log('info', 'Field %s added to table %s  (options : %s)', $params{'field'}, $params{'table'}, $options);

	return $report;
}

sub delete_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Deleting field %s from table %s',$params{'field'},$params{'table'});

	unless ($self->do_query("ALTER TABLE %s DROP COLUMN `%s`",$params{'table'},$params{'field'})) {
		Sympa::Log::Syslog::do_log('err', 'Could not delete field %s from table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf('Field %s removed from table %s', $params{'field'}, $params{'table'});
	Sympa::Log::Syslog::do_log('info', 'Field %s removed from table %s', $params{'field'}, $params{'table'});

	return $report;
}

sub get_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Getting primary key for table %s',$params{'table'});

	my $query = "SHOW COLUMNS FROM $params{table}";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get field list from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my @fields;
	while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
		push @fields, $row->{field} if $row->{key} eq 'PRI';
	}

	return \@fields;
}

sub _unset_primary_key {
	my ($self, %params) = @_;

	my $query = "ALTER TABLE $params{table} DROP PRIMARY KEY";
	return $self->{dbh}->do($query);
}

sub _set_primary_key {
	my ($self, %params) = @_;

	my $query =
		"ALTER TABLE $params{table} ADD PRIMARY KEY ($params{fields})";
	return $self->{dbh}->do($query);
}

sub get_indexes {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Looking for indexes in %s',$params{'table'});

	my %found_indexes;
	my $sth = $self->do_query(
		"SHOW INDEX FROM %s",
		$params{'table'}
	);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the list of indexes from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $index_part;
	while($index_part = $sth->fetchrow_hashref('NAME_lc')) {
		if ( $index_part->{'key_name'} ne "PRIMARY" ) {
			my $index_name = $index_part->{'key_name'};
			my $field_name = $index_part->{'column_name'};
			$found_indexes{$index_name}{$field_name} = 1;
		}
	}
return \%found_indexes;
}

sub _unset_index {
	my ($self, %params) = @_;

	my $query = "ALTER TABLE $params{table} DROP INDEX $params{index}";
	return $self->{dbh}->do($query);
}

sub _set_index {
	my ($self, %params) = @_;

	my $query = 
		"ALTER TABLE $params{table} "    .
		"ADD INDEX $params{index} ($params{fields})";
	return $self->{dbh}->do($query);
}

1;
