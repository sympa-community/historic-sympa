# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
# $Id$

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

Sympa::VOOT::Consumer - VOOT consumer object

=head1 DESCRIPTION

This class implements the client side of VOOT workflow.

=cut

package Sympa::VOOT::Consumer;

use strict;

use JSON::XS;

use Sympa::Log;
use Sympa::OAuth::Consumer;
use Sympa::Tools;

=head1 CLASS METHODS

=head2 Sympa::VOOT::Consumer->getProviders($config)

List providers.

=head3 Parameters

=over

=item * I<$config>: the VOOT configuration file

=back

=head3 Return value

An hashref.

=cut

sub getProviders {
	my ($class, $file) = @_;
	&Sympa::Log::do_log('debug2', '(%s)', $file);

	my $list = {};

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

=head2 Sympa::VOOT::Consumer->new(%parameters)

Creates a new L<Sympa::VOOT::Consumer> object.

=head3 Parameters

=over

=item * I<user>: a user email

=item * I<provider>: the VOOT provider key

=item * I<config>: the VOOT configuration file

=back

=head3 Return value

A L<Sympa::VOOT::Consumer> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %param) = @_;

	my $consumer;
	&Sympa::Log::do_log('debug2', '(%s, %s)', $param{'user'}, $param{'provider'});

	# Get oauth consumer and enpoints from provider_id
	$consumer->{'conf'} = &_get_config_for($param{'provider'}, $param{'config'});
	return undef unless(defined $consumer->{'conf'});

	$consumer->{'user'} = $param{'user'};
	$consumer->{'provider'} = $param{'provider'};

	$consumer->{'oauth_consumer'} = Sympa::OAuth::Consumer->new(
		user => $param{'user'},
		provider => 'voot:'.$param{'provider'},
		consumer_key => $consumer->{'conf'}{'oauth.ConsumerKey'},
		consumer_secret => $consumer->{'conf'}{'oauth.ConsumerSecret'},
		request_token_path => $consumer->{'conf'}{'oauth.RequestURL'},
        access_token_path  => $consumer->{'conf'}{'oauth.AccessURL'},
        authorize_path => $consumer->{'conf'}{'oauth.AuthorizationURL'},
        here_path => $consumer->{'here_path'}
	);

	return bless $consumer, $class;
}

=head1 INSTANCE METHODS

=head2 $consumer->getOAuthConsumer()

=cut

sub getOAuthConsumer {
	my ($self) = @_;

	return $self->{'oauth_consumer'};
}

=head2 $consumer->isMemberOf()

Get user groups.

=head3 Parameters

None.

=head3 Return value

An hashref containing groups definitions, or I<undef> if something went wrong.

=cut

sub isMemberOf {
	my ($self) = @_;
	&Sympa::Log::do_log('debug2', '(%s, %s)', $self->{'user'}, $self->{'provider'});

	my $data = $self->{'oauth_consumer'}->fetchRessource(url => $self->{'conf'}{'voot.BaseURL'}.'/groups/@me');
	return undef unless(defined $data);

	return &_get_groups(decode_json($data));
}

=head2 $consumer->check()

An alias for $consumer->isMemberOf();

=cut

sub check {
	my ($self) = @_;

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
	my ($self, %param) = @_;
	&Sympa::Log::do_log('debug2', '(%s, %s, %s)', $self->{'user'}, $self->{'provider'}, $param{'group'});

	my $data = $self->{'oauth_consumer'}->fetchRessource(url => $self->{'conf'}{'voot.BaseURL'}.'/people/@me/'.$param{'group'});
	return undef unless(defined $data);

	return &_get_members(decode_json($data));
}

# _get_groups($response)
# Fetch groups from response items.
# Return an hashref

sub _get_groups {
	my ($data) = @_;

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
	my ($data) = @_;

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
	my ($provider, $file) = @_;
	&Sympa::Log::do_log('debug2', '(%s)', $provider);

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

=head1 AUTHORS

=over

=item * Etienne Meleard <etienne.meleard AT renater.fr>

=back

=cut

1;
