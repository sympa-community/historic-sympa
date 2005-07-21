# Command.pm - this module does the mail commands processing
# RCS Identication ; $Revision$ ; $Date$ 

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

package Commands;

use strict 'subs';

use Conf;
use Language;
use Log;
use List;
use Version;
use Message;

use Digest::MD5;
use Fcntl;
use DB_File;
use Time::Local;
use MIME::Words;

require 'tools.pl';

use Exporter;
@ISA = ('Exporter');
@EXPORT_OK=('$sender');

my %comms =  ('add' =>			   	     'add',
	      'con|confirm' =>	                     'confirm',
	      'del|delete' =>			     'del',
	      'dis|distribute' =>      		     'distribute',
	      'get' =>				     'getfile',
	      'hel|help|sos' =>			     'help',
	      'inf|info' =>  			     'info',
	      'inv|invite' =>                        'invite',
	      'ind|index' =>			     'index',
	      'las|last' =>                          'last',
	      'lis|lists?' =>			     'lists',
	      'mod|modindex|modind' =>		     'modindex',
	      'qui|quit|end|stop|-' =>		     'finished',
	      'rej|reject' =>			     'reject',
	      'rem|remind' =>                        'remind',
	      'rev|review|who' =>		     'review',
	      'set' =>				     'set',
	      'sub|subscribe' =>             	     'subscribe',
	      'sig|signoff|uns|unsub|unsubscribe' => 'signoff',
	      'sta|stats' =>		       	     'stats',
	      'ver|verify' =>     	             'verify',
	      'whi|which|status' =>     	     'which'
	      );
# command sender
my $sender = '';
# time of the process command 
my $time_command;
## my $msg_file;
# command line to process
my $cmd_line; 
# key authentification if 'auth' is present in the command line
my $auth;
# boolean says if quiet is in the cmd line
my $quiet;
# path of the current mailfile
my $current_msg_filename;

## report message
local @errors_report;
local @notices_report;
local @global_report;

##############################################
#  parse
##############################################
# Parses the command and calls the adequate 
# subroutine with the arguments to the command. 
# 
# IN :-$sender (+): the command sender
#     -$robot (+): robot
#     -$i (+): command line
#     -$current_msg_file (+): current mailfile  
#     -$sign_mod : 'smime'| -
#
# OUT : $status |'unknown_cmd'
#      
##############################################
sub parse {
   $sender = lc(shift);
   my $robot = shift;
   my $i = shift;
   $current_msg_filename = shift;
   my $sign_mod = shift;

   do_log('debug2', 'Commands::parse(%s, %s, %s, %s)', $sender, $robot, $i, $current_msg_filename, $sign_mod );

   my $j;
   $cmd_line = '';

   do_log('notice', "Parsing: %s", $i);
   
   ## allow reply usage for auth process based on user mail replies
   if ($i =~ /auth\s+(\S+)\s+(.+)$/io) {
       $auth = $1;
       $i = $2;
   } else {
       $auth = '';
   }
   
   if ($i =~ /^quiet\s+(.+)$/i) {
       $i = $1;
       $quiet = 1;
   }else {
       $quiet = 0;
   }

   foreach $j (keys %comms) {
       if ($i =~ /^($j)(\s+(.+))?\s*$/i) {
	   $time_command = time;
	   my $args = $3;
	   $args =~ s/^\s*//;
	   $args =~ s/\s*$//;

	   my $status;
	  
	   $cmd_line = $i;
	   $status = & {$comms{$j}}($args, $robot, $sign_mod);

	   return $status ;
       }
   }
   
   ## Unknown command
   return 'unknown_cmd';  
}

##############################################
#  finished
##############################################
#  Do not process what is after this line
# 
# IN : -
#
# OUT : 1 
#      
################################################
sub finished {
    do_log('debug2', 'Commands::finished');

    &global_report_cmd($cmd_line,'finished');
    return 1;
}

##############################################
#  help
##############################################
#  Sends the help file for the software
# 
# IN : - ? 
#      -$robot (+): robot 
#
# OUT : 1 
#      
##############################################
sub help {

    shift;
    my $robot=shift;

    my $sympa = &Conf::get_robot_conf($robot, 'sympa');
    my $host = &Conf::get_robot_conf($robot, 'host');
    my $etc =  &Conf::get_robot_conf($robot, 'etc');

    &do_log('debug', 'Commands::help to robot %s',$robot);

    # sa ne prends pas en compte la structure des répertoires par lang.
    # we should make this utilize Template's chain of responsibility
    if ((-r "$etc/mail_tt2/helpfile.tt2")||("$etc/$robot/mail_tt2/helpfile.tt2")) {
  

	my $data = {};

	my @owner = &List::get_which ($sender, $robot,'owner');
	my @editor = &List::get_which ($sender, $robot, 'editor');
	
	$data->{'is_owner'} = 1 if ($#owner > -1);
	$data->{'is_editor'} = 1 if ($#editor > -1);
	$data->{'user'} =  &List::get_user_db($sender);
	&Language::SetLang($data->{'user'}{'lang'}) if $data->{'user'}{'lang'};
	$data->{'subject'} = MIME::Words::encode_mimewords(sprintf gettext("User guide"));

	unless(&List::send_global_file("helpfile", $sender, $robot, $data)){
	    &do_log('notice',"Unable to send template 'helpfile' to $sender");
	}

    }elsif (-r "--ETCBINDIR--/mail_tt2/helpfile.tt2") {

	my $data = {};

	my @owner = &List::get_which ($sender,$robot, 'owner');
	my @editor = &List::get_which ($sender,$robot, 'editor');
	
	$data->{'is_owner'} = 1 if ($#owner > -1);
	$data->{'is_editor'} = 1 if ($#editor > -1);
	$data->{'subject'} = sprintf gettext("User guide");
	unless (&List::send_global_file("helpfile", $sender, $robot, $data)){
	    &do_log('notice',"Unable to send template 'helpfile' to $sender");
	}

    }else{
	&error_report_cmd($cmd_line,'unable_read_file',{'filename' => "help file", 'sys_msg' => $!});
	&do_log('info', 'HELP from %s refused, file not found', $sender,);
	return undef;
    }

    &do_log('info', 'HELP from %s accepted (%d seconds)',$sender,time-$time_command);
    
    return 1;
}

#####################################################
#  lists
#####################################################
#  Sends back the list of public lists on this node.
# 
# IN : - ? 
#      -$robot (+): robot 
#
# OUT : 1 
#      
####################################################### 
sub lists {
    shift; 
    my $robot=shift;

    my $sympa = &Conf::get_robot_conf($robot, 'sympa');
    my $host = &Conf::get_robot_conf($robot, 'host');

    do_log('debug', 'Commands::lists for robot %s', $robot);

    my $data = {};
    my $lists = {};

    foreach my $l ( &List::get_lists($robot) ) {
	my $list = new List ($l);

	next unless ($list);
	my $action = &List::request_action('visibility','smtp',$robot,
                                            {'listname' => $l,
                                             'sender' => $sender });
	return undef
	    unless (defined $action);

	if ($action eq 'do_it') {
	    $lists->{$l}{'subject'} = $list->{'admin'}{'subject'};
	    $lists->{$l}{'host'} = $list->{'admin'}{'host'};
	}
    }

    my $data = {};
    $data->{'lists'} = $lists;
    
    unless (&List::send_global_file('lists', $sender, $robot, $data)){
	&do_log('notice',"Unable to send template 'lists' to $sender");
    }

    do_log('info', 'LISTS from %s accepted (%d seconds)', $sender, time-$time_command);

    return 1;
}

#####################################################
#  stats
#####################################################
#  Sends the statistics about a list using template
#  'stats_report'
# 
# IN : -$listname (+): list name
#      -$robot (+): robot 
#      -$sign_mod : 'smime' | -
#
# OUT : 'unknown_list'|'not_allowed'|1 
#      
####################################################### 
sub stats {
    my $listname = shift;
    my $robot=shift;
    my $sign_mod=shift;

    do_log('debug', 'Commands::stats(%s)', $listname);

    my $list = new List ($listname, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $listname});
	&do_log('info', 'STATS %s from %s refused, unknown list for robot %s', $listname, $sender,$robot);
	return 'unknown_list';
    }

    my $auth_method = &get_auth_method('stats',$sender,{'type'=>'auth_failed',
							'data'=>{},
							'msg'=> "STATS $listname from $sender"},$sign_mod,$list);
    return 'wrong_auth'
	unless (defined $auth_method);

    my $action = &List::request_action ('review',$auth_method,$robot,
					{'listname' => $listname,
					 'sender' => $sender});

    return undef
	unless (defined $action);

    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	my $tpl = $2;

	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command' => "STATS", 'listname' => $listname});
	}
	do_log('info', 'stats %s from %s refused (not allowed)', $listname,$sender);
	return 'not_allowed';
    }else {
	my %stats = ('msg_rcv' => $list->{'stats'}[0],
		     'msg_sent' => $list->{'stats'}[1],
		     'byte_rcv' => sprintf ('%9.2f', ($list->{'stats'}[2] / 1024 / 1024)),
		     'byte_sent' => sprintf ('%9.2f', ($list->{'stats'}[3] / 1024 / 1024))
		     );
	
	unless ($list->send_file('stats_report', $sender, $robot, {'stats' => \%stats, 
								   'subject' => "STATS $list->{'name'}"})) {
	    &do_log('notice',"Unable to send template 'stats_reports' to $sender");
	}

	
	do_log('info', 'STATS %s from %s accepted (%d seconds)', $listname, $sender, time-$time_command);
    }

    return 1;
}


