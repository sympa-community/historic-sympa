# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:et:sw=4:textwidth=78
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

Sympa::Auth - Web authentication functions

=head1 DESCRIPTION

This module provides web authentication functions.

=cut

package Sympa::Auth;

use strict;

use Digest::MD5;

use Sympa::Configuration;
use Sympa::Database;
use Sympa::Language;
use Sympa::List;
use Sympa::Log::Syslog;
use Sympa::Report;
use Sympa::Session;

=head1 FUNCTIONS

=over

=item password_fingerprint($pwd)

Return the password finger print (this proc allow futur replacement of md5 by
sha1 or ....)

=cut

sub password_fingerprint {
	my ($pwd) = @_;
	Sympa::Log::Syslog::do_log('debug', '');

	if(Sympa::Site->password_case eq 'insensitive') {
		return Digest::MD5::md5_hex(lc($pwd));
	} else {
		return Digest::MD5::md5_hex($pwd);
	}
}

=item check_auth($robot, $auth, $pwd)

Authentication via email or uid.

Parameters:

=over

=item string

=item string

user email or UID

=item string

password

=back

=cut

sub check_auth{
	my ($robot, $auth, $pwd) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s)', $auth);
	
	$robot = Sympa::Robot::clean_robot($robot);

	my ($canonic, $user);

	if( Sympa::Tools::valid_email($auth)) {
		return authentication($robot, $auth,$pwd);
	} else {
		## This is an UID
		foreach my $ldap (@{Sympa::Site->auth_services{$robot}}){
			# only ldap service are to be applied here
			next unless ($ldap->{'auth_type'} eq 'ldap');

			$canonic = ldap_authentication($robot, $ldap, $auth,$pwd,'uid_filter');
			last if ($canonic); ## Stop at first match
		}
		if ($canonic){

			unless($user = Sympa::List::get_global_user($canonic)){
				$user = {'email' => $canonic};
			}
			return {'user' => $user,
				'auth' => 'ldap',
				'alt_emails' => {$canonic => 'ldap'}
			};

		} else {
			Sympa::Report::reject_report_web('user','incorrect_passwd',{}) unless ($ENV{'SYMPA_SOAP'});
			Sympa::Log::Syslog::do_log('err', "Incorrect Ldap password");
			return undef;
		}
	}
}

=item may_use_sympa_native_auth($robot, $user_email)

This subroutine if Sympa may use its native authentication for a given user
It might not if no user_table paragraph is found in auth.conf or if the regexp
or negative_regexp exclude this user

Parameters:

=over

=item string

=item string

=back

Return value:

boolean

=cut

sub may_use_sympa_native_auth {
	my ($robot, $user_email) = @_;

	$robot = Sympa::Robot::clean_robot($robot);

	my $ok = 0;
	## check each auth.conf paragrpah
	foreach my $auth_service (@{Sympa::Site->auth_services{$robot}}){
		next unless ($auth_service->{'auth_type'} eq 'user_table');

		next if ($auth_service->{'regexp'} && ($user_email !~ /$auth_service->{'regexp'}/i));
		next if ($auth_service->{'negative_regexp'} && ($user_email =~ /$auth_service->{'negative_regexp'}/i));

		$ok = 1; last;
	}

	return $ok;
}

=item authentication($robot, $email, $pwd)

FIXME.

=cut

