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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=encoding utf-8

=head1 NAME

Sympa::Session - HTTP session object

=head1 DESCRIPTION

This class implements an HTTP session.

=cut

package Sympa::Session;

use strict;

use Carp;
use CGI::Cookie;
use Digest::MD5;

use Sympa::Language;
use Sympa::Log::Syslog;
use Sympa::Tools::Data;
use Sympa::Tools::Password;

# this structure is used to define which session attributes are stored in a
# dedicated database col where others are compiled in col 'data_session'
my %session_hard_attributes = (
	'id_session'  => 1,
	'date'        => 1,
	'remote_addr' => 1,
	'robot'       => 1,
	'email'       => 1,
	'start_date'  => 1,
	'hit'         => 1,
	'new_session' => 1,
);

=head1 CLASS METHODS

=over

=item Sympa::Session->new(%parameters)

Creates a new L<Sympa::Session> object.

Parameters:

=over

=item C<robot> => FIXME

=item C<context> => FIXME

=item C<crawlers> => FIXME

=item C<base> => L<Sympa::Database>

=back

Return:

A new L<Sympa::Session> object, or I<undef>, if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	croak "missing robot parameter" unless $params{robot};
    Sympa::Log::Syslog::do_log('debug2', '(%s, cookie=%s, action=%s)',
	$robot, $cookie, $action);

	croak "missing base parameter" unless $params{base};
	croak "invalid base parameter" unless
		$params{base}->isa('Sympa::Database');

	my $cookie = $params{context}->{'cookie'};
	my $action = $params{context}->{'action'};
	my $rss = $params{context}->{'rss'};

	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s)', $params{robot},$cookie,$action);
	my $self = {
		base => $params{base}
	};
	bless $self, $class;

	$self->{'is_a_crawler'} = $params{crawlers}->{$ENV{'HTTP_USER_AGENT'}};
	# passive_session are session not stored in the database, they are used
	# for crawler bots and action such as css, wsdl, ajax and rss
	$self->{'passive_session'} =
		$self->{'is_a_crawler'} ||
		$rss                    ||
		$action eq 'wsdl'       ||
		$action eq 'css';

	# if a session cookie exist, try to restore an existing session, don't store sessions from bots
	if (($cookie)&&($self->{'passive_session'} != 1)){
		my $status;
		$status = $self->load($cookie);
		unless (defined $status) {
			return undef;
		}
		if ($status eq 'not_found') {
			Sympa::Log::Syslog::do_log('info',"ignoring unknown session cookie '$cookie'"); # start a new session (may ne a fake cookie)
			return (Sympa::Session->new(
					robot    => $params{robot},
					crawlers => $params{crawlers},
				));
		}
		# checking if the client host is unchanged during the session brake sessions when using multiple proxy with
		# load balancing (round robin, etc). This check is removed until we introduce some other method
		# if($session->{'remote_addr'} ne $ENV{'REMOTE_ADDR'}){
		#    Sympa::Log::Syslog::do_log('info','SympaSession::new ignoring session cookie because remote host %s is not the original host %s', $ENV{'REMOTE_ADDR'},$session->{'remote_addr'}); # start a new session
		#    return (SympaSession->new($robot));
		#}
	} else {
		# create a new session context
		$self->{'new_session'} = 1; ## Tag this session as new, ie no data in the DB exist
		$self->{'id_session'} = Sympa::Session->get_random();
		$self->{'email'} = 'nobody';
		$self->{'remote_addr'} = $ENV{'REMOTE_ADDR'};
		$self->{'date'} = time();
		$self->{'start_date'} = time();
		$self->{'hit'} = 1;
		$self->{'robot'} = $params{robot};
		$self->{'data'} = '';
	}

	return $self;
}

=item Sympa::Session->purge_old_sessions(%parameters)

Remove old sessions from a particular robot or from all robots. delay is a
parameter in seconds

=cut
    my $id_session;
    my $is_old_session = 0;