###############################################
#  getfile
##############################################
# Sends back the requested archive file
# 
# IN : -$which (+): command parameters : listname filename
#      -$robot (+): robot 
#
# OUT : 'unknownlist'|'no_archive'|'not_allowed'|1
#      
############################################### 
sub getfile {
    my($which, $file) = split(/\s+/, shift);
    my $robot=shift;

    do_log('debug', 'Commands::getfile(%s, %s)', $which, $file);

    my $list = new List ($which, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	do_log('info', 'GET %s %s from %s refused, list unknown for robot %s', $which, $file, $sender, $robot);
	return 'unknownlist';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    unless ($list->is_archived()) {
	&error_report_cmd($cmd_line,'empty_archives',{});
	do_log('info', 'GET %s %s from %s refused, archive not found', $which, $file, $sender);
	return 'no_archive';
    }
    ## Check file syntax
    if ($file =~ /(\.\.|\/)/) {
	&error_report_cmd($cmd_line,'no_required_file',{});
	do_log('info', 'GET %s %s from %s, incorrect filename', $which, $file, $sender);
	return 'no_archive';
    }
    unless ($list->archive_exist($file)) {
	&error_report_cmd($cmd_line,'no_required_file',{});
 	do_log('info', 'GET %s %s from %s refused, archive not found', $which, $file, $sender);
	return 'no_archive';
    }
    unless ($list->may_do('get', $sender)) {
	&error_report_cmd($cmd_line,'list_private_no_archive',{});
	do_log('info', 'GET %s %s from %s refused, review not allowed', $which, $file, $sender);
	return 'not_allowed';
    }
    $list->archive_send($sender, $file);
    &do_log('info', 'GET %s %s from %s accepted (%d seconds)', $which, $file, $sender,time-$time_command);

    return 1;
}

###############################################
#  last
##############################################
# Sends back the last archive file
# 
# 
# IN : -$which (+): listname 
#      -$robot (+): robot 
#
# OUT : 'unknownlist'|'no_archive'|'not_allowed'|1
#      
############################################### 
sub last {
    my $which = shift;
    my $robot = shift;

    my $sympa = &Conf::get_robot_conf($robot, 'sympa');

    do_log('debug', 'Commands::last(%s, %s)', $which);

    my $list = new List ($which,$robot);
    unless ($list)  {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	do_log('info', 'LAST %s from %s refused, list unknown for robot %s', $which, $sender, $robot);
	return 'unknownlist';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    unless ($list->is_archived()) {
	&error_report_cmd($cmd_line,'empty_archives',{});
	do_log('info', 'LAST %s from %s refused, list not archived', $which,  $sender);
	return 'no_archive';
    }
    my $file;
    unless ($file = $list->archive_exist('last_message')) {
	&error_report_cmd($cmd_line,'no_required_file',{});
 	do_log('info', 'LAST %s from %s refused, archive not found', $which,  $sender);
	return 'no_archive';
    }
    unless ($list->may_do('get', $sender)) {
	&error_report_cmd($cmd_line,'list_private_no_archive',{});
	do_log('info', 'LAST %s from %s refused, archive access not allowed', $which, $sender);
	return 'not_allowed';
    }

    $list->archive_send($sender,'last_message');

    do_log('info', 'LAST %s from %s accepted (%d seconds)', $which,  $sender,time-$time_command);

    return 1;
}

############################################################
#  index
############################################################
#  Sends the list of archived files of a list
#
# IN : -$which (+): list name
#      -$robot (+): robot 
#
# OUT : 'unknown_list'|'not_allowed'|'no_archive'|1
#
#############################################################
sub index {
    my $which = shift;
    my $robot = shift;


    do_log('debug', 'Commands::index(%s) robot (%s)',$which,$robot);

    my $list = new List ($which, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	do_log('info', 'INDEX %s from %s refused, list unknown for robot %s', $which, $sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});
    
    ## Now check if we may send the list of users to the requestor.
    ## Check all this depending on the values of the Review field in
    ## the control file.
    unless ($list->may_do('index', $sender)) {
	&error_report_cmd($cmd_line,'list_private_no_browse',{});
	do_log('info', 'INDEX %s from %s refused, not allowed', $which, $sender);
	return 'not_allowed';
    }
    unless ($list->is_archived()) {
	&error_report_cmd($cmd_line,'empty_archives',{});
	do_log('info', 'INDEX %s from %s refused, list not archived', $which, $sender);
	return 'no_archive';
    }

    my @l = $list->archive_ls();
    unless ($list->send_file('index_archive',$sender,$robot,{'archives' => \@l })) {
	&do_log('notice',"Unable to send template 'index_archive' to $sender");
    }

    &do_log('info', 'INDEX %s from %s accepted (%d seconds)', $which, $sender,time-$time_command);

    return 1;
}

############################################################
#  review
############################################################
#  Sends the list of subscribers to the requester.
#
# IN : -$listname (+): list name
#      -$robot (+): robot 
#      -$sign_mod : 'smime'| -
#
# OUT : 'unknown_list'|'wrong_auth'|'not_allowed'
#       |'no_subscribers'|1
#
################################################################ 
sub review {
    my $listname  = shift;
    my $robot = shift;
    my $sign_mod = shift ;

    do_log('debug', 'Commands::review(%s,%s,%s)', $listname,$robot,$sign_mod );

    my $sympa = &Conf::get_robot_conf($robot, 'sympa');

    my $user;
    my $list = new List ($listname, $robot);

    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $listname});
	do_log('info', 'REVIEW %s from %s refused, list unknown to robot %s', $listname,$sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    my $auth_method = &get_auth_method('review','',{'type'=>'auth_failed',
						    'data'=>{},
						    'msg'=> "REVIEW $listname from $sender"},$sign_mod,$list);
    return 'wrong_auth'
	unless (defined $auth_method);

    my $action = &List::request_action ('review',$auth_method,$robot,
                                     {'listname' => $listname,
				      'sender' => $sender});

    return undef
	unless (defined $action);

    if ($action =~ /request_auth/i) {
	&do_log ('debug2',"auth requested from $sender");
        $list->request_auth ($sender,'review',$robot);
	&do_log('info', 'REVIEW %s from %s, auth requested (%d seconds)', $listname, $sender,time-$time_command);
	return 1;
    }
    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	my $tpl = $2;
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'review', 'listname' => $listname});  
	}
	&do_log('info', 'review %s from %s refused (not allowed)', $listname,$sender);
	return 'not_allowed';
    }

    my @users;

    if ($action =~ /do_it/i) {
	my $is_owner = $list->am_i('owner', $sender);
	unless ($user = $list->get_first_user({'sortby' => 'email'})) {
	    &error_report_cmd($cmd_line,'no_subscriber',{'listname' => $listname}); 
	    do_log('err', "No subscribers in list '%s'", $list->{'name'});
	    return 'no_subscribers';
	}
	do {
	    ## Owners bypass the visibility option
	    unless ( ($user->{'visibility'} eq 'conceal') 
		     and (! $is_owner) ) {

		## Lower case email address
		$user->{'email'} =~ y/A-Z/a-z/;
		push @users, $user;
	    }
	} while ($user = $list->get_next_user());
	unless ($list->send_file('review', $sender, $robot, {'users' => \@users, 
					     'total' => $list->get_total(),
							     'subject' => "REVIEW $listname"})) {
	    &do_log('notice',"Unable to send template 'review' to $sender");
	}

	&do_log('info', 'REVIEW %s from %s accepted (%d seconds)', $listname, $sender,time-$time_command);
	return 1;
    }
    &do_log('info', 'REVIEW %s from %s aborted, unknown requested action in scenario',$listname,$sender);
    &error_report_cmd($cmd_line,'internal_configuration_error',{'command' => 'review','listname' => $listname}); 
    return undef;
}

############################################################
#  verify
############################################################
#  Verify an S/MIME signature  
#
# IN : -$listname (+): list name
#      -$robot (+): robot 
#      -$sign_mod : 'smime'| -
#
# OUT : 1
#
#############################################################
sub verify {
    my $listname = shift ;
    my $robot = shift;

    my $sign_mod = shift ;
    do_log('debug', 'Commands::verify(%s)', $sign_mod );
    
    my $user;
    
    &Language::SetLang($list->{'admin'}{'lang'});
    
    if ($sign_mod eq 'smime') {
	$auth_method='smime';
	&do_log('info', 'VERIFY successfull from %s', $sender,time-$time_command);
	&notice_report_cmd($cmd_line,'smime',{}); 
    }else{
	&do_log('info', 'VERIFY from %s : could not find correct s/mime signature', $sender,time-$time_command);
	&error_report_cmd($cmd_line,'no_verify_sign',{}); 
    }
    return 1;
}

