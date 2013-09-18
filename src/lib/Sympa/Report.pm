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

Sympa::Report - Reporting functions

=head1 DESCRIPTION

This module provides functions for events notications.

reject_report_msg() and notice_report_msg() functions deliver an immediate
notification of an event to an user by mail.

global_report_cmd(), reject_report_cmd() and notice_report_cmd() functions
push events into a queue, to be notified later by mail using send_report_cmd().

reject_report_web() and notice_report_web() functions push events into another
queue.

=cut

package Sympa::Report;

use strict;

use Sympa::Language;
use Sympa::List;
use Sympa::Log::Syslog;

=head1 FUNCTIONS

=over

=item reject_report_msg($type, $error, $user, $params, $robot, $msg_string, $list)

Send a notification of message rejection to an user, using
I<message_report.tt2> mail template.

For I<intern> type, the listmaster is also notified.

Parameters:

=over

=item C<$type> => 'intern' || 'intern_quiet' || 'user' || 'auth'

=item C<$error> =>

=over

=item - the entry in template if $type = 'user',

=item - string error for listmaster if $type = 'intern',

=item - the entry in authorization reject (called by template) if $type = 'auth'

=back

=item C<$user> => the user to notify

=item C<$param> => variables used in template (hashref)

=item C<$robot> => robot

=item C<$msg_string> => rejected msg

=item C<$list> => list (Sympa::List object)

=back

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub reject_report_msg {
	my ($type, $error, $user, $params, $robot, $msg_string, $list) = @_;
	Sympa::Log::Syslog::do_log('debug2', "(%s,%s,%s)", $type,$error,$user);

	unless ($type eq 'intern' || $type eq 'intern_quiet' || $type eq 'user'|| $type eq 'auth'|| $type eq 'plugin') {
		Sympa::Log::Syslog::do_log('err',"error to prepare parsing 'message_report' template to %s : not a valid error type", $user);
		return undef
	}

	unless ($user){
		Sympa::Log::Syslog::do_log('err',"unable to send template command_report.tt2 : no user to notify");
		return undef;
	}

	if (ref $list and ref $list eq 'List') {
		$robot = $list->robot;
	} else {
		$robot = Sympa::Robot::clean_robot($robot, 1); #FIXME: really may be Site?
	}
	
	unless ($robot){
		Sympa::Log::Syslog::do_log('err',"unable to send template command_report.tt2 : no robot");
		return undef;
	}
    $param->{'entry'} = $error;

	chomp($user);
	$params->{'to'} = $user;
	$params->{'msg'} = $msg_string;
	$params->{'auto_submitted'} = 'auto-replied';

	if ($type eq 'user') {
		$params->{'entry'} = $error;
		$params->{'type'} = 'user_error';

	} elsif ($type eq 'auth') {
		$params->{'entry'} = $error;
		$params->{'type'} = 'authorization_reject';

	} elsif ($type eq 'oauth') {
		$params->{'entry'} = $error;
		$params->{'type'} = 'oauth';

	} else {
		$params->{'type'} = 'intern_error';
	}

	## Prepare the original message if provided
	if (defined $params->{'message'}) {
		$params->{'original_msg'} = _get_msg_as_hash($params->{'message'});
	}

	if (ref($list) && $list->isa('Sympa::List')) {
		unless ($list->send_file('message_report',$user,$robot,$params)) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report' to %s", $user);
		}
	} else {
		unless (Sympa::List::send_global_file('message_report',$user,$robot,$params)) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report' to %s", $user);
		}
	}
	if ($type eq 'intern') {
		chomp $params->{'msg_id'} if $params->{'msg_id'};

		$params ||= {};
		$params->{'error'} =  Sympa::Language::gettext($error);
		$params->{'who'} = $user;
		$params->{'action'} = 'message diffusion';
		$params->{'msg_id'} = $params->{'msg_id'};
		$params->{'list'} = $list if (defined $list);
		unless (Sympa::List::send_notify_to_listmaster('mail_intern_error', $robot, $params)) {
			Sympa::Log::Syslog::do_log('notice',"Unable to notify_listmaster concerning %s", $user);
		}
	}
	return 1;
}

# _get_msg_as_hash($msg)
# Provide useful parts of a message as a hash entries
# Return an hashred

