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

Sympa::OAuth1:Provider - OAuth v1 provider facilities

=head1 DESCRIPTION 

This package provides abstraction from the OAuth workflow (server side)
when getting requests for temporary/access tokens, handles database
storage and provides helpers.

=cut 

package Sympa::OAuth1::Provider;
use strict;
use warnings;

use OAuth::Lite::ServerUtil ();
use URI::Escape             qw/uri_escape uri_unescape/;

#use Log           ();

use constant SECOND => 1;
use constant MINUTE => 60 * SECOND;
use constant HOUR   => 60 * MINUTE;
use constant DAY    => 24 * HOUR;
use constant MONTH  => 30 * DAY;

sub db_prepared($@)
{   my ($thing, $query, @bind) = @_;
    SDM::do_prepared_query($query, @bind);
}

sub db_do($@)      # I want automatic quoting
{   my $thing = shift;
    my $sth   = $thing->db_prepared(@_);
    undef;
}

sub trace_calls(@)          # simplification of method logging
{   my $sub = (caller[1])[3];
    local $" =  ',';
    Log::do_log(debug2 => "$sub(@_)");
}

=head1 FUNCTIONS 

=head2 Constructors

=head3 new OPTIONS

Creates a new Sympa::OAuth1::Provider object.

=over 

=item * I<$method>, http method

=item * I<$url>, request url

=item * I<$authorization_header>

=item * I<$request_parameters>

=item * I<$request_body>

=back 

Returns

=over 

=item * I<an OAuthProvider object>, if created

=item * I<undef>, if something went wrong

=back 

=cut 

## Creates a new object
sub new($%)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    my %p;
    if(my $ah = $args->{authorization_header})
    {   foreach my $b (split /,\s*/, $ah)
        {   $b =~ /^(OAuth\s)?\s*(x?oauth_[^=]+)="([^"]*)"\s*$/ or next;
            $p{$2} = uri_unescape($3);
        }
    }
    elsif(my $rb = $args->{request_body})
    {   foreach my $k (keys %$rb)
        {   $k =~ /^x?oauth_/ or next;
            $p{$k} = uri_unescape($rb->{$k});
        }
    }
    elsif(my $rp = $args->{request_parameters})
    {   foreach my $k (keys %$rp)
        {   $k =~ /^x?oauth_/ or next;
            $p{$k} = uri_unescape($rp->{$k});
        }
    }
    keys %p or return;
    $self->{params} = \%p;

    my $key = $self->{consumer_key} = $p{oauth_consumer_key}
        or return;

    my $c   = $self->consumer_config_for($key)
        or return;

    $c->{enabled}
        or return;
 
    $self->{consumer_secret}= $c->{secret};

    $self->{method}         = $args->{method};
    $self->{url}            = $args->{url};

    trace_calls($key);
    
    my %settings =
      ( old_request_timeout => 10*MINUTE # Max age for requests timestamps
      , nonce_timeout       =>  3*MONTH  # Time the nonce tags are kept
      , temporary_timeout   =>  1*HOUR   # Time left to use the temp token
      , verifier_timeout    =>  5*MINUTE # Time left to request access once the verifier has been set
      , access_timeout      =>  3*MONTH  # Access timeout
      );

    $self->{constants} = \%settings;
    
    my $util = $self->{util} = OAuth::Lite::ServerUtil->new;
    $util->support_signature_method('HMAC-SHA1');
    $util->allow_extra_params(qw/oauth_callback oauth_verifier/);
    
    unless($self->db_do(<<'__CLEANUP', time - $settings{temporary_timeout}))
DELETE FROM oauthprovider_sessions_table
 WHERE isaccess_oauthprovider IS NULL
   AND lasttime_oauthprovider < ?
__CLEANUP
    {   Log::do_log(err => 'Unable to delete old temporary tokens in database');
        return undef;
    }
    $self;
}

sub consumerFromToken($)
{   my ($class, $token) = @_;

    my $sth = $class->db_prepared(<<'__GET_TOKEN', $token);
SELECT consumer_oauthprovider AS consumer
  FROM oauthprovider_sessions_table
 WHERE token_oauthprovider = ?
__GET_TOKEN

    unless($sth)
    {   Log::do_log(err => 'unable to query token data %s', $token);
        return undef;
    }
 
    my $data = $sth->fetchrow_hashref('NAME_lc');
    $data ? $data->{consumer} : undef;
}

=head2 Accessors
=cut

