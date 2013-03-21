
package Sympa::OAuth1;

use Sympa::OAuth1::Provider;
use Sympa::VOOT::Renater;

BEGIN {
  ### try to create a simple plugin-interface until there is a real one
  # these globals are copied during initiation
  my %url_commands =
  (
    oauth_check      => 
      { handler   => \&_do_oauth_check
      , path_args => 'oauth_provider'
      , required  => [ qw/param.user.email oauth_provider/ ]
      }
  , oauth_ready      =>
      { handler   => \&_do_oauth_ready
      , path_args => [ qw/oauth_provider ticket/ ]
      , required  => [ qw/oauth_provider ticket oauth_token oauth_verifier/]
      }
  , oauth_temporary  =>
      { handler   => \&_do_oauth_temporary
      }
  , oauth_authorize  =>
      { handler   => \&_do_oauth_authorize
      , required  => [ qw/param.user.email oauth_token/ ]
      }
  , oauth_access     =>
      { handler   => \&_do_oauth_access
      }
  );

  my %validate =
  ( oauth_provider     => '[^:]+:.+'
  , oauth_authorize_ok => '.+'
  , oauth_authorize_no => '.+'
  , oauth_signature    => '[a-zA-Z0-9\+\/\=\%]+'
  , oauth_callback     => '[^\\\$\*\"\'\`\^\|\<\>\n]+'
  );

  main::load_plugin
    ( url_commands => \%url_commands
    , validate     => \%validate
    );
}
### END

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;
    $self;
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
sub _do_oauth_temporary(%)
{   my %args = @_;

    my $param = $args{param};
    $param->{bypass} = 'extreme';

    my $provider = $self->create_provider('oauth_temporary', $param, $in, 0)
        or return 1;

    print $provider->generateTemporary;
    1;
}

# User needs to authorize access
sub _do_oauth_authorize(%)
{   my %args    = @_;
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
    if(!$verifier || $verifier ne $in_verifier)
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
{   my %args  = @_;
    my $param        = $args{param};
    $param->{bypass} = 'extreme';

    my $provider = $self->create_provider('oauth_access', $param, $args{in}, 1)
        or return 1;

    print $provider->generateAccess;
    return 1;
}

# User asks for access token check
sub do_oauth_check(%)
{   my %args = @_;
    my $in    = $args{in};
    my $param = $args{params};

    @{$param}{ qw/oauth_provider_ok oauth_config_ok oauth_check_ok/ } = ();

    $in->{oauth_provider} =~ /^([^:]+):(.+)$/
        or return 1;

    # $type is always 'voot'
    my ($type, $provider) = ($1, $2);

    $param->{oauth_provider_ok} = 1;

    my $voot = Sympa::VOOT::Renater->new
      ( user     => $param->{user}{email}
      , provider => $provider
      ) or return 1;

    $param->{oauth_config_ok} = 1;

    my $consumer = $voot->getOAuthConsumer;

    $consumer->setWebEnv
      ( robot     => $robot_id
      , here_path => "oauth_check/$in->{oauth_provider}"
      , base_path => "$param->{base_url}$param->{path_cgi}"
      );

    my $data = $voot->check;

    unless($data)
    {   my $url = $consumer->mustRedirect;
        return main::do_redirect($url) if $url;
    }

    $param->{oauth_check_ok}       = 1;
    $param->{oauth_access_renewed} = defined $in->{oauth_ready_done};
    return 1;
}

# Got back from OAuth workflow (provider), needs to get authorization
# token and call the right action
sub do_oauth_ready(%)
{   my %params   = @_;
    my $in       = $params{in};

    my $callback = main::do_ticket();

    $in->{oauth_ready_done} = 1;

    $in->{oauth_provider}   =~ /^([^:]+):(.+)$/
        or return undef;

    my ($type, $provider) = ($1, $2);

    my $voot = Sympa::VOOT::Renater->new
       ( user     => $param->{user}{email}
       , provider => $provider
       ) or return undef;

    my $consumer = $voot->getOAuthConsumer;
    $consumer->getAccessToken
      ( verifier => $in->{oauth_verifier}
      , token    => $in->{oauth_token}
      ) or return undef;

    return $callback;
}

sub create_provider($$$$)
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
