# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
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

package Sympa::SQLSource;

use strict;

use Carp;
use Sympa::Log;

#use Conf; # not used
#use List; # not used
#use tools; # not used
#use tt2; # not used
use Exporter;
use Data::Dumper;
use Sympa::Datasource;

our @ISA    = qw(Exporter);
our @EXPORT = qw(%date_format);
our @EXPORT_OK =
    qw(connect query disconnect fetch create_db ping quote set_fetch_timeout);

## Structure to keep track of active connections/connection status
## Key : connect_string (includes server+port+dbname+DB type)
## Values : dbh,status,first_try
## "status" can have value 'failed'
## 'first_try' contains an epoch date
my %db_connections;

sub new {
    my $pkg   = shift;
    my $param = shift;
    my $self  = $param;
    Sympa::Log::Syslog::do_log('debug',
        "Creating new SQLSource object for RDBMS '%s'",
        $param->{'db_type'});
    my $actualclass;
    our @ISA = qw(Sympa::Datasource);
    if ($param->{'db_type'} =~ /^mysql$/i) {
        unless (eval "require Sympa::DBManipulatorMySQL") {
            Sympa::Log::Syslog::do_log('err',
                "Unable to use Sympa::DBManipulatorMySQL module: $@");
            return undef;
        }
        require Sympa::DBManipulatorMySQL;
        $actualclass = "Sympa::DBManipulatorMySQL";
    } elsif ($param->{'db_type'} =~ /^sqlite$/i) {
        unless (eval "require Sympa::DBManipulatorSQLite") {
            Sympa::Log::Syslog::do_log('err',
                "Unable to use Sympa::DBManipulatorSQLite module");
            return undef;
        }
        require Sympa::DBManipulatorSQLite;

        $actualclass = "Sympa::DBManipulatorSQLite";
    } elsif ($param->{'db_type'} =~ /^pg$/i) {
        unless (eval "require Sympa::DBManipulatorPostgres") {
            Sympa::Log::Syslog::do_log('err',
                "Unable to use Sympa::DBManipulatorPostgres module");
            return undef;
        }
        require Sympa::DBManipulatorPostgres;

        $actualclass = "Sympa::DBManipulatorPostgres";
    } elsif ($param->{'db_type'} =~ /^oracle$/i) {
        unless (eval "require Sympa::DBManipulatorOracle") {
            Sympa::Log::Syslog::do_log('err',
                "Unable to use Sympa::DBManipulatorOracle module");
            return undef;
        }
        require Sympa::DBManipulatorOracle;

        $actualclass = "Sympa::DBManipulatorOracle";
    } elsif ($param->{'db_type'} =~ /^sybase$/i) {
        unless (eval "require Sympa::DBManipulatorSybase") {
            Sympa::Log::Syslog::do_log('err',
                "Unable to use Sympa::DBManipulatorSybase module");
            return undef;
        }
        require DBManipulatorSybase;

        $actualclass = "Sympa::DBManipulatorSybase";
    } else {
        ## We don't have a DB Manipulator for this RDBMS
        ## It might be an SQL source used to include list members/owners
        ## like CSV
        require Sympa::DBManipulatorDefault;

        $actualclass = "Sympa::DBManipulatorDefault";
    }
    $self = $pkg->SUPER::new($param);

    $self->{'db_host'}    ||= $self->{'host'};
    $self->{'db_user'}    ||= $self->{'user'};
    $self->{'db_passwd'}  ||= $self->{'passwd'};
    $self->{'db_options'} ||= $self->{'connect_options'};

    unless (eval "require DBI") {
        Sympa::Log::Syslog::do_log('err',
            "Unable to use DBI library, install DBI (CPAN) first");
        return undef;
    }
    require DBI;

    bless $self, $actualclass;
    return $self;
}

