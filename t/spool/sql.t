#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use Test::More;
use Test::Exception;

use Sympa::Database;
use Sympa::Spool::SQL;

# init sqlite database
my $file = File::Temp->new(UNLINK => $ENV{TEST_DEBUG} ? 0 : 1);
#system("sqlite3 $file < src/bin/create_db.SQLite");

# init datasource
my $base = Sympa::Database->create(
	db_type => 'SQLite',
	db_name => $file,
);
plan(skip_all => 'unable to create database') unless $base;

plan tests => 3;

my $spool;

throws_ok {
	$spool = Sympa::Spool::SQL->new();
} qr/^missing base parameter/,
'missing base parameter';

lives_ok {
	$spool = Sympa::Spool::SQL->new(
	    name => 'bounce',
	    base => $base
	);
}
'all parameters OK';

isa_ok($spool, 'Sympa::Spool::SQL');
