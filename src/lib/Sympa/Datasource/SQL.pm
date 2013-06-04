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

Sympa::Datasource::SQL - SQL data source object

=head1 DESCRIPTION

This class implements an SQL data source.

=cut

package Sympa::Datasource::SQL;

use strict;
use base qw(Sympa::Datasource);

use English qw(-no_match_vars);
use DBI;

use Sympa::DatabaseDescription;
use Sympa::List;
use Sympa::Log::Syslog;
use Sympa::Tools;
use Sympa::Tools::Data;

## Structure to keep track of active connections/connection status
## Key : connect_string (includes server+port+dbname+DB type)
## Values : dbh,status,first_try
## "status" can have value 'failed'
## 'first_try' contains an epoch date
my %db_connections;

my $structure = {
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
};

=head1 CLASS METHODS

=over

=item Sympa::Datasource::SQL->create(%parameters)

Factory method to create a new L<Sympa::Datasource::SQL> object from a
specific subclass.

Parameters:

=over

=item C<host> => FIXME

=item C<user> => FIXME

=item C<passwd> => FIXME

=item C<db_name> => FIXME

=item C<db_type> => FIXME

=item C<connect_options> => FIXME

=item C<domain> => FIXME

=back

Return value:

A new L<Sympa::Datasource::SQL> object, or I<undef> if something went wrong.

=cut

sub create {
	my ($class, %params) = @_;

	Sympa::Log::Syslog::do_log('debug',"Creating new SQLSource object for RDBMS '%s'",$params{'db_type'});

	my $db_type = lc($params{'db_type'});
	my $subclass =
		$db_type eq 'mysql'  ? 'Sympa::Datasource::SQL::MySQL'      :
		$db_type eq 'sqlite' ? 'Sympa::Datasource::SQL::SQLite'     :
		$db_type eq 'pg'     ? 'Sympa::Datasource::SQL::PostgreSQL' :
		$db_type eq 'oracle' ? 'Sympa::Datasource::SQL::Oracle'     :
		$db_type eq 'sybase' ? 'Sympa::Datasource::SQL::Sybase'     :
		                       'Sympa::Datasource::SQL'             ;

	# better solution: UNIVERSAL::require
	my $module = $subclass . '.pm';
	$module =~ s{::}{/}g;
	eval { require $module; };
	if ($EVAL_ERROR) {
		Sympa::Log::Syslog::do_log('err',"Unable to use $subclass: $EVAL_ERROR");
		return;
	}

	return $subclass->new(%params);
}

=item Sympa::Datasource::SQL->new(%parameters)

Create a new L<Sympa::Datasource::SQL> object.

Parameters:

=over

=item C<host> => FIXME

=item C<user> => FIXME

=item C<passwd> => FIXME

=item C<db_name> => FIXME

=item C<db_type> => FIXME

=item C<connect_options> => FIXME

=item C<domain> => FIXME

=back

Return value:

A new L<Sympa::Datasource::SQL> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	my $self = {
		db_host    => $params{'db_host'},
		db_user    => $params{'db_user'},
		db_passwd  => $params{'db_passwd'},
		db_name    => $params{'db_name'},
		db_type    => $params{'db_type'},
		db_options => $params{'connect_options'},
		domain     => $params{'domain'},
	};

	bless $self, $class;
	return $self;
}

=back

=head1 INSTANCE METHODS

=over

=item $source->connect()

Connect to a SQL database.

Return value:

A true value, or I<undef> if something went wrong.

=cut

sub connect {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug3',"Checking connection to database %s",$self->{'db_name'});
	if ($self->{'dbh'} && $self->{'dbh'}->ping) {
		Sympa::Log::Syslog::do_log('debug3','Connection to database %s already available',$self->{'db_name'});
		return 1;
	}
	unless($self->establish_connection()) {
		Sympa::Log::Syslog::do_log('err','Unable to establish new connection to database %s on host %s',$self->{'db_name'},$self->{'db_host'});
		return undef;
	}
}

=item $source->establish_connection()

Connect to a SQL database.

Parameters:

None.

Return value:

A DBI database handle object, or I<undef> if something went wrong.

=cut