sub connect {
    my $self = shift;
    Sympa::Log::Syslog::do_log('debug3', "Checking connection to database %s",
        $self->{'db_name'});
    if ($self->{'dbh'} && $self->{'dbh'}->ping) {
        Sympa::Log::Syslog::do_log('debug3',
            'Connection to database %s already available',
            $self->{'db_name'});
        return 1;
    }
    unless ($self->establish_connection()) {
        Sympa::Log::Syslog::do_log('err',
            'Unable to establish new connection to database %s on host %s',
            $self->{'db_name'}, $self->{'db_host'});
        return undef;
    }
}

############################################################
#  establish_connection
############################################################
#  Connect to an SQL database.
#
# IN : $options : ref to a hash. Options for the connection process.
#         currently accepts 'keep_trying' : wait and retry until
#         db connection is ok (boolean) ; 'warn' : warn
#         listmaster if connection fails (boolean)
# OUT : $self->{'dbh'}
#     | undef
#
##############################################################
sub establish_connection {
    my $self = shift;

    Sympa::Log::Syslog::do_log('debug', 'Creating connection to database %s',
        $self->{'db_name'});
    ## Do we have db_xxx required parameters
    foreach my $db_param ('db_type', 'db_name') {
        unless ($self->{$db_param}) {
            Sympa::Log::Syslog::do_log('info',
                'Missing parameter %s for DBI connection', $db_param);
            return undef;
        }
        ## SQLite just need a db_name
        unless ($self->{'db_type'} eq 'SQLite') {
            foreach my $db_param ('db_host', 'db_user') {
                unless ($self->{$db_param}) {
                    Sympa::Log::Syslog::do_log('info',
                        'Missing parameter %s for DBI connection', $db_param);
                    return undef;
                }
            }
        }
    }

    ## Check if DBD is installed
    unless (eval "require DBD::$self->{'db_type'}") {
        Sympa::Log::Syslog::do_log(
            'err',
            'No Database Driver installed for %s; you should download and install DBD::%s from CPAN',
            $self->{'db_type'},
            $self->{'db_type'}
        );
        Sympa::Site->send_notify_to_listmaster('missing_dbd',
            {'db_type' => $self->{'db_type'}});
        return undef;
    }

    ## Build connect_string
    if ($self->{'f_dir'}) {
        $self->{'connect_string'} = "DBI:CSV:f_dir=$self->{'f_dir'}";
    } else {
        $self->build_connect_string();
    }
    if ($self->{'db_options'}) {
        $self->{'connect_string'} .= ';' . $self->{'db_options'};
    }
    if (defined $self->{'db_port'}) {
        $self->{'connect_string'} .= ';port=' . $self->{'db_port'};
    }

    ## First check if we have an active connection with this server
    ## We require that user also matches (except SQLite).
    if (defined $db_connections{$self->{'connect_string'}}
        && (   $self->{'db_type'} eq 'SQLite'
            or $db_connections{$self->{'connect_string'}}{'db_user'} eq
            $self->{'db_user'})
        && defined $db_connections{$self->{'connect_string'}}{'dbh'}
        && $db_connections{$self->{'connect_string'}}{'dbh'}->ping()
        ) {
        Sympa::Log::Syslog::do_log('debug3', 'Use previous connection');
        $self->{'dbh'} = $db_connections{$self->{'connect_string'}}{'dbh'};
        return $db_connections{$self->{'connect_string'}}{'dbh'};
    } else {
        ## Set environment variables
        ## Used by Oracle (ORACLE_HOME)

        ## Client encoding derived from the environment variable.
        ## Set this before parsing db_env to allow override if one knows what
        ## she is doing.
        ## Note: on mysql and Pg, "SET NAMES" will be executed below; on
        ## SQLite,
        ## no need to set encoding.
        if ($self->{'db_type'} eq 'Oracle') {
            ## NLS_LANG.  This needs to be set before connecting, otherwise
            ## it's
            ## useless.  Underscore (_) and dot (.) are a vital part as
            ## NLS_LANG
            ## has the syntax "language_territory.charset".
            $ENV{'NLS_LANG'} = '_.UTF8';
        } elsif ($self->{'db_type'} eq 'Sybase') {
            $ENV{'SYBASE_CHARSET'} = 'utf8';
        }

        if ($self->{'db_env'}) {
            foreach my $env (split /;/, $self->{'db_env'}) {
                my ($key, $value) = split /=/, $env;
                $ENV{$key} = $value if ($key);
            }
        }

        $self->{'dbh'} = eval {
            DBI->connect(
                $self->{'connect_string'}, $self->{'db_user'},
                $self->{'db_passwd'}, {PrintError => 0}
            );
        };
        unless (defined $self->{'dbh'}) {
            ## Notify listmaster if warn option was set
            ## Unless the 'failed' status was set earlier
            if ($self->{'reconnect_options'}{'warn'}) {
                unless (defined $db_connections{$self->{'connect_string'}}
                    && $db_connections{$self->{'connect_string'}}{'status'} eq
                    'failed') {

                    Sympa::Site->send_notify_to_listmaster('no_db', {});
                }
            }
            if ($self->{'reconnect_options'}{'keep_trying'}) {
                Sympa::Log::Syslog::do_log(
                    'err',
                    'Can\'t connect to Database %s as %s, still trying...',
                    $self->{'connect_string'},
                    $self->{'db_user'}
                );
            } else {
                Sympa::Log::Syslog::do_log(
                    'err',
                    'Can\'t connect to Database %s as %s',
                    $self->{'connect_string'},
                    $self->{'db_user'}
                );
                $db_connections{$self->{'connect_string'}}{'status'} =
                    'failed';
                $db_connections{$self->{'connect_string'}}{'first_try'} ||=
                    time;
                return undef;
            }
            ## Loop until connect works
            my $sleep_delay = 60;
            while (1) {
                sleep $sleep_delay;
                eval {
                    $self->{'dbh'} = DBI->connect(
                        $self->{'connect_string'}, $self->{'db_user'},
                        $self->{'db_passwd'}, {PrintError => 0}
                    );
                };
                last if ($self->{'dbh'} && $self->{'dbh'}->ping());
                $sleep_delay += 10;
            }

            if ($self->{'reconnect_options'}{'warn'}) {
                Sympa::Log::Syslog::do_log(
                    'notice',
                    'Connection to Database %s restored.',
                    $self->{'connect_string'}
                );
                Sympa::Site->send_notify_to_listmaster('db_restored', {});
            }
        }

        # Configure Postgres to use ISO format dates
        if ($self->{'db_type'} eq 'Pg') {
            $self->{'dbh'}->do("SET DATESTYLE TO 'ISO';");
        }

        ## mysql or Pg: Set client encoding to UTF8
        if ($self->{'db_type'} eq 'mysql') {
            my ($sth, $res, $cset);

            ## Set client-side character set according to server-side
            ## character
            ## set, "utf8" or "utf8mb4".
            if ($sth =
                $self->{'dbh'}
                ->prepare(q{SHOW VARIABLES LIKE 'character_set_server'})
                and $sth->execute
                and $sth->rows
                and $res = $sth->fetchrow_hashref('NAME_lc')) {
                $sth->finish;
                $cset = $res->{'value'};

                if (    $cset eq 'utf8mb4'
                    and $sth = $self->{'dbh'}->prepare(q{SET NAMES 'utf8mb4'})
                    and $sth->execute) {
                    $sth->finish;
                } else {
                    ## Server-side character set is 'utf8', or server, client
                    ## or
                    ## both is earlier than MySQL 5.5.3.
                    Sympa::Log::Syslog::do_log(
                        'notice',
                        'Server-side character set of MySQL is "%s", not '
                            . 'either "utf8" nor "utf8mb4".  This means possible '
                            . 'data loss.',
                        $cset
                    ) unless $cset eq 'utf8';
                    $self->{'dbh'}->do(q{SET NAMES 'utf8'});
                }

                if ($sth =
                    $self->{'dbh'}
                    ->prepare(q{SHOW VARIABLES LIKE 'character_set_client'})
                    and $sth->execute
                    and $sth->rows
                    and $res = $sth->fetchrow_hashref('NAME_lc')) {
                    $sth->finish;
                    $cset = $res->{'value'};
                    Sympa::Log::Syslog::do_log('debug3',
                        'Client character set was set to %s', $cset);
                } else {
                    Sympa::Log::Syslog::do_log('error',
                        'Cannot determine client-side character set');
                }
            } else {
                ## Server may be earlier than MySQL 4.1.1.
                Sympa::Log::Syslog::do_log('error',
                    'Cannot get server-side character set');
            }
        } elsif ($self->{'db_type'} eq 'Pg') {
            Sympa::Log::Syslog::do_log('debug3',
                'Setting client encoding to UTF-8');
            $self->{'dbh'}->do("SET NAMES 'utf8'");
        }

        ## added sybase support
        if ($self->{'db_type'} eq 'Sybase') {
            my $dbname;
            $dbname = "use $self->{'db_name'}";
            $self->{'dbh'}->do($dbname);
        }

        ## Force field names to be lowercased
        ## This has has been added after some problems of field names
        ## upercased with Oracle
        $self->{'dbh'}{'FetchHashKeyName'} = 'NAME_lc';

        if ($self->{'db_type'} eq 'SQLite') {

            # Configure to use sympa database
            $self->{'dbh'}
                ->func('func_index', -1, sub { return index($_[0], $_[1]) },
                'create_function');
            if (defined $self->{'db_timeout'}) {
                $self->{'dbh'}->func($self->{'db_timeout'}, 'busy_timeout');
            } else {
                $self->{'dbh'}->func(5000, 'busy_timeout');
            }
        }

        $self->{'connect_string'} = $self->{'connect_string'} if $self;
        $db_connections{$self->{'connect_string'}}{'dbh'} = $self->{'dbh'};
        $db_connections{$self->{'connect_string'}}{'db_user'} =
            $self->{'db_user'};
        Sympa::Log::Syslog::do_log('debug3', 'Connected to Database %s',
            $self->{'db_name'});

        ## We set Long preload length to two times global max message size
        ## (because of base64 encoding) instead of defaulting to 80 on Oracle
        ## and 32768 on Sybase.
        ## This is to avoid error in Sympa::Bulk::messageasstring when using Oracle
        ## or
        ## Sybase database:
        ##   bulk[pid]: internal error : current packet 'messagekey=
        ##   0c40f56e07d3c8ce34683b98d54b6575 contain a ref to a null message
        ## FIXME: would be better to use lists' setting, but
        ##  * list config is not load()-ed at this point, and
        ##  * when invoked from Sympa::Bulk::messageasstring, list settings is not
        ##  even
        ##    load()-ed later.
        if ($self->{'db_type'} eq 'Oracle' or $self->{'db_type'} eq 'Sybase')
        {
            $self->{'dbh'}->{LongReadLen} = Sympa::Site->max_size * 2;
            $self->{'dbh'}->{LongTruncOk} = 0;
        }
        Sympa::Log::Syslog::do_log(
            'debug3',
            'Database driver seetings for this session: LongReadLen= %d, LongTruncOk= %d, RaiseError= %d',
            $self->{'dbh'}->{LongReadLen},
            $self->{'dbh'}->{LongTruncOk},
            $self->{'dbh'}->{RaiseError}
        );

        return $self->{'dbh'};
    }
}

