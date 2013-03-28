package Sympa::VOOT::Consumer;

use warnings;
use strict;

use Sympa::Plugin::Util qw/:functions/;

=head1 NAME

Sympa::VOOT::Consumer - represent one VOOT source in Sympa

=head1 SYNOPSIS

  my $voot = Sympa::VOOT->new;

  my $consumer = $voot->consumer
    ( provider => \%info
    , user     => \%user
    , auth     => \%config
    );
  # $consumer is a Sympa::VOOT::Consumer

=head1 DESCRIPTION

This object combines three aspects:

=over 4

=item one voot session for a user, implemented by L<Net::VOOT>

=item a session store, implemented by L<Sympa::OAuth1::Consumer> and L<Sympa::OAuth2::Consumer>

=item the sympa specific logic, in here

=back

=head1 METHODS

=head2 Constructors

=head3 class method: new OPTIONS

Options:

=over 4

=item * I<provider> =E<gt> INFO

=item * I<user> =E<gt> HASH

=item * I<auth> =E<gt> HASH, configuration

=cut

sub new(%) { my ($class, %args) = @_; (bless {}, $class)->init(\%args) }

sub init($)
{   my ($self, $args) = @_;
    my $provider = $self->{SVP_provider} = $args->{provider};

    my $server = $provider->{server};
    eval "require $server"
        or fatal "cannot load voot server class $server: $@";

    my $voot = $self->{SVP_voot} = $server->new
      ( provider     => $provider->{id}
      , auth         => $args->{auth}
      );

    my $auth_type  = $voot->authType;
    my $store_type = "Sympa::${auth_type}::Store";
    eval "require $store_type"
        or fatal "cannot load store class $store_type: $@";

    $self->{SVP_store} = $store_type->new(db => $args->{db} || default_db) ;
    $self->{SVP_user}  = $args->{user};

    $self;
}


=head2 Accessors

=head3 method: provider

=head3 method: voot

=head3 method: session

=head3 method: store

=head3 method: user

=cut

sub provider(){shift->{SVP_provider}}
sub voot()    {shift->{SVP_voot}}
sub session() {shift->{SVP_session}}
sub store()   {shift->{SVP_store}}
sub user()    {shift->{SVP_user}}


=head2 Action

=head3 get URL, PARAMS

Returns the L<HTTP::Response> on success.

=cut

sub get($$)
{   my ($self, $url, $params) = @_;
    my $resp = $self->voot->get($self->session, $url, $params);
    $resp->is_success ? $resp : undef;
}


=head3 startAuth OPTIONS

=over 4

=item * I<callback> =E<gt> URL

=back

=cut

sub startAuth(%)
{   my ($self, %args) = @_;
    trace_call($self->user->{email}, $self->provider->{id}, %args);

    my $voot    = $self->voot;
    my $session = eval { $voot->newSession
      ( user     => $self->user->{email}
      , provider => $self->provider->{id}
      , callback => $args{callback}
      ) };

    unless($session)
    {   log(err => $@);
        return undef;
    }

    $self->store->createSession($session);

    $voot->getAuthorizationStarter;
}

=method hasAccess

Returns true when the consumer has access to the VOOT resource.

=cut

sub hasAccess() { shift->voot->hasAccess }

1;
