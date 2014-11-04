# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997-2011 Comite Reseau des Universites
# Copyright (c) 2011-2014 GIP RENATER
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=encoding utf-8

=head1 NAME

Sympa::Session - FIXME

=head1 DESCRIPTION

FIXME

=cut

package Sympa::Session;

use strict;

use CGI::Cookie;

use Sympa::DatabaseManager;
use Sympa::Language;
use Sympa::Logger;
use Sympa::Robot;
use Sympa::Site;
use Sympa::Tools;
use Sympa::Tools::Data;
use Sympa::Tools::Password;
use Sympa::Tools::Time;

# this structure is used to define which session attributes are stored in a
# dedicated database col where others are compiled in col 'data_session'
my %session_hard_attributes = (
    'id_session'   => 1,
    'prev_id'      => 1,
    'date'         => 1,
    'refresh_date' => 1,
    'remote_addr'  => 1,
    'robot'        => 1,
    'email'        => 1,
    'start_date'   => 1,
    'hit'          => 1,
    'new_session'  => 1,
);

=head1 CLASS METHODS

=over 4

=item Sympa::Session->new(%parameters)

Creates a new L<Sympa::Session> object.

Parameters:

=over 4

=item * I<robot>: FIXME

=item * I<cookie>: FIXME

=item * I<action>: FIXME

=item * I<rss>: FIXME

=back

Returns a new L<Sympa::Session> object, or I<undef> for failure.

=cut

sub new {
    my ($class, %params) = @_;
    my $robot   = Sympa::Robot::clean_robot($params{'robot'}, 1);   #FIXME: maybe a Site object?
    my $cookie = $params{'cookie'};
    my $action = $params{'action'};
    my $rss    = $params{'rss'};
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, cookie=%s, action=%s)',
        $robot, $cookie, $action);

    my $self = {'robot' => $robot};
    bless $self, $class;

    # passive_session are session not stored in the database, they are used
    # for crawler bots and action such as css, wsdl, ajax and rss

    if (_is_a_crawler(
            $robot, {'user_agent_string' => $ENV{'HTTP_USER_AGENT'}}
        )
        ) {
        $self->{'is_a_crawler'}    = 1;
        $self->{'passive_session'} = 1;
    }
    $self->{'passive_session'} = 1
        if $rss
            or $action eq 'wsdl'
            or $action eq 'css';

    # if a session cookie exists, try to restore an existing session, don't
    # store sessions from bots
    if ($cookie and $self->{'passive_session'} != 1) {
        my $status;
        $status = $self->load($cookie);
        unless (defined $status) {
            return undef;
        }
        if ($status eq 'not_found') {

            # start a new session (may be a fake cookie)
            $main::logger->do_log(Sympa::Logger::INFO,
                'ignoring unknown session cookie "%s"', $cookie);
            return __PACKAGE__->new($robot);
        }
    } else {

        # create a new session context
        ## Tag this session as new, ie no data in the DB exist
        $self->{'new_session'} = 1;
        $self->{'id_session'}  = get_random();
        $self->{'email'}       = 'nobody';
        $self->{'remote_addr'} = $ENV{'REMOTE_ADDR'};
        $self->{'date'} = $self->{'start_date'} = $self->{'refresh_date'} =
            time;
        $self->{'hit'} = 1;
        ##$self->{'robot'} = $robot->name;
        $self->{'data'} = '';
    }
    return $self;
}

