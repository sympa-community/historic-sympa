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
# along with this program; if not, write to the Free Softwarec
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Datasource::SQL::Sybase - Sybase data source object

=head1 DESCRIPTION

This class implements a Sybase data source.

=cut

package Sympa::Datasource::SQL::Sybase;

use strict;
use base qw(Sympa::Datasource::SQL::Default);

use Data::Dumper;

use Sympa::Log;

our %date_format = (
	'read' => {
		'Sybase' => 'datediff(second, \'01/01/1970\',%s)',
	},
	'write' => {
		'Sybase' => 'dateadd(second,%s,\'01/01/1970\')',
	}
);

sub build_connect_string{
	my ($self) = @_;

	$self->{'connect_string'} =
		"DBI:Sybase:database=$self->{'db_name'};server=$self->{'db_host'}";
}

sub get_substring_clause {
	my ($self, $param) = @_;

	return sprintf
		"substring(%s,charindex('%s',%s)+1,%s)",
		$param->{'source_field'},
		$param->{'separator'},
		$param->{'source_field'},
		$param->{'substring_length'};
}

sub get_limit_clause {
	my ($self, $param) = @_;

	return "";
}

sub get_formatted_date {
	my ($self, $param) = @_;

	if (lc($param->{'mode'}) eq 'read') {
		return sprintf 'UNIX_TIMESTAMP(%s)',$param->{'target'};
	}elsif(lc($param->{'mode'}) eq 'write') {
		return sprintf 'FROM_UNIXTIME(%d)',$param->{'target'};
	}else {
		&Sympa::Log::do_log('err',"Unknown date format mode %s", $param->{'mode'});
		return undef;
	}
}

sub is_autoinc {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Checking whether field %s.%s is autoincremental',$param->{'field'},$param->{'table'});
	my $sth;
	unless ($sth = $self->do_query("SHOW FIELDS FROM `%s` WHERE Extra ='auto_increment' and Field = '%s'",$param->{'table'},$param->{'field'})) {
		&Sympa::Log::do_log('err','Unable to gather autoincrement field named %s for table %s',$param->{'field'},$param->{'table'});
		return undef;
	}
	my $ref = $sth->fetchrow_hashref('NAME_lc') ;
	return ($ref->{'field'} eq $param->{'field'});
}

sub set_autoinc {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Setting field %s.%s as autoincremental',$param->{'field'},$param->{'table'});
	unless ($self->do_query("ALTER TABLE `%s` CHANGE `%s` `%s` BIGINT( 20 ) NOT NULL AUTO_INCREMENT",$param->{'table'},$param->{'field'},$param->{'field'})) {
		&Sympa::Log::do_log('err','Unable to set field %s in table %s as autoincrement',$param->{'field'},$param->{'table'});
		return undef;
	}
	return 1;
}

sub get_tables {
	my ($self) = @_;

	my @raw_tables;
	my $sth;
	unless ($sth = $self->do_query("SELECT name FROM %s..sysobjects WHERE type='U'",$self->{'db_name'})) {
		&Sympa::Log::do_log('err','Unable to retrieve the list of tables from database %s',$self->{'db_name'});
		return undef;
	}
	while (my $table= $sth->fetchrow()) {
		push @raw_tables, lc ($table);
	}
	return \@raw_tables;
}

