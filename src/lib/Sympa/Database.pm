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

Sympa::Database - Sympa database object

=head1 DESCRIPTION

This class implements the Sympa database. This is a wrapper over a
DBI database handler object, providing caching and database-specific schema
manipulation methods.


=cut

package Sympa::Database;

use strict;

use Carp;
use English qw(-no_match_vars);

use Sympa::Log::Syslog;
use Sympa::Tools::Data;

my $singleton;

my $schema = {
	# subscription, subscription option, etc...
	'subscriber_table' => {
		fields => [
			{
				# email of subscriber
				name     => 'user_subscriber',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				# list name of a subscription
				name     => 'list_subscriber',
				type     => 'varchar(50)',
				not_null => 1,
			},
			{
				# robot (domain) of the list
				name     => 'robot_subscriber',
				type     => 'varchar(80)',
				not_null => 1,
			},
			{
				# reception format option (digest, summary, etc.)
				name => 'reception_subscriber',
				type => 'varchar(20)',
			},
			{
				# boolean set to 1 if subscription is suspended
				name => 'suspend_subscriber',
				type => 'int(1)',
			},
			{
				# The date (epoch) when message reception is suspended
				name => 'suspend_start_date_subscriber',
				type => 'int(11)',
			},
			{
				# The date (epoch) when message reception should be restored
				name => 'suspend_end_date_subscriber',
				type => 'int(11)',
			},
			{
				name => 'bounce_subscriber',
				type => 'varchar(35)',
			},
			{
				name => 'bounce_score_subscriber',
				type => 'smallint(6)',
			},
			{
				name => 'bounce_address_subscriber',
				type => 'varchar(100)',
			},
			{
				# date of subscription
				name     => 'date_subscriber',
				type     => 'datetime',
				not_null => 1,
			},
			{
				# the latest date where subscription is confirmed by subscriber
				name => 'update_subscriber',
				type => 'datetime',
			},
			{
				# free form name
				name => 'comment_subscriber',
				type => 'varchar(150)',
			},
			{
				# the number of message the subscriber sent
				name     => 'number_messages_subscriber',
				type     => 'int(5)',
				not_null => 1,
			},
			{
				name => 'visibility_subscriber',
				type => 'varchar(20)',
			},
			{
				# topic subscription specification
				name => 'topics_subscriber',
				type => 'varchar(200)',
			},
			{
				# boolean set to 1 if subscriber comes from ADD or SUB
				name => 'subscribed_subscriber',
				type => 'int(1)',
			},
			{
				# boolean, set to 1 is subscriber comes from an
				# external datasource. Note that included_subscriber
				# and subscribed_subscriber can both value 1
				name => 'included_subscriber',
				type => 'int(1)',
			},
			{
				# comma-separated list of datasource that contain this
				# subscriber
				name => 'include_sources_subscriber',
				type => 'varchar(50)',
			},
			{
				name => 'custom_attribute_subscriber',
				type => 'text',
			},
		],
		key => [
			'user_subscriber',
			'list_subscriber',
			'robot_subscriber'
		],
		indexes => {
			subscriber_user_index => ['user_subscriber'],
		},
		order => 1,
	},
	# The user_table is mainly used to manage login from web interface. A
	# subscriber may not appear in the user_table if he never log through
	# the web interface.',
	user_table => {
		fields => [
			{
				# email user is the key
				name     => 'email_user',
				type     => 'varchar(100)' ,
				not_null => 1,
			},
			{
				name => 'gecos_user',
				type => 'varchar(150)',
			},
			{
				# password are stored as fingerprint
				name => 'password_user',
				type => 'varchar(40)',
			},
			{
				# date epoch from last login, printed in login result
				# for security purpose
				name => 'last_login_date_user',
				type => 'int(11)',
			},
			{
				# host of last login, printed in login result for
				# security purpose
				name => 'last_login_host_user',
				type => 'varchar(60)',
			},
			{
				# login attempt count, used to prevent brut force
				# attack
				name => 'wrong_login_count_user',
				type => 'int(11)',
			},
			{
				name => 'cookie_delay_user',
				type => 'int(11)',
			},
			{
				# user langage preference
				name => 'lang_user',
				type => 'varchar(10)',
			},
			{
				name => 'attributes_user',
				type => 'text',
			},
			{
				name => 'data_user',
				type => 'text',
			},
		],
		key   => [ 'email_user' ],
		order => 2,
	},
	# message and task spools management
	spool_table => {
		fields => [
			{
				name          => 'messagekey_spool',
				type          => 'bigint(20)',
				not_null      => 1,
				autoincrement => 1,
			},
			{
				# the spool name
				name     => 'spoolname_spool',
				type     => "enum('msg','auth','mod','digest','archive','bounce','subscribe','topic','bulk','validated','task')",
				not_null => 1,
			},
			{
				name => 'list_spool',
				type => 'varchar(50)',
			},
			{
				name => 'robot_spool',
				type => 'varchar(80)',
			},
			{
				# priority (list priority, owner pririty etc)',
				name => 'priority_spool',
				type => 'varchar(2)',
			},
			{
				# the date a message is copied in spool table
				name => 'date_spool',
				type => 'int(11)',
			},
			{
				# message as base64-encoded string
				name => 'message_spool',
				type => 'longtext',
			},
			{
				# a unique string for each process
				name => 'messagelock_spool',
				type => 'varchar(90)',
			},
			{
				# the date a lock is set. Used in order detect old
				# locks
				name => 'lockdate_spool',
				type => 'int(11)',
			},
			{
				# if problem when processed entries have bad status
				name => 'message_status_spool',
				type => "enum('ok','bad')",
			},
			{
				# the reason why a message is moved to bad
				name => 'message_diag_spool',
				type => 'text',
			},
			{
				# list, list-request, sympa robot or other recipient
				name => 'type_spool',
				type => 'varchar(15)',
			},
			{
				# authentication key for email challenge
				name => 'authkey_spool',
				type => 'varchar(33)',
			},
			{
				# the message header date
				name => 'headerdate_spool',
				type => 'varchar(80)',
			},
			{
				# true if message is related to a dynamic list, false
				# if list as been created or if list is static',
				name => 'create_list_if_needed_spool',
				type => 'int(1)',
			},
			{
				# subject of the message stored to list spool content
				# faster
				name => 'subject_spool',
				type => 'varchar(110)',
			},
			{
				# this info is stored to browse spool content faster
				name => 'sender_spool',
				type => 'varchar(110)',
			},
			{
				# stored to list spool content faster
				name => 'messageid_spool',
				type => 'varchar(300)',
			},
			{
				# spamstatus scenario result
				name => 'spam_status_spool',
				type => 'varchar(12)',
			},
			{
				# info stored in order to browse spool content faster
				name => 'size_spool',
				type => 'int(11)',
			},
			{
				# date for a task
				name => 'task_date_spool',
				type => 'int(11)',
			},
			{
				# label for a task
				name => 'task_label_spool',
				type => 'varchar(20)',
			},
			{
				# model of related task
				name => 'task_model_spool',
				type => 'varchar(40)',
			},
			{
				# object of related task
				name => 'task_object_spool',
				type => 'varchar(50)',
			},
			{
				# private key to sign message
				name => 'dkim_privatekey_spool',
				type => 'varchar(1000)',
			},
			{
				# DKIM selector to sign message
				name => 'dkim_selector_spool',
				type => 'varchar(50)',
			},
			{
				# DKIM d parameter
				name => 'dkim_d_spool',
				type => 'varchar(50)',
			},
			{
				# DKIM i signature parameter
				name => 'dkim_i_spool',
				type => 'varchar(100)',
			},
		],
		key   => [ 'messagekey_spool' ],
		order => 3,
	},
	# storage of recipients with a ref to a message in spool_table. So a
	# very simple process can distribute them
	bulkpacket_table => {
		fields => [
			{
				# a pointer to a message in spool_table.It must be a
				# value of a line in table spool_table with same value
				# as messagekey_spool
				name     => 'messagekey_bulkpacket',
				type     => 'bigint(20)',
				not_null => 1,
			},
			{
				# an id for the packet
				name     => 'packetid_bulkpacket',
				type     => 'varchar(33)',
				not_null => 1,
			},
			{
				# the message Id
				name => 'messageid_bulkpacket',
				type => 'varchar(200)',
			},
			{
				# comma-separated list of recipient email for this
				# message
				name => 'receipients_bulkpacket',
				type => 'text',
			},
			{
				# the return path value that must be set when sending
				# the message
				name => 'returnpath_bulkpacket',
				type => 'varchar(100)',
			},
			{
				name => 'robot_bulkpacket',
				type => 'varchar(80)',
			},
			{
				name => 'listname_bulkpacket',
				type => 'varchar(50)',
			},
			{
				# true if VERP is required, in this cas return_path
				# will be formated using verp form
				name => 'verp_bulkpacket',
				type => 'int(1)',
			},
			{
				# Is DSN or MDM required when sending this message?',
				name => 'tracking_bulkpacket',
				type => "enum('mdn','dsn')",
			},
			{
				# true if the message is to be parsed as a TT2
				# template foreach recipient
				name => 'merge_bulkpacket',
				type => 'int(1)',
			},
			{
				name => 'priority_message_bulkpacket',
				type => 'smallint(10)',
			},
			{
				name => 'priority_packet_bulkpacket',
				type => 'smallint(10)',
			},
			{
				# the date where the message was received
				name => 'reception_date_bulkpacket',
				type => 'int(11)',
			},
			{
				# the date the message was sent
				name => 'delivery_date_bulkpacket',
				type => 'int(11)',
			},
			{
				# a lock. It is set as process-number @ hostname so
				# multiple bulkpacket can handle this spool
				name => 'lock_bulkpacket',
				type => 'varchar(30)',
			},
		],
		key   => [
			'messagekey_bulkpacket',
			'packetid_bulkpacket',
		],
		order => 4,
	},
	# exclusion table is used in order to manage unsubscription for
	# subsceriber inclued from an external data source
	exclusion_table => {
		fields => [
			{
				name     => 'list_exclusion',
				type     => 'varchar(50)',
				not_null => 1,
			},
			{
				name     => 'robot_exclusion',
				type     => 'varchar(50)',
				not_null => 1,
			},
			{
				name     => 'user_exclusion',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name => 'family_exclusion',
				type => 'varchar(50)',
			},
			{
				name => 'date_exclusion',
				type => 'int(11)',
			},
		],
		key => [
			'list_exclusion',
			'robot_exclusion',
			'user_exclusion',
		],
		order => 5,
	},
	# HTTP session management
	session_table => {
		fields => [
			{
				# database record identifier
				name     => 'id_session',
				type     => 'varchar(30)',
				not_null => 1,
			},
			{
				# previous identifier in the database
				name     => 'prev_id_session',
				type     => 'varchar(30)',
				doc => 'previous identifier of the database record',
			},
			{
				# the date when the session was created
				name     => 'start_date_session',
				type     => 'int(11)',
				not_null => 1,
			},
			{
				# date epoch of the last use of this session. It is
				# used in order to expire old sessions
				name     => 'date_session',
				type     => 'int(11)',
				not_null => 1,
			},
			{
				# date epoch of the last refrexh of this session. It is
				# used in order to refresh available sessions
				name     => 'refresh_date_session',
				type     => 'int(11)',
				doc => 'date epoch of the last refresh of this session. It is used in order to refresh available sessions',
			},
			{
				# IP address of the computer from which the
				# session was created
				name => 'remote_addr_session',
				type => 'varchar(60)',
			},
			{
				# virtual host in which the session was created
				name => 'robot_session',
				type => 'varchar(80)',
			},
			{
				# email associated to this session
				name => 'email_session',
				type => 'varchar(100)',
			},
			{
				# the number of hit performed during this session.
				# Used to detect crawlers
				name => 'hit_session',
				type => 'int(11)',
			},
			{
				# additional session parameters
				name => 'data_session',
				type => 'text',
			},
		],
		key => [ 'id_session' ],
		order => 6,
	},
	# one time ticket are random value use for authentication chalenge. A
	# ticket is associated with a context which look like a session',
	one_time_ticket_table => {
		fields => [
			{
				name    => 'ticket_one_time_ticket',
				type    => 'varchar(30)',
			},
			{
				name => 'email_one_time_ticket',
				type => 'varchar(100)',
			},
			{
				name => 'robot_one_time_ticket',
				type => 'varchar(80)',
			},
			{
				name => 'date_one_time_ticket',
				type => 'int(11)',
			},
			{
				name => 'data_one_time_ticket',
				type => 'varchar(200)',
			},
			{
				name => 'remote_addr_one_time_ticket',
				type => 'varchar(60)',
			},
			{
				name => 'status_one_time_ticket',
				type => 'varchar(60)',
			},
		],
		key   => [ 'ticket_one_time_ticket' ],
		order => 7,
	},
	# used for message tracking feature. If the list is configured for
	# tracking, outgoing messages include a delivery status notification
	# request and optionaly a return receipt request. When DSN MDN are
	# received by Sympa, they are store in this table in relation with the
	# related list and message_id.
	notification_table => {
		fields => [
			{
				name          => 'pk_notification',
				type          => 'bigint(20)',
				autoincrement => 1,
				not_null      => 1,
			},
			{
				# initial message-id. This feild is used to search DSN
				# and MDN related to a particular message
				name => 'message_id_notification',
				type => 'varchar(100)',
			},
			{
				# email address of recipient for which a DSN or MDM
				# was received
				name => 'recipient_notification',
				type => 'varchar(100)',
			},
			{
				# the subscription option of the subscriber when the
				# related message was sent to the list. Ussefull
				# because some receipient may have option such as
				# //digest// or //nomail//
				name => 'reception_option_notification',
				type => 'varchar(20)',
			},
			{
				# Value of notification
				name => 'status_notification',
				type => 'varchar(100)',
			},
			{
				# reception date of latest DSN or MDM
				name => 'arrival_date_notification',
				type => 'varchar(80)',
			},
			{
				# type of the notification (DSN or MDM)
				name => 'type_notification',
				type => "enum('DSN','MDN')",
			},
			{
				# the DSN or the MDN itself
				name => 'message_notification',
				type => 'longtext',
			},
			{
				# the listname the message was issued for
				name => 'list_notification',
				type => 'varchar(50)',
			},
			{
				# the robot the message is related to
				name => 'robot_notification',
				type => 'varchar(80)',
			},
			{
				name     => 'date_notification',
				type     => 'int(11)',
				not_null => 1
			},
		],
		key   => [ 'pk_notification' ],
		order => 8,
	},
	# each important event is stored in this table. List owners and
	# listmaster can search entries in this table using web interface.',
	logs_table => {
		fields => [
			{
				# event key
				name     => 'id_logs',
				type     => 'bigint(20)',
				not_null => 1,
			},
			{
				# e-mail address of the message sender or email of
				# identified web interface user (or soap user)',
				name => 'user_email_logs',
				type => 'varchar(100)',
			},
			{
				# date when the action was executed',
				name     => 'date_logs',
				type     => 'double',
				not_null => 1,
			},
			{
				# name of the robot in which context the action was
				# executed
				name => 'robot_logs',
				type => 'varchar(80)',
			},
			{
				# name of the mailing-list in which context the action
				# was executed
				name => 'list_logs',
				type => 'varchar(50)',
			},
			{
				# name of the Sympa subroutine which initiated the log
				name     => 'action_logs',
				type     => 'varchar(50)',
				not_null => 1,
			},
			{
				# List of commas-separated parameters. The amount and
				# type of parameters can differ from an action to
				# another
				name => 'parameters_logs',
				type => 'varchar(100)',
			},
			{
				# e-mail address (if any) targeted by the message
				name => 'target_email_logs',
				type => 'varchar(100)',
			},
			{
				# identifier of the message which triggered the action
				name => 'msg_id_logs',
				type => 'varchar(255)',
			},
			{
				# exit status of the action. If it was an error, it is
				# likely that the error_type_logs field will contain a
				# description of this error
				name     => 'status_logs',
				type     => 'varchar(10)',
				not_null => 1,
			},
			{
				# name of the error string – if any – issued by the
				# subroutine
				name => 'error_type_logs',
				type => 'varchar(150)',
			},
			{
				# IP address of the client machine from which the
				# message was sent
				name => 'client_logs',
				type => 'varchar(100)',
			},
			{
				# name of the Sympa daemon which ran the action
				name     => 'daemon_logs',
				type     => 'varchar(10)',
				not_null => 1,
			},
		],
		key   => [ 'id_logs' ],
		order => 9,
	},
	# Statistic item are store in this table, Sum average etc are stored
	# in Stat_counter_table
	stat_table => {
		fields => [
			{
				name     => 'id_stat',
				type     => 'bigint(20)',
				not_null => 1,
			},
			{
				name     => 'date_stat',
				type     => 'int(11)',
				not_null => 1,
			},
			{
				name => 'email_stat',
				type => 'varchar(100)',
			},
			{
				name     => 'operation_stat',
				type     => 'varchar(50)',
				not_null => 1,
			},
			{
				name => 'list_stat',
				type => 'varchar(150)',
			},
			{
				name => 'daemon_stat',
				type => 'varchar(10)',
			},
			{
				name => 'user_ip_stat',
				type => 'varchar(100)',
			},
			{
				name     => 'robot_stat',
				type     => 'varchar(80)',
				not_null => 1,
			},
			{
				name => 'parameter_stat',
				type  => 'varchar(50)',
			},
			{
				name     => 'read_stat',
				type     => 'tinyint(1)',
				not_null => 1,
			},
		],
		key     => [ 'id_stat' ],
		indexes => {
			stats_user_index => ['email_stat'],
		},
		order   => 10,
	},
	# Use in conjunction with stat_table for users statistics
	stat_counter_table => {
		fields => [
			{
				name     => 'id_counter',
				type     => 'bigint(20)',
				not_null => 1,
			},
			{
				name     => 'beginning_date_counter',
				type     => 'int(11)',
				not_null => 1,
			},
			{
				name => 'end_date_counter',
				type => 'int(11)',
			},
			{
				name     => 'data_counter',
				type     => 'varchar(50)',
				not_null => 1,
			},
			{
				name     => 'robot_counter',
				type     => 'varchar(80)',
				not_null => 1,
			},
			{
				name => 'list_counter',
				type => 'varchar(150)',
			},
			{
				name => 'variation_counter',
				type => 'int(11)',
			},
			{
				name => 'total_counter',
				type => 'int(11)',
			},
		],
		key   => [ 'id_counter' ],
		order => 11,
	},
	# internal cache where list admin roles are stored
	admin_table => {
		fields => [
			{
				# list admin email
				name     => 'user_admin',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				# listname
				name     => 'list_admin',
				type     => 'varchar(50)',
				not_null => 1,
			},
			{
				# list domain
				name     => 'robot_admin',
				type     => 'varchar(80)',
				not_null => 1,
			},
			{
				# a role of this user for this list (editor, owner or
				# listmaster which a kind of list owner too
				name => 'role_admin',
				type => "enum('listmaster','owner','editor')",
			},
			{
				# privilege level for this owner, value //normal// or
				# //privileged//. The related privilege are listed in
				# editlist.conf.
				name => 'profile_admin',
				type => "enum('privileged','normal')",
			},
			{
				# date this user become a list admin
				name     => 'date_admin',
				type     => 'datetime',
				not_null => 1,
			},
			{
				# last update timestamp
				name => 'update_admin',
				type => 'datetime',
			},
			{
				# email reception option for list management messages
				name => 'reception_admin',
				type => 'varchar(20)',
			},
			{
				# admin user email can be hidden in the list web page
				# description',
				name => 'visibility_admin',
				type => 'varchar(20)',
			},
			{
				name => 'comment_admin',
				type => 'varchar(150)',
			},
			{
				# true if user is list admin by definition in list
				# config file
				name => 'subscribed_admin',
				type => 'int(1)',
			},
			{
				# true if user is admin by an external data source
				name => 'included_admin',
				type => 'int(1)',
			},
			{
				# external datasource name
				name => 'include_sources_admin',
				type => 'varchar(50)',
			},
			{
				# private information usually dedicated to listmasters
				# who needs some additional information about list
				# owners
				name => 'info_admin',
				type => 'varchar(150)',
			},

		],
		key => [
			'user_admin',
			'list_admin',
			'robot_admin',
			'role_admin',
		],
		indexes => {
			admin_user_index => ['user_admin'],
		},
		order => 12,
	},
	netidmap_table => {
		fields => [
			{
				name     => 'netid_netidmap',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name     => 'serviceid_netidmap',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name => 'email_netidmap',
				type => 'varchar(100)',
			},
			{
				name     => 'robot_netidmap',
				type     => 'varchar(80)',
				not_null => 1,
			}
		],
		key => [
			'netid_netidmap',
			'serviceid_netidmap',
			'robot_netidmap',
		],
		order => 13,
	},
	conf_table => {
		fields => [
			{
				name    => 'robot_conf',
				type    => 'varchar(80)',
			},
			{
				name    => 'label_conf',
				type    => 'varchar(80)',
			},
			{
				# the parameter value
				name  => 'value_conf',
				type  => 'varchar(300)',
			},
		],
		key => [
			'robot_conf',
			'label_conf',
		],
		order => 14,
	},
	'oauthconsumer_sessions_table' => {
		fields => [
			{
				name     => 'user_oauthconsumer',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name     => 'provider_oauthconsumer',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name => 'tmp_token_oauthconsumer',
				type => 'varchar(100)',
			},
			{
				name => 'tmp_secret_oauthconsumer',
				type => 'varchar(100)',
			},
			{
				name => 'access_token_oauthconsumer',
				type => 'varchar(100)',
			},
			{
				name => 'access_secret_oauthconsumer',
				type => 'varchar(100)',
			},
		],
		key => [
			'user_oauthconsumer',
			'provider_oauthconsumer',
		],
		order => 15,
	},
	oauthprovider_sessions_table => {
		fields => [
			{
				name          => 'id_oauthprovider',
				type          => 'bigint(20)',
				not_null      => 1,
				autoincrement => 1,
			},
			{
				name     => 'token_oauthprovider',
				type     => 'varchar(32)',
				not_null => 1,
			},
			{
				name     => 'secret_oauthprovider',
				type     => 'varchar(32)',
				not_null => 1,
			},
			{
				name => 'isaccess_oauthprovider',
				type => 'tinyint(1)',
			},
			{
				name => 'accessgranted_oauthprovider',
				type => 'tinyint(1)',
			},
			{
				name     => 'consumer_oauthprovider',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name => 'user_oauthprovider',
				type => 'varchar(100)',
			},
			{
				name     => 'firsttime_oauthprovider',
				type     => 'int(11)',
				not_null => 1,
			},
			{
				name     => 'lasttime_oauthprovider',
				type     => 'int(11)',
				not_null => 1,
			},
			{
				name => 'verifier_oauthprovider',
				type => 'varchar(32)',
			},
			{
				name => 'callback_oauthprovider',
				type => 'varchar(100)',
			},
		],
		key => [
			'id_oauthprovider',
		],
		order => 16,
	},
	'oauthprovider_nonces_table' => {
		fields => [
			{
				name          => 'id_nonce',
				type          => 'bigint(20)',
				not_null      => 1,
				autoincrement => 1,
			},
			{
				name => 'id_oauthprovider',
				type => 'int(11)',
			},
			{
				name     => 'nonce_oauthprovider',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name => 'time_oauthprovider',
				type => 'int(11)',
			},
		],
		key   => [ 'id_nonce' ],
		order => 17,
	},
	list_table => {
		fields => [
			{
				name     => 'name_list',
				type     => 'varchar(100)',
				not_null => 1,
				doc		 => 'Name of the list',
			},
			{
				name     => 'robot_list',
				type     => 'varchar(100)',
				not_null => 1,
			},
			{
				name => 'family_list',
				type => 'varchar(100)',
				doc => 'Name of the family the list belongs to',
			},
			{
				name => 'status_list',
				type => "enum('open','closed','pending','error_config','family_closed')",
			},
			{
				name => 'creation_email_list',
				type => 'varchar(100)',
			},
			{
				name => 'creation_epoch_list',
				type => 'int(11)',
			},
			{
				name => 'update_email_list',
				type => 'varchar(100)',
			},
			{
				name => 'update_epoch_list',
				type => 'int(11)',
				'doc' => 'UNIX time when the list was updated',
			},
			{
				name => 'searchkey_list',
				type => 'varchar(255)',
				'doc' => 'Case-folded list subject to help searching',
			},
			{
				name => 'web_archive_list',
				type => 'tinyint(1)',
			},
			{
				name => 'topics_list',
				type => 'varchar(100)',
			},
			## cache management
			{
				name => 'cache_epoch_list',
				type => 'int(11)',
				'doc' => 'UNIX time of cache entry',
			},
			## admin cache
			{
				name => 'config_list',
				type => 'mediumblob',
				'doc' => 'Serialized list config',
			},
		],
		key => [
			'name_list',
			'robot_list',
		],
		order => 18,
	},
};