sub load {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, %s)', @_);
    my $self   = shift;
    my $cookie = shift;

    unless ($cookie) {
        $main::logger->do_log(Sympa::Logger::ERR, 'internal error, undef id_session');
        return undef;
    }

    my $sth;
    my $id_session;
    my $is_old_session = 0;

    ## Load existing session.
    if ($cookie and $cookie =~ /^\d{,16}$/) {
        ## Compatibility: session by older releases of Sympa.
        $id_session     = $cookie;
        $is_old_session = 1;

        ## Session by older releases of Sympa doesn't have refresh_date.
        unless (
            $sth = Sympa::DatabaseManager::do_prepared_query(
                q{SELECT id_session AS id_session, id_session AS prev_id,
		     date_session AS "date",
		     remote_addr_session AS remote_addr,
		     robot_session AS robot, email_session AS email,
		     data_session AS data, hit_session AS hit,
		     start_date_session AS start_date,
		     date_session AS refresh_date
	      FROM session_table
	      WHERE robot_session = ? AND
		    id_session = ? AND
		    refresh_date_session IS NULL},
                $self->{'robot'}->name, $id_session
            )
            ) {
            $main::logger->do_log(Sympa::Logger::ERR, 'Unable to load session %s',
                $id_session);
            return undef;
        }
    } else {
        $id_session = decrypt_session_id($cookie);
        unless ($id_session) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'internal error, undef id_session');
            return 'not_found';
        }

        ## Cookie may contain current or previous session ID.
        unless (
            $sth = Sympa::DatabaseManager::do_prepared_query(
                q{SELECT id_session AS id_session, prev_id_session AS prev_id,
		     date_session AS "date",
		     remote_addr_session AS remote_addr,
		     robot_session AS robot, email_session AS email,
		     data_session AS data, hit_session AS hit,
		     start_date_session AS start_date,
		     refresh_date_session AS refresh_date
	      FROM session_table
	      WHERE robot_session = ? AND
		    (id_session = ? AND prev_id_session IS NOT NULL OR
		     prev_id_session = ?)},
                $self->{'robot'}->name, $id_session, $id_session
            )
            ) {
            $main::logger->do_log(Sympa::Logger::ERR, 'Unable to load session %s',
                $id_session);
            return undef;
        }
    }

    my $session     = undef;
    my $new_session = undef;
    my $counter     = 0;
    while ($new_session = $sth->fetchrow_hashref('NAME_lc')) {
        if ($counter > 0) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'The SQL statement did return more than one session');
            $session->{'email'} = '';
            last;
        }
        $session = $new_session;
        $counter++;
    }

    unless ($session) {
        return 'not_found';
    }

    ## Compatibility: Upgrade session by older releases of Sympa.
    if ($is_old_session) {
        Sympa::DatabaseManager::do_prepared_query(
            q{UPDATE session_table
	      SET prev_id_session = id_session
	      WHERE id_session = ? AND prev_id_session IS NULL AND
		    refresh_date_session IS NULL},
            $id_session
        );
    }

    my %datas = Sympa::Tools::Data::string_2_hash($session->{'data'});

    ## canonicalize lang if possible.
    $datas{'lang'} = Sympa::Language::canonic_lang($datas{'lang'}) || $datas{'lang'}
        if $datas{'lang'};

    foreach my $key (keys %datas) { $self->{$key} = $datas{$key}; }

    $self->{'id_session'}   = $session->{'id_session'};
    $self->{'prev_id'}      = $session->{'prev_id'};
    $self->{'date'}         = $session->{'date'};
    $self->{'start_date'}   = $session->{'start_date'};
    $self->{'refresh_date'} = $session->{'refresh_date'};
    $self->{'hit'}          = $session->{'hit'} + 1;
    $self->{'remote_addr'}  = $session->{'remote_addr'};
    ##$self->{'robot'} = $session->{'robot'};
    $self->{'email'} = $session->{'email'};

    return ($self);
}

