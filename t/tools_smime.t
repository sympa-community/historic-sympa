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

plan tests => 5;

chdir "$Bin/..";

my ($crt_dir, $crt_file);

my $unsigned_message = Sympa::Message->new({
	file       => "t/samples/unsigned.eml",
	noxsympato => 1
});
ok(
	!defined Sympa::Tools::SMIME::check_signature(
		message  => $unsigned_message,
	),
	"unsigned message"
);

my $signed_message = Sympa::Message->new({
	file       => "t/samples/signed.eml",
	noxsympato => 1
});

$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
$crt_file = $crt_dir . '/guillaume.rousse@inria.fr';
is_deeply(
	Sympa::Tools::SMIME::check_signature(
		message  => $signed_message,
		cafile   => 't/pki/ca.pem',
		capath   => undef,
		openssl  => '/usr/bin/openssl',
		cert_dir => $crt_dir
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

ok(-f $crt_file, 'certificate file created');

$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
$crt_file = $crt_dir . '/guillaume.rousse@inria.fr';
is_deeply(
	Sympa::Tools::SMIME::check_signature(
		message  => $signed_message,
		cafile   => undef,
		capath   => 't/pki/ca',
		openssl  => '/usr/bin/openssl',
		cert_dir => $crt_dir
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
ok(-f $crt_file, 'certificate file created');