sub establish_connection {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug','Creating connection to database %s',$self->{'db_name'});
	## Do we have db_xxx required parameters
	foreach my $db_param ('db_type','db_name') {
		unless ($self->{$db_param}) {
			Sympa::Log::Syslog::do_log('info','Missing parameter %s for DBI connection', $db_param);
			return undef;
		}
		## SQLite just need a db_name
		unless ($self->{'db_type'} eq 'sqlite') {
			foreach my $db_param ('db_host','db_user') {
				unless ($self->{$db_param}) {
					Sympa::Log::Syslog::do_log('info','Missing parameter %s for DBI connection', $db_param);
					return undef;
				}
			}
		}
	}

	## Build connect_string
	if ($self->{'f_dir'}) {
		$self->{'connect_string'} = "DBI:CSV:f_dir=$self->{'f_dir'}";
	} else {
		$self->build_connect_string();
	}
	if ($self->{'db_options'}) {
		$self->{'connect_string'} .= ';' . $self->{'db_options'};
	}
	if (defined $self->{'db_port'}) {
		$self->{'connect_string'} .= ';port=' . $self->{'db_port'};
	}

	## First check if we have an active connection with this server
	if (defined $db_connections{$self->{'connect_string'}} &&
		defined $db_connections{$self->{'connect_string'}}{'dbh'} &&
		$db_connections{$self->{'connect_string'}}{'dbh'}->ping()) {

		Sympa::Log::Syslog::do_log('debug', "Use previous connection");
		$self->{'dbh'} = $db_connections{$self->{'connect_string'}}{'dbh'};
		return $db_connections{$self->{'connect_string'}}{'dbh'};

	} else {

		## Set environment variables
		## Used by Oracle (ORACLE_HOME)
		if ($self->{'db_env'}) {
			foreach my $env (split /;/,$self->{'db_env'}) {
				my ($key, $value) = split /=/, $env;
				$ENV{$key} = $value if ($key);
			}
		}

		$self->{'dbh'} = eval {DBI->connect($self->{'connect_string'}, $self->{'db_user'}, $self->{'db_passwd'}, { PrintError => 0 })} ;
		unless (defined $self->{'dbh'}) {
			## Notify listmaster if warn option was set
			## Unless the 'failed' status was set earlier
			if ($self->{'reconnect_options'}{'warn'}) {
				unless (defined $db_connections{$self->{'connect_string'}} &&
					$db_connections{$self->{'connect_string'}}{'status'} eq 'failed') {

					unless
					(Sympa::List::send_notify_to_listmaster('no_db', $self->{domain},{})) {
						Sympa::Log::Syslog::do_log('err',"Unable to send notify 'no_db' to listmaster");
					}
				}
			}
			if ($self->{'reconnect_options'}{'keep_trying'}) {
				Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s, still trying...', $self->{'connect_string'}, $self->{'db_user'});
			} else {
				Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s', $self->{'connect_string'}, $self->{'db_user'});
				$db_connections{$self->{'connect_string'}}{'status'} = 'failed';
				$db_connections{$self->{'connect_string'}}{'first_try'} ||= time;
				return undef;
			}
			## Loop until connect works
			my $sleep_delay = 60;
			while (1) {
				sleep $sleep_delay;
				eval {$self->{'dbh'} = DBI->connect($self->{'connect_string'}, $self->{'db_user'}, $self->{'db_passwd'}, { PrintError => 0 })};
				last if ($self->{'dbh'} && $self->{'dbh'}->ping());
				$sleep_delay += 10;
			}

			if ($self->{'reconnect_options'}{'warn'}) {
				Sympa::Log::Syslog::do_log('notice','Connection to Database %s restored.', $self->{'connect_string'});
				unless (Sympa::List::send_notify_to_listmaster('db_restored', $self->{domain},{})) {
					Sympa::Log::Syslog::do_log('notice',"Unable to send notify 'db_restored' to listmaster");
				}
			}
		}

		if ($self->{'db_type'} eq 'pg') { # Configure Postgres to use ISO format dates
			$self->{'dbh'}->do ("SET DATESTYLE TO 'ISO';");
		}

		## Set client encoding to UTF8
		if ($self->{'db_type'} eq 'mysql' ||
			$self->{'db_type'} eq 'pg') {
			Sympa::Log::Syslog::do_log('debug','Setting client encoding to UTF-8');
			$self->{'dbh'}->do("SET NAMES 'utf8'");
		} elsif ($self->{'db_type'} eq 'oracle') {
			$ENV{'NLS_LANG'} = 'UTF8';
		} elsif ($self->{'db_type'} eq 'sybase') {
			$ENV{'SYBASE_CHARSET'} = 'utf8';
		}

		## added sybase support
		if ($self->{'db_type'} eq 'sybase') {
			my $dbname;
			$dbname="use $self->{'db_name'}";
			$self->{'dbh'}->do ($dbname);
		}

		## Force field names to be lowercased
		## This has has been added after some problems of field names upercased with Oracle
		$self->{'dbh'}{'FetchHashKeyName'}='NAME_lc';

		if ($self->{'db_type'} eq 'sqlite') { # Configure to use sympa database
			$self->{'dbh'}->func( 'func_index', -1, sub { return index($_[0],$_[1]) }, 'create_function' );
			if(defined $self->{'db_timeout'}) { $self->{'dbh'}->func( $self->{'db_timeout'}, 'busy_timeout' ); } else { $self->{'dbh'}->func( 5000, 'busy_timeout' ); };
		}

		$self->{'connect_string'} = $self->{'connect_string'} if $self;
		$db_connections{$self->{'connect_string'}}{'dbh'} = $self->{'dbh'};
		Sympa::Log::Syslog::do_log('debug','Connected to Database %s',$self->{'db_name'});
		return $self->{'dbh'};
	}
}

