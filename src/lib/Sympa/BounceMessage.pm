# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997-2011 Comite Reseau des Universites
# Copyright (c) 2011-2014 GIP RENATER
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

package Sympa::BounceMessage;

use strict;
use warnings;
use base qw(Sympa::Message);

use English qw(-no_match_vars);

use Sympa::Log::Database;
use Sympa::Log::Syslog;
use Sympa::Site;
use Sympa::Tracking;

## Equivalents relative to RFC 1893
our %equiv = (
    "user unknown"                                                => '5.1.1',
    "receiver not found"                                          => '5.1.1',
    "the recipient name is not recognized"                        => '5.1.1',
    "sorry, no mailbox here by that name"                         => '5.1.1',
    "utilisateur non recens\xE9 dans le carnet d'adresses public" => '5.1.1',
    "unknown address"                                             => '5.1.1',
    "unknown user"                                                => '5.1.1',
    "550"                                                         => '5.1.1',
    "le nom du destinataire n'est pas reconnu"                    => '5.1.1',
    "user not listed in public name & address book"               => '5.1.1',
    "no such address"                                             => '5.1.1',
    "not known at this site."                                     => '5.1.1',
    "user not known"                                              => '5.1.1',

    "user is over the quota. you can try again later." => '4.2.2',
    "quota exceeded"                                   => '4.2.2',
    "write error to mailbox, disk quota exceeded"      => '4.2.2',
    "user mailbox exceeds allowed size"                => '4.2.2',
    "insufficient system storage"                      => '4.2.2',
    "User's Disk Quota Exceeded:"                      => '4.2.2'
);

## Creates a new object
sub new {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s, %s)', @_);
    my $pkg   = shift;
    my $datas = shift;
    my $self;

    return undef
        unless $self = $pkg->SUPER::new($datas);
    unless ($self->as_string()) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::NOTICE,
            'Ignoring bounce %s, because it is empty', $self);
        return undef;
    }

    ## Some MTAs decorate To: field of DSN as "mailbox <address>".
    ## Pick address only.
    my $to = $self->get_header('to');
    if ($to) {
        my @to = Mail::Address->parse($to);
        if (@to and $to[0] and $to[0]->address) {
            $self->{'to'} = $to[0]->address;
        }
    }

    return $self;
}

sub process {
    my $self = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::INFO, 'Processing bounce %s', $self);
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
        'Bounce for :%s:  Sympa::Site->bounce_email_prefix=%s',
        $self->{'to'}, Sympa::Site->bounce_email_prefix);

    if ($self->is_verp_in_use) {    #VERP in use
        $self->analyze_verp_header();
        if ($self->failed_on_first_try) {

            # in this case the bounce result from a remind or a welcome
            # message; so try to remove the subscriber
            Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
                'VERP for a service message, trying to remove the subscriber'
            );
            unless (
                $self->update_list($self->{'listname'}, $self->{'robotname'}))
            {
                Sympa::Log::Syslog::do_log(
                    Sympa::Log::Syslog::ERR,
                    'Skipping bounce where messagekey = %s for unknown list %s@%s',
                    $self->{'messagekey'},
                    $self->{'listname'},
                    $self->{'robotname'}
                );
                return undef;
            }
            unless ($self->delete_bouncer) {
                Sympa::Log::Syslog::do_log(
                    Sympa::Log::Syslog::ERR,
                    'Unable to remove %s from %s@%s (welcome message bounced but del is closed)',
                    $self->{'who'},
                    $self->{'listname'},
                    $self->{'robotname'}
                );
                return 0;
            }
            return 1;
        }    # close VERP + remind or welcome block
    }    # close VERP in use block

    # ---
    # If the DSN notification is correct and the tracking mode is enable, it
    # will be inserted in the database
    if ($self->is_dsn and $self->tracking_is_used) {
        if ($self->process_dsn) {
            Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::NOTICE,
                'DSN %s Correctly treated. DSN status is "%s"',
                $self, $self->{'dsn'}{'status'});
        } else {
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::ERR,
                'Delivery status notification processing for bounce %s (key %s) failed. Stopping here.',
                $self,
                $self->{'messagekey'}
            );
            return undef;
        }
        unless ($self->{'dsn'}{'status'} =~ /failed/) {

            # DSN for failure to deliver need to be processed as bounces.
            return 1;
        }
    }

    # ---
    # If the MDN notification is correct and the tracking mode is enabled, it
    # will be inserted in the database
    if ($self->is_mdn and $self->tracking_is_used) {
        if ($self->process_mdn) {
            Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::NOTICE, 'MDN %s Correctly treated.',
                $self);
            return 1;
        } else {
            Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR, 'Failed to treat MDN %s',
                $self);
            return undef;
        }
    }

    if ($self->is_email_feedback_report) {

        # this case a report Email Feedback Reports
        # http://tools.ietf.org/html/rfc6650 mainly used by AOL
        if ($self->process_email_feedback_report) {
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::NOTICE,
                'Feedback Report %s correctly treated. type: %s, original_rcpt: %s, listname: %s@%s)',
                $self,
                $self->{'feedback_type'},
                $self->{'original_rcpt'},
                $self->{'listname'},
                $self->{'robotname'}
            );
            return 1;
        } else {
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::ERR,
                'Ignoring Feedback Report %s : Unknown format (bounce where messagekey=%s), original_rcpt: %s, listname: %s@%s)',
                $self,
                $self->{'feedback_type'},
                $self->{'original_rcpt'},
                $self->{'listname'},
                $self->{'robotname'}
            );
            return undef;
        }
    }

    if ($self->process_ndn) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::NOTICE,
            'Bounce %s from %s to list %s correctly treated.',
            $self, $self->{'who'}, $self->{'list'});
        return 1;
    } else {
        Sympa::Log::Syslog::do_log(
            Sympa::Log::Syslog::ERR,
            'Could not correctly process bounce %s from %s to list %s@%s. Ignoring.',
            $self,
            $self->{'who'},
            $self->{'listname'},
            $self->{'robotname'}
        );
        return undef;
    }
    return 1;
}

sub analyze_verp_header {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s)', @_);
    my $self = shift;

    if ($self->is_verp_in_use) {
        if ($self->{'local_part'} =~
            /^(.*)\=\=a\=\=([^\=]*)\=\=([^\=]*)(\=\=([^\=]*))?$/) {
            $self->{'who'}             = $1 . '@' . $2;
            $self->{'listname'}        = $3;
            $self->{'distribution_id'} = $5;
        } else {
            Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
                'Unable to analyze VERP address %s for bounce %s',
                $self->{'to'}, $self);
            return undef;
        }
        $self->update_list($self->{'listname'}, $self->{'robotname'});
        if (   $self->{'distribution_id'} eq 'r'
            || $self->{'distribution_id'} eq 'w') {
            $self->{'unique'} = $self->{'distribution_id'};
        }
        undef $self->{'distribution_id'}
            unless ($self->{'distribution_id'} =~ /^[0-9]+$/);
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
            'VERP in use : bounce %s related to %s for list %s',
            $self, $self->{'who'}, $self->{'list'});
        return 1;
    }
    return 0;
}

sub is_verp_in_use {
    my $self = shift;
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s, to=%s, prefix=%s)',
        $self, $self->{'to'}, Sympa::Site->bounce_email_prefix);
    return $self->{'verp'}{'is_used'} if (defined $self->{'verp'}{'is_used'});
    my $bounce_email_prefix = Sympa::Site->bounce_email_prefix;
    if ($self->{'to'} =~ /^$bounce_email_prefix\+(.*)\@(.*)$/) {
        $self->{'local_part'} = $1;
        $self->{'robotname'}  = $2;
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Message %s uses VERP', $self);
        $self->{'verp'}{'is_used'} = 1;
    } else {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Message %s does not use VERP',
            $self);
        $self->{'verp'}{'is_used'} = 0;
    }
    return $self->{'verp'}{'is_used'};
}

