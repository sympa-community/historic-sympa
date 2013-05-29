# Sympa::Constants.pm - This module contains all installation-related variables
# RCS Identication ; $Revision: 5768 $ ; $Date: 2009-05-21 16:23:23 +0200 (jeu. 21 mai 2009) $ 
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Sympa::DatabaseDescription;
use strict;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(db_struct not_null %not_null primary %primary autoincrement %autoincrement %indexes %former_indexes);

our %not_null = &not_null;
our %primary = &primary;
our %autoincrement = &autoincrement;

sub full_db_struct {

my %full_db_struct = (
    'subscriber_table' => {
	'fields' => {
	    'user_subscriber' => {
		'struct'=> 'varchar(100)',
		'doc'=>'email of subscriber',
		'primary'=>1,
		'not_null'=>1,
		'order'=>1
	    },
	    'list_subscriber' => {
		'struct'=> 'varchar(50)',
		'doc'=>'list name of a subscription',
		'primary'=>1,
		'not_null'=>1,
		'order'=>2
	    },
	    'robot_subscriber' => {
		'struct'=> 'varchar(80)',
		'doc'=>'robot (domain) of the list',
		'primary'=>1,
		'not_null'=>1,
		'order'=>3
	    },
	    'reception_subscriber' => {
		'struct'=> 'varchar(20)',
		'doc'=>'reception format option of subscriber (digest, summary, etc.)',				
		'order'=>4,
	    },
	    'suspend_subscriber' => {
		'struct'=> 'int(1)',				
		'doc'=>'boolean set to 1 if subscription is suspended',
		'order'=>5,
	    },
	    'suspend_start_date_subscriber' => {
		'struct'=> 'int(11)',
		'doc'=>'The date (epoch) when message reception is suspended',
		'order'=>6,
	    },
	    'suspend_end_date_subscriber' => {
		'struct'=> 'int(11)',
		'doc'=>'The date (epoch) when message reception should be restored',
		'order'=>7,
	    },
	    'bounce_subscriber' => {
		'struct'=> 'varchar(35)',
		'doc'=>'FIXME',
		'order'=>8,
	    },
	    'bounce_score_subscriber' => {
		'struct'=> 'smallint(6)',
		'doc'=>'FIXME',
		'order'=>9,
	    },
	    'bounce_address_subscriber' => {
		'struct'=> 'varchar(100)',
		'doc'=>'FIXME',
		'order'=>10,
	    },
	    'date_subscriber' => {
		'struct'=> 'datetime',
		'doc'=>'date of subscription',
		'not_null'=>1,
		'order'=>11,
	    },
	    'update_subscriber' => {
		'struct'=> 'datetime',
		'doc'=>'the latest date where subscription is confirmed by subscriber',
		'order'=>12,
	    },
	    'comment_subscriber' => {
		'struct'=> 'varchar(150)',
		'doc'=>'Free form name',
		'order'=>13,
	    },
	    'number_messages_subscriber' => {
		'struct'=> 'int(5)',
		'doc'=>'the number of message the subscriber sent',
		'not_null'=>1,
		'order'=>5,
		'order'=>14,
	    },
	    'visibility_subscriber' => {
		'struct'=> 'varchar(20)',
		'doc'=>'FIXME',
		'order'=>15,
	    },
	    'topics_subscriber' => {
		'struct'=> 'varchar(200)',
		'doc'=>'topic subscription specification',
		'order'=>16,
	    },
	    'subscribed_subscriber' => {
		'struct'=> 'int(1)',
		'doc'=>'boolean set to 1 if subscriber comes from ADD or SUB',
		'order'=>17,
	    },
	    'included_subscriber' => {
		'struct'=> 'int(1)',
		'doc'=>'boolean, set to 1 is subscriber comes from an external datasource. Note that included_subscriber and subscribed_subscriber can both value 1',
		'order'=>18,
	    },
	    'include_sources_subscriber' => {
		'struct'=> 'varchar(50)',
		'doc'=>'comma seperated list of datasource that contain this subscriber',
		'order'=>19,
	    },
	    'custom_attribute_subscriber' => {
		'struct'=> 'text',
		'doc'=>'FIXME',
		'order'=>10,
	    },

	},
	'doc' =>'This table store subscription, subscription option etc.',
	'order'=>1,
    },
    'user_table'=> {
	'fields' => {
	    'email_user' => {
		'struct' => 'varchar(100)' ,
		'doc' =>'email user is the key',
		'primary'=>1,
		'not_null'=>1,
	    },
	    'gecos_user' => {
		'struct' => 'varchar(150)',
		'order'=>3,
	    },
	    'password_user' => {
		'struct' => 'varchar(40)',
		'doc' => 'password are stored as fringer print', 'order'=>2,
	    },
	    'last_login_date_user' => {
		'struct'=> 'int(11)',
		'doc' => 'date epoch from last login, printed in login result for security purpose',
		'order'=>4,
	    },
	    'last_login_host_user' => {
		'struct'=> 'varchar(60)',
		'doc' => 'host of last login, printed in login result for security purpose',
		'order'=>5,
	    },
	    'wrong_login_count_user' =>{
		'struct'=> 'int(11)',
		'doc' => 'login attempt count, used to prevent brut force attack',
		'order'=> 6,
	    },
	    'cookie_delay_user' => {
		'struct'=> 'int(11)',
		'doc'=>'FIXME',
	    },
	    'lang_user' => {
		'struct'=>'varchar(10)',
		'doc'=>'user langage preference',
	    },
	    'attributes_user' => {
		'struct'=>'text',
		'doc'=>'FIXME',
	    },
	    'data_user' => {
		'struct'=>'text',
		'doc'=>'FIXME',
	    },
	},
	'doc' => 'The user_table is mainly used to manage login from web interface. A subscriber may not appear in the user_table if he never log through the web interface.',
	'order'=>2,
    },
    'spool_table' => {
	'fields' => {
	    'messagekey_spool' => {
		'struct'=> 'bigint(20)',
		'doc'=>'primary key',
		'primary'=>1,
		'not_null'=>1,
		'autoincrement'=>1,
		'order'=>1,
	    },
	    'spoolname_spool'=> {
		'struct'=>  "enum('msg','auth','mod','digest','archive','bounce','subscribe','topic','bulk','validated','task')",
		'doc'=>'the spool name',
		'not_null'=>1,
		'order'=>2,
	    },
	    'list_spool'=> {
		'struct'=> 'varchar(50)',
		'doc' => '',
		'order'=>3,
	    },
	    'robot_spool' =>{
		'struct'=> 'varchar(80)',
		'doc'=>'',
		'order'=>4,
	    },
	    'priority_spool'=> {
		'struct'=> 'varchar(2)',
		'doc'=>'priority (list priority, owner pririty etc)',
		'order'=>5,
	    },
	    'date_spool'=> {
		'struct'=> 'int(11)',
		'doc'=>'the date a message is copied in spool table',
		'order'=>6,
	    },
	    'messagelock_spool' => {
		'struct'=> 'varchar(90)',
		'doc'=>'a unique string for each process : $$@hostname',
		'order'=>8,
	    },
	    'lockdate_spool' => {
		'struct'=> 'int(11)',
		'doc'=>'the date a lock is set. Used in order detect old locks',
		'order'=>9,
	    },
	    'message_status_spool' => {
		'struct'=> "enum('ok','bad')",
		'doc'=>'if problem when processed entries have bad status',
		'order'=>10,
	    },
	    'message_diag_spool' =>{
		'struct'=> 'text',
		'doc'=>'the reason why a message is moved to bad',
		'order'=>11,
	    },
	    'type_spool'=> {
		'struct'=> 'varchar(15)',
		'doc'=>'list, list-request,, sympa robot or other rcp ',
		'order'=>12,
	    },
	    'authkey_spool' => {
		'struct'=> 'varchar(33)',
		'doc'=>' authentication key for email chalenge',
		'order'=>13,
	    },
	    'headerdate_spool' => {
		'struct'=> 'varchar(80)',
		'doc'=>'the message header date',
		'order'=>14,
	    },
	    'create_list_if_needed_spool'=> {
		'struct'=> 'int(1)',
		'doc'=>'set to 1 if message is related to a dynamic list, set to 0 if list as been created or if list is static',
		'order'=>15,
	    },
	    'subject_spool'=>{
		'struct'=> 'varchar(110)',
		'doc'=>'subject of the message stored to list spool content faster',
		'order'=>16,
	    },
	    'sender_spool'=>{
		'struct'=> 'varchar(110)',
		'doc'=>'this info is stored to browse spool content faster',
		'order'=>17,
	    },
	    'messageid_spool' => {
		'struct'=> 'varchar(300)',
		'doc'=>'stored to list spool content faster',
		'order'=>18,
	    },
	    'spam_status_spool' => {
		'struct'=> 'varchar(12)',
		'doc'=>'spamstatus scenario result',
		'order'=>19,
	    },
	    'size_spool' => {
		'struct'=> 'int(11)',
		'doc'=>'info stored in order to browse spool content faster',
		'order'=>20,
	    },
	    'task_date_spool' => {
		'struct'=> 'int(11)',
		'doc'=>'date for a task',
		'order'=>21,
	    },
	    'task_label_spool' => {
		'struct'=> 'varchar(20)',
		'doc'=>'label for a task',
		'order'=>22,
	    },
	    'task_model_spool' => {
		'struct'=> 'varchar(40)',
		'doc'=>'model of related task',
		'order'=>23,
	    },
	    'task_flavour_spool' => {
		'struct'=> 'varchar(60)',
		'doc'=>'the declinaison of the model used with this task',
		'order'=>24,
	    },
	    'task_object_spool' => {
		'struct'=> 'varchar(50)',
		'doc'=>'object of related task',
		'order'=>25,
	    },
	    'dkim_privatekey_spool' => {
		'struct'=> 'varchar(2000)',
		'doc'=>'DKIM parameter stored for bulk daemon because bulk ignore list parameters, private key to sign message',
		'order'=>35,
	    },
	    'dkim_selector_spool' => {
		'struct'=> 'varchar(50)',
		'doc'=>'DKIM parameter stored for bulk daemon because bulk ignore list parameters, DKIM selector to sign message',
		'order'=>36,
	    },
	    'dkim_d_spool' => {
		'struct'=> 'varchar(50)',
		'doc'=>'DKIM parameter stored for bulk daemon because bulk ignore list parameters, the d DKIM parameter',
		'order'=>37,
	    },
	    'dkim_i_spool' => {
		'struct'=> 'varchar(100)',
		'doc'=>'DKIM parameter stored for bulk daemon because bulk ignore list parameters, DKIM i signature parameter',
		'order'=>38,
	    },
	    'message_spool' => {
		'struct'=> 'longtext',
		'doc'=>'message as string b64 encoded',
		'order'=>99, # long field should be the last column on Oracle.
	    },
	},
	'doc'=>'This table is created in version 6.2. It replace most of spools on file system for clustering purpose',
	'order'=>3,	    
    },
    'bulkpacket_table' => {
	'fields' => {
	    'messagekey_bulkpacket' => {
		'struct'=> 'bigint(20)',
		'doc'=>'A pointer to a message in spool_table.  It must be a value of a line in table spool_table with same value as messagekey_spool',
		'primary'=>1,
		'not_null'=>1,
		'order'=>1,
	    },
	    'packetid_bulkpacket' => {
		'struct'=> 'varchar(33)',
		'doc'=>'An id for the packet',
		'primary'=>1,
		'not_null'=>1,
		'order'=>2,
	    },
	    'messageid_bulkpacket' => {
		'struct'=> 'varchar(200)',
		'doc'=>'The message Id',
		'order'=>3,
	    },
	    'receipients_bulkpacket' => {
		'struct'=> 'text',
		'doc'=>'the comma separated list of receipient email for this message',
		'order'=>4,
	    },
	    'returnpath_bulkpacket' => {
		'struct'=> 'varchar(100)',
		'doc'=>'the return path value that must be set when sending the message',
		'order'=>5,
	    },
	    'robot_bulkpacket' => {
		'struct'=> 'varchar(80)',
		'doc'=>'',
		'order'=>6,
	    },
	    'listname_bulkpacket' => {
		'struct'=> 'varchar(50)',
		'doc'=>'',
		'order'=>7,
	    },
	    'verp_bulkpacket' => {
		'struct'=> 'int(1)',
		'doc'=>'A boolean to specify if VERP is requiered, in this cas return_path will be formated using verp form',
		'order'=>8,
	    },
	    'tracking_bulkpacket' => {
		'struct'=> "enum('mdn','dsn')",
		'doc'=>'Is DSN or MDM requiered when sending this message?',
		'order'=>9,
	    },
	    'merge_bulkpacket' => {
		'struct'=> 'int(1)',
		'doc'=>'Boolean, if true, the message is to be parsed as a TT2 template foreach receipient',
		'order'=>10,
	    },
	    'priority_message_bulkpacket' => {
		'struct'=> 'smallint(10)',
		'doc'=>'FIXME',
		'order'=>11,
	    },
	    'priority_packet_bulkpacket' => {
		'struct'=> 'smallint(10)',
		'doc'=>'FIXME',
		'order'=>12,
	    },
	    'reception_date_bulkpacket' => {
		'struct'=> 'int(11)',
		'doc'=>'The date where the message was received',
		'order'=>13,
	    },
	    'delivery_date_bulkpacket' => {
		'struct'=> 'int(11)',
		'doc'=>'The date the message was sent',
		'order'=>14,
	    },
	    'lock_bulkpacket' => {
		'struct'=> 'varchar(30)',
		'doc' => 'A lock. It is set as process-number @ hostname so multiple bulk mailers can handle this spool',
		'order'=>15,
	    },
	},
	'doc'=>'storage of receipients with a ref to a message in spool_table. So a very simple process can distribute them',
	'order'=>4,
    },
    'exclusion_table' => {
	'fields' => {
	    'list_exclusion' => {
		'struct'=> 'varchar(50)',
		'doc'=>'',
		'order' => 1,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'robot_exclusion' => {
		'struct'=> 'varchar(50)',
		'doc'=>'',
		'order' => 2,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'user_exclusion' => {
		'struct'=> 'varchar(100)',
		'doc'=>'',
		'order' => 3,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'family_exclusion' => {
		'struct'=> 'varchar(50)',
		'doc'=>'',
		'order' => 4,
	    },
	    'date_exclusion' => {
		'struct'=> 'int(11)',
		'doc'=>'',
		'order' => 5,
	    },
	},
	'doc'=>'exclusion table is used in order to manage unsubscription for subsceriber inclued from an external data source',
	'order'=>5,
    },
    'session_table' => {
	'fields' => {
	    'id_session' => {
		'struct'=> 'varchar(30)',
		'doc'=>'the identifier of the database record',
		'primary'=>1,
		'not_null'=>1,
		'order'=>1,
	    },
	    'prev_id_session' => {
		'struct' => 'varchar(30)',
		'doc' => 'previous identifier of the database record',
		'order' => 2,
	    },
	    'start_date_session' => {
		'struct'=> 'int(11)',
		'doc'=>'the date when the session was created',
		'not_null'=>1,
		'order' => 3,
	    },
	    'date_session' => {
		'struct'=> 'int(11)',
		'doc'=>'date epoch of the last use of this session. It is used in order to expire old sessions',
		'not_null'=>1,
		'order' => 4,
	    },
	    'refresh_date_session' => {
		'struct' => 'int(11)',
		'doc' => 'date epoch of the last refresh of this session.  It is used in order to refresh available sessions',
		'order' => 5,
	    },
	    'remote_addr_session' => {
		'struct'=> 'varchar(60)',
		'doc'=>'The IP address of the computer from which the session was created',
		'order' => 6,
	    },
	    'robot_session'  => {
		'struct'=> 'varchar(80)',
		'doc'=>'The virtual host in which the session was created',
		'order' => 7,
	    },
	    'email_session'  => {
		'struct'=> 'varchar(100)',
		'doc'=>'the email associated to this session',
		'order' => 8,
	    },
	    'hit_session' => {
		'struct'=> 'int(11)',
		'doc'=>'the number of hit performed during this session. Used to detect crawlers',
		'order' => 9,
	    },
	    'data_session'  => {
		'struct'=> 'text',
		'doc'=>'parameters attached to this session that don\'t have a dedicated column in the database',
		'order' => 10,
	    },
	},
	'doc'=>'management of HTTP session',
	'order' => 6,
    },
    'one_time_ticket_table' => {
	'fields' => {
	    'ticket_one_time_ticket' => {
		'struct'=> 'varchar(30)',
		'doc'=>'',
		'primary'=>1,
	    },
	    'email_one_time_ticket' => {
		'struct'=> 'varchar(100)',
		'doc'=>'',
	    },
	    'robot_one_time_ticket' => {
		'struct'=> 'varchar(80)',
		'doc'=>'',
	    },
	    'date_one_time_ticket' => {
		'struct'=> 'int(11)',
		'doc'=>'',
	    },
	    'data_one_time_ticket' => {
		'struct'=> 'varchar(200)',
		'doc'=>'',
	    },
	    'remote_addr_one_time_ticket' => {
		'struct'=> 'varchar(60)',
		'doc'=>'',
	    },
	    'status_one_time_ticket' => {
		'struct'=> 'varchar(60)',
		'doc'=>'',
	    },
	},
	'doc'=>'One time ticket are random value use for authentication chalenge. A ticket is associated with a context which look like a session',
	'order'=> 7,
    },
    'notification_table' => {
	'fields' => {
	    'pk_notification' => {
		'struct'=> 'bigint(20)',
		'doc'=>'Autoincrement key',
		'autoincrement'=>1,
		'primary'=>1,
		'not_null'=>1,
		'order'=>1,
	    },
	    'message_id_notification' => {
		'struct'=> 'varchar(100)',
		'doc'=>'initial message-id. This feild is used to search DSN and MDN related to a particular message',
		'order'=>2,
	    },
	    'recipient_notification' => {
		'struct'=> 'varchar(100)',
		'doc'=>'email adresse of receipient for which a DSN or MDM was received',
		'order'=>3,
	    },
	    'reception_option_notification' => {
		'struct'=> 'varchar(20)',
		'doc'=>'The subscription option of the subscriber when the related message was sent to the list. Ussefull because some receipient may have option such as //digest// or //nomail//',
		'order'=>4,
	    },
	    'status_notification' => {
		'struct'=> 'varchar(100)',
		'doc'=>'Value of notification',
		'order'=>5,
	    },
	    'arrival_date_notification' => {
		'struct'=> 'varchar(80)',
		'doc'=>'reception date of latest DSN or MDM',
		'order'=>6,
	    },
	    'type_notification' => {
		'struct'=> "enum('DSN', 'MDN')",
		'doc'=>'Type of the notification (DSN or MDM)',
		'order'=>7,
	    },
	    'list_notification' => {
		'struct'=> 'varchar(50)',
		'doc'=>'The listname the messaage was issued for',
		'order'=>9,
	    },
	    'robot_notification' => {
		'struct'=> 'varchar(80)',
		'doc'=>'The robot the message is related to',
		'order'=>10,
	    },
	    'date_notification' => {
		'struct'=> 'int(11)',
		'doc'=>'FIXME',
		'not_null'=>1,
	        'order' => 11,
	    },
	    'message_notification' => {
		'struct'=> 'longtext',
		'doc'=>'The DSN or the MDN itself',
		'order'=>99, # long field should be the last column on Oracle.
	    },
	},
	'doc' => 'used for message tracking feature. If the list is configured for tracking, outgoing messages include a delivery status notification request and optionnaly a return receipt request.When DSN MDN are received by Syamp, they are store in this table in relation with the related list and message_id',
	'order' => 8,
    },
    'logs_table' => {
	'fields' => {
	    'id_logs' => {
		'struct'=> 'bigint(20)',
		'doc'=>'Unique log\'s identifier',
		'primary'=>1,
		'not_null'=>1,
		'order'=>1,
	    },
	    'user_email_logs' => {
		'struct'=> 'varchar(100)',
		'doc'=>'e-mail address of the message sender or email of identified web interface user (or soap user)',
		'order'=>2,
	    },
	    'date_logs' => {
		'struct'=> 'double',
		'doc'=>'date when the action was executed',
		'not_null'=>1,
		'order'=>3,
	    },
	    'robot_logs' => {
		'struct'=> 'varchar(80)',
		'doc'=>'name of the robot in which context the action was executed',
		'order'=>4,
	    },
	    'list_logs' => {
		'struct'=> 'varchar(50)',
		'doc'=>'name of the mailing-list in which context the action was executed',
		'order'=>5,
	    },
	    'action_logs' => {
		'struct'=> 'varchar(50)',
		'doc'=>'name of the Sympa subroutine which initiated the log',
		'not_null'=>1,
		'order'=>6,
	    },
	    'parameters_logs' => {
		'struct'=> 'varchar(100)',
		'doc'=>'List of commas-separated parameters. The amount and type of parameters can differ from an action to another',
		'order'=>7,
	    },
	    'target_email_logs' => {
		'struct'=> 'varchar(100)',
		'doc'=>'e-mail address (if any) targeted by the message',
		'order'=>8,
	    },
	    'msg_id_logs' => {
		'struct'=> 'varchar(255)',
		'doc'=>'identifier of the message which triggered the action',
		'order'=>9,
	    },
	    'status_logs' => {
		'struct'=> 'varchar(10)',
		'doc'=>'exit status of the action. If it was an error, it is likely that the error_type_logs field will contain a description of this error',
		'not_null'=>1,
		'order'=>10,
	    },
	    'error_type_logs' => {
		'struct'=> 'varchar(150)',
		'doc'=>'name of the error string (if any) issued by the subroutine',
		'order'=>11,
	    },
	    'client_logs' => {
		'struct'=> 'varchar(100)',
		'doc'=>'IP address of the client machine from which the message was sent',
		'order'=>12,
	    },
	    'daemon_logs' => {
		'struct'=> 'varchar(10)',
		'doc'=>'name of the Sympa daemon which ran the action',
		'not_null'=>1,
		'order'=>13,
	    },
	},
	'doc'=> 'Each important event is stored in this table. List owners and listmaster can search entries in this table using web interface.',
	'order' => 9,
    },
    'stat_table' => {
	'fields' => {
	    'id_stat' => {
		'struct'=> 'bigint(20)',
		'doc'=>'',
		'order' => 1,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'date_stat' => {
		'struct'=> 'int(11)',
		'doc'=>'',
		'order' => 2,
		'not_null'=>1,
	    },
	    'email_stat' => {
		'struct'=> 'varchar(100)',
		'doc'=>'',
		'order' => 3,
	    },
	    'operation_stat' => {
		'struct'=> 'varchar(50)',
		'doc'=>'',
		'order' => 4,
		'not_null'=>1,
	    },
	    'list_stat' => {
		'struct'=> 'varchar(150)',
		'doc'=>'',
		'order' => 5,
	    },
	    'daemon_stat' => {
		'struct'=> 'varchar(10)',
		'doc'=>'',
		'order' => 6,
	    },
	    'user_ip_stat' => {
		'struct'=> 'varchar(100)',
		'doc'=>'',
		'order' => 7,
	    },
	    'robot_stat' => {
		'struct'=> 'varchar(80)',
		'doc'=>'',
		'order' => 8,
		'not_null'=>1,
	    },
	    'parameter_stat' => {
		'struct'=> 'varchar(50)',
		'doc'=>'',
		'order' => 9,
	    },
	    'read_stat' => {
		'struct'=> 'tinyint(1)',
		'doc'=>'',
		'order' => 10,
		'not_null'=>1,
	    },
	},
	'doc'=> 'Statistic item are store in this table, Sum average etc are stored in Stat_counter_table',
	'order' => 10,
    },
    'stat_counter_table' => {
	'fields' => {
	    'id_counter' => {
		'struct'=> 'bigint(20)',
		'doc'=>'',
		'order' => 1,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'beginning_date_counter' => {
		'struct'=> 'int(11)',
		'doc'=>'',
		'order' => 2,
		'not_null'=>1,
	    },
	    'end_date_counter' => {
		'struct'=> 'int(11)',
		'doc'=>'',
		'order' => 1,
	    },
	    'data_counter' => {
		'struct'=> 'varchar(50)',
		'doc'=>'',
		'not_null'=>1,
		'order' => 3,
	    },
	    'robot_counter' => {
		'struct'=> 'varchar(80)',
		'doc'=>'',
		'not_null'=>1,
		'order' => 4,
	    },
	    'list_counter' => {
		'struct'=> 'varchar(150)',
		'doc'=>'',
		'order' => 5,
	    },
	    'variation_counter' => {
		'struct'=> 'int',
		'doc'=>'',
		'order' => 6,
	    },
	    'total_counter' => {
		'struct'=> 'int',
		'doc'=>'',
		'order' => 7,
	    },
	},
	'doc' => 'Use in conjunction with stat_table for users statistics',
	'order' => 11,
    },
    
    'admin_table' => {
	'fields' => {

	    'user_admin' => {
		'struct'=> 'varchar(100)',
		'primary'=>1,
		'not_null'=>1,
		'doc'=>'List admin email',
		'order'=>1,
	    },
	    'list_admin' => {
		'struct'=> 'varchar(50)',
		'primary'=>1,
		'not_null'=>1,
		'doc'=>'Listname',
		'order'=>2,
	    },
	    'robot_admin' => {
		'struct'=> 'varchar(80)',
		'primary'=>1,
		'not_null'=>1,
		'doc'=>'List domain',
		'order'=>3,
	    },
	    'role_admin' => {
		'struct'=> "enum('listmaster','owner','editor')",
		'doc'=>'',
		'primary'=>1,
		'doc'=>'A role of this user for this list (editor, owner or listmaster which a kind of list owner too)',
		'order'=>4,
	    },
	    'profile_admin' => {
		'struct'=> "enum('privileged','normal')",
		'doc'=>'privilege level for this owner, value //normal// or //privileged//. The related privilege are listed in editlist.conf. ',
		'order'=>5,
	    },
	    'date_admin' => {
		'struct'=> 'datetime',
		'doc'=>'date this user become a list admin',
		'not_null'=>1,
		'order'=>6,
	    },
	    'update_admin' => {
		'struct'=> 'datetime',
		'doc'=>'last update timestamp',
		'order'=>7,
	    },
	    'reception_admin' => {
		'struct'=> 'varchar(20)',
		'doc'=>'email reception option for list managment messages',
		'order'=>8,
	    },
	    'visibility_admin' => {
		'struct'=> 'varchar(20)',
		'doc'=>'admin user email can be hidden in the list web page description',
		'order'=>9,
	    },
	    'comment_admin' => {
		'struct'=> 'varchar(150)',
		'doc'=>'',
		'order'=>10,
	    },
	    'subscribed_admin' => {
		'struct'=> 'int(1)',
		'doc'=>'Set to 1 if user is list admin by definition in list config file',
		'order'=>11,
	    },
	    'included_admin' => {
		'struct'=> 'int(1)',
		'doc'=>'Set to 1 if user is admin by an external data source',
		'order'=>12,
	    },
	    'include_sources_admin' => {
		'struct'=> 'varchar(50)',
		'doc'=>'name of external datasource',
		'order'=>13,
	    },
	    'info_admin' => {
		'struct'=>  'varchar(150)',
		'doc'=>'private information usually dedicated to listmasters who needs some additional information about list owners',
		'order'=>14,
	    },

	},
	'doc'=>'This table is a internal cash where list admin roles are stored. It is just a cash and and it does not need to saved. You may remove its content if needed. It will just make next Sympa start slower.',
	'order' => 12,
    },
    'netidmap_table' => {
	'fields' => {
	    'netid_netidmap' => {
		'struct'=> 'varchar(100)',
		'doc'=>'',
		'primary'=>1,
		'not_null'=>1,
		'order' => 1,
	    },
	    'serviceid_netidmap' => {
		'struct'=> 'varchar(100)',
		'doc'=>'',
		'primary'=>1,
		'not_null'=>1,
		'order' => 2,
	    },
	    'email_netidmap' => {
		'struct'=> 'varchar(100)',
		'doc'=>'',
		'order' => 4,
	    },
	    'robot_netidmap' => {
		'struct'=> 'varchar(80)',
		'doc'=>'',
		'primary'=>1,
		'not_null'=>1,
		'order' => 3,
	    },
	},
	'order' => 13,
	'doc' => 'FIXME',
    },
    'conf_table' => {
	'fields' => {
	    'robot_conf' => {
		'struct'=> 'varchar(80)',
		'doc'=>'',
		'primary'=>1,
		'order'=>1,
	    },
	    'label_conf' => {
		'struct'=> 'varchar(80)',
		'doc'=>'',
		'primary'=>1,
		'order'=>2,
	    },
	    'value_conf' => {
		'struct'=> 'varchar(300)',
		'doc'=>'the value of parameter //label_conf// of robot //robot_conf//.',
		'order' => 3,
	    },
	},
	'doc' => 'FIXME',
	'order' => 14,
    },
    'oauthconsumer_sessions_table' => {
	'fields' => {
	    'user_oauthconsumer' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 1,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'provider_oauthconsumer' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 2,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'tmp_token_oauthconsumer' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 3,
	    },
	    'tmp_secret_oauthconsumer' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 4,
	    },
	    'access_token_oauthconsumer' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 5,
	    },
	    'access_secret_oauthconsumer' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 6,
	    },
	},
	'doc' => 'FIXME',
	'order' => 15,
    },
    'oauthprovider_sessions_table' => {
	'fields' => {
	    'id_oauthprovider' => {
		'struct' => 'bigint(20)',
		'doc' => 'Autoincremental key',
		'order' => 1,
		'primary'=>1,
		'not_null'=>1,
		'autoincrement' => 1,
	    },
	    'token_oauthprovider' => {
		'struct' =>'varchar(32)',
		'doc' => 'FIXME',
		'order' => 2,
		'not_null'=>1,
	    },
	    'secret_oauthprovider' => {
		'struct' => 'varchar(32)',
		'doc' => 'FIXME',
		'order' => 3,
		'not_null'=>1,
	    },
	    'isaccess_oauthprovider' => {
		'struct' => 'tinyint(1)',
		'doc' => 'FIXME',
		'order' => 4,
	    },
	    'accessgranted_oauthprovider' => {
		'struct' => 'tinyint(1)',
		'doc' => 'FIXME',
		'order' => 5,
	    },
	    'consumer_oauthprovider' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 6,
		'not_null'=>1,
	    },
	    'user_oauthprovider' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 7,
	    },
	    'firsttime_oauthprovider' => {
		'struct' => 'int(11)',
		'doc' => 'FIXME',
		'order' => 8,
		'not_null'=>1,
	    },
	    'lasttime_oauthprovider' => {
		'struct' => 'int(11)',
		'doc' => 'FIXME',
		'order' => 9,
		'not_null'=>1,
	    },
	    'verifier_oauthprovider' => {
		'struct' => 'varchar(32)',
		'doc' => 'FIXME',
		'order' => 10,
	    },
	    'callback_oauthprovider' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 11,
	    },
	},
	'doc' => 'FIXME',
	'order' => 16,
    },
    'oauthprovider_nonces_table' => {
	'fields' => {
	    'id_nonce' => {
		'struct' => 'bigint(20)',
		'doc' => 'Autoincremental key',
		'order' => 1,
		'primary'=>1,
		'not_null'=>1,
		'autoincrement' => 1,
	    },
	    'id_oauthprovider' => {
		'struct' => 'int(11)',
		'doc' => 'FIXME',
		'order' => 2,
	    },
	    'nonce_oauthprovider' => {
		'struct' => 'varchar(100)',
		'doc' => 'FIXME',
		'order' => 3,
		'not_null'=>1,
	    },
	    'time_oauthprovider' => {
		'struct' => 'int(11)',
		'doc' => 'FIXME',
		'order' => 4,
	    },
	},
	'doc' => 'FIXME',
	'order' => 17,
    },
    'list_table' => {
	'fields' => {
	    ## Identification
	    'name_list'=> => {
		'struct' => 'varchar(100)',
		'doc' => 'Name of the list',
		'order' => 1,
		'primary'=>1,
		'not_null'=>1,
	    },
	    'robot_list' => {
		'struct' => 'varchar(100)',
		'doc' => 'Name of the robot (domain) the list belongs to',
		'order' => 2,
		'primary'=>1,
		'not_null'=>1,
	    },
	    ## basic profile
	    'family_list' => {
		'struct' => 'varchar(100)',
		'doc' => 'Name of the family the list belongs to',
		'order' => 3,
	    },
	    'status_list' => {
		'struct' => "enum('open','closed','pending','error_config','family_closed')",
		'doc' => 'Status of the list',
		'order' => 4,
	    },
	    'creation_email_list' => {
		'struct' => 'varchar(100)',
		'doc' => 'Email of user who created the list',
		'order' => 5,
	    },
	    'creation_epoch_list' => {
		'struct' => 'int(11)',
		'doc' => 'UNIX time when the list was created',
		'order' => 6,
	    },
	    'update_email_list' => {
		'struct' => 'varchar(100)',
		'doc' => 'Email of user who updated the list',
		'order' => 7,
	    },
	    'update_epoch_list' => {
		'struct' => 'int(11)',
		'doc' => 'UNIX time when the list was updated',
		'order' => 8,
	    },
	    ## Other indices to help searching lists
	    'searchkey_list' => {
		'struct' => 'varchar(255)',
		'doc' => 'Case-folded list subject to help searching',
		'order' => 10,
	    },
	    'web_archive_list' => {
		'struct' => 'tinyint(1)',
		'doc' => 'If the list has archives',
		'order' => 11,
	    },
	    'topics_list' => {
		'struct' => 'varchar(255)',
		'doc' => 'Topics of the list, separated and enclosed by commas',
		'order' => 12,
	    },
	    ## total cache
	    'total_list' => {
		'struct' => 'int(7)',
		'doc' => 'Estimated number of subscribers',
		'order' => 90,
	    },
	    ## cache management
	    'cache_epoch_list' => {
		'struct' => 'int(11)',
		'doc' => 'UNIX time of cache entry',
		'order' => 98,
	    },
	    ## admin cache
	    'config_list' => {
		'struct' => 'mediumblob',
		'doc' => 'Serialized list config',
		'order' => 99,
	    },
	},
	'doc' => 'The list_table holds cached list config and some items to help searching lists.',
	'order' => 18,
    },
);
return %full_db_struct;
}

