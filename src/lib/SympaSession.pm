# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014 GIP RENATER
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


package SympaSession;

use strict ;
use warnings;
use CGI::Cookie;
use Time::Local;

use Sympa::Language;
use Log;
use Conf;

# this structure is used to define which session attributes are stored in a
# dedicated database col where others are compiled in col 'data_session'
my %session_hard_attributes = ('id_session' => 1, 
			       'prev_id' => 1,
			       'date' => 1, 
			       'refresh_date' => 1,
			       'remote_addr'  => 1,
			       'robot'  => 1,
			       'email' => 1, 
			       'start_date' => 1, 
			       'hit' => 1,
			       'new_session' => 1,
			      );


sub new {
    my $pkg = shift; 
    my $robot = shift;
    my $context = shift;

    my $cookie = $context->{'cookie'};
    my $action = $context->{'action'};
    my $rss = $context->{'rss'};
    my $ajax =  $context->{'ajax'};

    &Log::do_log('debug', 'SympaSession::new(%s,%s,%s)', $robot,$cookie,$action);
    my $self = {'robot' => $robot}; # set current robot
    bless $self, $pkg;
    
    unless ($robot) {
	&Log::do_log('err', 'Missing robot parameter, cannot create session object') ;
	return undef;
    }

#   passive_session are session not stored in the database, they are used for crawler bots and action such as css, wsdl, ajax and rss
    
    if (&tools::is_a_crawler($robot,{'user_agent_string' => $ENV{'HTTP_USER_AGENT'}})) {
	$self->{'is_a_crawler'} = 1;
	$self->{'passive_session'} = 1;
    }
    $self->{'passive_session'} = 1 if ($rss||$action eq 'wsdl'||$action eq 'css');

    # if a session cookie exist, try to restore an existing session, don't
    # store sessions from bots
    if (($cookie)&&($self->{'passive_session'} != 1)){
	my $status ;
	$status = $self->load($cookie);
	unless (defined $status) {
	    return undef;
	}
	if ($status eq 'not_found') {
	    &Log::do_log('info',"SympaSession::new ignoring unknown session cookie '$cookie'" ); # start a new session (may ne a fake cookie)
	    return (new SympaSession ($robot));
	}
    }else{
	# create a new session context
	$self->{'new_session'} = 1; ## Tag this session as new, ie no data in the DB exist
	$self->{'id_session'} = &get_random();
	$self->{'email'} = 'nobody';
	$self->{'remote_addr'} = $ENV{'REMOTE_ADDR'};
	$self->{'date'} = $self->{'refresh_date'} = $self->{'start_date'} =
	    time;
	$self->{'hit'} = 1;
	$self->{'data'} = '';
    }
    return $self;
}

