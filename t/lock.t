#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use File::Temp;
use Test::More;
use Test::Exception;

use Sympa::Lock;

plan tests => 6;

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
        $main_file
    );
} qr/^missing method parameter/,
'missing method parameter';

ok(!-f $lock_file, "underlying lock file doesn't exist");

lives_ok {
    $lock = Sympa::Lock->new(
        $main_file,
        'anything'
    );
}
'all parameters OK';

isa_ok($lock, 'Sympa::Lock');

ok(-f $lock_file, "underlying lock file does exist");
