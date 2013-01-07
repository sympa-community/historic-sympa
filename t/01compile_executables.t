#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id$

use strict;
use warnings;
use lib 'src/lib';

use English qw(-no_match_vars);
use Test::More;

eval {
    require Test::Compile;
    Test::Compile->import();
};
if ($EVAL_ERROR) {
    my $msg = 'Test::Compile required';
    plan(skip_all => $msg);
}

$ENV{PERL5LIB} = $ENV{PERL5LIB} ? "$ENV{PERL5LIB}:src/lib" : "src/lib";

all_pl_files_ok(
	<src/sbin/*.pl>,
	<src/bin/*.pl>,
	<src/cgi/*.pl>,
	<src/soap/*.pl>,
	'src/cgi/wwsympa.fcgi',
	'src/soap/sympa_soap_server.fcgi'
);
