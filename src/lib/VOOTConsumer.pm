=head1 NAME 

VOOTConsumer.pm - VOOT consumer facilities for internal use in Sympa

=head1 DESCRIPTION 

This package provides abstraction for the VOOT workflow (client side),
handles OAuth workflow if nedeed.

=cut 

package VOOTConsumer;

use strict;

use OAuthConsumer;

use JSON::XS;
use Data::Dumper;

use tools;
use Conf;
use Log;

=pod 

=head1 METHODS

=head2 sub new

Creates a new VOOTConsumer object.

=head3 Arguments 

=over 

=item * I<$user>, a user email

=item * I<$provider>, the VOOT provider key

=back 

=head3 Return 

=over 

=item * I<a VOOTConsumer object>, if created

=item * I<undef>, if something went wrong

=back 

=cut 

## Creates a new object
sub new {
	my $pkg   = shift;
	my %param = @_;
    (bless {}, $pkg)->init(\%param);
}

sub init($)
{   my ($self, $args) = @_;
	
	my $user     = $self->{user}     = $args->{user};
	my $provider = $self->{provider} = $args->{provider};
	Log::do_log('debug2', 'VOOTConsumer::new(%s, %s)', $user, $provider);

	my $conf     = $self->{conf}     = _get_config_for($provider);
	$conf or return undef;

	$self->{oauth} = OAuthConsumer->new(
		user               => $user,
		provider           => "voot:$provider",
		consumer_key       => $conf->{ConsumerKey},
		consumer_secret    => $conf->{ConsumerSecret},
		request_token_path => $conf->{RequestURL},
        access_token_path  => $conf->{AccessURL},
        authorize_path     => $conf->{AuthorizationURL},
	);
    $self;
}

sub getOAuthConsumer { shift->{oauth_consumer} }

=pod 

=head2 sub isMemberOf

Get user groups

=head3 Arguments 

=over 

=item * None

=back 

=head3 Return 

=over 

=item * I<a reference to a hash> contains groups definitions

=item * I<undef>, if something went wrong

=back 

=head3 Calls 

=over 

=item * None

=back 

=cut 

## Get groups for user
sub isMemberOf {
	my $self = shift;
	&Log::do_log('debug2', 'VOOTConsumer::isMemberOf(%s, %s)', $self->{'user'}, $self->{'provider'});
	
	my $data = $self->{'oauth_consumer'}->fetchRessource(url => $self->{'conf'}{'voot.BaseURL'}.'/groups/@me');
	return undef unless(defined $data);
	
	return &_get_groups(decode_json($data));
}
sub check {
	my $self = shift;
	return $self->isMemberOf();
}

=pod 

=head2 sub getGroupMembers

Get members of a group.

=head3 Arguments 

=over 

=item * I<$self>, the OAuthConsumer to use.

=item * I<$group>, the group ID.

=back 

=head3 Return 

=over 

=item * I<a reference to a hash> contains members definitions

=item * I<undef>, if something went wrong

=back 

=head3 Calls 

=over 

=item * None

=back 

=cut 

## Get group members
sub getGroupMembers {
	my $self = shift;
	my %param = @_;
	&Log::do_log('debug2', 'VOOTConsumer::getGroupMembers(%s, %s, %s)', $self->{'user'}, $self->{'provider'}, $param{'group'});
	
	my $data = $self->{'oauth_consumer'}->fetchRessource(url => $self->{'conf'}{'voot.BaseURL'}.'/people/@me/'.$param{'group'});
	return undef unless(defined $data);
	
	return &_get_members(decode_json($data));
}

=pod 

=head2 sub _get_groups

Fetch groups from response items.

=head3 Arguments 

=over 

=item * I<$data>, the parsed request response.

=back 

=head3 Return 

=over 

=item * I<a reference to a hash>, if everything's alright

=back 

=head3 Calls 

=over 

=item * None

=back 

=cut 

## Fetch groups from response items
sub _get_groups {
	my $data = shift;
	my $groups = {};
	
	foreach my $grp (@{$data->{'entry'}}) {
		$groups->{$grp->{'id'}} = {
			name => $grp->{'name'} || $grp->{'id'},
			description => (defined $grp->{'description'}) ? $grp->{'description'} : '',
			voot_membership_role => (defined $grp->{'voot_membership_role'}) ? $grp->{'voot_membership_role'} : undef
		};
	}
	
	return $groups;
}

=pod 

=head2 sub _get_members

Fetch members from response items.

=head3 Arguments 

=over 

=item * I<$data>, the parsed request response.

=back 

=head3 Return 

=over 

=item * I<a reference to an array>, if everything's alright

=back 

=head3 Calls 

=over 

=item * None

=back 

=cut 

## Fetch members from response items
sub _get_members {
	my $data = shift;
	my $members = [];
	my $i;
	
	foreach my $mmb (@{$data->{'entry'}}) {
		next unless(defined $mmb->{'emails'}); # Skip members without email data that are useless for Sympa
		my $member = {
			displayName => $mmb->{'displayName'},
			emails => [],
			voot_membership_role => (defined $mmb->{'voot_membership_role'}) ? $mmb->{'voot_membership_role'} : undef
		};
		foreach my $email (@{$mmb->{'emails'}}) {
			if(ref($email) eq 'HASH') {
				push(@{$member->{'emails'}}, $email->{'value'});
			}else{
				push(@{$member->{'emails'}}, $email);
			}
		}
		push(@$members, $member);
	}
	
	return $members;
}

=pod 

=head2 sub _get_config_for

Get provider information.

=head3 Arguments 

=over 

=item * I<$provider>, the provider to get info about.

=back 

=head3 Return 

=over 

=item * I<a reference to a hash>, if everything's alright

=back 

=head3 Calls 

=over 

=item * None

=back 

=cut 

## Get provider information
sub _get_config_for {
	my $provider = shift;
	&Log::do_log('debug2', 'VOOTConsumer::_get_config_for(%s)', $provider);
	
	my $file = Site->etc.'/voot.conf';
	return undef unless (-f $file);
	
	open(my $fh, '<', $file) or return undef;
	my @ctn = <$fh>;
	chomp @ctn;
	close $fh;
	
	my $conf = decode_json(join('', @ctn)); # Returns array ref
	foreach my $item (@$conf) {
		next unless($item->{'voot.ProviderID'} eq $provider);
		return $item;
	}
	
	return undef;
}

1;

=pod 

=head1 AUTHORS 

=over 

=item * Etienne Meleard <etienne.meleard AT renater.fr> 

=back 

=cut 
