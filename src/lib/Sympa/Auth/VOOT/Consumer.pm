# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
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

Sympa::Auth::VOOT::Consumer - VOOT consumer object

=head1 DESCRIPTION

This class implements the client side of VOOT workflow.

=cut

package Sympa::Auth::VOOT::Consumer;

use strict;

use JSON::XS;

use Sympa::Auth::OAuth::Consumer;
use Sympa::Log::Syslog;
use Sympa::Tools;

=head1 CLASS METHODS

=over

=item Sympa::Auth::VOOT::Consumer->get_providers($config)

List providers.

Parameters:

=over

=item C<$config> => the VOOT configuration file

=back

Return value:

An hashref.

=cut

sub get_providers {
	my ($class, $file) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $file);

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

=item Sympa::Auth::VOOT::Consumer->new(%parameters)

Creates a new L<Sympa::Auth::VOOT::Consumer> object.

Parameters:

=over

=item C<user> => a user email

=item C<provider> => the VOOT provider key

=item C<config> => the VOOT configuration file

=back

Return value:

A L<Sympa::Auth::VOOT::Consumer> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	Sympa::Log::Syslog::do_log('debug2', '(%s, %s)', $params{'user'}, $params{'provider'});

	# Get oauth consumer and enpoints from provider_id
	my $config = _get_config_for($params{'provider'}, $params{'config'});
	return undef unless $config;

	my $self = {
		conf     => $config,
		user     => $params{'user'},
		provider => $params{'provider'},
		oauth_consumer => Sympa::Auth::OAuth::Consumer->new(
			user               => $params{'user'},
			provider           => 'voot:'.$params{'provider'},
			consumer_key       => $config->{'oauth.ConsumerKey'},
			consumer_secret    => $config->{'oauth.ConsumerSecret'},
			request_token_path => $config->{'oauth.RequestURL'},
			access_token_path  => $config->{'oauth.AccessURL'},
			authorize_path     => $config->{'oauth.AuthorizationURL'},
		)
	};

	bless $self, $class;

	return $self;
}

=back

=head1 INSTANCE METHODS

=over

=item $consumer->get_oauth_consumer()

=cut

sub get_oauth_consumer {
	my ($self) = @_;

	return $self->{'oauth_consumer'};
}

=item $consumer->is_member_of()

Get user groups.

Parameters:

None.

Return value:

An hashref containing groups definitions, or I<undef> if something went wrong.

=cut

sub is_member_of {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s)', $self->{'user'}, $self->{'provider'});

	my $data = $self->{'oauth_consumer'}->fetch_ressource(url => $self->{'conf'}{'voot.BaseURL'}.'/groups/@me');
	return undef unless(defined $data);

	return _get_groups(decode_json($data));
}

=item $consumer->check()

An alias for $consumer->is_member_of();

=cut

sub check {
	my ($self) = @_;

	return $self->is_member_of();
}

=item $consumer->get_group_members(%parameters)

Get members of a group.

Parameters:

=over

=item C<group> => the group ID

=back

Return value:

An hashref containing members definitions, or I<undef> if something went wrong.

=cut

sub get_group_members {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s)', $self->{'user'}, $self->{'provider'}, $params{'group'});

	my $data = $self->{'oauth_consumer'}->fetch_ressource(url => $self->{'conf'}{'voot.BaseURL'}.'/people/@me/'.$params{'group'});
	return undef unless(defined $data);

	return _get_members(decode_json($data));
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
			} else {
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
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $provider);

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

=back

=head1 AUTHORS

=over

=item * Etienne Meleard <etienne.meleard AT renater.fr>

=back

=cut

1;
