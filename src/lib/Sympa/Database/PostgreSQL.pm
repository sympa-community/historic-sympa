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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 NAME

Sympa::Database::PostgreSQL - PostgreSQL Sympa database object

=head1 DESCRIPTION

This class implements a PostgreSQL Sympa database.

=cut

package Sympa::Database::PostgreSQL;

use strict;
use base qw(Sympa::Database);

use Carp;

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

sub get_substring_clause {
	my ($self, %params) = @_;

	return sprintf
		"SUBSTRING(%s FROM position('%s' IN %s) FOR %s)",
		$params{source_field},
		$params{separator},
		$params{source_field},
		$params{substring_length};
}

sub get_limit_clause {
	my ($self, %params) = @_;

	if ($params{offset}) {
		return sprintf "LIMIT %s OFFSET %s",
			$params{rows_count},
			$params{offset};
	} else {
		return sprintf "LIMIT %s",
			$params{rows_count};
	}
}

sub get_formatted_date {
	my ($self, %params) = @_;

	my $mode = lc($params{mode});
	if ($mode eq 'read') {
		return sprintf 'date_part(\'epoch\',%s)',$params{target};
	} elsif ($mode eq 'write') {
		return sprintf '\'epoch\'::timestamp with time zone + \'%d sec\'',$params{target};
	} else {
		Sympa::Log::Syslog::do_log(
			'err',
			"Unknown date format mode %s",
			$params{mode}
		);
		return undef;
	}
}

sub is_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Checking whether field %s.%s is an autoincrement',
		$params{table},
		$params{field}
	);

	my $sequence = _get_sequence_name(
		table => $params{table},
		field => $params{field}
	);

	my $query =
		"SELECT relname "                                         .
		"FROM pg_class "                                          .
		"WHERE "                                                  .
			"relname = ? AND "                                .
			"relkind = 'S'  AND "                             .
			"relnamespace IN ("                               .
				"SELECT oid "                             .
				"FROM pg_namespace "                      .
				"WHERE "                                  .
					"nspname NOT LIKE ? AND         " .
					"nspname != 'information_schema'" .
			")";
	my $row = $self->{dbh}->selectrow_hashref(
		$query,
		undef,
		$sequence,
		'pg_' . $sequence
	);

	return $row && $row->{relname} eq $sequence;
}

sub set_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Setting field %s.%s as an auto increment',
		$params{table},
		$params{field}
	);

	my ($query, $rows);
	my $sequence = _get_sequence_name(
		table => $params{table},
		field => $params{field}
	);

	$self->_create_sequence($sequence);

	$query =
		"ALTER TABLE $params{table} " .
		"ALTER COLUMN $params{field} " .
		"TYPE BIGINT";
	$rows = $self->{dbh}->do($query);
	croak sprintf(
		'Unable to set type of field %s in table %s as bigint: %s',
		$params{field},
		$params{table},
		$self->{dbh}->errstr()
	) unless $rows;

	$query =
		"ALTER TABLE $params{table} "  .
		"ALTER COLUMN $params{field} " .
		"SET DEFAULT NEXTVAL($sequence)";
	$rows = $self->{dbh}->do($query);
	croak sprintf(
		'Unable to set default value of field %s in table %s as next ' .
		'value of sequence %s: %s',
		$params{field},
		$params{table},
		$sequence,
		$self->{dbh}->errstr()
	) unless $rows;

	$query =
		"UPDATE $params{table} " .
		"SET $params{field} = NEXTVAL($sequence)";
	$rows = $self->{dbh}->do($query);
	croak sprintf(
		'Unable to set sequence %s as value for field %s, table %s: %s',
		$sequence,
		$params{field},
		$params{table},
		$self->{dbh}->errstr()
	) unless $rows;

	return 1;
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting tables list in database %s',$self->{'db_name'}
	);

	# get schemas list
	my $query = 'SELECT current_schemas(false)';
	my $row = $self->{dbh}->selectrow_hashref($query);
	my $schemas = $row->{current_schemas};

	# get table names
	my @raw_tables;
	my %raw_tables;
	foreach my $schema (@{$schemas || []}) {
		my @tables = $self->{dbh}->tables(
			undef, $schema, undef, 'TABLE', {pg_noprefix => 1}
		);
		foreach my $table (@tables) {
			next if $raw_tables{$table};
			push @raw_tables, $table;
			$raw_tables{$table} = 1;
		}
	}

	return @raw_tables;
}

