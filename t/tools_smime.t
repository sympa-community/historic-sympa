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
use Sympa::Tools::SMIME;

plan tests => 11;

chdir "$Bin/..";

my ($crt_dir, $crt_file);

my $unsigned_message = Sympa::Message->new({
	file       => "t/samples/unsigned.eml",
	noxsympato => 1
});
$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
$crt_file = $crt_dir . '/guillaume.rousse@sympa.org';
ok(
	!defined Sympa::Tools::SMIME::check_signature(
		message  => $unsigned_message,
		openssl  => '/usr/bin/openssl',
		cert_dir => $crt_dir
	),
	"unsigned message"
);

my $signed_message = Sympa::Message->new({
	file       => "t/samples/signed.eml",
	noxsympato => 1
});

$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
$crt_file = $crt_dir . '/guillaume.rousse@sympa.org';
ok(
	!defined Sympa::Tools::SMIME::check_signature(
		message  => $signed_message,
		openssl  => '/usr/bin/openssl',
		cert_dir => $crt_dir
),
	"signed message, no CA certificate"
);
ok(! -f $crt_file, 'certificate file not created');

$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
$crt_file = $crt_dir . '/guillaume.rousse@sympa.org';
is_deeply(
	Sympa::Tools::SMIME::check_signature(
		message  => $signed_message,
		openssl  => '/usr/bin/openssl',
		cert_dir => $crt_dir,
		cafile   => 't/pki/crt/ca.pem',
	),
	{
		body => 'smime',
		subject => {
			email =>  {
				'guillaume.rousse@sympa.org' => '1'
			},
			subject => '/O=sympa developpers/OU=unit testing/CN=Guillaume Rousse/emailAddress=Guillaume.Rousse@sympa.org',
			purpose => {
				'enc'  => 1,
				'sign' => 1
			}
		}
	},
	"signed message, CA certificate file"
);

ok(-f $crt_file, 'certificate file created');

$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
$crt_file = $crt_dir . '/guillaume.rousse@sympa.org';
is_deeply(
	Sympa::Tools::SMIME::check_signature(
		message  => $signed_message,
		openssl  => '/usr/bin/openssl',
		cert_dir => $crt_dir,
		capath   => 't/pki/crt',
	),
	{
		body => 'smime',
		subject => {
			email =>  {
				'guillaume.rousse@sympa.org' => '1'
			},
			subject => '/O=sympa developpers/OU=unit testing/CN=Guillaume Rousse/emailAddress=Guillaume.Rousse@sympa.org',
			purpose => {
				'enc'  => 1,
				'sign' => 1
			}
		}
	},
	"signed message, CA certificate directory"
);
ok(-f $crt_file, 'certificate file created');

$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
copy('t/pki/crt/rousse.pem', "$crt_dir/cert.pem");
copy('t/pki/key/rousse_nopassword.pem', "$crt_dir/private_key");
my $new_message = Sympa::Tools::SMIME::sign_message(
	message => $unsigned_message->{msg},
	openssl => '/usr/bin/openssl',
	certdir => $crt_dir,
	tmpdir     => '/tmp',
	listid     => 'foo'
);
ok(defined $new_message, 'message signature, passwordless key');
isa_ok(
	$new_message,
	'MIME::Entity',
	'signed message'
);

$crt_dir = File::Temp->newdir(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
copy('t/pki/crt/rousse.pem', "$crt_dir/cert.pem");
copy('t/pki/key/rousse_password.pem', "$crt_dir/private_key");
my $new_message = Sympa::Tools::SMIME::sign_message(
	message    => $unsigned_message->{msg},
	openssl    => '/usr/bin/openssl',
	certdir    => $crt_dir,
	key_passwd => 'test',
	tmpdir     => '/tmp',
	listid     => 'foo'
);
ok(defined $new_message, 'message signature, password-protected key');
isa_ok(
	$new_message,
	'MIME::Entity',
	'signed message'
);