=item $self->get_structure()

FIXME.

=cut

sub get_structure {
	my ($self) = @_;

	return $structure;
}

=item $self->probe()

FIXME.

=cut

sub probe {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug3', 'Checking database structure');

	my @report;

	my @current_tables = $self->get_tables();
	my %current_structure;
	my $target_structure = $self->get_structure();

	## Check required tables
	foreach my $table (keys %{$target_structure}) {
		next if Sympa::Tools::Data::any { $table eq $_ }
			@current_tables;

		my $result = $self->add_table(table => $table);
		if ($result) {
			push @report, $result;
			Sympa::Log::Syslog::do_log('notice', 'Table %s created in database %s', $table, $self->{db_name});
			push @current_tables, $table;
			$current_structure{$table} = {};
		}
	}

	## Get fields
	foreach my $table (@current_tables) {
		$current_structure{$table} = $self->get_fields(table => $table);
	}

	if (!%current_structure) {
		Sympa::Log::Syslog::do_log('err',"Could not check the database structure. consider verify it manually before launching Sympa.");
		return undef;
	}

	## Check tables structure if we could get it
	## Only performed with mysql , Pg and SQLite
	foreach my $table (keys %{$target_structure}) {
		unless ($current_structure{$table}) {
			Sympa::Log::Syslog::do_log('err', "Table '%s' not found in database '%s' ; you should create it with create_db.%s script", $table, $self->{db_name}, $self->{db_type});
			return undef;
		}

		my $fields_result = $self->_check_fields(
			table             => $table,
			report            => \@report,
			current_structure => $current_structure{$table},
			target_structure  => $target_structure->{$table},
			update            => $params{update}
		);
		unless ($fields_result) {
			Sympa::Log::Syslog::do_log('err', "Unable to check the validity of fields definition for table %s. Aborting.", $table);
			return undef;
		}

		## Remove temporary DB field
		if ($current_structure{$table}{'temporary'}) {
			$self->delete_field(
				table => $table,
				field => 'temporary',
			);
			delete $current_structure{$table}{'temporary'};
		}

		if (
			$self->{db_type} eq 'mysql'||
			$self->{db_type} eq 'Pg'   ||
			$self->{db_type} eq 'SQLite'
		) {
			## Check that primary key has the right structure.
			my $primary_key_result = $self->_check_primary_key(
				table            => $table,
				report           => \@report,
				target_structure => $target_structure->{$table}
			);
			unless ($primary_key_result) {
				Sympa::Log::Syslog::do_log('err', "Unable to check the valifity of primary key for table %s. Aborting.", $table);
				return undef;
			}

			my $indexes_result = $self->_check_indexes(
				table  => $table,
				report => \@report
			);
			unless ($indexes_result) {
				Sympa::Log::Syslog::do_log('err', "Unable to check the valifity of indexes for table %s. Aborting.", $table);
				return undef;
			}

		}
	}
	# add autoincrement option if needed
	foreach my $table (keys %{$target_structure}) {
		Sympa::Log::Syslog::do_log('notice',"Checking autoincrement for table $table");
		foreach my $field (keys %{$target_structure->{$table}{'fields'}}) {
			next unless $target_structure->{$table}{'fields'}{$field}{'autoincrement'};
			next if $self->is_autoinc(
				table => $table,
				field => $field
			);
			my $result = $self->set_autoinc(
				table      => $table,
				field      => $field,
				field_type => $target_structure->{$table}{'fields'}{$field});
			if ($result) {
				Sympa::Log::Syslog::do_log('notice',"Setting table $table field $field as autoincrement");
			} else {
				Sympa::Log::Syslog::do_log('err',"Could not set table $table field $field as autoincrement");
				return undef;
			}
		}
	}

	return \@report;
}

