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

Sympa::Auth::OAuth::Provider - OAuth provider object

=head1 DESCRIPTION

This class implements the server side of the OAuth workflow.

It handles requests for temporary/access tokens and database storage.

=cut

package Sympa::Auth::OAuth::Provider;

use strict;
use constant {
	# Max age for requests timestamps
	OLD_REQUEST_TIMEOUT => 600,
	# Time the nonce tags are kept
	NONCE_TIMEOUT       => 3600 * 24 * 30 * 3,
	# Time left to use the temporary token
	TEMPORARY_TIMEOUT   => 3600,
	# Time left to request access once the verifier has been set
	VERIFIER_TIMEOUT    => 300,
	# Access timeout
	ACCESS_TIMEOUT      => 3600 * 24 * 30 * 3,
};

use OAuth::Lite::ServerUtil;
use URI::Escape;

use Sympa::Database;
use Sympa::Log::Syslog;
use Sympa::Tools;

=head1 CLASS METHODS

=over

=item Sympa::Auth::OAuth::Provider->new(%parameters)

Creates a new L<Sympa::Auth::OAuth::Provider> object.

Parameters:

=over

=item C<method> => http method

=item C<url> => request url

=item C<authorization_header> => FIXME

=item C<request_parameters> => FIXME

=item C<request_body> => FIXME

=item C<config> => FIXME

=back

Return value:

A L<Sympa::Auth::OAuth::Provider> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $params{'consumer_key'});

	my $p = _find_parameters(
		authorization_header => $params{'authorization_header'},
		request_parameters => $params{'request_parameters'},
		request_body => $params{'request_body'}
	);
	return undef unless(defined($p));
	return undef unless(defined($p->{'oauth_consumer_key'}));

	my $c = _get_consumer_config_for($p->{'oauth_consumer_key'}, $params{config});
	return undef unless(defined($c));
	return undef unless(defined($c->{'enabled'}));
	return undef unless($c->{'enabled'} eq '1');

	my $self = {
		method          => $params{'method'},
		url             => $params{'url'},
		params          => $p,
		consumer_key    => $p->{'oauth_consumer_key'},
		consumer_secret => $c->{'secret'},
	};

	my $util = OAuth::Lite::ServerUtil->new();
	$util->support_signature_method('HMAC-SHA1');
	$util->allow_extra_params(qw/oauth_callback oauth_verifier/);
	$self->{util} = $util;

	my $base = Sympa::Database::get_source();
	my $rows = $base->execute_query(
		'DELETE FROM oauthprovider_sessions_table '   .
		'WHERE '                                      .
			'isaccess_oauthprovider IS NULL AND ' .
			'lasttime_oauthprovider<?',
		time - TEMPORARY_TIMEOUT
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Unable to delete old temporary tokens in database');
		return undef;
	}

	bless $self, $class;
	return $self;
}

=item Sympa::Auth::OAuth::Provider->consumer_from_token($token)

=cut

sub consumer_from_token {
	my ($class, $token) = @_;

	my $base = Sympa::Database::get_source();
	my $handle = $base->get_query_handle(
		"SELECT consumer_oauthprovider AS consumer " .
		"FROM oauthprovider_sessions_table "         .
		"WHERE token_oauthprovider=?"
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to load token data %s', $token);
		return undef;
	}
	$handle->execute($token);

	my $data = $handle->fetchrow_hashref('NAME_lc');
	return undef unless($data);
	return $data->{'consumer'};
}

# _find_parameters(%parameters)
# Seek various request aspects for parameters
# Parameters:
# - authorization_header
# - request_parameters
# - request_body
# Returns an hashref, or undef if something went wrong

sub _find_parameters {
	my (%params) = @_;

	my $p = {};
	if(defined($params{'authorization_header'}) && $params{'authorization_header'} =~ /^OAuth /) {
		foreach my $b (split(/,\s*/, $params{'authorization_header'})) {
			next unless($b =~ /^(OAuth\s)?\s*(x?oauth_[^=]+)="([^"]*)"\s*$/);
			$p->{$2} = uri_unescape($3);
		}
	} elsif(defined($params{'request_body'})) {
		foreach my $k (keys(%{$params{'request_body'}})) {
			next unless($k =~ /^x?oauth_/);
			$p->{$k} = uri_unescape($params{'request_body'}{$k});
		}
	} elsif(defined($params{'request_parameters'})) {
		foreach my $k (keys(%{$params{'request_parameters'}})) {
			next unless($k =~ /^x?oauth_/);
			$p->{$k} = uri_unescape($params{'request_parameters'}{$k});
		}
	} else {
		return undef;
	}

	return $p;
}