sub is_dsn {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s)', @_);
    my $self = shift;

    return $self->{'dsn'}{'is_dsn'} if (defined $self->{'dsn'}{'is_dsn'});
    if ((   $self->get_mime_message->head->get('Content-type') =~
            /multipart\/report/
        )
        && ($self->get_mime_message->head->get('Content-type') =~
            /report\-type\=delivery-status/i)
        ) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Bounce %s is a DSN', $self);
        $self->{'dsn'}{'is_dsn'} = 1;
    } else {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Bounce %s is not a DSN', $self);
        $self->{'dsn'}{'is_dsn'} = 0;
    }
    return $self->{'dsn'}{'is_dsn'};
}

sub is_mdn {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s)', @_);
    my $self = shift;

    return $self->{'mdn'}{'is_mdn'} if (defined $self->{'mdn'}{'is_mdn'});
    if ((   $self->get_mime_message->head->get('Content-type') =~
            /multipart\/report/
        )
        && ($self->get_mime_message->head->get('Content-type') =~
            /report\-type\=disposition-notification/i)
        ) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Message %s is an MDN', $self);
        $self->{'mdn'}{'is_mdn'} = 1;
    } else {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Message %s is not an MDN',
            $self);
        $self->{'mdn'}{'is_mdn'} = 0;
    }
    return $self->{'mdn'}{'is_mdn'};
}

sub is_email_feedback_report {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s)', @_);
    my $self = shift;

    return $self->{'efr'}{'is_efr'} if (defined $self->{'efr'}{'is_efr'});
    if ((   $self->get_mime_message->head->get('Content-type') =~
            /multipart\/report/
        )
        && ($self->get_mime_message->head->get('Content-type') =~
            /report\-type\=feedback-report/)
        ) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
            'Bounce %s is an email feedback report', $self);
        $self->{'efr'}{'is_efr'} = 1;
    } else {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
            'Bounce %s is not an email feedback report', $self);
        $self->{'efr'}{'is_efr'} = 0;
    }
    return $self->{'efr'}{'is_efr'};
}

sub tracking_is_used {
    my $self = shift;
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s, list=%s)',
        $self, $self->{'list'});

    return $self->{'tracking'}{'is_used'}
        if defined $self->{'tracking'}{'is_used'};

    my $list = $self->{'list'};
    if (    $list->tracking->{'delivery_status_notification'}
        and $list->tracking->{'delivery_status_notification'} eq 'on'
        or $list->tracking->{'message_delivery_notification'}
        and (  $list->tracking->{'message_delivery_notification'} eq 'on'
            or $list->tracking->{'message_delivery_notification'} eq
            'on_demand')
        ) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
            'List %s for Message %s uses tracking',
            $list, $self);
        $self->{'tracking'}{'is_used'} = 1;
    } else {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
            'List %s for Message %s does not use tracking',
            $list, $self);
        $self->{'tracking'}{'is_used'} = 0;
    }
    return $self->{'tracking'}{'is_used'};
}

sub failed_on_first_try {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s)', @_);
    my $self = shift;

    if ($self->{'unique'} and $self->{'unique'} =~ /[wr]/) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
            'Bounce %s comes from a service message.', $self);
        return 1;
    }
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
        'Bounce %s does not come from a service message.', $self);
    return 0;
}

sub change_listname {
    my $self         = shift;
    my $new_listname = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
        'Changing listname from %s to %s for bounce %s',
        $self->{'listname'}, $new_listname, $self);
    $self->{'old_listname'} = $self->{'listname'};
    $self->{'listname'}     = $new_listname;
}

sub change_robotname {
    my $self          = shift;
    my $new_robotname = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
        'Changing robotname from %s to %s for bounce %s',
        $self->{'robotname'}, $new_robotname, $self);
    $self->{'old_robotname'} = $self->{'robotname'};
    $self->{'robotname'}     = $new_robotname;
}

sub update_list {
    my $self          = shift;
    my $new_listname  = shift;
    my $new_robotname = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Updating list for bounce %s',
        $self);
    $self->update_robot($new_robotname);
    $self->change_listname($new_listname);

    my $list = Sympa::List->new($self->{'listname'}, $self->{'robot'});
    unless ($list) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'Unable to set list object for unknown list %s@%s (bounce %s)',
            $self->{'listname'}, $self->{'robotname'}, $self);
        return undef;
    }
    $self->{'list'} = $list;

    return 1;
}

sub update_robot {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, '(%s, %s)', @_);
    my $self          = shift;
    my $new_robotname = shift;

    $self->change_robotname($new_robotname);

    my $robot = Sympa::Robot->new($self->{'robotname'});
    unless ($robot) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'Unable to set robot object for unknown robot %s (bounce %s)',
            $self->{'robotname'}, $self);
        return undef;
    }
    $self->{'robot'} = $robot;

    return 1;
}

sub delete_bouncer {
    my $self = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, 'Deleting bouncing user %s',
        $self->{'who'});
    my $result = Sympa::Scenario::request_action(
        $self->{'list'},
        'del', 'smtp',
        {   'sender' => [Sympa::Site->listmasters]->[0],
            'email'  => $self->{'who'}
        }
    );
    my $action;
    $action = $result->{'action'} if (ref($result) eq 'HASH');

    if ($action =~ /do_it/i) {
        if ($self->{'list'}->is_list_member($self->{'who'})) {
            $self->{'list'}->delete_list_member(
                'users'   => [$self->{'who'}],
                'exclude' => ' 1'
            );
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::NOTICE,
                '%s has been removed from %s because welcome message bounced',
                $self->{'who'},
                $self->{'list'}
            );
            Sympa::Log::Database::db_log(
                'robot'        => $self->{'list'}->domain,
                'list'         => $self->{'list'}->name,
                'action'       => 'del',
                'target_email' => $self->{'who'},
                'status'       => 'error',
                'error_type'   => 'welcome_bounced',
                'daemon'       => 'bounced'
            );
            Sympa::Log::Database::db_stat_log(
                'robot'     => $self->{'list'}->domain,
                'list'      => $self->{'list'}->name,
                'operation' => 'auto_del',
                'parameter' => '',
                'mail'      => $self->{'who'},
                'client'    => '',
                'daemon'    => 'bounced.pl'
            );

            if ($action =~ /notify/) {
                unless (
                    $self->{'list'}->send_notify_to_owner(
                        'automatic_del',
                        {   'who'    => $self->{'who'},
                            'by'     => 'bounce manager',
                            'reason' => 'welcome'
                        }
                    )
                    ) {
                    wwslog(
                        Sympa::Log::Syslog::ERR,
                        'Unable to send notify "automatic_del" to %s list owner',
                        $self->{'list'}
                    );
                }
            }
        }
    } else {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'Authorization to delete user %s from liste %s denied',
            $self->{'who'}, $self->{'list'});
        return undef;
    }
    return 1;
}