sub purge_old_sessions {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('info', '(%s)',$params{robot});

	croak "missing base parameter" unless $params{base};

	unless ($params{delay}) {
		Sympa::Log::Syslog::do_log('info', '%s exit with delay null',$params{robot});
		return;
	}
	unless ($params{anonymous_delay}) {
		Sympa::Log::Syslog::do_log('info', '%s exit with anonymous delay null',$params{robot});
		return;
	}

	my @clauses = (
		time() - $params{delay} . ' > date_session'
	);

	my @anonymous_clauses = (
		time() - $params{anonymous_delay} . ' > date_session',
		"email_session = 'nobody'",
		"hit_session = 1"
	);

	my @params;
    Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
	if (!$params{robot} eq '*') {
		push @clauses, 'robot_session = ?';
		push @anonymous_clauses, 'robot_session = ?';
		push @params, $params{robot};
	}

	my $count_query =
		"SELECT count(*) FROM session_table " .
		"WHERE " . join(' AND ', @clauses);
	my $anonymous_count_query =
		"SELECT count(*) FROM session_table "   .
		"WHERE " . join(' AND ', @anonymous_clauses);

	my $delete_query =
		"DELETE FROM session_table " .
		"WHERE " . join(' AND ', @clauses);
	my $anonymous_delete_query =
		"DELETE FROM session_table " .
		"WHERE " . join(' AND ', @anonymous_clauses);

	my $count_handle = $params{base}->get_query_handle($count_query);
	unless ($count_handle) {
		Sympa::Log::Syslog::do_log('err','Unable to count old session for robot %s',$params{robot});
		return undef;
	}
	$count_handle->execute(@params);

	my $total = $count_handle->fetchrow();
	if ($total == 0) {
		Sympa::Log::Syslog::do_log('debug','no sessions to expire');
	} else {
		my $rows = $params{base}->execute_query($delete_query);
		unless ($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to purge old sessions for robot %s', $params{robot});
			return undef;
		}
	}

	my $anonymous_count_handle =
		$params{base}->get_query_handle($anonymous_count_query);
	unless ($anonymous_count_handle) {
		Sympa::Log::Syslog::do_log('err','Unable to count anonymous sessions for robot %s', $params{robot});
		return undef;
	}
	$anonymous_count_handle->execute(@params);

	my $anonymous_total = $anonymous_count_handle->fetchrow();
	if ($anonymous_total == 0) {
		Sympa::Log::Syslog::do_log('debug','no anonymous sessions to expire');
	} else {
		my $anonymous_rows =
			$params{base}->execute_query($anonymous_delete_query);
		unless ($anonymous_rows) {
			Sympa::Log::Syslog::do_log('err','Unable to purge anonymous sessions for robot %s',$params{robot});
			return undef;
		}
	}

	return $total + $anonymous_total;
}

=item Sympa::Session->purge_old_tickets(%parameters)
    Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
Remove old one_time_ticket from a particular robot or from all robots. delay is a parameter in seconds

=cut

sub purge_old_tickets {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('info', '(%s)',$params{robot});

	croak "missing base parameter" unless $params{base};

	unless ($params{delay}) {
		Sympa::Log::Syslog::do_log('info', '%s exit with delay null',$params{robot});
		return;
	}

	my @clauses = (
		time() - $params{delay} . ' < date_one_time_ticket'
	);
	my @params;
    $self->{'refresh_date'} = $time;
    $self->{'remote_addr'} = $remote_addr;

	if (!$params{robot} eq '*') {
		push @clauses, 'robot_one_time_ticket = ?';
		push @params, $params{robot};
	}

	my $count_query =
		"SELECT count(*) FROM one_time_ticket_table " .
		"WHERE " . join(" AND ", @clauses);
	my $delete_query =
		"DELETE FROM one_time_ticket_table " .
		"WHERE " . join(" AND ", @clauses);

	my $count_handle = $params{base}->get_query_handle($count_query);
	unless ($count_handle) {
		Sympa::Log::Syslog::do_log('err','Unable to count old one time tickets for robot %s',$params{robot});
		return undef;
	}
	$count_handle->execute(@params);

	my $total = $count_handle->fetchrow();
	if ($total == 0) {
		Sympa::Log::Syslog::do_log('debug','no tickets to expire');
	} else {
		my $rows = $params{base}->execute_query(
			$delete_query, @params
		);
		unless ($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to delete expired one time tickets for robot %s',$params{robot});
			return undef;
		}
	}
	return $total;
}

