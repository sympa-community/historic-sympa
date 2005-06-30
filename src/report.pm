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
#                               if $type = 'authorization'
#      -$user (+): scalar - the user to notify
#      -$param (+) : ref(HASH) - var used in message_report.tt2
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
	&do_log('notice',"sympa::error_report_msg(): Unable to send template 'message_report' to $user : not a valid error type");
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
	    &do_log('notice',"sympa::error_report_msg(): Unable to send template 'message_report' to '$user'");
	}
    } else {
	unless (&List::send_global_file('message_report',$user,$robot,$param)) {
	    &do_log('notice',"sympa::error_report_msg(): Unable to send template 'message_report' to '$user'");
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
	    &do_log('notice',"sympa::error_report_msg(): Unable to notify_listmaster concerning '$user'");
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
#      -$param (+) : ref(HASH) - var used in message_report.tt2
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
	    &do_log('notice',"sympa::notice_report_msg(): Unable to send template 'message_report' to '$user'");
	}
    } else {
	unless (&List->send_global_file('message_report',$user,$robot,$param)) {
	    &do_log('notice',"sympa::notice_report_msg(): Unable to send template 'message_report' to '$user'");
	}
    }

    return 1;
}

#########################################################
# reject_report_cmd
#########################################################
#  puts reject reports of processed commands in 
#  @reject_report used to send message with template 
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
sub reject_report_cmd {




}


1;