sub load {
    my $self = shift;
    my $cookie = shift;
    Log::do_log('debug', '(%s)', $cookie);

    unless ($cookie) {
	Log::do_log('err',
	    'SympaSession::load() : internal error, SympaSession::load called with undef id_session');
	return undef;
    }

    my $sth;
    my $statement;
    my $id_session;
    my $is_old_session = 0;

    ## Load existing session.
    if ($cookie and $cookie =~ /^\d{,16}$/) {
	## Compatibility: session by older releases of Sympa.
	$id_session = $cookie;
	$is_old_session = 1;

	## Session by older releases of Sympa doesn't have refresh_date.
	unless ($sth = SDM::do_prepared_query(
	    q{SELECT id_session AS id_session, id_session AS prev_id,
		     date_session AS "date",
		     remote_addr_session AS remote_addr,
		     email_session AS email,
		     data_session AS data, hit_session AS hit,
		     start_date_session AS start_date,
		     date_session AS refresh_date
	      FROM session_table
	      WHERE id_session = ? AND
		    refresh_date_session IS NULL},
	    $id_session
	)) {
	    Log::do_log('err', 'Unable to load session %s', $id_session);
	    return undef;
	}    
    } else {
	$id_session = decrypt_session_id($cookie);
	unless ($id_session) {
	    Log::do_log('err',
		'SympaSession::load() : internal error, SympaSession::load called with undef id_session');
	    return 'not_found';
	}

	## Cookie may contain current or previous session ID.
	unless ($sth = SDM::do_prepared_query(
	    q{SELECT id_session AS id_session, prev_id_session AS prev_id,
		     date_session AS "date",
		     remote_addr_session AS remote_addr,
		     email_session AS email,
		     data_session AS data, hit_session AS hit,
		     start_date_session AS start_date,
		     refresh_date_session AS refresh_date
	      FROM session_table
	      WHERE id_session = ? AND prev_id_session IS NOT NULL OR
		    prev_id_session = ?},
	    $id_session, $id_session)) {
	    Log::do_log('err', 'Unable to load session %s', $id_session);
	    return undef;
	}    
    }

    my $session = undef;
    my $new_session = undef;
    my $counter = 0;
    while ($new_session = $sth->fetchrow_hashref('NAME_lc')) {
	if ( $counter > 0){
	    &Log::do_log('err',"The SQL statement did return more than one session. Is this a bug coming from dbi or mysql?");
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
	SDM::do_prepared_query(
	    q{UPDATE session_table
	      SET prev_id_session = id_session
	      WHERE id_session = ? AND prev_id_session IS NULL AND
		    refresh_date_session IS NULL},
	    $id_session
	);
    }

    my %datas= &tools::string_2_hash($session->{'data'});

    ## canonicalize lang if possible.
    $datas{'lang'} =
	Sympa::Language::canonic_lang($datas{'lang'}) || $datas{'lang'}
	if $datas{'lang'};

    foreach my $key (keys %datas) {$self->{$key} = $datas{$key};} 

    $self->{'id_session'} = $session->{'id_session'};
    $self->{'prev_id'} = $session->{'prev_id'};
    $self->{'date'} = $session->{'date'};
    $self->{'refresh_date'} = $session->{'refresh_date'};
    $self->{'start_date'} = $session->{'start_date'};
    $self->{'hit'} = $session->{'hit'} +1 ;
    $self->{'remote_addr'} = $session->{'remote_addr'};
    $self->{'email'} = $session->{'email'};    

    return ($self);
}

## This method will both store the session information in the database
sub store {
    my $self = shift;
    &Log::do_log('debug', '');

    return undef unless ($self->{'id_session'});
    return if ($self->{'is_a_crawler'}); # do not create a session in session table for crawlers; 
    return if ($self->{'passive_session'}); # do not create a session in session table for action such as RSS or CSS or wsdlthat do not require this sophistication; 

    my %hash ;    
    foreach my $var (keys %$self ) {
	next if ($session_hard_attributes{$var});
	next unless ($var);
	$hash{$var} = $self->{$var};
    }
    my $data_string = &tools::hash_2_string (\%hash);
    my $time = time;

    ## If this is a new session, then perform an INSERT
    if ($self->{'new_session'}) {

      ## Store the new session ID in the DB
	## Previous session ID is set to be same as new session ID.
	unless (SDM::do_prepared_query(
	    q{INSERT INTO session_table
	      (id_session, prev_id_session,
	       date_session, refresh_date_session,
	       remote_addr_session, robot_session,
	       email_session, start_date_session, hit_session,
	       data_session)
	      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
	    $self->{'id_session'}, $self->{'id_session'},
	    $time, $time,
	    $ENV{'REMOTE_ADDR'}, $self->{'robot'},
	    $self->{'email'}, $self->{'start_date'}, $self->{'hit'},
	    $data_string
	)) {
	    Log::do_log('err',
		'Unable to add new information for session %s in database',
		$self->{'id_session'}
	    );
	    return undef;
	}

	$self->{'prev_id'} = $self->{'id_session'};
    } else {
      ## If the session already exists in DB, then perform an UPDATE

	## Cookie may contain previous session ID.
	my $sth = SDM::do_prepared_query(
	    q{SELECT id_session
	      FROM session_table
	      WHERE prev_id_session = ?},
	    $self->{'id_session'});
	unless ($sth) {
	    Log::do_log('err',
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
      unless (SDM::do_prepared_query(
	    q{UPDATE session_table
	      SET date_session = ?, remote_addr_session = ?,
		  robot_session = ?, email_session = ?,
		  start_date_session = ?, hit_session = ?, data_session = ?
	      WHERE id_session = ? AND prev_id_session IS NOT NULL OR
		    prev_id_session = ?},
	    $time, $ENV{'REMOTE_ADDR'},
	    $self->{'robot'}, $self->{'email'},
	    $self->{'start_date'}, $self->{'hit'}, $data_string,
	    $self->{'id_session'},
	    $self->{'id_session'}
    )) {
	Log::do_log('err',
	    'Unable to update information for session %s in database',
	    $self->{'id_session'}
	);
	return undef;
      }
    }

    return 1;
}

## This method will renew the session ID 
sub renew {
    my $self = shift;
    &Log::do_log('debug', 'id_session=(%s)',$self->{'id_session'});

    return undef unless ($self->{'id_session'});
    return if ($self->{'is_a_crawler'}); # do not create a session in session table for crawlers; 
    return if ($self->{'passive_session'}); # do not create a session in session table for action such as RSS or CSS or wsdlthat do not require this sophistication; 

    my %hash ;    
    foreach my $var (keys %$self ) {
	next if ($session_hard_attributes{$var});
	next unless ($var);
	$hash{$var} = $self->{$var};
    }
    my $data_string = &tools::hash_2_string (\%hash);

    my $sth;
    ## Cookie may contain previous session ID.
    $sth = SDM::do_prepared_query(
	q{SELECT id_session
	  FROM session_table
	  WHERE prev_id_session = ?},
	$self->{'id_session'}
    );
    unless ($sth) {
	Log::do_log('err',
	    'Unable to update information for session %s in database',
	    $self->{'id_session'}
	);
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
    my $new_id = &get_random();

    ## Do refresh the session ID when remote address was changed or refresh
    ## interval was past.  Conditions also are checked by SQL so that
    ## simultaneous processes will be prevented renewing cookie.
    my $time = time;
    my $remote_addr = $ENV{'REMOTE_ADDR'};
    my $refresh_term;
    if ($Conf::Conf{'cookie_refresh'} == 0) {
	$refresh_term = $time;
    } else {
	my $cookie_refresh = $Conf::Conf{'cookie_refresh'};
	$refresh_term =
	    int($time - $cookie_refresh * 0.25 - rand($cookie_refresh * 0.5));
    }
    unless ($self->{'remote_addr'} ne $remote_addr or
	$self->{'refresh_date'} <= $refresh_term) {
	return 0;
    }

    ## First insert DB entry with new session ID,
    $sth = SDM::do_query(
	q{INSERT INTO session_table
	  (id_session, prev_id_session,
	   start_date_session, date_session, refresh_date_session,
	   remote_addr_session, robot_session, email_session,
	   hit_session, data_session)
	  SELECT %s, id_session,
		 start_date_session, date_session, %d,
		 %s, %s, email_session,
		 hit_session, data_session
	  FROM session_table
	  WHERE (id_session = %s AND prev_id_session IS NOT NULL OR
		 prev_id_session = %s) AND
		(remote_addr_session <> %s OR refresh_date_session <= %d)},
	SDM::quote($new_id),
	$time,
	SDM::quote($remote_addr),
	SDM::quote($self->{'robot'}),
	SDM::quote($self->{'id_session'}),
	SDM::quote($self->{'id_session'}),
	SDM::quote($remote_addr), $refresh_term
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
    SDM::do_prepared_query(
	q{UPDATE session_table
	  SET prev_id_session = NULL
	  WHERE id_session = ?},
	$self->{'id_session'}
    );
    ## Remove record of grand-parent ID.
    SDM::do_prepared_query(
        q{DELETE FROM session_table
          WHERE id_session = ? AND prev_id_session IS NULL},
        $self->{'prev_id'}
    );

    ## Renew the session ID in order to prevent session hijacking
    Log::do_log('info',
	'[robot %s] [session %s] [client %s]%s new session %s',
	$self->{'robot'}, $self->{'id_session'}, $remote_addr,
	($self->{'email'} ? sprintf(' [user %s]', $self->{'email'}) : ''),
	$new_id
    );
    $self->{'prev_id'} = $self->{'id_session'};
    $self->{'id_session'} = $new_id;
    $self->{'refresh_date'} = $time;
    $self->{'remote_addr'} = $remote_addr;

    return 1;
}

## remove old sessions from a particular robot or from all robots.
## delay is a parameter in seconds
sub purge_old_sessions {

    my $robot = shift;

    &Log::do_log('info', 'SympaSession::purge_old_sessions(%s,%s)',$robot);

    my $delay = &tools::duration_conv($Conf{'session_table_ttl'}) ; 
    my $anonymous_delay = &tools::duration_conv($Conf{'anonymous_session_table_ttl'}) ; 

    unless ($delay) { &Log::do_log('info', 'SympaSession::purge_old_session(%s) exit with delay null',$robot); return;}
    unless ($anonymous_delay) { &Log::do_log('info', 'SympaSession::purge_old_session(%s) exit with anonymous delay null',$robot); return;}

    my @sessions ;
    my  $sth;

    my $robot_condition = sprintf "robot_session = %s", &SDM::quote($robot) unless (($robot eq '*')||($robot));

    my $delay_condition = time-$delay.' > date_session' if ($delay);
    my $anonymous_delay_condition = time-$anonymous_delay.' > date_session' if ($anonymous_delay);

    my $and = ' AND ' if (($delay_condition) && ($robot_condition));
    my $anonymous_and = ' AND ' if (($anonymous_delay_condition) && ($robot_condition));

    my $count_statement = sprintf
	q{SELECT count(*) FROM session_table WHERE %s %s %s},
	$robot_condition, $and, $delay_condition;
    my $anonymous_count_statement = sprintf
	q{SELECT count(*) FROM session_table
	  WHERE %s %s %s AND email_session = 'nobody' AND hit_session = '1'},
	$robot_condition, $anonymous_and, $anonymous_delay_condition;

    my $statement = sprintf
	q{DELETE FROM session_table WHERE %s %s %s},
	$robot_condition, $and, $delay_condition;
    my $anonymous_statement = sprintf
	q{DELETE FROM session_table
	  WHERE %s %s %s AND email_session = 'nobody' AND hit_session = '1'},
	$robot_condition, $anonymous_and, $anonymous_delay_condition;

    unless ($sth = &SDM::do_query($count_statement)) {
	&Log::do_log('err', 'Unable to count old session for robot %s', $robot);
	return undef;
    }
    
    my $total =  $sth->fetchrow;
    if ($total == 0) {
	&Log::do_log('debug','SympaSession::purge_old_sessions no sessions to expire');
    }else{
	unless ($sth = &SDM::do_query($statement)) {
	    &Log::do_log('err','Unable to purge old sessions for robot %s', $robot);
	    return undef;
	}
    }
    unless ($sth = &SDM::do_query($anonymous_count_statement)) {
	&Log::do_log('err','Unable to count anonymous sessions for robot %s', $robot);
	return undef;
    }
    my $anonymous_total =  $sth->fetchrow;
    if ($anonymous_total == 0) {
	&Log::do_log('debug','SympaSession::purge_old_sessions no anonymous sessions to expire');
	return $total ;
    }
    unless ($sth = &SDM::do_query($anonymous_statement)) {
	&Log::do_log('err','Unable to purge anonymous sessions for robot %s',$robot);
	return undef;
    }
    return $total+$anonymous_total;
}


## remove old one_time_ticket from a particular robot or from all robots. delay is a parameter in seconds
## 
sub purge_old_tickets {

    my $robot = shift;

    &Log::do_log('info', 'SympaSession::purge_old_tickets(%s,%s)',$robot);

    my $delay = &tools::duration_conv($Conf{'one_time_ticket_table_ttl'}) ; 

    unless ($delay) { &Log::do_log('info', 'SympaSession::purge_old_tickets(%s) exit with delay null',$robot); return;}

    my @tickets ;
    my  $sth;

    my $robot_condition = sprintf "robot_one_time_ticket = %s", &SDM::quote($robot) unless (($robot eq '*')||($robot));
    my $delay_condition = time-$delay.' > date_one_time_ticket' if ($delay);
    my $and = ' AND ' if (($delay_condition) && ($robot_condition));
    my $count_statement = sprintf "SELECT count(*) FROM one_time_ticket_table WHERE $robot_condition $and $delay_condition";
    my $statement = sprintf "DELETE FROM one_time_ticket_table WHERE $robot_condition $and $delay_condition";

    unless ($sth = &SDM::do_query($count_statement)) {
	&Log::do_log('err','Unable to count old one time tickets for robot %s',$robot);
	return undef;
    }
    
    my $total =  $sth->fetchrow;
    if ($total == 0) {
	&Log::do_log('debug','SympaSession::purge_old_tickets no tickets to expire');
    }else{
	unless ($sth = &SDM::do_query($statement)) {
	    &Log::do_log('err','Unable to delete expired one time tickets for robot %s',$robot);
	    return undef;
	}
    }
    return $total;
}

# list sessions for $robot where last access is newer then $delay. List is limited to connected users if $connected_only
sub list_sessions {
    my $delay = shift;
    my $robot = shift;
    my $connected_only = shift;

    &Log::do_log('debug', 'SympaSession::list_session(%s,%s,%s)',$delay,$robot,$connected_only);

    my @sessions ;
    my $sth;

    my $condition = sprintf "robot_session = %s", &SDM::quote($robot) unless ($robot eq '*');
    my $condition2 = time-$delay.' < date_session ' if ($delay);
    my $and = ' AND ' if (($condition) && ($condition2));
    $condition = $condition.$and.$condition2 ;

    my $condition3 =  " email_session <> 'nobody' " if ($connected_only eq 'on');
    my $and2 = ' AND '  if (($condition) && ($condition3));
    $condition = $condition.$and2.$condition3 ;

    $condition .= sprintf '%sprev_id_session IS NOT NULL',
	($condition ? ' AND ' : '');

    my $statement = sprintf
	q{SELECT remote_addr_session, email_session, robot_session,
		 date_session AS date_epoch,
		 start_date_session AS start_date_epoch, hit_session
	  FROM session_table
	  WHERE %s},
	$condition;
    &Log::do_log('debug', 'SympaSession::list_session() : statement = %s',$statement);

    unless ($sth = &SDM::do_query($statement)) {
	&Log::do_log('err','Unable to get the list of sessions for robot %s',$robot);
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


## Generic subroutine to set a cookie
## Set user $email cookie, ckecksum use $secret, expire=(now|session|#sec) domain=(localhost|<a domain>)
sub set_cookie {
    my ($self, $http_domain, $expires,$use_ssl) = @_ ;
    &Log::do_log('debug','Session::set_cookie(%s,%s,secure= %s)',$http_domain, $expires,$use_ssl );

    my $expiration;
    if ($expires =~ /now/i) {
	## 10 years ago
	$expiration = '-10y';
    }else{
	$expiration = '+'.$expires.'m';
    }

    if ($http_domain eq 'localhost') {
	$http_domain="";
    }

    my $value = encrypt_session_id($self->{'id_session'});

    my $cookie;
    if ($expires =~ /session/i) {
	$cookie = new CGI::Cookie (-name    => 'sympa_session',
				   -value   => $value,
				   -domain  => $http_domain,
				   -path    => '/',
				   -secure => $use_ssl,
				   -httponly => 1 
				   );
    }else {
	$cookie = new CGI::Cookie (-name    => 'sympa_session',
				   -value   => $value,
				   -expires => $expiration,
				   -domain  => $http_domain,
				   -path    => '/',
				   -secure => $use_ssl,
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
    $expire ||= 600; ## 10 minutes

    if ($http_domain eq 'localhost') {
	$cookie = CGI::Cookie->new(
	    -name => 'sympa_session',
	    -value => $value,
	    -path => '/',
	);
	$cookie->max_age(time + $expire); # needs CGI >= 3.51.
    } else {
	$cookie = CGI::Cookie->new(
	    -name => 'sympa_session',
	    -value => $value,
	    -domain => $http_domain,
	    -path => '/',
	);
	$cookie->max_age(time + $expire); # needs CGI >= 3.51.
    }

    ## Return the cookie value
    return $cookie->as_string;
}

sub get_random {
    ## Concatenates two integers for a better entropy.
    return sprintf '%07d%07d', int(rand(10**7)), int(rand(10**7));
}

## Return the session object content, as a hashref
sub as_hashref {
  my $self = shift;
  my $data;
  
  foreach my $key (keys %{$self}) {
    $data->{$key} = $self->{$key};
  }
  
  return $data;
}

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

    my $cipher = tools::ciphersaber_installed();
    unless ($cipher) {
	return "5e55$id_session";
    }
    return unpack 'H*', $cipher->encrypt(pack 'H*', $id_session);
}

## Get session ID from cookie.
sub decrypt_session_id {
    my $cookie = shift;

    return undef unless $cookie and $cookie =~ /\A(?:[0-9a-f]{2})+\z/;

    my $cipher = tools::ciphersaber_installed();
    unless ($cipher) {
	return undef unless $cookie =~ s/\A5e55//;
	return $cookie;
    }
    return unpack 'H*', $cipher->decrypt(pack 'H*', $cookie);
}

1;
