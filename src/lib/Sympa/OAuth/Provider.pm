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

Sympa::OAuth::Provider - OAuth provider object

=head1 DESCRIPTION

This class implements the server side of the OAuth workflow.

It handles requests for temporary/access tokens and database storage.

=cut

package Sympa::OAuth::Provider;

use strict;

use OAuth::Lite::ServerUtil;
use URI::Escape;

use Sympa::Log;
use Sympa::SDM;
use Sympa::Tools;

=head1 CLASS METHODS

=head2 Sympa::OAuth::Provider->new(%parameters)

Creates a new L<Sympa::OAuth::Provider> object.

=head3 Parameters

=over

=item * I<method>: http method

=item * I<url>: request url

=item * I<authorization_header>

=item * I<request_parameters>

=item * I<request_body>

=item * I<config>

=back

=head3 Return value

A L<Sympa::OAuth::Provider> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;
	Sympa::Log::do_log('debug2', '(%s)', $params{'consumer_key'});

	my $p = _findParameters(
		authorization_header => $params{'authorization_header'},
		request_parameters => $params{'request_parameters'},
		request_body => $params{'request_body'}
	);
	return undef unless(defined($p));
	return undef unless(defined($p->{'oauth_consumer_key'}));

	my $c = _getConsumerConfigFor($p->{'oauth_consumer_key'}, $params{config});
	return undef unless(defined($c));
	return undef unless(defined($c->{'enabled'}));
	return undef unless($c->{'enabled'} eq '1');

	my $self = {
		method          => $params{'method'},
		url             => $params{'url'},
		params          => $p,
		consumer_key    => $p->{'oauth_consumer_key'},
		consumer_secret => $c->{'secret'},
		constants       => {
			old_request_timeout => 600, # Max age for requests timestamps
			nonce_timeout => 3 * 30 * 24 * 3600, # Time the nonce tags are kept
			temporary_timeout => 3600, # Time left to use the temporary token
			verifier_timeout => 300, # Time left to request access once the verifier has been set
			access_timeout => 3 * 30 * 24 * 3600 # Access timeout
		},
	};

	my $util = OAuth::Lite::ServerUtil->new();
	$util->support_signature_method('HMAC-SHA1');
	$util->allow_extra_params(qw/oauth_callback oauth_verifier/);
	$self->{util} = $util;

	unless(Sympa::SDM::do_query(
		'DELETE FROM oauthprovider_sessions_table WHERE isaccess_oauthprovider IS NULL AND lasttime_oauthprovider<%d',
		time - $self->{'constants'}{'temporary_timeout'}
	)) {
		Sympa::Log::do_log('err', 'Unable to delete old temporary tokens in database');
		return undef;
	}

	bless $self, $class;
	return $self;
}

=head1 FUNCTIONS

=head2 consumerFromToken($token)

=cut

sub consumerFromToken {
	my ($token) = @_;

	my $sth;
	unless($sth = Sympa::SDM::do_prepared_query('SELECT consumer_oauthprovider AS consumer FROM oauthprovider_sessions_table WHERE token_oauthprovider=?', $token)) {
		Sympa::Log::do_log('err','Unable to load token data %s', $token);
		return undef;
	}

	my $data = $sth->fetchrow_hashref('NAME_lc');
	return undef unless($data);
	return $data->{'consumer'};
}

# _findParameters(%parameters)
# Seek various request aspects for parameters
# Parameters:
# - authorization_header
# - request_parameters
# - request_body
# Returns an hashref, or undef if something went wrong

sub _findParameters {
	my (%params) = @_;

	my $p = {};
	if(defined($params{'authorization_header'}) && $params{'authorization_header'} =~ /^OAuth /) {
		foreach my $b (split(/,\s*/, $params{'authorization_header'})) {
			next unless($b =~ /^(OAuth\s)?\s*(x?oauth_[^=]+)="([^"]*)"\s*$/);
			$p->{$2} = uri_unescape($3);
		}
	}elsif(defined($params{'request_body'})) {
		foreach my $k (keys(%{$params{'request_body'}})) {
			next unless($k =~ /^x?oauth_/);
			$p->{$k} = uri_unescape($params{'request_body'}{$k});
		}
	}elsif(defined($params{'request_parameters'})) {
		foreach my $k (keys(%{$params{'request_parameters'}})) {
			next unless($k =~ /^x?oauth_/);
			$p->{$k} = uri_unescape($params{'request_parameters'}{$k});
		}
	}else{
		return undef;
	}

	return $p;
}

