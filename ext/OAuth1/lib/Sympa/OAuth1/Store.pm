package Sympa::OAuth1::Store;
use strict;
use warnings;

use Sympa::Plugin::Util qw/:functions/;

=head1 NAME 

Sympa::OAuth1::Store - OAuth v1 administration

=head1 SYNOPSIS

=head1 DESCRIPTION 

=head1 METHODS

=head2 Constructors

=head3 class method: new OPTIONS

Create the object, returns C<undef> on failure.

Options:

=over 4

=item * I<db> =E<gt> Database object

=back 

=cut 

sub new(@) { my $class = shift; (bless {}, $class)->init({@_}) }

sub init($)
{   my ($self, $args) = @_;
    $self->{SOC_db} = $args->{db} or die;
    $self;
}


=head2 Accessors

=head3 method: db

=cut

sub db    { shift->{SOC_db} }


=head2 Sessions

=head3 loadSession USER, PROVIDER

=cut

sub loadSession($$)
{   my ($self, $user, $prov_id) = @_;

    my $sth  = $self->db->prepared(<<'__GET_TMP_TOKEN', $user, $prov_id);
SELECT tmp_token_oauthconsumer     AS tmp_token
     , tmp_secret_oauthconsumer    AS tmp_secret
     , access_token_oauthconsumer  AS access_token
     , access_secret_oauthconsumer AS access_secret
  FROM oauthconsumer_sessions_table
 WHERE user_oauthconsumer     = ?
   AND provider_oauthconsumer = ?
__GET_TMP_TOKEN

    unless($sth)
    {   log(err => "Unable to load token data for $user at $prov_id");
        return undef;
    }
    
    $sth->fetchrow_hashref('NAME_lc');
}

=head3 updateSession SESSION

=cut

sub updateSession($)
{   my ($self, $session) = @_;
    my $tmp    = $session->{tmp};
    my $access = $session->{access};
    my $user   = $session->{user};
    my $provid = $session->{provider};

    my @bind   = ( $tmp->token, $tmp->secret, $access->token, $access->secret
      , $user, $provid);

    unless($self->db->do(<<'__UPDATE_SESSION', @bind))
UPDATE oauthconsumer_sessions_table
   SET tmp_token_oauthconsumer     = ? 
     , tmp_secret_oauthconsumer    = ?
     , access_token_oauthconsumer  = ?
     , access_secret_oauthconsumer = ?
 WHERE user_oauthconsumer          = ?
   AND provider_oauthconsumer      = ?
__UPDATE_SESSION
    {   log(err => "Unable to update token record $user $provid");
        return undef;
    }

    1;
}

=head3 createSession SESSION

=cut

sub createSession($)
{   my ($self, $session) = @_;
    my $tmp    = $session->{tmp};
    my $user   = $session->{user};
    my $provid = $session->{provider};

    my @bind   = ($user, $provid, $tmp->token, $tmp->secret);

    unless($self->db->do(<<'__INSERT_SESSION', @bind))
INSERT INTO oauthconsumer_sessions_table
   SET user_oauthconsumer          = ?
     , provider_oauthconsumer      = ?
     , tmp_token_oauthconsumer     = ?
     , tmp_secret_oauthconsumer    = ?
     , access_token_oauthconsumer  = NULL
     , access_secret_oauthconsumer = NULL
__INSERT_SESSION
    {   log(err => "Unable to add new token record $user $provid");
        return undef;
    }

    1;
}

1;
