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

Sympa::Commands - Mail commands processing functions

=head1 DESCRIPTION

This module provides mail commands processing functions.

=cut

package Sympa::Commands;

use strict;

use English;

use Sympa::Archive;
use Sympa::Configuration;
use Sympa::Constants;
use Sympa::Database;
use Sympa::Language;
use Sympa::List;
use Sympa::Log::Syslog;
use Sympa::Message;
use Sympa::Report;
use Sympa::Scenario;
use Sympa::Spool;
use Sympa::Tools;
use Sympa::Tools::File;
use Sympa::Tools::Password;

my %comms =  (
	'add'                               => '_add',
	'con|confirm'                       => '_confirm',
	'del|delete'                        => '_del',
	'dis|distribute'                    => '_distribute',
	'get'                               => '_getfile',
	'hel|help|sos'                      => '_help',
	'inf|info'                          => '_info',
	'inv|invite'                        => '_invite',
	'ind|index'                         => '_index',
	'las|last'                          => '_last',
	'lis|lists?'                        => '_lists',
	'mod|modindex|modind'               => '_modindex',
	'qui|quit|end|stop|-'               => '_finished',
	'rej|reject'                        => '_reject',
	'rem|remind'                        => '_remind',
	'rev|review|who'                    => '_review',
	'set'                               => '_set',
	'sub|subscribe'                     => '_subscribe',
	'sig|signoff|uns|unsub|unsubscribe' => '_signoff',
	'sta|stats'                         => '_stats',
	'ver|verify'                        => '_verify',
	'whi|which|status'                  => '_which'
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

=head1 FUNCTIONS

=over

=item parse($sender, $robot, $i, $sign_mod, $message)

Parses the command and calls the adequate subroutine with the arguments to the
command.

Parameters:

=over

=item C<$sender> => (+): the command sender

=item C<$robot> => (+): robot

=item C<$i> => (+): command line

=item C<$sign_mod> => : 'smime'| 'dkim' -

=back

Return value:

$status |'unknown_cmd'

=cut

sub parse {
	$sender = lc(shift);
	my $robot = shift;
	my $i = shift;
	my $sign_mod = shift;
	my $message = shift;

	Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s, %s, %s)', $sender, $robot, $i, $sign_mod, $message->{'msg'}->as_string() );

	my $j;
	$cmd_line = '';

	Sympa::Log::Syslog::do_log('notice', "Parsing: %s", $i);

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
	} else {
		$quiet = 0;
	}

	foreach $j (keys %comms) {
		if ($i =~ /^($j)(\s+(.+))?\s*$/i) {
			$time_command = time();
			my $args = $3;
			$args =~ s/^\s*//;
			$args =~ s/\s*$//;

			my $status;

			$cmd_line = $i;
			no strict 'refs';
			$status = & {$comms{$j}}($args, $robot, $sign_mod, $message);

			return $status;
		}
	}

	## Unknown command
	return 'unknown_cmd';
}

# _finished()
# Do not process what is after this line
# Parameters: None.
# Return value: a true value.

sub _finished {
	Sympa::Log::Syslog::do_log('debug2', '()');

	Sympa::Report::notice_report_cmd('finished',{},$cmd_line);
	return 1;
}


# _help(undef, $robot)
# Sends the help file for the software
# Parameters:
# - $robot => robot
# Return value: A true value, or undef if something went wrong.

sub _help {
	my (undef, $robot) = @_;

	my $etc =  Sympa::Configuration::get_robot_conf($robot, 'etc');

	Sympa::Log::Syslog::do_log('debug', 'to robot %s',$robot);

	# sa ne prends pas en compte la structure des répertoires par lang.
	# we should make this utilize Template's chain of responsibility
	if ((-r "$etc/mail_tt2/helpfile.tt2")||("$etc/$robot/mail_tt2/helpfile.tt2")) {


		my $data = {};

		my @owner = Sympa::List::get_which ($sender, $robot,'owner');
		my @editor = Sympa::List::get_which ($sender, $robot, 'editor');

		$data->{'is_owner'} = 1 if ($#owner > -1);
		$data->{'is_editor'} = 1 if ($#editor > -1);
		$data->{'user'} =  Sympa::List::get_global_user($sender);
		Sympa::Language::set_lang($data->{'user'}{'lang'}) if $data->{'user'}{'lang'};
		$data->{'subject'} = Sympa::Language::gettext("User guide");
		$data->{'auto_submitted'} = 'auto-replied';

		my $expedition_result = Sympa::List::send_global_file(
			"helpfile",
			$sender,
			$robot,
			$data
		);
		unless ($expedition_result) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'helpfile' to $sender");
			Sympa::Report::reject_report_cmd('intern_quiet','',{},$cmd_line,$sender,$robot);
		}

	} elsif (-r Sympa::Constants::DEFAULTDIR . '/mail_tt2/helpfile.tt2') {

		my $data = {};

		my @owner = Sympa::List::get_which ($sender,$robot, 'owner');
		my @editor = Sympa::List::get_which ($sender,$robot, 'editor');

		$data->{'is_owner'} = 1 if ($#owner > -1);
		$data->{'is_editor'} = 1 if ($#editor > -1);
		$data->{'subject'} = Sympa::Language::gettext("User guide");
		$data->{'auto_submitted'} = 'auto-replied';

		my $expedition_result = Sympa::List::send_global_file(
			"helpfile",
			$sender,
			$robot,
			$data
		);
		unless ($expedition_result) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'helpfile' to $sender");
			Sympa::Report::reject_report_cmd('intern_quiet','',{},$cmd_line,$sender,$robot);
		}

	} else {
		my $error = sprintf('Unable to read "help file" : %s',$ERRNO);
		Sympa::Report::reject_report_cmd('intern',$error,{},$cmd_line,$sender,$robot);
		Sympa::Log::Syslog::do_log('info', 'HELP from %s refused, file not found', $sender,);
		return undef;
	}

	Sympa::Log::Syslog::do_log('info', 'HELP from %s accepted (%d seconds)',$sender, time() - $time_command);

	return 1;
}

#_lists(undef, $robot, $sign_mod, $message)
# Sends back the list of public lists on this node.
# Parameters:
# - $robot: robot
# - $sign_mod:
# - $message:
# Return value:

sub _lists {
	my (undef, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', 'for robot %s, sign_mod %, message %s', $robot,$sign_mod , $message);

	my $data = {};
	my $lists = {};

	my $all_lists =  Sympa::List::get_lists($robot);

	foreach my $list ( @$all_lists ) {
		my $l = $list->{'name'};

		my $result = $list->check_list_authz(
			'visibility',
			'smtp', # 'smtp' isn't it a bug ?
			{
				'sender' => $sender,
				'message' => $message,
			}
		);
		my $action;
		$action = $result->{'action'} if (ref($result) eq 'HASH');

		unless (defined $action) {
			my $error = "Unable to evaluate scenario 'visibility' for list $l";
			Sympa::List::send_notify_to_listmaster(
				'intern_error',
				$robot,
				{
					'error'          => $error,
					'who'            => $sender,
					'cmd'            => $cmd_line,
					'list'           => $list,
					'action'         => 'Command process',
					'auto_submitted' => 'auto-replied'
				}
			);
			next;
		}

		if ($action eq 'do_it') {
			$lists->{$l}{'subject'} = $list->{'admin'}{'subject'};
			$lists->{$l}{'host'} = $list->{'admin'}{'host'};
		}
	}

	$data->{'lists'} = $lists;
	$data->{'auto_submitted'} = 'auto-replied';

	my $expedition_result = Sympa::List::send_global_file(
		'lists',
		$sender,
		$robot,
		$data
	);
	unless ($expedition_result) {
		Sympa::Log::Syslog::do_log('notice',"Unable to send template 'lists' to $sender");
		# FIXME: undefined variable
		Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> undef},$cmd_line,$sender,$robot);
	}

	Sympa::Log::Syslog::do_log('info', 'LISTS from %s accepted (%d seconds)', $sender, time() - $time_command);

	return 1;
}

# _stats($listname, $robot, $sign_mod, $message)
# Sends the statistics about a list using template 'stats_report'.
# Parameters:
# - $listname: list name
# - $robot: robot
# - $sign_mod: 'smime' | 'dkim'
# - $message:
# Return value: 'unknown_list'|'not_allowed'|1| undef

sub _stats {
	my ($listname, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s, %s, %s, %s)', $listname, $robot, $sign_mod, $message);

	my $list = Sympa::List->new(
		name   => $listname,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $listname},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'STATS %s from %s refused, unknown list for robot %s', $listname, $sender,$robot);
		return 'unknown_list';
	}

	my $auth_method = _get_auth_method(
		'stats',
		$sender,
		{
			'type' => 'auth_failed',
			'data' => {},
			'msg'  => "STATS $listname from $sender"
		},
		$sign_mod,
		$list
	);
	return 'wrong_auth' unless (defined $auth_method);

	my $result = $list->check_list_authz(
		'review',
		$auth_method,
		{
			'sender'  => $sender,
			'message' => $message,
		}
	);
	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action) {
		my $error = "Unable to evaluate scenario 'review' for list $list->{name}";
		Sympa::Report::reject_report_cmd(
			'intern',
			$error,
			{'listname'=>$listname},
			$cmd_line,
			$sender,
			$robot
		);
		return undef;
	}

	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{'auto_submitted' => 'auto-replied'}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'stats %s from %s refused (not allowed)', $listname,$sender);
		return 'not_allowed';
	} else {
		my %stats = (
			'msg_rcv'   => $list->{'stats'}[0],
			'msg_sent'  => $list->{'stats'}[1],
			'byte_rcv'  => sprintf ('%9.2f', ($list->{'stats'}[2] / 1024 / 1024)),
			'byte_sent' => sprintf ('%9.2f', ($list->{'stats'}[3] / 1024 / 1024))
		);

		my $expedition_result = $list->send_file(
			'stats_report',
			$sender,
			$robot,
			{
				'stats'          => \%stats,
				'subject'        => "STATS $list->{'name'}",
				'auto_submitted' => 'auto-replied'
			}
		);
		unless ($expedition_result) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'stats_reports' to $sender");
			Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> $listname},$cmd_line,$sender,$robot);
		}


		Sympa::Log::Syslog::do_log('info', 'STATS %s from %s accepted (%d seconds)', $listname, $sender, time() - $time_command);
	}

	return 1;
}

# _getfile($command, $robot)
# Sends back the requested archive file
# Parameters:
# - $which: command parameters : listname filename
# - $robot: robot
# Return value: 'unknownlist'|'no_archive'|'not_allowed'|1

