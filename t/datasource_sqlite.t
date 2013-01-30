#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use File::Temp;
use Test::More;
use Test::Without::Module qw(DBD::SQLite);

use Sympa::Datasource::SQL;

plan tests => 31;

my $source = Sympa::Datasource::SQL->new({
	db_type => 'SQLite',
	db_name => 'foo'
});
ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::SQLite');

$source->build_connect_string();
is($source->{connect_string}, 'DBI:SQLite:dbname=foo', 'connect string');

my $clause;
$clause = $source->get_substring_clause({
	source_field     => 'foo',
	separator        => ',',
	substring_length => 5
});
is($clause, "substr(foo,func_index(foo,',')+1,5)", 'substring clause');

$clause = $source->get_limit_clause({
	rows_count => 5
});
is($clause, "LIMIT 5", 'limit clause');

$clause = $source->get_limit_clause({
	rows_count => 5,
	offset     => 3
});
is($clause, "LIMIT 5 OFFSET 3", 'limit clause');

my $date;
$date = $source->get_formatted_date({
        target => 666,
});
ok(!defined $date, 'formatted date (no mode)');

$date = $source->get_formatted_date({
	target => 666,
	mode   => 'foo'
});
ok(!defined $date, 'formatted date (invalid mode)');

$date = $source->get_formatted_date({
	target => 666,
	mode   => 'read'
});
is($date, "UNIX_TIMESTAMP(666)", 'formatted date (read)');

$date = $source->get_formatted_date({
	target => 666,
	mode   => 'write'
});
is($date, "FROM_UNIXTIME(666)", 'formatted date (write)');

my $dbh;
$source = Sympa::Datasource::SQL->new({
	db_type => 'SQLite',
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_name');

$source = Sympa::Datasource::SQL->new({
	db_type => 'SQLite',
	db_name => File::Temp->new(),
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without DBD::SQLite');

# re-enable DBD::SQLite loading
# string-form mandatory for delayed loading
eval "no Test::Without::Module qw(DBD::SQLite)";

eval { require DBD::SQLite; };

SKIP: {
	skip 'DBD::SQLite required', 8 if $EVAL_ERROR;

	my $file = File::Temp->new(UNLINK => $ENV{TEST_DEBUG} ? 0 : 1);
	$source = Sympa::Datasource::SQL->new({
		db_type => 'SQLite',
		db_name => $file,
	});
	$dbh = $source->establish_connection();

	ok(defined $dbh, 'establish connection');
	isa_ok($dbh, 'DBI::db');

	my $result;
	$result = $source->get_tables();
	is_deeply(
		$result,
		[ ],
		'initial tables list'
	);

	$result = $source->add_table({ table => 'table1' });
	is(
		$result,
		"Table table1 created in database $file",
		'table creation'
	);

	$result = $source->get_tables();
	is_deeply(
		$result,
		[ qw/table1/ ],
		'tables list after table creation'
	);

	$result = $source->get_fields({ table => 'table1' });
	is_deeply(
		$result,
		{ temporary => 'numeric' },
		'fields list after table creation'
	);

	$result = $source->add_field({
		table   => 'table1',
		field   => 'id',
		type    => 'int',
		autoinc => 1,
		primary => 1,
	});
	ok(
		!defined $result,
		'field id creation failure (primary key issue)'
	);

	$result = $source->add_field({
		table   => 'table1',
		field   => 'id',
		type    => 'int',
		autoinc => 1,
	});
	is(
		$result,
		'Field id added to table table1 (options: AUTO_INCREMENT)',
		'field id creation'
	);

	$result = $source->add_field({
		table   => 'table1',
		field   => 'data',
		type    => 'char(30)',
		notnull => 1
	});
	ok(
		!defined $result,
		'field data creation failure (not null issue)'
	);

		$result = $source->add_field({
		table   => 'table1',
		field   => 'data',
		type    => 'char(30)',
	});
	is(
		$result,
		'Field data added to table table1 (options: )',
		'field data creation'
	);

	$result = $source->get_fields({ table => 'table1' });
	is_deeply(
		$result,
		{
			temporary => 'numeric',
			id        => 'integer',
			data      => 'text',
		},
		'fields list after fields creation'
	);

	$result = $result = $source->is_autoinc({
		table => 'table1',
		field => 'id',
	});
	ok(defined $result && $result, "id is autoinc");

	$result = $result = $source->is_autoinc({
		table => 'table1',
		field => 'data',
	});
	ok(defined $result && !$result, "data is not autoinc");

	$result = $source->get_primary_key({ table => 'table1' });
	is_deeply(
		$result,
		{ },
		'initial primary key list'
	);

	$result = $source->get_indexes({ table => 'table1' });
	is_deeply(
		$result,
		{ },
		'initial indexes list'
	);

	$result = $source->set_index({
		table      => 'table1',
		index_name => 'index1',
		fields     => [ qw/data/ ]
	});
	is(
		$result,
		"Table table1, index %s set using data",
		'index creation'
	);

	$result = $source->get_indexes({ table => 'table1' });
	is_deeply(
		$result,
		{ index1 => { data => 1 } },
		'indexes list after index creation'
	);

	$result = $source->delete_field({
		table => 'table1',
		field => 'data',
	});
	ok(!defined $result, "field data deletion failure");

	$result = $source->delete_field({
		table => 'table1',
		field => 'id',
	});
	ok(!defined $result, "field id deletion failure");

};
