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

Sympa::SDM - Database functions

=head1 DESCRIPTION

This module provides functions relative to the access and maintenance of the
Sympa database.

=cut

package Sympa::SDM;

use strict;

use English qw(-no_match_vars);

use Sympa::Configuration;
use Sympa::Datasource::SQL;
use Sympa::DatabaseDescription;
use Sympa::Log::Syslog;

# db structure description has moved in Sympa/Constant.pm
my %db_struct = Sympa::DatabaseDescription::db_struct();

my $db_source;
our $use_db;

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
	$db_conf->{'reconnect_options'} = {'keep_trying'=>($option ne 'just_try' && ( !$db_source->{'connected'} && !$ENV{'HTTP_HOST'})),
		'warn'=>1 };
	$db_conf->{domain} = $Sympa::Configuration::Conf{'domain'};
	my $db_source = Sympa::Datasource::SQL->create(%$db_conf);
	unless ($db_source) {
		Sympa::Log::Syslog::do_log('err', 'Unable to create Sympa::Datasource::SQL object');
		return undef;
	}
	## Used to check that connecting to the Sympa database works and the
	## Sympa::Datasource::SQL object is created.
	$use_db = 1;

	# Just in case, we connect to the database here. Probably not necessary.
	unless ( $db_source->{'dbh'} = $db_source->connect()) {
		Sympa::Log::Syslog::do_log('err', 'Unable to connect to the Sympa database');
		return undef;
	}
	Sympa::Log::Syslog::do_log('debug2','Connected to Database %s',Sympa::Configuration::get_robot_conf('*','db_name'));

	return 1;
}

=item probe_db()

FIXME.

=cut

sub probe_db {
	my ($db_source) = @_;
	Sympa::Log::Syslog::do_log('debug3', 'Checking database structure');

	my @report;

	my @current_tables = $db_source->get_tables();
	my %current_structure;
	my $target_structure = $db_struct{'mysql'};

	my $db_type = $db_source->get_type();
	my $db_name = $db_source->get_name();

	## Check required tables
	foreach my $t1 (keys %{$target_structure}) {
		my $found;
		foreach my $t2 (@current_tables) {
			$found = 1 if ($t1 eq $t2) ;
		}
		unless ($found) {
			if (my $rep = $db_source->add_table('table'=>$t1)) {
				push @report, $rep;
				Sympa::Log::Syslog::do_log('notice', 'Table %s created in database %s', $t1, $db_name);
				push @current_tables, $t1;
				$current_structure{$t1} = {};
			}
		}
	}
	## Get fields
	foreach my $t (@current_tables) {
		$current_structure{$t} = $db_source->get_fields('table'=>$t);
	}

	if (!%current_structure) {
		Sympa::Log::Syslog::do_log('err',"Could not check the database structure. consider verify it manually before launching Sympa.");
		return undef;
	}

	## Check tables structure if we could get it
	## Only performed with mysql , Pg and SQLite
	foreach my $t (keys %{$target_structure}) {
		unless ($current_structure{$t}) {
			Sympa::Log::Syslog::do_log('err', "Table '%s' not found in database '%s' ; you should create it with create_db.%s script", $t, $db_name, $db_type);
			return undef;
		}
		unless (_check_fields('table' => $t,'report' => \@report,'real_struct' => \%current_structure)) {
			Sympa::Log::Syslog::do_log('err', "Unable to check the validity of fields definition for table %s. Aborting.", $t);
			return undef;
		}

		## Remove temporary DB field
		if ($current_structure{$t}{'temporary'}) {
			$db_source->delete_field(
				'table' => $t,
				'field' => 'temporary',
			);
			delete $current_structure{$t}{'temporary'};
		}

		if ($db_type eq 'mysql'||$db_type eq 'Pg'||$db_type eq 'SQLite') {
			## Check that primary key has the right structure.
			unless (_check_primary_key('table' => $t,'report' => \@report)) {
				Sympa::Log::Syslog::do_log('err', "Unable to check the valifity of primary key for table %s. Aborting.", $t);
				return undef;
			}

			unless (_check_indexes('table' => $t,'report' => \@report)) {
				Sympa::Log::Syslog::do_log('err', "Unable to check the valifity of indexes for table %s. Aborting.", $t);
				return undef;
			}

		}
	}
	# add autoincrement option if needed
	foreach my $table (keys %{$target_structure}) {
		Sympa::Log::Syslog::do_log('notice',"Checking autoincrement for table $table");
		foreach my $field (keys %{$target_structure->{$table}{'fields'}}) {
			next unless $target_structure->{$table}{'fields'}{$field}{'autoincrement'};
			next if $db_source->is_autoinc(
				'table' => $table,
				'field' => $field
			);
			my $result = $db_source->set_autoinc(
				'table'      => $table,
				'field'      => $field,
				'field_type' => $target_structure->{$table}{'fields'}{$field});
			if ($result) {
				Sympa::Log::Syslog::do_log('notice',"Setting table $table field $field as autoincrement");
			} else {
				Sympa::Log::Syslog::do_log('err',"Could not set table $table field $field as autoincrement");
				return undef;
			}
		}
	}

	## Used by List subroutines to check that the DB is available
	$use_db = 1;
	
	return \@report;
}

