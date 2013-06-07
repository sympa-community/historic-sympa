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
	# subscription, subscription option, etc...
	'subscriber_table' => {
		fields => {
			# email of subscriber
			'user_subscriber' => {
				type     => 'varchar(100)',
				primary  => 1,
				not_null => 1,
				order    => 1
			},
			# list name of a subscription
			'list_subscriber' => {
				type     => 'varchar(50)',
				primary  => 1,
				not_null => 1,
				order    => 2
			},
			# robot (domain) of the list
			'robot_subscriber' => {
				type     => 'varchar(80)',
				primary  => 1,
				not_null => 1,
				order    => 3
			},
			# reception format option (digest, summary, etc.)
			'reception_subscriber' => {
				type   => 'varchar(20)',
				order  => 4,
			},
			# boolean set to 1 if subscription is suspended
			'suspend_subscriber' => {
				type   => 'int(1)',
				order  => 5,
			},
			# The date (epoch) when message reception is suspended
			'suspend_start_date_subscriber' => {
				type   => 'int(11)',
				order  => 6,
			},
			# The date (epoch) when message reception should be restored
			'suspend_end_date_subscriber' => {
				type   => 'int(11)',
				order  => 7,
			},
			'bounce_subscriber' => {
				type   => 'varchar(35)',
				order  => 8,
			},
			'bounce_score_subscriber' => {
				type   => 'smallint(6)',
				order  => 9,
			},
			'bounce_address_subscriber' => {
				type   => 'varchar(100)',
				order  => 10,
			},
			# date of subscription
			'date_subscriber' => {
				type     => 'datetime',
				not_null => 1,
				order    => 11,
			},
			# the latest date where subscription is confirmed by subscriber
			'update_subscriber' => {
				type   => 'datetime',
				order  => 12,
			},
			# free form name
			'comment_subscriber' => {
				type   => 'varchar(150)',
				order  => 13,
			},
			# the number of message the subscriber sent
			'number_messages_subscriber' => {
				type     => 'int(5)',
				not_null => 1,
				order    => 5,
				order    => 14,
			},
			'visibility_subscriber' => {
				type   => 'varchar(20)',
				order  => 15,
			},
			# topic subscription specification
			'topics_subscriber' => {
				type   => 'varchar(200)',
				order  => 16,
			},
			# boolean set to 1 if subscriber comes from ADD or SUB
			'subscribed_subscriber' => {
				type   => 'int(1)',
				order  => 17,
			},
			# boolean, set to 1 is subscriber comes from an
			# external datasource. Note that included_subscriber
			# and subscribed_subscriber can both value 1
			'included_subscriber' => {
				type   => 'int(1)',
				order  => 18,
			},
			# comma-separated list of datasource that contain this
			# subscriber
			'include_sources_subscriber' => {
				type   => 'varchar(50)',
				order  => 19,
			},
			'custom_attribute_subscriber' => {
				type   => 'text',
				order  => 10,
			},
		},
		subscriber_user_index => ['user_subscriber'],
		order => 1,
	},
	# The user_table is mainly used to manage login from web interface. A
	# subscriber may not appear in the user_table if he never log through
	# the web interface.',
	user_table => {
		fields => {
			# email user is the key
			email_user => {
				type     => 'varchar(100)' ,
				primary  => 1,
				not_null => 1,
			},
			gecos_user => {
				type  => 'varchar(150)',
				order => 3,
			},
			# password are stored as fingerprint
			password_user => {
				type  => 'varchar(40)',
				order => 2,
			},
			# date epoch from last login, printed in login result
			# for security purpose
			last_login_date_user => {
				type  => 'int(11)',
				order => 4,
			},
			# host of last login, printed in login result for
			# security purpose
			last_login_host_user => {
				type  => 'varchar(60)',
				order => 5,
			},
			# login attempt count, used to prevent brut force
			# attack
			wrong_login_count_user =>{
				type  => 'int(11)',
				order => 6,
			},
			cookie_delay_user => {
				type => 'int(11)',
			},
			# user langage preference
			lang_user => {
				type => 'varchar(10)',
			},
			attributes_user => {
				type => 'text',
			},
			data_user => {
				type => 'text',
			},
		},
		order => 2,
	},
	# message and task spools management
	spool_table => {
		fields => {
			messagekey_spool => {
				type          => 'bigint(20)',
				primary       => 1,
				not_null      => 1,
				autoincrement => 1,
				order         => 1,
			},
			# the spool name
			spoolname_spool => {
				type     => "enum('msg','auth','mod','digest','archive','bounce','subscribe','topic','bulk','validated','task')",
				not_null => 1,
				order    => 2,
			},
			list_spool=> {
				type  => 'varchar(50)',
				order => 3,
			},
			robot_spool => {
				type  => 'varchar(80)',
				order => 4,
			},
			# priority (list priority, owner pririty etc)',
			priority_spool => {
				type  => 'varchar(2)',
				order => 5,
			},
			# the date a message is copied in spool table
			date_spool => {
				type  => 'int(11)',
				order => 6,
			},
			# message as base64-encoded string
			message_spool => {
				type  => 'longtext',
				order => 7,
			},
			# a unique string for each process
			messagelock_spool => {
				type  => 'varchar(90)',
				order => 8,
			},
			# the date a lock is set. Used in order detect old
			# locks
			lockdate_spool => {
				type  => 'int(11)',
				order => 9,
			},
			# if problem when processed entries have bad status
			message_status_spool => {
				type  => "enum('ok','bad')",
				order => 10,
			},
			# the reason why a message is moved to bad
			message_diag_spool => {
				type  => 'text',
				order => 11,
			},
			# list, list-request, sympa robot or other recipient
			type_spool => {
				type  => 'varchar(15)',
				order => 12,
			},
			# authentication key for email challenge
			authkey_spool => {
				type  => 'varchar(33)',
				order => 13,
			},
			# the message header date
			headerdate_spool => {
				type  => 'varchar(80)',
				order => 14,
			},
			# true if message is related to a dynamic list, false
			# if list as been created or if list is static',
			create_list_if_needed_spool=> {
				type  => 'int(1)',
				order => 15,
			},
			# subject of the message stored to list spool content
			# faster
			subject_spool => {
				type  => 'varchar(110)',
				order => 16,
			},
			# this info is stored to browse spool content faster
			sender_spool => {
				type  => 'varchar(110)',
				order => 17,
			},
			# stored to list spool content faster
			messageid_spool => {
				type  => 'varchar(300)',
				order => 18,
			},
			# spamstatus scenario result
			spam_status_spool => {
				type  => 'varchar(12)',
				order => 19,
			},
			# info stored in order to browse spool content faster
			size_spool => {
				type  => 'int(11)',
				order => 20,
			},
			# date for a task
			task_date_spool => {
				type  => 'int(11)',
				order => 21,
			},
			# label for a task
			task_label_spool => {
				type  => 'varchar(20)',
				order => 22,
			},
			# model of related task
			task_model_spool => {
				type  => 'varchar(40)',
				order => 23,
			},
			# object of related task
			task_object_spool => {
				type  => 'varchar(50)',
				order => 24,
			},
			# private key to sign message
			dkim_privatekey_spool => {
				type  => 'varchar(1000)',
				order => 35,
			},
			# DKIM selector to sign message
			dkim_selector_spool => {
				type  => 'varchar(50)',
				order => 36,
			},
			# DKIM d parameter
			dkim_d_spool => {
				type  => 'varchar(50)',
				order => 37,
			},
			# DKIM i signature parameter
			dkim_i_spool => {
				type  => 'varchar(100)',
				order => 38,
			},
		},
		order => 3,
	},
	# storage of recipients with a ref to a message in spool_table. So a
	# very simple process can distribute them
	bulkmailer_table => {
		fields => {
			# a pointer to a message in spool_table.It must be a
			# value of a line in table spool_table with same value
			# as messagekey_spool
			messagekey_bulkmailer => {
				type     => 'varchar(80)',
				primary  => 1,
				not_null => 1,
				order    => 1,
			},
			# an id for the packet
			packetid_bulkmailer => {
				type     => 'varchar(33)',
				primary  => 1,
				not_null => 1,
				order    => 2,
			},
			# the message Id
			messageid_bulkmailer => {
				type  => 'varchar(200)',
				order => 3,
			},
			# comma-separated list of recipient email for this
			# message
			receipients_bulkmailer => {
				type  => 'text',
				order => 4,
			},
			# the return path value that must be set when sending
			# the message
			returnpath_bulkmailer => {
				type  => 'varchar(100)',
				order => 5,
			},
			robot_bulkmailer => {
				type  => 'varchar(80)',
				order => 6,
			},
			listname_bulkmailer => {
				type  => 'varchar(50)',
				order => 7,
			},
			# true if VERP is required, in this cas return_path
			# will be formated using verp form
			verp_bulkmailer => {
				type  => 'int(1)',
				order => 8,
			},
			# Is DSN or MDM required when sending this message?',
			tracking_bulkmailer => {
				type  => "enum('mdn','dsn')",
				order => 9,
			},
			# true if the message is to be parsed as a TT2
			# template foreach recipient
			merge_bulkmailer => {
				type  => 'int(1)',
				order => 10,
			},
			priority_message_bulkmailer => {
				type  => 'smallint(10)',
				order => 11,
			},
			priority_packet_bulkmailer => {
				type  => 'smallint(10)',
				order => 12,
			},
			# the date where the message was received
			'reception_date_bulkmailer' => {
				type  => 'int(11)',
				order => 13,
			},
			# the date the message was sent
			delivery_date_bulkmailer => {
				type  => 'int(11)',
				order => 14,
			},
			# a lock. It is set as process-number @ hostname so
			# multiple bulkmailer can handle this spool
			lock_bulkmailer => {
				type  => 'varchar(30)',
				order => 15,
			},
		},
		order => 4,
	},
	# exclusion table is used in order to manage unsubscription for
	# subsceriber inclued from an external data source
	exclusion_table => {
		fields => {
			list_exclusion => {
				type     => 'varchar(50)',
				order    => 1,
				primary  => 1,
				not_null => 1,
			},
			robot_exclusion => {
				type     => 'varchar(50)',
				order    => 2,
				primary  => 1,
				not_null => 1,
			},
			user_exclusion => {
				type     => 'varchar(100)',
				order    => 3,
				primary  => 1,
				not_null => 1,
			},
			family_exclusion => {
				type  => 'varchar(50)',
				order => 4,
			},
			date_exclusion => {
				type  => 'int(11)',
				order => 5,
			},
		},
		order => 5,
	},
	# HTTP session management
	session_table => {
		fields => {
			# database record identifier
			id_session => {
				type     => 'varchar(30)',
				primary  => 1,
				not_null => 1,
				order    => 1,
			},
			# the date when the session was created
			start_date_session => {
				type     => 'int(11)',
				not_null => 1,
				order    => 2,
			},
			# date epoch of the last use of this session. It is
			# used in order to expire old sessions
			date_session => {
				type     => 'int(11)',
				not_null => 1,
				order    => 3,
			},
			# IP address of the computer from which the
			# session was created
			remote_addr_session => {
				type  => 'varchar(60)',
				order => 4,
			},
			# virtual host in which the session was created
			robot_session  => {
				type  => 'varchar(80)',
				order => 5,
			},
			# email associated to this session
			email_session  => {
				type  => 'varchar(100)',
				order => 6,
			},
			# the number of hit performed during this session.
			# Used to detect crawlers
			hit_session => {
				type  => 'int(11)',
				order => 7,
			},
			# additional session parameters
			data_session  => {
				type  => 'text',
				order => 8,
			},
		},
		order => 6,
	},
	# one time ticket are random value use for authentication chalenge. A
	# ticket is associated with a context which look like a session',
	one_time_ticket_table => {
		fields => {
			ticket_one_time_ticket => {
				type    => 'varchar(30)',
				primary => 1,
			},
			email_one_time_ticket => {
				type => 'varchar(100)',
			},
			robot_one_time_ticket => {
				type => 'varchar(80)',
			},
			date_one_time_ticket => {
				type => 'int(11)',
			},
			data_one_time_ticket => {
				type => 'varchar(200)',
			},
			remote_addr_one_time_ticket => {
				type => 'varchar(60)',
			},
			status_one_time_ticket => {
				type => 'varchar(60)',
			},
		},
		order => 7,
	},
	# used for message tracking feature. If the list is configured for
	# tracking, outgoing messages include a delivery status notification
	# request and optionaly a return receipt request. When DSN MDN are
	# received by Sympa, they are store in this table in relation with the
	# related list and message_id.
	notification_table => {
		fields => {
			pk_notification => {
				type          => 'bigint(20)',
				autoincrement => 1,
				primary       => 1,
				not_null      => 1,
				order         => 1,
			},
			# initial message-id. This feild is used to search DSN
			# and MDN related to a particular message
			message_id_notification => {
				type  => 'varchar(100)',
				order => 2,
			},
			# email adresse of recipient for which a DSN or MDM
			# was received
			recipient_notification => {
				type  => 'varchar(100)',
				order => 3,
			},
			# the subscription option of the subscriber when the
			# related message was sent to the list. Ussefull
			# because some receipient may have option such as
			# //digest// or //nomail//
			reception_option_notification => {
				type  => 'varchar(20)',
				order => 4,
			},
			# Value of notification
			status_notification => {
				type  => 'varchar(100)',
				order => 5,
			},
			# reception date of latest DSN or MDM
			arrival_date_notification => {
				type  => 'varchar(80)',
				order => 6,
			},
			# type of the notification (DSN or MDM)
			type_notification => {
				type  => "enum('DSN', 'MDN')",
				order => 7,
			},
			# the DSN or the MDN itself
			'message_notification' => {
				type  => 'longtext',
				order => 8,
			},
			# the listname the message was issued for
			list_notification => {
				type  => 'varchar(50)',
				order => 9,
			},
			# the robot the message is related to
			robot_notification => {
				type  => 'varchar(80)',
				order => 10,
			},
			date_notification => {
				type     => 'int(11)',
				not_null => 1
			},
		},
		order => 8,
	},
	# each important event is stored in this table. List owners and
	# listmaster can search entries in this table using web interface.',
	logs_table => {
		fields => {
			# event key
			id_logs => {
				type     => 'bigint(20)',
				primary  => 1,
				not_null => 1,
				order    => 1,
			},
			# e-mail address of the message sender or email of
			# identified web interface user (or soap user)',
			user_email_logs => {
				type  => 'varchar(100)',
				order => 2,
			},
			# date when the action was executed',
			date_logs => {
				type     => 'int(11)',
				not_null => 1,
				order    => 3,
			},
			# name of the robot in which context the action was
			# executed
			robot_logs => {
				type  => 'varchar(80)',
				order => 4,
			},
			# name of the mailing-list in which context the action
			# was executed
			list_logs => {
				type  => 'varchar(50)',
				order => 5,
			},
			# name of the Sympa subroutine which initiated the log
			action_logs => {
				type     => 'varchar(50)',
				not_null => 1,
				order    => 6,
			},
			# List of commas-separated parameters. The amount and
			# type of parameters can differ from an action to
			# another
			parameters_logs => {
				type  => 'varchar(100)',
				order => 7,
			},
			# e-mail address (if any) targeted by the message
			target_email_logs => {
				type  => 'varchar(100)',
				order => 8,
			},
			# identifier of the message which triggered the action
			msg_id_logs => {
				type  => 'varchar(255)',
				order => 9,
			},
			# exit status of the action. If it was an error, it is
			# likely that the error_type_logs field will contain a
			# description of this error
			status_logs => {
				type     => 'varchar(10)',
				not_null => 1,
				order    => 10,
			},
			# name of the error string – if any – issued by the
			# subroutine
			error_type_logs => {
				type  => 'varchar(150)',
				order => 11,
			},
			# IP address of the client machine from which the
			# message was sent
			client_logs => {
				type  => 'varchar(100)',
				order => 12,
			},
			# name of the Sympa daemon which ran the action
			daemon_logs => {
				type     => 'varchar(10)',
				not_null => 1,
				order    => 13,
			},
		},
		order => 9,
	},
	# Statistic item are store in this table, Sum average etc are stored
	# in Stat_counter_table
	stat_table => {
		fields => {
			id_stat => {
				type     => 'bigint(20)',
				order    => 1,
				primary  => 1,
				not_null => 1,
			},
			date_stat => {
				type     => 'int(11)',
				order    => 2,
				not_null => 1,
			},
			email_stat => {
				type  => 'varchar(100)',
				order => 3,
			},
			operation_stat => {
				type     => 'varchar(50)',
				order    => 4,
				not_null => 1,
			},
			list_stat => {
				type  => 'varchar(150)',
				order => 5,
			},
			daemon_stat => {
				type  => 'varchar(10)',
				order => 6,
			},
			user_ip_stat => {
				type  => 'varchar(100)',
				order => 7,
			},
			robot_stat => {
				type     => 'varchar(80)',
				order    => 8,
				not_null => 1,
			},
			parameter_stat => {
				type  => 'varchar(50)',
				order => 9,
			},
			read_stat => {
				type     => 'tinyint(1)',
				order    => 10,
				not_null => 1,
			},
		},
		stats_user_index => ['email_stat'],
		order            => 10,
	},
	# Use in conjunction with stat_table for users statistics
	stat_counter_table => {
		fields => {
			id_counter => {
				type     => 'bigint(20)',
				order    => 1,
				primary  => 1,
				not_null => 1,
			},
			beginning_date_counter => {
				type     => 'int(11)',
				order    => 2,
				not_null => 1,
			},
			end_date_counter => {
				type  => 'int(11)',
				order => 1,
			},
			data_counter => {
				type     => 'varchar(50)',
				not_null => 1,
				order    => 3,
			},
			robot_counter => {
				type     => 'varchar(80)',
				not_null => 1,
				order    => 4,
			},
			list_counter => {
				type  => 'varchar(150)',
				order => 5,
			},
			variation_counter => {
				type  => 'int',
				order => 6,
			},
			total_counter => {
				type  => 'int',
				order => 7,
			},
		},
		order => 11,
	},
	# internal cache where list admin roles are stored
	admin_table => {
		fields => {
			# list admin email
			user_admin => {
				type     => 'varchar(100)',
				primary  => 1,
				not_null => 1,
				order    => 1,
			},
			# listname
			list_admin => {
				type     => 'varchar(50)',
				primary  => 1,
				not_null => 1,
				order    => 2,
			},
			# list domain
			robot_admin => {
				type     => 'varchar(80)',
				primary  => 1,
				not_null => 1,
				order    => 3,
			},
			# a role of this user for this list (editor, owner or
			# listmaster which a kind of list owner too
			role_admin => {
				type    => "enum('listmaster','owner','editor')",
				primary => 1,
				order   => 4,
			},
			# privilege level for this owner, value //normal// or
			# //privileged//. The related privilege are listed in
			# editlist.conf.
			profile_admin => {
				type  => "enum('privileged','normal')",
				order => 5,
			},
			# date this user become a list admin
			date_admin => {
				type     => 'datetime',
				not_null => 1,
				order    => 6,
			},
			# last update timestamp
			update_admin => {
				type  => 'datetime',
				order => 7,
			},
			# email reception option for list management messages
			reception_admin => {
				type  => 'varchar(20)',
				order => 8,
			},
			# admin user email can be hidden in the list web page
			# description',
			visibility_admin => {
				type  => 'varchar(20)',
				order => 9,
			},
			comment_admin => {
				type  => 'varchar(150)',
				order => 10,
			},
			# true if user is list admin by definition in list
			# config file
			subscribed_admin => {
				type  => 'int(1)',
				order => 11,
			},
			# true if user is admin by an external data source
			included_admin => {
				type  => 'int(1)',
				order => 12,
			},
			# external datasource name
			include_sources_admin => {
				type  => 'varchar(50)',
				order => 13,
			},
			# private information usually dedicated to listmasters
			# who needs some additional information about list
			# owners
			info_admin => {
				type  => 'varchar(150)',
				order => 14,
			},

		},
		admin_user_index => ['user_admin'],
		order            => 12,
	},
	netidmap_table => {
		fields => {
			netid_netidmap => {
				type     => 'varchar(100)',
				primary  => 1,
				not_null => 1,
				order    => 1,
			},
			serviceid_netidmap => {
				type     => 'varchar(100)',
				primary  => 1,
				not_null => 1,
				order    => 2,
			},
			email_netidmap => {
				type  => 'varchar(100)',
				order => 4,
			},
			robot_netidmap => {
				type     => 'varchar(80)',
				primary  => 1,
				not_null => 1,
				order    => 3,
			},
		},
		order => 13,
	},
	conf_table => {
		fields => {
			robot_conf => {
				type    => 'varchar(80)',
				primary => 1,
				order   => 1,
			},
			label_conf => {
				type    => 'varchar(80)',
				primary => 1,
				order   => 2,
			},
			# the parameter value
			value_conf => {
				type  => 'varchar(300)',
				order => 3,
			},
		},
		order => 14,
	},
	'oauthconsumer_sessions_table' => {
		fields => {
			user_oauthconsumer => {
				type     => 'varchar(100)',
				order    => 1,
				primary  => 1,
				not_null => 1,
			},
			provider_oauthconsumer => {
				type     => 'varchar(100)',
				order    => 2,
				primary  => 1,
				not_null => 1,
			},
			tmp_token_oauthconsumer => {
				type  => 'varchar(100)',
				order => 3,
			},
			tmp_secret_oauthconsumer => {
				type  => 'varchar(100)',
				order => 4,
			},
			access_token_oauthconsumer => {
				type  => 'varchar(100)',
				order => 5,
			},
			access_secret_oauthconsumer => {
				type  => 'varchar(100)',
				order => 6,
			},
		},
		order => 15,
	},
	oauthprovider_sessions_table => {
		fields => {
			id_oauthprovider => {
				type          => 'bigint(20)',
				order         => 1,
				primary       => 1,
				not_null      => 1,
				autoincrement => 1,
			},
			token_oauthprovider => {
				type     => 'varchar(32)',
				order    => 2,
				not_null => 1,
			},
			secret_oauthprovider => {
				type     => 'varchar(32)',
				order    => 3,
				not_null => 1,
			},
			isaccess_oauthprovider => {
				type  => 'tinyint(1)',
				order => 4,
			},
			accessgranted_oauthprovider => {
				type  => 'tinyint(1)',
				order => 5,
			},
			consumer_oauthprovider => {
				type     => 'varchar(100)',
				order    => 6,
				not_null => 1,
			},
			user_oauthprovider => {
				type  => 'varchar(100)',
				order => 7,
			},
			firsttime_oauthprovider => {
				type     => 'int(11)',
				order    => 8,
				not_null => 1,
			},
			lasttime_oauthprovider => {
				type     => 'int(11)',
				order    => 9,
				not_null => 1,
			},
			verifier_oauthprovider => {
				type  => 'varchar(32)',
				order => 10,
			},
			callback_oauthprovider => {
				type  => 'varchar(100)',
				order => 11,
			},
		},
		order => 16,
	},
	'oauthprovider_nonces_table' => {
		fields => {
			id_nonce => {
				type          => 'bigint(20)',
				order         => 1,
				primary       => 1,
				not_null      => 1,
				autoincrement => 1,
			},
			id_oauthprovider => {
				type  => 'int(11)',
				order => 2,
			},
			nonce_oauthprovider => {
				type     => 'varchar(100)',
				order    => 3,
				not_null => 1,
			},
			time_oauthprovider => {
				type  => 'int(11)',
				order => 4,
			},
		},
		order => 17,
	},
	list_table => {
		fields => {
			name_list => {
				type     => 'varchar(100)',
				order    => 1,
				primary  => 1,
				not_null => 1,
			},
			robot_list => {
				type     => 'varchar(100)',
				order    => 2,
				primary  => 1,
				not_null => 1,
			},
			path_list => {
				type  => 'varchar(100)',
				order => 3,
			},
			status_list => {
				type  => "enum('open','closed','pending','error_config','family_closed')",
				order => 4,
			},
			creation_email_list => {
				type  => 'varchar(100)',
				order => 5,
			},
			creation_epoch_list => {
				type  => 'datetime',
				order => 6,
			},
			subject_list => {
				type  => 'varchar(100)',
				order => 7,
			},
			web_archive_list => {
				type  => 'tinyint(1)',
				order => 8,
			},
			topics_list => {
				type  => 'varchar(100)',
				order => 9,
			},
			editors_list => {
				type  => 'varchar(100)',
				order => 10,
			},
			owners_list => {
				type  => 'varchar(100)',
				order => 11,
			},
		},
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
				table            => $table,
				report           => \@report,
				target_structure => $target_structure->{$table}
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

	my $table            = $params{table};
	my $report           = $params{report};
	my $target_structure = $params{target_structure};

	Sympa::Log::Syslog::do_log(
		'debug',
		'Checking primary key for table %s',
		$table
	);

	my $current_fields = $self->get_primary_key(table => $params{table});
	my $target_fields = [
		grep { $target_structure->{fields}{$_}{primary} }
		keys %{$target_structure->{fields}}
	];

	if (!$current_fields) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to check primary key, re-creating it'
		);

		my $deletion = $self->unset_primary_key(
			table => $table
		);
		push @{$report}, $deletion if $deletion;

		my $addition = $self->set_primary_key(
			table  => $table,
			fields => $target_fields
		);
		push @{$report}, $addition if $addition;

		return 1;
	}

	my $check = $self->_check_fields_list(
		current => $current_fields,
		target  => $target_fields
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
		table => $table
	);
	push @{$report}, $deletion if $deletion;

	my $addition = $self->set_primary_key(
		table  => $table,
		fields => $target_fields
	);
	push @{$report}, $addition if $addition;

	return 1;
}

