package Sympa::OAuth1::Consumer;
use strict;
use warnings;

use OAuth::Lite::Consumer;

use Sympa::Plugin::Util qw/:functions :http/;

=head1 NAME 

Sympa::OAuth1::Consumer - OAuth v1 consumer

=head1 SYNOPSIS

=head1 DESCRIPTION 

This package provides abstraction from the OAuth workflow (client side)
when performing authorization request, handles token retrieving as well
as database storage.

=head1 METHODS

=head2 Constructors

=head3 class method: new OPTIONS

Create the object, returns C<undef> on failure.

Options:

=over 4

=item * I<user> =E<gt> EMAIL-ADDRESS

=item * I<provider> =E<gt> STRING, provider key

=item * I<provider_secret> =E<gt> STRING, provider shared secret

=item * I<request_token_path> =E<gt> URL, the temporary token request URL

=item * I<access_token_path> =E<gt> URL, the access token request URL

=item * I<authorize_path> =E<gt> URL, the authorization URL

=back 

=cut 

sub new(@) { my $class = shift; (bless {}, $class)->init({@_}) }

sub init($)
{   my ($self, $args) = @_;
    $self->{$_} = $args->{$_}
        for qw/user provider consumer_key consumer_secret
               request_token_path access_token_path authorize_path/;

    $self->{redirect_url} = undef;
    $self->{SOC_db} = $args->{db} || default_db;

    my $user     = $self->{user};
    my $provider = $self->{provider};
    my $key      = $self->{consumer_key};
    trace_call($user, $provider, $key);

    $self->{SOC_handler} = $self->_create_handler($key);
    $self->{SOC_session} = $self->_create_session($user, $provider);
    $self;
}

sub _create_handler($)
{   my ($self, $key) = @_;
    OAuth::Lite::Consumer->new
      ( consumer_key       => $key
      , consumer_secret    => $self->{consumer_secret}
      , request_token_path => $self->{request_token_path}
      , access_token_path  => $self->{access_token_path}
      , authorize_path     => $self->{authorize_path}
      );
}

sub _create_session($$)
{   my ($self, $user, $provider) = @_;

    my $sth  = $self->db->prepared(<<'__GET_TMP_TOKEN', $user, $provider);
SELECT tmp_token_oauthconsumer     AS tmp_token
     , tmp_secret_oauthconsumer    AS tmp_secret
     , access_token_oauthconsumer  AS access_token
     , access_secret_oauthconsumer AS access_secret
  FROM oauthconsumer_sessions_table
 WHERE user_oauthconsumer     = ?
   AND provider_oauthconsumer = ?
__GET_TMP_TOKEN

    unless($sth)
    {   log(err => "Unable to load token data for $user at $provider");
        return undef;
    }
    
    my %session;
    if(my $data = $sth->fetchrow_hashref('NAME_lc'))
    {
        $session{tmp} = OAuth::Lite::Token->new
          ( token  => $data->{tmp_token}
          , secret => $data->{tmp_secret}
          ) if $data->{tmp_token};

        $session{access} = OAuth::Lite::Token->new
          ( token  => $data->{access_token},
          , secret => $data->{access_secret}
          ) if $data->{access_token};

        $session{defined} = 1;
    }
    \%session;
}


=head2 Accessors

=head3 method: db

=head3 method: mustRedirect

Returns the URL to redirect to, if we need to redirect for autorization.

=head3 method: session

=head3 method: handler

=head3 method: webenv

=head3 method: setWebEnv OPTIONS

=cut

sub db           { shift->{SOC_db}       }
sub mustRedirect { shift->{redirect_url} }
sub session      { shift->{SOC_session}  }
sub handler      { shift->{SOC_handler}  }
sub webenv       { shift->{SOC_webenv}   }

sub setWebEnv(%)
{   my $self = shift;
    $self->{SOC_webenv} = { @_ };
}

=head2 method: fetchResource OPTIONS

Check if user has an access token already and fetch resource.

Options:

=over 

=item * I<url>, the resource url.

=item * I<params>, (optional) the request parameters.

=back 

=cut 

## Check if user has an access token already and fetch ressource
sub fetchResource(%)
{   my ($self, %args) = @_;
    
    my $url = $args{url};
    trace_call($url);
    
    my $token = $self->hasAccess
        or return undef;

    my $res = $self->handler->request
      ( method => 'GET' 
      , url    => $url
      , token  => $token
      , params => $args{params}
      );
    
    return $res->decoded_content || $res->content
        if $res->is_success;

    if($res->status == HTTP_BAD || $res->status == HTTP_UNAUTH)
    {   my $auth_header = $res->header('WWW-Authenticate') || '';

        # access token may be expired, retry
        $self->triggerFlow if $auth_header =~ /^OAuth/;
    }

    ();
}

