# $Id$

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

Sympa::SOAP - SOAP facilities for Sympa

=head1 DESCRIPTION

This package provides abstraction for the VOOT workflow (server side).

=cut

package Sympa::SOAP;

use strict;

use Encode;
use HTTP::Cookies;

use Sympa::Admin;
use Sympa::Auth;
use Sympa::Configuration;
use Sympa::List;
use Sympa::Log;
use Sympa::Scenario;
use Sympa::Session;
use Sympa::Template;
use Sympa::Tools;

## Define types of SOAP type listType
my %types = ('listType' => {'listAddress' => 'string',
			    'homepage' => 'string',
			    'isSubscriber' => 'boolean',
			    'isOwner' => 'boolean',
			    'isEditor' => 'boolean',
			    'subject' => 'string',
			    'email' => 'string',
			    'gecos' => 'string'}
	     );

=head1 CLASS METHODS

=head2 Sympa::SOAP->checkCookie()

=head3 Parameters

None

=cut

sub checkCookie {
    my $class = shift;

    my $sender = $ENV{'USER_EMAIL'};

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not authentified')
	    ->faultdetail('You should login first');
    }

    &Sympa::Log::do_log('debug', '()');
    
    return SOAP::Data->name('result')->type('string')->value($sender);
}

=head2 Sympa::SOAP->lists($topic, $subtopic, $mode)

=head3 Parameters

=over

=item * I<$topic>

=item * I<$subtopic>

=item * I<$mode>

=back

=cut

sub lists {
    my $class = shift;
    my $topic = shift;
    my $subtopic = shift;
    my $mode = shift;

    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};

    &Sympa::Log::do_log('notice', 'lists(%s,%s,%s)', $topic, $subtopic,$sender);

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not authentified')
	    ->faultdetail('You should login first');
    }

    my @result;  
    
    &Sympa::Log::do_log('info', '(%s,%s)', $topic, $subtopic);
   
    my $all_lists = &Sympa::List::get_lists($robot);
    foreach my $list ( @$all_lists ) {
	
	my $listname = $list->{'name'};

	my $result_item = {};
	my $result = $list->check_list_authz('visibility','md5',
					     {'sender' => $sender,
					      'remote_application_name' =>  $ENV{'remote_application_name'} }
					    );
	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');
	next unless ($action eq 'do_it');
	
	##building result packet
	$result_item->{'listAddress'} = $listname.'@'.$list->{'admin'}{'host'};
	$result_item->{'subject'} = $list->{'admin'}{'subject'};
	$result_item->{'subject'} =~ s/;/,/g;
	$result_item->{'homepage'} = &Sympa::Configuration::get_robot_conf($robot,'wwsympa_url').'/info/'.$listname; 
	
	my $listInfo;
	if ($mode eq 'complex') {
	    $listInfo = struct_to_soap($result_item);
	}else {
	    $listInfo = struct_to_soap($result_item, 'as_string');
	}
	
	## no topic ; List all lists
	if (!$topic) {
	    push @result, $listInfo;
	    
	}elsif ($list->{'admin'}{'topics'}) {
	    foreach my $list_topic (@{$list->{'admin'}{'topics'}}) {
		my @tree = split '/', $list_topic;
		
		next if (($topic) && ($tree[0] ne $topic));
		next if (($subtopic) && ($tree[1] ne $subtopic));
		
		push @result, $listInfo;
	    }
	}elsif ($topic  eq 'topicsless') {
	    	push @result, $listInfo;
	}
    }
    
    return SOAP::Data->name('listInfo')->value(\@result);
}

=head2 Sympa::SOAP->login($email, $password)

=head3 Parameters

=over

=item * I<$email>

=item * I<$password>

=back

=cut

sub login {
    my $class = shift;
    my $email = shift;
    my $passwd = shift;

    my $http_host = $ENV{'SERVER_NAME'};
    my $robot = $ENV{'SYMPA_ROBOT'};
    &Sympa::Log::do_log('notice', 'login(%s)', $email);
    
    #foreach my  $k (keys %ENV) {
    #&Sympa::Log::do_log('notice', 'ENV %s = %s', $k, $ENV{$k});
    #}
    unless (defined $http_host){
	&Sympa::Log::do_log('err', 'login(): SERVER_NAME not defined');
    } 
    unless (defined $email){
	&Sympa::Log::do_log('err', 'login(): email not defined');
    } 
    unless (defined $passwd){
	&Sympa::Log::do_log('err', 'login(): passwd not defined');
    } 

    unless ($http_host and $email and $passwd) {
	&Sympa::Log::do_log('err', 'login(): incorrect number of parameters');
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <HTTP host> <email> <password>');
    }
    
    ## Authentication of the sender
    ## Set an env var to find out if in a SOAP context
    $ENV{'SYMPA_SOAP'} = 1;

    &Sympa::Log::do_log('debug', 'call check_auth(%s,%s)',$robot,$email);
    my $user = &Sympa::Auth::check_auth($robot,$email,$passwd);

    unless($user){
	&Sympa::Log::do_log('notice', "authentication failed");
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Authentification failed')
	    ->faultdetail("Incorrect password for user $email or bad login");
    } 

    ## Create Sympa::Session object
    my $session = new Sympa::Session($robot, {'cookie' => $ENV{'SESSION_ID'}});
    $ENV{'USER_EMAIL'} = $email;
    $session->{'email'} = $email;
    $session->store();
    
    ## Note that id_session changes each time it is saved in the DB
    $ENV{'SESSION_ID'} = $session->{'id_session'};

    ## Also return the cookie value
    return SOAP::Data->name('result')->type('string')->value($ENV{'SESSION_ID'});
}

=head2 Sympa::SOAP->casLogin($proxyTicket)

=head3 Parameters

=over

=item * I<$proxyTicket>

=back

=cut

