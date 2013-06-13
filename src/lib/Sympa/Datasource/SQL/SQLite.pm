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

use Sympa::Log::Syslog;

our %date_format = (
	'read' => {
		'SQLite' => 'strftime(\'%%s\',%s,\'utc\')'
	},
	'write' => {
		'SQLite' => 'datetime(%d,\'unixepoch\',\'localtime\')'
	}
);

sub new {
	my ($class, %params) = @_;

	return $class->SUPER::new(%params, db_type => 'sqlite');
}

sub build_connect_string{
	my ($self, %params) = @_;

	$self->{'connect_string'} = "DBI:SQLite:dbname=$self->{'db_name'}";
}

sub get_substring_clause {
	my ($self, %params) = @_;

	return sprintf
		"substr(%s,func_index(%s,'%s')+1,%s)",
		$params{'source_field'},
		$params{'source_field'},
		$params{'separator'},
		$params{'substring_length'};
}


sub get_limit_clause {
	my ($self, %params) = @_;

	if ($params{'offset'}) {
		return sprintf "LIMIT %s OFFSET %s",
			$params{'rows_count'},
			$params{'offset'};
	} else {
		return sprintf "LIMIT %s",
			$params{'rows_count'};
	}
}

sub get_formatted_date {
	my ($self, %params) = @_;

	my $mode = lc($params{'mode'});
	if ($mode eq 'read') {
		return sprintf 'UNIX_TIMESTAMP(%s)',$params{'target'};
	} elsif ($mode eq 'write') {
		return sprintf 'FROM_UNIXTIME(%d)',$params{'target'};
	} else {
		Sympa::Log::Syslog::do_log('err',"Unknown date format mode %s", $params{'mode'});
		return undef;
	}
}

sub is_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Checking whether field %s.%s is autoincremental',$params{'field'},$params{'table'});

	my $query = "PRAGMA table_info($params{table})";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the list of fields from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	$sth->execute();

	while (my $row = $sth->fetchrow_arrayref()) {
		next unless $row->[1] eq $params{'field'};
		return $row->[2] =~ /AUTO_INCREMENT/;
	}
}

sub set_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Setting field %s.%s as autoincremental',$params{'field'},$params{'table'});

	my $query = 
		"ALTER TABLE $params{table} CHANGE $params{field} " .
		"$params{field} BIGINT(20) NOT NULL AUTO_INCREMENT";
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to set field %s in table %s as autoincrement',$params{'field'},$params{'table'});
		return undef;
	}

	return 1;
}

sub get_tables {
	my ($self) = @_;

	my $query = "SELECT name FROM sqlite_master WHERE type='table'";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve the list of tables from database %s',$self->{'db_name'});
		return undef;
	}
	$sth->execute();

	my @tables;
	while (my $row = $sth->fetchrow_arrayref()) {
	    push @tables, $row->[0];
	}

	return @tables;
}

sub _add_table {
	my ($self, %params) = @_;

	my @clauses =
		map { $self->_get_field_clause(%$_) }
		@{$params{fields}};
	push @clauses, $self->_get_primary_key_clause(@{$params{key}})
		if $params{key};

	my $query =
		"CREATE TABLE $params{table} (" . join(',', @clauses) . ")";
	return $self->{dbh}->do($query);
}

sub _get_field_clause {
	my ($self, %params) = @_;

	my $clause = "$params{name} $params{type}";
	$clause .= ' NOT NULL' if $params{notnull};

	return $clause;
}

sub _get_native_type {
	my ($self, $type) = @_;

	return 'text'    if $type =~ /^varchar/;
	return 'numeric' if $type =~ /^int\(1\)/;
	return 'integer' if $type =~ /^int/;
	return 'integer' if $type =~ /^tinyint/;
	return 'integer' if $type =~ /^bigint/;
	return 'integer' if $type =~ /^smallint/;
	return 'numeric' if $type =~ /^datetime/;
	return 'text'    if $type =~ /^enum/;
	return $type;
}