=item Sympa::Session->list_sessions($delay, $robot, $connected_only)
    Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
    my $robot = Sympa::Robot::clean_robot(shift, 1);

List sessions for $robot where last access is newer then $delay. List is
limited to connected users if $connected_only

=cut

sub list_sessions {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('debug',
		'(%s,%s,%s)',$params{delay},$params{robot},$params{connected_only});

	my @sessions;
	my @clauses;
	my @params;

	if (!$params{robot} eq '*') {
		push @clauses, 'robot_session = ?';
		push @params, $params{robot};
	}

	if ($params{delay}) {
		push @clauses, time() - $params{delay} . ' < date_session';
	}

	if ($params{connected_only}) {
		push @clauses,  "email_session != 'nobody'";
	}

	my $query =
		"SELECT "                       .
			"remote_addr_session, " .
			"email_session, "       .
			"robot_session, "       .
			"date_session, "        .
			"start_date_session, "  .
			"hit_session "          .
		"FROM session_table "           .
		"WHERE " . join(" AND ", @clauses);
	Sympa::Log::Syslog::do_log('debug', 'statement = %s',$query);

	my $sth = $params{base}->get_query_handle($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to get the list of sessions for robot %s',$params{robot});
		return undef;
	}
	$sth->execute(@params);

	while (my $session = ($sth->fetchrow_hashref('NAME_lc'))) {

		$session->{'formated_date'} = Sympa::Language::gettext_strftime("%d %b %y  %H:%M", localtime($session->{'date_session'}));
		$session->{'formated_start_date'} = Sympa::Language::gettext_strftime("%d %b %y  %H:%M", localtime($session->{'start_date_session'}));

		push @sessions, $session;
	}

	return \@sessions;
}

=item Sympa::Session->get_session_cookie($http_cookie)

Generic function to get a cookie value.
    Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
    my $robot = Sympa::Robot::clean_robot(shift, 1);

=cut

sub get_session_cookie {
	my ($class, $http_cookie) = @_;

	if ($http_cookie =~/\S+/g) {
		my %cookies = parse CGI::Cookie($http_cookie);
		foreach (keys %cookies) {
			my $cookie = $cookies{$_};
			next unless ($cookie->name eq 'sympa_session');
			return ($cookie->value);
		}
	}

	return (undef);
}

=item Sympa::Session->get_random()

=cut

sub get_random {
	Sympa::Log::Syslog::do_log('debug', '');
	my $random = int(rand(10**7)).int(rand(10**7)); ## Concatenates 2 integers for a better entropy
	$random =~ s/^0(\.|\,)//;
	return ($random)
}

=back

=head1 INSTANCE METHODS

=over
    my $time = time;

=item $session->load($cookie)

FIXME.

=cut