sub casLogin {
    my $class = shift;
    my $proxyTicket = shift;

    my $http_host = $ENV{'SERVER_NAME'};
    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};
    &Sympa::Log::do_log('notice', 'casLogin(%s)', $proxyTicket);
    
    unless ($http_host and $proxyTicket) {
	&Sympa::Log::do_log('err', 'casLogin(): incorrect number of parameters');
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <HTTP host> <proxyTicket>');
    }
    
	eval {
            require AuthCAS;
        };
        if ($@) {
		&Sympa::Log::do_log('err',"Unable to use AuthCAS library, install AuthCAS (CPAN) first");
		return undef ;
    }
    require AuthCAS;

	
    ## Validate the CAS ST against all known CAS servers defined in auth.conf
    ## CAS server response will include the user's NetID
    my ($user, @proxies, $email, $cas_id);
    foreach my $service_id (0..$#{$Sympa::Configuration::Conf{'auth_services'}{$robot}}){
	my $auth_service = $Sympa::Configuration::Conf{'auth_services'}{$robot}[$service_id];
	next unless ($auth_service->{'auth_type'} eq 'cas'); ## skip non CAS entries
	
	my $cas = new AuthCAS(casUrl => $auth_service->{'base_url'}, 
			  #CAFile => '/usr/local/apache/conf/ssl.crt/ca-bundle.crt',
			  );
	
	($user, @proxies) = $cas->validatePT(&Sympa::Configuration::get_robot_conf($robot,'soap_url'), $proxyTicket);
	unless (defined $user) {
	    &Sympa::Log::do_log('err', 'CAS ticket %s not validated by server %s : %s', $proxyTicket, $auth_service->{'base_url'}, &AuthCAS::get_errors());
	    next;
	}

	&Sympa::Log::do_log('notice', 'User %s authenticated against server %s', $user, $auth_service->{'base_url'});
	
	## User was authenticated
	$cas_id = $service_id;
	last;	
    }
    
    unless($user){
	&Sympa::Log::do_log('notice', "authentication failed");
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Authentification failed')
	    ->faultdetail("Proxy ticket could not be validated");
    } 

    ## Now fetch email attribute from LDAP
    unless ($email = &Sympa::Auth::get_email_by_net_id($robot, $cas_id, {'uid' => $user})) {
	&Sympa::Log::do_log('err','Could not get email address from LDAP for user %s', $user);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Authentification failed')
	    ->faultdetail("Could not get email address from LDAP directory");
    }

    ## Create Sympa::Session object
    my $session = new Sympa::Session($robot, {'cookie' => $ENV{'SESSION_ID'}});
    $ENV{'USER_EMAIL'} = $email;
    $session->{'email'} = $email;
    $session->store();
    
    ## Note that id_session changes each time it is saved in the DB
    $ENV{'SESSION_ID'} = $session->{'id_session'};

    ## Also return the cookie value
    return SOAP::Data->name('result')->type('string')->value($ENV{'SESSION_ID'});
}

=head1 INSTANCE METHODS

=head2 $soap->authenticateAndRun($email, $cookie, $service, $parameters)

Used to call a service as an authenticated user without using HTTP cookies.

=head3 Parameters

=over

=item * I<$email>

=item * I<$cookie>: secret contained in the cookie

=item * I<$service>

=item * I<$parameters>

=back

=cut

sub authenticateAndRun {
    my ($self, $email, $cookie, $service, $parameters) = @_;

    my $session_id = $cookie;
    &Sympa::Log::do_log('notice','authenticateAndRun(%s,%s,%s,%s)', $email, $session_id, $service, join(',',@$parameters));

    unless ($session_id and $service) {
      &Sympa::Log::do_log('err', "Missing parameter");
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <email> <cookie> <service>');
    }
    my $auth ;
    

    ## Provided email is not trusted, we fetch the user email from the session_table instead
    my $session = new Sympa::Session($ENV{'SYMPA_ROBOT'},{'cookie' => $session_id});
    $email = $session->{'email'} if (defined $session);
    unless ($email or ($email eq 'unkown')  ) {
      &Sympa::Log::do_log('err', "Failed to authenticate user with session ID $session_id");
      die SOAP::Fault->faultcode('Client')
	->faultstring('Could not get email from cookie')
	  ->faultdetail('');
    }
    
    $ENV{'USER_EMAIL'} = $email;
    $ENV{'SESSION_ID'} = $session_id;

    &{$service}($self,@$parameters);
}

=head2 $soap->getUserEmailByCookie($cookie)

Request user email from http cookie.

=head3 Parameters

=over

=item * I<$cookie>

=back

=cut

sub getUserEmailByCookie {
    my ($self, $cookie) = @_;

    &Sympa::Log::do_log('debug3','getUserEmailByCookie(%s)', $cookie);
    
    unless ($cookie) {
      &Sympa::Log::do_log('err',"Missing parameter cookie");
      die SOAP::Fault->faultcode('Client')
	->faultstring('Missing parameter')
	  ->faultdetail('Use : <cookie>');
    }
    
    my $session = new Sympa::Session($ENV{'SYMPA_ROBOT'}, {'cookie' => $cookie});
    
    
    unless (defined $session && ($session->{'email'} ne 'unkown')  ) {
      &Sympa::Log::do_log('err',"Failed to load session for $cookie");
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Could not get email from cookie')
	    ->faultdetail('');
    }    

    return SOAP::Data->name('result')->type('string')->value($session->{'email'});
    
}

=head2 $soap->authenticateRemoteAppAndRun($appname, $apppassword, $vars, $service, $parameters)

Call a service from a remote proxy application.

=head3 Parameters

=over

=item * I<$appname>: remot application name

=item * I<$apppassword>: remote application password

=item * I<$vars>: comma separated list of variable definitions
(var=value,var=value,...)

=item * I<$service>: service name requested

=item * I<$parameters>: service parameters

=back

=cut

sub authenticateRemoteAppAndRun {
    my ($self, $appname, $apppassword, $vars, $service, $parameters) = @_;
    my $robot = $ENV{'SYMPA_ROBOT'};

    &Sympa::Log::do_log('notice','authenticateRemoteAppAndRun(%s,%s,%s,%s)', $appname, $vars, $service, join(',',@$parameters));

    unless ($appname and $apppassword and $service) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <appname> <apppassword> <vars> <service>');
    }
    my $proxy_vars = &Sympa::Auth::remote_app_check_password($appname, $apppassword, $robot);
        
    unless (defined $proxy_vars) {
	&Sympa::Log::do_log('notice', "authenticateRemoteAppAndRun(): authentication failed");
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Authentification failed')
	    ->faultdetail("Authentication failed for application $appname");
    }
    $ENV{'remote_application_name'}=$appname;

    foreach my $var (split(/,/,$vars)) {
	# check if the remote application is trusted proxy for this variable
	# &Sympa::Log::do_log('notice', "sympasoap::authenticateRemoteAppAndRun: Remote application is trusted proxy for  $var");		

	my ($id,$value) = split(/=/,$var);
	if (!defined $id) {	
	    &Sympa::Log::do_log('notice', "authenticateRemoteAppAndRun(): incorrect syntaxe id");
	    die SOAP::Fault->faultcode('Server')
		->faultstring('Incorrect syntaxe id')
		->faultdetail("Unrecognized syntaxe  $var");
	}
	if (!defined $value) {	
	    &Sympa::Log::do_log('notice', "authenticateRemoteAppAndRun(): incorrect syntaxe value");
	    die SOAP::Fault->faultcode('Server')
		->faultstring('Incorrect syntaxe value')
		->faultdetail("Unrecognized syntaxe  $var");
	}
	$ENV{$id}=$value	if ($proxy_vars->{$id}) ;	
    }		
    &{$service}($self,@$parameters);
}

=head1 CLASS METHODS

=head2 Sympa::SOAP->amI($listname, $function, $user)

=head3 Parameters

=over

=item * I<$listname>

=item * I<$function>

=item * I<$user>

=back

=cut