sub get_fields {
	my ($self, %params) = @_;

	my $query = "PRAGMA table_info($params{table})";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the list of fields from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	$sth->execute();

	my %result;
	while (my $row = $sth->fetchrow_arrayref()) {
		# http://www.sqlite.org/datatype3.html
		if($row->[2] =~ /int/) {
			$row->[2] = "integer";
		} elsif ($row->[2] =~ /char|clob|text/) {
			$row->[2] = "text";
		} elsif ($row->[2] =~ /blob/) {
			$row->[2] = "none";
		} elsif ($row->[2] =~ /real|floa|doub/) {
			$row->[2] = "real";
		} else {
			$row->[2] = "numeric";
		}
		$result{$row->[1]} = $row->[2];
	}
	return \%result;
}

sub update_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Updating field %s in table %s (%s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'});

	my $query =
		"ALTER TABLE $params{table} " .
		"CHANGE $params{field} $params{field} $params{type}";
	$query .= ' NOT NULL' if $params{notnull};

	my $rows = $self->{do}->($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Could not change field \'%s\' in table\'%s\'.',$params{'field'}, $params{'table'});
		return undef;
	}

	my $report = sprintf(
		'Field %s updated in table %s',
		$params{'field'},
		$params{'table'}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub add_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Adding field %s in table %s (%s, %s, %s, %s)',$params{'field'},$params{'table'},$params{'type'},$params{'notnull'},$params{'autoinc'},$params{'primary'});

	# specific issues:
	# - impossible to add a primary key
	# - impossible to use NOT NULL option with default value NULL
	my $query =
		"ALTER TABLE $params{table} "     .
		"ADD $params{field} $params{type}";

	$query .= ' NOT NULL'       if $params{notnull};
	$query .= ' AUTO_INCREMENT' if $params{autoinc};
	$query .= ' PRIMARY KEY'    if $params{primary};

	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Could not add field %s to table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my $report = sprintf(
		'Field %s added to table %s',
		$params{'field'},
		$params{'table'},
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub delete_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Deleting field %s from table %s',$params{'field'},$params{'table'});

	# unsupported
	Sympa::Log::Syslog::do_log('err', 'Could not delete field %s from table %s in database %s', $params{'field'}, $params{'table'}, $self->{'db_name'});
	return undef;
}

sub get_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Getting primary key for table %s',$params{'table'});

	my $query = "PRAGMA table_info($params{table})";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get field list from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}

	my %keys;
	while (my $row = $sth->fetchrow_arrayref()) {
		next unless $row->[5];
		$keys{$row->[0]} = 1;
	}

	return \%keys;
}

sub _unset_primary_key {
	my ($self, %params) = @_;

	my $query = "ALTER TABLE $params{table} DROP PRIMARY KEY";
	return $self->{dbh}->do($query);
}

sub _set_primary_key {
	my ($self, %params) = @_;

	my $query =
		"ALTER TABLE $params{table} ADD PRIMARY KEY ($params{fields})";
	return $self->{dbh}->do($query);
}

sub get_indexes {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Looking for indexes in %s',$params{'table'});

	my $query = "SELECT name,sql FROM sqlite_master WHERE type='index'";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err', 'Could not get the list of indexes from table %s in database %s', $params{'table'}, $self->{'db_name'});
		return undef;
	}
	$sth->execute();

	my %indexes;
	while (my $row = $sth->fetchrow_arrayref()) {
		my ($fields) = $row->[1] =~ /\( ([^)]+) \)$/x;
		foreach my $field (split(/,/, $fields)) {
			$indexes{$row->[0]}->{$field} = 1;
		}
	}

	return \%indexes;
}

sub _unset_index {
	my ($self, %params) = @_;

	my $query = "ALTER TABLE $params{table} DROP INDEX $params{index}";
	return $self->{dbh}->do($query);
}

sub _set_index {
	my ($self, %params) = @_;

	my $query = 
		"CREATE INDEX $params{index} " .
		"ON $params{table} ($params{fields})";
	return $self->{dbh}->do($query);
}

1;