sub _check_fields {
	my (%params) = @_;

	my $t = $params{'table'};
	my %real_struct = %{$params{'real_struct'}};
	my $report_ref = $params{'report'};
	my $db_type = Sympa::Configuration::get_robot_conf('*','db_type');

	foreach my $f (sort keys %{$db_struct{$db_type}{$t}}) {
		unless ($real_struct{$t}{$f}) {
			push @{$report_ref}, sprintf("Field '%s' (table '%s' ; database '%s') was NOT found. Attempting to add it...", $f, $t, Sympa::Configuration::get_robot_conf('*','db_name'));
			Sympa::Log::Syslog::do_log('info', "Field '%s' (table '%s' ; database '%s') was NOT found. Attempting to add it...", $f, $t, Sympa::Configuration::get_robot_conf('*','db_name'));

			my $rep = $db_source->add_field(
				'table'   => $t,
				'field'   => $f,
				'type'    => $db_struct{$db_type}{$t}{$f},
				'notnull' => $db_struct{$db_type}{$t}{fields}{$f}{'not_null'},
				'autoinc' => $db_struct{$db_type}{$t}{fields}{$f}{autoincrement},
				'primary' => $db_struct{$db_type}{$t}{fields}{$f}{autoincrement}
			);
			if ($rep) {
				push @{$report_ref}, $rep;

			} else {
				Sympa::Log::Syslog::do_log('err', 'Addition of fields in database failed. Aborting.');
				return undef;
			}
			next;
		}

		## Change DB types if different and if update_db_types enabled
		if (Sympa::Configuration::get_robot_conf('*','update_db_field_types') eq 'auto' && $db_type ne 'SQLite') {
			unless (_check_db_field_type(effective_format => $real_struct{$t}{$f},
					required_format => $db_struct{$db_type}{$t}{$f})) {
				push @{$report_ref}, sprintf("Field '%s'  (table '%s' ; database '%s') does NOT have awaited type (%s). Attempting to change it...",$f, $t, Sympa::Configuration::get_robot_conf('*','db_name'), $db_struct{$db_type}{$t}{$f});

				Sympa::Log::Syslog::do_log('notice', "Field '%s'  (table '%s' ; database '%s') does NOT have awaited type (%s) where type in database seems to be (%s). Attempting to change it...",$f, $t, Sympa::Configuration::get_robot_conf('*','db_name'), $db_struct{$db_type}{$t}{$f},$real_struct{$t}{$f});

				my $rep = $db_source->update_field(
					'table'   => $t,
					'field'   => $f,
					'type'    => $db_struct{$db_type}{$t}{$f},
					'notnull' => $db_struct{$db_type}{$t}{fields}{$f}{'not_null'},
				);
				if ($rep) {
					push @{$report_ref}, $rep;
				} else {
					Sympa::Log::Syslog::do_log('err', 'Fields update in database failed. Aborting.');
					return undef;
				}
			}
		} else {
			unless ($real_struct{$t}{$f} eq $db_struct{$db_type}{$t}{$f}) {
				Sympa::Log::Syslog::do_log('err', 'Field \'%s\'  (table \'%s\' ; database \'%s\') does NOT have awaited type (%s).', $f, $t, Sympa::Configuration::get_robot_conf('*','db_name'), $db_struct{$db_type}{$t}{$f});
				Sympa::Log::Syslog::do_log('err', 'Sympa\'s database structure may have change since last update ; please check RELEASE_NOTES');
				return undef;
			}
		}
	}
	return 1;
}

sub _check_primary_key {
	my (%params) = @_;

	my $table  = $params{'table'};
	my $report = $params{'report'};
	Sympa::Log::Syslog::do_log('debug','Checking primary key for table %s',$table);

	my @key_fields;
	foreach my $field (keys %{$db_struct{mysql}{$table}{fields}}) {
		next unless $db_struct{mysql}{$table}{fields}{$field}{primary};
		push @key_fields, $field;
	}

	my $key_as_string = "$table [" . join(',', @key_fields) . "]";
	Sympa::Log::Syslog::do_log('debug','Checking primary keys for table %s expected_keys %s',$table,$key_as_string );

	my $should_update = $db_source->check_key(
		table         => $table,
		key_name      => 'primary',
		expected_keys => \@key_fields
	);

	if ($should_update){
		if ($should_update->{'empty'}) {
			Sympa::Log::Syslog::do_log('notice',"Primary key %s is missing. Adding it.",$key_as_string);
			# Add primary key
			my $result = $db_source->set_primary_key(
				table  => $table,
				fields =>\@key_fields
			);
			push @{$report}, $result if $result;
		} elsif($should_update->{'existing_key_correct'}) {
			Sympa::Log::Syslog::do_log('debug',"Existing key correct (%s) nothing to change",$key_as_string);
		} else {
			my $result;

			# drop previous primary key
			$result = $db_source->unset_primary_key(table => $table);
			push @{$report}, $result if $result;

			# Add primary key
			$result = $db_source->set_primary_key(
				table  => $table,
				fields => \@key_fields
			);
			push @{$report}, $result if $result;
		}
	} else {
		Sympa::Log::Syslog::do_log('err','Unable to evaluate table %s primary key. Trying to reset primary key anyway.',$table);
		my $result;

		# drop previous primary key
		$result = $db_source->unset_primary_key(table => $table);
		push @{$report}, $result if $result;

		# Add primary key
		$result = $db_source->set_primary_key(
			table  => $table,
			fields => \@key_fields
		);
		push @{$report}, $result if $result;
	}
	return 1;
}