sub add_table {
	my ($self, %params) = @_;

	foreach my $field (@{$params{fields}}) {
		next unless $field->{autoincrement};
		$self->_create_sequence(
			_get_sequence_name(
				table => $params{table},
				field => $field->{name}
			)
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
	return 'float8'       if $type =~ /^double/;
	return 'varchar(500)' if $type =~ /^text/;
	return 'text'         if $type =~ /^longtext/;
	return 'timestamptz'  if $type =~ /^datetime/;
	return 'varchar(15)'  if $type =~ /^enum/;
	return 'bytea'        if $type =~ /^mediumblob/;
	return $type;
}

sub get_fields {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting fields list from table %s',
		$params{table},
	);

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
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get fields list from table %s',
			$params{table},
		);
		return undef;
	}
	$handle->execute($params{table});

	my %result;
	while (my $row = $handle->fetchrow_hashref('NAME_lc')) {
		my $length = $row->{length} - 4; # What a dirty method ! We give a Sympa tee shirt to anyone that suggest a clean solution ;-)
		if ($row->{type} eq 'varchar') {
			$result{$row->{field}} = $row->{type} . "($length)";
		} else {
			$result{$row->{field}} = $row->{type};
		}
	}
	return \%result;
}

# override needed for specific null constraint handling
sub update_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Updating field %s in table %s (%s, %s)',
		$params{field},
		$params{table},
		$params{type},
		$params{notnull}
	);

	my $query =
		"ALTER TABLE $params{table} " .
		"ALTER COLUMN $params{field} TYPE $params{type}";

	my $rows = $self->{dbh}->do($query);
	croak sprintf(
		'Could not change field %s in table %s: %s',
		$params{field},
		$params{table},
		$self->{dbh}->errstr()
	) unless $rows;

	my $report = sprintf(
		'Field %s updated in table %s',
		$params{field},
		$params{table}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

# override needed for specific autoincrement support
sub add_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Adding field %s in table %s (%s, %s, %s, %s)',
		$params{field},
		$params{table},
		$params{type},
		$params{notnull},
		$params{autoinc},
		$params{primary}
	);

	my $query =
		"ALTER TABLE $params{table} "     .
		"ADD $params{field} $params{type}";
	$query .= ' NOT NULL'       if $params{notnull};
	$query .= ' PRIMARY KEY'    if $params{primary};

	my $rows = $self->{dbh}->do($query);
	croak sprintf(
		'Unable to add field %s in table %s: %s',
		$params{field},
		$params{table},
		$self->{dbh}->errstr()
	) unless $rows;

	if ($params{autoinc}) {
		$self->set_autoinc(
			table => $params{table},
			field => $params{field},
		);
	}

	my $report = sprintf(
		'Field %s added to table %s',
		$params{field},
		$params{table},
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub get_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting primary key from table %s',
		$params{table}
	);

	my $query =
		"SELECT pg_attribute.attname AS field "                   .
		"FROM pg_index, pg_class, pg_attribute "                  .
		"WHERE "                                                  .
			"pg_class.oid = ?::regclass AND "                 .
			"indrelid = pg_class.oid AND "                    .
			"pg_attribute.attrelid = pg_class.oid AND "       .
			"pg_attribute.attnum = any(pg_index.indkey) AND " .
			"indisprimary";
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get primary key from table %s',
			$params{table},
		);
		return undef;
	}
	$handle->execute($params{table});

	my @keys;
	while (my $row = $handle->fetchrow_hashref('NAME_lc')) {
		push @keys, $row->{field};
	}
	return \@keys;
}

