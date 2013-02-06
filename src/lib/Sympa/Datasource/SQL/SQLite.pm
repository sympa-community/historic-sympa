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
# along with this program; if not, write to the Free Softwarec
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Datasource::SQL::SQLite - SQLite data source object

=head1 DESCRIPTION

This class implements an SQLite data source.

=cut

package Sympa::Datasource::SQL::SQLite;

use strict;
use base qw(Sympa::Datasource::SQL);

use Sympa::Log;

our %date_format = (
	'read' => {
		'SQLite' => 'strftime(\'%%s\',%s,\'utc\')'
	},
	'write' => {
		'SQLite' => 'datetime(%d,\'unixepoch\',\'localtime\')'
	}
);

sub build_connect_string{
	my ($self, $params) = @_;

	$self->{'connect_string'} = "DBI:SQLite:dbname=$self->{'db_name'}";
}

sub get_substring_clause {
	my ($self, $params) = @_;

	return sprintf
		"substr(%s,func_index(%s,'%s')+1,%s)",
		$params->{'source_field'},
		$params->{'source_field'},
		$params->{'separator'},
		$params->{'substring_length'};
}


sub get_limit_clause {
	my ($self, $params) = @_;

	if ($params->{'offset'}) {
		return sprintf "LIMIT %s OFFSET %s",
			$params->{'rows_count'},
			$params->{'offset'};
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

	my $sth = $self->do_query("PRAGMA table_info(%s)",$params->{'table'});
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not get the list of fields from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}

	while (my $row = $sth->fetchrow_arrayref()) {
		next unless $row->[1] eq $params->{'field'};
		return $row->[2] =~ /AUTO_INCREMENT/;
	}
}

sub set_autoinc {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Setting field %s.%s as autoincremental',$params->{'field'},$params->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE `%s` CHANGE `%s` `%s` BIGINT( 20 ) NOT NULL AUTO_INCREMENT",
		$params->{'table'},
		$params->{'field'},
		$params->{'field'}
	);
	unless ($sth) {
		Sympa::Log::do_log('err','Unable to set field %s in table %s as autoincrement',$params->{'field'},$params->{'table'});
		return undef;
	}
	return 1;
}

sub get_tables {
	my ($self) = @_;

	my $sth = $self->do_query(
		"SELECT name FROM sqlite_master WHERE type='table'"
	);
	unless ($sth) {
		Sympa::Log::do_log('err','Unable to retrieve the list of tables from database %s',$self->{'db_name'});
		return undef;
	}

	my @tables;
	while (my $row = $sth->fetchrow_arrayref()) {
	    push @tables, $row->[0];
    }

    return \@tables;
}

sub add_table {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Adding table %s to database %s',$params->{'table'},$self->{'db_name'});

	my $sth = $self->do_query(
		"CREATE TABLE %s (temporary INT)",
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

	my $sth = $self->do_query("PRAGMA table_info(%s)", $params->{'table'});
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not get the list of fields from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}

	my %result;
	while (my $row = $sth->fetchrow_arrayref()) {
		# http://www.sqlite.org/datatype3.html
		if($row->[2] =~ /int/) {
			$row->[2]="integer";
		} elsif ($row->[2] =~ /char|clob|text/) {
			$row->[2]="text";
		} elsif ($row->[2] =~ /blob/) {
			$row->[2]="none";
		} elsif ($row->[2] =~ /real|floa|doub/) {
			$row->[2]="real";
		} else {
			$row->[2]="numeric";
		}
		$result{$row->[1]} = $row->[2];
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
	# - impossible to add a primary key
	# - impossible to use NOT NULL option with default value NULL

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

	# unsupported
	Sympa::Log::do_log('err', 'Could not delete field %s from table %s in database %s', $params->{'field'}, $params->{'table'}, $self->{'db_name'});
	return undef;
}

sub get_primary_key {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Getting primary key for table %s',$params->{'table'});

	my $sth = $self->do_query("PRAGMA table_info(%s)", $params->{'table'});
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not get field list from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}

	my %keys;
	while (my $row = $sth->fetchrow_arrayref()) {
		next unless $row->[5];
		$keys{$row->[0]} = 1;
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
	Sympa::Log::do_log('info', $report);

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
	Sympa::Log::do_log('info', $report);

	return $report;
}

sub get_indexes {
	my ($self, $params) = @_;

	Sympa::Log::do_log('debug','Looking for indexes in %s',$params->{'table'});

	my $sth = $self->do_query(
		"SELECT name,sql FROM sqlite_master WHERE type='index'"
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not get the list of indexes from table %s in database %s', $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	my %indexes;
	while (my $row = $sth->fetchrow_arrayref()) {
		my ($fields) = $row->[1] =~ /\( ([^)]+) \)$/x;
		foreach my $field (split(/,/, $fields)) {
			$indexes{$row->[0]}->{$field} = 1;
		}
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
	Sympa::Log::do_log('info', $report);

	return $report;
}

sub set_index {
	my ($self, $params) = @_;

	my $fields = join ',',@{$params->{'fields'}};
	Sympa::Log::do_log('debug', 'Setting index %s for table %s using fields %s', $params->{'index_name'},$params->{'table'}, $fields);

	my $sth = $self->do_query(
		"CREATE INDEX %s ON %s (%s)",
		$params->{'index_name'},
		$params->{'table'},
		$fields
	);
	unless ($sth) {
		Sympa::Log::do_log('err', 'Could not add index %s using field %s for table %s in database %s', $fields, $params->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params->{'table'}, index %s set using $fields";
	Sympa::Log::do_log('info', $report);

	return $report;
}

1;