##############################################################
#  subscribe
##############################################################
#  Subscribes a user to a list. The user sent a subscribe
#  command. Format was : sub list optionnal comment. User can 
#  be informed by template 'welcome'
# 
# IN : -$what (+): command parameters : listname(+), comment
#      -$robot (+): robot 
#      -$sign_mod : 'smime'| -
#
# OUT : 'unknown_list'|'wrong_auth'|'not_allowed'| 1
#
################################################################
sub subscribe {
    my $what = shift;
    my $robot = shift;

    my $sign_mod = shift ;

    do_log('debug', 'Commands::subscribe(%s,%s)', $what,$sign_mod);
    
    $what =~ /^(\S+)(\s+(.+))?\s*$/;
    my($which, $comment) = ($1, $3);
    my $auth_method ;
    
    ## Load the list if not already done, and reject the
    ## subscription if this list is unknown to us.
    my $list = new List ($which, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	do_log('info', 'SUB %s from %s refused, unknown list for robot %s', $which,$sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    ## This is a really minimalistic handling of the comments,
    ## it is far away from RFC-822 completeness.
    $comment =~ s/"/\\"/g;
    $comment = "\"$comment\"" if ($comment =~ /[<>\(\)]/);
    
    ## Now check if the user may subscribe to the list
    
    my $auth_method = &get_auth_method('subscribe',$sender,{'type'=>'wrong_email_confirm',
							    'data'=>{'command'=>'subscription'},
							    'msg'=> "SUB $which from $sender"},$sign_mod,$list);
    return 'wrong_auth'
	unless (defined $auth_method);

    ## query what to do with this subscribtion request
    
    my $action = &List::request_action('subscribe',$auth_method,$robot,
				       {'listname' => $which, 
					'sender' => $sender });
    
    return undef
	unless (defined $action);

    &do_log('debug2', 'action : %s', $action);
    
    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	## deletes the possible tracability files in the spool
	&List::delete_tracability_spool_file($which, $sender);

	my $tpl = $2;
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }	    
	}else {
	   &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'subscribe', 'listname' => $which});  
	}
	&do_log('info', 'SUB %s from %s refused (not allowed)', $which, $sender);
	return 'not_allowed';
    }
    if ($action =~ /owner/i) {

	if ($auth eq '') {
	    my $sub_spoolfile = "$Conf{'queuetracability'}"."/"."$list->{'name'}"."$sender".'.sub';
	    unless (&tools::move_file($current_msg_filename, $sub_spoolfile)) {
		&do_log('err', "Unable to move file %s in %s", $current_msg_filename, $sub_spoolfile);
		return undef;
	    }
	} else {
	    my $auth_spoolfile = "$Conf{'queuetracability'}"."/"."$list->{'name'}"."$sender".'.auth';
	    unless (&tools::move_file($current_msg_filename, $auth_spoolfile)) {
		&do_log('err', "Unable to move file %s in %s", $current_msg_filename, $auth_spoolfile);
		return undef;
	    }
	}

	&notice_report_cmd($cmd_line,'req_forward',{});  
	## Send a notice to the owners.
	unless ($list->send_notify_to_owner('subrequest',{'who' => $sender,
				     'keyauth' => $list->compute_auth($sender,'add'),
				     'replyto' => &Conf::get_robot_conf($robot, 'sympa'),
							  'gecos' => $comment})) {
	    &do_log('info',"Unable to send notify 'subrequest' to $list->{'name'} list owner");
	}
	$list->store_subscription_request($sender, $comment);
	do_log('info', 'SUB %s from %s forwarded to the owners of the list (%d seconds)', $which, $sender,time-$time_command);   
	return 1;
    }
    if ($action =~ /request_auth/i) {
	
	if ($auth eq '') {
	    my $sub_spoolfile = "$Conf{'queuetracability'}"."/"."$list->{'name'}"."$sender".'.sub';
	    unless (&tools::move_file($current_msg_filename, $sub_spoolfile)) {
		&do_log('err', "Unable to move file %s in %s", $current_msg_filename, $sub_spoolfile);
		return undef;
	    }
	}

	my $cmd = 'subscribe';
	$cmd = "quiet $cmd" if $quiet;
	$list->request_auth ($sender, $cmd, $robot, $comment );
	do_log('info', 'SUB %s from %s, auth requested (%d seconds)', $which, $sender,time-$time_command);
	return 1;
    }
    if ($action =~ /do_it/i) {
	
	my $user_entry = $list->get_subscriber($sender);
	my $suffix;

	if (defined $user_entry) {

	    $suffix = 'update';

	    ## Only updates the date
	    ## Options remain the same
	    my $user = {};
	    $user->{'update_date'} = time;
	    $user->{'gecos'} = $comment if $comment;
	    $user->{'subscribed'} = 1;
	    $user->{'how_update'} = 'mail';
	    $user->{'who_update'} = $sender;
	    $user->{'ip_update'} = undef;

	    return undef
		unless $list->update_user($sender, $user);
	}else {

	    $suffix ='init';

	    my $u;
	    my $defaults = $list->get_default_user_options();
	    %{$u} = %{$defaults};
	    $u->{'email'} = $sender;
	    $u->{'gecos'} = $comment;
	    $u->{'date'} = $u->{'update_date'} = time;
	    $u->{'how_init'} = 'mail';
	    $u->{'who_init'} = $sender;

	    return undef  unless $list->add_user($u);
	}
	
	if ($List::use_db) {
	    my $u = &List::get_user_db($sender);
	    
	    &List::update_user_db($sender, {'lang' => $u->{'lang'} || $list->{'admin'}{'lang'},
					    'password' => $u->{'password'} || &tools::tmp_passwd($sender)
					    });
	}
	
	$list->save();

	my $tracability_dir = $list->{'dir'}.'/tracability';
	unless (-e $tracability_dir) {
		unless (mkdir ($tracability_dir, 0777)) {
			&do_log('err',"Unable to create %s : %s", $tracability_dir, $!);
			return undef;
    		}
	}

	my $sub_spoolfile; 
	my $auth_spoolfile;
	my $sub_dirfile = "$list->{'dir'}/tracability/$sender".'.sub.'."$suffix";
	my $auth_dirfile = "$list->{'dir'}/tracability/$sender".'.auth.'."$suffix";

	unless (&List::research_tracability_spool_file($list, $sender, 'sub') && &List::research_tracability_spool_file($list, $sender, 'auth')) {
	    &do_log('err','research of tracability spoolfile failed');
	    return undef;
	}

	if (&List::research_tracability_spool_file($list, $sender, 'sub') eq 'present') {
	    $sub_spoolfile = "$Conf{'queuetracability'}"."/"."$list->{'name'}"."$sender".'.sub'; 
	    if (&List::research_tracability_spool_file($list, $sender, 'auth') eq 'present') {
		$auth_spoolfile = "$Conf{'queuetracability'}"."/"."$list->{'name'}"."$sender".'.auth'; 
		unless (&tools::move_file($sub_spoolfile, $sub_dirfile)) {
		    &do_log('err', "Unable to move file %s in %s", $sub_spoolfile, $sub_dirfile);
		    return undef;
		}
		unless (&tools::move_file($auth_spoolfile, $auth_dirfile)) {
		    &do_log('err', "Unable to move file %s in %s", $auth_spoolfile, $auth_dirfile);
		    return undef;
		}
	    }
	    elsif ($auth ne '') {
		unless (&tools::move_file($sub_spoolfile, $sub_dirfile)) {
		    &do_log('err', "Unable to move file %s in %s", $sub_spoolfile, $sub_dirfile);
		    return undef;
		}
		unless (&tools::move_file($current_msg_filename, $auth_dirfile)) {
		    &do_log('err', "Unable to move file %s in %s", $current_msg_filename, $auth_dirfile);
		    return undef;
		}
	    }
	} else {
	    unless (&tools::move_file($current_msg_filename, $sub_dirfile)) {
		&do_log('err', "Unable to move file %s in %s", $current_msg_filename, $sub_dirfile);
		return undef;
	    }
	}

	## deletes the possible tracability files in the spool
	&List::delete_tracability_spool_file($which, $sender);

	## Now send the welcome file to the user
	unless ($quiet || ($action =~ /quiet/i )) {
	    unless ($list->send_file('welcome', $sender, $robot,{})) {
		&do_log('notice',"Unable to send template 'welcome' to $sender");
	    }
	}

	## If requested send notification to owners
	if ($action =~ /notify/i) {
	    unless ($list->send_notify_to_owner('notice',{'who' => $sender, 
					 'gecos' =>$comment, 
							  'command' => 'subscribe'})) {
		&do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
	}

	}
	&do_log('info', 'SUB %s from %s accepted (%d seconds, %d subscribers)', $which, $sender, time-$time_command, $list->get_total());
	
	return 1;
    }
    
    do_log('info', 'SUB %s  from %s aborted, unknown requested action in scenario',$which,$sender);
    &error_report_cmd($cmd_line,'internal_configuration_error',{'command' => 'subscribe','listname' => $listname}); 
    return undef;
}

############################################################
#  info
############################################################
#  Sends the information file to the requester
# 
# IN : -$listname (+): concerned list
#      -$robot (+): robot 
#      -$sign_mod : 'smime'|undef
#
# OUT : 'unknown_list'|'wrong_auth'|'not_allowed' 
#       | 1
#      
#
############################################################## 
sub info {
    my $listname = shift;
    my $robot = shift;
    my $sign_mod = shift ;

    do_log('debug', 'Commands::info(%s,%s)', $listname,$robot);

    my $sympa = &Conf::get_robot_conf($robot, 'sympa');

    my $list = new List ($listname, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $listname});
	&do_log('info', 'INFO %s from %s refused, unknown list for robot %s', $listname,$sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    my $auth_method = &get_auth_method('info','',{'type'=>'auth_failed',
						  'data'=>{},
						  'msg'=> "INFO $listname from $sender"},$sign_mod,$list);
	

    return 'wrong_auth'
	unless (defined $auth_method);

    my $action = &List::request_action('info',$auth_method,$robot,
				       {'listname' => $listname, 
					'sender' => $sender });
    
    return undef
	unless (defined $action);

    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {

	my $tpl = $2;
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'info', 'listname' => $listname});  
	}
	&do_log('info', 'review %s from %s refused (not allowed)', $listname,$sender);
	return 'not_allowed';
    }
    if ($action =~ /do_it/i) {

	my $data;
	foreach my $key (%{$list->{'admin'}}) {
	    $data->{$key} = $list->{'admin'}{$key};
	}

	foreach my $p ('subscribe','unsubscribe','send','review') {
	    $data->{$p} = $list->{'admin'}{$p}{'title'}{'gettext'}; 
	}

	## Digest
	my @days;
	if (defined $list->{'admin'}{'digest'}) {
	    
	    foreach my $d (@{$list->{'admin'}{'digest'}{'days'}}) {
		push @days, &POSIX::strftime("%A", localtime(0 + ($d +3) * (3600 * 24)))
		}
	    $data->{'digest'} = join (',', @days).' '.$list->{'admin'}{'digest'}{'hour'}.':'.$list->{'admin'}{'digest'}{'minute'};
	}

	$data->{'available_reception_mode'} = $list->available_reception_mode();

	my $wwsympa_url = &Conf::get_robot_conf($robot, 'wwsympa_url');
	$data->{'url'} = $wwsympa_url.'/info/'.$list->{'name'};

	unless ($list->send_file('info_report', $sender, $robot, $data)){
	    &do_log('notice',"Unable to send template 'info_report' to $sender");
	}

	do_log('info', 'INFO %s from %s accepted (%d seconds)', $listname, $sender,time-$time_command);
	return 1;
    }

    &do_log('info', 'INFO %s  from %s aborted, unknown requested action in scenario',$listname,$sender);
    &error_report_cmd($cmd_line,'internal_configuration_error',{'command' => 'info','listname' => $listname}); 
    return undef;

}

