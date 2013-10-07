# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:et:sw=4:textwidth=78
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

Sympa::WWSympa - WWSympa functions

=head1 DESCRIPTION

This module provides functions for wwsympa.

=cut

package Sympa::WWSympa;

use English qw(-no_match_vars);

use Sympa::Log::Syslog;

## No longer used: Use Sympa::List->get_option_title().
%reception_mode = (
    'mail'        => {'gettext_id' => 'standard (direct reception)'},
    'digest'      => {'gettext_id' => 'digest MIME format'},
    'digestplain' => {'gettext_id' => 'digest plain text format'},
    'summary'     => {'gettext_id' => 'summary mode'},
    'notice'      => {'gettext_id' => 'notice mode'},
    'txt'         => {'gettext_id' => 'text-only mode'},
    'html'        => {'gettext_id' => 'html-only mode'},
    'urlize'      => {'gettext_id' => 'urlize mode'},
    'nomail'      => {'gettext_id' => 'no mail (useful for vacations)'},
    'not_me'      => {'gettext_id' => 'you do not receive your own posts'}
);

## Cookie expiration periods with corresponding entry in NLS
%cookie_period = (
    0     => {'gettext_id' => "session"},
    10    => {'gettext_id' => "10 minutes"},
    30    => {'gettext_id' => "30 minutes"},
    60    => {'gettext_id' => "1 hour"},
    360   => {'gettext_id' => "6 hours"},
    1440  => {'gettext_id' => "1 day"},
    10800 => {'gettext_id' => "1 week"},
    43200 => {'gettext_id' => "30 days"});

## No longer used: Use Sympa::List->get_option_title().
%visibility_mode = (
    'noconceal' => {'gettext_id' => "listed in the list review page"},
    'conceal'   => {'gettext_id' => "concealed"}
);

## Filenames with corresponding entry in NLS set 15
%filenames = (
    'welcome.tt2'             => {'gettext_id' => "welcome message"},
    'bye.tt2'                 => {'gettext_id' => "unsubscribe message"},
    'removed.tt2'             => {'gettext_id' => "deletion message"},
    'message.footer'          => {'gettext_id' => "message footer"},
    'message.header'          => {'gettext_id' => "message header"},
    'remind.tt2'              => {'gettext_id' => "remind message"},
    'reject.tt2'              => {'gettext_id' => "editor rejection message"},
    'invite.tt2'              => {'gettext_id' => "subscribing invitation message"},
    'helpfile.tt2'            => {'gettext_id' => "help file"},
    'lists.tt2'               => {'gettext_id' => "directory of lists"},
    'global_remind.tt2'       => {'gettext_id' => "global remind message"},
    'summary.tt2'             => {'gettext_id' => "summary message"},
    'info'                    => {'gettext_id' => "list description"},
    'homepage'                => {'gettext_id' => "list homepage"},
    'create_list_request.tt2' => {'gettext_id' => "list creation request message"},
    'list_created.tt2'        => {'gettext_id' => "list creation notification message"},
    'your_infected_msg.tt2'   => {'gettext_id' => "virus infection message"},
    'list_aliases.tt2'        => {'gettext_id' => "list aliases template"}
);

%task_flavours = (
    'daily'   => {'gettext_id' => 'daily' },
    'monthly' => {'gettext_id' => 'monthly' },
    'weekly'  => {'gettext_id' => 'weekly' },
);

## Defined in RFC 1893
%bounce_status = (
    '1.0' => 'Other address status',
    '1.1' => 'Bad destination mailbox address',
    '1.2' => 'Bad destination system address',
    '1.3' => 'Bad destination mailbox address syntax',
    '1.4' => 'Destination mailbox address ambiguous',
    '1.5' => 'Destination mailbox address valid',
    '1.6' => 'Mailbox has moved',
    '1.7' => 'Bad sender\'s mailbox address syntax',
    '1.8' => 'Bad sender\'s system address',
    '2.0' => 'Other or undefined mailbox status',
    '2.1' => 'Mailbox disabled, not accepting messages',
    '2.2' => 'Mailbox full',
    '2.3' => 'Message length exceeds administrative limit',
    '2.4' => 'Mailing list expansion problem',
    '3.0' => 'Other or undefined mail system status',
    '3.1' => 'Mail system full',
    '3.2' => 'System not accepting network messages',
    '3.3' => 'System not capable of selected features',
    '3.4' => 'Message too big for system',
    '4.0' => 'Other or undefined network or routing status',
    '4.1' => 'No answer from host',
    '4.2' => 'Bad connection',
    '4.3' => 'Routing server failure',
    '4.4' => 'Unable to route',
    '4.5' => 'Network congestion',
    '4.6' => 'Routing loop detected',
    '4.7' => 'Delivery time expired',
    '5.0' => 'Other or undefined protocol status',
    '5.1' => 'Invalid command',
    '5.2' => 'Syntax error',
    '5.3' => 'Too many recipients',
    '5.4' => 'Invalid command arguments',
    '5.5' => 'Wrong protocol version',
    '6.0' => 'Other or undefined media error',
    '6.1' => 'Media not supported',
    '6.2' => 'Conversion required and prohibited',
    '6.3' => 'Conversion required but not supported',
    '6.4' => 'Conversion with loss performed',
    '6.5' => 'Conversion failed',
    '7.0' => 'Other or undefined security status',
    '7.1' => 'Delivery not authorized, message refused',
    '7.2' => 'Mailing list expansion prohibited',
    '7.3' => 'Security conversion required but not possible',
    '7.4' => 'Security features not supported',
    '7.5' => 'Cryptographic failure',
    '7.6' => 'Cryptographic algorithm not supported',
    '7.7' => 'Message integrity failure'
);

