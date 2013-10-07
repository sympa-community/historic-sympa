# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:et:sw=4:textwidth=78
# $Id$

###############################################################
#                      PlainDigest                            #
# version: 0.4.0rc6                                           #
#                                                             #
#                                                             #
# SYNOPSIS:                                                   #
# (assuming an existing MIME::Entity object as $mail)         #
#                                                             #
# use PlainDigest;                                            #
# $string = $mail->PlainDigest::plain_body_as_string(%opt);   #
#                                                             #
# where %opt is a hash of options, currently:                 #
# use_lynx => [0|1]: use Lynx to process HTML rather than     #
#                      cpan HTML::TreeBuilder and             #
#                      HTML::FormatText modules               #
#                                                             #
# WHAT DOES IT DO?                                            #
# Most attachments are stripped out and replaced with a       #
# note that they've been stripped. text/plain parts are       #
# retained.                                                   #
#                                                             #
# An attempt to convert text/html parts to plain text is made #
# if there is no text/plain alternative.                      #
#                                                             #
# All messages are converted from their original character    #
# set to UTF-8                                                #
#                                                             #
# Parts of type message/rfc822 are recursed                   #
# through in the same way, with brief headers included.       #
#                                                             #
# Any line consisting only of 30 hyphens has the first        #
# character changed to space (see RFC 1153). Lines are        #
# wrapped at 80 characters.                                   #
#                                                             #
# BUGS                                                        #
# Probably dozens of them, and possibly dependant on your     #
# versions of Perl and MIME-Tools (on which it is very        #
# reliant).                                                   #
# Seems to ignore any text after a UUencoded attachment.      #
#                                                             #
# LICENSE                                                     #
# Written by and (c) Chris Hastie 2004 - 2008                 #
# This program is free software; you can redistribute it      #
# and/or modify it under the terms of the GNU General Public  #
# License as published by the Free Software Foundation; either#
# version 2 of the License, or (at your option) any later     #
# version.                                                    #
#                                                             #
# This program is distributed in the hope that it will be     #
# useful,but WITHOUT ANY WARRANTY; without even the implied   #
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR     #
# PURPOSE. See the GNU General Public License for more details#
#                                                             #
# You should have received a copy of the GNU General Public   #
# License along with this program. If not, see                #
# <http://www.gnu.org/licenses/>.                             #
#                                        Chris Hastie         #
#                                                             #
###############################################################
# Changes
# 20080910
# - don't bother trying to find path to lynx unless use_lynx is true
# - anchor content-type test strings to end of string to avoid
#    picking up malformed headers as per bug 3702
# - local Text::Wrap variables
# - moved repeated code to get charset into sub _getCharset
# - added use of MIME::Charset to check charset aliases
# 20100810 - S. Ikeda
# - Remove dependency on Text::Wrap: use common utility Sympa::Tools::wrap_text().
# - Use MIME::Charset OO to handle vendor-defined encodings.
# - Use MIME::EncWords instead of MIME::WordDecoder.
# - Now HTML::FormatText is mandatory.  Remove Lynx support.

=encoding utf-8

=head1 NAME

Sympa::PlainDigest - MIME::Entity extension

=head1 DESCRIPTION

PlainDigest provides an extension to the MIME::Entity class that returns a
plain text version of an email message, suitable for use in plain text digests.

=cut

package Sympa::PlainDigest;

use strict;

use base qw(MIME::Entity);

use English qw(-no_match_vars);

use Mail::Address;
use MIME::EncWords;
use MIME::Charset;
use HTML::TreeBuilder;

use Sympa::HTML::FormatText;
use Sympa::Language;
use Sympa::Tools;

my $outstring;

sub plain_body_as_string {

    $outstring = "";
    my ($topent) = @_;

    _do_toplevel ($topent);

    # clean up after ourselves
    $topent->purge;

    return Sympa::Tools::wrap_text($outstring, '', '');
}

