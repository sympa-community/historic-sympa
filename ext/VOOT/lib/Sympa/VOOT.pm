package Sympa::VOOT;
use base 'Sympa::Plugin';

use warnings;
use strict;

our $VERSION = '0.10';

use JSON           qw/decode_json/;
use List::Util     qw/first/;

# Sympa modules
use report;
use Site;

# These should (have been) modularized via Log::
*wwslog     = \&main::wwslog;
*web_db_log = \&main::web_db_log;

my @url_commands =
  ( opensocial =>
      { handler   => \&do_opensocial
      , path_args => 'list'
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  , voot =>
      { handler   => \&do_voot
      , path_args => '@voot_path'
      }
  , select_voot_provider_request =>
      { handler   => \&do_select_voot_provider_request
      , path_args => 'list'
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  , select_voot_groups_request  =>
      { handler   => \&do_select_voot_groups_request
      , path_args => [ qw/list voot_provider/ ]
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  , select_voot_groups =>
      { handler   => \&do_select_voot_groups
      , path_args => [ qw/list voot_provider/ ]
      , required  => [ qw/param.user.email param.list/ ]
      , privilege => 'owner'
      }
  );

my @validate =
  ( voot_path => '[^<>\\\*\$\n]+'
  );  

my @fragments =
  ( list_menu => 'list_menu_opensocial.tt2'
  );

my %include_voot_form =
  ( group      => 'data_source'
  , gettext_id => 'VOOT group inclusion'
  , format     =>
     [ name =>
        { gettext_id => 'short name for this source'
        , format     => '.+'
        , length     => 15
        }
     , user =>
        { gettext_id => 'user'
        , format     => '\S+'
        }
     , provider =>
        { gettext_id => 'provider'
        , format     => '\S+'
        }
     , group =>
        { gettext_id => 'group'
        , format     => '\S+'
        }
     ]
  , occurrence => '0-n'
  );

sub register_plugin($)
{   my ($class, $args) = @_;
    push @{$args->{url_commands}}, @url_commands;
    push @{$args->{validate}}, @validate;

    (my $templ_dir = __FILE__) =~ s,\.pm$,/web_tt2,;
    push @{$args->{templates}},
     +{ tt2_path      => $templ_dir
      , tt2_fragments => \@fragments
      };
    push @{$args->{listdef}},
      ( include_voot_group => \%include_voot_form
      );

    $class->SUPER::register_plugin($args);
}

=head1 NAME

Sympa::VOOT - manage VOOT use in Sympa

=head1 SYNOPSIS

  my $voot = Sympa::VOOT->new(config => $filename);

=head1 DESCRIPTION

Integrate VOOT with Sympa.  This module handles the web interface, and
the various VOOT backends.

=head1 METHODS

=head2 Constructors

=over 4

=head3 class method: new OPTIONS

OPTIONS:
   config FILENAME|HASH            voot configuration file (default voot.conf)

=cut

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    my $config = $args->{config} || Site->get_etc_filename('voot.conf');

    if(ref $config eq 'HASH')
    {   $self->{SV_config}    = $config;
        $self->{SV_config_fn} = 'HASH';
    }
    else
    {   $self->{SV_config}    = $self->read_config($config);
        $self->{SV_config_fn} = $config;
    }

    $self;
}


=head2 Accessors

=head3 method: config

=head3 method: config_filename

=cut

sub config() { shift->{SV_config} }
sub config_filename() { shift->{SV_config_fn} }


=head2 Configuration handling

=head3 read_config FILENAME

=cut

sub read_config($)
{   my ($thing, $filename) = @_;
    local *IN;

    open IN, '<:encoding(utf8)', $filename
        or Log::fatal_err("cannot read VOOT config from $filename");

    local $/;
    my $config = eval { decode_json <IN> };
    $@ and Log::fatal_err("parse errors in VOOT config $filename: $@");

    close IN
        or Log::fatal_err("read errors in VOOT config $filename: $@");

    $config;
}

=head3 provider ID

Returns the object which handles the selected provider.

=cut

sub provider($)
{   my ($self, $id) = @_;
    my $info = first { $_->{'voot.ProviderID'} eq $id } @{$self->config}
        or Log::fatal_err("cannot find VOOT provider $id in "
              . $self->config_filename);

    my $impl = $info->{'voot.ServerClass'} || 'Net::VOOT::Renater';
    Sympa::Plugin::Manager->load_plugin($impl)
        or Log::fatal_err("cannot load module $impl for provider $id in "
              . $self->config_filename);

    my $provider = eval { $impl->new(%$impl) };
    
}

=head3 provider_configs

=cut

sub provider_configs() { @{shift->config} }

=head1 FUNCTIONS

=head2 Web interface actions

=cut

sub do_opensocial {
    return 'select_voot_provider_request';
}

# VOOT request
sub do_voot(%)
{   my %args  = @_;
    my $param = $args{param};
    my $in    = $args{in};

    $param->{bypass} = 'extreme';
    
    my $voot_path = $in->{voot_path};
    my $voot      = __PACKAGE__->new;

my $name;
    my $provider  = $voot->provider($name)->call
      ( method    => $ENV{REQUEST_METHOD}
      , voot_path => $voot_path
      , url       => "$param->{base_url}$param->{path_cgi}/voot/$voot_path"
      , authorization_header => $ENV{HTTP_AUTHORIZATION}
      , request_parameters   => $in
      , robot     => $args{robot_id}
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
sub do_select_voot_provider_request(%)
{   my %args  = @_;
    my $param = $args{param};
    my $voot  = __PACKAGE__->new;

    my @providers;
    foreach my $info ($voot->provider_configs)
    {   my $id   = $info->{'voot.ProviderID'};
        my $name = $info->{'voot.ProviderName'} || $id;
        push @providers, +{id => $id, name => $name};
    }
    $param->{voot_providers} = [ sort {$a->{name} cmp $b->{name}} @providers ];
    return 1;
}

# Display groups list for user/VOOT_provider
sub do_select_voot_groups_request(%)
{   my %args = @_;
    my $voot = __PACKAGE__->new;

    my $in       = $args{in};
    my $param    = $args{param};
    
    my $prov_id  = $param->{voot_provider} = $in->{voot_provider};
    my $email    = $param->{user}{email};
    
    my $provider = $voot->provider($prov_id)->call
      ( user      => $email
      ) or return undef;

    my $consumer = $voot->getOAuthConsumer;
    $consumer->setWebEnv
      ( robot     => $args{robot_id}
      , here_path => "select_voot_groups_request/$param->{list}/$provider"
      , base_path => "$param->{base_url}.$param->{path_cgi}"
      ) unless $in->{oauth_ready_done};

    my $groups = $param->{voot_groups} = $voot->isMemberOf;
    unless(defined $groups) {
        my $url = $consumer->mustRedirect;
        return do_redirect($url) if defined $url;
    }
    
    return 1;
}

# VOOT groups choosen, generate config
sub do_select_voot_groups(%)
{   my %args     = @_;
    my $param    = $args{param};
    my $in       = $args{in};
    my $list     = $args{list};
    my $robot_id = $args{robot_id};

    my $provider = $param->{voot_provider} = $in->{voot_provider};
    my $email    = $param->{user}{email};

    my @groups;
    foreach my $k (keys %$in)
    {   $k =~ /^voot_groups\[([^\]]+)\]$/ or next;
        push @groups, $1 if $in->{$k}==1;
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

        wwslog(info => 'do_select_voot_groups: Cannot save config file');
        web_db_log({status => 'error', error_type => 'internal'});
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

__END__

=head1 DETAILS

=head2 Description of the VOOT file

By default, the VOOT configuration is found in the Site's etc directory,
with name 'voot.conf'.  This is a JSON file which contains an ARRAY of
provider descriptions.

The OAuth and OAuth2 standards which are used, are weak standards: they
are extremely flexible.  You may need to configure a lot yourself to get
it to work.  This means that you have to provider loads of details about
your VOOT server.

Fields:

   voot.ProviderID            your abbreviation
   voot.ProviderName          beautified name (defaults to ID)
   voot.ServerClass           implementation (defaults to Net::VOOT::Renater)

=cut
