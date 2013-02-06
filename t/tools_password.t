#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use English qw(-no_match_vars);
use Test::More;

use Sympa::Tools::Password;

plan tests => 8;

my $password1 = Sympa::Tools::Password::new_passwd();
my $password2 = Sympa::Tools::Password::new_passwd();

ok($password1, "first random password: $password1");
ok($password2, "second random password: $password2");
ok($password1 ne $password2, "random passwords differ");

my $password3 = Sympa::Tools::Password::tmp_passwd('user@domain', 'cookie1');
my $password4 = Sympa::Tools::Password::tmp_passwd('user@domain', 'cookie1');
ok(
    $password3 eq $password4,
    "passwords for same user and same cookie are equals"
);

my $password5 = Sympa::Tools::Password::tmp_passwd('user@domain', 'cookie2');
ok(
    $password5 ne $password3,
    "passwords for same user and different cookie differ"
);

my $password6 = Sympa::Tools::Password::tmp_passwd('other@domain', 'cookie1');
ok(
    $password5 ne $password3,
    "passwords for different user and same cookie differ"
);

eval { require Crypt::CipherSaber; };

SKIP: {
	skip 'Crypt::CipherSaber required', 2 if $EVAL_ERROR;

	my $password = 'password';
	my $cookie   = 'cookie';
	my $crypted_password = Sympa::Tools::Password::crypt_password($password, $cookie);
	ok(
	    $password ne $crypted_password,
	    "encrypted password differs from original password"
	);

	my $decrypted_password = Sympa::Tools::Password::decrypt_password(
	    $crypted_password, $cookie
	);
	ok(
	    $password eq $decrypted_password,
	    "decrypted password is equal to original password"
	);
};
