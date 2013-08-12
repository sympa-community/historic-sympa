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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 NAME

Sympa::Database::SQLite - SQLite Sympa database

=head1 DESCRIPTION

This class implements a SQLite Sympa database.

=cut

package Sympa::Database::SQLite;

use strict;
use base qw(Sympa::Database);

use version;
use Carp;

use Sympa::Log::Syslog;
use Sympa::Tools::Data;

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

sub connect {
	my ($self, %params) = @_;

	my $result = $self->SUPER::connect(%params);
	return unless $result;

	$self->{dbh}->func(
		'func_index',
		-1,
		sub { return index($_[0], $_[1]) },
		'create_function'
	);

	if (defined $self->{db_timeout}) {
		$self->{dbh}->func($self->{db_timeout}, 'busy_timeout' );
	} else {
		$self->{dbh}->func(5000, 'busy_timeout');
	}

	return 1;
}

sub get_connect_string{
	my ($self, %params) = @_;

	return "DBI:SQLite:dbname=$self->{db_name}";
}

sub get_substring_clause {
	my ($self, %params) = @_;

	return sprintf
		"substr(%s,func_index(%s,'%s')+1,%s)",
		$params{source_field},
		$params{source_field},
		$params{separator},
		$params{substring_length};
}


sub get_limit_clause {
	my ($self, %params) = @_;

	if ($params{offset}) {
		return sprintf "LIMIT %s OFFSET %s",
			$params{rows_count},
			$params{offset};
	} else {
		return sprintf "LIMIT %s",
			$params{rows_count};
	}
}

sub get_formatted_date {
	my ($self, %params) = @_;

	my $mode = lc($params{mode});
	if ($mode eq 'read') {
		return $params{'target'};
	} elsif ($mode eq 'write') {
		return $params{'target'};
	} else {
		Sympa::Log::Syslog::do_log(
			'err',
			"Unknown date format mode %s",
			$params{'mode'}
		);
		return undef;
	}
}

sub is_autoinc {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Checking whether field %s.%s is autoincremental',
		$params{field},
		$params{table}
	);

	my $query = "PRAGMA table_info($params{table})";
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get the list of fields from table %s in database %s',
			$params{table},
			$self->{db_name}
		);
		return undef;
	}
	$handle->execute();

	while (my $row = $handle->fetchrow_arrayref()) {
		next unless $row->[1] eq $params{field};
		return $row->[2] eq 'integer' and $row->[5];
	}
}

sub set_autoinc {
	my ($self, %params) = @_;
	my $table = $params{'table'};
	my $field = $params{'field'};

	Sympa::Log::Syslog::do_log('debug3','Setting field %s.%s as autoincremental',
		$table, $field);

	my $type = $self->get_fields(table => $table)->{$field};
	return undef unless $type;

	my $r;
	my $pk;
	if ($type =~ /^integer\s+PRIMARY\s+KEY\b/i) {
		## INTEGER PRIMARY KEY is auto-increment.
		return 1;
	} elsif ($type =~ /\bPRIMARY\s+KEY\b/i) {
		$r = $self->_update_table($table,
			qr(\b$field\s[^,]+),
			"$field\tinteger PRIMARY KEY");
	} elsif ($pk = $self->get_primary_key({ 'table' => $table }) and
		$pk->{$field} and scalar keys %$pk == 1) {
		$self->unset_primary_key({ 'table' => $table });
		$r = $self->_update_table($table,
			qr(\b$field\s[^,]+),
			"$field\tinteger PRIMARY KEY");
	} else {
		$r = $self->_update_table($table,
			qr(\b$field\s[^,]+),
			"$field\t$type AUTOINCREMENT");
	}

	unless ($r) {
		Sympa::Log::Syslog::do_log('err','Unable to set field %s in table %s as autoincremental', $field, $table);
		return undef;
	}
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting tables list',
	);

	my $query = "SELECT name FROM sqlite_master WHERE type='table'";
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to get tables list',
		);
		return undef;
	}
	$handle->execute();

	my @tables;
	while (my $row = $handle->fetchrow_arrayref()) {
	    push @tables, $row->[0];
	}

	return @tables;
}

