# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014, 2015 GIP RENATER
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

package Sympa::Tools::WWW;

use strict;
use warnings;
use English qw(-no_match_vars);
use File::Path qw();

use Sympa;
use Conf;
use Sympa::ConfDef;
use Sympa::Constants;
use Sympa::Language;
use Sympa::LockedFile;
use Sympa::Log;
use Sympa::Report;
use Sympa::Template;
use tools;
use Sympa::Tools::File;
use Sympa::User;

my $log = Sympa::Log->instance;

# hash of the icons linked with a type of file
# application file
my %icons = (
    'unknown'        => 'unknown.png',
    'folder'         => 'folder.png',
    'current_folder' => 'folder.open.png',
    'application'    => 'unknown.png',
    'octet-stream'   => 'binary.png',
    'audio'          => 'sound1.png',
    'image'          => 'image2.png',
    'text'           => 'text.png',
    'video'          => 'movie.png',
    'father'         => 'back.png',
    'sort'           => 'down.png',
    'url'            => 'link.png',
    'left'           => 'left.png',
    'right'          => 'right.png',
);

# lazy loading on demand
my %mime_types;

## Cookie expiration periods with corresponding entry in NLS
our %cookie_period = (
    0     => {'gettext_id' => "session"},
    10    => {'gettext_id' => "10 minutes"},
    30    => {'gettext_id' => "30 minutes"},
    60    => {'gettext_id' => "1 hour"},
    360   => {'gettext_id' => "6 hours"},
    1440  => {'gettext_id' => "1 day"},
    10800 => {'gettext_id' => "1 week"},
    43200 => {'gettext_id' => "30 days"}
);

