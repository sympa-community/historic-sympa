package Net::VOOT::Renater;
use base 'Net::VOOT';

use warnings;
use strict;

use Log::Report 'net-voot';

use OAuth::Lite::Consumer ();

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

=requires auth M<OAuth::Lite::Consumer> object

=option  access_token M<OAuth::Lite::Token>-object
=default access_token C<undef>
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args) or return;

    $self->{NVR_auth} = $args->{auth} || $self->createAuth($args)
       or error __x"no configuration for authorization provided";

    $self->{NVR_acctoken} = $args->{access_token};
    $self;
}

#---------------------------
=section Attributes
=method auth
=method accessToken
=cut

sub auth()        {shift->{NVR_auth}}
sub accessToken() {shift->{NVR_acctoken}}

#---------------------------
=section Actions
=method get URI, PARAMS
=cut

sub get($;$)
{   my ($self, $url, %params) = @_;

    $self->auth->request
      ( method => 'GET'
      , url    => $url
      , token  => $self->accessToken
      , params => \%params
      );
}

#---------------------------
=section Helpers
=cut

=method createAuth
Create an authorization object based on the provider INFO.
=cut

sub createAuth($)
{   my ($self, $args) = @_;
    OAuth::Lite::Consumer->new
      ( consumer_key       => $args->{ConsumerKey}
      , consumer_secret    => $args->{ConsumerSecret}
      , request_token_path => $args->{RequestURL}
      , access_token_path  => $args->{AccessURL}
      , authorize_path     => $args->{AuthorizationURL}
      );
}

1;