sub _check_fields {
	my ($self, %params) = @_;

	my $table     = $params{'table'};
	my $report    = $params{'report'};
	my $current_structure = $params{'current_structure'};
	my $target_structure  = $params{'target_structure'};

	foreach my $field (keys %{$target_structure->{fields}}) {
		unless ($current_structure->{$field}) {
			push @{$report}, sprintf("Field '%s' (table '%s' ; database '%s') was NOT found. Attempting to add it...", $field, $table, $self->{db_name});
			Sympa::Log::Syslog::do_log('info', "Field '%s' (table '%s' ; database '%s') was NOT found. Attempting to add it...", $field, $table, $self->{db_name});

			my $rep = $self->add_field(
				table   => $table,
				field   => $field,
				type    => $target_structure->{fields}{$field}{type},
				notnull => $target_structure->{fields}{$field}{'not_null'},
				autoinc => $target_structure->{fields}{$field}{autoincrement},
				primary => $target_structure->{fields}{$field}{autoincrement}
			);
			if ($rep) {
				push @{$report}, $rep;

			} else {
				Sympa::Log::Syslog::do_log('err', 'Addition of fields in database failed. Aborting.');
				return undef;
			}
			next;
		}

		## Change DB types if different and if update_db_types enabled
		if ($params{update} eq 'auto' && $self->{db_type} ne 'SQLite') {
			my $type_check = $self->_check_db_field_type(
				effective_format => $current_structure->{$field},
				required_format => $target_structure->{$field}
			);
			unless ($type_check) {
				push @{$report}, sprintf("Field '%s'  (table '%s' ; database '%s') does NOT have awaited type (%s). Attempting to change it...",$field, $table, $self->{db_name}, $target_structure->{$table}{$field});

				Sympa::Log::Syslog::do_log('notice', "Field '%s'  (table '%s' ; database '%s') does NOT have awaited type (%s) where type in database seems to be (%s). Attempting to change it...",$field, $table, $self->{db_name}, $target_structure->{fields}{$field}{type},$current_structure->{$field});

				my $type_change = $self->update_field(
					table   => $table,
					field   => $field,
					type    => $target_structure->{fields}{$field}{type},
					notnull => $target_structure->{fields}{$field}{not_null},
				);
				if ($type_change) {
					push @{$report}, $type_change;
				} else {
					Sympa::Log::Syslog::do_log('err', 'Fields update in database failed. Aborting.');
					return undef;
				}
			}
		} else {
			unless ($current_structure->{$field} eq $target_structure->{fields}{$field}{type}) {
				Sympa::Log::Syslog::do_log('err', 'Field \'%s\'  (table \'%s\' ; database \'%s\') does NOT have awaited type (%s).', $field, $table, $self->{db_name}, $target_structure->{fields}{$field}{type});
				Sympa::Log::Syslog::do_log('err', 'Sympa\'s database structure may have change since last update ; please check RELEASE_NOTES');
				return undef;
			}
		}
	}
	return 1;
}

sub _check_primary_key {
	my ($self, %params) = @_;

	my $table     = $params{'table'};
	my $report    = $params{'report'};
	my $target_structure = $params{'target_structure'};
	Sympa::Log::Syslog::do_log('debug','Checking primary key for table %s',$table);

	my @key_fields;
	foreach my $field (keys %{$target_structure->{fields}}) {
		next unless $target_structure->{fields}{$field}{primary};
		push @key_fields, $field;
	}

	my $key_as_string = "$table [" . join(',', @key_fields) . "]";
	Sympa::Log::Syslog::do_log('debug','Checking primary keys for table %s expected_keys %s',$table,$key_as_string );

	my $key_check = $self->check_key(
		table         => $table,
		key_name      => 'primary',
		expected_keys => \@key_fields
	);

	if ($key_check) {
		if ($key_check->{'empty'}) {
			Sympa::Log::Syslog::do_log('notice',"Primary key %s is missing. Adding it.",$key_as_string);
			# Add primary key
			my $key_addition = $self->set_primary_key(
				table  => $table,
				fields => \@key_fields
			);
			push @{$report}, $key_addition if $key_addition;
		} elsif ($key_check->{'existing_key_correct'}) {
			Sympa::Log::Syslog::do_log('debug',"Existing key correct (%s) nothing to change",$key_as_string);
		} else {
			# drop previous primary key
			my $key_deletion = $self->unset_primary_key(
				table => $table
			);
			push @{$report}, $key_deletion if $key_deletion;

			# Add primary key
			my $key_addition = $self->set_primary_key(
				table  => $table,
				fields => \@key_fields
			);
			push @{$report}, $key_addition if $key_addition;
		}
	} else {
		Sympa::Log::Syslog::do_log('err','Unable to evaluate table %s primary key. Trying to reset primary key anyway.',$table);

		# drop previous primary key
		my $key_deletion = $self->unset_primary_key(
			table => $table
		);
		push @{$report}, $key_deletion if $key_deletion;

		# Add primary key
		my $key_addition = $self->set_primary_key(
			table  => $table,
			fields => \@key_fields
		);
		push @{$report}, $key_addition if $key_addition;
	}
	return 1;
}