sub do_query {
    my $self   = shift;
    my $query  = shift;
    my @params = @_;

    $query =~ s/^\s+//;
    $query =~ s/\s+$//;
    my $statement = sprintf $query, @params;

    my $s = $statement;
    $s =~ s/\n\s*/ /g;
    Sympa::Log::Syslog::do_log('debug2', "Will perform query '%s'", $s);

    unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {

        # Check connection to database in case it would be the cause of the
        # problem.
        unless ($self->connect()) {
            Sympa::Log::Syslog::do_log('err',
                'Unable to get a handle to %s database',
                $self->{'db_name'});
            return undef;
        } else {
            unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
                my $trace_statement = sprintf $query,
                    @{$self->prepare_query_log_values(@params)};
                Sympa::Log::Syslog::do_log('err',
                    'Unable to prepare SQL statement %s : %s',
                    $trace_statement, $self->{'dbh'}->errstr);
                return undef;
            }
        }
    }
    unless ($self->{'sth'}->execute) {

        # Check connection to database in case it would be the cause of the
        # problem.
        unless ($self->connect()) {
            Sympa::Log::Syslog::do_log('err',
                'Unable to get a handle to %s database',
                $self->{'db_name'});
            return undef;
        } else {
            unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {

                # Check connection to database in case it would be the cause
                # of the problem.
                unless ($self->connect()) {
                    Sympa::Log::Syslog::do_log('err',
                        'Unable to get a handle to %s database',
                        $self->{'db_name'});
                    return undef;
                } else {
                    unless ($self->{'sth'} =
                        $self->{'dbh'}->prepare($statement)) {
                        my $trace_statement = sprintf $query,
                            @{$self->prepare_query_log_values(@params)};
                        Sympa::Log::Syslog::do_log('err',
                            'Unable to prepare SQL statement %s : %s',
                            $trace_statement, $self->{'dbh'}->errstr);
                        return undef;
                    }
                }
            }
            unless ($self->{'sth'}->execute) {
                my $trace_statement = sprintf $query,
                    @{$self->prepare_query_log_values(@params)};
                Sympa::Log::Syslog::do_log('err',
                    'Unable to execute SQL statement "%s" : %s',
                    $trace_statement, $self->{'dbh'}->errstr);
                return undef;
            }
        }
    }

    return $self->{'sth'};
}