sub _getfile {
	my ($arg, $robot) = @_;

	my ($which, $file) = split(/\s+/, $arg);
	Sympa::Log::Syslog::do_log('debug', '(%s, %s, %s)', $which, $file, $robot);

	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'GET %s %s from %s refused, list unknown for robot %s', $which, $file, $sender, $robot);
		return 'unknownlist';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	unless ($list->is_archived()) {
		Sympa::Report::reject_report_cmd('user','empty_archives',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'GET %s %s from %s refused, no archive for list %s', $which, $file, $sender, $which );
		return 'no_archive';
	}
	## Check file syntax
	if ($file =~ /(\.\.|\/)/) {
		Sympa::Report::reject_report_cmd('user','no_required_file',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'GET %s %s from %s, incorrect filename', $which, $file, $sender);
		return 'no_archive';
	}
	unless ($list->may_do('get', $sender)) {
		Sympa::Report::reject_report_cmd('auth','list_private_no_archive',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'GET %s %s from %s refused, review not allowed', $which, $file, $sender);
		return 'not_allowed';
	}
#    unless ($list->archive_exist($file)) {
#	Sympa::Report::reject_report_cmd('user','no_required_file',{},$cmd_line);
# 	Sympa::Log::Syslog::do_log('info', 'GET %s %s from %s refused, archive not found for list %s', $which, $file, $sender, $which);
#	return 'no_archive';
#    }

	unless ($list->archive_send($sender, $file)) {
		Sympa::Report::reject_report_cmd('intern',"Unable to send archive to $sender",{'listname'=>$which},$cmd_line,$sender,$robot);
		return 'no_archive';
	}

	Sympa::Log::Syslog::do_log('info', 'GET %s %s from %s accepted (%d seconds)', $which, $file, $sender, time() - $time_command);

	return 1;
}

# _last($which, $robot)
# Sends back the last archive file.
# Parameters:
# - $which: listname
# - $robot: robot
# Return value: 'unknownlist'|'no_archive'|'not_allowed'|1

sub _last {
	my ($which, $robot) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s, %s)', $which, $robot);

	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list)  {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'LAST %s from %s refused, list unknown for robot %s', $which, $sender, $robot);
		return 'unknownlist';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	unless ($list->is_archived()) {
		Sympa::Report::reject_report_cmd('user','empty_archives',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'LAST %s from %s refused, list not archived', $which,  $sender);
		return 'no_archive';
	}
	my $file;
	unless ($file = Sympa::Archive::last_path($list)) {
		Sympa::Report::reject_report_cmd('user','no_required_file',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'LAST %s from %s refused, archive file %s not found', $which,  $sender, $file);
		return 'no_archive';
	}
	unless ($list->may_do('get', $sender)) {
		Sympa::Report::reject_report_cmd('auth','list_private_no_archive',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'LAST %s from %s refused, archive access not allowed', $which, $sender);
		return 'not_allowed';
	}

	unless ($list->archive_send_last($sender)) {
		Sympa::Report::reject_report_cmd('intern',"Unable to send archive to $sender",{'listname'=>$which},$cmd_line,$sender,$robot);
		return 'no_archive';
	}

	Sympa::Log::Syslog::do_log('info', 'LAST %s from %s accepted (%d seconds)', $which,  $sender, time() - $time_command);

	return 1;
}

# _index($which, $robot)
# Sends the list of archived files of a list
# Parameters:
# - $which: list name
# - $robot: robot
# Return value: 'unknown_list'|'not_allowed'|'no_archive'|1

sub _index {
	my ($which, $robot) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s) robot (%s)',$which,$robot);

	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'INDEX %s from %s refused, list unknown for robot %s', $which, $sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	## Now check if we may send the list of users to the requestor.
	## Check all this depending on the values of the Review field in
	## the control file.
	unless ($list->may_do('index', $sender)) {
		Sympa::Report::reject_report_cmd('auth','list_private_no_browse',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'INDEX %s from %s refused, not allowed', $which, $sender);
		return 'not_allowed';
	}
	unless ($list->is_archived()) {
		Sympa::Report::reject_report_cmd('user','empty_archives',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'INDEX %s from %s refused, list not archived', $which, $sender);
		return 'no_archive';
	}

	my @l = $list->archive_ls();
	my $expedition_result = $list->send_file(
		'index_archive',
		$sender,
		$robot,
		{
			'archives'       => \@l,
			'auto_submitted' => 'auto-replied'
		}
	);
	unless ($expedition_result) {
		Sympa::Log::Syslog::do_log('notice',"Unable to send template 'index_archive' to $sender");
		Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> $list->{'name'}},$cmd_line,$sender,$robot);
	}

	Sympa::Log::Syslog::do_log('info', 'INDEX %s from %s accepted (%d seconds)', $which, $sender, time() - $time_command);

	return 1;
}

# _review($listname, $robot, $sign_mod, $message)
# Sends the list of subscribers to the requester.
# Parameters:
# - $listname: list name
# - $robot: robot
# - $sign_mod : 'smime'| -
# Return value: 'unknown_list'|'wrong_auth'|'not_allowed'|'no_subscribers'|1|
# undef

sub _review {
	my ($listname, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s)', $listname,$robot,$sign_mod );

	my $user;
	my $list = Sympa::List->new(
		name   => $listname,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);

	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $listname},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'REVIEW %s from %s refused, list unknown to robot %s', $listname,$sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	$list->on_the_fly_sync_include('use_ttl' => 1);

	my $auth_method = _get_auth_method(
		'review',
		'',
		{
			'type' => 'auth_failed',
			'data' => {},
			'msg'  => "REVIEW $listname from $sender"
		},
		$sign_mod,
		$list
	);
	return 'wrong_auth' unless (defined $auth_method);

	my $result = $list->check_list_authz(
		'review',
		$auth_method,
		{
			'sender'  => $sender,
			'message' => $message
		}
	);
	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action){
		my $error = "Unable to evaluate scenario 'review' for list $listname";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$listname},$cmd_line,$sender,$robot);
		return undef;
	}

	if ($action =~ /request_auth/i) {
		Sympa::Log::Syslog::do_log ('debug2',"auth requested from $sender");
		unless ($list->request_auth ($sender,'review',$robot)){
			my $error = "Unable to request authentification for command 'review'";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$listname},$cmd_line,$sender,$robot);
			return undef;
		}
		Sympa::Log::Syslog::do_log('info', 'REVIEW %s from %s, auth requested (%d seconds)', $listname, $sender, time() - $time_command);
		return 1;
	}
	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{'auto_submitted' => 'auto-replied'}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'review %s from %s refused (not allowed)', $listname,$sender);
		return 'not_allowed';
	}

	my @users;

	if ($action =~ /do_it/i) {
		my $is_owner = $list->am_i('owner', $sender);
		unless ($user = $list->get_first_list_member({'sortby' => 'email'})) {
			Sympa::Report::reject_report_cmd('user','no_subscriber',{'listname' => $listname},$cmd_line);
			Sympa::Log::Syslog::do_log('err', "No subscribers in list '%s'", $list->{'name'});
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
		} while ($user = $list->get_next_list_member());
		my $expedition_result = $list->send_file(
			'review',
			$sender,
			$robot,
			{
			'users'          => \@users,
			'total'          => $list->get_total(),
			'subject'        => "REVIEW $listname",
			'auto_submitted' => 'auto-replied'
			}
		);
		unless ($expedition_result) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'review' to $sender");
			Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=>$listname},$cmd_line,$sender,$robot);
		}

		Sympa::Log::Syslog::do_log('info', 'REVIEW %s from %s accepted (%d seconds)', $listname, $sender, time() - $time_command);
		return 1;
	}
	Sympa::Log::Syslog::do_log('info', 'REVIEW %s from %s aborted, unknown requested action in scenario',$listname,$sender);
	my $error = "Unknown requested action in scenario: $action.";
	Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $listname},$cmd_line,$sender,$robot);
	return undef;
}

# _verify($listname, $robot, $sign_mod)
# Verify an S/MIME signature
# Parameters:
# - $listname: list name
# - $robot: robot
# - $sign_mod: 'smime'| 'dkim'
# Return value: 1

sub _verify {
	my ($listname, $robot, $sign_mod) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s, %s)', $sign_mod, $robot);

	my $list = Sympa::List->new(
		name   => $listname,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	if  ($sign_mod) {
		Sympa::Log::Syslog::do_log('info', 'VERIFY successfull from %s', $sender, time() - $time_command);
		if ($sign_mod eq 'smime') {
			Sympa::Report::notice_report_cmd('smime',{},$cmd_line);
		} elsif($sign_mod eq 'dkim') {
			Sympa::Report::notice_report_cmd('dkim',{},$cmd_line);
		}
	} else {
		Sympa::Log::Syslog::do_log('info', 'VERIFY from %s : could not find correct s/mime signature', $sender, time() - $time_command);
		Sympa::Report::reject_report_cmd('user','no_verify_sign',{},$cmd_line);
	}
	return 1;
}

