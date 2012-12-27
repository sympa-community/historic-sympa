#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id: datasource_mysql.t 8332 2012-12-27 14:02:35Z rousse $

use strict;

use File::Temp;
use Test::More;
use Test::Exception;

use Sympa::Lock;

plan tests => 4;

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

lives_ok {
    $lock = Sympa::Lock->new(
        File::Temp->new(),
        'anything'
    );
}
'all parameters OK';

isa_ok($lock, 'Sympa::Lock');
