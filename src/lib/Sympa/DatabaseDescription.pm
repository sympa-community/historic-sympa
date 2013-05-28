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

Sympa::DatabaseDescription

=head1 DESCRIPTION

=cut

package Sympa::DatabaseDescription;

use strict;

my %base_structure = (
	'subscriber_table' => {
		'fields' => {
			'user_subscriber' => {
				'type'     => 'varchar(100)',
				'doc'      => 'email of subscriber',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 1
			},
			'list_subscriber' => {
				'type'     => 'varchar(50)',
				'doc'      => 'list name of a subscription',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 2
			},
			'robot_subscriber' => {
				'type'     => 'varchar(80)',
				'doc'      => 'robot (domain) of the list',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 3
			},
			'reception_subscriber' => {
				'type'   => 'varchar(20)',
				'doc'    => 'reception format option of subscriber (digest, summary, etc.)',
				'order'  => 4,
			},
			'suspend_subscriber' => {
				'type'   => 'int(1)',
				'doc'    => 'boolean set to 1 if subscription is suspended',
				'order'  => 5,
			},
			'suspend_start_date_subscriber' => {
				'type'   => 'int(11)',
				'doc'    => 'The date (epoch) when message reception is suspended',
				'order'  => 6,
			},
			'suspend_end_date_subscriber' => {
				'type'   => 'int(11)',
				'doc'    => 'The date (epoch) when message reception should be restored',
				'order'  => 7,
			},
			'bounce_subscriber' => {
				'type'   => 'varchar(35)',
				'order'  => 8,
			},
			'bounce_score_subscriber' => {
				'type'   => 'smallint(6)',
				'order'  => 9,
			},
			'bounce_address_subscriber' => {
				'type'   => 'varchar(100)',
				'order'  => 10,
			},
			'date_subscriber' => {
				'type'     => 'datetime',
				'doc'      => 'date of subscription',
				'not_null' => 1,
				'order'    => 11,
			},
			'update_subscriber' => {
				'type'   => 'datetime',
				'doc'    => 'the latest date where subscription is confirmed by subscriber',
				'order'  => 12,
			},
			'comment_subscriber' => {
				'type'   => 'varchar(150)',
				'doc'    => 'Free form name',
				'order'  => 13,
			},
			'number_messages_subscriber' => {
				'type'     => 'int(5)',
				'doc'      => 'the number of message the subscriber sent',
				'not_null' => 1,
				'order'    => 5,
				'order'    => 14,
			},
			'visibility_subscriber' => {
				'type'   => 'varchar(20)',
				'order'  => 15,
			},
			'topics_subscriber' => {
				'type'   => 'varchar(200)',
				'doc'    => 'topic subscription specification',
				'order'  => 16,
			},
			'subscribed_subscriber' => {
				'type'   => 'int(1)',
				'doc'    => 'boolean set to 1 if subscriber comes from ADD or SUB',
				'order'  => 17,
			},
			'included_subscriber' => {
				'type'   => 'int(1)',
				'doc'    => 'boolean, set to 1 is subscriber comes from an external datasource. Note that included_subscriber and subscribed_subscriber can both value 1',
				'order'  => 18,
			},
			'include_sources_subscriber' => {
				'type'   => 'varchar(50)',
				'doc'    => 'comma seperated list of datasource that contain this subscriber',
				'order'  => 19,
			},
			'custom_attribute_subscriber' => {
				'type'   => 'text',
				'order'  => 10,
			},

		},
		'doc'   => 'This table store subscription, subscription option etc.',
		'order' => 1,
	},
	'user_table'=> {
		'fields' => {
			'email_user' => {
				'type'     => 'varchar(100)' ,
				'doc'      => 'email user is the key',
				'primary'  => 1,
				'not_null' => 1,
			},
			'gecos_user' => {
				'type'   => 'varchar(150)',
				'order'  => 3,
			},
			'password_user' => {
				'type'   => 'varchar(40)',
				'doc'    => 'password are stored as fringer print',
				'order'  => 2,
			},
			'last_login_date_user' => {
				'type'   => 'int(11)',
				'doc'    => 'date epoch from last login, printed in login result for security purpose',
				'order'  => 4,
			},
			'last_login_host_user' => {
				'type'   => 'varchar(60)',
				'doc'    => 'host of last login, printed in login result for security purpose',
				'order'  => 5,
			},
			'wrong_login_count_user' =>{
				'type'   => 'int(11)',
				'doc'    => 'login attempt count, used to prevent brut force attack',
				'order'  => 6,
			},
			'cookie_delay_user' => {
				'type'   => 'int(11)',
			},
			'lang_user' => {
				'type'   => 'varchar(10)',
				'doc'    => 'user langage preference',
			},
			'attributes_user' => {
				'type'   => 'text',
			},
			'data_user' => {
				'type'   => 'text',
			},
		},
		'doc'   => 'The user_table is mainly used to manage login from web interface. A subscriber may not appear in the user_table if he never log through the web interface.',
		'order' => 2,
	},
	'spool_table' => {
		'fields' => {
			'messagekey_spool' => {
				'type'          => 'bigint(20)',
				'doc'           => 'primary key',
				'primary'       => 1,
				'not_null'      => 1,
				'autoincrement' => 1,
				'order'         => 1,
			},
			'spoolname_spool'=> {
				'type'     => "enum('msg','auth','mod','digest','archive','bounce','subscribe','topic','bulk','validated','task')",
				'doc'      => 'the spool name',
				'not_null' => 1,
				'order'    => 2,
			},
			'list_spool'=> {
				'type'   => 'varchar(50)',
				'order'  => 3,
			},
			'robot_spool' =>{
				'type'   => 'varchar(80)',
				'order'  => 4,
			},
			'priority_spool'=> {
				'type'   => 'varchar(2)',
				'doc'    => 'priority (list priority, owner pririty etc)',
				'order'  => 5,
			},
			'date_spool'=> {
				'type'   => 'int(11)',
				'doc'    => 'the date a message is copied in spool table',
				'order'  => 6,
			},
			'message_spool' => {
				'type'   => 'longtext',
				'doc'    => 'message as string b64 encoded',
				'order'  => 7,
			},
			'messagelock_spool' => {
				'type'   => 'varchar(90)',
				'doc'    => 'a unique string for each process : $$EVAL_ERRORhostname',
				'order'  => 8,
			},
			'lockdate_spool' => {
				'type'   => 'int(11)',
				'doc'    => 'the date a lock is set. Used in order detect old locks',
				'order'  => 9,
			},
			'message_status_spool' => {
				'type'   => "enum('ok','bad')",
				'doc'    => 'if problem when processed entries have bad status',
				'order'  => 10,
			},
			'message_diag_spool' =>{
				'type'   => 'text',
				'doc'    => 'the reason why a message is moved to bad',
				'order'  => 11,
			},
			'type_spool'=> {
				'type'   => 'varchar(15)',
				'doc'    => 'list, list-request,, sympa robot or other rcp ',
				'order'  => 12,
			},
			'authkey_spool' => {
				'type'   => 'varchar(33)',
				'doc'    => ' authentication key for email chalenge',
				'order'  => 13,
			},
			'headerdate_spool' => {
				'type'   => 'varchar(80)',
				'doc'    => 'the message header date',
				'order'  => 14,
			},
			'create_list_if_needed_spool'=> {
				'type'   => 'int(1)',
				'doc'    => 'set to 1 if message is related to a dynamic list, set to 0 if list as been created or if list is static',
				'order'  => 15,
			},
			'subject_spool'=>{
				'type'   => 'varchar(110)',
				'doc'    => 'subject of the message stored to list spool content faster',
				'order'  => 16,
			},
			'sender_spool'=>{
				'type'   => 'varchar(110)',
				'doc'    => 'this info is stored to browse spool content faster',
				'order'  => 17,
			},
			'messageid_spool' => {
				'type'   => 'varchar(300)',
				'doc'    => 'stored to list spool content faster',
				'order'  => 18,
			},
			'spam_status_spool' => {
				'type'   => 'varchar(12)',
				'doc'    => 'spamstatus scenario result',
				'order'  => 19,
			},
			'size_spool' => {
				'type'   => 'int(11)',
				'doc'    => 'info stored in order to browse spool content faster',
				'order'  => 20,
			},
			'task_date_spool' => {
				'type'   => 'int(11)',
				'doc'    => 'date for a task',
				'order'  => 21,
			},
			'task_label_spool' => {
				'type'   => 'varchar(20)',
				'doc'    => 'label for a task',
				'order'  => 22,
			},
			'task_model_spool' => {
				'type'   => 'varchar(40)',
				'doc'    => 'model of related task',
				'order'  => 23,
			},
			'task_object_spool' => {
				'type'   => 'varchar(50)',
				'doc'    => 'object of related task',
				'order'  => 24,
			},
			'dkim_privatekey_spool' => {
				'type'   => 'varchar(1000)',
				'doc'    => 'DKIM parameter stored for bulk daemon because bulk ignore list parameters, private key to sign message',
				'order'  => 35,
			},
			'dkim_selector_spool' => {
				'type'   => 'varchar(50)',
				'doc'    => 'DKIM parameter stored for bulk daemon because bulk ignore list parameters, DKIM selector to sign message',
				'order'  => 36,
			},
			'dkim_d_spool' => {
				'type'   => 'varchar(50)',
				'doc'    => 'DKIM parameter stored for bulk daemon because bulk ignore list parameters, the d DKIM parameter',
				'order'  => 37,
			},
			'dkim_i_spool' => {
				'type'   => 'varchar(100)',
				'doc'    => 'DKIM parameter stored for bulk daemon because bulk ignore list parameters, DKIM i signature parameter',
				'order'  => 38,
			},
		},
		'doc'   => 'This table is created in version 6.2. It replace most of spools on file system for clustering purpose',
		'order' => 3,
	},
	'bulkmailer_table' => {
		'fields' => {
			'messagekey_bulkmailer' => {
				'type'     => 'varchar(80)',
				'doc'      => 'A pointer to a message in spool_table.It must be a value of a line in table spool_table with same value as messagekey_spool',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 1,
			},
			'packetid_bulkmailer' => {
				'type'     => 'varchar(33)',
				'doc'      => 'An id for the packet',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 2,
			},
			'messageid_bulkmailer' => {
				'type'   => 'varchar(200)',
				'doc'    => 'The message Id',
				'order'  => 3,
			},
			'receipients_bulkmailer' => {
				'type'   => 'text',
				'doc'    => 'the comma separated list of receipient email for this message',
				'order'  => 4,
			},
			'returnpath_bulkmailer' => {
				'type'   => 'varchar(100)',
				'doc'    => 'the return path value that must be set when sending the message',
				'order'  => 5,
			},
			'robot_bulkmailer' => {
				'type'   => 'varchar(80)',
				'order'  => 6,
			},
			'listname_bulkmailer' => {
				'type'   => 'varchar(50)',
				'order'  => 7,
			},
			'verp_bulkmailer' => {
				'type'   => 'int(1)',
				'doc'    => 'A boolean to specify if VERP is requiered, in this cas return_path will be formated using verp form',
				'order'  => 8,
			},
			'tracking_bulkmailer' => {
				'type'  => "enum('mdn','dsn')",
				'doc'   => 'Is DSN or MDM requiered when sending this message?',
				'order' => 9,
			},
			'merge_bulkmailer' => {
				'type'  => 'int(1)',
				'doc'   => 'Boolean, if true, the message is to be parsed as a TT2 template foreach receipient',
				'order' => 10,
			},
			'priority_message_bulkmailer' => {
				'type'  => 'smallint(10)',
				'order' => 11,
			},
			'priority_packet_bulkmailer' => {
				'type'  => 'smallint(10)',
				'order' => 12,
			},
			'reception_date_bulkmailer' => {
				'type'   => 'int(11)',
				'doc'    => 'The date where the message was received',
				'order'  => 13,
			},
			'delivery_date_bulkmailer' => {
				'type'   => 'int(11)',
				'doc'    => 'The date the message was sent',
				'order'  => 14,
			},
			'lock_bulkmailer' => {
				'type'   => 'varchar(30)',
				'doc'    => 'A lock. It is set as process-number @ hostname so multiple bulkmailer can handle this spool',
				'order'  => 15,
			},
		},
		'doc'   => 'storage of receipients with a ref to a message in spool_table. So a very simple process can distribute them',
		'order' => 4,
	},
	'exclusion_table' => {
		'fields' => {
			'list_exclusion' => {
				'type'     => 'varchar(50)',
				'order'    => 1,
				'primary'  => 1,
				'not_null' => 1,
			},
			'robot_exclusion' => {
				'type'     => 'varchar(50)',
				'order'    => 2,
				'primary'  => 1,
				'not_null' => 1,
			},
			'user_exclusion' => {
				'type'     => 'varchar(100)',
				'order'    => 3,
				'primary'  => 1,
				'not_null' => 1,
			},
			'family_exclusion' => {
				'type'  => 'varchar(50)',
				'order' => 4,
			},
			'date_exclusion' => {
				'type'  => 'int(11)',
				'order' => 5,
			},
		},
		'doc'   => 'exclusion table is used in order to manage unsubscription for subsceriber inclued from an external data source',
		'order' => 5,
	},
	'session_table' => {
		'fields' => {
			'id_session' => {
				'type'     => 'varchar(30)',
				'doc'      => 'the identifier of the database record',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 1,
			},
			'start_date_session' => {
				'type'     => 'int(11)',
				'doc'      => 'the date when the session was created',
				'not_null' => 1,
				'order'    => 2,
			},
			'date_session' => {
				'type'     => 'int(11)',
				'doc'      => 'date epoch of the last use of this session. It is used in order to expire old sessions',
				'not_null' => 1,
				'order'    => 3,
			},
			'remote_addr_session' => {
				'type'  => 'varchar(60)',
				'doc'   => 'The IP address of the computer from which the session was created',
				'order' => 4,
			},
			'robot_session'  => {
				'type'  => 'varchar(80)',
				'doc'   => 'The virtual host in which the session was created',
				'order' => 5,
			},
			'email_session'  => {
				'type'  => 'varchar(100)',
				'doc'   => 'the email associated to this session',
				'order' => 6,
			},
			'hit_session' => {
				'type'  => 'int(11)',
				'doc'   => 'the number of hit performed during this session. Used to detect crawlers',
				'order' => 7,
			},
			'data_session'  => {
				'type'  => 'text',
				'doc'   => 'parameters attached to this session that don\'t have a dedicated column in the database',
				'order' => 8,
			},
		},
		'doc'   => 'managment of http session',
		'order' => 6,
	},
	'one_time_ticket_table' => {
		'fields' => {
			'ticket_one_time_ticket' => {
				'type'    => 'varchar(30)',
				'primary' => 1,
			},
			'email_one_time_ticket' => {
				'type' => 'varchar(100)',
			},
			'robot_one_time_ticket' => {
				'type' => 'varchar(80)',
			},
			'date_one_time_ticket' => {
				'type' => 'int(11)',
			},
			'data_one_time_ticket' => {
				'type' => 'varchar(200)',
			},
			'remote_addr_one_time_ticket' => {
				'type' => 'varchar(60)',
			},
			'status_one_time_ticket' => {
				'type' => 'varchar(60)',
			},
		},
		'doc'   => 'One time ticket are random value use for authentication chalenge. A ticket is associated with a context which look like a session',
		'order' => 7,
	},
	'notification_table' => {
		'fields' => {
			'pk_notification' => {
				'type'          => 'bigint(20)',
				'doc'           => 'Autoincrement key',
				'autoincrement' => 1,
				'primary'       => 1,
				'not_null'      => 1,
				'order'         => 1,
			},
			'message_id_notification' => {
				'type'  => 'varchar(100)',
				'doc'   => 'initial message-id. This feild is used to search DSN and MDN related to a particular message',
				'order' => 2,
			},
			'recipient_notification' => {
				'type'  => 'varchar(100)',
				'doc'   => 'email adresse of receipient for which a DSN or MDM was received',
				'order' => 3,
			},
			'reception_option_notification' => {
				'type'  => 'varchar(20)',
				'doc'   => 'The subscription option of the subscriber when the related message was sent to the list. Ussefull because some receipient may have option such as //digest// or //nomail//',
				'order' => 4,
			},
			'status_notification' => {
				'type'  => 'varchar(100)',
				'doc'   => 'Value of notification',
				'order' => 5,
			},
			'arrival_date_notification' => {
				'type'  => 'varchar(80)',
				'doc'   => 'reception date of latest DSN or MDM',
				'order' => 6,
			},
			'type_notification' => {
				'type'  => "enum('DSN', 'MDN')",
				'doc'   => 'Type of the notification (DSN or MDM)',
				'order' => 7,
			},
			'message_notification' => {
				'type'  => 'longtext',
				'doc'   => 'The DSN or the MDN itself',
				'order' => 8,
			},
			'list_notification' => {
				'type'  => 'varchar(50)',
				'doc'   => 'The listname the messaage was issued for',
				'order' => 9,
			},
			'robot_notification' => {
				'type'  => 'varchar(80)',
				'doc'   => 'The robot the message is related to',
				'order' => 10,
			},
			'date_notification' => {
				'type'     => 'int(11)',
				'not_null' => 1
			},
		},
		'doc'   => 'used for message tracking feature. If the list is configured for tracking, outgoing messages include a delivery status notification request and optionnaly a return receipt request.When DSN MDN are received by Syamp, they are store in this table in relation with the related list and message_id',
		'order' => 8,
	},
	'logs_table' => {
		'fields' => {
			'id_logs' => {
				'type'     => 'bigint(20)',
				'doc'      => 'Unique log\'s identifier',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 1,
			},
			'user_email_logs' => {
				'type'  => 'varchar(100)',
				'doc'   => 'e-mail address of the message sender or email of identified web interface user (or soap user)',
				'order' => 2,
			},
			'date_logs' => {
				'type'     => 'int(11)',
				'doc'      => 'date when the action was executed',
				'not_null' => 1,
				'order'    => 3,
			},
			'robot_logs' => {
				'type'  => 'varchar(80)',
				'doc'   => 'name of the robot in which context the action was executed',
				'order' => 4,
			},
			'list_logs' => {
				'type'  => 'varchar(50)',
				'doc'   => 'name of the mailing-list in which context the action was executed',
				'order' => 5,
			},
			'action_logs' => {
				'type'     => 'varchar(50)',
				'doc'      => 'name of the Sympa subroutine which initiated the log',
				'not_null' => 1,
				'order'    => 6,
			},
			'parameters_logs' => {
				'type'   => 'varchar(100)',
				'doc'    => 'List of commas-separated parameters. The amount and type of parameters can differ from an action to another',
				'order'  => 7,
			},
			'target_email_logs' => {
				'type'  => 'varchar(100)',
				'doc'   => 'e-mail address (if any) targeted by the message',
				'order' => 8,
			},
			'msg_id_logs' => {
				'type'  => 'varchar(255)',
				'doc'   => 'identifier of the message which triggered the action',
				'order' => 9,
			},
			'status_logs' => {
				'type'     => 'varchar(10)',
				'doc'      => 'exit status of the action. If it was an error, it is likely that the error_type_logs field will contain a description of this error',
				'not_null' => 1,
				'order'    => 10,
			},
			'error_type_logs' => {
				'type'  => 'varchar(150)',
				'doc'   => 'name of the error string – if any – issued by the subroutine',
				'order' => 11,
			},
			'client_logs' => {
				'type'  => 'varchar(100)',
				'doc'   => 'IP address of the client machine from which the message was sent',
				'order' => 12,
			},
			'daemon_logs' => {
				'type'     => 'varchar(10)',
				'doc'      => 'name of the Sympa daemon which ran the action',
				'not_null' => 1,
				'order'    => 13,
			},
		},
		'doc'   => 'Each important event is stored in this table. List owners and listmaster can search entries in this table using web interface.',
		'order' => 9,
	},
	'stat_table' => {
		'fields' => {
			'id_stat' => {
				'type'     => 'bigint(20)',
				'order'    => 1,
				'primary'  => 1,
				'not_null' => 1,
			},
			'date_stat' => {
				'type'     => 'int(11)',
				'order'    => 2,
				'not_null' => 1,
			},
			'email_stat' => {
				'type'  => 'varchar(100)',
				'order' => 3,
			},
			'operation_stat' => {
				'type'     => 'varchar(50)',
				'order'    => 4,
				'not_null' => 1,
			},
			'list_stat' => {
				'type'  => 'varchar(150)',
				'order' => 5,
			},
			'daemon_stat' => {
				'type'  => 'varchar(10)',
				'order' => 6,
			},
			'user_ip_stat' => {
				'type'  => 'varchar(100)',
				'order' => 7,
			},
			'robot_stat' => {
				'type'     => 'varchar(80)',
				'order'    => 8,
				'not_null' => 1,
			},
			'parameter_stat' => {
				'type'  => 'varchar(50)',
				'order' => 9,
			},
			'read_stat' => {
				'type'     => 'tinyint(1)',
				'order'    => 10,
				'not_null' => 1,
			},
		},
		'doc'   => 'Statistic item are store in this table, Sum average etc are stored in Stat_counter_table',
		'order' => 10,
	},
	'stat_counter_table' => {
		'fields' => {
			'id_counter' => {
				'type'     => 'bigint(20)',
				'order'    => 1,
				'primary'  => 1,
				'not_null' => 1,
			},
			'beginning_date_counter' => {
				'type'     => 'int(11)',
				'order'    => 2,
				'not_null' => 1,
			},
			'end_date_counter' => {
				'type'  => 'int(11)',
				'order' => 1,
			},
			'data_counter' => {
				'type'     => 'varchar(50)',
				'not_null' => 1,
				'order'    => 3,
			},
			'robot_counter' => {
				'type'     => 'varchar(80)',
				'not_null' => 1,
				'order'    => 4,
			},
			'list_counter' => {
				'type'  => 'varchar(150)',
				'order' => 5,
			},
			'variation_counter' => {
				'type'  => 'int',
				'order' => 6,
			},
			'total_counter' => {
				'type'  => 'int',
				'order' => 7,
			},
		},
		'doc'   => 'Use in conjunction with stat_table for users statistics',
		'order' => 11,
	},

	'admin_table' => {
		'fields' => {
			'user_admin' => {
				'type'     => 'varchar(100)',
				'primary'  => 1,
				'not_null' => 1,
				'doc'      => 'List admin email',
				'order'    => 1,
			},
			'list_admin' => {
				'type'     => 'varchar(50)',
				'primary'  => 1,
				'not_null' => 1,
				'doc'      => 'Listname',
				'order'    => 2,
			},
			'robot_admin' => {
				'type'     => 'varchar(80)',
				'primary'  => 1,
				'not_null' => 1,
				'doc'      => 'List domain',
				'order'    => 3,
			},
			'role_admin' => {
				'type'    => "enum('listmaster','owner','editor')",
				'primary' => 1,
				'doc'     => 'A role of this user for this list (editor, owner or listmaster which a kind of list owner too)',
				'order'   => 4,
			},
			'profile_admin' => {
				'type'   => "enum('privileged','normal')",
				'doc'    => 'privilege level for this owner, value //normal// or //privileged//. The related privilege are listed in editlist.conf. ',
				'order'  => 5,
			},
			'date_admin' => {
				'type'     => 'datetime',
				'doc'      => 'date this user become a list admin',
				'not_null' => 1,
				'order'    => 6,
			},
			'update_admin' => {
				'type'  => 'datetime',
				'doc'   => 'last update timestamp',
				'order' => 7,
			},
			'reception_admin' => {
				'type'  => 'varchar(20)',
				'doc'   => 'email reception option for list managment messages',
				'order' => 8,
			},
			'visibility_admin' => {
				'type'  => 'varchar(20)',
				'doc'   => 'admin user email can be hidden in the list web page description',
				'order' => 9,
			},
			'comment_admin' => {
				'type'  => 'varchar(150)',
				'order' => 10,
			},
			'subscribed_admin' => {
				'type'  => 'int(1)',
				'doc'   => 'Set to 1 if user is list admin by definition in list config file',
				'order' => 11,
			},
			'included_admin' => {
				'type'  => 'int(1)',
				'doc'   => 'Set to 1 if user is admin by an external data source',
				'order'  => 12,
			},
			'include_sources_admin' => {
				'type'  => 'varchar(50)',
				'doc'   => 'name of external datasource',
				'order' => 13,
			},
			'info_admin' => {
				'type'  => 'varchar(150)',
				'doc'   => 'private information usually dedicated to listmasters who needs some additional information about list owners',
				'order' => 14,
			},

		},
		'doc'   => 'This table is a internal cash where list admin roles are stored. It is just a cash and and it does not need to saved. You may remove its content if needed. It will just make next Sympa start slower.',
		'order' => 12,
	},
	'netidmap_table' => {
		'fields' => {
			'netid_netidmap' => {
				'type'     => 'varchar(100)',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 1,
			},
			'serviceid_netidmap' => {
				'type'     => 'varchar(100)',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 2,
			},
			'email_netidmap' => {
				'type'  => 'varchar(100)',
				'order' => 4,
			},
			'robot_netidmap' => {
				'type'     => 'varchar(80)',
				'primary'  => 1,
				'not_null' => 1,
				'order'    => 3,
			},
		},
		'order' => 13,
	},
	'conf_table' => {
		'fields' => {
			'robot_conf' => {
				'type'    => 'varchar(80)',
				'primary' => 1,
				'order'   => 1,
			},
			'label_conf' => {
				'type'    => 'varchar(80)',
				'primary' => 1,
				'order'   => 2,
			},
			'value_conf' => {
				'type'  => 'varchar(300)',
				'doc'   => 'the value of parameter //label_conf// of robot //robot_conf//.',
				'order' => 3,
			},
		},
		'order' => 14,
	},
	'oauthconsumer_sessions_table' => {
		'fields' => {
			'user_oauthconsumer' => {
				'type'     => 'varchar(100)',
				'order'    => 1,
				'primary'  => 1,
				'not_null' => 1,
			},
			'provider_oauthconsumer' => {
				'type'     => 'varchar(100)',
				'order'    => 2,
				'primary'  => 1,
				'not_null' => 1,
			},
			'tmp_token_oauthconsumer' => {
				'type'  => 'varchar(100)',
				'order' => 3,
			},
			'tmp_secret_oauthconsumer' => {
				'type'  => 'varchar(100)',
				'order' => 4,
			},
			'access_token_oauthconsumer' => {
				'type'  => 'varchar(100)',
				'order' => 5,
			},
			'access_secret_oauthconsumer' => {
				'type'  => 'varchar(100)',
				'order' => 6,
			},
		},
		'order' => 15,
	},
	'oauthprovider_sessions_table' => {
		'fields' => {
			'id_oauthprovider' => {
				'type'          => 'bigint(20)',
				'doc'           => 'Autoincremental key',
				'order'         => 1,
				'primary'       => 1,
				'not_null'      => 1,
				'autoincrement' => 1,
			},
			'token_oauthprovider' => {
				'type'     => 'varchar(32)',
				'order'    => 2,
				'not_null' => 1,
			},
			'secret_oauthprovider' => {
				'type'     => 'varchar(32)',
				'order'    => 3,
				'not_null' => 1,
			},
			'isaccess_oauthprovider' => {
				'type'  => 'tinyint(1)',
				'order' => 4,
			},
			'accessgranted_oauthprovider' => {
				'type'  => 'tinyint(1)',
				'order' => 5,
			},
			'consumer_oauthprovider' => {
				'type'     => 'varchar(100)',
				'order'    => 6,
				'not_null' => 1,
			},
			'user_oauthprovider' => {
				'type'  => 'varchar(100)',
				'order' => 7,
			},
			'firsttime_oauthprovider' => {
				'type'     => 'int(11)',
				'order'    => 8,
				'not_null' => 1,
			},
			'lasttime_oauthprovider' => {
				'type'     => 'int(11)',
				'order'    => 9,
				'not_null' => 1,
			},
			'verifier_oauthprovider' => {
				'type'  => 'varchar(32)',
				'order' => 10,
			},
			'callback_oauthprovider' => {
				'type'  => 'varchar(100)',
				'order' => 11,
			},
		},
		'order' => 16,
	},
	'oauthprovider_nonces_table' => {
		'fields' => {
			'id_nonce' => {
				'type'          => 'bigint(20)',
				'doc'           => 'Autoincremental key',
				'order'         => 1,
				'primary'       => 1,
				'not_null'      => 1,
				'autoincrement' => 1,
			},
			'id_oauthprovider' => {
				'type'  => 'int(11)',
				'order' => 2,
			},
			'nonce_oauthprovider' => {
				'type'     => 'varchar(100)',
				'order'    => 3,
				'not_null' => 1,
			},
			'time_oauthprovider' => {
				'type'  => 'int(11)',
				'order' => 4,
			},
		},
		'order' => 17,
	},
	'list_table' => {
		'fields' => {
			'name_list'=> => {
				'type'     => 'varchar(100)',
				'order'    => 1,
				'primary'  => 1,
				'not_null' => 1,
			},
			'robot_list' => {
				'type'     => 'varchar(100)',
				'order'    => 2,
				'primary'  => 1,
				'not_null' => 1,
			},
			'path_list' => {
				'type'  => 'varchar(100)',
				'order' => 3,
			},
			'status_list' => {
				'type'  => "enum('open','closed','pending','error_config','family_closed')",
				'order' => 4,
			},
			'creation_email_list' => {
				'type'  => 'varchar(100)',
				'order' => 5,
			},
			'creation_epoch_list' => {
				'type'  => 'datetime',
				'order' => 6,
			},
			'subject_list' => {
				'type'  => 'varchar(100)',
				'order' => 7,
			},
			'web_archive_list' => {
				'type'  => 'tinyint(1)',
				'order' => 8,
			},
			'topics_list' => {
				'type'  => 'varchar(100)',
				'order' => 9,
			},
			'editors_list' => {
				'type'  => 'varchar(100)',
				'order' => 10,
			},
			'owners_list' => {
				'type'  => 'varchar(100)',
				'order' => 11,
			},
		},
		'order' => 18,
	},
);

