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

Sympa::Datasource::SQL - SQL data source object

=head1 DESCRIPTION

This class implements an SQL data source.

=cut

package Sympa::Datasource::SQL;

use strict;
use base qw(Sympa::Datasource);

use DBI;

use Sympa::Configuration;
use Sympa::List;
use Sympa::Log;
use Sympa::Tools;

## Structure to keep track of active connections/connection status
## Key : connect_string (includes server+port+dbname+DB type)
## Values : dbh,status,first_try
## "status" can have value 'failed'
## 'first_try' contains an epoch date
my %db_connections;

=head1 CLASS METHODS

=head2 Sympa::Datasource::SQL->new($params)

Create a new L<Sympa::Datasource::SQL> object.

=head3 Parameters

=over

=item * I<host>

=item * I<user>

=item * I<passwd>

=item * I<connect_options>

=item * I<db_type>

=back

=head3 Return value

A new L<Sympa::Datasource::SQL> object, or I<undef> if something went wrong.

=cut

sub new {
	my $pkg = shift;
	my $param = shift;
	my $self = $param;
	&Sympa::Log::do_log('debug',"Creating new SQLSource object for RDBMS '%s'",$param->{'db_type'});
	my $actualclass;
	if ($param->{'db_type'} =~ /^mysql$/i) {
		unless ( eval "require Sympa::Datasource::SQL::MySQL" ){
			&Sympa::Log::do_log('err',"Unable to use Sympa::Datasource::SQL::MySQL module: $@");
			return undef;
		}
		require Sympa::Datasource::SQL::MySQL;
		$actualclass = "Sympa::Datasource::SQL::MySQL";
	}elsif ($param->{'db_type'} =~ /^sqlite$/i) {
		unless ( eval "require Sympa::Datasource::SQL::SQLite" ){
			&Sympa::Log::do_log('err',"Unable to use Sympa::Datasource::SQL::SQLite module");
			return undef;
		}
		require Sympa::Datasource::SQL::SQLite;

		$actualclass = "Sympa::Datasource::SQL::SQLite";
	}elsif ($param->{'db_type'} =~ /^pg$/i) {
		unless ( eval "require Sympa::Datasource::SQL::PostgreSQL" ){
			&Sympa::Log::do_log('err',"Unable to use Sympa::Datasource::SQL::PostgreSQL module");
			return undef;
		}
		require Sympa::Datasource::SQL::PostgreSQL;

		$actualclass = "Sympa::Datasource::SQL::PostgreSQL";
	}elsif ($param->{'db_type'} =~ /^oracle$/i) {
		unless ( eval "require Sympa::Datasource::SQL::Oracle" ){
			&Sympa::Log::do_log('err',"Unable to use Sympa::Datasource::SQL::Oracle module");
			return undef;
		}
		require Sympa::Datasource::SQL::Oracle;

		$actualclass = "Sympa::Datasource::SQL::Oracle";
	}elsif ($param->{'db_type'} =~ /^sybase$/i) {
		unless ( eval "require Sympa::Datasource::SQL::Sybase" ){
			&Sympa::Log::do_log('err',"Unable to use Sympa::Datasource::SQL::Sybase module");
			return undef;
		}
		require Sympa::Datasource::SQL::Sybase;

		$actualclass = "Sympa::Datasource::SQL::Sybase";
	}else {
		## We don't have a DB Manipulator for this RDBMS
		## It might be an SQL source used to include list members/owners
		## like CSV
		require Sympa::Datasource::SQL::Default;

		$actualclass = "Sympa::Datasource::SQL::Default";
	}
	$self = $pkg->SUPER::new($param);

	$self->{'db_host'} ||= $self->{'host'};
	$self->{'db_user'} ||= $self->{'user'};
	$self->{'db_passwd'} ||= $self->{'passwd'};
	$self->{'db_options'} ||= $self->{'connect_options'};

	bless $self, $actualclass;
	return $self;
}

=head1 INSTANCE METHODS

=head2 $source->connect()

Connect to a SQL database.

=head3 Return value

A true value, or I<undef> if something went wrong.

=cut

sub connect {
	my $self = shift;
	&Sympa::Log::do_log('debug3',"Checking connection to database %s",$self->{'db_name'});
	if ($self->{'dbh'} && $self->{'dbh'}->ping) {
		&Sympa::Log::do_log('debug3','Connection to database %s already available',$self->{'db_name'});
		return 1;
	}
	unless($self->establish_connection()) {
		&Sympa::Log::do_log('err','Unable to establish new connection to database %s on host %s',$self->{'db_name'},$self->{'db_host'});
		return undef;
	}
}

=head2 $source->establish_connection()

Connect to a SQL database.

=head3 Parameters

None.

=head3 Return value

A DBI database handle object, or I<undef> if something went wrong.

=cut