## This method will both store the session information in the database
sub store {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);
    my $self = shift;

    return undef unless $self->{'id_session'};

    # do not create a session in session table for crawlers;
    return if $self->{'is_a_crawler'};

    # do not create a session in session table for action such as RSS or CSS
    # or wsdl that do not require this sophistication;
    return if $self->{'passive_session'};

    my %hash;
    foreach my $var (keys %$self) {
        next if ($session_hard_attributes{$var});
        next unless ($var);
        $hash{$var} = $self->{$var};
    }
    my $data_string = Sympa::Tools::Data::hash_2_string(\%hash);
    my $time        = time;

    ## If this is a new session, then perform an INSERT
    if ($self->{'new_session'}) {
        ## Store the new session ID in the DB
        ## Previous session ID is set to be same as new session ID.
        unless (
            Sympa::DatabaseManager::do_prepared_query(
                q{INSERT INTO session_table
	      (id_session, prev_id_session,
	       date_session, refresh_date_session,
	       remote_addr_session, robot_session,
	       email_session, start_date_session, hit_session,
	       data_session)
	      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
                $self->{'id_session'}, $self->{'id_session'},
                $time,                 $time,
                $ENV{'REMOTE_ADDR'},   $self->{'robot'}->name,
                $self->{'email'}, $self->{'start_date'}, $self->{'hit'},
                $data_string
            )
            ) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Unable to add new session %s informations in database',
                $self->{'id_session'});
            return undef;
        }

        $self->{'prev_id'} = $self->{'id_session'};

    } else {
        ## If the session already exists in DB, then perform an UPDATE

        ## Cookie may contain previous session ID.
        my $sth = Sympa::DatabaseManager::do_prepared_query(
            q{SELECT id_session
	      FROM session_table
	      WHERE robot_session = ? AND prev_id_session = ?},
            $self->{'robot'}->name, $self->{'id_session'}
        );
        unless ($sth) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Unable to update session information in database');
            return undef;
        }
        if ($sth->rows) {
            my $new_id = $sth->fetchrow;
            $sth->finish;
            if ($new_id) {
                $self->{'prev_id'}    = $self->{'id_session'};
                $self->{'id_session'} = $new_id;
            }
        }

        ## Update the new session in the DB
        unless (
            Sympa::DatabaseManager::do_prepared_query(
                q{UPDATE session_table
	      SET date_session = ?, remote_addr_session = ?,
		  robot_session = ?, email_session = ?,
		  start_date_session = ?, hit_session = ?, data_session = ?
	      WHERE robot_session = ? AND
		    (id_session = ? AND prev_id_session IS NOT NULL OR
		     prev_id_session = ?)},
                $time,                  $ENV{'REMOTE_ADDR'},
                $self->{'robot'}->name, $self->{'email'},
                $self->{'start_date'}, $self->{'hit'}, $data_string,
                $self->{'robot'}->name,
                $self->{'id_session'},
                $self->{'id_session'}
            )
            ) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Unable to update session %s information in database',
                $self->{'id_session'});
            return undef;
        }
    }

    return 1;
}

## This method will renew the session ID
sub renew {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);
    my $self = shift;

    return undef unless $self->{'id_session'};

    # do not create a session in session table for crawlers;
    return if $self->{'is_a_crawler'};

    # do not create a session in session table for action such as RSS or CSS
    # or wsdl that do not require this sophistication;
    return if $self->{'passive_session'};

    my %hash;
    foreach my $var (keys %$self) {
        next if ($session_hard_attributes{$var});
        next unless ($var);
        $hash{$var} = $self->{$var};
    }

    my $sth;
    ## Cookie may contain previous session ID.
    $sth = Sympa::DatabaseManager::do_prepared_query(
        q{SELECT id_session
	  FROM session_table
	  WHERE robot_session = ? AND prev_id_session = ?},
        $self->{'robot'}->name, $self->{'id_session'}
    );
    unless ($sth) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to update session information in database');
        return undef;
    }
    if ($sth->rows) {
        my $new_id = $sth->fetchrow;
        $sth->finish;
        if ($new_id) {
            $self->{'prev_id'}    = $self->{'id_session'};
            $self->{'id_session'} = $new_id;
        }
    }

    ## Renew the session ID in order to prevent session hijacking
    my $new_id = get_random();

    ## Do refresh the session ID when remote address was changed or refresh
    ## interval was past.  Conditions also are checked by SQL so that
    ## simultaneous processes will be prevented renewing cookie.
    my $time        = time;
    my $remote_addr = $ENV{'REMOTE_ADDR'};
    my $refresh_term;
    if (Sympa::Site->cookie_refresh == 0) {
        $refresh_term = $time;
    } else {
        my $cookie_refresh = Sympa::Site->cookie_refresh;
        $refresh_term =
            int($time - $cookie_refresh * 0.25 - rand($cookie_refresh * 0.5));
    }
    unless ($self->{'remote_addr'} ne $remote_addr
        or $self->{'refresh_date'} <= $refresh_term) {
        return 0;
    }

    ## First insert DB entry with new session ID,
    $sth = Sympa::DatabaseManager::do_query(
        q{INSERT INTO session_table
	  (id_session, prev_id_session,
	   start_date_session, date_session, refresh_date_session,
	   remote_addr_session, robot_session, email_session,
	   hit_session, data_session)
	  SELECT %s, id_session,
		 start_date_session, date_session, %d,
		 %s, robot_session, email_session,
		 hit_session, data_session
	  FROM session_table
	  WHERE robot_session = %s AND
		(id_session = %s AND prev_id_session IS NOT NULL OR
		 prev_id_session = %s) AND
		(remote_addr_session <> %s OR refresh_date_session <= %d)},
        Sympa::DatabaseManager::quote($new_id),
        $time,
        Sympa::DatabaseManager::quote($remote_addr),
        Sympa::DatabaseManager::quote($self->{'robot'}->name),
        Sympa::DatabaseManager::quote($self->{'id_session'}),
        Sympa::DatabaseManager::quote($self->{'id_session'}),
        Sympa::DatabaseManager::quote($remote_addr), $refresh_term
    );
    unless ($sth) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to renew session ID for session %s',
            $self->{'id_session'});
        return undef;
    }
    unless ($sth->rows) {
        return 0;
    }
    ## Keep previous ID to prevent crosstalk, clearing grand-parent ID.
    Sympa::DatabaseManager::do_prepared_query(
        q{UPDATE session_table
	  SET prev_id_session = NULL
	  WHERE robot_session = ? AND id_session = ?},
        $self->{'robot'}->name, $self->{'id_session'}
    );
    ## Remove record of grand-parent ID.
    Sympa::DatabaseManager::do_prepared_query(
        q{DELETE FROM session_table
	   WHERE id_session = ? AND prev_id_session IS NULL},
        $self->{'prev_id'}
    );

    ## Renew the session ID in order to prevent session hijacking
    $main::logger->do_log(
        Sympa::Logger::INFO,
        '[robot %s] [session %s] [client %s]%s new session %s',
        $self->{'robot'}->name,
        $self->{'id_session'},
        $remote_addr,
        ($self->{'email'} ? sprintf(' [user %s]', $self->{'email'}) : ''),
        $new_id
    );
    $self->{'prev_id'}      = $self->{'id_session'};
    $self->{'id_session'}   = $new_id;
    $self->{'refresh_date'} = $time;
    $self->{'remote_addr'}  = $remote_addr;

    return 1;
}