my @former_indexes = qw(
	user_subscriber
	list_subscriber
	subscriber_idx
	admin_idx
	netidmap_idx
	user_admin
	list_admin
	role_admin
	admin_table_index
	logs_table_index
	netidmap_table_index
	subscriber_table_index
	user_index
);

## Conversion of column data types. Basic definitions are based on MySQL.
## Following types are recognized:
## varchar(X) : Text with length upto X. X must be lower than 2^16 - 2.
## int(1): : Boolean, 1 or 0.
## int(11) : Unix time (a.k.a. "epoch").
## int(X) : Integer with columns upto X, -2^31 to 2^31 - 1.
## tinyint : Integer, -2^7 to 2^7 - 1.
## smallint : Integer, -2^15 to 2^15 - 1.
## bigint : Integer, -2^63 to 2^63 - 1.
## double : IEEE floating point number, 8 bytes.
## enum : Keyword with length upto 20 o.
## text : Text with length upto 500 o.
## longtext : Text with length upto 2^32 - 4 o.
## datetime: : Timestamp.
## mediumblob : Binary data with length upto 2^24 - 3 o.

=head1 CLASS METHODS

=over

=item Sympa::Database->create(%parameters)

Factory method to create a new L<Sympa::Database> object from a
specific subclass.

Parameters:

