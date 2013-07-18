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

This class implements a mechanism to populate a mailing list subscribers from
an external SQL database.

=cut

package Sympa::Datasource::SQL;

use strict;
use base qw(Sympa::Datasource);

use Carp;
use English qw(-no_match_vars);
use DBI;

use Sympa::Log::Syslog;
use Sympa::Tools;
use Sympa::Tools::Data;

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

=item C<db_options> => FIXME

=back

Return value:

A new L<Sympa::Datasource::SQL> object, or I<undef> if something went wrong.

=cut

sub create {
	my ($class, %params) = @_;

	croak "missing db_type parameter" unless $params{db_type};
	croak "missing db_name parameter" unless $params{db_name};

	Sympa::Log::Syslog::do_log('debug',"Creating new SQLSource object for RDBMS '%s'",$params{db_type});

	my $db_type = lc($params{db_type});
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

=item C<db_options> => FIXME

=back

Return value:

A new L<Sympa::Datasource::SQL> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	croak "missing db_type parameter" unless $params{db_type};
	croak "missing db_name parameter" unless $params{db_name};

	my $self = {
		db_host     => $params{db_host},
		db_user     => $params{db_user},
		db_passwd   => $params{db_passwd},
		db_name     => $params{db_name},
		db_type     => $params{db_type},
		db_options  => $params{db_options},
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

A true value on success, I<undef> otherwise.

=cut

sub connect {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Creating connection to database %s',$self->{db_name});

	## Build connect_string
	my $connect_string = $self->get_connect_string();
	$connect_string .= ';'   . $self->{db_options} if $self->{db_options};
	$connect_string .= ';port=' . $self->{db_port} if $self->{db_port};
	$self->{connect_string} = $connect_string;

	## Set environment variables
	## Used by Oracle (ORACLE_HOME)
	if ($self->{db_env}) {
		foreach my $env (split /;/,$self->{db_env}) {
			my ($key, $value) = split /=/, $env;
			$ENV{$key} = $value if ($key);
		}
	}

	$self->{dbh} = eval {
		DBI->connect(
			$connect_string,
			$self->{db_user},
			$self->{db_passwd},
			{ PrintError => 0 }
		)
	} ;
	unless ($self->{dbh}) {
		Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s', $connect_string, $self->{db_user});
		return undef;
	}

	# Force field names to be lowercased
	$self->{dbh}{FetchHashKeyName} = 'NAME_lc';

	Sympa::Log::Syslog::do_log('debug','Connected to Database %s',$self->{db_name});
	return 1;
}

sub disconnect {
	my ($self) = @_;

	$self->{dbh}->disconnect() if $self->{dbh};
}

=item $source->get_query_handle($query)

Returns a query handle for the given query.

Parameters:

=over

=item string

The SQL query.

=back

Return value:

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub get_query_handle {
	my ($self, $query) = @_;

	return $self->{dbh}->prepare($query);
}

=back

=cut

1;
