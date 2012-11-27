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

Sympa::VOOT::Provider - VOOT provider object

=head1 DESCRIPTION 

This class implements the server side of VOOT workflow.

=cut 

package Sympa::VOOT::Provider;

use strict;

use JSON::XS;

use Sympa::List;
use Sympa::Log;
use Sympa::OAuth::Provider;
use Sympa::Tools;

=head1 CLASS METHODS

=head2 Sympa::VOOT::Provider->new(%parameters)

Creates a new L<Sympa::VOOT::Provider> object.

=head3 Parameters 

=over 

=item * I<voot_path>: VOOT path, as array

=item * I<method>: http method

=item * I<url>: request url

=item * I<authorization_header>

=item * I<request_parameters>

=item * I<request_body>

=item * I<robot>

=back 

=head3 Return value

A L<Sympa::VOOT::Provider> object, or I<undef> if something went wrong.

=cut 

sub new {
	my $pkg = shift;
	my %param = @_;
	
	&Sympa::Log::do_log('debug2', '%s::new()', __PACKAGE__);
	
	my $provider = {
		oauth_provider => new Sympa::OAuth::Provider(
			method => $param{'method'},
			url => $param{'url'},
			authorization_header => $param{'authorization_header'},
			request_parameters => $param{'request_parameters'},
			request_body => $param{'request_body'}
		),
		robot => $param{'robot'},
		voot_path => $param{'voot_path'}
	};
	
 	return undef unless(defined($provider->{'oauth_provider'}));
 	
	return bless $provider, $pkg;
}

sub getOAuthProvider {
	my $self = shift;
	return $self->{'oauth_provider'};
}

=head1 INSTANCE METHODS

=head2 $provider->checkRequest()

Check if a request is valid.

    if(my $http_code = $provider->checkRequest()) {
            $server->error($http_code, $provider->getOAuthProvider()->{'util'}->errstr);
    }

=head3 Parameters 

None.

=head3 Return value

The HTTP error code if the request is NOT valid, I<undef> otherwise.

=cut 

sub checkRequest {
	my $self = shift;
	my %param = @_;
	
	my $r = $self->{'oauth_provider'}->checkRequest(checktoken => 1);
	return $r if($r);
	
	my $access = $self->{'oauth_provider'}->getAccess(
		token => $self->{'oauth_provider'}{'params'}{'oauth_token'}
	);
	return 401 unless($access->{'user'});
	return 403 unless($access->{'accessgranted'});
	
	$self->{'user'} = $access->{'user'};
	
	return undef;
}

=head2 $provider->response()

Respond to a request (parse url, build json), assumes that request is valid

=head3 Parameters 

None.

=head3 Return value

A string, or I<undef> if something went wrong.

=cut 

sub response {
	my $self = shift;
	my %param = @_;
	
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
		
		$r->{'entry'} = ($args[0] eq 'groups') ? $self->getGroups() : $self->getGroupMembers(group => $args[2]);
		$r->{'totalResults'} = $#{$r->{'entry'}} + 1;
	}
	
	return encode_json($r);
}

=head2 $provider->getGroups()

Get user groups.

=head3 Parameters 

None.

=head3 Return value

An hashref containing groups definitions, or I<undef> if something went wrong

=cut 

sub getGroups {
	my $self = shift;
	&Sympa::Log::do_log('debug2', '%s::getGroups(%s)', __PACKAGE__, $self->{'user'});
	
	my @entries = ();
	
	#foreach my $list (&Sympa::List::get_which($self->{'user'}, $self->{'robot'}, 'owner')) {
	#	push(@entries, $self->_list_to_group($list, 'admin'));
	#}
	
	#foreach my $list (&Sympa::List::get_which($self->{'user'}, $self->{'robot'}, 'editor')) {
	#	push(@entries, $self->_list_to_group($list, '???'));
	#}
	
	foreach my $list (&Sympa::List::get_which($self->{'user'}, $self->{'robot'}, 'member')) {
		push(@entries, $self->_list_to_group($list, 'member'));
	}
	
	return \@entries;
}

sub _list_to_group {
	my $self = shift;
	my $list = shift;
	my $role = shift;
	
	return {
		id => $list->{'name'},
		title => $list->{'admin'}{'subject'},
		description => $list->get_info(),
		voot_membership_role => $role
	};
}

=head2 $provider->getGroupMembers(%parameters)

Get members of a group.

=head3 Parameters 

=over 

=item * I<group>: the group ID.

=back 

=head3 Return value 

An hashref containing members definitions, or I<undef> if something went wrong.

=cut 

sub getGroupMembers {
	my $self = shift;
	my %param = @_;
	&Sympa::Log::do_log('debug2', '%s::getGroupMembers(%s, %s)', __PACKAGE__, $self->{'user'}, $param{'group'});
	
	my @entries = ();
	
	my $list = new Sympa::List($param{'group'}, $self->{'robot'});
	if(defined $list) {
		my $r = $list->check_list_authz('review', 'md5', {'sender' => $self->{'user'}});
		
		if(ref($r) ne 'HASH' || $r->{'action'} !~ /do_it/i) {
			$self->{'error'} = '403 Forbiden';
		}else{
			for(my $user = $list->get_first_list_member(); $user; $user = $list->get_next_list_member()) {
				push(@entries, $self->_subscriber_to_member($user, 'member'));
			}
		}
	}
	
	return \@entries;
}

sub _subscriber_to_member {
	my $self = shift;
	my $user = shift;
	my $role = shift;
	
	return {
		displayName => $user->{'gecos'},
		emails => [$user->{'email'}],
		voot_membership_role => $role
	};
}

## Packages must return true.
1;

=head1 AUTHORS 

=over 

=item * Etienne Meleard <etienne.meleard AT renater.fr> 

=back 

=cut 
