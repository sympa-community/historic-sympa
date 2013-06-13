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

use Sympa::Datasource::SQL;
use Sympa::Datasource::SQL::SQLite;

eval { require DBD::SQLite; };

plan(skip_all => 'DBD::SQLite required') if $EVAL_ERROR;
plan tests => 18;

my $file = File::Temp->new(UNLINK => $ENV{TEST_DEBUG} ? 0 : 1);
my $source = Sympa::Datasource::SQL::SQLite->new(
	db_name => $file,
);
my $dbh = $source->establish_connection();

ok(defined $dbh, 'establish connection');
isa_ok($dbh, 'DBI::db');

my @tables = $source->get_tables();
cmp_ok(@tables, '==', 0, 'initial tables list');

my $result;
$result = $source->add_table(
	table => 'table1',
	fields => [
		{
			name          => 'id',
			type          => 'int(11)',
			autoincrement => 1,
		},
	],
	key => [ 'id' ]
);
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
	{
		id => 'integer',
	},
	'initial fields list'
);

$result = $source->add_field(
	table   => 'table1',
	field   => 'data',
	type    => 'char(30)',
	notnull => 1
);
ok(
	!defined $result,
	'field data creation failure (not null issue)'
);

	$result = $source->add_field(
	table   => 'table1',
	field   => 'data',
	type    => 'char(30)',
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
		id   => 'integer',
		data => 'text',
	},
	'fields list after fields creation'
);

$result = $result = $source->is_autoinc(
	table => 'table1',
	field => 'id',
);
ok(defined $result && !$result, "id is autoinc");

$result = $result = $source->is_autoinc(
	table => 'table1',
	field => 'data',
);
ok(defined $result && !$result, "data is not autoinc");

$result = $source->get_primary_key(table => 'table1');
is_deeply(
	$result,
	[ ],
	'initial primary key list'
);

$result = $source->get_indexes(table => 'table1');
is_deeply(
	$result,
	{ },
	'initial indexes list'
);

$result = $source->set_index(
	table  => 'table1',
	index  => 'index1',
	fields => [ qw/data/ ]
);
is(
	$result,
	"Index index1 set as data on table table1",
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
ok(!defined $result, "field data deletion failure");

$result = $source->delete_field(
	table => 'table1',
	field => 'id',
);
ok(!defined $result, "field id deletion failure");

my $report = $source->probe();
ok(!defined $report, "database structure initialisation failure");
