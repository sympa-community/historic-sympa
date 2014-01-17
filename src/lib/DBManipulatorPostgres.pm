# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4:textwidth=78
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997-2011 Comite Reseau des Universites
# Copyright (c) 2011-2014 GIP RENATER
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

package DBManipulatorPostgres;

use strict;

#use Carp; # not used
# tentative
use Data::Dumper;

use Log;
use DBManipulatorDefault;

our @ISA = qw(DBManipulatorDefault);

#######################################################
####### Beginning the RDBMS-specific code. ############
#######################################################

our %date_format = (
    'read'  => {'Pg' => 'date_part(\'epoch\',%s)',},
    'write' => {'Pg' => '\'epoch\'::timestamp with time zone + \'%d sec\'',}
);

# Builds the string to be used by the DBI to connect to the database.
#
# IN: Nothing
#
# OUT: Nothing
sub build_connect_string {
    my $self = shift;
    Sympa::Log::Syslog::do_log('debug3', 'Building connect string');
    $self->{'connect_string'} =
        "DBI:Pg:dbname=$self->{'db_name'};host=$self->{'db_host'}";
}

## Returns an SQL clause to be inserted in a query.
## This clause will compute a substring of max length
## $param->{'substring_length'} starting from the first character equal
## to $param->{'separator'} found in the value of field $param->{'source_field'}.
sub get_substring_clause {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug2', 'Building a substring clause');
    return
          "SUBSTRING("
        . $param->{'source_field'}
        . " FROM position('"
        . $param->{'separator'} . "' IN "
        . $param->{'source_field'}
        . ") FOR "
        . $param->{'substring_length'} . ")";
}

## Returns an SQL clause to be inserted in a query.
## This clause will limit the number of records returned by the query to
## $param->{'rows_count'}. If $param->{'offset'} is provided, an offset of
## $param->{'offset'} rows is done from the first record before selecting
## the rows to return.
sub get_limit_clause {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3', 'Building limit clause');
    if ($param->{'offset'}) {
        return
              "LIMIT "
            . $param->{'rows_count'}
            . " OFFSET "
            . $param->{'offset'};
    } else {
        return "LIMIT " . $param->{'rows_count'};
    }
}

# Returns a character string corresponding to the expression to use in a query
# involving a date.
# IN: A ref to hash containing the following keys:
#	* 'mode'
# 	   authorized values:
#		- 'write': the sub returns the expression to use in 'INSERT' or 'UPDATE' queries
#		- 'read': the sub returns the expression to use in 'SELECT' queries
#	* 'target': the name of the field or the value to be used in the query
#
# OUT: the formatted date or undef if the date format mode is unknonw.
sub get_formatted_date {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3', 'Building SQL date formatting');
    if (lc($param->{'mode'}) eq 'read') {
        return sprintf 'date_part(\'epoch\',%s)', $param->{'target'};
    } elsif (lc($param->{'mode'}) eq 'write') {
        return sprintf '\'epoch\'::timestamp with time zone + \'%d sec\'',
            $param->{'target'};
    } else {
        Sympa::Log::Syslog::do_log('err', "Unknown date format mode %s",
            $param->{'mode'});
        return undef;
    }
}

# Checks whether a field is an autoincrement field or not.
# IN: A ref to hash containing the following keys:
# * 'field' : the name of the field to test
# * 'table' : the name of the table to add
#
# OUT: Returns true if the field is an autoincrement field, false otherwise
sub is_autoinc {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3',
        'Checking whether field %s.%s is an autoincrement',
        $param->{'table'}, $param->{'field'});
    my $seqname = $param->{'table'} . '_' . $param->{'field'} . '_seq';
    my $sth;
    unless (
        $sth = $self->do_query(
            "SELECT relname FROM pg_class WHERE relname = '%s' AND relkind = 'S'  AND relnamespace IN ( SELECT oid  FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema' )",
            $seqname
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Unable to gather autoincrement field named %s for table %s',
            $param->{'field'}, $param->{'table'});
        return undef;
    }
    my $field = $sth->fetchrow();
    return ($field eq $seqname);
}

