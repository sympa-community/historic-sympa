
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

use Sympa::Plugin::Util     qw/:functions :http :time/;
use OAuth::Lite::ServerUtil ();
use URI::Escape             qw/uri_escape uri_unescape/;

my @timeouts =
  ( old_request_timeout => 10*MINUTE # max age for requests timestamps
  , nonce_timeout       =>  3*MONTH  # time the nonce tags are kept
  , temporary_timeout   =>  1*HOUR   # time left to use the temp token
  , access_timeout      =>  3*MONTH  # access timeout
  , verifier_timeout    =>  5*MINUTE # time left to request access once
  );                                 #     the verifier has been set

=head1 METHODS

=head2 Constructors

=head3 new OPTIONS

Options:

=over 4

=item * I<db>, database object, defaults to the default_db

=item * I<method>, http method

=item * I<url>, request url

=item * I<authorization_header> =E<gt> STRING

=item * I<request_parameters> =E<gt> HASH

=item * I<request_body> =E<gt> HASH

=back 

=cut 

## Creates a new object
sub new($%)
{   my ($class, %args) = @_;
    (bless {@timeouts}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    $self->{SOP_db} = $args->{db} || default_db;

    my %p;
    if(my $ah = $args->{authorization_header})
    {   foreach my $b (split /,\s*/, $ah)
        {   $b =~ /^(OAuth\s)?\s*(x?oauth_[^=]+)="([^"]*)"\s*$/ or next;
            $p{$2} = uri_unescape($3);
        }
    }
    elsif(my $rb = $args->{request_body})
    {   $p{$_} = uri_unescape($rb->{$_})
             for grep /^x?oauth_/, keys %$rb;
    }
    elsif(my $rp = $args->{request_parameters})
    {   $p{$_} = uri_unescape($rp->{$_})
             for grep /^x?oauth_/, keys %$rp;
    }
    $self->{SOP_params} = \%p;

    my $key = $self->{SOP_consumer_key} = $p{oauth_consumer_key}
        or return;

    my $c   = $self->consumerConfigFor($key)
        or return;

    trace_call($key, $c->{enabled});

    $c->{enabled}
        or return;
 
    $self->{SOP_cons_secret} = $c->{secret};
    $self->{SOP_method}      = $args->{method};
    $self->{SOP_url}         = $args->{url};
    
    my $util = $self->{SOP_util} = OAuth::Lite::ServerUtil->new;
    $util->support_signature_method('HMAC-SHA1');
    $util->allow_extra_params(qw/oauth_callback oauth_verifier/);
    
    unless($self->db->do(<<'__CLEANUP', time - $self->{temporary_timeout}))
DELETE FROM oauthprovider_sessions_table
 WHERE isaccess_oauthprovider IS NULL
   AND lasttime_oauthprovider < ?
__CLEANUP
    {   log(err => 'Unable to delete old temporary tokens in database');
        return undef;
    }
    $self;
}

sub consumerFromToken($)
{   my ($self, $token) = @_;

    my $sth = $self->db->prepared(<<'__GET_TOKEN', $token);
SELECT consumer_oauthprovider AS consumer
  FROM oauthprovider_sessions_table
 WHERE token_oauthprovider = ?
__GET_TOKEN

    unless($sth)
    {   log(err => 'unable to query token data %s', $token);
        return undef;
    }
 
    my $data = $sth->fetchrow_hashref('NAME_lc');
    $data ? $data->{consumer} : undef;
}

=head2 Accessors
=cut

sub db()             {shift->{SOP_db}}
sub oauthUtil()      {shift->{SOP_util}}  # object
sub consumerKey()    {shift->{SOP_consumer_key}}
sub consumerSecret() {shift->{SOP_cons_secret}}
sub params()         {shift->{SOP_params}}
sub method()         {shift->{SOP_method}}
sub url()            {shift->{SOP_url}}


=head2 Actions

=head3 method checkRequest OPTIONS

Check whether a request is valid.  Returns an HTTP-code and an error
string.  An code of HTTP_OK means success.

  my ($http_code, $http_err) = $provider->checkRequest)
  if($http_code != HTTP_OK) {
     $server->error($http_code, $http_err);
  }

Options:

=over 4

=item * I<checktoken>, boolean

=item * I<url>

=back 

=cut 

