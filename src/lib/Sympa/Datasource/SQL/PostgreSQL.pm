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

use Sympa::Log;

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
		Sympa::Log::do_log('err',"Unknown date format mode %s", $params{'mode'});
		return undef;
	}
}

sub is_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Checking whether field %s.%s is an autoincrement',$params{'table'},$params{'field'});
	my $seqname = $params{'table'}.'_'.$params{'field'}.'_seq';
	my $sth;
	unless ($sth = $self->do_query("SELECT relname FROM pg_class WHERE relname = '%s' AND relkind = 'S'  AND relnamespace IN ( SELECT oid  FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema' )",$seqname)) {
		Sympa::Log::do_log('err','Unable to gather autoincrement field named %s for table %s',$params{'field'},$params{'table'});
		return undef;
	}
	my $field = $sth->fetchrow();
	return ($field eq $seqname);
}

sub set_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Setting field %s.%s as an auto increment',$params{'table'},$params{'field'});
	my $seqname = $params{'table'}.'_'.$params{'field'}.'_seq';
	unless ($self->do_query("CREATE SEQUENCE %s",$seqname)) {
		Sympa::Log::do_log('err','Unable to create sequence %s',$seqname);
		return undef;
	}
	unless ($self->do_query("ALTER TABLE %s ALTER COLUMN %s TYPE BIGINT",$params{'table'},$params{'field'})) {
		Sympa::Log::do_log('err','Unable to set type of field %s in table %s as bigint',$params{'field'},$params{'table'});
		return undef;
	}
	unless ($self->do_query("ALTER TABLE %s ALTER COLUMN %s SET DEFAULT NEXTVAL('%s')",$params{'table'},$params{'field'},$seqname)) {
		Sympa::Log::do_log('err','Unable to set default value of field %s in table %s as next value of sequence table %',$params{'field'},$params{'table'},$seqname);
		return undef;
	}
	unless ($self->do_query("UPDATE %s SET %s = NEXTVAL('%s')",$params{'table'},$params{'field'},$seqname)) {
		Sympa::Log::do_log('err','Unable to set sequence %s as value for field %s, table %s',$seqname,$params{'field'},$params{'table'});
		return undef;
	}
	return 1;
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::do_log('debug','Getting the list of tables in database %s',$self->{'db_name'});
	my @raw_tables;
	unless (@raw_tables = $self->{'dbh'}->tables(undef,'public',undef,'TABLE',{pg_noprefix => 1} )) {
		Sympa::Log::do_log('err','Unable to retrieve the list of tables from database %s',$self->{'db_name'});
		return undef;
	}
	return \@raw_tables;
}

