package Net::VOOT::SURFconext;
use base 'Net::VOOT';

use warnings;
use strict;

use Log::Report 'net-voot';
use Net::OAuth2::Profile::WebServer;

my $site_test = 'https://frko.surfnetlabs.nl/frkonext/';
my $site_live = 'unknown';

=chapter NAME
Net::VOOT::SURFconext - access to a VOOT server of SURFnet

=chapter SYNOPSIS

  my $voot = Net::VOOT::SURFconext->new(test => 1);

=chapter DESCRIPTION
"SURFconext" is an Dutch (i.e. Netherlands) national infrastructure
(organized by SURFnet) which arranges access-rights to people on
universities and research institutes (participants) to facilities offered
by other participants.  For instance, a student on one university can
use the library and WiFi of an other university when he is on visit there.

SURFconext uses OAuth2 authentication.
=chapter METHODS

=section Constructors

=c_method new OPTIONS

=default provider 'surfnet'
When 'test' is set, then the name is 'surfnet-test'.

=default voot_base <site>/php-voot-proxy/voot.php

=option  test BOOLEAN
=default test <false>
Access the current test environment, provided by SURFnet.

=option  auth M<Net::OAuth2::Profile::WebServer> object
=default auth <created for you>
If you do not provide an object, you need to add some parameters to
initialize the object.  See M<createAuth()> for the OPTIONS.

=option  site URI
=default site <hard-coded>
Depends whether you need the test voot server or the production environment.

=option  token M<Net::OAuth2::AccessToken>-object
=default token <requested when needed>
=cut

sub init($)
{   my ($self, $args) = @_;
    my $test = delete $args->{test} || 0;
    my $site = $args->{site} ||= $test ? $site_test : $site_live;
    $args->{provider}  ||= 'surfnet'.($test ? '-test' : '');
    $args->{voot_base} ||= "$site/php-voot-proxy/voot.php";

    $self->SUPER::init($args) or return;

    $self->{NVS_token}   = $args->{token};
    $self->{NVS_auth}    = $args->{auth} || $self->createAuth($args);
    $self;
}

#---------------------------
=section Attributes

=method auth
=method token
=cut

sub auth()  {shift->{NVS_auth}}
sub token() {my $self = shift; $self->{NVS_token} || $self->requestToken}

#---------------------------
=section Actions
=method 

#---------------------------
=section Helpers

=method createAuth OPTIONS
Returns an M<Net::OAuth2::Profile::WebServer> object.
The C<client_id>, C<client_secret> and C<redirect_uri> are registered
at the VOOT provider: they relate to the C<site>.

=requires site          URI
=requires client_id     STRING
=requires client_secret PASSWORD
=requires redirect_uri  URI
=cut

sub createAuth(%)
{   my ($self, %args) = @_;

    foreach my $param (qw/client_id client_secret site redirect_uri/)
    {   $args{$param}
            or error __x"VOOT auth needs value for {param}"
               , param => $param;
    }
    my $site = $args{site};

    my $auth = Net::OAuth2::Profile::WebServer->new
      ( client_id         => ($args{client_id}     || panic)
      , client_secret     => ($args{client_secret} || panic)
      , token_scheme      => 'auth-http:Bearer'

      , site              => $site
      , authorize_path    => 'php-oauth/authorize.php'
      , authorize_method  => 'GET'
      , access_token_path => 'php-oauth/token.php'

      , redirect_uri      => ($args{redirect_uri} || panic)
      , referer           => $site
      );

    trace "initialized oauth2 for voot to ".$self->provider if $auth;
    $auth;
}

=method requestToken OPTIONS
=cut

sub requestToken()
{   my $self    = shift;
    my $auth    = $self->auth;
    my $service = $auth->authorize(scope => 'read') or return;
    my $token   = $auth->get_access_token($service->{code});
    trace 'received token from '.$self->provider. ' for '.$auth->client_id;

    $token;
}

sub get($)
{   my ($self, $uri) = @_;
    $self->token->get($uri);
}

#-------------------

=chapter DETAILS

SURFconext is a service provided by SURFnet Nederland BV (NL)

SURFconext is an authorization provider which encapsulates authorization
mechanisms of all Dutch universities (and other higher educational
institutes) and many research organisations.  SURFconext enables the
students and employees of the participants to use each other's facilities.

B<Be warned:> SURFconext uses OAuth2 which requires that your client
website uses secure HTTP: https!

=section Setting up the test server

SURFnet's test environment is currently located at
L<https://frko.surfnetlabs.nl/frkonext/>.
On that page, you can register applications, which otherwise is a task
for SURFnet's security manager.

Go to the page which demonstrates the "manage applications" feature.  Login
using the C<admin> username as listed on the front page.  Register your
application with

=over 4

=item I<identifier>
Pick a clear identifier based on the service and your organisation.  For
instance, C<sympa-uva> for organisation UvA service sympa.  You
need to pass this to C<new(client_id)>

=item I<profile>
Only profile "Web Application" is supported by this module, for now.

=item I<redirect URI>
This will bring people back to your own installation after verfication
has succeeded.

=item pick any string as I<secret>
You need to pass that as C<new(client_secret)>.  Be warned: everyone
logs-in as the same admin user, so can see your secret.

=item Set I<Allowed Scope> to "read" or "write"

=back

B<Be aware> the registrations in the test-environment are regularly and
unpredictably flushed.  Also, the location of the service may change without
notice.

=section Setting up the "live" server
=cut

1;
