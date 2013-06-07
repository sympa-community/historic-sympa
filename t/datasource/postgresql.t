#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use Test::More;
use Test::Without::Module qw(DBD::Pg);

use Sympa::Datasource::SQL;

plan tests => 37;

my $source;

$source = Sympa::Datasource::SQL->create(db_type => 'Pg', db_name => 'foo');
ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::PostgreSQL');

$source = Sympa::Datasource::SQL::PostgreSQL->new(db_name => 'foo');
ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::PostgreSQL');

$source->build_connect_string();
is($source->{connect_string}, 'DBI:Pg:dbname=foo;host=', 'connect string');

my $clause;
$clause = $source->get_substring_clause(
	source_field     => 'foo',
	separator        => ',',
	substring_length => 5
);
is(
	$clause,
	"SUBSTRING(foo FROM position(',' IN foo) FOR 5)",
	'substring clause'
);

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
is($date, "date_part('epoch',666)", 'formatted date (read)');

$date = $source->get_formatted_date(
	target => 666,
	mode   => 'write'
);
is(
	$date,
	"'epoch'::timestamp with time zone + '666 sec'",
	'formatted date (write)'
);

my $dbh;
$source = Sympa::Datasource::SQL::PostgreSQL->new();
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_name');

$source = Sympa::Datasource::SQL::PostgreSQL->new(
	db_name => 'foo',
);
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_host');

$source = Sympa::Datasource::SQL::PostgreSQL->new(
	db_name => 'foo',
	db_host => 'localhost',
);
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_user');

$source = Sympa::Datasource::SQL::PostgreSQL->new(
	db_name => 'foo',
	db_host => 'localhost',
	db_user => 'user',
);
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without DBD::Pg');

# re-enable DBD::Pg loading
# string-form mandatory for delayed loading
eval "no Test::Without::Module qw(DBD::Pg)";

eval { require DBD::Pg; };

SKIP: {
	if      ($EVAL_ERROR) {
		skip 'DBD::Pg required',                    21,
	} elsif (!$ENV{DB_NAME}) {
		skip 'DB_NAME environment variable needed', 21;
	} elsif (!$ENV{DB_HOST}) {
		skip 'DB_HOST environment variable needed', 21;
	} elsif (!$ENV{DB_USER}) {
		skip 'DB_USER environment variable needed', 21;
	}

	$source = Sympa::Datasource::SQL::PostgreSQL->new(
		db_name   => $ENV{DB_NAME},
		db_host   => $ENV{DB_HOST},
		db_user   => $ENV{DB_USER},
		db_passwd => $ENV{DB_PASS},
	);
	$dbh = $source->establish_connection();

	ok(defined $dbh, 'establish connection');
	isa_ok($dbh, 'DBI::db');

	BAIL_OUT("unable to connect to database $ENV{DB_NAME} on $ENV{DB_HOST}")
		unless $dbh;

	# start from empty database
	cleanup($dbh);

	my @tables = $source->get_tables();
	cmp_ok(@tables, '==', 0, 'initial tables list');

	my $result;
	$result = $source->add_table(table => 'table1');
	is(
		$result,
		"Table table1 created",
		'table creation'
	);

	@tables = $source->get_tables();
	is_deeply(
		\@tables,
		[ qw/table1/ ],
		'tables list after table creation'
	);

	$result = $source->get_fields(table => 'table1');
	is_deeply(
		$result,
		{ temporary => 'int4' },
		'fields list after table creation'
	);

	$result = $source->add_field(
		table   => 'table1',
		field   => 'id',
		type    => 'int',
		autoinc => 1,
		primary => 1,
	);
	is(
		$result,
		'Field id added to table table1',
		'field id creation'
	);

	$result = $source->add_field(
		table   => 'table1',
		field   => 'data',
		type    => 'char(30)',
		notnull => 1
	);
	is(
		$result,
		'Field data added to table table1',
		'field data creation'
	);

	$result = $source->get_fields(table => 'table1');
	is_deeply(
		$result,
		{
			temporary => 'int4',
			id        => 'int4',
			data      => 'bpchar',
		},
		'fields list after fields creation'
	);

	$result = $source->is_autoinc(
		table => 'table1',
		field => 'id',
	);
	ok($result, "id is autoinc");

	$result = $result = $source->is_autoinc(
		table => 'table1',
		field => 'data',
	);
	ok(!$result, "data is not autoinc");

	$result = $source->get_primary_key(table => 'table1');
	is_deeply(
		$result,
		{ id => 1 },
		'initial primary key list'
	);

	$result = $source->get_indexes(table => 'table1');
	is_deeply(
		$result,
		{ },
		'initial indexes list'
	);

	$result = $source->set_index(
		table      => 'table1',
		index_name => 'index1',
		fields     => [ qw/data/ ]
	);
	is(
		$result,
		"Index set as data on table table1",
		'index creation'
	);

	$result = $source->get_indexes(table => 'table1');
	is_deeply(
		$result,
		{ index1 => { data => 1 } },
		'indexes list after index creation'
	);

	$result = $source->delete_field(
		table => 'table1',
		field => 'data',
	);
	ok($result, "field data deletion");

	$result = $source->delete_field(
		table => 'table1',
		field => 'id',
	);
	ok($result, "field id deletion");

	$result = $source->get_fields(table => 'table1');
	is_deeply(
		$result,
		{
			temporary => 'int4',
		},
		'fields list after field deletion'
	);

	$result = $source->get_primary_key(table => 'table1');
	is_deeply(
		$result,
		{ },
		'primary key list after field deletion'
	);

	$result = $source->get_indexes(table => 'table1');
	is_deeply(
		$result,
		{ },
		'indexes list after field deletion'
	);

	my $report = $source->probe();
	ok(defined $report, 'database structure initialisation');

	cleanup($dbh) if !$ENV{TEST_DEBUG};
};

sub cleanup {
	my ($dbh) = @_;

	foreach my $table ($source->get_tables()) {
		$dbh->do("DROP TABLE $table");
	}
}
