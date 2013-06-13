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

use Sympa::Log::Syslog;

our %date_format = (
	'read' => {
		'Pg' => 'date_part(\'epoch\',%s)',
	},
	'write' => {
		'Pg' => '\'epoch\'::timestamp with time zone + \'%d sec\'',
	}
);

sub new {
	my ($class, %params) = @_;

	return $class->SUPER::new(%params, db_type => 'pg');
}


sub build_connect_string{
	my ($self) = @_;

	$self->{'connect_string'} =
		"DBI:Pg:dbname=$self->{'db_name'};host=$self->{'db_host'}";
}

sub get_substring_clause {
	my ($self, %params) = @_;

	return sprintf
		"SUBSTRING(%s FROM position('%s' IN %s) FOR %s)",
		$params{'source_field'},
		$params{'separator'},
		$params{'source_field'},
		$params{'substring_length'};
}

sub get_limit_clause {
	my ($self, %params) = @_;

	if ($params{'offset'}) {
		return sprintf "LIMIT %s OFFSET %s",
			$params{'rows_count'},
			$params{'offset'};
	} else {
		return sprintf "LIMIT %s",
			$params{'rows_count'};
	}
}

sub get_formatted_date {
	my ($self, %params) = @_;

	my $mode = lc($params{'mode'});
	if ($mode eq 'read') {
		return sprintf 'date_part(\'epoch\',%s)',$params{'target'};
	} elsif ($mode eq 'write') {
		return sprintf '\'epoch\'::timestamp with time zone + \'%d sec\'',$params{'target'};
	} else {
		Sympa::Log::Syslog::do_log('err',"Unknown date format mode %s", $params{'mode'});
		return undef;
	}
}

sub is_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Checking whether field %s.%s is an autoincrement',$params{'table'},$params{'field'});

	my $sequence = _get_sequence_name(
		table => $params{table},
		field => $params{field}
	);

	my $query =
		"SELECT relname "                                         .
		"FROM pg_class "                                          .
		"WHERE "                                                  .
			"relname = '$sequence' AND "                      .
			"relkind = 'S'  AND "                             .
			"relnamespace IN ("                               .
				"SELECT oid "                             .
				"FROM pg_namespace "                      .
				"WHERE "                                  .
					"nspname NOT LIKE 'pg_$sequence' AND " .
					"nspname != 'information_schema'" .
			")";
	my $row = $self->{dbh}->selectrow_hashref($query);
	unless ($row) {
		Sympa::Log::Syslog::do_log('err','Unable to gather autoincrement field named %s for table %s',$params{'field'},$params{'table'});
		return undef;
	}

	return $row->{relname} eq $sequence;
}

sub set_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Setting field %s.%s as an auto increment',$params{'table'},$params{'field'});

	my ($query, $rows);
	my $sequence = _get_sequence_name(
		table => $params{table},
		field => $params{field}
	);

	$query = "CREATE SEQUENCE $sequence";
	$rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to create sequence %s',$sequence);
		return undef;
	}

	$query =
		"ALTER TABLE $params{table} " .
		"ALTER COLUMN $params{field} " .
		"TYPE BIGINT";
	$rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to set type of field %s in table %s as bigint',$params{'field'},$params{'table'});
		return undef;
	}

	$query =
		"ALTER TABLE $params{table} "  .
		"ALTER COLUMN $params{field} " .
		"SET DEFAULT NEXTVAL($sequence)";
	$rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to set default value of field %s in table %s as next value of sequence table %',$params{'field'},$params{'table'},$sequence);
		return undef;
	}

	$query = 
		"UPDATE $params{table} " .
		"SET $params{field} = NEXTVAL($sequence)";
	$rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to set sequence %s as value for field %s, table %s',$sequence,$params{'field'},$params{'table'});
		return undef;
	}
	return 1;
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug','Getting the list of tables in database %s',$self->{'db_name'});

	my @tables = $self->{dbh}->tables(
		undef,'public',undef,'TABLE',{pg_noprefix => 1}
	);

	return @tables;
}

sub add_table {
	my ($self, %params) = @_;

	foreach my $field (@{$params{field}}) {
		next unless $field->{autoincrement};
		$self->_create_sequence(
			table => $params{table},
			field => $field
		);
	}

	return $self->SUPER::add_table(%params);
}

sub _get_field_clause {
	my ($self, %params) = @_;

	my $clause = "$params{name} $params{type}";
	$clause .= ' NOT NULL' if $params{notnull};

	if ($params{autoincrement}) {
		my $sequence = _get_sequence_name(
			table => $params{table},
			field => $params{name}
		);
		$clause .= " DEFAULT NEXTVAL('$sequence')";
	}

	return $clause;
}

sub _get_native_type {
	my ($self, $type) = @_;

	return 'smallint'     if $type =~ /^int(1)/;
	return 'int4'         if $type =~ /^int/;
	return 'int4'         if $type =~ /^smallint/;
	return 'int2'         if $type =~ /^tinyint/;
	return 'int8'         if $type =~ /^bigint/;
	return 'varchar(500)' if $type =~ /^text/;
	return 'text'         if $type =~ /^longtext/;
	return 'timestamptz'  if $type =~ /^datetime/;
	return 'varchar(15)'  if $type =~ /^enum/;
	return $type;
}