=over

=item C<host> => FIXME

=item C<user> => FIXME

=item C<passwd> => FIXME

=item C<db_name> => FIXME

=item C<db_type> => FIXME

=item C<db_options> => FIXME

=back

Return value:

A new L<Sympa::Database> object, or I<undef> if something went wrong.

=cut

sub create {
	my ($class, %params) = @_;

	croak "missing db_type parameter" unless $params{db_type};
	croak "missing db_name parameter" unless $params{db_name};

	Sympa::Log::Syslog::do_log('debug',"Creating new SQLSource object for RDBMS '%s'",$params{db_type});

	my $db_type = lc($params{db_type});
	my $subclass =
		$db_type eq 'mysql'  ? 'Sympa::Database::MySQL'      :
		$db_type eq 'sqlite' ? 'Sympa::Database::SQLite'     :
		$db_type eq 'pg'     ? 'Sympa::Database::PostgreSQL' :
		$db_type eq 'oracle' ? 'Sympa::Database::Oracle'     :
		$db_type eq 'sybase' ? 'Sympa::Database::Sybase'     :
		                       'Sympa::Database'             ;

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

=item Sympa::Database->new(%parameters)

Create a new L<Sympa::Database> object.

Parameters:

=over

=item C<host> => FIXME

=item C<user> => FIXME

=item C<passwd> => FIXME

=item C<db_name> => FIXME

=item C<db_type> => FIXME

=item C<db_options> => FIXME

=back

Return value:

A new L<Sympa::Database> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	croak "missing db_type parameter" unless $params{db_type};
	croak "missing db_name parameter" unless $params{db_name};

	my $self = {
		db_host     => $params{db_host},
		db_user     => $params{db_user},
		db_passwd   => $params{db_passwd},
		db_name     => $params{db_name},
		db_type     => $params{db_type},
		db_options  => $params{db_options},
	};

	bless $self, $class;
	return $self;
}

