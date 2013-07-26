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

=head1 NAME

Sympa::Tracking - Mail tracking functions

=head1 DESCRIPTION

This module provides mail tracking functions

=cut

package Sympa::Tracking;

use strict;

#use CGI; # no longer used
#use Email::Simple; # no longer used
use MIME::Base64;


use Sympa::Database;
use Sympa::Log::Syslog;

=head1 FUNCTIONS

=over

=item get_recipients_status($list, $msgid)

Get mail addresses and status of the recipients who have a different DSN
status than "delivered"

#
#     -$pk_mail (+): the identifiant of the stored mail
#
# OUT : @pk_notifs |undef

=cut

sub get_recipients_status {
	my ($list, $msgid) = @_;
	
	my $listname = $list->name;
	my $robot_id = $list->domain;
	
	Sympa::Log::Syslog::do_log('debug2', 'get_recipients_status(%s,%s,%s)', $msgid, $listname, $robot_id);

	my $base = Sympa::Database->get_singleton();

	# the message->head method return message-id including <blabla@dom> where mhonarc return blabla@dom that's why we test both of them
	my $handle = $base->get_query_handle(
		"SELECT "                                                     .
			"recipient_notification AS recipient, "               .
			"reception_option_notification AS reception_option, " .
			"status_notification AS status, "                     .
			"arrival_date_notification AS arrival_date, "         .
			"type_notification as type, "                         .
			"message_notification as notification_message "       .
		"FROM notification_table "                                    .
		"WHERE "                                                      .
			"list_notification=? AND "                            .
			"robot_notification=? AND "                           .
			"(" .
				"message_id_notification=? OR " .
				"CONCAT('<',message_id_notification,'>')=? OR ".
				"message_id_notification=?" .
			")",
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve tracking informations for message %s, list %s@%s', $msgid, $listname, $robot_id);
		return undef;
	}
	$handle->execute(
		$listname,
		$robot_id,
		$msgid,
		$msgid,
		'<'.$msgid.'>'
	);

	my @pk_notifs;
	while (my $pk_notif = $handle->fetchrow_hashref){
		if ($pk_notif->{'notification_message'}) {
			$pk_notif->{'notification_message'} = MIME::Base64::decode($pk_notif->{'notification_message'});
		} else {
			$pk_notif->{'notification_message'} = '';
		}
		push @pk_notifs, $pk_notif;
	}
	return \@pk_notifs;
}

=item db_init_notification_table(%parameters)

Initialyse notification table for each subscriber

# IN :
#   listname
#   robot,
#   msgid  : the messageid of the original message
#   rcpt : a tab ref of recipients
#   reception_option : teh reception option of thoses subscribers
    my $list = shift;
    my %params = @_;

Return value:

A positive value on success, I<undef> otherwise.

=cut

sub db_init_notification_table {
	my $list = shift;
	my (%params) = @_;

	my $msgid =  $params{'msgid'}; chomp $msgid;
	my $listname =  $list->name;
	my $robot_id =  $list->domain;
	my $reception_option =  $params{'reception_option'};
	my @rcpt =  @{$params{'rcpt'}};

	Sympa::Log::Syslog::do_log('debug2', "db_init_notification_table (msgid = %s, listname = %s, reception_option = %s",$msgid,$listname,$reception_option);

	my $time = time();

	my $base = Sympa::Database->get_singleton();
	my $handle = $base->get_query_handle(
		"INSERT INTO notification_table ("        .
			"message_id_notification, "       .
			"recipient_notification, "        .
			"reception_option_notification, " .
			"list_notification, "             .
			"robot_notification, "            .
			"date_notification"               .
		") VALUES (?, ?, ?, ?, ?, ?)"
	);
	unless($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement');
		return undef;
	}

	foreach my $email (@rcpt){
		my $rows = $handle->execute(
			$msgid,
			lc($email),
			$reception_option,
			$listname,
			$robot_id,
			$time
		);

		unless($rows) {
			Sympa::Log::Syslog::do_log('err','Unable to prepare notification table for user %s, message %s, list %s@%s', $email, $msgid, $listname, $robot_id);
			return undef;
		}
	}
	return 1;
}

=item db_insert_notification($notification_id, $type, $status, $arrival_date, $notification_as_string)

Add a notification entry corresponding to a new report. This function is
called when a report has been received.  It build a new connection with the
database using the default database parameter. Then it search the notification
entry identifiant which correspond to the received report. Finally it update
the recipient entry concerned by the report.

# IN :-$id (+): the identifiant entry of the initial mail
#     -$type (+): the notification entry type (DSN|MDN)
#     -$recipient (+): the list subscriber who correspond to this entry
#     -$msg_id (+): the report message-id
#     -$status (+): the new state of the recipient entry depending of the report data
#     -$arrival_date (+): the mail arrival date.
#     -$notification_as_string : the DSN or the MDM as string

