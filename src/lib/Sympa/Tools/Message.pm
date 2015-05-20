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

=encoding utf-8

=head1 NAME

Sympa::Tools::Message - Message-related functions

=head1 DESCRIPTION

This package provides some message-related functions.

=cut

package Sympa::Tools::Message;

use strict;

use Carp qw(croak);
use English;

use MIME::EncWords;
use MIME::Decoder;
use MIME::Parser;
use Time::Local qw();

use Sympa::Logger;

## Make a multipart/alternative, a singlepart
sub as_singlepart {
    my ($msg, $preferred_type, $loops) = @_;
    my $done = 0;
    $loops++;

    unless (defined $msg) {
        $main::logger->do_log(Sympa::Logger::ERR, "Undefined message parameter");
        return undef;
    }

    if ($loops > 4) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Could not change multipart to singlepart');
        return undef;
    }

    if ($msg->effective_type() =~ /^$preferred_type$/) {
        $done = 1;
    } elsif ($msg->effective_type() =~ /^multipart\/alternative/) {
        foreach my $part ($msg->parts) {
            if (($part->effective_type() =~ /^$preferred_type$/)
                || (   ($part->effective_type() =~ /^multipart\/related$/)
                    && $part->parts
                    && ($part->parts(0)->effective_type() =~
                        /^$preferred_type$/)
                )
                ) {
                ## Only keep the first matching part
                $msg->parts([$part]);
                $msg->make_singlepart();
                $done = 1;
                last;
            }
        }
    } elsif ($msg->effective_type() =~ /multipart\/signed/) {
        my @parts = $msg->parts();
        ## Only keep the first part
        $msg->parts([$parts[0]]);
        $msg->make_singlepart();

        $done ||= as_singlepart($msg, $preferred_type, $loops);

    } elsif ($msg->effective_type() =~ /^multipart/) {
        foreach my $part ($msg->parts) {

            next unless (defined $part);    ## Skip empty parts

            if ($part->effective_type() =~ /^multipart\/alternative/) {
                if (as_singlepart($part, $preferred_type, $loops)) {
                    $msg->parts([$part]);
                    $msg->make_singlepart();
                    $done = 1;
                }
            }
        }
    }

    return $done;
}

sub split_mail {
    my $message  = shift;
    my $pathname = shift;
    my $dir      = shift;

    my $head     = $message->head;
    my $body     = $message->body;
    my $encoding = $head->mime_encoding;

    if ($message->is_multipart
        || ($message->mime_type eq 'message/rfc822')) {

        for (my $i = 0; $i < $message->parts; $i++) {
            split_mail($message->parts($i), $pathname . '.' . $i, $dir);
        }
    } else {
        my $fileExt;

        if ($head->mime_attr("content_type.name") =~ /\.(\w+)\s*\"*$/) {
            $fileExt = $1;
        } elsif ($head->recommended_filename =~ /\.(\w+)\s*\"*$/) {
            $fileExt = $1;
        } else {
            my $mime_types = load_mime_types();

            $fileExt = $mime_types->{$head->mime_type};
            my $var = $head->mime_type;
        }

        ## Store body in file
        unless (open OFILE, ">$dir/$pathname.$fileExt") {
            $main::logger->do_log(Sympa::Logger::ERR, 'Unable to create %s/%s.%s: %s',
                $dir, $pathname, $fileExt, $ERRNO);
            return undef;
        }

        if ($encoding =~
            /^(binary|7bit|8bit|base64|quoted-printable|x-uu|x-uuencode|x-gzip64)$/
            ) {
            open TMP, ">$dir/$pathname.$fileExt.$encoding";
            $message->print_body(\*TMP);
            close TMP;

            open BODY, "$dir/$pathname.$fileExt.$encoding";

            my $decoder = MIME::Decoder->new($encoding);
            unless (defined $decoder) {
                $main::logger->do_log(Sympa::Logger::ERR,
                    'Cannot create decoder for %s', $encoding);
                return undef;
            }
            $decoder->decode(\*BODY, \*OFILE);
            close BODY;
            unlink "$dir/$pathname.$fileExt.$encoding";
        } else {
            $message->print_body(\*OFILE);
        }
        close(OFILE);
        printf "\t-------\t Create file %s\n", $pathname . '.' . $fileExt;

        ## Delete files created twice or more (with Content-Type.name and
        ## Content-Disposition.filename)
        $message->purge;
    }

    return 1;
}