sub amI {
  my ($class,$listname,$function,$user)=@_;

  my $robot = $ENV{'SYMPA_ROBOT'};

  &Sympa::Log::do_log('notice','amI(%s,%s,%s)',$listname,$function,$user);

  unless ($listname and $user and $function) {
      die SOAP::Fault->faultcode('Client')
	  ->faultstring('Incorrect number of parameters')
	  ->faultdetail('Use : <list> <function> <user email>');
  }

  $listname = lc($listname);  
  my $list = new Sympa::List ($listname, $robot);  

  &Sympa::Log::do_log('debug', '(%s)', $listname);

  if ($list) {
      if ($function eq 'subscriber') {
	  return SOAP::Data->name('result')->type('boolean')->value($list->is_list_member($user));
      }elsif ($function =~ /^owner|editor$/) {
	  return SOAP::Data->name('result')->type('boolean')->value($list->am_i($function, $user));
      }else {
	  die SOAP::Fault->faultcode('Server')
	      ->faultstring('Unknown function.')
	      ->faultdetail("Function $function unknown");
      }
  }else {
      die SOAP::Fault->faultcode('Server')
	  ->faultstring('Unknown list.')
	  ->faultdetail("List $listname unknown");
  }

}

=head2 Sympa::SOAP->info($listname)

=head3 Parameters

=over

=item * I<$listname>

=back

=cut

sub info {
    my $class = shift;
    my $listname  = shift;
    
    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not authentified')
	    ->faultdetail('You should login first');
    }    

    my @resultSoap;

    unless ($listname) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <list>');
    }
	
    &Sympa::Log::do_log('notice', '(%s)', $listname);

    my $list = new Sympa::List ($listname, $robot);
    unless ($list) {
	&Sympa::Log::do_log('info', 'Info %s from %s refused, list unknown', $listname,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Unknown list')
	    ->faultdetail("List $listname unknown");
    }

    my $sympa = &Sympa::Configuration::get_robot_conf($robot, 'sympa');

    my $user;

    # Part of the authorization code
    $user = &Sympa::List::get_global_user($sender);
     
    my $result = $list->check_list_authz('info','md5',
					 {'sender' => $sender,
  					  'remote_application_name' =>  $ENV{'remote_application_name'} }
					 );
    my $action;
    $action = $result->{'action'} if (ref($result) eq 'HASH');

    die SOAP::Fault->faultcode('Server')
	->faultstring('No action available')
	unless (defined $action);

    if ($action =~ /reject/i) {
	my $reason_string = &get_reason_string($result->{'reason'},$robot);
	&Sympa::Log::do_log('info', '%s from %s refused (not allowed)', $listname,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Not allowed')
	    ->faultdetail($reason_string);
    }
    if ($action =~ /do_it/i) {
	my $result_item;

	$result_item->{'listAddress'} = SOAP::Data->name('listAddress')->type('string')->value($listname.'@'.$list->{'admin'}{'host'});
	$result_item->{'subject'} = SOAP::Data->name('subject')->type('string')->value($list->{'admin'}{'subject'});
	$result_item->{'homepage'} = SOAP::Data->name('homepage')->type('string')->value(&Sympa::Configuration::get_robot_conf($robot,'wwsympa_url').'/info/'.$listname); 
	
	## determine status of user 
	if (($list->am_i('owner',$sender) || $list->am_i('owner',$sender))) {
	     $result_item->{'isOwner'} = SOAP::Data->name('isOwner')->type('boolean')->value(1);
	 }
	if (($list->am_i('editor',$sender) || $list->am_i('editor',$sender))) {
	    $result_item->{'isEditor'} = SOAP::Data->name('isEditor')->type('boolean')->value(1);
	}
	if ($list->is_list_member($sender)) {
	    $result_item->{'isSubscriber'} = SOAP::Data->name('isSubscriber')->type('boolean')->value(1);
	}
	
	#push @result, SOAP::Data->type('listType')->value($result_item);
	return SOAP::Data->value($result_item);
    }
    &Sympa::Log::do_log('info', '%s from %s aborted, unknown requested action in scenario',$listname,$sender);
    die SOAP::Fault->faultcode('Server')
	->faultstring('Unknown requested action')
	    ->faultdetail("%s from %s aborted because unknown requested action in scenario",$listname,$sender);
}

=head2 Sympa::SOAP->createList($listname, $subject, $template, $description,
$topics)

=head3 Parameters

=over

=item * I<$listname>

=item * I<$subject>

=item * I<$template>

=item * I<$description>

=item * I<$topics>

=back

=cut

sub createList {
    my $class = shift;
    my $listname  = shift;
    my $subject = shift;
    my $template = shift;
    my $description = shift;
    my $topics = shift;

    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};
    my $remote_application_name = $ENV{'remote_application_name'};

    &Sympa::Log::do_log('info', '(list = %s\@%s,subject = %s,template = %s,description = %s,topics = %s) from %s via proxy application %s', $listname,$robot,$subject,$template,$description,$topics,$sender,$remote_application_name);

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not specified')
	    ->faultdetail('Use a trusted proxy or login first ');
    }

    my @resultSoap;

    unless ($listname) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <list>');
    }
	
    &Sympa::Log::do_log('debug', '(%s,%s)', $listname,$robot);

    my $list = new Sympa::List ($listname, $robot);
    if ($list) {
	&Sympa::Log::do_log('info', 'create_list %s@%s from %s refused, list already exist', $listname,$robot,$sender);
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('List already exists')
	    ->faultdetail("List $listname already exists");
    }
    
    my $reject;
    unless ($subject) {	
	$reject .= 'subject'; 
    }
    unless ($template) {	
	$reject .= ', template'; 
    }
    unless ($description) {	
	$reject .= ', description'; 
    }
    unless ($topics) {	
	$reject .= 'topics'; 
    }
    if ($reject){
	&Sympa::Log::do_log('info', 'create_list %s@%s from %s refused, missing parameter(s) %s', $listname,$robot,$sender,$reject);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Missing parameter')
	    ->faultdetail("Missing required parameter(s) : $reject");	
    }
    # check authorization
    my $result = &Sympa::Scenario::request_action('create_list','md5',$robot,
					 {'sender' => $sender,
					  'remote_host' => $ENV{'REMOTE_HOST'},
					  'remote_addr' =>  $ENV{'REMOTE_ADDR'},
					  'remote_application_name' =>  $ENV{'remote_application_name'} }
					 );
    my $r_action;
    my $reason;
    if (ref($result) eq 'HASH') {
	$r_action = $result->{'action'};
	$reason = $result->{'reason'};
    }
    unless ($r_action =~ /do_it|listmaster/) {
	&Sympa::Log::do_log('info', 'create_list %s@%s from %s refused, reason %s', $listname,$robot,$sender,$reason);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Authorization reject')
	    ->faultdetail("Authorization reject : $reason");	
    }

    # prepare parameters
    my $param = {};
    $param->{'user'}{'email'} = $sender;
    if (&Sympa::List::is_global_user($param->{'user'}{'email'})) {
	$param->{'user'} = &Sympa::List::get_global_user($sender);
    }
    my $parameters;
    $parameters->{'creation_email'} =$sender;
    my %owner;
    $owner{'email'} = $param->{'user'}{'email'};
    $owner{'gecos'} = $param->{'user'}{'gecos'};
    push @{$parameters->{'owner'}},\%owner;

    $parameters->{'listname'} = $listname;
    $parameters->{'subject'} = $subject;
    $parameters->{'description'} = $description;
    $parameters->{'topics'} = $topics;
    
    if ($r_action =~ /listmaster/i) {
	$param->{'status'} = 'pending' ;
    }elsif  ($r_action =~ /do_it/i) {
	$param->{'status'} = 'open' ;
    }
    
     ## create liste
     my $resul = &Sympa::Admin::create_list_old($parameters,$template,$robot,"soap");
     unless(defined $resul) {
	 &Sympa::Log::do_log('info', 'unable to create list %s@%s from %s ', $listname,$robot,$sender);
	 die SOAP::Fault->faultcode('Server')
	     ->faultstring('unable to create list')
	     ->faultdetail('unable to create list');	
     }
     
     ## notify listmaster
     if ($param->{'create_action'} =~ /notify/) {
         if(&Sympa::List::send_notify_to_listmaster('request_list_creation',$robot,{'list' => $list,'email' => $sender})) {
	     &Sympa::Log::do_log('info','notify listmaster for list creation');
	 }else{
	     &Sympa::Log::do_log('notice',"Unable to send notify 'request_list_creation' to listmaster");
	 }
     }
     return SOAP::Data->name('result')->type('boolean')->value(1);

}

