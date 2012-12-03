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

Sympa::Auth - Web authentication functions

=head1 DESCRIPTION 

This module provides web authentication functions.

=cut

package Sympa::Auth;

use Digest::MD5;

use Sympa::Configuration;
use Sympa::Datasource::LDAP;
use Sympa::Language;
use Sympa::List;
use Sympa::Log;
use Sympa::Report;
use Sympa::SDM;
use Sympa::Session;

=head1 FUNCTIONS

=head2 password_fingerprint($pwd)

Return the password finger print (this proc allow futur replacement of md5 by
sha1 or ....)

=cut

sub password_fingerprint{

    &Sympa::Log::do_log('debug', '%s::password_fingerprint', __PACKAGE__);

    my $pwd = shift;
    if(&Sympa::Configuration::get_robot_conf('*','password_case') eq 'insensitive') {
	return &Sympa::Tools::md5_fingerprint(lc($pwd));
    }else{
	return &Sympa::Tools::md5_fingerprint($pwd);
    }    
}

=head2 check_auth($robot, $auth, $pwd)

Authentication via email or uid.

=cut

 sub check_auth{
     my $robot = shift;
     my $auth = shift; ## User email or UID
     my $pwd = shift; ## Password
     &Sympa::Log::do_log('debug', '%s::check_auth(%s)', __PACKAGE__,$auth);

     my ($canonic, $user);

     if( &Sympa::Tools::valid_email($auth)) {
	 return &authentication($robot, $auth,$pwd);
     }else{
	 ## This is an UID
	 foreach my $ldap (@{$Conf{'auth_services'}{$robot}}){
	     # only ldap service are to be applied here
	     next unless ($ldap->{'auth_type'} eq 'ldap');
	     
	     $canonic = &ldap_authentication($robot, $ldap, $auth,$pwd,'uid_filter');
	     last if ($canonic); ## Stop at first match
	 }
	 if ($canonic){
	     
	     unless($user = &Sympa::List::get_global_user($canonic)){
		 $user = {'email' => $canonic};
	     }
	     return {'user' => $user,
		     'auth' => 'ldap',
		     'alt_emails' => {$canonic => 'ldap'}
		 };
	     
	 }else{
	     &Sympa::Report::reject_report_web('user','incorrect_passwd',{}) unless ($ENV{'SYMPA_SOAP'});
	     &Sympa::Log::do_log('err', "Incorrect Ldap password");
	     return undef;
	 }
     }
 }

=head2 may_use_sympa_native_auth($robot, $user_email)

This subroutine if Sympa may use its native authentication for a given user
It might not if no user_table paragraph is found in auth.conf or if the regexp
or negative_regexp exclude this user

=head3 Parameters

=over

=item * I<$robot>

=item * I<$user_email>

=back

=head3 Return value

boolean

=cut

sub may_use_sympa_native_auth {
    my ($robot, $user_email) = @_;

    my $ok = 0;
    ## check each auth.conf paragrpah
    foreach my $auth_service (@{$Conf{'auth_services'}{$robot}}){
	next unless ($auth_service->{'auth_type'} eq 'user_table');

	next if ($auth_service->{'regexp'} && ($user_email !~ /$auth_service->{'regexp'}/i));
	next if ($auth_service->{'negative_regexp'} && ($user_email =~ /$auth_service->{'negative_regexp'}/i));
	
	$ok = 1; last;
    }
    
    return $ok;
}