sub _check_indexes {
	my ($self, %params) = @_;

	my $table     = $params{'table'};
	my $report    = $params{'report'};
	Sympa::Log::Syslog::do_log('debug','Checking indexes for table %s',$table);
	## drop previous index if this index is not a primary key and was defined by a previous Sympa version
	my %index_columns = %{$self->get_indexes(table => $table)};
	foreach my $index ( keys %index_columns ) {
		Sympa::Log::Syslog::do_log('debug','Found index %s',$index);
		## Remove the index if obsolete.

		foreach my $known_index (@Sympa::DatabaseDescription::former_indexes) {
			if ( $index eq $known_index ) {
				Sympa::Log::Syslog::do_log('notice','Removing obsolete index %s',$index);
				my $index_deletion = $self->unset_index(
					table => $table,
					index => $index
				);
				push @{$report}, $index_deletion
					if $index_deletion;
				last;
			}
		}
	}

	## Create required indexes
	foreach my $index (keys %{$Sympa::DatabaseDescription::indexes{$table}}){
		## Add indexes
		unless ($index_columns{$index}) {
			Sympa::Log::Syslog::do_log('notice','Index %s on table %s does not exist. Adding it.',$index,$table);
			my $index_addition = $self->set_index(
				table      => $table,
				index_name => $index,
				fields     => $Sympa::DatabaseDescription::indexes{$table}{$index}
			);
			push @{$report}, $index_addition if $index_addition;
		}
		my $index_check = $self->check_key(
			table         => $table,
			key_name      => $index,
			expected_keys => $Sympa::DatabaseDescription::indexes{$table}{$index}
		);
		if ($index_check) {
			my $list_of_fields = join ',',@{$Sympa::DatabaseDescription::indexes{$table}{$index}};
			my $index_as_string = "$index: $table [$list_of_fields]";
			if ($index_check->{'empty'}) {
				## Add index
				Sympa::Log::Syslog::do_log('notice',"Index %s is missing. Adding it.",$index_as_string);
				my $index_addition = $self->set_index(
					table      => $table,
					index_name => $index,
					fields     => $Sympa::DatabaseDescription::indexes{$table}{$index}
				);
				push @{$report}, $index_addition
					if $index_addition;
			} elsif ($index_check->{'existing_key_correct'}) {
				Sympa::Log::Syslog::do_log('debug',"Existing index correct (%s) nothing to change",$index_as_string);
			} else {
				## drop previous index
				Sympa::Log::Syslog::do_log('notice',"Index %s has not the right structure. Changing it.",$index_as_string);
				my $index_deletion = $self->unset_index(
					table => $table,
					index => $index
				);
				push @{$report}, $index_deletion
					if $index_deletion;

				## Add index
				my $index_addition = $self->set_index(
					table      => $table,
					index_name => $index,
					fields     => $Sympa::DatabaseDescription::indexes{$table}{$index}
				);
				push @{$report}, $index_addition
					if $index_addition;
			}
		} else {
			Sympa::Log::Syslog::do_log('err','Unable to evaluate index %s in table %s. Trying to reset index anyway.',$table,$index);
			## drop previous index
			my $index_deletion = $self->unset_index(
				table => $table,
				index => $index
			);
			push @{$report}, $index_deletion
				if $index_deletion;

			## Add index
			my $index_addition = $self->set_index(
				table      => $table,
				index_name => $index,
				fields     => $Sympa::DatabaseDescription::indexes{$table}{$index}
			);
			push @{$report}, $index_addition
				if $index_addition;
		}
	}
	return 1;
}

=item $source->get_handle()

Return underlying database handle.

Parameters:

None

Return value:

A DBI database handle object.

=cut

sub get_handle {
	my ($self) = @_;

	return $self->{dbh};
}

=item $source->get_type()

Return underlying database type.

Parameters:

None

Return value:

A string.

=cut

sub get_type {
	my ($self) = @_;

	return $self->{db_type};
}

=item $source->get_name()

Return underlying database name.

Parameters:

None

Return value:

A string.

=cut

sub get_name {
	my ($self) = @_;

	return $self->{db_name};
}

=item $source->do_query($query, @params)

Parameters:

=over

=item C<$query> =>

=back