## List the required INDEXES
##   1st key is the concerned table
##   2nd key is the index name
##   the table lists the field on which the index applies
our %indexes = (
	'admin_table'      => {'admin_user_index'      => ['user_admin']},
	'subscriber_table' => {'subscriber_user_index' => ['user_subscriber']},
	'stat_table'       => {'stats_user_index'      => ['email_stat']}
);

# table indexes that can be removed during upgrade process
our @former_indexes = (
	'user_subscriber',
	'list_subscriber',
	'subscriber_idx',
	'admin_idx',
	'netidmap_idx',
	'user_admin',
	'list_admin',
	'role_admin',
	'admin_table_index',
	'logs_table_index',
	'netidmap_table_index',
	'subscriber_table_index',
	'user_index'
);

=head1 FUNCTIONS

=over

=item get_structure($type)

Return a database structure, adapted to given database type.

=cut

sub get_structure {
	my ($type) = @_;

	$type = lc($type);

	return
		$type eq 'mysql'  ? _get_mysql_structure()      :
		$type eq 'pg'     ? _get_postgresql_structure() :
		$type eq 'sqlite' ? _get_sqlite_structure()     :
		$type eq 'oracle' ? _get_oracle_structure()     :
		$type eq 'sybase' ? _get_sybase_structure()     :
		                    _get_generic_structure()    ;
}