sub _do_toplevel {
    my ($topent) = @_;

    if ($topent->effective_type =~ /^text\/plain$/i || $topent->effective_type =~ /^text\/enriched/i) {
        _do_text_plain($topent);
    }
    elsif ($topent->effective_type =~ /^text\/html$/i) {
        _do_text_html($topent);
    }
    elsif ($topent->effective_type =~ /^multipart\/.*/i) {
        _do_multipart ($topent);
    }
    elsif ($topent->effective_type =~ /^message\/rfc822$/i) {
        _do_message ($topent);
    }
    elsif ($topent->effective_type =~ /^message\/delivery\-status$/i) {
        _do_dsn ($topent);
    }
    else {
        _do_other ($topent);
    }
    return 1;
}

sub _do_multipart {
    my ($topent) = @_;

    # cycle through each part and process accordingly
    foreach my $subent ($topent->parts) {
        if ($subent->effective_type =~ /^text\/plain$/i || $subent->effective_type =~ /^text\/enriched/i) {
            _do_text_plain($subent);
        }
        elsif ($subent->effective_type =~ /^multipart\/related$/i){
            if ($topent->effective_type =~ /^multipart\/alternative$/i && _hasTextPlain($topent)) {
                # this is a rare case - /related nested inside /alternative.
                # If there's also a text/plain alternative just ignore it
                next;
            } else {
                # just treat like any other multipart
                _do_multipart ($subent);
            }
        }
        elsif ($subent->effective_type =~ /^multipart\/.*/i) {
            _do_multipart ($subent);
        }
        elsif ($subent->effective_type =~ /^text\/html$/i ) {
            if( $topent->effective_type =~ /^multipart\/alternative$/i && _hasTextPlain($topent)) {
                # there's a text/plain alternive, so don't warn
                # that the text/html part has been scrubbed
                next;
            }
            _do_text_html ($subent);
        }
        elsif ($subent->effective_type =~ /^message\/rfc822$/i) {
            _do_message ($subent);
        }
        elsif ($subent->effective_type =~ /^message\/delivery\-status$/i) {
            _do_dsn ($subent);
        }
        else {
            # something else - just scrub it and add a message to say what was there
            _do_other ($subent);
        }
    }
    return 1;

}

sub _do_message {
    my ($topent) = @_;

    my $msgent = $topent->parts(0);

    unless ($msgent) {
        $outstring .= sprintf(Sympa::Language::gettext("----- Malformed message ignored -----\n\n"));
        return undef;
    }

    my $from = Sympa::Tools::decode_header($msgent, 'From');
    $from = Sympa::Language::gettext("[Unknown]") unless defined $from and length $from;

    my $subject = Sympa::Tools::decode_header($msgent, 'Subject');
    $subject = '' unless defined $subject;

    my $date = Sympa::Tools::decode_header($msgent, 'Date');
    $date = '' unless defined $date;

    my $to = Sympa::Tools::decode_header($msgent, 'To', ', ');
    $to = '' unless defined $to;

    my $cc = Sympa::Tools::decode_header($msgent, 'Cc', ', ');
    $cc = '' unless defined $cc;

    chomp $from;
    chomp $to;
    chomp $cc;
    chomp $subject;
    chomp $date;

    my @fromline = Mail::Address->parse($msgent->head()->get('From'));
    my $name;
    if ($fromline[0]) {
        $name = MIME::EncWords::decode_mimewords($fromline[0]->name(),
            Charset=>'utf8');
        $name = $fromline[0]->address() unless $name =~ /\S/;
        chomp $name if $name;
    }
    $name = $from unless defined $name and length $name;

    $outstring .= Sympa::Language::gettext("\n[Attached message follows]\n-----Original message-----\n");
    my $headers = '';
    $headers .= sprintf(Sympa::Language::gettext("Date: %s\n") , $date) if $date;
    $headers .= sprintf(Sympa::Language::gettext("From: %s\n"), $from) if $from;
    $headers .= sprintf(Sympa::Language::gettext("To: %s\n"), $to) if $to;
    $headers .= sprintf(Sympa::Language::gettext("Cc: %s\n"), $cc) if $cc;
    $headers .= sprintf(Sympa::Language::gettext("Subject: %s\n"),$subject ) if $subject;
    $headers .= "\n";
    $outstring .= Sympa::Tools::wrap_text($headers, '', '    ');

    _do_toplevel ($msgent);

    $outstring .= sprintf(Sympa::Language::gettext("-----End of original message from %s-----\n\n"), $name);
    return 1;
}

