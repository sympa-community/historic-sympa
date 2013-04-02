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

Sympa::Datasource::SQL - SQL data source object

=head1 DESCRIPTION

This class implements an SQL data source.

=cut

package Sympa::Datasource::SQL;

use strict;
use base qw(Sympa::Datasource);

use English qw(-no_match_vars);
use DBI;

use Sympa::List;
use Sympa::Log::Syslog;
use Sympa::Tools;

## Structure to keep track of active connections/connection status
## Key : connect_string (includes server+port+dbname+DB type)
## Values : dbh,status,first_try
## "status" can have value 'failed'
## 'first_try' contains an epoch date
my %db_connections;

=head1 CLASS METHODS

=over

=item Sympa::Datasource::SQL->create(%parameters)

Factory method to create a new L<Sympa::Datasource::SQL> object from a
specific subclass.

Parameters:

=over

=item C<host> => FIXME

=item C<user> => FIXME

=item C<passwd> => FIXME

=item C<db_name> => FIXME

=item C<db_type> => FIXME

=item C<connect_options> => FIXME

=item C<domain> => FIXME

=back

Return value:

A new L<Sympa::Datasource::SQL> object, or I<undef> if something went wrong.

=cut

sub create {
	my ($class, %params) = @_;

	Sympa::Log::Syslog::do_log('debug',"Creating new SQLSource object for RDBMS '%s'",$params{'db_type'});

	my $db_type = lc($params{'db_type'});
	my $subclass =
		$db_type eq 'mysql'  ? 'Sympa::Datasource::SQL::MySQL'      :
		$db_type eq 'sqlite' ? 'Sympa::Datasource::SQL::SQLite'     :
		$db_type eq 'pg'     ? 'Sympa::Datasource::SQL::PostgreSQL' :
		$db_type eq 'oracle' ? 'Sympa::Datasource::SQL::Oracle'     :
		$db_type eq 'sybase' ? 'Sympa::Datasource::SQL::Sybase'     :
		                       'Sympa::Datasource::SQL'             ;

	# better solution: UNIVERSAL::require 
	my $module = $subclass . '.pm';
	$module =~ s{::}{/}g;
	eval { require $module; };
	if ($EVAL_ERROR) {
		Sympa::Log::Syslog::do_log('err',"Unable to use $subclass: $EVAL_ERROR");
		return;
	}

	return $subclass->new(%params);
}

=item Sympa::Datasource::SQL->new(%parameters)

Create a new L<Sympa::Datasource::SQL> object.

Parameters:

=over

=item C<host> => FIXME

=item C<user> => FIXME

=item C<passwd> => FIXME

=item C<db_name> => FIXME

=item C<db_type> => FIXME

=item C<connect_options> => FIXME

=item C<domain> => FIXME

=back

Return value:

A new L<Sympa::Datasource::SQL> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	my $self = {
		db_host    => $params{'host'},
		db_user    => $params{'user'},
		db_passwd  => $params{'passwd'},
		db_name    => $params{'db_name'},
		db_type    => $params{'db_type'},
		db_options => $params{'connect_options'},
		domain     => $params{'domain'},
	};

	bless $self, $class;
	return $self;
}

=back

=head1 INSTANCE METHODS

=over

=item $source->connect()

Connect to a SQL database.

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub connect {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug3',"Checking connection to database %s",$self->{'db_name'});
	if ($self->{'dbh'} && $self->{'dbh'}->ping) {
		Sympa::Log::Syslog::do_log('debug3','Connection to database %s already available',$self->{'db_name'});
		return 1;
	}
	unless($self->establish_connection()) {
		Sympa::Log::Syslog::do_log('err','Unable to establish new connection to database %s on host %s',$self->{'db_name'},$self->{'db_host'});
		return undef;
	}
}

=item $source->establish_connection()

Connect to a SQL database.

Parameters:

None.

Return value:

A DBI database handle object, or I<undef> if something went wrong.

=cut