=item Sympa::Database->get_singleton()

Return the shared database instance.

Return value:

A L<Sympa::Database> object.

=cut

sub get_singleton {
	my ($class);

	return $singleton;
}

=back

=head1 INSTANCE METHODS

=over

=item $database->connect()

Connect to the database.

Parameters:

=over

=item C<keep_trying> => retry indefinitly in case of failure

=back

Return value:

A true value on success, I<undef> otherwise.

=cut

sub connect {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log('debug','Creating connection to database %s',$self->{db_name});

	## Build connect_string
	my $connect_string = $self->get_connect_string();
	$connect_string .= ';'   . $self->{db_options} if $self->{db_options};
	$connect_string .= ';port=' . $self->{db_port} if $self->{db_port};
	$self->{connect_string} = $connect_string;

	## Set environment variables
	## Used by Oracle (ORACLE_HOME)
	if ($self->{db_env}) {
		foreach my $env (split /;/,$self->{db_env}) {
			my ($key, $value) = split /=/, $env;
			$ENV{$key} = $value if ($key);
		}
	}

	$self->{dbh} = eval {
		DBI->connect(
			$connect_string,
			$self->{db_user},
			$self->{db_passwd},
			{ PrintError => 0 }
		)
	} ;
	unless ($self->{dbh}) {
		if (!$params{keep_trying}) {
			Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s', $connect_string, $self->{db_user});
			return undef;
		}

		Sympa::Log::Syslog::do_log('err','Can\'t connect to Database %s as %s, still trying...', $connect_string, $self->{db_user});

		# Loop until connect works
		my $sleep_delay = 60;
		while (1) {
			sleep $sleep_delay;
			eval {
				$self->{dbh} = DBI->connect(
					$connect_string,
					$self->{db_user},
					$self->{db_passwd},
					{ PrintError => 0 }
				)
			};
			last if $self->{dbh};
			$sleep_delay += 10;
		}
	}

	# Force field names to be lowercased
	$self->{dbh}{FetchHashKeyName} = 'NAME_lc';

	Sympa::Log::Syslog::do_log('debug','Connected to Database %s',$self->{db_name});
	return 1;
}