=head3 method: hasAccess

Returns the access token as HASH when already present.  Triggers the
authentication flow otherwise.

=cut 

sub hasAccess()
{   my $self = shift;
    trace_call($self->{user}, "$self->{consumer_type}:$self->{provider}");

    if(my $access = $self->session->{access})
    {   return $access;
    }

    $self->triggerFlow;
    undef;
}


=head2 method: triggerFlow

Triggers OAuth authorization workflow, but only in web env.  Returns
whether this was successful.

=cut 

sub triggerFlow()
{   my $self = shift;

    my $web       = $self->webenv
        or return 0;

    my $user      = $self->{user};
    my $type      = $self->{consumer_type};
    my $provider  = $self->{provider};
    trace_call($user, "$type:$provider");
    
    my $here_path = $web->{here_path};

    my $ticket    = Auth::create_one_time_ticket($user
       , $web->{robot}, $here_path, 'mail');

    my $callback  = "$web->{base_path}/oauth_ready/$provider/$ticket";
    my $handler   = $self->handler;
 
    my $tmp = $handler->get_request_token(callback_url => $callback);
    unless($tmp)
    {   log(err => "Unable to get tmp token for $user $provider: ".$handler->errstr);
        return undef;
    }

    my $session  = $self->session;
    my $db       = $self->db;

    if($session->{defined})
    {    unless($db->do(<<'__UPDATE_SESSION', $tmp->{token}, $tmp->{secret}, $user, $provider))
UPDATE oauthconsumer_sessions_table
   SET tmp_token_oauthconsumer  = ? 
     , tmp_secret_oauthconsumer = ?
 WHERE user_oauthconsumer       = ?
   AND provider_oauthconsumer   = ?
__UPDATE_SESSION
          {   log(err => "Unable to update token record $user $provider");
              return undef;
          }
    }
    else
    {   unless($db->do(<<'__INSERT_SESSION', $user, $provider, $tmp->{token}, $tmp->{secret}))
INSERT INTO oauthconsumer_sessions_table
   SET user_oauthconsumer       = ?
     , provider_oauthconsumer   = ?
     , tmp_token_oauthconsumer  = ?
     , tmp_secret_oauthconsumer = ?
__INSERT_SESSION
         {   log(err => "Unable to add new token record $user $provider");
             return undef;
         }
    }
    
    $session->{tmp} = $tmp;
    
    my $url = $handler->url_to_authorize(token => $tmp);
    log(info => "redirect to $url with callback $callback for $here_path");

    $self->{redirect_url} = $url;
    return 1;
}


=head2 method: getAccessToken OPTIONS

Try to obtain access token from verifier.

=over 4

=item I<token>

=item I<verifier>

=back

=cut 

sub getAccessToken(%)
{   my ($self, %args) = @_;

    my $verifier = $args{verifier};

    my $user     = $self->{user};
    my $type     = $self->{consumer_type};
    my $provider = $self->{provider};
    my $session  = $self->{session};

    trace_call($user, "$type:$provider");
    return $session->{access}
        if $session->{access};

    my $tmp = $session->{tmp};
    $tmp && $tmp->token eq $args{token} && $verifier
        or return undef;
    
    my $access = $self->handler->get_access_token
      ( token    => $tmp
      , verifier => $verifier
      );
    
    $session->{access} = $access;
    $session->{tmp}    = undef;
    
    unless($self->db->do(<<'__UPDATE_SESSION', $access->{token}, $access->{secret}, $user, $provider))
UPDATE oauthconsumer_SOC_sessions_table
   SET tmp_token_oauthconsumer     = NULL
     , tmp_secret_oauthconsumer    = NULL
     , access_token_oauthconsumer  = ?
     , access_secret_oauthconsumer = ?
 WHERE user_oauthconsumer          = ?
   AND provider_oauthconsumer      = ?
__UPDATE_SESSION
    {   log(err => "Unable to update token record $user $provider");
        return undef;
    }
    
    $access;
}

=head1 AUTHORS 

=over 4

=item * Etienne Meleard <etienne.meleard AT renater.fr> 

=item * Mark Overmeer <mark AT overmeer.net >

=back 

=cut 

1;
