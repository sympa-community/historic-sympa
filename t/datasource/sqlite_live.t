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
plan tests => 23;

my $file = File::Temp->new(UNLINK => $ENV{TEST_DEBUG} ? 0 : 1);
my $source = Sympa::Datasource::SQL::SQLite->new(
	db_name => $file,
);
my $dbh = $source->connect();

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
			type          => 'integer',
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
ok($result, "id is autoinc");

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
cleanup($dbh);

my $report = $source->probe();
ok(defined $report, "database structure initialisation failure");

cmp_ok(scalar @$report, '==', 21, 'event count in report');

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

is_deeply(
	$source->get_fields(table => 'subscriber_table'),
	{
		user_subscriber               => 'text',
		list_subscriber               => 'text',
		robot_subscriber              => 'text',
		reception_subscriber          => 'text',
		suspend_subscriber            => 'numeric',
		suspend_start_date_subscriber => 'integer',
		suspend_end_date_subscriber   => 'integer',
		bounce_subscriber             => 'text',
		bounce_score_subscriber       => 'integer',
		bounce_address_subscriber     => 'text',
		date_subscriber               => 'numeric',
		update_subscriber             => 'numeric',
		comment_subscriber            => 'text',
		number_messages_subscriber    => 'integer',
		visibility_subscriber         => 'text',
		topics_subscriber             => 'text',
		subscribed_subscriber         => 'numeric',
		included_subscriber           => 'numeric',
		include_sources_subscriber    => 'text',
		custom_attribute_subscriber   => 'text',
	},
	'admin_table table structure'
);

is_deeply(
	$source->get_fields(table => 'notification_table'),
	{
		pk_notification               => 'integer',
		message_id_notification       => 'text',
		recipient_notification        => 'text',
		reception_option_notification => 'text',
		status_notification           => 'text',
		arrival_date_notification     => 'text',
		type_notification             => 'text',
		message_notification          => 'text',
		list_notification             => 'text',
		robot_notification            => 'text',
		date_notification             => 'integer',
	},
	'notification_table table structure'
);

$result = $source->is_autoinc(
	table => 'notification_table',
	field => 'pk_notification',
);
ok($result, "pk_notification is autoincremented");

sub cleanup {
	my ($dbh) = @_;

	foreach my $table ($source->get_tables()) {
		$dbh->do("DROP TABLE $table");
	}
}
