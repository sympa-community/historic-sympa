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

package Sympa::Archive;

use strict;
use English qw(-no_match_vars);
use Carp qw(croak);
use Cwd qw(getcwd);
use Digest::MD5;
use Encode qw(decode_utf8 encode_utf8);
use HTML::Entities qw(decode_entities);

use Sympa::Log;

my $serial_number = 0;    # incremented on each archived mail

## RCS identification.

## Does the real job : stores the message given as an argument into
## the indicated directory.

sub store_last {
    my ($list, $msg) = @_;

    Sympa::Log::Syslog::do_log('debug2', 'archive::store ()');

    my ($filename, $newfile);

    return unless $list->is_archived();
    my $dir = $list->dir . '/archives';

    ## Create the archive directory if needed
    mkdir($dir, "0775") if !(-d $dir);
    chmod 0774, $dir;

    ## erase the last  message and replace it by the current one
    open(OUT, "> $dir/last_message");
    if (ref($msg)) {
        $msg->print(\*OUT);
    } else {
        print OUT $msg;
    }
    close(OUT);

}

## Lists the files included in the archive, preformatted for printing
## Returns an array.
sub list {
    my $name = shift;

    Sympa::Log::Syslog::do_log('debug', "archive::list($name)");

    my ($filename, $newfile);
    my (@l,        $i);

    unless (-d "$name") {
        Sympa::Log::Syslog::do_log('warning',
            "archive::list($name) failed, no directory $name");

        #      @l = ($msg::no_archives_available);
        return @l;
    }
    unless (opendir(DIR, "$name")) {
        Sympa::Log::Syslog::do_log('warning',
            "archive::list($name) failed, cannot open directory $name");

        #	@l = ($msg::no_archives_available);
        return @l;
    }
    foreach $i (sort readdir(DIR)) {
        next if ($i =~ /^\./o);
        next unless ($i =~ /^\d\d\d\d\-\d\d$/);
        my (@s) = stat("$name/$i");
        my $a = localtime($s[9]);
        push(@l, sprintf("%-40s %7d   %s\n", $i, $s[7], $a));
    }
    return @l;
}

sub scan_dir_archive {

    my ($dir, $month) = @_;

    Sympa::Log::Syslog::do_log('info',
        "archive::scan_dir_archive($dir, $month)");

    unless (opendir(DIR, "$dir/$month/arctxt")) {
        Sympa::Log::Syslog::do_log('info',
            "archive::scan_dir_archive($dir, $month): unable to open dir $dir/$month/arctxt"
        );
        return undef;
    }

    my $all_msg = [];
    my $i       = 0;
    foreach my $file (sort readdir(DIR)) {
        next unless ($file =~ /^\d+$/);
        Sympa::Log::Syslog::do_log('debug',
            "archive::scan_dir_archive($dir, $month): start parsing message $dir/$month/arctxt/$file"
        );

        my $message = Sympa::Message->new(
            {   'file'       => "$dir/$month/arctxt/$file",
                'noxsympato' => 'noxsympato'
            }
        );
        unless ($message) {
            Sympa::Log::Syslog::do_log('err',
                'Unable to create Message object from file %s', $file);
            return undef;
        }

        Sympa::Log::Syslog::do_log('debug', 'MAIL object : %s', $message);

        $i++;
        my $msg = {};
        $msg->{'id'} = $i;

        $msg->{'subject'} = Sympa::Tools::decode_header($message, 'Subject');
        $msg->{'from'}    = Sympa::Tools::decode_header($message, 'From');
        $msg->{'date'}    = Sympa::Tools::decode_header($message, 'Date');

        $msg->{'full_msg'} = $message->as_string();    # raw message

        Sympa::Log::Syslog::do_log('debug',
            'Adding message %s in archive to send',
            $msg->{'subject'});

        push @{$all_msg}, $msg;
    }
    closedir DIR;

    return $all_msg;
}

#####################################################
#  search_msgid
####################################################
#
# find a message in archive specified by arcpath and msgid
#
# IN : arcpath and msgid
#
# OUT : undef | #message in arctxt
#
####################################################

