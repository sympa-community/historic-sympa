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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=encoding utf-8

# TT2 adapter for sympa's template system - Chia-liang Kao <clkao@clkao.org>
# usage: replace require 'parser.pl' in wwwsympa and other .pl

=head1 NAME

Sympa::Template - Template functions

=head1 DESCRIPTION

This module provides template-related functions.

=cut

package Sympa::Template;

use strict;
use warnings;
use CGI::Util;
use English qw(-no_match_vars);
use MIME::EncWords;
use Template;
use Template;

use Sympa::Constants;
use Sympa::Language;
use Sympa::Log::Syslog;
use Sympa::Template::Compat;

my $current_lang;
my $last_error;
my @other_include_path;
my $allow_absolute;

=head1 FUNCTIONS

=over

=item qencode($string)

FIXME.

=cut

sub qencode {
	my ($string) = @_;

	# We are not able to determine the name of header field, so assume
	# longest (maybe) one.
	return MIME::EncWords::encode_mimewords(Encode::decode('utf8', $string),
		Encoding=>'A',
		Charset=>Sympa::Language::get_charset(),
		Field=>"message-id");
}

=item escape_url($string)

FIXME.

=cut

sub escape_url {
	my ($string) = @_;

	$string =~ s/[\s+]/sprintf('%%%02x', ord($&))/eg;
	# Some MUAs aren't able to decode ``%40'' (escaped ``@'') in e-mail
	# address of mailto: URL, or take ``@'' in query component for a
	# delimiter to separate URL from the rest.
	my ($body, $query) = split(/\?/, $string, 2);
	if (defined $query) {
		$query =~ s/\@/sprintf('%%%02x', ord($&))/eg;
		$string = $body.'?'.$query;
	}

	return $string;
}

=item escape_xml($string)

FIXME.

=cut

sub escape_xml {
	my ($string) = @_;

	$string =~ s/&/&amp;/g;
	$string =~ s/</&lt;/g;
	$string =~ s/>/&gt;/g;
	$string =~ s/\'/&apos;/g;
	$string =~ s/\"/&quot;/g;

	return $string;
}

=item escape_quote($string)

FIXME.

=cut

sub escape_quote {
	my ($string) = @_;

	$string =~ s/\'/\\\'/g;
	$string =~ s/\"/\\\"/g;

	return $string;
}

=item encode_utf8($string)

FIXME.

=cut

sub encode_utf8 {
	my ($string) = @_;

	## Skip if already internally tagged utf8
	if (Encode::is_utf8($string)) {
		return Encode::encode_utf8($string);
	}

	return $string;

}

=item decode_utf8($string)

FIXME.

=cut

sub decode_utf8 {
	my ($string) = @_;

	## Skip if already internally tagged utf8
	unless (Encode::is_utf8($string)) {
		## Wrapped with eval to prevent Sympa process from dying
		## FB_CROAK is used instead of FB_WARN to pass $string intact to succeeding processes it operation fails
		eval {
			$string = Encode::decode('utf8', $string, Encode::FB_CROAK);
		};
		$EVAL_ERROR = '';
	}

	return $string;

}

=item maketext($context, @arg)

FIXME.

=cut

sub maketext {
	my ($context, @arg) = @_;

	my $stash = $context->stash();
	my $component = $stash->get('component');
	my $template_name = $component->{'name'};

	## Strangely the path is sometimes empty...
	## TODO : investigate
#    Sympa::Log::Syslog::do_log('notice', "PATH: $path ; $template_name");

	## Sample code to dump the STASH
	# my $s = $stash->_dump();

	return sub {
		Sympa::Language::maketext($template_name, $_[0],  @arg);
	}
}

=item locdatetime(undef, $arg)

FIXME.

Parameters:

=over

=item string

A date/time mask: "YYYY/MM", "YYYY/MM/DD", "YYYY/MM/DD/HH/MM", "YYYY/MM/DD/HH/MM/SS"

=back

Return value:

A date formating callback.

=cut

sub locdatetime {
	my (undef, $arg) = @_;

	if ($arg !~ /^(\d{4})\D(\d\d?)(?:\D(\d\d?)(?:\D(\d\d?)\D(\d\d?)(?:\D(\d\d?))?)?)?/) {
		return sub { Sympa::Language::gettext("(unknown date)"); };
	} else {
		my @arg = ($6+0, $5+0, $4+0, $3+0 || 1, $2-1, $1-1900, 0,0,0);
		return sub { Sympa::Language::gettext_strftime($_[0], @arg); };
	}
}

