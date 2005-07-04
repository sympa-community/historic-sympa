# report.pm - This module provides various tools for command and message 
# diffusion report
# RCS Identication ; $Revision$ ; $Date$ 
#
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

package report;

use strict;

use Log;
use List;






######################## MESSAGE DIFFUSION REPORT #############################################


############################################################
#  reject_report_msg
############################################################
#  Send a notification to the user about an error rejecting
#  its message diffusion, using message_report.tt2
#  
# IN : -$type (+): 'intern'|'intern_quiet'|'user'|auth' - the error type 
#      -$error (+): scalar - the entry in message_report.tt2 if $type = 'user'
#                          - string error for listmaster if $type = 'intern'
#                          - the entry in authorization reject (called by message_report.tt2)
#                               if $type = 'auth'
#      -$user (+): scalar - the user to notify
#      -$param : ref(HASH) - var used in message_report.tt2
#         $param->msg_id (+) if $type='intern'
#      -$robot (+): robot
#      -$msg_string : string - rejected msg 
#      -$list : ref(List)
#
# OUT : 1
#
############################################################## 
sub reject_report_msg {
    my ($type,$error,$user,$param,$robot,$msg_string,$list) = @_;

    unless ($type eq 'intern' | $type eq 'intern_quiet' | $type eq 'user'| $type eq 'auth') {
	&do_log('notice',"report::reject_report_msg(): error for to prepare parsing 'message_report' template to $user : not a valid error type");
    }

    chomp($user);
    $param->{'to'} = $user;
    $param->{'msg'} = $msg_string;

    if ($type eq 'user') {
	$param->{'entry'} = $error;
	$param->{'type'} = 'user_error';

    } elsif ($type eq 'authorization') {
	$param->{'reason'} = $error;
	$param->{'type'} = 'authorization_reject';

    } else {
	$param->{'type'} = 'intern_error';
    }

    if (ref($list) eq "List") {
	unless ($list->send_file('message_report',$user,$robot,$param)) {
	    &do_log('notice',"report::reject_report_msg(): Unable to send template 'message_report' to '$user'");
	}
    } else {
	unless (&List::send_global_file('message_report',$user,$robot,$param)) {
	    &do_log('notice',"report::reject_report_msg(): Unable to send template 'message_report' to '$user'");
	}
    }
    if ($type eq 'intern') {
	chomp($param->{'msg_id'});
	my $listname;
	if (ref($list) ){
	    $listname = $list->{'name'}; 
	}
	unless (&List::send_notify_to_listmaster('intern_error', $robot, {'error' => $error,
									  'who'  => $user,
									  'action' => 'message diffusion',
									  'msg_id' => $param->{'msg_id'},
								          'listname' => $listname})){
	    &do_log('notice',"report::reject_report_msg(): Unable to notify_listmaster concerning '$user'");
	}
    }
    return 1;
}


############################################################
#  notice_report_msg
############################################################
#  Send a notification to the user about a success for its
#   message diffusion, using message_report.tt2
#  
# IN : -$entry (+): scalar - the entry in message_report.tt2
#      -$user (+): scalar - the user to notify
#      -$param : ref(HASH) - var used in message_report.tt2
#      -$robot (+) : robot
#      -$list : ref(List)
#
# OUT : 1
#
############################################################## 
sub notice_report_msg {
    my ($entry,$user,$param,$robot,$list) = @_;

    $param->{'to'} = $user;
    $param->{'type'} = 'success';   
    $param->{'entry'} = $entry;
    
    if (ref($list) eq "List") {
	unless ($list->send_file('message_report',$user,$robot,$param)) {
	    &do_log('notice',"report::notice_report_msg(): Unable to send template 'message_report' to '$user'");
	}
    } else {
	unless (&List->send_global_file('message_report',$user,$robot,$param)) {
	    &do_log('notice',"report::notice_report_msg(): Unable to send template 'message_report' to '$user'");
	}
    }

    return 1;
}