Return value:

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub do_query {
	my ($self, $query, @params) = @_;

	my $statement = sprintf $query, @params;

	Sympa::Log::Syslog::do_log('debug', "Will perform query '%s'",$statement);
	unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
		# Check connection to database in case it would be the cause of the problem.
		unless($self->connect()) {
			Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		} else {
			unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
				my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
				Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement %s : %s', $trace_statement, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}
	unless ($self->{'sth'}->execute) {
		# Check connection to database in case it would be the cause of the problem.
		unless($self->connect()) {
			Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		} else {
			unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
				# Check connection to database in case it would be the cause of the problem.
				unless($self->connect()) {
					Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
					return undef;
				} else {
					unless ($self->{'sth'} = $self->{'dbh'}->prepare($statement)) {
						my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
						Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement %s : %s', $trace_statement, $self->{'dbh'}->errstr);
						return undef;
					}
				}
			}
			unless ($self->{'sth'}->execute) {
				my $trace_statement = sprintf $query, @{$self->prepare_query_log_values(@params)};
				Sympa::Log::Syslog::do_log('err','Unable to execute SQL statement "%s" : %s', $trace_statement, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}

	return $self->{'sth'};
}

=item $source->do_prepared_query($query, @params)

Parameters:

=over

=item C<$query> =>

=back

Return value:

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub do_prepared_query {
	my ($self, $query, @params) = @_;

	my $sth;

	unless ($self->{'cached_prepared_statements'}{$query}) {
		Sympa::Log::Syslog::do_log('debug3','Did not find prepared statement for %s. Doing it.',$query);
		$sth = $self->{'dbh'}->prepare($query);
		unless ($sth) {
			unless($self->connect()) {
				Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
				return undef;
			} else {
				$sth = $self->{'dbh'}->prepare($query);
				unless ($sth) {
					Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement : %s', $self->{'dbh'}->errstr);
					return undef;
				}
			}
		}
		$self->{'cached_prepared_statements'}{$query} = $sth;
	} else {
		Sympa::Log::Syslog::do_log('debug3','Reusing prepared statement for %s',$query);
	}

	unless ($self->{'cached_prepared_statements'}{$query}->execute(@params)) {
		# Check database connection in case it would be the cause of the problem.
		unless($self->connect()) {
			Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
			return undef;
		} else {
			$sth = $self->{'dbh'}->prepare($query);
			unless ($sth) {
				unless($self->connect()) {
					Sympa::Log::Syslog::do_log('err', 'Unable to get a handle to %s database',$self->{'db_name'});
					return undef;
				} else {
					$sth = $self->{'dbh'}->prepare($query);
					unless ($sth) {
						Sympa::Log::Syslog::do_log('err','Unable to prepare SQL statement : %s', $self->{'dbh'}->errstr);
						return undef;
					}
				}
			}
			$self->{'cached_prepared_statements'}{$query} = $sth;
			unless ($self->{'cached_prepared_statements'}{$query}->execute(@params)) {
				Sympa::Log::Syslog::do_log('err','Unable to execute SQL statement "%s" : %s', $query, $self->{'dbh'}->errstr);
				return undef;
			}
		}
	}

	return $self->{'cached_prepared_statements'}{$query};
}

=item $source->get_query_handle($query)

Returns a query handle for the given query, caching it automagically.

Parameters:

=over

=item string

The SQL query.

=back

Return value:

A DBI statement handle object, or I<undef> if something went wrong.

=cut

sub get_query_handle {
	my ($self, $query) = @_;

	return
		$self->{cache}->{$query} ||=
		$self->{dbh}->prepare($query);
}

=item $source->prepare_query_log_values(@values)

Parameters:

=over

=item C<@values> =>

=back

Return value:

The list of cropped values, as an arrayref.

=cut

sub prepare_query_log_values {
	my ($self) = @_;

	my @result;
	foreach my $value (@_) {
		my $cropped = substr($value,0,100);
		if ($cropped ne $value) {
			$cropped .= "...[shortened]";
		}
		push @result, $cropped;
	}
	return \@result;
}

sub fetch {
	my ($self) = @_;

	## call to fetchrow_arrayref() uses eval to set a timeout
	## this prevents one data source to make the process wait forever if SELECT does not respond
	my $array_of_users;
	$array_of_users = eval {
		local $SIG{ALRM} = sub { die "TIMEOUT\n" }; # NB: \n required
		alarm $self->{'fetch_timeout'};

		## Inner eval just in case the fetchall_arrayref call would die, thus leaving the alarm trigered
		my $status = eval {
			return $self->{'sth'}->fetchall_arrayref;
		};
		alarm 0;
		return $status;
	};
	if ( $EVAL_ERROR eq "TIMEOUT\n" ) {
		Sympa::Log::Syslog::do_log('err','Fetch timeout on remote SQL database');
		return undef;
	} elsif ($EVAL_ERROR) {
		Sympa::Log::Syslog::do_log('err','Fetch failed on remote SQL database');
		return undef;
	}

	return $array_of_users;
}

sub disconnect {
	my ($self) = @_;

	$self->{'sth'}->finish if $self->{'sth'};
	if ($self->{'dbh'}) {$self->{'dbh'}->disconnect;}
	delete $db_connections{$self->{'connect_string'}};
}

sub create_db {
	Sympa::Log::Syslog::do_log('debug3', '()');
	return 1;
}

sub ping {
	my ($self) = @_;

	return $self->{'dbh'}->ping;
}

sub quote {
	my ($self, $string, $datatype) = @_;

	return $self->{'dbh'}->quote($string, $datatype);
}

sub set_fetch_timeout {
	my ($self, $timeout) = @_;

	return $self->{'fetch_timeout'} = $timeout;
}

=item $source->get_canonical_write_date($field)

Returns a character string corresponding to the expression to use in a read
query (e.g. SELECT) for the field given as argument.

Parameters:

=over

=item C<$field> => field to be used in the query

=back

=cut

sub get_canonical_write_date {
	my ($self, $field) = @_;

	return $self->get_formatted_date('mode'=>'write','target'=>$field);
}

=item $source->get_canonical_read_date($value)

Returns a character string corresponding to the expression to use in
a write query (e.g. UPDATE or INSERT) for the value given as argument.

Parameters:

=over

=item C<$value> => value to be used in the query

=back

=cut

sub get_canonical_read_date {
	my $self = shift;
	my $value = shift;
	return $self->get_formatted_date('mode'=>'read','target'=>$value);
}

=item $source->get_all_primary_keys()

Returns the primary keys for all the tables in the database.

Parameters:

None.

Return value:

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item * The keys of the first level are the database's tables name.

=item * The keys of the second level are the name of the primary keys for the
table whose name is  given by the first level key.

=back

=cut

sub get_all_primary_keys {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug','Retrieving all primary keys in database %s',$self->{'db_name'});
	my %found_keys = undef;
	foreach my $table ($self->get_tables()) {
		unless($found_keys{$table} = $self->get_primary_key('table'=>$table)) {
			Sympa::Log::Syslog::do_log('err','Primary key retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_keys;
}

=item $source->get_all_indexes()

Returns the indexes for all the tables in the database.

Parameters:

None.

Return value:

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item * The keys of the first level are the database's tables name.

=item * The keys of the second level are the name of the indexes for the table whose name is given by the first level key.

=back

=cut

sub get_all_indexes {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log('debug','Retrieving all indexes in database %s',$self->{'db_name'});
	my %found_indexes;
	foreach my $table ($self->get_tables()) {
		unless($found_indexes{$table} = $self->get_indexes('table'=>$table)) {
			Sympa::Log::Syslog::do_log('err','Index retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_indexes;
}

=item $source->check_key(%parameters)

Checks the compliance of a key of a table compared to what it is supposed to
reference.

Parameters:

* 'table' : the name of the table for which we want to check the primary key
* 'key_name' : the kind of key tested:
	- if the value is 'primary', the key tested will be the table primary key
		- for any other value, the index whose name is this value will be tested.
	* 'expected_keys' : A ref to an array containing the list of fields that we
	   expect to be part of the key.

Return value:

A ref likely to contain the following values:
#	* 'empty': if this key is defined, then no key was found for the table
#	* 'existing_key_correct': if this key's value is 1, then a key
#	   exists and is fair to the structure defined in the 'expected_keys' parameter hash.
#	   Otherwise, the key is not correct.
#	* 'missing_key': if this key is defined, then a part of the key was missing.
#	   The value associated to this key is a hash whose keys are the names of the fields
#	   missing in the key.
#	* 'unexpected_key': if this key is defined, then we found fields in the actual
#	   key that don't belong to the list provided in the 'expected_keys' parameter hash.
#	   The value associated to this key is a hash whose keys are the names of the fields
#	   unexpectedely found.

=cut

sub check_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Checking %s key structure for table %s',$params{'key_name'},$params{'table'});
	my $keysFound;
	my $result;
	if (lc($params{'key_name'}) eq 'primary') {
		return undef unless ($keysFound = $self->get_primary_key('table'=>$params{'table'}));
	} else {
		return undef unless ($keysFound = $self->get_indexes('table'=>$params{'table'}));
		$keysFound = $keysFound->{$params{'key_name'}};
	}

	my @keys_list = keys %{$keysFound};
	if ($#keys_list < 0) {
		$result->{'empty'}=1;
	} else {
		$result->{'existing_key_correct'} = 1;
		my %expected_keys;
		foreach my $expected_field (@{$params{'expected_keys'}}){
			$expected_keys{$expected_field} = 1;
		}
		foreach my $field (@{$params{'expected_keys'}}) {
			unless ($keysFound->{$field}) {
				Sympa::Log::Syslog::do_log('info','Table %s: Missing expected key part %s in %s key.',$params{'table'},$field,$params{'key_name'});
				$result->{'missing_key'}{$field} = 1;
				$result->{'existing_key_correct'} = 0;
			}
		}
		foreach my $field (keys %{$keysFound}) {
			unless ($expected_keys{$field}) {
				Sympa::Log::Syslog::do_log('info','Table %s: Found unexpected key part %s in %s key.',$params{'table'},$field,$params{'key_name'});
				$result->{'unexpected_key'}{$field} = 1;
				$result->{'existing_key_correct'} = 0;
			}
		}
	}
	return $result;
}

=item source->build_connect_string()

Builds the string to be used by the DBI to connect to the database.

Parameters:

None

=item source->get_substring_clause(%parameters)

Returns an SQL clause to be inserted in a query.

This clause will compute a substring of max length I<substring_length> starting
from the first character equal to I<separator> found in the value of field
I<source_field>.

Parameters:

=over

=item C<substring_length> => maximum substring length

=item C<separator> => substring first character

=item C<source_field> => field to search

=back

=item $source->get_limit_clause(%parameters)

Returns an SQL clause to be inserted in a query.

This clause will limit the number of records returned by the query to
I<rows_count>. If I<offset> is provided, an offset of I<offset> rows is done
from the first record before selecting the rows to return.

Parameters:

=over

=item C<rows_count> => maximum number of records

=item C<offset> => rows offset (optional)

=back

=item $source->get_formatted_date()

Returns a character string corresponding to the expression to use in a query
involving a date.

Parameters:

=over

=item C<mode> => the query type (I<read> for SELECT, I<write> for INSERT or
UPDATE)

=item C<target> => field name or value

=back

Return value:

The formatted date or I<undef> if the date format mode is unknonw.

=item $source->is_autoinc(%parameters)

Checks whether a field is an autoincrement field or not.

Parameters:

=over

=item C<field> => field name

=item C<table> => table name

=back

Return value:

A true value if the field is an autoincrement field, false otherwise.

=item $source->set_autoinc(%parameters)

Defines the field as an autoincrement field.

Parameters:

=over

=item C<field> => field name

=item C<table> => table name

=back

Return value:

A true value if the autoincrement could be set, I<undef> otherwise.

=item $source->get_tables()

Get the list of the tables in the database.

Parametersr:

None.

Return value:

A list of table names, or I<undef> if something went wrong.

=item $source->add_table(%parameters)

Adds a table to the database

Parameters:

=over

=item C<table> => table name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->get_fields(%parameters)

Get the list of fields in a table from the database.

Parameters:

=over

=item C<table> => table name

=back

Return value:

A list of name => value pairs as an hashref, or I<undef> if something went
wrong.

=item $source->update_field(%parameters)

Changes the type of a field in a table from the database.

Parameters:

=over

=item C<table> => table name

=item C<field> => field name

=item C<type> => field type

=item C<notnull> => specifies that the field must not be null

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->add_field(%parameters)

Adds a field in a table from the database.

Parameters:

=over

=item C<table> => table name

=item C<field> => field name

=item C<type> => field type

=item C<notnull> => specifies that the field must not be null

=item C<autoinc> => specifies that the field must be autoincremental

=item C<primary> => specifies that the field is a key

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->delete_field(%parameters)

Delete a field in a table from the database.

Parameters:

=over

=item C<table> => table name

=item C<field> => field name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->get_primary_key(%parameters)

Returns the list of fields being part of a table's primary key.

Parameters:

=over

=item C<table> => table name

=back

Return value:

An hashref whose keys are the name of the fields of the primary key, or
I<undef> if something went wrong.

=item $source->unset_primary_key(%parameters)

Drops the primary key of a table.

Parameters:

=over

=item C<table> => table name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->set_primary_key(%parameters)

Sets the primary key of a table.

Parameters:

=over

=item C<table> => table name

=item C<fields> => field names, as an arrayref

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->get_indexes(%parameters)

Returns the list of indexes of a table.

Parameters:

=over

=item C<table> => table name

=back

Return value:

An hashref whose keys are the name of indexes, with hashref whose keys are the
indexed fields as values, or I<undef> if something went wrong.

=item $source->unset_index(%parameters)

Drops an index of a table.

Parameters:

=over

=item C<table> => table name

=item C<index> => index name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=item $source->set_index(%parameters)

Sets an index in a table.

Parameters:

=over

=item C<table> => table name

=item C<fields> => field names, as an arrayref

=item C<index_name> => index name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=back

=cut

1;