sub _get_table_query {
	my ($self, %params) = @_;

	my @clauses =
		map { $self->_get_field_clause(%$_, table => $params{table}) }
		@{$params{fields}};
	push @clauses, $self->_get_primary_key_clause(@{$params{key}})
		if $params{key} and
		! Sympa::Tools::Data::any { $_->{autoincrement} } @{$params{fields}};

	my $query =
		"CREATE TABLE $params{table} (" . join(',', @clauses) . ")";
	return $query;
}

sub _get_field_clause {
	my ($self, %params) = @_;

	my $clause = "$params{name} $params{type}";
	$clause .= ' NOT NULL' if $params{notnull};
	$clause .= ' PRIMARY KEY' if $params{autoincrement};

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
	return 'real'    if $type =~ /^double/;
	return 'numeric' if $type =~ /^datetime/;
	return 'text'    if $type =~ /^enum/;
	return 'none'    if $type =~ /^mediumblob/;
	return $type;
}

sub get_fields {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting fields list from table %s',
		$params{table},
	);

	my $query = "PRAGMA table_info($params{table})";
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to get fields list from table %s',
			$params{table},
		);
		return undef;
	}
	$handle->execute();

	my %result;
	while (my $row = $handle->fetchrow_arrayref()) {
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
	my $table = $params{'table'};
	my $field = $params{'field'};
	my $type = $params{'type'};
	my $options = '';
	if ($params{'notnull'}) {
		$options .= ' NOT NULL';
	}
	my $report;

	Sympa::Log::Syslog::do_log('debug3', 'Updating field %s in table %s (%s%s)',
		$field, $table, $type, $options);
	my $r = $self->_update_table($table,
		qr(\b$field\s[^,]+),
		"$field\t$type$options");
	unless (defined $r) {
		Sympa::Log::Syslog::do_log('err', 'Could not update field %s in table %s (%s%s)',
			$field, $table, $type, $options);
		return undef;
	}
	$report = $r;
	Sympa::Log::Syslog::do_log('info', '%s', $r);
	$report .= "\nTable $table, field $field updated";
	Sympa::Log::Syslog::do_log('info', 'Table %s, field %s updated', $table, $field);

	return $report;
}

# override needed to handle the specific case of adding a primary key
# to an already-existing table
sub add_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Adding field %s in table %s (%s, %s, %s, %s)',
		$params{field},
		$params{table},
		$params{type},
		$params{notnull},
		$params{autoinc},
		$params{primary}
	);

	if ($params{'primary'}) {
		my $options = ' PRIMARY KEY';
		# To prevent "Cannot add a NOT NULL column with default value NULL" errors
		if ( $params{'autoinc'}) {
			$options .= ' AUTOINCREMENT';
		}
		if ( $params{'notnull'}) {
			$options .= ' NOT NULL';
		}
		my $result = $self->_update_table($params{table},
			qr{[(]\s*},
			"(\n\t $params{field}\t$params{type}$options,\n\t ");
		unless ($result) {
			Sympa::Log::Syslog::do_log('err', 'Could not add field
				%s to table %s in database %s',
				$params{field}, $params{table}, $self->{'db_name'});
			return undef;
		}
	} else {
		my $query =
			"ALTER TABLE $params{table} "     .
			"ADD $params{field} $params{type}";
		$query .= ' NOT NULL'       if $params{notnull};
		$query .= ' AUTO_INCREMENT' if $params{autoinc};

		my $rows = $self->{dbh}->do($query);
		croak sprintf(
			'Unable to add field %s in table %s: %s',
			$params{field},
			$params{table},
			$self->{dbh}->errstr()
		) unless $rows;

		if ($self->_vernum <= 3.001003) {
			my $vacuum_rows = $self->{dbh}->do('VACUUM');
			croak sprintf(
				'Unable to vacuum database: %s',
				$self->{dbh}->errstr()
			) unless $vacuum_rows;
		}
	}

	my $report = sprintf(
		'Field %s added to table %s',
		$params{field},
		$params{table},
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

# overriden because sqlite doesn't support deleting fields
sub delete_field {
	croak "unsupported operation";
}

# overriden because there is no generic implementation available
sub get_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting primary key from table %s',
		$params{table}
	);

	my $query = "PRAGMA table_info($params{table})";
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get fields list from table %s',
			$params{table},
		);
		return undef;
	}
	$handle->execute();

	my @fields;
	while (my $row = $handle->fetchrow_hashref('NAME_lc')) {
		push @fields, $row->{name} if $row->{pk};
	}

	return \@fields;
}