=head1 INSTANCE METHODS

=head2 $provider->checkRequest(%parameters)

Check if a request is valid.

    if(my $http_code = $provider->checkRequest()) {
	$server->error($http_code, $provider->{'util'}->errstr);
    }

=head3 Parameters

=over

=item * I<checktoken>: boolean

=back

=head3 Return value

The HTTP error code if the request is NOT valid, I<undef> otherwise.

=cut

sub checkRequest {
	my ($self, %params) = @_;
	Sympa::Log::do_log('debug2', '(%s)', $params{'url'});

	my $checktoken = defined($params{'checktoken'}) ? $params{'checktoken'} : undef;
	unless($self->{'util'}->validate_params($self->{'params'}, $checktoken)) {
		return 400;
	}

	my $nonce = $self->{'params'}{'oauth_nonce'};
	my $token = $self->{'params'}{'oauth_token'};
	my $timestamp = $self->{'params'}{'oauth_timestamp'};

	return 401 unless($timestamp > time - $self->{'constants'}{'old_request_timeout'});

	unless(Sympa::SDM::do_query('DELETE FROM oauthprovider_nonces_table WHERE time_oauthprovider<%d', time - $self->{'constants'}{'nonce_timeout'})) {
		Sympa::Log::do_log('err', 'Unable to clean nonce store in database');
		return 401;
	}

	if($checktoken) {
		my $sth;
		unless($sth = Sympa::SDM::do_prepared_query(
			'SELECT id_oauthprovider AS id FROM oauthprovider_sessions_table WHERE consumer_oauthprovider=? AND token_oauthprovider=?',
			$self->{'consumer_key'},
			$token
		)) {
			Sympa::Log::do_log('err','Unable to get token %s %s', $self->{'consumer_key'}, $token);
			return 401;
		}

		if(my $data = $sth->fetchrow_hashref('NAME_lc')) {
			my $id = $data->{'id'};

			unless($sth = Sympa::SDM::do_prepared_query(
				'SELECT nonce_oauthprovider AS nonce FROM oauthprovider_nonces_table WHERE id_oauthprovider=? AND nonce_oauthprovider=?',
				$id,
				$nonce
			)) {
				Sympa::Log::do_log('err','Unable to check nonce %d %s', $id, $nonce);
				return 401;
			}

			return 401 if($sth->fetchrow_hashref('NAME_lc')); # Already used nonce

			unless(Sympa::SDM::do_query(
				'INSERT INTO oauthprovider_nonces_table(id_oauthprovider, nonce_oauthprovider, time_oauthprovider) VALUES (%d, %s, %d)',
				$id,
				Sympa::SDM::quote($nonce),
				time
			)) {
				Sympa::Log::do_log('err', 'Unable to add nonce record %d %s in database', $id, $nonce);
				return 401;
			}
		}
	}

	my $secret = '';
	if($checktoken) {
		my $sth;
		unless($sth = Sympa::SDM::do_prepared_query('SELECT secret_oauthprovider AS secret FROM oauthprovider_sessions_table WHERE token_oauthprovider=?', $token)) {
			Sympa::Log::do_log('err','Unable to load token data %s', $token);
			return undef;
		}

		my $data = $sth->fetchrow_hashref('NAME_lc');
		return 401 unless($data);
		$secret = $data->{'secret'};
	}

	$self->{'util'}->verify_signature(
		method          => $self->{'method'},
		params          => $self->{'params'},
		url             => $self->{'url'},
		consumer_secret => $self->{'consumer_secret'},
		token_secret => $secret
	) or return 401;

	return undef;
}

=head2 $provider->generateTemporary(%parameters)

Create a temporary token.

=head3 Parameters

=over

=item * I<authorize>: the authorization url

=back

=head3 Return value

The response body, as a string.

=cut