sub authentication {
	my ($robot, $email, $pwd) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s)', $email);

	$robot = Sympa::Robot::clean_robot($robot);

	my ($user,$canonic);

	unless ($user = Sympa::List::get_global_user($email)) {
		$user = {'email' => $email };
	}
	unless ($user->{'password'}) {
		$user->{'password'} = '';
	}

	if ($user->{'wrong_login_count'} > $robot->max_wrong_password){
		# too many wrong login attemp
		Sympa::List::update_global_user($email,{wrong_login_count => $user->{'wrong_login_count'}+1});
		Sympa::Report::reject_report_web('user','too_many_wrong_login',{}) unless ($ENV{'SYMPA_SOAP'});
		Sympa::Log::Syslog::do_log('err','login is blocked : too many wrong password submission for %s', $email);
		return undef;
	}
	foreach my $auth_service (@{Sympa::Site->auth_services{$robot}}){
		next if ($auth_service->{'auth_type'} eq 'authentication_info_url');
		next if ($email !~ /$auth_service->{'regexp'}/i);
		next if (($email =~ /$auth_service->{'negative_regexp'}/i)&&($auth_service->{'negative_regexp'}));

		## Only 'user_table' and 'ldap' backends will need that Sympa collects the user passwords
		## Other backends are Single Sign-On solutions
		if ($auth_service->{'auth_type'} eq 'user_table') {
			my $fingerprint = password_fingerprint ($pwd);

			if ($fingerprint eq $user->{'password'}) {
				Sympa::List::update_global_user($email,{wrong_login_count => 0});
				return {'user' => $user,
					'auth' => 'classic',
					'alt_emails' => {$email => 'classic'}
				};
			}
		} elsif($auth_service->{'auth_type'} eq 'ldap') {
			if ($canonic = ldap_authentication($robot, $auth_service, $email,$pwd,'email_filter')){
				unless($user = Sympa::List::get_global_user($canonic)){
					$user = {'email' => $canonic};
				}
				Sympa::List::update_global_user($canonic,{wrong_login_count => 0});
				return {'user' => $user,
					'auth' => 'ldap',
					'alt_emails' => {$email => 'ldap'}
				};
			}
		}
	}

	# increment wrong login count.
	Sympa::List::update_global_user($email,{wrong_login_count =>$user->{'wrong_login_count'}+1});

	Sympa::Report::reject_report_web('user','incorrect_passwd',{}) unless ($ENV{'SYMPA_SOAP'});
	Sympa::Log::Syslog::do_log('err','authentication: incorrect password for user %s', $email);

	return undef;
}

=item ldap_authentication($robot, $ldap, $auth, $pwd, $whichfilter)

FIXME.

=cut