=item $database->disconnect()

Disconnect from the database.

=cut

sub disconnect {
	my ($self) = @_;

	foreach my $handle (values %{$self->{cache}}) {
		$handle->finish();
	}
	$self->{dbh}->disconnect() if $self->{dbh};
}

=item $database->ping()

Check if the database is still connected.

Return value:

A true value on success, false otherwise.

=cut

sub ping {
	my ($self) = @_;

	return $self->{dbh}->ping();
}

=item $database->get_schema()

FIXME.

=cut

sub get_schema {
	my ($self) = @_;

	# return native structure if already computed
	return $self->{schema} if $self->{schema};

	# otherwise compute and cache it
	my $native_schema = Sympa::Tools::Data::dup_var($schema);
	foreach my $table (values %{$schema}) {
		foreach my $field (@{$table->{fields}}) {
			$field->{type} =
				$self->_get_native_type($field->{type});
		}
	}
	$self->{schema} = $native_schema;

	return $self->{schema};
}

=item $database->probe()

FIXME.

=cut

sub probe {
	my ($self, %params) = @_;
	Sympa::Log::Syslog::do_log('debug3', 'Checking database structure');

	my @current_tables = $self->get_tables();
	my %current_tables = map { $_ => 1 } @current_tables;

	my $target_schema = $self->get_schema();
	my $report = [];

	foreach my $table (keys %{$target_schema}) {
		if ($current_tables{$table}) {
			$self->_check_table(
				table     => $table,
				structure => $target_schema->{$table},
				report    => $report,
				update    => $params{update}
			);
		} else {
			$self->_create_table(
				table     => $table,
				structure => $target_schema->{$table},
				report    => $report
			);
		}
	}

	return $report;
}

