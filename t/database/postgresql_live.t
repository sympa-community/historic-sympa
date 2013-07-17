#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use Test::More;
use Test::Exception;

use Sympa::Database;
use Sympa::Database::PostgreSQL;

eval { require DBD::Pg; };
plan(skip_all => 'DBD::Pg required') if $EVAL_ERROR;
plan(skip_all => 'DB_NAME environment variable needed') if !$ENV{DB_NAME};
plan(skip_all => 'DB_HOST environment variable needed') if !$ENV{DB_HOST};
plan(skip_all => 'DB_USER environment variable needed') if !$ENV{DB_USER};
plan tests => 37;

my $base = Sympa::Database::PostgreSQL->new(
	db_name   => $ENV{DB_NAME},
	db_host   => $ENV{DB_HOST},
	db_user   => $ENV{DB_USER},
	db_passwd => $ENV{DB_PASS},
);
my $result = $base->connect();
ok($result, 'establish connection');

BAIL_OUT("unable to connect to database $ENV{DB_NAME} on $ENV{DB_HOST}")
	unless $base;

# start from empty database
cleanup($base);

my @tables = $base->get_tables();
cmp_ok(@tables, '==', 0, 'initial tables list');

my $result;
$result = $base->add_table(
	table => 'table1',
	fields => [
		{
			name          => 'id',
			type          => 'int4',
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

@tables = $base->get_tables();
is_deeply(
	\@tables,
	[ qw/table1/ ],
	'tables list after table creation'
);

$result = $base->get_fields(table => 'table1');
is_deeply(
	$result,
	{ id => 'int4' },
	'initial fields list'
);

$result = $base->add_field(
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

$result = $base->get_fields(table => 'table1');
is_deeply(
	$result,
	{
		id   => 'int4',
		data => 'bpchar',
	},
	'fields list after fields creation'
);

$result = $base->is_autoinc(
	table => 'table1',
	field => 'id',
);
ok($result, "id is autoinc");

$result = $result = $base->is_autoinc(
	table => 'table1',
	field => 'data',
);
ok(!$result, "data is not autoinc");

$result = $base->get_primary_key(table => 'table1');
is_deeply(
	$result,
	[ 'id' ],
	'initial primary key list'
);

$result = $base->get_indexes(table => 'table1');
is_deeply(
	$result,
	{ },
	'initial indexes list'
);

$result = $base->set_index(
	table  => 'table1',
	index  => 'index1',
	fields => [ qw/data/ ]
);
is(
	$result,
	"Index index1 set on table table1 using fields data",
	'index creation'
);

$result = $base->get_indexes(table => 'table1');
is_deeply(
	$result,
	{ index1 => { data => 1 } },
	'indexes list after index creation'
);

$result = $base->delete_field(
	table => 'table1',
	field => 'data',
);
ok($result, "field data deletion");

$result = $base->delete_field(
	table => 'table1',
	field => 'id',
);
ok($result, 'field id deletion');

$result = $base->get_fields(table => 'table1');
is_deeply(
	$result,
	{
	},
	'fields list after field deletion'
);

$result = $base->get_primary_key(table => 'table1');
is_deeply(
	$result,
	[ ],
	'primary key list after field deletion'
);

$result = $base->get_indexes(table => 'table1');
is_deeply(
	$result,
	{ },
	'indexes list after field deletion'
);

# database creation, from empty schema
cleanup($base);

my $report = $base->probe();
ok(defined $report, 'database creation, from empty schema');
cmp_ok(scalar @$report, '==', 21, 'event count in report');
check_database();

# database creation, from partial schema
cleanup($base);

$base->add_table(
	table  => 'subscriber_table',
	fields => [
		{
			name    => 'user_subscriber',
			type    => 'varchar(100)',
			notnull => 1
		},
	]
);

$base->add_table(
	table  => 'notification_table',
	fields => [
		{
			name          => 'pk_notification',
			type          => 'int8',
			notnull       => 1,
			autoincrement => 1
		},
	],
	key => [ 'pk_notification' ],
);

my $report = $base->probe();
ok(defined $report, 'database creation, from partial schema');
cmp_ok(scalar @$report, '==', 47, 'event count in report');

check_database();

# database creation from wrong schema, no automatic correction
cleanup($base);

$base->add_table(
	table  => 'subscriber_table',
	fields => [
		{
			name    => 'user_subscriber',
			type    => 'int4',
			notnull => 1
		},
	]
);

$base->add_table(
	table  => 'notification_table',
	fields => [
		{
			name    => 'pk_notification',
			type    => 'int8',
			notnull => 1,
		},
	],
	key => [ 'pk_notification' ],
);

dies_ok {
	$base->probe()
} 'database creation from wrong schema, no automatic correction';

# database creation from wrong schema, with automatic correction
cleanup($base);

$base->add_table(
	table  => 'subscriber_table',
	fields => [
		{
			name    => 'user_subscriber',
			type    => 'int4',
			notnull => 1
		},
	]
);

$base->add_table(
	table  => 'notification_table',
	fields => [
		{
			name    => 'pk_notification',
			type    => 'int8',
			notnull => 1,
		},
	],
	key => [ 'pk_notification' ],
);

my $report = $base->probe(update => 'auto');
ok(
	defined $report,
       	'database creation from wrong schema, with automatic correction');

cmp_ok(scalar @$report, '==', 47, 'event count in report');

check_database();

# final cleanup
cleanup($base) if !$ENV{TEST_DEBUG};

sub cleanup {
	my ($base) = @_;

	foreach my $table ($base->get_tables()) {
		$base->execute_query("DROP TABLE $table");
	}
}

sub check_database {
	my @tables = sort $base->get_tables();
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

	is_deeply(
		$base->get_fields(table => 'subscriber_table'),
		{
			user_subscriber               => 'varchar(100)',
			list_subscriber               => 'varchar(50)',
			robot_subscriber              => 'varchar(80)',
			reception_subscriber          => 'varchar(20)',
			suspend_subscriber            => 'int4',
			suspend_start_date_subscriber => 'int4',
			suspend_end_date_subscriber   => 'int4',
			bounce_subscriber             => 'varchar(35)',
			bounce_score_subscriber       => 'int4',
			bounce_address_subscriber     => 'varchar(100)',
			date_subscriber               => 'timestamptz',
			update_subscriber             => 'timestamptz',
			comment_subscriber            => 'varchar(150)',
			number_messages_subscriber    => 'int4',
			visibility_subscriber         => 'varchar(20)',
			topics_subscriber             => 'varchar(200)',
			subscribed_subscriber         => 'int4',
			included_subscriber           => 'int4',
			include_sources_subscriber    => 'varchar(50)',
			custom_attribute_subscriber   => 'varchar(500)',
		},
		'subscriber_table table structure'
	);

	is_deeply(
		$base->get_fields(table => 'notification_table'),
		{
			pk_notification               => 'int8',
			message_id_notification       => 'varchar(100)',
			recipient_notification        => 'varchar(100)',
			reception_option_notification => 'varchar(20)',
			status_notification           => 'varchar(100)',
			arrival_date_notification     => 'varchar(80)',
			type_notification             => 'varchar(15)',
			message_notification          => 'text',
			list_notification             => 'varchar(50)',
			robot_notification            => 'varchar(80)',
			date_notification             => 'int4',
		},
		'notification_table table structure'
	);

	$result = $base->is_autoinc(
		table => 'notification_table',
		field => 'pk_notification',
	);
	ok($result, "pk_notification is autoincremented");
}