##############################################################
#  signoff
##############################################################
#  Unsubscribes a user from a list. The user sent a signoff
# command. Format was : sig list. He can be informed by template 'bye'
# 
# IN : -$which (+): command parameters : listname(+), email(+)
#      -$robot (+): robot 
#      -$sign_mod : 'smime'| -
#
# OUT : 'syntax_error'|'unknown_list'|'wrong_auth'
#       |'not_allowed'| 1
#      
#
##############################################################
sub signoff {
    my $which = shift;
    my $robot = shift;

    my $sign_mod = shift ;
    do_log('debug', 'Commands::signoff(%s,%s)', $which,$sign_mod);

    my ($l,$list,$auth_method);
    my $host = &Conf::get_robot_conf($robot, 'host');

    ## $email is defined if command is "unsubscribe <listname> <e-mail>"    
    unless ($which =~ /^(\*|[\w\.\-]+)(\@$host)?(\s+(.+))?$/) {
	&error_report_cmd($cmd_line,'error_syntax',{}); 
	&do_log ('notice', "Command syntax error\n");
        return 'syntax_error';
    }

    ($which,$email) = ($1,$4||$sender);
    
    if ($which eq '*') {
	my $success ;
	foreach $l ( List::get_which ($email,$robot,'member') ){

	    ## Skip hidden lists
	    if (&List::request_action ('visibility', 'smtp',$robot,
				       {'listname' =>  $l,
					'sender' => $sender}) =~ /reject/) {
		next;
	    }
	    
	    my $result = &signoff("$l $email", $robot);
            $success ||= $result;
	}
	return ($success);
    }

    $list = new List ($which, $robot);
    
    ## Is this list defined
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	do_log('info', 'SIG %s %s from %s, unknown list for robot %s', $which,$email,$sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    my $auth_method = &get_auth_method('signoff',$email,{'type'=>'wrong_email_confirm',
							 'data'=>{'command'=>'unsubscription'},
							 'msg'=> "SIG $which from $sender"},$sign_mod,$list);
    return 'wrong_auth'
	unless (defined $auth_method);
    
    my $action = &List::request_action('unsubscribe',$auth_method,$robot,
				       {'listname' => $which, 
					'email' => $email,
					'sender' => $sender });
    
    return undef
	unless (defined $action);

    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	my $tpl = $2;
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'unsubscribe', 'listname' => $which}); 
	}
	&do_log('info', 'SIG %s %s from %s refused (not allowed)', $which, $email, $sender);
	return 'not_allowed';
    }
    if ($action =~ /request_auth\s*\(\s*\[\s*(email|sender)\s*\]\s*\)/i) {
	my $cmd = 'signoff';
	$cmd = "quiet $cmd" if $quiet;
	$list->request_auth ($$1, $cmd, $robot);
	&do_log('info', 'SIG %s from %s auth requested (%d seconds)', $which, $sender,time-$time_command);
	return 1;
    }

    if ($action =~ /owner/i) {
	&notice_report_cmd($cmd_line,'req_forward',{}) 
	    unless ($action =~ /quiet/i);
	## Send a notice to the owners.
	unless ($list->send_notify_to_owner('sigrequest',{'who' => $sender,
							  'keyauth' => $list->compute_auth($sender,'del')})) {
	    &do_log('info',"Unable to send notify 'sigrequest' to $list->{'name'} list owner");
	} 
	do_log('info', 'SIG %s from %s forwarded to the owners of the list (%d seconds)', $which, $sender,time-$time_command);   
	return 1;
    }
    if ($action =~ /do_it/i) {
	## Now check if we know this email on the list and
	## remove it if found, otherwise just reject the
	## command.
	my $user_entry = $list->get_subscriber($email);
	unless ((defined $user_entry) && ($user_entry->{'subscribed'} == 1)) {
	    &error_report_cmd($cmd_line,'your_email_not_found',{'email'=> $email, 'listname' => $list->{'name'}}); 
	    &do_log('info', 'SIG %s from %s refused, not on list', $which, $email);
	    
	    ## Tell the owner somebody tried to unsubscribe
	    if ($action =~ /notify/i) {
		unless ($list->send_notify_to_owner('warn-signoff',{'who' => $email, 
								    'gecos' => $comment})) {
		    &do_log('info',"Unable to send notify 'warn-signoff' to $list->{'name'} list owner");
		}
	    }
	    return 'not_allowed';
	}
	
	if ($user_entry->{'included'} == 1) {
	    unless ($list->update_user($email, 
				       {'subscribed' => 0,
					'update_date' => time,
					'who_init' => undef,
					'who_update' => undef,
					'how_init' => undef,
					'how_update' => undef,
					'ip_init' => undef,
					'ip_update' => undef})) {
		do_log('info', 'SIG %s from %s failed, database update failed', $which, $email);
		return undef;
	    }

	}else {
	    ## Really delete and rewrite to disk.
	    $list->delete_user($email);
	}
	
	unless ($list->delete_tracability_dir_file($email, 'init') || $list->delete_tracability_dir_file($email, 'update')) {
	    &do_log('info', 'SIG %s from %s failed, delete tracability files failed', $which, $email);
	    return undef;
	}	

	## Notify the owner
	if ($action =~ /notify/i) {
	    unless ($list->send_notify_to_owner('notice',{'who' => $email, 
							  'gecos' => $comment, 
							  'command' => 'signoff'})) {
		&do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
	    } 
	}
	
	$list->save();

	unless ($quiet || ($action =~ /quiet/i)) {
	    ## Send bye file to subscriber
	    unless ($list->send_file('bye', $email, $robot, {})) {
		&do_log('notice',"Unable to send template 'bye' to $email");
	    }
	}

	do_log('info', 'SIG %s from %s accepted (%d seconds, %d subscribers)', $which, $email, time-$time_command, $list->get_total() );
	
	return 1;	    
    }
    return undef;
}

############################################################
#  add                           
############################################################
#  Adds a user to a list (requested by another user). Verifies 
#  the proper authorization and sends acknowledgements unless 
#  quiet add.
# 
# IN : -$what (+): command parameters : listname(+), 
#                                    email(+), comments
#      -$robot (+): robot 
#      -$sign_mod : 'smime'|undef
#
# OUT : 'unknown_list'|'wrong_auth'|'not_allowed' 
#       | 1
#      
#
############################################################
sub add {
    my $what = shift;
    my $robot = shift;

    my $sign_mod = shift ;

    do_log('debug', 'Commands::add(%s,%s)', $what,$sign_mod );

    $what =~ /^(\S+)\s+($tools::regexp{'email'})(\s+(.+))?\s*$/;
    my($which, $email, $comment) = ($1, $2, $6);
    my $auth_method ;

    ## Load the list if not already done, and reject the
    ## subscription if this list is unknown to us.
    my $list = new List ($which, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	&do_log('info', 'ADD %s %s from %s refused, unknown list for robot %s', $which, $email,$sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});
    
    my $auth_method = &get_auth_method('add',$email,{'type'=>'wrong_email_confirm',
						     'data'=>{'command'=>'addition'},
						     'msg'=> "ADD $which $email from $sender"},$sign_mod,$list);
    return 'wrong_auth'
	unless (defined $auth_method);    
    
    my $action = &List::request_action('add',$auth_method,$robot,
				       {'listname' => $which, 
					'email' => $email,
					'sender' => $sender });
    
    return undef
	unless (defined $action);

    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	my $tpl = $2;
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'add', 'listname' => $which});  
	}
	&do_log('info', 'ADD %s %s from %s refused (not allowed)', $which, $email, $sender);
	return 'not_allowed';
    }
    
    if ($action =~ /request_auth/i) {
	my $cmd = 'add';
	$cmd = "quiet $cmd" if $quiet;
        $list->request_auth ($sender, $cmd, $robot, $email, $comment);
	&do_log('info', 'ADD %s from %s, auth requested(%d seconds)', $which, $sender,time-$time_command);
	return 1;
    }

    if ($action =~ /do_it/i) {
	
	my $subscribe;

	unless ($list->is_user($email)) {
	    if (($list->delete_subscription_request($email) eq 'deleted') && ($auth ne '')) {
		$subscribe = 1;

		my $tracability_dir = $list->{'dir'}.'/tracability';
		unless (-e $tracability_dir) {
		    unless (mkdir ($tracability_dir, 0777)) {
			&do_log('err',"Unable to create %s : %s", $tracability_dir, $!);
			return undef;
		    }
		}
	    
		my $sub_spoolfile; 
		my $auth_spoolfile;
		my $sub_dirfile = "$list->{'dir'}/tracability/$email".'.sub.init';
		my $auth_dirfile = "$list->{'dir'}/tracability/$email".'.auth.init';
	    
		unless (&List::research_tracability_spool_file($list, $email, 'sub') && &List::research_tracability_spool_file($list, $email, 'auth')) {
		    &do_log('err','research of tracability spoolfile failed');
		    return undef;
		}
	    
		if (&List::research_tracability_spool_file($list, $email, 'sub') eq 'present') {
		    $sub_spoolfile = "$Conf{'queuetracability'}"."/"."$list->{'name'}"."$email".'.sub'; 
		    unless (&tools::move_file($sub_spoolfile, $sub_dirfile)) {
			&do_log('err', "Unable to move file %s in %s", $sub_spoolfile, $sub_dirfile);
			return undef;
		    }
		    if (&List::research_tracability_spool_file($list, $email, 'auth') eq 'present') {
			$auth_spoolfile = "$Conf{'queuetracability'}"."/"."$list->{'name'}"."$email".'.auth'; 
			unless (&tools::move_file($auth_spoolfile, $auth_dirfile)) {
			    &do_log('err', "Unable to move file %s in %s", $auth_spoolfile, $auth_dirfile);
			    return undef;
			}
		    }
		}

		## deletes the possible tracability files in the spool
		&List::delete_tracability_spool_file($which, $email);
	    }
	}

	if ($list->is_user($email)) {
	    my $user = {};
	    $user->{'update_date'} = time;
	    $user->{'gecos'} = $comment if $comment;
	    $user->{'subscribed'} = 1;
	    $user->{'how_update'} = 'mail';
	    $user->{'who_update'} = $sender;
	    $user->{'ip_update'} = undef;
	
	    return undef 
		unless $list->update_user($email, $user);
	    &notice_report_cmd($cmd_line,'updated_info',{'email'=> $email, 'listname' => $which});  
	}else {
	    my $u;
	    my $defaults = $list->get_default_user_options();
	    %{$u} = %{$defaults};
	    $u->{'email'} = $email;
	    $u->{'gecos'} = $comment;
	    $u->{'date'} = $u->{'update_date'} = time;
	    $u->{'how_init'} = 'mail';

	    unless ($subscribe) {
		$u->{'who_init'} = $sender;
	    } else {
		$u->{'who_init'} = $email;
	    }
	    
	    return undef unless $list->add_user($u);
	    &notice_report_cmd($cmd_line,'now_subscriber',{'email'=> $email, 'listname' => $which});  
	}
	
	if ($List::use_db) {
	    my $u = &List::get_user_db($email);
	    
	    &List::update_user_db($email, {'lang' => $u->{'lang'} || $list->{'admin'}{'lang'},
					   'password' => $u->{'password'} || &tools::tmp_passwd($email)
				       });
	}
	
	$list->save();
	
    ## Now send the welcome file to the user if it exists.
	unless ($quiet || ($action =~ /quiet/i )) {
	    unless ($list->send_file('welcome', $email, $robot,{})) {
		&do_log('notice',"Unable to send template 'welcome' to $email");
	    }
	}
	
	do_log('info', 'ADD %s %s from %s accepted (%d seconds, %d subscribers)', $which, $email, $sender, time-$time_command, $list->get_total() );
	if ($action =~ /notify/i) {
	    unless ($list->send_notify_to_owner('notice',{'who' => $email, 
							  'gecos' => $comment,
							  'command' => 'add',
							  'by' => $sender})) {
		&do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
	    }
	}
	return 1;
    }
    
}


