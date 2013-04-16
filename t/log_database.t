#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: datasource_sqlite.t 8918 2013-03-19 13:30:30Z rousse $

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use File::Temp;
use Test::More;

use Sympa::Log::Database;
use Sympa::Log::Database::Iterator;
use Sympa::Datasource::SQL;

# init sqlite database
my $file = File::Temp->new(UNLINK => $ENV{TEST_DEBUG} ? 0 : 1);
system("sqlite3 $file < src/bin/create_db.SQLite");

# init datasource
my $source = Sympa::Datasource::SQL->create(
	db_type => 'SQLite',
	db_name => $file,
);
plan(skip_all => 'unable to create database') unless $source;
my $dbh = $source->establish_connection();

plan tests => 28;

Sympa::Log::Database::init(source => $source);

cmp_ok(get_row_count("logs_table"), '==', 0, "no message in database");

is_deeply(
	[ Sympa::Log::Database::get_log_date() ],
	[ undef, undef ],
	"neither minimal nor maximal log date"
);

ok(
	Sympa::Log::Database::add_event(
		daemon       => 'sympa',
		list         => 'list',
		action       => 'process_message',
		target_email => "",
		msg_id       => '',
		status       => 'error',
		error_type   => 'unable_create_message',
		user_email   => '',
		client       => '127.0.0.1'
	),
	'add a log message, no robot'
);

cmp_ok(get_row_count("logs_table"), '==', 1, 'one log record in database');

my $second_message_time = time();
ok(
	Sympa::Log::Database::add_event(
		daemon       => 'sympa',
		list         => 'list',
		action       => 'process_message',
		target_email => '',
		msg_id       => '',
		status       => 'error',
		error_type   => 'unable_create_message',
		user_email   => '',
		client       => '127.0.0.1',
		robot        => 'robot'
	),
	'add another log message, explicit robot'
);

cmp_ok(get_row_count("logs_table"), '==', 2, 'two log records in database');

my ($min, $max) = Sympa::Log::Database::get_log_date();
ok($min == $max, "identical minimum and maximum log dates");

my $iterator;

$iterator = Sympa::Log::Database::Iterator->new(source => $source);
ok($iterator, 'event iterator creation, no criteria');
ok(!defined $iterator->get_next(),'no matching event');

$iterator = Sympa::Log::Database::Iterator->new(
	source => $source,
	ip     => '127.0.0.1'
);
ok($iterator, 'event iterator creation, adress criteria');
ok(!defined $iterator->get_next(),'no matching event');

$iterator = Sympa::Log::Database::Iterator->new(
	source => $source,
	robot => 'robot',
);
ok($iterator, 'event iterator creation, robot criteria');
ok(!defined $iterator->get_next(),'no matching event');

$iterator = Sympa::Log::Database::Iterator->new(
	source => $source,
	ip    => '127.0.0.1',
	robot => 'robot'
);
ok($iterator, 'event iterator creation, address and robot criteria');
is_deeply(
	$iterator->get_next(),
	{
		'date'         => $second_message_time,
		'status'       => 'error',
		'target_email' => '',
		'client'       => '127.0.0.1',
		'parameters'   => '',
		'user_email'   => 'anonymous',
		'action'       => 'process_message',
		'msg_id'       => '',
		'daemon'       => 'sympa',
		'error_type'   => 'unable_create_message',
		'date_logs'    => $second_message_time,
		'robot'        => 'robot',
		'list'         => 'list'
	},
	'first matching eventl'
);
ok(!defined $iterator->get_next(),'no more matching event');

ok(
	Sympa::Log::Database::delete_events(1),
	'delete log messages older than one month'
);
cmp_ok(get_row_count("logs_table"), '==', 2, 'two log records in database');

ok(
	Sympa::Log::Database::delete_events(0),
	"delete all log messages"
);
cmp_ok(get_row_count("logs_table"), '==', 0, "no more log records in database");

my $stat_start_time = time();

ok(
	Sympa::Log::Database::add_stat(
		daemon     => 'daemon',
		list       => 'list',
		operation  => 'send_mail',
		parameter  => '',
		mail       => 'test@cru.fr',
		client     => '127.0.0.1'
	),
	'add a stat message'
);

cmp_ok(get_row_count("stat_table"), '==', 1, "one stat record in database");

ok(
	Sympa::Log::Database::add_stat(
		daemon     => 'daemon',
		list       => 'list',
		operation  => 'add_subscriber',
		parameter  => '',
		mail       => 'test@cru.fr',
		client     => '127.0.0.1'
	),
	'add another stat message'
);

cmp_ok(get_row_count("stat_table"), '==', 2, "two stat records in database");

cmp_ok(get_row_count("stat_counter_table"), '==', 0, "no stat counter record in database");

my $stat_stop_time = time();

ok(
	Sympa::Log::Database::aggregate_stats(),
	'data aggregation, no date provided'
);

ok(
	Sympa::Log::Database::aggregate_stats($stat_start_time, $stat_stop_time),
	'data aggregation, dates provided'
);

cmp_ok(get_row_count("stat_counter_table"), '==', 2, "two stat counter records in database");

sub get_row_count {
	my ($table) = @_;

	my @row = $dbh->selectrow_array("SELECT COUNT(*) from $table");
	return $row[0];
}