sub _create_table {
	my ($self, %params) = @_;

	my $table_creation = $self->add_table(
		table  => $params{table},
		fields => $params{structure}->{fields},
		key    => $params{structure}->{key}
	);
	push @{$params{report}}, $table_creation if $table_creation;

	foreach my $index (keys %{$params{structure}->{indexes}}) {
		my $index_creation = $self->set_index(
			table  => $params{table},
			index  => $index,
			fields => $params{structure}->{indexes}{$index}
		);
		push @{$params{report}}, $index_creation if $index_creation;
	}
}

sub _check_table {
	my ($self, %params) = @_;
	$self->_check_fields(%params);
	$self->_check_primary_key(%params);
	$self->_check_indexes(%params);
}

sub _check_fields {
	my ($self, %params) = @_;

	my $current_fields = $self->get_fields(table => $params{table});

	croak "Unable to check fields for $params{table}, aborting"
		unless $current_fields;

	foreach my $field (@{$params{structure}->{fields}}) {
		my $current_type = $current_fields->{$field->{name}};
		if ($current_type) {
			$self->_check_field(
				table        => $params{table},
				report       => $params{report},
				structure    => $field,
			       	current_type => $current_type,
				update       => $params{update},
			);
		} else {
			$self->_create_field(
				table     => $params{table},
				report    => $params{report},
				structure => $field,
			);
		}
	}
}

sub _create_field {
	my ($self, %params) = @_;

	my $field_creation = $self->add_field(
		table   => $params{table},
		field   => $params{structure}->{name},
		type    => $params{structure}->{type},
		notnull => $params{structure}->{not_null},
		autoinc => $params{structure}->{autoincrement},
	);
	push @{$params{report}}, $field_creation if $field_creation;
}

sub _check_field {
	my ($self, %params) = @_;

	$self->_check_field_type(
		table        => $params{table},
		field        => $params{structure}->{name},
		type         => $params{structure}->{type},
		not_null     => $params{structure}->{not_null},
		current_type => $params{current_type},
		update       => $params{update},
	);

	$self->_check_field_autoincrement(
		table         => $params{table},
		field         => $params{structure}->{name},
		type          => $params{structure}->{type},
		autoincrement => $params{structure}->{autoincrement},
		update        => $params{update}
	);
}

sub _check_field_type {
	my ($self, %params) = @_;

	return if $params{type} eq $params{current_type};

	croak
		"Field $params{field} in table $params{table} has type " .
		"$params{current_type} instead of expected type " .
		"$params{type}, and automatic update not allowed, aborting"
		if $params{update} ne 'auto';

	my $update = $self->update_field(
		table   => $params{table},
		field   => $params{field},
		type    => $params{type},
		notnull => $params{not_null},
	);
	push @{$params{report}}, $update if $update;
}

sub _check_field_autoincrement {
	my ($self, %params) = @_;

	return if !$params{autoincrement};
	return if $self->is_autoinc(
		table => $params{table},
		field => $params{field}
	);

	croak
		"Field $params{field} in table $params{table} not " .
		"autoincremented, and automatic update not allowed, aborting"
		if $params{update} ne 'auto';

	my $update = $self->set_autoinc(
		table => $params{table},
		field => $params{field},
		type  => $params{type}
	);
	push @{$params{report}}, $update if $update;
}

sub _check_primary_key {
	my ($self, %params) = @_;

	my $current_fields = $self->get_primary_key(table => $params{table});

	croak "Unable to check primary key for $params{table}, aborting"
		unless $current_fields;

	my $check = $self->_check_fields_list(
		current => $current_fields,
		target  => $params{structure}->{key}
	);

	if ($check) {
		Sympa::Log::Syslog::do_log(
			'debug',
			'Existing primary key correct, nothing to change',
		);
		return 1;
	}

	Sympa::Log::Syslog::do_log(
		'debug',
		'Existing primary key incorrect, re-creating it',
	);

	my $deletion = $self->unset_primary_key(
		table => $params{table}
	);
	push @{$params{report}}, $deletion if $deletion;

	my $addition = $self->set_primary_key(
		table  => $params{table},
		fields => $current_fields
	);
	push @{$params{report}}, $addition if $addition;

	return 1;
}