sub _get_msg_as_hash {
	my ($msg_object) = @_;

	my ($msg_entity, $msg_hash);

	if ($msg_object->isa('MIME::Entity')) { ## MIME-ttols object
		$msg_entity = $msg_object;
	} elsif ($msg_object->isa('Sympa::Message')) { ## Sympa's own Message object
		$msg_entity = $msg_object->{'msg'};
	} else {
		Sympa::Log::Syslog::do_log('err', "reject_report_msg: wrong type for msg parameter");
	}

	my $head = $msg_entity->head();
	my $body_handle = $msg_entity->bodyhandle();
	my $body_as_string;

	if (defined $body_handle) {
		$body_as_string = $body_handle->as_lines();
	}

	## TODO : we should also decode headers + remove trailing \n + use these variables in default mail templates

	my $from = $head->get('From');
	chomp $from if $from;
	my $subject = $head->get('Subject');
	chomp $subject if $subject;
	my $msg_id = $head->get('Message-Id');
	chomp $msg_id if $msg_id;
	$msg_hash = {'full' => $msg_entity->as_string,
		'body' => $body_as_string,
		'from' => $from,
		'subject' => $subject,
		'message_id' => $msg_id
	};

	return $msg_hash;
}

=item notice_report_msg($entry, $user, $params, $robot, $list)

Send a notification of message diffusion to an user, using
I<message_report.tt2> mail template.

Parameters:

=over

=item C<$entry> => the entry in template

=item C<$user> => the user to notify

=item C<$param> => variables used in template (hashref)

=item C<$robot> => robot

=item C<$list> => list (Sympa::List object)

=back

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub notice_report_msg {
	my ($entry, $user, $params, $robot, $list) = @_;

	$params->{'to'} = $user;
	$params->{'type'} = 'success';
	$params->{'entry'} = $entry;
	$params->{'auto_submitted'} = 'auto-replied';

	unless ($user){
		Sympa::Log::Syslog::do_log('err',"unable to send template message_report.tt2 : no user to notify");
		return undef;
	}
	
	if (ref $list and ref $list eq 'List') {
		$robot = $list->robot;
	} else {
		$robot = Sympa::Robot::clean_robot($robot, 1); #FIXME: really may be Site?
	}

	unless ($robot){
		Sympa::Log::Syslog::do_log('err',"unable to send template message_report.tt2 : no robot");
		return undef;
	}

	## Prepare the original message if provided
	if (defined $params->{'message'}) {
		$params->{'original_msg'} = _get_msg_as_hash($params->{'message'});
	}

	if (ref($list) && $list->isa('Sympa::List')) {
		unless ($list->send_file('message_report',$user,$robot,$params)) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report' to %s", $user);
		}
	} else {
		unless (List->send_global_file('message_report',$user,$robot,$params)) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report' to %s", $user);
		}
	}

	return 1;
}

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

=item init_report_cmd()

Flush the events queue for category I<cmd>.

Parameters:

None.

Return value:

None.

=cut

sub init_report_cmd {

	undef @intern_error_cmd;
	undef @user_error_cmd;
	undef @global_error_cmd;
	undef @auth_reject_cmd;
	undef @notice_cmd;
}

=item is_there_any_report_cmd()

Look for error events of category I<cmd> in the events queue.

Parameters:

None.

Return value:

A true value if there is any such event in the queue.

=cut

sub is_there_any_report_cmd {

	return (@intern_error_cmd ||
		@user_error_cmd ||
		@global_error_cmd ||
		@auth_reject_cmd ||
		@notice_cmd );
}

=item send_report_cmd($sender, $robot)

Send a mail report of all events of category I<cmd> in the queue, using
I<command_report.tt2> mail template, and flushes the queue of such events.

Parameters:

=over

=item C<$sender> =>

=item C<$robot> => robot