sub add_table {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Adding table %s',$params{'table'});
	unless ($self->do_query("CREATE TABLE %s (temporary INT)",$params{'table'})) {
		Sympa::Log::do_log('err', 'Could not create table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	return sprintf "Table %s created in database %s", $params{'table'}, $self->{'db_name'};
}

sub get_fields {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Getting the list of fields in table %s, database %s',$params{'table'}, $self->{'db_name'});
	my $sth;
	my %result;
	unless ($sth = $self->do_query("SELECT a.attname AS field, t.typname AS type, a.atttypmod AS length FROM pg_class c, pg_attribute a, pg_type t WHERE a.attnum > 0 and a.attrelid = c.oid and c.relname = '%s' and a.atttypid = t.oid order by a.attnum",$params{'table'})) {
		Sympa::Log::do_log('err', 'Could not get the list of fields from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
		my $length = $ref->{'length'} - 4; # What a dirty method ! We give a Sympa tee shirt to anyone that suggest a clean solution ;-)
		if ( $ref->{'type'} eq 'varchar') {
			$result{$ref->{'field'}} = $ref->{'type'}.'('.$length.')';
		}else{
			$result{$ref->{'field'}} = $ref->{'type'};
		}
	}
	return \%result;
}

sub update_field {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Updating field %s in table %s (%s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'});
	my $options;
	if ($params{'notnull'}) {
		$options .= ' NOT NULL ';
	}
	my $report = sprintf("ALTER TABLE %s ALTER COLUMN %s TYPE %s %s",$params{'table'},$params{'field'},$params{'type'},$options);
	Sympa::Log::do_log('notice', "ALTER TABLE %s ALTER COLUMN %s TYPE %s %s",$params{'table'},$params{'field'},$params{'type'},$options);
	unless ($self->do_query("ALTER TABLE %s ALTER COLUMN %s TYPE %s %s",$params{'table'},$params{'field'},$params{'type'},$options)) {
		Sympa::Log::do_log('err', 'Could not change field \'%s\' in table\'%s\'.',$params{'field'}, $params{'table'});
		return undef;
	}
	$report .= sprintf('\nField %s in table %s, structure updated', $params{'field'}, $params{'table'});
	Sympa::Log::do_log('info', 'Field %s in table %s, structure updated', $params{'field'}, $params{'table'});
	return $report;
}

sub add_field {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Adding field %s in table %s (%s, %s, %s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'},$params{'autoinc'},$params{'primary'});
	my $options;
	# To prevent "Cannot add a NOT NULL column with default value NULL" errors
	if ($params{'notnull'}) {
		$options .= 'NOT NULL ';
	}
	if ( $params{'primary'}) {
		$options .= ' PRIMARY KEY ';
	}
	unless ($self->do_query("ALTER TABLE %s ADD %s %s %s",$params{'table'},$params{'field'},$params{'type'},$options)) {
		Sympa::Log::do_log('err', 'Could not add field %s to table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf('Field %s added to table %s (options : %s)', $params{'field'}, $params{'table'}, $options);
	Sympa::Log::do_log('info', 'Field %s added to table %s  (options : %s)', $params{'field'}, $params{'table'}, $options);

	return $report;
}

sub delete_field {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Deleting field %s from table %s',$params{'field'},$params{'table'});

	unless ($self->do_query("ALTER TABLE %s DROP COLUMN %s",$params{'table'},$params{'field'})) {
		Sympa::Log::do_log('err', 'Could not delete field %s from table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf('Field %s removed from table %s', $params{'field'}, $params{'table'});
	Sympa::Log::do_log('info', 'Field %s removed from table %s', $params{'field'}, $params{'table'});

	return $report;
}

sub get_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Getting primary key for table %s',$params{'table'});
	my %found_keys;
	my $sth;
	unless ($sth = $self->do_query("SELECT pg_attribute.attname AS field FROM pg_index, pg_class, pg_attribute WHERE pg_class.oid ='%s'::regclass AND indrelid = pg_class.oid AND pg_attribute.attrelid = pg_class.oid AND pg_attribute.attnum = any(pg_index.indkey) AND indisprimary",$params{'table'})) {
		Sympa::Log::do_log('err', 'Could not get the primary key from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}

	while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
		$found_keys{$ref->{'field'}} = 1;
	}
	return \%found_keys;
}

sub unset_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Removing primary key from table %s',$params{'table'});

	my $sth;
	unless ($sth = $self->do_query("ALTER TABLE %s DROP PRIMARY KEY",$params{'table'})) {
		Sympa::Log::do_log('err', 'Could not drop primary key from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params{'table'}, PRIMARY KEY dropped";
	Sympa::Log::do_log('info', 'Table %s, PRIMARY KEY dropped', $params{'table'});

	return $report;
}

sub set_primary_key {
	my ($self, %params) = @_;

	my $sth;
	my $fields = join ',',@{$params{'fields'}};
	Sympa::Log::do_log('debug','Setting primary key for table %s (%s)',$params{'table'},$fields);
	unless ($sth = $self->do_query("ALTER TABLE %s ADD PRIMARY KEY (%s)",$params{'table'}, $fields)) {
		Sympa::Log::do_log('err', 'Could not set fields %s as primary key for table %s in database %s', $fields, $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params{'table'}, PRIMARY KEY set on $fields";
	Sympa::Log::do_log('info', 'Table %s, PRIMARY KEY set on %s', $params{'table'},$fields);
	return $report;
}

sub get_indexes {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Getting the indexes defined on table %s',$params{'table'});
	my %found_indexes;
	my $sth;
	unless ($sth = $self->do_query("SELECT c.oid FROM pg_catalog.pg_class c LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.relname ~ \'^(%s)$\' AND pg_catalog.pg_table_is_visible(c.oid)",$params{'table'})) {
		Sympa::Log::do_log('err', 'Could not get the oid for table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $ref = $sth->fetchrow_hashref('NAME_lc');

	unless ($sth = $self->do_query("SELECT c2.relname, pg_catalog.pg_get_indexdef(i.indexrelid, 0, true) AS description FROM pg_catalog.pg_class c, pg_catalog.pg_class c2, pg_catalog.pg_index i WHERE c.oid = \'%s\' AND c.oid = i.indrelid AND i.indexrelid = c2.oid AND NOT i.indisprimary ORDER BY i.indisprimary DESC, i.indisunique DESC, c2.relname",$ref->{'oid'})) {
		Sympa::Log::do_log('err', 'Could not get the list of indexes from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}

	while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
		$ref->{'description'} =~ s/CREATE INDEX .* ON .* USING .* \((.*)\)$/\1/i;
		$ref->{'description'} =~ s/\s//i;
		my @index_members = split ',',$ref->{'description'};
		foreach my $member (@index_members) {
			$found_indexes{$ref->{'relname'}}{$member} = 1;
		}
	}
return \%found_indexes;
}

sub unset_index {
	my ($self, %params) = @_;

	Sympa::Log::do_log('debug','Removing index %s from table %s',$params{'index'},$params{'table'});

	my $sth;
	unless ($sth = $self->do_query("DROP INDEX %s",$params{'index'})) {
		Sympa::Log::do_log('err', 'Could not drop index %s from table %s in database %s',$params{'index'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params{'table'}, index $params{'index'} dropped";
	Sympa::Log::do_log('info', 'Table %s, index %s dropped', $params{'table'},$params{'index'});

	return $report;
}

sub set_index {
	my ($self, %params) = @_;

	my $sth;
	my $fields = join ',',@{$params{'fields'}};
	Sympa::Log::do_log('debug', 'Setting index %s for table %s using fields %s', $params{'index_name'},$params{'table'}, $fields);
	unless ($sth = $self->do_query("CREATE INDEX %s ON %s (%s)", $params{'index_name'},$params{'table'}, $fields)) {
		Sympa::Log::do_log('err', 'Could not add index %s using field %s for table %s in database %s', $fields, $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params{'table'}, index %s set using $fields";
	Sympa::Log::do_log('info', 'Table %s, index %s set using fields %s',$params{'table'}, $params{'index_name'}, $fields);
	return $report;
}

1;