# _subscribe
# Subscribes a user to a list. The user sent a subscribe
# command. Format was : sub list optionnal comment. User can
# be informed by template 'welcome'
# Parameters:
# - $what (+): command parameters : listname(+), comment
# - $robot (+): robot
# - $sign_mod : 'smime'| -
# Return value: 'unknown_list'|'wrong_auth'|'not_allowed'| 1 | undef
sub _subscribe {
	my ($what, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s, %s, %s)', $what,$robot,$sign_mod,$message);

	$what =~ /^(\S+)(\s+(.+))?\s*$/;
	my($which, $comment) = ($1, $3);

	## Load the list if not already done, and reject the
	## subscription if this list is unknown to us.
	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'SUB %s from %s refused, unknown list for robot %s', $which,$sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	## This is a really minimalistic handling of the comments,
	## it is far away from RFC-822 completeness.
	$comment =~ s/"/\\"/g;
	$comment = "\"$comment\"" if ($comment =~ /[<>\(\)]/);

	## Now check if the user may subscribe to the list

	my $auth_method = _get_auth_method(
		'subscribe',
		$sender,
		{
			'type' => 'wrong_email_confirm',
			'data' => {'command' => 'subscription' },
			'msg'  => "SUB $which from $sender"
		},
		$sign_mod,
		$list
	);
	return 'wrong_auth' unless (defined $auth_method);

	## query what to do with this subscribtion request

	my $result = $list->check_list_authz(
		'subscribe',
		$auth_method,
		{
			'sender'  => $sender,
			'message' => $message
		}
	);
	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action){
		my $error = "Unable to evaluate scenario 'subscribe' for list $which";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
		return undef;
	}

	Sympa::Log::Syslog::do_log('debug2', 'action : %s', $action);

	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{'auto_submitted' => 'auto-replied'}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'SUB %s from %s refused (not allowed)', $which, $sender);
		return 'not_allowed';
	}

	## Unless rejected by scenario, don't go further if the user is subscribed already.
	my $user_entry = $list->get_list_member($sender);
	if ( defined($user_entry)) {
		Sympa::Report::reject_report_cmd('user','already_subscriber',{'email'=>$sender, 'listname'=>$list->{'name'}},$cmd_line);
		Sympa::Log::Syslog::do_log('err','User %s is subscribed to %s already. Ignoring subscription request.', $sender, $list->{'name'});
		return undef;
	}

	## Continue checking scenario.
	if ($action =~ /owner/i) {
		Sympa::Report::notice_report_cmd('req_forward',{},$cmd_line);
		## Send a notice to the owners.
		my $expedition_result = $list->send_notify_to_owner(
			'subrequest',
			{
				'who'     => $sender,
				'keyauth' => $list->compute_auth($sender,'add'),
				'replyto' => Sympa::Configuration::get_robot_conf($robot, 'sympa'),
				'gecos'   => $comment
			}
		);
		unless ($expedition_result) {
			Sympa::Log::Syslog::do_log('info',"Unable to send notify 'subrequest' to $list->{'name'} list owner");
			Sympa::Report::reject_report_cmd('intern',"Unable to send subrequest to $list->{'name'} list owner",{'listname'=> $list->{'name'}},$cmd_line,$sender,$robot);
		}
		if ($list->store_subscription_request($sender, $comment)) {
			Sympa::Log::Syslog::do_log('info', 'SUB %s from %s
				forwarded to the owners of the list (%d seconds)', $which, $sender, time() - $time_command);
		}
		return 1;
	}
	if ($action =~ /request_auth/i) {
		my $cmd = 'subscribe';
		$cmd = "quiet $cmd" if $quiet;
		unless ($list->request_auth ($sender, $cmd, $robot, $comment )){
			my $error = "Unable to request authentification for command 'subscribe'";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
			return undef;
		}
		Sympa::Log::Syslog::do_log('info', 'SUB %s from %s, auth requested (%d seconds)', $which, $sender, time() - $time_command);
		return 1;
	}
	if ($action =~ /do_it/i) {

		my $user_entry = $list->get_list_member($sender);

		if (defined $user_entry) {

			## Only updates the date
			## Options remain the same
			my $user = {};
			$user->{'update_date'} = time();
			$user->{'gecos'} = $comment if $comment;
			$user->{'subscribed'} = 1;

			unless ($list->update_list_member($sender, $user)){
				my $error = "Unable to update user $user in list $which";
				Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
				return undef;
			}
		} else {

			my $u;
			my $defaults = $list->get_default_user_options();
			%{$u} = %{$defaults};
			$u->{'email'} = $sender;
			$u->{'gecos'} = $comment;
			$u->{'date'} = $u->{'update_date'} = time();

			$list->add_list_member($u);
			if (defined $list->{'add_outcome'}{'errors'}) {
				my $error = sprintf "Unable to add user %s in list %s : %s",$u,$which,$list->{'add_outcome'}{'errors'}{'error_message'};
				my $error_type = 'intern';
				$error_type = 'user' if (defined $list->{'add_outcome'}{'errors'}{'max_list_members_exceeded'});
				Sympa::Report::reject_report_cmd($error_type,$error,{'listname'=>$which},$cmd_line,$sender,$robot);
				return undef;
			}
		}

		if ($Sympa::Database::use_db) {
			my $u = Sympa::List::get_global_user($sender);

			Sympa::List::update_global_user(
				$sender,
				{
					'lang' => $u->{'lang'} ||
					          $list->{'admin'}{'lang'},
					'password' => $u->{'password'} ||
						      Sympa::Tools::Password::tmp_passwd($sender, $Sympa::Configuration::Conf{'cookie'})
				}
			);
		}

		## Now send the welcome file to the user
		unless ($quiet || ($action =~ /quiet/i )) {
			my $expedition_result = $list->send_file(
				'welcome',
				$sender,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'welcome' to $sender");
			}
		}

		## If requested send notification to owners
		if ($action =~ /notify/i) {
			my $expedition_result = $list->send_notify_to_owner(
				'notice',
				{
					'who'     => $sender,
					'gecos'   => $comment,
					'command' => 'subscribe'
				}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
			}
		}
		Sympa::Log::Syslog::do_log('info', 'SUB %s from %s accepted (%d seconds, %d subscribers)', $which, $sender, time() - $time_command, $list->get_total());

		return 1;
	}

	Sympa::Log::Syslog::do_log('info', 'SUB %s  from %s aborted, unknown requested action in scenario',$which,$sender);
	my $error = "Unknown requested action in scenario: $action.";
	Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $which},$cmd_line,$sender,$robot);
	return undef;
}

#  _info
# Sends the information file to the requester
# Parameters:
# - $listname (+): concerned list
# - $robot (+): robot
# - $sign_mod : 'smime'|undef
# Return value: 'unknown_list'|'wrong_auth'|'not_allowed'|1| undef

sub _info {
	my ($listname, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s, %s, %s)', $listname,$robot, $sign_mod, $message);

	my $list = Sympa::List->new(
		name   => $listname,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $listname},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'INFO %s from %s refused, unknown list for robot %s', $listname,$sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	my $auth_method = _get_auth_method(
		'info',
		'',
		{
			'type' => 'auth_failed',
			'data' => {},
			'msg'  => "INFO $listname from $sender"
		},
		$sign_mod,
		$list
	);

	return 'wrong_auth' unless (defined $auth_method);

	my $result = $list->check_list_authz('info',$auth_method,
		{'sender' => $sender,
			'message' => $message, });

	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action) {
		my $error = "Unable to evaluate scenario 'review' for list $listname";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$listname},$cmd_line,$sender,$robot);
		return undef;
	}

	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'review %s from %s refused (not allowed)', $listname,$sender);
		return 'not_allowed';
	}
	if ($action =~ /do_it/i) {

		my $data;
		foreach my $key (%{$list->{'admin'}}) {
			$data->{$key} = $list->{'admin'}{$key};
		}

		foreach my $p ('subscribe','unsubscribe','send','review') {
			my $scenario = Sympa::Scenario->new('robot' => $robot,
				'directory' => $list->{'dir'},
				'file_path' => $list->{'admin'}{$p}{'file_path'}
			);
			my $title = $scenario->{'title'}{'gettext'};
			$data->{$p} =Sympa::Language::gettext($title);
		}

		## Digest
		my @days;
		if (defined $list->{'admin'}{'digest'}) {

			foreach my $d (@{$list->{'admin'}{'digest'}{'days'}}) {
				push @days, Sympa::Language::gettext_strftime(
					"%A",
					localtime(0 + ($d +3) * (3600 * 24))
				);
			}
			$data->{'digest'} = join (',', @days).' '.$list->{'admin'}{'digest'}{'hour'}.':'.$list->{'admin'}{'digest'}{'minute'};
		}

		$data->{'available_reception_mode'} = $list->available_reception_mode();

		my $wwsympa_url = Sympa::Configuration::get_robot_conf($robot, 'wwsympa_url');
		$data->{'url'} = $wwsympa_url.'/info/'.$list->{'name'};

		my $expedition_result = $list->send_file(
			'info_report',
			$sender,
			$robot,
			$data
		);
		unless ($expedition_result) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'info_report' to $sender");
			Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> $list->{'name'}},$cmd_line,$sender,$robot);
		}

		Sympa::Log::Syslog::do_log('info', 'INFO %s from %s accepted (%d seconds)', $listname, $sender, time() - $time_command);
		return 1;
	}

	Sympa::Log::Syslog::do_log('info', 'INFO %s  from %s aborted, unknown requested action in scenario',$listname,$sender);
	my $error = "Unknown requested action in scenario: $action.";
	Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $listname},$cmd_line,$sender,$robot);
	return undef;

}

# _signoff
# Unsubscribes a user from a list. The user sent a signoff
# command. Format was : sig list. He can be informed by template 'bye'
# Parametets:
# - $which (+): command parameters : listname(+), email(+)
# - $robot (+): robot
# - $sign_mod : 'smime'| -
# Return value : 'syntax_error'|'unknown_list'|'wrong_auth'|'not_allowed'|
# 1 | undef