sub _check_indexes {
	my ($self, %params) = @_;

	my $table            = $params{table};
	my $report           = $params{report};
	my $target_structure = $params{target_structure};

	Sympa::Log::Syslog::do_log(
		'debug',
		'Checking indexes for table %s',
		$table
	);

	my $current_indexes = $self->get_indexes(table => $table);

	# drop all former indexes
	foreach my $index (keys %{$current_indexes}) {
		Sympa::Log::Syslog::do_log('debug','Found index %s',$index);
		next unless Sympa::Tools::Data::any { $index eq $_ }
			@former_indexes;

		Sympa::Log::Syslog::do_log('notice','Removing obsolete index %s',$index);
		my $index_deletion = $self->unset_index(
			table => $table,
			index => $index
		);
		push @{$report}, $index_deletion if $index_deletion;
	}

	# create required indexes
	foreach my $index (keys %{$target_structure->{indexes}}) {

		# check index existence
		if (!$current_indexes->{$index}) {
			Sympa::Log::Syslog::do_log(
				'notice',
				'Index %s does not exist, creating it',
				$index
			);
			my $addition = $self->set_index(
				table      => $table,
				index_name => $index,
				fields     => $target_structure->{indexes}{$index}
			);
			push @{$report}, $addition if $addition;
			next;
		}

		# index exist, check it
		my $fields =
			$self->get_indexes(table => $params{table})->{$index};

		if (!$fields) {
			Sympa::Log::Syslog::do_log(
				'err',
				'Unable to check index %s, re-creating it',
				$index
			);
			my $deletion = $self->unset_index(
				table => $table,
				index => $index
			);
			push @{$report}, $deletion if $deletion;

			my $addition = $self->set_index(
				table      => $table,
				index_name => $index,
				fields     => $target_structure->{indexes}{$index}
			);
			push @{$report}, $addition if $addition;
			next;
		}

		my $check = $self->_check_fields_list(
			current => $fields,
			target  => $target_structure->{indexes}{$index}
		);

		if ($check) {
			Sympa::Log::Syslog::do_log(
				'debug',
				'Existing index %s correct, nothing to change',
				$index
			);
			next;
		}

		Sympa::Log::Syslog::do_log(
			'debug',
			'Existing index %s incorrect, re-creating it',
			$index
		);
		my $deletion = $self->unset_index(
			table => $table,
			index => $index
		);
		push @{$report}, $deletion if $deletion;

		my $addition = $self->set_index(
			table      => $table,
			index_name => $index,
			fields     => $target_structure->{indexes}{$index}
		);
		push @{$report}, $addition if $addition;
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

# $source->_check_fields_list(%parameters)
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