sub get_fields {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Getting the list of fields in table %s, database %s',$params{'table'}, $self->{'db_name'});

	my $query = 
		"SELECT " .
			"a.attname AS field, " .
			"t.typname AS type, " .
			"a.atttypmod AS length " .
		"FROM pg_class c, pg_attribute a, pg_type t " .
		"WHERE ".
			"a.attnum > 0 AND ".
			"a.attrelid = c.oid AND ".
			"c.relname = ? AND " .
			"a.atttypid = t.oid ". 
		"ORDER BY a.attnum";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the list of fields from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	$sth->execute($params{table});

	my %result;
	while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
		my $length = $row->{length} - 4; # What a dirty method ! We give a Sympa tee shirt to anyone that suggest a clean solution ;-)
		if ($row->{type} eq 'varchar') {
			$result{$row->{field}} = $row->{type} . "($length)";
		} else {
			$result{$row->{field}} = $row->{type};
		}
	}
	return \%result;
}

sub update_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Updating field %s in table %s (%s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'});

	my $query =
		"ALTER TABLE $params{table} " .
		"ALTER COLUMN $params{field} TYPE $params{type}";
	$query .= ' NOT NULL' if $params{notnull};

	my $rows = $self->{do}->($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Could not change field \'%s\' in table\'%s\'.',$params{'field'}, $params{'table'});
		return undef;
	}

	my $report = sprintf(
		'Field %s updated in table %s',
		$params{'field'},
		$params{'table'}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub add_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Adding field %s in table %s (%s, %s, %s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'},$params{'autoinc'},$params{'primary'});

	my $query =
		"ALTER TABLE $params{table} "     .
		"ADD $params{field} $params{type}";
	$query .= ' NOT NULL'       if $params{notnull};
	$query .= ' PRIMARY KEY'    if $params{primary};

	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Could not add field %s to table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}

	if ($params{autoinc}) {
		$self->set_autoinc(
			table => $params{table},
			field => $params{field},
		);
	}

	my $report = sprintf(
		'Field %s added to table %s',
		$params{'field'},
		$params{'table'},
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub delete_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Deleting field %s from table %s',$params{'field'},$params{'table'});

	my $query = "ALTER TABLE $params{table} DROP COLUMN $params{field}";
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Could not delete field %s from table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf(
		'Field %s removed from table %s',
		$params{'field'},
		$params{'table'}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub get_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Getting primary key for table %s',$params{'table'});

	my $query = 
		"SELECT pg_attribute.attname AS field "                   .
		"FROM pg_index, pg_class, pg_attribute "                  .
		"WHERE "                                                  .
			"pg_class.oid = '$params{table}'::regclass AND "  .
			"indrelid = pg_class.oid AND "                    .
			"pg_attribute.attrelid = pg_class.oid AND "       .
			"pg_attribute.attnum = any(pg_index.indkey) AND " .
			"indisprimary";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the primary key from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	$sth->execute();

	my @keys;
	while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
		push @keys, $row->{field};
	}
	return \@keys;
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

	Sympa::Log::Syslog::do_log('debug','Getting the indexes defined on table %s',$params{'table'});

	my $oid_query = 
		"SELECT c.oid "                                 .
		"FROM pg_catalog.pg_class c "                   .
		"LEFT JOIN pg_catalog.pg_namespace n "          .
			"ON n.oid = c.relnamespace "            .
		"WHERE "                                        .
			"c.relname ~ \'^$params{table}$\' AND " .
			"pg_catalog.pg_table_is_visible(c.oid)" ;
	my $row = $self->{dbh}->selectrow_hashref($oid_query);
	unless ($row) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the oid for table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my $index_query = 
		"SELECT "                                                     .
			"c2.relname, "                                        .
			"pg_catalog.pg_get_indexdef(i.indexrelid, 0, true) "  .
				"AS description "                             .
		"FROM "                                                       .
			"pg_catalog.pg_class c, "                             .
			"pg_catalog.pg_class c2, "                            .
			"pg_catalog.pg_index i "                              .
		"WHERE "                                                      .
			"c.oid = $row->{oid} AND "                            .
			"c.oid = i.indrelid AND "                             .
			"i.indexrelid = c2.oid AND "                          .
			"NOT i.indisprimary "                                 .
		"ORDER BY i.indisprimary DESC, i.indisunique DESC, c2.relname";

	my $sth = $self->{dbh}->prepare($index_query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the list of indexes from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	$sth->execute();

	my %indexes;
	while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
		$row->{description} =~ s/CREATE INDEX .* ON .* USING .* \((.*)\)$/\1/i;
		$row->{description} =~ s/\s//i;
		my @members = split(',', $row->{description});
		foreach my $member (@members) {
			$indexes{$row->{relname}}{$member} = 1;
		}
	}

	return \%indexes;
}

sub _unset_index {
	my ($self, %params) = @_;

	my $query = "DROP INDEX $params{index}";
	return $self->{dbh}->do($query);
}

sub _set_index {
	my ($self, %params) = @_;

	my $query = 
		"CREATE INDEX $params{index} " .
		"ON $params{table} ($params{fields})";
	return $self->{dbh}->do($query);
}

sub _get_sequence_name {
	my (%params) = @_;
	return $params{table} . '_' . $params{field} . '_seq';
}

sub _create_sequence {
	my ($self, $sequence) = @_;

	my $query = "CREATE SEQUENCE $sequence";
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to create sequence %s',$sequence);
		return undef;
	}
}

1;
