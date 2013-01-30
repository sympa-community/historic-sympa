#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id: datasource_mysql.t 8332 2012-12-27 14:02:35Z rousse $

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
$message = Sympa::Message->new({
	mimeentity => MIME::Entity->build(
		From    => 'guillaume.rousse@inria.fr',
		To      => 'sympa-developpers@listes.renater.fr',
		Subject => 'Test',
		Data    => [ 'test' ]
	)
});
ok($message, 'MIME::Entity source');
isa_ok($message, 'Sympa::Message');

# File source
$message = Sympa::Message->new({
	file => 't/samples/unsigned.eml',
});
ok(!$message, 'file source, no X-Sympa-To header');

$message = Sympa::Message->new({
	file       => 't/samples/unsigned.eml',
	noxsympato => 1
});
ok($message, 'file source, no X-Sympa-To header check');
isa_ok($message, 'Sympa::Message');
is($message->{sender}, 'guillaume.rousse@inria.fr', 'sender value');
is($message->{decoded_subject}, 'unsigned test', 'subject value');
is($message->{subject_charset}, 'US-ASCII', 'subject charset value');

# String source
my $string = <<'EOF';
X-Identity-Key: id5
X-Account-Key: account5
Message-ID: <510780E6.8090702@inria.fr>
Date: Tue, 29 Jan 2013 08:57:26 +0100
From: Guillaume Rousse <Guillaume.Rousse@inria.fr>
X-Mozilla-Draft-Info: internal/draft; vcard=0; receipt=0; DSN=0; uuencode=0
User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:17.0) Gecko/20130114 Thunderbird/17.0.2
MIME-Version: 1.0
To: sympa-developpers@listes.renater.fr
Subject: unsigned test
Content-Type: text/plain; charset=ISO-8859-1; format=flowed
Content-Transfer-Encoding: 7bit

this is an unsigned test message.
EOF
$message = Sympa::Message->new({
	messageasstring => $string
});
ok(!$message, 'string source, no X-Sympa-To header');

$message = Sympa::Message->new({
	messageasstring => $string,
	noxsympato      => 1
});
ok($message, 'string source, no X-Sympa-To header check');
isa_ok($message, 'Sympa::Message');
is($message->{sender}, 'guillaume.rousse@inria.fr', 'sender value');
is($message->{decoded_subject}, 'unsigned test', 'subject value');
is($message->{subject_charset}, 'US-ASCII', 'subject charset value');

$message = Sympa::Message->new({
	messageasstring => \$string,
	noxsympato      => 1
});
ok($message, 'string reference source, no X-Sympa-To header check');
isa_ok($message, 'Sympa::Message');
is($message->{sender}, 'guillaume.rousse@inria.fr', 'sender value');
is($message->{decoded_subject}, 'unsigned test', 'subject value');
is($message->{subject_charset}, 'US-ASCII', 'subject charset value');
