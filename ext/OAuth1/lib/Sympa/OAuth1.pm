use warnings;
use strict;

package Sympa::OAuth1;
use base 'Sympa::Plugin';

our $VERSION = '0.10';

use Sympa::OAuth1::Provider;

my $me = __PACKAGE__->new;

my @url_commands =
  ( oauth_check      => 
      { handler   => sub { $me->doOAuthCheck(@_) }
      , path_args => 'oauth_provider'
      , required  => [ qw/param.user.email oauth_provider/ ]
      }
  , oauth_temporary  =>
      { handler   => sub { $me->doOAuthTemporary(@_) }
      }
  , oauth_authorize  =>
      { handler   => sub { $me->doOAuthAuthorize(@_) }
      , required  => [ qw/param.user.email oauth_token/ ]
      }
  , oauth_access     =>
      { handler   => sub { $me->do_oauth_access(@_) }
      }
  );

my @validate =
  ( oauth_provider     => '[^:]+:.+'
  , oauth_authorize_ok => '.+'
  , oauth_authorize_no => '.+'
  , oauth_signature    => '[a-zA-Z0-9\+\/\=\%]+'
  , oauth_callback     => '[^\\\$\*\"\'\`\^\|\<\>\n]+'
  );

sub registerPlugin($)
{   my ($class, $args) = @_;
    push @{$args->{url_commands}}, @url_commands;
    push @{$args->{validate}}, @validate;
    $class->SUPER::registerPlugin($args);
}

#### Using HTTP_AUTHORIZATION header requires httpd config customization :
# <Location /sympa>
#   RewriteEngine on
#   RewriteBase /sympa/
#   RewriteCond %{HTTP:Authorization} (.+)
#   RewriteRule ^ - [e=HTTP_AUTHORIZATION:%1,L]
#   SetHandler fcgid-script
# </Location>

# Consumer requests a temporary token
sub doOAuthTemporary(%)
{   my ($self, %args) = @_;

    my $param = $args{param};
    my $in    = $args{in};

    $param->{bypass} = 'extreme';

    my $provider = $self->createProvider('oauth_temporary', $param, $in, 0)
        or return 1;

    print $provider->generateTemporary;
    1;
}

# User needs to authorize access
sub doOAuthAuthorize(%)
{   my ($self, %args) = @_;
    my $in      = $args{in};
    my $param   = $args{param};
    my $session = $args{session};

    my $token   = $param->{oauth_token} = $in->{oauth_token};
    my $oauth1  = 'Sympa::OAuth1::Provider';

    my $key     = $param->{consumer_key} = $oauth1->consumerFromToken($token)
        or return undef;

    $param->{consumer_key} = $key;

    my $verifier = $session->{oauth_authorize_verifier};
    my $in_verif = $in->{oauth_authorize_verifier} || '';
    if(!$verifier || $verifier ne $in_verif)
    {   $session->{oauth_authorize_verifier}
          = $param->{oauth_authorize_verifier}
          = $oauth1->generateRandomString(32);
        return 1;
    }

    delete $session->{oauth_authorize_verifier};

    my $provider = $oauth1->new
      ( method => $ENV{REQUEST_METHOD}
      , request_parameters =>
         +{ oauth_token        => $token
          , oauth_consumer_key => $key
          }
      ) or return;


    my $access_granted = defined $in->{oauth_authorize_ok}
                     && !defined $in->{oauth_authorize_no};

    my $r = $provider->generateVerifier
      ( token   => $token
      , user    => $param->{user}{email}
      , granted => $access_granted
      ) or return;

    main::do_redirect($r);
    1;
}

# Consumer requests an access token
sub do_oauth_access(%)
{   my ($self, %args) = @_;
    my $param        = $args{param};
    $param->{bypass} = 'extreme';

    my $provider = $self->createProvider('oauth_access', $param, $args{in}, 1)
        or return 1;

    print $provider->generateAccess;
    return 1;
}

# User asks for access token check
sub doOAuthCheck(%)
{   my ($self, %args) = @_;
    my $in    = $args{in};
    my $param = $args{params};

    my $user  = $param->{user}{email};

    @{$param}{ qw/oauth_prov_id_ok oauth_config_ok oauth_check_ok/ } = ();

    $in->{oauth_prov_id} =~ /^([^:]+):(.+)$/
        or return 1;

    # $type is always 'voot'
    my ($type, $prov_id) = ($1, $2);

    $param->{oauth_prov_id_ok} = 1;

    my $here     = "oauth_check/$in->{oauth_prov_id}";
    my $new_ticket = Sympa::VOOT->ticketFactory($param, $here);
    my $next     = "$param->{base_url}$param->{path_cgi}/oauth_ready/$prov_id";

    my $go       = sub { $next .'/'. $new_ticket->() };
    my $consumer = Sympa::VOOT->new->consumer(user => $user, prov_id => $prov_id
      , newflow => $go) or return 1;

    $param->{oauth_config_ok} = 1;

    my $data = $consumer->check;   # XXX ???
    unless($data)
    {   my $url = $consumer->mustRedirect;
        return $url ? main::do_redirect($url) : 1;
    }

    $param->{oauth_check_ok}       = 1;
    $param->{oauth_access_renewed} = defined $in->{oauth_ready_done};
    return 1;
}

sub createProvider($$$$)
{   my ($thing, $for, $param, $in, $check) = @_;

    my $provider = Sympa::OAuth1::Provider->new
      ( method               => $ENV{REQUEST_METHOD}
      , url                  => "$param->{base_url}$param->{path_cgi}/$for"
      , authorization_header => $ENV{HTTP_AUTHORIZATION}
      , request_parameters   => $in
      );

    my $bad = $provider ? $provider->checkRequest(checktoken => $check) : 400;
    my $http_code = $bad || 200;
    my $http_str  = !$bad ? 'OK'
                  : $provider ? $provider->{util}->errstr
                  : 'Bad Request';

    print <<__HEADER;
Status: $http_code $http_str
Cache-control: no-cache
Content-type: text/plain

__HEADER

    $bad ? undef : $provider;
}

1;
