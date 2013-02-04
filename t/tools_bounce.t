#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id: datasource_mysql.t 8332 2012-12-27 14:02:35Z rousse $

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;

use Sympa::Message;
use Sympa::Tools::Bounce;

my %tests_rfc1891 = (
	'error1.eml' => {
		'jpackage@zarb.org' => '5.7.1'
	},
	'error2.eml' => {
		'aris@samizdat.net' => '5.1.1'
	},
	'error3.eml' => {
		'tclapes@attglobal.net' => '5.0.0'
	},
	'error4.eml' => {
		'quanet@tin.it' => '5.1.1'
	},
	'error5.eml' => {
		'support@planetmirror.com' => '5.0.0'
	},
	'error6.eml' => undef
);

my %tests = (
	'error1.eml' => undef,
	'error2.eml' => {
		'the original message was received at fri, 1 feb 2013 05:18:38 +0100@samizdat.net' => '',
		'550 5.1.1 aris ... user unknown@samizdat.net' => '',
		'550 5.1.1 <aris@samizdat.net>... user unknown' => '',
		'from ryu.zarb.org [212.85.158.22]@samizdat.net' => '',
		'aris@samizdat.net' => ''
	},
	'error3.eml' => undef,
	'error4.eml' => undef,
	'error5.eml' => undef,
	'error6.eml' => undef
);

plan tests => (scalar keys %tests_rfc1891) + (scalar keys %tests);

chdir "$Bin/..";

foreach my $test (keys %tests_rfc1891) {
	my $message = Sympa::Message->new({
		file       => "t/samples/$test",
		noxsympato => 1
	});
	is_deeply(
		Sympa::Tools::Bounce::parse_rfc1891_notification($message),
		$tests_rfc1891{$test},
		"$test message parsing as RFC1891 compliant notification"
	);
}

foreach my $test (keys %tests) {
	my $message = Sympa::Message->new({
		file       => "t/samples/$test",
		noxsympato => 1
	});
	is_deeply(
		Sympa::Tools::Bounce::parse_notification($message),
		$tests{$test},
		"$test message parsing as arbitrary notification"
	);
}

