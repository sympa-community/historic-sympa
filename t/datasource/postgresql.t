#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use Test::Exception;
use Test::More;
use Test::Without::Module qw(DBD::Pg);

use Sympa::Datasource::SQL;

plan tests => 15;

my $source;

throws_ok {
	$source = Sympa::Datasource::SQL->create();
} qr/^missing db_type parameter/,
'missing db_name parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'pg',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'pg',
		db_name => 'foo',
	);
} qr/^missing db_host parameter/,
'missing db_host parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'pg',
		db_name => 'foo',
		db_host => 'localhost',
	);
} qr/^missing db_user parameter/,
'missing db_user parameter';

lives_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'pg',
		db_name => 'foo',
		db_host => 'localhost',
		db_user => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::PostgreSQL');

throws_ok {
	$source = Sympa::Datasource::SQL::PostgreSQL->new();
} qr/^missing db_host parameter/,
'missing db_host parameter';

throws_ok {
	$source = Sympa::Datasource::SQL::PostgreSQL->new(
		db_host => 'localhost',
	);
} qr/^missing db_user parameter/,
'missing db_user parameter';

throws_ok {
	$source = Sympa::Datasource::SQL::PostgreSQL->new(
		db_host => 'localhost',
		db_user => 'foo',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

lives_ok {
	$source = Sympa::Datasource::SQL::PostgreSQL->new(
		db_host => 'localhost',
		db_user => 'foo',
		db_name => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::PostgreSQL');

is($source->get_connect_string(), 'DBI:Pg:dbname=foo;host=localhost', 'connect string');

$source = Sympa::Datasource::SQL::PostgreSQL->new(
	db_name => 'foo',
	db_host => 'localhost',
	db_user => 'user',
);
ok(!defined $source->connect(), 'no connection without DBD::Pg');
