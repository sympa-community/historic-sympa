# load the VOOT plugin
package Sympa::VOOT;
use parent 'Sympa::Plugin';

use warnings;
use strict;

my @url_commands =
  ( opensocial =>
      { handler   => \&_do_opensocial
      , path_args => 'list'
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  , voot =>
      { handler   => \&_do_voot
      , path_args => '@voot_path'
      }
  , select_voot_provider_request =>
      { handler   => \&_do_select_voot_provider_request
      , path_args => 'list'
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  , select_voot_groups_request  =>
      { handler   => \&_do_select_voot_groups_request
      , path_args => [ qw/list voot_provider/ ]
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  , select_voot_groups =>
      { handler   => \&_do_select_voot_groups
      , path_args => [ qw/list voot_provider/ ]
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  );

my @validate =
  ( voot_path => '[^<>\\\*\$\n]+'
  );  

sub register($)
{   my ($class, $args) = @_;
    push @{$args{url_commands}}, @url_commands;
    push @{$args{validate}}, @validate;
    $class->SUPER::register($args);
}

=head1 NAME

Sympa::VOOT - manage the VOOT plugin

=head1 DESCRIPTION

=head1 METHODS

=head2 Constructors

=over 4

=head3 new OPTIONS

OPTIONS:
   config FILENAME            voot configuration file (required)

=cut

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;
    $self->{SV_config} = $args->{config};
    $self;
}

=head2 Accessors

=head3 method config

=cut

sub config() { shift->{SV_config} }

=back

=head2 Actions

=cut

sub _do_opensocial {
    return 'select_voot_provider_request';
}

# VOOT request
sub _do_voot(%)
{   my %args = @_;
    my $param = $args{param};
    my $in    = $args{in};

    $param->{bypass} = 'extreme';
    
    my $voot_path = $in->{voot_path};
    my $provider = Sympa::VOOT::Renater->new
      ( method    => $ENV{REQUEST_METHOD}
      , voot_path => $voot_path
      , url       => "$param->{base_url}$param->{path_cgi}/voot/$voot_path"
      , authorization_header => $ENV{HTTP_AUTHORIZATION}
      , request_parameters   => $in
      , robot     => $robot_id
      );
    
    my $bad       = $provider ? $provider->checkRequest : 400;
    my $http_code = $bad || 200;
    my $http_str
      = !$bad     ? 'OK'
      : $provider ? $provider->getOAuthProvider()->{'util'}->errstr
      :             'Bad Request';
    
    my $r      = $provider->response;
    my $err    = $provider->{error};
    my $status = $err || "$http_code $http_str";
    
    print <<__HEADER;
Status: $status
Cache-control: no-cache
Content-type: text/plain
__HEADER

    print $r unless $err;
    return 1;
}

# Displays VOOT providers list
sub _do_select_voot_provider_request(%)
{   my %args = @_;
    $param->{voot_providers} = VOOTConsumer::getProviders();
    return 1;
}

# Display groups list for user/VOOT_provider
sub _do_select_voot_groups_request(%)
{   my %args = @_;
    my $in       = $args{in};
    my $param    = $args{param};
    
    my $provider = $param->{voot_provider} = $in->{voot_provider};
    my $email    = $param->{user}{email};
    
    my $voot     = VOOTConsumer->new
      ( user      => $email
      , provider  => $provider
      ) or return undef;

    my $consumer = $voot->getOAuthConsumer;
    $consumer->setWebEnv
      ( robot     => $robot_id
      , here_path => "select_voot_groups_request/$param->{list}/$provider"
      , base_path => "$param->{base_url}.$param->{path_cgi}"
      ) unless $in{oauth_ready_done};

    my $groups = $param->{voot_groups} = $voot->isMemberOf;
    unless(defined $groups) {
        my $url = $consumer->mustRedirect;
        return do_redirect($url) if defined $url;
    }
    
    return 1;
}

# VOOT groups choosen, generate config
sub _do_select_voot_groups(%)
{   my %args     = @_;
    my $param    = $args{param};
    my $in       = $args{in};
    my $list     = $args{list};

    my $provider = $param->{voot_provider} = $in->{voot_provider};
    my $email    = $param->{user}{email};

    my @groups;
    foreach my $k (keys %in) {
        $k =~ /^voot_groups\[([^\]]+)\]$/ or next;
        push @groups, $1 if $in{$k}==1;
    }
    $param->{voot_groups}  = \@groups;

    my @include_voot_group = @{$list->include_voot_group};    
    foreach my $gid (@groups)
    {   push @include_voot_group,
         +{ name     => "$provider\::$gid"
          , user     => $email
          , provider => $provider
          , group    => $gid
          };

        # XXX MO: ???
        # No save otherwise ...
        $list->defaults(include_voot_group => undef);
    }
    $list->include_voot_group(\@include_voot_group);

    my $action = $param->{action};
    unless($list->save_config($email))
    {   report::reject_report_web('intern', 'cannot_save_config', {}
          , $action, $list, $email, $robot_id);

        main::wwslog(info => 'do_select_voot_groups: Cannot save config file');
        main::web_db_log({status => 'error', error_type => 'internal'});
        return undef;
    }    

    if($list->on_the_fly_sync_include(use_ttl => 0))
    {   report::notice_report_web('subscribers_updated', {}, $action);
    }
    else
    {   report::reject_report_web('intern', 'sync_include_failed'
           , {}, $action, $list, $email, $robot_id);
    }
    return 'review';
}

1;