## Conversion of column data types.  Basic definitions are based on MySQL.
## Following types are recognized:
## varchar(X)     : Text with length upto X.  X must be lower than 2^16 - 2.
## int(1):        : Boolean, 1 or 0.
## int(11)        : Unix time (a.k.a. "epoch").
## int(X)         : Integer with columns upto X, -2^31 to 2^31 - 1.
## tinyint        : Integer, -2^7 to 2^7 - 1.
## smallint       : Integer, -2^15 to 2^15 - 1.
## bigint         : Integer, -2^63 to 2^63 - 1.
## double         : IEEE floating point number, 8 bytes.
## enum           : Keyword with length upto 20 o.
## text           : Text with length upto 500 o.
## longtext       : Text with length upto 2^32 - 4 o.
## datetime:      : Timestamp.
## mediumblob     : Binary data with length upto 2^24 - 3 o.

sub db_struct {

  my %db_struct;
  my %full_db_struct = &full_db_struct();

  foreach my $table ( keys %full_db_struct  ) { 
      foreach my $field  ( keys %{ $full_db_struct{$table}{'fields'}  }) {
	  my $trans = $full_db_struct{$table}{'fields'}{$field}{
		'struct'};
	  my $trans_o = $trans;
	  my $trans_pg = $trans;
	  my $trans_syb = $trans;
	  my $trans_sq = $trans;
# Oracle	
	  $trans_o =~ s/^varchar/varchar2/g;	
	  $trans_o =~ s/^int.*/number/g;	
	  $trans_o =~ s/^bigint.*/number/g;	
	  $trans_o =~ s/^smallint.*/number/g;	
	  $trans_o =~ s/^double/float(24)/g;
	  $trans_o =~ s/^enum.*/varchar2(20)/g;	
	  $trans_o =~ s/^text.*/varchar2(500)/g;	
	  $trans_o =~ s/^longtext.*/long/g;	
	  $trans_o =~ s/^datetime.*/date/g;	
	  $trans_o =~ s/^mediumblob/blob/g;
#Postgresql
	  $trans_pg =~ s/^int(1)/smallint/g;
	  $trans_pg =~ s/^int\(?.*\)?/int4/g;
	  $trans_pg =~ s/^smallint.*/int4/g;
	  $trans_pg =~ s/^tinyint\(.*\)/int2/g;
	  $trans_pg =~ s/^bigint.*/int8/g;
	  $trans_pg =~ s/^double/float8/g;
	  $trans_pg =~ s/^text.*/varchar(500)/g;
	  $trans_pg =~ s/^longtext.*/text/g;
	  $trans_pg =~ s/^datetime.*/timestamptz/g;
	  $trans_pg =~ s/^enum.*/varchar(15)/g;
	  $trans_pg =~ s/^mediumblob/bytea/g;
#Sybase		
	  $trans_syb =~ s/^int.*/numeric/g;
	  $trans_syb =~ s/^text.*/varchar(500)/g;
	  $trans_syb =~ s/^smallint.*/numeric/g;
	  $trans_syb =~ s/^bigint.*/numeric/g;
	  $trans_syb =~ s/^double/double precision/g;
	  $trans_syb =~ s/^longtext.*/text/g;
	  $trans_syb =~ s/^enum.*/varchar(15)/g;
	  $trans_syb =~ s/^mediumblob/long binary/g;
#Sqlite		
	  $trans_sq =~ s/^varchar.*/text/g;
	  $trans_sq =~ s/^.*int\(1\).*/numeric/g;
	  $trans_sq =~ s/^int.*/integer/g;
	  $trans_sq =~ s/^tinyint.*/integer/g;
	  $trans_sq =~ s/^bigint.*/integer/g;
	  $trans_sq =~ s/^smallint.*/integer/g;
	  $trans_sq =~ s/^double/real/g;
	  $trans_sq =~ s/^longtext.*/text/g;
	  $trans_sq =~ s/^datetime.*/numeric/g;
	  $trans_sq =~ s/^enum.*/text/g;	 
	  $trans_sq =~ s/^mediumblob/none/g;

	  $db_struct{'mysql'}{$table}{$field} = $trans;
	  $db_struct{'Pg'}{$table}{$field} = $trans_pg;
	  $db_struct{'Oracle'}{$table}{$field} = $trans_o;
	  $db_struct{'Sybase'}{$table}{$field} = $trans_syb;
	  $db_struct{'SQLite'}{$table}{$field} = $trans_sq;
      }
  }   
  return %db_struct;
}

