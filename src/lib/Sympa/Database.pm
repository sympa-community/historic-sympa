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

Sympa::Database - Sympa database object

=head1 DESCRIPTION

This class implements the Sympa database.

=cut

package Sympa::Database;

use strict;

use Carp;
use English qw(-no_match_vars);

use Sympa::Configuration;
use Sympa::List;
use Sympa::Log::Syslog;

my $db_source;
our $use_db;

=head1 CLASS METHODS

=over

=over

=item Sympa::Database->create(%parameters)

Factory method to create a new L<Sympa::Database> object from a
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

A new L<Sympa::Database> object, or I<undef> if something went wrong.

=cut

sub create {
	my ($class, %params) = @_;

	croak "missing db_type parameter" unless $params{db_type};
	croak "missing db_name parameter" unless $params{db_name};

	Sympa::Log::Syslog::do_log('debug',"Creating new SQLSource object for RDBMS '%s'",$params{db_type});

	my $db_type = lc($params{db_type});
	my $subclass =
		$db_type eq 'mysql'  ? 'Sympa::Database::MySQL'      :
		$db_type eq 'sqlite' ? 'Sympa::Database::SQLite'     :
		$db_type eq 'pg'     ? 'Sympa::Database::PostgreSQL' :
		$db_type eq 'oracle' ? 'Sympa::Database::Oracle'     :
		$db_type eq 'sybase' ? 'Sympa::Database::Sybase'     :
		                       'Sympa::Database'             ;

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

=item Sympa::Database->new(%parameters)

Create a new L<Sympa::Database> object.

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

A new L<Sympa::Database> object, or I<undef> if something went wrong.

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

=head1 INSTANCE METHODS

=over

=item $database->connect()

Connect to a SQL database.

Parameters:

=over

=item C<keep_trying> => retry indefinitly in case of failure

=back

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
		if (!$params{keep_trying}) {
			Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s', $connect_string, $self->{db_user});
			return undef;
		}

		Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s, still trying...', $connect_string, $self->{db_user});

		# Loop until connect works
		my $sleep_delay = 60;
		while (1) {
			sleep $sleep_delay;
			eval {
				$self->{dbh} = DBI->connect(
					$connect_string,
					$self->{db_user},
					$self->{db_passwd},
					{ PrintError => 0 }
				)
			};
			last if $self->{dbh};
			$sleep_delay += 10;
		}
	}

	# Force field names to be lowercased
	$self->{dbh}{FetchHashKeyName} = 'NAME_lc';

	Sympa::Log::Syslog::do_log('debug','Connected to Database %s',$self->{db_name});
	return 1;
}

=over

=item $database->disconnect()

=cut

sub disconnect {
	my ($self) = @_;
	return $self->{source}->disconnect();
}

=head1 FUNCTIONS

=over

=item get_source()

Return data source.

=cut

sub get_source {
	return $db_source;
}

=item check_db_connect()

Just check if DB connection is ok

=cut

sub check_db_connect {

	#Sympa::Log::Syslog::do_log('debug2', 'Checking connection to the Sympa database');
	## Is the Database defined
	unless (Sympa::Configuration::get_robot_conf('*','db_name')) {
		Sympa::Log::Syslog::do_log('err', 'No db_name defined in configuration file');
		return undef;
	}

	unless ($db_source->{'dbh'} && $db_source->{'dbh'}->ping()) {
		unless (connect_sympa_database('just_try')) {
			Sympa::Log::Syslog::do_log('err', 'Failed to connect to database');
			return undef;
		}
	}

	return 1;
}

=item connect_sympa_database()

Connect to database.

=cut

sub connect_sympa_database {
	my ($option) = @_;

	Sympa::Log::Syslog::do_log('debug', 'Connecting to Sympa database');

	## We keep trying to connect if this is the first attempt
	## Unless in a web context, because we can't afford long response time on the web interface
	my $db_conf = Sympa::Configuration::get_parameters_group('*','Database related');
	my $db_source = Sympa::Database->create(%$db_conf);
	unless ($db_source) {
		Sympa::Log::Syslog::do_log('err', 'Unable to create Sympa::Database object');
		return undef;
	}

	# Just in case, we connect to the database here. Probably not necessary.
	my $result = $db_source->connect(
		'keep_trying' =>
			($option ne 'just_try' && !$ENV{'HTTP_HOST'} ? 1 : 0)
	);
	unless ($result) {
		Sympa::Log::Syslog::do_log('err', 'Unable to connect to the Sympa database');
		Sympa::List::send_notify_to_listmaster(
			'no_db', $Sympa::Configuration::Conf{'domain'}, {}
		);
		return undef;
	}
	Sympa::Log::Syslog::do_log('debug2','Connected to Database %s',Sympa::Configuration::get_robot_conf('*','db_name'));

	## Used to check that connecting to the Sympa database works and the
	## Sympa::Database object is created.
	$use_db = 1;

	return 1;
}

=item data_structure_uptodate($version)

Check if data structures are uptodate.

If not, no operation should be performed before the upgrade process is run

=cut

sub data_structure_uptodate {
	my ($version) = @_;

	my $version_file = "Sympa::Configuration::get_robot_conf('*','etc')/data_structure.version";
	my $data_structure_version;

	if (-f $version_file) {
		unless (open VFILE, $version_file) {
			Sympa::Log::Syslog::do_log('err', "Unable to open %s : %s", $version_file, $ERRNO);
			return undef;
		}
		while (<VFILE>) {
			next if /^\s*$/;
			next if /^\s*\#/;
			chomp;
			$data_structure_version = $_;
			last;
		}
		close VFILE;
	}

	if (defined $data_structure_version &&
		$data_structure_version ne $version) {
		Sympa::Log::Syslog::do_log('err', "Data structure (%s) is not uptodate for current release (%s)", $data_structure_version, $version);
		return 0;
	}

	return 1;
}

# _check_db_field_type(%parameters)
# Compare required DB field type
# Parameters:
# required_format> => string
# effective_format> => string
# Return value:
# 1 if field type is appropriate AND size >= required size
sub _check_db_field_type {
	my (%params) = @_;

	my ($required_type, $required_size, $effective_type, $effective_size);

	if ($params{required_format} =~ /^(\w+)(\((\d+)\))?$/) {
		($required_type, $required_size) = ($1, $3);
	}

	if ($params{effective_format} =~ /^(\w+)(\((\d+)\))?$/) {
		($effective_type, $effective_size) = ($1, $3);
	}

	if (($effective_type eq $required_type) && ($effective_size >= $required_size)) {
		return 1;
	}

	return 0;
}

=back

=cut

1;