=back

=head1 INSTANCE METHODS

=over

=item $provider->check_request(%parameters)

Check if a request is valid.

    if(my $http_code = $provider->check_request()) {
	$server->error($http_code, $provider->{'util'}->errstr);
    }

Parameters:

=over

=item C<checktoken> => boolean

=back

Return value:

The HTTP error code if the request is NOT valid, I<undef> otherwise.

=cut

sub check_request {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $params{'url'});

	my $checktoken = defined($params{'checktoken'}) ? $params{'checktoken'} : undef;
	unless($self->{'util'}->validate_params($self->{'params'}, $checktoken)) {
		return 400;
	}

	my $nonce = $self->{'params'}{'oauth_nonce'};
	my $token = $self->{'params'}{'oauth_token'};
	my $timestamp = $self->{'params'}{'oauth_timestamp'};

	return 401 unless($timestamp > time - OLD_REQUEST_TIMEOUT);

	my $base = Sympa::Database::get_source();
	my $rows = $base->execute_query(
		'DELETE FROM oauthprovider_nonces_table ' .
		'WHERE time_oauthprovider<?',
		time - NONCE_TIMEOUT
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Unable to clean nonce store in database');
		return 401;
	}

	if($checktoken) {
		my $id_handle = $base->get_query_handle(
			"SELECT id_oauthprovider AS id "        .
			"FROM oauthprovider_sessions_table "    .
			"WHERE "                                .
				"consumer_oauthprovider=? AND " .
				"token_oauthprovider=?",
		);
		unless ($id_handle) {
			Sympa::Log::Syslog::do_log('err','Unable to get token %s %s', $self->{'consumer_key'}, $token);
			return 401;
		}
		$id_handle->execute($self->{'consumer_key'}, $token);

		if (my $data = $id_handle->fetchrow_hashref('NAME_lc')) {
			my $id = $data->{'id'};

			my $nonce_handle = $base->get_query_handle(
				"SELECT nonce_oauthprovider AS nonce " .
				"FROM oauthprovider_nonces_table "     .
				"WHERE "                               .
					"id_oauthprovider=? AND "      .
					"nonce_oauthprovider=?",
			);
			unless ($nonce_handle) {
				Sympa::Log::Syslog::do_log('err','Unable to check nonce %d %s', $id, $nonce);
				return 401;
			}
			$nonce_handle->execute($id, $nonce);

			# Already used nonce
			return 401
				if $nonce_handle->fetchrow_hashref('NAME_lc');

			my $rows = $base->execute_query(
				"INSERT INTO oauthprovider_nonces_table(" .
					"id_oauthprovider, " .
					"nonce_oauthprovider, " .
					"time_oauthprovider" .
				") VALUES (?, ?, ?)",
				$id,
				$nonce,
				time
			);
			unless ($rows) {
				Sympa::Log::Syslog::do_log('err', 'Unable to add nonce record %d %s in database', $id, $nonce);
				return 401;
			}
		}
	}

	my $secret = '';
	if ($checktoken) {
		my $token_handle = $base->get_query_handle(
			"SELECT secret_oauthprovider AS secret " .
			"FROM oauthprovider_sessions_table "     .
			"WHERE token_oauthprovider=?"
		);
		unless ($token_handle) {
			Sympa::Log::Syslog::do_log('err','Unable to load token data %s', $token);
			return undef;
		}
		$token_handle->execute($token);

		my $data = $token_handle->fetchrow_hashref('NAME_lc');
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

=item $provider->generate_temporary(%parameters)

Create a temporary token.

Parameters:

=over

=item C<authorize> => the authorization url

=back

Return value:

The response body, as a string.

=cut

sub generate_temporary {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $self->{'consumer_key'});

	my $token = _generateRandomString(32); # 9x10^62 entropy ...
	my $secret = _generateRandomString(32); # may be sha1-ed or such ...

	my $base = Sympa::Database::get_source();
	my $rows = $base->execute_query(
		"INSERT INTO oauthprovider_sessions_table(" .
			"token_oauthprovider, "             .
			"secret_oauthprovider, "            .
			"isaccess_oauthprovider, "          .
			"accessgranted_oauthprovider, "     .
			"consumer_oauthprovider, "          .
			"user_oauthprovider, "              .
			"firsttime_oauthprovider, "         .
			"lasttime_oauthprovider, "          .
			"verifier_oauthprovider, "          .
			"callback_oauthprovider"            .
		") VALUES (?, ?, NULL, NULL, ?, NULL, ?, ?, NULL, ?)",
		$token,
		$secret,
		$self->{'consumer_key'},
		time(),
		time(),
		$self->{'params'}{'oauth_callback'}
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Unable to add new token record %s %s in database', $token, $self->{'consumer_key'});
		return undef;
	}

	my $r = 'oauth_token='.uri_escape($token);
	$r .= '&oauth_token_secret='.uri_escape($secret);
	$r .= '&oauth_expires_in='.TEMPORARY_TIMEOUT;
	$r .= '&xoauth_request_auth_url='.$params{'authorize'} if(defined($params{'authorize'}));
	$r .= '&oauth_callback_confirmed=true';

	return $r;
}

