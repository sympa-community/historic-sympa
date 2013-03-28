use warnings;
use strict;

package Sympa::OAuth2;
use base 'Sympa::Plugin';

our $VERSION = '0.10';

my $me = __PACKAGE__->new;

my @url_commands =
  ( oauth2_ready      =>
      { handler   => sub { $me->doAuthReady(@_) }
      , path_args => [ qw/oauth_provider / ]
      , required  => [ qw/oauth_provider oauth_token/]
      }
  );

my @validate =
  ( oauth_provider     => '[^:]+:.+'
# , oauth_signature    => '[a-zA-Z0-9\+\/\=\%]+'
# , oauth_callback     => '[^\\\$\*\"\'\`\^\|\<\>\n]+'
  );

sub registerPlugin($)
{   my ($class, $args) = @_;
    push @{$args->{url_commands}}, @url_commands;
    push @{$args->{validate}}, @validate;
    $class->SUPER::registerPlugin($args);
}

# token and call the right action
sub doAuthReady(%)
{   my ($self, %args) = @_;
    my $in    = $args{in};
    my $param = $args{param};

    my $callback = main::do_ticket();

    $in->{oauth_ready_done} = 1;

    $in->{oauth_provider}   =~ /^([^:]+):(.+)$/
        or return undef;

    my ($type, $provider) = ($1, $2);

      ) or return undef;

# XXX
    return $callback;
}

1;