sub do_prepared_query {
    my $self   = shift;
    my $query  = shift;
    my @params = ();
    my %types  = ();

    ## get binding types and parameters
    my $i = 0;
    while (scalar @_) {
        my $p = shift;
        if (ref $p eq 'HASH') {

            # a hashref { sql_type => SQL_type } etc.
            $types{$i} = $p;
            push @params, shift;
        } elsif (ref $p) {
            Sympa::Log::Syslog::do_log('err',
                'unexpected %s object.  Ask developer',
                ref $p);
            return undef;
        } else {
            push @params, $p;
        }
        $i++;
    }

    my $sth;

    $query =~ s/^\s+//;
    $query =~ s/\s+$//;
    $query =~ s/\n\s*/ /g;
    Sympa::Log::Syslog::do_log('debug3', "Will perform query '%s'", $query);

    if ($self->{'cached_prepared_statements'}{$query}) {
        $sth = $self->{'cached_prepared_statements'}{$query};
    } else {
        Sympa::Log::Syslog::do_log('debug3',
            'Did not find prepared statement for %s. Doing it.', $query);
        unless ($sth = $self->{'dbh'}->prepare($query)) {
            unless ($self->connect()) {
                Sympa::Log::Syslog::do_log('err',
                    'Unable to get a handle to %s database',
                    $self->{'db_name'});
                return undef;
            } else {
                unless ($sth = $self->{'dbh'}->prepare($query)) {
                    Sympa::Log::Syslog::do_log(
                        'err',
                        'Unable to prepare SQL statement : %s',
                        $self->{'dbh'}->errstr
                    );
                    return undef;
                }
            }
        }

        ## bind parameters with special types
        ## this may be done only once when handle is prepared.
        foreach my $i (sort keys %types) {
            $sth->bind_param($i + 1, $params[$i], $types{$i});
        }

        $self->{'cached_prepared_statements'}{$query} = $sth;
    }
    unless ($sth->execute(@params)) {

        # Check database connection in case it would be the cause of the
        # problem.
        unless ($self->connect()) {
            Sympa::Log::Syslog::do_log('err',
                'Unable to get a handle to %s database',
                $self->{'db_name'});
            return undef;
        } else {
            unless ($sth = $self->{'dbh'}->prepare($query)) {
                unless ($self->connect()) {
                    Sympa::Log::Syslog::do_log('err',
                        'Unable to get a handle to %s database',
                        $self->{'db_name'});
                    return undef;
                } else {
                    unless ($sth = $self->{'dbh'}->prepare($query)) {
                        Sympa::Log::Syslog::do_log(
                            'err',
                            'Unable to prepare SQL statement : %s',
                            $self->{'dbh'}->errstr
                        );
                        return undef;
                    }
                }
            }

            ## bind parameters with special types
            ## this may be done only once when handle is prepared.
            foreach my $i (sort keys %types) {
                $sth->bind_param($i + 1, $params[$i], $types{$i});
            }

            $self->{'cached_prepared_statements'}{$query} = $sth;
            unless ($sth->execute(@params)) {
                Sympa::Log::Syslog::do_log('err',
                    'Unable to execute SQL statement "%s" : %s',
                    $query, $self->{'dbh'}->errstr);
                return undef;
            }
        }
    }

    return $sth;
}

