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

Sympa::Session - HTTP session object

=head1 DESCRIPTION

This class implements an HTTP session.

=cut

package Sympa::Session;

use strict ;

use CGI::Cookie;
use Digest::MD5;
use Time::Local;

use Sympa::Database;
use Sympa::Language;
use Sympa::Log::Syslog;
use Sympa::Tools::Data;

# this structure is used to define which session attributes are stored in a dedicated database col where others are compiled in col 'data_session'
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

=back

Return:

A new L<Sympa::Session> object, or I<undef>, if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	unless ($params{robot}) {
		Sympa::Log::Syslog::do_log('err', 'Missing robot parameter, cannot create session object') ;
		return undef;
	}

	my $cookie = $params{context}->{'cookie'};
	my $action = $params{context}->{'action'};
	my $rss = $params{context}->{'rss'};

	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s)', $params{robot},$cookie,$action);
	my $self={};
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
		my $status ;
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
		$self->{'date'} = time;
		$self->{'start_date'} = time;
		$self->{'hit'} = 1;
		$self->{'robot'} = $params{robot};
		$self->{'data'} = '';
	}

	return $self;
}

=item purge_old_sessions(%parameters)

Remove old sessions from a particular robot or from all robots. delay is a parameter in seconds

=cut

sub purge_old_sessions {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('info', '(%s)',$params{robot});

	unless ($params{delay}) {
		Sympa::Log::Syslog::do_log('info', '%s exit with delay null',$params{robot});
		return;
	}
	unless ($params{anonymous_delay}) {
		Sympa::Log::Syslog::do_log('info', '%s exit with anonymous delay null',$params{robot});
		return;
	}

	my $source = Sympa::Database::get_source();

	my @clauses = (
		time - $params{delay} . ' > date_session'
	);

	my @anonymous_clauses = (
		time - $params{anonymous_delay} . ' > date_session',
		"email_session = 'nobody'",
		"hit_session = 1"
	);

	my @params;

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

	my $count_handle = $source->get_query_handle($count_query);
	unless ($count_handle) {
		Sympa::Log::Syslog::do_log('err','Unable to count old session for robot %s',$params{robot});
		return undef;
	}
	$count_handle->execute(@params);

	my $total = $count_handle->fetchrow();
	if ($total == 0) {
		Sympa::Log::Syslog::do_log('debug','no sessions to expire');
	} else {
		my $rows = $source->do($delete_query);
		unless ($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to purge old sessions for robot %s', $params{robot});
			return undef;
		}
	}

	my $anonymous_count_handle = $source->get_query_handle($anonymous_count_query);
	unless ($anonymous_count_handle) {
		Sympa::Log::Syslog::do_log('err','Unable to count anonymous sessions for robot %s', $params{robot});
		return undef;
	}
	$anonymous_count_handle->execute(@params);

	my $anonymous_total = $anonymous_count_handle->fetchrow();
	if ($anonymous_total == 0) {
		Sympa::Log::Syslog::do_log('debug','no anonymous sessions to expire');
	} else {
		my $anonymous_rows = $source->do($anonymous_delete_query);
		unless ($anonymous_rows) {
			Sympa::Log::Syslog::do_log('err','Unable to purge anonymous sessions for robot %s',$params{robot});
			return undef;
		}
	}

	return $total + $anonymous_total;
}

=item Sympa::Session->purge_old_tickets(%parameters)

Remove old one_time_ticket from a particular robot or from all robots. delay is a parameter in seconds

=cut

sub purge_old_tickets {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('info', '(%s)',$params{robot});

	unless ($params{delay}) {
		Sympa::Log::Syslog::do_log('info', '%s exit with delay null',$params{robot});
		return;
	}

	my $source = Sympa::Database::get_source();

	my @clauses = (
		time - $params{delay} . ' < date_one_time_ticket'
	);
	my @params;

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

	my $count_handle = $source->get_query_handle($count_query);
	unless ($count_handle) {
		Sympa::Log::Syslog::do_log('err','Unable to count old one time tickets for robot %s',$params{robot});
		return undef;
	}
	$count_handle->execute(@params);

	my $total = $count_handle->fetchrow();
	if ($total == 0) {
		Sympa::Log::Syslog::do_log('debug','no tickets to expire');
	} else {
		my $rows = $source->do($delete_query, undef, @params);
		unless ($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to delete expired one time tickets for robot %s',$params{robot});
			return undef;
		}
	}
	return $total;
}

=item Sympa::Session->list_sessions($delay, $robot, $connected_only)

List sessions for $robot where last access is newer then $delay. List is limited to connected users if $connected_only

=cut