# Defines the field as an autoincrement field
# IN: A ref to hash containing the following keys:
# * 'field' : the name of the field to set
# * 'table' : the name of the table to add
#
# OUT: 1 if the autoincrement could be set, undef otherwise.
sub set_autoinc {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3',
        'Setting field %s.%s as an auto increment',
        $param->{'table'}, $param->{'field'});
    my $seqname = $param->{'table'} . '_' . $param->{'field'} . '_seq';
    unless ($self->do_query("CREATE SEQUENCE %s", $seqname)) {
        Sympa::Log::Syslog::do_log('err', 'Unable to create sequence %s',
            $seqname);
        return undef;
    }
    unless (
        $self->do_query(
            "ALTER TABLE %s ALTER COLUMN %s TYPE BIGINT", $param->{'table'},
            $param->{'field'}
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Unable to set type of field %s in table %s as bigint',
            $param->{'field'}, $param->{'table'});
        return undef;
    }
    unless (
        $self->do_query(
            "ALTER TABLE %s ALTER COLUMN %s SET DEFAULT NEXTVAL('%s')",
            $param->{'table'}, $param->{'field'}, $seqname
        )
        ) {
        Sympa::Log::Syslog::do_log(
            'err',
            'Unable to set default value of field %s in table %s as next value of sequence table %',
            $param->{'field'},
            $param->{'table'},
            $seqname
        );
        return undef;
    }
    unless (
        $self->do_query(
            "UPDATE %s SET %s = NEXTVAL('%s')", $param->{'table'},
            $param->{'field'},                  $seqname
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Unable to set sequence %s as value for field %s, table %s',
            $seqname, $param->{'field'}, $param->{'table'});
        return undef;
    }
    return 1;
}

# Returns the list of the tables in the database.
# Returns undef if something goes wrong.
#
# OUT: a ref to an array containing the list of the tables names in the
# database, undef if something went wrong
#
# Note: Pg searches tables in schemas listed in search_path, defaults to be
#   '"$user",public'.
sub get_tables {
    my $self = shift;
    Sympa::Log::Syslog::do_log('debug3',
        'Getting the list of tables in database %s',
        $self->{'db_name'});

    ## get search_path.
    my $sth;
    unless ($sth = $self->do_query('SELECT current_schemas(false)')) {
        Sympa::Log::Syslog::do_log('err',
            'Unable to get search_path of database %s',
            $self->{'db_name'});
        return undef;
    }
    my $search_path = $sth->fetchrow;
    $sth->finish;

    ## get table names.
    my @raw_tables;
    my %raw_tables;
    foreach my $schema (@{$search_path || []}) {
        my @tables =
            $self->{'dbh'}
            ->tables(undef, $schema, undef, 'TABLE', {pg_noprefix => 1});
        foreach my $t (@tables) {
            next if $raw_tables{$t};
            push @raw_tables, $t;
            $raw_tables{$t} = 1;
        }
    }
    unless (@raw_tables) {
        Sympa::Log::Syslog::do_log('err',
            'Unable to retrieve the list of tables from database %s',
            $self->{'db_name'});
        return undef;
    }
    return \@raw_tables;
}

# Adds a table to the database
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table to add
#
# OUT: A character string report of the operation done or undef if something went wrong.
sub add_table {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3', 'Adding table %s',
        $param->{'table'});
    unless (
        $self->do_query("CREATE TABLE %s (temporary INT)", $param->{'table'}))
    {
        Sympa::Log::Syslog::do_log('err',
            'Could not create table %s in database %s',
            $param->{'table'}, $self->{'db_name'});
        return undef;
    }
    return sprintf "Table %s created in database %s", $param->{'table'},
        $self->{'db_name'};
}

# Returns a ref to an hash containing the description of the fields in a table from the database.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table whose fields are requested.
#
# OUT: A hash in which:
#	* the keys are the field names
#	* the values are the field type
#	Returns undef if something went wrong.
#
sub get_fields {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3',
        'Getting the list of fields in table %s, database %s',
        $param->{'table'}, $self->{'db_name'});
    my $sth;
    my %result;
    unless (
        $sth = $self->do_query(
            "SELECT a.attname AS field, t.typname AS type, a.atttypmod AS length FROM pg_class c, pg_attribute a, pg_type t WHERE a.attnum > 0 and a.attrelid = c.oid and c.relname = '%s' and a.atttypid = t.oid order by a.attnum",
            $param->{'table'}
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Could not get the list of fields from table %s in database %s',
            $param->{'table'}, $self->{'db_name'});
        return undef;
    }
    while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
        my $length =
            $ref->{'length'} - 4
            ; # What a dirty method ! We give a Sympa tee shirt to anyone that suggest a clean solution ;-)
        if ($ref->{'type'} eq 'varchar') {
            $result{$ref->{'field'}} = $ref->{'type'} . '(' . $length . ')';
        } else {
            $result{$ref->{'field'}} = $ref->{'type'};
        }
    }
    return \%result;
}