sub ldap_authentication {
	my ($robot, $ldap, $auth, $pwd, $whichfilter) = @_;
	Sympa::Log::Syslog::do_log('debug2','(%s,%s,%s)', $auth,'****',$whichfilter);
	Sympa::Log::Syslog::do_log('debug3','Password used: %s',$pwd);

	$robot = Sympa::Robot::clean_robot($robot);

	my ($mesg, $ldap_passwd,$ldap_anonymous);

	unless (Sympa::Tools::get_filename('etc',{},'auth.conf', $robot, undef, Sympa::Site->etc)) {
		return undef;
	}

	## No LDAP entry is defined in auth.conf
	if ($#{Sympa::Site->auth_services{$robot}} < 0) {
		Sympa::Log::Syslog::do_log('notice', 'Skipping empty auth.conf');
		return undef;
	}

	# only ldap service are to be applied here
	return undef unless ($ldap->{'auth_type'} eq 'ldap');

	# skip ldap auth service if the an email address was provided
	# and this email address does not match the corresponding regexp
	return undef if ($auth =~ /@/ && $auth !~ /$ldap->{'regexp'}/i);

	my @alternative_conf = split(/,/,$ldap->{'alternative_email_attribute'});
	my $attrs = $ldap->{'email_attribute'};
	my $filter = $ldap->{'get_dn_by_uid_filter'} if($whichfilter eq 'uid_filter');
	$filter = $ldap->{'get_dn_by_email_filter'} if($whichfilter eq 'email_filter');
	$filter =~ s/\[sender\]/$auth/ig;

	## bind in order to have the user's DN
	my $params = Sympa::Tools::Data::dup_var($ldap);
	require Sympa::Datasource::LDAP;
	my $ds = Sympa::Datasource::LDAP->new($params);

	unless (defined $ds && ($ldap_anonymous = $ds->connect())) {
		Sympa::Log::Syslog::do_log('err',"Unable to connect to the LDAP server '%s'", $ldap->{'host'});
		return undef;
	}


	$mesg = $ldap_anonymous->search(base => $ldap->{'suffix'},
		filter => "$filter",
		scope => $ldap->{'scope'} ,
		timeout => $ldap->{'timeout'});

	if ($mesg->count() == 0) {
		Sympa::Log::Syslog::do_log('notice','No entry in the Ldap Directory Tree of %s for %s',$ldap->{'host'},$auth);
		$ds->disconnect();
		return undef;
	}

	my $refhash=$mesg->as_struct();
	my (@DN) = keys(%$refhash);
	$ds->disconnect();

	##  bind with the DN and the pwd

	## Duplicate structure first
	## Then set the bind_dn and password according to the current user
	$params = Sympa::Tools::Data::dup_var($ldap);
	$params->{'ldap_bind_dn'} = $DN[0];
	$params->{'ldap_bind_password'} = $pwd;

	require Sympa::Datasource::LDAP;
	$ds = Sympa::Datasource::LDAP->new($params);

	unless (defined $ds && ($ldap_passwd = $ds->connect())) {
		Sympa::Log::Syslog::do_log('err',"Unable to connect to the LDAP server '%s'",
			$params->{'host'});
		return undef;
	}

	$mesg= $ldap_passwd->search ( base => $ldap->{'suffix'},
		filter => "$filter",
		scope => $ldap->{'scope'},
		timeout => $ldap->{'timeout'}
	);

	if ($mesg->count() == 0 || $mesg->code() != 0) {
		Sympa::Log::Syslog::do_log('notice',"No entry in the Ldap Directory Tree of %s", $ldap->{'host'});
		$ds->disconnect();
		return undef;
	}

	## To get the value of the canonic email and the alternative email
	my (@canonic_email, @alternative);

	## Keep previous alt emails not from LDAP source
	my $previous = {};
	foreach my $alt (keys %{$params->{'alt_emails'}}) {
		$previous->{$alt} = $params->{'alt_emails'}{$alt} if ($params->{'alt_emails'}{$alt} ne 'ldap');
	}
	$params->{'alt_emails'} = {};

	my $entry = $mesg->entry(0);
	@canonic_email = $entry->get_value($attrs, 'alloptions' => 1);
	foreach my $email (@canonic_email){
		my $e = lc($email);
		$params->{'alt_emails'}{$e} = 'ldap' if ($e);
	}

	foreach my $attribute_value (@alternative_conf){
		@alternative = $entry->get_value($attribute_value, 'alloptions' => 1);
		foreach my $alter (@alternative){
			my $a = lc($alter);
			$params->{'alt_emails'}{$a} = 'ldap' if($a);
		}
	}

	## Restore previous emails
	foreach my $alt (keys %{$previous}) {
		$params->{'alt_emails'}{$alt} = $previous->{$alt};
	}

	$ds->disconnect() or Sympa::Log::Syslog::do_log('notice', "unable to unbind");
	Sympa::Log::Syslog::do_log('debug3',"canonic: $canonic_email[0]");
	## If the identifier provided was a valid email, return the provided email.
	## Otherwise, return the canonical email guessed after the login.
	if( Sympa::Tools::valid_email($auth) && !$robot->ldap_force_canonical_email) {
		return ($auth);
	} else {
		return lc($canonic_email[0]);
	}
}

=item get_email_by_net_id($robot, $auth_id, $attributes)

Fetch user email using his cas net_id and the paragrapah number in auth.conf.

Parameters:

=over

=item string

=item string

=item string

=back

Return value:

=cut

