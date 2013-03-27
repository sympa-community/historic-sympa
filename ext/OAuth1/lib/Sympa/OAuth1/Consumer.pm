package Sympa::OAuth1::Consumer;
use strict;
use warnings;

#use Sympa::Plugin::Util qw/:functions/;

=head1 NAME 

Sympa::OAuth1::Consumer - OAuth v1 consumer

=head1 SYNOPSIS

=head1 DESCRIPTION 

=head1 METHODS

=head2 Constructors

=head3 class method: new OPTIONS

Create the object, returns C<undef> on failure.

=cut 

sub new(@) { my $class = shift; (bless {}, $class)->init({@_}) }

sub init($)
{   my ($self, $args) = @_;
    $self;
}


=head2 Accessors

my $data    = $auth->loadSession($user, $provider);
my $session = $voot->restoreSession($user, $provider);


=head3 method: mustRedirect

Returns the URL to redirect to, if we need to redirect for authorization.

=head3 method: session

=head3 method: webenv

=head3 method: set_webenv OPTIONS

=cut

sub mustRedirect { shift->{redirect_url} }
sub session      { shift->{SOC_session}  }
sub webenv       { shift->{SOC_webenv}   }

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
       , $web->{robot_id}, $here_path, 'mail');

    my $callback  = "$web->{base_path}/oauth_ready/$provider/$ticket";
 
    my $tmp = $handler->get_request_token(callback_url => $callback);
    unless($tmp)
    {   log(err => "Unable to get tmp token for $user $provider: ".$handler->errstr);
        return undef;
    }

    my $session  = $self->session;
    if($session->{tmp})
    {   $session->{tmp} = $tmp;
        $store->update_session($session)
    }
    else
    {   $session->{tmp} = $tmp;
        $store->create_session($session)
    }
    
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
    $oauth->updateSession($session)
    $access;
}

=head1 AUTHORS 

=over 4

=item * Etienne Meleard <etienne.meleard AT renater.fr> 

=item * Mark Overmeer <mark AT overmeer.net >

=back 

=cut 

1;