sub process_dsn {
    my $self = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG, 'processing  DSN %s',
        $self->get_msg_id);
    my @parts = $self->get_mime_message->parts();
    my $original_rcpt;
    my $final_rcpt;
    my $msg_id;
    my $arrival_date;

    $msg_id = $self->get_mime_message->head->get('Message-Id');
    chomp $msg_id if $msg_id;

    my $date = $self->get_mime_message->head->get('Date');
    chomp $date if $date;

    foreach my $p (@parts) {
        my $h       = $p->head();
        my $content = $h->get('Content-type');

        if ($content =~ /message\/delivery-status/) {
            my @report = split(/\n/, $p->bodyhandle->as_string());
            foreach my $line (@report) {
                $line = lc($line);

                # Action Field MUST be present in a DSN report, possible
                # values : failed, delayed, delivered, relayed,
                # expanded(rfc3464)
                if ($line =~ /action\:\s*(.+)/i) {
                    $self->{'dsn'}{'status'} = $1;
                    chomp $self->{'dsn'}{'status'};
                }

                if (   ($line =~ /final\-recipient\:\s*(.+)\s*$/i)
                    && (not $final_rcpt)) {
                    $final_rcpt = $1;
                    chomp $final_rcpt;
                    my @rcpt;
                    if ($final_rcpt =~ /.*;.*/) {
                        @rcpt = split /;\s*/, $final_rcpt;
                        foreach my $rcpt (@rcpt) {
                            if ($rcpt =~ /(\S+\@\S+)/) {
                                ($rcpt) = $rcpt =~ /(\S+\@\S+)/;
                                $final_rcpt = $rcpt;
                            }
                        }
                    } else {
                        ($final_rcpt) = $final_rcpt =~ /(\S+\@\S+)/;
                    }
                }
                if ($line =~ /arrival\-date\:\s*(.+)/i) {
                    $arrival_date = $1;
                    chomp $arrival_date;
                }
            }
        }
    }

    $original_rcpt = $self->{'who'};

    if ($final_rcpt =~ /<(\S+\@\S+)>/) {
        ($final_rcpt) = $final_rcpt =~ /<(\S+\@\S+)>/;
    }
    if ($msg_id =~ /<(\S+\@\S+)>/) {
        ($msg_id) = $msg_id =~ /<(\S+\@\S+)>/;
    }

    Sympa::Log::Syslog::do_log(
        Sympa::Log::Syslog::DEBUG2,
        'FINAL DSN Action Detected, value : %s',
        $self->{'dsn'}{'status'}
    );
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2,
        'FINAL DSN Recipient Detected, value : %s',
        $original_rcpt);
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2,
        'FINAL DSN final Recipient Detected, value : %s', $final_rcpt);
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2,
        'FINAL DSN Message-Id Detected, value : %s', $msg_id);
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2,
        'FINAL DSN Arrival Date Detected, value : %s',
        $arrival_date);

    unless ($self->{'dsn'}{'status'} =~ /failed/) {

        # DSN with status 'failed' should not be removed because they must be
        # processed for classical bounce managment (not only for tracking
        # feature)
        Sympa::Log::Syslog::do_log(
            Sympa::Log::Syslog::DEBUG2,
            'Non failed DSN status "%s"',
            $self->{'dsn'}{'status'}
        );
        unless ($self->{'distribution_id'}) {
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::ERR,
                'error: Id not found in destination address "%s". Will ignore',
                $self->{'to'}
            );
            return undef;
        }
        unless ($original_rcpt) {
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::ERR,
                'error: original recipient not found in DSN: "%s". Will ignore',
                $msg_id
            );
            return undef;
        }
        unless ($msg_id) {
            Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
                'error: message_id not found in DSN. Will ignore');
            return undef;
        }
    }

    if (Sympa::Tracking::db_insert_notification(
            $self->{'distribution_id'}, 'DSN',
            $self->{'dsn'}{'status'},   $arrival_date,
            $self->get_message_as_string
        )
        ) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG,
            'DSN for "%s" inserted into database for further consultation.',
            $self->{'who'});
    } else {
        Sympa::Log::Syslog::do_log(
            Sympa::Log::Syslog::ERR,
            'Not able to fill database with notification data for DSN to "%s"',
            $self->{'who'}
        );
        return undef;
    }
    return 1;
}

sub process_mdn {
    my $self = shift;
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG, 'processing  MDN %s',
        $self->get_msg_id);
    my @parts = $self->get_mime_message->parts();

    $self->{'mdn'}{'msg_id'} =
        $self->get_mime_message->head->get('Message-Id');
    chomp $self->{'mdn'}{'msg_id'}
        if $self->{'mdn'}{'msg_id'};

    $self->{'mdn'}{'date'} = $self->get_mime_message->head->get('Date');

    foreach my $p (@parts) {
        my $h       = $p->head();
        my $content = $h->get('Content-type');

        if ($content =~ /message\/disposition-notification/) {
            my @report = split /\n/, $p->bodyhandle->as_string();
            foreach my $line (@report) {
                $line = lc($line);

                # Disposition Field MUST be present in a MDN report, possible
                # values : displayed, deleted(rfc3798)
                if ($line =~ /disposition\:\s*(.+)\s*\;\s*(.+)/i) {
                    $self->{'mdn'}{'status'} = $2;
                    if ($self->{'mdn'}{'status'} =~ /.*\/.*/) {
                        my @results = split /\/\s*/, $self->{'mdn'}{'status'};
                        $self->{'mdn'}{'status'} = $results[$0];
                        chomp $self->{'mdn'}{'status'};
                    }
                }
                if (   ($line =~ /final\-recipient\:\s*(.+)\s*$/i)
                    && (not $self->{'mdn'}{'final_rcpt'})) {
                    $self->{'mdn'}{'final_rcpt'} = $1;
                    chomp $self->{'mdn'}{'final_rcpt'};
                    my @rcpt;
                    if ($self->{'mdn'}{'final_rcpt'} =~ /.*;.*/) {
                        @rcpt = split /;\s*/, $self->{'mdn'}{'final_rcpt'};
                        foreach my $rcpt (@rcpt) {
                            if ($rcpt =~ /(\S+\@\S+)/) {
                                ($rcpt) = $rcpt =~ /(\S+\@\S+)/;
                                $self->{'mdn'}{'final_rcpt'} = $rcpt;
                            }
                        }
                    } else {
                        ($self->{'mdn'}{'final_rcpt'}) =
                            $self->{'mdn'}{'final_rcpt'} =~ /(\S+\@\S+)/;
                    }
                }
            }
        }
    }

    if ($self->{'mdn'}{'original_rcpt'} =~ /<(\S+\@\S+)>/) {
        ($self->{'mdn'}{'original_rcpt'}) =
            $self->{'mdn'}{'original_rcpt'} =~ /<(\S+\@\S+)>/;
    }
    if ($self->{'mdn'}{'final_rcpt'} =~ /<(\S+\@\S+)>/) {
        ($self->{'mdn'}{'final_rcpt'}) =
            $self->{'mdn'}{'final_rcpt'} =~ /<(\S+\@\S+)>/;
    }
    if ($self->{'mdn'}{'msg_id'} =~ /<(\S+\@\S+)>/) {
        ($self->{'mdn'}{'msg_id'}) =
            $self->{'mdn'}{'msg_id'} =~ /<(\S+\@\S+)>/;
    }

    # let's use VERP
    $self->{'mdn'}{'original_rcpt'} = $self->{'who'};

    Sympa::Log::Syslog::do_log(
        Sympa::Log::Syslog::DEBUG2,
        'FINAL MDN Disposition Detected, value : %s',
        $self->{'mdn'}{'status'}
    );
    Sympa::Log::Syslog::do_log(
        Sympa::Log::Syslog::DEBUG2,
        'FINAL MDN Recipient Detected, value : %s',
        $self->{'mdn'}{'original_rcpt'}
    );
    Sympa::Log::Syslog::do_log(
        Sympa::Log::Syslog::DEBUG2,
        'FINAL MDN Message-Id Detected, value : %s',
        $self->{'mdn'}{'msg_id'}
    );
    Sympa::Log::Syslog::do_log(
        Sympa::Log::Syslog::DEBUG2,
        'FINAL MDN Date Detected, value : %s',
        $self->{'mdn'}{'date'}
    );

    unless ($self->{'distribution_id'}) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'error: Id not found in to address %s, will ignore',
            $self->{'to'});
        return undef;
    }
    unless ($self->{'mdn'}{'original_rcpt'}) {
        Sympa::Log::Syslog::do_log(
            Sympa::Log::Syslog::ERR,
            'error: original recipient not found in MDN "%s". Will ignore',
            $self->{'mdn'}{'msg_id'}
        );
        return undef;
    }
    unless ($self->{'mdn'}{'msg_id'}) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'error: message_id not found in MDN. Will ignore');
        return undef;
    }
    unless ($self->{'mdn'}{'status'}) {
        Sympa::Log::Syslog::do_log(
            Sympa::Log::Syslog::ERR,
            'error: MDN status not found in MDN "%s". Will ignore',
            $self->{'mdn'}{'msg_id'}
        );
        return undef;
    }

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, 'Save in database...');
    unless (
        Sympa::Tracking::db_insert_notification(
            $self->{'distribution_id'}, 'MDN',
            $self->{'mdn'}{'status'},   $self->{'mdn'}{'date'},
            $self->get_message_as_string
        )
        ) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'Not able to fill database with notification data for MDN %s',
            $self->get_msg_id);
        return undef;
    }
    return 1;
}