# overriden because sqlite doesn't support primary key alteration after 
# inital table creation
sub unset_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Removing primary key from table %s',
		$params{table}
	);
	my $table = $params{'table'};

	my $r = $self->_update_table($table,
		qr{,\s*PRIMARY\s+KEY\s+[(][^)]+[)]},
		'');
	unless (defined $r) {
		Sympa::Log::Syslog::do_log('err', 'Could not remove primary key from table %s',
			$table);
		return undef;
	}

	my $report = sprintf(
		"Primary key removed from table %s",
		$params{table}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

# overriden because sqlite doesn't support primary key alteration after 
# inital table creation
sub set_primary_key {
	my ($self, %params) = @_;

	my $fields = join(',', @{$params{fields}});
	Sympa::Log::Syslog::do_log(
		'debug',
		'Setting primary key on table %s using fields %s',
		$params{table},
		$fields
	);
	my $table = $params{'table'};
	my $report;

	my $r = $self->_update_table($table,
		qr{\s*[)]\s*$},
		",\n\t PRIMARY KEY ($fields)\n )");
	unless (defined $r) {
		Sympa::Log::Syslog::do_log('debug', 'Could not set primary key for table %s (%s)',
			$table, $fields);
		return undef;
	}

	my $report = sprintf(
		"Primary key set on table %s using fields %s",
		$params{table},
		$fields
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

# overriden because there is no generic implementation available
sub get_indexes {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting indexes list from table %s',
		$params{table}
	);

	my $list_query = "PRAGMA index_list($params{table})";
	my $list_handle = $self->{dbh}->prepare($list_query);
	unless ($list_handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get index list from table %s',
			$params{table},
		);
		return undef;
	}
	$list_handle->execute();

	my @indexes;
	while (my $row = $list_handle->fetchrow_hashref('NAME_lc')) {
		next if $row->{'unique'};
		push @indexes, $row->{'name'};
	}

	my %indexes;
	foreach my $index (@indexes) {
		my $info_query = "PRAGMA index_info($index)";
		my $info_handle = $self->{dbh}->prepare($info_query);
		unless ($info_handle) {
			Sympa::Log::Syslog::do_log(
				'err',
				'Could not get fields list from index %s',
				$index
			);
			return undef;
		}
		$info_handle->execute();

		while (my $row = $info_handle->fetchrow_hashref('NAME_lc')) {
			$indexes{$index}->{$row->{name}} = 1;
		}
	}

	return \%indexes;
}

# Drops an index of a table.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the index must be dropped.
#	* 'index' : the name of the index to be dropped.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub unset_index {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug3','Removing index %s from table %s',$params{'index'},$params{'table'});

	my $handle;
	unless ($handle = $self->do_query(
			q{DROP INDEX "%s"},
			$params{'index'}
		)) {
		Sympa::Log::Syslog::do_log('err', 'Could not drop index %s from table %s in database %s',$params{'index'}, $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params{'table'}, index $params{'index'} dropped";
	Sympa::Log::Syslog::do_log('info', 'Table %s, index %s dropped', $params{'table'},$params{'index'});

	my $query = "SELECT name,sql FROM sqlite_master WHERE type='index'";
	my $handle = $self->{dbh}->prepare($query);
	unless ($handle) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get the list of indexes from table %s in database %s',
			$params{table},
			$self->{db_name}
		);
		return undef;
	}
	$handle->execute();

	my %indexes;
	while (my $row = $handle->fetchrow_arrayref()) {
		my ($fields) = $row->[1] =~ /\( ([^)]+) \)$/x;
		foreach my $field (split(/,/, $fields)) {
			$indexes{$row->[0]}->{$field} = 1;
		}
	}

	my $handle;
	my $fields = join ',',@{$params{'fields'}};
	Sympa::Log::Syslog::do_log('debug3', 'Setting index %s for table %s using fields %s', $params{'index_name'},$params{'table'}, $fields);
	unless ($handle = $self->do_query(
			q{CREATE INDEX %s ON %s (%s)},
			$params{'index_name'}, $params{'table'}, $fields
		)) {
		Sympa::Log::Syslog::do_log('err', 'Could not add index %s using field %s for table %s in database %s', $fields, $params{'table'}, $self->{'db_name'});
		return undef;
	}
	my $report = "Table $params{'table'}, index %s set using $fields";
	Sympa::Log::Syslog::do_log('info', 'Table %s, index %s set using fields %s',$params{'table'}, $params{'index_name'}, $fields);
	return $report;
}