=head2 Sympa::SOAP->closeList($listname)

=head3 Parameters

=over

=item * I<$listname>

=back

=cut

sub closeList {
    my $class = shift;
    my $listname  = shift;

    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};
    my $remote_application_name = $ENV{'remote_application_name'};

    &Sympa::Log::do_log('info', '(list = %s\@%s) from %s via proxy application %s', $listname,$robot,$sender,$remote_application_name);

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not specified')
	    ->faultdetail('Use a trusted proxy or login first ');
    }

    my @resultSoap;

    unless ($listname) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <list>');
    }
	
    &Sympa::Log::do_log('debug', '(%s,%s)', $listname,$robot);

    my $list = new Sympa::List ($listname, $robot);
    unless ($list) {
	&Sympa::Log::do_log('info', 'closeList %s@%s from %s refused, unknown list', $listname,$robot,$sender);
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('unknown list')
	    ->faultdetail("inknown list $listname");
    }
    
    # check authorization
    unless (($list->am_i('owner', $sender)) || (&Sympa::List::is_listmaster($sender))) {
	&Sympa::Log::do_log('info', 'closeList %s from %s not allowed',$listname,$sender);
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Not allowed')
	    ->faultdetail("Not allowed");
     }      

    if ($list->{'admin'}{'status'} eq 'closed') {
	&Sympa::Log::do_log('info', 'closeList: already closed');
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('list allready closed')
	    ->faultdetail("list $listname all ready closed");
     }elsif($list->{'admin'}{'status'} eq 'pending') {
	 &Sympa::Log::do_log('info','do_close_list: closing a pending list makes it purged');
	 $list->purge($sender);
     }else{
	 $list->close_list($sender);
	 &Sympa::Log::do_log('info','do_close_list: list %s closed',$listname);
     }     
     return 1;
}

=head2 Sympa::SOAP->add($listname, $email, $gecos, $quiet)

=head3 Parameters

=over

=item * I<$listname>

=item * I<$email>

=item * I<$gecos>

=item * I<$quiet>

=back

=cut