sub process_email_feedback_report {
    my $self = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG,
        'processing  Email Feedback Report %s',
        $self->get_msg_id);
    my @parts = $self->get_mime_message->parts();
    $self->{'efr'}{'feedback_type'} = '';
    foreach my $p (@parts) {
        my $h       = $p->head();
        my $content = $h->get('Content-type');
        next if ($content =~ /text\/plain/i);
        if ($content =~ /message\/feedback-report/) {
            my @report = split /\n/, $p->bodyhandle->as_string();
            foreach my $line (@report) {
                $self->{'efr'}{'feedback_type'} = 'abuse'
                    if ($line =~ /Feedback\-Type\:\s*abuse/i);
                if ($line =~ /Feedback\-Type\:\s*(.*)/i) {
                    $self->{'efr'}{'feedback_type'} = $1;
                }

                if ($line =~ /User\-Agent\:\s*(.*)/i) {
                    $self->{'efr'}{'user_agent'} = $1;
                }
                if ($line =~ /Version\:\s*(.*)/i) {
                    $self->{'efr'}{'version'} = $1;
                }
                my $email_regexp = Sympa::Tools::get_regexp('email');
                if ($line =~ /Original\-Rcpt\-To\:\s*($email_regexp)\s*$/i) {
                    $self->{'efr'}{'original_rcpt'} = $1;
                    chomp $self->{'efr'}{'original_rcpt'};
                }
            }
        } elsif ($content =~ /message\/rfc822/) {
            my @subparts = $p->parts();
            foreach my $subp (@subparts) {
                my $subph = $subp->head;
                $self->{'listname'} = $subph->get('X-Loop');
            }
        }
    }
    my $forward;
    ## RFC compliance remark: We do something if there is an abuse or an
    ## unsubscribe request.
    ## We don't throw an error if we find another kind of feedback (fraud,
    ## miscategorized, not-spam, virus or other)
    ## but we don't take action if we meet them yet. This is to be done, if
    ## relevant.
    if ((   $self->{'efr'}{'feedback_type'} =~
            /(abuse|opt-out|opt-out-list|fraud|miscategorized|not-spam|virus|other)/i
        )
        && (defined $self->{'efr'}{'version'})
        && (defined $self->{'efr'}{'user_agent'})
        ) {

        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG,
            'Email Feedback Report: %s feedback-type: %s',
            $self->{'listname'}, $self->{'efr'}{'feedback_type'});
        if (defined $self->{'efr'}{'original_rcpt'}) {
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::DEBUG,
                'Recognized user : %s list',
                $self->{'efr'}{'original_rcpt'}
            );
            my @lists;

            if (($self->{'efr'}{'feedback_type'} =~ /(opt-out-list|abuse)/i)
                && (defined $self->{'listname'})) {
                $self->{'listname'} = lc($self->{'listname'});
                chomp $self->{'listname'};
                $self->{'listname'} =~ /(.*)\@(.*)/;
                $self->{'listname'}  = $1;
                $self->{'robotname'} = $2;
                my $list =
                    Sympa::List->new($self->{'listname'}, $self->{'robotname'});
                unless ($list) {
                    Sympa::Log::Syslog::do_log(
                        Sympa::Log::Syslog::ERR,
                        'Skipping Feedback Report (spool bounce, messagekey =%s) for unknown list %s@%s',
                        $self->{'messagekey'},
                        $self->{'listname'},
                        $self->{'robotname'}
                    );
                    return undef;
                }
                push @lists, $list;
            } elsif ($self->{'efr'}{'feedback_type'} =~ /opt-out/
                && (defined $self->{'efr'}{'original_rcpt'})) {
                @lists = Sympa::List::get_which($self->{'efr'}{'original_rcpt'},
                    $self->{'robotname'}, 'member');
            } else {
                Sympa::Log::Syslog::do_log(
                    Sympa::Log::Syslog::NOTICE,
                    'Ignoring Feedback Report (bounce where messagekey=%s) : Nothing to do for this feedback type.(feedback_type:%s, original_rcpt:%s, listname:%s)',
                    $self->{'messagekey'},
                    $self->{'efr'}{'feedback_type'},
                    $self->{'efr'}{'original_rcpt'},
                    $self->{'listname'}
                );
                return 0;
            }
            foreach my $list (@lists) {
                my $result =
                    Sympa::Scenario::request_action($list, 'unsubscribe', 'smtp',
                    {'sender' => $self->{'efr'}{'original_rcpt'}});
                my $action;
                $action = $result->{'action'} if (ref($result) eq 'HASH');
                if ($action =~ /do_it/i) {
                    if ($list->is_list_member(
                            $self->{'efr'}{'original_rcpt'}
                        )
                        ) {
                        $list->delete_list_member(
                            'users'   => [$self->{'efr'}{'original_rcpt'}],
                            'exclude' => ' 1'
                        );

                        Sympa::Log::Syslog::do_log(
                            Sympa::Log::Syslog::NOTICE,
                            '%s has been removed from %s because abuse feedback report',
                            $self->{'efr'}{'original_rcpt'},
                            $list->name
                        );
                        unless (
                            $list->send_notify_to_owner(
                                'automatic_del',
                                {   'who' => $self->{'efr'}{'original_rcpt'},
                                    'by'  => 'listmaster'
                                }
                            )
                            ) {
                            Sympa::Log::Syslog::do_log(
                                Sympa::Log::Syslog::NOTICE,
                                'Unable to send notify "automatic_del" to %s list owner',
                                $list->name
                            );
                        }
                    } else {
                        Sympa::Log::Syslog::do_log(
                            Sympa::Log::Syslog::ERR,
                            'Ignore Feedback Report (bounce where messagekey =%s) for list %s@%s : user %s not subscribed',
                            $self->{'messagekey'},
                            $list->name,
                            $self->{'robotname'},
                            $self->{'efr'}{'original_rcpt'}
                        );
                        unless (
                            $list->send_notify_to_owner(
                                'warn-signoff',
                                {'who' => $self->{'efr'}{'original_rcpt'}}
                            )
                            ) {
                            Sympa::Log::Syslog::do_log(
                                Sympa::Log::Syslog::NOTICE,
                                'Unable to send notify "warn-signoff" to %s list owner',
                                $list
                            );
                        }
                    }
                } else {
                    $forward = 'request';
                    Sympa::Log::Syslog::do_log(
                        Sympa::Log::Syslog::ERR,
                        'Ignore Feedback Report (bounce where messagekey=%s) for list %s : user %s is not allowed to unsubscribe',
                        $self->{'messagekey'},
                        $list,
                        $self->{'efr'}{'original_rcpt'}
                    );
                }
            }
        } else {
            Sympa::Log::Syslog::do_log(
                Sympa::Log::Syslog::ERR,
                'Ignoring Feedback Report (bounce where messagekey=%s) : Unknown Original-Rcpt-To field. Can\'t do anything. (feedback_type:%s, listname:%s)',
                $self->{'messagekey'},
                $self->{'efr'}{'feedback_type'},
                $self->{'listname'}
            );
            return undef;
        }
    } else {
        return undef;
    }
    return 1;
}

