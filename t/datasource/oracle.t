#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use Test::Exception;
use Test::More;

use Sympa::Datasource::SQL;

plan tests => 22;

my $source;

my $source;

throws_ok {
	$source = Sympa::Datasource::SQL->create();
} qr/^missing db_type parameter/,
'missing db_name parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'oracle',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'oracle',
		db_name => 'foo',
	);
} qr/^missing db_host parameter/,
'missing db_host parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'oracle',
		db_name => 'foo',
		db_host => 'localhost',
	);
} qr/^missing db_user parameter/,
'missing db_user parameter';

lives_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'oracle',
		db_name => 'foo',
		db_host => 'localhost',
		db_user => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::Oracle');

throws_ok {
	$source = Sympa::Datasource::SQL::Oracle->new();
} qr/^missing db_host parameter/,
'missing db_host parameter';

throws_ok {
	$source = Sympa::Datasource::SQL::Oracle->new(
		db_host => 'localhost',
	);
} qr/^missing db_user parameter/,
'missing db_user parameter';

throws_ok {
	$source = Sympa::Datasource::SQL::Oracle->new(
		db_host => 'localhost',
		db_user => 'foo',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

lives_ok {
	$source = Sympa::Datasource::SQL::Oracle->new(
		db_host => 'localhost',
		db_user => 'foo',
		db_name => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::Oracle');

is(
	$source->get_connect_string(),
	'DBI:Oracle:host=localhost;sid=foo',
	'connect string'
);

my $clause;
$clause = $source->get_substring_clause(
	source_field     => 'foo',
	separator        => ',',
	substring_length => 5
);
is(
	$clause,
	"substr(foo,instr(foo,',')+1)",
	'substring clause'
);

$clause = $source->get_limit_clause(
	rows_count => 5
);
is($clause, "", 'limit clause');

$clause = $source->get_limit_clause(
	rows_count => 5,
	offset     => 3
);
is($clause, "", 'limit clause');

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

eval { require DBD::Oracle; };
my $have_dbd = !$EVAL_ERROR;

SKIP: {
	skip "DBD::Oracle available", 1 if $have_dbd;

	$source = Sympa::Datasource::SQL::Oracle->new(
		db_name => 'foo',
		db_host => 'localhost',
		db_user => 'user',
	);
	$dbh = $source->connect();
	ok(!defined $dbh, 'no connection without DBD::Oracle');
};