## remove old sessions from a particular robot or from all robots.
## delay is a parameter in seconds
sub purge_old_sessions {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);
    my $robot = Sympa::Robot::clean_robot(shift, 1);

    my $delay = Sympa::Tools::Time::duration_conv(Sympa::Site->session_table_ttl);
    my $anonymous_delay =
        Sympa::Tools::Time::duration_conv(Sympa::Site->anonymous_session_table_ttl);

    unless ($delay) {
        $main::logger->do_log(Sympa::Logger::DEBUG3, 'exit with delay null');
        return;
    }
    unless ($anonymous_delay) {
        $main::logger->do_log(Sympa::Logger::DEBUG3,
            'exit with anonymous delay null');
        return;
    }

    my @sessions;
    my $sth;

    my $condition = '';
    $condition = sprintf 'robot_session = %s', Sympa::DatabaseManager::quote($robot->name)
        if ref $robot eq 'Sympa::Robot';
    my $anonymous_condition = $condition;

    $condition .= sprintf '%s%d > date_session',
        ($condition ? ' AND ' : ''), time - $delay
        if $delay;
    $condition = " WHERE $condition"
        if $condition;

    $anonymous_condition .= sprintf '%s%d > date_session',
        ($anonymous_condition ? ' AND ' : ''), time - $anonymous_delay
        if $anonymous_delay;
    $anonymous_condition .= sprintf
        "%semail_session = 'nobody' AND hit_session = 1",
        ($anonymous_condition ? ' AND ' : '');
    $anonymous_condition = " WHERE $anonymous_condition"
        if $anonymous_condition;

    my $count_statement           = q{SELECT count(*) FROM session_table%s};
    my $anonymous_count_statement = q{SELECT count(*) FROM session_table%s};
    my $statement                 = q{DELETE FROM session_table%s};
    my $anonymous_statement       = q{DELETE FROM session_table%s};

    unless ($sth = Sympa::DatabaseManager::do_query($count_statement, $condition)) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to count old session for robot %s', $robot);
        return undef;
    }

    my $total = $sth->fetchrow;
    if ($total == 0) {
        $main::logger->do_log(Sympa::Logger::DEBUG3, 'no sessions to expire');
    } else {
        unless ($sth = Sympa::DatabaseManager::do_query($statement, $condition)) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Unable to purge old sessions for robot %s', $robot);
            return undef;
        }
    }
    unless ($sth =
        Sympa::DatabaseManager::do_query($anonymous_count_statement, $anonymous_condition)) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to count anonymous sessions for robot %s', $robot);
        return undef;
    }
    my $anonymous_total = $sth->fetchrow;
    if ($anonymous_total == 0) {
        $main::logger->do_log(Sympa::Logger::DEBUG3,
            'no anonymous sessions to expire');
        return $total;
    }
    unless ($sth = Sympa::DatabaseManager::do_query($anonymous_statement, $anonymous_condition))
    {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to purge anonymous sessions for robot %s', $robot);
        return undef;
    }
    return $total + $anonymous_total;
}

