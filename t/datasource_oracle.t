#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use Test::More;

use Sympa::Datasource::SQL;

plan tests => 14;

my $source = Sympa::Datasource::SQL->new({db_type => 'Oracle', db_name => 'foo'});
ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::Oracle');

$source->build_connect_string();
is($source->{connect_string}, 'DBI:Oracle:', 'connect string');

my $clause;
$clause = $source->get_substring_clause({
	source_field     => 'foo',
	separator        => ',',
	substring_length => 5
});
is(
	$clause,
	"substr(foo,instr(foo,',')+1)",
	'substring clause'
);

$clause = $source->get_limit_clause({
	rows_count => 5
});
is($clause, "", 'limit clause');

$clause = $source->get_limit_clause({
	rows_count => 5,
	offset     => 3
});
is($clause, "", 'limit clause');

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
	db_type => 'Oracle',
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_name');

$source = Sympa::Datasource::SQL->new({
	db_type => 'Oracle',
	db_name => 'foo',
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_host');

$source = Sympa::Datasource::SQL->new({
	db_type => 'Oracle',
	db_name => 'foo',
	db_host => 'localhost',
});
$dbh = $source->establish_connection();
ok(!defined $dbh, 'no connection without db_user');

eval { require DBD::Oracle; };
my $have_dbd = !$EVAL_ERROR;

SKIP: {
	skip "DBD::Oracle available", 1 if $have_dbd;

	$source = Sympa::Datasource::SQL->new({
		db_type => 'Oracle',
		db_name => 'foo',
		db_host => 'localhost',
		db_host => 'user',
	});
	$dbh = $source->establish_connection();
	ok(!defined $dbh, 'no connection without DBD::Oracle');
};
