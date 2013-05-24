#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: spool.t 9267 2013-05-23 07:33:03Z rousse $

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;
use Test::Exception;

use Sympa::SDM;

# init sqlite database
my $file = File::Temp->new(UNLINK => $ENV{TEST_DEBUG} ? 0 : 1);

# init datasource
my $source = Sympa::Datasource::SQL->create(
	db_type => 'SQLite',
	db_name => $file,
);
plan(skip_all => 'unable to create database') unless $source;
my $dbh = $source->establish_connection();

plan tests => 1;

my $report = Sympa::SDM::probe_db($source);
ok(defined $report);