sub _check_indexes {
	my ($self, %params) = @_;

	my $current_indexes = $self->get_indexes(table => $params{table});

	croak "Unable to check indexes for $params{table}, aborting"
		unless $current_indexes;

	foreach my $index (keys %{$params{structure}->{indexes}}) {
		my $current_fields = $current_indexes->{$index};
		if ($current_fields) {
			$self->_check_index(
				table          => $params{table},
				index          => $params{index},
				fields         => $params{structure}->{indexes}{$index},
				current_fields => $current_fields,
			);
		} else {
			$self->_create_index(
				table  => $params{table},
				index  => $params{index},
				fields => $params{structure}->{indexes}{$index}
			);
		}
	}

	# drop former indexes
	foreach my $index (keys %{$current_indexes}) {
		Sympa::Log::Syslog::do_log('debug','Found index %s',$index);
		next unless Sympa::Tools::Data::any { $index eq $_ }
			@former_indexes;

		Sympa::Log::Syslog::do_log('notice','Removing obsolete index %s',$index);
		my $deletion = $self->unset_index(
			table => $params{table},
			index => $index
		);
		push @{$params{report}}, $deletion if $deletion;
	}
}


sub _create_index {
	my ($self, %params) = @_;

	my $addition = $self->set_index(
		table  => $params{table},
		index  => $params{index},
		fields => $params{fields}
	);
	push @{$params{report}}, $addition if $addition;
}

sub _check_index {
	my ($self, %params) = @_;

	my $check = $self->_check_fields_list(
		current => $params{current_fields},
		target  => $params{fields}
	);

	if ($check) {
		Sympa::Log::Syslog::do_log(
			'debug',
			'Existing index %s correct, nothing to change',
			$params{index}
		);
		return 1;
	}

	Sympa::Log::Syslog::do_log(
		'debug',
		'Existing index %s incorrect, re-creating it',
		$params{index}
	);

	my $deletion = $self->unset_index(
		table => $params{table},
		index => $params{index}
	);
	push @{$params{report}}, $deletion if $deletion;

	my $addition = $self->set_index(
		table  => $params{table},
		index  => $params{index},
		fields => $params{fields}
	);
	push @{$params{report}}, $addition if $addition;

	return 1;
}

=item $database->get_type()

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

=item $database->get_name()

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

=item $database->get_query_handle($query)

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

	$query =~ s/^\s+//;
	$query =~ s/\s+$//;
	return
		$self->{cache}->{$query} ||=
		$self->{dbh}->prepare($query);
}

=item $database->execute_query($query)

Execute a single SQL query.

Parameters:

=over

=item string

The SQL query.

=back

Return value:

The number of rows affected, or I<undef> if something went wrong.

=cut

sub execute_query {
	my ($self, $query, @values) = @_;

	return $self->{dbh}->do($query, undef, @values);
}

=item $database->prepare_query_log_values(@values)

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

=item $database->quote($string, $datatype)

Quote a string literal for use in query statement.

Return value:

The quoted string.

=cut

sub quote {
	my ($self, $string, $datatype) = @_;

	return $self->{dbh}->quote($string, $datatype);
}

=item $database->get_canonical_write_date($field)

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

=item $database->get_canonical_read_date($value)

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

=item $database->get_all_primary_keys()

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

	Sympa::Log::Syslog::do_log('debug','Retrieving all primary keys in database %s',$self->{db_name});
	my %found_keys = undef;
	foreach my $table ($self->get_tables()) {
		unless($found_keys{$table} = $self->get_primary_key('table'=>$table)) {
			Sympa::Log::Syslog::do_log('err','Primary key retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_keys;
}

=item $database->get_all_indexes()

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

	Sympa::Log::Syslog::do_log('debug','Retrieving all indexes in database %s',$self->{db_name});
	my %found_indexes;
	foreach my $table ($self->get_tables()) {
		unless($found_indexes{$table} = $self->get_indexes(table=>$table)) {
			Sympa::Log::Syslog::do_log('err','Index retrieval for table %s failed. Aborting.',$table);
			return undef;
		}
	}
	return \%found_indexes;
}

# $database->_check_fields_list(%parameters)
#
# Checks the compliance of an actual fields list with an expected one
# reference.
#
# Parameters:
# * current: the actual fields list
# * target: the expected one
#
# Return value:
# true if the actual fields list matched expected one,  false otherwise

sub _check_fields_list {
	my ($self, %params) = @_;

	return
		join(',', sort @{$params{current}}) eq
		join(',', sort @{$params{target}});
}

=item $database->get_connect_string()

Builds the string to be used by the DBI to connect to the database.

Parameters:

None

=item $database->get_substring_clause(%parameters)

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

=item $database->get_limit_clause(%parameters)

Returns an SQL clause to be inserted in a query.

This clause will limit the number of records returned by the query to
I<rows_count>. If I<offset> is provided, an offset of I<offset> rows is done
from the first record before selecting the rows to return.

Parameters:

=over

=item C<rows_count> => maximum number of records

=item C<offset> => rows offset (optional)

=back

=item $database->get_formatted_date()

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

=item $database->is_autoinc(%parameters)

Checks whether a field is an autoincrement field or not.

Parameters:

=over

=item C<field> => field name

=item C<table> => table name

=back

Return value:

A true value if the field is an autoincrement field, false otherwise.

=cut

sub is_autoinc {
	croak "not implemented";
}

=item $database->set_autoinc(%parameters)

Defines the field as an autoincrement field.

Parameters:

=over

=item C<field> => field name

=item C<table> => table name

=back

Return value:

A true value if the autoincrement could be set, I<undef> otherwise.

=cut

sub set_autoinc {
	croak "not implemented";
}

=item $database->get_tables()

Get the list of the tables in the database.

Parametersr:

None.

Return value:

A list of table names, or I<undef> if something went wrong.

=item $database->add_table(%parameters)

Adds a table to the database

Parameters:

=over

=item C<table> => table name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=cut

sub add_table {
	my ($self, %params) = @_;

	croak 'unable to create empty table'
		unless $params{fields} && @{$params{fields}};

	Sympa::Log::Syslog::do_log('debug','Adding table %s',$params{table});

	my $query = $self->_get_table_query(%params);
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to create table %s',
			$params{table},
		);
		return undef;
	}

	my $report = sprintf("Table %s created", $params{table});

	return $report;
}

sub _get_table_query {
	my ($self, %params) = @_;

	my @clauses =
		map { $self->_get_field_clause(%$_, table => $params{table}) }
		@{$params{fields}};
	push @clauses, $self->_get_primary_key_clause(@{$params{key}})
		if $params{key};

	my $query =
		"CREATE TABLE $params{table} (" . join(',', @clauses) . ")";
	return $query;
}