sub checkRequest(%)
{   my ($self, %args) = @_;
    trace_call($args{url});

    my $params     = $self->params;
    my $util       = $self->oauthUtil;
    my $checktoken = $args{checktoken} || 0;

    $util->validate_params($params, $checktoken)
        or return (HTTP_BAD, $util->errstr);
 
    my $nonce      = $params->{oauth_nonce};
    my $token      = $params->{oauth_token};
    my $timestamp  = $params->{oauth_timestamp};
    
    $timestamp > time - $self->{old_request_timeout}
        or return (HTTP_UNAUTH, $util->errstr);
    
    my $db         = $self->db;

    my $expire_nonces = time - $self->{nonce_timeout};
    unless($db->do(<<__DELETE_NONCE, $expire_nonces))
DELETE FROM oauthprovider_nonces_table
 WHERE time_oauthprovider < ?
__DELETE_NONCE
    {   log(err => 'Unable to clean nonce store in database');
        return (HTTP_INTERN, 'Unable to clean nonce store');
    }
    
    if($checktoken)
    {   my $key = $self->consumerKey;
        my $sth = $db->prepared(<<'__GET_KEY', $key, $token);
SELECT id_oauthprovider AS id
  FROM oauthprovider_sessions_table
 WHERE consumer_oauthprovider = ?
   AND token_oauthprovider    = ?
__GET_KEY

        unless($sth)
        {   log(err => 'Unable to get token %s %s', $key, $token);
            return (HTTP_INTERN, 'Unable to get token');
        }
        
        if(my $data = $sth->fetchrow_hashref('NAME_lc'))
        {   my $id  = $data->{id};
            my $sth = $db->prepared(<<'__GET_NONCE', $id, $nonce);
SELECT nonce_oauthprovider AS nonce
  FROM oauthprovider_nonces_table
 WHERE id_oauthprovider    = ?
   AND nonce_oauthprovider = ?
__GET_NONCE

            unless($sth)
            {   log(err => "Unable to check provider $id nonce $nonce");
                return (HTTP_INTERN, 'Unable to check nonce');
            }
            
            # Nonce must be new
            not $sth->fetchrow_hashref('NAME_lc')
                or return (HTTP_INTERN, 'Nonce already in use');
 
            unless($db->do(<<'__INSERT_NONCE', $id, $nonce))
INSERT INTO oauthprovider_nonces_table
   SET id_oauthprovider    = ?
     , nonce_oauthprovider = ?
     , time_oauthprovider  = NOW
__INSERT_NONCE
            {   log(err => "Unable to add nonce record $id nonce $nonce");
                return (HTTP_INTERN, 'Unable to add nonce');
            }
        }
    }
    
    my $secret = '';
    if($checktoken)
    {
        my $sth = $db->prepared(<<__PROVIDER, $token);
SELECT secret_oauthprovider AS secret
  FROM oauthprovider_sessions_table
 WHERE token_oauthprovider = ?
__PROVIDER

        my $data = $sth ? $sth->fetchrow_hashref('NAME_lc') : undef;
        unless($data)
        {   log(err => "Unable to load token data $token");
            return (HTTP_INTERN, 'Unable to load token data');
        }

        $secret = $data->{secret};
    }
    
    my $correct = $util->verify_signature
      ( method          => $self->method
      , params          => $self->params
      , url             => $self->url
      , consumer_secret => $self->consumerSecret
      , token_secret    => $secret
      );

    $correct ? (HTTP_OK => 'OK') : (HTTP_UNAUTH => $util->errstr);
}


=head2 method: generateTemporary

Returns the URI parameters to request the authorization.

=cut 

## Create a temporary token
sub generateTemporary(%)
{   my ($self, %args) = @_;

    my $key      = $self->consumerKey;
    my $callback = $self->params->{oauth_callback};
    my $token    = $self->generateRandomString(32);
    my $secret   = $self->generateRandomString(32);

    trace_call($key, $callback, $token, $secret);

    unless($self->db->do(<<'__START_SESSION', $token, $secret, $key, $callback))
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
    {   log(err => 'Unable to add new token record %s %s in database', $token, $key);
        return undef;
    }
    
    my @r =
      ( 'oauth_token='        . uri_escape($token)
      , 'oauth_token_secret=' . uri_escape($secret)
      , 'oauth_expires_in='   . $self->{temporary_timeout}
      , 'oauth_callback_confirmed=true'
      );

    push @r, "xoauth_request_auth_url=$args{authorize}"
        if defined $args{authorize};

    join '&', @r;
}

=head2 method: getTemporary OPTIONS

Retreive a temporary token from database, which is an unblessed HASH.  Returns
C<undef> on failure.

Options:

=over 4

=item * I<token>, the token key.

=item * I<timeout_type>, the timeout key, temporary or verifier.

=back 

=cut 

sub getTemporary(%)
{   my ($self, %args) = @_;
    my $token = $args{token};
    my $key   = $self->consumerKey;

    trace_call($token);
    
    my $sth = $self->db->prepared(<<'__GET_TEMP', $key, $token);
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
    {   log(err => 'Unable to load token data %s %s', $key, $token);
        return undef;
    }
    
    my $data = $sth->fetchrow_hashref('NAME_lc')
        or return undef;

    my $timeout_type = ($args{timeout_type} || 'temporary') . '_timeout';
    my $timeout      = $self->{$timeout_type};

    $data->{lasttime} + $timeout >= time ? $data : undef;
}

=head2 method: generateVerifier OPTIONS