sub generateTemporary {
	my ($self, %params) = @_;
	Sympa::Log::do_log('debug2', '(%s)', $self->{'consumer_key'});

	my $token = _generateRandomString(32); # 9x10^62 entropy ...
	my $secret = _generateRandomString(32); # may be sha1-ed or such ...

	unless(Sympa::SDM::do_query(
		'INSERT INTO oauthprovider_sessions_table(token_oauthprovider, secret_oauthprovider, isaccess_oauthprovider, accessgranted_oauthprovider, consumer_oauthprovider, user_oauthprovider, firsttime_oauthprovider, lasttime_oauthprovider, verifier_oauthprovider, callback_oauthprovider) VALUES (%s, %s, NULL, NULL, %s, NULL, %d, %d, NULL, %s)',
		Sympa::SDM::quote($token),
		Sympa::SDM::quote($secret),
		Sympa::SDM::quote($self->{'consumer_key'}),
		time,
		time,
		Sympa::SDM::quote($self->{'params'}{'oauth_callback'})
	)) {
		Sympa::Log::do_log('err', 'Unable to add new token record %s %s in database', $token, $self->{'consumer_key'});
		return undef;
	}

	my $r = 'oauth_token='.uri_escape($token);
	$r .= '&oauth_token_secret='.uri_escape($secret);
	$r .= '&oauth_expires_in='.$self->{'constants'}{'temporary_timeout'};
	$r .= '&xoauth_request_auth_url='.$params{'authorize'} if(defined($params{'authorize'}));
	$r .= '&oauth_callback_confirmed=true';

	return $r;
}

=head2 $provider->getTemporary(%parameters)

Retreive a temporary token from database.

=head3 Parameters

=over

=item * I<token>: the token key

=item * I<timeout_type>: the timeout key, temporary or verifier

=back

=head3 Return value

An hashref, or I<undef> if the token does not exist or is not valid anymore.

=cut

sub getTemporary {
	my ($self, %params) = @_;
	Sympa::Log::do_log('debug2', '(%s)', $params{'token'});

	my $sth;
	unless($sth = Sympa::SDM::do_prepared_query(
		'SELECT id_oauthprovider AS id, token_oauthprovider AS token, secret_oauthprovider AS secret, firsttime_oauthprovider AS firsttime, lasttime_oauthprovider AS lasttime, callback_oauthprovider AS callback, verifier_oauthprovider AS verifier FROM oauthprovider_sessions_table WHERE isaccess_oauthprovider IS NULL AND consumer_oauthprovider=? AND token_oauthprovider=?', $self->{'consumer_key'}, $params{'token'})) {
		Sympa::Log::do_log('err','Unable to load token data %s %s', $self->{'consumer_key'}, $params{'token'});
		return undef;
	}

	my $data = $sth->fetchrow_hashref('NAME_lc');
	return undef unless($data);

	my $timeout = $self->{'constants'}{(defined($params{'timeout_type'}) ? $params{'timeout_type'} : 'temporary').'_timeout'};
	return undef unless($data->{'lasttime'} + $timeout >= time);

	return $data;
}

=head2 $provider->generateVerifier(%parameters)

Create the verifier for a temporary token.

=head3 Parameters

=over

=item * I<token>: the token

=item * I<user>: the user

=back

=head3 Return value

A redirect URL, as a string, or I<undef> if the token does not exist or is not
valid anymore.

=cut

sub generateVerifier {
	my ($self, %params) = @_;
	Sympa::Log::do_log('debug2', '(%s, %s, %s, %s)', $params{'token'}, $params{'user'}, $params{'granted'}, $self->{'consumer_key'});

	return undef unless(my $tmp = $self->getTemporary(token => $params{'token'}));

	my $verifier = _generateRandomString(32);

	unless(Sympa::SDM::do_query(
		'DELETE FROM oauthprovider_sessions_table WHERE user_oauthprovider=%s AND consumer_oauthprovider=%s AND isaccess_oauthprovider=1',
		Sympa::SDM::quote($params{'user'}),
		Sympa::SDM::quote($self->{'consumer_key'})
	)) {
		Sympa::Log::do_log('err', 'Unable to delete other already granted access tokens for this user %s %s in database', Sympa::SDM::quote($params{'user'}), $self->{'consumer_key'});
		return undef;
	}

	unless(Sympa::SDM::do_query(
		'UPDATE oauthprovider_sessions_table SET verifier_oauthprovider=%s, user_oauthprovider=%s, accessgranted_oauthprovider=%d, lasttime_oauthprovider=%d WHERE isaccess_oauthprovider IS NULL AND consumer_oauthprovider=%s AND token_oauthprovider=%s',
		Sympa::SDM::quote($verifier),
		Sympa::SDM::quote($params{'user'}),
		$params{'granted'} ? 1 : 0,
		time,
		Sympa::SDM::quote($self->{'consumer_key'}),
		Sympa::SDM::quote($params{'token'})
	)) {
		Sympa::Log::do_log('err', 'Unable to set token verifier %s %s in database', $tmp->{'token'}, $self->{'consumer_key'});
		return undef;
	}

	my $r = $tmp->{'callback'};
	$r .= ($r =~ /^[^\?]\?/) ? '&' : '?';
	$r .= 'oauth_token='.uri_escape($tmp->{'token'});
	$r .= '&oauth_verifier='.uri_escape($verifier);

	return $r;
}

