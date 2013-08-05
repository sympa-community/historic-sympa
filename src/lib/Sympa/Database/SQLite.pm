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
    my $self = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3','Building SQL date formatting');
    if (lc($param->{'mode'}) eq 'read' or lc($param->{'mode'}) eq 'write') {
	return $param->{'target'};
    }else {
	Sympa::Log::Syslog::do_log('err',"Unknown date format mode %s", $param->{'mode'});
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
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get the list of fields from table %s in database %s',
			$params{table},
			$self->{db_name}
		);
		return undef;
	}
	$sth->execute();

	while (my $row = $sth->fetchrow_arrayref()) {
		next unless $row->[1] eq $params{field};
		return $row->[2] eq 'integer' and $row->[5];
	}
}

sub set_autoinc {
    my $self = shift;
    my $param = shift;
    my $table = $param->{'table'};
    my $field = $param->{'field'};

    Sympa::Log::Syslog::do_log('debug3','Setting field %s.%s as autoincremental',
		 $table, $field);

    my $type = $self->_get_field_type($table, $field);
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
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to get tables list',
		);
		return undef;
	}
	$sth->execute();

	my @tables;
	while (my $row = $sth->fetchrow_arrayref()) {
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
	return 'numeric' if $type =~ /^datetime/;
	return 'text'    if $type =~ /^enum/;
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
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to get fields list from table %s',
			$params{table},
		);
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
    my $self = shift;
    my $param = shift;
    my $table = $param->{'table'};
    my $field = $param->{'field'};
    my $type = $param->{'type'};
    my $options = '';
    if ($param->{'notnull'}) {
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

# Adds a field in a table from the database.
# IN: A ref to hash containing the following keys:
#	* 'field' : the name of the field to add
#	* 'table' : the name of the table where the field will be added.
#	* 'type' : the type of the field to add
#	* 'notnull' : specifies that the field must not be null
#	* 'autoinc' : specifies that the field must be autoincremental
#	* 'primary' : specifies that the field is a key
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub add_field {
    my $self = shift;
    my $param = shift;
    my $table = $param->{'table'};
    my $field = $param->{'field'};
    my $type = $param->{'type'};

    my $options = '';
    # To prevent "Cannot add a NOT NULL column with default value NULL" errors
    if ($param->{'primary'}) {
	$options .= ' PRIMARY KEY';
    }
    if ( $param->{'autoinc'}) {
	$options .= ' AUTOINCREMENT';
    }
    if ( $param->{'notnull'}) {
	$options .= ' NOT NULL';
    }
    Sympa::Log::Syslog::do_log('debug3','Adding field %s in table %s (%s%s)',
		 $field, $table, $type, $options);

    my $report = '';

    if ($param->{'primary'}) {
	$report = $self->_update_table($table,
				       qr{[(]\s*},
				       "(\n\t $field\t$type$options,\n\t ");
	unless (defined $report) {
	    Sympa::Log::Syslog::do_log('err', 'Could not add field %s to table %s in database %s', $field, $table, $self->{'db_name'});
	return undef;
    }
    } else { 
	unless ($self->do_query(
	    q{ALTER TABLE %s ADD %s %s%s},
	    $table, $field, $type, $options
	)) {
	    Sympa::Log::Syslog::do_log('err', 'Could not add field %s to table %s in database %s', $field, $table, $self->{'db_name'});
	    return undef;
	}
	if ($self->_vernum <= 3.001003) {
	    unless ($self->do_query(q{VACUUM})) {
		Sympa::Log::Syslog::do_log('err', 'Could not vacuum database %s',
			     $self->{'db_name'});
		return undef;
	    }
	}
    }

    $report .= "\n" if $report;
    $report .= sprintf 'Field %s added to table %s (%s%s)',
		       $field, $table, $type, $options;
    Sympa::Log::Syslog::do_log('info', 'Field %s added to table %s (%s%s)',
		 $field, $table, $type, $options);

    return $report;
}

# Deletes a field from a table in the database.
# IN: A ref to hash containing the following keys:
#	* 'field' : the name of the field to delete
#	* 'table' : the name of the table where the field will be deleted.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub delete_field {
    my $self = shift;
    my $param = shift;
    my $table = $param->{'table'};
    my $field = $param->{'field'};
    Sympa::Log::Syslog::do_log('debug3','Deleting field %s from table %s', $field, $table);

    ## SQLite does not support removal of columns

    my $report = "Could not remove field $field from table $table since SQLite does not support removal of columns";
    Sympa::Log::Syslog::do_log('info', '%s', $report);

    return $report;
}

# Returns the list fields being part of a table's primary key.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the primary keys are requested.
#
# OUT: A ref to a hash in which each key is the name of a primary key or undef if something went wrong.
#
sub get_primary_key {
    my $self = shift;
    my $param = shift;
    my $table = $param->{'table'};
    Sympa::Log::Syslog::do_log('debug3','Getting primary key for table %s', $table);

    my %found_keys = ();

    my $sth;
    unless ($sth = $self->do_query(
	q{PRAGMA table_info('%s')},
	$table
    )) {
	Sympa::Log::Syslog::do_log('err', 'Could not get field list from table %s in database %s', $table, $self->{'db_name'});
	return undef;
    }
    my $l;
    while ($l = $sth->fetchrow_hashref('NAME_lc')) {
	next unless $l->{'pk'};
	$found_keys{$l->{'name'}} = 1;
    }
    $sth->finish;

    return \%found_keys;
}

# Drops the primary key of a table.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the primary keys must be dropped.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub unset_primary_key {
    my $self = shift;
    my $param = shift;
    my $table = $param->{'table'};
    my $report;
    Sympa::Log::Syslog::do_log('debug3', 'Removing primary key from table %s', $table);

    my $r = $self->_update_table($table,
				 qr{,\s*PRIMARY\s+KEY\s+[(][^)]+[)]},
				 '');
    unless (defined $r) {
	Sympa::Log::Syslog::do_log('err', 'Could not remove primary key from table %s',
		     $table);
	return undef;
    }
    $report = $r;
    Sympa::Log::Syslog::do_log('info', '%s', $r);
    $report .= "\nTable $table, PRIMARY KEY dropped";
    Sympa::Log::Syslog::do_log('info', 'Table %s, PRIMARY KEY dropped', $table);

