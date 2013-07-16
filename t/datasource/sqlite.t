#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use English qw(-no_match_vars);
use File::Temp;
use Test::Exception;
use Test::More;
use Test::Without::Module qw(DBD::SQLite);

use Sympa::Datasource::SQL;

plan tests => 11;

my $source;

throws_ok {
	$source = Sympa::Datasource::SQL->create();
} qr/^missing db_type parameter/,
'missing db_name parameter';

throws_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'sqlite',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

lives_ok {
	$source = Sympa::Datasource::SQL->create(
		db_type => 'sqlite',
		db_name => 'foo',
		db_host => 'localhost',
		db_user => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::SQLite');

throws_ok {
	$source = Sympa::Datasource::SQL::SQLite->new(
		db_host => 'localhost',
		db_user => 'foo',
	);
} qr/^missing db_name parameter/,
'missing db_name parameter';

lives_ok {
	$source = Sympa::Datasource::SQL::SQLite->new(
		db_host => 'localhost',
		db_user => 'foo',
		db_name => 'foo',
	);
} 'all needed parameters';

ok($source, 'source is defined');
isa_ok($source, 'Sympa::Datasource::SQL::SQLite');

is(
	$source->get_connect_string(),
	'DBI:SQLite:dbname=foo',
	'connect string'
);

$source = Sympa::Datasource::SQL::SQLite->new(
	db_name => File::Temp->new(),
);
ok(!defined $source->connect(), 'no connection without DBD::SQLite');