sub _get_mysql_structure {
	return \%base_structure;
}

sub _get_postgresql_structure {

	foreach my $table_structure (values %base_structure) {
		foreach my $field_structure (values %{$table_structure->{fields}}) {
			$field_structure->{type} =~ s/^int(1)/smallint/;
			$field_structure->{type} =~ s/^int\(?.*\)?/int4/;
			$field_structure->{type} =~ s/^smallint.*/int4/;
			$field_structure->{type} =~ s/^tinyint\(.*\)/int2/;
			$field_structure->{type} =~ s/^bigint.*/int8/;
			$field_structure->{type} =~ s/^text.*/varchar(500)/;
			$field_structure->{type} =~ s/^longtext.*/text/;
			$field_structure->{type} =~ s/^datetime.*/timestamptz/;
			$field_structure->{type} =~ s/^enum.*/varchar(15)/;
		}
	}

	return \%base_structure;
}

sub _get_sqlite_structure {

	foreach my $table_structure (values %base_structure) {
		foreach my $field_structure (values %{$table_structure->{fields}}) {
			$field_structure->{type} =~ s/^varchar.*/text/;
			$field_structure->{type} =~ s/^int\(1\).*/numeric/;
			$field_structure->{type} =~ s/^int.*/integer/;
			$field_structure->{type} =~ s/^tinyint.*/integer/;
			$field_structure->{type} =~ s/^bigint.*/integer/;
			$field_structure->{type} =~ s/^smallint.*/integer/;
			$field_structure->{type} =~ s/^datetime.*/numeric/;
			$field_structure->{type} =~ s/^enum.*/text/;
		}
	}

	return \%base_structure;
}

