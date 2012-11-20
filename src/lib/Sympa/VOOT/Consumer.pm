#<!-- RCS Identication ; $Revision: 7207 $ ; $Date: 2011-09-05 15:33:26 +0200 (lun 05 sep 2011) $ --> 

#
# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
# Copyright (c) 1997,1998, 1999 Institut Pasteur & Christophe Wolfhugel
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME 

Sympa::VOOT::Consumer - VOOT consumer facilities for Sympa

=head1 DESCRIPTION 

This package provides abstraction for the VOOT workflow (client side), handles
OAuth workflow if nedeed.

=cut 

package Sympa::VOOT::Consumer;

use strict;

use JSON::XS;

use Sympa::Conf;
use Sympa::Log;
use Sympa::OAuth::Consumer;
use Sympa::Tools;

=head1 CLASS METHODS

=head2 Sympa::VOOT::Consumer->new(%parameters)

Creates a new L<Sympa::VOOT::Consumer> object.

=head3 Parameters

=over 

=item * I<user>: a user email

=item * I<provider>: the VOOT provider key

=back 

=head3 Return value

A L<Sympa::VOOT::Consumer> object, or I<undef> if something went wrong.

=cut 

sub new {
	my $pkg = shift;
	my %param = @_;
	
	my $consumer;
	&Sympa::Log::do_log('debug2', '%s::new(%s, %s)', __PACKAGE__, $param{'user'}, $param{'provider'});
	
	# Get oauth consumer and enpoints from provider_id
	$consumer->{'conf'} = &_get_config_for($param{'provider'});
	return undef unless(defined $consumer->{'conf'});
	
	$consumer->{'user'} = $param{'user'};
	$consumer->{'provider'} = $param{'provider'};
	
	$consumer->{'oauth_consumer'} = new Sympa::OAuth::Consumer(
		user => $param{'user'},
		provider => 'voot:'.$param{'provider'},
		consumer_key => $consumer->{'conf'}{'oauth.ConsumerKey'},
		consumer_secret => $consumer->{'conf'}{'oauth.ConsumerSecret'},
		request_token_path => $consumer->{'conf'}{'oauth.RequestURL'},
        access_token_path  => $consumer->{'conf'}{'oauth.AccessURL'},
        authorize_path => $consumer->{'conf'}{'oauth.AuthorizationURL'},
        here_path => $consumer->{'here_path'}
	);
	
	return bless $consumer, $pkg;
}

sub getOAuthConsumer {
	my $self = shift;
	return $self->{'oauth_consumer'};
}

=head1 INSTANCE METHODS

=head2 $consumer->isMemberOf()

Get user groups.

=head3 Parameters

None.

=head3 Return value

An hashref containing groups definitions, or I<undef> if something went wrong.

=cut 

sub isMemberOf {
	my $self = shift;
	&Sympa::Log::do_log('debug2', '%s::isMemberOf(%s, %s)', __PACKAGE__, $self->{'user'}, $self->{'provider'});
	
	my $data = $self->{'oauth_consumer'}->fetchRessource(url => $self->{'conf'}{'voot.BaseURL'}.'/groups/@me');
	return undef unless(defined $data);
	
	return &_get_groups(decode_json($data));
}
sub check {
	my $self = shift;
	return $self->isMemberOf();
}

=head2 $consumer->getGroupMembers(%parameters)

Get members of a group.

=head3 Parameters

=over 

=item * I<group>: the group ID

=back 

=head3 Return value

An hashref containing members definitions, or I<undef> if something went wrong.

=cut 

sub getGroupMembers {
	my $self = shift;
	my %param = @_;
	&Sympa::Log::do_log('debug2', '%s::getGroupMembers(%s, %s, %s)', __PACKAGE__, $self->{'user'}, $self->{'provider'}, $param{'group'});
	
	my $data = $self->{'oauth_consumer'}->fetchRessource(url => $self->{'conf'}{'voot.BaseURL'}.'/people/@me/'.$param{'group'});
	return undef unless(defined $data);
	
	return &_get_members(decode_json($data));
}

# _get_groups($response)
# Fetch groups from response items.
# Return an hashref

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

# _get_members($response)
# Fetch members from response items.
# Return an hashref

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

# _get_config_for($provider)
# Get provider information.
# Return an hashref

sub _get_config_for {
	my $provider = shift;
	&Sympa::Log::do_log('debug2', '%s::_get_config_for(%s)', __PACKAGE__, $provider);
	
	my $file = $Sympa::Conf::Conf{'etc'}.'/voot.conf';
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

=head1 FUNCTIONS

=head2 getProviders()

List providers.

=head3 Parameters

None.

=head3 Return value

An hashref.

=cut 

sub getProviders {
	&Sympa::Log::do_log('debug2', '%s::getProviders()', __PACKAGE__);
	
	my $list = {};
	
	my $file = $Sympa::Conf::Conf{'etc'}.'/voot.conf';
	return $list unless (-f $file);
	
	open(my $fh, '<', $file) or return $list;
	my @ctn = <$fh>;
	chomp @ctn;
	close $fh;
	
	my $conf = decode_json(join('', @ctn)); # Returns array ref
	foreach my $item (@$conf) {
		$list->{$item->{'voot.ProviderID'}} = $item->{'voot.ProviderID'};
	}
	
	return $list;
}

## Packages must return true.
1;

=head1 AUTHORS 

=over 

=item * Etienne Meleard <etienne.meleard AT renater.fr> 

=back 

=cut 