# Changes the type of a field in a table from the database.
# IN: A ref to hash containing the following keys:
# * 'field' : the name of the field to update
# * 'table' : the name of the table whose fields will be updated.
# * 'type' : the type of the field to add
# * 'notnull' : specifies that the field must not be null
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub update_field {
    my $self  = shift;
    my $param = shift;
    my $table = $param->{'table'};
    my $field = $param->{'field'};
    my $type  = $param->{'type'};
    Sympa::Log::Syslog::do_log('debug3',
        'Updating field %s in table %s (%s, %s)',
        $field, $table, $type, $param->{'notnull'});
    my $options = '';
    if ($param->{'notnull'}) {
        $options .= ' NOT NULL ';
    }
    my $report;
    my @sql;

    ## Conversion between timestamp and integer is not obvious.
    ## So create new column then copy contents.
    my $fields = $self->get_fields({'table' => $table});
    if ($fields->{$field} eq 'timestamptz' and $type =~ /^int/i) {
        @sql = (
            "ALTER TABLE list_table RENAME $field TO ${field}_tmp",
            "ALTER TABLE list_table ADD $field $type$options",
            "UPDATE list_table SET $field = date_part('epoch', ${field}_tmp)",
            "ALTER TABLE list_table DROP ${field}_tmp"
        );
    } else {
        @sql = sprintf("ALTER TABLE %s ALTER COLUMN %s TYPE %s %s",
            $table, $field, $type, $options);
    }
    foreach my $sql (@sql) {
        Sympa::Log::Syslog::do_log('notice', '%s', $sql);
        if ($report) {
            $report .= "\n$sql";
        } else {
            $report = $sql;
        }
        unless ($self->do_query('%s', $sql)) {
            Sympa::Log::Syslog::do_log('err',
                'Could not change field \'%s\' in table\'%s\'.',
                $param->{'field'}, $param->{'table'});
            return undef;
        }
    }
    $report .=
        sprintf("\nField %s in table %s, structure updated", $field, $table);
    Sympa::Log::Syslog::do_log('info',
        'Field %s in table %s, structure updated',
        $field, $table);
    return $report;
}

# Adds a field in a table from the database.
# IN: A ref to hash containing the following keys:
#	* 'field' : the name of the field to add
#	* 'table' : the name of the table where the field will be added.
#	* 'type' : the type of the field to add
#	* 'notnull' : specifies that the field must not be null
#	* 'autoinc' : specifies that the field must be autoincremental
#	* 'primary' : specifies that the field is a key
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub add_field {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log(
        'debug3',            'Adding field %s in table %s (%s, %s, %s, %s)',
        $param->{'field'},   $param->{'table'},
        $param->{'type'},    $param->{'notnull'},
        $param->{'autoinc'}, $param->{'primary'}
    );
    my $options;

    # To prevent "Cannot add a NOT NULL column with default value NULL" errors
    if ($param->{'notnull'}) {
        $options .= 'NOT NULL ';
    }
    if ($param->{'primary'}) {
        $options .= ' PRIMARY KEY ';
    }
    unless (
        $self->do_query(
            "ALTER TABLE %s ADD %s %s %s", $param->{'table'},
            $param->{'field'},             $param->{'type'},
            $options
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Could not add field %s to table %s in database %s',
            $param->{'field'}, $param->{'table'}, $self->{'db_name'});
        return undef;
    }

    my $report = sprintf('Field %s added to table %s (options : %s)',
        $param->{'field'}, $param->{'table'}, $options);
    Sympa::Log::Syslog::do_log('info',
        'Field %s added to table %s  (options : %s)',
        $param->{'field'}, $param->{'table'}, $options);

    return $report;
}

# Deletes a field from a table in the database.
# IN: A ref to hash containing the following keys:
#	* 'field' : the name of the field to delete
#	* 'table' : the name of the table where the field will be deleted.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub delete_field {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3', 'Deleting field %s from table %s',
        $param->{'field'}, $param->{'table'});

    unless (
        $self->do_query(
            "ALTER TABLE %s DROP COLUMN %s", $param->{'table'},
            $param->{'field'}
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Could not delete field %s from table %s in database %s',
            $param->{'field'}, $param->{'table'}, $self->{'db_name'});
        return undef;
    }

    my $report = sprintf('Field %s removed from table %s',
        $param->{'field'}, $param->{'table'});
    Sympa::Log::Syslog::do_log('info', 'Field %s removed from table %s',
        $param->{'field'}, $param->{'table'});

    return $report;
}