sub establish_connection {
	my $self = shift;

	&Sympa::Log::do_log('debug','Creating connection to database %s',$self->{'db_name'});
	## Do we have db_xxx required parameters
	foreach my $db_param ('db_type','db_name') {
		unless ($self->{$db_param}) {
			&Sympa::Log::do_log('info','Missing parameter %s for DBI connection', $db_param);
			return undef;
		}
		## SQLite just need a db_name
		unless ($self->{'db_type'} eq 'SQLite') {
			foreach my $db_param ('db_host','db_user') {
				unless ($self->{$db_param}) {
					&Sympa::Log::do_log('info','Missing parameter %s for DBI connection', $db_param);
					return undef;
				}
			}
		}
	}

	## Check if DBD is installed
	unless (eval "require DBD::$self->{'db_type'}") {
		&Sympa::Log::do_log('err',"No Database Driver installed for $self->{'db_type'} ; you should download and install DBD::$self->{'db_type'} from CPAN");
		&Sympa::List::send_notify_to_listmaster('missing_dbd', $Sympa::Configuration::Conf{'domain'},{'db_type' => $self->{'db_type'}});
		return undef;
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

		&Sympa::Log::do_log('debug', "Use previous connection");
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

					unless (&Sympa::List::send_notify_to_listmaster('no_db', $Sympa::Configuration::Conf{'domain'},{})) {
						&Sympa::Log::do_log('err',"Unable to send notify 'no_db' to listmaster");
					}
				}
			}
			if ($self->{'reconnect_options'}{'keep_trying'}) {
				&Sympa::Log::do_log('err','Can\'t connect to Database %s as %s, still trying...', $self->{'connect_string'}, $self->{'db_user'});
			} else{
				&Sympa::Log::do_log('err','Can\'t connect to Database %s as %s', $self->{'connect_string'}, $self->{'db_user'});
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
				&Sympa::Log::do_log('notice','Connection to Database %s restored.', $self->{'connect_string'});
				unless (&Sympa::List::send_notify_to_listmaster('db_restored', $Sympa::Configuration::Conf{'domain'},{})) {
					&Sympa::Log::do_log('notice',"Unable to send notify 'db_restored' to listmaster");
				}
			}
		}

		if ($self->{'db_type'} eq 'Pg') { # Configure Postgres to use ISO format dates
			$self->{'dbh'}->do ("SET DATESTYLE TO 'ISO';");
		}

		## Set client encoding to UTF8
		if ($self->{'db_type'} eq 'mysql' ||
			$self->{'db_type'} eq 'Pg') {
			&Sympa::Log::do_log('debug','Setting client encoding to UTF-8');
			$self->{'dbh'}->do("SET NAMES 'utf8'");
		}elsif ($self->{'db_type'} eq 'oracle') {
			$ENV{'NLS_LANG'} = 'UTF8';
		}elsif ($self->{'db_type'} eq 'Sybase') {
			$ENV{'SYBASE_CHARSET'} = 'utf8';
		}

		## added sybase support
		if ($self->{'db_type'} eq 'Sybase') {
			my $dbname;
			$dbname="use $self->{'db_name'}";
			$self->{'dbh'}->do ($dbname);
		}

		## Force field names to be lowercased
		## This has has been added after some problems of field names upercased with Oracle
		$self->{'dbh'}{'FetchHashKeyName'}='NAME_lc';

		if ($self->{'db_type'} eq 'SQLite') { # Configure to use sympa database
			$self->{'dbh'}->func( 'func_index', -1, sub { return index($_[0],$_[1]) }, 'create_function' );
			if(defined $self->{'db_timeout'}) { $self->{'dbh'}->func( $self->{'db_timeout'}, 'busy_timeout' ); } else { $self->{'dbh'}->func( 5000, 'busy_timeout' ); };
		}

		$self->{'connect_string'} = $self->{'connect_string'} if $self;
		$db_connections{$self->{'connect_string'}}{'dbh'} = $self->{'dbh'};
		&Sympa::Log::do_log('debug','Connected to Database %s',$self->{'db_name'});
		return $self->{'dbh'};
	}
}

=head2 $source->do_query($query, @params)

=head3 Parameters

=over

=item * I<$query>

=back