sub _do_text_plain {
    my ($entity) = @_;

    if (($entity->head->get('Content-Disposition') || '') =~ /attachment/) {
        return _do_other($entity);
    }

    my $thispart = $entity->bodyhandle()->as_string();

    # deal with CR/LF left over - a problem from Outlook which
    # qp encodes them
    $thispart =~ s/\r\n/\n/g;

    ## normalise body to UTF-8
    # get charset
    my $charset = _getCharset($entity);
    eval {
        $charset->encoder('utf8');
        $thispart = $charset->encode($thispart);
    };
    if ($EVAL_ERROR) {
        # mmm, what to do if it fails?
        $outstring .= sprintf (Sympa::Language::gettext("** Warning: Message part using unrecognised character set %s\n    Some characters may be lost or incorrect **\n\n"), $charset->as_string());
        $thispart =~ s/[^\x00-\x7F]/?/g;
    }

    # deal with 30 hyphens (RFC 1153)
    $thispart =~ s/\n-{30}(\n|$)/\n -----------------------------\n/g;
    # leading and trailing lines (RFC 1153)
    $thispart =~ s/^\n*//;
    $thispart =~ s/\n+$/\n/;

    $outstring .= $thispart;
    return 1;
}

# just add a note that attachment was stripped.
sub _do_other {
    my ($entity) = @_;

    $outstring .= sprintf (Sympa::Language::gettext("\n[An attachment of type %s was included here]\n"), $entity->mime_type);
    return 1;
}

sub _do_dsn {
    my ($entity) = @_;

    $outstring .= sprintf (Sympa::Language::gettext("\n-----Delivery Status Report-----\n"));
    _do_text_plain ($entity);
    $outstring .= sprintf (Sympa::Language::gettext("\n-----End of Delivery Status Report-----\n"));
}

# get a plain text representation of an HTML part
sub _do_text_html {
    my ($entity) = @_;

    my $text;

    unless (defined $entity->bodyhandle()) {
        $outstring .= Sympa::Language::gettext("\n[** Unable to process HTML message part **]\n");
        return undef;
    }

    my $body = $entity->bodyhandle()->as_string();

    # deal with CR/LF left over - a problem from Outlook which
    # qp encodes them
    $body =~ s/\r\n/\n/g;

    my $charset = _getCharset($entity);

    eval {
        # normalise body to internal unicode
        if ($charset->decoder) {
            $body =  $charset->decode($body);
        } else {
            # mmm, what to do if it fails?
            $outstring .= sprintf (Sympa::Language::gettext("** Warning: Message part using unrecognised character set %s\n    Some characters may be lost or incorrect **\n\n"), $charset->as_string());
            $body =~ s/[^\x00-\x7F]/?/g;
        }
        my $tree = HTML::TreeBuilder->new->parse($body);
        $tree->eof();
        my $formatter = Sympa::HTML::FormatText->new(leftmargin => 0, rightmargin => 72);
        $text = $formatter->format($tree);
        $tree->delete();
        $text = Encode::encode_utf8($text);
    };
    if ($EVAL_ERROR) {
        $outstring .= Sympa::Language::gettext("\n[** Unable to process HTML message part **]\n");
        return 1;
    }

    $outstring .= sprintf(Sympa::Language::gettext("[ Text converted from HTML ]\n"));

    # deal with 30 hyphens (RFC 1153)
    $text =~ s/\n-{30}(\n|$)/\n -----------------------------\n/g;
    # leading and trailing lines (RFC 1153)
    $text =~ s/^\n*//;
    $text =~ s/\n+$/\n/;

    $outstring .= $text;

    return 1;
}

# tell if an entity has text/plain children
sub _hasTextPlain {
    my ($topent) = @_;

    my @subents = $topent->parts;
    foreach my $subent (@subents) {
        if ($subent->effective_type =~ /^text\/plain$/i) {
            return 1;
        }
    }
    return undef;
}

sub _getCharset {
    my ($entity) = @_;

    my $charset = $entity->head()->mime_attr('content-type.charset')?$entity->head()->mime_attr('content-type.charset'):'us-ascii';
    # malformed mail with single quotes around charset?
    if ($charset =~ /'([^']*)'/i) { $charset = $1; };

    # get charset object.
    return MIME::Charset->new($charset);
}

1;