############################################################################
## Overridden methods
############################################################################

## To prevent "database is locked" error, acquire "immediate" lock
## by each query.  All queries including "SELECT" need to lock in this
## manner.

sub do_query {
	my ($self) = @_;
	my $handle;
	my $rc;

	my $need_lock =
	($_[0] =~ /^\s*(ALTER|CREATE|DELETE|DROP|INSERT|REINDEX|REPLACE|UPDATE)\b/i);

	## acquire "immediate" lock
	unless (! $need_lock or $self->{'dbh'}->begin_work) {
		Sympa::Log::Syslog::do_log('err', 'Could not lock database: (%s) %s',
			$self->{'dbh'}->err, $self->{'dbh'}->errstr);
		return undef;
	}

	## do query
	$handle = $self->SUPER::do_query(@_);

	## release lock
	return $handle unless $need_lock;
	eval {
		if ($handle) {
			$rc = $self->{'dbh'}->commit;
		} else {
			$rc = $self->{'dbh'}->rollback;
		}
	};
	if ($@ or ! $rc) {
		Sympa::Log::Syslog::do_log('err', 'Could not unlock database: %s',
			$@ || sprintf('(%s) %s', $self->{'dbh'}->err,
				$self->{'dbh'}->errstr));
		return undef;
	}

	return $handle;
}

sub do_prepared_query {
	my ($self) = @_;
	my $handle;
	my $rc;

	my $need_lock =
	($_[0] =~ /^\s*(ALTER|CREATE|DELETE|DROP|INSERT|REINDEX|REPLACE|UPDATE)\b/i);

	## acquire "immediate" lock
	unless (! $need_lock or $self->{'dbh'}->begin_work) {
		Sympa::Log::Syslog::do_log('err', 'Could not lock database: (%s) %s',
			$self->{'dbh'}->err, $self->{'dbh'}->errstr);
		return undef;
	}

	## do query
	$handle = $self->SUPER::do_prepared_query(@_);

	## release lock
	return $handle unless $need_lock;
	eval {
		if ($handle) {
			$rc = $self->{'dbh'}->commit;
		} else {
			$rc = $self->{'dbh'}->rollback;
		}
	};
	if ($@ or ! $rc) {
		Sympa::Log::Syslog::do_log('err', 'Could not unlock database: %s',
			$@ || sprintf('(%s) %s', $self->{'dbh'}->err,
				$self->{'dbh'}->errstr));
		return undef;
	}

	return $handle;
}

## For BLOB types.
sub AS_BLOB {
	return ( { TYPE => DBI::SQL_BLOB() } => $_[1] )
		if scalar @_ > 1;
	return ();
}

############################################################################
## private methods
############################################################################

## get numified version of SQLite
sub _vernum {
	my ($self) = @_;
	return version->new('v' . $self->{'dbh'}->{'sqlite_version'})->numify;
}