sub authentication {
    my ($robot, $email,$pwd) = @_;
    my ($user,$canonic);
    &Sympa::Log::do_log('debug', '%s::authentication(%s)', __PACKAGE__, $email);


    unless ($user = &Sympa::List::get_global_user($email)) {
	$user = {'email' => $email };
    }    
    unless ($user->{'password'}) {
	$user->{'password'} = '';
    }
    
    if ($user->{'wrong_login_count'} > &Sympa::Configuration::get_robot_conf($robot, 'max_wrong_password')){
	# too many wrong login attemp
	&Sympa::List::update_global_user($email,{wrong_login_count => $user->{'wrong_login_count'}+1}) ;
	&Sympa::Report::reject_report_web('user','too_many_wrong_login',{}) unless ($ENV{'SYMPA_SOAP'});
	&Sympa::Log::do_log('err','login is blocked : too many wrong password submission for %s', $email);
	return undef;
    }
    foreach my $auth_service (@{$Conf{'auth_services'}{$robot}}){
	next if ($auth_service->{'auth_type'} eq 'authentication_info_url');
	next if ($email !~ /$auth_service->{'regexp'}/i);
	next if (($email =~ /$auth_service->{'negative_regexp'}/i)&&($auth_service->{'negative_regexp'}));

	## Only 'user_table' and 'ldap' backends will need that Sympa collects the user passwords
	## Other backends are Single Sign-On solutions
	if ($auth_service->{'auth_type'} eq 'user_table') {
	    my $fingerprint = &password_fingerprint ($pwd);	    	    
	    
	    if ($fingerprint eq $user->{'password'}) {
		&Sympa::List::update_global_user($email,{wrong_login_count => 0}) ;
		return {'user' => $user,
			'auth' => 'classic',
			'alt_emails' => {$email => 'classic'}
			};
	    }
	}elsif($auth_service->{'auth_type'} eq 'ldap') {
	    if ($canonic = &ldap_authentication($robot, $auth_service, $email,$pwd,'email_filter')){
		unless($user = &Sympa::List::get_global_user($canonic)){
		    $user = {'email' => $canonic};
		}
		&Sympa::List::update_global_user($canonic,{wrong_login_count => 0}) ;
		return {'user' => $user,
			'auth' => 'ldap',
			'alt_emails' => {$email => 'ldap'}
			};
	    }
	}
    }

    # increment wrong login count.
    &Sympa::List::update_global_user($email,{wrong_login_count =>$user->{'wrong_login_count'}+1}) ;

    &Sympa::Report::reject_report_web('user','incorrect_passwd',{}) unless ($ENV{'SYMPA_SOAP'});
    &Sympa::Log::do_log('err','authentication: incorrect password for user %s', $email);

    $param->{'init_email'} = $email;
    $param->{'escaped_init_email'} = &Sympa::Tools::escape_chars($email);
    return undef;
}