sub establish_connection {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug','Creating connection to database %s',$self->{'db_name'});
	## Do we have db_xxx required parameters
	foreach my $db_param ('db_type','db_name') {
		unless ($self->{$db_param}) {
			Sympa::Log::Syslog::do_log('info','Missing parameter %s for DBI connection', $db_param);
			return undef;
		}
		## SQLite just need a db_name
		unless ($self->{'db_type'} eq 'sqlite') {
			foreach my $db_param ('db_host','db_user') {
				unless ($self->{$db_param}) {
					Sympa::Log::Syslog::do_log('info','Missing parameter %s for DBI connection', $db_param);
					return undef;
				}
			}
		}
	}

	## Build connect_string
	if ($self->{'f_dir'}) {
		$self->{'connect_string'} = "DBI:CSV:f_dir=$self->{'f_dir'}";
	}else {
		$self->build_connect_string();
	}
	if ($self->{'db_options'}) {
		$self->{'connect_string'} .= ';' . $self->{'db_options'};
	}
	if (defined $self->{'db_port'}) {
		$self->{'connect_string'} .= ';port=' . $self->{'db_port'};
	}

	## First check if we have an active connection with this server
	if (defined $db_connections{$self->{'connect_string'}} &&
		defined $db_connections{$self->{'connect_string'}}{'dbh'} &&
		$db_connections{$self->{'connect_string'}}{'dbh'}->ping()) {

		Sympa::Log::Syslog::do_log('debug', "Use previous connection");
		$self->{'dbh'} = $db_connections{$self->{'connect_string'}}{'dbh'};
		return $db_connections{$self->{'connect_string'}}{'dbh'};

	}else {

		## Set environment variables
		## Used by Oracle (ORACLE_HOME)
		if ($self->{'db_env'}) {
			foreach my $env (split /;/,$self->{'db_env'}) {
				my ($key, $value) = split /=/, $env;
				$ENV{$key} = $value if ($key);
			}
		}

		$self->{'dbh'} = eval {DBI->connect($self->{'connect_string'}, $self->{'db_user'}, $self->{'db_passwd'}, { PrintError => 0 })} ;
		unless (defined $self->{'dbh'}) {
			## Notify listmaster if warn option was set
			## Unless the 'failed' status was set earlier
			if ($self->{'reconnect_options'}{'warn'}) {
				unless (defined $db_connections{$self->{'connect_string'}} &&
					$db_connections{$self->{'connect_string'}}{'status'} eq 'failed') {

					unless
					(Sympa::List::send_notify_to_listmaster('no_db', $self->{domain},{})) {
						Sympa::Log::Syslog::do_log('err',"Unable to send notify 'no_db' to listmaster");
					}
				}
			}
			if ($self->{'reconnect_options'}{'keep_trying'}) {
				Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s, still trying...', $self->{'connect_string'}, $self->{'db_user'});
			} else{
				Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s', $self->{'connect_string'}, $self->{'db_user'});
				$db_connections{$self->{'connect_string'}}{'status'} = 'failed';
				$db_connections{$self->{'connect_string'}}{'first_try'} ||= time;
				return undef;
			}
			## Loop until connect works
			my $sleep_delay = 60;
			while (1) {
				sleep $sleep_delay;
				eval {$self->{'dbh'} = DBI->connect($self->{'connect_string'}, $self->{'db_user'}, $self->{'db_passwd'}, { PrintError => 0 })};
				last if ($self->{'dbh'} && $self->{'dbh'}->ping());
				$sleep_delay += 10;
			}

			if ($self->{'reconnect_options'}{'warn'}) {
				Sympa::Log::Syslog::do_log('notice','Connection to Database %s restored.', $self->{'connect_string'});
				unless (Sympa::List::send_notify_to_listmaster('db_restored', $self->{domain},{})) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send notify 'db_restored' to listmaster");
				}
			}
		}

		if ($self->{'db_type'} eq 'pg') { # Configure Postgres to use ISO format dates
			$self->{'dbh'}->do ("SET DATESTYLE TO 'ISO';");
		}

		## Set client encoding to UTF8
		if ($self->{'db_type'} eq 'mysql' ||
			$self->{'db_type'} eq 'pg') {
			Sympa::Log::Syslog::do_log('debug','Setting client encoding to UTF-8');
			$self->{'dbh'}->do("SET NAMES 'utf8'");
		}elsif ($self->{'db_type'} eq 'oracle') {
			$ENV{'NLS_LANG'} = 'UTF8';
		}elsif ($self->{'db_type'} eq 'sybase') {
			$ENV{'SYBASE_CHARSET'} = 'utf8';
		}

		## added sybase support
		if ($self->{'db_type'} eq 'sybase') {
			my $dbname;
			$dbname="use $self->{'db_name'}";
			$self->{'dbh'}->do ($dbname);
		}

		## Force field names to be lowercased
		## This has has been added after some problems of field names upercased with Oracle
		$self->{'dbh'}{'FetchHashKeyName'}='NAME_lc';

		if ($self->{'db_type'} eq 'sqlite') { # Configure to use sympa database
			$self->{'dbh'}->func( 'func_index', -1, sub { return index($_[0],$_[1]) }, 'create_function' );
			if(defined $self->{'db_timeout'}) { $self->{'dbh'}->func( $self->{'db_timeout'}, 'busy_timeout' ); } else { $self->{'dbh'}->func( 5000, 'busy_timeout' ); };
		}

		$self->{'connect_string'} = $self->{'connect_string'} if $self;
		$db_connections{$self->{'connect_string'}}{'dbh'} = $self->{'dbh'};
		Sympa::Log::Syslog::do_log('debug','Connected to Database %s',$self->{'db_name'});
		return $self->{'dbh'};
	}
}

