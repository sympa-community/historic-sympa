#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use Test::More;

use Sympa::Datasource::SQL;
use Sympa::Datasource::SQL::PostgreSQL;

eval { require DBD::Pg; };
plan(skip_all => 'DBD::Pg required') if $EVAL_ERROR;
plan(skip_all => 'DB_NAME environment variable needed') if !$ENV{DB_NAME};
plan(skip_all => 'DB_HOST environment variable needed') if !$ENV{DB_HOST};
plan(skip_all => 'DB_USER environment variable needed') if !$ENV{DB_USER};
plan tests => 23;

my $source = Sympa::Datasource::SQL::PostgreSQL->new(
	db_name   => $ENV{DB_NAME},
	db_host   => $ENV{DB_HOST},
	db_user   => $ENV{DB_USER},
	db_passwd => $ENV{DB_PASS},
);
my $dbh = $source->establish_connection();

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

cleanup($dbh);

my $report = $source->probe();
ok(defined $report, 'database structure initialisation');

cmp_ok(scalar @$report, '==', 408, 'event count in report');

@tables = sort $source->get_tables();
is_deeply(
	\@tables,
	[ qw/
		admin_table
		bulkmailer_table
		conf_table
		exclusion_table
		list_table
		logs_table
		netidmap_table
		notification_table
		oauthconsumer_sessions_table
		oauthprovider_nonces_table
		oauthprovider_sessions_table
		one_time_ticket_table
		session_table
		spool_table
		stat_counter_table
		stat_table
		subscriber_table
		user_table
	/ ],
	'tables list after table creation'
);

cleanup($dbh) if !$ENV{TEST_DEBUG};

sub cleanup {
	my ($dbh) = @_;

	foreach my $table ($source->get_tables()) {
		$dbh->do("DROP TABLE $table");
	}
}