sub process_ndn {
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, '(%s)', @_);
    my $self = shift;

    unless (ref $self->{'list'} and $self->{'list'}->isa('Sympa::List')) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'Skipping bounce %s for unknown list %s@%s',
            $self, $self->{'listname'}, $self->{'robotname'});
        return undef;
    } else {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3,
            'Processing bounce %s for list %s',
            $self->{'messagekey'}, $self->{'list'});

        my (%hash, $from);
        my $bounce_dir = $self->{'list'}->get_bounce_dir();

        ## RFC1891 compliance check
        $self->rfc1891(\%hash, \$from);

        unless ($self->{'ndn'}{'nbrcpt'}) {
            ## Analysis of bounced message
            $self->anabounce(\%hash, \$from);

            # Voir pour appeler une methode de parsing des dsn qui maj la bdd
            # updatedatabase(%hash);
        }

        ## Bounce directory
        if (!-d $bounce_dir) {
            unless (mkdir $bounce_dir, 0777) {
                Sympa::Site->send_notify_to_listmaster(
                    'bounce_intern_error',
                    {   'error' =>
                            "Failed to list create bounce directory $bounce_dir"
                    }
                );
                Sympa::Log::Syslog::do_log(
                    Sympa::Log::Syslog::ERR,
                    'Could not create %s: %s bounced dir, check bounce_path in wwsympa.conf',
                    $bounce_dir,
                    $ERRNO
                );
                exit;
            }
        }

        my $adr_count;
        ## Bouncing addresses
        # Voir si pas mettre un test conditionnel sur le status code pour
        # detecter les dsn positifs et ne pas fausser les statistiques de
        # l'abonné.
        # Peut être possibilité de lancer la maj des tables pour chaque
        # recipient ici a condition d'avoir approfondi le parsing en amont.
        while (my ($rcpt, $status) = each %hash) {
            $adr_count++;
            my $bouncefor = $self->{'who'};
            $bouncefor ||= $rcpt;

            unless ($self->store_bounce($bounce_dir, $bouncefor)) {
                Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
                    'Unable to store bounce %s. Aborting.',
                    $self->get_msg_id);
                return undef;
            }
            unless (
                $self->update_subscriber_bounce_history(
                    $rcpt, $bouncefor, canonicalize_status($status)
                )
                ) {
                Sympa::Log::Syslog::do_log(
                    Sympa::Log::Syslog::ERR,
                    'Unable to update bounce history for user %s, bounce %s. Aborting.',
                    $bouncefor,
                    $self->get_msg_id
                );
                return undef;
            }
        }

        ## No address found in the bounce itself
        unless ($adr_count) {

            if ($self->{'who'}) {

                # rcpt not recognized in the bounce but VERP was used
                unless ($self->store_bounce($bounce_dir, $self->{'who'})) {
                    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
                        'Unable to store bounce %s. Aborting.',
                        $self->get_msg_id);
                    return undef;
                }
                unless (
                    $self->update_subscriber_bounce_history(
                        'unknown', $self->{'who'}
                    )
                    ) {
                    Sympa::Log::Syslog::do_log(
                        Sympa::Log::Syslog::ERR,
                        'Unable to update bounce history for user %s, bounce %s. Aborting.',
                        $self->{'who'},
                        $self->get_msg_id
                    );
                    return undef;
                }
            } else {    # no VERP and no rcpt recognized
                Sympa::Log::Syslog::do_log(
                    Sympa::Log::Syslog::INFO,
                    'error: no address found in message from %s for list %s',
                    $from,
                    $self->{'list'}
                );
                return undef;
            }
        }
    }
    return 1;
}

## copy the bounce to the appropriate filename
sub store_bounce {

    my $self       = shift;
    my $bounce_dir = shift;
    my $rcpt       = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG, 'store_bounce(%s,%s,%s)', $self,
        $bounce_dir, $rcpt);

    my $filename = Sympa::Tools::escape_chars($rcpt);

    unless (open ARC, ">$bounce_dir/$filename") {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::NOTICE,
            "Unable to write $bounce_dir/$filename");
        return undef;
    }
    print ARC $self->get_message_as_string;
    close ARC;
    close BOUNCE;
    return 1;
}

## Set error message to a status RFC1893 compliant
sub canonicalize_status {

    my $status = shift;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, 'Canonicalizing status %s', $status);

    if ($status !~ /^\d+\.\d+\.\d+$/) {
        if ($equiv{$status}) {
            $status = $equiv{$status};
        } else {
            return undef;
        }
    }
    return $status;
}

## update subscriber information
# $bouncefor : the email address the bounce is related for (may be extracted
# using verp)
# $rcpt : the email address recognized in the bounce itself. In most case
# $rcpt eq $bouncefor

sub update_subscriber_bounce_history {
    my $self      = shift;
    my $list      = $self->{'list'};
    my $rcpt      = shift;
    my $bouncefor = shift;
    my $status    = shift;
    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, '(%s, %s, %s, %s, list=%s)',
        $self, $rcpt, $bouncefor, $status, $list);

    my $first = my $last = time;
    my $count = 0;

    my $user = $list->get_list_member($bouncefor);

    unless ($user) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'Subscriber %s not found in list %s : %s',
            $bouncefor, $list);
        return undef;
    }

    if ($user->{'bounce'} =~ /^(\d+)\s\d+\s+(\d+)/) {
        ($first, $count) = ($1, $2);
    }
    $count++;
    if ($rcpt ne $bouncefor) {
        Sympa::Log::Syslog::do_log(
            Sympa::Log::Syslog::NOTICE,
            'Bouncing address identified with VERP: actual rcpt: %s / subscriber address: %s (bounce %s)',
            $rcpt,
            $bouncefor,
            $self->get_msg_id
        );
        Sympa::Log::Syslog::do_log(
            Sympa::Log::Syslog::DEBUG,
            'update_subscribe (%s, bounce-> %s %s %s %s,bounce_address->%s)',
            $bouncefor,
            $first,
            $last,
            $count,
            $status,
            $rcpt
        );
        $list->update_list_member(
            $bouncefor,
            {   'bounce'         => "$first $last $count $status",
                'bounce_address' => $rcpt
            }
        );
        Sympa::Log::Database::db_log(
            'robot'        => $list->domain,
            'list'         => $list->name,
            'action'       => 'get_bounce',
            'parameters'   => "address=$rcpt",
            'target_email' => $bouncefor,
            'msg_id'       => '',
            'status'       => 'error',
            'error_type'   => $status,
            'daemon'       => 'bounced'
        );
    } else {
        $list->update_list_member($bouncefor,
            {'bounce' => "$first $last $count $status"});
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::NOTICE,
            'Received bounce for email address %s, list %s',
            $bouncefor, $list);
        Sympa::Log::Database::db_log(
            'robot'        => $list->domain,
            'list'         => $list->name,
            'action'       => 'get_bounce',
            'target_email' => $bouncefor,
            'msg_id'       => '',
            'status'       => 'error',
            'error_type'   => $status,
            'daemon'       => 'bounced'
        );
    }
}