sub add {
    my $class = shift;
    my $listname  = shift;
    my $email = shift;
    my $gecos = shift;
    my $quiet = shift;

    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};
    my $remote_application_name = $ENV{'remote_application_name'};
    
    &Sympa::Log::do_log('info', '(list = %s@%s,email = %s,quiet = %s) from %s via proxy application %s', $listname,$robot,$email,$quiet,$sender,$remote_application_name);

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not specified')
	    ->faultdetail('Use a trusted proxy or login first ');
    }
    
    unless ($listname) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <list>');
    }
    unless ($email) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <email>');
    }
    my $list = new Sympa::List ($listname, $robot);
    unless ($list) {
	&Sympa::Log::do_log('info', 'add %s@%s %s from %s refused, no such list ', $listname,$robot,$email,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Undefined list')
	    ->faultdetail("Undefined list");
    }

    # check authorization

    my $result = $list->check_list_authz('add','md5',
					 {'sender' => $sender, 
					  'email' => $email,
					  'remote_host' => $ENV{'REMOTE_HOST'},
					  'remote_addr' => $ENV{'REMOTE_ADDR'},
					  'remote_application_name' => $ENV{'remote_application_name'}} );

    
    my $action;
    my $reason;
    if (ref($result) eq 'HASH') {
	$action = $result->{'action'};
	$reason = $result->{'reason'};
    }

    unless (defined $action){
	&Sympa::Log::do_log('info', 'add %s@%s %s from %s : scenario error', $listname,$robot,$email,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('scenario error')
	    ->faultdetail("sender $sender email $email remote $ENV{'remote_application_name'} ");
    }

    unless ($action =~ /do_it/) {
	my $reason_string = &get_reason_string($reason,$robot);
	&Sympa::Log::do_log('info', '%s@%s %s from %s refused (not allowed)', $listname,$robot,$email,$sender);
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Not allowed')
	    ->faultdetail($reason_string);
    }


    if ($list->is_list_member($email)) {
      &Sympa::Log::do_log('err', 'add %s@%s %s from %s : failed, user already member of the list', $listname,$robot,$email,$sender);
      my $error = "User already member of list $listname";
      die SOAP::Fault->faultcode('Server')
	->faultstring('Unable to add user')
	  ->faultdetail($error);

    }else {
	my $u;
	my $defaults = $list->get_default_user_options();
	my $u2 = &Sympa::List::get_user_db($email);
	%{$u} = %{$defaults};
	$u->{'email'} = $email;
	$u->{'gecos'} = $gecos || $u2->{'gecos'};
	$u->{'date'} = $u->{'update_date'} = time;
	$u->{'password'} = $u2->{'password'} || &Sympa::Tools::tmp_passwd($email, $Sympa::Configuration::Conf{'cookie'}) ;
	$u->{'lang'} = $u2->{'lang'} || $list->{'admin'}{'lang'};

	$list->add_list_member($u);
	if (defined $list->{'add_outcome'}{'errors'}) {
	    &Sympa::Log::do_log('info', 'add %s@%s %s from %s : Unable to add user', $listname,$robot,$email,$sender);
	    my $error = sprintf ("Unable to add user %s in list %s: %s"),$email,$listname,$list->{'add_outcome'}{'errors'}{'error_message'};
	    die SOAP::Fault->faultcode('Server')
		->faultstring('Unable to add user')
		->faultdetail($error);
	}
	$list->delete_subscription_request($email);
    }
    
    ## Now send the welcome file to the user if it exists and notification is supposed to be sent.
    unless ($quiet || $action =~ /quiet/i) {
	unless ($list->send_file('welcome', $email, $robot,{'auto_submitted' => 'auto-generated'})) {
	    &Sympa::Log::do_log('notice',"Unable to send template 'welcome' to $email");
	}
    }
    
    &Sympa::Log::do_log('info', 'ADD %s %s from %s accepted (%d subscribers)', $list->{'name'}, $email, $sender, $list->get_total() );
    if ($action =~ /notify/i) {
	unless ($list->send_notify_to_owner('notice',{'who' => $email, 
						      'gecos' => $gecos,
						      'command' => 'add',
						      'by' => $sender})) {
	    &Sympa::Log::do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
	}
    }
}

=head2 Sympa::SOAP->del($listname, $email, $quiet)

=head3 Parameters

=over

=item * I<$listname>

=item * I<$email>

=item * I<$quiet>

=back

=cut

sub del {
    my $class = shift;
    my $listname  = shift;
    my $email = shift;
    my $quiet = shift;

    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};
    my $remote_application_name = $ENV{'remote_application_name'};
    
    &Sympa::Log::do_log('info', '(list = %s@%s,email = %s,quiet = %s) from %s via proxy application %s', $listname,$robot,$email,$quiet,$sender,$remote_application_name);

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not specified')
	    ->faultdetail('Use a trusted proxy or login first ');
    }
    
    unless ($listname) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <list>');
    }
    unless ($email) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <email>');
    }
    my $list = new Sympa::List ($listname, $robot);
    unless ($list) {
	&Sympa::Log::do_log('info', 'del %s@%s %s from %s refused, no such list ', $listname,$robot,$email,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Undefined list')
	    ->faultdetail("Undefined list");
    }

    # check authorization

    my $result = $list->check_list_authz('del','md5',
					 {'sender' => $sender, 
					  'email' => $email,
					  'remote_host' => $ENV{'REMOTE_HOST'},
					  'remote_addr' => $ENV{'REMOTE_ADDR'},
					  'remote_application_name' => $ENV{'remote_application_name'}} );

    
    my $action;
    my $reason;
    if (ref($result) eq 'HASH') {
	$action = $result->{'action'};
	$reason = $result->{'reason'};
    }

    unless (defined $action){
	&Sympa::Log::do_log('info', 'del %s@%s %s from %s : scenario error', $listname,$robot,$email,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('scenario error')
	    ->faultdetail("sender $sender email $email remote $ENV{'remote_application_name'} ");
    }

    unless ($action =~ /do_it/) {
	my $reason_string = &get_reason_string($reason,$robot);
	&Sympa::Log::do_log('info', '%s@%s %s from %s by %srefused (not allowed)', $listname,$robot,$email,$sender,$ENV{'remote_application_name'});
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Not allowed')
	    ->faultdetail($reason_string);
    }

    my $user_entry = $list->get_list_member($email);
    unless ((defined $user_entry)) {
	    &Sympa::Log::do_log('info', 'DEL %s %s from %s refused, not on list', $listname, $email, $sender);
	    die SOAP::Fault->faultcode('Client')
		->faultstring('Not subscribed')
		->faultdetail('Not member of list or not subscribed');
	}
    
    my $gecos = $user_entry->{'gecos'};
    
    
    ## Really delete and rewrite to disk.
    my $u;
    unless ($u = $list->delete_list_member('users' => [$email], 'exclude' =>' 1')){
	my $error = "Unable to delete user $email from list $listname for command 'del'";
	&Sympa::Log::do_log('info', 'DEL %s %s from %s failed, '.$error);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Unable to remove subscriber informations')
	    ->faultdetail('Database access failed');	  
    }
    
    
    ## Send a notice to the removed user, unless the owner indicated
    ## quiet del.
    unless ($quiet || $action =~ /quiet/i) {
	unless ($list->send_file('removed', $email, $robot, {'auto_submitted' => 'auto-generated'})) {
	    &Sympa::Log::do_log('notice',"Unable to send template 'removed' to $email");
	}
    }
    
    
    &Sympa::Log::do_log('info', 'DEL %s %s from %s accepted (%d subscribers)', $listname, $email, $sender,  $list->get_total() );
    if ($action =~ /notify/i) {
	unless ($list->send_notify_to_owner('notice',{'who' => $email, 
						      'gecos' => "", 
						      'command' => 'del',
						      'by' => $sender})) {
	    &Sympa::Log::do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
	}
    }
    return 1;
}

=head2 Sympa::SOAP->review($listname)

=head3 Parameters

=over

=item * I<$listname>

=back

=cut

sub review {
    my $class = shift;
    my $listname  = shift;
    
    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not authentified')
	    ->faultdetail('You should login first');
    }
    

    my @resultSoap;

    unless ($listname) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters')
	    ->faultdetail('Use : <list>');
    }
	
    &Sympa::Log::do_log('debug', '(%s,%s)', $listname,$robot);

    my $list = new Sympa::List ($listname, $robot);
    unless ($list) {
	&Sympa::Log::do_log('info', 'Review %s from %s refused, list unknown to robot %s', $listname,$sender,$robot);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Unknown list')
	    ->faultdetail("List $listname unknown");
    }

    my $sympa = &Sympa::Configuration::get_robot_conf($robot,'sympa');

    my $user;

    # Part of the authorization code
    $user = &Sympa::List::get_global_user($sender);
     
    my $result = $list->check_list_authz('review','md5',
					 {'sender' => $sender,
					  'remote_application_name' =>  $ENV{'remote_application_name'} }
					 );
    my $action;
    $action = $result->{'action'} if (ref($result) eq 'HASH');

    die SOAP::Fault->faultcode('Server')
	->faultstring('No action available')
	unless (defined $action);

    if ($action =~ /reject/i) {
	my $reason_string = &get_reason_string($result->{'reason'},$robot);
	&Sympa::Log::do_log('info', '%s from %s refused (not allowed)', $listname,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Not allowed')
		->faultdetail($reason_string);
    }
    if ($action =~ /do_it/i) {
	my $is_owner = $list->am_i('owner', $sender);
	
	## Members list synchronization if include is in use
	if ($list->has_include_data_sources()) {
	    unless ($list->on_the_fly_sync_include('use_ttl'=>1)) {
		&Sympa::Log::do_log('notice','Unable to synchronize list %s.', $listname);
	    }
	}
	unless ($user = $list->get_first_list_member({'sortby' => 'email'})) {
	    &Sympa::Log::do_log('err', "no subscribers in list '%s'", $list->{'name'});
	    push @resultSoap, SOAP::Data->name('result')->type('string')->value('no_subscribers');
	    return SOAP::Data->name('return')->value(\@resultSoap);
	}
	do {
	    ## Owners bypass the visibility option
	    unless ( ($user->{'visibility'} eq 'conceal') 
		     and (! $is_owner) ) {
		
		## Lower case email address
		$user->{'email'} =~ y/A-Z/a-z/;
		push @resultSoap, SOAP::Data->name('item')->type('string')->value($user->{'email'});
	    }
	} while ($user = $list->get_next_list_member());
	&Sympa::Log::do_log('info', '%s from %s accepted', $listname, $sender);
	return SOAP::Data->name('return')->value(\@resultSoap);
    }
    &Sympa::Log::do_log('info', '%s from %s aborted, unknown requested action in scenario',$listname,$sender);
    die SOAP::Fault->faultcode('Server')
	->faultstring('Unknown requested action')
	    ->faultdetail("%s from %s aborted because unknown requested action in scenario",$listname,$sender);
}

