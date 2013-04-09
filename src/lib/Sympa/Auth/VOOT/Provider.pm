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

Sympa::Auth::VOOT::Provider - VOOT provider object

=head1 DESCRIPTION

This class implements the server side of VOOT workflow.

=cut

package Sympa::Auth::VOOT::Provider;

use strict;

use JSON::XS;

use Sympa::Auth::OAuth::Provider;
use Sympa::List;
use Sympa::Log::Syslog;
use Sympa::Tools;

=head1 CLASS METHODS

=over

=item Sympa::Auth::VOOT::Provider->new(%parameters)

Creates a new L<Sympa::Auth::VOOT::Provider> object.

Parameters:

=over

=item C<voot_path> => VOOT path, as array

=item C<method> => http method

=item C<url> => request url

=item C<authorization_header> =>

=item C<request_parameters> =>

=item C<request_body> =>

=item C<robot> =>

=back

Return value:

A L<Sympa::Auth::VOOT::Provider> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '()');

 	my $provider = Sympa::Auth::OAuth::Provider->new(
		method               => $params{'method'},
		url                  => $params{'url'},
		authorization_header => $params{'authorization_header'},
		request_parameters   => $params{'request_parameters'},
		request_body         => $params{'request_body'},
		config               => $params{config}
	);
	return undef unless $provider;

	my $self = {
		oauth_provider => $provider,
		robot          => $params{'robot'},
		voot_path      => $params{'voot_path'}
	};

	bless $self, $class;

	return $self;
}

=back

=head1 INSTANCE METHODS

=over

=item $provider->get_oauth_provider()

Get the underlying OAuth provider.

=cut

sub get_oauth_provider {
	my ($self) = @_;

	return $self->{'oauth_provider'};
}

=item $provider->check_request()

Check if a request is valid.

    if(my $http_code = $provider->check_request()) {
            $server->error($http_code, $provider->get_oauth_provider()->{'util'}->errstr);
    }

Parameters:

None.

Return value:

The HTTP error code if the request is NOT valid, I<undef> otherwise.

=cut

sub check_request {
	my ($self, %params) = @_;

	my $r = $self->{'oauth_provider'}->check_request(checktoken => 1);
	return $r if($r);

	my $access = $self->{'oauth_provider'}->get_access(
		token => $self->{'oauth_provider'}{'params'}{'oauth_token'}
	);
	return 401 unless($access->{'user'});
	return 403 unless($access->{'accessgranted'});

	$self->{'user'} = $access->{'user'};

	return undef;
}

=item $provider->response()

Respond to a request (parse url, build json), assumes that request is valid

Parameters:

None.

Return value:

A string, or I<undef> if something went wrong.

=cut

sub response {
	my ($self, %params) = @_;

	my $r = {
		startIndex => 0,
		totalResults => 0,
		itemsPerPage => 3,
		entry => [],
	};

	if(defined($self->{'user'}) && $self->{'user'} ne '') {
		my @args = split('/', $self->{'voot_path'});;
		return undef if($#args < 1);
		return undef unless($args[1] eq '@me');
		return undef unless($args[0] eq 'groups' || $args[0] eq 'people');
		return undef if($args[0] eq 'people' && ($#args < 2 || $args[2] eq ''));

		$r->{'entry'} = ($args[0] eq 'groups') ? $self->get_groups() : $self->get_group_members(group => $args[2]);
		$r->{'totalResults'} = $#{$r->{'entry'}} + 1;
	}

	return encode_json($r);
}

=item $provider->get_groups()

Get user groups.

Parameters:

None.

Return value:

An hashref containing groups definitions, or I<undef> if something went wrong

=cut

sub get_groups {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $self->{'user'});

	my @entries = ();

	#foreach my $list (Sympa::List::get_which($self->{'user'}, $self->{'robot'}, 'owner')) {
	#	push(@entries, $self->_list_to_group($list, 'admin'));
	#}

	#foreach my $list (Sympa::List::get_which($self->{'user'}, $self->{'robot'}, 'editor')) {
	#	push(@entries, $self->_list_to_group($list, '???'));
	#}

	foreach my $list (Sympa::List::get_which($self->{'user'}, $self->{'robot'}, 'member')) {
		push(@entries, $self->_list_to_group($list, 'member'));
	}

	return \@entries;
}

sub _list_to_group {
	my ($self, $list, $role) = @_;

	return {
		id => $list->{'name'},
		title => $list->{'admin'}{'subject'},
		description => $list->get_info(),
		voot_membership_role => $role
	};
}

=item $provider->get_group_members(%parameters)

Get members of a group.

Parameters:

=over

=item C<group> => the group ID.

=back

Return value:

An hashref containing members definitions, or I<undef> if something went wrong.

=cut

sub get_group_members {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s)', $self->{'user'}, $params{'group'});

	my @entries = ();

	my $list = Sympa::List->new(
		name  => $params{'group'},
		robot => $self->{'robot'}
	);
	if(defined $list) {
		my $r = $list->check_list_authz('review', 'md5', {'sender' => $self->{'user'}});

		if(ref($r) ne 'HASH' || $r->{'action'} !~ /do_it/i) {
			$self->{'error'} = '403 Forbiden';
		} else {
			for(my $user = $list->get_first_list_member(); $user; $user = $list->get_next_list_member()) {
				push(@entries, $self->_subscriber_to_member($user, 'member'));
			}
		}
	}

	return \@entries;
}

sub _subscriber_to_member {
	my ($self, $user, $role) = @_;

	return {
		displayName => $user->{'gecos'},
		emails => [$user->{'email'}],
		voot_membership_role => $role
	};
}

=back

=head1 AUTHORS

=over

=item * Etienne Meleard <etienne.meleard AT renater.fr>

=back

=cut

1;
