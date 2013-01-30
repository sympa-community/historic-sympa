#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use Test::More;
use Test::Without::Module qw(DBD::mysql);

use Sympa::Datasource::SQL;

plan tests => 34;

my $source = Sympa::Datasource::SQL->new({
	db_type => 'mysql',
	db_name => 'foo'
});
ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::MySQL');

$source->build_connect_string();
is($source->{connect_string}, 'DBI:mysql:foo:', 'connect string');

my $clause;
$clause = $source->get_substring_clause({
	source_field     => 'foo',
	separator        => ',',
	substring_length => 5
});
is(
	$clause,
	"REVERSE(SUBSTRING(foo FROM position(',' IN foo) FOR 5))",
	'substring clause'
);

$clause = $source->get_limit_clause({
	rows_count => 5
});
is($clause, "LIMIT 5", 'limit clause');

$clause = $source->get_limit_clause({
	rows_count => 5,
	offset     => 3
});
is($clause, "LIMIT 3,5", 'limit clause');

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
	db_type => 'mysql',
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_name');

$source = Sympa::Datasource::SQL->new({
	db_type => 'mysql',
	db_name => 'foo',
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_host');

$source = Sympa::Datasource::SQL->new({
	db_type => 'mysql',
	db_name => 'foo',
	db_host => 'localhost',
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_user');

$source = Sympa::Datasource::SQL->new({
	db_type => 'mysql',
	db_name => 'foo',
	db_host => 'localhost',
	db_user => 'user',
    });
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without DBD::mysql');

# re-enable DBD::mysql loading
# string-form mandatory for delayed loading
eval "no Test::Without::Module qw(DBD::mysql)";

eval { require DBD::mysql; };

SKIP: {
	if      ($EVAL_ERROR) {
		skip 'DBD::mysql required',                 17;
	} elsif (!$ENV{DB_NAME}) {
		skip 'DB_NAME environment variable needed', 17;
	} elsif (!$ENV{DB_HOST}) {
		skip 'DB_HOST environment variable needed', 17;
	} elsif (!$ENV{DB_USER}) {
		skip 'DB_USER environment variable needed', 17;
	}

	$source = Sympa::Datasource::SQL->new({
		db_type   => 'mysql',
		db_name   => $ENV{DB_NAME},
		db_host   => $ENV{DB_HOST},
		db_user   => $ENV{DB_USER},
		db_passwd => $ENV{DB_PASS},
	});
	$dbh = $source->establish_connection();

	ok(defined $dbh, 'establish connection');
	isa_ok($dbh, 'DBI::db');

	BAIL_OUT("unable to connect to database $ENV{DB_NAME} on $ENV{DB_HOST}")
		unless $dbh;

	# start from empty database
	my $tables = $source->get_tables();
	foreach my $table (@$tables) {
		$dbh->do("DROP TABLE $table");
	}

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
		"Table table1 created in database $ENV{DB_NAME}",
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
		{ temporary => 'int(11)' },
		'fields list after table creation'
	);

	$result = $source->add_field({
		table   => 'table1',
		field   => 'id',
		type    => 'int',
		autoinc => 1,
		primary => 1,
	});
	is(
		$result,
		'Field id added to table table1 (options: AUTO_INCREMENT PRIMARY KEY)',
		'field id creation'
	);

	$result = $source->add_field({
		table   => 'table1',
		field   => 'data',
		type    => 'char(30)',
		notnull => 1
	});
	is(
		$result,
		'Field data added to table table1 (options: NOT NULL)',
		'field data creation'
	);

	$result = $source->get_fields({ table => 'table1' });
	is_deeply(
		$result,
		{
			temporary => 'int(11)',
			id        => 'int(11)',
			data      => 'char(30)',
		},
		'fields list after fields creation'
	);

	$result = $result = $source->is_autoinc({
		table => 'table1',
		field => 'id',
	});
	ok($result, "id is autoinc");

	$result = $result = $source->is_autoinc({
		table => 'table1',
		field => 'data',
	});
	ok(!$result, "data is not autoinc");

	$result = $source->get_primary_key({ table => 'table1' });
	is_deeply(
		$result,
		{ id => 1 },
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
	ok($result, "field data deletion");

	$result = $source->delete_field({
		table => 'table1',
		field => 'id',
	});
	ok($result, "field id deletion");

	$result = $source->get_fields({ table => 'table1' });
	is_deeply(
		$result,
		{
			temporary => 'int(11)',
		},
		'fields list after field deletion'
	);

	$result = $source->get_primary_key({ table => 'table1' });
	is_deeply(
		$result,
		{ },
		'primary key list after field deletion'
	);

	$result = $source->get_indexes({ table => 'table1' });
	is_deeply(
		$result,
		{ },
		'indexes list after field deletion'
	);

	if (!$ENV{TEST_DEBUG}) {
		my $tables = $source->get_tables();
		foreach my $table (@$tables) {
			$dbh->do("DROP TABLE $table");
		}
	}
};

