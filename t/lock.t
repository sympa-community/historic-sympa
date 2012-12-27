#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id: datasource_mysql.t 8332 2012-12-27 14:02:35Z rousse $

use strict;

use File::Temp;
use Test::More;
use Test::Exception;

use Sympa::Lock;

plan tests => 6;

my $lock;

throws_ok {
    $lock = Sympa::Lock->new();
} qr/^missing filepath parameter/,
'missing filepath parameter';

throws_ok {
    $lock = Sympa::Lock->new(
        File::Temp->new(),
    );
} qr/^missing method parameter/,
'missing method parameter';

my $main_file = File::Temp->new();
my $lock_file = $main_file . '.lock';
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