########################### MAIL COMMAND REPORT #############################################


# for rejected command because of internal error
my @intern_error_cmd;
# for rejected command because of user error
my @user_error_cmd;
# for errors no relative to a command
my @global_error_cmd;
# for rejected command because of no authorization
my @auth_reject_cmd;
# for command notice
my @notice_cmd;



#########################################################
# init_report_cmd
#########################################################
#  init arrays for commands reports :
#
# 
# IN : -
#
# OUT : - 
#      
######################################################### 
sub init_report_cmd {

    undef @intern_error_cmd;
    undef @user_error_cmd;
    undef @global_error_cmd;
    undef @auth_reject_cmd;
    undef @notice_cmd;
}


#########################################################
# is_there_any_report_cmd
#########################################################
#  Look for some commands report in one of arrays report
# 
# IN : -
#
# OUT : 1 if there are some reports to send
#      
######################################################### 
sub is_there_any_report_cmd {
    
    return (@intern_error_cmd ||
	    @user_error_cmd ||
	    @global_error_cmd ||
	    @auth_reject_cmd ||
	    @notice_cmd );
}


#########################################################
# send_report_cmd
#########################################################
#  Send the template command_report to $sender 
#   with global arrays :
#  @intern_error_cmd,@user_error_cmd,@global_error_cmd,
#   @auth_reject_cmd,@notice_cmd.
#
# 
# IN : -$sender (+): SCALAR
#      -$robot (+): SCALAR
#
# OUT : 1 if there are some reports to send
#      
######################################################### 
sub send_report_cmd {
    my ($sender,$robot) = @_;

   
    # for mail layout
    my $before_auth = 0;
    $before_auth = 1 if ($#notice_cmd +1);

    my $before_user_err;
    $before_user_err = 1 if ($before_auth || ($#auth_reject_cmd +1));

    my $before_intern_err;
    $before_intern_err = 1 if ($before_user_err || ($#user_error_cmd +1));

    chomp($sender);

    # 
    my $data = { 'to' => $sender,
	         'nb_notice' =>$#notice_cmd +1,
		 'nb_auth' => $#auth_reject_cmd +1,
		 'nb_user_err' => $#user_error_cmd +1,
		 'nb_intern_err' => $#intern_error_cmd +1,
		 'nb_global' => $#global_error_cmd +1,	
		 'before_auth' => $before_auth,
		 'before_user_err' => $before_user_err,
		 'before_intern_err' => $before_intern_err,
		 'notices' => \@notice_cmd,
		 'auths' => \@auth_reject_cmd,
		 'user_errors' => \@user_error_cmd,
		 'intern_errors' => \@intern_error_cmd,
		 'globals' => \@global_error_cmd,
		 



};

    unless (&List::send_global_file('command_report',$sender,$robot,$data)) {
	&do_log('notice',"Unable to send template 'command_report' to $sender");
    }
    
    &init_report_cmd();
}


#########################################################
# global_report_cmd
#########################################################
#  puts global report of mail with commands in 
#  @global_report_cmd  used to send message with template 
#  command_report.tt2
#  if $now , the template is sent now
#  if $type eq 'intern', the listmaster is notified
# 
# IN : -$type (+): 'intern'|'intern_quiet|'user'
#      -$error (+): scalar - $glob.entry in command_report.tt2 if $type = 'user'
#                          - string error for listmaster if $type = 'intern'
#      -$data : ref(HASH) - var used in command_report.tt2
#      -$sender :  required if $type eq 'intern' or if $now
#                  scalar - the user to notify 
#      -$robot :   required if $type eq 'intern' or if $now
#                  scalar - to notify useror listmaster
#
# OUT : 1| undef  
#      
######################################################### 
sub global_report_cmd {
    my ($type,$error,$data,$sender,$robot,$now) = @_;
    my $entry;

    unless ($type eq 'intern' | $type eq 'intern_quiet' | $type eq 'user') {
	&do_log('notice',"report::global_report_msg(): error to prepare parsing 'command_report' template to $sender : not a valid error type");
    }
    
    if ($type eq 'intern') {
	unless ($robot){
	    &do_log('notice',"report::global_report_cmd(): unable to send notify to listmaster : no robot");
	    return undef;
	}	
	unless (&List::send_notify_to_listmaster('intern_error', $robot, {'error' => $error,
									  'who'  => $sender,
									  'action' => 'Command process'})) {
	    &do_log('notice',"report::global_report_cmd(): Unable to notify listmaster concerning '$sender'");
	}
    }

    if ($type eq 'user') {
	$entry = $error;

    } else {
	$entry = 'intern_error';
    }

    $data ||= {};
    $data->{'entry'} = $entry;
    push @global_error_cmd, $data;

    if ($now) {
	unless ($sender && $robot){
	    &do_log('notice',"report::global_report_msg(): unable to send template command_report now : no sender or robot");
	    return undef;
	}	
	&send_report_cmd($sender,$robot);
	
    }
}


#########################################################
# reject_report_cmd
#########################################################
#  puts errors reports of processed commands in 
#  @reject_report_cmd used to send message with template 
#  command_report.tt2
#  if $type eq 'intern', the listmaster is notified
# 
# IN : -$type (+): 'intern'|'intern_quiet|'user'|'auth'
#      -$error (+): scalar - $u_err.entry in command_report.tt2 if $type = 'user'
#                          - $auth.reason in command_report.tt2 if $type = 'auth' 
#                          - string error for listmaster if $type = 'intern'|'intern_quiet'
#      -$data : ref(HASH) - var used in command_report.tt2
#      -$cmd : SCALAR - the rejected cmd
#      -$sender :  required if $type eq 'intern' 
#                  scalar - the user to notify 
#      -$robot :   required if $type eq 'intern'
#                  scalar - to notify useror listmaster
#
# OUT : 1| undef  
#      
######################################################### 
sub reject_report_cmd {
    my ($type,$error,$data,$cmd,$sender,$robot) = @_;

    unless ($type eq 'intern' | $type eq 'intern_quiet' | $type eq 'user' | $type eq 'auth') {
	&do_log('notice',"report::reject_report_msg(): error to prepare parsing 'command_report' template to $sender : not a valid error type");
    }
    
    if ($type eq 'intern') {
	unless ($robot){
	    &do_log('notice',"report::reject_report_cmd(): unable to send template message_report : no robot");
	    return undef;
	}	
	unless (&List::send_notify_to_listmaster('intern_error', $robot, {'error' => $error,
									  'who'  => $sender,
									  'cmd' => $cmd,
									  'action' => 'Command process'})) {
	    &do_log('notice',"report::reject_report_cmd(): Unable to notify listmaster concerning '$sender'");
	}
    }

    $data ||= {};
    $data->{'cmd'} = $cmd;

    if ($type eq 'auth') {
	$data->{'reason'} = $error;
	push @auth_reject_cmd,$data;

    } elsif ($type eq 'user') {
	$data->{'entry'} = $error;
	push @user_error_cmd,$data;

    } else {
	$data->{'entry'} = 'intern_error';
	push @intern_error_cmd, $data;

    }

}

#########################################################
# notice_report_cmd
#########################################################
#  puts notices reports of processed commands in 
#  @notice_cmd used to send message with template 
#  command_report.tt2
# 
# IN : -$entry : $notice.entry to select string in
#               command_report.tt2
#      -$data : ref(HASH) - var used in command_report.tt2
#      -$cmd : SCALAR - the noticed cmd
#
# OUT : 1
#      
######################################################### 
sub notice_report_cmd {
    my ($entry,$data,$cmd) = @_;
   
    $data ||= {};
    $data->{'cmd'} = $cmd;
    $data->{'entry'} = $entry;
    push @notice_cmd, $data;
}


1;
