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
use Test::Without::Module qw(DBD::Sybase);

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
		db_type => 'sybase',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'sybase',
		db_name => 'foo',
	);
} qr/^missing db_host parameter/,
'missing db_host parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'sybase',
		db_name => 'foo',
		db_host => 'localhost',
	);
} qr/^missing db_user parameter/,
'missing db_user parameter';

lives_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'sybase',
		db_name => 'foo',
		db_host => 'localhost',
		db_user => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::Sybase');

throws_ok {
	$source = Sympa::Datasource::SQL::Sybase->new();
} qr/^missing db_host parameter/,
'missing db_host parameter';

throws_ok {
	$source = Sympa::Datasource::SQL::Sybase->new(
		db_host => 'localhost',
	);
} qr/^missing db_user parameter/,
'missing db_user parameter';

throws_ok {
	$source = Sympa::Datasource::SQL::Sybase->new(
		db_host => 'localhost',
		db_user => 'foo',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

lives_ok {
	$source = Sympa::Datasource::SQL::Sybase->new(
		db_host => 'localhost',
		db_user => 'foo',
		db_name => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::Sybase');

is(
	$source->get_connect_string(),
	'DBI:Sybase:database=foo;server=localhost',
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
	"substring(foo,charindex(',',foo)+1,5)",
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

$source = Sympa::Datasource::SQL::Sybase->new(
	db_name => 'foo',
	db_host => 'localhost',
	db_user => 'user',
);
my $dbh = $source->connect();
ok(!defined $dbh, 'no connection without DBD::Sybase');