=item $source->do_query($query, @params)

Parameters:

=over

=item C<$query> =>

=back

Return value:

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub do_query {
	my ($self, $query, @params) = @_;

	my $statement = sprintf $query, @params;

	Sympa::Log::Syslog::do_log('debug', "Will perform query '%s'",$statement);
	unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
		# Check connection to database in case it would be the cause of the problem.
		unless($self->connect()) {
			Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		}else {
			unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
				my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
				Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement %s : %s', $trace_statement, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}
	unless ($self->{'sth'}->execute) {
		# Check connection to database in case it would be the cause of the problem.
		unless($self->connect()) {
			Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		}else {
			unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
				# Check connection to database in case it would be the cause of the problem.
				unless($self->connect()) {
					Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
					return undef;
				}else {
					unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
						my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
						Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement %s : %s', $trace_statement, $self->{'dbh'}->errstr);
						return undef;
					}
				}
			}
			unless ($self->{'sth'}->execute) {
				my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
				Sympa::Log::Syslog::do_log('err','Unable to execute SQL statement "%s" : %s', $trace_statement, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}

	return $self->{'sth'};
}

=item $source->do_prepared_query($query, @params)

Parameters:

=over

=item C<$query> =>

=back

Return value:

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub do_prepared_query {
	my ($self, $query, @params) = @_;

	my $sth;

	unless ($self->{'cached_prepared_statements'}{$query}) {
		Sympa::Log::Syslog::do_log('debug3','Did not find prepared statement for %s. Doing it.',$query);
		unless ($sth = $self->{'dbh'}->prepare($query)) {
			unless($self->connect()) {
				Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
				return undef;
			}else {
				unless ($sth = $self->{'dbh'}->prepare($query)) {
					Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement : %s', $self->{'dbh'}->errstr);
					return undef;
				}
			}
		}
		$self->{'cached_prepared_statements'}{$query} = $sth;
	}else {
		Sympa::Log::Syslog::do_log('debug3','Reusing prepared statement for %s',$query);
	}
	unless ($self->{'cached_prepared_statements'}{$query}->execute(@params)) {
		# Check database connection in case it would be the cause of the problem.
		unless($self->connect()) {
			Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		}else {
			unless ($sth = $self->{'dbh'}->prepare($query)) {
				unless($self->connect()) {
					Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
					return undef;
				}else {
					unless ($sth = $self->{'dbh'}->prepare($query)) {
						Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement : %s', $self->{'dbh'}->errstr);
						return undef;
					}
				}
			}
			$self->{'cached_prepared_statements'}{$query} = $sth;
			unless ($self->{'cached_prepared_statements'}{$query}->execute(@params)) {
				Sympa::Log::Syslog::do_log('err','Unable to execute SQL statement "%s" : %s', $query, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}

	return $self->{'cached_prepared_statements'}{$query};
}

=item $source->prepare_query_log_values(@values)

Parameters:

=over

=item C<@values> =>

=back

Return value:

The list of cropped values, as an arrayref.

=cut

sub prepare_query_log_values {
	my ($self) = @_;

	my @result;
	foreach my $value (@_) {
		my $cropped = substr($value,0,100);
		if ($cropped ne $value) {
			$cropped .= "...[shortened]";
		}
		push @result, $cropped;
	}
	return \@result;
}

=item $source->fetch()

Parameters:

None.

Return value:

=cut

sub fetch {
	my ($self) = @_;

	## call to fetchrow_arrayref() uses eval to set a timeout
	## this prevents one data source to make the process wait forever if SELECT does not respond
	my $array_of_users;
	$array_of_users = eval {
		local $SIG{ALRM} = sub { die "TIMEOUT\n" }; # NB: \n required
		alarm $self->{'fetch_timeout'};

		## Inner eval just in case the fetchall_arrayref call would die, thus leaving the alarm trigered
		my $status = eval {
			return $self->{'sth'}->fetchall_arrayref;
		};
		alarm 0;
		return $status;
	};
	if ( $EVAL_ERROR eq "TIMEOUT\n" ) {
		Sympa::Log::Syslog::do_log('err','Fetch timeout on remote SQL database');
		return undef;
	}elsif ($EVAL_ERROR) {
		Sympa::Log::Syslog::do_log('err','Fetch failed on remote SQL database');
		return undef;
	}

	return $array_of_users;
}

=item $source->disconnect()

Parameters:

None.

Return value:

None.

=cut

sub disconnect {
	my ($self) = @_;

	$self->{'sth'}->finish if $self->{'sth'};
	if ($self->{'dbh'}) {$self->{'dbh'}->disconnect;}
	delete $db_connections{$self->{'connect_string'}};
}

=item $source->create_db()

Parameters:

None.

Return value:

A true value.

=cut

sub create_db {
	Sympa::Log::Syslog::do_log('debug3', '()');
	return 1;
}

=item $source->ping()

Ping underlying data source.

See L<DBI> for details.

=cut

sub ping {
	my ($self) = @_;

	return $self->{'dbh'}->ping;
}

=item $source->quote($string, $datatype)

Quote a string literal for use in an SQL statement.

See L<DBI> for details.

=cut

sub quote {
	my ($self, $string, $datatype) = @_;

	return $self->{'dbh'}->quote($string, $datatype);
}

=item $source->set_fetch_timeout($timeout)

Set a timeout for fetch operations.

=cut

sub set_fetch_timeout {
	my ($self, $timeout) = @_;

	return $self->{'fetch_timeout'} = $timeout;
}

=item $source->get_canonical_write_date($field)

Returns a character string corresponding to the expression to use in a read
query (e.g. SELECT) for the field given as argument.

Parameters:

=over

=item C<$field> => field to be used in the query

=back

=cut

sub get_canonical_write_date {
	my ($self, $field) = @_;

	return $self->get_formatted_date('mode'=>'write','target'=>$field);
}

=item $source->get_canonical_read_date($value)

Returns a character string corresponding to the expression to use in
a write query (e.g. UPDATE or INSERT) for the value given as argument.

Parameters:

=over

=item C<$value> => value to be used in the query

=back

=cut

sub get_canonical_read_date {
	my $self = shift;
	my $value = shift;
	return $self->get_formatted_date('mode'=>'read','target'=>$value);
}

=item $source->get_all_primary_keys()

Returns the primary keys for all the tables in the database.

Parameters:

None.

Return value:

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item * The keys of the first level are the database's tables name.

=item * The keys of the second level are the name of the primary keys for the
table whose name is  given by the first level key.

=back

=cut

sub get_all_primary_keys {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug','Retrieving all primary keys in database %s',$self->{'db_name'});
	my %found_keys = undef;
	foreach my $table (@{$self->get_tables()}) {
		unless($found_keys{$table} = $self->get_primary_key('table'=>$table)) {
			Sympa::Log::Syslog::do_log('err','Primary key retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_keys;
}

=item $source->get_all_indexes()

Returns the indexes for all the tables in the database.

Parameters:

None.

Return value:

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item * The keys of the first level are the database's tables name.

=item * The keys of the second level are the name of the indexes for the table whose name is given by the first level key.

=back

=cut

sub get_all_indexes {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug','Retrieving all indexes in database %s',$self->{'db_name'});
	my %found_indexes;
	foreach my $table (@{$self->get_tables()}) {
		unless($found_indexes{$table} = $self->get_indexes('table'=>$table)) {
			Sympa::Log::Syslog::do_log('err','Index retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_indexes;
}

=item $source->check_key(%parameters)

Checks the compliance of a key of a table compared to what it is supposed to
reference.

Parameters:

* 'table' : the name of the table for which we want to check the primary key
* 'key_name' : the kind of key tested:
	- if the value is 'primary', the key tested will be the table primary key
		- for any other value, the index whose name is this value will be tested.
	* 'expected_keys' : A ref to an array containing the list of fields that we
	   expect to be part of the key.

Return value:

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
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Checking %s key structure for table %s',$params{'key_name'},$params{'table'});
	my $keysFound;
	my $result;
	if (lc($params{'key_name'}) eq 'primary') {
		return undef unless ($keysFound = $self->get_primary_key('table'=>$params{'table'}));
	}else {
		return undef unless ($keysFound = $self->get_indexes('table'=>$params{'table'}));
		$keysFound = $keysFound->{$params{'key_name'}};
	}

	my @keys_list = keys %{$keysFound};
	if ($#keys_list < 0) {
		$result->{'empty'}=1;
	}else{
		$result->{'existing_key_correct'} = 1;
		my %expected_keys;
		foreach my $expected_field (@{$params{'expected_keys'}}){
			$expected_keys{$expected_field} = 1;
		}
		foreach my $field (@{$params{'expected_keys'}}) {
			unless ($keysFound->{$field}) {
				Sympa::Log::Syslog::do_log('info','Table %s: Missing expected key part %s in %s key.',$params{'table'},$field,$params{'key_name'});
				$result->{'missing_key'}{$field} = 1;
				$result->{'existing_key_correct'} = 0;
			}
		}
		foreach my $field (keys %{$keysFound}) {
			unless ($expected_keys{$field}) {
				Sympa::Log::Syslog::do_log('info','Table %s: Found unexpected key part %s in %s key.',$params{'table'},$field,$params{'key_name'});
				$result->{'unexpected_key'}{$field} = 1;
				$result->{'existing_key_correct'} = 0;
			}
		}
	}
	return $result;
}

=item source->build_connect_string()

Builds the string to be used by the DBI to connect to the database.

Parameters:

None

=item source->get_substring_clause(%parameters)

Returns an SQL clause to be inserted in a query.

This clause will compute a substring of max length I<substring_length> starting
from the first character equal to I<separator> found in the value of field
I<source_field>.

Parameters:

=over

=item C<substring_length> => maximum substring length

=item C<separator> => substring first character

=item C<source_field> => field to search

=back

=item $source->get_limit_clause(%parameters)

Returns an SQL clause to be inserted in a query.

This clause will limit the number of records returned by the query to
I<rows_count>. If I<offset> is provided, an offset of I<offset> rows is done
from the first record before selecting the rows to return.

Parameters:

=over

=item C<rows_count> => maximum number of records

=item C<offset> => rows offset (optional)

=back

=item $source->get_formatted_date()

Returns a character string corresponding to the expression to use in a query
involving a date.

Parameters:

=over

=item C<mode> => the query type (I<read> for SELECT, I<write> for INSERT or
UPDATE)

=item C<target> => field name or value

=back

Return value:

The formatted date or I<undef> if the date format mode is unknonw.

=item $source->is_autoinc(%parameters)

Checks whether a field is an autoincrement field or not.

Parameters:

=over

=item C<field> => field name

=item C<table> => table name

=back

Return value:

A true value if the field is an autoincrement field, false otherwise.

=item $source->set_autoinc(%parameters)

Defines the field as an autoincrement field.

Parameters:

=over

=item C<field> => field name

=item C<table> => table name

=back

Return value:

A true value if the autoincrement could be set, I<undef> otherwise.

=item $source->get_tables()

Get the list of the tables in the database.

Parametersr:

None.

Return value:

A list of table names as an arrayref, or I<undef> if something went wrong.

=item $source->add_table(%parameters)

Adds a table to the database

Parameters:

=over

=item C<table> => table name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->get_fields(%parameters)

Get the list of fields in a table from the database.

Parameters:

=over

=item C<table> => table name

=back

Return value:

A list of name => value pairs as an hashref, or I<undef> if something went
wrong.

=item $source->update_field(%parameters)

Changes the type of a field in a table from the database.

Parameters:

=over

=item C<table> => table name

=item C<field> => field name

=item C<type> => field type

=item C<notnull> => specifies that the field must not be null

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->add_field(%parameters)

Adds a field in a table from the database.

Parameters:

=over

=item C<table> => table name

=item C<field> => field name

=item C<type> => field type

=item C<notnull> => specifies that the field must not be null

=item C<autoinc> => specifies that the field must be autoincremental

=item C<primary> => specifies that the field is a key

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->delete_field(%parameters)

Delete a field in a table from the database.

Parameters:

=over

=item C<table> => table name

=item C<field> => field name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->get_primary_key(%parameters)

Returns the list of fields being part of a table's primary key.

Parameters:

=over

=item C<table> => table name

=back

Return value:

An hashref whose keys are the name of the fields of the primary key, or
I<undef> if something went wrong.

=item $source->unset_primary_key(%parameters)

Drops the primary key of a table.

Parameters:

=over

=item C<table> => table name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->set_primary_key(%parameters)

Sets the primary key of a table.

Parameters:

=over

=item C<table> => table name

=item C<fields> => field names, as an arrayref

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->get_indexes(%parameters)

Returns the list of indexes of a table.

Parameters:

=over

=item C<table> => table name

=back

Return value:

An hashref whose keys are the name of indexes, with hashref whose keys are the
indexed fields as values, or I<undef> if something went wrong.

=item $source->unset_index(%parameters)

Drops an index of a table.

Parameters:

=over

=item C<table> => table name

=item C<index> => index name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->set_index(%parameters)

Sets an index in a table.

Parameters:

=over

=item C<table> => table name

=item C<fields> => field names, as an arrayref

=item C<index_name> => index name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=back

=cut

1;