## RFC1891 compliance check
sub rfc1891 {
    my ($self, $result) = @_;
    local $RS = "\n";

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2,
        'RFC 1891 compliance check for bounce %s',
        $self->get_msg_id);
    my $nbrcpt;

    my $entity = $self->get_mime_message;
    unless ($entity) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR,
            'No message object to process. Aborting.');
        return undef;
    }

    my @parts = $entity->parts();

    foreach my $p (@parts) {
        my $h       = $p->head();
        my $content = $h->get('Content-type');

        next unless ($content =~ /message\/delivery-status/i);

        my $body = $p->body();

        ## Fork, communicate with child via BODY
        my $pid = open BODY, "-|";

        unless (defined($pid)) {
            die 'Fork failed';
        }

        if (!$pid) {
            ## Child process
            print STDOUT @$body;
            exit;
        } else {
            ## Multiline paragraph separator
            local $RS = '';

            while (<BODY>) {

                my ($status, $recipient);
                if (/^Status:\s*(\d+\.\d+\.\d+)(\s|$)/mi) {
                    $status = $1;
                }

                if (   /^Original-Recipient:\s*rfc822\s*;\s*(.*)$/mi
                    || /^Final-Recipient:\s*rfc822\s*;\s*(.*)$/mi) {
                    $recipient = $1;
                    if ($recipient =~ /\@.+:(.+)$/) {
                        $recipient = $1;
                    }
                    $recipient =~ s/^<(.*)>$/$1/;
                    $recipient =~ y/[A-Z]/[a-z]/;
                }

                if ($recipient and $status) {
                    $result->{$recipient} = $status;
                    $nbrcpt++;
                }
            }
            local $RS = "\n";
            close BODY;
        }
    }
    $self->{'ndn'}{'nbrcpt'} = $nbrcpt;
    return 1;
}