sub ldap_authentication {
     my ($robot, $ldap, $auth, $pwd, $whichfilter) = @_;
     my ($mesg, $host,$ldap_passwd,$ldap_anonymous);
     &Sympa::Log::do_log('debug2','%s::ldap_authentication(%s,%s,%s)', __PACKAGE__, $auth,'****',$whichfilter);
     &Sympa::Log::do_log('debug3','Password used: %s',$pwd);

     unless (&Sympa::Tools::get_filename('etc',{},'auth.conf', $robot, undef, $Sympa::Configuration::Conf{'etc'})) {
	 return undef;
     }

     ## No LDAP entry is defined in auth.conf
     if ($#{$Conf{'auth_services'}{$robot}} < 0) {
	 &Sympa::Log::do_log('notice', 'Skipping empty auth.conf');
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
     my $param = &Sympa::Tools::Data::dup_var($ldap);
     my $ds = new Sympa::Datasource::LDAP($param);
     
     unless (defined $ds && ($ldap_anonymous = $ds->connect())) {
       &Sympa::Log::do_log('err',"Unable to connect to the LDAP server '%s'", $ldap->{'host'});
       return undef;
     }
     
     
     $mesg = $ldap_anonymous->search(base => $ldap->{'suffix'},
				     filter => "$filter",
				     scope => $ldap->{'scope'} ,
				     timeout => $ldap->{'timeout'});
     
     if ($mesg->count() == 0) {
       &Sympa::Log::do_log('notice','No entry in the Ldap Directory Tree of %s for %s',$ldap->{'host'},$auth);
       $ds->disconnect();
       return undef;
     }
     
     my $refhash=$mesg->as_struct();
     my (@DN) = keys(%$refhash);
     $ds->disconnect();
     
     ##  bind with the DN and the pwd
     
     ## Duplicate structure first
     ## Then set the bind_dn and password according to the current user
     $param = &Sympa::Tools::Data::dup_var($ldap);
     $param->{'ldap_bind_dn'} = $DN[0];
     $param->{'ldap_bind_password'} = $pwd;
     
     $ds = new Sympa::Datasource::LDAP($param);
     
     unless (defined $ds && ($ldap_passwd = $ds->connect())) {
       &Sympa::Log::do_log('err',"Unable to connect to the LDAP server '%s'", $param->{'host'});
       return undef;
     }
     
     $mesg= $ldap_passwd->search ( base => $ldap->{'suffix'},
				   filter => "$filter",
				   scope => $ldap->{'scope'},
				   timeout => $ldap->{'timeout'}
				 );
     
     if ($mesg->count() == 0 || $mesg->code() != 0) {
       &Sympa::Log::do_log('notice',"No entry in the Ldap Directory Tree of %s", $ldap->{'host'});
       $ds->disconnect();
       return undef;
     }
     
     ## To get the value of the canonic email and the alternative email
     my (@canonic_email, @alternative);
     
     ## Keep previous alt emails not from LDAP source
     my $previous = {};
     foreach my $alt (keys %{$param->{'alt_emails'}}) {
       $previous->{$alt} = $param->{'alt_emails'}{$alt} if ($param->{'alt_emails'}{$alt} ne 'ldap');
     }
     $param->{'alt_emails'} = {};
     
     my $entry = $mesg->entry(0);
     @canonic_email = $entry->get_value($attrs, 'alloptions' => 1);
     foreach my $email (@canonic_email){
       my $e = lc($email);
       $param->{'alt_emails'}{$e} = 'ldap' if ($e);
     }
     
     foreach my $attribute_value (@alternative_conf){
       @alternative = $entry->get_value($attribute_value, 'alloptions' => 1);
       foreach my $alter (@alternative){
	 my $a = lc($alter); 
	 $param->{'alt_emails'}{$a} = 'ldap' if($a) ;
       }
     }
     
     ## Restore previous emails
     foreach my $alt (keys %{$previous}) {
       $param->{'alt_emails'}{$alt} = $previous->{$alt};
     }
     
     $ds->disconnect() or &Sympa::Log::do_log('notice', "unable to unbind");
     &Sympa::Log::do_log('debug3',"canonic: $canonic_email[0]");
     ## If the identifier provided was a valid email, return the provided email.
     ## Otherwise, return the canonical email guessed after the login.
     if( &Sympa::Tools::valid_email($auth) && !&Sympa::Configuration::get_robot_conf($robot,'ldap_force_canonical_email')) {
	 return ($auth);
     }else{
	 return lc($canonic_email[0]);
     } 
}

=head2 get_email_by_net_id($robot, $auth_id, $attributes)

Fetch user email using his cas net_id and the paragrapah number in auth.conf.

=head3 Parameters

=over

=item * I<$robot>

=item * I<$auth_id>

=item * I<$attributes>

=back

=head3 Return value

=cut

sub get_email_by_net_id {
    
    my $robot = shift;
    my $auth_id = shift;
    my $attributes = shift;
    
    &Sympa::Log::do_log ('debug',"%s::get_email_by_net_id($auth_id,$attributes->{'uid'})", __PACKAGE__);
    
    if (defined $Conf{'auth_services'}{$robot}[$auth_id]{'internal_email_by_netid'}) {
	my $sso_config = @{$Conf{'auth_services'}{$robot}}[$auth_id];
	my $netid_cookie = $sso_config->{'netid_http_header'} ;
	
	$netid_cookie =~ s/(\w+)/$attributes->{$1}/ig;
	
	$email = &Sympa::List::get_netidtoemail_db($robot, $netid_cookie, $Conf{'auth_services'}{$robot}[$auth_id]{'service_id'});
	
	return $email;
    }
 
    my $ldap = @{$Conf{'auth_services'}{$robot}}[$auth_id];

    my $param = &Sympa::Tools::Data::dup_var($ldap);
    my $ds = new Sympa::Datasource::LDAP($param);
    my $ldap_anonymous;
    
    unless (defined $ds && ($ldap_anonymous = $ds->connect())) {
	&Sympa::Log::do_log('err',"Unable to connect to the LDAP server '%s'", $ldap->{'ldap_host'});
	return undef;
    }

    my $filter = $ldap->{'ldap_get_email_by_uid_filter'} ;
    $filter =~ s/\[([\w-]+)\]/$attributes->{$1}/ig;

#	my @alternative_conf = split(/,/,$ldap->{'alternative_email_attribute'});
		
	my $emails= $ldap_anonymous->search ( base => $ldap->{'ldap_suffix'},
				      filter => $filter,
				      scope => $ldap->{'ldap_scope'},
				      timeout => $ldap->{'ldap_timeout'},
				      attrs =>  $ldap->{'ldap_email_attribute'}
				      );
	my $count = $emails->count();

	if ($emails->count() == 0) {
	    &Sympa::Log::do_log('notice',"No entry in the Ldap Directory Tree of %s", $host);
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

=head2 remote_app_check_password($trusted_application_name,$password,$robot)

Check trusted_application_name et trusted_application_password

=head3 Parameters

=over

=item * I<$trusted_application_name>

=item * I<$password>

=item * I<$robot>

=back

=head3 Return value

return 1 or I<undef>.

=cut

sub remote_app_check_password {
    
    my ($trusted_application_name,$password,$robot) = @_;
    &Sympa::Log::do_log('debug','%s::remote_app_check_password (%s,%s)',__PACKAGE__,$trusted_application_name,$robot);
    
    my $md5 = &Sympa::Tools::md5_fingerprint($password);
    
    my $vars;
    # seach entry for trusted_application in Conf
    my @trusted_apps ;
    
    # select trusted_apps from robot context or sympa context
    @trusted_apps = @{&Sympa::Configuration::get_robot_conf($robot,'trusted_applications')};
    
    foreach my $application (@trusted_apps){
	
 	if (lc($application->{'name'}) eq lc($trusted_application_name)) {
 	    if ($md5 eq $application->{'md5password'}) {
 		# &Sympa::Log::do_log('debug', '%s::remote_app_check_password : authentication succeed for %s',__PACKAGE__,$application->{'name'});
 		my %proxy_for_vars ;
 		foreach my $varname (@{$application->{'proxy_for_variables'}}) {
 		    $proxy_for_vars{$varname}=1;
 		}		
 		return (\%proxy_for_vars);
 	    }else{
 		&Sympa::Log::do_log('info', '%s::remote_app_check_password: bad password from %s', __PACKAGE__,$trusted_application_name);
 		return undef;
 	    }
 	}
    }				 
    # no matching application found
    &Sympa::Log::do_log('info', '%s::remote_app-check_password: unknown application name %s', __PACKAGE__, $trusted_application_name);
    return undef;
}

=head2 create_one_time_ticket($email, $robot, $data_string, $remote_addr)

Create new entry in one_time_ticket table using a rand as id so later access is
authenticated

=head3 Parameters

=over

=item * I<$email>

=item * I<$robot>

=item * I<$data_string>

=item * I<$remote_addr>

=back

=head3 Return value

=cut

sub create_one_time_ticket {
    my $email = shift;
    my $robot = shift;
    my $data_string = shift;
    my $remote_addr = shift; ## Value may be 'mail' if the IP address is not known

    my $ticket = &Sympa::Session::get_random();
    &Sympa::Log::do_log('info', '%s::create_one_time_ticket(%s,%s,%s,%s) value = %s',__PACKAGE__,$email,$robot,$data_string,$remote_addr,$ticket);

    my $date = time;
    my $sth;
    
    unless (&Sympa::SDM::do_query("INSERT INTO one_time_ticket_table (ticket_one_time_ticket, robot_one_time_ticket, email_one_time_ticket, date_one_time_ticket, data_one_time_ticket, remote_addr_one_time_ticket, status_one_time_ticket) VALUES (%s, %s, %s, %d, %s, %s, %s)",&Sympa::SDM::quote($ticket),&Sympa::SDM::quote($robot),&Sympa::SDM::quote($email),time,&Sympa::SDM::quote($data_string),&Sympa::SDM::quote($remote_addr),&Sympa::SDM::quote('open'))) {
	&Sympa::Log::do_log('err','Unable to insert new one time ticket for user %s, robot %s in the database',$email,$robot);
	return undef;
    }   
    return $ticket;
}

=head2 get_one_time_ticket($ticket_number, $addr)

Read one_time_ticket from table and remove it

=head3 Parameters

=over

=item * I<$ticket_number>

=item * I<$addr>

=back

=head3 Return value

=cut

sub get_one_time_ticket {
    my $ticket_number = shift;
    my $addr = shift; 
    
    &Sympa::Log::do_log('debug2', '(%s)',$ticket_number);
    
    my $sth;
    
    unless ($sth = &Sympa::SDM::do_query("SELECT ticket_one_time_ticket AS ticket, robot_one_time_ticket AS robot, email_one_time_ticket AS email, date_one_time_ticket AS \"date\", data_one_time_ticket AS data, remote_addr_one_time_ticket AS remote_addr, status_one_time_ticket as status FROM one_time_ticket_table WHERE ticket_one_time_ticket = %s ", &Sympa::SDM::quote($ticket_number))) {
	&Sympa::Log::do_log('err','Unable to retrieve one time ticket %s from database',$ticket_number);
	return {'result'=>'error'};
    }
 
    my $ticket = $sth->fetchrow_hashref('NAME_lc');
    
    unless ($ticket) {	
	&Sympa::Log::do_log('info','%s::get_one_time_ticket: Unable to find one time ticket %s', __PACKAGE__, $ticket);
	return {'result'=>'not_found'};
    }
    
    my $result;
    my $printable_date = gettext_strftime "%d %b %Y at %H:%M:%S", localtime($ticket->{'date'});

    if ($ticket->{'status'} ne 'open') {
	$result = 'closed';
	&Sympa::Log::do_log('info','%s::get_one_time_ticket: ticket %s from %s has been used before (%s)',__PACKAGE__,$ticket_number,$ticket->{'email'},$printable_date);
    }
    elsif (time - $ticket->{'date'} > 48 * 60 * 60) {
	&Sympa::Log::do_log('info','%s::get_one_time_ticket: ticket %s from %s refused because expired (%s)',__PACKAGE__,$ticket_number,$ticket->{'email'},$printable_date);
	$result = 'expired';
    }else{
	$result = 'success';
    }
    unless (&Sympa::SDM::do_query("UPDATE one_time_ticket_table SET status_one_time_ticket = %s WHERE (ticket_one_time_ticket=%s)", &Sympa::SDM::quote($addr), &Sympa::SDM::quote($ticket_number))) {
    	&Sympa::Log::do_log('err','Unable to set one time ticket %s status to %s',$ticket_number, $addr);
    }

    &Sympa::Log::do_log('info', '%s::get_one_time_ticket(%s) : result : %s',__PACKAGE__,$ticket_number,$result);
    return {'result'=>$result,
	    'date'=>$ticket->{'date'},
	    'email'=>$ticket->{'email'},
	    'remote_addr'=>$ticket->{'remote_addr'},
	    'robot'=>$ticket->{'robot'},
	    'data'=>$ticket->{'data'},
	    'status'=>$ticket->{'status'}
	};
}
    
1;
