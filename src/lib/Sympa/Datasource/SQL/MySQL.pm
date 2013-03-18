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

Sympa::Datasource::SQL::MySQL - MySQL data source object

=head1 DESCRIPTION

This class implements a MySQL data source.

=cut

package Sympa::Datasource::SQL::MySQL;

use strict;
use base qw(Sympa::Datasource::SQL);

use Sympa::Log;

sub new {
	my ($class, %params) = @_;

	return $class->SUPER::new(%params, db_type => 'mysql');
}

sub build_connect_string {
	my ($self) = @_;

	$self->{'connect_string'} =
		"DBI:$self->{'db_type'}:$self->{'db_name'}:$self->{'db_host'}";
}

sub get_substring_clause {
	my ($self, $params) = @_;

	return sprintf
		"REVERSE(SUBSTRING(%s FROM position('%s' IN %s) FOR %s))",
		$params->{'source_field'},
		$params->{'separator'},
		$params->{'source_field'},
		$params->{'substring_length'};
}

sub get_limit_clause {
	my ($self, $params) = @_;

	if ($params->{'offset'}) {
		return sprintf "LIMIT %s,%s",
			$params->{'offset'},
			$params->{'rows_count'};
	} else {
		return sprintf "LIMIT %s",
			$params->{'rows_count'};
	}
}

sub get_formatted_date {
	my ($self, $params) = @_;

	my $mode = lc($params->{'mode'});
	if ($mode eq 'read') {
		return sprintf 'UNIX_TIMESTAMP(%s)',$params->{'target'};
	} elsif ($mode eq 'write') {
		return sprintf 'FROM_UNIXTIME(%d)',$params->{'target'};
	} else {
		Sympa::Log::do_log('err',"Unknown date format mode %s", $params->{'mode'});
		return undef;
	}
}

sub is_autoinc {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Checking whether field %s.%s is autoincremental',$params->{'field'},$params->{'table'});

	my $sth = $self->do_query(
		"SHOW FIELDS FROM `%s` WHERE Extra='auto_increment' and Field = '%s'",
		$params->{'table'},
		$params->{'field'}
	);
	unless ($sth) {
		Sympa::Log::do_log('err','Unable to gather autoincrement field named %s for table %s',$params->{'field'},$params->{'table'});
		return undef;
	}
	my $row = $sth->fetchrow_hashref('NAME_lc') ;
	return ($row->{'field'} eq $params->{'field'});
}