# Returns the list fields being part of a table's primary key.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the primary keys are requested.
#
# OUT: A ref to a hash in which each key is the name of a primary key or undef if something went wrong.
#
sub get_primary_key {
    my $self  = shift;
    my $param = shift;

    Sympa::Log::Syslog::do_log('debug3', 'Getting primary key for table %s',
        $param->{'table'});
    my %found_keys;
    my $sth;
    unless (
        $sth = $self->do_query(
            "SELECT pg_attribute.attname AS field FROM pg_index, pg_class, pg_attribute WHERE pg_class.oid ='%s'::regclass AND indrelid = pg_class.oid AND pg_attribute.attrelid = pg_class.oid AND pg_attribute.attnum = any(pg_index.indkey) AND indisprimary",
            $param->{'table'}
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Could not get the primary key from table %s in database %s',
            $param->{'table'}, $self->{'db_name'});
        return undef;
    }

    while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
        $found_keys{$ref->{'field'}} = 1;
    }
    return \%found_keys;
}

# Drops the primary key of a table.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the primary keys must be dropped.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub unset_primary_key {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3', 'Removing primary key from table %s',
        $param->{'table'});

    my $sth;

    ## PostgreSQL does not have 'ALTER TABLE ... DROP PRIMARY KEY'.
    ## Instead, get a name of constraint then drop it.
    my $key_name;

    unless (
        $sth = $self->do_query(
            q{SELECT tc.constraint_name
	  FROM information_schema.table_constraints AS tc
	  WHERE tc.table_catalog = %s AND tc.table_name = %s AND
		tc.constraint_type = 'PRIMARY KEY'},
            &SDM::quote($self->{'db_name'}), &SDM::quote($param->{'table'})
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Could not search primary key from table %s in database %s',
            $param->{'table'}, $self->{'db_name'});
        return undef;
    }

    $key_name = $sth->fetchrow_array();
    $sth->finish;
    unless (defined $key_name) {
        Sympa::Log::Syslog::do_log('err',
            'Could not get primary key from table %s in database %s',
            $param->{'table'}, $self->{'db_name'});
        return undef;
    }

    unless (
        $sth = $self->do_query(
            q{ALTER TABLE %s DROP CONSTRAINT "%s"}, $param->{'table'},
            $key_name
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Could not drop primary key "%s" from table %s in database %s',
            $key_name, $param->{'table'}, $self->{'db_name'});
        return undef;
    }

    my $report = "Table $param->{'table'}, PRIMARY KEY dropped";
    Sympa::Log::Syslog::do_log('info', 'Table %s, PRIMARY KEY dropped',
        $param->{'table'});

    return $report;
}

# Sets the primary key of a table.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the primary keys must be defined.
#	* 'fields' : a ref to an array containing the names of the fields used in the key.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub set_primary_key {
    my $self  = shift;
    my $param = shift;

    my $sth;

    ## Give fixed key name if possible.
    my $key;
    if ($param->{'table'} =~ /^(.+)_table$/) {
        $key = sprintf 'CONSTRAINT "ind_%s" PRIMARY KEY', $1;
    } else {
        $key = 'PRIMARY KEY';
    }

    my $fields = join ',', @{$param->{'fields'}};
    Sympa::Log::Syslog::do_log('debug3',
        'Setting primary key for table %s (%s)',
        $param->{'table'}, $fields);
    unless (
        $sth = $self->do_query(
            q{ALTER TABLE %s ADD %s (%s)}, $param->{'table'},
            $key,                          $fields
        )
        ) {
        Sympa::Log::Syslog::do_log(
            'err',
            'Could not set fields %s as primary key for table %s in database %s',
            $fields,
            $param->{'table'},
            $self->{'db_name'}
        );
        return undef;
    }

    my $report = "Table $param->{'table'}, PRIMARY KEY set on $fields";
    Sympa::Log::Syslog::do_log('info', 'Table %s, PRIMARY KEY set on %s',
        $param->{'table'}, $fields);
    return $report;
}