=head2 Sympa::SOAP->fullReview($listname)

=head3 Parameters

=over

=item * I<$listname>

=back

=cut

sub fullReview {
	my $class = shift;
	my $listname  = shift;
	
	my $sender = $ENV{'USER_EMAIL'};
	my $robot = $ENV{'SYMPA_ROBOT'};
	
	unless($sender) {
		die SOAP::Fault->faultcode('Client')
			->faultstring('User not authentified')
			->faultdetail('You should login first');
	}
	
	unless($listname) {
		die SOAP::Fault->faultcode('Client')
			->faultstring('Incorrect number of parameters')
			->faultdetail('Use : <list>');
	}
	
	&Sympa::Log::do_log('debug', '(%s,%s)', $listname, $robot);
	
	my $list = new Sympa::List($listname, $robot);
	unless($list) {
		&Sympa::Log::do_log('info', 'Review %s from %s refused, list unknown to robot %s', $listname, $sender, $robot);
		die SOAP::Fault->faultcode('Server')
			->faultstring('Unknown list')
			->faultdetail("List $listname unknown");
	}
	
	unless($list->is_listmaster($sender, $robot) || $list->am_i('owner', $sender)) {
		die SOAP::Fault->faultcode('Client')
			->faultstring('Not enough privileges')
			->faultdetail('Listmaster or listowner required');
	}
	
	my $sympa = &Sympa::Configuration::get_robot_conf($robot, 'sympa');
	
	my $is_owner = $list->am_i('owner', $sender);
	
	## Members list synchronization if include is in use
	if($list->has_include_data_sources()) {
		unless($list->on_the_fly_sync_include('use_ttl' => 1)) {
			&Sympa::Log::do_log('notice','Unable to synchronize list %s.', $listname);
		}
	}
	
	my $members;
	my $user;
	if($user = $list->get_first_list_member({'sortby' => 'email'})) {
		do {
			$user->{'email'} =~ y/A-Z/a-z/;
			
			my $res;
			$res->{'email'} = $user->{'email'};
			$res->{'gecos'} = $user->{'gecos'};
			$res->{'isOwner'} = 0;
			$res->{'isEditor'} = 0;
			$res->{'isSubscriber'} = 0;
			if($list->is_list_member($user->{'email'})) {
				$res->{'isSubscriber'} = 1;
			}
			
			$members->{$user->{'email'}} = $res;
		} while ($user = $list->get_next_list_member());
	}
	
	my $editors = $list->get_editors();
	if($editors) {
		foreach my $user (@$editors) {
			$user->{'email'} =~ y/A-Z/a-z/;
			if(defined $members->{$user->{'email'}}) {
				$members->{$user->{'email'}}{'isEditor'} = 1;
			}else{
				my $res;
				$res->{'email'} = $user->{'email'};
				$res->{'gecos'} = $user->{'gecos'};
				$res->{'isOwner'} = 0;
				$res->{'isEditor'} = 1;
				$res->{'isSubscriber'} = 0;
				$members->{$user->{'email'}} = $res;
			}
		}
	}
	
	my $owners = $list->get_owners();
	if($owners) {
		foreach my $user (@$owners) {
			$user->{'email'} =~ y/A-Z/a-z/;
			if(defined $members->{$user->{'email'}}) {
				$members->{$user->{'email'}}{'isOwner'} = 1;
			}else{
				my $res;
				$res->{'email'} = $user->{'email'};
				$res->{'gecos'} = $user->{'gecos'};
				$res->{'isOwner'} = 1;
				$res->{'isEditor'} = 0;
				$res->{'isSubscriber'} = 0;
				$members->{$user->{'email'}} = $res;
			}
		}
	}
	
	my @result;
	foreach my $email (keys %$members) {
		push @result, struct_to_soap($members->{$email});
	}
	
	&Sympa::Log::do_log('info', '%s from %s accepted', $listname, $sender);
	return SOAP::Data->name('return')->value(\@result);
}

=head2 Sympa::SOAP->signoff($listname)

=head3 Parameters

=over

=item * I<$listname>

=back

=cut

sub signoff {
    my ($class,$listname)=@_;

    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};

    &Sympa::Log::do_log('notice', '(%s,%s)', $listname,$sender);
    
    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not authentified')
	    ->faultdetail('You should login first');
    }
    
    unless ($listname) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('Incorrect number of parameters.')
	    ->faultdetail('Use : <list> ');
    }
    
    
    my $l;
    my $list = new Sympa::List ($listname, $robot);
    
    ## Is this list defined
    unless ($list) {
	&Sympa::Log::do_log('info', 'from %s for %s refused, list unknown', $listname,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Unknown list.')
	    ->faultdetail("List $listname unknown");	
    }
    
    my $host = &Sympa::Configuration::get_robot_conf($robot,'host');
    
    if ($listname eq '*') {
	my $success;
	foreach my $list  ( &Sympa::List::get_which ($sender,$robot,'member') ){
	    my $l = $list->{'name'};

	    $success ||= &signoff($l,$sender);
	}
	return SOAP::Data->name('result')->value($success);
    } 
    
    $list = new Sympa::List ($listname, $robot);
    
    # Part of the authorization code
    my $user = &Sympa::List::get_global_user($sender);
    
    my $result = $list->check_list_authz('unsubscribe','md5',
					 {'email' => $sender,
					  'sender' => $sender,
					  'remote_application_name' =>  $ENV{'remote_application_name'} }
					 );
    my $action;
    $action = $result->{'action'} if (ref($result) eq 'HASH');

    die SOAP::Fault->faultcode('Server')
	->faultstring('No action available.')
	unless (defined $action);   
    
    if ($action =~ /reject/i) {
	my $reason_string = &get_reason_string($result->{'reason'},$robot);
	&Sympa::Log::do_log('info', 'from %s for the email %s of the user %s refused (not allowed)',  
		     $listname,$sender,$sender);
	die SOAP::Fault->faultcode('Server')
	    ->faultstring('Not allowed.')
	    ->faultdetail($reason_string);
    }
    if ($action =~ /do_it/i) {
	## Now check if we know this email on the list and
	## remove it if found, otherwise just reject the
	## command.
	unless ($list->is_list_member($sender)) {
	    &Sympa::Log::do_log('info', '%s from %s refused, not on list', $listname, $sender);
	    
	    ## Tell the owner somebody tried to unsubscribe
	    if ($action =~ /notify/i) {
		unless ($list->send_notify_to_owner('warn-signoff',{'who' => $sender})) {
		    &Sympa::Log::do_log('err',"Unable to send notify 'warn-signoff' to $list->{'name'} listowner");
		}
	    }
	    die SOAP::Fault->faultcode('Server')
		->faultstring('Not allowed.')
		->faultdetail("Email address $sender has not been found on the list $list->{'name'}. You did perhaps subscribe using a different address ?");
	}
	
	## Really delete and rewrite to disk.
	$list->delete_list_member('users' => [$sender], 'exclude' =>' 1');

	## Notify the owner
	if ($action =~ /notify/i) {
	    unless ($list->send_notify_to_owner('notice',{'who' => $sender,
							  'command' => 'signoff'})) {
		&Sympa::Log::do_log('err',"Unable to send notify 'notice' to $list->{'name'} listowner");
	    }
	}

	## Send bye.tpl to sender
	unless ($list->send_file('bye', $sender, $robot,{})) {
	    &Sympa::Log::do_log('err',"Unable to send template 'bye' to $sender");
	}
	
	&Sympa::Log::do_log('info', '%s from %s accepted', $listname, $sender);

     
	return SOAP::Data->name('result')->type('boolean')->value(1);
    }

    &Sympa::Log::do_log('info', '%s from %s aborted, unknown requested action in scenario',$listname,$sender);
  die SOAP::Fault->faultcode('Server')
      ->faultstring('Undef')
	  ->faultdetail("Sign off %s from %s aborted because unknown requested action in scenario",$listname,$sender);
}

