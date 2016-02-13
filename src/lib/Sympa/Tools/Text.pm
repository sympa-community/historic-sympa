# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014, 2015, 2016 GIP RENATER
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

package Sympa::Tools::Text;

use strict;
use warnings;
use Encode qw();
use English;                 # FIXME: drop $MATCH usage
use Encode::MIME::Header;    # 'MIME-Q' encoding.
use MIME::EncWords;
use Text::LineFold;
use if (5.008 < $] && $] < 5.016), qw(Unicode::CaseFold fc);
use if (5.016 <= $]), qw(feature fc);

use Sympa::Regexps;

# Old name: tools::addrencode().
sub addrencode {
    my $addr    = shift;
    my $phrase  = (shift || '');
    my $charset = (shift || 'utf8');
    my $comment = (shift || '');

    return undef unless $addr =~ /\S/;

    if ($phrase =~ /[^\s\x21-\x7E]/) {
        $phrase = MIME::EncWords::encode_mimewords(
            Encode::decode('utf8', $phrase),
            'Encoding'    => 'A',
            'Charset'     => $charset,
            'Replacement' => 'FALLBACK',
            'Field'       => 'Resent-Sender', # almost longest
            'Minimal'     => 'DISPNAME',      # needs MIME::EncWords >= 1.012.
        );
    } elsif ($phrase =~ /\S/) {
        $phrase =~ s/([\\\"])/\\$1/g;
        $phrase = '"' . $phrase . '"';
    }
    if ($comment =~ /[^\s\x21-\x27\x2A-\x5B\x5D-\x7E]/) {
        $comment = MIME::EncWords::encode_mimewords(
            Encode::decode('utf8', $comment),
            'Encoding'    => 'A',
            'Charset'     => $charset,
            'Replacement' => 'FALLBACK',
            'Minimal'     => 'DISPNAME',
        );
    } elsif ($comment =~ /\S/) {
        $comment =~ s/([\\\"])/\\$1/g;
    }

    return
          ($phrase  =~ /\S/ ? "$phrase "    : '')
        . ($comment =~ /\S/ ? "($comment) " : '')
        . "<$addr>";
}

# Old names: tools::clean_email(), tools::get_canonical_email().
sub canonic_email {
    my $email = shift;

    return undef unless defined $email;

    # Remove leading and trailing white spaces.
    $email =~ s/\A\s+//;
    $email =~ s/\s+\z//;

    # Lower-case.
    $email =~ tr/A-Z/a-z/;

    return (length $email) ? $email : undef;
}

# Old name: tools::clean_msg_id().
sub canonic_message_id {
    my $msg_id = shift;

    return $msg_id unless defined $msg_id;

    chomp $msg_id;

    if ($msg_id =~ /\<(.+)\>/) {
        $msg_id = $1;
    }

    return $msg_id;
}

sub wrap_text {
    my $text = shift;
    my $init = shift;
    my $subs = shift;
    my $cols = shift;
    $cols = 78 unless defined $cols;
    return $text unless $cols;

    $text = Text::LineFold->new(
        Language      => Sympa::Language->instance->get_lang,
        OutputCharset => (Encode::is_utf8($text) ? '_UNICODE_' : 'utf8'),
        Prep          => 'NONBREAKURI',
        ColumnsMax    => $cols
    )->fold($init, $subs, $text);

    return $text;
}

sub decode_filesystem_safe {
    my $str = shift;
    return '' unless defined $str and length $str;

    $str = Encode::encode_utf8($str) if Encode::is_utf8($str);
    # On case-insensitive filesystem "_XX" along with "_xx" should be decoded.
    $str =~ s/_([0-9A-Fa-f]{2})/chr hex "0x$1"/eg;
    return $str;
}

sub encode_filesystem_safe {
    my $str = shift;
    return '' unless defined $str and length $str;

    $str = Encode::encode_utf8($str) if Encode::is_utf8($str);
    $str =~ s/([^-+.0-9\@A-Za-z])/sprintf '_%02x', ord $1/eg;
    return $str;
}

# Old name: tools::escape_chars().
sub escape_chars {
    my $s          = shift;
    my $except     = shift;                            ## Exceptions
    my $ord_except = ord $except if defined $except;

    ## Escape chars
    ##  !"#$%&'()+,:;<=>?[] AND accented chars
    ## escape % first
    foreach my $i (
        0x25,
        0x20 .. 0x24,
        0x26 .. 0x2c,
        0x3a .. 0x3f,
        0x5b, 0x5d,
        0x80 .. 0x9f,
        0xa0 .. 0xff
        ) {
        next if defined $ord_except and $i == $ord_except;
        my $hex_i = sprintf "%lx", $i;
        $s =~ s/\x$hex_i/%$hex_i/g;
    }
    ## Special traetment for '/'
    $s =~ s/\//%a5/g unless defined $except and $except eq '/';

    return $s;
}

# Old name: tt2::escape_url().
sub escape_url {
    my $string = shift;

    $string =~ s/[\s+]/sprintf('%%%02x', ord($MATCH))/eg;
    # Some MUAs aren't able to decode ``%40'' (escaped ``@'') in e-mail
    # address of mailto: URL, or take ``@'' in query component for a
    # delimiter to separate URL from the rest.
    my ($body, $query) = split(/\?/, $string, 2);
    if (defined $query) {
        $query =~ s/\@/sprintf('%%%02x', ord($MATCH))/eg;
        $string = $body . '?' . $query;
    }

    return $string;
}

sub foldcase {
    my $str = shift;
    return '' unless defined $str and length $str;

    if ($] <= 5.008) {
        # Perl 5.8.0 does not support Unicode::CaseFold. Use lc() instead.
        return Encode::encode_utf8(lc(Encode::decode_utf8($str)));
    } else {
        # later supports it. Perl 5.16.0 and later have built-in fc().
        return Encode::encode_utf8(fc(Encode::decode_utf8($str)));
    }
}

# Old name: tools::qdecode_filename().
sub qdecode_filename {
    my $filename = shift;

    ## We don't use MIME::Words here because it does not encode properly
    ## Unicode
    ## Check if string is already Q-encoded first
    #if ($filename =~ /\=\?UTF-8\?/) {
    $filename = Encode::encode_utf8(Encode::decode('MIME-Q', $filename));
    #}

    return $filename;
}

# Old name: tools::qencode_filename().
sub qencode_filename {
    my $filename = shift;

    ## We don't use MIME::Words here because it does not encode properly
    ## Unicode
    ## Check if string is already Q-encoded first
    ## Also check if the string contains 8bit chars
    unless ($filename =~ /\=\?UTF-8\?/
        || $filename =~ /^[\x00-\x7f]*$/) {

        ## Don't encode elements such as .desc. or .url or .moderate
        ## or .extension
        my $part = $filename;
        my ($leading, $trailing);
        $leading  = $1 if ($part =~ s/^(\.desc\.)//);    ## leading .desc
        $trailing = $1 if ($part =~ s/((\.\w+)+)$//);    ## trailing .xx

        my $encoded_part = MIME::EncWords::encode_mimewords(
            $part,
            Charset    => 'utf8',
            Encoding   => 'q',
            MaxLineLen => 1000,
            Minimal    => 'NO'
        );

        $filename = $leading . $encoded_part . $trailing;
    }

    return $filename;
}

# Old name: tools::unescape_chars().
sub unescape_chars {
    my $s = shift;

    $s =~ s/%a5/\//g;    ## Special traetment for '/'
    foreach my $i (0x20 .. 0x2c, 0x3a .. 0x3f, 0x5b, 0x5d, 0x80 .. 0x9f,
        0xa0 .. 0xff) {
        my $hex_i = sprintf "%lx", $i;
        my $hex_s = sprintf "%c",  $i;
        $s =~ s/%$hex_i/$hex_s/g;
    }

    return $s;
}

# Old name: tools::valid_email().
sub valid_email {
    my $email = shift;

    my $email_re = Sympa::Regexps::email();
    return undef unless $email =~ /^${email_re}$/;

    # Forbidden characters.
    return undef if $email =~ /[\|\$\*\?\!]/;

    return 1;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sympa::Tools::Text - Text-related functions

=head1 DESCRIPTION

This package provides some text-related functions.

=head2 Functions

=over

=item addrencode ( $addr, [ $phrase, [ $charset, [ $comment ] ] ] )

Returns formatted (and encoded) name-addr as RFC5322 3.4.

=item canonic_email ( $email )

I<Function>.
Returns canonical form of e-mail address.

Leading and trailing whilte spaces are removed.
Latin letters without accents are lower-cased.

For malformed inputs returns C<undef>.

=item canonic_message_id ( $message_id )

Returns canonical form of message ID without trailing or leading whitespaces
or C<E<lt>>, C<E<gt>>.

=item wrap_text ( $text, [ $init_tab, [ $subsequent_tab, [ $cols ] ] ] )

I<Function>.
Returns line-wrapped text.

Parameters:

=over

=item $text

The text to be folded.

=item $init_tab

Indentation prepended to the first line of paragraph.
Default is C<''>, no indentation.

=item $subsequent_tab

Indentation prepended to each subsequent line of folded paragraph.
Default is C<''>, no indentation.

=item $cols

Max number of columns of folded text.
Default is C<78>.

=back

=item decode_filesystem_safe ( $str )

I<Function>.
Decodes a string encoded by encode_filesystem_safe().

Parameter:

=over

=item $str

String to be decoded.

=back

Returns:

Decoded string, stripped C<utf8> flag if any.

=item encode_filesystem_safe ( $str )

I<Function>.
Encodes a string $str to be suitable for filesystem.

Parameter:

=over

=item $str

String to be encoded.

=back

Returns:

Encoded string, stripped C<utf8> flag if any.
All bytes except C<'-'>, C<'+'>, C<'.'>, C<'@'>
and alphanumeric characters are encoded to sequences C<'_'> followed by
two hexdigits.

Note that C<'/'> will also be encoded.

=item escape_chars ( $str )

Escape weird characters.

ToDo: This should be obsoleted in the future release: Would be better to use
L</encode_filesystem_safe>.

=item escape_url ( $str )

Escapes string using URL encoding.

=item foldcase ( $str )

I<Function>.
Returns "fold-case" string suitable for case-insensitive match.
For example, a code below looks for a needle in haystack not regarding case,
even if they are non-ASCII UTF-8 strings.

  $haystack = Sympa::Tools::Text::foldcase($HayStack);
  $needle   = Sympa::Tools::Text::foldcase($NeedLe);
  if (index $haystack, $needle >= 0) {
      ...
  }

Parameter:

=over

=item $str

A string.

=back

=item qdecode_filename ( $filename )

Q-Decodes web file name.

ToDo:
This should be obsoleted in the future release: Would be better to use
L</decode_filesystem_safe>.

=item qencode_filename ( $filename )

Q-Encodes web file name.

ToDo:
This should be obsoleted in the future release: Would be better to use
L</encode_filesystem_safe>.

=item unescape_chars ( $str )

Unescape weird characters.

ToDo: This should be obsoleted in the future release: Would be better to use
L</decode_filesystem_safe>.

=item valid_email ( $string )

Basic check of an email address.

=back

=head1 HISTORY

L<Sympa::Tools::Text> appeared on Sympa 6.2a.41.

decode_filesystem_safe() and encode_filesystem_safe() were added
on Sympa 6.2.10.

=cut