# override needed as unsupported
sub delete_field {
	croak "unsupported operation";
}

sub get_primary_key {
	my ($self, %params) = @_;
    my $table = $param->{'table'};
    my $fields = join ',',@{$param->{'fields'}};
    my $report;
    Sympa::Log::Syslog::do_log('debug3', 'Setting primary key for table %s (%s)',
		 $table, $fields);

    my $r = $self->_update_table($table,
				 qr{\s*[)]\s*$},
				 ",\n\t PRIMARY KEY ($fields)\n )");
    unless (defined $r) {
	Sympa::Log::Syslog::do_log('debug', 'Could not set primary key for table %s (%s)',
		     $table, $fields);
	return undef;
    }
    $report = $r;
    Sympa::Log::Syslog::do_log('info', '%s', $r);
    $report .= "\nTable $table, PRIMARY KEY set on $fields";
    Sympa::Log::Syslog::do_log('info', 'Table %s, PRIMARY KEY set on %s', $table, $fields);

    return $report;
}

# Returns a ref to a hash in which each key is the name of an index.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the indexes are requested.
#
# OUT: A ref to a hash in which each key is the name of an index. These key point to
#	a second level hash in which each key is the name of the field indexed.
#      Returns undef if something went wrong.
#
sub get_indexes {
    my $self = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3','Looking for indexes in %s',$param->{'table'});

    my %found_indexes;
    my $sth;
    my $l;
    unless ($sth = $self->do_query(
	q{PRAGMA index_list('%s')},
	$param->{'table'}
    )) {
	Sympa::Log::Syslog::do_log('err', 'Could not get the list of indexes from table %s in database %s', $param->{'table'}, $self->{'db_name'});
	return undef;
    }
    while($l = $sth->fetchrow_hashref('NAME_lc')) {
	next if $l->{'unique'};
	$found_indexes{$l->{'name'}} = {};
	}
    $sth->finish;

    foreach my $index_name (keys %found_indexes) {
	unless ($sth = $self->do_query(
	    q{PRAGMA index_info('%s')},
	    $index_name
	)) {
	    Sympa::Log::Syslog::do_log('err', 'Could not get the list of indexes from table %s in database %s', $param->{'table'}, $self->{'db_name'});
	    return undef;
    }
	while($l = $sth->fetchrow_hashref('NAME_lc')) {
	    $found_indexes{$index_name}{$l->{'name'}} = {};
	}
	$sth->finish;
    }

    return \%found_indexes;
}

