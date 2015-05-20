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

package Sympa::Wwslib;

use Sympa::Log::Syslog;
use Sympa::Conf;
use Sympa::Constants;

## No longer used: Use List->get_option_title().
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
    43200 => {'gettext_id' => "30 days"}
);

## No longer used: Use List->get_option_title().
%visibility_mode = (
    'noconceal' => {'gettext_id' => "listed in the list review page"},
    'conceal'   => {'gettext_id' => "concealed"}
);

## Filenames with corresponding entry in NLS set 15
%filenames = (
    'welcome.tt2'       => {'gettext_id' => "welcome message"},
    'bye.tt2'           => {'gettext_id' => "unsubscribe message"},
    'removed.tt2'       => {'gettext_id' => "deletion message"},
    'message.footer'    => {'gettext_id' => "message footer"},
    'message.header'    => {'gettext_id' => "message header"},
    'remind.tt2'        => {'gettext_id' => "remind message"},
    'reject.tt2'        => {'gettext_id' => "editor rejection message"},
    'invite.tt2'        => {'gettext_id' => "subscribing invitation message"},
    'helpfile.tt2'      => {'gettext_id' => "help file"},
    'lists.tt2'         => {'gettext_id' => "directory of lists"},
    'global_remind.tt2' => {'gettext_id' => "global remind message"},
    'summary.tt2'       => {'gettext_id' => "summary message"},
    'info'              => {'gettext_id' => "list description"},
    'homepage'          => {'gettext_id' => "list homepage"},
    'create_list_request.tt2' =>
        {'gettext_id' => "list creation request message"},
    'list_created.tt2' =>
        {'gettext_id' => "list creation notification message"},
    'your_infected_msg.tt2' => {'gettext_id' => "virus infection message"},
    'list_aliases.tt2'      => {'gettext_id' => "list aliases template"}
);

%task_flavours = (
    'daily'   => {'gettext_id' => 'daily'},
    'monthly' => {'gettext_id' => 'monthly'},
    'weekly'  => {'gettext_id' => 'weekly'},
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

## Load WWSympa configuration file
##sub load_config
## MOVED: use Sympa::Conf::load_wwsconf().

## Load HTTPD MIME Types
sub load_mime_types {
    my $types = {};

    @localisation = (
        '/etc/mime.types',            '/usr/local/apache/conf/mime.types',
        '/etc/httpd/conf/mime.types', Sympa::Site->etc . '/mime.types'
    );

    foreach my $loc (@localisation) {
        next unless (-r $loc);

        unless (open(CONF, $loc)) {
            Sympa::Log::Syslog::do_log('err',
                "load_mime_types: unable to open $loc");
            return undef;
        }
    }

    while (<CONF>) {
        next if /^\s*\#/;

        if (/^(\S+)\s+(.+)\s*$/i) {
            my ($k, $v) = ($1, $2);

            my @extensions = split / /, $v;

            ## provides file extention, given the content-type
            if ($#extensions >= 0) {
                $types->{$k} = $extensions[0];
            }

            foreach my $ext (@extensions) {
                $types->{$ext} = $k;
            }
            next;
        }
    }

    close FILE;
    return $types;
}

## Returns user information extracted from the cookie
sub get_email_from_cookie {

    #    Sympa::Log::Syslog::do_log('debug', 'get_email_from_cookie');
    my $cookie = shift;
    my $secret = shift;

    my ($email, $auth);

    # Sympa::Log::Syslog::do_log('info',
    # "get_email_from_cookie($cookie,$secret)");

    unless (defined $secret) {
        &Sympa::Report::reject_report_web('intern', 'cookie_error', {}, '', '', '',
            $robot);
        Sympa::Log::Syslog::do_log('info',
            'parameter cookie undefined, authentication failure');
    }

    unless ($cookie) {
        &Sympa::Report::reject_report_web('intern', 'cookie_error', $cookie,
            'get_email_from_cookie', '', '', $robot);
        Sympa::Log::Syslog::do_log('info',
            ' cookie undefined, authentication failure');
    }

    ($email, $auth) = &Sympa::CookieLib::check_cookie($cookie, $secret);
    unless ($email) {
        &Sympa::Report::reject_report_web('user', 'auth_failed', {}, '');
        Sympa::Log::Syslog::do_log('info',
            'get_email_from_cookie: auth failed for user %s', $email);
        return undef;
    }

    return ($email, $auth);
}

sub new_passwd {

    my $passwd;
    my $nbchar = int(rand 5) + 6;
    foreach my $i (0 .. $nbchar) {
        $passwd .= chr(int(rand 26) + ord('a'));
    }

    return 'init' . $passwd;
}

## Basic check of an email address
sub valid_email {
    my $email = shift;

    $email =~ /^([\w\-\_\.\/\+\=]+|\".*\")\@[\w\-]+(\.[\w\-]+)+$/;
}

sub init_passwd {
    my ($email, $data) = @_;

    my ($passwd, $user);

    if (Sympa::User::is_global_user($email)) {
        $user = Sympa::User::get_global_user($email);

        $passwd = $user->{'password'};

        unless ($passwd) {
            $passwd = &new_passwd();

            unless (
                Sympa::User::update_global_user(
                    $email,
                    {   'password' => $passwd,
                        'lang'     => $user->{'lang'} || $data->{'lang'}
                    }
                )
                ) {
                &Sympa::Report::reject_report_web('intern', 'update_user_db_failed',
                    {'user' => $email},
                    '', '', $email, $robot);
                Sympa::Log::Syslog::do_log('info',
                    'init_passwd: update failed');
                return undef;
            }
        }
    } else {
        $passwd = &new_passwd();
        unless (
            Sympa::User::add_global_user(
                {   'email'    => $email,
                    'password' => $passwd,
                    'lang'     => $data->{'lang'},
                    'gecos'    => $data->{'gecos'}
                }
            )
            ) {
            &Sympa::Report::reject_report_web('intern', 'add_user_db_failed',
                {'user' => $email},
                '', '', $email, $robot);
            Sympa::Log::Syslog::do_log('info', 'init_passwd: add failed');
            return undef;
        }
    }

    return 1;
}

sub get_my_url {

    my $return_url;

    ## Mod_ssl sets SSL_PROTOCOL ; apache-ssl sets SSL_PROTOCOL_VERSION
    if ($ENV{'HTTPS'} eq 'on') {
        $return_url = 'https';
    } else {
        $return_url = 'http';
    }

    $return_url .= '://' . &main::get_header_field('HTTP_HOST');
    $return_url .= ':' . $ENV{'SERVER_PORT'}
        unless (($ENV{'SERVER_PORT'} eq '80')
        || ($ENV{'SERVER_PORT'} eq '443'));
    $return_url .= $ENV{'REQUEST_URI'};
    return ($return_url);
}

# Uploade source file to the destination on the server
sub upload_file_to_server {
    my $param = shift;
    Sympa::Log::Syslog::do_log(
        'debug',
        "Uploading file from field %s to destination %s",
        $param->{'file_field'},
        $param->{'destination'}
    );
    my $fh;
    unless ($fh = $param->{'query'}->upload($param->{'file_field'})) {
        Sympa::Log::Syslog::do_log('debug',
            "Cannot upload file from field $param->{'file_field'}");
        return undef;
    }

    unless (open FILE, ">:bytes", $param->{'destination'}) {
        Sympa::Log::Syslog::do_log('debug',
            "Cannot open file $param->{'destination'} : $!");
        return undef;
    }
    while (<$fh>) {
        print FILE;
    }
    close FILE;
    return 1;
}

1;