## remove old one_time_ticket from a particular robot or from all robots.
## delay is a parameter in seconds
##
sub purge_old_tickets {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);
    my $robot = Sympa::Robot::clean_robot(shift, 1);

    my $delay = Sympa::Tools::Time::duration_conv(Sympa::Site->one_time_ticket_table_ttl);
    unless ($delay) {
        $main::logger->do_log(Sympa::Logger::DEBUG3, 'exit with delay null');
        return;
    }

    my @tickets;
    my $sth;

    my $condition = '';
    $condition = sprintf '%d > date_one_time_ticket', time - $delay
        if $delay;
    $condition .= sprintf '%srobot_one_time_ticket = %s',
        ($condition ? ' AND ' : ''), Sympa::DatabaseManager::quote($robot->name)
        if ref $robot eq 'Sympa::Robot';
    $condition = " WHERE $condition"
        if $condition;

    unless (
        $sth = Sympa::DatabaseManager::do_query(
            q{SELECT count(*) FROM one_time_ticket_table%s}, $condition
        )
        ) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to count old one time tickets for robot %s', $robot);
        return undef;
    }

    my $total = $sth->fetchrow;
    if ($total == 0) {
        $main::logger->do_log(Sympa::Logger::DEBUG3, 'no tickets to expire');
    } else {
        unless ($sth =
            Sympa::DatabaseManager::do_query(q{DELETE FROM one_time_ticket_table%s}, $condition))
        {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Unable to delete expired one time tickets for robot %s',
                $robot);
            return undef;
        }
    }
    return $total;
}

# list sessions for $robot where last access is newer then $delay. List is
# limited to connected users if $connected_only
sub list_sessions {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, %s, %s)', @_);
    my $delay          = shift;
    my $robot          = Sympa::Robot::clean_robot(shift, 1);
    my $connected_only = shift;

    my @sessions;
    my $sth;
    my $time = time;

    my $condition = '';
    $condition = sprintf 'robot_session = %s', Sympa::DatabaseManager::quote($robot->name)
        if ref $robot eq 'Sympa::Robot';
    $condition .= sprintf '%s%d < date_session',
        ($condition ? ' AND ' : ''), $time - $delay
        if $delay;
    $condition .= sprintf "%semail_session <> 'nobody'",
        ($condition ? ' AND ' : '')
        if $connected_only eq 'on';
    $condition .= sprintf "%sprev_id_session IS NOT NULL",
        ($condition ? ' AND ' : '');
    $condition = " WHERE $condition"
        if $condition;

    unless (
        $sth = Sympa::DatabaseManager::do_query(
            q{SELECT remote_addr_session, email_session, robot_session,
	             date_session AS date_epoch,
                     start_date_session AS start_date_epoch, hit_session
	  FROM session_table%s},
            $condition
        )
        ) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to get the list of sessions for robot %s', $robot);
        return undef;
    }

    while (my $session = ($sth->fetchrow_hashref('NAME_lc'))) {
        push @sessions, $session;
    }

    return \@sessions;
}

###############################
# Subroutines to read cookies #
###############################

## Generic subroutine to get a cookie value
sub get_session_cookie {
    my $http_cookie = shift;

    if ($http_cookie =~ /\S+/g) {
        my %cookies = parse CGI::Cookie($http_cookie);
        foreach (keys %cookies) {
            my $cookie = $cookies{$_};
            next unless ($cookie->name eq 'sympa_session');
            return ($cookie->value);
        }
    }

    return (undef);
}

