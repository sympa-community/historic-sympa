# list.pm - This module includes all list processing functions
# RCS Identication ; $Revision$ ; $Date$ 
#
# Sympa - SYsteme de Multi-Postage Automatique
# Copyrigh (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
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
# You should have received a copy of the GNU General Public License# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

package List;

use strict;
use POSIX;
use SQLSource;
use Datasource;
use LDAPSource;
use SDM;
use Robot;
use Upgrade;
use Lock;
use Task;
use Scenario;
use Fetch;
use WebAgent;
use Exporter;
use Sympaspool;
use Archive;
# xxxxxxx faut-il virer encode ? Faut en faire un use ? 
require Encode;

use VOOTConsumer;
use tt2;
use Sympa::Constants;
use Data::Dumper;

our @ISA = qw(Exporter);
our @EXPORT = qw(%list_of_lists);

use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN);

=encoding utf-8

=head1 CONSTRUCTOR

=over 4

=item new( NAME, [ ROBOT, [ OPTIONS ] ] )

 List->new();

Creates a new object which will be used for a list and
eventually loads the list if a name is given. Returns
a List object.

=over 4

=item NAME

Name of list.

=item ROBOT

Name of robot.

=item OPTIONS

Optional hashref.  See load().

=back

=back

=head1 METHODS

=over 4

=item load ( NAME, [ ROBOT, [ OPTIONS ] ] )

Loads the indicated list into the object.

=over 4

=item NAME

Name of list.

=item ROBOT

Name of robot.

=item OPTIONS

Optional hashref.  

=over 4

=item C<'just_try' =E<gt> TRUE>

Won't really load list to object.

=item C<'reload_config' =E<gt> TRUE>

Force reload config.  Cache won't be used anyway.

=item C<'skip_sync_admin' =E<gt> TRUE>

Won't synchronize owner/editor.

=item C<'force_sync_admin' =E<gt> TRUE>

Force synchronizing owner/editor.

=back

=back

=item save_config ( EMAIL )

Saves the indicated list object to the disk files.
EMAIL is the user performing save.

=item savestats ()

Saves updates the statistics file on disk.

=item update_stats( BYTES )

Updates the stats, argument is number of bytes, returns the next
sequence number. Does nothing if no stats.

=item send_sub_to_owner ( WHO, COMMENT )

Send a message to the list owners telling that someone
wanted to subscribe to the list.

=item send_to_editor ( MSG )
    
Send a Mail::Internet type object to the editor (for approval).

=item send_msg ( MSG )

Sends the Mail::Internet message to the list.

=item send_file ( FILE, USER, GECOS )

Sends the file to the USER. FILE may only be welcome for now.

=item delete_list_member ( ARRAY )

Delete the indicated users from the list.
 
=item delete_list_admin ( ROLE, ARRAY )

Delete the indicated admin user with the predefined role from the list.

=item get_cookie ()

Returns the cookie for a list, if available.

=item get_max_size ()

Returns the maximum allowed size for a message.

=item get_reply_to ()

Returns an array with the Reply-To values.

=item get_default_user_options ()

Returns a default option of the list for subscription.

=item get_real_total ()

Returns the number of subscribers to the list.
Older name is get_total().  Current version won't use cache anymore.
Use total() to get cached number.

=item get_global_user ( USER )

Returns a hash with the information regarding the indicated
user.

=item get_list_member ( USER )

Returns a subscriber of the list.

=item get_list_admin ( ROLE, USER)

Return an admin user of the list with predefined role

=item get_first_list_member ()

Returns a hash to the first user on the list.

=item get_first_list_admin ( ROLE )

Returns a hash to the first admin user with predefined role on the list.

=item get_next_list_member ()

Returns a hash to the next users, until we reach the end of
the list.

=item get_next_list_admin ()

Returns a hash to the next admin users, until we reach the end of
the list.

=item update_list_member ( USER, HASHPTR )

Sets the new values given in the hash for the user.

=item update_list_admin ( USER, ROLE, HASHPTR )

Sets the new values given in the hash for the admin user.

=item add_list_member ( USER, HASHPTR )

Adds a new user to the list. May overwrite existing
entries.

=item add_admin_user ( USER, ROLE, HASHPTR )

Adds a new admin user to the list. May overwrite existing
entries.

=item is_list_member ( USER )

Returns true if the indicated user is member of the list.
 
=item am_i ( FUNCTION, USER )

Returns true is USER has FUNCTION (owner, editor) on the
list.

=item get_state ( FLAG )

Returns the value for a flag : sig or sub.

=item may_do ( ACTION, USER )

Chcks is USER may do the ACTION for the list. ACTION can be
one of following : send, review, index, getm add, del,
reconfirm, purge.

=item is_moderated ()

Returns true if the list is moderated.

=item archive_exist ( FILE )

Returns true if the indicated file exists.

=item archive_send ( WHO, FILE )

Send the indicated archive file to the user, if it exists.

=item archive_ls ()

Returns the list of available files, if any.

=item archive_msg ( MSG )

Archives the Mail::Internet message given as argument.

=item is_archived ()

Returns true is the list is configured to keep archives of
its messages.

=item get_stats ( OPTION )

Returns either a formatted printable strings or an array whith
the statistics. OPTION can be 'text' or 'array'.

=item print_info ( FDNAME )

Print the list information to the given file descriptor, or the
currently selected descriptor.

=back

=cut

use Carp;

use IO::Scalar;
use Storable;
use Mail::Header;
use Archive;
use Language;
use Log;
use Conf;
use mail;
use Ldap;
use Time::Local;
use MIME::Entity;
use MIME::EncWords;
use MIME::Parser;
use Message;
use Family;
use PlainDigest;

## Database and SQL statement handlers
my ($sth, @sth_stack);

my %list_cache;
my %list_cache_filled = ();

## DB fields with numeric type
## We should not do quote() for these while inserting data
my %numeric_field = ('cookie_delay_user' => 1,
		     'bounce_score_subscriber' => 1,
		     'subscribed_subscriber' => 1,
		     'included_subscriber' => 1,
		     'subscribed_admin' => 1,
		     'included_admin' => 1,
		     'wrong_login_count' => 1,
		      );
		      
## List parameters defaults
my %default = ('occurrence' => '0-1',
	       'length' => 25
	       );

my @param_order = qw (subject visibility info subscribe add unsubscribe del owner owner_include
		      send editor editor_include delivery_time account topics 
		      host lang web_archive archive digest digest_max_size available_user_options 
		      default_user_options msg_topic msg_topic_keywords_apply_on msg_topic_tagging reply_to_header reply_to forced_reply_to * 
		      verp_rate tracking welcome_return_path remind_return_path user_data_source include_file include_remote_file 
		      include_list include_remote_sympa_list include_ldap_query
                      include_ldap_2level_query include_sql_query include_voot_group include_admin ttl distribution_ttl creation update 
		      status serial custom_attribute include_ldap_ca include_ldap_2level_ca include_sql_ca);

## List parameters aliases
my %alias = ('reply-to' => 'reply_to',
	     'replyto' => 'reply_to',
	     'forced_replyto' => 'forced_reply_to',
	     'forced_reply-to' => 'forced_reply_to',
	     'custom-subject' => 'custom_subject',
	     'custom-header' => 'custom_header',
	     'subscription' => 'subscribe',
	     'unsubscription' => 'unsubscribe',
	     'max-size' => 'max_size');

##############################################################
## This hash COMPLETELY defines ALL list parameters     
## It is then used to load, save, view, edit list config files
##############################################################
## List parameters format accepts the following keywords :
## format :      Regexp aplied to the configuration file entry; 
##               some common regexps are defined in %regexp
## file_format : Config file format of the parameter might not be
##               the same in memory
## split_char:   Character used to separate multiple parameters 
## length :      Length of a scalar variable ; used in web forms
## scenario :    tells that the parameter is a scenario, providing its name
## default :     Default value for the param ; may be a configuration parameter (conf)
## synonym :     Defines synonyms for parameter values (for compatibility reasons)
## gettext_unit :Unit of the parameter ; this is used in web forms and refers to translated
##               strings in PO catalogs
## occurrence :  Occurerence of the parameter in the config file
##               possible values: 0-1 | 1 | 0-n | 1-n
##               example : a list may have multiple owner 
## gettext_id :    Title reference in NLS catalogues
## description : deescription text of a parameter
## group :       Group of parameters
## obsolete :    Obsolete parameter ; should not be displayed 
##               nor saved
## obsolete_values : defined obsolete values for a parameter
##                   these values should not get proposed on the web interface edition form
## order :       Order of parameters within paragraph
## internal :    Indicates that the parameter is an internal parameter
##               that should always be saved in the config file
## field_type :  used to select passwords web input type
###############################################################
%::pinfo = (

	### Global definition page ###
	
	'subject' => {
		'group' => 'description',
		'gettext_id' => "Subject of the list",
		'format' => '.+',
		'occurrence' => '1',
		'length' => 50
	},
	
	'visibility' => {
		'group' => 'description',
		'gettext_id' => "Visibility of the list",
		'scenario' => 'visibility',
		'synonym' => {
			'public' => 'noconceal',
			'private' => 'conceal'
		}
	},
	
	'owner' => {
		'group' => 'description',
		'gettext_id' => "Owner",
		'format' => {
			'email' => {
				'order' => 1,
				'gettext_id' => "email address",
				'format' => &tools::get_regexp('email'),
				'occurrence' => '1',
				'length' => 30
			},
			'gecos' => {
				'order' => 2,
				'gettext_id' => "name",
				'format' => '.+',
				'length' => 30
			},
			'info' => {
				'order' => 3,
				'gettext_id' => "private information",
				'format' => '.+',
				'length' => 30
			},
			'profile' => {
				'order' => 4,
				'gettext_id' => "profile",
				'format' => ['privileged', 'normal'],
				'default' => 'normal'
			},
			'reception' => {
				'order' => 5,
				'gettext_id' => "reception mode",
				'format' => ['mail', 'nomail'],
				'default' => 'mail'
			},
			'visibility' => {
				'order' => 6,
				'gettext_id' => "visibility",
				'format' => ['conceal', 'noconceal'],
				'default' => 'noconceal'
			}
		},
		'occurrence' => '1-n'
	},
	
	'owner_include' => {
		'group' => 'description',,
		'gettext_id' => 'Owners defined in an external data source',
		'format' => {
			'source' => {
				'order' => 1,
				'gettext_id' => 'the datasource',
				'datasource' => 1,
				'occurrence' => '1'
			},
			'source_parameters' => {
				'order' => 2,
				'gettext_id' => 'datasource parameters',
				'format' => '.*',
				'occurrence' => '0-1'
			},
			'reception' => {
				'order' => 4,
				'gettext_id' => 'reception mode',
				'format' => ['mail', 'nomail'],
				'default' => 'mail'
			},
			'visibility' => {
				'order' => 5,
				'gettext_id' => "visibility",
				'format' => ['conceal', 'noconceal'],
				'default' => 'noconceal'
			},
			'profile' => {
				'order' => 3,
				'gettext_id' => 'profile',
				'format' => ['privileged', 'normal'],
				'default' => 'normal'
			}
		},
		'occurrence' => '0-n'
	},
	
	'editor' => {
		'group' => 'description',
		'gettext_id' => "Moderators",
		'format' => {
			'email' => {
				'order' => 1,
				'gettext_id' => "email address",
				'format' => &tools::get_regexp('email'),
				'occurrence' => '1',
				'length' => 30
			},
			'reception' => {
				'order' => 4,
				'gettext_id' => "reception mode",
				'format' => ['mail', 'nomail'],
				'default' => 'mail'
			},
			'visibility' => {
				'order' => 5,
				'gettext_id' => "visibility",
				'format' => ['conceal', 'noconceal'],
				'default' => 'noconceal'
			},
			'gecos' => {
				'order' => 2,
				'gettext_id' => "name",
				'format' => '.+',
				'length' => 30
			},
			'info' => {
				'order' => 3,
				'gettext_id' => "private information",
				'format' => '.+',
				'length' => 30
			}
		},
		'occurrence' => '0-n'
	},
	
	'editor_include' => {
		'group' => 'description',
		'gettext_id' => 'Moderators defined in an external data source',
		'format' => {
			'source' => {
				'order' => 1,
				'gettext_id' => 'the data source',
				'datasource' => 1,
				'occurrence' => '1'
			},
			'source_parameters' => {
				'order' => 2,
				'gettext_id' => 'data source parameters',
				'format' => '.*',
				'occurrence' => '0-1'
			},
			'reception' => {
				'order' => 3,
				'gettext_id' => 'reception mode',
				'format' => ['mail', 'nomail'],
				'default' => 'mail'
			},
			'visibility' => {
				'order' => 5,
				'gettext_id' => "visibility",
				'format' => ['conceal', 'noconceal'],
				'default' => 'noconceal'
			}
		},
		'occurrence' => '0-n'
	},
	
	'topics' => {
		'group' => 'description',
		'gettext_id' => "Topics for the list",
		'format' => '[\-\w]+(\/[\-\w]+)?',
		'split_char' => ',',
		'occurrence' => '0-n'
	},
	
	'host' => {
		'group' => 'description',
		'gettext_id' => "Internet domain",
		'format' => &tools::get_regexp('host'),
		'default' => {
			'conf' => 'host'
		},
		'length' => 20
	},
	
	'lang' => {
		'group' => 'description',
		'gettext_id' => "Language of the list",
		'format' => [], ## &Language::GetSupportedLanguages() called later
		'file_format' => '\w+',
		'default' => {
			'conf' => 'lang'
		}
	},
	
	'family_name' => {
		'group' => 'description',
		'gettext_id' => 'Family name',
		'format' => &tools::get_regexp('family_name'),
		'occurrence' => '0-1',
		'internal' => 1
	},
	
	'max_list_members' => {
		'group' => 'description',
		'gettext_id' => "Maximum number of list members",
		'gettext_unit' => 'list members',
		'format' => '\d+',
		'length' => 8,
		'default' => {
			'conf' => 'default_max_list_members'
		}
	},
	
	'priority' => {
		'group' => 'description',
		'gettext_id' => "Priority",
		'format' => [0..9, 'z'],
		'length' => 1,
		'default' => {
			'conf' => 'default_list_priority'
		}
	},
	
	### Sending page ###
	
	'send' => {
		'group' => 'sending',
		'gettext_id' => "Who can send messages",
		'scenario' => 'send'
	},
	
	'delivery_time' => {
		'group' => 'sending',
		'gettext_id' => "Delivery time (hh:mm)",
		'format' => '[0-2]?\d\:[0-6]\d',
		'occurrence' => '0-1',
		'length' => 5
	},
	
	'digest' => {
		'group' => 'sending',
		'gettext_id' => "Digest frequency",
		'file_format' => '\d+(\s*,\s*\d+)*\s+\d+:\d+',
		'format' => {
			'days' => {
				'order' => 1,
				'gettext_id' => "days",
				'format' => [0..6],
				'file_format' => '1|2|3|4|5|6|7',
				'occurrence' => '1-n'
			},
			'hour' => {
				'order' => 2,
				'gettext_id' => "hour",
				'format' => '\d+',
				'occurrence' => '1',
				'length' => 2
			},
			'minute' => {
				'order' => 3,
				'gettext_id' => "minute",
				'format' => '\d+',
				'occurrence' => '1',
				'length' => 2
			}
		},
	},
	
	'digest_max_size' => {
		'group' => 'sending',
		'gettext_id' => "Digest maximum number of messages",
		'gettext_unit' => 'messages',
		'format' => '\d+',
		'default' => 25,
		'length' => 2
	},
	
	'available_user_options' => {
		'group' => 'sending',
		'gettext_id' => "Available subscription options",
		'format' => {
			'reception' => {
				'gettext_id' => "reception mode",
				'format' => ['mail', 'notice', 'digest', 'digestplain', 'summary', 'nomail', 'txt', 'html', 'urlize', 'not_me'],
				'occurrence' => '1-n',
				'split_char' => ',',
				'default' => 'mail,notice,digest,digestplain,summary,nomail,txt,html,urlize,not_me'
			}
		}
	},
	
	'default_user_options' => {
		'group' => 'sending',
		'gettext_id' => "Subscription profile",
		'format' => {
			'reception' => {
				'order' => 1,
				'gettext_id' => "reception mode",
				'format' => ['digest', 'digestplain', 'mail', 'nomail', 'summary', 'notice', 'txt', 'html', 'urlize', 'not_me'],
				'default' => 'mail'
			},
			'visibility' => {
				'order' => 2,
				'gettext_id' => "visibility",
				'format' => ['conceal', 'noconceal'],
				'default' => 'noconceal'
			}
		},
	},
	
	'msg_topic' => {
		'group' => 'sending',
		'gettext_id' => "Topics for message categorization",
		'format' => {
			'name' => {
				'order' => 1	,
				'gettext_id' => "Message topic name",
				'format' => '[\-\w]+',
				'occurrence' => '1',
				'length' => 15
			}, 
			'keywords' => {
				'order' => 2,
				'gettext_id' => "Message topic keywords",
				'format' => '[^,\n]+(,[^,\n]+)*',
				'occurrence' => '0-1'
			},
			'title' => {
				'order' => 3,
				'gettext_id' => "Message topic title",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 35
			}
		},
		'occurrence' => '0-n'
	},
	
	'msg_topic_keywords_apply_on' => {
		'group' => 'sending',
		'gettext_id' => "Defines to which part of messages topic keywords are applied",
		'format' => ['subject', 'body', 'subject_and_body'],
		'occurrence' => '0-1',
		'default' => 'subject'
	},
	
	'msg_topic_tagging' => {
		'group' => 'sending',
		'gettext_id' => "Message tagging",
		'format' => ['required_sender', 'required_moderator', 'optional'],
		'occurrence' => '0-1',
		'default' => 'optional'
	},
	
	'reply_to' => {
		'group' => 'sending',
		'gettext_id' => "Reply address",
		'format' => '\S+',
		'default' => 'sender',
		'obsolete' => 1
	},
	
	'forced_reply_to' => {
		'group' => 'sending',
		'gettext_id' => "Forced reply address",
		'format' => '\S+',
		'obsolete' => 1
	},
	
	'reply_to_header' => {
		'group' => 'sending',
		'gettext_id' => "Reply address",
		'format' => {
			'value' => {
				'order' => 1,
				'gettext_id' => "value",
				'format' => ['sender', 'list', 'all', 'other_email'],
				'default' => 'sender',
				'occurrence' => '1'
			},
			'other_email' => {
				'order' => 2,
				'gettext_id' => "other email address",
				'format' => &tools::get_regexp('email')
			},
			'apply' => {
				'order' => 3,
				'gettext_id' => "respect of existing header field",
				'format' => ['forced', 'respect'],
				'default' => 'respect'
			}
		}
	},
	
	'anonymous_sender' => {
		'group' => 'sending',
		'gettext_id' => "Anonymous sender",
		'format' => '.+'
	},
	
	'custom_header' => {
		'group' => 'sending',
		'gettext_id' => "Custom header field",
		'format' => '\S+:\s+.*',
		'occurrence' => '0-n',
		'length' => 30
	},
	
	'custom_subject' => {
		'group' => 'sending',
		'gettext_id' => "Subject tagging",
		'format' => '.+',
		'length' => 15
	},
	
	'footer_type' => {
		'group' => 'sending',
		'gettext_id' => "Attachment type",
		'format' => ['mime', 'append'],
		'default' => 'mime'
	},
	
	'max_size' => {
		'group' => 'sending',
		'gettext_id' => "Maximum message size",
		'gettext_unit' => 'bytes',
		'format' => '\d+',
		'length' => 8,
		'default' => {
			'conf' => 'max_size'
		}
	},
	
	'merge_feature' => {
		'group' => 'sending',
		'gettext_id' => "Allow message personnalization",
		'format' => ['on', 'off'],
		'occurence' => '0-1',
		'default' => {
			'conf' => 'merge_feature'
		}
	},
	
	'reject_mail_from_automates_feature' => {
		'group' => 'sending',
		'gettext_id' => "Reject mail from automates (crontab, etc)?",
		'format' => ['on', 'off'],
		'occurence' => '0-1',
		'default' => {
			'conf' => 'reject_mail_from_automates_feature'
		}
	},
	
	'remove_headers' => {
		'group' => 'sending',
		'gettext_id' => 'Incoming SMTP header fields to be removed',
		'format' => '\S+',
		'default' => {
			'conf' => 'remove_headers'
		},
		'occurrence' => '0-n',
		'split_char' => ','
	},
	
	'remove_outgoing_headers' => {
		'group' => 'sending',
		'gettext_id' => 'Outgoing SMTP header fields to be removed',
		'format' => '\S+',
		'default' => {
			'conf' => 'remove_outgoing_headers'
		},
		'occurrence' => '0-n',
		'split_char' => ','
	},
	
	'rfc2369_header_fields' => {
		'group' => 'sending',
		'gettext_id' => "RFC 2369 Header fields",
		'format' => ['help', 'subscribe', 'unsubscribe', 'post', 'owner', 'archive'],
		'default' => {
			'conf' => 'rfc2369_header_fields'
		},
		'occurrence' => '0-n',
		'split_char' => ','
	},
	
	### Command page ###
	
	'info' => {
		'group' => 'command',
		'gettext_id' => "Who can view list information",
		'scenario' => 'info'
	},
	
	'subscribe' => {
		'group' => 'command',
		'gettext_id' => "Who can subscribe to the list",
		'scenario' => 'subscribe'
	},
	
	'add' => {
		'group' => 'command',
		'gettext_id' => "Who can add subscribers",
		'scenario' => 'add'
	},
	
	'unsubscribe' => {
		'group' => 'command',
		'gettext_id' => "Who can unsubscribe",
		'scenario' => 'unsubscribe'
	},
	
	'del' => {
		'group' => 'command',
		'gettext_id' => "Who can delete subscribers",
		'scenario' => 'del'
	},
	
	'invite' => {
		'group' => 'command',
		'gettext_id' => "Who can invite people",
		'scenario' => 'invite'
	},
	
	'remind' => {
		'group' => 'command',
		'gettext_id' => "Who can start a remind process",
		'scenario' => 'remind'
	},
	
	'review' => {
		'group' => 'command',
		'gettext_id' => "Who can review subscribers",
		'scenario' => 'review',
		'synonym' => {
			'open' => 'public'
		}
	},
	
	'shared_doc' => {
		'group' => 'command',
		'gettext_id' => "Shared documents",
		'format' => {
			'd_read' => {
				'order' => 1,
				'gettext_id' => "Who can view",
				'scenario' => 'd_read'
			},
			'd_edit' => {
				'order' => 2,
				'gettext_id' => "Who can edit",
				'scenario' => 'd_edit'
			},
			'quota' => {
				'order' => 3,
				'gettext_id' => "quota",
				'gettext_unit' => 'Kbytes',
				'format' => '\d+',
				'default' => {
					'conf' => 'default_shared_quota'
				},
				'length' => 8
			}
		}
	},
	
	### Archives page ###
	
	'web_archive'  => {
		'group' => 'archives',
		'gettext_id' => "Web archives",
		'format' => {
			'access' => {
				'order' => 1,
				'gettext_id' => "access right",
				'scenario' => 'access_web_archive'
			},
			'quota' => {
				'order' => 2,
				'gettext_id' => "quota",
				'gettext_unit' => 'Kbytes',
				'format' => '\d+',
				'default' => {
					'conf' => 'default_archive_quota'
				},
				'length' => 8
			},
			'max_month' => {
				'order' => 3,
				'gettext_id' => "Maximum number of month archived",
				'format' => '\d+',
				'length' => 3
			}
		}
	},
	
	'archive' => {
		'group' => 'archives',
		'gettext_id' => "Text archives",
		'format' => {
			'period' => {
				'order' => 1,
				'gettext_id' => "frequency",
				'format' => ['day', 'week', 'month', 'quarter', 'year'],
				'synonym' => {
					'weekly' => 'week'
				}
			},
			'access' => {
				'order' => 2,
				'gettext_id' => "access right",
				'format' => ['open', 'private', 'public', 'owner', 'closed'],
				'synonym' => {
					'open' => 'public'
				}
			}
		}
	},
	
	'archive_crypted_msg' => {
		'group' => 'archives',
		'gettext_id' => "Archive encrypted mails as cleartext",
		'format' => ['original', 'decrypted'],
		'default' => 'original'
	},
	
	'web_archive_spam_protection' => {
		'group' => 'archives',
		'gettext_id' => "email address protection method",
		'format' => ['cookie', 'javascript', 'at', 'none'],
		'default' => {
			'conf' => 'web_archive_spam_protection'
		}
	},
	
	### Bounces page ###
	
	'bounce' => {
		'group' => 'bounces',
		'gettext_id' => "Bounces management",
		'format' => {
			'warn_rate' => {
				'order' => 1,
				'gettext_id' => "warn rate",
				'gettext_unit' => '%',
				'format' => '\d+',
				'length' => 3,
				'default' => {
					'conf' => 'bounce_warn_rate'
				}
			},
			'halt_rate' => {
				'order' => 2,
				'gettext_id' => "halt rate",
				'gettext_unit' => '%',
				'format' => '\d+',
				'length' => 3,
				'default' => {
					'conf' => 'bounce_halt_rate'
				}
			}
		}
	},
	
	'bouncers_level1' => {
		'group' => 'bounces',
		'gettext_id' => "Management of bouncers, 1st level",
		'format' => {
			'rate' => {
				'order' => 1,
				'gettext_id' => "threshold",
				'gettext_unit' => 'points',
				'format' => '\d+',
				'length' => 2,
				'default' => {
					'conf' => 'default_bounce_level1_rate'
				}
			},
			'action' => {
				'order' => 2,
				'gettext_id' => "action for this population",
				'format' => ['remove_bouncers', 'notify_bouncers', 'none'],
				'default' => 'notify_bouncers'
			},
			'notification' => {
				'order' => 3,
				'gettext_id' => "notification",
				'format' => ['none', 'owner', 'listmaster'],
				'default' => 'owner'
			}
		}
	},
	
	'bouncers_level2' => {
		'group' => 'bounces',
		'gettext_id' => "Management of bouncers, 2nd level",
		'format' => {
			'rate' => {
				'order' => 1,
				'gettext_id' => "threshold",
				'gettext_unit' => 'points',
				'format' => '\d+',
				'length' => 2,
				'default' => {
					'conf' => 'default_bounce_level2_rate'
				},
			},
			'action' => {
				'order' => 2,
				'gettext_id' => "action for this population",
				'format' => ['remove_bouncers', 'notify_bouncers', 'none'],
				'default' => 'remove_bouncers'
			},
			'notification' => {
				'order' => 3,
				'gettext_id' => "notification",
				'format' => ['none', 'owner', 'listmaster'],
				'default' => 'owner'
			}
		}
	},
	
	'verp_rate' => {
		'group' => 'bounces',
		'gettext_id' => "percentage of list members in VERP mode",
		'format' => ['100%', '50%', '33%', '25%', '20%', '10%', '5%', '2%', '0%'],
		'default' =>  {
			'conf' => 'verp_rate'
		}
	},
	
	'tracking' => {
		'group' => 'bounces',
		'gettext_id' => "Message tracking feature",
		'format' => {
			'delivery_status_notification' => {
				'order' => 1,
				'gettext_id' => "tracking message by delivery status notification",
				'format' => ['on', 'off'],
				'default' =>  {
					'conf' => 'tracking_delivery_status_notification'
				}
			},
			'message_delivery_notification' => {
				'order' => 2,
				'gettext_id' => "tracking message by message delivery notification",
				'format' => ['on', 'on_demand', 'off'],
				'default' =>  {
					'conf' => 'tracking_message_delivery_notification'
				}
			},
			'tracking' => {
				'order' => 3 ,
				'gettext_id' => "who can view message tracking",
				'scenario' => 'tracking'
			},
			'retention_period' => {
				'order' => 4 ,
				'gettext_id' => "Tracking datas are removed after this number of days",
				'gettext_unit' => 'days',
				'format' => '\d+',
				'default' =>  {
					'conf' => 'tracking_default_retention_period'
				},
				'length' => 5
			}
		}
	},
	
	'welcome_return_path' => {
		'group' => 'bounces',
		'gettext_id' => "Welcome return-path",
		'format' => ['unique', 'owner'],
		'default' => {
			'conf' => 'welcome_return_path'
		}
	},
	
	'remind_return_path' => {
		'group' => 'bounces',
		'gettext_id' => "Return-path of the REMIND command",
		'format' => ['unique', 'owner'],
		'default' => {
			'conf' => 'remind_return_path'
		}
	},
	
	### Datasources page ###
	
	'inclusion_notification_feature' => {
		'group' => 'data_source',
		'gettext_id' => "Notify subscribers when they are included from a data source?",
		'format' => ['on', 'off'],
		'occurence' => '0-1',
		'default' => 'off',
	},
	
	'sql_fetch_timeout' => {
		'group' => 'data_source',
		'gettext_id' => "Timeout for fetch of include_sql_query",
		'gettext_unit' => 'seconds',
		'format' => '\d+',
		'length' => 6,
		'default' => {
			'conf' => 'default_sql_fetch_timeout'
		},
	},
	
	'user_data_source' => {
		'group' => 'data_source',
		'gettext_id' => "User data source",
		'format' => '\S+',
		'default' => 'include2',
		'obsolete' => 1,
	},
	
	'include_file' => {
		'group' => 'data_source',
		'gettext_id' => "File inclusion",
		'format' => '\S+',
		'occurrence' => '0-n',
		'length' => 20,
	},
	
	'include_remote_file' => {
		'group' => 'data_source',
		'gettext_id' => "Remote file inclusion",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'url' => {
				'order' => 2,
				'gettext_id' => "data location URL",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 50
			},					       
			'user' => {
				'order' => 3,
				'gettext_id' => "remote user",
				'format' => '.+',
				'occurrence' => '0-1'
			},
			'passwd' => {
				'order' => 4,
				'gettext_id' => "remote password",
				'format' => '.+',
				'field_type' => 'password',
				'occurrence' => '0-1',
				'length' => 10
			}
		},
		'occurrence' => '0-n'
	},
	
	'include_list' => {
		'group' => 'data_source',
		'gettext_id' => "List inclusion",
		'format' => &tools::get_regexp('listname').'(\@'.&tools::get_regexp('host').')?',
		'occurrence' => '0-n'
	},
	
	'include_remote_sympa_list' => {
		'group' => 'data_source',
		'gettext_id' => "remote list inclusion",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'host' => {
				'order' => 1.5,
				'gettext_id' => "remote host",
				'format' => &tools::get_regexp('host'),
				'occurrence' => '1'
			},
			'port' => {
				'order' => 2,
				'gettext_id' => "remote port",
				'format' => '\d+',
				'default' => 443,
				'length' => 4
			},
			'path' => {
				'order' => 3,
				'gettext_id' => "remote path of sympa list dump",
				'format' => '\S+',
				'occurrence' => '1',
				'length' => 20
			},
			'cert' => {
				'order' => 4,
				'gettext_id' => "certificate for authentication by remote Sympa",
				'format' => ['robot', 'list'],
				'default' => 'list'
			}
		},
		'occurrence' => '0-n'
	},
	
	'include_ldap_query' => {
		'group' => 'data_source',
		'gettext_id' => "LDAP query inclusion",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'host' => {
				'order' => 2,
				'gettext_id' => "remote host",
				'format' => &tools::get_regexp('multiple_host_with_port'),
				'occurrence' => '1'
			},
			'port' => {
				'order' => 2,
				'gettext_id' => "remote port",
				'format' => '\d+',
				'obsolete' => 1,
				'length' => 4
			},
			'use_ssl' => {
				'order' => 2.5,
				'gettext_id' => 'use SSL (LDAPS)',
				'format' => ['yes', 'no'],
				'default' => 'no'
			},
			'ssl_version' => {
				'order' => 2.6,
				'gettext_id' => 'SSL version',
				'format' => ['sslv2', 'sslv3', 'tls'],
				'default' => 'sslv3'
			},
			'ssl_ciphers' => {
				'order' => 2.7,
				'gettext_id' => 'SSL ciphers used',
				'format' => '.+',
				'default' => 'ALL',
			},
			'user' => {
				'order' => 3,
				'gettext_id' => "remote user",
				'format' => '.+'
			},
			'passwd' => {
				'order' => 3.5,
				'gettext_id' => "remote password",
				'format' => '.+',
				'field_type' => 'password',
				'length' => 10
			},
			'suffix' => {
				'order' => 4,
				'gettext_id' => "suffix",
				'format' => '.+'
			},
			'scope' => {
				'order' => 5,
				'gettext_id' => "search scope",
				'format' => ['base', 'one', 'sub'],
				'default' => 'sub'
			},
			'timeout' => {
				'order' => 6,
				'gettext_id' => "connection timeout",
				'gettext_unit' => 'seconds',
				'format' => '\w+',
				'default' => 30
			},
			'filter' => {
				'order' => 7,
				'gettext_id' => "filter",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 50
			},
			'attrs' => {
				'order' => 8,
				'gettext_id' => "extracted attribute",
				'format' => '\w+(\s*,\s*\w+)?',
				'default' => 'mail',
				'length' => 50
			},
			'select' => {
				'order' => 9,
				'gettext_id' => "selection (if multiple)",
				'format' => ['all', 'first'],
				'default' => 'first'
			},
			'nosync_time_ranges' => {
				'order' => 10,
				'gettext_id' => "Time ranges when inclusion is not allowed",
				'format' => &tools::get_regexp('time_ranges'),
				'occurrence' => '0-1'
			}
		},
		'occurrence' => '0-n'
	},
	
	'include_ldap_2level_query' => {
		'group' => 'data_source',
		'gettext_id' => "LDAP 2-level query inclusion",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'host' => {
				'order' => 2,
				'gettext_id' => "remote host",
				'format' => &tools::get_regexp('multiple_host_with_port'),
				'occurrence' => '1'
			},
			'port' => {
				'order' => 2,
				'gettext_id' => "remote port",
				'format' => '\d+',
				'obsolete' => 1,
				'length' => 4
			},
			'use_ssl' => {
				'order' => 2.5,
				'gettext_id' => 'use SSL (LDAPS)',
				'format' => ['yes', 'no'],
				'default' => 'no'
			},
			'ssl_version' => {
				'order' => 2.6,
				'gettext_id' => 'SSL version',
				'format' => ['sslv2', 'sslv3', 'tls'],
				'default' => ''
			},
			'ssl_ciphers' => {
				'order' => 2.7,
				'gettext_id' => 'SSL ciphers used',
				'format' => '.+',
				'default' => 'ALL'
			},
			'user' => {
				'order' => 3,
				'gettext_id' => "remote user",
				'format' => '.+'
			},
			'passwd' => {
				'order' => 3.5,
				'gettext_id' => "remote password",
				'format' => '.+',
				'field_type' => 'password',
				'length' => 10
			},
			'suffix1' => {
				'order' => 4,
				'gettext_id' => "first-level suffix",
				'format' => '.+'
			},
			'scope1' => {
				'order' => 5,
				'gettext_id' => "first-level search scope",
				'format' => ['base', 'one', 'sub'],
				'default' => 'sub'
			},
			'timeout1' => {
				'order' => 6,
				'gettext_id' => "first-level connection timeout",
				'gettext_unit' => 'seconds',
				'format' => '\w+',
				'default' => 30
			},
			'filter1' => {
				'order' => 7,
				'gettext_id' => "first-level filter",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 50
			},
			'attrs1' => {
				'order' => 8,
				'gettext_id' => "first-level extracted attribute",
				'format' => '\w+',
				'length' => 15
			},
			'select1' => {
				'order' => 9,
				'gettext_id' => "first-level selection",
				'format' => ['all', 'first', 'regex'],
				'default' => 'first'
			},
			'regex1' => {
				'order' => 10,
				'gettext_id' => "first-level regular expression",
				'format' => '.+',
				'default' => '',
				'length' => 50
			},
			'suffix2' => {
				'order' => 11,
				'gettext_id' => "second-level suffix template",
				'format' => '.+'
			},
			'scope2' => {
				'order' => 12,
				'gettext_id' => "second-level search scope",
				'format' => ['base', 'one', 'sub'],
				'default' => 'sub'
			},
			'timeout2' => {
				'order' => 13,
				'gettext_id' => "second-level connection timeout",
				'gettext_unit' => 'seconds',
				'format' => '\w+',
				'default' => 30
			},
			'filter2' => {
				'order' => 14,
				'gettext_id' => "second-level filter template",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 50
			},
			'attrs2' => {
				'order' => 15,
				'gettext_id' => "second-level extracted attribute",
				'format' => '\w+(\s*,\s*\w+)?',
				'default' => 'mail',
				'length' => 50
			},
			'select2' => {
				'order' => 16,
				'gettext_id' => "second-level selection",
				'format' => ['all', 'first', 'regex'],
				'default' => 'first'
			},
			'regex2' => {
				'order' => 17,
				'gettext_id' => "second-level regular expression",
				'format' => '.+',
				'default' => '',
				'length' => 50
			},
			'nosync_time_ranges' => {
				'order' => 18,
				'gettext_id' => "Time ranges when inclusion is not allowed",
				'format' => &tools::get_regexp('time_ranges'),
				'occurrence' => '0-1'
			}
		},
		'occurrence' => '0-n'
	},
	
	'include_sql_query' => {
		'group' => 'data_source',
		'gettext_id' => "SQL query inclusion",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'db_type' => {
				'order' => 1.5,
				'gettext_id' => "database type",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'host' => {
				'order' => 2,
				'gettext_id' => "remote host",
				'format' => &tools::get_regexp('host'),
				'occurrence' => '1'
			},
			'db_port' => {
				'order' => 3,
				'gettext_id' => "database port",
				'format' => '\d+'
			},
			'db_name' => {
				'order' => 4,
				'gettext_id' => "database name",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'connect_options' => {
				'order' => 4,
				'gettext_id' => "connection options",
				'format' => '.+'
			},
			'db_env' => {
				'order' => 5,
				'gettext_id' => "environment variables for database connection",
				'format' => '\w+\=\S+(;\w+\=\S+)*'
			},
			'user' => {
				'order' => 6,
				'gettext_id' => "remote user",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'passwd' => {
				'order' => 7,
				'gettext_id' => "remote password",
				'format' => '.+',
				'field_type' => 'password'
			},
			'sql_query' => {
				'order' => 8,
				'gettext_id' => "SQL query",
				'format' => &tools::get_regexp('sql_query'),
				'occurrence' => '1',
				'length' => 50
			},
			'f_dir' => {
				'order' => 9,
				'gettext_id' => "Directory where the database is stored (used for DBD::CSV only)",
				'format' => '.+'
			},
			'nosync_time_ranges' => {
				'order' => 10,
				'gettext_id' => "Time ranges when inclusion is not allowed",
				'format' => &tools::get_regexp('time_ranges'),
				'occurrence' => '0-1'
			}
		},
		'occurrence' => '0-n'
	},
	
	'include_voot_group' => {
		'group' => 'data_source',
		'gettext_id' => "VOOT group inclusion",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'user' => {
				'order' => 2,
				'gettext_id' => "user",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'provider' => {
				'order' => 3,
				'gettext_id' => "provider",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'group' => {
				'order' => 4 ,
				'gettext_id' => "group",
				'format' => '\S+',
				'occurrence' => '1'
			}
		},
		'occurrence' => '0-n'
	},
	
	'ttl' => {
		'group' => 'data_source',
		'gettext_id' => "Inclusions timeout",
		'gettext_unit' => 'seconds',
		'format' => '\d+',
		'default' => 3600,
		'length' => 6
	},
	
	'distribution_ttl' => {
		'group' => 'data_source',
		'gettext_id' => "Inclusions timeout for message distribution",
		'gettext_unit' => 'seconds',
		'format' => '\d+',
		'length' => 6
	},
	
	'include_ldap_ca' => {
		'group' => 'data_source',
		'gettext_id' => "LDAP query custom attribute",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'host' => {
				'order' => 2,
				'gettext_id' => "remote host",
				'format' => &tools::get_regexp('multiple_host_with_port'),
				'occurrence' => '1'
			},
			'port' => {
				'order' => 2,
				'gettext_id' => "remote port",
				'format' => '\d+',
				'obsolete' => 1,
				'length' => 4
			},
			'use_ssl' => {
				'order' => 2.5,
				'gettext_id' => 'use SSL (LDAPS)',
				'format' => ['yes', 'no'],
				'default' => 'no'
			},
			'ssl_version' => {
				'order' => 2.6,
				'gettext_id' => 'SSL version',
				'format' => ['sslv2', 'sslv3', 'tls'],
				'default' => 'sslv3'
			},
			'ssl_ciphers' => {
				'order' => 2.7,
				'gettext_id' => 'SSL ciphers used',
				'format' => '.+',
				'default' => 'ALL'
			},
			'user' => {
				'order' => 3,
				'gettext_id' => "remote user",
				'format' => '.+'
			},
			'passwd' => {
				'order' => 3.5,
				'gettext_id' => "remote password",
				'format' => '.+',
				'field_type' => 'password',
				'length' => 10
			},
			'suffix' => {
				'order' => 4,
				'gettext_id' => "suffix",
				'format' => '.+'
			},
			'scope' => {
				'order' => 5,
				'gettext_id' => "search scope",
				'format' => ['base', 'one', 'sub'],
				'default' => 'sub'
			},
			'timeout' => {
				'order' => 6,
				'gettext_id' => "connection timeout",
				'gettext_unit' => 'seconds',
				'format' => '\w+',
				'default' => 30
			},
			'filter' => {
				'order' => 7,
				'gettext_id' => "filter",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 50
			},
			'attrs' => {
				'order' => 8,
				'gettext_id' => "extracted attribute",
				'format' => '\w+',
				'default' => 'mail',
				'length' => 15
			},
			'email_entry' => {
				'order' => 9,
				'gettext_id' => "Name of email entry",
				'format' => '\S+',
				'occurence' => '1'
			},
			'select' => {
				'order' => 10,
				'gettext_id' => "selection (if multiple)",
				'format' => ['all', 'first'],
				'default' => 'first'
			},
			'nosync_time_ranges' => {
				'order' => 11,
				'gettext_id' => "Time ranges when inclusion is not allowed",
				'format' => &tools::get_regexp('time_ranges'),
				'occurrence' => '0-1'
			}
		},
		'occurrence' => '0-n'
	},
	
	'include_ldap_2level_ca' => {
		'group' => 'data_source',
		'gettext_id' => "LDAP 2-level query custom attribute",
		'format' => {
			'name' => {
				'format' => '.+',
				'gettext_id' => "short name for this source",
				'length' => 15,
				'order' => 1,
			},
			'host' => {
				'order' => 1,
				'gettext_id' => "remote host",
				'format' => &tools::get_regexp('multiple_host_with_port'),
				'occurrence' => '1'
			},
			'port' => {
				'order' => 2,
				'gettext_id' => "remote port",
				'format' => '\d+',
				'obsolete' => 1,
				'length' => 4
			},
			'use_ssl' => {
				'order' => 2.5,
				'gettext_id' => 'use SSL (LDAPS)',
				'format' => ['yes', 'no'],
				'default' => 'no'
			},
			'ssl_version' => {
				'order' => 2.6,
				'gettext_id' => 'SSL version',
				'format' => ['sslv2', 'sslv3', 'tls'],
				'default' => ''
			},
			'ssl_ciphers' => {
				'order' => 2.7,
				'gettext_id' => 'SSL ciphers used',
				'format' => '.+',
				'default' => 'ALL'
			},
			'user' => {
				'order' => 3,
				'gettext_id' => "remote user",
				'format' => '.+',
			},
			'passwd' => {
				'order' => 3.5,
				'gettext_id' => "remote password",
				'format' => '.+',
				'field_type' => 'password',
				'length' => 10
			},
			'suffix1' => {
				'order' => 4,
				'gettext_id' => "first-level suffix",
				'format' => '.+'
			},
			'scope1' => {
				'order' => 5,
				'gettext_id' => "first-level search scope",
				'format' => ['base', 'one', 'sub'],
				'default' => 'sub'
			},
			'timeout1' => {
				'order' => 6,
				'gettext_id' => "first-level connection timeout",
				'gettext_unit' => 'seconds',
				'format' => '\w+',
				'default' => 30
			},
			'filter1' => {
				'order' => 7,
				'gettext_id' => "first-level filter",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 50
			},
			'attrs1' => {
				'order' => 8,
				'gettext_id' => "first-level extracted attribute",
				'format' => '\w+',
				'length' => 15
			},
			'select1' => {
				'order' => 9,
				'gettext_id' => "first-level selection",
				'format' => ['all', 'first', 'regex'],
				'default' => 'first'
			},
			'regex1' => {
				'order' => 10,
				'gettext_id' => "first-level regular expression",
				'format' => '.+',
				'default' => '',
				'length' => 50
			},
			'suffix2' => {
				'order' => 11,
				'gettext_id' => "second-level suffix template",
				'format' => '.+'
			},
			'scope2' => {
				'order' => 12,
				'gettext_id' => "second-level search scope",
				'format' => ['base', 'one', 'sub'],
				'default' => 'sub'
			},
			'timeout2' => {
				'order' => 13,
				'gettext_id' => "second-level connection timeout",
				'gettext_unit' => 'seconds',
				'format' => '\w+',
				'default' => 30
			},
			'filter2' => {
				'order' => 14,
				'gettext_id' => "second-level filter template",
				'format' => '.+',
				'occurrence' => '1',
				'length' => 50
			},
			'attrs2' => {
				'order' => 15,
				'gettext_id' => "second-level extracted attribute",
				'format' => '\w+',
				'default' => 'mail',
				'length' => 15
			},
			'select2' => {
				'order' => 16,
				'gettext_id' => "second-level selection",
				'format' => ['all', 'first', 'regex'],
				'default' => 'first'
			},
			'regex2' => {
				'order' => 17,
				'gettext_id' => "second-level regular expression",
				'format' => '.+',
				'default' => '',
				'length' => 50
			},
			'email_entry' => {
				'order' => 18,
				'gettext_id' => "Name of email entry",
				'format' => '\S+',
				'occurence' => '1'
			},
			'nosync_time_ranges' => {
				'order' => 19,
				'gettext_id' => "Time ranges when inclusion is not allowed",
				'format' => &tools::get_regexp('time_ranges'),
				'occurrence' => '0-1'
			}
		},
		'occurrence' => '0-n'
	},
	
	'include_sql_ca' => {
		'group' => 'data_source',
		'gettext_id' => "SQL query custom attribute",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => "short name for this source",
				'format' => '.+',
				'length' => 15
			},
			'db_type' => {
				'order' => 1.5,
				'gettext_id' => "database type",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'host' => {
				'order' => 2,
				'gettext_id' => "remote host",
				'format' => &tools::get_regexp('host'),
				'occurrence' => '1'
			},
			'db_port' => {
				'order' => 3 ,
				'gettext_id' => "database port",
				'format' => '\d+'
			},
			'db_name' => {
				'order' => 4 ,
				'gettext_id' => "database name",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'connect_options' => {
				'order' => 4.5,
				'gettext_id' => "connection options",
				'format' => '.+'
			},
			'db_env' => {
				'order' => 5,
				'gettext_id' => "environment variables for database connection",
				'format' => '\w+\=\S+(;\w+\=\S+)*'
			},
			'user' => {
				'order' => 6,
				'gettext_id' => "remote user",
				'format' => '\S+',
				'occurrence' => '1'
			},
			'passwd' => {
				'order' => 7,
				'gettext_id' => "remote password",
				'format' => '.+',
				'field_type' => 'password'
			},
			'sql_query' => {
				'order' => 8,
				'gettext_id' => "SQL query",
				'format' => &tools::get_regexp('sql_query'),
				'occurrence' => '1',
				'length' => 50
			},
			'f_dir' => {
				'order' => 9,
				'gettext_id' => "Directory where the database is stored (used for DBD::CSV only)",
				'format' => '.+'
			},
			'email_entry' => {
				'order' => 10,
				'gettext_id' => "Name of email entry",
				'format' => '\S+',
				'occurence' => '1'
			},
			'nosync_time_ranges' => {
				'order' => 11,
				'gettext_id' => "Time ranges when inclusion is not allowed",
				'format' => &tools::get_regexp('time_ranges'),
				'occurrence' => '0-1'
			}
		},
		'occurrence' => '0-n'
	},
	
	### DKIM page ###
	
	'dkim_feature' => {
		'group' => 'dkim',
		'gettext_id' => "Insert DKIM signature to messages sent to the list",
		'comment' =>  "Enable/Disable DKIM. This feature require Mail::DKIM to installed and may be some custom scenario to be updated",
		'format' => ['on', 'off'],
		'occurence' => '0-1',
		'default' => {
			'conf' => 'dkim_feature'
		}
	},
	
	'dkim_parameters' => {
		'group' => 'dkim',
		'gettext_id' => "DKIM configuration",
		'comment' => 'A set of parameters in order to define outgoing DKIM signature', 
		'format' => {
			'private_key_path' => {
				'order' => 1,
				'gettext_id' => "File path for list DKIM private key",
				'comment' => "The file must contain a RSA pem encoded private key", 
				'format' => '\S+',
				'occurence' => '0-1',
				'default' => {
					'conf' => 'dkim_private_key_path'
				}
			},
			'selector' => {
				'order' => 2,
				'gettext_id' => "Selector for DNS lookup of DKIM public key",
				'comment' => "The selector is used in order to build the DNS query for public key. It is up to you to choose the value you want but verify that you can query the public DKIM key for <selector>._domainkey.your_domain",
				'format' => '\S+',
				'occurence' => '0-1',
				'default' => {
					'conf' => 'dkim_selector'
				}
			},
			'header_list' => {
				'order' => 4,
				'gettext_id' => 'List of headers to be included ito the message for signature',
				'comment' => 'You should probably use teh default value which is the value recommended by RFC4871',
				'format' => '\S+',
				'occurence' => '0-1',
				'default' => {
					'conf' => 'dkim_header_list'
				}
			},
			'signer_domain' => {
				'order' => 5,
				'gettext_id' => 'DKIM "d=" tag, you should probably use the default value',
				'comment' => ' The DKIM "d=" tag, is the domain of the signing entity. the list domain MUST must be included in the "d=" domain',
				'format' => '\S+',
				'occurence' => '0-1',
				'default' => {
					'conf' => 'dkim_signer_domain'
				}
			},
			'signer_identity' => {
				'order' => 6,
				'gettext_id' => 'DKIM "i=" tag, you should probably leave this parameter empty',
				'comment' => 'DKIM "i=" tag, you should probably not use this parameter, as recommended by RFC 4871, default for list brodcasted messages is i=<listname>-request@<domain>',
				'format' => '\S+',
				'occurence' => '0-1'
			},
		},
		'occurrence' => '0-1'
	},
	
	'dkim_signature_apply_on' => {
		'group' => 'dkim',
		'gettext_id' => "The categories of messages sent to the list that will be signed using DKIM.",
		'comment' => "This parameter controls in which case messages must be signed using DKIM, you may sign every message choosing 'any' or a subset. The parameter value is a comma separated list of keywords",
		'format' => ['md5_authenticated_messages', 'smime_authenticated_messages', 'dkim_authenticated_messages', 'editor_validated_messages', 'none', 'any'],
		'occurrence' => '0-n',
		'split_char' => ',',
		'default' => {
			'conf' => 'dkim_signature_apply_on'
		}
	},
	
	### Others page ###
	
	'account' => {
		'group' => 'other',
		'gettext_id' => "Account",
		'format' => '\S+',
		'length' => 10
	},
	
	'clean_delay_queuemod' => {
		'group' => 'other',
		'gettext_id' => "Expiration of unmoderated messages",
		'gettext_unit' => 'days',
		'format' => '\d+',
		'length' => 3,
		'default' => {
			'conf' => 'clean_delay_queuemod'
		}
	},
	
	'cookie' => {
		'group' => 'other',
		'gettext_id' => "Secret string for generating unique keys",
		'format' => '\S+',
		'length' => 15,
		'default' => {
			'conf' => 'cookie'
		}
	},
	
	'custom_vars' => {
		'group' => 'other',
		'gettext_id' => "custom parameters",
		'format' => {
			'name' => {
				'order' => 1,
				'gettext_id' => 'var name',
				'format' => '\S+',
				'occurrence' => '1'
			},
			'value' => {
				'order' => 2,
				'gettext_id' => 'var value',
				'format' => '\S+',
				'occurrence' => '1',
			}
		},
		'occurrence' => '0-n'
	},
	
	'expire_task' => {
		'group' => 'other',
		'gettext_id' => "Periodical subscription expiration task",
		'task' => 'expire'
	},
	
	'latest_instantiation' => {
		'group' => 'other',
		'gettext_id' => 'Latest family instantiation',
		'format' => {
			'email' => {
				'order' => 1,
				'gettext_id' => 'who ran the instantiation',
				'format' => 'listmaster|'.&tools::get_regexp('email'),
				'occurrence' => '0-1'
			},
			'date' => {
				'order' => 2,
				'gettext_id' => 'date',
				'format' => '.+'
			},
			'date_epoch' => {
				'order' => 3,
				'gettext_id' => 'epoch date',
				'format' => '\d+',
				'occurrence' => '1'
			}
		},
		'internal' => 1
	},
	
	'loop_prevention_regex' => {
		'group' => 'other',
		'gettext_id' => "Regular expression applied to prevent loops with robots",
		'format' => '\S*',
		'length' => 70,
		'default' => {
			'conf' => 'loop_prevention_regex'
		}
	},
	
	'pictures_feature' => {
		'group' => 'other',
		'gettext_id' => "Allow picture display? (must be enabled for the current robot)",
		'format' => ['on', 'off'],
		'occurence' => '0-1',
		'default' => {
			'conf' => 'pictures_feature'
		}
	},
	
	'remind_task' => {
		'group' => 'other',
		'gettext_id' => 'Periodical subscription reminder task',
		'task' => 'remind',
		'default' => {
			'conf' => 'default_remind_task'
		}
	},
	
	'spam_protection' => {
		'group' => 'other',
		'gettext_id' => "email address protection method",
		'format' => ['at', 'javascript', 'none'],
		'default' => 'javascript'
	},
	
	'creation' => {
		'group' => 'other',
		'gettext_id' => "Creation of the list",
		'format' => {
			'date_epoch' => {
				'order' => 3,
				'gettext_id' => "epoch date",
				'format' => '\d+',
				'occurrence' => '1'
			},
			'date' => {
				'order' => 2,
				'gettext_id' => "human readable",
				'format' => '.+'
			},
			'email' => {
				'order' => 1,
				'gettext_id' => "who created the list",
				'format' => 'listmaster|'.&tools::get_regexp('email'),
				'occurrence' => '1'
			}
		},
		'occurrence' => '0-1',
		'internal' => 1
	},
	
	'update' => {
		'group' => 'other',
		'gettext_id' => "Last update of config",
		'format' => {
			'email' => {
				'order' => 1,
				'gettext_id' => 'who updated the config',
				'format' => '(listmaster|automatic|'.&tools::get_regexp('email').')',
				'occurrence' => '0-1',
				'length' => 30
			},
			'date' => {
				'order' => 2,
				'gettext_id' => 'date',
				'format' => '.+',
				'length' => 30
			},
			'date_epoch' => {
				'order' => 3,
				'gettext_id' => 'epoch date',
				'format' => '\d+',
				'occurrence' => '1',
				'length' => 8
			}
		},
		'internal' => 1,
	},
	
	'status' => {
		'group' => 'other',
		'gettext_id' => "Status of the list",
		'format' => ['open', 'closed', 'pending', 'error_config', 'family_closed'],
		'default' => 'open',
		'internal' => 1
	},
	
	'serial' => {
		'group' => 'other',
		'gettext_id' => "Serial number of the config",
		'format' => '\d+',
		'default' => 0,
		'internal' => 1,
		'length' => 3
	},
	
	'custom_attribute' => {
		'group' => 'other',
		'gettext_id' => "Custom user attributes",
		'format' => {
			'id' => {
				'order' =>1,
				'gettext_id' => "internal identifier",
				'format' => '\w+',
				'occurrence' => '1',
				'length' => 20
			},
			'name' => {
				'order' => 2,
				'gettext_id' => "label",
				'format' => '.+',
				'occurrence' => '1',
				'length' =>30
			},
			'comment' => {
				'order' => 3,
				'gettext_id' => "additional comment",
				'format' => '.+',
				'length' => 100
			},
			'type' => {
				'order' => 4,
				'gettext_id' => "type",
				'format' => ['string', 'text', 'integer', 'enum'],
				'default' => 'string',
				'occurence' => 1
			},
			'enum_values' => {
				'order' => 5,
				'gettext_id' => "possible attribute values (if enum is used)",
				'format' => '.+',
				'length' => 100
			},
			'optional' => {
				'order' => 6,
				'gettext_id' => "is the attribute optional?",
				'format' => ['required', 'optional']
			}
		},
		'occurrence' => '0-n'
	}
);

## This is the generic hash which keeps all lists in memory.
my %list_of_lists = ();
my %list_of_robots = ();
our %list_of_topics = ();
my %edit_list_conf = ();

## Last modification times
my %mtime;

use Fcntl;
use DB_File;

$DB_BTREE->{compare} = \&_compare_addresses;

our %listmaster_messages_stack;

## Creates an object.
sub new {
    &Log::do_log('debug2', '(%s, %s, %s, %s)', @_);

    ## NOTICE: Don't use accessors like "$self->dir" but "$self->{'dir'}",
    ## since the object has not been fully initialized yet.

    my $pkg = shift;
    my $name = shift;
    my $robot = shift;
    my $options = shift || {};
    my $list;

    ## Allow robot in the name
    if ($name =~ /\@/) {
	my @parts = split /\@/, $name;
	$robot ||= $parts[1];
	$name = $parts[0];
    }

    ## Look for the list if no robot was provided
    $robot ||= &search_list_among_robots($name);

    unless ($robot) {
	&Log::do_log('err', 'Missing robot parameter, cannot create list object for %s',  $name) unless ($options->{'just_try'});
	return undef;
    }

    ## Only process the list if the name is valid.
    my $listname_regexp = &tools::get_regexp('listname');
    unless ($name and ($name =~ /^($listname_regexp)$/io) ) {
	&Log::do_log('err', 'Incorrect listname "%s"',  $name) unless ($options->{'just_try'});
	return undef;
    }
    ## Lowercase the list name.
    $name = $1;
    $name =~ tr/A-Z/a-z/;
    
    ## Reject listnames with reserved list suffixes
    my $regx = &Conf::get_robot_conf($robot,'list_check_regexp');
    if ( $regx ) {
	if ($name =~ /^(\S+)-($regx)$/) {
	    &Log::do_log('err', 'Incorrect name: listname "%s" matches one of service aliases',  $name) unless ($options->{'just_try'});
	    return undef;
	}
    }

    my $status ;
    ## If list already in memory and not previously purged by another process
    if ($list_of_lists{$robot}{$name} and
	-d $list_of_lists{$robot}{$name}{'dir'}) {
	# use the current list in memory and update it
	$list = $list_of_lists{$robot}{$name};
    }else{
	# create a new object list
	$list = bless { } => $pkg;
    }   
    $status = $list->load($name, $robot, $options);
    unless (defined $status) {
	return undef;
    }

    ## Config file was loaded or reloaded
    if (($status == 1 && ! $options->{'skip_sync_admin'}) ||
	$options->{'force_sync_admin'}) {

	## Update admin_table
	unless (defined $list->sync_include_admin()) {
	    &Log::do_log('err', 'sync_include_admin for list %s failed', $list)
		unless $options->{'just_try'};
	}
	if ($list->get_nb_owners() < 1) {
	    $list->set_status_error_config('no_owner_defined');
	}
    }

    return $list;
}

## When no robot is specified, look for a list among robots
sub search_list_among_robots {
    my $listname = shift;
    
    unless ($listname) {
 	&Log::do_log('err', 'List::search_list_among_robots() : Missing list parameter');
 	return undef;
    }
    
    ## Search in default robot
    if (-d $Conf::Conf{'home'}.'/'.$listname) {
 	return $Conf::Conf{'domain'};
    }
    
     foreach my $r (keys %{$Conf::Conf{'robots'}}) {
	 if (-d $Conf::Conf{'home'}.'/'.$r.'/'.$listname) {
	     return $r;
	 }
     }
    
     return 0;
}

## set the list in status error_config and send a notify to listmaster
sub set_status_error_config {
    &Log::do_log('debug2', '(%s, %s, ...)', @_);

    my ($self, $message, @param) = @_;

    unless ($self->admin and $self->status eq 'error_config') {
	$self->status('error_config');

	#my $host = &Conf::get_robot_conf($self->domain, 'host');
	## No more save config in error...
	#$self->save_config("listmaster\@$host");
	#$self->savestats();
	&Log::do_log('err', 'The list %s is set in status error_config: %s(%s)', $self, $message, join(', ', @param));
	unless (&List::send_notify_to_listmaster($message, $self->domain, [$self->name, @param])) {
	    &Log::do_log('notice', 'Unable to send notify "%s" to listmaster', $message);
	};
    }
}

## set the list in status family_closed and send a notify to owners
sub set_status_family_closed {
    &Log::do_log('debug2', '(%s, %s, ...)', @_);

    my ($self, $message, @param) = @_;

    unless ($self->status eq 'family_closed'){
	my $host = &Conf::get_robot_conf($self->domain, 'host');	
	unless ($self->close_list("listmaster\@$host",'family_closed')) {
	    &Log::do_log('err', 'Impossible to set the list %s in status family_closed', $self);
	    return undef;
	}
	&Log::do_log('info', 'The list %s is set in status family_closed', $self);
	unless ($self->send_notify_to_owner($message,\@param)){
	    &Log::do_log('err','Impossible to send notify to owner informing status family_closed for the list %s', $self);
	}
# messages : close_list
    }
    return 1;
}

## Saves the statistics data to disk.
sub savestats {
    my $self = shift;
    &Log::do_log('debug2', 'List::savestats');
   
    ## Be sure the list has been loaded.
    my $name = $self->{'name'};
    my $dir = $self->{'dir'};
    return undef unless ($list_of_lists{$self->{'domain'}}{$name});
    
    ## Lock file
    my $lock = new Lock ($dir.'/stats');
    unless (defined $lock) {
	&Log::do_log('err','Could not create new lock');
	return undef;
    }
    $lock->set_timeout(2); 
    unless ($lock->lock('write')) {
	return undef;
    }   

    $self->_save_stats_file();

    ## Release the lock
    unless ($lock->unlock()) {
	return undef;
    }

    ## Changed on disk
    $self->{'mtime'}[2] = time;

    return 1;
}

## msg count.
sub increment_msg_count {
    &Log::do_log('debug2', '(%s)', @_);
    my $self = shift;

    ## Be sure the list has been loaded.
    my $name = $self->name;
    my $file = $self->dir . '/msg_count';
    my $time = time;

    my %count;
    if (open(MSG_COUNT, $file)) {
	while (<MSG_COUNT>){
	    if ($_ =~ /^(\d+)\s(\d+)$/) {
		$count{$1} = $2;
	    }
	}
	close MSG_COUNT ;
    }
    my $today = int($time / 86400);
    if ($count{$today}) {
	$count{$today}++;
    }else{
	$count{$today} = 1;
    }

    unless (open(MSG_COUNT, ">$file.$$")) {
	&Log::do_log('err', "Unable to create '%s.%s' : %s", $file,$$, $!);
	return undef;
    }
    foreach my $key (sort {$a <=> $b} keys %count) {
	printf MSG_COUNT "%d\t%d\n",$key,$count{$key} ;
    }
    close MSG_COUNT ;
    
    unless (rename("$file.$$", $file)) {
	&Log::do_log('err', "Unable to write '%s' : %s", $file, $!);
	return undef;
    }

    return 1;
}

# Returns the number of messages sent to the list
sub get_msg_count {
    my $self = shift;
    &Log::do_log('debug3', "Getting the number of messages for list %s",$self->{'name'});

    ## Be sure the list has been loaded.
    my $name = $self->{'name'};
    my $file = "$self->{'dir'}/stats";
    
    my $count = 0 ;
    if (open(MSG_COUNT, $file)) {	
	while (<MSG_COUNT>){
	    if ($_ =~ /^(\d+)\s+(.*)$/) {
		$count=$1;	
	    }
	}
	close MSG_COUNT ;
    }

    return $count;

}
## last date of distribution message .
sub get_latest_distribution_date {
    my $self = shift;
    &Log::do_log('debug3', "List::latest_distribution_date($self->{'name'})");
   
    ## Be sure the list has been loaded.
    my $name = $self->{'name'};
    my $file = "$self->{'dir'}/msg_count";
    
    my %count ; 
    my $latest_date = 0 ; 
    unless (open(MSG_COUNT, $file)) {
	&Log::do_log('debug2',"get_latest_distribution_date: unable to open $file");
	return undef ;
    }

    while (<MSG_COUNT>){
	if ($_ =~ /^(\d+)\s(\d+)$/) {
	    $latest_date = $1 if ($1 > $latest_date);
	}
    }
    close MSG_COUNT ;

    return undef if ($latest_date == 0); 
    return $latest_date ;
}

## Update the stats struct 
## Input  : num of bytes of msg
## Output : num of msgs sent
sub update_stats {
    &Log::do_log('debug2', '(%s, %s)', @_);
    my($self, $bytes) = @_;

    my @stats = (@{$self->stats});
    $stats[0]++;			# messsages sent
    $stats[1] += $self->total;		# total messages sent
    $stats[2] += $bytes;		# octets sent
    $stats[3] += $bytes * $self->total; # total octets sent
    $self->{'stats'} = \@stats;

    ## Update 'msg_count' file, used for bounces management
    $self->increment_msg_count();

    return $stats[0];
}

## Extract a set of rcpt for which verp must be use from a rcpt_tab.
## Input  :  percent : the rate of subscribers that must be threaded using verp
##           xseq    : the message sequence number
##           @rcpt   : a tab of emails
## return :  a tab of rcpt for which rcpt must be use depending on the message sequence number, this way every subscriber is "verped" from time to time
##           input table @rcpt is spliced : rcpt for which verp must be used are extracted from this table
sub extract_verp_rcpt() {
    my $percent = shift;
    my $xseq = shift;
    my $refrcpt = shift;
    my $refrcptverp = shift;

    &Log::do_log('debug','&extract_verp(%s,%s,%s,%s)',$percent,$xseq,$refrcpt,$refrcptverp)  ;

    my @result;

    if ($percent ne '0%') {
	my $nbpart ; 
	if ( $percent =~ /^(\d+)\%/ ) {
	    $nbpart = 100/$1;  
	}
	else {
	    &Log::do_log ('err', 'Wrong format for parameter extract_verp: %s. Can\'t process VERP.',$percent);
	    return undef;
	}
	
	my $modulo = $xseq % $nbpart ;
	my $lenght = int (($#{$refrcpt} + 1) / $nbpart) + 1;
	
	@result = splice @$refrcpt, $lenght*$modulo, $lenght ;
    }
    foreach my $verprcpt (@$refrcptverp) {
	push @result, $verprcpt;
    }
    return ( @result ) ;
}



## Dumps a copy of lists to disk, in text format
sub dump {
    my $self = shift;
    &Log::do_log('debug2', 'List::dump(%s)', $self->{'name'});

    unless (defined $self) {
	&Log::do_log('err','Unknown list');
	return undef;
    }

    my $user_file_name = "$self->{'dir'}/subscribers.db.dump";

    unless ($self->_save_list_members_file($user_file_name)) {
	&Log::do_log('err', 'Failed to save file %s', $user_file_name);
	return undef;
    }
    
    $self->{'mtime'} = [ (stat("$self->{'dir'}/config"))[9], (stat("$self->{'dir'}/subscribers"))[9], (stat("$self->{'dir'}/stats"))[9] ];

    return 1;
}

## Saves the configuration file to disk
sub save_config {
    my ($self, $email) = @_;
    &Log::do_log('debug3', 'List::save_config(%s,%s)', $self->{'name'}, $email);

    return undef 
	unless ($self);

    my $config_file_name = "$self->{'dir'}/config";

    ## Lock file
    my $lock = new Lock ($self->{'dir'}.'/config');
    unless (defined $lock) {
	&Log::do_log('err','Could not create new lock');
	return undef;
    }
    $lock->set_timeout(5); 
    unless ($lock->lock('write')) {
	return undef;
    }

    my $name = $self->{'name'};    
    my $old_serial = $self->{'admin'}{'serial'};
    my $old_config_file_name = "$self->{'dir'}/config.$old_serial";

    ## Update management info
    $self->{'admin'}{'serial'}++;
    $self->{'admin'}{'update'} = {'email' => $email,
				  'date_epoch' => time,
				  'date' => (gettext_strftime "%d %b %Y at %H:%M:%S", localtime(time)),
				  };

    unless (&_save_list_config_file($config_file_name, $old_config_file_name, $self->{'admin'})) {
	&Log::do_log('info', 'unable to save config file %s', $config_file_name);
	$lock->unlock();
	return undef;
    }

    $lock->unlock();

    ## Also update the binary version of the data structure
    $self->list_cache_update_admin;

    return 1;
}

## Loads the administrative data for a list
sub load {
    &Log::do_log('debug2', '(%s, %s, %s, %s)', @_);

    ## NOTICE: Don't use accessors like "$self->dir" but "$self->{'dir'}",
    ## since the object has not been fully initialized yet.

    my ($self, $name, $robot, $options) = @_;

    ## Set of initializations ; only performed when the config is first loaded
    unless ($self->{'name'} and $self->{'domain'} and $self->{'dir'}) {
	## Search robot if none was provided
	unless ($robot) {
	    foreach my $r (keys %{$Conf::Conf{'robots'}}) {
		if (-d "$Conf::Conf{'home'}/$r/$name") {
		    $robot=$r;
		    last;
		}
	    }
	    
	    ## Try default robot
	    unless ($robot) {
		if (-d "$Conf::Conf{'home'}/$name") {
		    $robot = $Conf::Conf{'domain'};
		}
	    }
	}
	
	if ($robot && (-d "$Conf::Conf{'home'}/$robot")) {
	    $self->{'dir'} = "$Conf::Conf{'home'}/$robot/$name";
	}elsif (lc($robot) eq lc($Conf::Conf{'domain'})) {
	    $self->{'dir'} = "$Conf::Conf{'home'}/$name";
	}else {
	    &Log::do_log('err', 'No such robot (virtual domain) %s', $robot) unless ($options->{'just_try'});
	    return undef ;
	}
	
	$self->{'domain'} = $robot;
	$self->{'name'} = $name;
    }

    unless ($self->{'name'} eq $name and $self->{'domain'} eq $robot) {
	&Log::do_log('err', 'Bug in logic.  Ask developer');
	return undef;
    }

    unless (-d $self->{'dir'} and -f $self->{'dir'} . '/config') {
	&Log::do_log('debug3', 'Missing directory (%s) or config file for %s',
		     $self->{'dir'}, $self)
	    unless $options->{'just_try'};
	return undef;
    }

    ## Last modification of list config ($m1), subscribers ($m2) and stats
    ## ($m3) on memory cache.  $m2 is no longer used.
    my ($m1, $m2, $m3) = (0, 0, 0);
    ($m1, $m2, $m3) = @{$self->{'mtime'}} if defined $self->{'mtime'};

    my $time_config = (stat("$self->{'dir'}/config"))[9];
    my $time_stats = (stat("$self->{'dir'}/stats"))[9];
    my $admin = undef;
    my $cached;

    ## Load list config
    if (! $options->{'reload_config'} and
	$m1 and $time_config and $time_config <= $m1) {
	&Log::do_log('debug3', 'config for %s on memory is up-to-date',
		     $self);
    } elsif (! $options->{'reload_config'} and
	     defined ($cached = $self->list_cache_fetch($m1, $time_config))) {
	$m1 = $cached->{'epoch'};
	$self->{'admin'} = $admin = $cached->{'admin'};
	$self->{'total'} = $cached->{'total'} if defined $cached->{'total'};
	&Log::do_log('debug3', 'got config for %s from serialized data',
		     $self);
    } elsif ($options->{'reload_config'} or $time_config > $m1) {
	$admin = &_load_list_config_file($self->{'dir'}, $robot, 'config');
 	unless (defined $admin) {
 	    $self->set_status_error_config('load_admin_file_error');
	    $self->list_cache_purge;
 	    return undef;	    
 	}
	$m1 = $time_config;
	$self->{'admin'} = $admin;
	&Log::do_log('debug3', 'got config for %s from file', $self);

 	## check param_constraint.conf if belongs to a family and
 	## the config has been loaded
 	if (defined $self->family_name and $self->status ne 'error_config') {
 	    my $family;
 	    unless ($family = $self->family) {
 		$self->set_status_error_config('no_list_family',
					       $self->family_name);
		$self->list_cache_purge;
		return undef;
	    }

	    my $error = $family->check_param_constraint($self);
	    unless ($error) {
 		$self->set_status_error_config('no_check_rules_family',
					       $family->{'name'});
	    } elsif (ref $error eq 'ARRAY') {
 		$self->set_status_error_config('no_respect_rules_family',
					       $family->{'name'});
 	    }
 	}

	# config was reloaded.  Update cache too.
	$self->list_cache_update_admin;
    }

    ## Check if the current list has a public key X.509 certificate.
    $self->{'as_x509_cert'} =
	(-r $self->{'dir'}.'/cert.pem' || -r $self->{'dir'}.'/cert.pem.enc') ?
	1 : 0;

    ## Load stats file if first new() or stats file changed
    if ($time_stats > $m3) {
	$self->_load_stats_file();
	$m3 = $time_stats;
    }

    $self->{'mtime'} = [ $m1, $m2, $m3 ];
    $list_of_lists{$robot}{$name} = $self;
    return $admin ? 1 : 0;
}

## Return a list of hash's owners and their param
sub get_owners {
    my($self) = @_;
    &Log::do_log('debug3', 'List::get_owners(%s)', $self->{'name'});
  
    my $owners = ();

    # owners are in the admin_table ; they might come from an include data source
    for (my $owner = $self->get_first_list_admin('owner'); $owner; $owner = $self->get_next_list_admin()) {
	push(@{$owners},$owner);
    } 

    return $owners;
}

sub get_nb_owners {
    my($self) = @_;
    &Log::do_log('debug3', 'List::get_nb_owners(%s)', $self->{'name'});
    
    my $resul = 0;
    my $owners = $self->get_owners;

    if (defined $owners) {
	$resul = $#{$owners} + 1;
    }
    return $resul;
}

## Return a hash of list's editors and their param(empty if there isn't any editor)
sub get_editors {
    my($self) = @_;
    &Log::do_log('debug3', 'List::get_editors(%s)', $self->{'name'});
  
    my $editors = ();

    # editors are in the admin_table ; they might come from an include data source
    for (my $editor = $self->get_first_list_admin('editor'); $editor; $editor = $self->get_next_list_admin()) {
	push(@{$editors},$editor);
    } 

    return $editors;
}


## Returns an array of owners' email addresses
sub get_owners_email {
    my($self,$param) = @_;
    &Log::do_log('debug3', 'List::get_owners_email(%s,%s)', $self->{'name'}, $param -> {'ignore_nomail'});
    
    my @rcpt;
    my $owners = ();

    $owners = $self->get_owners();

    if ($param -> {'ignore_nomail'}) {
	foreach my $o (@{$owners}) {
	    push (@rcpt, lc($o->{'email'}));
	}
    }
    else {
	foreach my $o (@{$owners}) {
	    next if ($o->{'reception'} eq 'nomail');
	    push (@rcpt, lc($o->{'email'}));
	}
    }
    unless (@rcpt) {
	&Log::do_log('notice','Warning : no owner found for list %s', $self->{'name'} );
    }
    return @rcpt;
}

## Returns an array of editors' email addresses
#  or owners if there isn't any editors'email adress
sub get_editors_email {
    my($self,$param) = @_;
    &Log::do_log('debug3', 'List::get_editors_email(%s,%s)', $self->{'name'}, $param -> {'ignore_nomail'});
    
    my @rcpt;
    my $editors = ();

    $editors = $self->get_editors();

    if ($param -> {'ignore_nomail'}) {
	foreach my $e (@{$editors}) {
	    push (@rcpt, lc($e->{'email'}));
	}
    }
    else {
	foreach my $e (@{$editors}) {
	    next if ($e->{'reception'} eq 'nomail');
	    push (@rcpt, lc($e->{'email'}));
	}
    }
    unless (@rcpt) {
	&Log::do_log('notice','Warning : no editor found for list %s, getting owners', $self->{'name'} );
	@rcpt = $self->get_owners_email($param);
    }
    return @rcpt;
}

## DEPRECATED.  Use family().
##sub get_family

## return the config_changes hash
## Used ONLY with lists belonging to a family.
sub get_config_changes {
    my $self = shift;
    &Log::do_log('debug3', 'List::get_config_changes(%s)', $self->{'name'});
    
    unless ($self->{'admin'}{'family_name'}) {
	&Log::do_log('err', 'List::get_config_changes(%s) is called but there is no family_name for this list.',$self->{'name'});
	return undef;
    }
    
    ## load config_changes
    my $time_file = (stat("$self->{'dir'}/config_changes"))[9];
    unless (defined $self->{'config_changes'} && ($self->{'config_changes'}{'mtime'} >= $time_file)) {
	unless ($self->{'config_changes'} = $self->_load_config_changes_file()) {
	    &Log::do_log('err','Impossible to load file config_changes from list %s',$self->{'name'});
	    return undef;
	}
    }
    return $self->{'config_changes'};
}


## update file config_changes if the list belongs to a family by
#  writing the $what(file or param) name 
sub update_config_changes {
    my $self = shift;
    my $what = shift;
    # one param or a ref on array of param
    my $name = shift;
    &Log::do_log('debug2', 'List::update_config_changes(%s,%s)', $self->{'name'},$what);
    
    unless ($self->{'admin'}{'family_name'}) {
	&Log::do_log('err', 'List::update_config_changes(%s,%s,%s) is called but there is no family_name for this list.',$self->{'name'},$what);
	return undef;
    }
    unless (($what eq 'file') || ($what eq 'param')){
	&Log::do_log('err', 'List::update_config_changes(%s,%s) : %s is wrong : must be "file" or "param".',$self->{'name'},$what);
	return undef;
    } 
    
    # status parameter isn't updating set in config_changes
    if (($what eq 'param') && ($name eq 'status')) {
	return 1;
    }

    ## load config_changes
    my $time_file = (stat("$self->{'dir'}/config_changes"))[9];
    unless (defined $self->{'config_changes'} && ($self->{'config_changes'}{'mtime'} >= $time_file)) {
	unless ($self->{'config_changes'} = $self->_load_config_changes_file()) {
	    &Log::do_log('err','Impossible to load file config_changes from list %s',$self->{'name'});
	    return undef;
	}
    }
    
    if (ref($name) eq 'ARRAY' ) {
	foreach my $n (@{$name}) {
	    $self->{'config_changes'}{$what}{$n} = 1; 
	}
    } else {
	$self->{'config_changes'}{$what}{$name} = 1;
    }
    
    $self->_save_config_changes_file();
    
    return 1;
}

## return a hash of config_changes file
sub _load_config_changes_file {
    my $self = shift;
    ##&Log::do_log('debug3', 'List::_load_config_changes_file(%s)', $self->{'name'});

    my $config_changes = {};

    unless (-e "$self->{'dir'}/config_changes") {
	&Log::do_log('err','No file %s/config_changes. Assuming no changes', $self->{'dir'});
	return $config_changes;
    }

    unless (open (FILE,"$self->{'dir'}/config_changes")) {
	&Log::do_log('err','File %s/config_changes exists, but unable to open it: %s', $self->{'dir'},$_);
	return undef;
    }
    
    while (<FILE>) {
	
	next if /^\s*(\#.*|\s*)$/;

	if (/^param\s+(.+)\s*$/) {
	    $config_changes->{'param'}{$1} = 1;

	}elsif (/^file\s+(.+)\s*$/) {
	    $config_changes->{'file'}{$1} = 1;
	
	}else {
	    &Log::do_log ('err', 'List::_load_config_changes_file(%s) : bad line : %s',$self->{'name'},$_);
	    next;
	}
    }
    close FILE;

    $config_changes->{'mtime'} = (stat("$self->{'dir'}/config_changes"))[9];

    return $config_changes;
}

## save config_changes file in the list directory
sub _save_config_changes_file {
    my $self = shift;
    ##&Log::do_log('debug3', 'List::_save_config_changes_file(%s)', $self->{'name'});

    unless ($self->{'admin'}{'family_name'}) {
	&Log::do_log('err', 'List::_save_config_changes_file(%s) is called but there is no family_name for this list.',$self->{'name'});
	return undef;
    }
    unless (open (FILE,">$self->{'dir'}/config_changes")) {
	&Log::do_log('err','List::_save_config_changes_file(%s) : unable to create file %s/config_changes : %s',$self->{'name'},$self->{'dir'},$_);
	return undef;
    }

    foreach my $what ('param','file') {
	foreach my $name (keys %{$self->{'config_changes'}{$what}}) {
	    print FILE "$what $name\n";
	}
    }
    close FILE;
    
    return 1;
}




sub _get_param_value_anywhere {
    my $new_admin = shift;
    my $param = shift; 
    &Log::do_log('debug3', '_get_param_value_anywhere(%s %s)',$param);
    my $minor_p;
    my @values;

   if ($param =~ /^([\w-]+)\.([\w-]+)$/) {
	$param = $1;
	$minor_p = $2;
    }

    ## Multiple parameter (owner, custom_header, ...)
    if ((ref ($new_admin->{$param}) eq 'ARRAY') &&
	!($::pinfo{$param}{'split_char'})) {
	foreach my $elt (@{$new_admin->{$param}}) {
	    my $val = &List::_get_single_param_value($elt,$param,$minor_p);
	    if (defined $val) {
		push @values,$val;
	    }
	}

    }else {
	my $val = &List::_get_single_param_value($new_admin->{$param},$param,$minor_p);
	if (defined $val) {
	    push @values,$val;
	}
    }
    return \@values;
}


## Returns the list parameter value from $list->{'admin'}
#  the parameter is simple ($param) or composed ($param & $minor_param)
#  the value is a scalar or a ref on an array of scalar
# (for parameter digest : only for days)
sub get_param_value {
    my $self = shift;
    my $param = shift; 
    &Log::do_log('debug3', 'List::get_param_value(%s,%s)', $self->{'name'},$param);
    my $minor_param;
    my $value;

    if ($param =~ /^([\w-]+)\.([\w-]+)$/) {
	$param = $1;
	$minor_param = $2;
    }

    ## Multiple parameter (owner, custom_header, ...)
    if ((ref ($self->{'admin'}{$param}) eq 'ARRAY') &&
	! $::pinfo{$param}{'split_char'}) {
	my @values;
	foreach my $elt (@{$self->{'admin'}{$param}}) {
	    push @values,&_get_single_param_value($elt,$param,$minor_param) 
	}
	$value = \@values;
    }else {
	$value = &_get_single_param_value($self->{'admin'}{$param},$param,$minor_param);
    }
    return $value;
}

## Returns the single list parameter value from struct $p, with $key entrie,
#  $k is optionnal
#  the single value can be a ref on a list when the parameter value is a list
sub _get_single_param_value {
    my ($p,$key,$k) = @_;
    &Log::do_log('debug3', 'List::_get_single_value(%s %s)',$key,$k);

    if (defined ($::pinfo{$key}{'scenario'}) ||
        defined ($::pinfo{$key}{'task'})) {
	return $p->{'name'};
    
    }elsif (ref($::pinfo{$key}{'file_format'})) {
	
	if (defined ($::pinfo{$key}{'file_format'}{$k}{'scenario'})) {
	    return $p->{$k}{'name'};

	}elsif (($::pinfo{$key}{'file_format'}{$k}{'occurrence'} =~ /n$/)
		    && $::pinfo{$key}{'file_format'}{$k}{'split_char'}) {
	    return $p->{$k}; # ref on an array
	}else {
	    return $p->{$k};
	}

    }else {
	if (($::pinfo{$key}{'occurrence'} =~ /n$/)
	    && $::pinfo{$key}{'split_char'}) {
	    return $p; # ref on an array
	}elsif ($key eq 'digest') {
	    return $p->{'days'}; # ref on an array 
	}else {
	    return $p;
	}
    }
}



###########################################################################
#                FUNCTIONS FOR MESSAGE SENDING                            #
###########################################################################
#                                                                         #
#  -list distribution   
#  -template sending                                                      #
#  -service messages
#  -notification sending(listmaster, owner, editor, user)                 #
#                                                                         #
                                             
###################   LIST DISTRIBUTION  ##################################

####################################################
# distribute_msg                              
####################################################
#  prepares and distributes a message to a list, do 
#  some of these :
#  stats, hidding sender, adding custom subject, 
#  archive, changing the replyto, removing headers, 
#  adding headers, storing message in digest
# 
#  
# IN : -$self (+): ref(List)
#      -$message (+): ref(Message)
#      -$apply_dkim_signature : on | off
# OUT : -$numsmtp : number of sendmail process
####################################################
sub distribute_msg {
    my $self = shift;
    my %param = @_;

    my $message = $param{'message'};
    my $apply_dkim_signature = $param{'apply_dkim_signature'};

    &Log::do_log('debug2', 'List::distribute_msg(%s, %s, %s, %s, %s, %s, apply_dkim_signature=%s)', $self->{'name'}, $message->{'msg'}, $message->{'size'}, $message->{'filename'}, $message->{'smime_crypted'}, $apply_dkim_signature );

    my $hdr = $message->{'msg'}->head;
    my ($name, $host) = ($self->name, $self->host);
    my $robot = $self->domain;

    ## Update the stats, and returns the new X-Sequence, if any.
    my $sequence = $self->update_stats($message->{'size'});
    
    ## Loading info msg_topic file if exists, add X-Sympa-Topic
    my $info_msg_topic;
    if ($self->is_there_msg_topic()) {
	my $msg_id = $hdr->get('Message-ID');
	chomp($msg_id);
	$info_msg_topic = $self->load_msg_topic($msg_id,$robot);

	# add X-Sympa-Topic header
	if (ref($info_msg_topic) eq "HASH") {
	    $message->add_topic($info_msg_topic->{'topic'});
	}
    }

    ## Hide the sender if the list is anonymoused
    if ($self->anonymous_sender) {
	foreach my $field (@{$Conf::Conf{'anonymous_header_fields'}}) {
	    $hdr->delete($field);
	}
	$hdr->add('From', $self->anonymous_sender);
	my $new_id = '<' . $self->name . '.' . $sequence . '@anonymous' . '>';
	$hdr->add('Message-id', $new_id);

	# rename update topic content id of the message
	if ($info_msg_topic) {
	    my $topicspool = new Sympaspool ('topic');	    
	    $topicspool->update({'list' => $self->name, 'robot' => $robot}, 'messagekey' => $info_msg_topic->{'messagekey'}, {'messageid' => $new_id});	
	}
	## TODO remove S/MIME and PGP signature if any
    }
    
    ## Add Custom Subject
    if ($self->custom_subject) {
	my $subject_field = $message->{'decoded_subject'};
	$subject_field =~ s/^\s*(.*)\s*$/$1/; ## Remove leading and trailing blanks
	
	## Search previous subject tagging in Subject
	my $custom_subject = $self->custom_subject;

	## tag_regexp will be used to remove the custom subject if it is already present in the message subject.
	## Remember that the value of custom_subject can be "dude number [%list.sequence"%]" whereas the actual
	## subject will contain "dude number 42".
	my $list_name_escaped = $self->name;
	$list_name_escaped =~ s/(\W)/\\$1/g;
	my $tag_regexp = $custom_subject;
	$tag_regexp =~ s/([^\w\s\x80-\xFF])/\\$1/g;  ## cleanup, just in case dangerous chars were left
	$tag_regexp =~ s/\\\[\\\%\s*list\\\.sequence\s*\\\%\\\]/\\d+/g; ## Replaces "[%list.sequence%]" by "\d+"
	$tag_regexp =~ s/\\\[\\\%\s*list\\\.name\s*\\\%\\\]/$list_name_escaped/g; ## Replace "[%list.name%]" by escaped list name
	$tag_regexp =~ s/\\\[\\\%\s*[^]]+\s*\\\%\\\]/[^]]+/g; ## Replaces variables declarations by "[^\]]+"
	$tag_regexp =~ s/\s+/\\s+/g; ## Takes spaces into account

	## Add subject tag
	$message->{'msg'}->head->delete('Subject');
	my $parsed_tag;
	&tt2::parse_tt2({'list' => {'name' => $self->name,
				    'sequence' => $self->stats->[0]
				    }},
			[$custom_subject], \$parsed_tag);

	## If subject is tagged, replace it with new tag
	## Splitting the subject in two parts :
	##   - what will be before the custom subject (probably some "Re:")
	##   - what will be after it : the orginal subject sent to the list.
	## The custom subject is not kept.
	my $before_tag;
	my $after_tag;
	if ($custom_subject =~ /\S/) {
	    $subject_field =~ s/\s*\[$tag_regexp\]\s*/ /;
	}
	$subject_field =~ s/\s+$//;

	# truncate multiple "Re:" and equivalents.
	my $re_regexp = tools::get_regexp('re');
	if ($subject_field =~ /^\s*($re_regexp\s*)($re_regexp\s*)*/) {
	    ($before_tag, $after_tag) = ($1, $'); #'
	} else {
	    ($before_tag, $after_tag) = ('', $subject_field);
	}
	
 	## Encode subject using initial charset

	## Don't try to encode the subject if it was not originaly encoded.
	if ($message->{'subject_charset'}) {
	    $subject_field = MIME::EncWords::encode_mimewords([
							       [Encode::decode('utf8', $before_tag), $message->{'subject_charset'}],
							       [Encode::decode('utf8', '['.$parsed_tag.'] '), &Language::GetCharset()],
							       [Encode::decode('utf8', $after_tag), $message->{'subject_charset'}]
							       ], Encoding=>'A', Field=>'Subject');
	}else {
	    $subject_field = $before_tag . ' ' .  MIME::EncWords::encode_mimewords([
										    [Encode::decode('utf8', '['.$parsed_tag.']'), &Language::GetCharset()]
										    ], Encoding=>'A', Field=>'Subject') . ' ' . $after_tag;
	}
	$message->{'msg'}->head->add('Subject', $subject_field);
    }

    ## Prepare tracking if list config allow it
    my $apply_tracking = 'off';
    
    $apply_tracking = 'dsn'
	if $self->tracking->{'delivery_status_notification'} eq 'on';
    $apply_tracking = 'mdn'
	if $self->tracking->{'message_delivery_notification'} eq 'on';
    $apply_tracking = 'mdn'
	if $self->tracking->{'message_delivery_notification'} eq 'on_demand'
	   and $hdr->get('Disposition-Notification-To');

    if ($apply_tracking ne 'off'){
	$hdr->delete('Disposition-Notification-To'); # remove notification request becuse a new one will be inserted if needed
    }
    
    ## Remove unwanted headers if present.
    if ($self->remove_headers) {
        foreach my $field (@{$self->remove_headers}) {
            $hdr->delete($field);
        }
    }

    ## Archives

    $self->archive_msg($message);

    ## Change the reply-to header if necessary. 
    if ($self->reply_to_header) {
	unless ($hdr->get('Reply-To') and
		$self->reply_to_header->{'apply'} ne 'forced') {
	    my $reply;

	    $hdr->delete('Reply-To');

	    if ($self->reply_to_header->{'value'} eq 'list') {
		$reply = $self->get_list_address();
	    } elsif ($self->reply_to_header->{'value'} eq 'sender') {
		$reply = $hdr->get('From');
	    } elsif ($self->reply_to_header->{'value'} eq 'all') {
		$reply = $self->get_list_address() . ',' . $hdr->get('From');
	    } elsif ($self->reply_to_header->{'value'} eq 'other_email') {
		$reply = $self->reply_to_header->{'other_email'};
	    }

	    $hdr->add('Reply-To', $reply) if $reply;
	}
    }
    
    ## Add useful headers
    $hdr->add('X-Loop', $self->get_list_address());
    $message->{'msg'}->head->add('X-Loop', "$name\@$host");
    $hdr->add('X-Sequence', $sequence);
    $hdr->add('Errors-to', $self->get_list_address('return_path'));
    $hdr->add('Precedence', 'list');
    $hdr->add('Precedence', 'bulk');
    $hdr->add('Sender', $self->get_list_address('owner')); # The Sender: header should be add at least for DKIM compatibility
    $hdr->add('X-no-archive', 'yes');
    foreach my $i (@{$self->custom_header}) {
	$hdr->add($1, $2) if $i =~ /^([\S\-\:]*)\s(.*)$/;
    }
    
    ## Add RFC 2919 header field
    if ($hdr->get('List-Id')) {
	&Log::do_log('notice', 'Found List-Id: %s', $hdr->get('List-Id'));
	$hdr->delete('List-ID');
    }
    $self->add_list_header($hdr, 'id');

    ## Add RFC 2369 header fields
    foreach my $field (@{$::pinfo{'rfc2369_header_fields'}->{'format'}}) {
	if (scalar grep { $_ eq $field } @{$self->rfc2369_header_fields}) {
	    $self->add_list_header($hdr, $field);
	}
    }

    ## Add RFC5064 Archived-At SMTP header field
    $self->add_list_header($hdr, 'archived_at');

    ## Remove outgoing header fileds
    ## Useful to remove some header fields that Sympa has set
    if ($self->remove_outgoing_headers) {
        foreach my $field (@{$self->remove_outgoing_headers}) {
            $hdr->delete($field);
        }
    }   
    
    ## store msg in digest if list accept digest mode (encrypted message can't be included in digest)
    if (($self->is_digest()) and ($message->{'smime_crypted'} ne 'smime_crypted')) {
	$self->store_digest($message);
    }

    ## Synchronize list members, required if list uses include sources
    ## unless sync_include has been performed recently.
    if ($self->has_include_data_sources()) {
	$self->on_the_fly_sync_include('use_ttl' => 1);
    }

    ## Blindly send the message to all users.
    my $numsmtp = $self->send_msg('message'=> $message, 'apply_dkim_signature'=>$apply_dkim_signature, 'apply_tracking'=>$apply_tracking);
    $self->savestats() if (defined ($numsmtp));
    return $numsmtp;
}

####################################################
# send_msg_digest                              
####################################################
# Send a digest message to the subscribers with 
# reception digest, digestplain or summary
# 
# IN : -$self(+) : ref(List)
#      $message_in_spool : an digest spool entry in database
# OUT : 1 : ok
#       | 0 if no subscriber for sending digest
#       | undef
####################################################
sub send_msg_digest {
    my $self = shift;
    my $messagekey = shift;
   &Log::do_log('debug',"send_msg_disgest(%s)",$messagekey);

    # fetch and lock message. 
    my $digestspool = new Sympaspool ('digest');

    my $message_in_spool = $digestspool->next({'messagekey'=>$messagekey});

    my $listname = $self->{'name'};
    my $robot = $self->{'domain'};
    &Log::do_log('debug2', 'List:send_msg_digest(%s)', $listname);
    
    my $param = {'replyto' => $self->get_list_address('owner'),
		 'to' => $self->get_list_address(),
		 'table_of_content' => sprintf(gettext("Table of contents:")),
		 'boundary1' => '----------=_'.&tools::get_message_id($robot),
		 'boundary2' => '----------=_'.&tools::get_message_id($robot),
		 };
    if ($self->get_reply_to() =~ /^list$/io) {
	$param->{'replyto'}= "$param->{'to'}";
    }
    
    my @tabrcpt ;
    my @tabrcptsummary;
    my @tabrcptplain;
    my $i;
    
    my (@list_of_mail);

    ## Create the list of subscribers in various digest modes
    for (my $user = $self->get_first_list_member(); $user; $user = $self->get_next_list_member()) {
	my $user_data = $self->user('member', $user->{'email'}) || undef;
	## test to know if the rcpt suspended her subscription for this list
	## if yes, don't send the message
	if ($user_data->{'suspend'} eq '1'){
	    if(($user_data->{'startdate'} <= time) && ((time <= $user_data->{'enddate'}) || (!$user_data->{'enddate'}))){
		next;
	    }elsif(($user_data->{'enddate'} < time) && ($user_data->{'enddate'})){
		## If end date is < time, update the BDD by deleting the suspending's data
		$self->restore_suspended_subscription($user->{'email'});
	    }
	}
	if ($user->{'reception'} eq "digest") {
	    push @tabrcpt, $user->{'email'};

	}elsif ($user->{'reception'} eq "summary") {
	    ## Create the list of subscribers in summary mode
	    push @tabrcptsummary, $user->{'email'};
        
	}elsif ($user->{'reception'} eq "digestplain") {
	    push @tabrcptplain, $user->{'email'};              
	}
    }
    if (($#tabrcptsummary == -1) and ($#tabrcpt == -1) and ($#tabrcptplain == -1)) {
	&Log::do_log('info', 'No subscriber for sending digest in list %s', $listname);
	return 0;
    }

    my $separator = "\n\n" . &tools::get_separator() . "\n\n";
    my @messages_as_string = split (/$separator/,$message_in_spool->{'messageasstring'}); 

    foreach my $message_as_string (@messages_as_string){  
	my $parser = new MIME::Parser;
	$parser->output_to_core(1);
	$parser->extract_uuencode(1);  
	$parser->extract_nested_messages(1);
	#   $parser->output_dir($Conf::Conf{'spool'} ."/tmp");    
	my $mail = $parser->parse_data($message_as_string);
	next unless (defined $mail);
	push @list_of_mail, $mail;
    }

    ## Deletes the introduction part
    splice @list_of_mail, 0, 1;
    
    ## Digest index
    my @all_msg;
    foreach $i (0 .. $#list_of_mail){
	my $mail = $list_of_mail[$i];
	my $subject = &tools::decode_header($mail, 'Subject');
	my $from = &tools::decode_header($mail, 'From');
	my $date = &tools::decode_header($mail, 'Date');

        my $msg = {};
	$msg->{'id'} = $i+1;
        $msg->{'subject'} = $subject;	
	$msg->{'from'} = $from;
	$msg->{'date'} = $date;
	
	#$mail->tidy_body;
	
        ## Commented because one Spam made Sympa die (MIME::tools 5.413)
	#$mail->remove_sig;
	
	$msg->{'full_msg'} = $mail->as_string;
	$msg->{'body'} = $mail->body_as_string;
	$msg->{'plain_body'} = $mail->PlainDigest::plain_body_as_string();
	#$msg->{'body'} = $mail->bodyhandle->as_string();
	chomp $msg->{'from'};
	$msg->{'month'} = &POSIX::strftime("%Y-%m", localtime(time)); ## Should be extracted from Date:
	$msg->{'message_id'} = &tools::clean_msg_id($mail->head->get('Message-Id'));
	
	## Clean up Message-ID
	$msg->{'message_id'} = &tools::escape_chars($msg->{'message_id'});

        #push @{$param->{'msg_list'}}, $msg ;
	push @all_msg, $msg ;	
    }
    
    my @now  = localtime(time);
    $param->{'datetime'} = gettext_strftime "%a, %d %b %Y %H:%M:%S", @now;
    $param->{'date'} = gettext_strftime "%a, %d %b %Y", @now;

    ## Split messages into groups of digest_max_size size
    my @group_of_msg;
    while (@all_msg) {
	my @group = splice @all_msg, 0, $self->{'admin'}{'digest_max_size'};
	
	push @group_of_msg, \@group;
    }
    

    $param->{'current_group'} = 0;
    $param->{'total_group'} = $#group_of_msg + 1;
    ## Foreach set of digest_max_size messages...
    foreach my $group (@group_of_msg) {
	
	$param->{'current_group'}++;
	$param->{'msg_list'} = $group;
	$param->{'auto_submitted'} = 'auto-forwarded';
	
	## Prepare Digest
	if (@tabrcpt) {
	    ## Send digest
	    unless ($self->send_file('digest', \@tabrcpt, $robot, $param)) {
		&Log::do_log('notice',"Unable to send template 'digest' to $self->{'name'} list subscribers");
	    }
	}    
	
	## Prepare Plain Text Digest
	if (@tabrcptplain) {
	    ## Send digest-plain
	    unless ($self->send_file('digest_plain', \@tabrcptplain, $robot, $param)) {
		&Log::do_log('notice',"Unable to send template 'digest_plain' to $self->{'name'} list subscribers");
	    }
	}    	
	
	## send summary
	if (@tabrcptsummary) {
	    unless ($self->send_file('summary', \@tabrcptsummary, $robot, $param)) {
		&Log::do_log('notice',"Unable to send template 'summary' to $self->{'name'} list subscribers");
	    }
	}
    }    
    $digestspool->remove_message({'messagekey'=>$messagekey});    
    return 1;
}


###################   TEMPLATE SENDING  ###################################


####################################################
# send_global_file                              
####################################################
#  Send a global (not relative to a list) 
#  message to a user.
#  Find the tt2 file according to $tpl, set up 
#  $data for the next parsing (with $context and
#  configuration )
#  
# IN : -$tpl (+): template file name (file.tt2),
#         without tt2 extension
#      -$who (+): SCALAR |ref(ARRAY) - recipient(s)
#      -$robot (+): robot
#      -$context : ref(HASH) - for the $data set up 
#         to parse file tt2, keys can be :
#         -user : ref(HASH), keys can be :
#           -email
#           -lang
#           -password
#         -auto_submitted auto-generated|auto-replied|auto-forwarded
#         -...
#      -$options : ref(HASH) - options
# OUT : 1 | undef
#       
####################################################
sub send_global_file {
    my($tpl, $who, $robot, $context, $options) = @_;
    &Log::do_log('debug2', 'List::send_global_file(%s, %s, %s)', $tpl, $who, $robot);

    my $data = &tools::dup_var($context);

    unless ($data->{'user'}) {
	$data->{'user'} = &get_global_user($who) unless ($options->{'skip_db'});
	$data->{'user'}{'email'} = $who unless (defined $data->{'user'});;
    }
    unless ($data->{'user'}{'lang'}) {
	$data->{'user'}{'lang'} = $Language::default_lang;
    }
    
    unless ($data->{'user'}{'password'}) {
	$data->{'user'}{'password'} = &tools::tmp_passwd($who);
    }

    ## Lang
    $data->{'lang'} = $data->{'lang'} || $data->{'user'}{'lang'} || &Conf::get_robot_conf($robot, 'lang');

    ## What file 
    my $lang = &Language::Lang2Locale($data->{'lang'});
    my $tt2_include_path = &tools::make_tt2_include_path($robot,'mail_tt2',$lang,'');

    foreach my $d (@{$tt2_include_path}) {
	&tt2::add_include_path($d);
    }

    my @path = &tt2::get_include_path();
    my $filename = &tools::find_file($tpl.'.tt2',@path);
 
    unless (defined $filename) {
	&Log::do_log('err','Could not find template %s.tt2 in %s', $tpl, join(':',@path));
	return undef;
    }

    foreach my $p ('email','email_gecos','host','sympa','request','listmaster','wwsympa_url','title','listmaster_email') {
	$data->{'conf'}{$p} = &Conf::get_robot_conf($robot, $p);
    }

    $data->{'sender'} = $who;
    $data->{'conf'}{'version'} = $main::Version;
    $data->{'from'} = "$data->{'conf'}{'email'}\@$data->{'conf'}{'host'}" unless ($data->{'from'});
    $data->{'robot_domain'} = $robot;
    $data->{'return_path'} = &Conf::get_robot_conf($robot, 'request');
    $data->{'boundary'} = '----------=_'.&tools::get_message_id($robot) unless ($data->{'boundary'});

    if ((&Conf::get_robot_conf($robot, 'dkim_feature') eq 'on')&&(&Conf::get_robot_conf($robot, 'dkim_add_signature_to')=~/robot/)){
	$data->{'dkim'} = &tools::get_dkim_parameters({'robot' => $robot});
    }
    
    $data->{'use_bulk'} = 1  unless ($data->{'alarm'}) ; # use verp excepted for alarms. We should make this configurable in order to support Sympa server on a machine without any MTA service
    
    my $r = &mail::mail_file($filename, $who, $data, $robot, $options->{'parse_and_return'});
    return $r if($options->{'parse_and_return'});
    
    unless ($r) {
	&Log::do_log('err',"List::send_global_file, could not send template $filename to $who");
	return undef;
    }

    return 1;
}

####################################################
# send_file                              
####################################################
#  Send a message to a user, relative to a list.
#  Find the tt2 file according to $tpl, set up 
#  $data for the next parsing (with $context and
#  configuration)
#  Message is signed if the list has a key and a 
#  certificate
#  
# IN : -$self (+): ref(List)
#      -$tpl (+): template file name (file.tt2),
#         without tt2 extension
#      -$who (+): SCALAR |ref(ARRAY) - recipient(s)
#      -$robot (+): robot
#      -$context : ref(HASH) - for the $data set up 
#         to parse file tt2, keys can be :
#         -user : ref(HASH), keys can be :
#           -email
#           -lang
#           -password
#         -auto_submitted auto-generated|auto-replied|auto-forwarded
#         -...
# OUT : 1 | undef
####################################################
sub send_file {
    my($self, $tpl, $who, $robot, $context) = @_;
    &Log::do_log('debug2', 'List::send_file(%s, %s, %s)', $tpl, $who, $robot);

    my $name = $self->{'name'};
    my $sign_mode;

    my $data = &tools::dup_var($context);

    ## Any recipients
    if ((ref ($who) && ($#{$who} < 0)) ||
	(!ref ($who) && ($who eq ''))) {
	&Log::do_log('err', 'No recipient for sending %s', $tpl);
	return undef;
    }
    
    ## Unless multiple recipients
    unless (ref ($who)) {
	unless ($data->{'user'}) {
	    unless ($data->{'user'} = &get_global_user($who)) {
		$data->{'user'}{'email'} = $who;
		$data->{'user'}{'lang'} = $self->{'admin'}{'lang'};
	    }
	}
	
	$data->{'subscriber'} = $self->get_list_member($who);
	
	if ($data->{'subscriber'}) {
	    $data->{'subscriber'}{'date'} = gettext_strftime "%d %b %Y", localtime($data->{'subscriber'}{'date'});
	    $data->{'subscriber'}{'update_date'} = gettext_strftime "%d %b %Y", localtime($data->{'subscriber'}{'update_date'});
	    if ($data->{'subscriber'}{'bounce'}) {
		$data->{'subscriber'}{'bounce'} =~ /^(\d+)\s+(\d+)\s+(\d+)(\s+(.*))?$/;
		
		$data->{'subscriber'}{'first_bounce'} = gettext_strftime "%d %b %Y", localtime($1);
	    }
	}
	
	unless ($data->{'user'}{'password'}) {
	    $data->{'user'}{'password'} = &tools::tmp_passwd($who);
	}
	
	## Unique return-path VERP
	if ($self->welcome_return_path eq 'unique' and $tpl eq 'welcome') {
	    $data->{'return_path'} = $self->get_bounce_address($who, 'w');
	} elsif ($self->remind_return_path eq 'unique' and $tpl eq 'remind') {
	    $data->{'return_path'} = $self->get_bounce_address($who, 'r');
	}
    }

    $data->{'return_path'} ||= $self->get_list_address('return_path');

    ## Lang
    $data->{'lang'} = $data->{'user'}{'lang'} || $self->{'admin'}{'lang'} || &Conf::get_robot_conf($robot, 'lang');

    ## Trying to use custom_vars
    if (defined $self->{'admin'}{'custom_vars'}) {
	$data->{'custom_vars'} = {};
	foreach my $var (@{$self->{'admin'}{'custom_vars'}}) {
 	    $data->{'custom_vars'}{$var->{'name'}} = $var->{'value'};
	}
    }
    
    ## What file   
    my $lang = &Language::Lang2Locale($data->{'lang'});
    my $tt2_include_path = &tools::make_tt2_include_path($robot,'mail_tt2',$lang,$self);

    push @{$tt2_include_path},$self->{'dir'};             ## list directory to get the 'info' file
    push @{$tt2_include_path},$self->{'dir'}.'/archives'; ## list archives to include the last message

    foreach my $d (@{$tt2_include_path}) {
	&tt2::add_include_path($d);
    }

    foreach my $p ('email','email_gecos','host','sympa','request','listmaster','wwsympa_url','title','listmaster_email') {
	$data->{'conf'}{$p} = &Conf::get_robot_conf($robot, $p);
    }

    my @path = &tt2::get_include_path();
    my $filename = &tools::find_file($tpl.'.tt2',@path);
    
    unless (defined $filename) {
	&Log::do_log('err','Could not find template %s.tt2 in %s', $tpl, join(':',@path));
	return undef;
    }

    $data->{'sender'} ||= $who;
    $data->{'list'}{'lang'} = $self->{'admin'}{'lang'};
    $data->{'list'}{'name'} = $name;
    $data->{'list'}{'domain'} = $data->{'robot_domain'} = $robot;
    $data->{'list'}{'host'} = $self->{'admin'}{'host'};
    $data->{'list'}{'subject'} = $self->{'admin'}{'subject'};
    $data->{'list'}{'owner'} = $self->get_owners();
    $data->{'list'}{'dir'} = $self->{'dir'};

    ## Sign mode
    if ($Conf::Conf{'openssl'} &&
	(-r $self->{'dir'}.'/cert.pem') && (-r $self->{'dir'}.'/private_key')) {
	$sign_mode = 'smime';
    }

    # if the list have it's private_key and cert sign the message
    # . used only for the welcome message, could be usefull in other case? 
    # . a list should have several certificats and use if possible a certificat
    #   issued by the same CA as the receipient CA if it exists 
    if ($sign_mode eq 'smime') {
	$data->{'fromlist'} = $self->get_list_address();
	$data->{'replyto'} = $self->get_list_address('owner');
    }else{
	$data->{'fromlist'} = $self->get_list_address('owner');
    }

    $data->{'from'} = $data->{'fromlist'} unless ($data->{'from'});
    $data->{'boundary'} = '----------=_'.&tools::get_message_id($robot) unless ($data->{'boundary'});
    $data->{'sign_mode'} = $sign_mode;
    
    if ((&Conf::get_robot_conf($self->{'domain'}, 'dkim_feature') eq 'on')&&(&Conf::get_robot_conf($self->{'domain'}, 'dkim_add_signature_to')=~/robot/)){
	$data->{'dkim'} = &tools::get_dkim_parameters({ 'robot' => $self->domain });
    } 
    $data->{'use_bulk'} = 1  unless ($data->{'alarm'}) ; # use verp excepted for alarms. We should make this configurable in order to support Sympa server on a machine without any MTA service
	  # my $dump = &Dumper($data); open (DUMP,">>/tmp/dumper2"); printf DUMP '----------------data \n%s',$dump ; close DUMP; 
    unless (&mail::mail_file($filename, $who, $data, $self->{'domain'})) {
	&Log::do_log('err',"List::send_file, could not send template $filename to $who");
	return undef;
    }

    return 1;
}

####################################################
# send_msg                              
####################################################
# selects subscribers according to their reception 
# mode in order to distribute a message to a list
# and sends the message to them. For subscribers in reception mode 'mail', 
# and in a msg topic context, selects only one who are subscribed to the topic
# of the message.
# 
#  
# IN : -$self (+): ref(List)  
#      -$message (+): ref(Message)
# OUT : -$numsmtp : number of sendmail process 
#       | 0 : no subscriber for sending message in list
#       | undef 
####################################################
sub send_msg {

    my $self = shift;
    my %param = @_;

    my $message = $param{'message'};
    my $apply_dkim_signature = $param{'apply_dkim_signature'};
    my $apply_tracking = $param{'apply_tracking'};

    &Log::do_log('debug2', 'List::send_msg(filname = %s, smime_crypted = %s,apply_dkim_signature = %s )', $message->{'filename'}, $message->{'smime_crypted'},$apply_dkim_signature);
    my $hdr = $message->{'msg'}->head;
    my $original_message_id = $hdr->get('Message-Id');
    my $name = $self->name;
    my $robot = $self->domain;
    #my $admin = $self->admin;
    my $total = $self->get_real_total;
    my $sender_line = $hdr->get('From');
    my @sender_hdr = Mail::Address->parse($sender_line);
    my %sender_hash;
    foreach my $email (@sender_hdr) {
	$sender_hash{lc($email->address)} = 1;
    }
   
    unless (defined $message && ref($message) eq 'Message') {
	&Log::do_log('err', 'Invalid message paramater');
	return undef;	
    }

    unless ($total > 0) {
	&Log::do_log('info', 'No subscriber in list %s', $name);
	return 0;
    }

    ## Bounce rate
    my $rate = $self->get_total_bouncing() * 100 / $total;
    if ($rate > $self->bounce->{'warn_rate'}) {
	unless ($self->send_notify_to_owner('bounce_rate',{'rate' => $rate})) {
	    &Log::do_log('notice', 'Unable to send notify "bounce_rate" to %s listowner', $self);
	}
    }
 
    ## Who is the enveloppe sender?
    my $host = $self->host;
    my $from = $self->get_list_address('return_path');

    # separate subscribers depending on user reception option and also if verp a dicovered some bounce for them.
    my (@tabrcpt, @tabrcpt_notice, @tabrcpt_txt, @tabrcpt_html, @tabrcpt_url, @tabrcpt_verp, @tabrcpt_notice_verp, @tabrcpt_txt_verp, @tabrcpt_html_verp, @tabrcpt_url_verp, @tabrcpt_digestplain, @tabrcpt_digest, @tabrcpt_summary, @tabrcpt_nomail, @tabrcpt_digestplain_verp, @tabrcpt_digest_verp, @tabrcpt_summary_verp, @tabrcpt_nomail_verp );
    my $mixed = ($message->{'msg'}->head->get('Content-Type') =~ /multipart\/mixed/i);
    my $alternative = ($message->{'msg'}->head->get('Content-Type') =~ /multipart\/alternative/i);
    my $recip = $message->{'msg'}->head->get('X-Sympa-Receipient');
 

    if ($recip) {
	@tabrcpt = split /,/, $recip;
	$message->{'msg'}->head->delete('X-Sympa-Receipient');

    } else {

    for ( my $user = $self->get_first_list_member(); $user; $user = $self->get_next_list_member() ){
	unless ($user->{'email'}) {
	    &Log::do_log('err','Skipping user with no email address in list %s', $name);
	    next;
	}
	my $user_data = $self->user('member', $user->{'email'}) || undef;
	## test to know if the rcpt suspended her subscription for this list
	## if yes, don't send the message
	if (defined $user_data && $user_data->{'suspend'} eq '1'){
	    if(($user_data->{'startdate'} <= time) && ((time <= $user_data->{'enddate'}) || (!$user_data->{'enddate'}))){
		push @tabrcpt_nomail_verp, $user->{'email'}; next;
	    }elsif(($user_data->{'enddate'} < time) && ($user_data->{'enddate'})){
		## If end date is < time, update the BDD by deleting the suspending's data
		$self->restore_suspended_subscription($user->{'email'});
	    }
	}
	if ($user->{'reception'} eq 'digestplain') { # digest digestplain, nomail and summary reception option are initialized for tracking feature only
	    push @tabrcpt_digestplain_verp, $user->{'email'}; next;
	}elsif($user->{'reception'} eq 'digest') {
	    push @tabrcpt_digest_verp, $user->{'email'}; next;
	}elsif($user->{'reception'} eq 'summary'){
	    push @tabrcpt_summary_verp, $user->{'email'}; next;
	}elsif($user->{'reception'} eq 'nomail'){
	    push @tabrcpt_nomail_verp, $user->{'email'}; next;
	}elsif ($user->{'reception'} eq 'notice') {
	    if ($user->{'bounce_address'}) {
		push @tabrcpt_notice_verp, $user->{'email'}; 
	    }else{
		push @tabrcpt_notice, $user->{'email'}; 
	    }
	}elsif ($alternative and ($user->{'reception'} eq 'txt')) {
	    if ($user->{'bounce_address'}) {
		push @tabrcpt_txt_verp, $user->{'email'};
	    }else{
		push @tabrcpt_txt, $user->{'email'};
	    }
	}elsif ($alternative and ($user->{'reception'} eq 'html')) {
	    if ($user->{'bounce_address'}) {
		push @tabrcpt_html_verp, $user->{'email'};
	    }else{
		if ($user->{'bounce_address'}) {
		    push @tabrcpt_html_verp, $user->{'email'};
		}else{
		    push @tabrcpt_html, $user->{'email'};
		}
	    }
	} elsif ($mixed and ($user->{'reception'} eq 'urlize')) {
	    if ($user->{'bounce_address'}) {
	        push @tabrcpt_url_verp, $user->{'email'};
	    }else{
	        push @tabrcpt_url, $user->{'email'};
	    }
	} elsif ($message->{'smime_crypted'} && 
      	     (! -r $Conf::Conf{'ssl_cert_dir'}.'/'.&tools::escape_chars($user->{'email'}) &&
       	      ! -r $Conf::Conf{'ssl_cert_dir'}.'/'.&tools::escape_chars($user->{'email'}.'@enc' ))) {
       	    ## Missing User certificate
	    my $subject = $message->{'msg'}->head->get('Subject');
	    my $sender = $message->{'msg'}->head->get('From');
	    unless ($self->send_file('x509-user-cert-missing', $user->{'email'}, $robot, {'mail' => {'subject' => $subject, 'sender' => $sender}, 'auto_submitted' => 'auto-generated'})) {
	        &Log::do_log('notice',"Unable to send template 'x509-user-cert-missing' to $user->{'email'}");
	    }
	}else{
	    if ($user->{'bounce_score'}) {
		push @tabrcpt_verp, $user->{'email'} unless ($sender_hash{$user->{'email'}})&&($user->{'reception'} eq 'not_me');
	    }else{	    
		push @tabrcpt, $user->{'email'} unless ($sender_hash{$user->{'email'}})&&($user->{'reception'} eq 'not_me');}
	    }
	}    
    }

    unless (@tabrcpt || @tabrcpt_notice || @tabrcpt_txt || @tabrcpt_html || @tabrcpt_url || @tabrcpt_verp || @tabrcpt_notice_verp || @tabrcpt_txt_verp || @tabrcpt_html_verp || @tabrcpt_url_verp) {
	&Log::do_log('info', 'No subscriber for sending msg in list %s', $name);
	return 0;
    }

    #save the message before modifying it
    my $saved_msg = $message->{'msg'}->dup;
    my $nbr_smtp = 0;
    my $nbr_verp = 0;

    # prepare verp parameter
    my $verp_rate =  $self->verp_rate;
    $verp_rate = '100%' if (($apply_tracking eq 'dsn')||($apply_tracking eq 'mdn')); # force verp if tracking is requested.  

    my $xsequence = $self->stats->[0] ;
    my $tags_to_use;

    # Define messages which can be tagged as first or last according to the verp rate.
    # If the VERP is 100%, then all the messages are VERP. Don't try to tag not VERP
    # messages as they won't even exist.
    if($verp_rate eq '0%'){
	$tags_to_use->{'tag_verp'} = 0;
	$tags_to_use->{'tag_noverp'} = 1;
    }else{
	$tags_to_use->{'tag_verp'} = 1;
	$tags_to_use->{'tag_noverp'} = 0;
    }
 
    my $dkim_parameters ;
    # prepare dkim parameters
    if ($apply_dkim_signature eq 'on') {
	$dkim_parameters = &tools::get_dkim_parameters({ 'robot' => $self->domain, 'listname' => $self->name });
    }
    ## Storing the not empty subscribers' arrays into a hash.
    my $available_rcpt;
    my $available_verp_rcpt;

    if (@tabrcpt) {
	$available_rcpt->{'tabrcpt'} = \@tabrcpt;
	$available_verp_rcpt->{'tabrcpt'} = \@tabrcpt_verp;	
    }
    if (@tabrcpt_notice) {
	$available_rcpt->{'tabrcpt_notice'} = \@tabrcpt_notice;
	$available_verp_rcpt->{'tabrcpt_notice'} = \@tabrcpt_notice_verp;
    }
    if (@tabrcpt_txt) {
	$available_rcpt->{'tabrcpt_txt'} = \@tabrcpt_txt;
	$available_verp_rcpt->{'tabrcpt_txt'} = \@tabrcpt_txt_verp;
    }
    if (@tabrcpt_html) {
	$available_rcpt->{'tabrcpt_html'} = \@tabrcpt_html;
	$available_verp_rcpt->{'tabrcpt_html'} = \@tabrcpt_html_verp;
    }
    if (@tabrcpt_url) {
	$available_rcpt->{'tabrcpt_url'} = \@tabrcpt_url;
	$available_verp_rcpt->{'tabrcpt_url'} = \@tabrcpt_url_verp;
    }
    if (@tabrcpt_digestplain_verp)  {
	$available_rcpt->{'tabrcpt_digestplain'} = \@tabrcpt_digestplain;
	$available_verp_rcpt->{'tabrcpt_digestplain'} = \@tabrcpt_digestplain_verp;
    }
    if (@tabrcpt_digest_verp) {
	$available_rcpt->{'tabrcpt_digest'} = \@tabrcpt_digest;
	$available_verp_rcpt->{'tabrcpt_digest'} = \@tabrcpt_digest_verp;
    }
    if (@tabrcpt_summary_verp) {
	$available_rcpt->{'tabrcpt_summary'} = \@tabrcpt_summary;
	$available_verp_rcpt->{'tabrcpt_summary'} = \@tabrcpt_summary_verp;
    }
    if (@tabrcpt_nomail_verp) {
	$available_rcpt->{'tabrcpt_nomail'} = \@tabrcpt_nomail;
	$available_verp_rcpt->{'tabrcpt_nomail'} = \@tabrcpt_nomail_verp;
    }
    foreach my $array_name (keys %$available_rcpt) {
	my $reception_option ;	 
	if ($array_name =~ /^tabrcpt_((nomail)|(summary)|(digest)|(digestplain)|(url)|(html)|(txt)|(notice))?(_verp)?/) {
	    $reception_option =  $1;	    
	    $reception_option = 'mail' unless $reception_option ;
	}
	my $new_message;
	##Prepare message for normal reception mode
	if ($array_name eq 'tabrcpt'){
	    ## Add a footer
	    unless ($message->{'protected'}) {
		my $new_msg = $self->add_parts($message->{'msg'});
		if (defined $new_msg) {
		    $message->{'msg'} = $new_msg;
		    $message->{'altered'} = '_ALTERED_';
		}
	    }
	    $new_message = $message;	    
	}elsif(($array_name eq 'tabrcpt_nomail')||($array_name eq 'tabrcpt_summary')||($array_name eq 'tabrcpt_digest')||($array_name eq 'tabrcpt_digestplain')){
	    $new_message = $message;
	}	##Prepare message for notice reception mode
	elsif($array_name eq 'tabrcpt_notice'){
	    my $notice_msg = $saved_msg->dup;
	    $notice_msg->bodyhandle(undef);    
	    $notice_msg->parts([]);
	    $new_message = new Message({'mimeentity' => $notice_msg});

	##Prepare message for txt reception mode
	}elsif($array_name eq 'tabrcpt_txt'){
	    my $txt_msg = $saved_msg->dup;
	    if (&tools::as_singlepart($txt_msg, 'text/plain')) {
		&Log::do_log('notice', 'Multipart message changed to singlepart');
	    }
	    
	    ## Add a footer
	    my $new_msg = $self->add_parts($txt_msg);
	    if (defined $new_msg) {
		$txt_msg = $new_msg;
	    }
	    $new_message = new Message({'mimeentity' => $txt_msg});

	##Prepare message for html reception mode
	}elsif($array_name eq 'tabrcpt_html'){
	    my $html_msg = $saved_msg->dup;
	    if (&tools::as_singlepart($html_msg, 'text/html')) {
		&Log::do_log('notice', 'Multipart message changed to singlepart');
	    }
	    ## Add a footer
	    my $new_msg = $self->add_parts($html_msg);
	    if (defined $new_msg) {
		$html_msg = $new_msg;
	    }
	    $new_message = new Message({'mimeentity' => $html_msg});
	    
	##Prepare message for urlize reception mode
	}elsif($array_name eq 'tabrcpt_url'){
	    my $url_msg = $saved_msg->dup; 
	    
	    my $expl = $self->dir . '/urlized';
	    
	    unless ((-d $expl) ||( mkdir $expl, 0775)) {
		&Log::do_log('err', "Unable to create urlize directory $expl");
		return undef;
	    }
	    
	    my $dir1 = &tools::clean_msg_id($url_msg->head->get('Message-ID'));
	    
	    ## Clean up Message-ID
	    $dir1 = &tools::escape_chars($dir1);
	    $dir1 = '/'.$dir1;
	    
	    unless ( mkdir ("$expl/$dir1", 0775)) {
		&Log::do_log('err', "Unable to create urlize directory $expl/$dir1");
		printf "Unable to create urlized directory $expl/$dir1";
		return 0;
	    }
	    my $mime_types = &tools::load_mime_types();
	    my @parts = ();
	    my $i = 0;
	    foreach my $part ($url_msg->parts()) {
		my $entity = &_urlize_part($part, $self, $dir1, $i, $mime_types,  &Conf::get_robot_conf($robot, 'wwsympa_url'));
		if (defined $entity) {
		    push @parts, $entity;
		} else {
		    push @parts, $part;
		}
		$i++;
	    }
	    
	    ## Replace message parts
	    $url_msg->parts (\@parts);
	    
	    ## Add a footer
	    my $new_msg = $self->add_parts($url_msg);
	    if (defined $new_msg) {
		$url_msg = $new_msg;
	    } 
	    $new_message = new Message({'mimeentity' => $url_msg});
	}else {
	    &Log::do_log('err', "Unknown variable/reception mode $array_name");
	    return undef;
	}

	unless (defined $new_message) {
		&Log::do_log('err', "Failed to create Message object");
		return undef;	    
	}

	## TOPICS
	my @selected_tabrcpt;
	my @possible_verptabrcpt;
	if ($self->is_there_msg_topic()){
	    @selected_tabrcpt = $self->select_list_members_for_topic($new_message->get_topic(),$available_rcpt->{$array_name});
	    @possible_verptabrcpt = $self->select_list_members_for_topic($new_message->get_topic(),$available_verp_rcpt->{$array_name});
	} else {
	    @selected_tabrcpt = @{$available_rcpt->{$array_name}};
	    @possible_verptabrcpt = @{$available_verp_rcpt->{$array_name}};
	}
	
	if ($array_name =~ /^tabrcpt_((nomail)|(summary)|(digest)|(digestplain)|(url)|(html)|(txt)|(notice))?(_verp)?/) {
	    my $reception_option =  $1;
	    
	    $reception_option = 'mail' unless $reception_option ;
	}
	
	## Preparing VERP receipients.
	my @verp_selected_tabrcpt = &extract_verp_rcpt($verp_rate, $xsequence,\@selected_tabrcpt, \@possible_verptabrcpt);
	my $verp= 'off';

	my $result = &mail::mail_message('message'=>$new_message, 
					 'rcpt'=> \@selected_tabrcpt, 
					 'list'=>$self, 
					 'verp' => $verp,					 
					 'dkim_parameters'=>$dkim_parameters,
					 'tag_as_last' => $tags_to_use->{'tag_noverp'});
	unless (defined $result) {
	    &Log::do_log('err',"List::send_msg, could not send message to distribute from $from (verp disabled)");
	    return undef;
	}
	$tags_to_use->{'tag_noverp'} = 0 if ($result > 0);
	$nbr_smtp += $result;
	
	$verp= 'on';

	if (($apply_tracking eq 'dsn')||($apply_tracking eq 'mdn')){
	    $verp = $apply_tracking ;
	    &tracking::db_init_notification_table('listname' => $self->name,
						  'robot' => $robot,
						  'msgid' => $original_message_id, # what ever the message is transformed because of the reception option, tracking use the original message id
						  'rcpt' => \@verp_selected_tabrcpt, 
						  'reception_option' => $reception_option,
						  );
	    
	}	

	#  ignore those reception option where mail must not ne sent
        #  next if  (($array_name eq 'tabrcpt_digest') or ($array_name eq 'tabrcpt_digestlplain') or ($array_name eq 'tabrcpt_summary') or ($array_name eq 'tabrcpt_nomail')) ;
	next if  ($array_name =~ /^tabrcpt_((nomail)|(summary)|(digest)|(digestplain))(_verp)?/);
	
	## prepare VERP sending.
	$result = &mail::mail_message('message'=> $new_message, 
				      'rcpt'=> \@verp_selected_tabrcpt, 
				      'list'=> $self,
				      'verp' => $verp,
				      'dkim_parameters'=>$dkim_parameters,
				      'tag_as_last' => $tags_to_use->{'tag_verp'});
	unless (defined $result) {
	    &Log::do_log('err',"List::send_msg, could not send message to distribute from $from (verp enabled)");
	    return undef;
	}
	$tags_to_use->{'tag_verp'} = 0 if ($result > 0);
	$nbr_smtp += $result;
	$nbr_verp += $result;	
    }
    return $nbr_smtp;
}

###################   SERVICE MESSAGES   ##################################

###############################################################
# send_to_editor
###############################################################
# Sends a message to the list editor to ask him for moderation 
# ( in moderation context : editor or editorkey). The message 
# to moderate is set in spool queuemod with name containing
# a key (reference send to editor for moderation)
# In context of msg_topic defined the editor must tag it 
# for the moderation (on Web interface)
#  
# IN : -$self(+) : ref(List)
#      -$method : 'md5' - for "editorkey" | 'smtp' - for "editor"
#      -$message(+) : ref(Message) - the message to moderatte
# OUT : $modkey : the moderation key for naming message waiting 
#         for moderation in spool queuemod
#       | undef
#################################################################
sub send_to_editor {
   my($self, $method, $message) = @_;
   my $msg = $message->{'msg'};
   my $encrypt = 'smime_crypted' if ($message->{'smime_crypted'}); 
  &Log::do_log('debug', "List::send_to_editor, messagekey: $message->{'messagekey'}, method : $method, encrypt : $encrypt");

   my($i, @rcpt);
   my $admin = $self->{'admin'};
   my $name = $self->{'name'};
   my $host = $admin->{'host'};
   my $robot = $self->{'domain'};

   return unless ($name && $admin);
  
   my @now = localtime(time);
   my $messageid=$now[6].$now[5].$now[4].$now[3].$now[2].$now[1]."."
                 .int(rand(6)).int(rand(6)).int(rand(6)).int(rand(6)).int(rand(6)).int(rand(6))."\@".$host;
   my $modkey=Digest::MD5::md5_hex(join('/', $self->get_cookie(),$messageid));
   my $boundary ="__ \<$messageid\>";
   
   if ($method eq 'md5'){  
       # move message to spool  mod
       my $spoolmod = new Sympaspool('mod');
       $spoolmod->update({'messagekey' => $message->{'messagekey'}},{"authkey" => $modkey,'messagelock'=> 'NULL'});

       # prepare html view of this message
       my $destination_dir  = $Conf::Conf{'viewmail_dir'}.'/mod/'.$self->get_list_id().'/'.$modkey;
       &Archive::convert_single_msg_2_html ({'msg_as_string'=>$message->{'msg_as_string'},
					     'destination_dir'=>$destination_dir,
					     'attachement_url' => "viewmod/$name/$modkey",
					     'list'=>$self} );
   }
   @rcpt = $self->get_editors_email();
   
   my $hdr = $message->{'msg'}->head;

   ## Did we find a recipient?
   if ($#rcpt < 0) {
       &Log::do_log('notice', "No editor found for list %s. Trying to proceed ignoring nomail option", $self->{'name'});
       my $messageid = $hdr->get('Message-Id');
       
       @rcpt = $self->get_editors_email({'ignore_nomail',1});
       &Log::do_log('notice', 'Warning : no owner and editor defined at all in list %s', $name ) unless (@rcpt);
       
       ## Could we find a recipient by ignoring the "nomail" option?
       if ($#rcpt >= 0) {
	   &Log::do_log('notice', 'All the intended recipients of message %s in list %s have set the "nomail" option. Ignoring it and sending it to all of them.', $messageid, $self->{'name'} );
       }
       else {
	   &Log::do_log ('err','Impossible to send the moderation request for message %s to editors of list %s. Neither editor nor owner defined!',$messageid,$self->{'name'}) ;
	   return undef;
       }
   }

   my $subject = tools::decode_header($hdr, 'Subject');
   my $param = {'modkey' => $modkey,
		'boundary' => $boundary,
		'msg_from' => $message->{'sender'},
		'subject' => $subject,
		'spam_status' => $message->{'spam_status'},
		'mod_spool_size' => $self->get_mod_spool_size,
		'method' => $method};

   if ($self->is_there_msg_topic()) {
       $param->{'request_topic'} = 1;
   }

   foreach my $recipient (@rcpt) {
       if ($encrypt eq 'smime_crypted') {	       
	   ## is $msg->body_as_string respect base64 number of char per line ??
	   my $cryptedmsg = &tools::smime_encrypt($msg->head, $msg->body_as_string, $recipient); 
	   unless ($cryptedmsg) {
	       &Log::do_log('notice', 'Failed encrypted message for moderator');
	       #  send a generic error message : X509 cert missing
	       return undef;
	   }
	   $param->{'msg'} = $cryptedmsg;
       }else{
	   $param->{'msg'} = $msg;
       }
       # create a one time ticket that will be used as un md5 URL credential
       
       unless ($param->{'one_time_ticket'} = &Auth::create_one_time_ticket($recipient,$robot,'modindex/'.$name,'mail')){
	   &Log::do_log('notice',"Unable to create one_time_ticket for $recipient, service modindex/$name");
       }else{
	   &Log::do_log('debug',"ticket $param->{'one_time_ticket'} created");
       }
       &tt2::allow_absolute_path();
       $param->{'auto_submitted'} = 'auto-forwarded';

       unless ($self->send_file('moderate', $recipient, $self->{'domain'}, $param)) {
	   &Log::do_log('notice',"Unable to send template 'moderate' to $recipient");
	   return undef;
       }
   }
   return $modkey;
}

####################################################
# send_auth                              
####################################################
# Sends an authentication request for a sent message to distribute.
# The message for distribution is copied in the authqueue 
# spool in order to wait for confirmation by its sender.
# This message is named with a key.
# In context of msg_topic defined, the sender must tag it 
# for the confirmation
#  
# IN : -$self (+): ref(List)
#      -$message (+): ref(Message)
#
# OUT : $authkey : the key for naming message waiting 
#         for confirmation (or tagging) in spool queueauth
#       | undef
####################################################
sub send_auth {
   my($self, $message) = @_;
   my ($sender, $msg, $file) = ($message->{'sender'}, $message->{'msg'}, $message->{'filename'});
   &Log::do_log('debug3', 'List::send_auth(%s, %s)', $sender, $file);

   ## Ensure 1 second elapsed since last message
   sleep (1);

   my($i, @rcpt);
   my $admin = $self->{'admin'};
   my $name = $self->{'name'};
   my $host = $admin->{'host'};
   my $robot = $self->{'domain'};
   my $authqueue = $Conf::Conf{'queueauth'};
   return undef unless ($name && $admin);
  

   my @now = localtime(time);
   my $messageid = $now[6].$now[5].$now[4].$now[3].$now[2].$now[1]."."
                   .int(rand(6)).int(rand(6)).int(rand(6)).int(rand(6))
		   .int(rand(6)).int(rand(6))."\@".$host;
   my $authkey = Digest::MD5::md5_hex(join('/', $self->get_cookie(),$messageid));
   chomp $authkey;
  
   my $spool = new Sympaspool('auth');
   $spool->update({'messagekey' => $message->{'messagekey'}},{"spoolname" => 'auth','authkey'=> $authkey, 'messagelock'=> 'NULL'});
   my $param = {'authkey' => $authkey,
		'boundary' => "----------------- Message-Id: \<$messageid\>",
		'file' => $file};
   
   if ($self->is_there_msg_topic()) {
       $param->{'request_topic'} = 1;
   }

   &tt2::allow_absolute_path();
   $param->{'auto_submitted'} = 'auto-replied';
   unless ($self->send_file('send_auth',$sender,$robot,$param)) {
       &Log::do_log('notice',"Unable to send template 'send_auth' to $sender");
       return undef;
   }

   return $authkey;
}

####################################################
# request_auth                              
####################################################
# sends an authentification request for a requested 
# command .
# 
#  
# IN : -$self : ref(List) if is present
#      -$email(+) : recepient (the personn who asked 
#                   for the command)
#      -$cmd : -signoff|subscribe|add|del|remind if $self
#              -remind else
#      -$robot(+) : robot
#      -@param : 0 : used if $cmd = subscribe|add|del|invite
#                1 : used if $cmd = add 
#
# OUT : 1 | undef
#
####################################################
sub request_auth {
    &Log::do_log('debug2', 'List::request_auth(%s, %s, %s, %s)', @_);
    my $first_param = shift;
    my ($self, $email, $cmd, $robot, @param);

    if (ref($first_param) eq 'List') {
	$self = $first_param;
	$email= shift;
    }else {
	$email = $first_param;
    }
    $cmd = shift;
    $robot = shift;
    @param = @_;
    &Log::do_log('debug3', 'List::request_auth() List : %s,$email: %s cmd : %s',$self->{'name'},$email,$cmd);

    
    my $keyauth;
    my $data = {'to' => $email};


    if (ref($self) eq 'List') {
	my $listname = $self->{'name'};
	$data->{'list_context'} = 1;

	if ($cmd =~ /signoff$/){
	    $keyauth = $self->compute_auth ($email, 'signoff');
	    $data->{'command'} = "auth $keyauth $cmd $listname $email";
	    $data->{'type'} = 'signoff';
	    
	}elsif ($cmd =~ /subscribe$/){
	    $keyauth = $self->compute_auth ($email, 'subscribe');
	    $data->{'command'} = "auth $keyauth $cmd $listname $param[0]";
	    $data->{'type'} = 'subscribe';

	}elsif ($cmd =~ /add$/){
	    $keyauth = $self->compute_auth ($param[0],'add');
	    $data->{'command'} = "auth $keyauth $cmd $listname $param[0] $param[1]";
	    $data->{'type'} = 'add';
	    
	}elsif ($cmd =~ /del$/){
	    my $keyauth = $self->compute_auth($param[0], 'del');
	    $data->{'command'} = "auth $keyauth $cmd $listname $param[0]";
	    $data->{'type'} = 'del';

	}elsif ($cmd eq 'remind'){
	    my $keyauth = $self->compute_auth('','remind');
	    $data->{'command'} = "auth $keyauth $cmd $listname";
	    $data->{'type'} = 'remind';
	
	}elsif ($cmd eq 'invite'){
	    my $keyauth = $self->compute_auth($param[0],'invite');
	    $data->{'command'} = "auth $keyauth $cmd $listname $param[0]";
	    $data->{'type'} = 'invite';
	}

	$data->{'command_escaped'} = &tt2::escape_url($data->{'command'});
	$data->{'auto_submitted'} = 'auto-replied';
	unless ($self->send_file('request_auth',$email,$robot,$data)) {
	    &Log::do_log('notice',"Unable to send template 'request_auth' to $email");
	    return undef;
	}

    }else {
	if ($cmd eq 'remind'){
	    my $keyauth = &List::compute_auth('',$cmd);
	    $data->{'command'} = "auth $keyauth $cmd *";
	    $data->{'command_escaped'} = &tt2::escape_url($data->{'command'});
	    $data->{'type'} = 'remind';
	    
	}
	$data->{'auto_submitted'} = 'auto-replied';
	unless (&send_global_file('request_auth',$email,$robot,$data)) {
	    &Log::do_log('notice',"Unable to send template 'request_auth' to $email");
	    return undef;
	}
    }


    return 1;
}


####################################################
# archive_send                              
####################################################
# sends an archive file to someone (text archive
# file : independant from web archives)
#  
# IN : -$self(+) : ref(List)
#      -$who(+) : recepient
#      -file(+) : name of the archive file to send
# OUT : - | undef
#
######################################################
sub archive_send {
   my($self, $who, $file) = @_;
   &Log::do_log('debug', 'List::archive_send(%s, %s)', $who, $file);

   return unless ($self->is_archived());
       
   my $dir = &Conf::get_robot_conf($self->{'domain'},'arc_path').'/'.$self->get_list_id();
   my $msg_list = Archive::scan_dir_archive($dir, $file);

   my $subject = 'File '.$self->{'name'}.' '.$file ;
   my $param = {'to' => $who,
		'subject' => $subject,
		'msg_list' => $msg_list } ;

   $param->{'boundary1'} = &tools::get_message_id($self->{'domain'});
   $param->{'boundary2'} = &tools::get_message_id($self->{'domain'});
   $param->{'from'} = &Conf::get_robot_conf($self->{'domain'},'sympa');

#    open TMP2, ">/tmp/digdump"; &tools::dump_var($param, 0, \*TMP2); close TMP2;
$param->{'auto_submitted'} = 'auto-replied';
   unless ($self->send_file('get_archive',$who,$self->{'domain'},$param)) {
	   &Log::do_log('notice',"Unable to send template 'archive_send' to $who");
	   return undef;
       }

}

####################################################
# archive_send_last                              
####################################################
# sends last archive file
#  
# IN : -$self(+) : ref(List)
#      -$who(+) : recepient
# OUT : - | undef
#
######################################################
sub archive_send_last {
   my($self, $who) = @_;
   &Log::do_log('debug', 'List::archive_send_last(%s, %s)',$self->{'listname'}, $who);

   return unless ($self->is_archived());
   my $dir = $self->{'dir'}.'/archives' ;

   my $mail = new Message({'file' => "$dir/last_message",'noxsympato'=>'noxsympato'});
   unless (defined $mail) {
       &Log::do_log('err', 'Unable to create Message object %s', "$dir/last_message");
       return undef;
   }
   
   my @msglist;
   my $msg = {};
   $msg->{'id'} = 1;

   $msg->{'subject'} = &tools::decode_header($mail, 'Subject');
   $msg->{'from'} = &tools::decode_header($mail, 'From');
   $msg->{'date'} = &tools::decode_header($mail, 'Date');

   $msg->{'full_msg'} = $mail->{'msg'}->as_string;
   
   push @msglist,$msg;

   my $subject = 'File '.$self->{'name'}.'.last_message' ;
   my $param = {'to' => $who,
		'subject' => $subject,
		'msg_list' => \@msglist } ;


   $param->{'boundary1'} = &tools::get_message_id($self->{'domain'});
   $param->{'boundary2'} = &tools::get_message_id($self->{'domain'});
   $param->{'from'} = &Conf::get_robot_conf($self->{'domain'},'sympa');
   $param->{'auto_submitted'} = 'auto-replied';
#    open TMP2, ">/tmp/digdump"; &tools::dump_var($param, 0, \*TMP2); close TMP2;

   unless ($self->send_file('get_archive',$who,$self->{'domain'},$param)) {
	   &Log::do_log('notice',"Unable to send template 'archive_send' to $who");
	   return undef;
       }

}


###################   NOTIFICATION SENDING  ###############################


####################################################
# send_notify_to_listmaster                         
####################################################
# Sends a notice to listmaster by parsing
# listmaster_notification.tt2 template
#  
# IN : -$operation (+): notification type
#      -$robot (+): robot
#      -$param(+) : ref(HASH) | ref(ARRAY)
#       values for template parsing
#    
# OUT : 1 | undef
#       
###################################################### 
sub send_notify_to_listmaster {
	my ($operation, $robot, $data, $checkstack, $purge) = @_;
	
	if($checkstack or $purge) {
		foreach my $robot (keys %List::listmaster_messages_stack) {
			foreach my $operation (keys %{$List::listmaster_messages_stack{$robot}}) {
				my $first_age = time - $List::listmaster_messages_stack{$robot}{$operation}{'first'};
				my $last_age = time - $List::listmaster_messages_stack{$robot}{$operation}{'last'};
				next unless($purge or ($last_age > 30) or ($first_age > 60)); # not old enough to send and first not too old
				next unless($List::listmaster_messages_stack{$robot}{$operation}{'messages'});
				
				my %messages = %{$List::listmaster_messages_stack{$robot}{$operation}{'messages'}};
				&Log::do_log('info', 'got messages about "%s" (%s)', $operation, join(', ', keys %messages));
				
				##### bulk send
				foreach my $email (keys %messages) {
					my $param = {
						to => $email,
						auto_submitted => 'auto-generated',
						alarm => 1,
						operation => $operation,
						notification_messages => $messages{$email},
						boundary => '----------=_'.&tools::get_message_id($robot)
					};
					
					my $options = {};
					$options->{'skip_db'} = 1 if(($operation eq 'no_db') || ($operation eq 'db_restored'));
					
					&Log::do_log('info', 'send messages to %s', $email);
					unless(&send_global_file('listmaster_groupednotifications', $email, $robot, $param, $options)) {
						&Log::do_log('notice',"Unable to send template 'listmaster_notification' to $email") unless($operation eq 'logs_failed');
						return undef;
					}
				}
				
				&Log::do_log('info', 'cleaning stacked notifications');
				delete $List::listmaster_messages_stack{$robot}{$operation};
			}
		}
		return 1;
	}
	
	my $stack = 0;
	$List::listmaster_messages_stack{$robot}{$operation}{'first'} = time unless($List::listmaster_messages_stack{$robot}{$operation}{'first'});
	$List::listmaster_messages_stack{$robot}{$operation}{'counter'}++;
	$List::listmaster_messages_stack{$robot}{$operation}{'last'} = time;
	if($List::listmaster_messages_stack{$robot}{$operation}{'counter'} > 3) { # stack if too much messages w/ same code
		$stack = 1;
	}
	
	unless(defined $operation) {
		&Log::do_log('err','List::send_notify_to_listmaster(%s) : missing incoming parameter "$operation"');
		return undef;
	}
	
	unless($operation eq 'logs_failed') {
		&Log::do_log('debug2', 'List::send_notify_to_listmaster(%s,%s )', $operation, $robot );
		unless (defined $robot) {
			&Log::do_log('err','List::send_notify_to_listmaster(%s) : missing incoming parameter "$robot"');
			return undef;
		}
	}
	
	my $host = &Conf::get_robot_conf($robot, 'host');
	my $listmaster = &Conf::get_robot_conf($robot, 'listmaster');
	my $to = "$Conf::Conf{'listmaster_email'}\@$host";
	my $options = {}; ## options for send_global_file()
	
	if((ref($data) ne 'HASH') and (ref($data) ne 'ARRAY')) {
		&Log::do_log('err','List::send_notify_to_listmaster(%s,%s) : error on incoming parameter "$param", it must be a ref on HASH or a ref on ARRAY', $operation, $robot ) unless($operation eq 'logs_failed');
		return undef;
	}
	
	if(ref($data) ne 'HASH') {
		my $d = {};
		for my $i(0..$#{$data}) {
			$d->{"param$i"} = $data->[$i];
		}
		$data = $d;
	}
	
	$data->{'to'} = $to;
	$data->{'type'} = $operation;
	$data->{'auto_submitted'} = 'auto-generated';
	$data->{'alarm'} = 1;
	
	if($data->{'list'} && ref($data->{'list'}) eq 'List') {
		my $list = $data->{'list'};
		$data->{'list'} = {
			'name' => $list->{'name'},
			'host' => $list->{'domain'},
			'subject' => $list->{'admin'}{'subject'},
		};
	}
	
	my @tosend;
	
	if($operation eq 'automatic_bounce_management') {
		## Automatic action done on bouncing adresses
		delete $data->{'alarm'};
		my $list = new List ($data->{'list'}{'name'}, $robot);
		unless(defined $list) {
			&Log::do_log('err','Parameter %s is not a valid list', $data->{'list'}{'name'});
			return undef;
		}
		unless($list->send_file('listmaster_notification',$listmaster, $robot, $data, $options)) {
			&Log::do_log('notice',"Unable to send template 'listmaster_notification' to $listmaster");
			return undef;
		}
		return 1;
	}
	
	if(($operation eq 'no_db') || ($operation eq 'db_restored')) {
		## No DataBase |  DataBase restored
		$data->{'db_name'} = &Conf::get_robot_conf($robot, 'db_name');  
		$options->{'skip_db'} = 1; ## Skip DB access because DB is not accessible
	}
	
	if($operation eq 'loop_command') {
		## Loop detected in Sympa
		$data->{'boundary'} = '----------=_'.&tools::get_message_id($robot);
		&tt2::allow_absolute_path();
	}
	
	if(($operation eq 'request_list_creation') or ($operation eq 'request_list_renaming')) {
		foreach my $email (split (/\,/, $listmaster)) {
			my $cdata = &tools::dup_var($data);
			$cdata->{'one_time_ticket'} = &Auth::create_one_time_ticket($email,$robot,'get_pending_lists',$cdata->{'ip'});
			push @tosend, {
				email => $email,
				data => $cdata
			};
		}
	}else{
		push @tosend, {
			email => $listmaster,
			data => $data
		};
	}
	
	foreach my $ts (@tosend) {
		$options->{'parse_and_return'} = 1 if($stack);
		my $r = &send_global_file('listmaster_notification', $ts->{'email'}, $robot, $ts->{'data'}, $options);
		if($stack) {
			&Log::do_log('info', 'stacking message about "%s" for %s (%s)', $operation, $ts->{'email'}, $robot);
			push @{$List::listmaster_messages_stack{$robot}{$operation}{'messages'}{$ts->{'email'}}}, $r;
			return 1;
		}
		
		unless($r) {
			&Log::do_log('notice',"Unable to send template 'listmaster_notification' to $listmaster") unless($operation eq 'logs_failed');
			return undef;
		}
	}
	
	return 1;
}


####################################################
# send_notify_to_owner                              
####################################################
# Sends a notice to list owner(s) by parsing
# listowner_notification.tt2 template
# 
# IN : -$self (+): ref(List)
#      -$operation (+): notification type
#      -$param(+) : ref(HASH) | ref(ARRAY)
#       values for template parsing
#
# OUT : 1 | undef
#    
######################################################
sub send_notify_to_owner {
    
    my ($self,$operation,$param) = @_;
    &Log::do_log('debug2', 'List::send_notify_to_owner(%s, %s)', $self->{'name'}, $operation);

    my $host = $self->{'admin'}{'host'};
    my @to = $self->get_owners_email();
    my $robot = $self->{'domain'};

    unless (@to) {
	&Log::do_log('notice', 'No owner defined or all of them use nomail option in list %s ; using listmasters as default', $self->{'name'} );
	@to = split /,/, &Conf::get_robot_conf($robot, 'listmaster');
    }
    unless (defined $operation) {
	&Log::do_log('err','List::send_notify_to_owner(%s) : missing incoming parameter "$operation"', $self->{'name'});
	return undef;
    }

    if (ref($param) eq 'HASH') {

	$param->{'auto_submitted'} = 'auto-generated';
	$param->{'to'} =join(',', @to);
	$param->{'type'} = $operation;


	if ($operation eq 'warn-signoff') {
	    $param->{'escaped_gecos'} = $param->{'gecos'};
	    $param->{'escaped_gecos'} =~ s/\s/\%20/g;
	    $param->{'escaped_who'} = $param->{'who'};
	    $param->{'escaped_who'} =~ s/\s/\%20/g;
	    foreach my $owner (@to) {
		$param->{'one_time_ticket'} = &Auth::create_one_time_ticket($owner,$robot,'search/'.$self->{'name'}.'/'.$param->{'escaped_who'},$param->{'ip'});
		unless ($self->send_file('listowner_notification',[$owner], $robot,$param)) {
		    &Log::do_log('notice',"Unable to send template 'listowner_notification' to $self->{'name'} list owner $owner");		    
		}
	    }
	}elsif ($operation eq 'subrequest') {
	    $param->{'escaped_gecos'} = $param->{'gecos'};
	    $param->{'escaped_gecos'} =~ s/\s/\%20/g;
	    $param->{'escaped_who'} = $param->{'who'};
	    $param->{'escaped_who'} =~ s/\s/\%20/g;
	    foreach my $owner (@to) {
		$param->{'one_time_ticket'} = &Auth::create_one_time_ticket($owner,$robot,'subindex/'.$self->{'name'},$param->{'ip'});
		unless ($self->send_file('listowner_notification',[$owner], $robot,$param)) {
		    &Log::do_log('notice',"Unable to send template 'listowner_notification' to $self->{'name'} list owner $owner");		    
		}
	    }
	}else{
	    if ($operation eq 'sigrequest') {
		$param->{'escaped_who'} = $param->{'who'};
		$param->{'escaped_who'} =~ s/\s/\%20/g;
		$param->{'sympa'} = &Conf::get_robot_conf($self->{'domain'}, 'sympa');
		
	    }elsif ($operation eq 'bounce_rate') {
		$param->{'rate'} = int ($param->{'rate'} * 10) / 10;
	    }
	    unless ($self->send_file('listowner_notification',\@to, $robot,$param)) {
		&Log::do_log('notice',"Unable to send template 'listowner_notification' to $self->{'name'} list owner");
		return undef;
	    }
	}

    }elsif(ref($param) eq 'ARRAY') {	

	my $data = {'to' => join(',', @to),
		    'type' => $operation};

	for my $i(0..$#{$param}) {
		$data->{"param$i"} = $param->[$i];
 	}
 	unless ($self->send_file('listowner_notification', \@to, $robot, $data)) {
	    &Log::do_log('notice',"Unable to send template 'listowner_notification' to $self->{'name'} list owner");
	    return undef;
	}

    }else {

	&Log::do_log('err','List::send_notify_to_owner(%s,%s) : error on incoming parameter "$param", it must be a ref on HASH or a ref on ARRAY', $self->{'name'},$operation);
	return undef;
    }
    return 1;
}

#########################
## Delete a member's picture file
#########################
# remove picture from user $2 in list $1 
#########################
sub delete_list_member_picture {
    &Log::do_log('debug2', '(%s, %s)', @_);
    my ($self, $email) = @_;    

    my $fullfilename = undef;
    my $filename = &tools::md5_fingerprint($email);

    my $file = &Conf::get_robot_conf($self->domain, 'pictures_path') . '/' .
	       $self->get_list_id() . '/' . $filename;
    foreach my $ext ('.gif','.jpg','.jpeg','.png') {
	if (-f $file . $ext) {
  	    $fullfilename = $file . $ext;
  	    last;
  	} 	
    }

    if (defined $fullfilename) {
	unless(unlink($fullfilename)) {
	    &Log::do_log('err', 'Failed to delete %s', $fullfilename);
	    return undef;  
	}

	&Log::do_log('debug3', 'File deleted successfull: %s', $fullfilename);
    }

    return 1;
}


####################################################
# send_notify_to_editor                             
####################################################
# Sends a notice to list editor(s) or owner (if no editor)
# by parsing listeditor_notification.tt2 template
# 
# IN : -$self (+): ref(List)
#      -$operation (+): notification type
#      -$param(+) : ref(HASH) | ref(ARRAY)
#       values for template parsing
#
# OUT : 1 | undef
#    
######################################################
sub send_notify_to_editor {

    my ($self,$operation,$param) = @_;
    &Log::do_log('debug2', 'List::send_notify_to_editor(%s, %s)', $self->{'name'}, $operation);

    my @to = $self->get_editors_email();
    my $robot = $self->{'domain'};
    $param->{'auto_submitted'} = 'auto-generated';
      
      unless (@to) {
	&Log::do_log('notice', 'Warning : no editor or owner defined or all of them use nomail option in list %s', $self->{'name'} );
	return undef;
    }
    unless (defined $operation) {
	&Log::do_log('err','List::send_notify_to_editor(%s) : missing incoming parameter "$operation"', $self->{'name'});
	return undef;
    }
    if (ref($param) eq 'HASH') {

	$param->{'to'} =join(',', @to);
	$param->{'type'} = $operation;

	unless ($self->send_file('listeditor_notification',\@to, $robot,$param)) {
	    &Log::do_log('notice',"Unable to send template 'listeditor_notification' to $self->{'name'} list editor");
	    return undef;
	}
	
    }elsif(ref($param) eq 'ARRAY') {	
	
	my $data = {'to' => join(',', @to),
		    'type' => $operation};
	
	foreach my $i(0..$#{$param}) {
	    $data->{"param$i"} = $param->[$i];
 	}
 	unless ($self->send_file('listeditor_notification', \@to, $robot, $data)) {
	    &Log::do_log('notice',"Unable to send template 'listeditor_notification' to $self->{'name'} list editor");
	    return undef;
	}	
	
    }else {
	&Log::do_log('err','List::send_notify_to_editor(%s,%s) : error on incoming parameter "$param", it must be a ref on HASH or a ref on ARRAY', $self->{'name'},$operation);
	return undef;
    }
    return 1;
}


####################################################
# send_notify_to_user                             
####################################################
# Send a notice to a user (sender, subscriber ...)
# by parsing user_notification.tt2 template
# 
# IN : -$self (+): ref(List)
#      -$operation (+): notification type
#      -$user(+): email of notified user
#      -$param(+) : ref(HASH) | ref(ARRAY)
#       values for template parsing
#
# OUT : 1 | undef
#    
######################################################
sub send_notify_to_user{

    my ($self,$operation,$user,$param) = @_;
    &Log::do_log('debug2', 'List::send_notify_to_user(%s, %s, %s)', $self->{'name'}, $operation, $user);

    my $host = $self->{'admin'}->{'host'};
    my $robot = $self->{'domain'};
    $param->{'auto_submitted'} = 'auto-generated';

    unless (defined $operation) {
	&Log::do_log('err','List::send_notify_to_user(%s) : missing incoming parameter "$operation"', $self->{'name'});
	return undef;
    }
    unless ($user) {
	&Log::do_log('err','List::send_notify_to_user(%s) : missing incoming parameter "$user"', $self->{'name'});
	return undef;
    }
    
    if (ref($param) eq "HASH") {
	$param->{'to'} = $user;
	$param->{'type'} = $operation;

	if ($operation eq 'auto_notify_bouncers') {	
	}
	
 	unless ($self->send_file('user_notification',$user,$robot,$param)) {
	    &Log::do_log('notice',"Unable to send template 'user_notification' to $user");
	    return undef;
	}

    }elsif (ref($param) eq "ARRAY") {	
	
	my $data = {'to' => $user,
		    'type' => $operation};
	
	for my $i(0..$#{$param}) {
	    $data->{"param$i"} = $param->[$i];
 	}
 	unless ($self->send_file('user_notification',$user,$robot,$data)) {
	    &Log::do_log('notice',"Unable to send template 'user_notification' to $user");
	    return undef;
	}	
	
    }else {
	
	&Log::do_log('err','List::send_notify_to_user(%s,%s,%s) : error on incoming parameter "$param", it must be a ref on HASH or a ref on ARRAY', 
		$self->{'name'},$operation,$user);
	return undef;
    }
    return 1;
}
#                                                                         #
#                                                                         #  
#                                                                         #
################### END functions for sending messages ####################



## genererate a md5 checksum using private cookie and parameters
sub compute_auth {
    &Log::do_log('debug3', 'List::compute_auth(%s, %s, %s)', @_);

    my $first_param = shift;
    my ($self, $email, $cmd);
    
    if (ref($first_param) eq 'List') {
	$self = $first_param;
	$email= shift;
    }else {
	$email = $email;
    }
    $cmd = shift;

    $email =~ y/[A-Z]/[a-z]/;
    $cmd =~ y/[A-Z]/[a-z]/;

    my ($cookie, $key, $listname) ;

    if ($self){
	$listname = $self->{'name'};
        $cookie = $self->get_cookie() || $Conf::Conf{'cookie'};
    }else {
	$cookie = $Conf::Conf{'cookie'};
    }
    
    $key = substr(Digest::MD5::md5_hex(join('/', $cookie, $listname, $email, $cmd)), -8) ;

    return $key;
}


## Add footer/header to a message
sub add_parts {
    my ($self, $msg) = @_;
    my ($listname,$type) = ($self->{'name'}, $self->{'admin'}{'footer_type'});
    my $listdir = $self->{'dir'};
    &Log::do_log('debug2', 'List:add_parts(%s, %s, %s)', $msg, $listname, $type);

    my ($header, $headermime);
    foreach my $file ("$listdir/message.header", 
		      "$listdir/message.header.mime",
		      "$Conf::Conf{'etc'}/mail_tt2/message.header", 
		      "$Conf::Conf{'etc'}/mail_tt2/message.header.mime") {
	if (-f $file) {
	    unless (-r $file) {
		&Log::do_log('notice', 'Cannot read %s', $file);
		next;
	    }
	    $header = $file;
	    last;
	} 
    }

    my ($footer, $footermime);
    foreach my $file ("$listdir/message.footer", 
		      "$listdir/message.footer.mime",
		      "$Conf::Conf{'etc'}/mail_tt2/message.footer", 
		      "$Conf::Conf{'etc'}/mail_tt2/message.footer.mime") {
	if (-f $file) {
	    unless (-r $file) {
		&Log::do_log('notice', 'Cannot read %s', $file);
		next;
	    }
	    $footer = $file;
	    last;
	} 
    }
    
    ## No footer/header
    unless (($footer and -s $footer) or ($header and -s $header)) {
 	return undef;
    }
    
    if ($type eq 'append'){
	## append footer/header
	my ($footer_msg, $header_msg);
	if ($header and -s $header) {
	    open HEADER, $header;
	    $header_msg = join '', <HEADER>;
	    close HEADER;
	    $header_msg = '' unless $header_msg =~ /\S/;
	}
	if ($footer and -s $footer) {
	    open FOOTER, $footer;
	    $footer_msg = join '', <FOOTER>;
	    close FOOTER;
	    $footer_msg = '' unless $footer_msg =~ /\S/;
	}
	if (length $header_msg or length $footer_msg) {
	    if (&_append_parts($msg, $header_msg, $footer_msg)) {
		$msg->sync_headers(Length => 'COMPUTE')
		    if $msg->head->get('Content-Length');
	    }
	}
    } else {
	## MIME footer/header
	my $parser = new MIME::Parser;
	$parser->output_to_core(1);

	my $content_type = $msg->effective_type || 'text/plain';

	if ($content_type =~ /^multipart\/alternative/i || $content_type =~ /^multipart\/related/i) {

	    &Log::do_log('notice', 'Making $1 into multipart/mixed'); 
	    $msg->make_multipart("mixed",Force=>1); 
	}
	
	if ($header and -s $header) {
	    if ($header =~ /\.mime$/) {
		my $header_part;
		eval { $header_part = $parser->parse_in($header); };
		if ($@) {
		    &Log::do_log('err', 'Failed to parse MIME data %s: %s',
				 $header, $parser->last_error);
		} else {
		    $msg->make_multipart unless $msg->is_multipart;
		    $msg->add_part($header_part, 0); ## Add AS FIRST PART (0)
		}
	    ## text/plain header
	    }else {
		
		$msg->make_multipart unless $msg->is_multipart;
		my $header_part = build MIME::Entity Path        => $header,
		Type        => "text/plain",
		Filename    => undef,
		'X-Mailer'  => undef,
		Encoding    => "8bit",
		Charset     => "UTF-8";
		$msg->add_part($header_part, 0);
	    }
	}
	if ($footer and -s $footer) {
	    if ($footer =~ /\.mime$/) {
		my $footer_part;
		eval { $footer_part = $parser->parse_in($footer); };
		if ($@) {
		    &Log::do_log('err', 'Failed to parse MIME data %s: %s',
				 $footer, $parser->last_error);
		} else {
		    $msg->make_multipart unless $msg->is_multipart;
		    $msg->add_part($footer_part);
		}
	    ## text/plain footer
	    }else {
		
		$msg->make_multipart unless $msg->is_multipart;
		$msg->attach(Path        => $footer,
			     Type        => "text/plain",
			     Filename    => undef,
			     'X-Mailer'  => undef,
			     Encoding    => "8bit",
			     Charset     => "UTF-8"
			     );
	    }
	}
    }

    return $msg;
}

sub _append_parts {
    my $part = shift;
    my $header_msg = shift || '';
    my $footer_msg = shift || '';

    my $eff_type = $part->effective_type || 'text/plain';

    if ($eff_type eq 'text/plain') {
	my $cset = MIME::Charset->new('UTF-8');
	$cset->encoder($part->head->mime_attr('Content-Type.Charset')||'NONE');

	my $body;
	if (defined $part->bodyhandle) {
	    $body = $part->bodyhandle->as_string;
	} else {
	    $body = '';
	}

	## Only encodable footer/header are allowed.
	if ($cset->encoder) {
	    eval {
		$header_msg = $cset->encode($header_msg, 1);
	    };
	    $header_msg = '' if $@;
	    eval {
		$footer_msg = $cset->encode($footer_msg, 1);
	    };
	    $footer_msg = '' if $@;
	} else {
	    $header_msg = '' if $header_msg =~ /[^\x01-\x7F]/;
	    $footer_msg = '' if $footer_msg =~ /[^\x01-\x7F]/;
	}

	if (length $header_msg or length $footer_msg) {
	    $header_msg .= "\n"
		if length $header_msg and $header_msg !~ /\n$/;
	    $body .= "\n"
		if length $footer_msg and length $body and $body !~ /\n$/;

	    my $io = $part->bodyhandle->open('w');
	    unless (defined $io) {
		&Log::do_log('err', "List::add_parts: Failed to save message : $!");
		return undef;
	    }
	    $io->print($header_msg);
	    $io->print($body);
	    $io->print($footer_msg);
	    $io->close;
	    $part->sync_headers(Length => 'COMPUTE')
		if $part->head->get('Content-Length');
	}
	return 1;
    } elsif ($eff_type eq 'multipart/mixed') {
	## Append to first part if text/plain
	if ($part->parts and
	    &_append_parts($part->parts(0), $header_msg, $footer_msg)) {
	    return 1;
	}
    } elsif ($eff_type eq 'multipart/alternative') {
	## Append to first text/plain part
	foreach my $p ($part->parts) {
	    if (&_append_parts($p, $header_msg, $footer_msg)) {
		return 1;
	    }
	}
    }

    return undef;
}

## Delete a user in the user_table
sub delete_global_user {
    my @users = @_;
    
    &Log::do_log('debug2', '');
    
    return undef unless ($#users >= 0);
    
    foreach my $who (@users) {
	$who = &tools::clean_email($who);
	## Update field
	
	unless (&SDM::do_query("DELETE FROM user_table WHERE (email_user =%s)", &SDM::quote($who))) {
	    &Log::do_log('err','Unable to delete user %s', $who);
	    next;
	}
    }

    return $#users + 1;
}

## Delete the indicate list member 
## IN : - ref to array 
##      - option exclude
##
## $list->delete_list_member('users' => \@u, 'exclude' => 1)
## $list->delete_list_member('users' => [$email], 'exclude' => 1)
sub delete_list_member {
    &Log::do_log('debug2', '(%s, %s => %s, ...)', @_);
    my $self = shift;
    my %param = @_;
    my @u = @{$param{'users'}};
    my $exclude = $param{'exclude'};
    my $parameter = $param{'parameter'};#case of deleting : bounce? manual signoff or deleted by admin?
    my $daemon_name = $param{'daemon'};

    my $name = $self->name;
    my $total = 0;

    foreach my $who (@u) {
	$who = &tools::clean_email($who);

	## Include in exclusion_table only if option is set.
	if($exclude == 1){
	    ## Insert in exclusion_table if $user->{'included'} eq '1'
	    $self->insert_delete_exclusion($who, 'insert');
	    
	}

	$self->user('member', $who, 0);

	## Delete record in SUBSCRIBER
	unless(&SDM::do_prepared_query('DELETE FROM subscriber_table WHERE user_subscriber = ? AND list_subscriber = ? AND robot_subscriber = ?',
				       $who, $name, $self->domain)) {
	    &Log::do_log('err', 'Unable to remove member %s on list %s',
				$who, $self);
	    next;
	}

	$self->delete_list_member_picture($who);

	#log in stat_table to make statistics
	&Log::db_stat_log({'robot' => $self->domain, 'list' => $name, 'operation' => 'del subscriber', 'parameter' => $parameter, 'mail' => $who, 'client' => '', 'daemon' => $daemon_name});

	$total--;
    }

    $self->total($self->total + $total);
    $self->savestats();

    return (-1 * $total);
}


## Delete the indicated admin users from the list.
sub delete_list_admin {
    &Log::do_log('debug2', '(%s, %s, ...)', @_);
    my($self, $role, @u) = @_;

    my $name = $self->name;
    my $total = 0;
    
    foreach my $who (@u) {
	$who = &tools::clean_email($who);

	$self->user($role, $who, 0);
	    
	## Delete record in ADMIN
	unless(&SDM::do_prepared_query('DELETE FROM admin_table WHERE user_admin = ? AND list_admin = ? AND robot_admin = ? AND role_admin = ?',
				       $who, $name, $self->domain, $role)) {
	    &Log::do_log('err','Unable to remove admin %s on list %s',
			 $who, $self);
	    next;
	}   
	
	$total--;
    }
    
    return (-1 * $total);
}

## Delete all admin_table entries
sub delete_all_list_admin {
    &Log::do_log('debug2', '()'); 

    my $total = 0;

    ## Delete record in ADMIN
    unless($sth = &SDM::do_prepared_query('DELETE FROM admin_table')) {
	&Log::do_log('err','Unable to remove all admin from database');
	return undef;
    }   
    
    return 1;
}


## Returns the cookie for a list, if any.
sub get_cookie {
   return shift->{'admin'}{'cookie'};
}

## Returns the maximum size allowed for a message to the list.
sub get_max_size {
   return shift->{'admin'}{'max_size'};
}

## Returns an array with the Reply-To data
sub get_reply_to {
    my $admin = shift->{'admin'};

    my $value = $admin->{'reply_to_header'}{'value'};

    $value = $admin->{'reply_to_header'}{'other_email'} if ($value eq 'other_email');

    return $value
}

## Returns a default user option
sub get_default_user_options {
    my $self = shift->{'admin'};
    my $what = shift;
    &Log::do_log('debug3', 'List::get_default_user_options(%s)', $what);

    if ($self) {
	return $self->{'default_user_options'};
    }
    return undef;
}

## Returns the number of subscribers to the list
## not using cache.
sub get_real_total {
    &Log::do_log('debug2', '(%s)', @_);
    my $self = shift;

    push @sth_stack, $sth;

    ## Query the Database
    unless ($sth = &SDM::do_prepared_query('SELECT count(*) FROM subscriber_table WHERE list_subscriber = ? AND robot_subscriber = ?',
					   $self->name, $self->domain)) {
	&Log::do_log('debug','Unable to get subscriber count for list %s',
		     $self);
	$sth = pop @sth_stack;
	return undef;
    }
    my $total = $sth->fetchrow;
    $sth->finish();

    $sth = pop @sth_stack;

    return $self->total($total);
}

## Returns a hash for a given user
sub get_global_user {
    &Log::do_log('debug2', '(%s)', @_);
    my $who = &tools::clean_email(shift);

    ## Additional subscriber fields
    my $additional = '';
    if ($Conf::Conf{'db_additional_user_fields'}) {
	$additional = ', ' . $Conf::Conf{'db_additional_user_fields'};
    }

    push @sth_stack, $sth;

    unless ($sth = &SDM::do_prepared_query(sprintf('SELECT email_user AS email, gecos_user AS gecos, password_user AS password, cookie_delay_user AS cookie_delay, lang_user AS lang, attributes_user AS attributes, data_user AS data, last_login_date_user AS last_login_date, wrong_login_count_user AS wrong_login_count, last_login_host_user AS last_login_host%s FROM user_table WHERE email_user = ?',
						   $additional),
					   $who)) {
	&Log::do_log('err', 'Failed to prepare SQL query');
	$sth = pop @sth_stack;
	return undef;
    }

    my $user = $sth->fetchrow_hashref('NAME_lc');
    $sth->finish();

    $sth = pop @sth_stack;

    if (defined $user) {
	## decrypt password
	if ($user->{'password'}) {
	    $user->{'password'} = &tools::decrypt_password($user->{'password'});
	}

	## Turn user_attributes into a hash
	my $attributes = $user->{'attributes'};
	$user->{'attributes'} = undef;
	foreach my $attr (split (/\;/, $attributes)) {
	    my ($key, $value) = split (/\=/, $attr);
	    $user->{'attributes'}{$key} = $value;
	}    
	## Turn data_user into a hash
	 if ($user->{'data'}) {
	     my %prefs = &tools::string_2_hash($user->{'data'});
	     $user->{'prefs'} = \%prefs;
	 }
    }

    return $user;
}

## Returns an array of all users in User table hash for a given user
sub get_all_global_user {
    &Log::do_log('debug2', '()');

    my @users;

    push @sth_stack, $sth;

    unless ($sth = &SDM::do_prepared_query('SELECT email_user FROM user_table')) {
	&Log::do_log('err','Unable to gather all users in DB');
	$sth = pop @sth_stack;
	return undef;
    }

    while (my $email = ($sth->fetchrow_array)[0]) {
	push @users, $email;
    }
    $sth->finish();

    $sth = pop @sth_stack;

    return @users;
}

######################################################################
###  suspend_subscription                                            #
## Suspend an user from list(s)                                      #
######################################################################
# IN:                                                                #
#   - email : the subscriber email                                   #
#   - data : start_date and end_date                                 #
# OUT:                                                               #
#   - undef if something went wrong.                                 #
#   - 1 if user is suspended from the list                           #
######################################################################
sub suspend_subscription {
    &Log::do_log('debug2', '(%s, %s, %s)', @_);
    my $self = shift;
    my $email = shift;
    my $data = shift;

    croak "Invalid parameter: $self" unless ref $self; #prototype changed (6.2)

    unless (&SDM::do_prepared_query('UPDATE subscriber_table SET suspend_subscriber = 1, suspend_start_date_subscriber = ?, suspend_end_date_subscriber = ? WHERE user_subscriber = ? AND list_subscriber = ? AND robot_subscriber = ?', 
				    $data->{'startdate'}, $data->{'enddate'},
				    $email, $self->name, $self->domain)) {
	&Log::do_log('err', 'Unable to suspend subscription of user %s to list %s', $email, $self);
	return undef;
    }

    return 1;
}

######################################################################
###  restore_suspended_subscription                                  #
## Restore the subscription of an user from list(s)                  #
######################################################################
# IN:                                                                #
#   - email : the subscriber email                                   #
# OUT:                                                               #
#   - undef if something went wrong.                                 #
#   - 1 if his/her subscription is restored                          #
######################################################################
sub restore_suspended_subscription {
    &Log::do_log('debug2', '(%s, %s)', @_);
    my $self = shift;
    my $email = shift;

    croak "Invalid parameter: $self" unless ref $self; #prototype changed (6.2)

    unless (&SDM::do_prepared_query('UPDATE subscriber_table SET suspend_subscriber = 0, suspend_start_date_subscriber = NULL, suspend_end_date_subscriber = NULL WHERE user_subscriber = ? AND list_subscriber = ? AND robot_subscriber = ?',  
				    $email, $self->name, $self->domain)) {
	&Log::do_log('err','Unable to restore subscription of user %s to list %s', $email, $self);
	return undef;
    }

    return 1;
}

######################################################################
###  insert_delete_exclusion                                         #
## Update the exclusion_table                                        #
######################################################################
# IN:                                                                #
#   - email : the subscriber email                                   #
#   - action : insert or delete                                      #
# OUT:                                                               #
#   - undef if something went wrong.                                 #
#   - 1                                                              #
######################################################################
sub insert_delete_exclusion {
    &Log::do_log('debug2', '(%s, %s, %s, %s)', @_);
    my $self = shift;
    my $email = shift;
    my $action = shift;

    croak "Invalid parameter: $self" unless ref $self; #prototype changed (6.2)

    my $name = $self->name;
    my $robot = $self->domain;

    my $r = 1;
    
    if($action eq 'insert'){
	## INSERT only if $user->{'included'} eq '1'
	my $user = $self->user('member', $email) || undef;
	my $date = time;

	if ($user->{'included'} eq '1') {
	    ## Insert : list, user and date
	    unless (&SDM::do_query('INSERT INTO exclusion_table (list_exclusion, robot_exclusion, user_exclusion, date_exclusion) VALUES (%s, %s, %s, %s)', &SDM::quote($name), &SDM::quote($robot), &SDM::quote($email), &SDM::quote($date))) {
		&Log::do_log('err','Unable to exclude user %s from list %s', $email, $self);
		return undef;
	    }
	}
    } elsif ($action eq 'delete') {
	## If $email is in exclusion_table, delete it.
	my $data_excluded = $self->get_exclusion();
	my @users_excluded;

	my $key =0;
	while ($data_excluded->{'emails'}->[$key]) {
	    push @users_excluded, $data_excluded->{'emails'}->[$key];
	    $key = $key + 1;
	}
	
	$r = 0;
	my $sth;
	foreach my $users (@users_excluded) {
	    if ($email eq $users) {
		## Delete : list, user and date
		unless ($sth = &SDM::do_query('DELETE FROM exclusion_table WHERE (list_exclusion = %s AND robot_exclusion = %s AND user_exclusion = %s)', &SDM::quote($name), &SDM::quote($robot), &SDM::quote($email))) {
		    &Log::do_log('err', 'Unable to remove entry %s for list %s from table exclusion_table', $email, $self);
		}
		$r = $sth->rows;
	    }
	}
    } else {
	&Log::do_log('err', 'Unknown action %s', $action);
	return undef;
    }
   
    return $r;
}

######################################################################
###  get_exclusion                                                   #
## Returns a hash with those excluded from the list and the date.    #
##                                                                   # 
# IN:  - name : the name of the list                                 #
# OUT: - data_exclu : * %data_exclu->{'emails'}->[]                  #
#                     * %data_exclu->{'date'}->[]                    # 
######################################################################
sub get_exclusion {
    &Log::do_log('debug2', '(%s)', @_);
    my $self = shift;

    croak "Invalid parameter: $self" unless ref $self; #prototype changed (6.2)

    my $name = $self->name;
    my $robot = $self->domain;

    push @sth_stack, $sth;

    if (defined $self->family_name and $self->family_name ne '') {
	unless ($sth = &SDM::do_query("SELECT user_exclusion AS email, date_exclusion AS date FROM exclusion_table WHERE (list_exclusion = %s OR family_exclusion = %s) AND robot_exclusion=%s", 
				      &SDM::quote($name), &SDM::quote($self->family_name), &SDM::quote($robot))) {
	    &Log::do_log('err','Unable to retrieve excluded users for list %s@%s',$name, $robot);
	    $sth = pop @sth_stack;
	    return undef;
	}
    } else {
	unless ($sth = &SDM::do_query("SELECT user_exclusion AS email, date_exclusion AS date FROM exclusion_table WHERE list_exclusion = %s AND robot_exclusion=%s", 
				      &SDM::quote($name), &SDM::quote($robot))) {
	    &Log::do_log('err','Unable to retrieve excluded users for list %s@%s',$name, $robot);
	    $sth = pop @sth_stack;
	    return undef;
	}
    }

    my @users;
    my @date;
    my $data;
    while ($data = $sth->fetchrow_hashref) {
	push @users, $data->{'email'};
	push @date, $data->{'date'};
    }
    ## in order to use the data, we add the emails and dates in differents array
    my $data_exclu = {"emails" => \@users,
		      "date"   => \@date
		      };
    $sth->finish();

    $sth = pop @sth_stack;

    unless($data_exclu){
	&Log::do_log('err','Unable to retrieve information from database for list %s', $self);
	return undef;
    }
    return $data_exclu;
}

######################################################################
###  get_list_member                                                  #
## Returns a subscriber of the list.  
## Options : 
##    probe : don't log error if user does not exist                             #
######################################################################
sub get_list_member {
    &Log::do_log('debug2', '(%s, %s)', @_);
    my $self = shift;
    return $self->user('member', shift) || undef;
}

#######################################################################
# IN
#   - a single reference to a hash with the following keys:          #
#     * email : the subscriber email                                 #
#     * name: the name of the list                                   #
#     * domain: the virtual host under which the list is installed.  #
#
# OUT : undef if something wrong
#       a hash of tab of ressembling emails
sub get_ressembling_list_members_no_object {
    my $options = shift;
    &Log::do_log('debug2', '(%s, %s, %s)', $options->{'name'}, $options->{'email'}, $options->{'domain'});
    my $name = $options->{'name'};
    my @output;


    
    my $email = &tools::clean_email($options->{'email'});
    my $robot = $options->{'domain'};
    my $listname = $options->{'name'};
    
    
    $email =~ /^(.*)\@(.*)$/;
    my $local_part = $1;
    my $subscriber_domain = $2;
    my %subscribers_email;



    ##### plused
    # is subscriber a plused email ?
    if ($local_part =~ /^(.*)\+(.*)$/) {

	foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => $1.'@'.$subscriber_domain,'name'=>$listname,'domain'=>$robot})){
	    next if ($subscribers_email{$subscriber->{'email'}});
	    $subscribers_email{$subscriber->{'email'}} = 1;
	    push @output,$subscriber;
	}			       
    }
    # is some subscriber ressembling with a plused email ?    
    foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => $local_part.'+%@'.$subscriber_domain,'name'=>$listname,'domain'=>$robot})){
    	next if ($subscribers_email{$subscriber->{'email'}});
       $subscribers_email{ $subscriber->{'email'} } = 1;
    	push @output,$subscriber;
    }		

    # ressembling local part    
    # try to compare firstname.name@domain with name@domain
        foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => '%'.$local_part.'@'.$subscriber_domain,'name'=>$listname,'domain'=>$robot})){
    	next if ($subscribers_email{$subscriber->{'email'}});
    	$subscribers_email{ $subscriber->{'email'} } = 1;
    	push @output,$subscriber;
    }
    
    if ($local_part =~ /^(.*)\.(.*)$/) {
	foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => $2.'@'.$subscriber_domain,'name'=>$listname,'domain'=>$robot})){
	    next if ($subscribers_email{$subscriber->{'email'}});
	    $subscribers_email{ $subscriber->{'email'} } = 1;
	    push @output,$subscriber;
	}
    }

    #### Same local_part and ressembling domain
    #
    # compare host.domain.tld with domain.tld
    if ($subscriber_domain =~ /^[^\.]\.(.*)$/) {
	my $upperdomain = $1;
	if ($upperdomain =~ /\./) {
            # remove first token if there is still at least 2 tokens try to find a subscriber with that domain
	    foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => $local_part.'@'.$upperdomain,'name'=>$listname,'domain'=>$robot})){
	    	next if ($subscribers_email{$subscriber->{'email'}});
	    	$subscribers_email{ $subscriber->{'email'} } = 1;
	    	push @output,$subscriber;
	    }
	}
    }
    foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => $local_part.'@%'.$subscriber_domain,'name'=>$listname,'domain'=>$robot})){
    	next if ($subscribers_email{$subscriber->{'email'}});
    	$subscribers_email{ $subscriber->{'email'} } = 1;
    	push @output,$subscriber;
    }

    # looking for initial
    if ($local_part =~ /^(.*)\.(.*)$/) {
	my $givenname = $1;
	my $name= $2;
	my $initial = '';
	if ($givenname =~ /^([a-z])/){
	    $initial = $1;
	}
	if ($name =~ /^([a-z])/){
	    $initial = $initial.$1;
	}
	foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => $initial.'@'.$subscriber_domain,'name'=>$listname,'domain'=>$robot})){
	    next if ($subscribers_email{$subscriber->{'email'}});
	    $subscribers_email{ $subscriber->{'email'} } = 1;
	    push @output,$subscriber;
	}
    }
    


    #### users in the same local part in any other domain
    #
    foreach my $subscriber (&find_list_member_by_pattern_no_object({'email_pattern' => $local_part.'@%','name'=>$listname,'domain'=>$robot})){
	next if ($subscribers_email{$subscriber->{'email'}});
	$subscribers_email{ $subscriber->{'email'} } = 1;
	push @output,$subscriber;
    }

    return \@output;


}


######################################################################
###  find_list_member_by_pattern_no_object                            #
## Get details regarding a subscriber.                               #
# IN:                                                                #
#   - a single reference to a hash with the following keys:          #
#     * email pattern : the subscriber email patern looking for      #
#     * name: the name of the list                                   #
#     * domain: the virtual host under which the list is installed.  #
# OUT:                                                               #
#   - undef if something went wrong.                                 #
#   - a hash containing the user details otherwise                   #
######################################################################

sub find_list_member_by_pattern_no_object {
    my $options = shift;
    my $name = $options->{'name'};
    my $email_pattern = &tools::clean_email($options->{'email_pattern'});
    my @ressembling_users;

    push @sth_stack, $sth;

    unless ($sth = SDM::do_query('SELECT %s FROM subscriber_table WHERE user_subscriber LIKE %s AND list_subscriber = %s AND robot_subscriber = %s', 
				 &_list_member_cols,
				 &SDM::quote($email_pattern), 
				 &SDM::quote($name),
				 &SDM::quote($options->domain))) {
	&Log::do_log('err','Unable to gather informations corresponding to pattern %s for list %s@%s',$email_pattern,$name,$options->{'domain'});
	$sth = pop @sth_stack;
	return undef;
    }
    
    while (my $user = $sth->fetchrow_hashref('NAME_lc')){
	if (defined $user) {
	    
	    $user->{'reception'} ||= 'mail';
	    $user->{'escaped_email'} = &tools::escape_chars($user->{'email'});
	    $user->{'update_date'} ||= $user->{'date'};
	    if (defined $user->{custom_attribute}) {
		$user->{'custom_attribute'} = &parseCustomAttribute($user->{'custom_attribute'});
	    }
	push @ressembling_users, $user;
	}
    }
    $sth->finish();
    
    $sth = pop @sth_stack;
    ## Set session cache

    return @ressembling_users;
}

sub _list_member_cols {
    my $additional = '';
    if ($Conf::Conf{'db_additional_subscriber_fields'}) {
	$additional = ', ' . $Conf::Conf{'db_additional_subscriber_fields'};
    }
    return sprintf 'user_subscriber AS email, comment_subscriber AS gecos, bounce_subscriber AS bounce, bounce_score_subscriber AS bounce_score, bounce_address_subscriber AS bounce_address, reception_subscriber AS reception, topics_subscriber AS topics, visibility_subscriber AS visibility, %s AS date, %s AS update_date, subscribed_subscriber AS subscribed, included_subscriber AS included, include_sources_subscriber AS id, custom_attribute_subscriber AS custom_attribute, suspend_subscriber AS suspend, suspend_start_date_subscriber AS startdate, suspend_end_date_subscriber AS enddate%s',
		   &SDM::get_canonical_read_date('date_subscriber'),
		   &SDM::get_canonical_read_date('update_subscriber'),
		   $additional;
}

## Returns an admin user of the list.
sub get_list_admin {
    &Log::do_log('debug2', '(%s, %s, %s)', @_);
    my  $self = shift;
    my  $role = shift;
    return $self->user($role, shift) || undef;
}

sub _list_admin_cols {
    return sprintf 'user_admin AS email, comment_admin AS gecos, reception_admin AS reception, visibility_admin AS visibility, %s AS date, %s AS update_date, info_admin AS info, profile_admin AS profile, subscribed_admin AS subscribed, included_admin AS included, include_sources_admin AS id',
		   &SDM::get_canonical_read_date('date_admin'),
		   &SDM::get_canonical_read_date('update_admin');
}

## Returns the first user for the list.
sub get_first_list_member {
    my ($self, $data) = @_;

    my ($sortby, $offset, $rows, $sql_regexp);
    $sortby = $data->{'sortby'};
    ## Sort may be domain, email, date
    $sortby ||= 'domain';
    $offset = $data->{'offset'};
    $rows = $data->{'rows'};
    $sql_regexp = $data->{'sql_regexp'};
    
    my $lock = new Lock ($self->{'dir'}.'/include');
    unless (defined $lock) {
	&Log::do_log('err','Could not create new lock');
	return undef;
    }
    $lock->set_timeout(10*60); 

    &Log::do_log('debug2', 'List::get_first_list_member(%s,%s,%d,%d)', $self->{'name'},$sortby, $offset, $rows);
        
    ## Get an Shared lock	    
    unless ($lock->lock('read')) {
	return undef;
    }
    
    my $name = $self->{'name'};
    my $statement;

    ## SQL regexp
    my $selection;
    if ($sql_regexp) {
	$selection = sprintf " AND (user_subscriber LIKE %s OR comment_subscriber LIKE %s)"
	    ,&SDM::quote($sql_regexp), &SDM::quote($sql_regexp);
    }

    ## Additional subscriber fields
    $statement = sprintf 'SELECT %s FROM subscriber_table WHERE list_subscriber = %s AND robot_subscriber = %s %s', 
			 &_list_member_cols,
			 &SDM::quote($name), 
			 &SDM::quote($self->domain),
			 $selection;

    ## SORT BY
    if ($sortby eq 'domain') {
	## Redefine query to set "dom"
	$statement = sprintf 'SELECT %s, %s AS dom FROM subscriber_table WHERE list_subscriber = %s AND robot_subscriber = %s ORDER BY dom', 
			     &_list_member_cols,
			     &SDM::get_substring_clause({'source_field'=>'user_subscriber','separator'=>'\@','substring_length'=>'50',}),
			     &SDM::quote($name),
			     &SDM::quote($self->domain);
	
    }elsif ($sortby eq 'email') {
	## Default SORT
	$statement .= ' ORDER BY email';
	
    }elsif ($sortby eq 'date') {
	$statement .= ' ORDER BY date DESC';
	
    }elsif ($sortby eq 'sources') {
	$statement .= " ORDER BY subscribed DESC,id";
	
    }elsif ($sortby eq 'name') {
	$statement .= ' ORDER BY gecos';
    } 

    ## LIMIT clause
    if (defined($rows) and defined($offset)) {
	$statement .= &SDM::get_limit_clause({'rows_count'=>$rows,'offset'=>$offset});
    }

    push @sth_stack, $sth;

    unless ($sth = SDM::do_query($statement)) {
	&Log::do_log('err','Unable to get members of list %s@%s', $name, $self->{'domain'});
	$sth = pop @sth_stack;
	return undef;
    }
    
    my $user = $sth->fetchrow_hashref('NAME_lc');
    if (defined $user) {
		&Log::do_log('err','Warning: entry with empty email address in list %s', $self->{'name'}) if (! $user->{'email'});
		$user->{'reception'} ||= 'mail';
		$user->{'reception'} = $self->{'admin'}{'default_user_options'}{'reception'}
		unless ($self->is_available_reception_mode($user->{'reception'}));
		$user->{'update_date'} ||= $user->{'date'};

		############################################################################	    
		if (defined $user->{custom_attribute}) {
			$user->{'custom_attribute'} = &parseCustomAttribute($user->{'custom_attribute'});
		}
    }
    else {
		$sth->finish;
		$sth = pop @sth_stack;
	
		## Release the Shared lock
		unless ($lock->unlock()) {
			return undef;
		}
    }
    
    ## If no offset (for LIMIT) was used, update total of subscribers
    unless ($offset) {
	$self->savestats()
	    unless $self->total == $self->get_real_total;
    }
    
    return $user;
}

# Create a custom attribute from an XML description
# IN : File handle or a string, XML formed data as stored in database
# OUT : HASH data storing custome attributes.
sub parseCustomAttribute {
	my $xmldoc = shift ;
	return undef if ! defined $xmldoc or $xmldoc eq '';

	my $parser = XML::LibXML->new();
	my $tree;

	## We should use eval to parse to prevent the program to crash if it fails
	if (ref($xmldoc) eq 'GLOB') {
	    $tree = eval {$parser->parse_fh($xmldoc)};
	}else {
	    $tree = eval {$parser->parse_string($xmldoc)};
	}

	unless (defined $tree) {
	    &Log::do_log('err', "Failed to parse XML data: %s", $@);
	    return undef;
	}

	my $doc = $tree->getDocumentElement;
	
	my @custom_attr = $doc->getChildrenByTagName('custom_attribute') ;
	my %ca ;
	foreach my $ca (@custom_attr) {
	        my $id = Encode::encode_utf8($ca->getAttribute('id'));
	        my $value = Encode::encode_utf8($ca->getElementsByTagName('value'));
		$ca{$id} = {value=>$value} ;
	}
	return \%ca ;
}

# Create an XML Custom attribute to be stored into data base.
# IN : HASH data storing custome attributes
# OUT : string, XML formed data to be stored in database
sub createXMLCustomAttribute {
	my $custom_attr = shift ;
	return '<?xml version="1.0" encoding="UTF-8" ?><custom_attributes></custom_attributes>' if (not defined $custom_attr) ;
	my $XMLstr = '<?xml version="1.0" encoding="UTF-8" ?><custom_attributes>';
	foreach my $k (sort keys %{$custom_attr} ) {
		$XMLstr .= "<custom_attribute id=\"$k\"><value>".&tools::escape_html($custom_attr->{$k}{value})."</value></custom_attribute>";
	}
	$XMLstr .= "</custom_attributes>";
	
	return $XMLstr ;
}

## Returns the first admin_user with $role for the list.
sub get_first_list_admin {
    my ($self, $role, $data) = @_;

    my ($sortby, $offset, $rows, $sql_regexp);
    $sortby = $data->{'sortby'};
    ## Sort may be domain, email, date
    $sortby ||= 'domain';
    $offset = $data->{'offset'};
    $rows = $data->{'rows'};
    $sql_regexp = $data->{'sql_regexp'};
    my $fh;

    &Log::do_log('debug2', '(%s,%s,%s,%d,%d)', $self->{'name'},$role, $sortby, $offset, $rows);

    my $lock = new Lock ($self->{'dir'}.'/include_admin_user');
    unless (defined $lock) {
	&Log::do_log('err','Could not create new lock');
	return undef;
    }
    $lock->set_timeout(20); 

    ## Get a shared lock
    unless ($fh = $lock->lock('read')) {
	return undef;
    }
          
    my $name = $self->{'name'};
    my $statement;
    
    ## SQL regexp
    my $selection;
    if ($sql_regexp) {
	$selection = sprintf " AND (user_admin LIKE %s OR comment_admin LIKE %s)"
	    ,&SDM::quote($sql_regexp), &SDM::quote($sql_regexp);
    }

    $statement = sprintf 'SELECT %s FROM admin_table WHERE list_admin = %s AND robot_admin = %s %s AND role_admin = %s', 
			 &_list_admin_cols,
			 &SDM::quote($name), 
			 &SDM::quote($self->domain),
			 $selection, 
			 &SDM::quote($role);

    ## SORT BY
    if ($sortby eq 'domain') {
	## Redefine query to set "dom"
	$statement = sprintf 'SELECT %s, %s AS dom FROM admin_table WHERE list_admin = %s AND robot_admin = %s AND role_admin = %s ORDER BY dom',
			     &_list_admin_cols,
			     &SDM::get_substring_clause({'source_field'=>'user_admin','separator'=>'\@','substring_length'=>'50'}),
			     &SDM::quote($name),
			     &SDM::quote($self->{'domain'}),
			     &SDM::quote($role);
    } elsif ($sortby eq 'email') {
	$statement .= ' ORDER BY email';
    } elsif ($sortby eq 'date') {
	$statement .= ' ORDER BY date DESC';
    }elsif ($sortby eq 'sources') {
	$statement .= " ORDER BY subscribed DESC,id";
    }elsif ($sortby eq 'email') {
	$statement .= ' ORDER BY gecos';
    }

    ## LIMIT clause
    if (defined($rows) and defined($offset)) {
	$statement .= &SDM::get_substring_clause({'rows_count'=>$rows,'offset'=>$offset});
    }

    push @sth_stack, $sth;

    unless ($sth = &SDM::do_query($statement)) {
	&Log::do_log('err','Unable to get admins having role %s for list %s@%s', $role,$name,$self->{'domain'});
	$sth = pop @sth_stack;
	return undef;
    }
    
    my $admin_user = $sth->fetchrow_hashref('NAME_lc');
    if (defined $admin_user) {
	&Log::do_log('err','Warning: entry with empty email address in list %s', $self->{'name'}) 
	    if (! $admin_user->{'email'});
	$admin_user->{'reception'} ||= 'mail';
	$admin_user->{'update_date'} ||= $admin_user->{'date'};
    }else {
	$sth->finish;
        $sth = pop @sth_stack;

	## Release the Shared lock
	my $lock = new Lock($self->{'dir'}.'/include_admin_user');
	unless (defined $lock) {
	    &Log::do_log('err','Could not create new lock');
	    return undef;
	}
	
	unless ($lock->unlock()) {
	    return undef;
	}
    }

    return $admin_user;
}
    
## Loop for all subsequent users.
sub get_next_list_member {
    my $self = shift;
    &Log::do_log('debug2', '');

    unless (defined $sth) {
	&Log::do_log('err', 'No handle defined, get_first_list_member(%s) was not run', $self->{'name'});
	return undef;
    }
    
    my $user = $sth->fetchrow_hashref('NAME_lc');
    
    if (defined $user) {
		&Log::do_log('err','Warning: entry with empty email address in list %s', $self->{'name'}) if (! $user->{'email'});
		$user->{'reception'} ||= 'mail';
		unless ($self->is_available_reception_mode($user->{'reception'})){
			$user->{'reception'} = $self->{'admin'}{'default_user_options'}{'reception'}
		}
		$user->{'update_date'} ||= $user->{'date'};

		&Log::do_log('debug2', '(email = %s)', $user->{'email'});
		if (defined $user->{custom_attribute}) {
			my $custom_attr = &parseCustomAttribute($user->{'custom_attribute'});
			unless (defined $custom_attr) {
				&Log::do_log('err',"Failed to parse custom attributes for user %s, list %s", $user->{'email'}, $self->get_list_id());
			}
			$user->{'custom_attribute'} = $custom_attr ;
		}
    }else {
		$sth->finish;
		$sth = pop @sth_stack;
	
		## Release lock
		my $lock = new Lock ($self->{'dir'}.'/include');
		unless (defined $lock) {
			&Log::do_log('err','Could not create new lock');
			return undef;
		}
		unless ($lock->unlock()) {
			return undef;
		}
    }
    
    return $user;
}

## Loop for all subsequent admin users with the role defined in get_first_list_admin.
sub get_next_list_admin {
    my $self = shift;
    &Log::do_log('debug2', ''); 

    unless (defined $sth) {
		&Log::do_log('err','Statement handle not defined in get_next_list_admin for list %s', $self->{'name'});
		return undef;
    }
    
    my $admin_user = $sth->fetchrow_hashref('NAME_lc');

    if (defined $admin_user) {
		&Log::do_log('err','Warning: entry with empty email address in list %s', $self->{'name'}) if (! $admin_user->{'email'});
		$admin_user->{'reception'} ||= 'mail';
		$admin_user->{'update_date'} ||= $admin_user->{'date'};
    }else {
		$sth->finish;
		$sth = pop @sth_stack;
	
		## Release the Shared lock
		my $lock = new Lock($self->{'dir'}.'/include_admin_user');
		unless (defined $lock) {
			&Log::do_log('err','Could not create new lock');
			return undef;
		}
	
		unless ($lock->unlock()) {
			return undef;
		}
    }
    return $admin_user;
}

## Returns the first bouncing user
sub get_first_bouncing_list_member {
    my $self = shift;
    &Log::do_log('debug2', '');

    my $lock = new Lock ($self->{'dir'}.'/include');
    unless (defined $lock) {
	&Log::do_log('err','Could not create new lock');
	return undef;
    }
    $lock->set_timeout(10*60); 

    ## Get an Shared lock
    unless ($lock->lock('read')) {
	return undef;
    }

    my $name = $self->{'name'};

    push @sth_stack, $sth;

    unless ($sth = SDM::do_query('SELECT %s FROM subscriber_table WHERE list_subscriber = %s AND robot_subscriber = %s AND bounce_subscriber is not NULL',
				 &_list_member_cols,
				 &SDM::quote($name),
				 &SDM::quote($self->domain))) {
	&Log::do_log('err','Unable to get bouncing users %s@%s',$name,$self->{'domain'});
	$sth = pop @sth_stack;
	return undef;
    }

    my $user = $sth->fetchrow_hashref('NAME_lc');
	    
    if (defined $user) {
		&Log::do_log('err','Warning: entry with empty email address in list %s', $self->{'name'}) if (! $user->{'email'});
    }else {
		$sth->finish;
		$sth = pop @sth_stack;
	
		## Release the Shared lock
		unless ($lock->unlock()) {
			return undef;
		}
    }
    return $user;
}

## Loop for all subsequent bouncing users.
sub get_next_bouncing_list_member {
    my $self = shift;
    &Log::do_log('debug2', '');

    unless (defined $sth) {
		&Log::do_log('err', 'No handle defined, get_first_bouncing_list_member(%s) was not run', $self->{'name'});
		return undef;
    }
    
    my $user = $sth->fetchrow_hashref('NAME_lc');
    
    if (defined $user) {
		&Log::do_log('err','Warning: entry with empty email address in list %s', $self->{'name'}) if (! $user->{'email'});
	
		if (defined $user->{custom_attribute}) {
		    $user->{'custom_attribute'} = &parseCustomAttribute($user->{'custom_attribute'});
		}

    }else {
		$sth->finish;
		$sth = pop @sth_stack;
	
		## Release the Shared lock
		my $lock = new Lock ($self->{'dir'}.'/include');
		unless (defined $lock) {
			&Log::do_log('err','Could not create new lock');
			return undef;
		}
		unless ($lock->unlock()) {
			return undef;
		}
    }

    return $user;
}

sub get_info {
    my $self = shift;

    my $info;
    
    unless (open INFO, "$self->{'dir'}/info") {
	&Log::do_log('err', 'Could not open %s : %s', $self->{'dir'}.'/info', $!);
	return undef;
    }
    
    while (<INFO>) {
	$info .= $_;
    }
    close INFO;

    return $info;
}

## Total bouncing subscribers
sub get_total_bouncing {
    my $self = shift;
    &Log::do_log('debug2', 'List::get_total_boucing');

    my $name = $self->{'name'};
   
    push @sth_stack, $sth;

    ## Query the Database
    unless ($sth = &SDM::do_query( "SELECT count(*) FROM subscriber_table WHERE (list_subscriber = %s  AND robot_subscriber = %s AND bounce_subscriber is not NULL)", &SDM::quote($name), &SDM::quote($self->{'domain'}))) {
	&Log::do_log('err','Unable to gather bouncing subscribers count for list %s@%s',$name,$self->{'domain'});
	$sth = pop @sth_stack;
	return undef;
    }
    
    my $total =  $sth->fetchrow;

    $sth->finish();

    $sth = pop @sth_stack;

    return $total;
}

## Is the person in user table (db only)
sub is_global_user {
   my $who = &tools::clean_email(pop);
   &Log::do_log('debug3', '(%s)', $who);

   return undef unless ($who);
   
   push @sth_stack, $sth;

   ## Query the Database
   unless($sth = &SDM::do_query("SELECT count(*) FROM user_table WHERE email_user = %s", &SDM::quote($who))) {
	&Log::do_log('err','Unable to check whether user %s is in the user table.');
	$sth = pop @sth_stack;
	return undef;
   }
   
   my $is_user = $sth->fetchrow();
   $sth->finish();
   
   $sth = pop @sth_stack;

   return $is_user;
}

## Is the indicated person a subscriber to the list?
sub is_list_member {
    &Log::do_log('debug2', '(%s, %s)', @_);
    my $self = shift;
    return $self->user('member', shift) ? 1 : undef;
}

## Sets new values for the given user (except gecos)
sub update_list_member {
    my($self, $who, $values) = @_;
    &Log::do_log('debug2', '(%s)', $who);
    $who = &tools::clean_email($who);    

    my ($field, $value);
    
    my ($user, $statement, $table);
    my $name = $self->{'name'};
    
    ## mapping between var and field names
    my %map_field = ( reception => 'reception_subscriber',
		      topics => 'topics_subscriber',
		      visibility => 'visibility_subscriber',
		      date => 'date_subscriber',
		      update_date => 'update_subscriber',
		      gecos => 'comment_subscriber',
		      password => 'password_user',
		      bounce => 'bounce_subscriber',
		      score => 'bounce_score_subscriber',
		      email => 'user_subscriber',
		      subscribed => 'subscribed_subscriber',
		      included => 'included_subscriber',
		      id => 'include_sources_subscriber',
		      bounce_address => 'bounce_address_subscriber',
		      custom_attribute => 'custom_attribute_subscriber',
		      suspend => 'suspend_subscriber',
		      startdate_subscriber => 'suspend_start_date_subscriber',
		      enddate => 'suspend_end_date_subscriber'
		      );
    
    ## mapping between var and tables
    my %map_table = ( reception => 'subscriber_table',
		      topics => 'subscriber_table', 
		      visibility => 'subscriber_table',
		      date => 'subscriber_table',
		      update_date => 'subscriber_table',
		      gecos => 'subscriber_table',
		      password => 'user_table',
		      bounce => 'subscriber_table',
		      score => 'subscriber_table',
		      email => 'subscriber_table',
		      subscribed => 'subscriber_table',
		      included => 'subscriber_table',
		      id => 'subscriber_table',
		      bounce_address => 'subscriber_table',
		      custom_attribute => 'subscriber_table',
		      suspend => 'subscriber_table',
		      startdate => 'subscriber_table',
		      enddate => 'subscriber_table'
		      );
    
    ## additional DB fields
    if (defined $Conf::Conf{'db_additional_subscriber_fields'}) {
	foreach my $f (split ',', $Conf::Conf{'db_additional_subscriber_fields'}) {
	    $map_table{$f} = 'subscriber_table';
	    $map_field{$f} = $f;
	}
    }
    
    if (defined $Conf::Conf{'db_additional_user_fields'}) {
	foreach my $f (split ',', $Conf::Conf{'db_additional_user_fields'}) {
	    $map_table{$f} = 'user_table';
	    $map_field{$f} = $f;
	}
    }
    
    &Log::do_log('debug2', " custom_attribute id: $Conf::Conf{'custom_attribute'}");
    ## custom attributes
    if (defined $Conf::Conf{'custom_attribute'}){
	foreach my $f (sort keys %{$Conf::Conf{'custom_attribute'}}){
	    &Log::do_log('debug2', "custom_attribute id: $Conf::Conf{'custom_attribute'}{id} name: $Conf::Conf{'custom_attribute'}{name} type: $Conf::Conf{'custom_attribute'}{type} ");
	    	
	}
    }
    
    ## Update each table
    foreach $table ('user_table','subscriber_table') {
	
	my @set_list;
	while (($field, $value) = each %{$values}) {
	    
	    unless ($map_field{$field} and $map_table{$field}) {
		&Log::do_log('err', 'Unknown database field %s', $field);
		next;
	    }
	    
	    if ($map_table{$field} eq $table) {
		if ($field eq 'date' || $field eq 'update_date') {
		    $value = &SDM::get_canonical_write_date($value);
		}elsif ($value eq 'NULL'){ ## get_null_value?
		    if ($Conf::Conf{'db_type'} eq 'mysql') {
			$value = '\N';
		    }
		}else {
		    if ($numeric_field{$map_field{$field}}) {
			$value ||= 0; ## Can't have a null value
		    }else {
			$value = &SDM::quote($value);
		    }
		}
		my $set = sprintf "%s=%s", $map_field{$field}, $value;
		push @set_list, $set;
	    }
	}
	next unless @set_list;

	## Update field
	if ($table eq 'user_table') {
	    unless (&SDM::do_query("UPDATE %s SET %s WHERE (email_user=%s)", $table, join(',', @set_list), &SDM::quote($who))) {
		&Log::do_log('err','Could not update informations for user %s in table %s',$who,$table);
		return undef;
	    }
	}elsif ($table eq 'subscriber_table') {
	    if ($who eq '*') {
		unless (&SDM::do_query("UPDATE %s SET %s WHERE (list_subscriber=%s AND robot_subscriber = %s)", 
		$table, 
		join(',', @set_list), 
		&SDM::quote($name), 
		&SDM::quote($self->{'domain'}))) {
		    &Log::do_log('err','Could not update informations for user %s in table %s for list %s@%s',$who,$table,$name,$self->{'domain'});
		    return undef;
		}	
	    }else {
		unless (&SDM::do_query("UPDATE %s SET %s WHERE (user_subscriber=%s AND list_subscriber=%s AND robot_subscriber = %s)", 
		$table, 
		join(',', @set_list), 
		&SDM::quote($who), 
		&SDM::quote($name),
		&SDM::quote($self->{'domain'}))) {
		    &Log::do_log('err','Could not update informations for user %s in table %s for list %s@%s',$who,$table,$name,$self->{'domain'});
		    return undef;
		}
	    }
	}
    }

    ## Rename picture on disk if user email changed
    if ($values->{'email'}) {
	my $file_name = &tools::md5_fingerprint($who);
	my $picture_file_path = &Conf::get_robot_conf($self->domain, 'pictures_path') . '/' . $self->get_list_id();

	foreach my $extension ('gif','png','jpg','jpeg') {
	    if (-f $picture_file_path.'/'.$file_name.'.'.$extension) {
		my $new_file_name = &tools::md5_fingerprint($values->{'email'});
		unless (rename $picture_file_path.'/'.$file_name.'.'.$extension, $picture_file_path.'/'.$new_file_name.'.'.$extension) {
		    &Log::do_log('err', "Failed to rename %s to %s : %s", $picture_file_path.'/'.$file_name.'.'.$extension, $picture_file_path.'/'.$new_file_name.'.'.$extension, $!);
		}
	    }
	}
    }

    ## Reset session cache
    $self->user('member', $who, undef);
    $self->user('member', $who);

    return 1;
}


## Sets new values for the given admin user (except gecos)
sub update_list_admin {
    my($self, $who,$role, $values) = @_;
    &Log::do_log('debug2', '(%s,%s)', $role, $who); 
    $who = &tools::clean_email($who);    

    my ($field, $value);
    
    my ($admin_user, $statement, $table);
    my $name = $self->{'name'};
    
    ## mapping between var and field names
    my %map_field = ( reception => 'reception_admin',
		      visibility => 'visibility_admin',
		      date => 'date_admin',
		      update_date => 'update_admin',
		      gecos => 'comment_admin',
		      password => 'password_user',
		      email => 'user_admin',
		      subscribed => 'subscribed_admin',
		      included => 'included_admin',
		      id => 'include_sources_admin',
		      info => 'info_admin',
		      profile => 'profile_admin',
		      role => 'role_admin'
		      );
    
    ## mapping between var and tables
    my %map_table = ( reception => 'admin_table',
		      visibility => 'admin_table',
		      date => 'admin_table',
		      update_date => 'admin_table',
		      gecos => 'admin_table',
		      password => 'user_table',
		      email => 'admin_table',
		      subscribed => 'admin_table',
		      included => 'admin_table',
		      id => 'admin_table',
		      info => 'admin_table',
		      profile => 'admin_table',
		      role => 'admin_table'
		      );
#### ??
    ## additional DB fields
#    if (defined $Conf::Conf{'db_additional_user_fields'}) {
#	foreach my $f (split ',', $Conf::Conf{'db_additional_user_fields'}) {
#	    $map_table{$f} = 'user_table';
#	    $map_field{$f} = $f;
#	}
#    }
    
    ## Update each table
    foreach $table ('user_table','admin_table') {
	
	my @set_list;
	while (($field, $value) = each %{$values}) {
	    
	    unless ($map_field{$field} and $map_table{$field}) {
		&Log::do_log('err', 'Unknown database field %s', $field);
		next;
	    }
	    
	    if ($map_table{$field} eq $table) {
		if ($field eq 'date' || $field eq 'update_date') {
		    $value = &SDM::get_canonical_write_date($value);
		}elsif ($value eq 'NULL'){ #get_null_value?
		    if ($Conf::Conf{'db_type'} eq 'mysql') {
			$value = '\N';
		    }
		}else {
		    if ($numeric_field{$map_field{$field}}) {
			$value ||= 0; ## Can't have a null value
		    }else {
			$value = &SDM::quote($value);
		    }
		}
		my $set = sprintf "%s=%s", $map_field{$field}, $value;

		push @set_list, $set;
	    }
	}
	next unless @set_list;
	
	## Update field
	if ($table eq 'user_table') {
	    unless ($sth = &SDM::do_query("UPDATE %s SET %s WHERE (email_user=%s)", $table, join(',', @set_list), &SDM::quote($who))) {
		&Log::do_log('err','Could not update informations for admin %s in table %s',$who,$table);
		return undef;
	    } 
	    
	}elsif ($table eq 'admin_table') {
	    if ($who eq '*') {
		unless ($sth = &SDM::do_query("UPDATE %s SET %s WHERE (list_admin=%s AND robot_admin=%s AND role_admin=%s)", 
		$table, 
		join(',', @set_list), 
		&SDM::quote($name), 
		&SDM::quote($self->{'domain'}),
		&SDM::quote($role))) {
		    &Log::do_log('err','Could not update informations for admin %s in table %s for list %s@%s',$who,$table,$name,$self->{'domain'});
		    return undef;
		}
	    }else {
		unless ($sth = &SDM::do_query("UPDATE %s SET %s WHERE (user_admin=%s AND list_admin=%s AND robot_admin=%s AND role_admin=%s )", 
		$table, 
		join(',', @set_list), 
		&SDM::quote($who), 
		&SDM::quote($name), 
		&SDM::quote($self->{'domain'}),
		&SDM::quote($role))) {
		    &Log::do_log('err','Could not update informations for admin %s in table %s for list %s@%s',$who,$table,$name,$self->{'domain'});
		    return undef;
		}
	    }
	}
    }

    ## Reset session cache
    $self->user($role, $who, undef);
    $self->user($role, $who);

    return 1;
}



## Sets new values for the given user in the Database
sub update_global_user {
    my($who, $values) = @_;
    &Log::do_log('debug', '(%s)', $who);

    $who = &tools::clean_email($who);

    ## use md5 fingerprint to store password   
    $values->{'password'} = &Auth::password_fingerprint($values->{'password'}) if ($values->{'password'});

    my ($field, $value);
    
    my ($user, $statement, $table);
    
    ## mapping between var and field names
    my %map_field = ( gecos => 'gecos_user',
		      password => 'password_user',
		      cookie_delay => 'cookie_delay_user',
		      lang => 'lang_user',
		      attributes => 'attributes_user',
		      email => 'email_user',
		      data => 'data_user',
		      last_login_date => 'last_login_date_user',
		      last_login_host => 'last_login_host_user',
		      wrong_login_count => 'wrong_login_count_user'
		      );
    
    ## Update each table
    my @set_list;

    while (($field, $value) = each %{$values}) {
	unless ($map_field{$field}) {
	    &Log::do_log('error',"unkown field $field in map_field internal error");
	    next;
	};
	my $set;
	
	if ($numeric_field{$map_field{$field}})  {
	    $value ||= 0; ## Can't have a null value
	    $set = sprintf '%s=%s', $map_field{$field}, $value;
	}else { 
	    $set = sprintf '%s=%s', $map_field{$field}, &SDM::quote($value);
	}
	push @set_list, $set;
    }
    
    return undef unless @set_list;
    
    ## Update field

    unless ($sth = &SDM::do_query("UPDATE user_table SET %s WHERE (email_user=%s)"
	    , join(',', @set_list), &SDM::quote($who))) {
	&Log::do_log('err','Could not update informations for user %s in user_table',$who);
	return undef;
    }
    
    return 1;
}

## Adds a user to the user_table
sub add_global_user {
    my($values) = @_;
    &Log::do_log('debug2', '');

    my ($field, $value);
    my ($user, $statement, $table);
    
    ## encrypt password   
    $values->{'password'} = &Auth::password_fingerprint($values->{'password'}) if ($values->{'password'});
    
    return undef unless (my $who = &tools::clean_email($values->{'email'}));
    
    return undef if (is_global_user($who));
    
    ## mapping between var and field names
    my %map_field = ( email => 'email_user',
		      gecos => 'gecos_user',
		      custom_attribute => 'custom_attribute',
		      password => 'password_user',
		      cookie_delay => 'cookie_delay_user',
		      lang => 'lang_user',
		      attributes => 'attributes_user'
		      );
    
    ## Update each table
    my (@insert_field, @insert_value);
    while (($field, $value) = each %{$values}) {
	
	next unless ($map_field{$field});
	
	my $insert;
	if ($numeric_field{$map_field{$field}}) {
	    $value ||= 0; ## Can't have a null value
	    $insert = $value;
	}else {
	    $insert = sprintf "%s", &SDM::quote($value);
	}
	push @insert_value, $insert;
	push @insert_field, $map_field{$field}
    }
    
    unless (@insert_field) {
	&Log::do_log('err','The fields (%s) do not correspond to anything in the database',join (',',keys(%{$values})));
	return undef;
    }
    
    ## Update field
    unless($sth = &SDM::do_query("INSERT INTO user_table (%s) VALUES (%s)"
	, join(',', @insert_field), join(',', @insert_value))) {
	    &Log::do_log('err','Unable to add user %s to the DB table user_table', $values->{'email'});
	    return undef;
	}
    
    return 1;
}

## Adds a list member ; no overwrite.
sub add_list_member {
    my($self, @new_users, $daemon) = @_;
    &Log::do_log('debug2', '%s', $self->{'name'});
    
    my $name = $self->{'name'};
    $self->{'add_outcome'} = undef;
    $self->{'add_outcome'}{'added_members'} = 0;
    $self->{'add_outcome'}{'expected_number_of_added_users'} = $#new_users;
    $self->{'add_outcome'}{'remaining_members_to_add'} = $self->{'add_outcome'}{'expected_number_of_added_users'};
    
    my $subscriptions = $self->get_subscription_requests();
    my $current_list_members_count = $self->total;

    foreach my $new_user (@new_users) {
	my $who = &tools::clean_email($new_user->{'email'});
	next unless $who;
	unless ($current_list_members_count < $self->{'admin'}{'max_list_members'} || $self->{'admin'}{'max_list_members'} == 0) {
	    $self->{'add_outcome'}{'errors'}{'max_list_members_exceeded'} = 1;
	    &Log::do_log('notice','Subscription of user %s failed: max number of subscribers (%s) reached',$new_user->{'email'},$self->{'admin'}{'max_list_members'});
	    last;
	}

	# Delete from exclusion_table and force a sync_include if new_user was excluded
	if($self->insert_delete_exclusion($who, 'delete')) {
		$self->sync_include();
		next if($self->is_list_member($who));
	}

	$new_user->{'date'} ||= time;
	$new_user->{'update_date'} ||= $new_user->{'date'};

	my %custom_attr = %{ $subscriptions->{$who}{'custom_attribute'} } if (defined $subscriptions->{$who}{'custom_attribute'} );
	$new_user->{'custom_attribute'} ||= &createXMLCustomAttribute(\%custom_attr) ;
	&Log::do_log('debug2', 'custom_attribute = %s', $new_user->{'custom_attribute'});
	
	## Crypt password if it was not crypted
	unless ($new_user->{'password'} =~ /^crypt/) {
		$new_user->{'password'} = &tools::crypt_password($new_user->{'password'});
	}

	$self->user('member', $who, undef);

	## Either is_included or is_subscribed must be set
	## default is is_subscriber for backward compatibility reason
	unless ($new_user->{'included'}) {
		$new_user->{'subscribed'} = 1;
	}
	
	unless ($new_user->{'included'}) {
	    ## Is the email in user table?
	    if (! is_global_user($who)) {
		## Insert in User Table
		unless(&SDM::do_query("INSERT INTO user_table (email_user, gecos_user, lang_user, password_user) VALUES (%s,%s,%s,%s)",&SDM::quote($who), &SDM::quote($new_user->{'gecos'}), &SDM::quote($new_user->{'lang'}), &SDM::quote($new_user->{'password'}))){
		    &Log::do_log('err','Unable to add user %s to user_table.', $who);
		    $self->{'add_outcome'}{'errors'}{'unable_to_add_to_database'} = 1;
		    next;
		}
		}
	}	    
	
	$new_user->{'subscribed'} ||= 0;
	$new_user->{'included'} ||= 0;

	#Log in stat_table to make staistics
	&Log::db_stat_log({'robot' => $self->{'domain'}, 'list' => $self->{'name'}, 'operation' =>'add subscriber', 'parameter' => '', 'mail' => $new_user->{'email'},
		       'client' => '', 'daemon' => $daemon});
	
	## Update Subscriber Table
	unless(&SDM::do_query("INSERT INTO subscriber_table (user_subscriber, comment_subscriber, list_subscriber, robot_subscriber, date_subscriber, update_subscriber, reception_subscriber, topics_subscriber, visibility_subscriber,subscribed_subscriber,included_subscriber,include_sources_subscriber,custom_attribute_subscriber,suspend_subscriber,suspend_start_date_subscriber,suspend_end_date_subscriber) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)", 
	&SDM::quote($who), 
	&SDM::quote($new_user->{'gecos'}), 
	&SDM::quote($name), 
	&SDM::quote($self->{'domain'}),
	&SDM::get_canonical_write_date($new_user->{'date'}), 
	&SDM::get_canonical_write_date($new_user->{'update_date'}), 
	&SDM::quote($new_user->{'reception'}), 
	&SDM::quote($new_user->{'topics'}), 
	&SDM::quote($new_user->{'visibility'}), 
	$new_user->{'subscribed'}, 
	$new_user->{'included'}, 
	&SDM::quote($new_user->{'id'}),
	&SDM::quote($new_user->{'custom_attribute'}),
	&SDM::quote($new_user->{'suspend'}),
	&SDM::quote($new_user->{'startdate'}),
	&SDM::quote($new_user->{'enddate'}))){
	    &Log::do_log('err','Unable to add subscriber %s to table subscriber_table for list %s@%s %s', $who,$name,$self->{'domain'});
	    next;
	}
	$self->{'add_outcome'}{'added_members'}++;
	$self->{'add_outcome'}{'remaining_member_to_add'}--;
	$current_list_members_count++;
    }

    $self->total($self->total + $self->{'add_outcome'}{'added_members'});
    $self->savestats();
    $self->_create_add_error_string() if ($self->{'add_outcome'}{'errors'});
    return 1;
}

sub _create_add_error_string {
    my $self = shift;
    $self->{'add_outcome'}{'errors'}{'error_message'} = '';
    if ($self->{'add_outcome'}{'errors'}{'max_list_members_exceeded'}) {
	$self->{'add_outcome'}{'errors'}{'error_message'} .= sprintf &gettext('Attempt to exceed the max number of members (%s) for this list.'), $self->{'admin'}{'max_list_members'} ;
    }
    if ($self->{'add_outcome'}{'errors'}{'unable_to_add_to_database'}) {
	$self->{'add_outcome'}{'error_message'} .= ' '.&gettext('Attempts to add some users in database failed.');
    }
    $self->{'add_outcome'}{'errors'}{'error_message'} .= ' '.sprintf &gettext('Added %s users out of %s required.'),$self->{'add_outcome'}{'added_members'},$self->{'add_outcome'}{'expected_number_of_added_users'};
}
    
## Adds a new list admin user, no overwrite.
sub add_list_admin {
    my($self, $role, @new_admin_users) = @_;
    &Log::do_log('debug2', '');
    
    my $name = $self->{'name'};
    my $total = 0;
    
    foreach my $new_admin_user (@new_admin_users) {
	my $who = &tools::clean_email($new_admin_user->{'email'});
	
	next unless $who;
	
	$new_admin_user->{'date'} ||= time;
	$new_admin_user->{'update_date'} ||= $new_admin_user->{'date'};

	$self->user($role, $who, undef);

	##  either is_included or is_subscribed must be set
	## default is is_subscriber for backward compatibility reason
	unless ($new_admin_user->{'included'}) {
	    $new_admin_user->{'subscribed'} = 1;
	}
	    
	unless ($new_admin_user->{'included'}) {
	    ## Is the email in user table?
	    if (! is_global_user($who)) {
		## Insert in User Table
		unless(&SDM::do_query("INSERT INTO user_table (email_user, gecos_user, lang_user, password_user) VALUES (%s,%s,%s,%s)",&SDM::quote($who), &SDM::quote($new_admin_user->{'gecos'}), &SDM::quote($new_admin_user->{'lang'}), &SDM::quote($new_admin_user->{'password'}))){
		    &Log::do_log('err','Unable to add admin %s to user_table', $who);
		    next;
		}
	    }
	}	    

	$new_admin_user->{'subscribed'} ||= 0;
 	$new_admin_user->{'included'} ||= 0;

	## Update Admin Table
	unless(&SDM::do_query("INSERT INTO admin_table (user_admin, comment_admin, list_admin, robot_admin, date_admin, update_admin, reception_admin, visibility_admin, subscribed_admin,included_admin,include_sources_admin, role_admin, info_admin, profile_admin) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)", 
	&SDM::quote($who), 
	&SDM::quote($new_admin_user->{'gecos'}), 
	&SDM::quote($name), 
	&SDM::quote($self->{'domain'}),
	&SDM::get_canonical_write_date($new_admin_user->{'date'}), 
	&SDM::get_canonical_write_date($new_admin_user->{'update_date'}), 
	&SDM::quote($new_admin_user->{'reception'}), 
	&SDM::quote($new_admin_user->{'visibility'}), 
	$new_admin_user->{'subscribed'}, 
	$new_admin_user->{'included'}, 
	&SDM::quote($new_admin_user->{'id'}), 
	&SDM::quote($role), 
	&SDM::quote($new_admin_user->{'info'}), 
	&SDM::quote($new_admin_user->{'profile'}))){
	    &Log::do_log('err','Unable to add admin %s to table admin_table for list %s@%s %s', $who,$name,$self->{'domain'});
	    next;
	}
	$total++;
    }

    return $total;
}

#XXX sub rename_list_db

## Is the user listmaster
sub is_listmaster {
    my $who = shift;
    my $robot = shift;

    $who =~ y/A-Z/a-z/;

    return 0 unless ($who);

    foreach my $listmaster (@{&Conf::get_robot_conf($robot,'listmasters')}){
	return 1 if (lc($listmaster) eq lc($who));
    }
	
    foreach my $listmaster (Conf->listmasters) {
	return 1 if (lc($listmaster) eq lc($who));
    }    

    return 0;
}

## Does the user have a particular function in the list?
sub am_i {
    &Log::do_log('debug2', '(%s, %s, %s, %s)', @_);
    my $self = shift;
    my $function = lc(shift || '');
    my $who = &tools::clean_email(shift || '');
    my $options = shift || {};

    return undef unless $self and $who;

    ## If 'strict' option is given, then listmaster does not inherit privileged
    unless ($options->{'strict'}) {
	## Listmaster has all privileges except editor
	# sa contestable.
	if (($function eq 'owner' || $function eq 'privileged_owner') and
	    &is_listmaster($who, $self->domain)) {
	    #$self->user('owner', $who, { 'profile' => 'privileged' });
	    return 1;
	}
    }
	
    if ($function eq 'privileged_owner') {
	if ($self->user('owner', $who) and
	    $self->user('owner', $who)->{'profile'} eq 'privileged') {
	    return 1;
	}
    } elsif ($function eq 'editor') {
	if ($self->user('editor', $who)) {
	    return 1;
	}
	## Check if any editor is defined ; if not owners are editors
	my $editors = $self->get_editors() || [];
	unless (scalar @$editors) {
	    # if no editor defined, owners has editor privilege
	    if ($self->user('owner', $who)) {
		return 1;
	    }
	}
    } elsif ($self->user($function, $who)) {
	return 1;
    }

    return undef;
}

## Check list authorizations
## Higher level sub for request_action
sub check_list_authz {
    my $self = shift;
    my $operation = shift;
    my $auth_method = shift;
    my $context = shift;
    my $debug = shift;
    &Log::do_log('debug', 'List::check_list_authz %s,%s',$operation,$auth_method);

    $context->{'list_object'} = $self;

    return &Scenario::request_action($operation, $auth_method, $self->{'domain'}, $context, $debug);
}

## Initialize internal list cache
sub init_list_cache {
    &Log::do_log('debug2', 'List::init_list_cache()');
    
    undef %list_cache;
}

## May the indicated user edit the indicated list parameter or not?
sub may_edit {

    my($self,$parameter, $who) = @_;
    &Log::do_log('debug3', 'List::may_edit(%s, %s)', $parameter, $who);

    my $role;

    return undef unless ($self);

    my $edit_conf;

    # Load edit_list.conf: track by file, not domain (file may come from server, robot, family or list context)
    my $edit_conf_file = &tools::get_filename('etc',{},'edit_list.conf',$self->{'domain'},$self); 
    if (! $edit_list_conf{$edit_conf_file} || ((stat($edit_conf_file))[9] > $mtime{'edit_list_conf'}{$edit_conf_file})) {

        $edit_conf = $edit_list_conf{$edit_conf_file} = &tools::load_edit_list_conf($self->{'domain'}, $self);
	$mtime{'edit_list_conf'}{$edit_conf_file} = time;
    }else {
        $edit_conf = $edit_list_conf{$edit_conf_file};
    }

    ## What privilege?
    if (&is_listmaster($who,$self->{'domain'})) {
	$role = 'listmaster';
    }elsif ( $self->am_i('privileged_owner',$who) ) {
	$role = 'privileged_owner';
	
    }elsif ( $self->am_i('owner',$who) ) {
	$role = 'owner';
	
    }elsif ( $self->am_i('editor',$who) ) {
	$role = 'editor';
	
#    }elsif ( $self->am_i('subscriber',$who) ) {
#	$role = 'subscriber';
#	
    }else {
	return ('user','hidden');
    }

    ## What privilege does he/she has?
    my ($what, @order);

    if (($parameter =~ /^(\w+)\.(\w+)$/) &&
	($parameter !~ /\.tt2$/)) {
	my $main_parameter = $1;
	@order = ($edit_conf->{$parameter}{$role},
		  $edit_conf->{$main_parameter}{$role}, 
		  $edit_conf->{'default'}{$role}, 
		  $edit_conf->{'default'}{'default'})
    }else {
	@order = ($edit_conf->{$parameter}{$role}, 
		  $edit_conf->{'default'}{$role}, 
		  $edit_conf->{'default'}{'default'})
    }
    
    foreach $what (@order) {
	if (defined $what) {
	    return ($role,$what);
	}
    }
    
    return ('user','hidden');
}


## May the indicated user edit a paramter while creating a new list
## Dev note: This sub is never called. Shall we remove it?
sub may_create_parameter {

    my($self, $parameter, $who,$robot) = @_;
    &Log::do_log('debug3', 'List::may_create_parameter(%s, %s, %s)', $parameter, $who,$robot);

    if ( &is_listmaster($who,$robot)) {
	return 1;
    }
    my $edit_conf = &tools::load_edit_list_conf($robot,$self);
    $edit_conf->{$parameter} ||= $edit_conf->{'default'};
    if (! $edit_conf->{$parameter}) {
	&Log::do_log('notice','tools::load_edit_list_conf privilege for parameter $parameter undefined');
	return undef;
    }
    if ($edit_conf->{$parameter}  =~ /^(owner|privileged_owner)$/i ) {
	return 1;
    }else{
	return 0;
    }

}


## May the indicated user do something with the list or not?
## Action can be : send, review, index, get
##                 add, del, reconfirm, purge
sub may_do {
   my($self, $action, $who) = @_;
   &Log::do_log('debug3', 'List::may_do(%s, %s)', $action, $who);

   my $i;

   ## Just in case.
   return undef unless ($self && $action);
   my $admin = $self->{'admin'};
   return undef unless ($admin);

   $action =~ y/A-Z/a-z/;
   $who =~ y/A-Z/a-z/;

   if ($action =~ /^(index|get)$/io) {
       my $arc_access = $admin->{'archive'}{'access'};
       if ($arc_access =~ /^public$/io)  {
	   return 1;
       }elsif ($arc_access =~ /^private$/io) {
	   return 1 if ($self->is_list_member($who));
	   return $self->am_i('owner', $who);
       }elsif ($arc_access =~ /^owner$/io) {
	   return $self->am_i('owner', $who);
       }
       return undef;
   }

   if ($action =~ /^(review)$/io) {
       foreach $i (@{$admin->{'review'}}) {
	   if ($i =~ /^public$/io) {
	       return 1;
	   }elsif ($i =~ /^private$/io) {
	       return 1 if ($self->is_list_member($who));
	       return $self->am_i('owner', $who);
	   }elsif ($i =~ /^owner$/io) {
	       return $self->am_i('owner', $who);
	   }
	   return undef;
       }
   }

   if ($action =~ /^send$/io) {
      if ($admin->{'send'} =~/^(private|privateorpublickey|privateoreditorkey)$/i) {

         return undef unless ($self->is_list_member($who) || $self->am_i('owner', $who));
      }elsif ($admin->{'send'} =~ /^(editor|editorkey|privateoreditorkey)$/i) {
         return undef unless ($self->am_i('editor', $who));
      }elsif ($admin->{'send'} =~ /^(editorkeyonly|publickey|privatekey)$/io) {
         return undef;
      }
      return 1;
   }

   if ($action =~ /^(add|del|remind|reconfirm|purge)$/io) {
      return $self->am_i('owner', $who);
   }

   if ($action =~ /^(modindex)$/io) {
       return undef unless ($self->am_i('editor', $who));
       return 1;
   }

   if ($action =~ /^auth$/io) {
       if ($admin->{'send'} =~ /^(privatekey)$/io) {
	   return 1 if ($self->is_list_member($who) || $self->am_i('owner', $who));
       } elsif ($admin->{'send'} =~ /^(privateorpublickey)$/io) {
	   return 1 unless ($self->is_list_member($who) || $self->am_i('owner', $who));
       }elsif ($admin->{'send'} =~ /^(publickey)$/io) {
	   return 1;
       }
       return undef; #authent
   } 
   return undef;
}

## Does the list support digest mode
sub is_digest {
   return (shift->{'admin'}{'digest'});
}

## Does the file exist?
sub archive_exist {
   my($self, $file) = @_;
   &Log::do_log('debug', 'List::archive_exist (%s)', $file);

   return undef unless ($self->is_archived());
   my $dir = &Conf::get_robot_conf($self->{'domain'},'arc_path').'/'.$self->get_list_id();
   Archive::exist($dir, $file);

}


## List the archived files
sub archive_ls {
   my $self = shift;
   &Log::do_log('debug2', 'List::archive_ls');

   my $dir = &Conf::get_robot_conf($self->{'domain'},'arc_path').'/'.$self->get_list_id();

   Archive::list($dir) if ($self->is_archived());
}

## Archive 
sub archive_msg {
    my($self, $message ) = @_;
   &Log::do_log('debug', 'List::archive_msg for %s',$self->{'name'});

    if ($self->is_archived()){
	
	my $msgtostore = $message->{'msg_as_string'};
	if (($message->{'smime_crypted'} eq 'smime_crypted') && ($self->{admin}{archive_crypted_msg} eq 'original')) {
	    $msgtostore = $message->{'orig_msg'}->as_string;
	}
#	Archive::store_last($self, $msgtostore) ;
	
	if (($Conf::Conf{'ignore_x_no_archive_header_feature'} ne 'on') && (($message->{'msg'}->head->get('X-no-archive') =~ /yes/i) || ($message->{'msg'}->head->get('Restrict') =~ /no\-external\-archive/i))) {
	    ## ignoring message with a no-archive flag	    
	   &Log::do_log('info',"Do not archive message with no-archive flag for list %s",$self->get_list_id());
	}else{
	    my $spoolarchive = new Sympaspool ('archive');
	    unless ($message->{'messagekey'}) {
	&Log::do_log('err', "could not store message in archive spool, messagekey missing");
		return undef;
	    }
	    unless ($spoolarchive->store($msgtostore,{ 'robot' => $self->domain,'list' => $self->name })){
	&Log::do_log('err', "could not store message in archive spool, unkown reason");
		return undef;
	    }
	}
    }
}

## Is the list moderated?                                                          
sub is_moderated {
    return 1 if (defined shift->{'admin'}{'editor'});                                                          
    return 0;
}

## Is the list archived?
sub is_archived {
    if (shift->{'admin'}{'web_archive'}{'access'}) {&Log::do_log('debug', 'List::is_archived : 1'); return 1 ;}  
    return undef;
}

## Is the list web archived?
sub is_web_archived {
    return 1 if (shift->{'admin'}{'web_archive'}{'access'}) ;
    return undef;
   
}

## Returns 1 if the  digest  must be send 
sub get_nextdigest {
    my $self = shift;
    my $date = shift;   # the date epoch as stored in the spool database

   &Log::do_log('debug3', 'List::get_nextdigest (list = %s)',$self->{'name'});

    my $digest = $self->{'admin'}{'digest'};

    unless ($digest) {
	return undef;
    }
    
    my @days = @{$digest->{'days'}};
    my ($hh, $mm) = ($digest->{'hour'}, $digest->{'minute'});
     
    my @now  = localtime(time);
    my $today = $now[6]; # current day
    my @timedigest = localtime($date);

    ## Should we send a digest today
    my $send_digest = 0;
    foreach my $d (@days){
	if ($d == $today) {
	    $send_digest = 1;
	    last;
	}
    }

    return undef unless ($send_digest == 1);

    if (($now[2] * 60 + $now[1]) >= ($hh * 60 + $mm) and 
	(timelocal(0, $mm, $hh, $now[3], $now[4], $now[5]) > timelocal(0, $timedigest[1], $timedigest[2], $timedigest[3], $timedigest[4], $timedigest[5]))
        ){
	return 1;
    }

    return undef;
}

	
## Loads all scenari for an action
sub load_scenario_list {
    my ($self, $action,$robot) = @_;
    &Log::do_log('debug3', 'List::load_scenario_list(%s,%s)', $action,$robot);

    my $directory = "$self->{'dir'}";
    my %list_of_scenario;
    my %skip_scenario;

    foreach my $dir (
        "$directory/scenari",
        "$Conf::Conf{'etc'}/$robot/scenari",
        "$Conf::Conf{'etc'}/scenari",
        Sympa::Constants::DEFAULTDIR . '/scenari'
    ) {
	next unless (-d $dir);
	
	my $scenario_regexp = &tools::get_regexp('scenario');

	while (<$dir/$action.*:ignore>) {
	    if (/$action\.($scenario_regexp):ignore$/) {
		my $name = $1;
		$skip_scenario{$name} = 1;
	    }
	}

	while (<$dir/$action.*>) {
	    next unless (/$action\.($scenario_regexp)$/);
	    my $name = $1;
	    
	    next if (defined $list_of_scenario{$name});
	    next if (defined $skip_scenario{$name});

	    my $scenario = new Scenario ('robot' => $robot,
					 'directory' => $directory,
					 'function' => $action,
					 'name' => $name);
	    $list_of_scenario{$name} = $scenario;

	    ## Set the title in the current language
	    if (defined  $scenario->{'title'}{&Language::GetLang()}) {
		$list_of_scenario{$name}{'web_title'} = $scenario->{'title'}{&Language::GetLang()};
	    }elsif (defined $scenario->{'title'}{'gettext'}) {
		$list_of_scenario{$name}{'web_title'} = gettext($scenario->{'title'}{'gettext'});
	    }elsif (defined $scenario->{'title'}{'us'}) {
		$list_of_scenario{$name}{'web_title'} = gettext($scenario->{'title'}{'us'});
	    }else {
		$list_of_scenario{$name}{'web_title'} = $name;		     
	    }
	    $list_of_scenario{$name}{'name'} = $name;	    
	}
    }

    ## Return a copy of the data to prevent unwanted changes in the central scenario data structure
    return &tools::dup_var(\%list_of_scenario);
}

sub load_task_list {
    my ($self, $action,$robot) = @_;
    &Log::do_log('debug2', 'List::load_task_list(%s,%s)', $action,$robot);

    my $directory = "$self->{'dir'}";
    my %list_of_task;
    
    foreach my $dir (
        "$directory/list_task_models",
        "$Conf::Conf{'etc'}/$robot/list_task_models",
        "$Conf::Conf{'etc'}/list_task_models",
        Sympa::Constants::DEFAULTDIR . '/list_task_models'
    ) {

	next unless (-d $dir);

	foreach my $file (<$dir/$action.*>) {
	    next unless ($file =~ /$action\.(\w+)\.task$/);
	    my $name = $1;
	    
	    next if (defined $list_of_task{$name});
	    
	    $list_of_task{$name}{'name'} = $name;

	    my $titles = &List::_load_task_title ($file);

	    ## Set the title in the current language
	    if (defined  $titles->{&Language::GetLang()}) {
		$list_of_task{$name}{'title'} = $titles->{&Language::GetLang()};
	    }elsif (defined $titles->{'gettext'}) {
		$list_of_task{$name}{'title'} = gettext( $titles->{'gettext'});
	    }elsif (defined $titles->{'us'}) {
		$list_of_task{$name}{'title'} = gettext( $titles->{'us'});		
	    }else {
		$list_of_task{$name}{'title'} = $name;		     
	    }

	}
    }

    return \%list_of_task;
}

sub _load_task_title {
    my $file = shift;
    &Log::do_log('debug3', 'List::_load_task_title(%s)', $file);
    my $title = {};

    unless (open TASK, $file) {
	&Log::do_log('err', 'Unable to open file "%s"' , $file);
	return undef;
    }

    while (<TASK>) {
	last if /^\s*$/;

	if (/^title\.([\w-]+)\s+(.*)\s*$/) {
	    $title->{$1} = $2;
	}
    }

    close TASK;

    return $title;
}

## Loads all data sources
sub load_data_sources_list {
    my ($self, $robot) = @_;
    &Log::do_log('debug3', 'List::load_data_sources_list(%s,%s)', $self->{'name'},$robot);

    my $directory = "$self->{'dir'}";
    my %list_of_data_sources;

    foreach my $dir (
        "$directory/data_sources",
        "$Conf::Conf{'etc'}/$robot/data_sources",
        "$Conf::Conf{'etc'}/data_sources",
        Sympa::Constants::DEFAULTDIR . '/data_sources'
    ) {

	next unless (-d $dir);
	
	while  (my $f = <$dir/*.incl>) {
	    
	    next unless ($f =~ /([\w\-]+)\.incl$/);
	    
	    my $name = $1;
	    
	    next if (defined $list_of_data_sources{$name});
	    
	    $list_of_data_sources{$name}{'title'} = $name;
	    $list_of_data_sources{$name}{'name'} = $name;
	}
    }
    
    return \%list_of_data_sources;
}

## Loads the statistics information
sub _load_stats_file {
    my $self = shift;

    croak "Invalid parameter: $self" unless ref $self; #prototype changed (6.2)

    my $file = $self->dir . '/stats';
    &Log::do_log('debug3', '(%s, file=%s)', $self, $file);

   ## Create the initial stats array.
   my ($stats, $total, $last_sync, $last_sync_admin_user);
 
   if (open(L, $file)){     
       if (<L> =~ /^(\d+)\s+(\d+)\s+(\d+)\s+(\d+)(\s+(\d+))?(\s+(\d+))?(\s+(\d+))?/) {
	   $stats = [ $1, $2, $3, $4];
	   $total = $6;
	   $last_sync = $8;
	   $last_sync_admin_user = $10;
	   
       } else {
	   $stats = [ 0, 0, 0, 0];
	   $total = 0;
	   $last_sync = 0;
	   $last_sync_admin_user = 0;
       }
       close(L);
   } else {
       $stats = [ 0, 0, 0, 0];
       $total = 0;
       $last_sync = 0;
       $last_sync_admin_user = 0;
   }

    $self->{'last_sync'} = $last_sync;
    $self->{'last_sync_admin_user'} = $last_sync_admin_user;
    $self->{'stats'} = $stats if defined $stats;
    $self->total($total) if defined $total;
}

## Loads the list of subscribers.
sub _load_list_members_file {
    my $file = shift;
    &Log::do_log('debug2', '(%s)', $file);
    
    ## Open the file and switch to paragraph mode.
    open(L, $file) || return undef;
    
    ## Process the lines
    local $/;
    my $data = <L>;

    my @users;
    foreach (split /\n\n/, $data) {
	my(%user, $email);
	$user{'email'} = $email = $1 if (/^\s*email\s+(.+)\s*$/om);
	$user{'gecos'} = $1 if (/^\s*gecos\s+(.+)\s*$/om);
	$user{'date'} = $1 if (/^\s*date\s+(\d+)\s*$/om);
	$user{'update_date'} = $1 if (/^\s*update_date\s+(\d+)\s*$/om);
	$user{'reception'} = $1 if (/^\s*reception\s+(digest|nomail|summary|notice|txt|html|urlize|not_me)\s*$/om);
	$user{'visibility'} = $1 if (/^\s*visibility\s+(conceal|noconceal)\s*$/om);

	push @users, \%user;
    }
    close(L);
    
    return @users;
}

## include a remote sympa list as subscribers.
sub _include_users_remote_sympa_list {
    my ($self, $users, $param, $dir, $robot, $default_user_options , $tied) = @_;

    my $host = $param->{'host'};
    my $port = $param->{'port'} || '443';
    my $path = $param->{'path'};
    my $cert = $param->{'cert'} || 'list';

    my $id = Datasource::_get_datasource_id($param);

    &Log::do_log('debug', 'List::_include_users_remote_sympa_list(%s) https://%s:%s/%s using cert %s,', $self->{'name'}, $host, $port, $path, $cert);
    
    my $total = 0; 
    my $get_total = 0;

    my $cert_file ; my $key_file ;

    $cert_file = $dir.'/cert.pem';
    $key_file = $dir.'/private_key';
    if ($cert eq 'list') {
	$cert_file = $dir.'/cert.pem';
	$key_file = $dir.'/private_key';
    }elsif($cert eq 'robot') {
	$cert_file = &tools::get_filename('etc',{},'cert.pem',$robot,$self);
	$key_file =  &tools::get_filename('etc',{},'private_key',$robot,$self);
    }
    unless ((-r $cert_file) && ( -r $key_file)) {
	&Log::do_log('err', 'Include remote list https://%s:%s/%s using cert %s, unable to open %s or %s', $host, $port, $path, $cert,$cert_file,$key_file);
	return undef;
    }
    
    my $getting_headers = 1;

    my %user ;
    my $email ;


    foreach my $line ( &Fetch::get_https($host,$port,$path,$cert_file,$key_file,{'key_passwd' => $Conf::Conf{'key_passwd'},
                                                                               'cafile'    => $Conf::Conf{'cafile'},
                                                                               'capath' => $Conf::Conf{'capath'}})
		){	
	chomp $line;

	if ($getting_headers) { # ignore http headers
	    next unless ($line =~ /^(date|update_date|email|reception|visibility)/);
	}
	undef $getting_headers;

	if ($line =~ /^\s*email\s+(.+)\s*$/o) {
	    $user{'email'} = $email = $1;
	    &Log::do_log('debug',"email found $email");
	    $get_total++;
	}
	$user{'gecos'} = $1 if ($line =~ /^\s*gecos\s+(.+)\s*$/o);
        
  	next unless ($line =~ /^$/) ;
	
	unless ($user{'email'}) {
	    &Log::do_log('debug','ignoring block without email definition');
	    next;
	}
	my %u;
	## Check if user has already been included
	if ($users->{$email}) {
	    &Log::do_log('debug3',"ignore $email because already member");
	    if ($tied) {
		%u = split "\n",$users->{$email};
	    }else {
		%u = %{$users->{$email}};
	    }
	}else{
	    &Log::do_log('debug3',"add new subscriber $email");
	    %u = %{$default_user_options};
	    $total++;
	}	    
	$u{'email'} = $user{'email'};
	$u{'id'} = join (',', split(',', $u{'id'}), $id);
	$u{'gecos'} = $user{'gecos'};delete $user{'gecos'};
	
	$u{'visibility'} = $default_user_options->{'visibility'} if (defined $default_user_options->{'visibility'});
	$u{'reception'} = $default_user_options->{'reception'} if (defined $default_user_options->{'reception'});
	$u{'profile'} = $default_user_options->{'profile'} if (defined $default_user_options->{'profile'});
	$u{'info'} = $default_user_options->{'info'} if (defined $default_user_options->{'info'});
	
	if ($tied) {
	    $users->{$email} = join("\n", %u);
	}else{
	    $users->{$email} = \%u;
	}
	delete $user{$email};undef $email;

    }
    &Log::do_log('info','Include %d users from list (%d subscribers) https://%s:%s%s',$total,$get_total,$host,$port,$path);
    return $total ;    
}



## include a list as subscribers.
sub _include_users_list {
    my ($users, $includelistname, $robot, $default_user_options, $tied) = @_;
    &Log::do_log('debug2', 'List::_include_users_list');

    my $total = 0;
    
    my $includelist;
    
    ## The included list is local or in another local robot
    if ($includelistname =~ /\@/) {
	$includelist = new List ($includelistname);
    }else {
	$includelist = new List ($includelistname, $robot);
    }

    unless ($includelist) {
	&Log::do_log('info', 'Included list %s unknown' , $includelistname);
	return undef;
    }
    
    my $id = Datasource::_get_datasource_id($includelistname);

    for (my $user = $includelist->get_first_list_member(); $user; $user = $includelist->get_next_list_member()) {
	my %u;

	## Check if user has already been included
	if ($users->{$user->{'email'}}) {
	    if ($tied) {
		%u = split "\n",$users->{$user->{'email'}};
	    }else {
		%u = %{$users->{$user->{'email'}}};
	    }
	}else {
	    %u = %{$default_user_options};
	    $total++;
	}
	    
	my $email =  $u{'email'} = $user->{'email'};
	$u{'gecos'} = $user->{'gecos'};
	$u{'id'} = join (',', split(',', $u{'id'}), $id);

	$u{'visibility'} = $default_user_options->{'visibility'} if (defined $default_user_options->{'visibility'});
	$u{'reception'} = $default_user_options->{'reception'} if (defined $default_user_options->{'reception'});
	$u{'profile'} = $default_user_options->{'profile'} if (defined $default_user_options->{'profile'});
	$u{'info'} = $default_user_options->{'info'} if (defined $default_user_options->{'info'});

	if ($tied) {
	    $users->{$email} = join("\n", %u);
	}else {
	    $users->{$email} = \%u;
	}
    }
    &Log::do_log('info',"Include %d users from list %s",$total,$includelistname);
    return $total ;
}

sub _include_users_file {
    my ($users, $filename, $default_user_options,$tied) = @_;
    &Log::do_log('debug2', 'List::_include_users_file(%s)', $filename);

    my $total = 0;
    
    unless (open(INCLUDE, "$filename")) {
	&Log::do_log('err', 'Unable to open file "%s"' , $filename);
	return undef;
    }
    &Log::do_log('debug2','including file %s' , $filename);

    my $id = Datasource::_get_datasource_id($filename);
    my $lines = 0;
    my $emails_found = 0;
    my $email_regexp = &tools::get_regexp('email');
    
    while (<INCLUDE>) {
	if($lines > 49 && $emails_found == 0){
	    &Log::do_log('err','Too much errors in file %s (%s lines, %s emails found). Source file probably corrupted. Cancelling.',$filename, $lines, $emails_found);
	    return undef;
	}
	
	## Each line is expected to start with a valid email address
	## + an optional gecos
	## Empty lines are skipped
	next if /^\s*$/;
	next if /^\s*\#/;

	## Skip badly formed emails
	unless (/^\s*($email_regexp)(\s*(\S.*))?\s*$/) {
		Log::do_log('err', "Skip badly formed line: '%s'", $_);
		next;
	}

	my $email = &tools::clean_email($1);

	unless (&tools::valid_email($email)) {
		Log::do_log('err', "Skip badly formed email address: '%s'", $email);
		next;
	}
	
        $lines++;
	next unless $email;
	my $gecos = $5;
	$emails_found++;

	my %u;
	## Check if user has already been included
	if ($users->{$email}) {
	    if ($tied) {
		%u = split "\n",$users->{$email};
	    }else {
		%u = %{$users->{$email}};
	    }
	}else {
	    %u = %{$default_user_options};
	    $total++;
	}
	$u{'email'} = $email;
	$u{'gecos'} = $gecos;
	$u{'id'} = join (',', split(',', $u{'id'}), $id);

	$u{'visibility'} = $default_user_options->{'visibility'} if (defined $default_user_options->{'visibility'});
	$u{'reception'} = $default_user_options->{'reception'} if (defined $default_user_options->{'reception'});
	$u{'profile'} = $default_user_options->{'profile'} if (defined $default_user_options->{'profile'});
	$u{'info'} = $default_user_options->{'info'} if (defined $default_user_options->{'info'});

	if ($tied) {
	    $users->{$email} = join("\n", %u);
	}else {
	    $users->{$email} = \%u;
	}
    }
    close INCLUDE ;
    
    
    &Log::do_log('info',"include %d new users from file %s",$total,$filename);
    return $total ;
}
    
sub _include_users_remote_file {
    my ($users, $param, $default_user_options,$tied) = @_;

    my $url = $param->{'url'};
    
    &Log::do_log('debug', "List::_include_users_remote_file($url)");

    my $total = 0;
    my $id = Datasource::_get_datasource_id($param);

    ## WebAgent package is part of Fetch.pm and inherites from LWP::UserAgent

    my $fetch = WebAgent->new (agent => 'Sympa/'. Sympa::Constants::VERSION);

    my $req = HTTP::Request->new(GET => $url);
    
    if (defined $param->{'user'} && defined $param->{'passwd'}) {
	&WebAgent::set_basic_credentials($param->{'user'},$param->{'passwd'});
    }

    my $res = $fetch->request($req);  

    # check the outcome
    if ($res->is_success) {
	my @remote_file = split(/\n/,$res->content);
	my $lines = 0;
	my $emails_found = 0;
	my $email_regexp = &tools::get_regexp('email');

	# forgot headers (all line before one that contain a email
	foreach my $line (@remote_file) {
	    if($lines > 49 && $emails_found == 0){
		&Log::do_log('err','Too much errors in file %s (%s lines, %s emails found). Source file probably corrupted. Cancelling.',$url, $lines, $emails_found);
		return undef;
	    }
	    
	    ## Each line is expected to start with a valid email address
	    ## + an optional gecos
	    ## Empty lines are skipped
	    next if ($line =~ /^\s*$/);
	    next if ($line =~ /^\s*\#/);

	    ## Skip badly formed emails
	    unless ($line =~ /^\s*($email_regexp)(\s*(\S.*))?\s*$/) {
		Log::do_log('err', "Skip badly formed line: '%s'", $line);
		next;
	    }

	    my $email = &tools::clean_email($1);

	    unless (&tools::valid_email($email)) {
		Log::do_log('err', "Skip badly formed email address: '%s'", $line);
		next;
	    }

	    $lines++;
	    next unless $email;
	    my $gecos = $5;		
	    $emails_found++;

	    my %u;
	    ## Check if user has already been included
	    if ($users->{$email}) {
		if ($tied) {
		    %u = split "\n",$users->{$email};
		}else{
		    %u = %{$users->{$email}};
		    foreach my $k (keys %u) {
		    }
		}
	    }else {
		%u = %{$default_user_options};
		$total++;
	    }
	    $u{'email'} = $email;
	    $u{'gecos'} = $gecos;
	    $u{'id'} = join (',', split(',', $u{'id'}), $id);
	    
	    $u{'visibility'} = $default_user_options->{'visibility'} if (defined $default_user_options->{'visibility'});
	    $u{'reception'} = $default_user_options->{'reception'} if (defined $default_user_options->{'reception'});
	    $u{'profile'} = $default_user_options->{'profile'} if (defined $default_user_options->{'profile'});
	    $u{'info'} = $default_user_options->{'info'} if (defined $default_user_options->{'info'});
	    
	    if ($tied) {
		$users->{$email} = join("\n", %u);
	    }else {
		$users->{$email} = \%u;
	    }
	}
    }
    else {
	&Log::do_log ('err',"List::include_users_remote_file: Unable to fetch remote file $url : %s", $res->message());
	return undef; 
    }

    ## Reset http credentials
    &WebAgent::set_basic_credentials('','');

    &Log::do_log('info',"include %d users from remote file %s",$total,$url);
    return $total ;
}

## Includes users from voot group
sub _include_users_voot_group {
	my($users, $param, $default_user_options, $tied) = @_;

	&Log::do_log('debug', "List::_include_users_voot_group(%s, %s, %s)", $param->{'user'}, $param->{'provider'}, $param->{'group'});

	my $id = Datasource::_get_datasource_id($param);
	
	my $consumer = new VOOTConsumer(
		user => $param->{'user'},
		provider => $param->{'provider'}
	);
	
	# Here we need to check if we are in a web environment and set consumer's webEnv accordingly
	
	unless($consumer) {
		&Log::do_log('err', 'Cannot create VOOT consumer. Cancelling.');
		return undef;
	}
	
	my $members = $consumer->getGroupMembers(group => $param->{'group'});
	unless(defined $members) {
		my $url = $consumer->getOAuthConsumer()->mustRedirect();
		# Report error with redirect url
		#return &do_redirect($url) if(defined $url);
		return undef;
	}
	
	my $email_regexp = &tools::get_regexp('email');
	my $total = 0;
	
	foreach my $member (@$members) {
		#foreach my $email (@{$member->{'emails'}}) {
		if(my $email = shift(@{$member->{'emails'}})) {
			unless(&tools::valid_email($email)) {
				&Log::do_log('err', "Skip badly formed email address: '%s'", $email);
				next;
			}
			next unless($email);
			
			## Check if user has already been included
			my %u;
			if($users->{$email}) {
				%u = $tied ? split("\n", $users->{$email}) : %{$users->{$email}};
			}else{
				%u = %{$default_user_options};
				$total++;
			}
			
			$u{'email'} = $email;
			$u{'gecos'} = $member->{'displayName'};
			$u{'id'} = join (',', split(',', $u{'id'}), $id);
			
			$u{'visibility'} = $default_user_options->{'visibility'} if(defined $default_user_options->{'visibility'});
			$u{'reception'} = $default_user_options->{'reception'} if(defined $default_user_options->{'reception'});
			$u{'profile'} = $default_user_options->{'profile'} if(defined $default_user_options->{'profile'});
			$u{'info'} = $default_user_options->{'info'} if(defined $default_user_options->{'info'});
			
			if($tied) {
				$users->{$email} = join("\n", %u);
			}else{
				$users->{$email} = \%u;
			}
		}
	}
	
	&Log::do_log('info',"included %d users from VOOT group %s at provider %s", $total, $param->{'group'}, $param->{'provider'});
	
	return $total;
}


## Returns a list of subscribers extracted from a remote LDAP Directory
sub _include_users_ldap {
    my ($users, $id, $source, $default_user_options, $tied) = @_;
    &Log::do_log('debug2', 'List::_include_users_ldap');
    
    my $user = $source->{'user'};
    my $passwd = $source->{'passwd'};
    my $ldap_suffix = $source->{'suffix'};
    my $ldap_filter = $source->{'filter'};
    my $ldap_attrs = $source->{'attrs'};
    my $ldap_select = $source->{'select'};
    
    my ($email_attr, $gecos_attr) = split(/\s*,\s*/, $ldap_attrs);
    my @ldap_attrs = ($email_attr);
    push @ldap_attrs, $gecos_attr if($gecos_attr);
    
    ## LDAP and query handler
    my ($ldaph, $fetch);

    ## Connection timeout (default is 120)
    #my $timeout = 30; 
    
    unless (defined $source && $source->connect()) {
	&Log::do_log('err',"Unable to connect to the LDAP server '%s'", $source->{'host'});
	    return undef;
	}
    &Log::do_log('debug2', 'Searching on server %s ; suffix %s ; filter %s ; attrs: %s', $source->{'host'}, $ldap_suffix, $ldap_filter, $ldap_attrs);
    $fetch = $source->{'ldap_handler'}->search ( base => "$ldap_suffix",
			      filter => "$ldap_filter",
			      attrs => @ldap_attrs,
			      scope => "$source->{'scope'}");
    if ($fetch->code()) {
	&Log::do_log('err','Ldap search (single level) failed : %s (searching on server %s ; suffix %s ; filter %s ; attrs: %s)', 
	       $fetch->error(), $source->{'host'}, $ldap_suffix, $ldap_filter, $ldap_attrs);
        return undef;
    }
    
    ## Counters.
    my $total = 0;
    my $dn; 
    my @emails;
    my %emailsViewed;

    while (my $e = $fetch->shift_entry) {
	my $emailentry = $e->get_value($email_attr, asref => 1);
	my $gecosentry = $e->get_value($gecos_attr, asref => 1);
	$gecosentry = $gecosentry->[0] if(ref($gecosentry) eq 'ARRAY');
	
	## Multiple values
	if (ref($emailentry) eq 'ARRAY') {
	    foreach my $email (@{$emailentry}) {
		my $cleanmail = &tools::clean_email($email);
		## Skip badly formed emails
		unless (&tools::valid_email($email)) {
			Log::do_log('err', "Skip badly formed email address: '%s'", $email);
			next;
		}
		    
		next if ($emailsViewed{$cleanmail});
		push @emails, [$cleanmail, $gecosentry];
		$emailsViewed{$cleanmail} = 1;
		last if ($ldap_select eq 'first');
	    }
	}else {
	    my $cleanmail = &tools::clean_email($emailentry);
	    ## Skip badly formed emails
	    unless (&tools::valid_email($emailentry)) {
		Log::do_log('err', "Skip badly formed email address: '%s'", $emailentry);
		next;
	    }
	    unless ($emailsViewed{$cleanmail}) {
		push @emails, [$cleanmail, $gecosentry];
		$emailsViewed{$cleanmail} = 1;
	    }
	}
    }
    
    unless ($source->disconnect()) {
	&Log::do_log('notice','Can\'t unbind from  LDAP server %s', $source->{'host'});
	return undef;
    }
    
    foreach my $emailgecos (@emails) {
	my ($email, $gecos) = @$emailgecos;
	next if ($email =~ /^\s*$/);

	$email = &tools::clean_email($email);
	my %u;
	## Check if user has already been included
	if ($users->{$email}) {
	    if ($tied) {
		%u = split "\n",$users->{$email};
	    }else {
		%u = %{$users->{$email}};
	    }
	}else {
	    %u = %{$default_user_options};
	    $total++;
	}

	$u{'email'} = $email;
	$u{'gecos'} = $gecos if($gecos);
	$u{'date'} = time;
	$u{'update_date'} = time;
	$u{'id'} = join (',', split(',', $u{'id'}), $id);

	$u{'visibility'} = $default_user_options->{'visibility'} if (defined $default_user_options->{'visibility'});
	$u{'reception'} = $default_user_options->{'reception'} if (defined $default_user_options->{'reception'});
	$u{'profile'} = $default_user_options->{'profile'} if (defined $default_user_options->{'profile'});
	$u{'info'} = $default_user_options->{'info'} if (defined $default_user_options->{'info'});

	if ($tied) {
	    $users->{$email} = join("\n", %u);
	}else {
	    $users->{$email} = \%u;
	}
    }

    &Log::do_log('debug2',"unbinded from LDAP server %s ", $source->{'host'});
    &Log::do_log('info','%d new users included from LDAP query',$total);

    return $total;
}

## Returns a list of subscribers extracted indirectly from a remote LDAP
## Directory using a two-level query
sub _include_users_ldap_2level {
    my ($users, $id, $source, $default_user_options,$tied) = @_;
    &Log::do_log('debug2', 'List::_include_users_ldap_2level');
    
    my $user = $source->{'user'};
    my $passwd = $source->{'passwd'};
    my $ldap_suffix1 = $source->{'suffix1'};
    my $ldap_filter1 = $source->{'filter1'};
    my $ldap_attrs1 = $source->{'attrs1'};
    my $ldap_select1 = $source->{'select1'};
    my $ldap_scope1 = $source->{'scope1'};
    my $ldap_regex1 = $source->{'regex1'};
    my $ldap_suffix2 = $source->{'suffix2'};
    my $ldap_filter2 = $source->{'filter2'};
    my $ldap_attrs2 = $source->{'attrs2'};
    my $ldap_select2 = $source->{'select2'};
    my $ldap_scope2 = $source->{'scope2'};
    my $ldap_regex2 = $source->{'regex2'};
    my @sync_errors = ();
    
    my ($email_attr, $gecos_attr) = split(/\s*,\s*/, $ldap_attrs2);
    my @ldap_attrs2 = ($email_attr);
    push @ldap_attrs2, $gecos_attr if($gecos_attr);
    
   ## LDAP and query handler
    my ($ldaph, $fetch);

    unless (defined $source && ($ldaph = $source->connect())) {
	&Log::do_log('err',"Unable to connect to the LDAP server '%s'", $source->{'host'});
	    return undef;
	}
    
    &Log::do_log('debug2', 'Searching on server %s ; suffix %s ; filter %s ; attrs: %s', $source->{'host'}, $ldap_suffix1, $ldap_filter1, $ldap_attrs1) ;
    $fetch = $ldaph->search ( base => "$ldap_suffix1",
			      filter => "$ldap_filter1",
			      attrs => [ "$ldap_attrs1" ],
			      scope => "$ldap_scope1");
    if ($fetch->code()) {
	&Log::do_log('err','LDAP search (1st level) failed : %s (searching on server %s ; suffix %s ; filter %s ; attrs: %s)', 
	       $fetch->error(), $source->{'host'}, $ldap_suffix1, $ldap_filter1, $ldap_attrs1);
        return undef;
    }
    
    ## Counters.
    my $total = 0;
    my $dn; 
   
    ## returns a reference to a HASH where the keys are the DNs
    ##  the second level hash's hold the attributes

    my (@attrs, @emails);
 
    while (my $e = $fetch->shift_entry) {
	my $entry = $e->get_value($ldap_attrs1, asref => 1);
	## Multiple values
	if (ref($entry) eq 'ARRAY') {
	    foreach my $attr (@{$entry}) {
		next if (($ldap_select1 eq 'regex') && ($attr !~ /$ldap_regex1/));
		push @attrs, $attr;
		last if ($ldap_select1 eq 'first');
	    }
	}else {
	    push @attrs, $entry
		unless (($ldap_select1 eq 'regex') && ($entry !~ /$ldap_regex1/));
	}
    }

    my %emailsViewed;

    my ($suffix2, $filter2);
    foreach my $attr (@attrs) {
	($suffix2 = $ldap_suffix2) =~ s/\[attrs1\]/$attr/g;
	($filter2 = $ldap_filter2) =~ s/\[attrs1\]/$attr/g;

	&Log::do_log('debug2', 'Searching on server %s ; suffix %s ; filter %s ; attrs: %s', $source->{'host'}, $suffix2, $filter2, $ldap_attrs2);
	$fetch = $ldaph->search ( base => "$suffix2",
				  filter => "$filter2",
				  attrs => @ldap_attrs2,
				  scope => "$ldap_scope2");
	if ($fetch->code()) {
	    &Log::do_log('err','LDAP search (2nd level) failed : %s. Node: %s (searching on server %s ; suffix %s ; filter %s ; attrs: %s)', 
		   $fetch->error(), $attr, $source->{'host'}, $suffix2, $filter2, $ldap_attrs2);
	    push @sync_errors, {'error',$fetch->error(), 'host', $source->{'host'}, 'suffix2', $suffix2, 'fliter2', $filter2,'ldap_attrs2', $ldap_attrs2};
	}

	## returns a reference to a HASH where the keys are the DNs
	##  the second level hash's hold the attributes
	
	while (my $e = $fetch->shift_entry) {
		my $emailentry = $e->get_value($email_attr, asref => 1);
		my $gecosentry = $e->get_value($gecos_attr, asref => 1);
		$gecosentry = $gecosentry->[0] if(ref($gecosentry) eq 'ARRAY');

	    ## Multiple values
	    if (ref($emailentry) eq 'ARRAY') {
		foreach my $email (@{$emailentry}) {
		    my $cleanmail = &tools::clean_email($email);
		    ## Skip badly formed emails
		    unless (&tools::valid_email($email)) {
			Log::do_log('err', "Skip badly formed email address: '%s'", $email);
			next;
		    }

		    next if (($ldap_select2 eq 'regex') && ($cleanmail !~ /$ldap_regex2/));
		    next if ($emailsViewed{$cleanmail});
		    push @emails, [$cleanmail, $gecosentry];
		    $emailsViewed{$cleanmail} = 1;
		    last if ($ldap_select2 eq 'first');
		}
	    }else {
		my $cleanmail = &tools::clean_email($emailentry);
		## Skip badly formed emails
		unless (&tools::valid_email($emailentry)) {
			Log::do_log('err', "Skip badly formed email address: '%s'", $emailentry);
			next;
		}

		unless( (($ldap_select2 eq 'regex') && ($cleanmail !~ /$ldap_regex2/))||$emailsViewed{$cleanmail}) {
		    push @emails, [$cleanmail, $gecosentry];
		    $emailsViewed{$cleanmail} = 1;
		}
	    }
	}
    }
    
    unless ($source->disconnect()) {
	&Log::do_log('err','Can\'t unbind from  LDAP server %s', $source->{'host'});
	return undef;
    }
    
    foreach my $emailgecos (@emails) {
	my ($email, $gecos) = @$emailgecos;
	next if ($email =~ /^\s*$/);

	$email = &tools::clean_email($email);
	my %u;
	## Check if user has already been included
	if ($users->{$email}) {
	    if ($tied) {
		%u = split "\n",$users->{$email};
	    }else {
		%u = %{$users->{$email}};
	    }
	}else {
	    %u = %{$default_user_options};
	    $total++;
	}

	$u{'email'} = $email;
	$u{'gecos'} = $gecos if($gecos);
	$u{'date'} = time;
	$u{'update_date'} = time;
	$u{'id'} = join (',', split(',', $u{'id'}), $id);

	$u{'visibility'} = $default_user_options->{'visibility'} if (defined $default_user_options->{'visibility'});
	$u{'reception'} = $default_user_options->{'reception'} if (defined $default_user_options->{'reception'});
	$u{'profile'} = $default_user_options->{'profile'} if (defined $default_user_options->{'profile'});
	$u{'info'} = $default_user_options->{'info'} if (defined $default_user_options->{'info'});

	if ($tied) {
	    $users->{$email} = join("\n", %u);
	}else {
	    $users->{$email} = \%u;
	}
    }

    &Log::do_log('debug2',"unbinded from LDAP server %s ", $source->{'host'}) ;
    &Log::do_log('info','%d new users included from LDAP query 2level',$total);

    my $result;
    $result->{'total'} = $total;
    if ($#sync_errors > -1) {$result->{'errors'} = \@sync_errors;}
    return $result;
}

sub _include_sql_ca {
	my $source = shift;
	
	return {} unless($source->connect());
	
	&Log::do_log('debug', '%s, email_entry = %s', $source->{'sql_query'}, $source->{'email_entry'});
    
	my $sth = $source->do_query($source->{'sql_query'});
	my $mailkey = $source->{'email_entry'};
	my $ca = $sth->fetchall_hashref($mailkey);
	my $result;
	foreach my $email (keys %{$ca}) {
		foreach my $custom_attribute (keys %{$ca->{$email}}) {
			$result->{$email}{$custom_attribute}{'value'} = $ca->{$email}{$custom_attribute} unless($custom_attribute eq $mailkey);
		}
	}
	return $result;
}

sub _include_ldap_ca {
	my $source = shift;
	
	return {} unless($source->connect());
	
	&Log::do_log('debug', 'server %s ; suffix %s ; filter %s ; attrs: %s', $source->{'host'}, $source->{'suffix'}, $source->{'filter'}, $source->{'attrs'});
	
	my @attrs = split(/\s*,\s*/, $source->{'attrs'});
	
	my $results = $source->{'ldap_handler'}->search(
		base => $source->{'suffix'},
		filter => $source->{'filter'},
		attrs => @attrs,
		scope => $source->{'scope'}
	);
	if($results->code()) {
		&Log::do_log('err', 'Ldap search (single level) failed : %s (searching on server %s ; suffix %s ; filter %s ; attrs: %s)', $results->error(), $source->{'host'}, $source->{'suffix'}, $source->{'filter'}, $source->{'attrs'});
		return {};
	}
    
	my $attributes;
	while(my $entry = $results->shift_entry) {
		my $email = $entry->get_value($source->{'email_entry'});
		next unless($email);
		foreach my $attr (@attrs) {
			next if($attr eq $source->{'email_entry'});
			$attributes->{$email}{$attr}{'value'} = $entry->get_value($attr);
		}
	}
    
	return $attributes;
}

sub _include_ldap_level2_ca {
	my $source = shift;
	
	return {} unless($source->connect());
	
	return {};
	
	&Log::do_log('debug', 'server %s ; suffix %s ; filter %s ; attrs: %s', $source->{'host'}, $source->{'suffix'}, $source->{'filter'}, $source->{'attrs'});
	
	my @attrs = split(/\s*,\s*/, $source->{'attrs'});
	
	my $results = $source->{'ldap_handler'}->search(
		base => $source->{'suffix'},
		filter => $source->{'filter'},
		attrs => @attrs,
		scope => $source->{'scope'}
	);
	if($results->code()) {
		&Log::do_log('err', 'Ldap search (single level) failed : %s (searching on server %s ; suffix %s ; filter %s ; attrs: %s)', $results->error(), $source->{'host'}, $source->{'suffix'}, $source->{'filter'}, $source->{'attrs'});
		return {};
	}
    
	my $attributes;
	while(my $entry = $results->shift_entry) {
		my $email = $entry->get_value($source->{'email_entry'});
		next unless($email);
		foreach my $attr (@attrs) {
			next if($attr eq $source->{'email_entry'});
			$attributes->{$email}{$attr}{'value'} = $entry->get_value($attr);
		}
	}
    
	return $attributes;
}


## Returns a list of subscribers extracted from an remote Database
sub _include_users_sql {
    my ($users, $id, $source, $default_user_options, $tied, $fetch_timeout) = @_;

    &Log::do_log('debug','List::_include_users_sql()');
    
    unless (ref($source) =~ /DBManipulator/) {
	&Log::do_log('err','source object has not a DBManipulator type : %s',$source);
        return undef;
    }

    unless ($source->connect() && ($source->do_query($source->{'sql_query'}))) {
	&Log::do_log('err','Unable to connect to SQL datasource with parameters host: %s, database: %s',$source->{'host'},$source->{'db_name'});
        return undef;
    }
    ## Counters.
    my $total = 0;
    
    ## Process the SQL results
    $source->set_fetch_timeout($fetch_timeout);
    my $array_of_users = $source->fetch;
	
    unless (defined $array_of_users && ref($array_of_users) eq 'ARRAY') {
	&Log::do_log('err', 'Failed to include users from %s',$source->{'name'});
	return undef;
    }

    foreach my $row (@{$array_of_users}) {
	my $email = $row->[0]; ## only get first field
	my $gecos = $row->[1]; ## second field (if it exists) is gecos
	## Empty value
	next if ($email =~ /^\s*$/);

	$email = &tools::clean_email($email);

	## Skip badly formed emails
	unless (&tools::valid_email($email)) {
		Log::do_log('err', "Skip badly formed email address: '%s'", $email);
		next;
	}

	my %u;
	## Check if user has already been included
	if ($users->{$email}) {
	    if ($tied eq 'tied') {
		%u = split "\n",$users->{$email};
	    }else {
		%u = %{$users->{$email}};
	    }
	}else {
	    %u = %{$default_user_options};
	    $total++;
	}

	$u{'email'} = $email;
	$u{'gecos'} = $gecos if($gecos);
	$u{'date'} = time;
	$u{'update_date'} = time;
	$u{'id'} = join (',', split(',', $u{'id'}), $id);

	$u{'visibility'} = $default_user_options->{'visibility'} if (defined $default_user_options->{'visibility'});
	$u{'reception'} = $default_user_options->{'reception'} if (defined $default_user_options->{'reception'});
	$u{'profile'} = $default_user_options->{'profile'} if (defined $default_user_options->{'profile'});
	$u{'info'} = $default_user_options->{'info'} if (defined $default_user_options->{'info'});

	if ($tied eq 'tied') {
	    $users->{$email} = join("\n", %u);
	}else {
	    $users->{$email} = \%u;
	}
    }
    $source->disconnect();
    &Log::do_log('info','%d included users from SQL query', $total);
    return $total;
}

## Loads the list of subscribers from an external include source
sub _load_list_members_from_include {
    &Log::do_log('debug2', '(%s, %s)', @_);

    my $self = shift;
    my $old_subs = shift;
    my $name = $self->name; 
    my $dir = $self->dir;
    my (%users, $depend_on, $ref);
    my $total = 0;
    my @errors;
    my $result;
    my @ex_sources;
    
    
    foreach my $type ('include_list','include_remote_sympa_list','include_file','include_ldap_query','include_ldap_2level_query','include_sql_query','include_remote_file', 'include_voot_group') {
	last unless (defined $total);
	    
	foreach my $tmp_incl (@{$self->admin->{$type}}) {
	    my $included;
	    my $source_is_new = 1;
        ## Work with a copy of admin hash branch to avoid including temporary variables into the actual admin hash.[bug #3182]
	    my $incl = &tools::dup_var($tmp_incl);
		my $source_id = Datasource::_get_datasource_id($tmp_incl);
		if (defined $old_subs->{$source_id}) {
			$source_is_new = 0;
		}
	    ## Get the list of users.
	    ## Verify if we can syncronize sources. If it's allowed OR there are new sources, we update the list, and can add subscribers.
		## Else if we can't syncronize sources. We make an array with excluded sources.
	    if ($type eq 'include_sql_query') {
			my $source = new SQLSource($incl);
			if ($source->is_allowed_to_sync() || $source_is_new) {
				&Log::do_log('debug', 'is_new %d, syncing', $source_is_new);
				$included = _include_users_sql(\%users, $source_id, $source, $self->default_user_options, 'untied', $self->sql_fetch_timeout);
				unless (defined $included){
					push @errors, {'type' => $type, 'name' => $incl->{'name'}};
				}
			}else{
				my $exclusion_data = {	'id' => $source_id,
										'name' => $incl->{'name'},
										'starthour' => $source->{'starthour'},
										'startminute' => $source->{'startminute'} ,
										'endhour' => $source->{'endhour'},
										'endminute' => $source->{'endminute'}};
				push @ex_sources, $exclusion_data;
				$included = 0;
			}
	    }elsif ($type eq 'include_ldap_query') {
			my $source = new LDAPSource($incl);
			if ($source->is_allowed_to_sync() || $source_is_new) {
				$included = _include_users_ldap(\%users, $source_id, $source, $self->default_user_options);
				unless (defined $included){
					push @errors, {'type' => $type, 'name' => $incl->{'name'}};
				}
			}else{
				my $exclusion_data = {	'id' => $source_id,
										'name' => $incl->{'name'},
										'starthour' => $source->{'starthour'},
										'startminute' => $source->{'startminute'} ,
										'endhour' => $source->{'endhour'},
										'endminute' => $source->{'endminute'}};
				push @ex_sources, $exclusion_data;
				$included = 0;
			}
		}elsif ($type eq 'include_ldap_2level_query') {
			my $source = new LDAPSource($incl);
			if ($source->is_allowed_to_sync() || $source_is_new) {
				my $result = _include_users_ldap_2level(\%users,$source_id, $source, $self->default_user_options);
				if (defined $result) {
					$included = $result->{'total'};
					if (defined $result->{'errors'}){
						&Log::do_log('err', 'Errors occurred during the second LDAP passe');
						push @errors, {'type' => $type, 'name' => $incl->{'name'}};
					}
				}else{
					$included = undef;
					push @errors, {'type' => $type, 'name' => $incl->{'name'}};
				}
			}else{	
				my $exclusion_data = {	'id' => $source_id,
										'name' => $incl->{'name'},
										'starthour' => $source->{'starthour'},
										'startminute' => $source->{'startminute'} ,
										'endhour' => $source->{'endhour'},
										'endminute' => $source->{'endminute'}};
				push @ex_sources, $exclusion_data;
				$included = 0;
			}
	    }elsif ($type eq 'include_remote_sympa_list') {
		$included = $self->_include_users_remote_sympa_list(\%users, $incl, $dir, $self->domain, $self->default_user_options);
		unless (defined $included){
		    push @errors, {'type' => $type, 'name' => $incl->{'name'}};
		}
	    }elsif ($type eq 'include_list') {
		$depend_on->{$name} = 1 ;
		if (&_inclusion_loop ($name,$incl,$depend_on)) {
		    &Log::do_log('err','loop detection in list inclusion : could not include again %s in %s',$incl,$name);
		}else{
		    $depend_on->{$incl} = 1;
		    $included = _include_users_list (\%users, $incl, $self->domain, $self->default_user_options);
		    unless (defined $included){
			push @errors, {'type' => $type, 'name' => $incl};
		    }
		}
	    }elsif ($type eq 'include_file') {
		$included = _include_users_file (\%users, $incl, $self->default_user_options);
		unless (defined $included){
		    push @errors, {'type' => $type, 'name' => $incl};
		}
	    }elsif ($type eq 'include_remote_file') {
		$included = _include_users_remote_file (\%users, $incl, $self->default_user_options);
		unless (defined $included){
		    push @errors, {'type' => $type, 'name' => $incl->{'name'}};
		}
	    }elsif ($type eq 'include_voot_group') {
		$included = _include_users_voot_group(\%users, $incl, $self->default_user_options);
		unless (defined $included){
		    push @errors, {'type' => $type, 'name' => $incl->{'name'}};
		}
	    }

	    unless (defined $included) {
		&Log::do_log('err', 'Inclusion %s failed in list %s', $type, $name);
		next;
	    }
	    $total += $included;
	}
    }

    ## If an error occured, return an undef value
    $result->{'users'} = \%users;
    $result->{'errors'} = \@errors;
    $result->{'exclusions'} = \@ex_sources;
    return $result;
}

## Loads the list of admin users from an external include source
sub _load_list_admin_from_include {
    &Log::do_log('debug2', '(%s, %s)', @_);

    my $self = shift;
    my $role = shift;
    my $name = $self->name;

    my (%admin_users, $depend_on, $ref);
    my $total = 0;
    my $list_admin = $self->admin;
    my $dir = $self->dir;

    foreach my $entry (@{$self->admin->{$role . '_include'}}) {
    
	next unless (defined $entry); 

	my %option;
	$option{'reception'} = $entry->{'reception'} if (defined $entry->{'reception'});
	$option{'visibility'} = $entry->{'visibility'} if (defined $entry->{'visibility'});
	$option{'profile'} = $entry->{'profile'} if (defined $entry->{'profile'} && ($role eq 'owner'));
	

      	my $include_file = &tools::get_filename('etc', {}, "data_sources/$entry->{'source'}\.incl", $self->domain, $self);

        unless (defined $include_file){
	    &Log::do_log('err', 'the file %s.incl doesn\'t exist',$entry->{'source'});
	    return undef;
	}

	my $include_admin_user;
	## the file has parameters
	if (defined $entry->{'source_parameters'}) {
	    my %parsing;
	    
	    $parsing{'data'} = $entry->{'source_parameters'};
	    $parsing{'template'} = "$entry->{'source'}\.incl";
	    
	    my $name = "$entry->{'source'}\.incl";
	    
	    my $include_path = $include_file;
	    if ($include_path =~ s/$name$//) {
		$parsing{'include_path'} = $include_path;
		$include_admin_user = &_load_include_admin_user_file($self->domain, $include_path, \%parsing);	
	    } else {
		&Log::do_log('err', 'errors to get path of the the file %s.incl',$entry->{'source'});
		return undef;
	    }
	    
	    
	} else {
	    $include_admin_user = &_load_include_admin_user_file($self->domain, $include_file);
	}
	foreach my $type ('include_list','include_remote_sympa_list','include_file','include_ldap_query','include_ldap_2level_query','include_sql_query','include_remote_file', 'include_voot_group') {
	    last unless (defined $total);
	    
	    foreach my $tmp_incl (@{$include_admin_user->{$type}}) {
		my $included;
		
		## Work with a copy of admin hash branch to avoid including temporary variables into the actual admin hash.[bug #3182]
		my $incl = &tools::dup_var($tmp_incl);

		## get the list of admin users
		## does it need to define a 'default_admin_user_option'?
		if ($type eq 'include_sql_query') {
		    my $source = new SQLSource($incl);
		    $included = _include_users_sql(\%admin_users, $incl,$source,\%option, 'untied', $self->sql_fetch_timeout); 
		}elsif ($type eq 'include_ldap_query') {
		    my $source = new LDAPSource($incl);
		    $included = _include_users_ldap(\%admin_users, $incl,$source,\%option); 
		}elsif ($type eq 'include_ldap_2level_query') {
		    my $source = new LDAPSource($incl);
		    my $result = _include_users_ldap_2level(\%admin_users, $incl,$source,\%option); 
		    if (defined $result) {
			$included = $result->{'total'};
			if (defined $result->{'errors'}){
			    &Log::do_log('err', 'Errors occurred during the second LDAP passe. Please verify your LDAP query.');
			}
		    }else{
			$included = undef;
		    }
		}elsif ($type eq 'include_remote_sympa_list') {
		    $included = $self->_include_users_remote_sympa_list(\%admin_users, $incl, $dir, $self->domain, \%option);
		}elsif ($type eq 'include_list') {
		    $depend_on->{$name} = 1 ;
		    if (&_inclusion_loop ($name,$incl,$depend_on)) {
			&Log::do_log('err','loop detection in list inclusion : could not include again %s in %s',$incl,$name);
		    }else{
			$depend_on->{$incl} = 1;
			$included = _include_users_list (\%admin_users, $incl, $self->domain, \%option);
		    }
		}elsif ($type eq 'include_file') {
		    $included = _include_users_file (\%admin_users, $incl, \%option);
		}elsif ($type eq 'include_remote_file') {
		    $included = _include_users_remote_file (\%admin_users, $incl, \%option);
		}elsif ($type eq 'include_voot_group') {
			$included = _include_users_voot_group(\%admin_users, $incl, \%option);
	    }

		unless (defined $included) {
		    &Log::do_log('err', 'Inclusion %s %s failed in list %s', $role, $type, $name);
		    next;
		}
		$total += $included;
	    }
	}

	## If an error occured, return an undef value
	unless (defined $total) {
	    return undef;
	}
    }
   
    return \%admin_users;
}


# Load an include admin user file (xx.incl)
sub _load_include_admin_user_file {
    &Log::do_log('debug2', '(%s, %s, %s)', @_);

    my ($robot, $file, $parsing) = @_;

    my %include;
    my (@paragraphs);
    
    # the file has parmeters
    if (defined $parsing) {
	my @data = split(',',$parsing->{'data'});
        my $vars = {'param' => \@data};
	my $output = '';
	
	unless (&tt2::parse_tt2($vars,$parsing->{'template'},\$output,[$parsing->{'include_path'}])) {
	    &Log::do_log('err', 'Failed to parse %s', $parsing->{'template'});
	    return undef;
	}
	
	my @lines = split('\n',$output);
	
	my $i = 0;
	foreach my $line (@lines) {
	    if ($line =~ /^\s*$/) {
		$i++ if $paragraphs[$i];
	    }else {
		push @{$paragraphs[$i]}, $line;
	    }
	}
    } else {
	unless (open INCLUDE, $file) {
	    &Log::do_log('info', 'Cannot open %s', $file);
	}
	
	## Just in case...
	local $/ = "\n";
	
	## Split in paragraphs
	my $i = 0;
	while (<INCLUDE>) {
	    if (/^\s*$/) {
		$i++ if $paragraphs[$i];
	    }else {
		push @{$paragraphs[$i]}, $_;
	    }
	}
	close INCLUDE;
    }
    
    for my $index (0..$#paragraphs) {
	my @paragraph = @{$paragraphs[$index]};
	
	my $pname;
	
	## Clean paragraph, keep comments
	for my $i (0..$#paragraph) {
	    my $changed = undef;
	    for my $j (0..$#paragraph) {
		if ($paragraph[$j] =~ /^\s*\#/) {
		    chomp($paragraph[$j]);
		    push @{$include{'comment'}}, $paragraph[$j];
		    splice @paragraph, $j, 1;
		    $changed = 1;
		}elsif ($paragraph[$j] =~ /^\s*$/) {
		    splice @paragraph, $j, 1;
		    $changed = 1;
		}
		
		last if $changed;
	    }
	    
	    last unless $changed;
	}
	
	## Empty paragraph
	next unless ($#paragraph > -1);
	
	## Look for first valid line
	unless ($paragraph[0] =~ /^\s*([\w-]+)(\s+.*)?$/) {
	    &Log::do_log('info', 'Bad paragraph "%s" in %s', @paragraph, $file);
	    next;
	}
	
	$pname = $1;   
	
	unless(($pname eq 'include_list')||($pname eq 'include_remote_sympa_list')||($pname eq 'include_file')||($pname eq 'include_remote_file')||
	       ($pname eq 'include_ldap_query')||($pname eq 'include_ldap_2level_query')||($pname eq 'include_sql_query'))   {
	    &Log::do_log('info', 'Unknown parameter "%s" in %s', $pname, $file);
	    next;
	}
	
	## Uniqueness
	if (defined $include{$pname}) {
	    unless (($::pinfo{$pname}{'occurrence'} eq '0-n') or
		    ($::pinfo{$pname}{'occurrence'} eq '1-n')) {
		&Log::do_log('info', 'Multiple parameter "%s" in %s', $pname, $file);
	    }
	}
	
	## Line or Paragraph
	if (ref $::pinfo{$pname}{'file_format'} eq 'HASH') {
	    ## This should be a paragraph
	    unless ($#paragraph > 0) {
		&Log::do_log('info', 'Expecting a paragraph for "%s" parameter in %s, ignore it', $pname, $file);
		next;
	    }
	    
	    ## Skipping first line
	    shift @paragraph;
	    
	    my %hash;
	    for my $i (0..$#paragraph) {	    
		next if ($paragraph[$i] =~ /^\s*\#/);
		
		unless ($paragraph[$i] =~ /^\s*(\w+)\s*/) {
		    &Log::do_log('info', 'Bad line "%s" in %s',$paragraph[$i], $file);
		}
		
		my $key = $1;
		
		unless (defined $::pinfo{$pname}{'file_format'}{$key}) {
		    &Log::do_log('info', 'Unknown key "%s" in paragraph "%s" in %s', $key, $pname, $file);
		    next;
		}
		
		unless ($paragraph[$i] =~ /^\s*$key\s+($::pinfo{$pname}{'file_format'}{$key}{'file_format'})\s*$/i) {
		    chomp($paragraph[$i]);
		    &Log::do_log('info', 'Bad entry "%s" for key "%s", paragraph "%s" in %s', $paragraph[$i], $key, $pname, $file);
		    next;
		}
	       
		$hash{$key} = &_load_list_param($robot,$key, $1, $::pinfo{$pname}{'file_format'}{$key});
	    }

	    ## Apply defaults & Check required keys
	    my $missing_required_field;
	    foreach my $k (keys %{$::pinfo{$pname}{'file_format'}}) {

		## Default value
		unless (defined $hash{$k}) {
		    if (defined $::pinfo{$pname}{'file_format'}{$k}{'default'}) {
			$hash{$k} = &_load_list_param($robot,$k, 'default', $::pinfo{$pname}{'file_format'}{$k});
		    }
		}
		## Required fields
		if ($::pinfo{$pname}{'file_format'}{$k}{'occurrence'} eq '1') {
		    unless (defined $hash{$k}) {
			&Log::do_log('info', 'Missing key "%s" in param "%s" in %s', $k, $pname, $file);
			$missing_required_field++;
		    }
		}
	    }

	    next if $missing_required_field;

	    ## Should we store it in an array
	    if (($::pinfo{$pname}{'occurrence'} =~ /n$/)) {
		push @{$include{$pname}}, \%hash;
	    }else {
		$include{$pname} = \%hash;
	    }
	}else {
	    ## This should be a single line
	    unless ($#paragraph == 0) {
		&Log::do_log('info', 'Expecting a single line for "%s" parameter in %s', $pname, $file);
	    }

	    unless ($paragraph[0] =~ /^\s*$pname\s+($::pinfo{$pname}{'file_format'})\s*$/i) {
		chomp($paragraph[0]);
		&Log::do_log('info', 'Bad entry "%s" in %s', $paragraph[0], $file);
		next;
	    }

	    my $value = &_load_list_param($robot,$pname, $1, $::pinfo{$pname});

	    if (($::pinfo{$pname}{'occurrence'} =~ /n$/)
		&& ! (ref ($value) =~ /^ARRAY/)) {
		push @{$include{$pname}}, $value;
	    }else {
		$include{$pname} = $value;
	    }
	}
    }
    
    return \%include;
}

## Returns a ref to an array containing the ids (as computed by Datasource::_get_datasource_id) of the list of memebers given as argument.
sub get_list_of_sources_id {
	my $self = shift;
	my $list_of_subscribers = shift;
	
	my %old_subs_id;
	foreach my $old_sub (keys %{$list_of_subscribers}) {
		my @tmp_old_tab = split(/,/,$list_of_subscribers->{$old_sub}{'id'});
		foreach my $raw (@tmp_old_tab) {
			$old_subs_id{$raw} = 1;
		}
	}
	my $ids = join(',',keys %old_subs_id);
	return \%old_subs_id;
}


sub sync_include_ca {
	my $self = shift;
	#my $admin = $self->admin;
	my $purge = shift;
	my %users;
	my %changed;
	
	$self->purge_ca() if($purge);
	
	&Log::do_log('debug', 'syncing CA');
	
	for (my $user=$self->get_first_list_member(); $user; $user=$self->get_next_list_member()) {
		$users{$user->{'email'}} = $user->{'custom_attribute'};
	}
	
	foreach my $type ('include_sql_ca') {
		foreach my $tmp_incl (@{$self->admin->{$type}}) {
			## Work with a copy of admin hash branch to avoid including temporary variables into the actual admin hash.[bug #3182]
			my $incl = &tools::dup_var($tmp_incl);
			my $source = undef;
			my $srcca = undef;
			if ($type eq 'include_sql_ca') {
				$source = new SQLSource($incl);
			}elsif(($type eq 'include_ldap_ca') or ($type eq 'include_ldap_2level_ca')) {
				$source = new LDAPSource($incl);
			}
			next unless(defined($source));
			if($source->is_allowed_to_sync()) {
				my $getter = '_'.$type;
				{ # Magic inside
					no strict "refs";
					$srcca = &$getter($source);
				}
				if(defined($srcca)) {
					foreach my $email (keys %$srcca) {
						$users{$email} = {} unless(defined $users{$email});
						foreach my $key (keys %{$srcca->{$email}}) {
							next if($users{$email}{$key}{'value'} eq $srcca->{$email}{$key}{'value'});
							$users{$email}{$key} = $srcca->{$email}{$key};
							$changed{$email} = 1;
						}
					}
				}
			}
			unless($source->disconnect()) {
				&Log::do_log('notice','Can\'t unbind from source %s', $type);
				return undef;
			}
		}
	}
	
	foreach my $email (keys %changed) {
		if($self->update_list_member($email, {'custom_attribute' => &createXMLCustomAttribute($users{$email})})) {
			&Log::do_log('debug', 'Updated user %s', $email);
		}else{
			&Log::do_log('error', 'could not update user %s', $email);
		}
	}
	
	return 1;
}

### Purge synced custom attributes from user records, only keep user writable ones
sub purge_ca {
	my $self = shift;
	#my $admin = $self->admin;
	my %userattributes;
	my %users;
	
	&Log::do_log('debug', 'purge CA');
	
	foreach my $attr (@{$self->custom_attribute}) {
		$userattributes{$attr->{'id'}} = 1;
	}
	
	for (my $user=$self->get_first_list_member(); $user; $user=$self->get_next_list_member()) {
		next unless(keys %{$user->{'custom_attribute'}});
		my $attributes;
		foreach my $id (keys %{$user->{'custom_attribute'}}) {
			next unless(defined $userattributes{$id});
			$attributes->{$id} = $user->{'custom_attribute'}{$id};
		}
		$users{$user->{'email'}} = $attributes;
	}
	
	foreach my $email (keys %users) {
		if($self->update_list_member($email, {'custom_attribute' => &createXMLCustomAttribute($users{$email})})) {
			&Log::do_log('debug', 'Updated user %s', $email);
		}else{
			&Log::do_log('error', 'could not update user %s', $email);
		}
	}
	
	return 1;
}

sub sync_include {
    my ($self) = shift;
    my $option = shift;
    my $name=$self->{'name'};
    &Log::do_log('debug', 'List:sync_include(%s)', $name);
    my %old_subscribers;
    my $total=0;
    my $errors_occurred=0;

    ## Load a hash with the old subscribers
    for (my $user=$self->get_first_list_member(); $user; $user=$self->get_next_list_member()) {
	$old_subscribers{lc($user->{'email'})} = $user;
	
	## User neither included nor subscribed = > set subscribed to 1 
	unless ($old_subscribers{lc($user->{'email'})}{'included'} || $old_subscribers{lc($user->{'email'})}{'subscribed'}) {
	    &Log::do_log('notice','Update user %s neither included nor subscribed', $user->{'email'});
	    unless( $self->update_list_member(lc($user->{'email'}),  {'update_date' => time,
							       'subscribed' => 1 }) ) {
			&Log::do_log('err', 'List:sync_include(%s): Failed to update %s', $name, lc($user->{'email'}));
			next;
	    }			    
	    $old_subscribers{lc($user->{'email'})}{'subscribed'} = 1;
	}

	$total++;
    }
    
    ## Load a hash with the new subscriber list
    my $new_subscribers;
    unless ($option eq 'purge') {
		my $result = $self->_load_list_members_from_include($self->get_list_of_sources_id(\%old_subscribers));
		$new_subscribers = $result->{'users'};
		my @errors = @{$result->{'errors'}};
		my @exclusions = @{$result->{'exclusions'}};
		
		## If include sources were not available, do not update subscribers
		## Use DB cache instead and warn the listmaster.
		if($#errors > -1) {
			&Log::do_log('err', 'Errors occurred while synchronizing datasources for list %s', $name);
			$errors_occurred = 1;
			unless (&List::send_notify_to_listmaster('sync_include_failed', $self->{'domain'}, {'errors' => \@errors, 'listname' => $self->{'name'}})) {
			&Log::do_log('notice',"Unable to send notify 'sync_include_failed' to listmaster");
			}
			foreach my $e (@errors) {
				next unless($e->{'type'} eq 'include_voot_group');
				my $cfg = undef;
				foreach my $p (@{$self->{'admin'}{'include_voot_group'}}) {
					$cfg = $p if($p->{'name'} eq $e->{'name'});
				}
				next unless(defined $cfg);
				&report::reject_report_web(
					'user',
					'sync_include_voot_failed',
					{
						'oauth_provider' => 'voot:'.$cfg->{'provider'}
					},
					'sync_include',
					$self->{'domain'},
					$cfg->{'user'},
					$self->{'name'}
				);
				&report::reject_report_msg(
					'oauth',
					'sync_include_voot_failed',
					$cfg->{'user'},
					{
						'consumer_name' => 'VOOT',
						'oauth_provider' => 'voot:'.$cfg->{'provider'}
					},
					$self->{'domain'},
					'',
					$self->{'name'}
				);
			}
			return undef;
		}
		
		# Feed the new_subscribers hash with users previously subscribed
		# with data sources not used because we were not in the period of
		# time during which synchronization is allowed. This will prevent
		# these users from being unsubscribed.
		if($#exclusions > -1) {
			foreach my $ex_sources (@exclusions) {
				my $id = $ex_sources->{'id'};
				foreach my $email (keys %old_subscribers) {
					if($old_subscribers{$email}{'id'} =~ /$id/g) {
						$new_subscribers->{$email}{'date'} = $old_subscribers{$email}{'date'};
						$new_subscribers->{$email}{'update_date'} = $old_subscribers{$email}{'update_date'};
						$new_subscribers->{$email}{'visibility'} = $self->{'default_user_options'}{'visibility'} if (defined $self->{'default_user_options'}{'visibility'});
						$new_subscribers->{$email}{'reception'} = $self->{'default_user_options'}{'reception'} if (defined $self->{'default_user_options'}{'reception'});
						$new_subscribers->{$email}{'profile'} = $self->{'default_user_options'}{'profile'} if (defined $self->{'default_user_options'}{'profile'});
						$new_subscribers->{$email}{'info'} = $self->{'default_user_options'}{'info'} if (defined $self->{'default_user_options'}{'info'});
						if(defined $new_subscribers->{$email}{'id'} && $new_subscribers->{$email}{'id'} ne '') {
							$new_subscribers->{$email}{'id'} = join (',', split(',', $new_subscribers->{$email}{'id'}), $id);
						}else{
							$new_subscribers->{$email}{'id'} = $old_subscribers{$email}{'id'};
						}
					}
				}
			}
		}
	}

	my $data_exclu;
	my @subscriber_exclusion;

	## Gathering a list of emails for a the list in 'exclusion_table'
	$data_exclu = $self->get_exclusion();

	my $key =0;
	while ($data_exclu->{'emails'}->[$key]){
		push @subscriber_exclusion, $data_exclu->{'emails'}->[$key];
		$key = $key + 1;
	}

    my $users_added = 0;
    my $users_updated = 0;

    ## Get an Exclusive lock
    my $lock = new Lock ($self->{'dir'}.'/include');
    unless (defined $lock) {
	&Log::do_log('err','Could not create new lock');
	return undef;
    }
    $lock->set_timeout(10*60); 
    unless ($lock->lock('write')) {
	return undef;
    }

    ## Go through previous list of users
    my $users_removed = 0;
    my $user_removed;
    my @deltab;
    foreach my $email (keys %old_subscribers) {
		unless( defined($new_subscribers->{$email}) ) {
			## User is also subscribed, update DB entry
			if ($old_subscribers{$email}{'subscribed'}) {
				&Log::do_log('debug', 'List:sync_include: updating %s to list %s', $email, $name);
				unless( $self->update_list_member($email,  {'update_date' => time,
								'included' => 0,
								'id' => ''}) ) {
					&Log::do_log('err', 'List:sync_include(%s): Failed to update %s',  $name, $email);
					next;
				}
			
				$users_updated++;
	
				## Tag user for deletion
			}else {
				&Log::do_log('debug3', 'List:sync_include: removing %s from list %s', $email, $name);
				@deltab = ($email);
				unless($user_removed = $self->delete_list_member('users' => \@deltab)) {
					&Log::do_log('err', 'List:sync_include(%s): Failed to delete %s', $name, $user_removed);
					return undef;
				}
				if ($user_removed) {
					$users_removed++;
					## Send notification if the list config authorizes it only.
					if ($self->{'admin'}{'inclusion_notification_feature'} eq 'on') {
						unless ($self->send_file('removed', $email, $self->{'domain'},{})) {
							&Log::do_log('err',"Unable to send template 'removed' to $email");
						}
					}
				}
			}
		}
    }
    if ($users_removed > 0) {
		&Log::do_log('notice', 'List:sync_include(%s): %d users removed', $name, $users_removed);
    }

    ## Go through new users
    my @add_tab;
    $users_added = 0;
    foreach my $email (keys %{$new_subscribers}) {
	my $compare = 0;
	foreach my $sub_exclu (@subscriber_exclusion){
	    if ($email eq $sub_exclu){
		$compare = 1;
		last;
	    }
	}
	if($compare == 1){
	    delete $new_subscribers->{$email};
	    next;
	}
		if (defined($old_subscribers{$email}) ) {
			if ($old_subscribers{$email}{'included'}) {
				## If one user attribute has changed, then we should update the user entry
				my $succesful_update = 0;
				foreach my $attribute ('id','gecos') {
					if ($old_subscribers{$email}{$attribute} ne $new_subscribers->{$email}{$attribute}) {
						&Log::do_log('debug', 'List:sync_include: updating %s to list %s', $email, $name);
						my $update_time = $new_subscribers->{$email}{'update_date'} || time;
						unless( $self->update_list_member(
															$email,
															{'update_date' => $update_time,
															$attribute => $new_subscribers->{$email}{$attribute}}
														)){
															
							&Log::do_log('err', 'List:sync_include(%s): Failed to update %s', $name, $email);
							next;
						}else {
							$succesful_update = 1;
						}
					}
				}
				$users_updated++ if($succesful_update);
				## User was already subscribed, update include_sources_subscriber in DB
			}else {
				&Log::do_log('debug', 'List:sync_include: updating %s to list %s', $email, $name);
				unless( $self->update_list_member($email,  {'update_date' => time,
						     'included' => 1,
						     'id' => $new_subscribers->{$email}{'id'} }) ) {
					&Log::do_log('err', 'List:sync_include(%s): Failed to update %s',
					$name, $email);
					next;
				}
				$users_updated++;
			}

	    ## Add new included user
		}else {
			my $compare = 0;
			foreach my $sub_exclu (@subscriber_exclusion){
				unless ($compare eq '1'){
					if ($email eq $sub_exclu){
						$compare = 1;
					}else{
						next;
					}
				}
			}
			if($compare eq '1'){
				next;
			}
			&Log::do_log('debug3', 'List:sync_include: adding %s to list %s', $email, $name);
			my $u = $new_subscribers->{$email};
			$u->{'included'} = 1;
			$u->{'date'} = time;
			@add_tab = ($u);
			my $user_added = 0;
			unless( $user_added = $self->add_list_member( @add_tab ) ) {
				&Log::do_log('err', 'List:sync_include(%s): Failed to add new users', $name);
				return undef;
			}
			if ($user_added) {
				$users_added++;
				## Send notification if the list config authorizes it only.
				if ($self->{'admin'}{'inclusion_notification_feature'} eq 'on') {
					unless ($self->send_file('welcome', $u->{'email'}, $self->{'domain'},{})) {
						&Log::do_log('err',"Unable to send template 'welcome' to $u->{'email'}");
					}
				}
			}
		}
    }

    if ($users_added) {
        &Log::do_log('notice', 'List:sync_include(%s): %d users added', $name, $users_added);
    }

    &Log::do_log('notice', 'List:sync_include(%s): %d users updated', $name, $users_updated);

    ## Release lock
    unless ($lock->unlock()) {
	return undef;
    }

    ## Get and save total of subscribers
    $self->get_real_total;
    $self->{'last_sync'} = time;
    $self->savestats();
    $self->sync_include_ca($option eq 'purge');
		

    return 1;
}

## The previous function (sync_include) is to be called by the task_manager.
## This one is to be called from anywhere else. This function deletes the scheduled
## sync_include task. If this deletion happened in sync_include(), it would disturb
## the normal task_manager.pl functionning.

sub on_the_fly_sync_include {
    my $self = shift;
    my %options = @_;

    my $pertinent_ttl = $self->{'admin'}{'distribution_ttl'}||$self->{'admin'}{'ttl'};
    &Log::do_log('debug2','List::on_the_fly_sync_include(%s)',$pertinent_ttl);
    if ( $options{'use_ttl'} != 1 || $self->{'last_sync'} < time - $pertinent_ttl) { 
	&Log::do_log('notice', "Synchronizing list members...");
	my $return_value = $self->sync_include();
	if ($return_value == 1) {
	    $self->remove_task('sync_include');
	    return 1;
	}
	else {
	    return $return_value;
	}
    }
    return 1;
}

sub sync_include_admin {
    my ($self) = shift;
    my $option = shift;
    
    my $name=$self->{'name'};
    &Log::do_log('debug2', 'List:sync_include_admin(%s)', $name);

    ## don't care about listmaster role
    foreach my $role ('owner','editor'){
	my $old_admin_users = {};
        ## Load a hash with the old admin users
	for (my $admin_user=$self->get_first_list_admin($role); $admin_user; $admin_user=$self->get_next_list_admin()) {
	    $old_admin_users->{lc($admin_user->{'email'})} = $admin_user;
	}
	
	## Load a hash with the new admin user list from an include source(s)
	my $new_admin_users_include;
	## Load a hash with the new admin user users from the list config
	my $new_admin_users_config;
	unless ($option eq 'purge') {
	    
	    $new_admin_users_include = $self->_load_list_admin_from_include($role);
	    
	    ## If include sources were not available, do not update admin users
	    ## Use DB cache instead
	    unless (defined $new_admin_users_include) {
		&Log::do_log('err', 'Could not get %ss from an include source for list %s', $role, $name);
		unless (&List::send_notify_to_listmaster('sync_include_admin_failed', $self->{'domain'}, [$name])) {
		    &Log::do_log('notice',"Unable to send notify 'sync_include_admmin_failed' to listmaster");
		}
		return undef;
	    }

	    $new_admin_users_config = $self->_load_list_admin_from_config($role);
	    
	    unless (defined $new_admin_users_config) {
		&Log::do_log('err', 'Could not get %ss from config for list %s', $role, $name);
		return undef;
	    }
	}
	
	my @add_tab;
	my $admin_users_added = 0;
	my $admin_users_updated = 0;
	
	## Get an Exclusive lock
	my $lock = new Lock ($self->{'dir'}.'/include_admin_user');
	unless (defined $lock) {
	    &Log::do_log('err','Could not create new lock');
	    return undef;
	}
	$lock->set_timeout(20); 
	unless ($lock->lock('write')) {
	    return undef;
	}
	
	## Go through new admin_users_include
	foreach my $email (keys %{$new_admin_users_include}) {
	    
	    # included and subscribed
	    if (defined $new_admin_users_config->{$email}) {
		my $param;
		foreach my $p ('reception','visibility','gecos','info','profile') {
		    #  config parameters have priority on include parameters in case of conflict
		    $param->{$p} = $new_admin_users_config->{$email}{$p} if (defined $new_admin_users_config->{$email}{$p});
		    $param->{$p} ||= $new_admin_users_include->{$email}{$p};
		}

                #Admin User was already in the DB
		if (defined $old_admin_users->{$email}) {

		    $param->{'included'} = 1;
		    $param->{'id'} = $new_admin_users_include->{$email}{'id'};
		    $param->{'subscribed'} = 1;
		   
		    my $param_update = &is_update_param($param,$old_admin_users->{$email});
		    
		    # updating
		    if (defined $param_update) {
			if (%{$param_update}) {
			    &Log::do_log('debug', 'List:sync_include_admin : updating %s %s to list %s',$role, $email, $name);
			    $param_update->{'update_date'} = time;
			    
			    unless ($self->update_list_admin($email, $role,$param_update)) {
				&Log::do_log('err', 'List:sync_include_admin(%s): Failed to update %s %s', $name,$role,$email);
				next;
			    }
			    $admin_users_updated++;
			}
		    }
		    #for the next foreach (sort of new_admin_users_config that are not included)
		    delete ($new_admin_users_config->{$email});
		    
		# add a new included and subscribed admin user 
		}else {
		    &Log::do_log('debug2', 'List:sync_include_admin: adding %s %s to list %s',$email,$role, $name);
		    
		    foreach my $key (keys %{$param}) {  
			$new_admin_users_config->{$email}{$key} = $param->{$key};
		    }
		    $new_admin_users_config->{$email}{'included'} = 1;
		    $new_admin_users_config->{$email}{'subscribed'} = 1;
		    push (@add_tab,$new_admin_users_config->{$email});
		    
                    #for the next foreach (sort of new_admin_users_config that are not included)
		    delete ($new_admin_users_config->{$email});
		}
		
	    # only included
	    }else {
		my $param = $new_admin_users_include->{$email};

                #Admin User was already in the DB
		if (defined($old_admin_users->{$email}) ) {

		    $param->{'included'} = 1;
		    $param->{'id'} = $new_admin_users_include->{$email}{'id'};
		    $param->{'subscribed'} = 0;

		    my $param_update = &is_update_param($param,$old_admin_users->{$email});
		   
		    # updating
		    if (defined $param_update) {
			if (%{$param_update}) {
			    &Log::do_log('debug', 'List:sync_include_admin : updating %s %s to list %s', $role, $email, $name);
			    $param_update->{'update_date'} = time;
			    
			    unless ($self->update_list_admin($email, $role,$param_update)) {
				&Log::do_log('err', 'List:sync_include_admin(%s): Failed to update %s %s', $name, $role,$email);
				next;
			    }
			    $admin_users_updated++;
			}
		    }
		# add a new included admin user 
		}else {
		    &Log::do_log('debug2', 'List:sync_include_admin: adding %s %s to list %s', $role, $email, $name);
		    
		    foreach my $key (keys %{$param}) {  
			$new_admin_users_include->{$email}{$key} = $param->{$key};
		    }
		    $new_admin_users_include->{$email}{'included'} = 1;
		    push (@add_tab,$new_admin_users_include->{$email});
		}
	    }
	}   

	## Go through new admin_users_config (that are not included : only subscribed)
	foreach my $email (keys %{$new_admin_users_config}) {

	    my $param = $new_admin_users_config->{$email};
	    
	    #Admin User was already in the DB
	    if (defined($old_admin_users->{$email}) ) {

		$param->{'included'} = 0;
		$param->{'id'} = '';
		$param->{'subscribed'} = 1;
		my $param_update = &is_update_param($param,$old_admin_users->{$email});

		# updating
		if (defined $param_update) {
		    if (%{$param_update}) {
			&Log::do_log('debug', 'List:sync_include_admin : updating %s %s to list %s', $role, $email, $name);
			$param_update->{'update_date'} = time;
			
			unless ($self->update_list_admin($email, $role,$param_update)) {
			    &Log::do_log('err', 'List:sync_include_admin(%s): Failed to update %s %s', $name, $role, $email);
			    next;
			}
			$admin_users_updated++;
		    }
		}
	    # add a new subscribed admin user 
	    }else {
		&Log::do_log('debug2', 'List:sync_include_admin: adding %s %s to list %s', $role, $email, $name);
		
		foreach my $key (keys %{$param}) {  
		    $new_admin_users_config->{$email}{$key} = $param->{$key};
		}
		$new_admin_users_config->{$email}{'subscribed'} = 1;
		push (@add_tab,$new_admin_users_config->{$email});
	    }
	}
	
	if ($#add_tab >= 0) {
	    unless( $admin_users_added = $self->add_list_admin($role,@add_tab ) ) {
		&Log::do_log('err', 'List:sync_include_admin(%s): Failed to add new %ss',  $role, $name);
		return undef;
	    }
	}
	
	if ($admin_users_added) {
	    &Log::do_log('debug', 'List:sync_include_admin(%s): %d %s(s) added',
		    $name, $admin_users_added, $role);
	}
	
	&Log::do_log('debug', 'List:sync_include_admin(%s): %d %s(s) updated', $name, $admin_users_updated, $role);

	## Go though old list of admin users
	my $admin_users_removed = 0;
	my @deltab;
	
	foreach my $email (keys %$old_admin_users) {
	    unless (defined($new_admin_users_include->{$email}) || defined($new_admin_users_config->{$email})) {
		&Log::do_log('debug2', 'List:sync_include_admin: removing %s %s to list %s', $role, $email, $name);
		push(@deltab, $email);
	    }
	}
	
	if ($#deltab >= 0) {
	    unless($admin_users_removed = $self->delete_list_admin($role,@deltab)) {
		&Log::do_log('err', 'List:sync_include_admin(%s): Failed to delete %s %s',
			$name, $role, $admin_users_removed);
		return undef;
	    }
	    &Log::do_log('debug', 'List:sync_include_admin(%s): %d %s(s) removed',
		    $name, $admin_users_removed, $role);
	}

	## Release lock
	unless ($lock->unlock()) {
	    return undef;
	}
    }	
   
    $self->{'last_sync_admin_user'} = time;
    $self->savestats();
 
    return $self->get_nb_owners;
}

## Load param admin users from the config of the list
sub _load_list_admin_from_config {
    my $self = shift;
    my $role = shift; 
    my $name = $self->{'name'};
    my %admin_users;

    &Log::do_log('debug2', '(%s) for list %s',$role, $name);  

    foreach my $entry (@{$self->{'admin'}{$role}}) {
	my $email = lc($entry->{'email'});
	my %u;
  
	$u{'email'} = $email;
	$u{'reception'} = $entry->{'reception'};
	$u{'visibility'} = $entry->{'visibility'};
	$u{'gecos'} = $entry->{'gecos'};
	$u{'info'} = $entry->{'info'};
	$u{'profile'} = $entry->{'profile'} if ($role eq 'owner');
 
	$admin_users{$email} = \%u;
    }
    return \%admin_users;
}

## return true if new_param has changed from old_param
#  $new_param is changed to return only entries that need to
# be updated (only deals with admin user parameters, editor or owner)
sub is_update_param {
    my $new_param = shift;
    my $old_param = shift;
    my $resul = {};
    my $update = 0;

    &Log::do_log('debug2', 'List::is_update_param ');  

    foreach my $p ('reception','visibility','gecos','info','profile','id','included','subscribed') {
	if (defined $new_param->{$p}) {
	    if ($new_param->{$p} ne $old_param->{$p}) {
		$resul->{$p} = $new_param->{$p};
		$update = 1;
	    }
	}else {
	    if (defined $old_param->{$p} && ($old_param->{$p} ne '')) {
		$resul->{$p} = '';
		$update = 1;
	    }
	}
    }
    if ($update) {
	return $resul;
    }else {
	return undef;
    }
}



sub _inclusion_loop {

    my $name = shift;
    my $incl = shift;
    my $depend_on = shift;

    return 1 if ($depend_on->{$incl}) ; 
    
    return undef;
}

## Writes to disk the stats data for a list.
sub _save_stats_file {
    my $self = shift;

    croak "Invalid parameter: $self" unless ref $self; #prototype changed (6.2)

    my $file = $self->dir . '/stats';
    my $stats = $self->stats;
    my $total = $self->total;
    my $last_sync = $self->{'last_sync'};
    my $last_sync_admin_user = $self->{'last_sync_admin_user'};

    unless (defined $stats and ref $stats eq 'ARRAY') {
	&Log::do_log('err', 'incorrect parameter: %s', $self);
	return undef;
    }

    &Log::do_log('debug3', '(file=%s, total=%s, last_sync=%s, last_sync_admin_user=%s)', $file, $total,$last_sync,$last_sync_admin_user);
    my $untainted_filename = sprintf("%s", $file); #XXX required?
    open(L, '>', $untainted_filename) || return undef;
    printf L "%d %.0f %.0f %.0f %d %d %d\n", @{$stats}, $total, $last_sync, $last_sync_admin_user;
    close(L);
}

## Writes the user list to disk
sub _save_list_members_file {
    my($self, $file) = @_;
    &Log::do_log('debug3', '(%s)', $file);
    
    my($k, $s);
    
    &Log::do_log('debug2','Saving user file %s', $file);
    
    rename("$file", "$file.old");
    open SUB, "> $file" or return undef;
    
    for ($s = $self->get_first_list_member(); $s; $s = $self->get_next_list_member()) {
	foreach $k ('date','update_date','email','gecos','reception','visibility') {
	    printf SUB "%s %s\n", $k, $s->{$k} unless ($s->{$k} eq '');
	    
	}
	print SUB "\n";
    }
    close SUB;
    return 1;
}

sub _compare_addresses {
   my ($a, $b) = @_;

   my ($ra, $rb);

   $a =~ tr/A-Z/a-z/;
   $b =~ tr/A-Z/a-z/;

   $ra = reverse $a;
   $rb = reverse $b;

   return ($ra cmp $rb);
}

## Store the message in spool digest  by creating a new enrty for it or updating an existing one for this list
## 
sub store_digest {

    my($self,$message) = @_;
   &Log::do_log('debug', 'List::store_digest (list= %s)',$self->{'name'});
    my $separator = &tools::get_separator();  

    my @now  = localtime(time);

    my $digestspool = new Sympaspool('digest');
    my $current_digest = $digestspool->next({ 'list' => $self->name, 'robot'=>$self->domain }); # remember that spool->next lock the selected message if any
    my $message_as_string;

    if($current_digest) {
	$message_as_string = $current_digest->{'messageasstring'};
    }else{
	$message_as_string =  sprintf "\nThis digest for list has been created on %s\n\n", POSIX::strftime("%a %b %e %H:%M:%S %Y", @now);
	$message_as_string .= sprintf "------- THIS IS A RFC934 COMPLIANT DIGEST, YOU CAN BURST IT -------\n\n";
	$message_as_string .= sprintf "\n%s\n\n", &tools::get_separator();
    }
    $message_as_string .= $message->{'msg_as_string'} ;
    $message_as_string .= sprintf "\n%s\n\n", &tools::get_separator();

    # update and unlock current digest message or create it
    if ($current_digest) {
	# update does not modify the date field, this is needed in order to send digest when needed.
	unless ($digestspool->update({'messagekey'=>$current_digest->{'messagekey'}},{'message'=>$message_as_string,'messagelock'=>'NULL'})){
	   &Log::do_log('err',"could not update digest adding this message (digest spool entry key %s)",$current_digest->{'messagekey'});
	    return undef;
	}
    }else{
	unless ($digestspool->store($message_as_string, { 'list'=>$self->name, 'robot' => $self->domain })){
	   &Log::do_log('err',"could not store message in digest spool messafge digestkey %s",$current_digest->{'messagekey'})	;
	    return undef;
	}
    }
}

=over 4

=item get_lists( [ ROBOT, [ OPTIONS, [ REQUESTED_LISTS ] ] ] )

I<Function>.
List of lists hosted a robot

=over 4

=item ROBOT

Name of robot or C<'*'> (default).

=item OPTIONS

A hashref including options passed to List->new() (see load()) and any of
following pairs:

=over 4

=item C<'filter_query' =E<gt> [ KEYS =E<gt> VALS, ... ]>

Filter with list profiles.  When any of items specified by KEYS
(separated by C<"|">) have any of values specified by VALS,
condition by that pair is satisfied.
KEYS prefixed by C<"!"> mean negated condition.
Only lists satisfying all conditions of query are returned.
Currently available keys and values are:

=over 4

=item 'creation' => EPOCH

=item 'creation<' => EPOCH

=item 'creation>' => EPOCH

Creation date is equal to, earlier than or later than the date (epoch).

=item 'member' => EMAIL

=item 'owner' => EMAIL

=item 'editor' => EMAIL

XXX @todo doc

=item 'name' => STRING

=item 'name%' => STRING

=item '%name%' => STRING

Exact, prefixed or subsctring match against list name,
case-insensitive.

=item 'status' => "STATUS|..."

Status of list.  One of 'open', 'closed', 'pending',
'error_config' and 'family_closed'.

=item 'subject' => STRING

=item 'subject%' => STRING

=item '%subject%' => STRING

Exact, prefixed or subsctring match against list subject,
case-insensitive (case folding is Unicode-aware).

=item 'topics' => "TOPIC|..."

Exact match against any of list topics.
'others' or 'topicsless' means no topics.

=item 'update' => EPOCH

=item 'update<' => EPOCH

=item 'update>' => EPOCH

Date of last update is equal to, earlier than or later than the date (epoch).

=begin comment

=item 'web_archive' => ( 1 | 0 )

Whether Web archive of the list is available.  1 or 0.

=end comment

=back

=item C<'order' =E<gt> [ KEY, ... ]>

Subordinate sort key(s).  The results are sorted primarily by robot names
then by other key(s).  Keys prefixed by C<"-"> mean descendent ordering.
Available keys are:

=over 4

=item C<'creation'>

FIXME @todo doc

=item C<'name'>

List name, case-insensitive.  It is the default.

=item C<'total'>

Estimated number of subscribers.

=item C<'update'>

FIXME @todo doc

=back

=back

=item REQUESTED_LISTS

Arrayref to name of requested lists, if any.

=back

Returns a ref to an array of List objects.

=back

=cut

sub get_lists {
    &Log::do_log('debug2', '(%s, %s, %s)', @_);

    my $robot_context = shift || '*';
    my $options = shift || {};
    my $requested_lists = shift; ## Optional parameter to load only a subset of all lists

    my(@lists, @robots);

    $options->{'reload_config'} = 1 if $options->{'use_files'}; # For compat.

    # Build query: Perl expression for files and SQL expression for list_table.
    my $cond_perl = undef;
    my $cond_sql = undef;
    my $which_role = undef;
    my $which_user = undef;
    my @query = (@{$options->{'filter_query'} || []});
    my @clause_perl = ();
    my @clause_sql = ();
    while (1 < scalar @query) {
        my @expr_perl = ();
        my @expr_sql = ();

	my $keys = shift @query;
	next unless defined $keys and $keys =~ /\S/;
	$keys =~ s/^(!?)\s*//;
	my $negate = $1;
	my @keys = split /[|]/, $keys;

	my $vals = shift @query;
	next unless defined $vals and length $vals; # spaces are allowed
	my @vals = split /[|]/, $vals;

        foreach my $k (@keys) {
            next unless $k =~ /\S/;

	    my $c = undef;
	    my ($b, $a) = ('', '');
	    $b = $1 if $k =~ s/^(%)//;
	    $a = $1 if $k =~ s/(%)$//;
	    if ($b or $a) {
		unless ($a) {
		    $c = '%s eq "%s"';
		} elsif ($b) {
		    $c = 'index(%s, "%s") >= 0';
		} else {
		    $c = 'index(%s, "%s") == 0';
		}
	    } elsif ($k =~ s/\s*([<>])\s*$//) {
		$c = '%s '.$1.' %s';
	    }

	    ## query with single key and single value

	    if ($k =~ /^(member|owner|editor)$/) {
		if (defined $which_role) {
		    &Log::do_log('err', "bug in logic. Ask developer");
		    return undef;
		}
		$which_role = $k;
		$which_user = $vals;
		next;
	    }

	    ## query with single value

	    if ($k eq 'name' or $k eq 'subject') {
		my ($vl, $ve, $key_perl, $key_sql);
		if ($k eq 'name') {
		    $key_perl = '$list->name';
		    $key_sql = 'name_list';
		    $vl = lc $vals;
		} else {
		    $key_perl = 'tools::foldcase($list->subject)';
		    $key_sql = 'searchkey_list';
		    $vl = tools::foldcase($vals);
		}

		## Perl expression
		$ve = $vl;
		$ve =~ s/([^ \w\x80-\xFF])/\\$1/g;
		push @expr_perl,
		     sprintf(($c ? $c : '%s eq "%s"'), $key_perl, $ve);

		## SQL expression
		if ($a or $b) {
		    $ve = &SDM::quote($vl);
		    $ve =~ s/^["'](.*)['"]$/$1/;
		    $ve =~ s/([%_])/\\$1/g;
		    push @expr_sql,
			 sprintf("%s LIKE '%s'", $key_sql, "$b$ve$a");
                } else {
                    push @expr_sql,
			 sprintf('%s = %s', $key_sql, &SDM::quote($vl));
		}

		next;
	    }

	    foreach my $v (@vals) {
		## Perl expressions
		if ($k eq 'creation' or $k eq 'update') {
		    push @expr_perl,
			 sprintf(($c ? $c : '%s == %s'),
				 sprintf('$list->%s->{"date_epoch"}',
					$k),
				$v);
##		} elsif ($k eq 'web_archive') {
##		    push @expr_perl,
##			 sprintf('%s$list->is_web_archived',
##		    		 ($v+0 ? '' : '! '));
                } elsif ($k eq 'status') {
		    my $ve = lc $v;
		    $ve =~ s/([^ \w\x80-\xFF])/\\$1/g;
		    push @expr_perl,
			 sprintf('$list->status eq "%s"', $ve);
		} elsif ($k eq 'topics') {
		    my $ve = lc $v;
		    if ($ve eq 'others' or $ve eq 'topicsless') {
			push @expr_perl,
			     '! scalar(grep { $_ ne "others" } @{$list->topics || []})';
		    } else {
			$ve =~ s/([^ \w\x80-\xFF])/\\$1/g;
			push @expr_perl,
			     sprintf('scalar(grep { $_ eq "%s" } @{$list->topics || []})',
				     $ve);
		    }
                } else {
                    &Log::do_log('err', "bug in logic. Ask developer");
                    return undef;
                }

		## SQL expressions
		if ($k eq 'creation' or $k eq 'update') {
		    push @expr_sql,
			 sprintf('%s_epoch_list %s %s',
				 $k, ($c ? $c : '='), $v);
##		} elsif ($k eq 'web_archive') {
##                    push @expr_sql,
##			 sprintf('web_archive_list = %d', ($v+0 ? 1 : 0));
		} elsif ($k eq 'status') {
                    push @expr_sql,
			 sprintf('%s_list = %s', $k, &SDM::quote($v));
		} elsif ($k eq 'topics') {
		    my $ve = lc $v;
		    if ($ve eq 'others' or $ve eq 'topicsless') {
			push @expr_sql,	"topics_list = ''";
		    } else {
			$ve = &SDM::quote($ve);
			$ve =~ s/^["'](.*)['"]$/$1/;
			$ve =~ s/([%_])/\\$1/g;
			push @expr_sql,
			     sprintf("topics_list LIKE '%%,%s,%%'", $ve);
		    }
                }
            }
        }
        if (scalar @expr_perl) {
            push @clause_perl, ($negate ? '! ' : '') .
			       '(' . join(' || ', @expr_perl) . ')';
            push @clause_sql, ($negate ? 'NOT ' : '') .
			      '(' . join(' OR ', @expr_sql) . ')';
        }
    }
    if (scalar @clause_perl) {
        $cond_perl = join ' && ', @clause_perl;
        $cond_sql = join ' AND ', @clause_sql;
    } else {
        $cond_perl = undef;
        $cond_sql = undef;
    }
    &Log::do_log('debug3', 'filter_query %s; %s', $cond_perl, $cond_sql);

    ## Sort order
    my $order_perl;
    my $order_sql;
    my $keys = $options->{'order'} || [ ];
    my @keys_perl = ();
    my @keys_sql = ();
    foreach my $key (@{$keys}) {
	my $desc = ($key =~ s/^\s*-\s*//i);

	if ($key eq 'creation' or $key eq 'update') {
	    if ($desc) {
		push @keys_perl,
		     sprintf '$b->%s->{"date_epoch"} <=> $a->%s->{"date_epoch"}', $key, $key;
	    } else {
		push @keys_perl,
		     sprintf '$a->%s->{"date_epoch"} <=> $b->%s->{"date_epoch"}', $key, $key;
	    }
	} elsif ($key eq 'name') {
	    if ($desc) {
		push @keys_perl, '$b->name cmp $a->name';
	    } else {
		push @keys_perl, '$a->name cmp $b->name';
	    }
	} elsif ($key eq 'total') {
	    if ($desc) {
		push @keys_perl,
		     sprintf '$b->total <=> $a->total';
	    } else {
		push @keys_perl,
		     sprintf '$a->total <=> $b->total';
	    }
	} else {
	    &Log::do_log('err', 'bug in logic.  Ask developer');
	    return undef;
	}

	if ($key eq 'creation' or $key eq 'update') {
	    push @keys_sql,
		 sprintf '%s_epoch_list%s', $key, ($desc ? ' DESC' : '');
	} else {
	    push @keys_sql,
		 sprintf '%s_list%s', $key, ($desc ? ' DESC' : '');
	}
    }
    $order_perl = join(' or ', @keys_perl) || undef;
    push @keys_sql, 'name_list'
	unless scalar grep { $_ =~ /name_list/ } @keys_sql;
    $order_sql = join(', ', @keys_sql);
    &Log::do_log('debug3', 'order %s; %s', $order_perl, $order_sql);


    if ($robot_context eq '*') {
	@robots = sort &get_robots;
    } else {
	@robots = ($robot_context);
    }
    foreach my $robot (@robots) {
	## Load only requested lists if $requested_list is set
	## otherwise load all lists
	my %requested_lists = ();
	if (defined $requested_lists) {
	    my $robot_re = $robot;
	    $robot_re =~ s/(\W)/\\$1/g;
	    %requested_lists =
		map { ($_ => 1) }
		    grep { index($_, '@') < 0 or s/\@${robot_re}$// }
			 sort @{$requested_lists};
	    ## none requested on this robot.
	    next unless %requested_lists; # foreach my $robot
	}

	## Check on-memory cache first
	if (! defined $which_role and $list_cache_filled{$robot}) {
	    ## filter list if required.
	    my @l = ();
	    my @all_lists = map { $list_of_lists{$robot}{$_} }
				sort keys %{$list_of_lists{$robot}};
	    if (defined $cond_perl or %requested_lists) {
		foreach my $list (@all_lists) {
		    if (%requested_lists) {
			next unless $requested_lists{$list->name};
		    }
		    if (defined $cond_perl) {
			next unless eval $cond_perl;
		    }
		    push @l, $list;
		}
	    } else {
		push @l, @all_lists;
	    }

	    ## sort
	    if ($order_perl) {
		use sort "stable";
		push @lists, sort { eval $order_perl } @l;
		use sort "defaults";
	    } else {
		push @lists, @l;
	    }

	    next; # foreach my $robot
	}

	## check existence of robot directory
	my $robot_dir =  $Conf::Conf{'home'}.'/'.$robot;
	$robot_dir = $Conf::Conf{'home'}
	    unless -d $robot_dir or $robot ne $Conf::Conf{'domain'};
	unless (-d $robot_dir) {
	    &Log::do_log('err', 'unknown robot %s, Unable to open %s',
			 $robot, $robot_dir);
	    return undef ;
	}

	## Files are used instead of list_table DB cache.

	if (&Conf::get_robot_conf($robot, 'cache_list_config') ne 'database' or
	    $options->{'reload_config'}) {
	    ## filter by role
	    if (defined $which_role) {
		my %r = ();

		push @sth_stack, $sth;

		if ($which_role eq 'member') {
		    $sth = &SDM::do_prepared_query('SELECT list_subscriber FROM subscriber_table WHERE robot_subscriber = ? AND user_subscriber = ?',
						   $robot, $which_user);
		} else {
		    $sth = &SDM::do_prepared_query('SELECT list_admin FROM admin_table WHERE robot_admin = ? AND user_admin = ? AND role_admin = ?',
						   $robot, $which_user,
						   $which_role);
		}
		unless ($sth) {
		    &Log::do_log('err', 'failed to get lists with user %s as %s from database: %s', $which_user, $which_role, $@);
		    $sth = pop @sth_stack;
		    return undef;
		}
		my @row;
		while (@row = $sth->fetchrow_array) {
		    my $listname = $row[0];
		    if (%requested_lists) {
			next unless $requested_lists{$listname};
		    }
		    $r{$listname} = 1;
		}
		$sth->finish;

		$sth = pop @sth_stack;

		# none found
		next unless %r; # foreach my $robot
		%requested_lists = %r;
	    }

	    ## If entire lists on a robot are requested,
	    ## check orphan entries on cache.
	    my %orphan = ();
	    if (! %requested_lists and $options->{'reload_config'}) {
		push @sth_stack, $sth;

		unless ($sth = &SDM::do_prepared_query('SELECT name_list FROM list_table WHERE robot_list = ?',
						       $robot)) {
		    &Log::do_log('err', 'Failed to get lists from database');
		    $sth = pop @sth_stack;
		    return undef;
		}
		my @row;
		while (@row = $sth->fetchrow_array) {
		    $orphan{$row[0]} = 1;
		}
		$sth->finish;

		$sth = pop @sth_stack;
	    }

	    unless (opendir(DIR, $robot_dir)) {
		&Log::do_log('err', 'Unable to open %s', $robot_dir);
		return undef;
	    }
	    my @l = ();
	    foreach my $listname (sort readdir(DIR)) {
		next if $listname =~ /^\.+$/;
		next unless -d "$robot_dir/$listname";
		next unless -f "$robot_dir/$listname/config";

		## filter list by requested_lists (and role).
		if (%requested_lists) {
		    next unless $requested_lists{$listname};
		}
		## create object
		my $list = new List($listname, $robot, $options);
		next unless defined $list;

		## not orphan entry
		delete $orphan{$listname};

		## filter by condition
		if (defined $cond_perl) {
		    next unless eval $cond_perl;
		}

		push @l, $list;
	    }
	    closedir DIR;

	    ## All lists are in memory cache
	    $list_cache_filled{$robot} = 1 unless %requested_lists;

	    ## sort
	    if ($order_perl) {
		eval 'use sort "stable"';
		push @lists, sort { eval $order_perl } @l;
		eval 'use sort "defaults"';
	    } else {
		push @lists, @l;
	    }

	    ## clear orphan cache entries in list_table.
	    if ($options->{'reload_config'} and %orphan) {
		foreach my $name (keys %orphan) {
		    &Log::do_log('notice', 'Clearing orphan list cache on list_table: %s@%s',
				 $name, $robot);
		    &SDM::do_prepared_query('DELETE from list_table WHERE name_list = ? AND robot_list = ?',
					    $name, $robot);
		}
	    }

	    next; # foreach my $robot
	}

	## Use list_table DB cache.

	my $table;
	my $cond;
	my $cols;
	if (! defined $which_role) {
	    $table = 'list_table';
	    $cond = '';
	    $cols = '';
	} elsif ($which_role eq 'member') {
	    $table = 'list_table, subscriber_table';
	    $cond = 'robot_list = robot_subscriber AND name_list = list_subscriber AND ';
	    $cols = ', ' . &_list_member_cols;
	} else {
	    $table = 'list_table, admin_table';
	    $cond = sprintf 'robot_list = robot_admin AND name_list = list_admin AND role_admin = %s AND ',
			    &SDM::quote($which_role);
	    $cols = ', ' . &_list_admin_cols;
	}

	push @sth_stack, $sth;

	if (defined $cond_sql) {
	    $sth = &SDM::do_query('SELECT name_list AS name%s FROM %s WHERE %s robot_list = %s AND %s ORDER BY %s',
				  $cols, $table, $cond,
				  &SDM::quote($robot),
				  $cond_sql, $order_sql);
	} else {
	    $sth = &SDM::do_prepared_query(sprintf('SELECT name_list AS name%s FROM %s WHERE %s robot_list = ? ORDER BY %s',
						   $cols, $table, $cond,
						   $order_sql),
					   $robot);
	}
	unless ($sth) {
	    &Log::do_log('err', 'Failed to get lists from %s', $table);
	    $sth = pop @sth_stack;
	    return undef;
	}
	my $list;
	my $l;
	my @l = ();
	while ($l = $sth->fetchrow_hashref('NAME_lc')) {
	    ## filter by requested_lists
	    if (%requested_lists) {
		next unless $requested_lists{$l->{'name'}};
	    }
	    push @l, $l;
	}
	$sth->finish;

	$sth = pop @sth_stack;

	foreach my $l (@l) {
	    ## renew object on memory.
	    ## If list already in memory and
	    ## not previously purged by another process
	    if ($list_of_lists{$robot}{$l->{'name'}} and
		-d $list_of_lists{$robot}{$l->{'name'}}{'dir'}) {
		# use the current list in memory and update it
		$list = $list_of_lists{$robot}{$l->{'name'}};
	    } else {
		# create a new List object
		$list = bless { } => __PACKAGE__;
	    }
	    next unless defined $list->load($l->{'name'}, $robot, $options);

	    ## save subscriber/admin information to memory cache.
	    if (defined $which_role) {
		delete $l->{'name'};
		$list->user($which_role, $which_user, $l);
	    }

	    push @lists, $list;
	}

	$list_cache_filled{$robot} = 1
	    unless defined $which_role or defined $cond_sql or
		   %requested_lists;
    }
    return \@lists;
}

=over 4

=item get_robots()

I<Function>.
List of robots hosted by Sympa

=back

=cut

sub get_robots {

    my(@robots, $r);
    &Log::do_log('debug2', 'List::get_robots()');

    unless (opendir(DIR, $Conf::Conf{'etc'})) {
	&Log::do_log('err',"Unable to open $Conf::Conf{'etc'}");
	return undef;
    }
    my $use_default_robot = 1 ;
    foreach $r (sort readdir(DIR)) {
	next unless (($r !~ /^\./o) && (-d "$Conf::Conf{'home'}/$r"));
	next unless (-r "$Conf::Conf{'etc'}/$r/robot.conf");
	push @robots, $r;
	undef $use_default_robot if ($r eq $Conf::Conf{'domain'});
    }
    closedir DIR;

    push @robots, $Conf::Conf{'domain'} if ($use_default_robot);
    return @robots ;
}

## get idp xref to locally validated email address
sub get_netidtoemail_db {
    my $robot = shift;
    my $netid = shift;
    my $idpname = shift;
    &Log::do_log('debug', 'List::get_netidtoemail_db(%s, %s)', $netid, $idpname);

    my ($l, %which, $email);

    push @sth_stack, $sth;

    unless ($sth = &SDM::do_query( "SELECT email_netidmap FROM netidmap_table WHERE netid_netidmap = %s and serviceid_netidmap = %s and robot_netidmap = %s", &SDM::quote($netid), &SDM::quote($idpname), &SDM::quote($robot))) {
	&Log::do_log('err','Unable to get email address from netidmap_table for id %s, service %s, robot %s', $netid, $idpname, $robot);
	$sth = pop @sth_stack;
	return undef;
    }

    $email = $sth->fetchrow;
    $sth->finish();

    $sth = pop @sth_stack;

    return $email;
}

## set idp xref to locally validated email address
sub set_netidtoemail_db {
    my $robot = shift;
    my $netid = shift;
    my $idpname = shift;
    my $email = shift; 
    &Log::do_log('debug', 'List::set_netidtoemail_db(%s, %s, %s)', $netid, $idpname, $email);

    my ($l, %which);

    unless (&SDM::do_query( "INSERT INTO netidmap_table (netid_netidmap,serviceid_netidmap,email_netidmap,robot_netidmap) VALUES (%s, %s, %s, %s)", &SDM::quote($netid), &SDM::quote($idpname), &SDM::quote($email), &SDM::quote($robot))) {
	&Log::do_log('err','Unable to set email address %s in netidmap_table for id %s, service %s, robot %s', $email, $netid, $idpname, $robot);
	return undef;
    }

    return 1;
}

## Update netidmap table when user email address changes
sub update_email_netidmap_db{
    my ($robot, $old_email, $new_email) = @_;
    
    unless (defined $robot && 
	    defined $old_email &&
	    defined $new_email) {
	&Log::do_log('err', 'Missing parameter');
	return undef;
    }

    unless (&SDM::do_query( "UPDATE netidmap_table SET email_netidmap = %s WHERE (email_netidmap = %s AND robot_netidmap = %s)",&SDM::quote($new_email), &SDM::quote($old_email), &SDM::quote($robot))) {
	&Log::do_log('err','Unable to set new email address %s in netidmap_table to replace old address %s for robot %s', $new_email, $old_email, $robot);
	return undef;
    }

    return 1;
}

=over 4

=item get_which ( EMAIL, ROBOT, ROLE )

I<Function>.
Get a list of lists where EMAIL assumes this ROLE (owner, editor or member) of
function to any list in ROBOT.

=back

=cut

sub get_which {
    &Log::do_log('debug2', '(%s, %s, %s)', @_);
    my $email = &tools::clean_email(shift);
    my $robot = shift;
    my $role = shift;

    unless ($role eq 'member' or $role eq 'owner' or $role eq 'editor') {
	&Log::do_log('err', 'Internal error, unknown or undefined parameter "%s"', $role);
	return undef;
    }

    my $all_lists = &get_lists($robot,
	{ 'filter_query' => [ $role => $email,
			      '! status' => 'closed|family_closed' ] });

    return @{$all_lists || []};
}

## return total of messages awaiting moderation
sub get_mod_spool_size {
    my $self = shift;
    &Log::do_log('debug3', 'List::get_mod_spool_size()');    

    my $spool = new Sympaspool('mod');
    my $count =  $spool->get_content({ 'selector' => { 'list' => $self->name, 'robot' => $self->domain },
				      'selection'=>'count'});
    
    if ($count) {
	return $count;
    }else{
	return 0;
    }
}

### moderation for shared

# return the status of the shared
sub get_shared_status {
    my $self = shift;
    &Log::do_log('debug3', '(%s)', $self->{'name'});
    
    if (-e $self->{'dir'}.'/shared') {
	return 'exist';
    }elsif (-e $self->{'dir'}.'/pending.shared') {
	return 'deleted';
    }else{
	return 'none';
    }
}

# return the list of documents shared waiting for moderation 
sub get_shared_moderated {
    my $self = shift;
    &Log::do_log('debug3', 'List::get_shared_moderated()');  
    my $shareddir = $self->{'dir'}.'/shared';

    unless (-e "$shareddir") {
	return undef;
    }
    
    ## sort of the shared
    my @mod_dir = &sort_dir_to_get_mod("$shareddir");
    return \@mod_dir;
}

# return the list of documents awaiting for moderation in a dir and its subdirs
sub sort_dir_to_get_mod {
    #dir to explore
    my $dir = shift;
    &Log::do_log('debug3', 'List::sort_dir_to_get_mod()');  
    
    # listing of all the shared documents of the directory
    unless (opendir DIR, "$dir") {
	&Log::do_log('err',"sort_dir_to_get_mod : cannot open $dir : $!");
	return undef;
    }
    
    # array of entry of the directory DIR 
    my @tmpdir = readdir DIR;
    closedir DIR;

    # private entry with documents not yet moderated
    my @moderate_dir = grep (/(\.moderate)$/, @tmpdir);
    @moderate_dir = grep (!/^\.desc\./, @moderate_dir);

    foreach my $d (@moderate_dir) {
	$d = "$dir/$d";
    }
   
    my $path_d;
    foreach my $d (@tmpdir) {
	# current document
        $path_d = "$dir/$d";

	if ($d =~ /^\.+$/){
	    next;
	}

	if (-d $path_d) {
	    push(@moderate_dir,&sort_dir_to_get_mod($path_d));
	}
    }
	
    return @moderate_dir;
    
 } 


## Get the type of a DB field
sub get_db_field_type {
    my ($table, $field) = @_;

    unless ($sth = &SDM::do_query("SHOW FIELDS FROM $table")) {
	&Log::do_log('err','get the list of fields for table %s', $table);
	return undef;
    }
	    
    while (my $ref = $sth->fetchrow_hashref('NAME_lc')) {
	next unless ($ref->{'Field'} eq $field);

	return $ref->{'Type'};
    }

    return undef;
}

## Lowercase field from database
sub lowercase_field {
    my ($table, $field) = @_;

    my $total = 0;

    unless ($sth = &SDM::do_query( "SELECT $field from $table")) {
	&Log::do_log('err','Unable to get values of field %s for table %s',$field,$table);
	return undef;
    }

    while (my $user = $sth->fetchrow_hashref('NAME_lc')) {
	my $lower_cased = lc($user->{$field});
	next if ($lower_cased eq $user->{$field});

	$total++;

	## Updating Db
	unless ($sth = &SDM::do_query( "UPDATE $table SET $field=%s WHERE ($field=%s)", &SDM::quote($lower_cased), &SDM::quote($user->{$field}))) {
	    &Log::do_log('err','Unable to set field % from table %s to value %s',$field,$lower_cased,$table);
	    next;
	}
    }
    $sth->finish();

    return $total;
}

## Loads the list of topics if updated
sub load_topics {
    
    my $robot = shift ;
    &Log::do_log('debug2', 'List::load_topics(%s)',$robot);

    my $conf_file = &tools::get_filename('etc',{},'topics.conf',$robot);

    unless ($conf_file) {
	&Log::do_log('err','No topics.conf defined');
	return undef;
    }

    my $topics = {};

    ## Load if not loaded or changed on disk
    if (! $list_of_topics{$robot} || ((stat($conf_file))[9] > $mtime{'topics'}{$robot})) {

	## delete previous list of topics
	%list_of_topics = undef;

	unless (-r $conf_file) {
	    &Log::do_log('err',"Unable to read $conf_file");
	    return undef;
	}
	
	unless (open (FILE, "<", $conf_file)) {
	    &Log::do_log('err',"Unable to open config file $conf_file");
	    return undef;
	}
	
	## Raugh parsing
	my $index = 0;
	my (@raugh_data, $topic);
	while (<FILE>) {
	    Encode::from_to($_, $Conf::Conf{'filesystem_encoding'}, 'utf8');
	    if (/^([\-\w\/]+)\s*$/) {
		$index++;
		$topic = {'name' => $1,
			  'order' => $index
			  };
	    }elsif (/^([\w\.]+)\s+(.+)\s*$/) {
		next unless (defined $topic->{'name'});
		
		$topic->{$1} = $2;
	    }elsif (/^\s*$/) {
		if (defined $topic->{'name'}) {
		    push @raugh_data, $topic;
		    $topic = {};
		}
	    }	    
	}
	close FILE;

	## Last topic
	if (defined $topic->{'name'}) {
	    push @raugh_data, $topic;
	    $topic = {};
	}

	$mtime{'topics'}{$robot} = (stat($conf_file))[9];

	unless ($#raugh_data > -1) {
	    &Log::do_log('notice', 'No topic defined in %s/topics.conf', $Conf::Conf{'etc'});
	    return undef;
	}

	## Analysis
	foreach my $topic (@raugh_data) {
	    my @tree = split '/', $topic->{'name'};
	    
	    if ($#tree == 0) {
		my $title = _get_topic_titles($topic);
		$list_of_topics{$robot}{$tree[0]}{'title'} = $title;
		$list_of_topics{$robot}{$tree[0]}{'visibility'} = $topic->{'visibility'}||'default';
		#$list_of_topics{$robot}{$tree[0]}{'visibility'} = &_load_scenario_file('topics_visibility', $robot,$topic->{'visibility'}||'default');
		$list_of_topics{$robot}{$tree[0]}{'order'} = $topic->{'order'};
	    }else {
		my $subtopic = join ('/', @tree[1..$#tree]);
		my $title = _get_topic_titles($topic);
		$list_of_topics{$robot}{$tree[0]}{'sub'}{$subtopic} = &_add_topic($subtopic,$title);
	    }
	}

	## Set undefined Topic (defined via subtopic)
	foreach my $t (keys %{$list_of_topics{$robot}}) {
	    unless (defined $list_of_topics{$robot}{$t}{'visibility'}) {
		#$list_of_topics{$robot}{$t}{'visibility'} = &_load_scenario_file('topics_visibility', $robot,'default');
	    }
	    
	    unless (defined $list_of_topics{$robot}{$t}{'title'}) {
		$list_of_topics{$robot}{$t}{'title'} = {'default' => $t};
	    }	
	}
    }

    ## Set the title in the current language
    my $lang = &Language::GetLang();
    foreach my $top (keys %{$list_of_topics{$robot}}) {
	my $topic = $list_of_topics{$robot}{$top};
	$topic->{'current_title'} = $topic->{'title'}{$lang} || $topic->{'title'}{'default'} || $top;

	foreach my $subtop (keys %{$topic->{'sub'}}) {
	$topic->{'sub'}{$subtop}{'current_title'} = $topic->{'sub'}{$subtop}{'title'}{$lang} || $topic->{'sub'}{$subtop}{'title'}{'default'} || $subtop;	    
	}
    }

    return %{$list_of_topics{$robot}};
}

sub _get_topic_titles {
    my $topic = shift;

    my $title;
    foreach my $key (%{$topic}) {
	if ($key =~ /^title(.(\w+))?$/) {
	    my $lang = $2 || 'default';
	    $title->{$lang} = $topic->{$key};
	}
    }
    
    return $title;
}

## Inner sub used by load_topics()
sub _add_topic {
    my ($name, $title) = @_;
    my $topic = {};

    my @tree = split '/', $name;
    if ($#tree == 0) {
	return {'title' => $title};
    }else {
	$topic->{'sub'}{$name} = &_add_topic(join ('/', @tree[1..$#tree]), $title);
	return $topic;
    }
}

############ THIS IS RELATED TO NEW LOAD_ADMIN_FILE #############

## Sort function for writing config files
sub by_order {
    ($::pinfo{$main::a}{'order'} <=> $::pinfo{$main::b}{'order'}) || ($main::a cmp $main::b);
}

## Apply defaults to parameters definition (%::pinfo)
sub _apply_defaults {
    &Log::do_log('debug3', 'List::_apply_defaults()');

    ## List of available languages
    $::pinfo{'lang'}{'format'} = &Language::GetSupportedLanguages();

    ## Parameter order
    foreach my $index (0..$#param_order) {
	if ($param_order[$index] eq '*') {
	    $default{'order'} = $index;
	}else {
	    $::pinfo{$param_order[$index]}{'order'} = $index;
	}
    }

    ## Parameters
    foreach my $p (keys %::pinfo) {

	## Apply defaults to %pinfo
	foreach my $d (keys %default) {
	    unless (defined $::pinfo{$p}{$d}) {
		$::pinfo{$p}{$d} = $default{$d};
	    }
	}

	## Scenario format
	if ($::pinfo{$p}{'scenario'}) {
	    $::pinfo{$p}{'format'} = &tools::get_regexp('scenario');
	    $::pinfo{$p}{'default'} = 'default';
	}

	## Task format
	if ($::pinfo{$p}{'task'}) {
	    $::pinfo{$p}{'format'} = &tools::get_regexp('task');
	}

	## Datasource format
	if ($::pinfo{$p}{'datasource'}) {
	    $::pinfo{$p}{'format'} = &tools::get_regexp('datasource');
	}

	## Enumeration
	if (ref ($::pinfo{$p}{'format'}) eq 'ARRAY') {
	    $::pinfo{$p}{'file_format'} ||= join '|', @{$::pinfo{$p}{'format'}};
	}


	## Set 'format' as default for 'file_format'
	$::pinfo{$p}{'file_format'} ||= $::pinfo{$p}{'format'};
	
	if (($::pinfo{$p}{'occurrence'} =~ /n$/) 
	    && $::pinfo{$p}{'split_char'}) {
	    my $format = $::pinfo{$p}{'file_format'};
	    my $char = $::pinfo{$p}{'split_char'};
	    $::pinfo{$p}{'file_format'} = "($format)*(\\s*$char\\s*($format))*";
	}


	next unless ((ref $::pinfo{$p}{'format'} eq 'HASH')
		     && (ref $::pinfo{$p}{'file_format'} eq 'HASH'));
	
	## Parameter is a Paragraph)
	foreach my $k (keys %{$::pinfo{$p}{'format'}}) {
	    ## Defaults
	    foreach my $d (keys %default) {
		unless (defined $::pinfo{$p}{'format'}{$k}{$d}) {
		    $::pinfo{$p}{'format'}{$k}{$d} = $default{$d};
		}
	    }
	    
	    ## Scenario format
	    if (ref($::pinfo{$p}{'format'}{$k}) && $::pinfo{$p}{'format'}{$k}{'scenario'}) {
		$::pinfo{$p}{'format'}{$k}{'format'} = &tools::get_regexp('scenario');
		$::pinfo{$p}{'format'}{$k}{'default'} = 'default' unless (($p eq 'web_archive') && ($k eq 'access'));
	    }

	    ## Task format
	    if (ref($::pinfo{$p}{'format'}{$k}) && $::pinfo{$p}{'format'}{$k}{'task'}) {
		$::pinfo{$p}{'format'}{$k}{'format'} = &tools::get_regexp('task');
	    }

	    ## Datasource format
	    if (ref($::pinfo{$p}{'format'}{$k}) && $::pinfo{$p}{'format'}{$k}{'datasource'}) {
		$::pinfo{$p}{'format'}{$k}{'format'} = &tools::get_regexp('datasource');
	    }

	    ## Enumeration
	    if (ref ($::pinfo{$p}{'format'}{$k}{'format'}) eq 'ARRAY') {
		$::pinfo{$p}{'file_format'}{$k}{'file_format'} ||= join '|', @{$::pinfo{$p}{'format'}{$k}{'format'}};
	    }

	    if (($::pinfo{$p}{'file_format'}{$k}{'occurrence'} =~ /n$/) 
		&& $::pinfo{$p}{'file_format'}{$k}{'split_char'}) {
		my $format = $::pinfo{$p}{'file_format'}{$k}{'file_format'};
		my $char = $::pinfo{$p}{'file_format'}{$k}{'split_char'};
		$::pinfo{$p}{'file_format'}{$k}{'file_format'} = "($format)*(\\s*$char\\s*($format))*";
	    }

	}

	next unless (ref $::pinfo{$p}{'file_format'} eq 'HASH');

	foreach my $k (keys %{$::pinfo{$p}{'file_format'}}) {
	    ## Set 'format' as default for 'file_format'
	    $::pinfo{$p}{'file_format'}{$k}{'file_format'} ||= $::pinfo{$p}{'file_format'}{$k}{'format'};
	}
    }

    return \%::pinfo;
}

## Save a parameter
sub _save_list_param {
    my ($key, $p, $defaults, $fd) = @_;
    ##&Log::do_log('debug3', '_save_list_param(%s)', $key);

    ## Ignore default value
    return 1 if ($defaults == 1);
#    next if ($defaults == 1);

    return 1 unless (defined ($p));
#    next  unless (defined ($p));

    if (defined ($::pinfo{$key}{'scenario'}) ||
        defined ($::pinfo{$key}{'task'}) ) {
	return 1 if ($p->{'name'} eq 'default');

	$fd->print(sprintf "%s %s\n", $key, $p->{'name'});
	$fd->print("\n");

    }elsif (ref($::pinfo{$key}{'file_format'})) {
	$fd->print(sprintf "%s\n", $key);
	foreach my $k (keys %{$p}) {

	    if (defined ($::pinfo{$key}{'file_format'}{$k}{'scenario'}) ) {
		## Skip if empty value
		next if ($p->{$k}{'name'} =~ /^\s*$/);

		$fd->print(sprintf "%s %s\n", $k, $p->{$k}{'name'});

	    }elsif (($::pinfo{$key}{'file_format'}{$k}{'occurrence'} =~ /n$/)
		    && $::pinfo{$key}{'file_format'}{$k}{'split_char'}) {
		
		$fd->print(sprintf "%s %s\n", $k, join($::pinfo{$key}{'file_format'}{$k}{'split_char'}, @{$p->{$k}}));
	    }else {
		## Skip if empty value
		next if ($p->{$k} =~ /^\s*$/);

		$fd->print(sprintf "%s %s\n", $k, $p->{$k});
	    }
	}
	$fd->print("\n");

    }else {
	if (($::pinfo{$key}{'occurrence'} =~ /n$/)
	    && $::pinfo{$key}{'split_char'}) {
	    ################" avant de debugger do_edit_list qui crée des nouvelles entrées vides
 	    my $string = join($::pinfo{$key}{'split_char'}, @{$p});
 	    $string =~ s/\,\s*$//;
	    
 	    $fd->print(sprintf "%s %s\n\n", $key, $string);
	}elsif ($key eq 'digest') {
	    my $value = sprintf '%s %d:%d', join(',', @{$p->{'days'}})
		,$p->{'hour'}, $p->{'minute'};
	    $fd->print(sprintf "%s %s\n\n", $key, $value);
	}else {
	    $fd->print(sprintf "%s %s\n\n", $key, $p);
	}
    }
    
    return 1;
}

## Load a single line
sub _load_list_param {
    my ($robot,$key, $value, $p, $directory) = @_;
    ##&Log::do_log('debug3','_load_list_param(%s,\'%s\',\'%s\')', $robot,$key, $value);
    
    ## Empty value
    if ($value =~ /^\s*$/) {
	return undef;
    }

    ## Default
    if ($value eq 'default') {
	$value = $p->{'default'};
    }

    ## Search configuration file
    if (ref($value) && defined $value->{'conf'}) {
	$value = &Conf::get_robot_conf($robot, $value->{'conf'});
    }

    ## Synonyms
    if (defined $p->{'synonym'}{$value}) {
	$value = $p->{'synonym'}{$value};
    }

    ## Scenario
    if ($p->{'scenario'}) {
	$value =~ y/,/_/;
	my $scenario = new Scenario ('function' => $p->{'scenario'},
				     'robot' => $robot, 
				     'name' => $value, 
				     'directory' => $directory);

	## We store the path of the scenario in the sstructure
	## Later &Scenario::request_action() will look for the scenario in %Scenario::all_scenarios through Scenario::new()
	$value = {'file_path' => $scenario->{'file_path'},
		  'name' => $scenario->{'name'}};
    }elsif ($p->{'task'}) {
	$value = {'name' => $value};
    }

    ## Do we need to split param if it is not already an array
    if (($p->{'occurrence'} =~ /n$/)
	&& $p->{'split_char'}
	&& !(ref($value) eq 'ARRAY')) {
	my @array = split /$p->{'split_char'}/, $value;
	foreach my $v (@array) {
	    $v =~ s/^\s*(.+)\s*$/$1/g;
	}
	
	return \@array;
    }else {
	return $value;
    }
}


## Load the certificat file
sub get_cert {

    my $self = shift;
    my $format = shift;

    ## Default format is PEM (can be DER)
    $format ||= 'pem';

    &Log::do_log('debug2', 'List::load_cert(%s)',$self->{'name'});

    # we only send the encryption certificate: this is what the user
    # needs to send mail to the list; if he ever gets anything signed,
    # it will have the respective cert attached anyways.
    # (the problem is that netscape, opera and IE can't only
    # read the first cert in a file)
    my($certs,$keys) = tools::smime_find_keys($self->{dir},'encrypt');

    my @cert;
    if ($format eq 'pem') {
	unless(open(CERT, $certs)) {
	    &Log::do_log('err', "List::get_cert(): Unable to open $certs: $!");
	    return undef;
	}
	
	my $state;
	while(<CERT>) {
	    chomp;
	    if($state == 1) {
		# convert to CRLF for windows clients
		push(@cert, "$_\r\n");
		if(/^-+END/) {
		    pop @cert;
		    last;
		}
	    }elsif (/^-+BEGIN/) {
		$state = 1;
	    }
	}
	close CERT ;
    }elsif ($format eq 'der') {
	unless (open CERT, "$Conf::Conf{'openssl'} x509 -in $certs -outform DER|") {
	    &Log::do_log('err', "$Conf::Conf{'openssl'} x509 -in $certs -outform DER|");
	    &Log::do_log('err', "List::get_cert(): Unable to open get $certs in DER format: $!");
	    return undef;
	}

	@cert = <CERT>;
	close CERT;
    }else {
	&Log::do_log('err', "List::get_cert(): unknown '$format' certificate format");
	return undef;
    }
    
    return @cert;
}

## Load a config file of a list
sub _load_list_config_file {
    my ($directory,$robot, $file) = @_;
    &Log::do_log('debug3', '(%s, %s, %s)', $directory, $robot, $file);

    my $config_file = $directory.'/'.$file;

    my %admin;
    my (@paragraphs);

    ## Just in case...
    local $/ = "\n";

    ## Set defaults to 1
    foreach my $pname (keys %::pinfo) {
	$admin{'defaults'}{$pname} = 1 unless ($::pinfo{$pname}{'internal'});
    }

    ## Lock file
    my $lock = new Lock ($config_file);
    unless (defined $lock) {
	&Log::do_log('err','Could not create new lock on %s',$config_file);
	return undef;
    }
    $lock->set_timeout(5); 
    unless ($lock->lock('read')) {
	&Log::do_log('err','Could not put a read lock on the config file %s',$config_file);
	return undef;
    }   

    unless (open CONFIG, "<", $config_file) {
	&Log::do_log('info', 'Cannot open %s', $config_file);
    }

    ## Split in paragraphs
    my $i = 0;
    while (<CONFIG>) {
	if (/^\s*$/) {
	    $i++ if $paragraphs[$i];
	}else {
	    push @{$paragraphs[$i]}, $_;
	}
    }

    for my $index (0..$#paragraphs) {
	my @paragraph = @{$paragraphs[$index]};

	my $pname;

	## Clean paragraph, keep comments
	for my $i (0..$#paragraph) {
	    my $changed = undef;
	    for my $j (0..$#paragraph) {
		if ($paragraph[$j] =~ /^\s*\#/) {
		    chomp($paragraph[$j]);
		    push @{$admin{'comment'}}, $paragraph[$j];
		    splice @paragraph, $j, 1;
		    $changed = 1;
		}elsif ($paragraph[$j] =~ /^\s*$/) {
		    splice @paragraph, $j, 1;
		    $changed = 1;
		}

		last if $changed;
	    }

	    last unless $changed;
	}

	## Empty paragraph
	next unless ($#paragraph > -1);
	
	## Look for first valid line
	unless ($paragraph[0] =~ /^\s*([\w-]+)(\s+.*)?$/) {
	    &Log::do_log('err', 'Bad paragraph "%s" in %s, ignore it', @paragraph, $config_file);
	    next;
	}
	    
	$pname = $1;

	## Parameter aliases (compatibility concerns)
	if (defined $alias{$pname}) {
	    $paragraph[0] =~ s/^\s*$pname/$alias{$pname}/;
	    $pname = $alias{$pname};
	}
	
	unless (defined $::pinfo{$pname}) {
	    &Log::do_log('err', 'Unknown parameter "%s" in %s, ignore it', $pname, $config_file);
	    next;
	}

	## Uniqueness
	if (defined $admin{$pname}) {
	    unless (($::pinfo{$pname}{'occurrence'} eq '0-n') or
		    ($::pinfo{$pname}{'occurrence'} eq '1-n')) {
		&Log::do_log('err', 'Multiple occurences of a unique parameter "%s" in %s', $pname, $config_file);
	    }
	}
	
	## Line or Paragraph
	if (ref $::pinfo{$pname}{'file_format'} eq 'HASH') {
	    ## This should be a paragraph
	    unless ($#paragraph > 0) {
		&Log::do_log('err', 'Expecting a paragraph for "%s" parameter in %s, ignore it', $pname, $config_file);
		next;
	    }
	    
	    ## Skipping first line
	    shift @paragraph;

	    my %hash;
	    for my $i (0..$#paragraph) {	    
		next if ($paragraph[$i] =~ /^\s*\#/);
		
		unless ($paragraph[$i] =~ /^\s*(\w+)\s*/) {
		    &Log::do_log('err', 'Bad line "%s" in %s',$paragraph[$i], $config_file);
		}
		
		my $key = $1;
		
		unless (defined $::pinfo{$pname}{'file_format'}{$key}) {
		    &Log::do_log('err', 'Unknown key "%s" in paragraph "%s" in %s', $key, $pname, $config_file);
		    next;
		}
		
		unless ($paragraph[$i] =~ /^\s*$key\s+($::pinfo{$pname}{'file_format'}{$key}{'file_format'})\s*$/i) {
		    chomp($paragraph[$i]);
		    &Log::do_log('err', 'Bad entry "%s" for key "%s", paragraph "%s" in file "%s"', $paragraph[$i], $key, $pname, $config_file);
		    next;
		}

		$hash{$key} = &_load_list_param($robot,$key, $1, $::pinfo{$pname}{'file_format'}{$key}, $directory);
	    }

	    ## Apply defaults & Check required keys
	    my $missing_required_field;
	    foreach my $k (keys %{$::pinfo{$pname}{'file_format'}}) {

		## Default value
		unless (defined $hash{$k}) {
		    if (defined $::pinfo{$pname}{'file_format'}{$k}{'default'}) {
			$hash{$k} = &_load_list_param($robot,$k, 'default', $::pinfo{$pname}{'file_format'}{$k}, $directory);
		    }
		}

		## Required fields
		if ($::pinfo{$pname}{'file_format'}{$k}{'occurrence'} eq '1') {
		    unless (defined $hash{$k}) {
			&Log::do_log('info', 'Missing key "%s" in param "%s" in %s', $k, $pname, $config_file);
			$missing_required_field++;
		    }
		}
	    }

	    next if $missing_required_field;

	    delete $admin{'defaults'}{$pname};

	    ## Should we store it in an array
	    if (($::pinfo{$pname}{'occurrence'} =~ /n$/)) {
		push @{$admin{$pname}}, \%hash;
	    }else {
		$admin{$pname} = \%hash;
	    }
	}else {
	    ## This should be a single line
	    unless ($#paragraph == 0) {
		&Log::do_log('info', 'Expecting a single line for "%s" parameter in %s', $pname, $config_file);
	    }

	    unless ($paragraph[0] =~ /^\s*$pname\s+($::pinfo{$pname}{'file_format'})\s*$/i) {
		chomp($paragraph[0]);
		&Log::do_log('info', 'Bad entry "%s" in %s', $paragraph[0], $config_file);
		next;
	    }

	    my $value = &_load_list_param($robot,$pname, $1, $::pinfo{$pname}, $directory);

	    delete $admin{'defaults'}{$pname};

	    if (($::pinfo{$pname}{'occurrence'} =~ /n$/)
		&& ! (ref ($value) =~ /^ARRAY/)) {
		push @{$admin{$pname}}, $value;
	    }else {
		$admin{$pname} = $value;
	    }
	}
    }
    
    close CONFIG;

    ## Release the lock
    unless ($lock->unlock()) {
	&Log::do_log('err', 'Could not remove the read lock on file %s',$config_file);
	return undef;
    }

    ## Apply defaults & check required parameters
    foreach my $p (keys %::pinfo) {

	## Defaults
	unless (defined $admin{$p}) {

	    ## Simple (versus structured) parameter case
	    if (defined $::pinfo{$p}{'default'}) {
		$admin{$p} = &_load_list_param($robot,$p, $::pinfo{$p}{'default'}, $::pinfo{$p}, $directory);

	    ## Sructured parameters case : the default values are defined at the next level
	    }elsif ((ref $::pinfo{$p}{'format'} eq 'HASH')
		    && ($::pinfo{$p}{'occurrence'} =~ /1$/)) {
		## If the paragraph is not defined, try to apply defaults
		my $hash;
		
		foreach my $key (keys %{$::pinfo{$p}{'format'}}) {

		    ## Skip keys without default value.
		    unless (defined $::pinfo{$p}{'format'}{$key}{'default'}) {
			next;
		    }
		    
		    $hash->{$key} = &_load_list_param($robot,$key, $::pinfo{$p}{'format'}{$key}{'default'}, $::pinfo{$p}{'format'}{$key}, $directory);
		}

		$admin{$p} = $hash if (defined $hash);

	    }

#	    $admin{'defaults'}{$p} = 1;
	}
	
	## Required fields
	if ($::pinfo{$p}{'occurrence'} =~ /^1(-n)?$/ ) {
	    unless (defined $admin{$p}) {
		&Log::do_log('info','Missing parameter "%s" in %s', $p, $config_file);
	    }
	}
    }

    ## "Original" parameters
    if (defined ($admin{'digest'})) {
	if ($admin{'digest'} =~ /^(.+)\s+(\d+):(\d+)$/) {
	    my $digest = {};
	    $digest->{'hour'} = $2;
	    $digest->{'minute'} = $3;
	    my $days = $1;
	    $days =~ s/\s//g;
	    @{$digest->{'days'}} = split /,/, $days;

	    $admin{'digest'} = $digest;
	}
    }
    # The 'host' parameter is ignored if the list is stored on a 
    #  virtual robot directory
   
    # $admin{'host'} = $self{'domain'} if ($self{'dir'} ne '.'); 

	
    if (defined ($admin{'custom_subject'})) {
	if ($admin{'custom_subject'} =~ /^\s*\[\s*(\w+)\s*\]\s*$/) {
	    $admin{'custom_subject'} = $1;
	}
    }

    ## Format changed for reply_to parameter
    ## New reply_to_header parameter
    if (($admin{'forced_reply_to'} && ! $admin{'defaults'}{'forced_reply_to'}) ||
	($admin{'reply_to'} && ! $admin{'defaults'}{'reply_to'})) {
	my ($value, $apply, $other_email);
	$value = $admin{'forced_reply_to'} || $admin{'reply_to'};
	$apply = 'forced' if ($admin{'forced_reply_to'});
	if ($value =~ /\@/) {
	    $other_email = $value;
	    $value = 'other_email';
	}

	$admin{'reply_to_header'} = {'value' => $value,
				     'other_email' => $other_email,
				     'apply' => $apply};

	## delete old entries
	$admin{'reply_to'} = undef;
	$admin{'forced_reply_to'} = undef;
    }

    ############################################
    ## Below are constraints between parameters
    ############################################

    ## Do we have a database config/access
    unless ($SDM::use_db) {
		&Log::do_log('info', 'Sympa not setup to use DBI or no database access');
		## We should notify the listmaster here...
		#return undef;
    }

    ## This default setting MUST BE THE LAST ONE PERFORMED
#    if ($admin{'status'} ne 'open') {
#	## requested and closed list are just list hidden using visibility parameter
#	## and with send parameter set to closed.
#	$admin{'send'} = &_load_list_param('.','send', 'closed', $::pinfo{'send'}, $directory);
#	$admin{'visibility'} = &_load_list_param('.','visibility', 'conceal', $::pinfo{'visibility'}, $directory);
#    }

    ## reception of default_user_options must be one of reception of
    ## available_user_options. If none, warning and put reception of
    ## default_user_options in reception of available_user_options
    if (! grep (/^$admin{'default_user_options'}{'reception'}$/,
		@{$admin{'available_user_options'}{'reception'}})) {
      push @{$admin{'available_user_options'}{'reception'}}, $admin{'default_user_options'}{'reception'};
      &Log::do_log('info','reception is not compatible between default_user_options and available_user_options in %s',$directory);
    }

    return \%admin;
}

## Save a config file
sub _save_list_config_file {
    my ($config_file, $old_config_file, $admin) = @_;
    &Log::do_log('debug3', '(%s, %s, %s)', $config_file,$old_config_file, $admin);

    unless (rename $config_file, $old_config_file) {
	&Log::do_log('notice', 'Cannot rename %s to %s', $config_file, $old_config_file);
	return undef;
    }

    unless (open CONFIG, ">", $config_file) {
	&Log::do_log('info', 'Cannot open %s', $config_file);
	return undef;
    }
    my $config = '';
    my $fd = new IO::Scalar \$config;
    
    foreach my $c (@{$admin->{'comment'}}) {
	$fd->print(sprintf "%s\n", $c);
    }
    $fd->print("\n");

    foreach my $key (sort by_order keys %{$admin}) {

	next if ($key =~ /^(comment|defaults)$/);
	next unless (defined $admin->{$key});

	## Multiple parameter (owner, custom_header,...)
	if ((ref ($admin->{$key}) eq 'ARRAY') &&
	    ! $::pinfo{$key}{'split_char'}) {
	    foreach my $elt (@{$admin->{$key}}) {
		&_save_list_param($key, $elt, $admin->{'defaults'}{$key}, $fd);
	    }
	}else {
	    &_save_list_param($key, $admin->{$key}, $admin->{'defaults'}{$key}, $fd);
	}

    }
    print CONFIG $config;
    close CONFIG;

    return 1;
}

# Is a reception mode in the parameter reception of the available_user_options
# section?
sub is_available_reception_mode {
  my ($self,$mode) = @_;
  $mode =~ y/[A-Z]/[a-z]/;
  
  return undef unless ($self && $mode);

  my @available_mode = @{$self->{'admin'}{'available_user_options'}{'reception'}};
  
  foreach my $m (@available_mode) {
    if ($m eq $mode) {
      return $mode;
    }
  }

  return undef;
}

# List the parameter reception of the available_user_options section 
sub available_reception_mode {
  my $self = shift;
  
  return join (' ',@{$self->{'admin'}{'available_user_options'}{'reception'}});
}

########################################################################################
#                       FUNCTIONS FOR MESSAGE TOPICS                                   #
########################################################################################
#                                                                                      #
#                                                                                      #


####################################################
# is_there_msg_topic
####################################################
#  Test if some msg_topic are defined
# 
# IN : -$self (+): ref(List)
#      
# OUT : 1 - some are defined | 0 - not defined
####################################################
sub is_there_msg_topic {
    my ($self) = shift;
    
    if (defined $self->{'admin'}{'msg_topic'}) {
	if (ref($self->{'admin'}{'msg_topic'}) eq "ARRAY") {
	    if ($#{$self->{'admin'}{'msg_topic'}} >= 0) {
		return 1;
	    }
	}
    }
    return 0;
}

 
####################################################
# is_available_msg_topic
####################################################
#  Checks for a topic if it is available in the list
# (look foreach list parameter msg_topic.name)
# 
# IN : -$self (+): ref(List)
#      -$topic (+): string
# OUT : -$topic if it is available  | undef
####################################################
sub is_available_msg_topic {
    my ($self,$topic) = @_;
    
    my @available_msg_topic;
    foreach my $msg_topic (@{$self->{'admin'}{'msg_topic'}}) {
	return $topic
	    if ($msg_topic->{'name'} eq $topic);
    }
    
    return undef;
}


####################################################
# get_available_msg_topic
####################################################
#  Return an array of available msg topics (msg_topic.name)
# 
# IN : -$self (+): ref(List)
#
# OUT : -\@topics : ref(ARRAY)
####################################################
sub get_available_msg_topic {
    my ($self) = @_;
    
    my @topics;
    foreach my $msg_topic (@{$self->{'admin'}{'msg_topic'}}) {
	if ($msg_topic->{'name'}) {
	    push @topics,$msg_topic->{'name'};
	}
    }
    
    return \@topics;
}

####################################################
# is_msg_topic_tagging_required
####################################################
# Checks for the list parameter msg_topic_tagging
# if it is set to 'required'
#
# IN : -$self (+): ref(List)
#
# OUT : 1 - the msg must must be tagged 
#       | 0 - the msg can be no tagged
####################################################
sub is_msg_topic_tagging_required {
    my ($self) = @_;
    
    if ($self->{'admin'}{'msg_topic_tagging'} =~ /required/) {
	return 1;
    } else {
	return 0;
    }
}

####################################################
# automatic_tag
####################################################
#  Compute the topic(s) of the message and tag it.
#
# IN : -$self (+): ref(List)
#      -$msg (+): ref(MIME::Entity)
#      -$robot (+): robot
#
# OUT : string of tag(s), can be separated by ',', can be empty
#        | undef 
####################################################
sub automatic_tag {
    my ($self,$msg,$robot) = @_;
    my $msg_id = $msg->head->get('Message-ID');
    chomp($msg_id);
    &Log::do_log('debug3','automatic_tag(%s,%s)',$self->{'name'},$msg_id);


    my $topic_list = $self->compute_topic($msg,$robot);

    if ($topic_list) {
	unless ($self->tag_topic($msg_id,$topic_list,'auto')) {
	    &Log::do_log('err','Unable to tag message %s with topic "%s"',$msg_id,$topic_list);
	    return undef;
	}
    } 
	
    return $topic_list;
}


####################################################
# compute_topic
####################################################
#  Compute the topic of the message. The topic is got
#  from applying a regexp on the message, regexp 
#  based on keywords defined in list_parameter
#  msg_topic.keywords. The regexp is applied on the 
#  subject and/or the body of the message according
#  to list parameter msg_topic_keywords_apply_on
#
# IN : -$self (+): ref(List)
#      -$msg (+): ref(MIME::Entity)
#      -$robot(+) : robot
#
# OUT : string of tag(s), can be separated by ',', can be empty
####################################################
sub compute_topic {
    my ($self,$msg,$robot) = @_;
    my $msg_id = $msg->head->get('Message-ID');
    chomp($msg_id);
    &Log::do_log('debug3','compute_topic(%s,%s)',$self->{'name'},$msg_id);
    my @topic_array;
    my %topic_hash;
    my %keywords;


    ## TAGGING INHERITED BY THREAD
    # getting reply-to
    my $reply_to = $msg->head->get('In-Reply-To');
    my $info_msg_reply_to = $self->load_msg_topic($reply_to,$robot);

    # is msg reply to already tagged?	
    if (ref($info_msg_reply_to) eq "HASH") { 
	return $info_msg_reply_to->{'topic'};
    }
     
    ## TAGGING BY KEYWORDS
    # getting keywords
    foreach my $topic (@{$self->{'admin'}{'msg_topic'}}) {

	my $list_keyw = &tools::get_array_from_splitted_string($topic->{'keywords'});

	foreach my $keyw (@{$list_keyw}) {
	    $keywords{$keyw} = $topic->{'name'}
	}
    }

    # getting string to parse
    # We convert it to Unicode for case-ignore match with non-ASCII keywords.
    my $mail_string = '';
    if ($self->{'admin'}{'msg_topic_keywords_apply_on'} eq 'subject'){
	$mail_string = Encode::decode_utf8(&tools::decode_header($msg, 'Subject'))."\n";
    }
    unless ($self->{'admin'}{'msg_topic_keywords_apply_on'} eq 'subject') {
	# get bodies of any text/* parts, not digging nested subparts.
	my @parts;
	if ($msg->effective_type =~ /^(multipart|message)\//i) {
	    @parts = $msg->parts();
	} else {
	    @parts = ($msg);
	}
	foreach my $part (@parts) {
	    next unless $part->effective_type =~ /^text\//i;
	    my $charset = $part->head->mime_attr("Content-Type.Charset");
	    $charset = MIME::Charset->new($charset);
	    if (defined $part->bodyhandle) {
		my $body = $part->bodyhandle->as_string();
		my $converted;
		eval {
		    $converted = $charset->decode($body);
		};
		if ($@) {
		    $converted = Encode::decode('US-ASCII', $body);
		}
		$mail_string .= $converted."\n";
	    }
	}
    }

    # parsing
    foreach my $keyw (keys %keywords) {
	my $k = $keywords{$keyw};
	$keyw = Encode::decode_utf8($keyw);
	$keyw = &tools::escape_regexp($keyw);
	if ($mail_string =~ /$keyw/i){
	    $topic_hash{$k} = 1;
	}
    }


    
    # for no double
    foreach my $k (keys %topic_hash) {
	push @topic_array,$k if ($topic_hash{$k});
    }
    
    if ($#topic_array <0) {
	return '';

    } else {
	return (join(',',@topic_array));
    }
}

####################################################
# tag_topic
####################################################
#  tag the message by creating the msg topic file
# 
# IN : -$self (+): ref(List)
#      -$msg_id (+): string, msg_id of the msg to tag
#      -$topic_list (+): string (splitted by ',')
#      -$method (+) : 'auto'|'editor'|'sender'
#         the method used for tagging
#
# OUT : string - msg topic messagekey
#       | undef
####################################################
sub tag_topic {
    my ($self,$msg_id,$topic_list,$method) = @_;
    &Log::do_log('debug3','tag_topic(%s,%s,"%s",%s)',$self->{'name'},$msg_id,$topic_list,$method);

    my $topic_item =  sprintf  "TOPIC   $topic_list\n";
    $topic_item .= sprintf  "METHOD  $method\n";
    my $topicspool = new Sympaspool ('topic');
    
    return ($topicspool->store($topic_item,{ 'list' => $self->name, 'robot' => $self->domain, 'messageid' => $msg_id }));
}



####################################################
# load_msg_topic
####################################################
#  Looks for a msg topic using the msg_id of 
# the message, loads it and return contained information 
# in a HASH
#
# IN : -$self (+): ref(List)
#      -$msg_id (+): the message ID 
#      -$robot (+): the robot
#
# OUT : ref(HASH) file contents : 
#         - topic : string - list of topic name(s)
#         - method : editor|sender|auto - method used to tag
#         - msg_id : the msg_id
#         - filename : name of the file containing this information 
#     | undef 
####################################################
sub load_msg_topic {
    my ($self,$msg_id,$robot) = @_;

    &Log::do_log('debug','List::load_msg_topic(%s,%s)',$self->{'name'},$msg_id);    
    my  $topicspool = new Sympaspool('topic');

    my $topics_from_spool = $topicspool->get_message({'listname' => $self->name, 'robot' => $robot, 'messageid' => $msg_id});
    unless ($topics_from_spool) {
	&Log::do_log('debug','No topic define ; unable to find topic for message %s / list  %s', $msg_id,$self->{'name'});
	return undef;
    }
    
    my %info = ();
    
    my @topics = split(/\n/,$topics_from_spool->{'messageasstring'});
    foreach my $topic (@topics) {
	next if ($topic =~ /^\s*(\#.*|\s*)$/);
	
	if ($topic =~/^(\S+)\s+(.+)$/io) {
	    my($keyword, $value) = ($1, $2);
	    $value =~ s/\s*$//;
	    
	    if ($keyword eq 'TOPIC') {
		$info{'topic'} = $value;
		
	    }elsif ($keyword eq 'METHOD') {
		if ($value =~ /^(editor|sender|auto)$/) {
		    $info{'method'} = $value;
		}else {
		    &Log::do_log('err','List::load_msg_topic(%s,%s): syntax error in record %s@%s : %s', $$self->{'name'},$robot,$msg_id);
		    return undef;
		}
	    }
	}
    }
    
    if ((exists $info{'topic'}) && (exists $info{'method'})) {
	$info{'msg_id'} = $msg_id;
	$info{'messagekey'} = $topics_from_spool->{'messagekey'};	
	return \%info;
    }
    return undef;
}


####################################################
# modifying_msg_topic_for_list_members()
####################################################
#  Deletes topics subscriber that does not exist anymore
#  and send a notify to concerned subscribers.
# 
# IN : -$self (+): ref(List)
#      -$new_msg_topic (+): ref(ARRAY) - new state 
#        of msg_topic parameters
#
# OUT : -0 if no subscriber topics have been deleted
#       -1 if some subscribers topics have been deleted 
##################################################### 
sub modifying_msg_topic_for_list_members(){
    my ($self,$new_msg_topic) = @_;
    &Log::do_log('debug3',"($self->{'name'}");
    my $deleted = 0;

    my @old_msg_topic_name;
    foreach my $msg_topic (@{$self->{'admin'}{'msg_topic'}}) {
	push @old_msg_topic_name,$msg_topic->{'name'};
    }

    my @new_msg_topic_name;
    foreach my $msg_topic (@{$new_msg_topic}) {
	push @new_msg_topic_name,$msg_topic->{'name'};
    }

    my $msg_topic_changes = &tools::diff_on_arrays(\@old_msg_topic_name,\@new_msg_topic_name);

    if ($#{$msg_topic_changes->{'deleted'}} >= 0) {
	
	for (my $subscriber=$self->get_first_list_member(); $subscriber; $subscriber=$self->get_next_list_member()) {
	    
	    if ($subscriber->{'reception'} eq 'mail') {
		my $topics = &tools::diff_on_arrays($msg_topic_changes->{'deleted'},&tools::get_array_from_splitted_string($subscriber->{'topics'}));
		
		if ($#{$topics->{'intersection'}} >= 0) {
		    my $wwsympa_url = &Conf::get_robot_conf($self->{'domain'}, 'wwsympa_url');
		    unless ($self->send_notify_to_user('deleted_msg_topics',$subscriber->{'email'},
						       {'del_topics' => $topics->{'intersection'},
							'url' => $wwsympa_url.'/suboptions/'.$self->{'name'}})) {
			&Log::do_log('err',"($self->{'name'}) : impossible to send notify to user about 'deleted_msg_topics'");
		    }
		    unless ($self->update_list_member(lc($subscriber->{'email'}), 
					       {'update_date' => time,
						'topics' => join(',',@{$topics->{'added'}})})) {
			&Log::do_log('err',"($self->{'name'} : impossible to update user '$subscriber->{'email'}'");
		    }
		    $deleted = 1;
		}
	    }
	}
    }
    return 1 if ($deleted);
    return 0;
}

####################################################
# select_list_members_for_topic
####################################################
# Select users subscribed to a topic that is in
# the topic list incoming when reception mode is 'mail', 'notice', 'not_me', 'txt', 'html' or 'urlize', and the other
# subscribers (recpetion mode different from 'mail'), 'mail' and no topic subscription
# 
# IN : -$self(+) : ref(List)
#      -$string_topic(+) : string splitted by ','
#                          topic list
#      -$subscribers(+) : ref(ARRAY) - list of subscribers(emails)
#
# OUT : @selected_users
#     
#
####################################################
sub select_list_members_for_topic {
    my ($self,$string_topic,$subscribers) = @_;
    &Log::do_log('debug3', '(%s, %s)', $self->{'name'},$string_topic); 
    
    my @selected_users;
    my $msg_topics;

    if ($string_topic) {
	$msg_topics = &tools::get_array_from_splitted_string($string_topic);
    }

    foreach my $user (@$subscribers) {

	# user topic
	my $info_user = $self->get_list_member($user);

	if ($info_user->{'reception'} !~ /^(mail|notice|not_me|txt|html|urlize)$/i) {
	    push @selected_users,$user;
	    next;
	}
	unless ($info_user->{'topics'}) {
	    push @selected_users,$user;
	    next;
	}
	my $user_topics = &tools::get_array_from_splitted_string($info_user->{'topics'});

	if ($string_topic) {
	    my $result = &tools::diff_on_arrays($msg_topics,$user_topics);
	    if ($#{$result->{'intersection'}} >=0 ) {
		push @selected_users,$user;
	    }
	}else {
	    my $result = &tools::diff_on_arrays(['other'],$user_topics);
	    if ($#{$result->{'intersection'}} >=0 ) {
		push @selected_users,$user;
	    }
	}
    }
    return @selected_users;
}

#                                                                                         #
#                                                                                         # 
#                                                                                         #
########## END - functions for message topics #############################################




sub _urlize_part {
    my $message = shift;
    my $list = shift;
    my $expl = $list->{'dir'}.'/urlized';
    my $robot = $list->{'domain'};
    my $dir = shift;
    my $i = shift;
    my $mime_types = shift;
    my $listname = $list->{'name'};
    my $wwsympa_url = shift;

    my $head = $message->head ;
    my $encoding = $head->mime_encoding ;

    ##  name of the linked file
    my $fileExt = $mime_types->{$head->mime_type};
    if ($fileExt) {
	$fileExt = '.'.$fileExt;
    }
    my $filename;

    if ($head->recommended_filename) {
	$filename = $head->recommended_filename;
    } else {
        if ($head->mime_type =~ /multipart\//i) {
          my $content_type = $head->get('Content-Type');
          $content_type =~ s/multipart\/[^;]+/multipart\/mixed/g;
          $message->head->replace('Content-Type', $content_type);
          my @parts = $message->parts();
          foreach my $i (0..$#parts) {
              my $entity = &_urlize_part ($message->parts ($i), $list, $dir, $i, $mime_types,  &Conf::get_robot_conf($robot, 'wwsympa_url')) ;
              if (defined $entity) {
                $parts[$i] = $entity;
              }
          }
          ## Replace message parts
          $message->parts (\@parts);
        }
        $filename ="msg.$i".$fileExt;
    }
  
    ##create the linked file 	
    ## Store body in file 
    if (open OFILE, ">$expl/$dir/$filename") {
	my $ct = $message->effective_type || 'text/plain';
	printf OFILE "Content-type: %s", $ct;
	printf OFILE "; Charset=%s", $head->mime_attr('Content-Type.Charset')
	    if $head->mime_attr('Content-Type.Charset') =~ /\S/;
	print OFILE "\n\n";
    } else {
	&Log::do_log('notice', "Unable to open $expl/$dir/$filename") ;
	return undef ; 
    }
    
    if ($encoding =~ /^(binary|7bit|8bit|base64|quoted-printable|x-uu|x-uuencode|x-gzip64)$/ ) {
	open TMP, ">$expl/$dir/$filename.$encoding";
	$message->print_body (\*TMP);
	close TMP;

	open BODY, "$expl/$dir/$filename.$encoding";
	my $decoder = new MIME::Decoder $encoding;
	$decoder->decode(\*BODY, \*OFILE);
	unlink "$expl/$dir/$filename.$encoding";
    }else {
	$message->print_body (\*OFILE) ;
    }
    close (OFILE);
    my $file = "$expl/$dir/$filename";
    my $size = (-s $file);

    ## Only URLize files with a moderate size
    if ($size < $Conf::Conf{'urlize_min_size'}) {
	unlink "$expl/$dir/$filename";
	return undef;
    }
	    
    ## Delete files created twice or more (with Content-Type.name and Content-Disposition.filename)
    $message->purge ;	

    (my $file_name = $filename) =~ s/\./\_/g;
    my $file_url = "$wwsympa_url/attach/$listname".&tools::escape_chars("$dir/$filename",'/'); # do NOT escape '/' chars

    my $parser = new MIME::Parser;
    $parser->output_to_core(1);
    my $new_part;

    my $lang = &Language::GetLang();
    my $charset = &Language::GetCharset();

    my $tt2_include_path = &tools::make_tt2_include_path($robot,'mail_tt2',$lang,$list);

    &tt2::parse_tt2({'file_name' => $file_name,
		     'file_url'  => $file_url,
		     'file_size' => $size ,
		     'charset' => $charset},
		    'urlized_part.tt2',
		    \$new_part,
		    $tt2_include_path);

    my $entity = $parser->parse_data(\$new_part);

    return $entity;
}

sub store_subscription_request {
    &Log::do_log('debug2', '(%s, %s, %s, %s)', @_);
    my ($self, $email, $gecos, $custom_attr) = @_;

    my $subscription_request_spool = new Sympaspool ('subscribe');
    
    if ($subscription_request_spool->get_content({ 'selector' =>{ 'list' => $self->name, 'robot' => $self->domain, 'sender'=>$email },'selection'=>'count' }) != 0) {
	&Log::do_log('notice', 'Subscription already requested by %s', $email);
	return undef;
    }else{
	my $subrequest = sprintf "$gecos||$custom_attr\n";
	$subscription_request_spool->store($subrequest,{'list' => $self->name, 'robot' => $self->domain, 'sender' => $email });
    }
    return 1;
} 

sub get_subscription_requests {
    my ($self) = shift;
    &Log::do_log('debug2', 'List::get_subscription_requests(%s)', $self->{'name'});

    my %subscriptions;

    my $subscription_request_spool = new Sympaspool ('subscribe');
    my @subrequests = $subscription_request_spool->get_content({ 'selector' =>{ 'list' => $self->name, 'robot' => $self->domain }, 'selection'=>'*' });

    foreach my $subrequest ( $subscription_request_spool->get_content({ 'selector' => { 'list' => $self->name, 'robot' => $self->domain }, 'selection'=>'*' })) {

	my $email = $subrequest->{'sender'};
	my $gecos; my $customattributes;
	if ($subrequest->{'messageasstring'} =~ /(.*)\|\|.*$/) {
	    $gecos = $1; $customattributes = $subrequest->{'messageasstring'} ; $customattributes =~ s/^.*\|\|// ; 
	}else{
	    &Log::do_log('err', "Failed to parse subscription request %s",$subrequest->{'messagekey'});
	    next;
	}
	my $user_entry = $self->get_list_member($email, probe => 1);
	 
	if ( defined($user_entry) && ($user_entry->{'subscribed'} == 1)) {
	    &Log::do_log('err','User %s is subscribed to %s already. Deleting subscription request.', $email, $self->{'name'});
	    unless ($subscription_request_spool->remove_message({ 'list' => $self->name, 'robot' => $self->domain, 'sender' => $email })) {
		&Log::do_log('err', 'Could not delete subrequest %s for list %s@%s from %s', $subrequest->{'messagekey'}, $self->name, $self->domain, $subrequest->{'sender'});
	    }
	    next;
	}
	## Following lines may contain custom attributes in an XML format
	my $xml = &parseCustomAttribute($customattributes) ;
	
	$subscriptions{$email} = {'gecos' => $gecos,
				  'custom_attribute' => $xml};
	unless($subscriptions{$email}{'gecos'}) {
		my $user = get_global_user($email);
		if ($user->{'gecos'}) {
			$subscriptions{$email}{'gecos'} = $user->{'gecos'};
		}
	}
	$subscriptions{$email}{'date'} = $subrequest->{'date'};
    }

    return \%subscriptions;
} 

sub get_subscription_request_count {
    my ($self) = shift;

    my $subscription_request_spool = new Sympaspool ('subscribe');    
    return $subscription_request_spool->get_content({ 'selector' => { 'list' => $self->name, 'robot' => $self->domain }, 'selection'=>'count' });
} 


sub delete_subscription_request {
    my ($self, @list_of_email) = @_;
    &Log::do_log('debug2', 'List::delete_subscription_request(%s, %s)', $self->{'name'}, join(',',@list_of_email));

    my $subscription_request_spool = new Sympaspool ('subscribe');

    my $removed = 0;
    foreach my $email (@list_of_email) {
	$removed++ if  $subscription_request_spool->remove_message({ 'list' => $self->name, 'robot' => $self->domain, 'sender' => $email });	
    }

    unless ($removed > 0) {
	&Log::do_log('debug2', 'No pending subscription was found for users %s', join(',',@list_of_email));
	return undef;
    }
    return 1;
} 


sub get_shared_size {
    my $self = shift;

    return tools::get_dir_size("$self->{'dir'}/shared");
}

sub get_arc_size {
    my $self = shift;
    my $dir = shift;

    return tools::get_dir_size($dir.'/'.$self->get_list_id());
}

# return the date epoch for next delivery planified for a list
sub  get_next_delivery_date {
    my $self = shift;

    my $dtime = $self->{'admin'}{'delivery_time'} ;
    unless ($dtime =~ /(\d?\d)\:(\d\d)/ ) {
	# if delivery _time if not defined, the delivery time right now
	return time();
    }
    my $h = $1;
    my $m = $2;
    unless ((($h == 24)&&($m == 0))||(($h <= 23)&&($m <= 60))){
	&Log::do_log('err',"ignoring wrong parameter format delivery_time, delivery_tile must be smaller than 24:00");
	return time();
    }
    my $date = time();

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime($date);

    my $plannified_time = (($h*60)+$m)*60;       # plannified time in sec
    my $now_time = ((($hour*60)+$min)*60)+$sec;  # Now #sec since to day 00:00
    
    my $result = $date - $now_time + $plannified_time;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime($result);

    if ($now_time <= $plannified_time ) {
	return ( $date - $now_time + $plannified_time) ;
    }else{
	return ( $date - $now_time + $plannified_time + (24*3600)); # plannified time is past so report to tomorrow
    }
}


## Searches the include datasource corresponding to the provided ID
sub search_datasource {
    my ($self, $id) = @_;
    &Log::do_log('debug2','List::search_datasource(%s,%s)', $self->{'name'}, $id);

    ## Go through list parameters
    foreach my $p (keys %{$self->{'admin'}}) {
	next unless ($p =~ /^include/);
	
	## Go through sources
	foreach my $s (@{$self->{'admin'}{$p}}) {
	    if (&Datasource::_get_datasource_id($s) eq $id) {
		return {'type' => $p, 'def' => $s};
	    }
	}
    }

    return undef;
}

## Return the names of datasources, given a coma-separated list of source ids
# IN : -$class 
#      -$id : datasource ids (coma-separated)
# OUT : -$name : datasources names (scalar)
sub get_datasource_name {
    my ($self, $id) = @_;
    &Log::do_log('debug2','(%s,%s)', $self->{'name'}, $id);
    my %sources;

    my @ids = split /,/,$id;
    foreach my $id (@ids) {
	## User may come twice from the same datasource
	unless (defined ($sources{$id})) {
	    my $datasource = $self->search_datasource($id);
	    if (defined $datasource) {
		if (ref($datasource->{'def'})) {
		    $sources{$id} = $datasource->{'def'}{'name'} || $datasource->{'def'}{'host'};
		}else {
		    $sources{$id} = $datasource->{'def'};
		}
	    }
	}
    }
    
    return join(', ', values %sources);
}

## Remove a task in the tasks spool
sub remove_task {
    my $self = shift;
    my $task = shift;

    unless (opendir(DIR, $Conf::Conf{'queuetask'})) {
	&Log::do_log ('err', "error : can't open dir %s: %s", $Conf::Conf{'queuetask'}, $!);
	return undef;
    }
    my @tasks = grep !/^\.\.?$/, readdir DIR;
    closedir DIR;

    foreach my $task_file (@tasks) {
	if ($task_file =~ /^(\d+)\.\w*\.$task\.$self->{'name'}\@$self->{'domain'}$/) {
	    unless (unlink("$Conf::Conf{'queuetask'}/$task_file")) {
		&Log::do_log('err', 'Unable to remove task file %s : %s', $task_file, $!);
		return undef;
	    }
	    &Log::do_log('notice', 'Removing task file %s', $task_file);
	}
    }

    return 1;
}

## Close the list (remove from DB, remove aliases, change status to 'closed' or 'family_closed')
sub close_list {
    &Log::do_log('debug2', '(%s, %s, %s)', @_);
    my ($self, $email, $status) = @_;

    return undef 
	unless $self and $list_of_lists{$self->domain}{$self->name};
    
    ## If list is included by another list, then it cannot be removed
    ## TODO : we should also check owner_include and editor_include, but a bit more tricky
    my $all_lists = get_lists('*');
    foreach my $list (@{$all_lists}) {
	my $included_lists = $list->include_list;
	next unless defined $included_lists;

	foreach my $included_list_name (@{$included_lists}) {
	    if ($included_list_name eq $self->get_list_id() or
		($included_list_name eq $self->name and
		 $list->domain eq $self->domain)) {
		&Log::do_log('err','List %s is included by list %s : cannot close it', $self, $list);
		return undef;
	    }
	}
    }
    
    ## Dump subscribers, unless list is already closed
    unless ($self->status eq 'closed') {
	$self->_save_list_members_file($self->dir.'/subscribers.closed.dump');
    }

    ## Delete users
    my @users;
    for ( my $user = $self->get_first_list_member(); $user; $user = $self->get_next_list_member() ){
	push @users, $user->{'email'};
    }
    $self->delete_list_member('users' => \@users);

    ## Remove entries from admin_table
    foreach my $role ('owner','editor') {
	my @admin_users;
	for ( my $user = $self->get_first_list_admin($role); $user; $user = $self->get_next_list_admin() ){
	    push @admin_users, $user->{'email'};
	}
	$self->delete_list_admin($role, @admin_users);
    }

    ## Change status & save config
    $self->status('closed');

    if (defined $status) {
 	foreach my $s ('family_closed','closed') {
 	    if ($status eq $s) {
 		$self->status($status);
 		last;
 	    }
 	}
    }
    
    $self->{'admin'}{'defaults'}{'status'} = 0;

    $self->save_config($email);
    $self->savestats();
    
    $self->remove_aliases();   

    #log in stat_table to make staistics
    &Log::db_stat_log({ 'robot' => $self->domain, 'list' => $self->name,
		       'operation' => 'close_list', 'parameter' => '',
		       'mail' => $email, 'client' => '',
		       'daemon' => 'damon_name' }); #FIXME: unknown daemon

    return 1;
}

## Remove the list
sub purge {
    my ($self, $email) = @_;

    return undef 
	unless ($self && ($list_of_lists{$self->{'domain'}}{$self->{'name'}}));
    
    ## Remove tasks for this list
    &Task::list_tasks($Conf::Conf{'queuetask'});
    foreach my $task (&Task::get_tasks_by_list($self->get_list_id())) {
	unlink $task->{'filepath'};
    }
    
    ## Close the list first, just in case...
    $self->close_list();

    if ($self->{'name'}) {
	my $arc_dir = &Conf::get_robot_conf($self->{'domain'},'arc_path');
	&tools::remove_dir($arc_dir.'/'.$self->get_list_id());
	&tools::remove_dir($self->get_bounce_dir());
    }
    
    ## Clean list table if needed
    if ($Conf::get_robot_conf{$self->domain, 'cache_list_config'} eq 'database') {
	unless (defined $self->list_cache_purge) {
	    &do_log('err', 'Cannot remove list %s from table', $self);
	}
    }
    
    ## Clean memory cache
    delete $list_of_lists{$self->{'domain'}}{$self->{'name'}};

    &tools::remove_dir($self->{'dir'});

    #log ind stat table to make statistics
    &Log::db_stat_log({ 'robot' => $self->domain, 'list' => $self->name, 'operation' => 'purge list', 'parameter' => '',
		       'mail' => $email, 'client' => '', 'daemon' => 'daemon_name' });
    
    return 1;
}

## Remove list aliases
sub remove_aliases {
    my $self = shift;

    return undef 
	unless ($self && ($list_of_lists{$self->domain}{$self->name})
		&& ($Conf::Conf{'sendmail_aliases'} !~ /^none$/i));
    
    my $alias_manager = $Conf::Conf{'alias_manager'};
    
    unless (-x $alias_manager) {
	&Log::do_log('err','Cannot run alias_manager %s', $alias_manager);
	return undef;
    }
    
    system (sprintf '%s del %s %s', $alias_manager, $self->name, $self->host);
    my $status = $? >> 8;
    unless ($status == 0) {
	&Log::do_log('err','Failed to remove aliases ; status %d : %s', $status, $!);
	return undef;
    }
    
    &Log::do_log('info', 'Aliases for list %s removed successfully', $self);
    
    return 1;
}


##
## bounce management actions
##

# Sub for removing user
#
sub remove_bouncers {
    my $self = shift;
    my $reftab = shift;
    &Log::do_log('debug','List::remove_bouncers(%s)',$self->{'name'});
    
    ## Log removal
    foreach my $bouncer (@{$reftab}) {
	&Log::do_log('notice','Removing bouncing subsrciber of list %s : %s', $self->{'name'}, $bouncer);
    }

    unless ($self->delete_list_member('users' => $reftab, 'exclude' =>' 1')){
      &Log::do_log('info','error while calling sub delete_users');
      return undef;
    }
    return 1;
}

#Sub for notifying users : "Be carefull,You're bouncing"
#
sub notify_bouncers{
    my $self = shift;
    my $reftab = shift;
    &Log::do_log('debug','List::notify_bouncers(%s)', $self->{'name'});

    foreach my $user (@$reftab){
 	&Log::do_log('notice','Notifying bouncing subsrciber of list %s : %s', $self->{'name'}, $user);
	unless ($self->send_notify_to_user('auto_notify_bouncers',$user,{})) {
	    &Log::do_log('notice',"Unable to send notify 'auto_notify_bouncers' to $user");
	}
    }
    return 1;
}

## Create the document repository
sub create_shared {
    my $self = shift;

    my $dir = $self->{'dir'}.'/shared';

    if (-e $dir) {
	&Log::do_log('err',"List::create_shared : %s already exists", $dir);
	return undef;
    }

    unless (mkdir ($dir, 0777)) {
	&Log::do_log('err',"List::create_shared : unable to create %s : %s ", $dir, $!);
	return undef;
    }

    return 1;
}

## check if a list  has include-type data sources
sub has_include_data_sources {
    my $self = shift;

    foreach my $type ('include_file','include_list','include_remote_sympa_list','include_sql_query','include_remote_file',
		      'include_ldap_query','include_ldap_2level_query','include_admin','owner_include','editor_include', 'include_voot_group') {
	if (ref($self->{'admin'}{$type}) eq 'ARRAY' && $#{$self->{'admin'}{$type}} >= 0) {
	    return 1;
	}
    }
    
    return 0
}

# move a message to a queue or distribute spool
sub move_message {
    my ($self, $file, $queue) = @_;
    &Log::do_log('debug2', "List::move_message($file, $self->{'name'}, $queue)");

    my $dir = $queue || $Conf::Conf{'queuedistribute'};    
    my $filename = $self->get_list_id().'.'.time.'.'.int(rand(999));

    unless (open OUT, ">$dir/T.$filename") {
	&Log::do_log('err', 'Cannot create file %s', "$dir/T.$filename");
	return undef;
    }
    
    unless (open IN, $file) {
	&Log::do_log('err', 'Cannot open file %s', $file);
	return undef;
    }
    
    print OUT <IN>; close IN; close OUT;
    unless (rename "$dir/T.$filename", "$dir/$filename") {
	&Log::do_log('err', 'Cannot rename file %s into %s',"$dir/T.$filename","$dir/$filename" );
	return undef;
    }
    return 1;
}

## Return the path to the list bounce directory, where bounces are stored
sub get_bounce_dir {
    my $self = shift;

    my $root_dir = &Conf::get_robot_conf($self->{'domain'}, 'bounce_path');
    
    return $root_dir.'/'.$self->get_list_id();
}

=over 4

=item get_list_address ( [ TYPE ] )

Return the list email address of type TYPE: posting address (default),
"owner", "editor" or (non-VERP) "return_path".

=back

=cut

sub get_list_address {
    my $self = shift;
    my $type = shift || '';

    unless ($type) {
	return $self->name . '@' . $self->host;
    } elsif ($type eq 'owner') {
	return $self->name . '-request' . '@' . $self->host;
    } elsif ($type eq 'editor') {
	return $self->name . '-editor' . '@' . $self->host;
    } elsif ($type eq 'return_path') {
	return $self->name .
	       &Conf::get_robot_conf($self->domain, 'return_path_suffix') .
	       '@' . $self->host;
    }
    &Log::do_log('err', 'Unknown type of list address "%s".  Ask developer',
		 $type);
    return undef;
}

=over 4

=item get_bounce_address ( WHO, [ OPTS, ... ] )

Return the VERP address of the list for the user WHO.

Note that VERP addresses have the name of originating robot, not mail host.

=back

=cut

sub get_bounce_address {
    my $self = shift;
    my $who = shift;
    my @opts = @_;

    my $escwho = $who;
    $escwho =~ s/\@/==a==/;

    return sprintf('%s+%s@%s',
		   $Conf::Conf{'bounce_email_prefix'},
		   join('==', $escwho, $self->name, @opts),
		   $self->domain);
}

=over 4

=item get_list_id ( )

Return the list ID, different from the list address (uses the robot name)

=back

=cut

sub get_list_id {
    my $self = shift;

    ## DO NOT use accessors since $self may not have been fully initialized.

    return '' unless $self->{'name'} and $self->{'domain'};
    return $self->{'name'} . '@' . $self->{'domain'};
}

=over 4

=item add_list_header ( HEADER_OBJ, FIELD )

FIXME @todo doc

=back

=cut

sub add_list_header {
    my $self = shift;
    my $hdr = shift;
    my $field = shift;
    my $robot = $self->domain;

    if ($field eq 'id') {
	$hdr->add('List-Id',
		  sprintf('<%s.%s>', $self->name, $self->host));
    } elsif ($field eq 'help') {
	$hdr->add('List-Help',
		  sprintf('<mailto:%s@%s?subject=help>',
			  &Conf::get_robot_conf($robot, 'email'),
			  &Conf::get_robot_conf($robot, 'host')));
    } elsif ($field eq 'unsubscribe') {
	$hdr->add('List-Unsubscribe',
		  sprintf('<mailto:%s@%s?subject=unsubscribe%%20%s>',
			  &Conf::get_robot_conf($robot, 'email'),
			  &Conf::get_robot_conf($robot, 'host'),
			  $self->name));
    } elsif ($field eq 'subscribe') {
	$hdr->add('List-Subscribe',
		  sprintf('<mailto:%s@%s?subject=subscribe%%20%s>',
			  &Conf::get_robot_conf($robot, 'email'),
			  &Conf::get_robot_conf($robot, 'host'),
			  $self->name));
    } elsif ($field eq 'post') {
	$hdr->add('List-Post',
		  sprintf('<mailto:%s>', $self->get_list_address()));
    } elsif ($field eq 'owner') {
	$hdr->add('List-Owner',
		  sprintf('<mailto:%s>', $self->get_list_address('owner')));
    } elsif ($field eq 'archive') {
	if (&Conf::get_robot_conf($robot, 'wwsympa_url') and
	    $self->is_web_archived()) {
	    $hdr->add('List-Archive',
		      sprintf ('<%s/arc/%s>',
			       &Conf::get_robot_conf($robot, 'wwsympa_url'),
			       $self->name));
	} else {
	    return 0;
	}
    } elsif ($field eq 'archived_at') {
	if (&Conf::get_robot_conf($robot, 'wwsympa_url') and
	    $self->is_web_archived()) {
	    my @now = localtime(time);
	    my $yyyy = sprintf '%04d', 1900+$now[5];
	    my $mm = sprintf '%02d', $now[4]+1;
	    my $archived_msg_url =
		sprintf '%s/arcsearch_id/%s/%s-%s/%s',
			&Conf::get_robot_conf($robot, 'wwsympa_url'),
			$self->name, $yyyy, $mm,
			&tools::clean_msg_id($hdr->get('Message-Id'));
	    $hdr->add('Archived-At', '<'.$archived_msg_url.'>');
	} else {
	    return 0;
	}
    } else {
	&Log::do_log('err', 'Unknown field "%s".  Ask developer', $field);
	return undef;
    }

    return 1;
}
 
##connect to stat_counter_table and extract data.
sub get_data {
    my ($data, $robotname, $listname) = @_;

    unless ( $sth = &SDM::do_query( "SELECT * FROM stat_counter_table WHERE data_counter = '%s' AND robot_counter = '%s' AND list_counter = '%s'", $data,$robotname, $listname)) {
		&Log::do_log('err','Unable to get stat data %s for liste %s@%s',$data,$listname,$robotname);
		return undef;
    }
    my $res = $sth->fetchall_hashref('beginning_date_counter');
    return $res;
}

################################################

=head1 ACCESSORS

=over 4

=item E<lt>config parameterE<gt>

=item E<lt>config parameterE<gt>C<( VALUE )>

I<Getters/Setters>.
Get or set list config parameter.
For example C<$list-E<gt>subject> returns "subject" parameter of the list,
and C<$list-E<gt>subject("foo")> also changes it.
Basic list profiles "name", "domain", "dir" and so on have only getters,
so they are read-only.

Some accessors have a bit confusing names: $list->host() gets/sets 'host'
list parameter, not its robot name; $list->update() that gets/sets 'update'
list parameter (actually hashref) won't update the list object itself.

=back

=cut

our $AUTOLOAD;

sub DESTROY;

sub AUTOLOAD {
    $AUTOLOAD =~ m/^(.*)::(.*)/;

    my $attr = $2;
    if (ref $_[0] and
	grep { $_ eq $attr } qw(name domain dir admin stats as_x509_cert)) {
	## getter for list attributes.
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    croak "Can't modify \"$attr\" attribute" if scalar @_ > 1;
	    shift->{$attr};
	};
    } elsif (ref $_[0] and $::pinfo{$attr}) {
	## getter/setter for list parameters.
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    my $self = shift;
	    unless (defined $self->{'admin'}) {
		croak "Can't call method \"$attr\" on uninitialized " .
		      (ref $self) . " object";
	    } elsif (scalar @_) {
		$self->{'admin'}{$attr} = shift;
	    } else {
		$self->{'admin'}{$attr};
	    }
	};
    } elsif (ref $_[0] and index($attr, '_') != 0 and defined $_[0]->{$attr}) {
	## getter for unknwon list attributes.
	## XXX This code would be removed later.
	&Log::do_log('err', 'Unconcerned object method "%s" via package "%s".  Though it may not be fatal, you might want to report it developer',
		     $2, $1);
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    croak "Can't modify \"$attr\" attribute" if scalar @_ > 1;
	    shift->{$attr};
	};
    } else {
	croak "Can't locate object method \"$2\" via package \"$1\"";
    }
    goto &$AUTOLOAD;
}

=over 4

=item family

I<Getter>.
Gets Family object the list is belonging to, or undef.

=back

=cut

sub family {
    my $self = shift;
    return undef unless $self->family_name;

    unless (ref $self->{'family'} and
	    $self->{'family'}->{'name'} eq $self->family_name and
	    $self->{'family'}->{'robot'} eq $self->domain) {
	$self->{'family'} = new Family($self->family_name, $self->domain);
    }

    return $self->{'family'};
}

=over 4

=item robot

I<Getter>.
Gets Robot object the list is belonging to.  Returns undef on error.

=back

=cut

sub robot {
    my $self = shift;
    return undef unless $self->domain;

    unless (ref $self->{'robot'}) {
	$self->{'robot'} = new Robot($self->domain);
    }

    return $self->{'robot'};
}

=over 4

=item total ( [ NUMBER ] )

Handles cached number of subscribers on memory.

I<Getter>.
Gets cached value.

I<Setter>.
Updates both memory and database cache.

Use get_real_total() to recalculate actual value and to renew caches with it.

=back

=cut

sub total {
    my $self = shift;
    if (scalar @_) {
	my $total = shift;
	unless (defined $self->{'total'} and $self->{'total'} == $total) {
	    $self->{'total'} = $total;
	    $self->list_cache_update_total($total);
	}
    }
    return $self->{'total'};
}

=over 4

=item user ( ROLE, WHO, [ INFO ] )

Handles cached information of list users on memory.

I<Getter>.
Gets cached value on memory.  If memory cache is missed, gets actual value
and updates memory cache.
Returns numeric zero (C<0>) if user WHO is known I<not> to be a user of the
list.  Returns C<undef> on error.

I<Setter>.
Updates memory cache.
If C<0> was given as INFO, negative cache will be set.
If C<undef> was given as INFO, cache entry on the memory will be removed.

=back

=cut

sub user {
    my $self = shift;
    my $role = shift;
    my $who = &tools::clean_email(shift || '');
    my $info;

    unless ($role eq 'member' or $role eq 'owner' or $role eq 'editor') {
	&Log::do_log('err', '"%s" is wrong: must be "member", "owner" or "editor"', $role);
	return undef;
    }
    return undef unless $who;

    if (scalar @_) {
	$info = shift;
	$self->{'user'} ||= {};
	$self->{'user'}{$role} ||= {};

	unless (defined $info) {
	    delete $self->{'user'}{$role}{$who};
	} elsif (ref $info) {
	    $self->{'user'}{$role}{$who} = $info;
	} elsif ($info) {
	    $self->{'user'}{$role}{$who} = $info
		unless $self->{'user'}{$role}{$who};
	} else {
	    $self->{'user'}{$role}{$who} = 0;
	}

	return $self->{'user'}{$role}{$who};
    }

    return $self->{'user'}{$role}{$who}
	if defined $self->{'user'}{$role}{$who};

    push @sth_stack, $sth;

    if ($role eq 'member') {
	## Query the Database
	unless ($sth = &SDM::do_prepared_query(sprintf('SELECT %s FROM subscriber_table WHERE list_subscriber = ? AND robot_subscriber = ? AND user_subscriber = ?', &_list_member_cols()),
					       $self->name, $self->domain,
					       $who)) {
	    &Log::do_log('err', 'Unable to check whether user %s is subscribed to list %s', $who, $self);
	    $sth = pop @sth_stack;
	    return undef;
	}
	$info = $sth->fetchrow_hashref('NAME_lc');
	$sth->finish();

	if (defined $info) {
	    $info->{'reception'} ||= 'mail';
	    $info->{'update_date'} ||= $info->{'date'};
	    &Log::do_log('debug3', 'custom_attribute = (%s)',
			 $info->{custom_attribute});
	    if (defined $info->{custom_attribute}) {
		$info->{'custom_attribute'} =
		    &parseCustomAttribute($info->{'custom_attribute'});
	    }
	    $info->{'reception'} = $self->default_user_options->{'reception'}
		unless $self->is_available_reception_mode($info->{'reception'});
	} else {
	    &Log::do_log('debug3', 'No user with the email %s is subscribed to list %s', $who, $self);
	    $info = 0;
	}
    } else {
	unless ($sth = &SDM::do_prepared_query(
	    sprintf('SELECT %s FROM admin_table WHERE user_admin = ? AND list_admin = ? AND robot_admin = ? AND role_admin = ?', &_list_admin_cols()),
	    $who, $self->name, $self->domain, $role)) {
            &Log::do_log('err', 'Unable to get admin %s for list %s', $who, $self);
            $sth = pop @sth_stack;
            return undef;
	}
	$info = $sth->fetchrow_hashref('NAME_lc');
	$sth->finish();

	if (defined $info) {
	    $info->{'reception'} ||= 'mail';
	    $info->{'update_date'} ||= $info->{'date'};
	} else {
	    $info = 0;
	}
    }

    $sth = pop @sth_stack;

    ## Set cache
    return $self->{'user'}{$role}{$who} = $info;
}

###### END of the List package ######

############################################################################
##                       LIST CACHE FUNCTIONS                             ##
############################################################################

##package ListCache;
##
##sub new {
##    my $pkg = shift;
##    my $list = shift;
##    bless { 'list' => $list } => $pkg;
##}

sub list_cache_fetch {
    my $self = shift;
    my $m1 = shift;
    my $time_config = shift;
    my $name = $self->name;
    my $robot = $self->domain;

    my $cache_list_config = &Conf::get_robot_conf($robot, 'cache_list_config');
    my $admin;
    my $time_config_bin;

    if ($cache_list_config eq 'database') {
	my $l;
	push @sth_stack, $sth;

	unless ($sth = &SDM::do_prepared_query(
	    q{SELECT cache_epoch_list AS epoch, total_list AS total,
		     config_list AS admin
	      FROM list_table
	      WHERE name_list = ? AND robot_list = ? AND
		    cache_epoch_list > ? AND ? <= cache_epoch_list},
	    $name, $robot, $m1, $time_config
	) and $sth->rows) {
	    $sth = pop @sth_stack;
	    return undef;
	}
	$l = $sth->fetchrow_hashref('NAME_lc');
	$sth->finish;

	$sth = pop @sth_stack;

	return undef unless $l;

	eval { $admin = &Storable::thaw($l->{'admin'}) };
	if ($@ or ! defined $admin) {
	    &Log::do_log('err', 'Unable to deserialize binary config of %s: %s',
			 $self, $@ || 'possible format error');
	    return undef;
	}

	return { 'epoch' => $l->{'epoch'},
		 'total' => $l->{'total'},
		 'admin' => $admin };
    } elsif ($cache_list_config eq 'binary_file' and
	     ($time_config_bin = (stat($self->dir.'/config.bin'))[9]) > $m1 and
	     $time_config <= $time_config_bin) {
	## Get a shared lock on config file first 
	my $lock = new Lock ($self->dir.'/config');
	unless (defined $lock) {
	    &Log::do_log('err','Could not create new lock');
	    return undef;
	}
	$lock->set_timeout(5); 
	unless ($lock->lock('read')) {
	    &Log::do_log('err','Could not create new lock');
	    return undef;
	}

	## Load a binary version of the data structure
	## unless config is more recent than config.bin
	eval { $admin = &Storable::retrieve($self->dir.'/config.bin') };
	if ($@ or ! defined $admin) {
	    &Log::do_log('err', 'Unable to deserialize config.bin of %s: $@',
			 $self, $@ || 'possible format error');
	    $lock->unlock();
	    return undef;
	}

	$lock->unlock();

	$self->get_real_total;
	return { 'epoch' => $time_config_bin,
		 'total' => $self->total,
		 'admin' => $admin };
    }
    return undef;
}


## Update list cache.
sub list_cache_update_admin
{
    my ($self) = shift;
    my $cache_list_config = &Conf::get_robot_conf($self->domain,
						  'cache_list_config');

    if ($cache_list_config eq 'binary_file') {
	## Get a shared lock on config file first
	my $lock = new Lock ($self->dir . '/config');
	unless (defined $lock) {
	    &Log::do_log('err','Could not create new lock');
	    return undef;
	}
	$lock->set_timeout(5);
	unless ($lock->lock('write')) {
	    return undef;
	}

	eval {&Storable::store($self->admin, $self->dir . '/config.bin')};
	if ($@) {
	    &Log::do_log('err', 'Failed to save the binary config %s. error: %s', $self->dir . '/config.bin', $@);
	    $lock->unlock;
	    return undef;
	}

	$lock->unlock;

	return 1;
    }

    return 1 unless $cache_list_config eq 'database';

    my $config;

    my $name = $self->name;
    my $searchkey = tools::foldcase($self->subject);
    my $status = $self->status;
    my $robot = $self->domain;
    my $web_archive  = $self->is_web_archived ? 1 : 0; 
    my $topics = join(',',
		      grep { $_ and $_ ne 'others' } @{$self->topics || []});
    $topics = ",$topics," if length $topics;

    my $creation_epoch = $self->creation->{'date_epoch'};
    my $creation_email = $self->creation->{'email'};
    my $update_epoch = $self->update->{'date_epoch'};
    my $update_email = $self->update->{'email'};
##    my $latest_instantiation_epoch =
##	$self->latest_instantiation->{'date_epoch'};
##    my $latest_instantiation_email =
##	$self->latest_instantiation->{'email'};

    eval { $config = Storable::nfreeze($self->admin); };
    if ($@) {
	&Log::do_log('err', 'Failed to save the config to database. error: %s', $@);
	return undef;
    }

    my $time = time;

    push @sth_stack, $sth;

    ## update database cache
    ## try INSERT then UPDATE
    unless($sth = &SDM::do_prepared_query(
	q{UPDATE list_table
	  SET status_list = ?, name_list = ?, robot_list = ?,
	      creation_epoch_list = ?, creation_email_list = ?,
	      update_epoch_list = ?, update_email_list = ?,
	      searchkey_list = ?, web_archive_list = ?, topics_list = ?,
	      cache_epoch_list = ?, config_list = ?
	  WHERE robot_list = ? AND name_list = ?},
	$status, $name, $robot,
	$creation_epoch, $creation_email,
	$update_epoch, $update_email,
	$searchkey, $web_archive, $topics,
	$time, SDM::AS_BLOB($config),
	$robot, $name
    ) and $sth->rows or
    $sth = &SDM::do_prepared_query(
	q{INSERT INTO list_table
	  (status_list, name_list, robot_list,
	   creation_epoch_list, creation_email_list,
	   update_epoch_list, update_email_list,
	   searchkey_list, web_archive_list, topics_list,
	   cache_epoch_list, config_list)
	  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
	$status, $name, $robot,
	$creation_epoch, $creation_email,
	$update_epoch, $update_email,
	$searchkey, $web_archive, $topics,
	$time, SDM::AS_BLOB($config)
    ) and $sth->rows) {
	&Log::do_log('err','Unable to insert list %s in database', $self);
	$sth = pop @sth_stack;
	return undef;
    }

    $sth = pop @sth_stack;

    return 1;
}

sub list_cache_update_total {
    my $self = shift;
    my $cache_list_config = &Conf::get_robot_conf($self->domain,
						  'cache_list_config');

    if ($cache_list_config eq 'database') {
	unless (&SDM::do_prepared_query(
	    q{UPDATE list_table
	      SET total_list = ?
	      WHERE name_list = ? AND robot_list = ?},
	    $self->{'total'}, $self->name, $self->domain
	)) {
	    &Log::do_log('err', 'Canot update subscriber count of list %s on database cache',
			 $self);
	}
    }
}

sub list_cache_purge {
    my $self = shift;

    my $cache_list_config = &Conf::get_robot_conf($self->domain,
						 'cache_list_config');
    if ($cache_list_config eq 'binary_file' and -e $self->dir.'/config.bin') {
        ## Get a shared lock on config file first
	my $lock = new Lock ($self->dir.'/config');
	unless (defined $lock) {
	    &Log::do_log('err','Could not create new lock');
	    return undef;
	}
	$lock->set_timeout(5);
	unless ($lock->lock('write')) {
	    return undef;
	}

	unlink($self->dir.'/config.bin');

	$lock->unlock;
    }

    return 1 unless $cache_list_config eq 'database';

    return defined &SDM::do_prepared_query('DELETE from list_table WHERE name_list = ? AND robot_list = ?',
					   $self->name, $self->domain);
}

###### END of the ListCache package ######

## Packages must return true.
1;