sub load {
	my ($self, $cookie) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s)', $cookie);
	$session->{'formated_date'} =
	    Sympa::Language::gettext_strftime("%d %b %y  %H:%M", localtime($session->{'date_session'}));
	$session->{'formated_start_date'} =
	    Sympa::Language::gettext_strftime ("%d %b %y  %H:%M", localtime($session->{'start_date_session'}));

	unless ($cookie) {
		Sympa::Log::Syslog::do_log('err', 'internal error, called with undef id_session');
		return undef;
	}

    ## Load existing session.
    if ($cookie and $cookie =~ /^\d{,16}$/) {
		## Compatibility: session by older releases of Sympa.
		$id_session = $cookie;
		$is_old_session = 1;

		## Session by older releases of Sympa doesn't have refresh_date.
		my $sth = $self->{base}->get_query_handle(
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
	);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to load session %s', $cookie);
		return undef;
	}
	$sth->execute($cookie);
    } else {
		$id_session = decrypt_session_id($cookie);
		unless ($id_session) {
			Sympa::Log::Syslog::do_log('err', 'internal error, undef id_session');
			return 'not_found';
		}

		## Cookie may contain current or previous session ID.
		unless ($sth = $self->{base}->get_query_handle(
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
		)) {
			Sympa::Log::Syslog::do_log('err', 'Unable to load session %s', $id_session);
			return undef;
		}
    }

	my $session = undef;
	my $new_session = undef;
	my $counter = 0;
	while ($new_session = $sth->fetchrow_hashref('NAME_lc')) {
		if ( $counter > 0){
			Sympa::Log::Syslog::do_log('err',"The SQL statement did return more than one session. Is this a bug coming from dbi or mysql?");
			$session->{'email'} = '';
			last;
		}
		$session = $new_session;
		$counter ++;
	}

	unless ($session) {
		return 'not_found';
	}

    ## Compatibility: Upgrade session by older releases of Sympa.
    if ($is_old_session) {
	$sth = $self->{base}->execute_query(
	    q{UPDATE session_table
	      SET prev_id_session = id_session
	      WHERE id_session = ? AND prev_id_session IS NULL AND
		    refresh_date_session IS NULL},
	    $id_session
	);
    }

	my %datas= Sympa::Tools::Data::string_2_hash($session->{'data'});
	foreach my $key (keys %datas) {$self->{$key} = $datas{$key};}

	$self->{'id_session'} = $session->{'id_session'};
	$self->{'date'} = $session->{'date'};
	$self->{'start_date'} = $session->{'start_date'};
	$self->{'hit'} = $session->{'hit'} +1;
	$self->{'remote_addr'} = $session->{'remote_addr'};
	$self->{'robot'} = $session->{'robot'};
	$self->{'email'} = $session->{'email'};

	return ($self);
}

=item $session->store()

Store the session information in the database

=cut