## Generic subroutine to set a cookie
## Set user $email cookie, ckecksum use $secret, expire=(now|session|#sec)
## domain=(localhost|<a domain>)
sub set_cookie {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s, %s, %s, %s)', @_);
    my ($self, $http_domain, $expires, $use_ssl) = @_;

    my $expiration;
    if ($expires =~ /now/i) {
        ## 10 years ago
        $expiration = '-10y';
    } else {
        $expiration = '+' . $expires . 'm';
    }

    if ($http_domain eq 'localhost') {
        $http_domain = "";
    }

    my $value = encrypt_session_id($self->{'id_session'});

    my $cookie;
    if ($expires =~ /session/i) {
        $cookie = CGI::Cookie->new(
            -name     => 'sympa_session',
            -value    => $value,
            -domain   => $http_domain,
            -path     => '/',
            -secure   => $use_ssl,
            -httponly => 1
        );
    } else {
        $cookie = CGI::Cookie->new(
            -name     => 'sympa_session',
            -value    => $value,
            -expires  => $expiration,
            -domain   => $http_domain,
            -path     => '/',
            -secure   => $use_ssl,
            -httponly => 1
        );
    }

    ## Send cookie to the client
    printf "Set-Cookie: %s\n", $cookie->as_string;
    return 1;
}

# Build an HTTP cookie value to be sent to a SOAP client
sub soap_cookie2 {
    my ($session_id, $http_domain, $expire) = @_;
    my $cookie;
    my $value;

    # WARNING : to check the cookie the SOAP services does not gives
    # all the cookie, only it's value so we need ':'
    $value = encrypt_session_id($session_id);

    ## With set-cookie2 max-age of 0 means removing the cookie
    ## Maximum cookie lifetime is the session
    $expire ||= 600;    ## 10 minutes

    if ($http_domain eq 'localhost') {
        $cookie = CGI::Cookie->new(
            -name  => 'sympa_session',
            -value => $value,
            -path  => '/',
        );
        $cookie->max_age(time + $expire);    # needs CGI >= 3.51.
    } else {
        $cookie = CGI::Cookie->new(
            -name   => 'sympa_session',
            -value  => $value,
            -domain => $http_domain,
            -path   => '/',
        );
        $cookie->max_age(time + $expire);    # needs CGI >= 3.51.
    }

    ## Return the cookie value
    return $cookie->as_string;
}

sub get_random {
    $main::logger->do_log(Sympa::Logger::DEBUG3, '()');
    ## Concatenates 2 integers for a better entropy
    my $random = int(rand(10**7)) . int(rand(10**7));
    $random =~ s/^0(\.|\,)//;
    return ($random);
}

## Return the session object content, as a hashref
sub as_hashref {
    my $self = shift;
    my $data;

    foreach my $key (keys %{$self}) {
        if ($key eq 'robot') {
            $data->{$key} = $self->{'robot'}->name;
        } else {
            $data->{$key} = $self->{$key};
        }
    }

    return $data;
}

## Return 1 if the Session object corresponds to an anonymous session.
sub is_anonymous {
    my $self = shift;
    if ($self->{'email'} eq 'nobody' || $self->{'email'} eq '') {
        return 1;
    } else {
        return 0;
    }
}

## Generate cookie from session ID.
sub encrypt_session_id {
    my $id_session = shift;

    return $id_session unless Sympa::Site->cookie;
    my $cipher = Sympa::Tools::Password::ciphersaber_installed();
    return $id_session unless $cipher;

    my $id_session_bin = pack 'nN', ($id_session >> 32),
        $id_session % (1 << 32);
    my $cookie_bin = $cipher->encrypt($id_session_bin);
    return sprintf '%*v02x', '', $cookie_bin;
}

## Get session ID from cookie.
sub decrypt_session_id {
    my $cookie = shift;

    return $cookie unless Sympa::Site->cookie;
    my $cipher = Sympa::Tools::Password::ciphersaber_installed();
    return $cookie unless $cipher;

    return undef unless $cookie =~ /\A[0-9a-f]+\z/;
    my $cookie_bin = $cookie;
    $cookie_bin =~ s/([0-9a-f]{2})/sprintf '%c', hex("0x$1")/eg;
    my ($id_session_hi, $id_session_lo) = unpack 'nN',
        $cipher->decrypt($cookie_bin);

    return ($id_session_hi << 32) + $id_session_lo;
}

## Get unique ID
sub get_id {
    my $self = shift;
    return '' unless $self->{'id_session'} and $self->{'robot'};
    return sprintf '%s@%s', $self->{'id_session'}, $self->{'robot'}->name;
}

# input user agent string and IP. return 1 if suspected to be a crawler.
# initial version based on crawlers_detection.conf file only
# later : use Session table to identify those who create a lot of sessions
##FIXME:per-robot config should be available.
sub _is_a_crawler {
    my $robot = shift;
    my $context = shift || {};

    return Sympa::Site->crawlers_detection->{'user_agent_string'}
        {$context->{'user_agent_string'} || ''};
}

1;