# overriden to use CONSTRAINT syntax, as PostgreSQL doesn't support DROP
# PRIMARY KEY syntax
sub unset_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Removing primary key from table %s',
		$params{table}
	);

	my $query =
		"SELECT tc.constraint_name "                       .
		"FROM information_schema.table_constraints AS tc " .
		"WHERE "                                           .
			"tc.table_catalog = ? AND "                .
			"tc.table_name = ? AND "                   .
			"tc.constraint_type = 'PRIMARY KEY'";
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not search primary key from table %s',
			$params{table}
		);
		return undef;
	}
	$handle->execute($self->{db_name}, $params{table});
	my $key_name = $handle->fetchrow_array();
	unless ($key_name) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get primary key from table %s',
			$params{table}
		);
		return undef;
	}

	my $query = "ALTER TABLE $params{table} DROP CONSTRAINT '$key_name'";
	my $rows = $self->{dbh}->do($query);
	croak sprintf(
		'Unable to remove primary key from table %s: %s',
		$params{table},
		$self->{dbh}->errstr()
	) unless $rows;

	my $report = sprintf(
		"Primary key removed from table %s",
		$params{table}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

# overriden to use CONSTRAINT syntax
sub set_primary_key {
	my ($self, %params) = @_;

	my $fields = join(',', @{$params{fields}});
	Sympa::Log::Syslog::do_log(
		'debug',
		'Setting primary key on table %s using fields %s',
		$params{table},
		$fields
	);

	## Give fixed key name if possible.
	my $key_name;
	if ($params{table} =~ /^(.+)_table$/) {
		$key_name = sprintf 'CONSTRAINT "ind_%s" PRIMARY KEY', $1;
	} else {
		$key_name = 'PRIMARY KEY';
	}

	my $query =
		"ALTER TABLE $params{table} ADD $key_name ($fields)";
	my $rows = $self->{dbh}->do($query);
	croak sprintf(
		'Unable to set primary key on table %s using fields %s: %s',
		$params{table},
		$fields,
		$self->{dbh}->errstr()
	) unless $rows;

	my $report = sprintf(
		"Primary key set on table %s using fields %s",
		$params{table},
		$fields
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub get_indexes {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting indexes list from table %s',
		$params{table}
	);

	my $oid_query =
		"SELECT c.oid "                                 .
		"FROM pg_catalog.pg_class c "                   .
		"LEFT JOIN pg_catalog.pg_namespace n "          .
			"ON n.oid = c.relnamespace "            .
		"WHERE "                                        .
			"c.relname ~ \'^$params{table}$\' AND " .
			"pg_catalog.pg_table_is_visible(c.oid)";
	my $row = $self->{dbh}->selectrow_hashref($oid_query);
	croak sprintf(
		'Unable to get oid from table %s: %s',
		$params{table},
		$self->{dbh}->errstr()
	) unless $row;

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

	my $handle = $self->{dbh}->prepare($index_query);
	croak sprintf(
		'Unable to get indexes list from table %s: %s',
		$params{table},
		$self->{dbh}->errstr()
	) unless $handle;
	$handle->execute();

	my %indexes;
	while (my $row = $handle->fetchrow_hashref('NAME_lc')) {
		$row->{description} =~ s/CREATE INDEX .* ON .* USING .* \((.*)\)$/\1/i;
		$row->{description} =~ s/\s//i;
		my @members = split(',', $row->{description});
		foreach my $member (@members) {
			$indexes{$row->{relname}}{$member} = 1;
		}
	}

	return \%indexes;
}

sub _get_unset_index_query {
	my ($self, %params) = @_;

	return "DROP INDEX $params{index}";
}

sub _get_set_index_query {
	my ($self, %params) = @_;

	return
		"CREATE INDEX $params{index} " .
		"ON $params{table} ($params{fields})";
}

sub _get_sequence_name {
	my (%params) = @_;
	return $params{table} . '_' . $params{field} . '_seq';
}

sub _create_sequence {
	my ($self, $sequence) = @_;

	my $query = "CREATE SEQUENCE $sequence";
	my $rows = $self->{dbh}->do($query);
	# check if the sequence already exist
	my $select_query =
		"SELECT relname "                    .
		"FROM pg_class "                     .
		"WHERE relname = ? AND relkind = 'S'";
	my $select_rows = $self->{dbh}->do($select_query, undef, $sequence);
	return if $select_rows;

	my $create_query = "CREATE SEQUENCE $sequence";
	my $create_rows = $self->{dbh}->do($create_query);
	croak sprintf(
		'Unable to create sequence %s: %s',
		$sequence,
		$self->{dbh}->errstr()
	) unless $create_rows;
}

## For DOUBLE types.
sub AS_DOUBLE {
    return ( { 'pg_type' => DBD::Pg::PG_FLOAT8() } => $_[1] )
	if scalar @_ > 1;
    return ();
}

## For BLOB types.
sub AS_BLOB {
    return ( { 'pg_type' => DBD::Pg::PG_BYTEA() } => $_[1] )
	if scalar @_ > 1;
    return ();
}

1;
