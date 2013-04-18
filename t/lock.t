#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use File::Temp;
use Test::More;
use Test::Exception;

use Sympa::Lock;

plan tests => 24;

my $lock;
my $temp_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
my $main_file = $temp_dir . '/file';
my $lock_file = $main_file . '.lock';

throws_ok {
    $lock = Sympa::Lock->new();
} qr/^missing filepath parameter/,
'missing filepath parameter';

throws_ok {
    $lock = Sympa::Lock->new(
        path   => $main_file,
	method => 'something'
    );
} qr/^invalid method parameter/,
'invalid method parameter';

ok(!-f $lock_file, "underlying lock file doesn't exist");

lives_ok {
    $lock = Sympa::Lock->new(
        path => $main_file,
    );
}
'all parameters OK';

isa_ok($lock, 'Sympa::Lock');
can_ok($lock, 'set_timeout');
can_ok($lock, 'lock');
can_ok($lock, 'unlock');

ok(-f $lock_file, "underlying lock file does exist");

ok($lock->lock(), 'locking, unspecified mode');
cmp_ok($lock->get_lock_count(), '==', 1, 'locks mode');
ok($lock->lock('anything'), 'locking, irrelevant mode');
cmp_ok($lock->get_lock_count(), '==', 2, 'locks count');
ok($lock->lock('read'), 'locking, read mode');
cmp_ok($lock->get_lock_count(), '==', 3, 'locks count');
ok($lock->lock('write'), 'locking, write mode');
cmp_ok($lock->get_lock_count(), '==', 4, 'locks count');

ok(attempt_parallel_lock('/tmp/foo', 'write'), 'write lock on another file');
ok(!attempt_parallel_lock($main_file, 'read'), 'read lock on same file');
ok(!attempt_parallel_lock($main_file, 'write'), 'write lock on same file');

my $another_lock = Sympa::Lock->new(
	path => $main_file,
);
cmp_ok($another_lock->get_lock_count(), '==', 4, 'lock count, new lock');
ok($another_lock->unlock(), 'unlocking, new lock');
cmp_ok($another_lock->get_lock_count(), '==', 3, 'lock count, new lock');
cmp_ok($lock->get_lock_count(),         '==', 3, 'lock count, original lock');

sub attempt_parallel_lock {
	my ($file, $mode) = @_;

	my $code = <<EOF;
my \$lock = Sympa::Lock->new(path => "$file");
\$lock->set_timeout(-1);
exit \$lock->lock("$mode");
EOF
	my @command = (
		$EXECUTABLE_NAME,
		"-I", "$Bin/../src/lib",
		"-MSympa::Lock",
		"-e", $code
	);
	system(@command);
	return $CHILD_ERROR >> 8;
}