# Returns a ref to a hash in which each key is the name of an index.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the indexes are requested.
#
# OUT: A ref to a hash in which each key is the name of an index. These key point to
#	a second level hash in which each key is the name of the field indexed.
#      Returns undef if something went wrong.
#
sub get_indexes {
    my $self  = shift;
    my $param = shift;

    Sympa::Log::Syslog::do_log('debug3',
        'Getting the indexes defined on table %s',
        $param->{'table'});
    my %found_indexes;
    my $sth;
    unless (
        $sth = $self->do_query(
            "SELECT c.oid FROM pg_catalog.pg_class c LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.relname ~ \'^(%s)$\' AND pg_catalog.pg_table_is_visible(c.oid)",
            $param->{'table'}
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            'Could not get the oid for table %s in database %s',
            $param->{'table'}, $self->{'db_name'});
        return undef;
    }
    my $ref = $sth->fetchrow_hashref('NAME_lc');

    unless (
        $sth = $self->do_query(
            "SELECT c2.relname, pg_catalog.pg_get_indexdef(i.indexrelid, 0, true) AS description FROM pg_catalog.pg_class c, pg_catalog.pg_class c2, pg_catalog.pg_index i WHERE c.oid = \'%s\' AND c.oid = i.indrelid AND i.indexrelid = c2.oid AND NOT i.indisprimary ORDER BY i.indisprimary DESC, i.indisunique DESC, c2.relname",
            $ref->{'oid'}
        )
        ) {
        Sympa::Log::Syslog::do_log(
            'err',
            'Could not get the list of indexes from table %s in database %s',
            $param->{'table'},
            $self->{'db_name'}
        );
        return undef;
    }

    while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
        $ref->{'description'} =~
            s/CREATE INDEX .* ON .* USING .* \((.*)\)$/$1/i;
        $ref->{'description'} =~ s/\s//i;
        my @index_members = split ',', $ref->{'description'};
        foreach my $member (@index_members) {
            $found_indexes{$ref->{'relname'}}{$member} = 1;
        }
    }
    return \%found_indexes;
}

# Drops an index of a table.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the index must be dropped.
#	* 'index' : the name of the index to be dropped.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub unset_index {
    my $self  = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3', 'Removing index %s from table %s',
        $param->{'index'}, $param->{'table'});

    my $sth;
    unless ($sth = $self->do_query("DROP INDEX %s", $param->{'index'})) {
        Sympa::Log::Syslog::do_log('err',
            'Could not drop index %s from table %s in database %s',
            $param->{'index'}, $param->{'table'}, $self->{'db_name'});
        return undef;
    }
    my $report = "Table $param->{'table'}, index $param->{'index'} dropped";
    Sympa::Log::Syslog::do_log('info', 'Table %s, index %s dropped',
        $param->{'table'}, $param->{'index'});

    return $report;
}

# Sets an index in a table.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the index must be defined.
#	* 'fields' : a ref to an array containing the names of the fields used in the index.
#	* 'index_name' : the name of the index to be defined..
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub set_index {
    my $self  = shift;
    my $param = shift;

    my $sth;
    my $fields = join ',', @{$param->{'fields'}};
    Sympa::Log::Syslog::do_log(
        'debug3',
        'Setting index %s for table %s using fields %s',
        $param->{'index_name'},
        $param->{'table'}, $fields
    );
    unless (
        $sth = $self->do_query(
            "CREATE INDEX %s ON %s (%s)", $param->{'index_name'},
            $param->{'table'},            $fields
        )
        ) {
        Sympa::Log::Syslog::do_log(
            'err',
            'Could not add index %s using field %s for table %s in database %s',
            $fields,
            $param->{'table'},
            $self->{'db_name'}
        );
        return undef;
    }
    my $report = "Table $param->{'table'}, index %s set using $fields";
    Sympa::Log::Syslog::do_log('info',
        'Table %s, index %s set using fields %s',
        $param->{'table'}, $param->{'index_name'}, $fields);
    return $report;
}

## For DOUBLE types.
sub AS_DOUBLE {
    return ({'pg_type' => DBD::Pg::PG_FLOAT8()} => $_[1])
        if scalar @_ > 1;
    return ();
}

## For BLOB types.
sub AS_BLOB {
    return ({'pg_type' => DBD::Pg::PG_BYTEA()} => $_[1])
        if scalar @_ > 1;
    return ();
}

1;
