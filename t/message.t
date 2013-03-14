#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;

use Sympa::Message;

plan tests => 20;

chdir "$Bin/..";

my $message;

# no source
$message = Sympa::Message->new();
ok(!$message, 'no source');

# MIME::Entity source
$message = Sympa::Message->new(
	mimeentity => MIME::Entity->build(
		From    => 'guillaume.rousse@inria.fr',
		To      => 'sympa-developpers@listes.renater.fr',
		Subject => 'Test',
		Data    => [ 'test' ]
	)
);
ok($message, 'MIME::Entity source');
isa_ok($message, 'Sympa::Message');

# File source
$message = Sympa::Message->new(
	file => 't/samples/unsigned.eml',
);
ok(!$message, 'file source, no X-Sympa-To header');

$message = Sympa::Message->new(
	file       => 't/samples/unsigned.eml',
	noxsympato => 1
);
ok($message, 'file source, no X-Sympa-To header check');
isa_ok($message, 'Sympa::Message');
is($message->{sender}, 'guillaume.rousse@sympa.org', 'sender value');
is($message->{decoded_subject}, 'unsigned test message', 'subject value');
is($message->{subject_charset}, 'US-ASCII', 'subject charset value');

# String source
my $string = <<'EOF';
Date: Mon, 25 Feb 2013 17:10:38 +0100
From: Guillaume Rousse <Guillaume.Rousse@sympa.org>
MIME-Version: 1.0
To: sympa-developpers@listes.renater.fr
Subject: unsigned test message
Content-Type: text/plain; charset=ISO-8859-1; format=flowed
Content-Transfer-Encoding: 7bit

This is an unsigned test message.
EOF
$message = Sympa::Message->new(
	messageasstring => $string
);
ok(!$message, 'string source, no X-Sympa-To header');

$message = Sympa::Message->new(
	messageasstring => $string,
	noxsympato      => 1
);
ok($message, 'string source, no X-Sympa-To header check');
isa_ok($message, 'Sympa::Message');
is($message->{sender}, 'guillaume.rousse@sympa.org', 'sender value');
is($message->{decoded_subject}, 'unsigned test message', 'subject value');
is($message->{subject_charset}, 'US-ASCII', 'subject charset value');

$message = Sympa::Message->new(
	messageasstring => \$string,
	noxsympato      => 1
);
ok($message, 'string reference source, no X-Sympa-To header check');
isa_ok($message, 'Sympa::Message');
is($message->{sender}, 'guillaume.rousse@sympa.org', 'sender value');
is($message->{decoded_subject}, 'unsigned test message', 'subject value');
is($message->{subject_charset}, 'US-ASCII', 'subject charset value');