## Fixes an STMP address
sub corrige {

    my ($adr, $from) = @_;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG3, 'Fixing address %s using from %s',
        $adr, $from);
    ## adresse X400
    if ($adr =~ /^\//) {

        my (%x400, $newadr);

        my @detail = split /\//, $adr;
        foreach (@detail) {

            my ($var, $val) = split /=/;
            $x400{$var} = $val;

            #print "\t$var <=> $val\n";

        }

        $newadr = $x400{PN} || "$x400{s}";
        $newadr = "$x400{g}." . $newadr if $x400{g};
        my (undef, $d) = split /\@/, $from;

        $newadr .= "\@$d";

        return $newadr;

    } elsif ($adr =~ /\@/) {

        return $adr;

    } elsif ($adr =~ /\!/) {

        my ($dom, $loc) = split /\!/, $adr;
        return "$loc\@$dom";

    } else {

        my (undef, $d) = split /\@/, $from;
        my $newadr = "$adr\@$d";

        return $newadr;

    }
}
## Analyse d'un rapport de non-remise
## Param 1 : descripteur du fichier contenant le bounce
## //    2 : reference d'un hash pour retourner @ en erreur
## //    3 : reference d'un tableau pour retourner des stats
## //    4 : reference d'un tableau pour renvoyer le bounce
sub anabounce {

    my ($self, $result, $from) = @_;

    Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::DEBUG2, 'Analyzing bounce %s',
        $self->get_msg_id);

    # this old subroutine do not use message object but parse the message
    # itself!!! It should be rewrited.
    # a temporary file is used when introducing database spool. It should be
    # rewrited! It should be rewrited! It should be rewrited! Yes, it should
    # be rewrited!
    my $tmpfile = Sympa::Site->tmpdir . '/bounce.' . $PID;
    my $fh;
    unless (open $fh, '>', $tmpfile) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR, 'Could not create %s', $tmpfile);
        return undef;
    }
    print $fh $self->as_string();    # raw message
    close $fh;
    unless (open BOUNCE, '<', $tmpfile) {
        Sympa::Log::Syslog::do_log(Sympa::Log::Syslog::ERR, 'Could not read %s', $tmpfile);
        return undef;
    }

    my $entete = 1;
    my $type;
    my %info;
    my ($qmail,                $type_9,      $type_18,
        $exchange,             $ibm_vm,      $lotus,
        $sendmail_5,           $yahoo,       $type_21,
        $exim,                 $vines,       $mercury_143,
        $altavista,            $mercury_131, $type_31,
        $type_32,              $exim_173,    $type_38,
        $type_39,              $type_40,     $pmdf,
        $following_recipients, $postfix,     $groupwise7
    );

    ## Le champ separateur de paragraphe est un ensemble
    ## de lignes vides
    local $RS = '';

    ## Parcour du bounce, paragraphe par paragraphe
    foreach (<BOUNCE>) {
        if ($entete) {
            undef $entete;
            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            my ($champ_courant, %champ);
            foreach (@paragraphe) {

                if (/^(\S+):\s*(.*)$/) {
                    $champ_courant = $1;
                    $champ_courant =~ y/[A-Z]/[a-z]/;
                    $champ{$champ_courant} = $2;
                } elsif (/^\s+(.*)$/) {
                    $champ{$champ_courant} .= " $1";
                }

                ## Le champ From:
                if ($champ{'from'} and $champ{from} =~ /([^\s<]+@[^\s>]+)/) {
                    $$from = $1;
                }
            }
            local $RS = '';

            $champ{from} =~ s/^.*<(.+)[\>]$/$1/;
            $champ{from} =~ y/[A-Z]/[a-z]/;

            if ($champ{subject} =~
                /^Returned mail: (Quota exceeded for user (\S+))$/) {
                $info{$2}{error} = $1;
                $type = 27;
            } elsif ($champ{subject} =~
                /^Returned mail: (message not deliverable): \<(\S+)\>$/) {
                $info{$2}{error} = $1;
                $type = 34;
            }
            if (    $champ{'x-failed-recipients'}
                and $champ{'x-failed-recipients'} =~ /^\s*(\S+)$/) {
                $info{$1}{error} = "";
            } elsif ($champ{'x-failed-recipients'}
                and $champ{'x-failed-recipients'} =~ /^\s*(\S+),/) {
                for my $xfr (split(/\s*,\s*/, $champ{'x-failed-recipients'}))
                {
                    $info{$xfr}{error} = "";
                }
            }
        } elsif (
            /^\s*-+ The following addresses (had permanent fatal errors|had transient non-fatal errors|have delivery notifications) -+/m
            ) {
            my $adr;
            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {
                if (/^(\S[^\(]*)/) {
                    $adr = $1;
                    my $error = $2;
                    $adr =~ s/^[\"\<](.+)[\"\>]\s*$/$1/;

                    #print "\tADR : #$adr#\n";
                    $info{$adr}{error} = $error;
                    $type = 1;
                } elsif (/^\s+\(expanded from: (.+)\)/) {

                    #print "\tEXPANDED $adr : $1\n";
                    $info{$adr}{expanded} = $1;
                    $info{$adr}{expanded} =~ s/^[\"\<](.+)[\"\>]$/$1/;
                }
            }
            local $RS = '';
        } elsif (/^\s+-+\sTranscript of session follows\s-+/m) {
            my $adr;
            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {
                if (/^(\d{3}\s)?(\S+|\".*\")\.{3}\s(.+)$/) {
                    $adr = $2;
                    my $cause = $3;
                    $cause =~ s/^(.*) [\(\:].*$/$1/;
                    foreach $a (split /,/, $adr) {
                        $a =~ s/^[\"\<]([^\"\>]+)[\"\>]$/$1/;
                        $info{$a}{error} = $cause;
                        $type = 2;
                    }
                } elsif (/^\d{3}\s(too many hops).*to\s(.*)$/i) {
                    $adr = $2;
                    my $cause = $1;
                    foreach $a (split /,/, $adr) {
                        $a =~ s/^[\"\<](.+)[\"\>]$/$1/;
                        $info{$a}{error} = $cause;
                        $type = 2;
                    }
                } elsif (/^\d{3}\s.*\s([^\s\)]+)\.{3}\s(.+)$/) {
                    $adr = $1;
                    my $cause = $2;
                    $cause =~ s/^(.*) [\(\:].*$/$1/;
                    foreach $a (split /,/, $adr) {
                        $a =~ s/^[\"\<](.+)[\"\>]$/$1/;
                        $info{$a}{error} = $cause;
                        $type = 2;
                    }
                }
            }
            local $RS = '';

            ## Rapport Compuserve
        } elsif (/^Receiver not found:/m) {

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                $info{$2}{error} = $1 if /^(.*): (\S+)/;
                $type = 3;

            }
            local $RS = '';

        } elsif (/^\s*-+ Special condition follows -+/m) {

            my ($cause, $adr);

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/^(Unknown QuickMail recipient\(s\)):/) {
                    $cause = $1;
                    $type  = 4;

                } elsif (/^\s+(.*)$/ and $cause) {

                    $adr = $1;
                    $adr =~ s/^[\"\<](.+)[\"\>]$/$1/;
                    $info{$adr}{error} = $cause;
                    $type = 4;

                }
            }
            local $RS = '';

        } elsif (/^Your message adressed to .* couldn\'t be delivered/m) {

            my $adr;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/^Your message adressed to (.*) couldn\'t be delivered, for the following reason :/
                    ) {
                    $adr = $1;
                    $adr =~ s/^[\"\<](.+)[\"\>]$/$1/;
                    $type = 5;

                } else {

                    /^(.*)$/;
                    $info{$adr}{error} = $1;
                    $type = 5;

                }
            }
            local $RS = '';

            ## Rapport X400
        } elsif (
            /^Your message was not delivered to:\s+(\S+)\s+for the following reason:\s+(.+)$/m
            ) {

            my ($adr, $error) = ($1, $2);
            $error =~ s/Your message.*$//;
            $info{$adr}{error} = $error;
            $type = 6;

            ## Rapport X400
        } elsif (
            /^Your message was not delivered to\s+(\S+)\s+for the following reason:\s+(.+)$/m
            ) {

            my ($adr, $error) = ($1, $2);
            $error =~ s/\(.*$//;
            $info{$adr}{error} = $error;
            $type = 6;

            ## Rapport X400
        } elsif (/^Original-Recipient: rfc822; (\S+)\s+Action: (.*)$/m) {

            $info{$1}{error} = $2;
            $type = 16;

            ## Rapport NTMail
        } elsif (/^The requested destination was:\s+(.*)$/m) {
            $type = 7;
        } elsif (($type == 7) && (/^\s+(\S+)/)) {
            undef $type;
            my $adr = $1;
            $adr =~ s/^[\"\<](.+)[\"\>]$/$1/;
            next unless $adr;
            $info{$adr}{'error'} = '';
            ## Rapport Qmail dans prochain paragraphe
        } elsif (/^Hi\. This is the qmail-send program/m) {
            $qmail = 1;
            ## Rapport Qmail
        } elsif ($qmail) {
            undef $qmail if /^[^<]/;
            if (/^<(\S+)>:\n(.*)/m) {
                $info{$1}{error} = $2;
                $type = 8;
            }
            local $RS = '';
            ## Sendmail
        } elsif (
            /^Your message was not delivered to the following recipients:/m) {
            $type_9 = 1;
        } elsif ($type_9) {
            undef $type_9;
            if (/^\s*(\S+):\s+(.*)$/m) {
                $info{$1}{error} = $2;
                $type = 9;
            }

            ## Rapport Exchange dans prochain paragraphe
        } elsif (/^The following recipient\(s\) could not be reached:/m
            or /^did not reach the following recipient\(s\):/m) {
            $exchange = 1;
            ## Rapport Exchange
        } elsif ($exchange) {
            undef $exchange;
            if (/^\s*(\S+).*\n\s+(.*)$/m) {
                $info{$1}{error} = $2;
                $type = 10;
            }

            ## IBM VM dans prochain paragraphe
        } elsif (
            /^Your mail item could not be delivered to the following users/m)
        {
            $ibm_vm = 1;
            ## Rapport IBM VM
        } elsif ($ibm_vm) {
            undef $ibm_vm;
            if (/^(.*)\s+\---->\s(\S+)$/m) {
                $info{$2}{error} = $1;
                $type = 12;
            }
            ## Rapport Lotus SMTP dans prochain paragraphe
        } elsif (/^-+\s+Failure Reasons\s+-+/m) {
            $lotus = 1;
            ## Rapport Lotus SMTP
        } elsif ($lotus) {
            undef $lotus;
            if (/^(.*)\n(\S+)$/m) {
                $info{$2}{error} = $1;
                $type = 13;
            }
            ## Rapport Sendmail 5 dans prochain paragraphe
        } elsif (/^\-+\sTranscript of session follows\s\-+/m) {
            $sendmail_5 = 1;
            ## Rapport  Sendmail 5
        } elsif ($sendmail_5) {
            undef $sendmail_5;
            if (/<(\S+)>\n\S+, (.*)$/m) {
                $info{$1}{error} = $2;
                $type = 14;
            }
            ## Rapport Smap
        } elsif (/^\s+-+ Transcript of Report follows -+/) {
            my $adr;
            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {
                if (/^Rejected-For: (\S+),/) {
                    $adr               = $1;
                    $info{$adr}{error} = "";
                    $type              = 17;
                } elsif (/^\s+explanation (.*)$/) {
                    $info{$adr}{error} = $1;
                }
            }
            local $RS = '';
        } elsif (/^\s*-+Message not delivered to the following:/) {
            $type_18 = 1;
        } elsif ($type_18) {
            undef $type_18;
            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/^\s*(\S+)\s+(.*)$/) {

                    $info{$1}{error} = $2;
                    $type = 18;

                }
            }
            local $RS = '';
        } elsif (/unable to deliver following mail to recipient\(s\):/m) {
            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/^\d+ <(\S+)>\.{3} (.+)$/) {
                    $info{$1}{error} = $2;
                    $type = 19;
                }
            }
            local $RS = '';
            ## Rapport de Yahoo dans paragraphe suivant
        } elsif (/^Unable to deliver message to the following address\(es\)/m)
        {
            $yahoo = 1;
            ## Rapport Yahoo
        } elsif ($yahoo) {
            undef $yahoo;
            if (/^<(\S+)>:\s(.+)$/m) {

                $info{$1}{error} = $2;
                $type = 20;

            }
        } elsif (/^Content-Description: Session Transcript/m) {
            $type_21 = 1;
        } elsif ($type_21) {
            undef $type_21;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {
                if (/<(\S+)>\.{3} (.*)$/) {
                    $info{$1}{error} = $2;
                    $type = 21;
                }
            }
            local $RS = '';
        } elsif (
            /^Your message has encountered delivery problems\s+to local user \S+\.\s+\(Originally addressed to (\S+)\)/m
            or
            /^Your message has encountered delivery problems\s+to (\S+)\.$/m
            or
            /^Your message has encountered delivery problems\s+to the following recipient\(s\):\s+(\S+)$/m
            ) {

            my $adr = $2 || $1;
            $info{$adr}{error} = "";
            $type = 22;
        } elsif (/^(The user return_address (\S+) does not exist)/) {
            $info{$2}{error} = $1;
            $type = 23;
            ## Rapport Exim paragraphe suivant
        } elsif (
            /^A message that you sent could not be delivered to all of its recipients/m
            or /^The following address\(es\) failed:/m) {
            $exim = 1;
            ## Rapport Exim
        } elsif ($exim) {
            undef $exim;
            if (/^\s*(\S+):\s+(.*)$/m) {

                $info{$1}{error} = $2;
                $type = 24;

            } elsif (/^\s*(\S+)$/m) {
                $info{$1}{error} = "";
            }

            ## Rapport VINES-ISMTP par. suivant
        } elsif (/^Message not delivered to recipients below/m) {

            $vines = 1;

            ## Rapport VINES-ISMTP
        } elsif ($vines) {

            undef $vines;

            if (/^\s+\S+:.*\s+(\S+)$/m) {

                $info{$1}{error} = "";
                $type = 25;

            }

            ## Rapport Mercury 1.43 par. suivant
        } elsif (
            /^The local mail transport system has reported the following problems/m
            ) {

            $mercury_143 = 1;

            ## Rapport Mercury 1.43
        } elsif ($mercury_143) {

            undef $mercury_143;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/<(\S+)>\s+(.*)$/) {

                    $info{$1}{error} = $2;
                    $type = 26;
                }
            }
            local $RS = '';

            ## Rapport de AltaVista Mail dans paragraphe suivant
        } elsif (/unable to deliver mail to the following recipient\(s\):/m) {

            $altavista = 1;

            ## Rapport AltaVista Mail
        } elsif ($altavista) {

            undef $altavista;

            if (/^(\S+):\n.*\n\s*(.*)$/m) {

                $info{$1}{error} = $2;
                $type = 27;

            }

            ## Rapport SMTP32
        } elsif (/^(User mailbox exceeds allowed size): (\S+)$/m) {

            $info{$2}{error} = $1;
            $type = 28;

        } elsif (/^The following recipients did not receive this message:$/m)
        {

            $following_recipients = 1;

        } elsif ($following_recipients) {

            undef $following_recipients;

            if (/^\s+<(\S+)>/) {

                $info{$1}{error} = "";
                $type = 29;

            }

            ## Rapport Mercury 1.31 par. suivant
        } elsif (
            /^One or more addresses in your message have failed with the following/m
            ) {

            $mercury_131 = 1;

            ## Rapport Mercury 1.31
        } elsif ($mercury_131) {

            undef $mercury_131;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/<(\S+)>\s+(.*)$/) {

                    $info{$1}{error} = $2;
                    $type = 30;
                }
            }
            local $RS = '';

        } elsif (/^The following recipients haven\'t received this message:/m)
        {

            $type_31 = 1;

        } elsif ($type_31) {

            undef $type_31;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/(\S+)$/) {

                    $info{$1}{error} = "";
                    $type = 31;
                }
            }
            local $RS = '';

        } elsif (/^The following destination addresses were unknown/m) {

            $type_32 = 1;

        } elsif ($type_32) {

            undef $type_32;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/<(\S+)>/) {

                    $info{$1}{error} = "";
                    $type = 32;
                }
            }
            local $RS = '';

        } elsif (/^-+Transcript of session follows\s-+$/m) {

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/^(\S+)$/) {

                    $info{$1}{error} = "";
                    $type = 33;

                } elsif (/<(\S+)>\.{3} (.*)$/) {

                    $info{$1}{error} = $2;
                    $type = 33;

                }
            }
            local $RS = '';

            ## Rapport Bigfoot
        } elsif (/^The message you tried to send to <(\S+)>/m) {
            $info{$1}{error} = "destination mailbox unavailable";

        } elsif (/^The destination mailbox (\S+) is unavailable/m) {

            $info{$1}{error} = "destination mailbox unavailable";

        } elsif (
            /^The following message could not be delivered because the address (\S+) does not exist/m
            ) {

            $info{$1}{error} = "user unknown";

        } elsif (/^Error-For:\s+(\S+)\s/) {

            $info{$1}{error} = "";

            ## Rapport Exim 1.73 dans proc. paragraphe
        } elsif (
            /^The address to which the message has not yet been delivered is:/m
            ) {

            $exim_173 = 1;

            ## Rapport Exim 1.73
        } elsif ($exim_173) {

            undef $exim_173;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/(\S+)/) {

                    $info{$1}{error} = "";
                    $type = 37;
                }
            }
            local $RS = '';

        } elsif (
            /^This Message was undeliverable due to the following reason:/m) {

            $type_38 = 1;

        } elsif ($type_38) {

            undef $type_38 if /Recipient:/;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/\s+Recipient:\s+<(\S+)>/) {

                    $info{$1}{error} = "";
                    $type = 38;

                } elsif (/\s+Reason:\s+<(\S+)>\.{3} (.*)/) {

                    $info{$1}{error} = $2;
                    $type = 38;

                }
            }
            local $RS = '';

        } elsif (/Your message could not be delivered to:/m) {

            $type_39 = 1;

        } elsif ($type_39) {

            undef $type_39;

            if (/^(\S+)/) {

                $info{$1}{error} = "";
                $type = 39;

            }
        } elsif (/Session Transcription follow:/m) {

            if (/^<+\s+\d+\s+(.*) for \((.*)\)$/m) {

                $info{$2}{error} = $1;
                $type = 43;

            }

        } elsif (
            /^This message was returned to you for the following reasons:/m) {

            $type_40 = 1;

        } elsif ($type_40) {

            undef $type_40;

            if (/^\s+(.*): (\S+)/) {

                $info{$2}{error} = $1;
                $type = 40;

            }

            ## Rapport PMDF dans proc. paragraphe
        } elsif (
            /^Your message cannot be delivered to the following recipients:/m
            or
            /^Your message has been enqueued and undeliverable for \d day\s*to the following recipients/m
            ) {

            $pmdf = 1;

            ## Rapport PMDF
        } elsif ($pmdf) {

            my $adr;
            undef $pmdf;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/\s+Recipient address:\s+(\S+)/) {

                    $adr               = $1;
                    $info{$adr}{error} = "";
                    $type              = 41;

                } elsif (/\s+Reason:\s+(.*)$/) {

                    $info{$adr}{error} = $1;
                    $type = 41;

                }
            }
            local $RS = '';

            ## Rapport MDaemon
        } elsif (/^(\S+) - (no such user here)\.$/m) {

            $info{$1}{error} = $2;
            $type = 42;

            # Postfix dans le prochain paragraphe
        } elsif (/^This is the Postfix program/m
            || /^This is the mail system at host/m) {
            $postfix = 1;
            ## Rapport Postfix
        } elsif ($postfix) {

            undef $postfix
                if /THIS IS A WARNING/;    # Pas la peine de le traiter

            if (/^<(\S+)>:\s(.*)/m) {
                my ($addr, $error) = ($1, $2);

                if ($error =~ /^host\s[^:]*said:\s(\d+)/) {
                    $info{$addr}{error} = $1;
                } elsif ($error =~ /^([^:]+):/) {
                    $info{$addr}{error} = $1;
                } else {
                    $info{$addr}{error} = $error;
                }
            }
            local $RS = '';
        } elsif (
            /^The message that you sent was undeliverable to the following:/)
        {

            $groupwise7 = 1;

        } elsif ($groupwise7) {

            undef $groupwise7;

            ## Parcour du paragraphe
            my @paragraphe = split /\n/, $_;
            local $RS = "\n";
            foreach (@paragraphe) {

                if (/^\s+(\S*) \((.+)\)/) {

                    $info{$1}{error} = $2;

                }
            }

            local $RS = '';

            ## Wanadoo
        } elsif (/^(\S+); Action: Failed; Status: \d.\d.\d \((.*)\)/m) {
            $info{$1}{error} = $2;
        }
    }

    close BOUNCE;
    my $count = 0;
    ## On met les adresses au clair
    foreach my $a1 (keys %info) {

        next unless ($a1 and ref($info{$a1}));

        $count++;
        my ($a2, $a3);

        $a2 = $a1;

        unless (!$info{$a1}{expanded}
            or ($a1 =~ /\@/ and $info{$a1}{expanded} !~ /\@/)) {

            $a2 = $info{$a1}{expanded};

        }

        $a3 = corrige($a2, $$from);

        $a3 =~ y/[A-Z]/[a-z]/;
        $a3 =~ s/^<(.*)>$/$1/;

        $result->{$a3} = lc($info{$a1}{error});
    }

    return $count;
}

1;