sub search_msgid {

    my ($dir, $msgid) = @_;

    Sympa::Log::Syslog::do_log('info', "archive::search_msgid($dir, $msgid)");

    if ($msgid =~ /NO-ID-FOUND\.mhonarc\.org/) {
        Sympa::Log::Syslog::do_log('err', 'remove_arc: no message id found');
        return undef;
    }
    unless ($dir =~ /\d\d\d\d\-\d\d\/arctxt/) {
        Sympa::Log::Syslog::do_log('err',
            "archive::search_msgid : dir $dir look improper");
        return undef;
    }
    unless (opendir(ARC, "$dir")) {
        Sympa::Log::Syslog::do_log('err',
            "archive::scan_dir_archive($dir, $msgid): unable to open dir $dir"
        );
        return undef;
    }
    chomp $msgid;

    foreach my $file (grep (!/\./, readdir ARC)) {
        next unless (open MAIL, "$dir/$file");
        while (<MAIL>) {
            last if /^$/;    #stop parse after end of headers
            if (/^Message-id:\s?<?([^>\s]+)>?\s?/i) {
                my $id = $1;
                if ($id eq $msgid) {
                    close MAIL;
                    closedir ARC;
                    return $file;
                }
            }
        }
        close MAIL;
    }
    closedir ARC;
    return undef;
}

sub exist {
    my ($name, $file) = @_;
    my $fn = "$name/$file";

    return $fn if (-r $fn && -f $fn);
    return undef;
}

# return path for latest message distributed in the list
sub last_path {

    my $list = shift;

    Sympa::Log::Syslog::do_log('debug', 'Archived::last_path(%s)',
        $list->name);

    return undef unless ($list->is_archived());
    my $file = $list->dir . '/archives/last_message';

    return ($list->dir . '/archives/last_message')
        if (-f $list->dir . '/archives/last_message');
    return undef;

}