## update table structure
## old table will be saved as "<table name>_<YYmmddHHMMSS>_<PID>".
sub _update_table {
	my ($self, $table, $regex, $replacement) = @_;
	my $statement;
	my $table_saved = sprintf '%s_%s_%d', $table,
	POSIX::strftime("%Y%m%d%H%M%S", gmtime $^T),
	$$;
	my $report;

	## create temporary table with new structure
	$statement = $self->_get_create_table($table);
	unless (defined $statement) {
		Sympa::Log::Syslog::do_log('err', 'Table \'%s\' does not exist', $table);
		return undef;
	}
	$statement=~ s/^\s*CREATE\s+TABLE\s+([\"\w]+)/CREATE TABLE ${table_saved}_new/;
	$statement =~ s/$regex/$replacement/;
	my $s = $statement; $s =~ s/\n\s*/ /g; $s =~ s/\t/ /g;
	Sympa::Log::Syslog::do_log('info', '%s', $s);
	unless ($self->do_query('%s', $statement)) {
		Sympa::Log::Syslog::do_log('err', 'Could not create temporary table \'%s_new\'',
			$table_saved);
		return undef;
	}

	Sympa::Log::Syslog::do_log('info', 'Copy \'%s\' to \'%s_new\'', $table, $table_saved);
	## save old table
	my $indexes = $self->get_indexes(table => $table);
	unless (defined $self->_copy_table($table, "${table_saved}_new") and
		defined $self->_rename_or_drop_table($table, $table_saved) and
		defined $self->_rename_table("${table_saved}_new", $table)) {
		return undef;
	}
	## recreate indexes
	foreach my $name (keys %{$indexes || {}}) {
		unless (defined $self->unset_index(
				table => "${table_saved}_new",
				index => $name
			) and defined $self->set_index(
				table      => $table,
				index_name => $name,
				fields     => [ sort keys %{$indexes->{$name}} ]
			)
		) {
			return undef;
		}
	}

	$report = "Old table was saved as \'$table_saved\'";
	return $report;
}

## Get SQL statement by which table was created.
sub _get_create_table {
	my ($self, $table) = @_;
	my $handle;

	unless ($handle = $self->do_query(
			q{SELECT sql
			FROM sqlite_master
			WHERE type = 'table' AND name = '%s'},
			$table
		)) {
		Sympa::Log::Syslog::do_log('Could not get table \'%s\' on database \'%s\'',
			$table, $self->{'db_name'});
		return undef;
	}
	my $sql = $handle->fetchrow_array();
	$handle->finish;

	return $sql || undef;
}

## copy table content to another table
## target table must have all columns source table has.
sub _copy_table {
	my ($self, $table, $table_new) = @_;
	return undef unless defined $table and defined $table_new;

	my $fields = join ', ',
	sort keys %{$self->get_fields({ 'table' => $table })};

	my $handle;
	unless ($handle = $self->do_query(
			q{INSERT INTO "%s" (%s) SELECT %s FROM "%s"},
			$table_new, $fields, $fields, $table
		)) {
		Sympa::Log::Syslog::do_log('err', 'Could not copy talbe \'%s\' to temporary table \'%s_new\'', $table, $table_new);
		return undef;
	}

	return 1;
}

## rename table
## if target already exists, do nothing and return 0.
sub _rename_table {
	my ($self, $table, $table_new) = @_;
	return undef unless defined $table and defined $table_new;

	if ($self->_get_create_table($table_new)) {
		return 0;
	}
	unless ($self->do_query(
			q{ALTER TABLE %s RENAME TO %s},
			$table, $table_new
		)) {
		Sympa::Log::Syslog::do_log('err', 'Could not rename table \'%s\' to \'%s\'',
			$table, $table_new);
		return undef;
	}
	return 1;
}

## rename table
## if target already exists, drop source table.
sub _rename_or_drop_table {
	my ($self, $table, $table_new) = @_;

	my $r = $self->_rename_table($table, $table_new);
	unless (defined $r) {
		return undef;
	} elsif ($r) {
		return $r;
	} else {
		unless ($self->do_query(q{DROP TABLE "%s"}, $table)) {
			Sympa::Log::Syslog::do_log('err', 'Could not drop table \'%s\'', $table);
			return undef;
		}
		return 0;
	}
}

1;