=item $provider->get_temporary(%parameters)

Retreive a temporary token from database.

Parameters:

=over

=item C<token> => the toke

=item C<timeout> => the timeout

=back

Return value:

An hashref, or I<undef> if the token does not exist or is not valid anymore.

=cut

sub get_temporary {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $params{'token'});

	my $base = Sympa::Database::get_source();
	my $handle = $base->get_query_handle(
		"SELECT "                                        .
			"id_oauthprovider AS id, "               .
			"token_oauthprovider AS token, "         .
			"secret_oauthprovider AS secret, "       .
			"firsttime_oauthprovider AS firsttime, " .
			"lasttime_oauthprovider AS lasttime, "   .
			"callback_oauthprovider AS callback, "   .
			"verifier_oauthprovider AS verifier "    .
		"FROM oauthprovider_sessions_table "             .
		"WHERE "                                         .
			"isaccess_oauthprovider IS NULL AND "    .
			"consumer_oauthprovider=? AND "          .
			"token_oauthprovider=?"
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to load token data %s %s', $self->{'consumer_key'}, $params{'token'});
		return undef;
	}
	$handle->execute($self->{'consumer_key'}, $params{'token'});

	my $data = $handle->fetchrow_hashref('NAME_lc');
	return undef unless($data);

	return undef unless($data->{'lasttime'} + $params{timeout} >= time);

	return $data;
}

=item $provider->generate_verifier(%parameters)

Create the verifier for a temporary token.

Parameters:

=over

=item C<token> => the token

=item C<user> => the user

=back

Return value:

A redirect URL, as a string, or I<undef> if the token does not exist or is not
valid anymore.

=cut

sub generate_verifier {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s, %s)', $params{'token'}, $params{'user'}, $params{'granted'}, $self->{'consumer_key'});

	return undef unless(my $tmp = $self->get_temporary(token => $params{'token'}, timeout => TEMPORARY_TIMEOUT));

	my $verifier = _generateRandomString(32);

	my $base = Sympa::Database::get_source();
	my $delete_rows = $base->execute_query(
		'DELETE FROM oauthprovider_sessions_table ' .
		'WHERE '                                    .
			'user_oauthprovider=? AND '         .
			'consumer_oauthprovider=? AND '     .
			'isaccess_oauthprovider=1',
		$params{'user'},
		$self->{'consumer_key'}
	);
	unless ($delete_rows) {
		Sympa::Log::Syslog::do_log('err', 'Unable to delete other already granted access tokens for this user %s %s in database', $params{'user'}, $self->{'consumer_key'});
		return undef;
	}

	my $update_rows = $base->execute_query(
		"UPDATE oauthprovider_sessions_table "        .
		"SET "                                        .
			"verifier_oauthprovider=?, "          .
			"user_oauthprovider=?, "              .
			"accessgranted_oauthprovider=?, "     .
			"lasttime_oauthprovider=? "           .
		"WHERE "                                      .
			"isaccess_oauthprovider IS NULL AND " .
			"consumer_oauthprovider=? AND "       .
			"token_oauthprovider=?",
		$verifier,
		$params{'user'},
		$params{'granted'} ? 1 : 0,
		time(),
		$self->{'consumer_key'},
		$params{'token'}
	);
	unless ($update_rows) {
		Sympa::Log::Syslog::do_log('err', 'Unable to set token verifier %s %s in database', $tmp->{'token'}, $self->{'consumer_key'});
		return undef;
	}

	my $r = $tmp->{'callback'};
	$r .= ($r =~ /^[^\?]\?/) ? '&' : '?';
	$r .= 'oauth_token='.uri_escape($tmp->{'token'});
	$r .= '&oauth_verifier='.uri_escape($verifier);

	return $r;
}