sub prepare_query_log_values {
    my $self = shift;
    my @result;
    foreach my $value (@_) {
        my $cropped = substr($value, 0, 100);
        if ($cropped ne $value) {
            $cropped .= "...[shortened]";
        }
        push @result, $cropped;
    }
    return \@result;
}

sub fetch {
    my $self = shift;

    ## call to fetchrow_arrayref() uses eval to set a timeout
    ## this prevents one data source to make the process wait forever if
    ## SELECT does not respond
    my $array_of_users;
    $array_of_users = eval {
        local $SIG{ALRM} = sub { die "TIMEOUT\n" };    # NB: \n required
        alarm $self->{'fetch_timeout'};

        ## Inner eval just in case the fetchall_arrayref call would die, thus
        ## leaving the alarm trigered
        my $status = eval { return $self->{'sth'}->fetchall_arrayref; };
        alarm 0;
        return $status;
    };
    if ($@ eq "TIMEOUT\n") {
        Sympa::Log::Syslog::do_log('err',
            'Fetch timeout on remote SQL database');
        return undef;
    } elsif ($@) {
        Sympa::Log::Syslog::do_log('err',
            'Fetch failed on remote SQL database');
        return undef;
    }

    return $array_of_users;
}

sub disconnect {
    my $self = shift;
    $self->{'sth'}->finish if $self->{'sth'};
    if ($self->{'dbh'}) { $self->{'dbh'}->disconnect; }
    delete $db_connections{$self->{'connect_string'}};
}

sub create_db {
    Sympa::Log::Syslog::do_log('debug3', '()');
    return 1;
}

sub ping {
    my $self = shift;
    return $self->{'dbh'}->ping;
}

sub quote {
    my ($self, $string, $datatype) = @_;
    return $self->{'dbh'}->quote($string, $datatype);
}

sub set_fetch_timeout {
    my ($self, $timeout) = @_;
    return $self->{'fetch_timeout'} = $timeout;
}

## Returns a character string corresponding to the expression to use in
## a read query (e.g. SELECT) for the field given as argument.
## This sub takes a single argument: the name of the field to be used in
## the query.
##
sub get_canonical_write_date {
    my $self  = shift;
    my $field = shift;
    return $self->get_formatted_date({'mode' => 'write', 'target' => $field});
}

## Returns a character string corresponding to the expression to use in
## a write query (e.g. UPDATE or INSERT) for the value given as argument.
## This sub takes a single argument: the value of the date to be used in
## the query.
##
sub get_canonical_read_date {
    my $self  = shift;
    my $value = shift;
    return $self->get_formatted_date({'mode' => 'read', 'target' => $value});
}

1;
