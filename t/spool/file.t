#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: sql.t 9585 2013-07-22 11:58:25Z rousse $

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../src/lib";

use File::Temp;
use POSIX qw(setlocale LC_ALL);
use Test::More;
use Test::Exception;

use Sympa::Spool::File;

plan tests => 17;

my $temp_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);

throws_ok {
	my $spool = Sympa::Spool::File->new();
} qr/^missing name parameter/,
'missing name parameter';

throws_ok {
	my $spool = Sympa::Spool::File->new(
		name => 'foo',
	);
} qr/^missing dir parameter/,
'missing dir parameter';

POSIX::setlocale(LC_ALL, 'C');

chmod 0555, $temp_dir->dirname();
throws_ok {
	my $spool = Sympa::Spool::File->new(
		name => 'foo',
		dir  => $temp_dir . '/foo'
	);
} qr/Permission denied/,
'unable to create a new spool directory with a read-only parent';
chmod 0755, $temp_dir->dirname();

my $unreadable_dir =  $temp_dir . '/unreadable';
mkdir $unreadable_dir;
chmod 0111, $unreadable_dir;
throws_ok {
	my $spool = Sympa::Spool::File->new(
		name => 'foo',
		dir  => $unreadable_dir
	);
} qr/unreadable directory/,
'unable to use an already-existing unreadable directory';

my $unwritable_dir =  $temp_dir . '/unwritable';
mkdir $unwritable_dir;
chmod 0555, $unwritable_dir;
throws_ok {
	my $spool = Sympa::Spool::File->new(
		name => 'foo',
		dir  => $unwritable_dir
	);
} qr/unwritable directory/,
'unable to use an already-existing unwritable directory';

my $ok_spool_dir = $temp_dir . '/foo';

ok(! -d $ok_spool_dir, "spool directory doesn't exist yet");

my $ok_spool;
lives_ok {
	$ok_spool = Sympa::Spool::File->new(
		name => 'foo',
		dir  => $ok_spool_dir
	);
} 'OK spool instanciation';
isa_ok($ok_spool, 'Sympa::Spool::File');

ok(-d $ok_spool_dir, "spool directory does exist");
is($ok_spool->get_id(), "foo/ok", "expected ok_spool id");

my $bad_spool_dir = $temp_dir . '/foo/bad';

ok(! -d $bad_spool_dir, "spool directory doesn't exist yet");

my $bad_spool;
lives_ok {
	$bad_spool = Sympa::Spool::File->new(
		name   => 'foo',
		dir    => $ok_spool_dir,
		status => 'bad'
	);
} 'Bad spool instanciation';
isa_ok($bad_spool, 'Sympa::Spool::File');

ok(-d $bad_spool_dir, "spool directory does exist");
is($bad_spool->get_id(), "foo/bad", "expected bad_spool id");


is_deeply(
	[ $ok_spool->get_files_in_spool() ],
	[],
	"initial file list is empty"
);
is_deeply(
	[ $ok_spool->get_dirs_in_spool() ],
	[ 'bad' ],
	"initial directory list contains 'bad'"
);