sub add_table {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Adding table %s to database %s',$param->{'table'},$self->{'db_name'});
	unless ($self->do_query("CREATE TABLE %s (temporary INT)",$param->{'table'})) {
		&Sympa::Log::do_log('err', 'Could not create table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	return sprintf "Table %s created in database %s", $param->{'table'}, $self->{'db_name'};
}

sub get_fields {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Getting fields list from table %s in database %s',$param->{'table'},$self->{'db_name'});
	my $sth;
	my %result;
	unless ($sth = $self->do_query("SHOW FIELDS FROM %s",$param->{'table'})) {
		&Sympa::Log::do_log('err', 'Could not get the list of fields from table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
		$result{$ref->{'field'}} = $ref->{'type'};
	}
	return \%result;
}

sub update_field {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Updating field %s in table %s (%s, %s)',$param->{'field'},$param->{'table'},$param->{'type'},$param->{'notnull'});
	my $options;
	if ($param->{'notnull'}) {
		$options .= ' NOT NULL ';
	}
	my $report = sprintf("ALTER TABLE %s CHANGE %s %s %s %s",$param->{'table'},$param->{'field'},$param->{'field'},$param->{'type'},$options);
	&Sympa::Log::do_log('notice', "ALTER TABLE %s CHANGE %s %s %s %s",$param->{'table'},$param->{'field'},$param->{'field'},$param->{'type'},$options);
	unless ($self->do_query("ALTER TABLE %s CHANGE %s %s %s %s",$param->{'table'},$param->{'field'},$param->{'field'},$param->{'type'},$options)) {
		&Sympa::Log::do_log('err', 'Could not change field \'%s\' in table\'%s\'.',$param->{'field'}, $param->{'table'});
		return undef;
	}
	$report .= sprintf('\nField %s in table %s, structure updated', $param->{'field'}, $param->{'table'});
	&Sympa::Log::do_log('info', 'Field %s in table %s, structure updated', $param->{'field'}, $param->{'table'});
	return $report;
}

sub add_field {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Adding field %s in table %s (%s, %s, %s, %s)',$param->{'field'},$param->{'table'},$param->{'type'},$param->{'notnull'},$param->{'autoinc'},$param->{'primary'});
	my $options;
	# To prevent "Cannot add a NOT NULL column with default value NULL" errors
	if ($param->{'notnull'}) {
		$options .= 'NOT NULL ';
	}
	if ( $param->{'autoinc'}) {
		$options .= ' AUTO_INCREMENT ';
	}
	if ( $param->{'primary'}) {
		$options .= ' PRIMARY KEY ';
	}
	unless ($self->do_query("ALTER TABLE %s ADD %s %s %s",$param->{'table'},$param->{'field'},$param->{'type'},$options)) {
		&Sympa::Log::do_log('err', 'Could not add field %s to table %s in database %s', $param->{'field'}, $param->{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf('Field %s added to table %s (options : %s)', $param->{'field'}, $param->{'table'}, $options);
	&Sympa::Log::do_log('info', 'Field %s added to table %s  (options : %s)', $param->{'field'}, $param->{'table'}, $options);

	return $report;
}

sub delete_field {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Deleting field %s from table %s',$param->{'field'},$param->{'table'});

	unless ($self->do_query("ALTER TABLE %s DROP COLUMN `%s`",$param->{'table'},$param->{'field'})) {
		&Sympa::Log::do_log('err', 'Could not delete field %s from table %s in database %s', $param->{'field'}, $param->{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf('Field %s removed from table %s', $param->{'field'}, $param->{'table'});
	&Sympa::Log::do_log('info', 'Field %s removed from table %s', $param->{'field'}, $param->{'table'});

	return $report;
}

sub get_primary_key {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Getting primary key for table %s',$param->{'table'});

	my %found_keys;
	my $sth;
	unless ($sth = $self->do_query("SHOW COLUMNS FROM %s",$param->{'table'})) {
		&Sympa::Log::do_log('err', 'Could not get field list from table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}

	my $test_request_result = $sth->fetchall_hashref('field');
	foreach my $scannedResult ( keys %$test_request_result ) {
		if ( $test_request_result->{$scannedResult}{'key'} eq "PRI" ) {
			$found_keys{$scannedResult} = 1;
		}
	}
	return \%found_keys;
}

sub unset_primary_key {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Removing primary key from table %s',$param->{'table'});

	my $sth;
	unless ($sth = $self->do_query("ALTER TABLE %s DROP PRIMARY KEY",$param->{'table'})) {
		&Sympa::Log::do_log('err', 'Could not drop primary key from table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, PRIMARY KEY dropped";
	&Sympa::Log::do_log('info', 'Table %s, PRIMARY KEY dropped', $param->{'table'});

	return $report;
}

sub set_primary_key {
	my ($self, $param) = @_;

	my $sth;
	my $fields = join ',',@{$param->{'fields'}};
	&Sympa::Log::do_log('debug','Setting primary key for table %s (%s)',$param->{'table'},$fields);
	unless ($sth = $self->do_query("ALTER TABLE %s ADD PRIMARY KEY (%s)",$param->{'table'}, $fields)) {
		&Sympa::Log::do_log('err', 'Could not set fields %s as primary key for table %s in database %s', $fields, $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, PRIMARY KEY set on $fields";
	&Sympa::Log::do_log('info', 'Table %s, PRIMARY KEY set on %s', $param->{'table'},$fields);
	return $report;
}

sub get_indexes {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Looking for indexes in %s',$param->{'table'});

	my %found_indexes;
	my $sth;
	unless ($sth = $self->do_query("SHOW INDEX FROM %s",$param->{'table'})) {
		&Sympa::Log::do_log('err', 'Could not get the list of indexes from table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $index_part;
	while($index_part = $sth->fetchrow_hashref('NAME_lc')) {
		if ( $index_part->{'key_name'} ne "PRIMARY" ) {
			my $index_name = $index_part->{'key_name'};
			my $field_name = $index_part->{'column_name'};
			$found_indexes{$index_name}{$field_name} = 1;
		}
	}
	open TMP, ">>/tmp/toto"; print TMP &Dumper(\%found_indexes); close TMP;
return \%found_indexes;
}

sub unset_index {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Removing index %s from table %s',$param->{'index'},$param->{'table'});

	my $sth;
	unless ($sth = $self->do_query("ALTER TABLE %s DROP INDEX %s",$param->{'table'},$param->{'index'})) {
		&Sympa::Log::do_log('err', 'Could not drop index %s from table %s in database %s',$param->{'index'}, $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, index $param->{'index'} dropped";
	&Sympa::Log::do_log('info', 'Table %s, index %s dropped', $param->{'table'},$param->{'index'});

	return $report;
}

sub set_index {
	my ($self, $param) = @_;

	my $sth;
	my $fields = join ',',@{$param->{'fields'}};
	&Sympa::Log::do_log('debug', 'Setting index %s for table %s using fields %s', $param->{'index_name'},$param->{'table'}, $fields);
	unless ($sth = $self->do_query("ALTER TABLE %s ADD INDEX %s (%s)",$param->{'table'}, $param->{'index_name'}, $fields)) {
		&Sympa::Log::do_log('err', 'Could not add index %s using field %s for table %s in database %s', $fields, $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, index %s set using $fields";
	&Sympa::Log::do_log('info', 'Table %s, index %s set using fields %s',$param->{'table'}, $param->{'index_name'}, $fields);
	return $report;
}

1;