sub oauth_util()     {shift->{util}}  # object
sub oauth_token()    {shift->{params}{oauth_token}}
sub oauth_verifier() {shift->{params}{oauth_verifier}}
sub oauth_callback() {shift->{params}{oauth_callback}}
sub consumer_key()   {shift->{consumer_key}}
sub consumer_secret(){shift->{consumer_secret}}
sub constants()      {shift->{constants}}
sub params()         {shift->{params}}

=head2 Actions

=head3 method checkRequest

Check whether a request is valid

  if(my $http_code = $provider->checkRequest) {
      $server->error($http_code, $provider->{util}->errstr);
  }

=over 

=item * I<$self>, the OAuthProvider object to test.

=item * I<$checktoken>, boolean

=back 

Returns

=over 

=item * I<undef>, if request is valid

=item * I<!= 1>, if request is NOT valid (http error code)

=back 

=cut 

sub checkRequest
{   my ($self, %args) = @_;
    trace_calls($args{url});

    my $params     = $self->params;
    my $constants  = $self->constants;

    my $checktoken = $args{checktoken};
    $self->oauth_util->validate_params($params, $checktoken)
        or return 400;
 
    my $nonce      = $params->{oauth_nonce};
    my $token      = $params->{oauth_token};
    my $timestamp  = $params->{oauth_timestamp};
    
    $timestamp > time - $constants->{old_request_timeout}
        or return 401;
    
    my $expire_nonces = time - $constants->{nonce_timeout};
    unless($self->db_do(<<__DELETE_NONCE, $expire_nonces))
DELETE FROM oauthprovider_nonces_table
 WHERE time_oauthprovider < ?
__DELETE_NONCE
    {   Log::do_log(err => 'Unable to clean nonce store in database');
        return 401;
    }
    
    if($checktoken)
    {   my $key = $self->consumer_key;
        my $sth = $self->db_prepared(<<'__GET_KEY', $key, $token);
SELECT id_oauthprovider AS id
  FROM oauthprovider_sessions_table
 WHERE consumer_oauthprovider = ?
   AND token_oauthprovider    = ?
__GET_KEY

        unless($sth)
        {   Log::do_log(err => 'Unable to get token %s %s', $key, $token);
            return 401;
        }
        
        if(my $data = $sth->fetchrow_hashref('NAME_lc'))
        {   my $id  = $data->{id};
            my $sth = $self->db_prepared(<<'__GET_NONCE', $id, $nonce);
SELECT nonce_oauthprovider AS nonce
  FROM oauthprovider_nonces_table
 WHERE id_oauthprovider    = ?
   AND nonce_oauthprovider = ?
__GET_NONCE

            unless($sth)
            {   Log::do_log(err => 'Unable to check nonce %d %s', $id, $nonce);
                return 401;
            }
            
            # Already used nonce?
            return 401 if $sth->fetchrow_hashref('NAME_lc');
 
            unless($self->db_do(<<'__INSERT_NONCE', $id, $nonce))
INSERT INTO oauthprovider_nonces_table
   SET id_oauthprovider    = ?
     , nonce_oauthprovider = ?
     , time_oauthprovider  = NOW
__INSERT_NONCE
            {   Log::do_log(err => 'Unable to add nonce record %d %s in database', $id, $nonce);
                return 401;
            }
        }
    }
    
    my $secret = '';
    if($checktoken)
    {
        my $sth = $self->db_prepared(<<__PROVIDER, $token);
SELECT secret_oauthprovider AS secret
  FROM oauthprovider_sessions_table
 WHERE token_oauthprovider = ?
__PROVIDER

        unless($sth)
        {   Log::do_log(err => 'Unable to load token data %s', $token);
            return undef;
        }
        
        my $data = $sth->fetchrow_hashref('NAME_lc')
            or return 401;

        $secret = $data->{secret};
    }
    
    my $correct = $self->outh_util->verify_signature
      ( method          => $self->{method}
      , params          => $self->{params}
      , url             => $self->{url}
      , consumer_secret => $self->consumer_secret
      , token_secret    => $secret
      );

    $correct ? undef : 401;
}

=pod 

=head2 method generateTemporary

Create a temporary token

=head3 Arguments 

=over 

=item * I<$self>, the OAuthProvider object.

=item * I<$authorize>, the authorization url.

=back 

=head3 Return 

=over 

=item * I<string> response body

=back 

=cut 