=head2 Sympa::SOAP->subscribe($listname, $gecos)

=head3 Parameters

=over

=item * I<$listname>

=item * I<$gecos>

=back

=cut

sub subscribe {
  my ($class,$listname,$gecos)=@_;

  my $sender = $ENV{'USER_EMAIL'};
  my $robot = $ENV{'SYMPA_ROBOT'};

  &Sympa::Log::do_log('info', 'subscribe(%s,%s, %s)', $listname,$sender, $gecos);

  unless ($sender) {
      die SOAP::Fault->faultcode('Client')
	  ->faultstring('User not authentified')
	  ->faultdetail('You should login first');
  }

  unless ($listname) {
      die SOAP::Fault->faultcode('Client')
	  ->faultstring('Incorrect number of parameters')
	      ->faultdetail('Use : <list> [user gecos]');
  } 

  &Sympa::Log::do_log('notice', '(%s,%s)', $listname, $sender);
  
  ## Load the list if not already done, and reject the
  ## subscription if this list is unknown to us.
  my $list = new Sympa::List ($listname, $robot);
  unless ($list) {
      &Sympa::Log::do_log('info', 'Subscribe to %s from %s refused, list unknown to robot %s', $listname,$sender,$robot);
      die SOAP::Fault->faultcode('Server')
	  ->faultstring('Unknown list')
	  ->faultdetail("List $listname unknown");	  
  }

  ## This is a really minimalistic handling of the comments,
  ## it is far away from RFC-822 completeness.
  $gecos =~ s/"/\\"/g;
  $gecos = "\"$gecos\"" if ($gecos =~ /[<>\(\)]/);
  
  ## query what to do with this subscribtion request
  my $result = $list->check_list_authz('subscribe','md5',
				       {'sender' => $sender,
					'remote_application_name' =>  $ENV{'remote_application_name'} }
				       );
  my $action;
  $action = $result->{'action'} if (ref($result) eq 'HASH');

  die SOAP::Fault->faultcode('Server')
      ->faultstring('No action available.')
	  unless (defined $action); 
  
  &Sympa::Log::do_log('debug2', 'action : %s', $action);
  
  if ($action =~ /reject/i) {
      my $reason_string = &get_reason_string($result->{'reason'},$robot);
      &Sympa::Log::do_log('info', 'to %s from %s refused (not allowed)', $listname,$sender);
      die SOAP::Fault->faultcode('Server')
	  ->faultstring('Not allowed.')
	  ->faultdetail($reason_string);
  }
  if ($action =~ /owner/i) {
       
      ## Send a notice to the owners.
      my $keyauth = $list->compute_auth($sender,'add');
      unless ($list->send_notify_to_owner('subrequest',{'who' => $sender,
				   'keyauth' => $list->compute_auth($sender,'add'),
				   'replyto' => &Sympa::Configuration::get_robot_conf($robot, 'sympa'),
							'gecos' => $gecos})) {
	  &Sympa::Log::do_log('err',"Unable to send notify 'subrequest' to $list->{'name'} listowner");
      }

#      $list->send_sub_to_owner($sender, $keyauth, &Sympa::Configuration::get_robot_conf($robot, 'sympa'), $gecos);
      $list->store_subscription_request($sender, $gecos);
      &Sympa::Log::do_log('info', '%s from %s forwarded to the owners of the list',$listname,$sender);
      return SOAP::Data->name('result')->type('boolean')->value(1);
  }
  if ($action =~ /request_auth/i) {
      my $cmd = 'subscribe';
      $list->request_auth ($sender, $cmd, $robot, $gecos );
      &Sympa::Log::do_log('info', '%s from %s, auth requested', $listname,$sender);
      return SOAP::Data->name('result')->type('boolean')->value(1);
  }
  if ($action =~ /do_it/i) {
      
      my $is_sub = $list->is_list_member($sender);
      
      unless (defined($is_sub)) {
	  &Sympa::Log::do_log('err','user lookup failed');
	  die SOAP::Fault->faultcode('Server')
	      ->faultstring('Undef')
	      ->faultdetail("user lookup failed");
      }
      
      if ($is_sub) {
	  
	  ## Only updates the date
	  ## Options remain the same
	  my $user = {};
	  $user->{'update_date'} = time;
	  $user->{'gecos'} = $gecos if $gecos;

	  &Sympa::Log::do_log('err','Subscribe : user already subscribed');

	  die SOAP::Fault->faultcode('Server')
	      ->faultstring('Undef.')
		  ->faultdetail("update user failed" )
		      unless $list->update_list_member($sender, $user);
      }else {
	  
	  my $u;
	  my $defaults = $list->get_default_user_options();
	  %{$u} = %{$defaults};
	  $u->{'email'} = $sender;
	  $u->{'gecos'} = $gecos;
	  $u->{'date'} = $u->{'update_date'} = time;
	  
	  die SOAP::Fault->faultcode('Server')
	      ->faultstring('Undef')
		  ->faultdetail("add user failed")
		      unless $list->add_list_member($u);
      }
      
      if ($Sympa::List::use_db) {
	  my $u = &Sympa::List::get_global_user($sender);
	  
	  &Sympa::List::update_global_user($sender, {'lang' => $u->{'lang'} || $list->{'admin'}{'lang'}
					  });
      }
      
      ## Now send the welcome file to the user
      unless ($action =~ /quiet/i ) {
	  unless ($list->send_file('welcome', $sender, $robot,{})) {
	      &Sympa::Log::do_log('err',"Unable to send template 'bye' to $sender");
	  }
      }
      
      ## If requested send notification to owners
      if ($action =~ /notify/i) {
	  unless ($list->send_notify_to_owner('notice',{'who' => $sender,
				       'gecos' => $gecos,
							'command' => 'subscribe'})) {
	      &Sympa::Log::do_log('err',"Unable to send notify 'notice' to $list->{'name'} listowner");
	  }
      }
      &Sympa::Log::do_log('info', '%s from %s accepted', $listname, $sender);
      

      return SOAP::Data->name('result')->type('boolean')->value(1);
  }

  
  &Sympa::Log::do_log('info', '%s from %s aborted, unknown requested action in scenario',$listname,$sender);
  die SOAP::Fault->faultcode('Server')
      ->faultstring('Undef')
      ->faultdetail("%s from %s aborted because unknown requested action in scenario",$listname,$sender);
}