############################################################
#  invite
############################################################
#  Invite someone to subscribe a list by sending him 
#  template 'invite'
# 
# IN : -$what (+): listname(+), email(+) and comments
#      -$robot (+): robot 
#      -$sign_mod : 'smime'|undef
#
# OUT : 'unknown_list'|'wrong_auth'|'not_allowed' 
#       | 1
#      
#
##############################################################
sub invite {
    my $what = shift;
    my $robot=shift;
    my $sign_mod = shift ;
    do_log('debug', 'Commands::invite(%s,%s)', $what,$sign_mod);

    my $sympa = &Conf::get_robot_conf($robot, 'sympa');

    $what =~ /^(\S+)\s+(\S+)(\s+(.+))?\s*$/;
    my($which, $email, $comment) = ($1, $2, $4);
    my $auth_method ;

    ## Load the list if not already done, and reject the
    ## subscription if this list is unknown to us.
    my $list = new List ($which, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	&do_log('info', 'INVITE %s %s from %s refused, unknown list for robot', $which, $email,$sender,$robot);
	return 'unknown_list';
    }
    
    &Language::SetLang($list->{'admin'}{'lang'});

    my $auth_method = &get_auth_method('invite',$email,{'type'=>'wrong_email_confirm',
							'data'=>{'command'=>'invitation'},
							'msg'=> "INVITE $which $email from $sender"},$sign_mod,$list);
    return 'wrong_auth'
	unless (defined $auth_method);    
    
    my $action = &List::request_action('invite',$auth_method,$robot,
				       {'listname' => $which, 
					'sender' => $sender });

    return undef
	unless (defined $action);

    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	my $tpl = $2;
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})){
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'invite', 'listname' => $which}); 
	}
	&do_log('info', 'INVITE %s %s from %s refused (not allowed)', $which, $email, $sender);
	return 'not_allowed';
    }
    
    if ($action =~ /request_auth/i) {
        $list->request_auth ($sender, 'invite', $robot, $email, $comment);
	do_log('info', 'INVITE %s from %s, auth requested (%d seconds)', $which, $sender,time-$time_command);
	return 1;
    }
    if ($action =~ /do_it/i) {
	if ($list->is_user($email)) {
	    &error_report_cmd($cmd_line,'already_subscriber',{'email'=> $email, 'listname' => $which}); 
	}else{
            ## Is the guest user allowed to subscribe in this list ?

	    my %context;
	    $context{'user'}{'email'} = $email;
	    $context{'user'}{'gecos'} = $comment;
	    $context{'requested_by'} = $sender;

	    my $action = &List::request_action('subscribe','smtp',$robot,
					       {'listname' => $which, 
						'sender' => $sender });

	    return undef
		unless (defined $action);

            if ($action =~ /request_auth/i) {
		my $keyauth = $list->compute_auth ($email, 'subscribe');
		my $command = "auth $keyauth sub $which $comment";
		$context{'subject'} = $command;
		$context{'url'}= "mailto:$sympa?subject=$command";
		$context{'url'} =~ s/\s/%20/g;
		unless ($list->send_file('invite', $email, $robot, \%context)) {
         	    &do_log('notice',"Unable to send template 'invite' to $email");
		}
		do_log('info', 'INVITE %s %s from %s accepted, auth requested (%d seconds, %d subscribers)', $which, $email, $sender, time-$time_command, $list->get_total() );
		&notice_report_cmd($cmd_line,'invite',{'email'=> $email, 'listname' => $which}); 

	    }elsif ($action !~ /reject/i) {
                $context{'subject'} = "sub $which $comment";
		$context{'url'}= "mailto:$sympa?subject=$context{'subject'}";
		$context{'url'} =~ s/\s/%20/g;
		unless ($list->send_file('invite', $email, $robot,\%context)) {
		    &do_log('notice',"Unable to send template 'invite' to $email");
		}
		do_log('info', 'INVITE %s %s from %s accepted,  (%d seconds, %d subscribers)', $which, $email, $sender, time-$time_command, $list->get_total() );
		&notice_report_cmd($cmd_line,'invite',{'email'=> $email, 'listname' => $which}); 

	    }elsif ($action =~ /reject\(\'?(\w+)\'?\)/i) {
		$tpl = 41;
		do_log('info', 'INVITE %s %s from %s refused, not allowed (%d seconds, %d subscribers)', $which, $email, $sender, time-$time_command, $list->get_total() );
		if ($tpl) {
		    unless ($list->send_file($tpl, $sender, $robot, {})) {
			&do_log('notice',"Unable to send template '$tpl' to $sender");
		    }
		}else {
		    &error_report_cmd($cmd_line,'unwanted_user',{'email'=> $email, 'listname' => $which}); 
		}
	    }
	}
    
	return 1;
    }
}

############################################################
#  remind
############################################################
#  Sends a personal reminder to each subscriber of one list or
#  of every list ($which = *) using template 'remind' or 
#  'global_remind'
#
#
# IN : -$which (+): * | listname
#      -$robot (+): robot 
#      -$sign_mod : 'smime'| -
#
# OUT : 'syntax_error'|'unknown_list'|'wrong_auth'
#       |'not_allowed' 1
#      
#
############################################################## 
sub remind {
    my $which = shift;
    my $robot = shift;
    my $sign_mod = shift ;

    do_log('debug', 'Commands::remind(%s,%s)', $which,$sign_mod);

    my $host = &Conf::get_robot_conf($robot, 'host');
    
    my $auth_method ;
    my %context;
    
    unless ($which =~ /^(\*|[\w\.\-]+)(\@$host)?\s*$/) {
	&error_report_cmd($cmd_line,'error_syntax',{}); 
	do_log ('notice', "Command syntax error\n");
        return 'syntax_error';
    }

    my $listname = $1;
    my $list;

    unless ($listname eq '*') {
	$list = new List ($listname, $robot);
	unless ($list) {
	    &error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	    do_log('info', 'REMIND %s from %s refused, unknown list for robot %s', $which, $sender,$robot);
	    return 'unknown_list';
	}
    }

    my $auth_method;

	if ($listname eq '*') {
	$auth_method = &get_auth_method('remind','',{'type'=>'auth_failed',
						     'data'=>{},
						     'msg'=> "REMIND $listname from $sender"},$sign_mod);
	}else {
	$auth_method = &get_auth_method('remind','',{'type'=>'auth_failed',
						     'data'=>{},
						     'msg'=> "REMIND $listname from $sender"},$sign_mod,$list);
	}

    return 'wrong_auth'
	unless (defined $auth_method);  
	
    my $action;

    if ($listname eq '*') {
	$action = &List::request_action('global_remind',$auth_method,$robot,
					   {'sender' => $sender });
	
    }else{
	
	&Language::SetLang($list->{'admin'}{'lang'});

	$host = $list->{'admin'}{'host'};

	$action = &List::request_action('remind',$auth_method,$robot,
					   {'listname' => $listname, 
					    'sender' => $sender });
    }

    return undef
	unless (defined $action);

    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	my $tpl = $2;
	&do_log ('info',"Remind for list $listname from $sender refused");
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'remind', 'listname' => $listname});  
	}
	return 'not_allowed';
    }elsif ($action =~ /request_auth/i) {
	&do_log ('debug2',"auth requested from $sender");
	if ($listname eq '*') {
	    &List::request_auth ($sender,'remind', $robot);
	}else {
	    $list->request_auth ($sender,'remind', $robot);
	}
	&do_log('info', 'REMIND %s from %s, auth requested (%d seconds)', $listname, $sender,time-$time_command);
	return 1;
    }elsif ($action =~ /do_it/i) {

	if ($listname ne '*') {

	    unless ($list) {
		&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $listname});
		&do_log('info', 'REMIND %s from %s refused, unknown list for robot %s', $listname,$sender,$robot);
		return 'unknown_list';
	    }
	    
	    ## for each subscriber send a reminder
	    my $total=0;
	    my $user;
	    
	    unless ($user = $list->get_first_user()) {
		return undef;
	    }
	    
	    do {
		unless ($list->send_file('remind', $user->{'email'},$robot, {})) {
		    &do_log('notice',"Unable to send template 'remind' to $user->{'email'}");
		}
		$total += 1 ;
	    } while ($user = $list->get_next_user());
	    
	    &notice_report_cmd($cmd_line,'remind',{'total'=> $total,'listname' => $listname});
	    &do_log('info', 'REMIND %s  from %s accepted, sent to %d subscribers (%d seconds)',$listname,$sender,$total,time-$time_command);

	    return 1;
	}else{
	    ## Global REMIND
	    my %global_subscription;
	    my %global_info;
	    my $count = 0 ;

	    $context{'subject'} = gettext("Subscription summary");
	    # this remind is a global remind.
	    foreach my $listname (List::get_lists($robot)){

		my $list = new List ($listname, $robot);
		next unless $list;

		next unless ($user = $list->get_first_user()) ;

		do {
		    my $email = lc ($user->{'email'});
		    if (List::request_action('visibility','smtp',$robot,
					     {'listname' => $listname, 
					      'sender' => $email}) eq 'do_it') {
			push @{$global_subscription{$email}},$listname;
			
			$user->{'lang'} ||= $list->{'admin'}{'lang'};
			
			$global_info{$email} = $user;

			do_log('debug2','remind * : %s subscriber of %s', $email,$listname);
			$count++ ;
		    } 
		} while ($user = $list->get_next_user());
	    }
	    &do_log('debug2','Sending REMIND * to %d users', $count);

	    foreach my $email (keys %global_subscription) {
		my $user = &List::get_user_db($email);
		foreach my $key (keys %{$user}) {
		    $global_info{$email}{$key} = $user->{$key}
		    if ($user->{$key});
		}
		
                $context{'user'}{'email'} = $email;
		$context{'user'}{'lang'} = $global_info{$email}{'lang'};
		$context{'user'}{'password'} = $global_info{$email}{'password'};
		$context{'user'}{'gecos'} = $global_info{$email}{'gecos'};
                @{$context{'lists'}} = @{$global_subscription{$email}};

		unless (&List::send_global_file('global_remind', $email, $robot, \%context)){
		    &do_log('notice',"Unable to send template 'global_remind' to $email");
		}
	    }
	    &notice_report_cmd($cmd_line,'glob_remind',{'count'=> $count});
	}
    }else{
	&do_log('info', 'REMIND %s  from %s aborted, unknown requested action in scenario',$listname,$sender);
	&error_report_cmd($cmd_line,'internal_configuration_error',{'command' => 'remind','listname' => $listname}); 
	return undef;
    }
}