## Create a temporary token
sub generateTemporary(%)
{   my ($self, %args) = @_;

    my $key      = $self->consumer_key;
    my $callback = $self->oauth_callback;

    trace_calls($key);
    
    my $token  = $self->generateRandomString(32);
    my $secret = $self->generateRandomString(32);

    unless($self->db_do(<<'__START_SESSION', $token, $secret, $key, $callback))
INSERT INTO oauthprovider_sessions_table
   SET token_oauthprovider     = ?
     , secret_oauthprovider    = ?
     , isaccess_oauthprovider  = NULL
     , accessgranted_oauthprovider = NULL
     , consumer_oauthprovider  = ?
     , user_oauthprovider      = NULL
     , firsttime_oauthprovider = NOW
     , lasttime_oauthprovider  = NOW
     , verifier_oauthprovider  = NULL
     , callback_oauthprovider  = ?
__START_SESSION
    {   Log::do_log(err => 'Unable to add new token record %s %s in database', $token, $key);
        return undef;
    }
    
    my @r =
      ( 'oauth_token='        . uri_escape($token)
      , 'oauth_token_secret=' . uri_escape($secret)
      , 'oauth_expires_in='   . $self->constants->{temporary_timeout}
      , 'oauth_callback_confirmed=true'
      );

    push @r, "xoauth_request_auth_url=$args{authorize}"
        if defined $args{authorize};

    join '&', @r;
}

=head2 sub getTemporary

Retreive a temporary token from database.

=head3 Arguments 

=over 

=item * I<$self>, the OAuthProvider to use.

=item * I<$token>, the token key.

=item * I<$timeout_type>, the timeout key, temporary or verifier.

=back 

=head3 Return 

=over 

=item * I<a reference to a hash>, if everything's alright

=item * I<undef>, if token does not exist or is not valid anymore

=back 

=cut 

sub getTemporary(%)
{   my ($self, %args) = @_;
    my $token = $args{token};
    my $key   = $self->consumer_key;

    trace_calls($token);
    
    my $sth = $self->db_prepared(<<'__GET_TEMP', $key, $token);
SELECT id_oauthprovider        AS id
     , token_oauthprovider     AS token
     , secret_oauthprovider    AS secret
     , firsttime_oauthprovider AS firsttime
     , lasttime_oauthprovider  AS lasttime
     , callback_oauthprovider  AS callback
     , verifier_oauthprovider  AS verifier
  FROM oauthprovider_sessions_table
 WHERE isaccess_oauthprovider IS NULL
   AND consumer_oauthprovider = ?
   AND token_oauthprovider    = ?
__GET_TEMP

    unless($sth)
    {   Log::do_log(err => 'Unable to load token data %s %s', $key, $token);
        return undef;
    }
    
    my $data = $sth->fetchrow_hashref('NAME_lc')
        or return undef;

    my $timeout_type = ($args{timeout_type} || 'temporary') . '_timeout';
    my $timeout      = $self->constants->{$timeout_type};

    $data->{lasttime} + $timeout >= time ? $data : undef;
}

=head2 sub generateVerifier

Create the verifier for a temporary token

=head3 Arguments 

=over 

=item * I<$self>, the OAuthProvider object.

=item * I<$token>, the token.

=item * I<$user>, the user.

=back 

=head3 Return 

=over 

=item * I<string> redirect url

=item * I<undef>, if token does not exist or is not valid anymore

=back 

=cut 

## Create the verifier for a temporary token
sub generateVerifier
{   my ($self, %args) = @_;

    my $token   = $args{token};
    my $user    = $args{user};
    my $granted = $args{granted} ? 1 : 0;
    my $key     = $self->consumer_key;

    trace_calls($token, $user, $granted, $key);
    
    my $tmp = $self->getTemporary(token => $token)
        or return undef;
    
    my $verifier = $self->generateRandomString(32);
 
    unless($self->db_do(<<__DELETE_SESSION, $user, $key))
DELETE FROM oauthprovider_sessions_table
 WHERE user_oauthprovider= ?
   AND consumer_oauthprovider= ?
   AND isaccess_oauthprovider=1
__DELETE_SESSION
    {   Log::do_log(err => 'Unable to delete other already granted access tokens for this user %s %s in database', $user, $key);
        return undef;
    }
    
    unless($self->db_do(<<'__UPDATE', $verifier, $user, $granted, $key, $token))
UPDATE oauthprovider_sessions_table
   SET verifier_oauthprovider      = ?
     , user_oauthprovider          = ?
     , accessgranted_oauthprovider = ?
     , lasttime_oauthprovider      = NOW
 WHERE isaccess_oauthprovider      IS NULL
   AND consumer_oauthprovider      = ?
   AND token_oauthprovider         = ?
__UPDATE
    {   Log::do_log(err => 'Unable to set token verifier %s %s in database', $token, $key);
        return undef;
    }
    
    my $r = $tmp->{callback};
    $r   .= $r =~ /^[^\?]\?/ ? '&' : '?';                  # XXX MO: ???
    $r   .= 'oauth_token='     . uri_escape($tmp->{token}) # XXX MO: ==$token??
         .  '&oauth_verifier=' . uri_escape($verifier);
    
    return $r;
}