=item wrap(undef, $init, $subs, $cols)

FIXME.

Parameters:

=over

=item number

The indentation depth of each paragraph.

=item number

The indentation of other lines

=item number

The line width (default: 78)

=back

Return value:

A text formating callback.

=cut

sub wrap {
	my (undef, $init, $subs, $cols) = @_;

	$init = '' unless defined $init;
	$init = ' ' x $init if $init =~ /^\d+$/;
	$subs = '' unless defined $subs;
	$subs = ' ' x $subs if $subs =~ /^\d+$/;

	return sub {
		my $text = shift;
		my $nl = $text =~ /\n$/;
		my $ret = Sympa::Tools::wrap_text($text, $init, $subs, $cols);
		$ret =~ s/\n$// unless $nl;
		$ret;
	};
}

=item optdesc($context, $type, $withval)

FIXME.

Parameters:

=over

=item number

The context.

=item number

The type of list parameter value: 'reception', 'visibility', 'status' or 'others' (default)

=item number

Should parameter value be added to the description. False by default.

=back

Return value:

Subref to generate i18n'ed description of list parameter value.

=cut

sub optdesc {
	my ($context, $type, $withval) = @_;
	return sub {
		my $x = shift;
		return undef unless defined $x;
		return undef unless $x =~ /\S/;
		$x =~ s/^\s+//;
		$x =~ s/\s+$//;
		return List->get_option_title($x, $type, $withval);
	};
}

=item add_include_path($path)

Add a directory to TT2 template search path.

=cut

sub add_include_path {
	my ($path) = @_;

	push @other_include_path, $path;
}

=item get_include_path()

Get current TT2 template search path.

=cut

sub get_include_path {
	return @other_include_path;
}

=item allow_absolute_path()

Allow inclusion/insertion of file with absolute path.

=cut

sub allow_absolute_path {
	$allow_absolute = 1;
}

=item get_error()

Return the last error message

=cut

sub get_error {
	return $last_error;
}

=item parse_tt2($data, $template, $output, $include_path, $options)

The main parsing function

Parameters:

=over

=item data: a HASH ref containing the data

=item template : a filename or a ARRAY ref that contains the template

=item output : a Filedescriptor or a SCALAR ref for the output

=back

Return value:

The last error message

=cut

sub parse_tt2 {
	my ($data, $template, $output, $include_path, $options) = @_;
	$include_path ||= [Sympa::Constants::DEFAULTDIR];
	$options ||= {};

	## Add directories that may have been added
	push @{$include_path}, @other_include_path;
	@other_include_path = (); ## Reset it

	## An array can be used as a template (instead of a filename)
	if (ref($template) eq 'ARRAY') {
		$template = \join('', @$template);
	}

	Sympa::Language::set_lang($data->{lang}) if ($data->{'lang'});

	my $config = {
	#	ABSOLUTE   => 1,
		INCLUDE_PATH => $include_path,
	#	PRE_CHOMP  => 1,
		UNICODE      => 0, # Prevent BOM auto-detection
		FILTERS      => {
			unescape     => \CGI::Util::unescape,
			l            => [\&maketext, 1],
			loc          => [\&maketext, 1],
			helploc      => [\&maketext, 1],
			locdt        => [\&locdatetime, 1],
			wrap         => [\&wrap, 1],
			optdesc      => [\&optdesc, 1],
			qencode      => [\&qencode, 0],
			escape_xml   => [\&escape_xml, 0],
			escape_url   => [\&escape_url, 0],
			escape_quote => [\&escape_quote, 0],
			decode_utf8  => [\&decode_utf8, 0],
			encode_utf8  => [\&encode_utf8, 0]
		}
	};

	unless($options->{'is_not_template'}){
		$config->{'INCLUDE_PATH'} = $include_path;
	}
	if ($allow_absolute) {
		$config->{'ABSOLUTE'} = 1;
		$allow_absolute = 0;
	}
	if ($options->{'has_header'}) { # body is separated by an empty line.
		if (ref $template) {
			$template = \("\n" . $$template);
		} else {
			$template = \"\n[% PROCESS $template %]";
		}
	}

	my $tt2 = Template->new($config) or die "Template error: ".Template->error();

	unless ($tt2->process($template, $data, $output)) {
		$last_error = $tt2->error();
		Sympa::Log::Syslog::do_log('err', 'Failed to parse %s : %s', $template, "$last_error");
		Sympa::Log::Syslog::do_log('err', 'Looking for TT2 files in %s', join(',',@{$include_path}));


		return undef;
	}

	return 1;
}

=back

=cut

1;