############################################################
#  del                          
############################################################
# Removes a user from a list (requested by another user). 
# Verifies the authorization and sends acknowledgements 
# unless quiet is specified.
# 
# IN : -$what (+): command parameters : listname(+), email(+)
#      -$robot (+): robot 
#      -$sign_mod : 'smime'|undef
#
# OUT : 'unknown_list'|'wrong_auth'|'not_allowed' 
#       | 1
#      
#
############################################################## 
sub del {
    my $what = shift;
    my $robot = shift;

    my $sign_mod = shift ;

    &do_log('debug', 'Commands::del(%s,%s)', $what,$sign_mod);

    $what =~ /^(\S+)\s+($tools::regexp{'email'})\s*/;
    my($which, $who) = ($1, $2);
    my $auth_method;
    
    ## Load the list if not already done, and reject the
    ## subscription if this list is unknown to us.
    my $list = new List ($which, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	do_log('info', 'DEL %s %s from %s refused, unknown list for robot %s', $which, $who,$sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    my $auth_method = &get_auth_method('del',$who,{'type'=>'wrong_email_confirm',
						   'data'=>{'command'=>'delete'},
						   'msg'=> "DEL $which $who from $sender"},$sign_mod,$list);
    return 'wrong_auth'
	unless (defined $auth_method);  

    ## query what to do with this DEL request
    my $action = &List::request_action ('del',$auth_method,$robot,
					{'listname' =>$which,
					 'sender' => $sender,
					 'email' => $who
					 });

    return undef
	unless (defined $action);

    if ($action =~ /reject(\(\'?(\w+)\'?\))?/i) {
	my $tpl = $2;
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    &error_report_cmd($cmd_line,'not_allowed_command',{'command'=>'del', 'listname' => $which});  
	}
	&do_log('info', 'DEL %s %s from %s refused (not allowed)', $which, $who, $sender);
	return 'not_allowed';
    }
    if ($action =~ /request_auth/i) {
	my $cmd = 'del';
	$cmd = "quiet $cmd" if $quiet;
        $list->request_auth ($sender, $cmd, $robot, $who );
	do_log('info', 'DEL %s %s from %s, auth requested (%d seconds)', $which, $who, $sender,time-$time_command);
	return 1;
    }

    if ($action =~ /do_it/i) {
	## Check if we know this email on the list and remove it. Otherwise
	## just reject the message.
	my $user_entry = $list->get_subscriber($who);

	unless ((defined $user_entry) && ($user_entry->{'subscribed'} == 1)) {
	    &error_report_cmd($cmd_line,'email_not_found',{'email'=> $who, 'listname' => $which}); 
	    &do_log('info', 'DEL %s %s from %s refused, not on list', $which, $who, $sender);
	    return 'not_allowed';
	}
	
	## Get gecos before deletion
	my $gecos = $user_entry->{'gecos'};
	
	if ($user_entry->{'included'} == 1) {
	    unless ($list->update_user($who, 
				       {'subscribed' => 0,
					'update_date' => time,
					'who_init' => undef,
					'who_update' => undef,
					'how_init' => undef,
					'how_update' => undef,
					'ip_init' => undef,
					'ip_update' => undef})) {
		&do_log('info', 'DEL %s %s from %s failed, database update failed', $which, $who, $sender);
		return undef;
	    }

	}else {
	    ## Really delete and rewrite to disk.
	    my $u = $list->delete_user($who);
	}
	
	my $tracability_dir = $list->{'dir'}.'/tracability';
	if (-e $tracability_dir) {
	    unless ($list->delete_tracability_dir_file($who, 'init') || $list->delete_tracability_dir_file($who, 'update')) {
		&do_log('info', 'DEL %s %s from %s failed, delete tracability files failed', $which, $who, $sender);
		return undef;
	    }
	}

	$list->save();
	
	## Send a notice to the removed user, unless the owner indicated
	## quiet del.
	unless ($quiet || ($action =~ /quiet/i )) {
	    unless ($list->send_file('removed', $who, $robot, {})) {
		&do_log('notice',"Unable to send template 'removed' to $who");
	}
	}
	&notice_report_cmd($cmd_line,'removed',{'email'=> $who, 'listname' => $which});  
	&do_log('info', 'DEL %s %s from %s accepted (%d seconds, %d subscribers)', $which, $who, $sender, time-$time_command, $list->get_total() );
	if ($action =~ /notify/i) {
	    unless ($list->send_notify_to_owner('notice',{'who' => $who, 
					 'gecos' => "", 
							  'command' => 'del',
							  'by' => $sender})) {
		&do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
	    }
	}
	return 1;
    }
    &do_log('info', 'DEL %s %s from %s aborted, unknown requested action in scenario',$which,$who,$sender);
    &error_report_cmd($cmd_line,'internal_configuration_error',{'command' => 'del','listname' => $listname}); 
    return undef;
}


############################################################
#  set                          
############################################################
#  Change subscription options (reception or visibility)
# 
# IN : -$what (+): command parameters : listname, 
#        reception mode (digest|digestplain|nomail|normal...)
#        or visibility mode(conceal|noconceal)
#      -$robot (+): robot 
#
# OUT : 'syntax_error'|'unknown_list'|'not_allowed'|'failed'|1
#      
#
#############################################################
sub set {
    my $what = shift;
    my $robot = shift;

    do_log('debug', 'Commands::set(%s)', $what);

    $what =~ /^\s*(\S+)\s+(\S+)\s*$/; 
    my ($which, $mode) = ($1, $2);

    ## Unknown command (should be checked....)
    unless ($mode =~ /^(digest|digestplain|nomail|normal|each|mail|conceal|noconceal|summary|notice|txt|html|urlize)$/i) {
	&error_report_cmd($cmd_line,'error_syntax',{}); 
	return 'syntax_error';
    }

    ## SET EACH is a synonim for SET MAIL
    $mode = 'mail' if ($mode =~ /^each|eachmail|nodigest|normal$/i);
    $mode =~ y/[A-Z]/[a-z]/;
    
    ## Recursive call to subroutine
    if ($which eq "*"){
        my ($l);
	my $status;
	foreach $l ( &List::get_which ($sender,$robot,'member')){

	    ## Skip hidden lists
	    if (&List::request_action ('visibility', 'smtp',$robot,
				       {'listname' =>  $l,
					'sender' => $sender}) =~ /reject/) {
		next;
	    }

	    my $current_status = &set ("$l $mode");
	    $status ||= $current_status;
	}
	return $status;
    }

    ## Load the list if not already done, and reject
    ## if this list is unknown to us.
    my $list = new List ($which, $robot);

    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $which});
	do_log('info', 'SET %s %s from %s refused, unknown list for robot %s', $which, $mode, $sender,$robot);
	return 'unknown_list';
    }

    ## No subscriber pref if 'include'
    if ($list->{'admin'}{'user_data_source'} eq 'include') {
	&error_report_cmd($cmd_line,'no_subscriber_preference',{'listname' => $which});
	&do_log('info', 'SET %s %s from %s refused, user_data_source include',  $which, $mode, $sender);
	return 'not allowed';
    }
    
    &Language::SetLang($list->{'admin'}{'lang'});

    ## Check if we know this email on the list and remove it. Otherwise
    ## just reject the message.
    unless ($list->is_user($sender) ) {
	&error_report_cmd($cmd_line,'email_not_found',{'email'=> $email, 'listname' => $which}); 
	&do_log('info', 'SET %s %s from %s refused, not on list',  $which, $mode, $sender);
	return 'not allowed';
    }
    
    ## May set to DIGEST
    if ($mode =~ /^(digest|digestplain|summary)/ and !$list->is_digest()){
	&error_report_cmd($cmd_line,'no_digest',{'listname' => $which}); 
	&do_log('info', 'SET %s DIGEST from %s refused, no digest mode', $which, $sender);
	return 'not_allowed';
    }
    
    if ($mode =~ /^(mail|nomail|digest|digestplain|summary|notice|txt|html|urlize|not_me)/){
        # Verify that the mode is allowed
        if (! $list->is_available_reception_mode($mode)) {
	    &error_report_cmd($cmd_line,'available_reception_mode',{'listname' => $which, 'modes' => $list->available_reception_mode}); 
	    &do_log('info','SET %s %s from %s refused, mode not available', $which, $mode, $sender);
	  return 'not_allowed';
	}

	my $update_mode = $mode;
	$update_mode = '' if ($update_mode eq 'mail');
	unless ($list->update_user($sender,{'reception'=> $update_mode, 'update_date' => time})) {
	    &error_report_cmd($cmd_line,'failed_change_reception',{'listname' => $which});
	    &do_log('info', 'SET %s %s from %s refused, update failed',  $which, $mode, $sender);
	    return 'failed';
	}
	$list->save();
	
	&notice_report_cmd($cmd_line,'config_updated',{'listname' => $which});  

	&do_log('info', 'SET %s %s from %s accepted (%d seconds)', $which, $mode, $sender, time-$time_command);
    }
    
    if ($mode =~ /^(conceal|noconceal)/){
	unless ($list->update_user($sender,{'visibility'=> $mode, 'update_date' => time})) {
	    &error_report_cmd($cmd_line,'failed_change_reception',{'listname' => $which});
	    &do_log('info', 'SET %s %s from %s refused, update failed',  $which, $mode, $sender);
	    return 'failed';
	}
	$list->save();
	
	&notice_report_cmd($cmd_line,'config_updated',{'listname' => $which});  
	&do_log('info', 'SET %s %s from %s accepted (%d seconds)', $which, $mode, $sender, time-$time_command);
    }
    return 1;
}