=head3 method generateAccess

Create an access token.

=over 

=item * I<$token>, the temporary token.

=item * I<$verifier>, the verifier.

=back 

Returns

=over 

=item * I<string> response body

=item * I<undef>, if temporary token does not exist or is not valid anymore

=back 

=cut 

## Create an access token
sub generateAccess(%)
{   my ($self, %args) = @_;

    my $token    = $args{token}    || $self->oauth_token;
    my $verifier = $args{verifier} || $self->oauth_verifier;
    my $key      = $self->consumer_key;

    trace_calls($token, $verifier, $key);
    
    my $tmp = $self->getTemporary(token => $token, timeout_type => 'verifier')
        or return;

     $verifier eq $tmp->{verifier}
        or return;
    
    my $tmp_token = $self->generateRandomString(32);
    my $secret    = $self->generateRandomString(32);
    
    unless($self->db_do(<<'__UPDATE', $tmp_token,$secret, $token,$verifier))
UPDATE oauthprovider_sessions_table
   SET token_oauthprovider    = ?
     , secret_oauthprovider   = ?
     , isaccess_oauthprovider = 1
     , lasttime_oauthprovider = NOW
     , verifier_oauthprovider = NULL
     , callback_oauthprovider = NULL
 WHERE token_oauthprovider    = ?
   AND verifier_oauthprovider = ?
__UPDATE
    {   Log::do_log(err => 'Unable to transform temporary token into access token record %s %s in database', $tmp_token, $key);
        return undef;
    }
    
    join '&'
     , 'oauth_token='        . uri_escape($tmp_token)
     , 'oauth_token_secret=' . uri_escape($secret)
     , 'oauth_expires_in='   . $self->constants->{access_timeout};
}

=head3 method getAccess

Retreive an access token from database.

=over 

=item * I<$token>, the token key.

=back 

Returns

=over 

=item * I<a reference to a hash>, if everything's alright

=item * I<undef>, if token does not exist or is not valid anymore

=back 

=cut 

## Retreive an access token from database
sub getAccess(%)
{   my ($self, %args) = @_;
    my $token = $args{token};

    trace_calls($token);

    my $key   = $self->consumer_key;
    my $sth   = $self->db_prepared(<<'__GET_ACCESS', $key, $token);
SELECT token_oauthprovider         AS token
     , secret_oauthprovider        AS secret
     , lasttime_oauthprovider      AS lasttime
     , user_oauthprovider          AS user
     , accessgranted_oauthprovider AS accessgranted
  FROM oauthprovider_sessions_table
 WHERE isaccess_oauthprovider = 1
   AND consumer_oauthprovider = ?
   AND token_oauthprovider    = ?
__GET_ACCESS

    unless($sth)
    {   Log::do_log(err => 'Unable to load token data %s %s', $key, $token);
        return undef;
    }
    
    my $data = $sth->fetchrow_hashref('NAME_lc')
        or return undef;

    my $valid_until = $data->{lasttime} + $self->constants->{access_timeout};
    $valid_until >= time ? $data : undef;
}

=head3 method generateRandomString

Create a random string.

=over 

=item * I<$size>, the string length.

=back 

Returns

=over 

=item * I<string>

=back 

=cut

sub generateRandomString($)
{   my ($thing, $chars) = @_;
    join '', map { (0..9, 'a'..'z', 'A'..'Z')[rand 62] } 1..$chars;
}


=head3 consumer_config_for

Retreive config for a consumer

Config file is like :
# comment

<consumer_key>
secret <consumer_secret>
enabled 0|1

=over 

=item * I<string>, the consumer key.

=back 

Returns

=over 

=item * I<string>

=back 

=cut

sub consumer_config_for
{   my ($thing, $key) = @_;

    trace_calls($key);
    
    my $file = Site->etc . '/oauth_provider.conf';
    -f $file or return undef;
    
    open(my $fh, '<', $file)
        or return undef;

    my %c;
    my $k = '';
    while(my $l = <$fh>) {
        chomp $l;
        next if $l =~ /^#/;
        next if $k eq '' && $l ne $key;

        $k = $key;
        next if $l eq $key;
        last if $l eq '';
        next if $l !~ /\s*([^\s]+)\s+(.+)$/;
        $c{$1} = $2;
    }
    close $fh;
    
    return \%c;
}

'Packages must return true';

=head1 AUTHORS 

=over 

=item * Etienne Meleard <etienne.meleard AT renater.fr> 

=item * Mark Overmeer <solutions@overmeer.net>

=back 

=cut 
