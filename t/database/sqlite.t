#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use File::Temp;
use Test::Exception;
use Test::More;
use Test::Without::Module qw(DBD::SQLite);

use Sympa::Database;

plan tests => 18;

my $source;

my $source;

throws_ok {
	$source = Sympa::Database->create();
} qr/^missing db_type parameter/,
'missing db_name parameter';

throws_ok {
	$source = Sympa::Database->create(
		db_type => 'sqlite',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

lives_ok {
	$source = Sympa::Database->create(
		db_type => 'sqlite',
		db_name => 'foo',
		db_host => 'localhost',
		db_user => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Database::SQLite');

throws_ok {
	$source = Sympa::Database::SQLite->new(
		db_host => 'localhost',
		db_user => 'foo',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

lives_ok {
	$source = Sympa::Database::SQLite->new(
		db_host => 'localhost',
		db_user => 'foo',
		db_name => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Database::SQLite');

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
is($date, "666", 'formatted date (read)');

$date = $source->get_formatted_date(
	target => 666,
	mode   => 'write'
);
is($date, "666", 'formatted date (write)');

$source = Sympa::Database::SQLite->new(
	db_name => File::Temp->new(),
);
ok(!defined $source->connect(), 'no connection without DBD::SQLite');
