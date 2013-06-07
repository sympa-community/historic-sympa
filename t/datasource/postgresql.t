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

plan tests => 16;

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

sub cleanup {
	my ($dbh) = @_;

	foreach my $table ($source->get_tables()) {
		$dbh->do("DROP TABLE $table");
	}
}