sub list_sessions {
	my ($class, $delay, $robot, $connected_only) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s)',$delay,$robot,$connected_only);

	my @sessions ;
	my $source = Sympa::Database::get_source();

	my @clauses;
	my @params;

	if (!$robot eq '*') {
		push @clauses, 'robot_session = ?';
		push @params, $robot;
	}

	if ($delay) {
		push @clauses, time - $delay . ' < date_session';
	}

	if ($connected_only eq 'on') {
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

	my $sth = $source->get_query_handle($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to get the list of sessions for robot %s',$robot);
		return undef;
	}
	$sth->execute(@params);

	while (my $session = ($sth->fetchrow_hashref('NAME_lc'))) {

		$session->{'formated_date'} = Sympa::Language::gettext_strftime ("%d %b %y  %H:%M", localtime($session->{'date_session'}));
		$session->{'formated_start_date'} = Sympa::Language::gettext_strftime ("%d %b %y  %H:%M", localtime($session->{'start_date_session'}));

		push @sessions, $session;
	}

	return \@sessions;
}

=item Sympa::Session->get_session_cookie($http_cookie)

Generic function to get a cookie value.

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

=item $session->load($cookie)

FIXME.

=cut

sub load {
	my ($self, $cookie) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s)', $cookie);

	unless ($cookie) {
		Sympa::Log::Syslog::do_log('err', 'internal error, called with undef id_session');
		return undef;
	}

	my $source = Sympa::Database::get_source();
	my $sth = $source->get_query_handle(
		"SELECT "                                      .
			"id_session AS id_session, "           .
			"date_session AS \"date\", "           .
			"remote_addr_session AS remote_addr, " .
			"robot_session AS robot, "             .
			"email_session AS email, "             .
			"data_session AS data, "               .
			"hit_session AS hit, "                 .
			"start_date_session AS start_date "    .
		"FROM session_table WHERE id_session = ?",
	);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to load session %s', $cookie);
		return undef;
	}
	$sth->execute($cookie);

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

	my %datas= Sympa::Tools::Data::string_2_hash($session->{'data'});
	foreach my $key (keys %datas) {$self->{$key} = $datas{$key};}

	$self->{'id_session'} = $session->{'id_session'};
	$self->{'date'} = $session->{'date'};
	$self->{'start_date'} = $session->{'start_date'};
	$self->{'hit'} = $session->{'hit'} +1 ;
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

	my %hash ;
	foreach my $var (keys %$self ) {
		next if ($session_hard_attributes{$var});
		next unless ($var);
		$hash{$var} = $self->{$var};
	}
	my $data_string = Sympa::Tools::Data::hash_2_string (\%hash);

	my $source = Sympa::Database::get_source();
## If this is a new session, then perform an INSERT
if ($self->{'new_session'}) {
	## Store the new session ID in the DB
	my $rows = $source->do(
		"INSERT INTO session_table ("   .
			"id_session, "          .
			"date_session, "        .
			"remote_addr_session, " .
			"robot_session, "       .
			"email_session, "       .
			"start_date_session, "  .
			"hit_session, "         .
			"data_session"          .
		") VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		undef,
		$self->{'id_session'},
		time,
		$ENV{'REMOTE_ADDR'},
		$self->{'robot'},
		$self->{'email'},
		$self->{'start_date'},
		$self->{'hit'},
		$data_string
	);
	unless($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to add new session %s informations in database', $self->{'id_session'});
		return undef;
	}
	## If the session already exists in DB, then perform an UPDATE
} else {
	## Update the new session in the DB
	my $rows = $source->do(
		"UPDATE session_table SET "       .
			"date_session=?, "        .
			"remote_addr_session=?, " .
			"robot_session=?, "       .
			"email_session=?,"        .
			"start_date_session=?, "  .
			"hit_session=?, "         .
			"data_session=? "         .
			"WHERE (id_session=?)",
		undef,
		time,
		$ENV{'REMOTE_ADDR'},
		$self->{'robot'},
		$self->{'email'},
		$self->{'start_date'},
		$self->{'hit'},
		$data_string,
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

	my %hash ;
	foreach my $var (keys %$self ) {
		next if ($session_hard_attributes{$var});
		next unless ($var);
		$hash{$var} = $self->{$var};
	}

	## Renew the session ID in order to prevent session hijacking
	my $new_id = Sympa::Session->get_random();

	## First remove the DB entry for the previous session ID
	my $source = Sympa::Database::get_source();
	my $rows = $source->do(
		"UPDATE session_table SET id_session=? WHERE (id_session=?)",
		undef,
		$new_id,
		$self->{'id_session'}
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to renew session ID for session %s',$self->{'id_session'});
		return undef;
	}

	## Renew the session ID in order to prevent session hijacking
	$self->{'id_session'} = $new_id;

	return 1;
}

=item $self->set_cookie($http_domain, $expires,$use_ssl)

Generic method to set a cookie

=cut

sub set_cookie {
	my ($self, $http_domain, $expires,$use_ssl) = @_ ;
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

sub is_anonymous {
	my ($self) = @_;

	if($self->{'email'} eq 'nobody' || $self->{'email'} eq '') {
		return 1;
	} else {
		return 0;
	}
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