sub store {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug', '');

	return undef unless ($self->{'id_session'});
	return if ($self->{'is_a_crawler'}); # do not create a session in session table for crawlers;
	return if ($self->{'passive_session'}); # do not create a session in session table for action such as RSS or CSS or wsdlthat do not require this sophistication;

	my %hash;
	foreach my $var (keys %$self ) {
		next if ($session_hard_attributes{$var});
		next unless ($var);
		$hash{$var} = $self->{$var};
	}
	my $data_string = Sympa::Tools::Data::hash_2_string (\%hash);

	## If this is a new session, then perform an INSERT
	if ($self->{'new_session'}) {
		## Store the new session ID in the DB
		my $rows = $self->{base}->execute_query(
	    q{INSERT INTO session_table
	      (id_session, prev_id_session,
	       date_session, refresh_date_session,
	       remote_addr_session, robot_session,
	       email_session, start_date_session, hit_session,
	       data_session)
	      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
	    $self->{'id_session'}, $self->{'id_session'},
	    $time, $time,
	    $ENV{'REMOTE_ADDR'}, $self->{'robot'}->name,
	    $self->{'email'}, $self->{'start_date'}, $self->{'hit'},
	    $data_string
		);
		unless($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to add new session %s informations in database', $self->{'id_session'});
			return undef;
		}
	$self->{'prev_id'} = $self->{'id_session'};
		## If the session already exists in DB, then perform an UPDATE
	} else {
	## Cookie may contain previous session ID.
	my $sth = $self->{base}->get_query_handle(
	    q{SELECT id_session
	      FROM session_table
	      WHERE robot_session = ? AND prev_id_session = ?},
	    $self->{'robot'}->name, $self->{'id_session'}
	);
	unless ($sth) {
	    Sympa::Log::Syslog::do_log('err',
		'Unable to update session information in database');
	    return undef;
	}
	if ($sth->rows) {
	    my $new_id = $sth->fetchrow;
	    $sth->finish;
	    if ($new_id) {
		$self->{'prev_id'} = $self->{'id_session'};
		$self->{'id_session'} = $new_id;
	    }
	}

		## Update the new session in the DB
		my $rows = $self->{base}->execute_query(
	    q{UPDATE session_table
	      SET date_session = ?, remote_addr_session = ?,
		  robot_session = ?, email_session = ?,
		  start_date_session = ?, hit_session = ?, data_session = ?
	      WHERE robot_session = ? AND
		    (id_session = ? AND prev_id_session IS NOT NULL OR
		     prev_id_session = ?)},
	    $time, $ENV{'REMOTE_ADDR'},
	    $self->{'robot'}->name, $self->{'email'},
	    $self->{'start_date'}, $self->{'hit'}, $data_string,
	    $self->{'robot'}->name,
	    $self->{'id_session'},
	    $self->{'id_session'}
		);
		unless ($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to update session %s information in database', $self->{'id_session'});
			return undef;
		}
	}

	return 1;
}

=item $session->renew()

Renew the session ID.

=cut

sub renew {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug', 'id_session=(%s)',$self->{'id_session'});

	return undef unless ($self->{'id_session'});
	return if ($self->{'is_a_crawler'}); # do not create a session in session table for crawlers;
	return if ($self->{'passive_session'}); # do not create a session in session table for action such as RSS or CSS or wsdlthat do not require this sophistication;

	my %hash;
	foreach my $var (keys %$self ) {
		next if ($session_hard_attributes{$var});
		next unless ($var);
		$hash{$var} = $self->{$var};
	}

    my $data_string = Sympa::Tools::Data::hash_2_string(\%hash);

    my $sth;
    ## Cookie may contain previous session ID.
    $sth = $self->{base}->get_query_handle(
	q{SELECT id_session
	  FROM session_table
	  WHERE robot_session = ? AND prev_id_session = ?},
	$self->{'robot'}->name, $self->{'id_session'}
    );
    unless ($sth) {
	Sympa::Log::Syslog::do_log('err',
	    'Unable to update session information in database');
	return undef;
    }
    if ($sth->rows) {
	my $new_id = $sth->fetchrow;
	$sth->finish;
	 if ($new_id) {
	     $self->{'prev_id'} = $self->{'id_session'};
	     $self->{'id_session'} = $new_id;
	 }
    }

	## Renew the session ID in order to prevent session hijacking
	my $new_id = Sympa::Session->get_random();
    ## Do refresh the session ID when remote address was changed or refresh
    ## interval was past.  Conditions also are checked by SQL so that
    ## simultaneous processes will be prevented renewing cookie.
    my $time = time;
    my $remote_addr = $ENV{'REMOTE_ADDR'};
    my $refresh_term;
    if (Sympa::Site->cookie_refresh == 0) {
	$refresh_term = $time;
    } else {
	my $cookie_refresh = Sympa::Site->cookie_refresh;
	$refresh_term =
	    int($time - $cookie_refresh * 0.25 - rand($cookie_refresh * 0.5));
    }
    unless ($self->{'remote_addr'} ne $remote_addr or
	$self->{'refresh_date'} <= $refresh_term) {
	return 0;
    }

    ## First insert DB entry with new session ID,
    $sth = $self->{base}->execute_query(
	q{INSERT INTO session_table
	  (id_session, prev_id_session,
	   start_date_session, date_session, refresh_date_session,
	   remote_addr_session, robot_session, email_session,
	   hit_session, data_session)
	  SELECT ?, id_session,
		 start_date_session, date_session, ?,
		 ?, robot_session, email_session,
		 hit_session, data_session
	  FROM session_table
	  WHERE robot_session = ? AND
		(id_session = ? AND prev_id_session IS NOT NULL OR
		 prev_id_session = ?) AND
		(remote_addr_session <> ? OR refresh_date_session <= ?)},
	$new_id,
	$time,
	$remote_addr,
	$self->{'robot'}->name,
	$self->{'id_session'},
	$self->{'id_session'},
	$remote_addr, $refresh_term
    );
    unless ($sth) {
	Sympa::Log::Syslog::do_log('err', 'Unable to renew session ID for session %s',
	    $self->{'id_session'});
	return undef;
    }
    unless ($sth->rows) {
	return 0;
    }
    ## Keep previous ID to prevent crosstalk, clearing grand-parent ID.
    $self->{base}->execute_query(
	q{UPDATE session_table
	  SET prev_id_session = NULL
	  WHERE robot_session = ? AND id_session = ?},
	$self->{'robot'}->name, $self->{'id_session'}
    );
    ## Remove record of grand-parent ID.
    $self->{base}->execute_query(
	 q{DELETE FROM session_table
	   WHERE id_session = ? AND prev_id_session IS NULL},
	 $self->{'prev_id'}
    );

    ## Renew the session ID in order to prevent session hijacking
    Sympa::Log::Syslog::do_log('info',
	'[robot %s] [session %s] [client %s]%s new session %s',
	$self->{'robot'}->name, $self->{'id_session'}, $remote_addr,
	($self->{'email'} ? sprintf(' [user %s]', $self->{'email'}) : ''),
	$new_id
    );
    $self->{'prev_id'} = $self->{'id_session'};
    $self->{'id_session'} = $new_id;
    $self->{'refresh_date'} = $time;
    $self->{'remote_addr'} = $remote_addr;

	return 1;
}
# Build an HTTP cookie value to be sent to a SOAP client
sub soap_cookie2 {
    my ($session_id, $http_domain, $expire) = @_;
    my $cookie;
    my $value;

=item $self->set_cookie($http_domain, $expires,$use_ssl)

Generic method to set a cookie

=cut

sub set_cookie {
	my ($self, $http_domain, $expires,$use_ssl) = @_;
	Sympa::Log::Syslog::do_log('debug','%s,%s,secure= %s',$http_domain, $expires,$use_ssl );

	my $expiration;
	if ($expires =~ /now/i) {
		## 10 years ago
		$expiration = '-10y';
	} else {
		$expiration = '+'.$expires.'m';
	}

	if ($http_domain eq 'localhost') {
		$http_domain="";
	}

	my $cookie;
	if ($expires =~ /session/i) {
		$cookie = CGI::Cookie->new(-name    => 'sympa_session',
			-value   => $self->{'id_session'},
			-domain  => $http_domain,
			-path    => '/',
			-secure => $use_ssl,
			-httponly => 1
		);
	} else {
		$cookie = CGI::Cookie->new(-name    => 'sympa_session',
			-value   => $self->{'id_session'},
			-expires => $expiration,
			-domain  => $http_domain,
			-path    => '/',
			-secure => $use_ssl,
			-httponly => 1
		);
	}

	## Send cookie to the client
	printf "Set-Cookie: %s\n", $cookie->as_string();
	return 1;
}

=item $session->as_hashref()

Return the session object content, as a hashref

=cut

sub as_hashref {
	my ($self) = @_;

	my $data;

	foreach my $key (keys %{$self}) {
		$data->{$key} = $self->{$key};
	}

	return $data;
}

=item $session->is_anonymous()

Return a true value if the session object corresponds to an anonymous session.

=cut

## Return 1 if the Session object corresponds to an anonymous session.
sub is_anonymous {
    my $self = shift;
    if($self->{'email'} eq 'nobody' || $self->{'email'} eq '') {
	return 1;
    }else{
	return 0;
    }
}

## Generate cookie from session ID.
sub encrypt_session_id {
    my $id_session = shift;

    return $id_session unless Sympa::Site->cookie;
    my $cipher = Sympa::Tools::Password::ciphersaber_installed();
    return $id_session unless $cipher;

    my $id_session_bin =
	pack 'nN', ($id_session >> 32), $id_session % (1 << 32);
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
    my ($id_session_hi, $id_session_lo) =
	unpack 'nN', $cipher->decrypt($cookie_bin);

    return ($id_session_hi << 32) + $id_session_lo;
}

## Get unique ID
sub get_id {
    my $self = shift;
    return '' unless $self->{'id_session'} and $self->{'robot'};
    return sprintf '%s@%s', $self->{'id_session'}, $self->{'robot'}->name;
}

=item $session->is_a_crawler()

Return a true value if the session object corresponds to a crawler, according to the user agent.

=cut

sub is_a_crawler {
	my ($self) = @_;

	return $self->{'is_a_crawler'};
}

=back

=cut

1;
