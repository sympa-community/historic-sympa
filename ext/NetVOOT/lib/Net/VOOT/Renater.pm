package Net::VOOT::Renater;
use base 'Net::VOOT';

use warnings;
use strict;

use Log::Report 'net-voot';

use OAuth::Lite::Consumer ();
use OAuth::Lite::Token    ();

# default parameters for Renater servers
# XXX MO: to be filled in
my %auth_defaults;

=chapter NAME
Net::VOOT::Renater - access to a VOOT server of Renater

=chapter SYNOPSIS

  my $voot = Net::VOOT::Renater->new(auth => $auth);

=chapter DESCRIPTION
This module provides an implementation of a VOOT client in a Renater-style
VOOT setup, which may be served via Sympa.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=requires auth M<OAuth::Lite::Consumer>|HASH

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args) or return;

    my $auth = $args->{auth};
    $auth    = OAuth::Lite::Consumer->new(%auth_defaults, %$auth)
        if ref $auth eq 'HASH';

    $self->{NVR_auth} = $auth
       or error __x"no configuration for authorization provided";

    $self;
}

#---------------------------
=section Attributes
=method auth
=cut

sub auth()        {shift->{NVR_auth}}

sub authType()    { 'OAuth1' }

#---------------------------
=section Actions
=cut

sub get($$$)
{   my ($self, $session, $url, $params) = @_;

    my $resp = $self->auth->request
      ( method => 'GET'
      , url    => $url
      , token  => $self->accessToken($session)
      , params => $params
      );

    return $resp
        if $resp->is_success;

    if($resp->status > 400)
    {   my $auth_header = $resp->header('WWW-Authenticate') || '';

        # access token may be expired, retry
        $self->triggerFlow if $auth_header =~ /^OAuth/;
    }

    $resp;
}

#---------------------------
=section Sessions


=cut

sub newSession(%)
{   my ($self, %args) = @_;

    my $user    = $args{user};
    my $prov_id = $args{provider};

    my $auth    = $self->auth;
    my $tmp     = $auth->get_request_token(callback_url => $args{callback});

    unless($tmp)
    {   error __x"unable to get tmp token for {user} {provider}: {err}"
           , $user, $prov_id, $auth->errstr;
        return undef;
    }

    +{ user => $user, provider => $prov_id, tmp => $tmp };
}

sub restoreSession($$$)
{   my ($self, $user, $provider, $data) = @_;
    my $session     = $self->newSession($user, $provider);

    $session->{tmp} = OAuth::Lite::Token->new
      ( token  => $data->{tmp_token}
      , secret => $data->{tmp_secret}
      ) if $data->{tmp_token};

    $session->{access} = OAuth::Lite::Token->new
      ( token  => $data->{access_token},
      , secret => $data->{access_secret}
      ) if $data->{access_token};

    $session;
}

=method accessToken SESSION
=cut

sub accessToken($) { $_[1]->{access} }

1;