sub _signoff {
	my ($which, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s, %s, %s)', $which,$robot, $sign_mod, $message);

	my ($l,$list,$auth_method);
	my $host = Sympa::Configuration::get_robot_conf($robot, 'host');

	## $email is defined if command is "unsubscribe <listname> <e-mail>"
	unless ($which =~ /^(\*|[\w\.\-]+)(\@$host)?(\s+(.+))?$/) {
		Sympa::Report::reject_report_cmd('user','error_syntax',{},$cmd_line);
		Sympa::Log::Syslog::do_log ('notice', "Command syntax error\n");
		return 'syntax_error';
	}

	my $email;
	($which,$email) = ($1,$4||$sender);

	if ($which eq '*') {
		my $success;
		foreach $list ( Sympa::List::get_which ($email,$robot,'member') ){
			$l = $list->{'name'};

			## Skip hidden lists
			my $result = $list->check_list_authz('visibility', 'smtp',
				{'sender' => $sender,
					'message' => $message, });

			my $action;
			$action = $result->{'action'} if (ref($result) eq 'HASH');

			unless (defined $action) {
				my $error = "Unable to evaluate scenario 'visibility' for list $l";
				Sympa::List::send_notify_to_listmaster(
					'intern_error',
					$robot,
					{
						'error'  => $error,
						'who'    => $sender,
						'cmd'    => $cmd_line,
						'list'   => $list,
						'action' => 'Command process'
					}
				);
				next;
			}

			if ($action =~ /reject/) {
				next;
			}

			$result = signoff("$l $email", $robot);
			$success ||= $result;
		}
		return ($success);
	}

	$list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);

	## Is this list defined
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'SIG %s %s from %s, unknown list for robot %s', $which,$email,$sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	$auth_method = _get_auth_method(
		'signoff',
		$email,
		{
			'type' => 'wrong_email_confirm',
			'data' => {'command' => 'unsubscription'},
			'msg'  => "SIG $which from $sender"
		},
		$sign_mod,
		$list
	);
	return 'wrong_auth' unless (defined $auth_method);

	my $result = $list->check_list_authz(
		'unsubscribe',
		$auth_method,
		{
			'email'   => $email,
			'sender'  => $sender,
			'message' => $message
		}
	);
	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action) {
		my $error = "Unable to evaluate scenario 'unsubscribe' for list $l";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=> $which},$cmd_line,$sender,$robot);
		return undef;
	}


	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'listname' => $which},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'listname' => $which},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'SIG %s %s from %s refused (not allowed)', $which, $email, $sender);
		return 'not_allowed';
	}
	if ($action =~ /request_auth\s*\(\s*\[\s*(email|sender)\s*\]\s*\)/i) {
		my $cmd = 'signoff';
		$cmd = "quiet $cmd" if $quiet;
		unless ($list->request_auth ($$1, $cmd, $robot)){
			my $error = "Unable to request authentification for command 'signoff'";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
			return undef;
		}
		Sympa::Log::Syslog::do_log('info', 'SIG %s from %s auth requested (%d seconds)', $which, $sender, time() - $time_command);
		return 1;
	}

	if ($action =~ /owner/i) {
		Sympa::Report::notice_report_cmd('req_forward',{},$cmd_line)
		unless ($action =~ /quiet/i);
		## Send a notice to the owners.
		my $expedition_result = $list->send_notify_to_owner(
			'sigrequest',
			{
				'who' => $sender,
				'keyauth' => $list->compute_auth($sender,'del')
			}
		);
		unless ($expedition_result) {
			Sympa::Log::Syslog::do_log('info',"Unable to send notify 'sigrequest' to $list->{'name'} list owner");
			Sympa::Report::reject_report_cmd('intern_quiet',"Unable to send sigrequest to $list->{'name'} list owner",{'listname'=> $list->{'name'}},$cmd_line,$sender,$robot);
		}
		Sympa::Log::Syslog::do_log('info', 'SIG %s from %s forwarded to the owners of the list (%d seconds)', $which, $sender, time() - $time_command);
		return 1;
	}
	if ($action =~ /do_it/i) {
		## Now check if we know this email on the list and
		## remove it if found, otherwise just reject the
		## command.
		my $user_entry = $list->get_list_member($email);
		unless ((defined $user_entry)) {
			Sympa::Report::reject_report_cmd('user','your_email_not_found',{'email'=> $email, 'listname' => $list->{'name'}},$cmd_line);
			Sympa::Log::Syslog::do_log('info', 'SIG %s from %s refused, not on list', $which, $email);

			## Tell the owner somebody tried to unsubscribe
			if ($action =~ /notify/i) {
				# try to find email from same domain or email wwith same local part.

				my $expedition_result = $list->send_notify_to_owner(
					'warn-signoff',
					{'who' => $email }
				);
				unless ($expedition_result) {
					Sympa::Log::Syslog::do_log('info',"Unable to send notify 'warn-signoff' to $list->{'name'} list owner");
				}
			}
			return 'not_allowed';
		}

		## Really delete and rewrite to disk.
		unless ($list->delete_list_member('users' => [$email], 'exclude' =>' 1', 'parameter' => 'unsubscription')){
			my $error = "Unable to delete user $email from list $which";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
		}


		## Notify the owner
		if ($action =~ /notify/i) {
			my $expedition_result = $list->send_notify_to_owner(
				'notice',
				{
					'who'     => $email,
					'command' => 'signoff'
				}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
			}
		}

		unless ($quiet || ($action =~ /quiet/i)) {
			## Send bye file to subscriber
			my $expedition_result = $list->send_file(
				'bye',
				$email,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'bye' to $email");
			}
		}

		Sympa::Log::Syslog::do_log('info', 'SIG %s from %s accepted (%d seconds, %d subscribers)', $which, $email, time() - $time_command, $list->get_total() );

		return 1;
	}
	my $error = "Unknown requested action in scenario: $action.";
	Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $which},$cmd_line,$sender,$robot);
	return undef;
}

# _add
# Adds a user to a list (requested by another user). Verifies
# the proper authorization and sends acknowledgements unless
# quiet add.
# Parameters:
# - $what (+): command parameters : listname(+), email(+), comments
# - $robot (+): robot
# - $sign_mod : 'smime'|undef
# Return value: 'unknown_list'|'wrong_auth'|'not_allowed'|1|undef

sub _add {
	my ($what, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s,%s)', $what,$robot, $sign_mod, $message);

	my $email_regexp = Sympa::Tools::get_regexp('email');

	$what =~ /^(\S+)\s+($email_regexp)(\s+(.+))?\s*$/;
	my($which, $email, $comment) = ($1, $2, $6);

	## Load the list if not already done, and reject the
	## subscription if this list is unknown to us.
	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'ADD %s %s from %s refused, unknown list for robot %s', $which, $email,$sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	my $auth_method = _get_auth_method(
		'add',
		$email,
		{
			'type' => 'wrong_email_confirm',
			'data' => {'command' => 'addition'},
			'msg'  => "ADD $which $email from $sender"
		},
		$sign_mod,
		$list
	);
	return 'wrong_auth' unless (defined $auth_method);

	my $result = $list->check_list_authz('add',$auth_method,
		{'email' => $email,
			'sender' => $sender,
			'message' => $message, });
	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action){
		my $error = "Unable to evaluate scenario 'add' for list $which";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
		return undef;
	}

	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'listname' => $which},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'listname' => $which},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'ADD %s %s from %s refused (not allowed)', $which, $email, $sender);
		return 'not_allowed';
	}

	if ($action =~ /request_auth/i) {
		my $cmd = 'add';
		$cmd = "quiet $cmd" if $quiet;
		unless ($list->request_auth ($sender, $cmd, $robot, $email, $comment)){
			my $error = "Unable to request authentification for command 'add'";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
			return undef;
		}
		Sympa::Log::Syslog::do_log('info', 'ADD %s from %s, auth requested(%d seconds)', $which, $sender, time() - $time_command);
		return 1;
	}
	if ($action =~ /do_it/i) {
		if ($list->is_list_member($email)) {
			Sympa::Report::reject_report_cmd('user','already_subscriber',{'email'=> $email, 'listname' => $which},$cmd_line);
			Sympa::Log::Syslog::do_log('err',"ADD command rejected ; user '%s' already member of list '%s'", $email, $which);
			return undef;

		} else {
			my $u;
			my $defaults = $list->get_default_user_options();
			%{$u} = %{$defaults};
			$u->{'email'} = $email;
			$u->{'gecos'} = $comment;
			$u->{'date'} = $u->{'update_date'} = time();

			$list->add_list_member($u);
			if (defined $list->{'add_outcome'}{'errors'}) {
				my $error = sprintf "Unable to add user %s in list %s : %s",$u,$which,$list->{'add_outcome'}{'errors'}{'error_message'};
				my $error_type = 'intern';
				$error_type = 'user' if (defined $list->{'add_outcome'}{'errors'}{'max_list_members_exceeded'});
				Sympa::Report::reject_report_cmd($error_type,$error,{'listname'=>$which},$cmd_line,$sender,$robot);
				return undef;
			}

			$list->delete_subscription_request($email);
			Sympa::Report::notice_report_cmd('now_subscriber',{'email'=> $email, 'listname' => $which},$cmd_line);
		}

		if ($Sympa::Database::use_db) {
			my $u = Sympa::List::get_global_user($email);

			Sympa::List::update_global_user($email, {'lang' => $u->{'lang'} || $list->{'admin'}{'lang'},
					'password' => $u->{'password'} ||
					Sympa::Tools::Password::tmp_passwd($email, $Sympa::Configuration::Conf{'cookie'})
				});
		}

		## Now send the welcome file to the user if it exists and notification is supposed to be sent.
		unless ($quiet || $action =~ /quiet/i) {
			my $expedition_result = $list->send_file(
				'welcome',
				$email,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'welcome' to $email");
			}
		}

		Sympa::Log::Syslog::do_log('info', 'ADD %s %s from %s accepted
			(%d seconds, %d subscribers)', $which, $email, $sender,  time() - $time_command, $list->get_total() );
		if ($action =~ /notify/i) {
			my $expedition_result = $list->send_notify_to_owner(
				'notice',
				{
					'who'     => $email,
					'gecos'   => $comment,
					'command' => 'add',
					'by'      => $sender
				}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
			}
		}
		return 1;
	}
	Sympa::Log::Syslog::do_log('info', 'ADD %s  from %s aborted, unknown requested action in scenario',$which,$sender);
	my $error = "Unknown requested action in scenario: $action.";
	Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $which},$cmd_line,$sender,$robot);
	return undef;

}

# _invite
# Invite someone to subscribe a list by sending him
# template 'invite'
# Parameters:
# - $what (+): listname(+), email(+) and comments
# - $robot (+): robot
# - $sign_mod : 'smime'|undef
# Return value: 'unknown_list'|'wrong_auth'|'not_allowed'|1|undef