=back

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub send_report_cmd {
	my ($sender, $robot_id) = @_;

	unless ($sender){
		Sympa::Log::Syslog::do_log('err',"unable to send template command_report.tt2 : no user to notify");
		return undef;
	}

	my $robot = undef;
	if ($robot_id and $robot_id ne '*') {
		$robot = Sympa::Robot->new($robot_id);
	}

	unless ($robot){
		Sympa::Log::Syslog::do_log('err',"unable to send template command_report.tt2 : no robot");
		return undef;
	}

	# for mail layout
	my $before_auth = 0;
	$before_auth = 1 if ($#notice_cmd +1);

	my $before_user_err;
	$before_user_err = 1 if ($before_auth || ($#auth_reject_cmd +1));

	my $before_intern_err;
	$before_intern_err = 1 if ($before_user_err || ($#user_error_cmd +1));

	chomp($sender);

	my $data = {
		'to'                => $sender,
		'nb_notice'         => $#notice_cmd +1,
		'nb_auth'           => $#auth_reject_cmd +1,
		'nb_user_err'       => $#user_error_cmd +1,
		'nb_intern_err'     => $#intern_error_cmd +1,
		'nb_global'         => $#global_error_cmd +1,
		'before_auth'       => $before_auth,
		'before_user_err'   => $before_user_err,
		'before_intern_err' => $before_intern_err,
		'notices'           => \@notice_cmd,
		'auths'             => \@auth_reject_cmd,
		'user_errors'       => \@user_error_cmd,
		'intern_errors'     => \@intern_error_cmd,
		'globals'           => \@global_error_cmd,
	};

	unless (Sympa::List::send_global_file('command_report',$sender,$robot,$data)) {
		Sympa::Log::Syslog::do_log('notice',"Unable to send template 'command_report' to %s", $sender);
	}

	init_report_cmd();
}

=item global_report_cmd($type, $error,  $data, $sender, $robot, $now)

Push an event of type I<intern> or I<user> in the command execution events
queue.

If I<$now> is true, send_report_cmd() is called immediatly.

For I<intern> type, the listmaster is notified immediatly.

Parameters:

=over

=item C<$type> => 'intern' || 'intern_quiet' || 'user'

=item C<$error> =>

=over

=item - $glob.entry in template if $type = 'user'

=item - string error for listmaster if $type = 'intern'

=back

=item C<$data> => variables used in template (hashref)

=item C<$sender> => the user to notify (required if $type eq 'intern' or if I<$now> is true)

=item C<$robot> => to notify listmaster (required if $type eq 'intern' or if I<$now> is true)

=item C<$now> => send now if true

=back

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub global_report_cmd {
	my ($type, $error,  $data, $sender, $robot_id, $now) = @_;

	my $entry;

	unless ($type eq 'intern' || $type eq 'intern_quiet' || $type eq 'user') {
		Sympa::Log::Syslog::do_log('err',"error to prepare parsing 'command_report' template to %s : not a valid error type", $sender);
		return undef;
	}

	my $robot = undef;
	if ($robot_id and $robot_id ne '*') {
		$robot = Sympa::Robot->new($robot_id);
	}

	if ($type eq 'intern') {

		if ($robot){
			my $params = $data;
			$params ||= {};
			$params->{'error'} = Sympa::Language::gettext($error);
			$params->{'who'} = $sender;
			$params->{'action'} = 'Command process';

			unless (Sympa::List::send_notify_to_listmaster('mail_intern_error', $robot,$params)) {
				Sympa::Log::Syslog::do_log('notice',"Unable to notify listmaster concerning %s", $sender);
			}
		} else {
			Sympa::Log::Syslog::do_log('notice',"unable to send notify to listmaster : no robot");
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
			Sympa::Log::Syslog::do_log('err',"unable to send template command_report now : no sender or robot");
			return undef;
		}
		send_report_cmd($sender,$robot);

	}
}

=item reject_report_cmd($type, $error, $data, $cmd, $sender, $robot)

Push an event of category I<cmd>, type I<auth>, I<user> or I<intern> in the
events queue.

For I<intern> type, the listmaster is notified immediatly.

Parameters:

=over

=item C<$type> => 'intern' || 'intern_quiet' || 'user' || 'auth'

=item C<$error> =>

=over

=item - $u_err.entry in template if $type = 'user'

=item - $auth.entry in template if $type = 'auth'

=item - string error for listmaster if $type = 'intern'

=back

=item C<$data> => variables used in template (hashref)

=item C<$cmd> => the rejected cmd ($xx.cmd in template)

=item C<$sender> => the user to notify (required if $type eq 'intern')

=item C<$robot> => to notify listmaster (required if $type eq 'intern')

=back

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub reject_report_cmd {
	my ($type, $error, $data, $cmd, $sender, $robot) = @_;

	unless ($type eq 'intern' || $type eq 'intern_quiet' || $type eq 'user' || $type eq 'auth') {
		Sympa::Log::Syslog::do_log('err',"error to prepare parsing 'command_report' template to $sender : not a valid error type");
		return undef;
	}

	if ($type eq 'intern') {
		if ($robot){

			my $listname;
			if (defined $data->{'listname'}) {
				$listname = $data->{'listname'};
			}

			my $params = $data;
			$params ||= {};
			$params->{'error'} = Sympa::Language::gettext($error);
			$params->{'cmd'} = $cmd;
			$params->{'listname'} = $listname;
			$params->{'who'} = $sender;
			$params->{'action'} = 'Command process';

			unless (Sympa::List::send_notify_to_listmaster('mail_intern_error', $robot,$params)) {
				Sympa::Log::Syslog::do_log('notice',"Unable to notify listmaster concerning '$sender'");
			}
		} else {
			Sympa::Log::Syslog::do_log('notice','unable to notify listmaster for error: "" : (no robot) ', $error);
		}
	}

	$data ||= {};
	$data->{'cmd'} = $cmd;

	if ($type eq 'auth') {
		$data->{'entry'} = $error;
		push @auth_reject_cmd,$data;

	} elsif ($type eq 'user') {
		$data->{'entry'} = $error;
		push @user_error_cmd,$data;

	} else {
		$data->{'entry'} = 'intern_error';
		push @intern_error_cmd, $data;

	}

}

=item notice_report_cmd($entry, $data, $cmd)

Push an event of category I<cmd>, type I<notice> in the events queue.

Parameters:

=over

=item C<$entry> => $notice.entry to select string in template

=item C<$data> => variables used in template (hashref)

=item C<$cmd> => the noticed cmd

=back

Return value:

None.

=cut

sub notice_report_cmd {
	my ($entry, $data, $cmd) = @_;
	$data ||= {};

	$data->{'cmd'} = $cmd;
	$data->{'entry'} = $entry;
	push @notice_cmd, $data;
}

# for rejected web command because of internal error
my @intern_error_web;
# for rejected web command because of system error
my @system_error_web;
# for rejected web command because of user error
my @user_error_web;
# for rejected web command because of no authorization
my @auth_reject_web;
# for web command notice
my @notice_web;

=item init_report_web()

Flush the events queue for category I<web>.

Parameters:

None.

Return value:

None.

=cut

sub init_report_web {

	undef @intern_error_web;
	undef @system_error_web;
	undef @user_error_web;
	undef @auth_reject_web;
	undef @notice_web;
}

=item is_there_any_reject_report_web()

Look for error events of category I<web> in the events queue.

Parameters:

None.

Return value:

A true value if there is any such event in the queue.

=cut

sub is_there_any_reject_report_web {

	return (@intern_error_web ||
		@system_error_web ||
		@user_error_web ||
		@auth_reject_web );
}


=item get_intern_error_web()

Get the list of reports for category I<web>, type I<intern>.

Parameters:

None.

Return value:

A list of error reports, as an arrayref.

=cut

sub get_intern_error_web {
	my @intern_err;

	foreach my $i (@intern_error_web) {
		push @intern_err,$i;
	}
	return \@intern_err;
}

=item get_system_error_web()

Get the list of reports for category I<web>, type I<system>.

Parameters:

None.

Return value:

A list of reports, as an arrayref.

=cut

sub get_system_error_web {
	my @system_err;

	foreach my $i (@system_error_web) {
		push @system_err,$i;
	}
	return \@system_err;
}


=item get_user_error_web()

Get the list of reports for category I<web>, type I<user>.

Parameters:

None.

Return value:

A list of reports, as an arrayref.

=cut

sub get_user_error_web {
	my @user_err;

	foreach my $u (@user_error_web) {
		push @user_err,$u;
	}
	return \@user_err;
}


=item get_auth_reject_web()

Get the list of reports for category I<web>, type I<auth>.

Parameters:

None.

Return value:

A list of reports, as an arrayref.

=cut

sub get_auth_reject_web {
	my @auth_rej;

	foreach my $a (@auth_reject_web) {
		push @auth_rej,$a;
	}
	return \@auth_rej;
}


=item get_notice_web()

Get the list of reports for category I<web>, type I<notice>.

Parameters:

None.

Return value:

A list of reports, as an arrayref.

=cut

sub get_notice_web {
	my @notice;

	if (@notice_web) {

		foreach my $n (@notice_web) {
			push @notice,$n;
		}
		return \@notice;

} else {
	return 0;
}

}

=item notice_report_web($msg, $data, $action)

Push an event of category I<web>, type <notice>, in the events queue.

Parameters:

=over

=item C<$msg> => $notice.msg to select string in template

=item C<$data> => variables used in template (hashref)

=item C<$action> => the noticed action $notice.action in template

=back

Return value:

None.

=cut

sub notice_report_web {
	my ($msg,$data,$action) = @_;

	$data ||= {};
	$data->{'action'} = $action;
	$data->{'msg'} = $msg;
	push @notice_web,$data;

}

=item reject_report_web($type, $error, $data, $action, $list, $user, $robot)

Push an event of category I<web>, type I<intern>, I<system>, I<user> or
I<auth> in the events queue.

For I<intern> or I<system> types, the listmaster is notified immediatly.

Parameters:

=over

=item C<$type> => 'intern' || 'intern_quiet' || 'system' || 'system_quiet' ||
'user' || 'auth'

=item C<$error> =>

=over

=item - $u_err.msg in template if $type = 'user'

=item - $auth.msg in template if $type = 'auth'

=item - $s_err.msg in template if $type = 'system'||'system_quiet'

=item - $i_err.msg in template if $type = 'intern' || 'intern_quiet'

=item - $error in listmaster_notification if $type = 'system'||'intern'

=back

=item C<$data> => variables used in template (hashref)

=item C<$action> => the rejected action :
	$xx.action in template
	$action in listmaster_notification.tt2 if needed

=item C<$list> => Sympa::List object

=item C<$user> => the user to notify listmaster (required if $type eq 'intern'
or 'system')

=item C<$robot> => the robot to notify listmaster (required if $type eq
'intern' or 'system')

=back

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub reject_report_web {
	my ($type,$error,$data,$action,$list,$user,$robot_id) = @_;

	unless ($type eq 'intern' || $type eq 'intern_quiet' || $type eq 'system' || $type eq 'system_quiet' || $type eq 'user'|| $type eq 'auth') {
		Sympa::Log::Syslog::do_log('err',"error  to prepare parsing 'web_tt2/error.tt2' template to $user : not a valid error type");
		return undef
	}

	my $robot = undef;
	if (ref $list and ref $list eq 'List') {
		$robot = $list->robot;
	} elsif ($robot_id and $robot_id ne '*') {
		$robot = Sympa::Robot->new($robot_id);
	}
	
	my $listname;
	if (ref($list) && $list->isa('Sympa::List')){
		$listname = $list->{'name'};
	}

	## Notify listmaster for internal or system errors
	if ($type eq 'intern'|| $type eq 'system') {
		if ($robot){
			my $params = $data;
			$params ||= {};
			$params->{'error'} = Sympa::Language::gettext($error);
			$params->{'list'} = $list if (defined $list);
			$params->{'who'} = $user;
			$params->{'action'} ||= 'Command process';

			unless (Sympa::List::send_notify_to_listmaster('web_'.$type.'_error', $robot, $params)) {
				Sympa::Log::Syslog::do_log('notice',"Unable to notify listmaster concerning '$user'");
			}
		} else {
			Sympa::Log::Syslog::do_log('notice','unable to notify listmaster for error: "%s" : (no robot) ', $error);
		}
	}

	$data ||= {};

	$data->{'action'} = $action;
	$data->{'msg'} = $error;
	$data->{'listname'} = $listname;

	if ($type eq 'auth') {
		push @auth_reject_web,$data;

	} elsif ($type eq 'user') {
		push @user_error_web,$data;

	} elsif ($type eq 'system' || $type eq 'system_quiet') {
		push @system_error_web,$data;

	} elsif ($type eq 'intern' || $type eq 'intern_quiet') {
		push @intern_error_web,$data;

	}
}

=back

=cut

1;