=head3 Return value

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub do_query {
	my $self = shift;
	my $query = shift;
	my @params = @_;

	my $statement = sprintf $query, @params;

	&Sympa::Log::do_log('debug', "Will perform query '%s'",$statement);
	unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
		# Check connection to database in case it would be the cause of the problem.
		unless($self->connect()) {
			&Sympa::Log::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		}else {
			unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
				my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
				&Sympa::Log::do_log('err','Unable to prepare SQL statement %s : %s', $trace_statement, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}
	unless ($self->{'sth'}->execute) {
		# Check connection to database in case it would be the cause of the problem.
		unless($self->connect()) {
			&Sympa::Log::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		}else {
			unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
				# Check connection to database in case it would be the cause of the problem.
				unless($self->connect()) {
					&Sympa::Log::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
					return undef;
				}else {
					unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
						my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
						&Sympa::Log::do_log('err','Unable to prepare SQL statement %s : %s', $trace_statement, $self->{'dbh'}->errstr);
						return undef;
					}
				}
			}
			unless ($self->{'sth'}->execute) {
				my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
				&Sympa::Log::do_log('err','Unable to execute SQL statement "%s" : %s', $trace_statement, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}

	return $self->{'sth'};
}

=head2 $source->do_prepared_query($query, @params)

=head3 Parameters

=over

=item * I<$query>

=back

=head3 Return value

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub do_prepared_query {
	my $self = shift;
	my $query = shift;
	my @params = @_;

	my $sth;

	unless ($self->{'cached_prepared_statements'}{$query}) {
		&Sympa::Log::do_log('debug3','Did not find prepared statement for %s. Doing it.',$query);
		unless ($sth = $self->{'dbh'}->prepare($query)) {
			unless($self->connect()) {
				&Sympa::Log::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
				return undef;
			}else {
				unless ($sth = $self->{'dbh'}->prepare($query)) {
					&Sympa::Log::do_log('err','Unable to prepare SQL statement : %s', $self->{'dbh'}->errstr);
					return undef;
				}
			}
		}
		$self->{'cached_prepared_statements'}{$query} = $sth;
	}else {
		&Sympa::Log::do_log('debug3','Reusing prepared statement for %s',$query);
	}
	unless ($self->{'cached_prepared_statements'}{$query}->execute(@params)) {
		# Check database connection in case it would be the cause of the problem.
		unless($self->connect()) {
			&Sympa::Log::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		}else {
			unless ($sth = $self->{'dbh'}->prepare($query)) {
				unless($self->connect()) {
					&Sympa::Log::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
					return undef;
				}else {
					unless ($sth = $self->{'dbh'}->prepare($query)) {
						&Sympa::Log::do_log('err','Unable to prepare SQL statement : %s', $self->{'dbh'}->errstr);
						return undef;
					}
				}
			}
			$self->{'cached_prepared_statements'}{$query} = $sth;
			unless ($self->{'cached_prepared_statements'}{$query}->execute(@params)) {
				&Sympa::Log::do_log('err','Unable to execute SQL statement "%s" : %s', $query, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}

	return $self->{'cached_prepared_statements'}{$query};
}

=head2 $source->prepare_query_log_values(@values)

=head3 Parameters

=over

=item * I<@values>

=back

=head3 Return value

The list of cropped values, as an arrayref.

=cut

sub prepare_query_log_values {
	my $self = shift;
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

=head2 $source->fetch()

=head3 Parameters

None.

=head3 Return value

=cut

sub fetch {
	my $self = shift;

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
	if ( $@ eq "TIMEOUT\n" ) {
		&Sympa::Log::do_log('err','Fetch timeout on remote SQL database');
		return undef;
	}elsif ($@) {
		&Sympa::Log::do_log('err','Fetch failed on remote SQL database');
		return undef;
	}

	return $array_of_users;
}

=head2 $source->disconnect()

=head3 Parameters

None.

=head3 Return value

None.

=cut

sub disconnect {
	my $self = shift;
	$self->{'sth'}->finish if $self->{'sth'};
	if ($self->{'dbh'}) {$self->{'dbh'}->disconnect;}
	delete $db_connections{$self->{'connect_string'}};
}

=head2 $source->create_db()

=head3 Parameters

None.

=head3 Return value

A true value.

=cut

sub create_db {
	&Sympa::Log::do_log('debug3', '()');
	return 1;
}

=head2 $source->ping()

Ping underlying data source.

See L<DBI> for details.

=cut

sub ping {
	my $self = shift;
	return $self->{'dbh'}->ping;
}

=head2 $source->quote($string, $datatype)

Quote a string literal for use in an SQL statement.

See L<DBI> for details.

=cut

sub quote {
	my ($self, $string, $datatype) = @_;
	return $self->{'dbh'}->quote($string, $datatype);
}

=head2 $source->set_fetch_timeout($timeout)

Set a timeout for fetch operations.

=cut

sub set_fetch_timeout {
	my ($self, $timeout) = @_;
	return $self->{'fetch_timeout'} = $timeout;
}

=head2 $source->get_canonical_write_date($field)

Returns a character string corresponding to the expression to use in a read
query (e.g. SELECT) for the field given as argument.

=head3 Parameters

=over

=item * I<$field>: field to be used in the query

=back

=cut

sub get_canonical_write_date {
	my $self = shift;
	my $field = shift;
	return $self->get_formatted_date({'mode'=>'write','target'=>$field});
}

=head2 $source->get_canonical_read_date($value)

Returns a character string corresponding to the expression to use in
a write query (e.g. UPDATE or INSERT) for the value given as argument.

=head3 Parameters

=over

=item * I<$value>: value to be used in the query

=back

=cut

sub get_canonical_read_date {
	my $self = shift;
	my $value = shift;
	return $self->get_formatted_date({'mode'=>'read','target'=>$value});
}

1;
