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

Sympa::Datasource::SQL::SQLite - SQLite data source object

=head1 DESCRIPTION

This class implements an SQLite data source.

=cut

package Sympa::Datasource::SQL::SQLite;

use strict;
use base qw(Sympa::Datasource::SQL::Default);

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
	my ($self, $param) = @_;

	$self->{'connect_string'} = "DBI:SQLite:dbname=$self->{'db_name'}";
}

sub get_substring_clause {
	my ($self, $param) = @_;

	return sprintf
		"substr(%s,func_index(%s,'%s')+1,%s)",
		$param->{'source_field'},
		$param->{'source_field'},
		$param->{'separator'},
		$param->{'substring_length'};
}


sub get_limit_clause {
	my ($self, $param) = @_;

	if ($param->{'offset'}) {
		return sprintf "LIMIT %s OFFSET %s",
			$param->{'rows_count'},
			$param->{'offset'};
	} else {
		return sprintf "LIMIT %s", 
			$param->{'rows_count'};
	}
}

sub get_formatted_date {
	my ($self, $param) = @_;

	my $mode = lc($param->{'mode'});
	if ($mode eq 'read') {
		return sprintf 'UNIX_TIMESTAMP(%s)',$param->{'target'};
	} elsif ($mode eq 'write') {
		return sprintf 'FROM_UNIXTIME(%d)',$param->{'target'};
	} else {
		&Sympa::Log::do_log('err',"Unknown date format mode %s", $param->{'mode'});
		return undef;
	}
}

sub is_autoinc {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Checking whether field %s.%s is autoincremental',$param->{'field'},$param->{'table'});

	my $sth = $self->do_query("PRAGMA table_info(%s)",$param->{'table'});
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not get the list of fields from table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}

	while (my $row = $sth->fetchrow_arrayref()) {
		next unless $row->[1] eq $param->{'field'};
		return $row->[2] =~ /AUTO_INCREMENT/;
	}
}

sub set_autoinc {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Setting field %s.%s as autoincremental',$param->{'field'},$param->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE `%s` CHANGE `%s` `%s` BIGINT( 20 ) NOT NULL AUTO_INCREMENT",
		$param->{'table'},
		$param->{'field'},
		$param->{'field'}
	);
	unless ($sth) {
		&Sympa::Log::do_log('err','Unable to set field %s in table %s as autoincrement',$param->{'field'},$param->{'table'});
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
		&Sympa::Log::do_log('err','Unable to retrieve the list of tables from database %s',$self->{'db_name'});
		return undef;
	}

	my @tables;
	while (my $row = $sth->fetchrow_arrayref()) {
	    push @tables, $row->[0];
    }

    return \@tables;
}

sub add_table {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Adding table %s to database %s',$param->{'table'},$self->{'db_name'});

	my $sth = $self->do_query(
		"CREATE TABLE %s (temporary INT)",
		$param->{'table'}
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not create table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	return sprintf "Table %s created in database %s", $param->{'table'}, $self->{'db_name'};
}

sub get_fields {
	my ($self, $param) = @_;

	my $sth = $self->do_query("PRAGMA table_info(%s)", $param->{'table'});
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not get the list of fields from table %s in database %s', $param->{'table'}, $self->{'db_name'});
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
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Updating field %s in table %s (%s, %s)',$param->{'field'},$param->{'table'},$param->{'type'},$param->{'notnull'});
	my $options;
	if ($param->{'notnull'}) {
		$options .= ' NOT NULL ';
	}
	my $report = sprintf(
		"ALTER TABLE %s CHANGE %s %s %s %s",
		$param->{'table'},
		$param->{'field'},
		$param->{'field'},
		$param->{'type'},
		$options
	);
	&Sympa::Log::do_log('notice', $report);

	my $sth = $self->do_query(
		"ALTER TABLE %s CHANGE %s %s %s %s",
		$param->{'table'},
		$param->{'field'},
		$param->{'field'},
		$param->{'type'},
		$options
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not change field \'%s\' in table\'%s\'.',$param->{'field'}, $param->{'table'});
		return undef;
	}
	$report .= sprintf(
		'\nField %s in table %s, structure updated',
		$param->{'field'},
		$param->{'table'}
	);
	&Sympa::Log::do_log('info', $report);

	return $report;
}