sub _invite {
	my ($what, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s,%s)', $what, $robot, $sign_mod, $message);

	my $sympa = Sympa::Configuration::get_robot_conf($robot, 'sympa');

	$what =~ /^(\S+)\s+(\S+)(\s+(.+))?\s*$/;
	my($which, $email, $comment) = ($1, $2, $4);

	## Load the list if not already done, and reject the
	## subscription if this list is unknown to us.
	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'INVITE %s %s from %s refused, unknown list for robot', $which, $email,$sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	my $auth_method = _get_auth_method(
		'invite',
		$email,
		{
			'type' => 'wrong_email_confirm',
			'data' => {'command' => 'invitation'},
			'msg'  => "INVITE $which $email from $sender"
		},
		$sign_mod,
		$list
	);
	return 'wrong_auth' unless (defined $auth_method);

	my $result = $list->check_list_authz('invite',$auth_method,
		{'sender' => $sender,
			'message' => $message, });

	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action){
		my $error = "Unable to evaluate scenario 'invite' for list $which";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
		return undef;
	}

	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'INVITE %s %s from %s refused (not allowed)', $which, $email, $sender);
		return 'not_allowed';
	}

	if ($action =~ /request_auth/i) {
		unless ($list->request_auth ($sender, 'invite', $robot, $email, $comment)){
			my $error = "Unable to request authentification for command 'invite'";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
			return undef;
		}

		Sympa::Log::Syslog::do_log('info', 'INVITE %s from %s, auth requested (%d seconds)', $which, $sender, time() - $time_command);
		return 1;
	}
	if ($action =~ /do_it/i) {
		if ($list->is_list_member($email)) {
			Sympa::Report::reject_report_cmd('user','already_subscriber',{'email'=> $email, 'listname' => $which},$cmd_line);
			Sympa::Log::Syslog::do_log('err',"INVITE command rejected ; user '%s' already member of list '%s'", $email, $which);
			return undef;
		} else {
			## Is the guest user allowed to subscribe in this list ?

			my %context;
			$context{'user'}{'email'} = $email;
			$context{'user'}{'gecos'} = $comment;
			$context{'requested_by'} = $sender;

			my $result = $list->check_list_authz('subscribe','smtp',
				{'sender' => $sender,
					'message' => $message, });
			my $action;
			$action = $result->{'action'} if (ref($result) eq 'HASH');

			unless (defined $action){
				my $error = "Unable to evaluate scenario 'subscribe' for list $which";
				Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
				return undef;
			}

			if ($action =~ /request_auth/i) {
				my $keyauth = $list->compute_auth ($email, 'subscribe');
				my $command = "auth $keyauth sub $which $comment";
				$context{'subject'} = $command;
				$context{'url'}= "mailto:$sympa?subject=$command";
				$context{'url'} =~ s/\s/%20/g;
				my $expedition_result =
				$list->send_file(
					'invite',
					$email,
					$robot,
					\%context
			);
				unless ($expedition_result) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send template 'invite' to $email");
					Sympa::Report::reject_report_cmd('intern',"Unable to send template 'invite' to $email",{'listname'=> $which},$cmd_line,$sender,$robot);
					return undef;
				}
				Sympa::Log::Syslog::do_log('info', 'INVITE %s %s from %s accepted, auth requested (%d seconds, %d subscribers)', $which, $email, $sender, time() - $time_command, $list->get_total());
				Sympa::Report::notice_report_cmd('invite',{'email'=> $email, 'listname' => $which},$cmd_line);

			} elsif ($action !~ /reject/i) {
				$context{'subject'} = "sub $which $comment";
				$context{'url'}= "mailto:$sympa?subject=$context{'subject'}";
				$context{'url'} =~ s/\s/%20/g;
				my $expedition_result = $list->send_file(
					'invite',
					$email,
					$robot,
					\%context
				);
				unless ($expedition_result) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send template 'invite' to $email");
					Sympa::Report::reject_report_cmd('intern',"Unable to send template 'invite' to $email",{'listname'=> $which},$cmd_line,$sender,$robot);
					return undef;
				}
				Sympa::Log::Syslog::do_log('info', 'INVITE %s %s from %s accepted,  (%d seconds, %d subscribers)', $which, $email, $sender, time() - $time_command, $list->get_total() );
				Sympa::Report::notice_report_cmd('invite',{'email'=> $email, 'listname' => $which},$cmd_line);

			} elsif ($action =~ /reject/i) {
				Sympa::Log::Syslog::do_log('info', 'INVITE %s %s from %s refused, not allowed (%d seconds, %d subscribers)', $which, $email, $sender, time() - $time_command, $list->get_total() );
				if (defined $result->{'tt2'}) {
				my $expedition_result = $list->send_file(
					$result->{'tt2'},
					$sender,
					$robot,
					{}
				);
				unless ($expedition_result) {
						Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
						Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
					}
				} else {
					Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'email'=> $email, 'listname' => $which},$cmd_line);
				}
			}
		}
		return 1;
	}
	Sympa::Log::Syslog::do_log('info', 'INVITE %s  from %s aborted, unknown requested action in scenario',$which,$sender);
	my $error = "Unknown requested action in scenario: $action.";
	Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $which},$cmd_line,$sender,$robot);
	return undef;
}

# _remind
# Sends a personal reminder to each subscriber of one list or
# of every list ($which = *) using template 'remind' or
# 'global_remind'
# Parameters:
# - $which (+): * | listname
# - $robot (+): robot
# - $sign_mod : 'smime'| -
# Return value: 'syntax_error'|'unknown_list'|'wrong_auth'|'not_allowed'|1|undef

sub _remind {
	my ($which, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s,%s)', $which,$robot,$sign_mod,$message);

	my $host = Sympa::Configuration::get_robot_conf($robot, 'host');

	my %context;

	unless ($which =~ /^(\*|[\w\.\-]+)(\@$host)?\s*$/) {
		Sympa::Report::reject_report_cmd('user','error_syntax',{},$cmd_line);
		Sympa::Log::Syslog::do_log ('notice', "Command syntax error\n");
		return 'syntax_error';
	}

	my $listname = $1;
	my $list;

	unless ($listname eq '*') {
		$list = Sympa::List->new(
			name   => $listname,
			robot  => $robot,
			source => Sympa::Database::get_source()
		);
		unless ($list) {
			Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
			Sympa::Log::Syslog::do_log('info', 'REMIND %s from %s refused, unknown list for robot %s', $which, $sender,$robot);
			return 'unknown_list';
		}
	}

	my $auth_method;

	if ($listname eq '*') {
		$auth_method = _get_auth_method(
			'remind',
			'',
			{
				'type' => 'auth_failed',
				'data' => {},
				'msg'  => "REMIND $listname from $sender"
			},
			$sign_mod
		);
	} else {
		$auth_method = _get_auth_method(
			'remind',
			'',
			{
				'type' => 'auth_failed',
				'data' => {},
				'msg'  => "REMIND $listname from $sender"
			},
			$sign_mod,
			$list
		);
	}

	return 'wrong_auth' unless (defined $auth_method);

	my $action;
	my $result;

	if ($listname eq '*') {

		$result = Sympa::Scenario::request_action(
			'global_remind',
			$auth_method,
			$robot,
			{'sender' => $sender }
		);
		$action = $result->{'action'} if (ref($result) eq 'HASH');

	} else {

		Sympa::Language::set_lang($list->{'admin'}{'lang'});

		$host = $list->{'admin'}{'host'};

		$result = $list->check_list_authz(
			'remind',
			$auth_method,
			{
				'sender'  => $sender,
				'message' => $message
			}
		);

		$action = $result->{'action'} if (ref($result) eq 'HASH');

	}

	unless (defined $action){
		my $error = "Unable to evaluate scenario 'remind' for list $listname";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=> $listname},$cmd_line,$sender,$robot);
		return undef;
	}


	if ($action =~ /reject/i) {
		Sympa::Log::Syslog::do_log ('info',"Remind for list $listname from $sender refused");
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");

				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'listname' => $listname},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{},$cmd_line);
		}
		return 'not_allowed';
	} elsif ($action =~ /request_auth/i) {
		Sympa::Log::Syslog::do_log ('debug2',"auth requested from $sender");
		if ($listname eq '*') {
			unless (Sympa::List::request_auth ($sender,'remind', $robot)){
				my $error = "Unable to request authentification for command 'remind'";
				Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$listname},$cmd_line,$sender,$robot);
				return undef;
			}
		} else {
			unless ($list->request_auth ($sender,'remind', $robot)){
				my $error = "Unable to request authentification for command 'remind'";
				Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$listname},$cmd_line,$sender,$robot);
				return undef;
			}
		}
		Sympa::Log::Syslog::do_log('info', 'REMIND %s from %s, auth requested (%d seconds)', $listname, $sender, time() - $time_command);
		return 1;
	} elsif ($action =~ /do_it/i) {

		if ($listname ne '*') {

			unless ($list) {
				Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $listname},$cmd_line);
				Sympa::Log::Syslog::do_log('info', 'REMIND %s from %s refused, unknown list for robot %s', $listname,$sender,$robot);
				return 'unknown_list';
			}

			## for each subscriber send a reminder
			my $total=0;
			my $user;

			unless ($user = $list->get_first_list_member()) {
				my $error = "Unable to get subscribers for list $listname";
				Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$listname},$cmd_line,$sender,$robot);
				return undef;
			}

			do {
				my $expedition_result = $list->send_file(
					'remind',
					$user->{'email'},
					$robot,
					{}
				);
				unless ($expedition_result) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send template 'remind' to $user->{'email'}");
					Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> $listname},$cmd_line,$sender,$robot);
				}
				$total += 1;
			} while ($user = $list->get_next_list_member());

			Sympa::Report::notice_report_cmd('remind',{'total'=> $total,'listname' => $listname},$cmd_line);
			Sympa::Log::Syslog::do_log('info', 'REMIND %s  from %s accepted, sent to %d subscribers (%d seconds)',$listname,$sender,$total, time() - $time_command);

			return 1;
		} else {
			## Global REMIND
			my %global_subscription;
			my %global_info;
			my $count = 0;

			$context{'subject'} =Sympa::Language::gettext("Subscription summary");
			# this remind is a global remind.

			my $all_lists = Sympa::List::get_lists($robot);
			foreach my $list (@$all_lists){

				my $listname = $list->{'name'};

				next unless (my $user = $list->get_first_list_member());

				do {
					my $email = lc ($user->{'email'});


					my $result = $list->check_list_authz('visibility','smtp',
						{'sender' => $sender,
							'message' => $message, });
					my $action;
					$action = $result->{'action'} if (ref($result) eq 'HASH');

					unless (defined $action) {
						my $error = "Unable to evaluate scenario 'visibility' for list $listname";
						Sympa::List::send_notify_to_listmaster(
							'intern_error',
							$robot,
							{
								'error'  => $error,
								'who'    => $sender,
								'cmd'    => $cmd_line,
								'list'   => $list,
								'action' => 'Command process'
							}
						);
						next;
					}

					if ($action eq 'do_it') {
						push @{$global_subscription{$email}},$listname;

						$user->{'lang'} ||= $list->{'admin'}{'lang'};

						$global_info{$email} = $user;

						Sympa::Log::Syslog::do_log('debug2','remind * : %s subscriber of %s', $email,$listname);
						$count++;
					}
				} while ($user = $list->get_next_list_member());
			}
			Sympa::Log::Syslog::do_log('debug2','Sending REMIND * to %d users', $count);

			foreach my $email (keys %global_subscription) {
				my $user = Sympa::List::get_global_user($email);
				foreach my $key (keys %{$user}) {
					$global_info{$email}{$key} = $user->{$key}
					if ($user->{$key});
				}

				$context{'user'}{'email'} = $email;
				$context{'user'}{'lang'} = $global_info{$email}{'lang'};
				$context{'user'}{'password'} = $global_info{$email}{'password'};
				$context{'user'}{'gecos'} = $global_info{$email}{'gecos'};
				$context{'use_bulk'} = 1;
				@{$context{'lists'}} = @{$global_subscription{$email}};
				$context{'use_bulk'} = 1;

				my $expedition_result = Sympa::List::send_global_file(
					'global_remind',
					$email,
					$robot,
					\%context
				);
				unless ($expedition_result) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send template 'global_remind' to $email");
					Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> $listname},$cmd_line,$sender,$robot);
				}
			}
			Sympa::Report::notice_report_cmd('glob_remind',{'count'=> $count},$cmd_line);
		}
	} else {
		Sympa::Log::Syslog::do_log('info', 'REMIND %s  from %s aborted, unknown requested action in scenario',$listname,$sender);
		my $error = "Unknown requested action in scenario: $action.";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $listname},$cmd_line,$sender,$robot);
		return undef;
	}
}