=head2 $provider->generateAccess(%parameters)

Create an access token.

=head3 Parameters

=over

=item * I<token>: the temporary token

=item * I<verifier>: the verifier

=back

=head3 Return value

The response body as a string, or I<undef> if the temporary token does not
exist or is not valid anymore.

=cut

sub generateAccess {
	my ($self, %params) = @_;
	Sympa::Log::do_log('debug2', '(%s, %s, %s)', $params{'token'}, $params{'verifier'}, $self->{'consumer_key'});

	return undef unless(my $tmp = $self->getTemporary(token => $params{'token'}, timeout_type => 'verifier'));
	return undef unless($params{'verifier'} eq $tmp->{'verifier'});

	my $token = _generateRandomString(32);
	my $secret = _generateRandomString(32);

	unless(Sympa::SDM::do_query(
		'UPDATE oauthprovider_sessions_table SET token_oauthprovider=%s, secret_oauthprovider=%s, isaccess_oauthprovider=1, lasttime_oauthprovider=%d, verifier_oauthprovider=NULL, callback_oauthprovider=NULL WHERE token_oauthprovider=%s AND verifier_oauthprovider=%s',
		Sympa::SDM::quote($token),
		Sympa::SDM::quote($secret),
		time,
		Sympa::SDM::quote($params{'token'}),
		Sympa::SDM::quote($params{'verifier'})
	)) {
		Sympa::Log::do_log('err', 'Unable to transform temporary token into access token record %s %s in database', Sympa::SDM::quote($tmp->{'token'}), $self->{'consumer_key'});
		return undef;
	}

	my $r = 'oauth_token='.uri_escape($token);
	$r .= '&oauth_token_secret='.uri_escape($secret);
	$r .= '&oauth_expires_in='.$self->{'constants'}{'access_timeout'};

	return $r;
}

=head2 $provider->getAccess(%parameters)

Retreive an access token from database.

=head3 Parameters

=over

=item * I<token>: the token

=back

=head3 Return value

An hashref if everything's alright, or I<undef> if the token does not exist or
is not valid anymore.

=cut

sub getAccess {
	my ($self, %params) = @_;
	Sympa::Log::do_log('debug2', '(%s)', $params{'token'});

	my $sth;
	unless($sth = Sympa::SDM::do_prepared_query(
		'SELECT token_oauthprovider AS token, secret_oauthprovider AS secret, lasttime_oauthprovider AS lasttime, user_oauthprovider AS user, accessgranted_oauthprovider AS accessgranted FROM oauthprovider_sessions_table WHERE isaccess_oauthprovider=1 AND consumer_oauthprovider=? AND token_oauthprovider=?', $self->{'consumer_key'}, $params{'token'})) {
		Sympa::Log::do_log('err','Unable to load token data %s %s', $self->{'consumer_key'}, $params{'token'});
		return undef;
    }

	my $data = $sth->fetchrow_hashref('NAME_lc');
	return undef unless($data);

	return undef unless($data->{'lasttime'} + $self->{'constants'}{'access_timeout'} >= time);

	return $data;
}

# _generateRandomString($size)
#
# Generate a random string from given size

sub _generateRandomString {
	return join('', map { (0..9, 'a'..'z', 'A'..'Z')[rand 62] } (1..shift));
}

# _getConsumerConfigFor($key)
#
# Retreive the configuration for a consumer, as an hashref
#
# the configuration file looks like:
# # comment
# <consumer_key>
# secret <consumer_secret>
# enabled 0|1

sub _getConsumerConfigFor {
	my ($key, $file) = @_;
	Sympa::Log::do_log('debug2', '(%s)', $key);

	return undef unless (-f $file);

	my $c = {};
	my $k = '';
	open(my $fh, '<', $file) or return undef;
	while(my $l = <$fh>) {
		chomp $l;
		next if($l =~ /^#/);
		next if($k eq '' && $l ne $key);
		$k = $key;
		next if($l eq $key);
		last if($l eq '');
		next unless($l =~ /\s*([^\s]+)\s+(.+)$/);
		$c->{$1} = $2;
	}
	close $fh;

	return $c;
}

=head1 AUTHORS

=over

=item * Etienne Meleard <etienne.meleard AT renater.fr>

=back

=cut

1;
