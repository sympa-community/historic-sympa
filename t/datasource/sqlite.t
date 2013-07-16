#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use File::Temp;
use Test::More;
use Test::Without::Module qw(DBD::SQLite);

use Sympa::Datasource::SQL;

plan tests => 14;

my $source;

$source = Sympa::Datasource::SQL->create(db_type => 'SQLite', db_name => 'foo');
ok($source, 'factory creation OK');
isa_ok($source, 'Sympa::Datasource::SQL::SQLite');

$source = Sympa::Datasource::SQL::SQLite->new(db_name => 'foo');
ok($source, 'direct create OK');
isa_ok($source, 'Sympa::Datasource::SQL::SQLite');

is(
	$source->get_connect_string(),
	'DBI:SQLite:dbname=foo',
	'connect string'
);

my $clause;
$clause = $source->get_substring_clause(
	source_field     => 'foo',
	separator        => ',',
	substring_length => 5
);
is($clause, "substr(foo,func_index(foo,',')+1,5)", 'substring clause');

$clause = $source->get_limit_clause(
	rows_count => 5
);
is($clause, "LIMIT 5", 'limit clause');

$clause = $source->get_limit_clause(
	rows_count => 5,
	offset     => 3
);
is($clause, "LIMIT 5 OFFSET 3", 'limit clause');

my $date;
$date = $source->get_formatted_date(
        target => 666,
);
ok(!defined $date, 'formatted date (no mode)');

$date = $source->get_formatted_date(
	target => 666,
	mode   => 'foo'
);
ok(!defined $date, 'formatted date (invalid mode)');

$date = $source->get_formatted_date(
	target => 666,
	mode   => 'read'
);
is($date, "UNIX_TIMESTAMP(666)", 'formatted date (read)');

$date = $source->get_formatted_date(
	target => 666,
	mode   => 'write'
);
is($date, "FROM_UNIXTIME(666)", 'formatted date (write)');

my $dbh;
$source = Sympa::Datasource::SQL::SQLite->new(
);
$dbh = $source->connect();
ok(!defined $dbh, 'no connection without db_name');

$source = Sympa::Datasource::SQL::SQLite->new(
	db_name => File::Temp->new(),
);
$dbh = $source->connect();
ok(!defined $dbh, 'no connection without DBD::SQLite');