# _del
# Removes a user from a list (requested by another user).
# Verifies the authorization and sends acknowledgements
# unless quiet is specified.
# Parameters:
# - $what (+): command parameters : listname(+), email(+)
# - $robot (+): robot
# - $sign_mod : 'smime'|undef
# Return value: 'unknown_list'|'wrong_auth'|'not_allowed'|1|undef

sub _del {
	my ($what, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s,%s)', $what,$robot,$sign_mod,$message);

	my $email_regexp = Sympa::Tools::get_regexp('email');

	$what =~ /^(\S+)\s+($email_regexp)\s*/;
	my($which, $who) = ($1, $2);

	## Load the list if not already done, and reject the
	## subscription if this list is unknown to us.
	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'DEL %s %s from %s refused, unknown list for robot %s', $which, $who,$sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	my $auth_method = _get_auth_method(
		'del',
		$who,
		{
			'type' => 'wrong_email_confirm',
			'data' => {'command' => 'delete'},
			'msg'  => "DEL $which $who from $sender"
		},
		$sign_mod,
		$list
	);
	return 'wrong_auth' unless (defined $auth_method);

	## query what to do with this DEL request
	my $result = $list->check_list_authz('del',$auth_method,
		{'sender' => $sender,
			'email' => $who,
			'message' => $message, });

	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');

	unless (defined $action){
		my $error = "Unable to evaluate scenario 'del' for list $which";
		Sympa::Report::reject_report_cmd('intern',$error,{'listname'=> $which},$cmd_line,$sender,$robot);
		return undef;
	}


	if ($action =~ /reject/i) {
		if (defined $result->{'tt2'}) {
			my $expedition_result = $list->send_file(
				$result->{'tt2'},
				$sender,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{tt2}' to $sender");
				Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'listname' => $which},$cmd_line);
			}
		} else {
			Sympa::Report::reject_report_cmd('auth',$result->{'reason'},{'listname' => $which},$cmd_line);
		}
		Sympa::Log::Syslog::do_log('info', 'DEL %s %s from %s refused (not allowed)', $which, $who, $sender);
		return 'not_allowed';
	}
	if ($action =~ /request_auth/i) {
		my $cmd = 'del';
		$cmd = "quiet $cmd" if $quiet;
		unless ($list->request_auth ($sender, $cmd, $robot, $who )){
			my $error = "Unable to request authentification for command 'del'";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
			return undef;
		}
		Sympa::Log::Syslog::do_log('info', 'DEL %s %s from %s, auth requested (%d seconds)', $which, $who, $sender, time() - $time_command);
		return 1;
	}

	if ($action =~ /do_it/i) {
		## Check if we know this email on the list and remove it. Otherwise
		## just reject the message.
		my $user_entry = $list->get_list_member($who);

		unless ((defined $user_entry)) {
			Sympa::Report::reject_report_cmd('user','your_email_not_found',{'email'=> $who, 'listname' => $which},$cmd_line);
			Sympa::Log::Syslog::do_log('info', 'DEL %s %s from %s refused, not on list', $which, $who, $sender);
			return 'not_allowed';
		}

		## Really delete and rewrite to disk.
		my $u;
		unless ($u = $list->delete_list_member('users' => [$who], 'exclude' =>' 1', 'parameter' => 'deletd by admin')){
			my $error = "Unable to delete user $who from list $which for command 'del'";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname'=>$which},$cmd_line,$sender,$robot);
		}


		## Send a notice to the removed user, unless the owner indicated
		## quiet del.
		unless ($quiet || $action =~ /quiet/i) {
			my $expedition_result = $list->send_file(
				'removed',
				$who,
				$robot,
				{}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'removed' to $who");
			}
		}
		Sympa::Report::notice_report_cmd('removed',{'email'=> $who, 'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'DEL %s %s from %s accepted (%d seconds, %d subscribers)', $which, $who, $sender, time() - $time_command, $list->get_total() );
		if ($action =~ /notify/i) {
			my $expedition_result = $list->send_notify_to_owner(
				'notice',
				{
					'who'     => $who,
					'gecos'   => "",
					'command' => 'del',
					'by'      => $sender
				}
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('info',"Unable to send notify 'notice' to $list->{'name'} list owner");
			}
		}
		return 1;
	}
	Sympa::Log::Syslog::do_log('info', 'DEL %s %s from %s aborted, unknown requested action in scenario',$which,$who,$sender);
	my $error = "Unknown requested action in scenario: $action.";
	Sympa::Report::reject_report_cmd('intern',$error, {'listname' => $which},$cmd_line,$sender,$robot);
	return undef;
}

# _set
# Change subscription options (reception or visibility)
# Parameters:
# - $what (+): command parameters : listname,
#        reception mode (digest|digestplain|nomail|normal...)
#        or visibility mode(conceal|noconceal)
# - $robot (+): robot
# Return value:'syntax_error'|'unknown_list'|'not_allowed'|'failed'|1

sub _set {
	my ($what, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s,%s)', $what, $robot, $sign_mod, $message);

	$what =~ /^\s*(\S+)\s+(\S+)\s*$/;
	my ($which, $mode) = ($1, $2);

	## Unknown command (should be checked....)
	unless ($mode =~ /^(digest|digestplain|nomail|normal|each|mail|conceal|noconceal|summary|notice|txt|html|urlize)$/i) {
		Sympa::Report::reject_report_cmd('user','error_syntax',{},$cmd_line);
		return 'syntax_error';
	}

	## SET EACH is a synonim for SET MAIL
	$mode = 'mail' if ($mode =~ /^(each|eachmail|nodigest|normal)$/i);
	$mode =~ y/[A-Z]/[a-z]/;

	## Recursive call to subroutine
	if ($which eq "*"){
		my $status;
		foreach my $list  ( Sympa::List::get_which ($sender,$robot,'member')){
			my $l = $list->{'name'};

			## Skip hidden lists
			my $result = $list->check_list_authz('visibility', 'smtp',
				{'sender' => $sender,
					'message' => $message, });

			my $action;
			$action = $result->{'action'} if (ref($result) eq 'HASH');

			unless (defined $action) {
				my $error = "Unable to evaluate scenario 'visibility' for list $l";
				Sympa::List::send_notify_to_listmaster(
					'intern_error',
					$robot,
					{
						'error'  => $error,
						'who'    => $sender,
						'cmd'    => $cmd_line,
						'list'   => $list,
						'action' => 'Command process'
					}
				);
				next;
			}


			if ($action =~ /reject/) {
				next;
			}

			my $current_status = set ("$l $mode");
			$status ||= $current_status;
		}
		return $status;
	}

	## Load the list if not already done, and reject
	## if this list is unknown to us.
	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);

	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'SET %s %s from %s refused, unknown list for robot %s', $which, $mode, $sender,$robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	## Check if we know this email on the list and remove it. Otherwise
	## just reject the message.
	unless ($list->is_list_member($sender) ) {
		Sympa::Report::reject_report_cmd('user','email_not_found',{'email'=> $sender, 'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'SET %s %s from %s refused, not on list',  $which, $mode, $sender);
		return 'not allowed';
	}

	## May set to DIGEST
	if ($mode =~ /^(digest|digestplain|summary)/ and !$list->is_digest()){
		Sympa::Report::reject_report_cmd('user','no_digest',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'SET %s DIGEST from %s refused, no digest mode', $which, $sender);
		return 'not_allowed';
	}

	if ($mode =~ /^(mail|nomail|digest|digestplain|summary|notice|txt|html|urlize|not_me)/){
		# Verify that the mode is allowed
		if (! $list->is_available_reception_mode($mode)) {
			Sympa::Report::reject_report_cmd('user','available_reception_mode',{'listname' => $which, 'modes' => $list->available_reception_mode},$cmd_line);
			Sympa::Log::Syslog::do_log('info','SET %s %s from %s refused, mode not available', $which, $mode, $sender);
			return 'not_allowed';
		}

		my $update_mode = $mode;
		$update_mode = '' if ($update_mode eq 'mail');
		unless ($list->update_list_member($sender,{'reception'=> $update_mode, 'update_date' => time})) {
			my $error = "Failed to change subscriber '$sender' options for list $which";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $which},$cmd_line,$sender,$robot);
			Sympa::Log::Syslog::do_log('info', 'SET %s %s from %s refused, update failed',  $which, $mode, $sender);
			return 'failed';
		}

		Sympa::Report::notice_report_cmd('config_updated',{'listname' => $which},$cmd_line);

		Sympa::Log::Syslog::do_log('info', 'SET %s %s from %s accepted (%d seconds)', $which, $mode, $sender, time() - $time_command);
	}

	if ($mode =~ /^(conceal|noconceal)/){
		unless ($list->update_list_member($sender,{'visibility'=> $mode, 'update_date' => time})) {
			my $error = "Failed to change subscriber '$sender' options for list $which";
			Sympa::Report::reject_report_cmd('intern',$error,{'listname' => $which},$cmd_line,$sender,$robot);
			Sympa::Log::Syslog::do_log('info', 'SET %s %s from %s refused, update failed',  $which, $mode, $sender);
			return 'failed';
		}

		Sympa::Report::notice_report_cmd('config_updated',{'listname' => $which},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'SET %s %s from %s accepted (%d seconds)', $which, $mode, $sender, time() - $time_command);
	}
	return 1;
}

# _distribute
# Distributes the broadcast of a validated moderated message
# Parameters:
# - $what (+): command parameters : listname(+), authentification key(+)
# - $robot (+): robot
#
# Return value: 'unknown_list'|'msg_noty_found'| 1 | undef