############################################################
#  distribute                          
############################################################
#  distributes the broadcast of a validated moderated message
# 
# IN : -$what (+): command parameters : listname(+), authentification key(+)
#      -$robot (+): robot 
#
# OUT : 'unknown_list'|'msg_noty_found'| 1
#      
##############################################################
sub distribute {
    my $what =shift;
    my $robot = shift;

    $what =~ /^\s*(\S+)\s+(.+)\s*$/;
    my($which, $key) = ($1, $2);
    $which =~ y/A-Z/a-z/;

    &do_log('debug', 'Commands::distribute(%s,%s,%s,%s)', $which,$robot,$key,$what);

    my $start_time=time; # get the time at the beginning
    ## Load the list if not already done, and reject the
    ## subscription if this list is unknown to us.
    my $list = new List ($which, $robot);
    unless ($list) {
	unless (&List::send_global_file('message_report',$sender,$robot,{'to' => $sender,
									 'type' => 'list_unknown',
									 'listname' => $which})){
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}
	&do_log('info', 'DISTRIBUTE %s %s from %s refused, unknown list for robot %s', $which, $key, $sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    #read the moderation queue and purge it
    my $modqueue =  &Conf::get_robot_conf($robot,'queuemod') ;
    
    my $name = $list->{'name'};
    my $host = $list->{'admin'}{'host'};
    my $file = "$modqueue\/$name\_$key";
    
    ## if the file has been accepted by WWSympa, it's name is different.
    unless (-r $file) {
        $file= "$modqueue\/$name\_$key.distribute";
    }

    ## Open and parse the file
    my $message = new Message($file);
    unless (defined $message) {
	do_log('err', 'Unable to create Message object %s', $file);
	unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
								  'type' => 'unfound_message',
								  'listname' => $which,
								  'key'=> $key})) {
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}
	return 'msg_not_found';
    }

    my $msg = $message->{'msg'};
    my $hdr= $msg->head;

    ## encrypted message ## no used variable ???
    if ($message->{'smime_crypted'}) {
	$is_crypted = 'smime_crypted';
    }else {
	$is_crypted = 'not_crypted';
    }

    $hdr->add('X-Validation-by', $sender);

    ## Distribute the message
    if (($main::daemon_usage eq  'message') || ($main::daemon_usage eq  'command_and_message')) {

	my $numsmtp =$list->distribute_msg($message);
	unless (defined $numsmtp) {
	    return undef;
	}
	unless ($numsmtp) {
	    &do_log('info', 'Message for %s from %s accepted but all subscribers use digest,nomail or summary',$which, $sender);
	} 
	&do_log('info', 'Message for %s from %s accepted (%d seconds, %d sessions), size=%d', $which, $sender, time - $start_time, $numsmtp, $bytes);

	unless ($quiet || ($action =~ /quiet/i )) {
	    unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
								      'type' => 'message_distributed',
								      'listname' => $which,
								      'key' => $key})) {
		&do_log('notice',"Unable to send template 'message_report' to $sender");
	    }
	}
	
	&do_log('info', 'DISTRIBUTE %s %s from %s accepted (%d seconds)', $name, $key, $sender, time-$time_command);
	
    }else{   
	# this message is to be distributed but this daemon is dedicated to commands -> move it to distribution spool
	return undef unless (&tools::move_message($file,$name,$robot)) ;	    
	&do_log('info', 'Message for %s from %s moved in spool %s for distribution message-id=%s', $name, $sender, $Conf{'queuedistribute'},$hdr->get('Message-Id'));
    }
    unlink($file);
    
    return 1;
}


############################################################
#  confirm                           
############################################################
#  confirms the authentification of a message for its 
#  distribution on a list
# 
# IN : -$what (+): command parameter : authentification key
#      -$robot (+): robot 
#
# OUT : 'wrong_auth'|'msg_not_found' 
#       | 1 
#      
#
############################################################
sub confirm {
    my $what = shift;
    my $robot = shift;
    do_log('debug', 'Commands::confirm(%s)', $what);

    $what =~ /^\s*(\S+)\s*$/;
    my $key = $1;
    my $start_time = time; # get the time at the beginning

    my $file;
    my $queueauth = &Conf::get_robot_conf($robot, 'queueauth');

    unless (opendir DIR, $queueauth ) {
        do_log('info', 'WARNING unable to read %s directory', $queueauth);
    }


    # delete old file from the auth directory
    foreach (grep (!/^\./,readdir(DIR))) {
        if (/\_$key$/i){
	    $file= "$queueauth\/$_";
        }
    }
    closedir DIR ;
    
    unless ($file && (-r $file)) {
	unless (&List::send_global_file('message_report',$sender,$robot,{'to' => $sender,
									 'type' => 'unfound_file_message',
									 'key' => $key})){
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}
	
        &do_log('info', 'CONFIRM %s from %s refused, auth failed', $key,$sender);
        return 'wrong_auth';
    }

    my $message = new Message ($file);
    unless (defined $message) {
	do_log('err', 'Unable to create Message object %s', $file);
	unless (&List::send_global_file('message_report',$sender,$robot,{'to' => $sender,
									 'type' => 'wrong_format_message',
									 'key' => $key})){
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}

	return 'msg_not_found';
    }

    my $msg = $message->{'msg'};
    my $list = $message->{'list'};

    &Language::SetLang($list->{'admin'}{'lang'});

    my $name = $list->{'name'};
   
    my $bytes = -s $file;
    my $hdr= $msg->head;

    my $action = &List::request_action('send','md5',$robot,
				       {'listname' => $name, 
					'sender' => $sender ,
					'message' => $message});

    return undef
	unless (defined $action);

    if ($action =~ /^editorkey/) {
	my $key = $list->send_to_editor('md5', $message);
	do_log('info', 'Key %s for list %s from %s sent to editors', $key, $name, $sender);
	unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
								  'type' => 'moderating_message'})) {
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}
	return 1;
    }elsif($action =~ /editor/){
	my $key = $list->send_to_editor('smtp', $message);
	do_log('info', 'Message for %s from %s sent to editors', $name, $sender);
	unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
								  'type' => 'moderating_message'})) {
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}
	return 1;
    }elsif($action =~ /^reject(\(\'?(\w+)\'?\))?/) {
	my $tpl = $2;
   	do_log('notice', 'Message for %s from %s rejected, sender not allowed', $name, $sender);
	if ($tpl) {
	    unless ($list->send_file($tpl, $sender, $robot, {})) {
		&do_log('notice',"Unable to send template '$tpl' to $sender");
	    }
	}else {
	    unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
								      'type' => 'sender_not_allowed',
								      'msg' => $msg->as_string})) {
		&do_log('notice',"Unable to send template 'message_report' to $sender");
	    }

	    return 1;
	}
    }elsif($action =~ /^do_it/) {

	$hdr->add('X-Validation-by', $sender);
	
	## Distribute the message
	if (($main::daemon_usage eq  'message') || ($main::daemon_usage eq  'command_and_message')) {
	    my $numsmtp = $list->distribute_msg($message);
	    unless (defined $numsmtp) {
		do_log('info','Unable to send message to list %s', $list->{'name'});
		return undef;
	    }
 
	    unless ($quiet || ($action =~ /quiet/i )) {
		unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
									  'type' => 'message_distributed',
									  'listname' => $which,
									  'key' => $key})) {
		    &do_log('notice',"Unable to send template 'message_report' to $sender");
		}
	    }
	    &do_log('info', 'CONFIRM %s from %s for list %s accepted (%d seconds)', $key, $sender, $which, time-$time_command);

	}else{
	    # this message is to be distributed but this daemon is dedicated to commands -> move it to distribution spool
	    return undef unless (&tools::move_message($file,$name,$robot)) ;	    
	    do_log('info', 'Message for %s from %s moved in spool %s for distribution message-id=%s', $name, $sender, $Conf{'queuedistribute'},$hdr->get('Message-Id'));
	}
	unlink($file);
	
	return 1;
    }
}

