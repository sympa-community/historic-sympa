# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
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

Sympa::Datasource::SQL::Default - Generic SQL data source object

=head1 DESCRIPTION

This class implements a generic SQL data source.

=cut

package Sympa::Datasource::SQL::Default;

use strict;
use base qw(Sympa::Datasource::SQL);

use Sympa::Log;

=head1 INSTANCE METHODS

=head2 $source->get_all_primary_keys()

Returns the primary keys for all the tables in the database.

=head3 Parameters

None.

=head3 Return value

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item * The keys of the first level are the database's tables name.

=item * The keys of the second level are the name of the primary keys for the
table whose name is  given by the first level key.

=back

=cut

sub get_all_primary_keys {
	my $self = shift;
	&Sympa::Log::do_log('debug','Retrieving all primary keys in database %s',$self->{'db_name'});
	my %found_keys = undef;
	foreach my $table (@{$self->get_tables()}) {
		unless($found_keys{$table} = $self->get_primary_key({'table'=>$table})) {
			&Sympa::Log::do_log('err','Primary key retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_keys;
}

=head2 $source->get_all_indexes()

Returns the indexes for all the tables in the database.

=head3 Parameters

None.

=head3 Return value

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item * The keys of the first level are the database's tables name.

=item * The keys of the second level are the name of the indexes for the table whose name is given by the first level key.

=back

=cut

sub get_all_indexes {
	my $self = shift;
	&Sympa::Log::do_log('debug','Retrieving all indexes in database %s',$self->{'db_name'});
	my %found_indexes;
	foreach my $table (@{$self->get_tables()}) {
		unless($found_indexes{$table} = $self->get_indexes({'table'=>$table})) {
			&Sympa::Log::do_log('err','Index retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_indexes;
}

=head2 $source->check_key($parameters)

Checks the compliance of a key of a table compared to what it is supposed to
reference.

=head3 Parameters

* 'table' : the name of the table for which we want to check the primary key
* 'key_name' : the kind of key tested:
	- if the value is 'primary', the key tested will be the table primary key
		- for any other value, the index whose name is this value will be tested.
	* 'expected_keys' : A ref to an array containing the list of fields that we
	   expect to be part of the key.

=head3 Return value

A ref likely to contain the following values:
#	* 'empty': if this key is defined, then no key was found for the table
#	* 'existing_key_correct': if this key's value is 1, then a key
#	   exists and is fair to the structure defined in the 'expected_keys' parameter hash.
#	   Otherwise, the key is not correct.
#	* 'missing_key': if this key is defined, then a part of the key was missing.
#	   The value associated to this key is a hash whose keys are the names of the fields
#	   missing in the key.
#	* 'unexpected_key': if this key is defined, then we found fields in the actual
#	   key that don't belong to the list provided in the 'expected_keys' parameter hash.
#	   The value associated to this key is a hash whose keys are the names of the fields
#	   unexpectedely found.

=cut

sub check_key {
	my $self = shift;
	my $param = shift;
	&Sympa::Log::do_log('debug','Checking %s key structure for table %s',$param->{'key_name'},$param->{'table'});
	my $keysFound;
	my $result;
	if (lc($param->{'key_name'}) eq 'primary') {
		return undef unless ($keysFound = $self->get_primary_key({'table'=>$param->{'table'}}));
	}else {
		return undef unless ($keysFound = $self->get_indexes({'table'=>$param->{'table'}}));
		$keysFound = $keysFound->{$param->{'key_name'}};
	}

	my @keys_list = keys %{$keysFound};
	if ($#keys_list < 0) {
		$result->{'empty'}=1;
	}else{
		$result->{'existing_key_correct'} = 1;
		my %expected_keys;
		foreach my $expected_field (@{$param->{'expected_keys'}}){
			$expected_keys{$expected_field} = 1;
		}
		foreach my $field (@{$param->{'expected_keys'}}) {
			unless ($keysFound->{$field}) {
				&Sympa::Log::do_log('info','Table %s: Missing expected key part %s in %s key.',$param->{'table'},$field,$param->{'key_name'});
				$result->{'missing_key'}{$field} = 1;
				$result->{'existing_key_correct'} = 0;
			}
		}
		foreach my $field (keys %{$keysFound}) {
			unless ($expected_keys{$field}) {
				&Sympa::Log::do_log('info','Table %s: Found unexpected key part %s in %s key.',$param->{'table'},$field,$param->{'key_name'});
				$result->{'unexpected_key'}{$field} = 1;
				$result->{'existing_key_correct'} = 0;
			}
		}
	}
	return $result;
}

=head2 source->build_connect_string()

Builds the string to be used by the DBI to connect to the database.

=head3 Parameters

None

=head2 source->get_substring_clause($parameters)

Returns an SQL clause to be inserted in a query.

This clause will compute a substring of max length I<substring_length> starting
from the first character equal to I<separator> found in the value of field
I<source_field>.

=head3 Parameters

=over

=item * I<substring_length>: maximum substring length

=item * I<separator>: substring first character

=item * I<source_field>: field to search

=back

=head2 $source->get_limit_clause($parameters)

Returns an SQL clause to be inserted in a query.

This clause will limit the number of records returned by the query to
I<rows_count>. If I<offset> is provided, an offset of I<offset> rows is done
from the first record before selecting the rows to return.

=head3 Parameters

=over

=item * I<rows_count>: maximum number of records

=item * I<offset>: rows offset (optional)

=back

=head2 $source->get_formatted_date()

Returns a character string corresponding to the expression to use in a query
involving a date.

=head3 Parameters

=over

=item * I<mode>: the query type (I<read> for SELECT, I<write> for INSERT or
UPDATE)

=item * I<target>: field name or value

=back

=head3 Return value

The formatted date or I<undef> if the date format mode is unknonw.

=head2 $source->is_autoinc($parameters)

Checks whether a field is an autoincrement field or not.

=head3 Parameters

=over

=item * I<field>: field name

=item * I<table>: table name

=back

=head3 Return value

A true value if the field is an autoincrement field, false otherwise.

=head2 $source->set_autoinc($parameters)

Defines the field as an autoincrement field.

=head3 Parameters

=over

=item * I<field>: field name

=item * I<table>: table name

=back

=head3 Return value

A true value if the autoincrement could be set, I<undef> otherwise.

=head2 $source->get_tables()

Get the list of the tables in the database.

=head3 Parametersr

None.

=head3 Return value

A list of table names as an arrayref, or I<undef> if something went wrong.

=head2 $source->add_table($parameters)

Adds a table to the database

=head3 Parameters

=over

=item * I<table>: table name

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=head2 $source->get_fields($parameters)

Get the list of fields in a table from the database.

=head3 Parameters

=over

=item * I<table>: table name

=back

=head3 Return value

A list of name => value pairs as an hashref, or I<undef> if something went
wrong.

=head2 $source->update_field($parameters)

Changes the type of a field in a table from the database.

=head3 Parameters

=over

=item * I<table>: table name

=item * I<field>: field name

=item * I<type>: field type

=item * I<notnull>: specifies that the field must not be null

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=head2 $source->add_field($parameters)

Adds a field in a table from the database.

=head3 Parameters

=over

=item * I<table>: table name

=item * I<field>: field name

=item * I<type>: field type

=item * I<notnull>: specifies that the field must not be null

=item * I<autoinc>: specifies that the field must be autoincremental

=item * I<primary>: specifies that the field is a key

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=head2 $source->delete_field($parameters)

Delete a field in a table from the database.

=head3 Parameters

=over

=item * I<table>: table name

=item * I<field>: field name

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=head2 $source->get_primary_key($parameters)

Returns the list of fields being part of a table's primary key.

=head3 Parameters

=over

=item * I<table>: table name

=back

=head3 Return value

An hashref whose keys are the name of the fields of the primary key, or
I<undef> if something went wrong.

=head2 $source->unset_primary_key($parameters)

Drops the primary key of a table.

=head3 Parameters

=over

=item * I<table>: table name

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=head2 $source->set_primary_key($parameters)

Sets the primary key of a table.

=head3 Parameters

=over

=item * I<table>: table name

=item * I<fields>: field names, as an arrayref

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=head2 $source->get_indexes($parameters)

Returns the list of indexes of a table.

=head3 Parameters

=over

=item * I<table>: table name

=back

=head3 Return value

An hashref whose keys are the name of indexes, with hashref whose keys are the
indexed fields as values, or I<undef> if something went wrong.

=head2 $source->unset_index($parameters)

Drops an index of a table.

=head3 Parameters

=over

=item * I<table>: table name

=item * I<index>: index name

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=head2 $source->set_index($parameters)

Sets an index in a table.

=head3 Parameters

=over

=item * I<table>: table name

=item * I<fields>: field names, as an arrayref

=item * I<index_name>: index name

=back

=head3 Return value

A report of the operation done as a string, or I<undef> if something went wrong.

=cut

1;