## Filenames with corresponding entry in NLS set 15
our %filenames = (
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

# Taken from IANA registry:
# <http://www.iana.org/assignments/smtp-enhanced-status-codes>
our %bounce_status = (
    '0.0'  => 'Other undefined Status',
    '1.0'  => 'Other address status',
    '1.1'  => 'Bad destination mailbox address',
    '1.2'  => 'Bad destination system address',
    '1.3'  => 'Bad destination mailbox address syntax',
    '1.4'  => 'Destination mailbox address ambiguous',
    '1.5'  => 'Destination address valid',
    '1.6'  => 'Destination mailbox has moved, No forwarding address',
    '1.7'  => 'Bad sender\'s mailbox address syntax',
    '1.8'  => 'Bad sender\'s system address',
    '1.9'  => 'Message relayed to non-compliant mailer',
    '1.10' => 'Recipient address has null MX',
    '2.0'  => 'Other or undefined mailbox status',
    '2.1'  => 'Mailbox disabled, not accepting messages',
    '2.2'  => 'Mailbox full',
    '2.3'  => 'Message length exceeds administrative limit',
    '2.4'  => 'Mailing list expansion problem',
    '3.0'  => 'Other or undefined mail system status',
    '3.1'  => 'Mail system full',
    '3.2'  => 'System not accepting network messages',
    '3.3'  => 'System not capable of selected features',
    '3.4'  => 'Message too big for system',
    '3.5'  => 'System incorrectly configured',
    '3.6'  => 'Requested priority was changed',
    '4.0'  => 'Other or undefined network or routing status',
    '4.1'  => 'No answer from host',
    '4.2'  => 'Bad connection',
    '4.3'  => 'Directory server failure',
    '4.4'  => 'Unable to route',
    '4.5'  => 'Mail system congestion',
    '4.6'  => 'Routing loop detected',
    '4.7'  => 'Delivery time expired',
    '5.0'  => 'Other or undefined protocol status',
    '5.1'  => 'Invalid command',
    '5.2'  => 'Syntax error',
    '5.3'  => 'Too many recipients',
    '5.4'  => 'Invalid command arguments',
    '5.5'  => 'Wrong protocol version',
    '5.6'  => 'Authentication Exchange line is too long',
    '6.0'  => 'Other or undefined media error',
    '6.1'  => 'Media not supported',
    '6.2'  => 'Conversion required and prohibited',
    '6.3'  => 'Conversion required but not supported',
    '6.4'  => 'Conversion with loss performed',
    '6.5'  => 'Conversion Failed',
    '6.6'  => 'Message content not available',
    '6.7'  => 'Non-ASCII addresses not permitted for that sender/recipient',
    '6.8' =>
        'UTF-8 string reply is required, but not permitted by the SMTP client',
    '6.9' =>
        'UTF-8 header message cannot be transferred to one or more recipients, so the message must be rejected',
    #'6.10' => '',    # Duplicate of 6.8, deprecated.
    '7.0'  => 'Other or undefined security status',
    '7.1'  => 'Delivery not authorized, message refused',
    '7.2'  => 'Mailing list expansion prohibited',
    '7.3'  => 'Security conversion required but not possible',
    '7.4'  => 'Security features not supported',
    '7.5'  => 'Cryptographic failure',
    '7.6'  => 'Cryptographic algorithm not supported',
    '7.7'  => 'Message integrity failure',
    '7.8'  => 'Authentication credentials invalid',
    '7.9'  => 'Authentication mechanism is too weak',
    '7.10' => 'Encryption Needed',
    '7.11' => 'Encryption required for requested authentication mechanism',
    '7.12' => 'A password transition is needed',
    '7.13' => 'User Account Disabled',
    '7.14' => 'Trust relationship required',
    '7.15' => 'Priority Level is too low',
    '7.16' => 'Message is too big for the specified priority',
    '7.17' => 'Mailbox owner has changed',
    '7.18' => 'Domain owner has changed',
    '7.19' => 'RRVS test cannot be completed',
    '7.20' => 'No passing DKIM signature found',
    '7.21' => 'No acceptable DKIM signature found',
    '7.22' => 'No valid author-matched DKIM signature found',
    '7.23' => 'SPF validation failed',
    '7.24' => 'SPF validation error',
    '7.25' => 'Reverse DNS validation failed',
    '7.26' => 'Multiple authentication checks failed',
    '7.27' => 'Sender address has null MX',
);

## Load WWSympa configuration file
##sub load_config
## MOVED: use Conf::_load_wwsconf().

## Load HTTPD MIME Types
# Moved to _load_mime_types().
#sub load_mime_types();

## Returns user information extracted from the cookie
# Deprecated.  Use Sympa::Session->new etc.
#sub get_email_from_cookie;

sub new_passwd {

    my $passwd;
    my $nbchar = int(rand 5) + 6;
    foreach my $i (0 .. $nbchar) {
        $passwd .= chr(int(rand 26) + ord('a'));
    }

    return 'init' . $passwd;
}

## Basic check of an email address
# DUPLICATE: Use tools::valid_email().
#sub valid_email($email);

# 6.2b: added $robot parameter.
sub init_passwd {
    my ($robot, $email, $data) = @_;

    my ($passwd, $user);

    if (Sympa::User::is_global_user($email)) {
        $user = Sympa::User::get_global_user($email);

        $passwd = $user->{'password'};

        unless ($passwd) {
            $passwd = new_passwd();

            unless (
                Sympa::User::update_global_user(
                    $email, {'password' => $passwd}
                )
                ) {
                Sympa::Report::reject_report_web('intern',
                    'update_user_db_failed', {'user' => $email},
                    '', '', $email, $robot);
                $log->syslog('info', 'Update failed');
                return undef;
            }
        }
    } else {
        $passwd = new_passwd();
        unless (
            Sympa::User::add_global_user(
                {   'email'    => $email,
                    'password' => $passwd,
                    'lang'     => $data->{'lang'},
                    'gecos'    => $data->{'gecos'}
                }
            )
            ) {
            Sympa::Report::reject_report_web('intern', 'add_user_db_failed',
                {'user' => $email},
                '', '', $email, $robot);
            $log->syslog('info', 'Add failed');
            return undef;
        }
    }

    return 1;
}

sub get_my_url {
    my $return_url;

    # mod_ssl sets SSL_PROTOCOL; Apache-SSL sets SSL_PROTOCOL_VERSION.
    if ($ENV{'HTTPS'} and $ENV{'HTTPS'} eq 'on') {
        $return_url = 'https';
    } else {
        $return_url = 'http';
    }

    $return_url .= '://' . Sympa::Tools::WWW::get_http_host();
    $return_url .= ':' . $ENV{'SERVER_PORT'}
        unless $ENV{'SERVER_PORT'} eq '80'
            or $ENV{'SERVER_PORT'} eq '443';
    $return_url .= $ENV{'REQUEST_URI'};
    return ($return_url);
}

# Old name: (part of) get_header_field() in wwsympa.fcgi.
sub get_server_name {
    # HTTP_X_ header fields set when using a proxy
    return $ENV{'HTTP_X_FORWARDED_SERVER'} || $ENV{'SERVER_NAME'};
}

# Old name: (part of) get_header_field() in wwsympa.fcgi.
sub get_http_host {
    # HTTP_X_ header fields set when using a proxy
    return $ENV{'HTTP_X_FORWARDED_HOST'} || $ENV{'HTTP_HOST'};
}

# Uploade source file to the destination on the server
sub upload_file_to_server {
    my $param = shift;
    $log->syslog(
        'debug',
        "Uploading file from field %s to destination %s",
        $param->{'file_field'},
        $param->{'destination'}
    );
    my $fh;
    unless ($fh = $param->{'query'}->upload($param->{'file_field'})) {
        $log->syslog(
            'debug',
            'Cannot upload file from field %s',
            $param->{'file_field'}
        );
        return undef;
    }

    unless (open FILE, ">:bytes", $param->{'destination'}) {
        $log->syslog(
            'debug',
            'Cannot open file %s: %m',
            $param->{'destination'}
        );
        return undef;
    }
    while (<$fh>) {
        print FILE;
    }
    close FILE;
    return 1;
}

## Useful function to get off the slash at the end of the path
## at its end
sub no_slash_end {
    my $path = shift;

    ## supress ending '/'
    $path =~ s/\/+$//;

    return $path;
}

## return a visible path from a moderated file or not
sub make_visible_path {
    my $path = shift;

    my $visible_path = $path;

    if ($path =~ /\.url(\.moderate)?$/) {
        if ($path =~ /^([^\/]*\/)*([^\/]+)\.([^\/]+)$/) {
            $visible_path =~ s/\.moderate$//;
            $visible_path =~ s/^\.//;
            $visible_path =~ s/\.url$//;
        }

    } elsif ($path =~ /\.moderate$/) {
        if ($path =~ /^(([^\/]*\/)*)([^\/]+)(\/?)$/) {
            my $name = $3;
            $name =~ s/^\.//;
            $name =~ s/\.moderate//;
            $visible_path = "$2" . "$name";
        }
    }

    ## Qdecode the visible path
    return tools::qdecode_filename($visible_path);
}

## returns a mailto according to list spam protection parameter
sub mailto {
    my $list  = shift;
    my $email = shift;
    my $gecos = shift;
    my $next_one;

    my $mailto = '';
    my @addresses;
    my %recipients;

    @addresses = split(',', $email);

    $gecos = $email unless ($gecos);
    $gecos =~ s/&/&amp;/g;
    $gecos =~ s/</&lt;/g;
    $gecos =~ s/>/&gt;/g;
    foreach my $address (@addresses) {

        ($recipients{$address}{'local'}, $recipients{$address}{'domain'}) =
            split('@', $address);
    }

    if ($list->{'admin'}{'spam_protection'} eq 'none') {
        $mailto .= "<a href=\"mailto:?";
        foreach my $address (@addresses) {
            $mailto .= "&amp;" if ($next_one);
            $mailto .= "to=$address";
            $next_one = 1;
        }
        $mailto .= "\">$gecos</a>";
    } elsif ($list->{'admin'}{'spam_protection'} eq 'javascript') {

        if ($gecos =~ /\@/) {
            $gecos =~ s/@/\" + \"@\" + \"/;
        }

        $mailto .= "<script type=\"text/javascript\">
 <!--
 document.write(\"<a href=\\\"\" + \"mail\" + \"to:?\" + ";
        foreach my $address (@addresses) {
            $mailto .= "\"\&amp\;\" + " if ($next_one);
            $mailto .=
                "\"to=\" + \"$recipients{$address}{'local'}\" + \"@\" + \"$recipients{$address}{'domain'}\" + ";
            $next_one = 1;
        }
        $mailto .= "\"\\\">$gecos<\" + \"/a>\")
 // --></script>";

    } elsif ($list->{'admin'}{'spam_protection'} eq 'at') {
        foreach my $address (@addresses) {
            $mailto .= " AND " if ($next_one);
            $mailto .=
                "$recipients{$address}{'local'} AT $recipients{$address}{'domain'}";
            $next_one = 1;
        }
    }
    return $mailto;

}

## return the mode of editing included in $action : 0, 0.5 or 1
sub find_edit_mode {
    my $action = shift;

    my $result;
    if ($action =~ /editor/i) {
        $result = 0.5;
    } elsif ($action =~ /do_it/i) {
        $result = 1;
    } else {
        $result = 0;
    }
    return $result;
}

## return the mode of editing : 0, 0.5 or 1 :
#  do the merging between 2 args of right access edit  : "0" > "0.5" > "1"
#  instead of a "and" between two booleans : the most restrictive right is
#  imposed
sub merge_edit {
    my $arg1 = shift;
    my $arg2 = shift;
    my $result;

    if ($arg1 == 0 || $arg2 == 0) {
        $result = 0;
    } elsif ($arg1 == 0.5 || $arg2 == 0.5) {
        $result = 0.5;
    } else {
        $result = 1;
    }
    return $result;
}

sub get_desc_file {
    my $file = shift;
    my $ligne;
    my %hash;

    open DESC_FILE, "$file";

    while ($ligne = <DESC_FILE>) {
        if ($ligne =~ /^title\s*$/) {
            #case title of the document
            while ($ligne = <DESC_FILE>) {
                last if ($ligne =~ /^\s*$/);
                $ligne =~ /^\s*(\S.*\S)\s*/;
                $hash{'title'} = $hash{'title'} . $1 . " ";
            }
        }

        if ($ligne =~ /^creation\s*$/) {
            #case creation of the document
            while ($ligne = <DESC_FILE>) {
                last if ($ligne =~ /^\s*$/);
                if ($ligne =~ /^\s*email\s*(\S*)\s*/) {
                    $hash{'email'} = $1;
                }
                if ($ligne =~ /^\s*date_epoch\s*(\d*)\s*/) {
                    $hash{'date'} = $1;
                }
            }
        }

        if ($ligne =~ /^access\s*$/) {
            #case access scenarios for the document
            while ($ligne = <DESC_FILE>) {
                last if ($ligne =~ /^\s*$/);
                if ($ligne =~ /^\s*read\s*(\S*)\s*/) {
                    $hash{'read'} = $1;
                }
                if ($ligne =~ /^\s*edit\s*(\S*)\s*/) {
                    $hash{'edit'} = $1;
                }
            }
        }
    }

    close DESC_FILE;

    return %hash;
}

## return a ref on an array of file (or subdirecties) to show to user
sub get_directory_content {
    my $tmpdir = shift;
    my $user   = shift;
    my $list   = shift;
    my $doc    = shift;

    # array of file not hidden
    my @dir = grep !/^\./, @$tmpdir;

    # array with documents not yet moderated
    my @moderate_dir = grep (/(\.moderate)$/, @$tmpdir);
    @moderate_dir = grep (!/^\.desc\./, @moderate_dir);

    # The editor can see file not yet moderated.
    # A user can see file not yet moderated if they are the owner of these
    # files.
    if ($list->is_admin('actual_editor', $user)) {
        push(@dir, @moderate_dir);
    } else {
        my @privatedir = select_my_files($user, $doc, \@moderate_dir);
        push(@dir, @privatedir);
    }

    return \@dir;
}

## return an array that contains only file from @$refdir that belongs to $user
sub select_my_files {
    my ($user, $path, $refdir) = @_;
    my @new_dir;

    foreach my $d (@$refdir) {
        if (-e "$path/.desc.$d") {
            my %desc_hash = get_desc_file("$path/.desc.$d");
            if ($user eq $desc_hash{'email'}) {
                $new_dir[$#new_dir + 1] = $d;
            }
        }
    }
    return @new_dir;
}

sub get_icon {
    my $robot = shift || '*';
    my $type = shift;

    return undef unless defined $icons{$type};
    return
          Conf::get_robot_conf($robot, 'static_content_url')
        . '/icons/'
        . $icons{$type};
}

sub get_mime_type {
    my $type = shift;

    %mime_types = _load_mime_types() unless %mime_types;

    return $mime_types{$type};
}

sub _load_mime_types {
    my %types = ();

    my @localisation = (
        Sympa::search_fullpath('*', 'mime.types'),
        '/etc/mime.types', '/usr/local/apache/conf/mime.types',
        '/etc/httpd/conf/mime.types',
    );

    foreach my $loc (@localisation) {
        my $fh;
        next unless $loc and open $fh, '<', $loc;

        foreach my $line (<$fh>) {
            next if $line =~ /^\s*\#/;
            chomp $line;

            my ($k, $v) = split /\s+/, $line, 2;
            next unless $k and $v and $v =~ /\S/;

            my @extensions = split /\s+/, $v;
            # provides file extention, given the content-type
            if (@extensions) {
                $types{$k} = $extensions[0];
            }
            foreach my $ext (@extensions) {
                $types{$ext} = $k;
            }
        }

        close $fh;
        return %types;
    }

    return;
}

## return a hash from the edit_list_conf file
# Old name: tools::load_create_list_conf().
sub _load_create_list_conf {
    my $robot = shift;

    my $file;
    my $conf;

    $file = Sympa::search_fullpath($robot, 'create_list.conf');
    unless ($file) {
        $log->syslog(
            'info',
            'Unable to read %s',
            Sympa::Constants::DEFAULTDIR . '/create_list.conf'
        );
        return undef;
    }

    unless (open(FILE, $file)) {
        $log->syslog('info', 'Unable to open config file %s', $file);
        return undef;
    }

    while (<FILE>) {
        next if /^\s*(\#.*|\s*)$/;

        if (/^\s*(\S+)\s+(read|hidden)\s*$/i) {
            $conf->{$1} = lc($2);
        } else {
            $log->syslog(
                'info',
                'Unknown parameter in %s (Ignored) %s',
                "$Conf::Conf{'etc'}/create_list.conf", $_
            );
            next;
        }
    }

    close FILE;
    return $conf;
}

# Old name: tools::get_list_list_tpl().
sub get_list_list_tpl {
    my $robot = shift;

    my $language = Sympa::Language->instance;

    my $list_conf;
    my $list_templates;
    unless ($list_conf = _load_create_list_conf($robot)) {
        return undef;
    }

    my %tpl_names;
    foreach my $directory (
        @{  Sympa::get_search_path(
                $robot,
                subdir => 'create_list_templates',
                lang   => $language->get_lang
            )
        }
        ) {
        my $dh;
        if (opendir $dh, $directory) {
            foreach my $tpl_name (readdir $dh) {
                next if $tpl_name =~ /\A\./;
                next unless -d $directory . '/' . $tpl_name;

                $tpl_names{$tpl_name} = 1;
            }
            closedir $dh;
        }
    }

LOOP_FOREACH_TPL_NAME:
    foreach my $tpl_name (keys %tpl_names) {
        my $status = $list_conf->{$tpl_name}
            || $list_conf->{'default'};
        next if $status eq 'hidden';

        # Look for a comment.tt2.
        # Check old style locale first then canonic language and its
        # fallbacks.
        my $comment_tt2 = Sympa::search_fullpath(
            $robot, 'comment.tt2',
            subdir => 'create_list_templates/' . $tpl_name,
            lang   => $language->get_lang
        );
        next unless $comment_tt2;

        open my $fh, '<', $comment_tt2 or next;
        my $tpl_string = do { local $RS; <$fh> };
        close $fh;

        pos $tpl_string = 0;
        my %titles;
        while ($tpl_string =~ /\G(title(?:[.][-\w]+)?[ \t]+(?:.*))(\n|\z)/cgi
            or $tpl_string =~ /\G(\s*)(\n|\z)/cg) {
            my $line = $1;
            last if $line =~ /\A\s*\z/;

            if ($line =~ /^title\.gettext\s+(.*)\s*$/i) {
                $titles{'gettext'} = $1;
            } elsif ($line =~ /^title\.(\S+)\s+(.*)\s*$/i) {
                my ($lang, $title) = ($1, $2);
                # canonicalize lang if possible.
                $lang = Sympa::Language::canonic_lang($lang) || $lang;
                $titles{$lang} = $title;
            } elsif (/^title\s+(.*)\s*$/i) {
                $titles{'default'} = $1;
            }
        }

        $list_templates->{$tpl_name}{'html_content'} = substr $tpl_string,
            pos $tpl_string;

        # Set the title in the current language
        foreach
            my $lang (Sympa::Language::implicated_langs($language->get_lang))
        {
            if (exists $titles{$lang}) {
                $list_templates->{$tpl_name}{'title'} = $titles{$lang};
                next LOOP_FOREACH_TPL_NAME;
            }
        }
        if ($titles{'gettext'}) {
            $list_templates->{$tpl_name}{'title'} =
                $language->gettext($titles{'gettext'});
        } elsif ($titles{'default'}) {
            $list_templates->{$tpl_name}{'title'} = $titles{'default'};
        }
    }

    return $list_templates;
}

# Old name: Conf::update_css().
sub update_css {
    my %options = @_;

    my $force = $options{force};

    # Set umask.
    my $umask = umask 022;

    # create or update static CSS files
    my $css_updated = undef;
    my @robots = ('*', keys %{$Conf::Conf{'robots'}});
    foreach my $robot (@robots) {
        my $dir = Conf::get_robot_conf($robot, 'css_path');

        ## Get colors for parsing
        my $param = {};

        foreach my $p (
            map  { $_->{name} }
            grep { $_->{name} } @Sympa::ConfDef::params
            ) {
            $param->{$p} = Conf::get_robot_conf($robot, $p)
                if $p =~ /_color\z/ or $p =~ /\Acolor_/ or $p =~ /_url\z/;
        }

        # Create directory if required
        unless (-d $dir) {
            my $error;
            File::Path::make_path(
                $dir,
                {   mode  => 0755,
                    owner => Sympa::Constants::USER(),
                    group => Sympa::Constants::GROUP(),
                    error => \$error
                }
            );
            if (@$error) {
                my ($target, $err) = %{$error->[-1] || {}};

                Sympa::send_notify_to_listmaster($robot, 'cannot_mkdir',
                    ["Could not create $target: $err"]);
                $log->syslog('err', 'Failed to create %s: %s', $target, $err);

                umask $umask;
                return undef;
            }
        }

        my $css_tt2_path =
            Sympa::search_fullpath($robot, 'css.tt2', subdir => 'web_tt2');
        my $css_tt2_mtime = Sympa::Tools::File::get_mtime($css_tt2_path);

        foreach my $css ('style.css', 'print.css', 'fullPage.css',
            'print-preview.css') {
            # Lock file to prevent multiple processes from writing it.
            my $lock_fh = Sympa::LockedFile->new($dir . '/' . $css, -1, '+');
            next unless $lock_fh;

            $param->{'css'} = $css;

            # Update the CSS if it is missing or if a new css.tt2 was
            # installed
            if (!-f $dir . '/' . $css
                or $css_tt2_mtime >
                Sympa::Tools::File::get_mtime($dir . '/' . $css)
                or $force) {
                $log->syslog(
                    'notice',
                    'TT2 file %s has changed; updating static CSS file %s/%s; previous file renamed',
                    $css_tt2_path,
                    $dir,
                    $css
                );

                ## Keep copy of previous file
                rename $dir . '/' . $css, $dir . '/' . $css . '.' . time;

                unless (open CSS, '>', $dir . '/' . $css) {
                    my $errno = $ERRNO;
                    Sympa::send_notify_to_listmaster($robot,
                        'cannot_open_file',
                        ["Could not open file $dir/$css: $errno"]);
                    $log->syslog('err',
                        'Failed to open (write) file %s/%s: %s',
                        $dir, $css, $errno);

                    umask $umask;
                    return undef;
                }

                my $css_template =
                    Sympa::Template->new($robot, subdir => 'web_tt2');
                unless ($css_template->parse($param, 'css.tt2', \*CSS)) {
                    my $error = $css_template->{last_error};
                    $error = $error->as_string if ref $error;
                    $param->{'tt2_error'} = $error;
                    Sympa::send_notify_to_listmaster($robot, 'web_tt2_error',
                        [$error]);
                    $log->syslog('err', 'Error while installing %s/%s',
                        $dir, $css);
                }

                $css_updated++;

                close CSS;
            }
        }
    }
    if ($css_updated) {
        ## Notify main listmaster
        Sympa::send_notify_to_listmaster(
            '*',
            'css_updated',
            [   "Static CSS files have been updated ; check log file for details"
            ]
        );
    }

    umask $umask;
    return 1;
}

1;
__END__
