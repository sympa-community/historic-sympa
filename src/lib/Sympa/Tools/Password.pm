# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
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

=encoding utf-8

=head1 NAME

Sympa::Tools::Password - Password-related functions

=head1 DESCRIPTION

This module provides various functions for managing passwords.

=cut

package Sympa::Tools::Password;

use strict;

use Digest::MD5;
use MIME::Base64;

use Sympa::Log::Syslog;

## global var to store a CipherSaber object
my $cipher;

=head1 FUNCTIONS

=over

=item tmp_passwd($email, $cookie)

Return a temporary password.

=cut

sub tmp_passwd {
    my ($email, $cookie) = @_;

    return ('init'.substr(Digest::MD5::md5_hex(join('/', $cookie, $email)), -8));
}

=item ciphersaber_installed($cookie)

Create a cipher.

=cut

sub ciphersaber_installed {
    return $cipher if defined $cipher;

    eval { require Crypt::CipherSaber; };
    unless ($@) {
	$cipher = Crypt::CipherSaber->new(Site->cookie);
    } else {
	$cipher = '';
    }
    return $cipher;
}

=item crypt_password($inpasswd, $cookie)

Encrypt a password.

=cut

sub crypt_password {
    my $inpasswd = shift ;

    ciphersaber_installed();
    return $inpasswd unless $cipher;
    return ("crypt.".MIME::Base64::encode($cipher->encrypt ($inpasswd))) ;
}

=item decrypt_password($inpasswd, $cookie)

Decrypt a password.

=cut

sub decrypt_password {
    my $inpasswd = shift ;
    Sympa::Log::Syslog::do_log('debug2', 'Sympa::Tools::decrypt_password (%s)', $inpasswd);

    return $inpasswd unless ($inpasswd =~ /^crypt\.(.*)$/) ;
    $inpasswd = $1;

    ciphersaber_installed();
    unless ($cipher) {
	Sympa::Log::Syslog::do_log('info','password seems encrypted while CipherSaber is not installed !');
	return $inpasswd ;
    }
    return ($cipher->decrypt(MIME::Base64::decode($inpasswd)));
}

=item new_passwd()

Return a new random password.

=cut

sub new_passwd {

    my $passwd;
    my $nbchar = int(rand 5) + 6;
    foreach my $i (0..$nbchar) {
	$passwd .= chr(int(rand 26) + ord('a'));
    }

    return 'init'.$passwd;
}

=back

=cut

1;