sub add_field {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Adding field %s in table %s (%s, %s, %s, %s)',$param->{'field'},$param->{'table'},$param->{'type'},$param->{'notnull'},$param->{'autoinc'},$param->{'primary'});

	my $options = join(' ',
		$param->{notnull} ? 'NOT NULL'       : (),
		$param->{autoinc} ? 'AUTO_INCREMENT' : (),
		$param->{primary} ? 'PRIMARY KEY'    : (),
	);

	my $sth = $self->do_query(
		"ALTER TABLE %s ADD %s %s %s",
		$param->{'table'},
		$param->{'field'},
		$param->{'type'},
		$options
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not add field %s to table %s in database %s', $param->{'field'}, $param->{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf(
		'Field %s added to table %s (options: %s)',
		$param->{'field'},
		$param->{'table'},
		$options
	);
	&Sympa::Log::do_log('info', $report);

	return $report;
}

sub delete_field {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Deleting field %s from table %s',$param->{'field'},$param->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE %s DROP COLUMN `%s`",
		$param->{'table'},
		$param->{'field'}
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not delete field %s from table %s in database %s', $param->{'field'}, $param->{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf(
		'Field %s removed from table %s',
		$param->{'field'},
		$param->{'table'}
	);
	&Sympa::Log::do_log('info', $report);

	return $report;
}

sub get_primary_key {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Getting primary key for table %s',$param->{'table'});

	my $sth = $self->do_query("PRAGMA table_info(%s)", $param->{'table'});
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not get field list from table %s in database %s', $param->{'table'}, $self->{'db_name'});
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
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Removing primary key from table %s',$param->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE %s DROP PRIMARY KEY",
		$param->{'table'}
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not drop primary key from table %s in database %s', $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, PRIMARY KEY dropped";
	&Sympa::Log::do_log('info', $report);

	return $report;
}

sub set_primary_key {
	my ($self, $param) = @_;

	my $fields = join ',',@{$param->{'fields'}};
	&Sympa::Log::do_log('debug','Setting primary key for table %s (%s)',$param->{'table'},$fields);

	my $sth = $self->do_query(
		"ALTER TABLE %s ADD PRIMARY KEY (%s)",
		$param->{'table'},
		$fields
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not set fields %s as primary key for table %s in database %s', $fields, $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, PRIMARY KEY set on $fields";
	&Sympa::Log::do_log('info', $report);

	return $report;
}

sub get_indexes {
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Looking for indexes in %s',$param->{'table'});

	my $sth = $self->do_query(
		"SELECT name,sql FROM sqlite_master WHERE type='index'"
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not get the list of indexes from table %s in database %s', $param->{'table'}, $self->{'db_name'});
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
	my ($self, $param) = @_;

	&Sympa::Log::do_log('debug','Removing index %s from table %s',$param->{'index'},$param->{'table'});

	my $sth = $self->do_query(
		"ALTER TABLE %s DROP INDEX %s",
		$param->{'table'},
		$param->{'index'}
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not drop index %s from table %s in database %s',$param->{'index'}, $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, index $param->{'index'} dropped";
	&Sympa::Log::do_log('info', $report);

	return $report;
}

sub set_index {
	my ($self, $param) = @_;

	my $fields = join ',',@{$param->{'fields'}};
	&Sympa::Log::do_log('debug', 'Setting index %s for table %s using fields %s', $param->{'index_name'},$param->{'table'}, $fields);

	my $sth = $self->do_query(
		"CREATE INDEX %s ON %s (%s)",
		$param->{'index_name'},
		$param->{'table'},
		$fields
	);
	unless ($sth) {
		&Sympa::Log::do_log('err', 'Could not add index %s using field %s for table %s in database %s', $fields, $param->{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $param->{'table'}, index %s set using $fields";
	&Sympa::Log::do_log('info', $report);

	return $report;
}

1;