sub _check_indexes {
	my (%params) = @_;

	my $t = $params{'table'};
	my $report_ref = $params{'report'};
	Sympa::Log::Syslog::do_log('debug','Checking indexes for table %s',$t);
	## drop previous index if this index is not a primary key and was defined by a previous Sympa version
	my %index_columns = %{$db_source->get_indexes('table' => $t)};
	foreach my $idx ( keys %index_columns ) {
		Sympa::Log::Syslog::do_log('debug','Found index %s',$idx);
		## Remove the index if obsolete.

		foreach my $known_index (@Sympa::DatabaseDescription::former_indexes) {
			if ( $idx eq $known_index ) {
				Sympa::Log::Syslog::do_log('notice','Removing obsolete index %s',$idx);
				if (my $rep = $db_source->unset_index('table'=>$t,'index'=>$idx)) {
					push @{$report_ref}, $rep;
				}
				last;
			}
		}
	}

	## Create required indexes
	foreach my $idx (keys %{$Sympa::DatabaseDescription::indexes{$t}}){
		## Add indexes
		unless ($index_columns{$idx}) {
			Sympa::Log::Syslog::do_log('notice','Index %s on table %s does not exist. Adding it.',$idx,$t);
			if (my $rep = $db_source->set_index('table'=>$t, 'index_name'=> $idx, 'fields'=>$Sympa::DatabaseDescription::indexes{$t}{$idx})) {
				push @{$report_ref}, $rep;
			}
		}
		my $index_check = $db_source->check_key('table'=>$t,'key_name'=>$idx,'expected_keys'=>$Sympa::DatabaseDescription::indexes{$t}{$idx});
		if ($index_check){
			my $list_of_fields = join ',',@{$Sympa::DatabaseDescription::indexes{$t}{$idx}};
			my $index_as_string = "$idx: $t [$list_of_fields]";
			if ($index_check->{'empty'}) {
				## Add index
				my $rep = undef;
				Sympa::Log::Syslog::do_log('notice',"Index %s is missing. Adding it.",$index_as_string);
				if ($rep = $db_source->set_index('table'=>$t, 'index_name'=> $idx, 'fields'=>$Sympa::DatabaseDescription::indexes{$t}{$idx})) {
					push @{$report_ref}, $rep;
				}
			} elsif($index_check->{'existing_key_correct'}) {
				Sympa::Log::Syslog::do_log('debug',"Existing index correct (%s) nothing to change",$index_as_string);
			} else {
				## drop previous index
				Sympa::Log::Syslog::do_log('notice',"Index %s has not the right structure. Changing it.",$index_as_string);
				my $rep = undef;
				if ($rep = $db_source->unset_index('table'=>$t, 'index'=> $idx)) {
					push @{$report_ref}, $rep;
				}
				## Add index
				$rep = undef;
				if ($rep = $db_source->set_index('table'=>$t, 'index_name'=> $idx, 'fields'=>$Sympa::DatabaseDescription::indexes{$t}{$idx})) {
					push @{$report_ref}, $rep;
				}
			}
		} else {
			Sympa::Log::Syslog::do_log('err','Unable to evaluate index %s in table %s. Trying to reset index anyway.',$t,$idx);
			## drop previous index
			my $rep = undef;
			if ($rep = $db_source->unset_index('table'=>$t, 'index'=> $idx)) {
				push @{$report_ref}, $rep;
			}
			## Add index
			$rep = undef;
			if ($rep = $db_source->set_index('table'=>$t, 'index_name'=> $idx,'fields'=>$Sympa::DatabaseDescription::indexes{$t}{$idx})) {
				push @{$report_ref}, $rep;
			}
		}
	}
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

	if ($params{'required_format'} =~ /^(\w+)(\((\d+)\))?$/) {
		($required_type, $required_size) = ($1, $3);
	}

	if ($params{'effective_format'} =~ /^(\w+)(\((\d+)\))?$/) {
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