sub not_null {
    my %not_null;
    my %full_db_struct = &full_db_struct() ;
    my %db_struct = &db_struct() ;
    foreach my $table ( keys %full_db_struct  ) {
	foreach my $field  ( keys %{ $full_db_struct{$table}{'fields'}  }) {
	    $not_null{'$field'} = $full_db_struct{$table}{'fields'}{$field}{'not_null'}; 
	}
    }
    return %not_null;
}

sub autoincrement {
    my %autoincrement;
    my %full_db_struct = &full_db_struct() ;
    my %db_struct = &db_struct() ;
    foreach my $table ( keys %full_db_struct  ) {		
	foreach my $field  ( keys %{ $full_db_struct{$table}{'fields'}  }) {
	    $autoincrement{$table} = $field if ($full_db_struct{$table}{'fields'}{$field}{'autoincrement'}); 
	}
    }
    return %autoincrement;
}

sub primary {
    my %primary;
    my %full_db_struct = &full_db_struct() ;

    foreach my $table ( keys %full_db_struct ) {
	my @primarykey;
	foreach my $field  ( keys %{ $full_db_struct{$table}{'fields'}  }) {
	    push (@primarykey,$field) if ($full_db_struct{$table}{'fields'}{$field}{'primary'}); 
	}
	
	$primary{$table} = \@primarykey;					    
    }
    return %primary;
}

## List the required INDEXES
##   1st key is the concerned table
##   2nd key is the index name
##   the table lists the field on which the index applies
our %indexes = ('admin_table' => {'admin_user_index' => ['user_admin']},
	       'subscriber_table' => {'subscriber_user_index' => ['user_subscriber']},
	       'stat_table' => {'stats_user_index' => ['email_stat']}
	       );

# table indexes that can be removed during upgrade process
our @former_indexes = ('user_subscriber', 'list_subscriber', 'subscriber_idx', 'admin_idx', 'netidmap_idx', 'user_admin', 'list_admin', 'role_admin', 'admin_table_index', 'logs_table_index','netidmap_table_index','subscriber_table_index','user_index');

return 1;