sub set_autoinc {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Setting field %s.%s as autoincremental',$params->{'field'},$params->{'table'});

	my $field_type = defined ($params->{'field_type'}) ? $params->{'field_type'} : 'BIGINT( 20 )';
	my $sth = $self->do_query(
		"ALTER TABLE `%s` CHANGE `%s` `%s` %s NOT NULL AUTO_INCREMENT",
		$params->{'table'},
		$params->{'field'},
		$params->{'field'},
		$field_type
	);
	unless ($sth) {
		Sympa::Log::do_log('err','Unable to set field %s in table %s as autoincrement',$params->{'field'},$params->{'table'});
		return undef;
	}
	return 1;
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::do_log('debug','Retrieving all tables in database %s',$self->{'db_name'});
	my @tables = $self->{'dbh'}->tables();

	foreach my $table (@tables) {
		$table =~ s/^\`[^\`]+\`\.//; # drop db name prefix
		$table =~ s/^\`(.+)\`$/$1/;  # drop quotes
	}
	return \@tables;
}

sub add_table {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Adding table %s to database %s',$params->{'table'},$self->{'db_name'});

	my $sth = $self->do_query(
		"CREATE TABLE %s (temporary INT) DEFAULT CHARACTER SET utf8",
		$params->{'table'}
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not create table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	return sprintf "Table %s created in database %s", $params->{'table'}, $self->{'db_name'};
}

sub get_fields {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Getting fields list from table %s in database %s',$params->{'table'},$self->{'db_name'});
	my $sth = $self->do_query("SHOW FIELDS FROM %s",$params->{'table'});
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not get the list of fields from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}

	my %result;
	while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
		$result{$row->{'field'}} = $row->{'type'};
	}
	return \%result;
}

sub update_field {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Updating field %s in table %s (%s, %s)',$params->{'field'},$params->{'table'},$params->{'type'},$params->{'notnull'});
	my $options;
	if ($params->{'notnull'}) {
		$options .= ' NOT NULL ';
	}
	my $report = sprintf(
		"ALTER TABLE %s CHANGE %s %s %s %s",
		$params->{'table'},
		$params->{'field'},
		$params->{'field'},
		$params->{'type'},
		$options
	);
	Sympa::Log::do_log('notice', $report);

	my $sth = $self->do_query(
		"ALTER TABLE %s CHANGE %s %s %s %s",
		$params->{'table'},
		$params->{'field'},
		$params->{'field'},
		$params->{'type'},
		$options
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not change field \'%s\' in table\'%s\'.',$params->{'field'}, $params->{'table'});
		return undef;
	}
	$report .= sprintf(
		'\nField %s in table %s, structure updated',
		$params->{'field'},
		$params->{'table'}
	);
	Sympa::Log::do_log('info', $report);

	return $report;
}

sub add_field {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Adding field %s in table %s (%s, %s, %s, %s)',$params->{'field'},$params->{'table'},$params->{'type'},$params->{'notnull'},$params->{'autoinc'},$params->{'primary'});

	# specific issues:
	# - an auto column must be defined as primary key
	# - impossible to add more than one auto column

	my $options = join(' ',
		$params->{notnull} ? 'NOT NULL'       : (),
		$params->{autoinc} ? 'AUTO_INCREMENT' : (),
		$params->{primary} ? 'PRIMARY KEY'    : (),
	);

	my $sth = $self->do_query(
		"ALTER TABLE %s ADD %s %s %s",
		$params->{'table'},
		$params->{'field'},
		$params->{'type'},
		$options
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not add field %s to table %s in database %s', $params->{'field'}, $params->{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf(
		'Field %s added to table %s (options: %s)',
		$params->{'field'},
		$params->{'table'},
		$options
	);
	Sympa::Log::do_log('info', $report);

	return $report;
}

sub delete_field {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Deleting field %s from table %s',$params->{'field'},$params->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE %s DROP COLUMN `%s`",
		$params->{'table'},
		$params->{'field'}
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not delete field %s from table %s in database %s', $params->{'field'}, $params->{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf('Field %s removed from table %s', $params->{'field'}, $params->{'table'});
	Sympa::Log::do_log('info', 'Field %s removed from table %s', $params->{'field'}, $params->{'table'});

	return $report;
}

sub get_primary_key {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Getting primary key for table %s',$params->{'table'});

	my $sth = $self->do_query("SHOW COLUMNS FROM %s",$params->{'table'});
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not get field list from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}

	my %keys;
	my $test_request_result = $sth->fetchall_hashref('field');
	foreach my $scannedResult ( keys %$test_request_result ) {
		if ( $test_request_result->{$scannedResult}{'key'} eq "PRI" ) {
			$keys{$scannedResult} = 1;
		}
	}
	return \%keys;
}

sub unset_primary_key {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Removing primary key from table %s',$params->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE %s DROP PRIMARY KEY",
		$params->{'table'}
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not drop primary key from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params->{'table'}, PRIMARY KEY dropped";
	Sympa::Log::do_log('info', 'Table %s, PRIMARY KEY dropped', $params->{'table'});

	return $report;
}

sub set_primary_key {
	my ($self, $params) = @_;

	my $fields = join ',',@{$params->{'fields'}};
	Sympa::Log::do_log('debug','Setting primary key for table %s (%s)',$params->{'table'},$fields);

	my $sth = $self->do_query(
		"ALTER TABLE %s ADD PRIMARY KEY (%s)",
		$params->{'table'},
		$fields
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not set fields %s as primary key for table %s in database %s', $fields, $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params->{'table'}, PRIMARY KEY set on $fields";
	Sympa::Log::do_log('info', 'Table %s, PRIMARY KEY set on %s', $params->{'table'},$fields);
	return $report;
}

sub get_indexes {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Looking for indexes in %s',$params->{'table'});

	my $sth = $self->do_query("SHOW INDEX FROM %s",$params->{'table'});
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not get the list of indexes from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	my %indexes;
	while(my $row = $sth->fetchrow_hashref('NAME_lc')) {
		next if $row->{'key_name'} eq "PRIMARY";
		$indexes{$row->{'key_name'}}->{$row->{'column_name'}} = 1;
	}
	return \%indexes;
}

sub unset_index {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Removing index %s from table %s',$params->{'index'},$params->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE %s DROP INDEX %s",
		$params->{'table'},
		$params->{'index'}
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not drop index %s from table %s in database %s',$params->{'index'}, $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params->{'table'}, index $params->{'index'} dropped";
	Sympa::Log::do_log('info', 'Table %s, index %s dropped', $params->{'table'},$params->{'index'});

	return $report;
}

sub set_index {
	my ($self, $params) = @_;

	my $fields = join ',',@{$params->{'fields'}};
	Sympa::Log::do_log('debug', 'Setting index %s for table %s using fields %s', $params->{'index_name'},$params->{'table'}, $fields);

	my $sth = $self->do_query(
		"ALTER TABLE %s ADD INDEX %s (%s)",
		$params->{'table'},
		$params->{'index_name'},
		$fields
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not add index %s using field %s for table %s in database %s', $fields, $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params->{'table'}, index %s set using $fields";
	Sympa::Log::do_log('info', 'Table %s, index %s set using fields %s',$params->{'table'}, $params->{'index_name'}, $fields);
	return $report;
}

1;
