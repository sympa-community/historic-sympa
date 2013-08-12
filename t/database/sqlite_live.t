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
use Test::Exception;

use Sympa::Database;
use Sympa::Database::SQLite;

eval { require DBD::SQLite; };

plan(skip_all => 'DBD::SQLite required') if $EVAL_ERROR;
plan tests => 22;

my $file = File::Temp->new(UNLINK => $ENV{TEST_DEBUG} ? 0 : 1);
my $base = Sympa::Database::SQLite->new(
	db_name => $file,
);
my $result = $base->connect();
ok($result, 'establish connection');

my @tables = $base->get_tables();
cmp_ok(@tables, '==', 0, 'initial tables list');

my $result;
$result = $base->add_table(
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

@tables = $base->get_tables();
is_deeply(
	\@tables,
	[ qw/table1/ ],
	'tables list after table creation'
);

$result = $base->get_fields(table => 'table1');
is_deeply(
	$result,
	{
		id => 'integer',
	},
	'initial fields list'
);

throws_ok {
	$result = $base->add_field(
		table   => 'table1',
		field   => 'data',
		type    => 'char(30)',
		notnull => 1
	);
} qr/Cannot add a NOT NULL column with default value NULL/,
'field data creation failure (not null issue)';

$result = $base->add_field(
	table   => 'table1',
	field   => 'data',
	type    => 'char(30)',
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
		id   => 'integer',
		data => 'text',
	},
	'fields list after fields creation'
);

$result = $result = $base->is_autoinc(
	table => 'table1',
	field => 'id',
);
ok($result, "id is autoinc");

$result = $result = $base->is_autoinc(
	table => 'table1',
	field => 'data',
);
ok(defined $result && !$result, "data is not autoinc");

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

throws_ok {
	$result = $base->delete_field(
		table => 'table1',
		field => 'data',
	);
} qr/unsupported operation/;
"field data deletion failure";

throws_ok {
	$result = $base->delete_field(
		table => 'table1',
		field => 'id',
	);
} qr/unsupported operation/,
"field id deletion failure";

cleanup($base);

my $report = $base->probe();
ok(defined $report, "database structure initialisation failure");

cmp_ok(scalar @$report, '==', 21, 'event count in report');

@tables = sort $base->get_tables();
is_deeply(
	\@tables,
	[ qw/
		admin_table
		bulkpacket_table
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
	$base->get_fields(table => 'notification_table'),
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

$result = $base->is_autoinc(
	table => 'notification_table',
	field => 'pk_notification',
);
ok($result, "pk_notification is autoincremented");

sub cleanup {
	my ($base) = @_;

	foreach my $table ($base->get_tables()) {
		$base->execute_query("DROP TABLE $table");
	}
}