## Load an archived message, returns the mhonarc metadata
## IN : file_path
sub load_html_message {
    my %parameters = @_;

    Sympa::Log::Syslog::do_log('debug2', $parameters{'file_path'});
    my %metadata;

    unless (open ARC, $parameters{'file_path'}) {
        Sympa::Log::Syslog::do_log(
            'err',
            "Failed to load message '%s' : $ERRNO",
            $parameters{'file_path'}
        );
        return undef;
    }

    while (<ARC>) {
        last if /^\s*$/;    ## Metadata end with an emtpy line

        if (/^<!--(\S+): (.*) -->$/) {
            my ($key, $value) = ($1, $2);
            $value = encode_utf8(decode_entities(decode_utf8($value)));
            if ($key eq 'X-From-R13') {
                $metadata{'X-From'} = $value;
                ## Mhonarc protection of email addresses
                $metadata{'X-From'} =~ tr/N-Z[@A-Mn-za-m/@A-Z[a-z/;
                $metadata{'X-From'} =~ s/^.*<(.*)>/$1/g;   ## Remove the gecos
            }
            $metadata{$key} = $value;
        }
    }

    close ARC;

    return \%metadata;
}

sub clean_archive_directory {
    Sympa::Log::Syslog::do_log('debug2', '(%s, %s)', @_);
    my $robot          = shift;
    my $dir_to_rebuild = shift;

    my $arc_root = $robot->arc_path;
    my $answer;
    $answer->{'dir_to_rebuild'} = $arc_root . '/' . $dir_to_rebuild;
    $answer->{'cleaned_dir'}    = Sympa::Site->tmpdir . '/' . $dir_to_rebuild;
    unless (
        my $number_of_copies = Sympa::Tools::copy_dir(
            $answer->{'dir_to_rebuild'},
            $answer->{'cleaned_dir'}
        )
        ) {
        Sympa::Log::Syslog::do_log(
            'err',
            "Unable to create a temporary directory where to store files for HTML escaping (%s). Cancelling.",
            $number_of_copies
        );
        return undef;
    }
    if (opendir ARCDIR, $answer->{'cleaned_dir'}) {
        my $files_left_uncleaned = 0;
        foreach my $file (readdir(ARCDIR)) {
            next if ($file =~ /^\./);
            $file = $answer->{'cleaned_dir'} . '/' . $file;
            $files_left_uncleaned++
                unless (clean_archived_message($robot, $file, $file));
        }
        closedir DIR;
        if ($files_left_uncleaned) {
            Sympa::Log::Syslog::do_log('err',
                "HTML cleaning failed for %s files in the directory %s.",
                $files_left_uncleaned, $answer->{'dir_to_rebuild'});
        }
        $answer->{'dir_to_rebuild'} = $answer->{'cleaned_dir'};
    } else {
        Sympa::Log::Syslog::do_log(
            'err',
            'Unable to open directory %s: %s',
            $answer->{'dir_to_rebuild'}, $ERRNO
        );
        Sympa::Tools::del_dir($answer->{'cleaned_dir'});
        return undef;
    }
    return $answer;
}

sub clean_archived_message {
    Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s)', @_);
    my $robot   = shift;
    my $input   = shift;
    my $output  = shift;
    my $message = Sympa::Message->new({'file' => $input, 'noxsympato' => 1});

    if ($message->clean_html($robot)) {
        if (open TMP, '>', $output) {
            print TMP $message->as_string();
            close TMP;
        } else {
            Sympa::Log::Syslog::do_log('err',
                'Unable to create a temporary file %s to write clean HTML',
                $output);
            return undef;
        }
    } else {
        Sympa::Log::Syslog::do_log('err', 'HTML cleaning in file %s failed.',
            $output);
        return undef;
    }
}

#############################
# convert a message to HTML.
#    result is stored in $destination_dir
#    attachement_url is used to link attachement
#
# NOTE: This might be moved to Site package as a mutative method.
# NOTE: convert_single_msg_2_html() was deprecated.
sub convert_single_message {
    my $that    = shift;    # List or Robot object
    my $message = shift;    # Message object or hashref
    my %opts    = @_;

    my $robot;
    my $listname;
    my $hostname;
    if (ref $that and ref $that eq 'List') {
        $robot    = $that->robot;
        $listname = $that->name;
    } elsif (ref $that and ref $that eq 'Sympa::Robot') {
        $robot    = $that;
        $listname = '';
    } else {
        croak 'bug in logic.  Ask developer';
    }
    $hostname = $that->host;

    my $msg_as_string;
    my $messagekey;
    if (ref $message eq 'Message') {
        $msg_as_string = $message->get_message_as_string;
        $messagekey    = $message->{'messagekey'};
    } elsif (ref $message eq 'HASH') {
        $msg_as_string = $message->{'messageasstring'};
        $messagekey    = $message->{'messagekey'};
    } else {
        croak 'bug in logic.  Ask developer';
    }

    my $destination_dir = $opts{'destination_dir'};
    my $attachement_url = $opts{'attachement_url'};

    my $mhonarc_ressources =
        $that->get_etc_filename('mhonarc-ressources.tt2');
    unless ($mhonarc_ressources) {
        Sympa::Log::Syslog::do_log('notice',
            'Cannot find any MhOnArc ressource file');
        return undef;
    }

    unless (-d $destination_dir) {
        unless (Sympa::Tools::mkdir_all($destination_dir, 0755)) {
            Sympa::Log::Syslog::do_log('err', 'Unable to create %s',
                $destination_dir);
            return undef;
        }
    }

    my $msg_file = $destination_dir . '/msg00000.txt';
    unless (open OUT, '>', $msg_file) {
        Sympa::Log::Syslog::do_log('notice', 'Could Not open %s', $msg_file);
        return undef;
    }
    print OUT $msg_as_string;
    close OUT;

    # mhonarc require du change workdir so this proc must retore it
    my $pwd = getcwd;

    ## generate HTML
    unless (chdir $destination_dir) {
        Sympa::Log::Syslog::do_log('err',
            'Could not change working directory to %s',
            $destination_dir);
        return undef;
    }

    my $tag = get_tag($that);
    my $exitcode = system($robot->mhonarc, '-single',
        '-rcfile'     => $mhonarc_ressources,
        '-definevars' => "listname='$listname' hostname=$hostname tag=$tag",
        '-outdir'     => $destination_dir,
        '-attachmentdir' => $destination_dir,
        '-attachmenturl' => $attachement_url,
        '-umask'         => Sympa::Site->umask,
        '-stdout'        => "$destination_dir/msg00000.html",
        '--', $msg_file
    ) >> 8;

    # restore current wd
    chdir $pwd;

    if ($exitcode) {
        Sympa::Log::Syslog::do_log('err',
            'Command %s failed with exit code %d',
            $robot->mhonarc, $exitcode);
    }

    return 1;
}

=head2 sub get_tag(OBJECT $that)

Returns a tag derived from the listname.

=head3 Arguments 

=over 

=item * I<$that>, a List or Robot object.

=back 

=head3 Return 

=over 

=item * I<a character string>, corresponding to the 10 last characters of a 32 bytes string containing the MD5 digest of the concatenation of the following strings (in this order):

=over 4

=item - the cookie config parameter

=item - a slash: "/"

=item - name attribute of the I<$that> argument

=back 

=back

=head3 Calls 

=over 

=item * Digest::MD5::md5_hex

=back 

=cut 

sub get_tag {
    my $that = shift;

    return
        substr(Digest::MD5::md5_hex(join '/', Sympa::Site->cookie, $that->name),
        -10);
}

1;