## NOTE: This might be moved to Robot package.
sub get_email_by_net_id {
	my ($robot, $auth_id, $attributes) = @_;

	$robot = Sympa::Robot::clean_robot($robot);

	Sympa::Log::Syslog::do_log ('debug',"($auth_id,$attributes->{'uid'})");

	if (defined Sympa::Site->auth_services{$robot}[$auth_id]{'internal_email_by_netid'}) {
		my $sso_config = @{Sympa::Site->auth_services{$robot}}[$auth_id];
		my $netid_cookie = $sso_config->{'netid_http_header'};

		$netid_cookie =~ s/(\w+)/$attributes->{$1}/ig;

		my $email = $robot->get_netidtoemail_db($netid_cookie, Sympa::Site->auth_services{$robot}[$auth_id]{'service_id'});

		return $email;
	}

	my $ldap = @{Sympa::Site->auth_services{$robot}}[$auth_id];

	my $param = Sympa::Tools::Data::dup_var($ldap);
	require Sympa::Datasource::LDAP;
	my $ds = Sympa::Datasource::LDAP->new($param);
	my $ldap_anonymous;

	unless (defined $ds && ($ldap_anonymous = $ds->connect())) {
		Sympa::Log::Syslog::do_log('err',"Unable to connect to the LDAP server '%s'", $ldap->{'ldap_host'});
		return undef;
	}

	my $filter = $ldap->{'ldap_get_email_by_uid_filter'};
	$filter =~ s/\[([\w-]+)\]/$attributes->{$1}/ig;

#	my @alternative_conf = split(/,/,$ldap->{'alternative_email_attribute'});

	my $emails= $ldap_anonymous->search ( base => $ldap->{'ldap_suffix'},
		filter => $filter,
		scope => $ldap->{'ldap_scope'},
		timeout => $ldap->{'ldap_timeout'},
		attrs =>  $ldap->{'ldap_email_attribute'}
	);
	if ($emails->count() == 0) {
		Sympa::Log::Syslog::do_log('notice',"No entry in the Ldap Directory Tree of %s");
		$ds->disconnect();
		return undef;
    }

	$ds->disconnect();

	## return only the first attribute
	my @results = $emails->entries;
	foreach my $result (@results){
		return (lc($result->get_value($ldap->{'ldap_email_attribute'})));
	}

}

=item remote_app_check_password($trusted_application_name,$password,$robot)

Check trusted_application_name et trusted_application_password

Parameters:

=over

=item string

=item string

=item string

=back

Return value:

return 1 or I<undef>.

=cut

sub remote_app_check_password {
	my ($trusted_application_name, $password, $robot) = @_;
	Sympa::Log::Syslog::do_log('debug','(%s,%s)',$trusted_application_name,$robot);

	$robot = Sympa::Robot::clean_robot($robot);

	my $md5 = Digest::MD5::md5_hex($password);

	# seach entry for trusted_application in Conf
	my @trusted_apps;

	# select trusted_apps from robot context or sympa context
	@trusted_apps = @{$robot->trusted_applications};

	foreach my $application (@trusted_apps){

		if (lc($application->{'name'}) eq lc($trusted_application_name)) {
			if ($md5 eq $application->{'md5password'}) {
				# Sympa::Log::Syslog::do_log('debug', 'authentication succeed for %s',$application->{'name'});
				my %proxy_for_vars;
				foreach my $varname (@{$application->{'proxy_for_variables'}}) {
					$proxy_for_vars{$varname}=1;
				}
				return (\%proxy_for_vars);
		} else {
			Sympa::Log::Syslog::do_log('info', 'bad password from %s', $trusted_application_name);
			return undef;
		}
	}
}
# no matching application found
Sympa::Log::Syslog::do_log('info', 'unknown application name %s', $trusted_application_name);
return undef;
}

=item create_one_time_ticket($email, $robot, $data_string, $remote_addr)

Create new entry in one_time_ticket table using a rand as id so later access is
authenticated

Parameters:

=over

=item string

=item string

=item string

=item string

Value may be 'mail' if the IP address is not known

=back

Return value:

=cut

sub create_one_time_ticket {
	my ($email,  $robot, $data_string, $remote_addr) = @_;

	$robot = Sympa::Robot::clean_robot($robot);

	my $ticket = Sympa::Session->get_random();
	Sympa::Log::Syslog::do_log('info', '(%s,%s,%s,%s value = %s)',$email,$robot,$data_string,$remote_addr,$ticket);

	my $date = time();
	my $base = Sympa::Database->get_singleton();
	my $rows = $base->execute_query(
		"INSERT INTO one_time_ticket_table ("   .
			"ticket_one_time_ticket, "      .
			"robot_one_time_ticket, "       .
			"email_one_time_ticket, "       .
			"date_one_time_ticket, "        .
			"data_one_time_ticket, "        .
			"remote_addr_one_time_ticket, " .
			"status_one_time_ticket"        .
		") VALUES (?, ?, ?, ?, ?, ?, ?)",
		$ticket,
		$robot,
		$email,
		time(),
		$data_string,
		$remote_addr,
		'open'
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to insert new one time ticket for user %s, robot %s in the database',$email,$robot);
		return undef;
	}
	return $ticket;
}