sub _distribute {
	my ($what, $robot) = @_;

	$what =~ /^\s*(\S+)\s+(.+)\s*$/;
	my($which, $key) = ($1, $2);
	$which =~ y/A-Z/a-z/;

	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s,%s)', $which,$robot,$key,$what);

	my $start_time = time(); # get the time at the beginning
	## Load the list if not already done, and reject the
	## subscription if this list is unknown to us.
	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Log::Syslog::do_log('info', 'DISTRIBUTE %s %s from %s refused, unknown list for robot %s', $which, $key, $sender,$robot);
		Sympa::Report::reject_report_msg('user','list_unknown',$sender,{'listname' => $which},$robot,'','');
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	#read the moderation queue and purge it

	my $modspool = Sympa::Spool->new(
		name   => 'mod',
		source => Sympa::Database::get_source()
	);
	my $name = $list->{'name'};

	my $message_in_spool = $modspool->get_message({'list'=>$list->{'name'},'robot'=>$robot,'authkey'=>$key});
	unless ($message_in_spool) {
		## if the message has been accepted via WWSympa, it's in spool 'validated'
		my $validatedspool = Sympa::Spool->new(
			name   => 'validated',
			source => Sympa::Database::get_source()
		);
		$message_in_spool = $validatedspool->get_message({'list'=>$list->{'name'},'robot'=>$robot,'authkey'=>$key});
	}
	unless ($message_in_spool) {
		Sympa::Log::Syslog::do_log('err', 'Unable to find message for %s with key %s', $name, $key);
		Sympa::Report::reject_report_msg('user','unfound_message',$sender,{'listname' => $name,'key'=> $key},$robot,'',$list);
		return 'msg_not_found';

	}
	my $message = Sympa::Message->new(
		string                => $message_in_spool->{messageasstring},
		messagekey            => $message_in_spool->{messagekey},
		spoolname             => $message_in_spool->{spoolname},
		create_list_if_needed => $message_in_spool->{create_list_if_needed}
	);
	unless (defined $message) {
		Sympa::Log::Syslog::do_log('err', 'Unable to create message object for %s@%s validation key %s',$name,$robot,$key);
		Sympa::Report::reject_report_msg('user','unfound_message',$sender,{'listname' => $name,'key'=> $key},$robot,'',$list);
		return 'msg_not_found';
	}

	my $msg = $message->{'msg'};
	my $bytes = $message->{'size'};
	my $hdr= $msg->head();

	my $msg_id = $hdr->get('Message-Id');
	my $msg_string = $msg->as_string();

	$hdr->add('X-Validation-by', $sender);

	## Distribute the message
	my $numsmtp;
	my $apply_dkim_signature = 'off';
	$apply_dkim_signature = 'on' if Sympa::Tools::Data::is_in_array($list->{'admin'}{'dkim_signature_apply_on'},'any');
	$apply_dkim_signature = 'on' if Sympa::Tools::Data::is_in_array($list->{'admin'}{'dkim_signature_apply_on'},'editor_validated_messages');

	$numsmtp =$list->distribute_msg('message'=> $message,
		'apply_dkim_signature'=>$apply_dkim_signature);
	unless (defined $numsmtp) {
		Sympa::Log::Syslog::do_log('err','Unable to send message to list %s', $name);
		Sympa::Report::reject_report_msg('intern','',$sender,{'msg_id' => $msg_id},$robot,$msg_string,$list);
		return undef;
	}
	unless ($numsmtp) {
		Sympa::Log::Syslog::do_log('info', 'Message for %s from %s accepted but all subscribers use digest,nomail or summary',$which, $sender);
	}
	Sympa::Log::Syslog::do_log('info', 'Message for %s from %s accepted (%d seconds, %d sessions, %d subscribers), message-id=%s, size=%d', $which, $sender, time - $start_time, $numsmtp, $list->get_total(), $hdr->get('Message-Id'), $bytes);

	unless ($quiet) {
		unless (Sympa::Report::notice_report_msg('message_distributed',$sender,{'key' => $key,'message' => $message},$robot,$list)) {
			Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report', entry 'message_distributed' to $sender");
		}
	}

	Sympa::Log::Syslog::do_log('info', 'DISTRIBUTE %s %s from %s accepted (%d seconds)', $name, $key, $sender, time() - $time_command);

	return 1;
}

# _confirm
# Confirms the authentification of a message for its distribution on a list
# Parameters:
# - $what (+): command parameter : authentification key
# - $robot (+): robot
# Return value: 'wrong_auth'|'msg_not_found'| 1  | undef

sub _confirm {
	my ($what, $robot) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s)', $what, $robot);

	$what =~ /^\s*(\S+)\s*$/;
	my $key = $1; chomp $key;

	my $spool = Sympa::Spool->new(
		name   => 'auth',
		source => Sympa::Database::get_source()
	);

	my $messageinspool = $spool->get_message({'authkey'=>$key});

	unless ($messageinspool) {
		Sympa::Log::Syslog::do_log('info', 'CONFIRM %s from %s refused, auth failed', $key,$sender);
		Sympa::Report::reject_report_msg('user','unfound_file_message',$sender,{'key'=> $key},$robot,'','');
		return 'wrong_auth';
	}
	my $message = Sympa::Message->new(
		string                => $messageinspool->{messageasstring},
		messagekey            => $messageinspool->{messagekey},
		spoolname             => $messageinspool->{spoolname},
		create_list_if_needed => $messageinspool->{create_list_if_needed}
	);

	unless (defined $message) {
		Sympa::Log::Syslog::do_log('err', 'Unable to create message object for key %s', $key);
		Sympa::Report::reject_report_msg('user','wrong_format_message',$sender,{'key'=> $key},$robot,'','');
		return 'msg_not_found';
	}

	my $msg        = $message->{'msg'};
	my $msg_id     = $msg->head()->get('Message-Id');
	my $msg_string = $msg->as_string();

	my $list = Sympa::List->new(
		name    => $message->{'listname'},
		robot   => $robot,
		source  => Sympa::Database::get_source(),
		options => {'just_try' => 1}
	);
	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	my $name = $list->{'name'};

	my $result = $list->check_list_authz(
		'send',
		'md5',
		{
			'sender'  => $sender,
			'message' => $message,
		}
	);

	my $action;
	$action = $result->{'action'} if (ref($result) eq 'HASH');


	unless (defined $action) {
		Sympa::Log::Syslog::do_log('err', 'message (%s) ignored because unable to evaluate scenario for list %s',$msg_id,$name);
		Sympa::Report::reject_report_msg('intern','Message ignored because scenario "send" cannot be evaluated',$sender,{'msg_id' => $msg_id,'message' => $message},
			$robot,$msg_string,$list);
		return undef;
	}

	if ($action =~ /^editorkey(\s?,\s?(quiet))?/) {
		my $key = $list->send_to_editor('md5', $message);

		unless (defined $key) {
			Sympa::Log::Syslog::do_log('err','Calling to send_to_editor() function failed for user %s in list %s', $sender, $name);
			Sympa::Report::reject_report_msg('intern','The request moderation sending to moderator failed.',$sender,{'msg_id' => $msg_id,'message' => $message},$robot,$msg_string,$list);
			return undef
		}

		Sympa::Log::Syslog::do_log('info', 'Message with key %s for list %s from %s sent to editors', $key, $name, $sender);

		unless ($2 eq 'quiet') {
			unless (Sympa::Report::notice_report_msg('moderating_message',$sender,{'message' => $message},$robot,$list)) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report', entry 'moderating_message' to $sender");
			}
		}
		return 1;

	} elsif($action =~ /editor(\s?,\s?(quiet))?/){
		my $key = $list->send_to_editor('smtp', $message);

		unless (defined $key) {
			Sympa::Log::Syslog::do_log('err','Calling to send_to_editor() function failed for user %s in list %s', $sender, $name);
			Sympa::Report::reject_report_msg('intern','The request moderation sending to moderator failed.',$sender,{'msg_id' => $msg_id,'message' => $message},$robot,$msg_string,$list);
			return undef
		}

		Sympa::Log::Syslog::do_log('info', 'Message with key %s for list %s from %s sent to editors', $name, $sender);

		unless ($2 eq 'quiet') {
			unless (Sympa::Report::notice_report_msg('moderating_message',$sender,{'message' => $message},$robot,$list)) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report', type 'success', entry 'moderating_message' to $sender");
			}
		}
		return 1;

	} elsif($action =~ /^reject(,(quiet))?/) {
		Sympa::Log::Syslog::do_log('notice', 'Message for %s from %s rejected, sender not allowed', $name, $sender);
		unless ($2 eq 'quiet') {
			if (defined $result->{'tt2'}) {
				my $expedition_result = $list->send_file(
					$result->{'tt2'},
					$sender,
					$robot,
					{}
				);
				unless ($expedition_result) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send template '$result->{'tt2'}' to $sender");
					Sympa::Report::reject_report_msg('auth',$result->{'reason'},$sender,{'message' => $message},$robot,$msg_string,$list);
				}
			} else {
				unless (Sympa::Report::reject_report_msg('auth',$result->{'reason'},$sender,{'message' => $message},$robot,$msg_string,$list)) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report', type 'auth' to $sender");
				}
			}
		}
		return undef;

	} elsif($action =~ /^do_it/) {

		$msg->head()->add('X-Validation-by', $sender);

		## Distribute the message
		my $apply_dkim_signature = 'off';
		$apply_dkim_signature = 'on' if Sympa::Tools::Data::is_in_array($list->{'admin'}{'dkim_signature_apply_on'},'any');
		$apply_dkim_signature = 'on' if Sympa::Tools::Data::is_in_array($list->{'admin'}{'dkim_signature_apply_on'},'md5_authenticated_messages');

		my $numsmtp = $list->distribute_msg(
			'message'              => $message,
			'apply_dkim_signature' => $apply_dkim_signature
		);

		unless (defined $numsmtp) {
			Sympa::Log::Syslog::do_log('err','Unable to send message to list %s', $list->{'name'});
			Sympa::Report::reject_report_msg('intern','',$sender,{'msg_id' => $msg_id,'message' => $message},$robot,$msg_string,$list);
			return undef;
		}

		unless ($quiet || ($action =~ /quiet/i )) {
			unless (Sympa::Report::notice_report_msg('message_confirmed',$sender,{'key' => $key,'message' => $message},$robot,$list)) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'message_report', entry 'message_distributed' to $sender");
			}
		}
		Sympa::Log::Syslog::do_log('info', 'CONFIRM %s from %s for list %s accepted (%d seconds)', $key, $sender, $list->{'name'}, time() - $time_command);

		$spool->remove({'authkey'=>$key});

		return 1;
	}
}

# _reject
# Refuse and delete  a moderated message and notify sender
# by sending template 'reject'
# Parameters:
# - $what (+): command parameter : listname and authentification key
# - $robot (+): robot
# Return value: 'unknown_list'|'wrong_auth'| 1 | undef