=item $provider->generate_access(%parameters)

Create an access token.

Parameters:

=over

=item C<token> => the temporary token

=item C<verifier> => the verifier

=back

Return value:

The response body as a string, or I<undef> if the temporary token does not
exist or is not valid anymore.

=cut

sub generate_access {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s)', $params{'token'}, $params{'verifier'}, $self->{'consumer_key'});

	return undef unless(my $tmp = $self->get_temporary(token => $params{'token'}, timeout => VERIFIER_TIMEOUT));
	return undef unless($params{'verifier'} eq $tmp->{'verifier'});

	my $token = _generateRandomString(32);
	my $secret = _generateRandomString(32);

	my $base = Sympa::Database::get_source();
	my $rows = $base->execute_query(
		"UPDATE oauthprovider_sessions_table "       .
		"SET "                                       .
			"token_oauthprovider=?, "            .
			"secret_oauthprovider=?, "           .
			"isaccess_oauthprovider=1, "         .
			"lasttime_oauthprovider=?, "         .
			"verifier_oauthprovider=NULL, "      .
			"callback_oauthprovider=NULL "       .
			"WHERE "                             .
				"token_oauthprovider=? AND " .
				"verifier_oauthprovider=?",
		undef,
		$token,
		$secret,
		time(),
		$params{'token'},
		$params{'verifier'}
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err', 'Unable to transform temporary token into access token record %s %s in database', $tmp->{'token'}, $self->{'consumer_key'});
		return undef;
	}

	my $r = 'oauth_token='.uri_escape($token);
	$r .= '&oauth_token_secret='.uri_escape($secret);
	$r .= '&oauth_expires_in='.ACCESS_TIMEOUT;

	return $r;
}

=item $provider->get_access(%parameters)

Retreive an access token from database.

Parameters:

=over

=item C<token> => the token

=back

Return value:

An hashref if everything's alright, or I<undef> if the token does not exist or
is not valid anymore.

=cut

sub get_access {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $params{'token'});

	my $base = Sympa::Database::get_source();
	my $handle = $base->get_query_handle(
		"SELECT "                                               .
			"token_oauthprovider AS token, "                .
			"secret_oauthprovider AS secret, "              .
			"lasttime_oauthprovider AS lasttime, "          .
			"user_oauthprovider AS user, "                  .
			"accessgranted_oauthprovider AS accessgranted " .
		"FROM oauthprovider_sessions_table "                    .
		"WHERE "                                                .
			"isaccess_oauthprovider=1 AND "                 .
			"consumer_oauthprovider=? AND "                 .
			"token_oauthprovider=?"
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to load token data %s %s', $self->{'consumer_key'}, $params{'token'});
		return undef;
	}
	$handle->execute($self->{'consumer_key'}, $params{'token'});

	my $data = $handle->fetchrow_hashref('NAME_lc');
	return undef unless($data);

	return undef unless($data->{'lasttime'} + ACCESS_TIMEOUT >= time);

	return $data;
}

# _generateRandomString($size)
#
# Generate a random string from given size

sub _generateRandomString {
	return join('', map { (0..9, 'a'..'z', 'A'..'Z')[rand 62] } (1..shift));
}

# _get_consumer_config_for($key)
#
# Retreive the configuration for a consumer, as an hashref
#
# the configuration file looks like:
# # comment
# <consumer_key>
# secret <consumer_secret>
# enabled 0|1

sub _get_consumer_config_for {
	my ($key, $file) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $key);

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

=back

=head1 AUTHORS

=over

=item * Etienne Meleard <etienne.meleard AT renater.fr>

=back

=cut

1;