# Drops an index of a table.
# IN: A ref to hash containing the following keys:
#	* 'table' : the name of the table for which the index must be dropped.
#	* 'index' : the name of the index to be dropped.
#
# OUT: A character string report of the operation done or undef if something went wrong.
#
sub unset_index {
    my $self = shift;
    my $param = shift;
    Sympa::Log::Syslog::do_log('debug3','Removing index %s from table %s',$param->{'index'},$param->{'table'});

    my $sth;
    unless ($sth = $self->do_query(
	q{DROP INDEX "%s"},
	$param->{'index'}
    )) {
	Sympa::Log::Syslog::do_log('err', 'Could not drop index %s from table %s in database %s',$param->{'index'}, $param->{'table'}, $self->{'db_name'});
	return undef;
    }
    my $report = "Table $param->{'table'}, index $param->{'index'} dropped";
    Sympa::Log::Syslog::do_log('info', 'Table %s, index %s dropped', $param->{'table'},$param->{'index'});

	my $query = "SELECT name,sql FROM sqlite_master WHERE type='index'";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Could not get the list of indexes from table %s in database %s',
			$params{table},
			$self->{db_name}
		);
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

    my $sth;
    my $fields = join ',',@{$param->{'fields'}};
    Sympa::Log::Syslog::do_log('debug3', 'Setting index %s for table %s using fields %s', $param->{'index_name'},$param->{'table'}, $fields);
    unless ($sth = $self->do_query(
	q{CREATE INDEX %s ON %s (%s)},
	$param->{'index_name'}, $param->{'table'}, $fields
    )) {
	Sympa::Log::Syslog::do_log('err', 'Could not add index %s using field %s for table %s in database %s', $fields, $param->{'table'}, $self->{'db_name'});
	return undef;
    }
    my $report = "Table $param->{'table'}, index %s set using $fields";
    Sympa::Log::Syslog::do_log('info', 'Table %s, index %s set using fields %s',$param->{'table'}, $param->{'index_name'}, $fields);
    return $report;
}

############################################################################
## Overridden methods
############################################################################

## To prevent "database is locked" error, acquire "immediate" lock
## by each query.  All queries including "SELECT" need to lock in this
## manner.

sub do_query {
    my $self = shift;
    my $sth;
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
    $sth = $self->SUPER::do_query(@_);

    ## release lock
    return $sth unless $need_lock;
    eval {
	if ($sth) {
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

    return $sth;
}

sub do_prepared_query {
    my $self = shift;
    my $sth;
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
    $sth = $self->SUPER::do_prepared_query(@_);

    ## release lock
    return $sth unless $need_lock;
    eval {
	if ($sth) {
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

    return $sth;
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
    my $self = shift;
    return version->new('v' . $self->{'dbh'}->{'sqlite_version'})->numify;
}

## get raw type of column
sub _get_field_type {
    my $self = shift;
    my $table = shift;
    my $field = shift;

    my $sth;
    unless ($sth = $self->do_query(q{PRAGMA table_info('%s')}, $table)) {
	Sympa::Log::Syslog::do_log('err', 'Could not get the list of fields from table %s in database %s', $table, $self->{'db_name'});
	return undef;
    }
    my $l;
    while ($l = $sth->fetchrow_hashref('NAME_lc')) {
	if (lc $l->{'name'} eq lc $field) {
	    $sth->finish;
	    return $l->{'type'};
	}
    }
    $sth->finish;

    Sympa::Log::Syslog::do_log('err', 'Could not gather information of field %s from table %s in database %s', $field, $table, $self->{'db_name'});
    return undef;
}

## update table structure
## old table will be saved as "<table name>_<YYmmddHHMMSS>_<PID>".
sub _update_table {
    my $self = shift;
    my $table = shift;
    my $regex = shift;
    my $replacement = shift;
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
    my $indexes = $self->get_indexes({ 'table' => $table });
    unless (defined $self->_copy_table($table, "${table_saved}_new") and
	    defined $self->_rename_or_drop_table($table, $table_saved) and
	    defined $self->_rename_table("${table_saved}_new", $table)) {
	return undef;
    }
    ## recreate indexes
    foreach my $name (keys %{$indexes || {}}) {
	unless (defined $self->unset_index(
		    { 'table' => "${table_saved}_new", 'index' => $name }) and
		defined $self->set_index(
		    { 'table' => $table, 'index_name' => $name,
		      'fields' => [ sort keys %{$indexes->{$name}} ] })
	) {
	    return undef;
	}
    }

    $report = "Old table was saved as \'$table_saved\'";
    return $report;
}

## Get SQL statement by which table was created.
sub _get_create_table {
    my $self = shift;
    my $table = shift;
    my $sth;

    unless ($sth = $self->do_query(
	q{SELECT sql
	  FROM sqlite_master
	  WHERE type = 'table' AND name = '%s'},
	$table
    )) {
	Sympa::Log::Syslog::do_log('Could not get table \'%s\' on database \'%s\'',
		     $table, $self->{'db_name'});
	return undef;
    }
    my $sql = $sth->fetchrow_array();
    $sth->finish;

    return $sql || undef;
}

## copy table content to another table
## target table must have all columns source table has.
sub _copy_table {
    my $self = shift;
    my $table = shift;
    my $table_new = shift;
    return undef unless defined $table and defined $table_new;

    my $fields = join ', ',
		      sort keys %{$self->get_fields({ 'table' => $table })};

    my $sth;
    unless ($sth = $self->do_query(
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
    my $self = shift;
    my $table = shift;
    my $table_new = shift;
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
    my $self = shift;
    my $table = shift;
    my $table_new = shift;

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