############################################################
#  reject
############################################################
#  Refuse and delete  a moderated message and notify sender 
#  by sending template 'reject'
#
# IN : -$what (+): command parameter : listname and authentification key
#      -$robot (+): robot 
#
# OUT : 'unknown_list'|'wrong_auth'| 1
#      
#
############################################################## 
sub reject {
    my $what = shift;
    my $robot = shift;

    do_log('debug', 'Commands::reject(%s)', $what);

    $what =~ /^(\S+)\s+(.+)\s*$/;
    my($which, $key) = ($1, $2);
    $which =~ y/A-Z/a-z/;
    my $modqueue = &Conf::get_robot_conf($robot,'queuemod');
    ## Load the list if not already done, and reject the
    ## subscription if this list is unknown to us.
    my $list = new List ($which, $robot);
    unless ($list) {
	unless (&List::send_global_file('message_report',$sender,$robot,{'to' => $sender,
									 'type' => 'list_unknown',
									 'listname' => $which})){
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}	
	&do_log('info', 'REJECT %s %s from %s refused, unknown list for robot %s', $which, $key, $sender,$robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    my $name = "$list->{'name'}";
    my $file= "$modqueue\/$name\_$key";


    my $msg;
    my $parser = new MIME::Parser;
    $parser->output_to_core(1);
    unless ($msg = $parser->read(\*IN)) {
	do_log('notice', 'Unable to parse message');
	return undef;
    }

    close(IN);
    
    my $bytes = -s $file;
    my $hdr= $msg->head;
    my $customheader = $list->{'admin'}{'custom_header'};
    my $to_field = $hdr->get('To');


    
    ## Open the file
    if (!open(IN, $file)) {
	unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
								  'type' => 'unfound_message',
								  'listname' => $name,
								  'key'=> $key})){
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}

	&do_log('info', 'REJECT %s %s from %s refused, auth failed', $which, $key, $sender);
	return 'wrong_auth';
    }
    do_log('debug2', 'message to be rejected by %s',$sender);
    unless ($quiet || ($action =~ /quiet/i )) {
	unless ($list->send_file('message_report',$sender,$robot,{'to' => $sender,
								  'type' => 'message_rejected',
								  'listname' => $name,
								  'key'=> $key})){
	    &do_log('notice',"Unable to send template 'message_report' to $sender");
	}

	my $message;
	my $parser = new MIME::Parser;
	$parser->output_to_core(1);
	unless ($message = $parser->read(\*IN)) {
	    do_log('notice', 'Unable to parse message');
	    return undef;
	}

	my @sender_hdr = Mail::Address->parse($message->head->get('From'));
        unless  ($#sender_hdr == -1) {
	    my $rejected_sender = $sender_hdr[0]->address;
	    my %context;
	    $context{'subject'} = &MIME::Words::decode_mimewords($message->head->get('subject'));
	    $context{'rejected_by'} = $sender;
	    do_log('debug2', 'message %s by %s rejected sender %s',$context{'subject'},$context{'rejected_by'},$rejected_sender);

 	    unless ($list->send_file('reject', $rejected_sender, $robot, \%context)){
 		&do_log('notice',"Unable to send template 'reject' to $rejected_sender");
		
	    }
	}
    }
    close(IN);
    do_log('info', 'REJECT %s %s from %s accepted (%d seconds)', $name, $sender, $key, time-$time_command);
    unlink($file);

    return 1;
}


#########################################################
#  modindex
#########################################################
#  Sends a list of current messages to moderate of a list
#  (look into spool queuemod)
#  usage :    modindex <liste> 
# 
# IN : -$name (+): listname  
#      -$robot (+): robot 
#
# OUT : 'unknown_list'|'not_allowed'|'no_file'|1 
#      
######################################################### 
sub modindex {
    my $name = shift;
    my $robot = shift;
    do_log('debug', 'Commands::modindex(%s)', $name);
    
    $name =~ y/A-Z/a-z/;

    my $list = new List ($name, $robot);
    unless ($list) {
	&error_report_cmd($cmd_line,'no_existing_list',{'listname' => $name});
	do_log('info', 'MODINDEX %s from %s refused, unknown list for robot %s', $name, $sender, $robot);
	return 'unknown_list';
    }

    &Language::SetLang($list->{'admin'}{'lang'});

    my $modqueue = &Conf::get_robot_conf($robot,'queuemod');
    
    my $i;
    
    unless ($list->may_do('modindex', $sender)) {
	&error_report_cmd($cmd_line,'restricted_modindex',{});
	&do_log('info', 'MODINDEX %s from %s refused, not allowed', $name,$sender);
	return 'not_allowed';
    }

    # purge the queuemod -> delete old files
    if (!opendir(DIR, $modqueue)) {
	do_log('info', 'WARNING unable to read %s directory', $modqueue);
    }
    my @qfile = sort grep (!/^\.+$/,readdir(DIR));
    closedir(DIR);
    my ($curlist,$moddelay);
    foreach $i (sort @qfile) {

	## Erase diretories used for web modindex
	if (-d "$modqueue/$i") {
	    unlink <$modqueue/$i/*>;
	    rmdir "$modqueue/$i";
	    next;
	}

	$i=~/\_(.+)$/;
	$curlist = new List ($`);
	if ($curlist) {
	    # list loaded    
	    if (exists $curlist->{'admin'}{'clean_delay_queuemod'}){
		$moddelay = $curlist->{'admin'}{'clean_delay_queuemod'}
	    }else{
		$moddelay = &Conf::get_robot_conf($robot,'clean_delay_queuemod');
	    }
	    
	    if ((stat "$modqueue/$i")[9] < (time -  $moddelay*86400) ){
		unlink ("$modqueue/$i") ;
		do_log('notice', 'Deleting unmoderated message %s, too old', $i);
	    };
	}
    }

    opendir(DIR, $modqueue);

    my @files = ( sort grep (/^$name\_/,readdir(DIR)));
    closedir(DIR);
    my $n;
    my @now = localtime(time);

    ## List of messages
    my @spool;

    foreach $i (@files) {
	## skip message allready marked to be distributed using WWS
	next if ($i =~ /.distribute$/) ;

	## Push message for building MODINDEX
	my $raw_msg;
	open(IN, "$modqueue\/$i");
	while (<IN>) {
	    $raw_msg .= $_;
	}
	close IN;
	push @spool, $raw_msg;

	$n++;
    }
    
    unless ($n){
	do_log('info', 'MODINDEX %s from %s refused, no message to moderate', $name, $sender);
	return 'no_file';
    }  
    
    unless ($list->send_file('modindex', $sender, $robot, {'spool' => \@spool,
					   'total' => $n,
					   'boundary1' => "==main $now[6].$now[5].$now[4].$now[3]==",
							   'boundary2' => "==digest $now[6].$now[5].$now[4].$now[3]=="})){
	&do_log('notice',"Unable to send template 'modindex' to $sender");
    }

    do_log('info', 'MODINDEX %s from %s accepted (%d seconds)', $name,
	   $sender,time-$time_command);
    
    return 1;
}


#########################################################
#  which
#########################################################
#  Return list of lists that sender is subscribed. If he is
#  owner and/or editor, managed lists are also noticed.
# 
# IN : - : ?
#      -$robot (+): robot 
#
# OUT : 1 
#      
######################################################### 
sub which {
    my($listname, @which);
    shift;
    my $robot = shift;
    do_log('debug', 'Commands::which(%s)', $listname);
    
    ## Subscriptions
    my $data;
    foreach $listname (List::get_which ($sender,$robot,'member')){
	next unless (&List::request_action ('visibility', 'smtp',$robot,
					    {'listname' =>  $listname,
					     'sender' => $sender}) =~ /do_it/);
	push @{$data->{'lists'}},$listname;
    }

    ## Ownership
    if (@which = List::get_which ($sender,$robot,'owner')){
	foreach $listname (@which){
	    push @{$data->{'owner_lists'}},$listname;
	}
	$data->{'is_owner'} = 1;
    }

    ## Editorship
    if (@which = List::get_which ($sender,$robot,'editor')){
	foreach $listname (@which){
	    push @{$data->{'editor_lists'}},$listname;
	}
	$data->{'is_editor'} = 1;
    }

    unless (&List::send_global_file('which',$sender,$robot,$data)){
	&do_log('notice',"Unable to send template 'which' to $sender");
    }

    do_log('info', 'WHICH from %s accepted (%d seconds)', $sender,time-$time_command);

    return 1;
}


################ Function for authentification #######################

##########################################################
#  get_auth_method
##########################################################
# Checks the authentification and return method 
# used if authentification not failed
# 
# IN :-$cmd (+): current command 
#     -$email (+): used to compute auth
#     -$error (+):ref(HASH) with keys :
#        -type : for message_report.tt2 parsing
#        -data : ref(HASH) for message_report.tt2 parsing
#        -msg : for do_log
#     -$sign_mod (+): 'smime'| -
#     -$list : ref(List) | -
#
# OUT : 'smime'|'md5'|'smtp' if authentification OK, undef else
#      
##########################################################
sub get_auth_method {
    my ($cmd,$email,$error,$sign_mod,$list) = @_;
    &do_log('debug3',"Commands::get_auth_method()");
    
    my $auth_method;

    if ($sign_mod eq 'smime') {
	$auth_method='smime';

    }elsif ($auth ne '') {
	&do_log('debug',"auth received from $sender : $auth");	
      
	my $compute;
	if (ref($list) eq "List"){
	    $compute= $list->compute_auth($email,$cmd);

	}else {
	    $compute= &List::compute_auth($email,$cmd);	    
	}
	if ($auth eq $compute) {
	    $auth_method='md5' ;
	}else{           
	    &do_log('debug2', 'auth should be %s',$compute);
	    &error_report_cmd($cmd_line,$error->{'type'},$error->{'data'});
	    &do_log('info', '%s refused, auth failed',$error->{'msg'});
	    return undef;
	}
    }else {
	$auth_method='smtp';
    }
 
    return $auth_method;
}

#### Functions for notices/errors/globals report command : ###########

#########################################################
# error_report_cmd
#########################################################
#  puts errors reports of processed commands in 
#  @errors_report used to send message with template 
#  command_report
# 
# IN : -$cmd : command line: command and args
#      -$type : type of error, to select string in
#               command_report.tt2
#      -$data : hash of vars for command_report.tt2
#
# OUT :  
#      
######################################################### 
sub error_report_cmd {
    my ($cmd,$type,$data) = @_;

    $data ||= {};
    $data->{'cmd'} = $cmd;
    $data->{'type'} = $type;

    push @errors_report, $data;
}

#########################################################
# notice_report_cmd
#########################################################
#  puts notices reports of processed commands in 
#  @notices_report used to send message with template 
#  command_report
# 
# IN : -$cmd : string command : command and args
#      -$type : type of notice, to select string in
#               command_report.tt2
#      -$data : hash of vars for command_report.tt2
#
# OUT :  
#      
######################################################### 
sub notice_report_cmd {
    my ($cmd,$type,$data) = @_;

    $data ||= {};
    $data->{'cmd'} = $cmd;
    $data->{'type'} = $type;

    push @notices_report, $data;
}

#########################################################
# global_report_cmd
#########################################################
#  puts global reports of processed commands in 
#  @global_report used to send message with template 
#  command_report
# 
# IN : -$cmd : string command : command and args
#      -$type : type of notice, to select string in
#               command_report.tt2
#      -$data : HASH of vars for command_report.tt2
#
# OUT :  
#      
######################################################### 
sub global_report_cmd {
    my ($cmd,$type,$data) = @_;

    $data ||= {};
    $data->{'cmd'} = $cmd;
    $data->{'type'} = $type;

    push @globals_report, $data;
}
# end of package
1;





