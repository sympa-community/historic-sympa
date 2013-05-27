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

	my $db_type = $db_source->get_type();
	my $db_name = $db_source->get_name();

	my @current_tables = $db_source->get_tables();
	my %current_structure;
	my $target_structure = Sympa::DatabaseDescription::db_struct()->{$db_type};

	## Check required tables
	foreach my $table (keys %{$target_structure}) {
		next if Sympa::Tools::Data::any { $table eq $_ }
			@current_tables;

		my $result = $db_source->add_table(table => $table);
		if ($result) {
			push @report, $result;
			Sympa::Log::Syslog::do_log('notice', 'Table %s created in database %s', $table, $db_name);
			push @current_tables, $table;
			$current_structure{$table} = {};
		}
	}

	## Get fields
	foreach my $table (@current_tables) {
		$current_structure{$table} = $db_source->get_fields(table => $table);
	}

	if (!%current_structure) {
		Sympa::Log::Syslog::do_log('err',"Could not check the database structure. consider verify it manually before launching Sympa.");
		return undef;
	}

	## Check tables structure if we could get it
	## Only performed with mysql , Pg and SQLite
	foreach my $table (keys %{$target_structure}) {
		unless ($current_structure{$table}) {
			Sympa::Log::Syslog::do_log('err', "Table '%s' not found in database '%s' ; you should create it with create_db.%s script", $table, $db_name, $db_type);
			return undef;
		}

		my $fields_result = _check_fields(
			source            => $db_source,
			table             => $table,
			report            => \@report,
			current_structure => \%current_structure,
			target_structure  => $target_structure
		);
		unless ($fields_result) {
			Sympa::Log::Syslog::do_log('err', "Unable to check the validity of fields definition for table %s. Aborting.", $table);
			return undef;
		}

		## Remove temporary DB field
		if ($current_structure{$table}{'temporary'}) {
			$db_source->delete_field(
				table => $table,
				field => 'temporary',
			);
			delete $current_structure{$table}{'temporary'};
		}

		if ($db_type eq 'mysql'||$db_type eq 'Pg'||$db_type eq 'SQLite') {
			## Check that primary key has the right structure.
			my $primary_key_result = _check_primary_key(
				source           => $db_source,
				table            => $table,
				report           => \@report,
				target_structure => $target_structure
			);
			unless ($primary_key_result) {
				Sympa::Log::Syslog::do_log('err', "Unable to check the valifity of primary key for table %s. Aborting.", $table);
				return undef;
			}

			my $indexes_result = _check_indexes(
				source => $db_source,
				table  => $table,
				report => \@report
			);
			unless ($indexes_result) {
				Sympa::Log::Syslog::do_log('err', "Unable to check the valifity of indexes for table %s. Aborting.", $table);
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
				table => $table,
				field => $field
			);
			my $result = $db_source->set_autoinc(
				table      => $table,
				field      => $field,
				field_type => $target_structure->{$table}{'fields'}{$field});
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

	my $db_source = $params{'source'};
	my $table     = $params{'table'};
	my $report    = $params{'report'};
	my $current_structure = $params{'current_structure'};
	my $target_structure = $params{'target_structure'};

	my $db_type = $db_source->get_type();
	my $db_name = $db_source->get_name();

	foreach my $field (sort keys %{$target_structure->{$table}}) {
		unless ($current_structure->{$table}{$field}) {
			push @{$report}, sprintf("Field '%s' (table '%s' ; database '%s') was NOT found. Attempting to add it...", $field, $table, $db_name);
			Sympa::Log::Syslog::do_log('info', "Field '%s' (table '%s' ; database '%s') was NOT found. Attempting to add it...", $field, $table, $db_name);

			my $rep = $db_source->add_field(
				'table'   => $table,
				'field'   => $field,
				'type'    => $target_structure->{$table}{$field},
				'notnull' => $target_structure->{$table}{fields}{$field}{'not_null'},
				'autoinc' => $target_structure->{$table}{fields}{$field}{autoincrement},
				'primary' => $target_structure->{$table}{fields}{$field}{autoincrement}
			);
			if ($rep) {
				push @{$report}, $rep;

			} else {
				Sympa::Log::Syslog::do_log('err', 'Addition of fields in database failed. Aborting.');
				return undef;
			}
			next;
		}

		## Change DB types if different and if update_db_types enabled
		if (Sympa::Configuration::get_robot_conf('*','update_db_field_types') eq 'auto' && $db_type ne 'SQLite') {
			unless (_check_db_field_type(effective_format => $current_structure->{$table}{$field},
					required_format => $target_structure->{$table}{$field})) {
				push @{$report}, sprintf("Field '%s'  (table '%s' ; database '%s') does NOT have awaited type (%s). Attempting to change it...",$field, $table, $db_name, $target_structure->{$table}{$field});

				Sympa::Log::Syslog::do_log('notice', "Field '%s'  (table '%s' ; database '%s') does NOT have awaited type (%s) where type in database seems to be (%s). Attempting to change it...",$field, $table, $db_name, $target_structure->{$table}{$field},$current_structure->{$table}{$field});

				my $rep = $db_source->update_field(
					'table'   => $table,
					'field'   => $field,
					'type'    => $target_structure->{$table}{$field},
					'notnull' => $target_structure->{$table}{fields}{$field}{'not_null'},
				);
				if ($rep) {
					push @{$report}, $rep;
				} else {
					Sympa::Log::Syslog::do_log('err', 'Fields update in database failed. Aborting.');
					return undef;
				}
			}
		} else {
			unless ($current_structure->{$table}{$field} eq $target_structure->{$table}{$field}) {
				Sympa::Log::Syslog::do_log('err', 'Field \'%s\'  (table \'%s\' ; database \'%s\') does NOT have awaited type (%s).', $field, $table, $db_name, $target_structure->{$table}{$field});
				Sympa::Log::Syslog::do_log('err', 'Sympa\'s database structure may have change since last update ; please check RELEASE_NOTES');
				return undef;
			}
		}
	}
	return 1;
}

sub _check_primary_key {
	my (%params) = @_;

	my $db_source = $params{'source'};
	my $table     = $params{'table'};
	my $report    = $params{'report'};
	my $target_structure = $params{'target_structure'};
	Sympa::Log::Syslog::do_log('debug','Checking primary key for table %s',$table);

	my @key_fields;
	foreach my $field (keys %{$target_structure->{$table}{fields}}) {
		next unless $target_structure->{$table}{fields}{$field}{primary};
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

	my $db_source = $params{'source'};
	my $table     = $params{'table'};
	my $report    = $params{'report'};
	Sympa::Log::Syslog::do_log('debug','Checking indexes for table %s',$table);
	## drop previous index if this index is not a primary key and was defined by a previous Sympa version
	my %index_columns = %{$db_source->get_indexes('table' => $table)};
	foreach my $index ( keys %index_columns ) {
		Sympa::Log::Syslog::do_log('debug','Found index %s',$index);
		## Remove the index if obsolete.

		foreach my $known_index (@Sympa::DatabaseDescription::former_indexes) {
			if ( $index eq $known_index ) {
				Sympa::Log::Syslog::do_log('notice','Removing obsolete index %s',$index);
				if (my $rep = $db_source->unset_index('table'=>$table,'index'=>$index)) {
					push @{$report}, $rep;
				}
				last;
			}
		}
	}

	## Create required indexes
	foreach my $index (keys %{$Sympa::DatabaseDescription::indexes{$table}}){
		## Add indexes
		unless ($index_columns{$index}) {
			Sympa::Log::Syslog::do_log('notice','Index %s on table %s does not exist. Adding it.',$index,$table);
			if (my $rep = $db_source->set_index('table'=>$table, 'index_name'=> $index, 'fields'=>$Sympa::DatabaseDescription::indexes{$table}{$index})) {
				push @{$report}, $rep;
			}
		}
		my $index_check = $db_source->check_key('table'=>$table,'key_name'=>$index,'expected_keys'=>$Sympa::DatabaseDescription::indexes{$table}{$index});
		if ($index_check){
			my $list_of_fields = join ',',@{$Sympa::DatabaseDescription::indexes{$table}{$index}};
			my $index_as_string = "$index: $table [$list_of_fields]";
			if ($index_check->{'empty'}) {
				## Add index
				my $rep = undef;
				Sympa::Log::Syslog::do_log('notice',"Index %s is missing. Adding it.",$index_as_string);
				if ($rep = $db_source->set_index('table'=>$table, 'index_name'=> $index, 'fields'=>$Sympa::DatabaseDescription::indexes{$table}{$index})) {
					push @{$report}, $rep;
				}
			} elsif($index_check->{'existing_key_correct'}) {
				Sympa::Log::Syslog::do_log('debug',"Existing index correct (%s) nothing to change",$index_as_string);
			} else {
				## drop previous index
				Sympa::Log::Syslog::do_log('notice',"Index %s has not the right structure. Changing it.",$index_as_string);
				my $rep = undef;
				if ($rep = $db_source->unset_index('table'=>$table, 'index'=> $index)) {
					push @{$report}, $rep;
				}
				## Add index
				$rep = undef;
				if ($rep = $db_source->set_index('table'=>$table, 'index_name'=> $index, 'fields'=>$Sympa::DatabaseDescription::indexes{$table}{$index})) {
					push @{$report}, $rep;
				}
			}
		} else {
			Sympa::Log::Syslog::do_log('err','Unable to evaluate index %s in table %s. Trying to reset index anyway.',$table,$index);
			## drop previous index
			my $rep = undef;
			if ($rep = $db_source->unset_index('table'=>$table, 'index'=> $index)) {
				push @{$report}, $rep;
			}
			## Add index
			$rep = undef;
			if ($rep = $db_source->set_index('table'=>$table, 'index_name'=> $index,'fields'=>$Sympa::DatabaseDescription::indexes{$table}{$index})) {
				push @{$report}, $rep;
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
