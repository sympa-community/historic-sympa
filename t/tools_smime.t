#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: datasource_mysql.t 8332 2012-12-27 14:02:35Z rousse $

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use File::Temp;
use Test::More;

use Sympa::Message;
use Sympa::Tools::SMIME;

plan tests => 3;

chdir "$Bin/..";

my $top_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
my $tmp_dir = "$top_dir/tmp";
my $crt_dir = "$top_dir/crt";
mkdir($tmp_dir);
mkdir($crt_dir);

my $unsigned_message = Sympa::Message->new({
	file       => "t/samples/unsigned.eml",
	noxsympato => 1
});
ok(
	!defined Sympa::Tools::SMIME::check_signature(
		$unsigned_message,
		't/pki/ca.pem',
		undef,
		'/usr/bin/openssl',
		$crt_dir
	),
	"unsigned message"
);

my $signed_message = Sympa::Message->new({
	file       => "t/samples/signed.eml",
	noxsympato => 1
});

is_deeply(
	Sympa::Tools::SMIME::check_signature(
		$signed_message,
		't/pki/ca.pem',
		undef,
		'/usr/bin/openssl',
		$crt_dir
	),
	{
		body => 'smime',
		subject => {
			email =>  {
				'guillaume.rousse@inria.fr' => '1'
			},
			subject => '/C=FR/O=INRIA/CN=Guillaume ROUSSE/unstructuredName=rousse@inria.fr',
			purpose => {
				'enc'  => 1,
				'sign' => 1
			}
		}
	},
	"signed message, CA file"
);

is_deeply(
	Sympa::Tools::SMIME::check_signature(
		$signed_message,
		undef,
		't/pki/ca',
		'/usr/bin/openssl',
		$crt_dir
	),
	{
		body => 'smime',
		subject => {
			email =>  {
				'guillaume.rousse@inria.fr' => '1'
			},
			subject => '/C=FR/O=INRIA/CN=Guillaume ROUSSE/unstructuredName=rousse@inria.fr',
			purpose => {
				'enc'  => 1,
				'sign' => 1
			}
		}
	},
	"signed message, CA directory"
);