sub _get_primary_key_clause {
	my ($self, @fields) = @_;

	my $clause =
		"PRIMARY KEY (" . join(',', @fields) . ")";

	return $clause;
}

=item $database->get_fields(%parameters)

Get the list of fields in a table from the database.

Parameters:

=over

=item C<table> => table name

=back

Return value:

A list of name => value pairs as an hashref, or I<undef> if something went
wrong.

=cut

sub get_fields {
	croak "not implemented";
}

=item $database->update_field(%parameters)

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

=cut

sub update_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Updating field %s in table %s (%s, %s)',
		$params{field},
		$params{table},
		$params{type},
		$params{notnull}
	);

	my $query =
		"ALTER TABLE $params{table} " .
		"CHANGE $params{field} $params{field} $params{type}";
	$query .= ' NOT NULL' if $params{notnull};

	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to update field %s in table %s',
			$params{field},
			$params{table}
		);
		return undef;
	}

	my $report = sprintf(
		'Field %s updated in table %s',
		$params{field},
		$params{table}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

=item $database->add_field(%parameters)

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

=cut

sub add_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Adding field %s in table %s (%s, %s, %s, %s)',
		$params{field},
		$params{table},
		$params{type},
		$params{notnull},
		$params{autoinc},
		$params{primary}
	);

	# specific issues:
	# - an auto column must be defined as primary key
	# - impossible to add more than one auto column
	my $query =
		"ALTER TABLE $params{table} "     .
		"ADD $params{field} $params{type}";

	$query .= ' NOT NULL'       if $params{notnull};
	$query .= ' AUTO_INCREMENT' if $params{autoinc};
	$query .= ' PRIMARY KEY'    if $params{primary};

	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to add field %s in table %s',
			$params{field},
			$params{table},
		);
		return undef;
	}

	my $report = sprintf(
		'Field %s added in table %s',
		$params{field},
		$params{table},
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

=item $database->delete_field(%parameters)

Delete a field in a table from the database.

Parameters:

=over

=item C<table> => table name

=item C<field> => field name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=cut

sub delete_field {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Removing field %s from table %s',
		$params{field},
		$params{table}
	);

	my $query = "ALTER TABLE $params{table} DROP COLUMN $params{field}";
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to remove field %s from table %s',
			$params{field},
			$params{table},
		);
		return undef;
	}

	my $report = sprintf(
		'Field %s removed from table %s',
		$params{field},
		$params{table}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

=item $database->get_primary_key(%parameters)

Returns the list of fields being part of a table's primary key.

Parameters:

=over

=item C<table> => table name

=back

Return value:

The list of primary key fields, as an arrayref, or I<undef> if something went
wrong.

=cut

sub get_primary_key {
	croak "not implemented";
}

=item $database->unset_primary_key(%parameters)

Drops the primary key of a table.

Parameters:

=over

=item C<table> => table name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=cut

sub unset_primary_key {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Removing primary key from table %s',
		$params{table}
	);

	my $query = "ALTER TABLE $params{table} DROP PRIMARY KEY";
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to remove primary key from table %s',
			$params{table},
		);
		return undef;
	}

	my $report = sprintf(
		"Primary key removed from table %s",
		$params{table}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

=item $database->set_primary_key(%parameters)

Sets the primary key of a table.

Parameters:

=over

=item C<table> => table name

=item C<fields> => field names, as an arrayref

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=cut

sub set_primary_key {
	my ($self, %params) = @_;

	my $fields = join(',', @{$params{fields}});
	Sympa::Log::Syslog::do_log(
		'debug',
		'Setting primary key on table %s using fields %s',
		$params{table},
		$fields
	);

	my $query =
		"ALTER TABLE $params{table} ADD PRIMARY KEY ($params{fields})";
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to set primary key on table %s using fields %s',
			$params{table},
			$fields
		);
		return undef;
	}

	my $report = sprintf(
		"Primary key set on table %s using fields %s",
		$params{table},
		$fields
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

=item $database->get_indexes(%parameters)

Returns the list of indexes of a table.

Parameters:

=over

=item C<table> => table name

=back

Return value:

An hashref whose keys are the name of indexes, with hashref whose keys are the
indexed fields as values, or I<undef> if something went wrong.

=cut

sub get_indexes {
	croak "not implemented";
}

=item $database->unset_index(%parameters)

Drops an index of a table.

Parameters:

=over

=item C<table> => table name

=item C<index> => index name

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=cut

sub unset_index {
	my ($self, %params) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Removing index %s from table %s',
		$params{index},
		$params{table}
	);

	my $query = $self->_get_unset_index_query(%params);
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to remove index %s from table %s',
			$params{index},
			$params{table},
		);
		return undef;
	}

	my $report = sprintf(
		"Index %s removed from table %s",
		$params{index},
		$params{table}
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub _get_unset_index_query {
	my ($self, %params) = @_;

	return "ALTER TABLE $params{table} DROP INDEX $params{index}";
}


=item $database->set_index(%parameters)

Sets an index in a table.

Parameters:

=over

=item C<table> => table name

=item C<index> => index name

=item C<fields> => field names, as an arrayref

=back

Return value:

A report of the operation done as a string, or I<undef> if something went wrong.

=cut

sub set_index {
	my ($self, %params) = @_;

	my $fields = join(',', @{$params{fields}});
	Sympa::Log::Syslog::do_log(
		'debug',
		'Setting index %s on table %s using fields %s',
		$params{index},
		$params{table},
		$fields
	);

	my $query = $self->_get_set_index_query(%params, fields => $fields);
	my $rows = $self->{dbh}->do($query);
	unless ($rows) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to set index %s on table %s using fields %s',
			$params{index},
			$params{table},
			$fields,
		);
		return undef;
	}

	my $report = sprintf(
		"Index %s set on table %s using fields %s",
		$params{index},
		$params{table},
		$fields
	);
	Sympa::Log::Syslog::do_log('info', $report);

	return $report;
}

sub _get_set_index_query {
	my ($self, %params) = @_;

	return
		"CREATE INDEX $params{index} " .
		"ON $params{table} ($params{fields})";
}

=back

=cut

1;