sub _get_oracle_structure {

	foreach my $table_structure (values %base_structure) {
		foreach my $field_structure (values %{$table_structure->{fields}}) {
			$field_structure->{type} =~ s/^varchar/varchar2/;
			$field_structure->{type} =~ s/^int.*/number/;
			$field_structure->{type} =~ s/^bigint.*/number/;
			$field_structure->{type} =~ s/^smallint.*/number/;
			$field_structure->{type} =~ s/^enum.*/varchar2(20)/;
			$field_structure->{type} =~ s/^text.*/varchar2(500)/;
			$field_structure->{type} =~ s/^longtext.*/long/;
			$field_structure->{type} =~ s/^datetime.*/date/;
		}
	}

	return \%base_structure;
}

sub _get_sybase_structure {

	foreach my $table_structure (values %base_structure) {
		foreach my $field_structure (values %{$table_structure->{fields}}) {
			$field_structure->{type} =~ s/^int.*/numeric/;
			$field_structure->{type} =~ s/^text.*/varchar(500)/;
			$field_structure->{type} =~ s/^smallint.*/numeric/;
			$field_structure->{type} =~ s/^bigint.*/numeric/;
			$field_structure->{type} =~ s/^longtext.*/text/;
			$field_structure->{type} =~ s/^enum.*/varchar(15)/;
		}
	}

	return \%base_structure;
}

1;