Return value:

A positive value on success, I<undef> otherwise.

=cut

sub db_insert_notification {
	my ($notification_id, $type, $status, $arrival_date ,$notification_as_string  ) = @_;
	Sympa::Log::Syslog::do_log('debug2', "db_insert_notification  :notification_id : %s, type : %s, recipient : %s, msgid : %s, status :%s",$notification_id, $type, $status);

	chomp $arrival_date;

	$notification_as_string = MIME::Base64::encode($notification_as_string);

	my $base = Sympa::Database->get_singleton();
	my $rows = $base->execute_query(
		"UPDATE notification_table "            .
		"SET "                                  .
			"status_notification=?, "       .
			"arrival_date_notification=?, " .
			"message_notification=?"        .
		"WHERE pk_notification=?",
		$status,
		$arrival_date,
		$notification_as_string,
		$notification_id
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to update notification %s in database', $notification_id);
		return undef;
	}

	return 1;
}

=item find_notification_id_by_message($recipient, $msgid, $listname, $robot)

Return the tracking_id find by recipeint,message-id,listname and robot

=cut

sub find_notification_id_by_message{
	my ($recipient, $msgid, $listname, $robot) = @_;
	chomp $msgid;
	Sympa::Log::Syslog::do_log('debug2','find_notification_id_by_message(%s,%s,%s,%s)',$recipient,$msgid ,$listname,$robot );

	my $base = Sympa::Database->get_singleton();

	# the message->head method return message-id including <blabla@dom> where mhonarc return blabla@dom that's why we test both of them
	my $handle = $base->get_query_handle(
		"SELECT pk_notification "                                      .
		"FROM notification_table "                                     .
		"WHERE "                                                       .
			"recipient_notification=? AND "                        .
			"list_notification=? AND "                             .
			"robot_notification=? AND "                            .
			"("                                                    .
				"message_id_notification=? OR "                .
				"CONCAT('<',message_id_notification,'>')=? OR ".
				"message_id_notification=?"                    .
			")"
		);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve the tracking informations for user %s, message %s, list %s@%s', $recipient, $msgid, $listname, $robot);
		return undef;
	}
	$handle->execute(
		$recipient,
		$listname,
		$robot,
		$msgid,
		$msgid,
		'<'.$msgid.'>'
	);

	my @pk_notifications = $handle->fetchrow_array;
	if ($#pk_notifications > 0){
		Sympa::Log::Syslog::do_log('err','Found more then one pk_notification maching  (recipient=%s,msgis=%s,listname=%s,robot%s)',$recipient,$msgid ,$listname,$robot );
		# we should return undef...
	}
	return @pk_notifications[0];
}

=item remove_message_by_id($msgid, $listname, $robot)

Remove notifications.

# IN : $msgid : id of related message
#    : $listname
#    : $robot

Return value:

A positive value on success, I<undef> otherwise.

=cut

sub remove_message_by_id{
	my ($list, $msgid) = @_;
	
	my $listname = $list->name;
	my $robot_id = $list->domain;
	
	Sympa::Log::Syslog::do_log('debug2', 'Remove message id =  %s, listname = %s, robot = %s', $msgid,$listname,$robot_id);

	my $base = Sympa::Database->get_singleton();
	my $rows = $base->execute_query(
		"DELETE FROM notification_table "        .
		"WHERE "                                 .
			"message_id_notification=? AND " .
			"list_notification=? AND "       .
			"robot_notification=?",
		$msgid,
		$listname,
		$robot_id
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to remove the tracking informations for message %s, list %s@%s', $msgid, $listname, $robot_id);
		return undef;
	}

	return 1;
}

=item remove_message_by_period($period, $listname, $robot)

Remove notifications older than number of days.
# IN : $list : ref(List)
#    : $period

Return value:

The number of removed messages on success, I<undef> otherwise.

=cut

sub remove_message_by_period{
	my ($list, $period) = @_;
	
	my $listname = $list->name;
	my $robot_id = $list->domain;
	
	Sympa::Log::Syslog::do_log('debug2', 'Remove message by period=  %s, listname = %s, robot = %s', $period,$listname,$robot_id);

	my $base = Sympa::Database->get_singleton();

	my $limit = time - ($period * 24 * 60 * 60);
	my $rows = $base->execute_query(
		"DELETE FROM notification_table "  .
		"WHERE "                           .
			"date_notification<? AND " .
			"list_notification=? AND " .
			"robot_notification=?",
		$limit,
		$listname,
		$robot_id
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to remove the tracking informations older than %s days for list %s@%s', $limit, $listname, $robot_id);
		return undef;
	}

	return 1;
}

=back

=cut

1;