=head1 INSTANCE METHODS

=head2 $soap->complexWhich()

Which list the user is subscribed to.

TODO: all the lists, for listmaster.

=head3 Parameters

None.

=cut

 sub complexWhich {
     my $self = shift;
     my @result;
     my $sender = $ENV{'USER_EMAIL'};
     &Sympa::Log::do_log('notice', 'xx complexWhich(%s)',$sender);

     $self->which('complex');
 }

=head2 $soap->complexLists($topic, $subtopic)

=head3 Parameters

=over

=item * I<$topic>

=item * I<$subtopic>

=back

=cut

 sub complexLists {
     my $self = shift;
     my $topic = shift || '';
     my $subtopic = shift || '';
     my @result;
     my $sender = $ENV{'USER_EMAIL'};
     &Sympa::Log::do_log('notice', 'complexLists(%s)',$sender);

     $self->lists($topic, $subtopic, 'complex');
 }

=head2 $soap->which($mode)

Which list the user is subscribed to, with a simplified return structure.

TODO: all the lists, for listmaster.

=head3 Parameters

=over

=item * I<$mode>

=back

=cut

sub which {
    my $self = shift;
    my $mode = shift;
    my @result;

    my $sender = $ENV{'USER_EMAIL'};
    my $robot = $ENV{'SYMPA_ROBOT'};

    &Sympa::Log::do_log('notice', 'which(%s,%s)',$sender,$mode);

    unless ($sender) {
	die SOAP::Fault->faultcode('Client')
	    ->faultstring('User not authentified')
	    ->faultdetail('You should login first');
    }
    
    my %listnames;

    
    foreach my $role ('member','owner','editor') {
	foreach my $list( &Sympa::List::get_which($sender,$robot,$role) ){         
	    my $name = $list->{'name'};
	    $listnames{$name} = $list;
	}
    }
    
    foreach my $name (keys %listnames) {
	my $list = $listnames{$name};

	my $list_address;
	my $result_item;

	my $result = $list->check_list_authz('visibility', 'md5',
					     {'sender' =>$sender,
					      'remote_application_name' =>  $ENV{'remote_application_name'} }
					     );
	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');
	next unless ($action =~ /do_it/i);

	$result_item->{'listAddress'} = $name.'@'.$list->{'admin'}{'host'};
	$result_item->{'subject'} = $list->{'admin'}{'subject'};
	$result_item->{'subject'} =~ s/;/,/g;
	$result_item->{'homepage'} = &Sympa::Configuration::get_robot_conf($robot,'wwsympa_url').'/info/'.$name;
	 
	## determine status of user 
	$result_item->{'isOwner'} = 0;
	if (($list->am_i('owner',$sender) || $list->am_i('owner',$sender))) {
	    $result_item->{'isOwner'} = 1;
	}
	$result_item->{'isEditor'} = 0;
	if (($list->am_i('editor',$sender) || $list->am_i('editor',$sender))) {
	     $result_item->{'isEditor'} = 1;
	 }
	$result_item->{'isSubscriber'} = 0;
	if ($list->is_list_member($sender)) {
	    $result_item->{'isSubscriber'} = 1;
	}
	## determine bounce informations of this user for this list
	if ($result_item->{'isSubscriber'}) {
		my $subscriber ;
		if($subscriber = $list->get_list_member($sender)) { 
			$result_item->{'bounceCount'} = 0;
			if ($subscriber->{'bounce'} =~ /^(\d+)\s+(\d+)\s+(\d+)(\s+(.*))?$/) {
				$result_item->{'firstBounceDate'} =  $1;
				$result_item->{'lastBounceDate'} = $2;
				$result_item->{'bounceCount'} = $3;
				if ($4 =~ /^\s*(\d+\.(\d+\.\d+))$/) {
				$result_item->{'bounceCode'} = $1;
				}	
			}
			$result_item->{'bounceScore'} = $subscriber->{'bounce_score'};
		}
	}
	
	my $listInfo;
	if ($mode eq 'complex') {
	    $listInfo = struct_to_soap($result_item);
	}else {
	    $listInfo = struct_to_soap($result_item, 'as_string');
	}
	push @result, $listInfo;	
    }
    
#    return SOAP::Data->name('return')->type->('ArrayOfString')->value(\@result);
    return SOAP::Data->name('return')->value(\@result);
}

=head1 FUNCTIONS

=head2 struct_to_soap($data, $format)

Return a structure in SOAP data format
either flat (string) or structured (complexType)

=head3 Parameters

=over

=item * I<$data>

=item * I<$format>

=back

=cut

sub struct_to_soap {
    my ($data, $format) = @_;
    my $soap_data;
    
    unless (ref($data) eq 'HASH') {
	return undef;
    }

    if ($format eq 'as_string') {
	my @all;
	my $formated_data;
	foreach my $k (keys %$data) {
	    my $one_data = $k.'='.$data->{$k};
	    
	    ## Decode from the current charset to perl internal charset
	    ## Then encode strings to UTF-8
            $one_data = &Encode::encode('utf-8', $one_data);

	    push @all, $one_data;
	}

	$formated_data = join ';', @all;
	$soap_data = SOAP::Data->type('string')->value($formated_data);
    }else {	
	my $formated_data;
	foreach my $k (keys %$data) {
	    $formated_data->{$k} = SOAP::Data->name($k)->type($types{'listType'}{$k})->value($data->{$k});
	}

	$soap_data = SOAP::Data->value($formated_data);
    }

    return $soap_data;
}

=head2 get_reason_string($data, $format)

=head3 Parameters

=over

=item * I<$reason>

=item * I<$robot>

=back

=cut

sub get_reason_string {
    my ($reason,$robot) = @_;

    my $data = {'reason' => $reason };
    my $string;
    my $tt2_include_path =  &Sympa::Tools::make_tt2_include_path($robot,'mail_tt2','','',$Sympa::Configuration::Conf{'etc'},$Sympa::Configuration::Conf{'viewmaildir'},$Sympa::Configuration::Conf{'domain'});

    unless (&Sympa::Template::parse_tt2($data,'authorization_reject.tt2' ,\$string, $tt2_include_path)) {
	my $error = &Sympa::Template::get_error();
	&Sympa::List::send_notify_to_listmaster('web_tt2_error', $robot, [$error]);
	&Sympa::Log::do_log('info', "get_reason_string : error parsing");
	return '';
    }
    
    return $string
}

1;
