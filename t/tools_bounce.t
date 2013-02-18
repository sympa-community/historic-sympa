#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
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
	'error6.eml' => undef,
	'error7.eml' => undef,
	'error8.eml' => {
		'chuck@cvip.uofl.edu' => '5.0.0'
	},
	'error9.eml' => {
		'emmanuel.delaborde@citycampus.com' => '4.4.2'
	},
	'error10.eml' => {
		'aiolia@maciste.it' => '4.4.1'
	},
	'error11.eml' => {
		'kenduest@mdk.linux.org.tw' => '4.7.1'
	},
	'error12.eml' => {
		'wojtula95@op.pl' => '4.7.1'
	},
	'error13.eml' => {
		'mlhydeau@austarnet.com.au' => '4.4.1'
	},
	'error14.eml' => {
		'ftpmaster@t-online.fr' => '4.4.1'
	},
	'error15.eml' => {
		'fuwafuwa@jessicara.co.uk' => '4.4.3'
	},
	'error16.eml' => {
		'jpackage@zarb.org' => '5.1.1'
	},
);

my %tests = (
	'error1.eml' => {
		'fnasser@redhat.com' => '5.7.1'
	},
	'error2.eml' => {
		'aris@samizdat.net' => 'user unknown'
	},
	'error3.eml' => undef,
	'error4.eml' => undef,
	'error5.eml' => undef,
	'error6.eml' => {
		'efthimeros@chemeng.upatras.gr' => '5.1.1'
	},
	'error7.eml' => undef,
	'error8.eml' => undef,
	'error9.eml' => {
		'emmanuel.delaborde@citycampus.com' => 'conversation with
    citycampus.com[199.59.243.118] timed out while receiving the initial server
    greeting'
	},
	'error10.eml' => {
		'aiolia@maciste.it' => 'connect to mx2.maciste.it[62.149.198.62]'
	},
	'error11.eml' => {
		'kenduest@mdk.linux.org.tw' => 'host mdk.linux.org.tw[210.240.39.201] said',
	},
	'error12.eml' => {
		'wojtula95@op.pl' => 'host mx.poczta.onet.pl[213.180.147.146] refused to talk to
    me'
	},
	'error13.eml' => {
		'mlhydeau@austarnet.com.au' => 'connect to austarnet.com.au[203.22.8.238]'
	},
	'error14.eml' => {
		'ftpmaster@t-online.fr' => 'connect to mailx.tcommerce.de[193.158.123.94]'
	},
	'error15.eml' => {
		'fuwafuwa@jessicara.co.uk' => 'host or domain name not found. name service error
    for name=jessicara.co.uk type=mx'
	},
	'error16.eml' => {
		'nim@zarb.org' => 'unknown user',
		'fnasser@zarb.org' => 'unknown user'
	},
);

plan tests => (scalar keys %tests_rfc1891) + (scalar keys %tests);

chdir "$Bin/..";

foreach my $test (sort keys %tests_rfc1891) {
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

foreach my $test (sort keys %tests) {
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
