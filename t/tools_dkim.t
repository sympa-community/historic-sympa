#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use File::Copy;
use File::Temp;
use Test::More;

use Sympa::Message;
use Sympa::Tools::DKIM;

my %tests = (
	error2 => undef,
	error3 => undef,
	error7 => 1
);

plan tests => scalar keys %tests;

chdir "$Bin/..";

foreach my $test (keys %tests) {

	my $message = Sympa::Message->new(
		file       => "t/samples/$test.eml",
		noxsympato => 1
	);
	is(
		Sympa::Tools::DKIM::dkim_verifier(
			$message->{msg_as_string},
			'/tmp'
		),
		$tests{$test},
		"DKIM verifier: $test sample"
	);
}