sub virus_infected {
    my (%params) = @_;

    my $mail   = $params{entity};
    my $path   = $params{path};
    my $args   = $params{args};
    my $tmpdir = $params{tmpdir};

    # in, version previous from db spools, $file was the filename of the
    # message
    my $file = int(rand(time));
    $main::logger->do_log(Sympa::Logger::DEBUG2, 'Scan virus in %s', $file);

    unless ($path) {
        $main::logger->do_log(Sympa::Logger::DEBUG,
            'Sympa not configured to scan virus in message');
        return 0;
    }
    my @name = split(/\//, $file);
    my $work_dir = $tmpdir . '/antivirus';

    unless ((-d $work_dir) || (mkdir $work_dir, 0755)) {
        $main::logger->do_log(Sympa::Logger::ERR,
            "Unable to create tmp antivirus directory $work_dir");
        return undef;
    }

    $work_dir = $tmpdir . '/antivirus/' . $name[$#name];

    unless ((-d $work_dir) || mkdir($work_dir, 0755)) {
        $main::logger->do_log(Sympa::Logger::ERR,
            "Unable to create tmp antivirus directory $work_dir");
        return undef;
    }

    #$mail->dump_skeleton;

    ## Call the procedure of splitting mail
    unless (split_mail($mail, 'msg', $work_dir)) {
        $main::logger->do_log(Sympa::Logger::ERR, 'Could not split mail %s', $mail);
        return undef;
    }

    my $virusfound = 0;
    my $error_msg;
    my $result;

    ## McAfee
    if ($path =~ /\/uvscan$/) {

        # impossible to look for viruses with no option set
        unless ($args) {
            $main::logger->do_log(Sympa::Logger::ERR,
                "Missing 'antivirus_args' in sympa.conf");
            return undef;
        }

        my $cmd = sprintf '%s %s %s', $path, $args, $work_dir;
        open(ANTIVIR, "$cmd |");

        while (<ANTIVIR>) {
            $result .= $_;
            chomp $result;
            if (   (/^\s*Found the\s+(.*)\s*virus.*$/i)
                || (/^\s*Found application\s+(.*)\.\s*$/i)) {
                $virusfound = $1;
            }
        }
        close ANTIVIR;

        my $status = $CHILD_ERROR >> 8;

        ## uvscan status =12 or 13 (*256) => virus
        if (($status == 13) || ($status == 12)) {
            $virusfound ||= "unknown";
        }

        ## Meaning of the codes
        ##  12 : The program tried to clean a file, and that clean failed for
        ##  some reason and the file is still infected.
        ##  13 : One or more viruses or hostile objects (such as a Trojan
        ##  horse, joke program,  or  a  test file) were found.
        ##  15 : The programs self-check failed; the program might be infected
        ##  or damaged.
        ##  19 : The program succeeded in cleaning all infected files.

        $error_msg = $result
            if ($status != 0
            && $status != 12
            && $status != 13
            && $status != 19);

        ## Trend Micro
    } elsif ($path =~ /\/vscan$/) {
        my $cmd = sprintf '%s %s %s', $path, $args, $work_dir;
        open(ANTIVIR, "$cmd |");

        while (<ANTIVIR>) {
            if (/Found virus (\S+) /i) {
                $virusfound = $1;
            }
        }
        close ANTIVIR;

        my $status = $CHILD_ERROR >> 8;

        ## uvscan status = 1 | 2 (*256) => virus
        if ((($status == 1) or ($status == 2)) and not($virusfound)) {
            $virusfound = "unknown";
        }

        ## F-Secure
    } elsif ($path =~ /\/fsav$/) {
        my $dbdir = $PREMATCH;

        # impossible to look for viruses with no option set
        unless ($args) {
            $main::logger->do_log(Sympa::Logger::ERR,
                "Missing 'antivirus_args' in sympa.conf");
            return undef;
        }
        my $cmd = sprintf '%s --databasedirectory %s %s %s',
            $path, $dbdir, $args, $work_dir;
        open(ANTIVIR, "$cmd |");

        while (<ANTIVIR>) {

            if (/infection:\s+(.*)/) {
                $virusfound = $1;
            }
        }

        close ANTIVIR;

        my $status = $CHILD_ERROR >> 8;

        ## fsecure status =3 (*256) => virus
        if (($status == 3) and not($virusfound)) {
            $virusfound = "unknown";
        }
    } elsif ($path =~ /f-prot\.sh$/) {

        $main::logger->do_log(Sympa::Logger::DEBUG2, 'f-prot is running');
        my $cmd = sprintf '%s %s %s', $path, $args, $work_dir;
        open(ANTIVIR, "$cmd |");

        while (<ANTIVIR>) {
            if (/Infection:\s+(.*)/) {
                $virusfound = $1;
            }
        }

        close ANTIVIR;

        my $status = $CHILD_ERROR >> 8;

        $main::logger->do_log(Sympa::Logger::DEBUG2, 'Status: ' . $status);

        ## f-prot status =3 (*256) => virus
        if (($status == 3) and not($virusfound)) {
            $virusfound = "unknown";
        }
    } elsif ($path =~ /kavscanner/) {

        # impossible to look for viruses with no option set
        unless ($args) {
            $main::logger->do_log(Sympa::Logger::ERR,
                "Missing 'antivirus_args' in sympa.conf");
            return undef;
        }
        my $cmd = sprintf '%s %s %s', $path, $args, $work_dir;
        open(ANTIVIR, "$cmd |");

        while (<ANTIVIR>) {
            if (/infected:\s+(.*)/) {
                $virusfound = $1;
            } elsif (/suspicion:\s+(.*)/i) {
                $virusfound = $1;
            }
        }
        close ANTIVIR;

        my $status = $CHILD_ERROR >> 8;

        ## uvscan status =3 (*256) => virus
        if (($status >= 3) and not($virusfound)) {
            $virusfound = "unknown";
        }

        ## Sophos Antivirus... by liuk@publinet.it
    } elsif ($path =~ /\/sweep$/) {

        # impossible to look for viruses with no option set
        unless ($args) {
            $main::logger->do_log(Sympa::Logger::ERR,
                "Missing 'antivirus_args' in sympa.conf");
            return undef;
        }
        my $cmd = sprintf '%s %s %s', $path, $args, $work_dir;
        open(ANTIVIR, "$cmd |");

        while (<ANTIVIR>) {
            if (/Virus\s+(.*)/) {
                $virusfound = $1;
            }
        }
        close ANTIVIR;

        my $status = $CHILD_ERROR >> 8;

        ## sweep status =3 (*256) => virus
        if (($status == 3) and not($virusfound)) {
            $virusfound = "unknown";
        }

        ## Clam antivirus
    } elsif ($path =~ /\/clamd?scan$/) {
        my $cmd = sprintf '%s %s %s', $path, $args, $work_dir;
        open(ANTIVIR, "$cmd |");

        my $result;
        while (<ANTIVIR>) {
            $result .= $_;
            chomp $result;
            if (/^\S+:\s(.*)\sFOUND$/) {
                $virusfound = $1;
            }
        }
        close ANTIVIR;

        my $status = $CHILD_ERROR >> 8;

        ## Clamscan status =1 (*256) => virus
        if (($status == 1) and not($virusfound)) {
            $virusfound = "unknown";
        }

        $error_msg = $result
            if ($status != 0 && $status != 1);

    }

    ## Error while running antivir, notify listmaster
    if ($error_msg) {
        Sympa::Site->send_notify_to_listmaster('virus_scan_failed',
            {'filename' => $file, 'error_msg' => $error_msg});
    }

    ## if debug mode is active, the working directory is kept
    unless ($main::options{'debug'}) {
        opendir(DIR, ${work_dir});
        my @list = readdir(DIR);
        closedir(DIR);
        foreach (@list) {
            my $nbre = unlink("$work_dir/$_");
        }
        rmdir($work_dir);
    }

    return $virusfound;

}

#*******************************************
# Function : decode_header
# Description : return header value decoded to UTF-8 or undef.
#               trailing newline will be removed.
#               If sep is given, return all occurrences joined by it.
## IN : msg, tag, [sep]
## OUT : decoded header(s), with hostile characters (newline, nul) removed.
#*******************************************
sub decode_header {
    my $msg = shift;
    my $tag = shift;
    my $sep = shift || undef;

    my $head;
    if (ref $msg and $msg->isa('Sympa::Message')) {
        $head = $msg->as_entity()->head;
    } elsif (ref $msg eq 'MIME::Entity') {
        $head = $msg->head;
    } elsif (ref $msg eq 'MIME::Head' or ref $msg eq 'Mail::Header') {
        $head = $msg;
    } else {
        croak 'bug in logic.  Ask developer';
    }

    if (defined $sep) {
        my @values = $head->get($tag);
        return undef unless scalar @values;
        foreach my $val (@values) {
            $val = MIME::EncWords::decode_mimewords($val, Charset => 'UTF-8');
            chomp $val;
            $val =~ s/(\r\n|\r|\n)([ \t])/$2/g;    #unfold
            $val =~ s/\0|\r\n|\r|\n//g;            # remove newline & nul
        }
        return join $sep, @values;
    } else {
        my $val = $head->get($tag, 0);
        return undef unless defined $val;
        $val = MIME::EncWords::decode_mimewords($val, Charset => 'UTF-8');
        chomp $val;
        $val =~ s/(\r\n|\r|\n)([ \t])/$2/g;        #unfold
        $val =~ s/\0|\r\n|\r|\n//g;                # remove newline & nul

        return $val;
    }
}

####################################################
# public parse_tt2_messageasstring
####################################################
# parse a tt2 file as message
#
#
# IN : -$filename(+) : tt2 filename (with .tt2) | ''
#      -$rcpt(+) : SCALAR |ref(ARRAY) : SMTP "RCPT To:" field
#      -$data(+) : used to parse tt2 file, ref(HASH) with keys :
#         -return_path(+) : SMTP "MAIL From:" field if send by smtp,
#                           "X-Sympa-From:" field if send by spool
#         -to : "To:" header field
#         -lang : tt2 language if $filename
#         -list :  ref(HASH) if $sign_mode = 'smime', keys are :
#            -name
#            -dir
#         -from : "From:" field if not a full msg
#         -subject : "Subject:" field if not a full msg
#         -replyto : "Reply-to:" field if not a full msg
#         -body  : body message if not $filename
#         -headers : ref(HASH) with keys are headers mail
#         -dkim : a set of parameters for appying DKIM signature
#            -d : d=tag
#            -i : i=tag (optionnal)
#            -selector : dkim dns selector
#            -key : the RSA private key
#      -$self(+) : ref(Robot) | "Site"
#      -$sign_mode :'smime' | '' | undef
#
# OUT : 1 | undef
####################################################
sub parse_tt2_messageasstring {
    my $robot    = shift;
    my $filename = shift;
    my $rcpt     = shift;
    my $data     = shift;

    my $header_possible = $data->{'header_possible'};
    my $sign_mode       = $data->{'sign_mode'};
    $main::logger->do_log(Sympa::Logger::DEBUG2,
        '(%s, %s, %s, header_possible=%s, sign_mode=%s)',
        $robot, $filename, $rcpt, $header_possible, $sign_mode);
    my ($to, $message_as_string);

    ## boolean
    $header_possible = 0 unless (defined $header_possible);
    my %header_ok;    # hash containing no missing headers
    my $existing_headers = 0;    # the message already contains headers

    ## We may receive a list of recipients
    if (ref($rcpt)) {
        unless (ref($rcpt) eq 'ARRAY') {
            $main::logger->do_log(Sympa::Logger::NOTICE,
                'Wrong type of reference for rcpt');
            return undef;
        }
    }

    ## Charset for encoding
    $data->{'charset'} ||= Site->get_charset($data->{'lang'});

    if ($filename =~ /\.tt2$/) {

        # TT2 file parsing
        #FIXME: Check TT2 parse error
        my $output;
        my @path = split /\//, $filename;
        Sympa::Template::parse_tt2($data, $path[$#path], \$output);
        $message_as_string .= join('', $output);
        $header_possible = 1;
    } else {    # or not
        $message_as_string .= $data->{'body'};
    }

    ## ## Does the message include headers ?
    if ($header_possible) {
        foreach my $line (split(/\n/, $message_as_string)) {
            last if ($line =~ /^\s*$/);
            if ($line =~ /^[\w-]+:\s*/) {    ## A header field
                $existing_headers = 1;
            } elsif ($existing_headers && ($line =~ /^\s/)) {
                ## Following of a header field
                next;
            } else {
                last;
            }

            foreach my $header (
                qw(message-id date to from subject reply-to
                mime-version content-type content-transfer-encoding)
                ) {
                if ($line =~ /^$header\s*:/i) {
                    $header_ok{$header} = 1;
                    last;
                }
            }
        }
    }

    ## ADD MISSING HEADERS
    my $headers = "";

    unless ($header_ok{'message-id'}) {
        $headers .=
            sprintf("Message-Id: %s\n", Sympa::Tools::get_message_id($robot));
    }

    unless ($header_ok{'date'}) {
        my $now   = time;
        my $tzoff = Time::Local::timegm(localtime $now) - $now;
        my $sign;
        if ($tzoff < 0) {
            ($sign, $tzoff) = ('-', -$tzoff);
        } else {
            $sign = '+';
        }
        $tzoff = sprintf '%s%02d%02d',
            $sign, int($tzoff / 3600), int($tzoff / 60) % 60;
        Sympa::Language::PushLang('en');
        $headers .=
              'Date: '
            . POSIX::strftime("%a, %d %b %Y %H:%M:%S $tzoff", localtime $now)
            . "\n";
        Sympa::Language::PopLang();
    }

    unless ($header_ok{'to'}) {

        # Currently, bare e-mail address is assumed.  Complex ones such as
        # "phrase" <email> won't be allowed.
        if (ref($rcpt)) {
            if ($data->{'to'}) {
                $to = $data->{'to'};
            } else {
                $to = join(",\n   ", @{$rcpt});
            }
        } else {
            $to = $rcpt;
        }
        $headers .= "To: $to\n";
    }
    unless ($header_ok{'from'}) {
        if (   !defined $data->{'from'}
            or $data->{'from'} eq 'sympa'
            or $data->{'from'} eq $data->{'conf'}{'sympa'}) {
            $headers .= 'From: '
                . Sympa::Tools::addrencode(
                $data->{'conf'}{'sympa'},
                $data->{'conf'}{'email_gecos'},
                $data->{'charset'}
                ) . "\n";
        } else {
            $headers .= "From: "
                . MIME::EncWords::encode_mimewords(
                Encode::decode('utf8', $data->{'from'}),
                'Encoding' => 'A',
                'Charset'  => $data->{'charset'},
                'Field'    => 'From'
                ) . "\n";
        }
    }
    unless ($header_ok{'subject'}) {
        $headers .= "Subject: "
            . MIME::EncWords::encode_mimewords(
            Encode::decode('utf8', $data->{'subject'}),
            'Encoding' => 'A',
            'Charset'  => $data->{'charset'},
            'Field'    => 'Subject'
            ) . "\n";
    }
    unless ($header_ok{'reply-to'}) {
        $headers .= "Reply-to: "
            . MIME::EncWords::encode_mimewords(
            Encode::decode('utf8', $data->{'replyto'}),
            'Encoding' => 'A',
            'Charset'  => $data->{'charset'},
            'Field'    => 'Reply-to'
            )
            . "\n"
            if ($data->{'replyto'});
    }
    if ($data->{'headers'}) {
        foreach my $field (keys %{$data->{'headers'}}) {
            $headers .=
                $field . ': '
                . MIME::EncWords::encode_mimewords(
                Encode::decode('utf8', $data->{'headers'}{$field}),
                'Encoding' => 'A',
                'Charset'  => $data->{'charset'},
                'Field'    => $field
                ) . "\n";
        }
    }
    unless ($header_ok{'mime-version'}) {
        $headers .= "MIME-Version: 1.0\n";
    }
    unless ($header_ok{'content-type'}) {
        $headers .=
            "Content-Type: text/plain; charset=" . $data->{'charset'} . "\n";
    }
    unless ($header_ok{'content-transfer-encoding'}) {
        $headers .= "Content-Transfer-Encoding: 8bit\n";
    }

    ## Determine what value the Auto-Submitted header field should take
    ## See http://www.tools.ietf.org/html/draft-palme-autosub-01
    ## the header field can have one of the following values :
    ## auto-generated, auto-replied, auto-forwarded
    ## The header should not be set when wwsympa sends a command/mail to
    ## sympa.pl through its spool
    unless ($data->{'not_auto_submitted'} || $header_ok{'auto_submitted'}) {
        ## Default value is 'auto-generated'
        my $header_value = $data->{'auto_submitted'} || 'auto-generated';
        $headers .= "Auto-Submitted: $header_value\n";
    }

    unless ($existing_headers) {
        $headers .= "\n";
    }

    ## All these data provide mail attachements in service messages
    my @msgs = ();
    if (ref($data->{'msg_list'}) eq 'ARRAY') {
        @msgs =
            map { $_->{'msg'} || $_->{'full_msg'} } @{$data->{'msg_list'}};
    } elsif ($data->{'spool'}) {
        @msgs = @{$data->{'spool'}};
    } elsif ($data->{'msg'}) {
        push @msgs, $data->{'msg'};
    } elsif ($data->{'msg_path'} and open IN, '<' . $data->{'msg_path'}) {
        push @msgs, join('', <IN>);
        close IN;
    } elsif ($data->{'file'} and open IN, '<' . $data->{'file'}) {
        push @msgs, join('', <IN>);
        close IN;
    }

    unless (
        $message_as_string = _reformat_message(
            "$headers" . "$message_as_string",
            \@msgs, $data->{'charset'}
        )
        ) {
        $main::logger->do_log(Sympa::Logger::ERR, 'Failed to reformat message');
    }

    return $message_as_string;
}

####################################################
# reformat_message
####################################################
# Reformat bodies of text parts contained in the message using
# recommended encoding schema and/or charsets defined by MIME::Charset.
#
# MIME-compliant headers are appended / modified.  And custom X-Mailer:
# header is appended :).
#
# IN : $msg: ref(MIME::Entity) | string - message to reformat
#      $attachments: ref(ARRAY) - messages to be attached as subparts.
# OUT : string
#
####################################################

####################################################
## Comments from Soji Ikeda below
##  Some paths of message processing in Sympa can't recognize Unicode strings.
##  At least MIME::Parser::parse_data() and Template::proccess(): these
##  methods
## occationalily break strings containing Unicode characters.
##
##  My mail_utf8 patch expects the behavior as following ---
##
##  Sub-messages to be attached (into digests, moderation notices etc.) will
##  passed to Sympa::Mail::reformat_message() separately then attached to reformatted
##  parent message again.  As a result, sub-messages won't be broken.  Since
##  they won't cause mixture of Unicode string (parent message generated by
##  Sympa::Template::parse_tt2()) and byte string (sub-messages).
##
##  Note: For compatibility with old style, data passed to
##  Sympa::Mail::reformat_message() already includes sub-message(s).  Then:
##   - When a part has an `X-Sympa-Attach:' header field for internal use, new
##     style, Sympa::Mail::reformat_message() attaches raw sub-message to reformatted
##     parent message again;
##   - When a part doesn't have any `X-Sympa-Attach:' header fields,
##     sub-messages generated by [% INSERT %] directive(s) in the template
##     will be used.
##
##  More Note: Latter behavior above will give expected result only if
##  contents of sub-messages are US-ASCII or ISO-8859-1. In other cases
##  customized templates (if any) should be modified so that they have
##  appropriate `X-Sympa-Attach:' header fileds.
##
##  Sub-messages are gathered from template context paramenters.

sub _reformat_message($;$$) {
    my $message     = shift;
    my $attachments = shift || [];
    my $defcharset  = shift;
    my $msg;

    my $parser = MIME::Parser->new();
    unless (defined $parser) {
        $main::logger->do_log(Sympa::Logger::ERR,
            "Sympa::Mail::reformat_message: Failed to create MIME parser");
        return undef;
    }
    $parser->output_to_core(1);

    if (ref($message) eq 'MIME::Entity') {
        $msg = $message;
    } else {
        eval { $msg = $parser->parse_data($message); };
        if ($EVAL_ERROR) {
            $main::logger->do_log(Sympa::Logger::ERR,
                "Sympa::Mail::reformat_message: Failed to parse MIME data");
            return undef;
        }
    }
    $msg->head->delete("X-Mailer");
    $msg = _fix_part($msg, $parser, $attachments, $defcharset);
    $msg->head->add("X-Mailer", sprintf "Sympa %s",
        Sympa::Constants::VERSION);
    return $msg->as_string();
}

sub _fix_part {
    my $part        = shift;
    my $parser      = shift;
    my $attachments = shift || [];
    my $defcharset  = shift;
    return $part unless $part;

    my $enc = $part->head->mime_encoding;

    # Parts with nonstandard encodings aren't modified.
    if ($enc and $enc !~ /^(?:base64|quoted-printable|[78]bit|binary)$/i) {
        return $part;
    }
    my $eff_type = $part->effective_type;

    # Signed or encrypted parts aren't modified.
    if ($eff_type =~ m{^multipart/(signed|encrypted)$}) {
        return $part;
    }

    if ($part->head->get('X-Sympa-Attach')) {    # Need re-attaching data.
        my $data = shift @{$attachments};
        if (ref($data) ne 'MIME::Entity') {
            eval { $data = $parser->parse_data($data); };
            if ($EVAL_ERROR) {
                $main::logger->do_log(Sympa::Logger::NOTICE,
                    "Failed to parse MIME data");
                $data = $parser->parse_data('');
            }
        }
        $part->head->delete('X-Sympa-Attach');
        $part->parts([$data]);
    } elsif ($part->parts) {
        my @newparts = ();
        foreach ($part->parts) {
            push @newparts, _fix_part($_, $parser, $attachments, $defcharset);
        }
        $part->parts(\@newparts);
    } elsif ($eff_type =~ m{^(?:multipart|message)(?:/|\Z)}i) {

        # multipart or message types without subparts.
        return $part;
    } elsif (MIME::Tools::textual_type($eff_type)) {
        my $bodyh = $part->bodyhandle;

        # Encoded body or null body won't be modified.
        return $part if !$bodyh or $bodyh->is_encoded;

        my $head = $part->head;
        my $body = $bodyh->as_string();
        my $wrap = $body;
        if ($head->get('X-Sympa-NoWrap')) {    # Need not wrapping
            $head->delete('X-Sympa-NoWrap');
        } elsif ($eff_type eq 'text/plain'
            and lc($head->mime_attr('Content-type.Format') || '') ne 'flowed')
        {
            $wrap = Sympa::Tools::Text::wrap_text($body);
        }
        my $charset = $head->mime_attr("Content-Type.Charset") || $defcharset;

        my ($newbody, $newcharset, $newenc) =
            MIME::Charset::body_encode(Encode::decode('utf8', $wrap),
            $charset, Replacement => 'FALLBACK');
        if (    $newenc eq $enc
            and $newcharset eq $charset
            and $newbody eq $body) {
            $head->add("MIME-Version", "1.0")
                unless $head->get("MIME-Version");
            return $part;
        }

        ## normalize newline to CRLF if transfer-encoding is BASE64.
        $newbody =~ s/\r\n|\r|\n/\r\n/g
            if $newenc and $newenc eq 'BASE64';

        # Fix headers and body.
        $head->mime_attr("Content-Type", "TEXT/PLAIN")
            unless $head->mime_attr("Content-Type");
        $head->mime_attr("Content-Type.Charset",      $newcharset);
        $head->mime_attr("Content-Transfer-Encoding", $newenc);
        $head->add("MIME-Version", "1.0") unless $head->get("MIME-Version");
        my $io = $bodyh->open("w");

        unless (defined $io) {
            $main::logger->do_log(Sympa::Logger::ERR,
                "Sympa::Mail::reformat_message: Failed to save message : $ERRNO");
            return undef;
        }

        $io->print($newbody);
        $io->close;
        $part->sync_headers(Length => 'COMPUTE');
    } else {

        # Binary or text with long lines will be suggested to be BASE64.
        $part->head->mime_attr("Content-Transfer-Encoding",
            $part->suggest_encoding);
        $part->sync_headers(Length => 'COMPUTE');
    }
    return $part;
}

1;
