# $Id$

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

Sympa::Tools::Cookie - Cookie-related functions

=head1 DESCRIPTION

This module provides various functions for managing HTTP cookies.

=cut

package Sympa::Tools::Cookie;

use strict;

use CGI::Cookie;
use Digest::MD5;

use Sympa::Log;

=head1 FUNCTIONS

=head2 set_cookie_soap($session_id, $http_domain, $expire)

Sets an HTTP cookie to be sent to a SOAP client

=cut
    
sub set_cookie_soap {
    my ($session_id,$http_domain,$expire) = @_ ;
    my $cookie;
    my $value;

    # WARNING : to check the cookie the SOAP services does not gives
    # all the cookie, only it's value so we need ':'
    $value = $session_id;
  
    ## With set-cookie2 max-age of 0 means removing the cookie
    ## Maximum cookie lifetime is the session
    $expire ||= 600; ## 10 minutes

    if ($http_domain eq 'localhost') {
	$cookie = sprintf "%s=%s; Path=/; Max-Age=%s", 'sympa_session', $value, $expire;
    }else {
	$cookie = sprintf "%s=%s; Domain=%s; Path=/; Max-Age=%s", 'sympa_session', $value, $http_domain, $expire;;
    }

    ## Return the cookie value
    return $cookie;
}

=head2 get_mac($email, $secret)

Returns Message Authentication Check code

=cut

sub get_mac {
        my $email = shift ;
	my $secret = shift ;	
	&Sympa::Log::do_log('debug3', "get_mac($email, $secret)");

	unless ($secret) {
	    &Sympa::Log::do_log('err', 'get_mac : failure missing server secret for cookie MD5 digest');
	    return undef;
	}
	unless ($email) {
	    &Sympa::Log::do_log('err', 'get_mac : failure missing email adresse or cookie MD5 digest');
	    return undef;
	}



	my $md5 = new Digest::MD5;

	$md5->reset;
	$md5->add($email.$secret);

	return substr( unpack("H*", $md5->digest) , -8 );

}

sub set_cookie_extern {
    my ($secret,$http_domain,%alt_emails) = @_ ;
    my $expiration;
    my $cookie;
    my $value;

    my @mails ;
    foreach my $mail (keys %alt_emails) {
	my $string = $mail.':'.$alt_emails{$mail};
	push(@mails,$string);
    }
    my $emails = join(',',@mails);

    $value = sprintf '%s&%s',$emails,&get_mac($emails,$secret);
 
    if ($http_domain eq 'localhost') {
	$http_domain="";
    }

	$cookie = new CGI::Cookie (-name    => 'sympa_altemails',
	                           -value   => $value,
				   -expires => '+1y',
				   -domain  => $http_domain,
				   -path    => '/'
				   );
    ## Send cookie to the client
    printf "Set-Cookie: %s\n", $cookie->as_string;
    #&Sympa::Log::do_log('notice',"set_cookie_extern : %s",$cookie->as_string);
    return 1;
}

=head2 generic_get_cookie($http_cookie, $cookie_name)

Generic subroutine to get a cookie value

=cut

sub generic_get_cookie {
    my $http_cookie = shift;
    my $cookie_name = shift;

    if ($http_cookie =~/\S+/g) {
	my %cookies = parse CGI::Cookie($http_cookie);
	foreach (keys %cookies) {
	    my $cookie = $cookies{$_};
	    next unless ($cookie->name eq $cookie_name);
	    return ($cookie->value);
	}
    }
    return (undef);
}

=head2 check_cookie($http_cookie, $secret)

Returns user information extracted from the cookie

=cut

sub check_cookie {
    my $http_cookie = shift;
    my $secret = shift;
    
    my $user = &generic_get_cookie($http_cookie, 'sympauser');

    my @values = split /:/, $user; 
    if ($#values >= 1) {
	my ($email, $mac, $auth) = @values;
	$auth ||= 'classic';
	
	## Check the MAC
	if (&get_mac($email,$secret) eq $mac) {
	    return ($email, $auth);
	}
    }	

    return undef;
}

sub check_cookie_extern {
    my ($http_cookie,$secret,$user_email) = @_;

    my $extern_value = &generic_get_cookie($http_cookie, 'sympa_altemails');
 
    if ($extern_value =~ /^(\S+)&(\w+)$/) {
	return undef unless (&get_mac($1,$secret) eq $2) ;
		
	my %alt_emails ;
	foreach my $element (split(/,/,$1)){
	    my @array = split(/:/,$element);
	    $alt_emails{$array[0]} = $array[1];
	}
	      
	my $e = lc($user_email);
	unless ($alt_emails{$e}) {
	    return undef;
	}
	return (\%alt_emails);
    }
    return undef
}

1;
