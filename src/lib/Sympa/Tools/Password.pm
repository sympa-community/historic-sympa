# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id: Tools.pm 8288 2012-12-17 15:47:19Z rousse $

# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
# Copyright (c) 1997,1998, 1999 Institut Pasteur & Christophe Wolfhugel
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Tools::Password - Password-related functions

=head1 DESCRIPTION

This module provides various functions for managing passwords.

=cut

package Sympa::Tools::Password;

use strict;

use Digest::MD5;
use MIME::Base64;

use Sympa::Log;

## global var to store a CipherSaber object
my $cipher;

sub tmp_passwd {
    my $email = shift;
    my $cookie = shift;

    return ('init'.substr(Digest::MD5::md5_hex(join('/', $cookie, $email)), -8)) ;
}

=head2 ciphersaber_installed($cookie)

Create a cipher.

=cut

sub ciphersaber_installed {
    my $cookie = shift;

    my $is_installed;
    foreach my $dir (@INC) {
	if (-f "$dir/Crypt/CipherSaber.pm") {
	    $is_installed = 1;
	    last;
	}
    }

    if ($is_installed) {
	require Crypt::CipherSaber;
	$cipher = Crypt::CipherSaber->new($cookie);
    }else{
	$cipher = 'no_cipher';
    }
}

=head2 crypt_password($inpasswd, $cookie)

Encrypt a password.

=cut

sub crypt_password {
    my $inpasswd = shift ;
    my $cookie = shift;

    unless (defined($cipher)){
	$cipher = ciphersaber_installed($cookie);
    }
    return $inpasswd if ($cipher eq 'no_cipher') ;
    return ("crypt.".&MIME::Base64::encode($cipher->encrypt ($inpasswd))) ;
}

=head2 decrypt_password($inpasswd, $cookie)

Decrypt a password.

=cut

sub decrypt_password {
    my $inpasswd = shift ;
    my $cookie = shift;
    Sympa::Log::do_log('debug2', '(%s,%s)', $inpasswd, $cookie);

    return $inpasswd unless ($inpasswd =~ /^crypt\.(.*)$/) ;
    $inpasswd = $1;

    unless (defined($cipher)){
	$cipher = ciphersaber_installed($cookie);
    }
    if ($cipher eq 'no_cipher') {
	&Sympa::Log::do_log('info','password seems crypted while CipherSaber is not installed !');
	return $inpasswd ;
    }
    return ($cipher->decrypt(&MIME::Base64::decode($inpasswd)));
}

sub new_passwd {

    my $passwd;
    my $nbchar = int(rand 5) + 6;
    foreach my $i (0..$nbchar) {
	$passwd .= chr(int(rand 26) + ord('a'));
    }

    return 'init'.$passwd;
}

1;
