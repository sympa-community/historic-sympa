package Sympa::OAuth2::Store;
use strict;
use warnings;

use Sympa::Plugin::Util qw/:functions/;

use Data::Dumper  ();

=head1 NAME 

Sympa::OAuth2::Store - OAuth v2 administration

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

    my $sth  = $self->db->prepared(<<'__LOAD_SESSION', $user, $prov_id);
SELECT *
  FROM oauth2_sessions
 WHERE user     = ?
   AND provider = ?
__LOAD_SESSION

    unless($sth)
    {   log(err => "Unable to load token data for $user at $prov_id");
        return undef;
    }
    
    my $record = $sth->fetchrow_hashref('NAME_lc')
        or return undef;

    eval $record->{session};
}

=head3 updateSession SESSION

=cut

sub updateSession($)
{   my ($self, $session) = @_;
    my $user   = $session->{user};
    my $provid = $session->{provider};
    my $dump   = Data::Dumper->new([$session],['Session'])->Indent(0);

    unless($self->db->do(<<'__UPDATE_SESSION', $dump, $user, $provid))
UPDATE oauth2_sessions
   SET session  = ?
 WHERE user     = ?
   AND provider = ?
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
    my $user   = $session->{user};
    my $provid = $session->{provider};
    my $dump   = Data::Dumper->new([$session],['Session'])->Indent(0);

    unless($self->db->do(<<'__INSERT_SESSION', $dump, $user, $provid))
INSERT oauth2_sessions
   SET session  = ?
     , user     = ?
     , provider = ?
__INSERT_SESSION
    {   log(err => "Unable to add new token record $user $provid");
        return undef;
    }

    1;
}

1;