sub _reject {
	my ($what, $robot, undef, $editor_msg) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s)', $what, $robot);

	$what =~ /^(\S+)\s+(.+)\s*$/;
	my($which, $key) = ($1, $2);
	$which =~ y/A-Z/a-z/;
	## Load the list if not already done, and reject the
	## subscription if this list is unknown to us.
	my $list = Sympa::List->new(
		name   => $which,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);

	unless ($list) {
		Sympa::Log::Syslog::do_log('info', 'REJECT %s %s from %s refused, unknown list for robot %s', $which, $key, $sender,$robot);
		Sympa::Report::reject_report_msg('user','list_unknown',$sender,{'listname' => $which},$robot,'','');
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	my $name = "$list->{'name'}";

	my $modspool = Sympa::Spool->new(
		name   => 'mod',
		source => Sympa::Database::get_source()
	);
	my $message_in_spool = $modspool->get_message({'list'=>$list->{'name'},'robot'=>$robot,'authkey'=>$key});

	unless ($message_in_spool) {
		Sympa::Log::Syslog::do_log('info', 'REJECT %s %s from %s refused, auth failed', $which, $key, $sender);
		Sympa::Report::reject_report_msg('user','unfound_message',$sender,{'key'=> $key},$robot,'',$list);
		return 'wrong_auth';
	}
	my $message = Sympa::Message->new(
		string                => $message_in_spool->{messageasstring},
		messagekey            => $message_in_spool->{messagekey},
		spoolname             => $message_in_spool->{spoolname},
		create_list_if_needed => $message_in_spool->{create_list_if_needed}
	);
	unless ($message) {
		Sympa::Log::Syslog::do_log('err', 'Could not parse spool message %s %s from %s refused, auth failed', $which, $key, $sender);
		Sympa::Report::reject_report_msg('user','unfound_message',$sender,{'key'=> $key},$robot,'',$list);
		return 'wrong_auth';
	}
	my $msg = $message->{'msg'};

	my @sender_hdr = Mail::Address->parse($message->head()->get('From'));
	unless  ($#sender_hdr == -1) {
		my $rejected_sender = $sender_hdr[0]->address;
		my %context;
		$context{'subject'} = Sympa::Tools::decode_header($message, 'Subject');
		$context{'rejected_by'} = $sender;
		$context{'editor_msg_body'} = $editor_msg->{'msg'}->body_as_string() if ($editor_msg);

		Sympa::Log::Syslog::do_log('debug', 'message %s by %s rejected sender %s',$context{'subject'},$context{'rejected_by'},$rejected_sender);

		## Notify author of message
		unless ($quiet) {
			my $expedition_result = $list->send_file(
				'reject',
				$rejected_sender,
				$robot,
				\%context
			);
			unless ($expedition_result) {
				Sympa::Log::Syslog::do_log('notice',"Unable to send template 'reject' to $rejected_sender");
				Sympa::Report::reject_report_msg('intern_quiet','',$sender,{'listname'=> $list->{'name'},'message' => $msg},$robot,'',$list);
			}
		}

		## Notify list moderator
		unless (Sympa::Report::notice_report_msg('message_rejected', $sender, {'key' => $key,'message' => $msg}, $robot, $list)) {
			Sympa::Log::Syslog::do_log('err',"Unable to send template 'message_report', entry 'message_rejected' to $sender");
		}

	}

	Sympa::Log::Syslog::do_log('info', 'REJECT %s %s from %s accepted (%d seconds)', $name, $sender, $key, time() - $time_command);
	Sympa::Tools::File::remove_dir ( $Sympa::Configuration::Conf{'viewmail_dir'}.'/mod/'.$list->get_list_id().'/'.$key);

	$modspool->remove({'list'=>$list->{'name'},'robot'=>$robot,'authkey'=>$key});

	return 1;
}

#  _modindex
# Sends a list of current messages to moderate of a list
# (look into spool queuemod)
# Parameters:
# - $name (+): listname
# - $robot (+): robot
# Return value: 'unknown_list'|'not_allowed'|'no_file'|1

sub _modindex {
	my ($name, $robot) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s)',$name,$robot);

	$name =~ y/A-Z/a-z/;

	my $list = Sympa::List->new(
		name   => $name,
		robot  => $robot,
		source => Sympa::Database::get_source()
	);
	unless ($list) {
		Sympa::Report::reject_report_cmd('user','no_existing_list',{'listname' => $name},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'MODINDEX %s from %s refused, unknown list for robot %s', $name, $sender, $robot);
		return 'unknown_list';
	}

	Sympa::Language::set_lang($list->{'admin'}{'lang'});

	my $modqueue = Sympa::Configuration::get_robot_conf($robot,'queuemod');

	my $i;

	unless ($list->may_do('modindex', $sender)) {
		Sympa::Report::reject_report_cmd('auth','restricted_modindex',{},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'MODINDEX %s from %s refused, not allowed', $name,$sender);
		return 'not_allowed';
	}

	# purge the queuemod -> delete old files
	if (!opendir(DIR, $modqueue)) {
		Sympa::Log::Syslog::do_log('info', 'WARNING unable to read %s directory', $modqueue);
	}
	my @qfile = sort grep (!/^\.+$/,readdir(DIR));
	closedir(DIR);
	my ($curlist,$moddelay);
	foreach $i (sort @qfile) {

		next if (-d "$modqueue/$i");

		$i=~/\_(.+)$/;
		$curlist = Sympa::List->new(
			name   => $PREMATCH,
			robot  => $robot,
			source => Sympa::Database::get_source()
		);
		if ($curlist) {
			# list loaded
			if (exists $curlist->{'admin'}{'clean_delay_queuemod'}){
				$moddelay = $curlist->{'admin'}{'clean_delay_queuemod'}
			} else {
				$moddelay = Sympa::Configuration::get_robot_conf($robot,'clean_delay_queuemod');
			}

			if ((stat "$modqueue/$i")[9] < (time() -  $moddelay*86400) ){
				unlink ("$modqueue/$i");
				Sympa::Log::Syslog::do_log('notice', 'Deleting unmoderated message %s, too old', $i);
			};
		}
	}

	opendir(DIR, $modqueue);

	my $list_id = $list->get_list_id();
	my @files = ( sort grep (/^($name|$list_id)\_/,readdir(DIR)));
	closedir(DIR);
	my $n;
	my @now = localtime(time());

	## List of messages
	my @spool;

	foreach $i (@files) {
		## skip message already marked to be distributed using WWS
		next if ($i =~ /.distribute$/);

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
		Sympa::Report::notice_report_cmd('no_message_to_moderate',{'listname'=>$name},$cmd_line);
		Sympa::Log::Syslog::do_log('info', 'MODINDEX %s from %s refused, no message to moderate', $name, $sender);
		return 'no_file';
	}

	my $expedition_result = $list->send_file(
		'modindex',
		$sender,
		$robot,
		{
			'spool'     => \@spool,
			'total'     => $n,
			'boundary1' => "==main $now[6].$now[5].$now[4].$now[3]==",
			'boundary2' => "==digest $now[6].$now[5].$now[4].$now[3]=="
		}
	);
	unless ($expedition_result) {
		Sympa::Log::Syslog::do_log('notice',"Unable to send template 'modindex' to $sender");
		Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> $name},$cmd_line,$sender,$robot);
	}

	Sympa::Log::Syslog::do_log('info', 'MODINDEX %s from %s accepted (%d seconds)', $name,
		$sender, time() - $time_command);

	return 1;
}

# _which
# Return list of lists that sender is subscribed. If he is
# owner and/or editor, managed lists are also noticed.
# Parameters:
# - : ?
# - $robot (+): robot
# Return value : 1

sub _which {
	my (undef, $robot, $sign_mod, $message) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s,%s,%s)', '', $robot, $sign_mod, $message);

	my($listname, @which);

	## Subscriptions
	my $data;
	foreach my $list (Sympa::List::get_which ($sender,$robot,'member')){
		## wwsympa :  my $list = Sympa::List->new($l);
		##            next unless (defined $list);
		$listname = $list->{'name'};

		my $result = $list->check_list_authz('visibility', 'smtp',
			{'sender' => $sender,
				'message' => $message, });

		my $action;
		$action = $result->{'action'} if (ref($result) eq 'HASH');

		unless (defined $action) {
			my $error = "Unable to evaluate scenario 'visibility' for list $listname";
			Sympa::List::send_notify_to_listmaster(
				'intern_error',
				$robot,
				{
					'error'  => $error,
					'who'    => $sender,
					'cmd'    => $cmd_line,
					'list'   => $list,
					'action' => 'Command process'
				}
			);
			next;
		}



		next unless ($action =~ /do_it/);

		push @{$data->{'lists'}},$listname;
	}

	## Ownership
	if (@which = Sympa::List::get_which ($sender,$robot,'owner')){
		foreach my $list (@which){
			push @{$data->{'owner_lists'}},$list->{'name'};
		}
		$data->{'is_owner'} = 1;
	}

	## Editorship
	if (@which = Sympa::List::get_which ($sender,$robot,'editor')){
		foreach my $list (@which){
			push @{$data->{'editor_lists'}},$list->{'name'};
		}
		$data->{'is_editor'} = 1;
	}

	my $expedition_result = Sympa::List::send_global_file(
		'which',
		$sender,
		$robot,
		$data
	);
	unless ($expedition_result) {
		Sympa::Log::Syslog::do_log('notice',"Unable to send template 'which' to $sender");
		Sympa::Report::reject_report_cmd('intern_quiet','',{'listname'=> $listname},$cmd_line,$sender,$robot);
	}

	Sympa::Log::Syslog::do_log('info', 'WHICH from %s accepted (%d
		seconds)', $sender, time() - $time_command);

	return 1;
}

# _get_auth_method($cmd,$email,$error,$sign_mod,$list)
# Checks the authentification and return method
# used if authentification not failed
# Parameters:
# - $cmd (+): current command
# - $email (+): used to compute auth
# - $error (+):ref(HASH) with keys :
#   -type : for message_report.tt2 parsing
#   -data : ref(HASH) for message_report.tt2 parsing
#   -msg : for Sympa::Log::Syslog::do_log
# - $sign_mod (+): 'smime'| 'dkim' | -
# - $list : ref(List) | -
# Return value: 'smime'|'md5'|'dkim'|'smtp' if authentification OK, undef else
sub _get_auth_method {
	my ($cmd,$email,$error,$sign_mod,$list) = @_;
	Sympa::Log::Syslog::do_log('debug3',"()");

	my $auth_method;

	if ($sign_mod eq 'smime') {
		$auth_method ='smime';

	} elsif ($auth ne '') {
		Sympa::Log::Syslog::do_log('debug',"auth received from $sender : $auth");

		my $compute;
		if (ref($list) && $list->isa('Sympa::List')){
			$compute= $list->compute_auth($email,$cmd);
		} else {
			$compute= Sympa::List::compute_auth($email,$cmd);
		}
		if ($auth eq $compute) {
			$auth_method = 'md5';
		} else {
			Sympa::Log::Syslog::do_log('debug2', 'auth should be %s',$compute);
			if ($error->{'type'} eq 'auth_failed'){
				Sympa::Report::reject_report_cmd('intern',"The authentication process failed",$error->{'data'},$cmd_line,$sender);
			} else {
				Sympa::Report::reject_report_cmd('user',$error->{'type'},$error->{'data'},$cmd_line);
			}
			Sympa::Log::Syslog::do_log('info', '%s refused, auth failed',$error->{'msg'});
			return undef;
		}
	} else {
		$auth_method = 'smtp';
		$auth_method = 'dkim' if ($sign_mod eq 'dkim');
	}

	return $auth_method;
}

=back

=cut

1;