## if Crypt::CipherSaber installed store the cipher object
my $cipher;

=head1 FUNCTIONS

=over

=item load_config($file, $params)

DEPRECATED. Use Sympa::Configuration::_load_wwsconf instead.

=cut

## Load WWSympa configuration file
##sub load_config
## MOVED: use Conf::load_wwsconf().

=item get_my_url()

FIXME

=cut

sub get_my_url {
    my $return_url;

    ## Mod_ssl sets SSL_PROTOCOL ; apache-ssl sets SSL_PROTOCOL_VERSION
    if ($ENV{'HTTPS'} eq 'on') {
        $return_url = 'https';
    } else {
        $return_url = 'http';
    }

    $return_url .= '://'.main::get_header_field('HTTP_HOST');
    $return_url .= ':'.$ENV{'SERVER_PORT'} unless (($ENV{'SERVER_PORT'} eq '80')||($ENV{'SERVER_PORT'} eq '443'));
    $return_url .= $ENV{'REQUEST_URI'};
    return ($return_url);
}

=item upload_file_to_server(%parameters)

Upload source file to the destination on the server

=cut

sub upload_file_to_server {
    my (%params) = @_;
    Sympa::Log::Syslog::do_log('debug',"Uploading file from field %s to destination %s",$params{'file_field'},$params{'destination'});

    my $fh;
    unless ($fh = $params{'query'}->upload($params{'file_field'})) {
        Sympa::Log::Syslog::do_log('debug',"Cannot upload file from field $params{'file_field'}");
        return undef;
    }

    unless (open FILE, ">:bytes", $params{'destination'}) {
        Sympa::Log::Syslog::do_log('debug',"Cannot open file $params{'destination'} : $ERRNO");
        return undef;
    }
    while (<$fh>) {
        print FILE;
    }
    close FILE;
    return 1;
}

=item load_create_list_conf($robot, $basedir)

Return a hash from the create_list_conf file

Parameters:

=over

=item FIXME

=item FIXME

=back

=cut

sub load_create_list_conf {
    my ($robot) = @_;
    $robot = Sympa::Robot::clean_robot($robot);

    my $file;
    my $conf ;

    $file = $robot->get_etc_filename('create_list.conf');
    unless ($file) {
        Sympa::Log::Syslog::do_log('info', 'unable to read %s', Sympa::Constants::DEFAULTDIR . '/create_list.conf');
        return undef;
    }

    unless (open (FILE, $file)) {
        Sympa::Log::Syslog::do_log('info','Unable to open config file %s', $file);
        return undef;
    }

    while (<FILE>) {
        next if /^\s*(\#.*|\s*)$/;

        if (/^\s*(\S+)\s+(read|hidden)\s*$/i) {
            $conf->{$1} = lc($2);
        }else{
            Sympa::Log::Syslog::do_log ('info', 'unknown parameter in %s  (Ignored) %s',
                $file, $_);
            next;
        }
    }

    close FILE;
    return $conf;
}

=item get_list_list_tpl($robot, $directory)

FIXME.

=cut

sub get_list_list_tpl {
    my ($robot) = @_;
    $robot = Sympa::Robot::clean_robot($robot);

    my $list_conf;
    my $list_templates ;
    unless ($list_conf = load_create_list_conf($robot)) {
        return undef;
    }

    foreach my $dir (
        reverse @{$robot->get_etc_include_path('create_list_templates')}
    ) {
        if (opendir(DIR, $dir)) {
            foreach my $template ( sort grep (!/^\./,readdir(DIR))) {

                my $status = $list_conf->{$template} || $list_conf->{'default'};

                next if ($status eq 'hidden') ;

                $list_templates->{$template}{'path'} = $dir;

                my $locale = Sympa::Language::Lang2Locale_old(Language::GetLang());
                ## FIXME: lang should be used instead of "locale".
                ## Look for a comment.tt2 in the appropriate locale first
                if (-r $dir.'/'.$template.'/'.$locale.'/comment.tt2') {
                    $list_templates->{$template}{'comment'} =
                    $template.'/'.$locale.'/comment.tt2';
                }elsif (-r $dir.'/'.$template.'/comment.tt2') {
                    $list_templates->{$template}{'comment'} =
                    $template.'/comment.tt2';
                }
            }
            closedir(DIR);
        }
    }

    return ($list_templates);
}

=back

=cut

1;