=item get_one_time_ticket($ticket_number, $addr)

Read one_time_ticket from table and remove it

Parameters:

=over

=item string

=item string

=back

Return value:

=cut

sub get_one_time_ticket {
	my ($robot, $ticket_number, $addr) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)',$ticket_number);

	$robot = Sympa::Robot::clean_robot($robot);

	my $base = Sympa::Database->get_singleton();
	my $handle = $base->get_query_handle(
		"SELECT "                                              .
			"ticket_one_time_ticket AS ticket, "           .
			"robot_one_time_ticket AS robot, "             .
			"email_one_time_ticket AS email, "             .
			"date_one_time_ticket AS \"date\", "           .
			"data_one_time_ticket AS data, "               .
			"remote_addr_one_time_ticket AS remote_addr, " .
			"status_one_time_ticket AS status "            .
		"FROM one_time_ticket_table "                          .
		"WHERE ticket_one_time_ticket=? AND robot_one_time_ticket = ?",
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve one time ticket %s from database',$ticket_number);
		return {'result'=>'error'};
	}
	$handle->execute($ticket_number, $robot->domain);

	my $ticket = $handle->fetchrow_hashref('NAME_lc');

	unless ($ticket) {
		Sympa::Log::Syslog::do_log('info','Unable to find one time ticket %s', $ticket);
		return {'result'=>'not_found'};
	}

	my $result;
	my $printable_date = Sympa::Language::gettext_strftime(
		"%d %b %Y at %H:%M:%S", localtime($ticket->{'date'})
	);

    my $lockout = $robot->one_time_ticket_lockout || 'open';
    my $lifetime = Sympa::Tools::duration_conv($robot->one_time_ticket_lifetime || 0);

    if ($lockout eq 'one_time' and $ticket->{'status'} ne 'open') {
		$result = 'closed';
		Sympa::Log::Syslog::do_log('info', 'ticket %s from %s has been used before (%s)',
			$ticket_number,
			$ticket->{'email'},
			$printable_date
		);
	} elsif ($lockout eq 'remote_addr' and $ticket->{'status'} ne $addr and $ticket->{'status'} ne 'open') {
		$result = 'closed';
		Sympa::Log::Syslog::do_log('info', 'ticket %s from %s refused because accessed by the other (%s)',
			$ticket_number,
			$ticket->{'email'},
			$printable_date
		);
	} elsif ($lifetime and $ticket->{'date'} + $lifetime < time) {
		Sympa::Log::Syslog::do_log('info', 'ticket %s from %s refused because expired (%s)',
			$ticket_number,
			$ticket->{'email'},
			$printable_date
		);
		$result = 'expired';
	} else {
		$result = 'success';
	}
	
	if ($result eq 'success') {
		my $rows = $base->execute_query(
			"UPDATE one_time_ticket_table " .
			"SET status_one_time_ticket=? " .
			"WHERE ticket_one_time_ticket=? AND robot_one_time_ticket = ?",
			$addr,
			$ticket_number,
			$robot->domain
		);
		unless ($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to set one time ticket %s status to %s',$ticket_number, $addr);
		}
	}

	Sympa::Log::Syslog::do_log('info', '(%s): result : %s',$ticket_number,$result);
	return {'result'=>$result,
		'date'=>$ticket->{'date'},
		'email'=>$ticket->{'email'},
		'remote_addr'=>$ticket->{'remote_addr'},
		'robot'=>$ticket->{'robot'},
		'data'=>$ticket->{'data'},
		'status'=>$ticket->{'status'}
	};
}

=back

=cut

1;