Create the verifier for a temporary token.  Returns the redirect url, or
C<undef> when the token does not exist (anymore) or isn't valid.

Options:

=over 4

=item * I<token>

=item * I<user>

=item * I<granted>, boolean

=back 

=cut 

## Create the verifier for a temporary token
sub generateVerifier
{   my ($self, %args) = @_;

    my $token   = $args{token};
    my $user    = $args{user};
    my $granted = $args{granted} ? 1 : 0;
    my $key     = $self->consumerKey;

    trace_call($token, $user, $granted, $key);
    
    my $tmp = $self->getTemporary(token => $token)
        or return undef;

    my $verifier = $self->generateRandomString(32);
 
    my $db       = $self->db;

    unless($db->do(<<__DELETE_SESSION, $user, $key))
DELETE FROM oauthprovider_sessions_table
 WHERE user_oauthprovider= ?
   AND consumer_oauthprovider= ?
   AND isaccess_oauthprovider=1
__DELETE_SESSION
    {   log(err => 'Unable to delete other already granted access tokens for this user %s %s in database', $user, $key);
        return undef;
    }
    
    unless($db->do(<<'__UPDATE', $verifier, $user, $granted, $key, $token))
UPDATE oauthprovider_sessions_table
   SET verifier_oauthprovider      = ?
     , user_oauthprovider          = ?
     , accessgranted_oauthprovider = ?
     , lasttime_oauthprovider      = NOW
 WHERE isaccess_oauthprovider      IS NULL
   AND consumer_oauthprovider      = ?
   AND token_oauthprovider         = ?
__UPDATE
    {   log(err => 'Unable to set token verifier %s %s in database', $token, $key);
        return undef;
    }
    
    my $r = $tmp->{callback};
    $r   .= $r =~ /^[^\?]\?/ ? '&' : '?';                  # XXX MO: ???
    $r   .= 'oauth_token='     . uri_escape($tmp->{token}) # XXX MO: ==$token??
         .  '&oauth_verifier=' . uri_escape($verifier);
    
    return $r;
}

=head3 method: generateAccess OPTIONS

Create an access token.  Returned is the response body, but C<undef>
if the token does not exist anymore or is invalid.

Options:

=over 

=item * I<token>, the temporary token.

=item * I<verifier>, the verifier.

=back 

=cut 

## Create an access token
sub generateAccess(%)
{   my ($self, %args) = @_;

    my $params   = $self->params;
    my $token    = $args{token}    || $params->{oauth_token};
    my $verifier = $args{verifier} || $params->{oauth_verifier};
    my $key      = $self->consumerKey;

    trace_call($token, $verifier, $key);
    
    my $tmp = $self->getTemporary(token => $token, timeout_type => 'verifier')
        or return;

     $verifier eq $tmp->{verifier}
        or return;
    
    my $tmp_token = $self->generateRandomString(32);
    my $secret    = $self->generateRandomString(32);
    my $db        = $self->db;
    
    unless($db->do(<<'__UPDATE', $tmp_token,$secret, $token,$verifier))
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
    {   log(err => 'Unable to transform temporary token into access token record %s %s in database', $tmp_token, $key);
        return undef;
    }
    
    join '&'
     , 'oauth_token='        . uri_escape($tmp_token)
     , 'oauth_token_secret=' . uri_escape($secret)
     , 'oauth_expires_in='   . $self->{access_timeout};
}

=head3 method: getAccess OPTIONS

Retreive an access token from database.  Returned is the HASH, or C<undef>
when the token does not exist anymore or is invalid.

Options:

=over 4

=item * I<token>

=back 

=cut 

## Retreive an access token from database
sub getAccess(%)
{   my ($self, %args) = @_;
    my $token = $args{token};

    trace_call($token);

    my $key   = $self->consumerKey;
    my $sth   = $self->db->prepared(<<'__GET_ACCESS', $key, $token);
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
    {   log(err => 'Unable to load token data %s %s', $key, $token);
        return undef;
    }
    
    my $data = $sth->fetchrow_hashref('NAME_lc')
        or return undef;

    my $valid_until = $data->{lasttime} + $self->{access_timeout};
    $valid_until >= time ? $data : undef;
}

=head3 method: generateRandomString $size

Return a random string with a sub-set of base64 characters.

=over 4

=item * I<$size>, the string length.

=back 

=cut

sub generateRandomString($)
{   my ($thing, $chars) = @_;
    join '', map { (0..9, 'a'..'z', 'A'..'Z')[rand 62] } 1..$chars;
}


=head3 consumerConfigFor

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

sub consumerConfigFor
{   my ($thing, $key) = @_;
    trace_call($key);
    
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

=head1 AUTHORS 

=over 4

=item * Etienne Meleard <etienne.meleard AT renater.fr> 

=item * Mark Overmeer <solutions@overmeer.net>

=back 

=cut 

1;
