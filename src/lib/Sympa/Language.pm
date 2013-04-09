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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Language - Language functions

=head1 DESCRIPTION

This module does just the initial setup for the international messages.

=cut

package Sympa::Language;

use strict;

use Locale::Messages qw (:locale_h :libintl_h !gettext);
use POSIX qw();

#use Sympa::Configuration; FIXME
use Sympa::Constants;
use Sympa::Log::Syslog;

BEGIN {
	## Using the Pure Perl implementation of gettext
	## This is required on Solaris : native implementation of gettext does not map ll_CC with ll
	Locale::Messages->select_package ('gettext_pp');
}

my %msghash;     # Hash organization is like Messages file: File>>Sections>>Messages
my %set_comment; #sets-of-messages comment

## The lang is the NLS catalogue name ; locale is the locale preference
## Ex: lang = fr ; locale = fr_FR
my ($current_lang, $current_locale, $current_charset, @previous_locale);
my $default_lang = 'en';
## This was the old style locale naming, used for templates, nls, scenario
my %language_equiv = (
	'zh_CN' => 'cn',
	'zh_TW' => 'tw',
	'cs'    => 'cz',
	'en_US' => 'us',
);

## Supported languages are defined by 'supported_lang' sympa.conf parameter

my %lang2locale = (
	'ar' => 'ar_SY',
	'af' => 'af_ZA',
	'br' => 'br_FR',
	'bg' => 'bg_BG',
	'ca' => 'ca_ES',
	'cs' => 'cs_CZ',
	'de' => 'de_DE',
	'us' => 'en_US',
	'en' => 'en_US',
	'el' => 'el_GR',
	'es' => 'es_ES',
	'et' => 'et_EE',
	'eu' => 'eu_ES',
	'fi' => 'fi_FI',
	'fr' => 'fr_FR',
	'hu' => 'hu_HU',
	'id' => 'id_ID',
	'it' => 'it_IT',
	'ko' => 'ko_KR',
	'ml' => 'ml_IN',
	'ja' => 'ja_JP',
	'nb' => 'nb_NO',
	'nn' => 'nn_NO',
	'nl' => 'nl_NL',
	'oc' => 'oc_FR',
	'pl' => 'pl_PL',
	'pt' => 'pt_PT',
	'ro' => 'ro_RO',
	'ru' => 'ru_RU',
	'sv' => 'sv_SE',
	'cn' => 'zh_CN',
	'tr' => 'tr_TR',
	'tw' => 'zh_TW',
	'vi' => 'vi_VN',
);

## We use different catalog/textdomains depending on the template that requests translations
my %template2textdomain = (
	'help_admin.tt2'         => 'web_help',
	'help_arc.tt2'           => 'web_help',
	'help_editfile.tt2'      => 'web_help',
	'help_editlist.tt2'      => 'web_help',
	'help_faqadmin.tt2'      => 'web_help',
	'help_faquser.tt2'       => 'web_help',
	'help_introduction.tt2'  => 'web_help',
	'help_listconfig.tt2'    => 'web_help',
	'help_mail_commands.tt2' => 'web_help',
	'help_sendmsg.tt2'       => 'web_help',
	'help_shared.tt2'        => 'web_help',
	'help.tt2'               => 'web_help',
	'help_user_options.tt2'  => 'web_help',
	'help_user.tt2'          => 'web_help',
);

=head1 FUNCTIONS

=over

=item get_supported_languages($supported_languages)

FIXME.

=cut

sub get_supported_languages {
	my ($supported_languages) = @_;

	my @lang_list;

	foreach my $l (split(/,/, $supported_languages)) {
		push @lang_list, $lang2locale{$l}||$l;
	}
	return \@lang_list;
}

=item push_lang($locale)

Keep the previous lang ; can be restored with PopLang.

=cut

sub push_lang {
	my ($locale) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s)', $locale);

	push @previous_locale, $current_locale;
	set_lang($locale);

	return 1;
}

=item pop_lang()

FIXME.

=cut

sub pop_lang {
	Sympa::Log::Syslog::do_log('debug', '');

	my $locale = pop @previous_locale;
	set_lang($locale);

	return 1;
}

=item set_lang($locale)

FIXME.

=cut

sub set_lang {
	my ($locale) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $locale);

	my $lang = $locale || $default_lang;## Use default_lang if an empty parameter

	unless ($lang) {
		Sympa::Log::Syslog::do_log('err', 'missing locale parameter');
		return undef;
	}

	if (length($lang) == 2) {
		$locale = $lang2locale{$lang};
	} else {
		## uppercase the country part if needed
		my @items = split /_/, $locale;
		$items[1] = uc($items[1]);
		$locale = join '_', @items;

		## Get the NLS equivalent for the lang
		$lang = locale2lang($locale);
	}

	## Set Locale::Messages context
	my $locale_dashless = $locale.'.utf-8';
	$locale_dashless =~ s/-//g;
	foreach my $type (POSIX::LC_ALL, POSIX::LC_TIME) {
		my $success;
		foreach my $try ($locale.'.utf-8',
			$locale.'.UTF-8',  ## UpperCase required for FreeBSD
			$locale_dashless, ## Required on HPUX
			$locale,
			$lang
		) {
			if (POSIX::setlocale($type, $try)) {
				$success = 1;
				last;
			}
		}
		unless ($success) {
			Sympa::Log::Syslog::do_log('err','Failed to setlocale(%s) ; you either have a problem with the catalogue .mo files or you should extend available locales in  your /etc/locale.gen (or /etc/sysconfig/i18n) file', $locale);
			return undef;
		}
	}

	$ENV{'LANGUAGE'}=$locale;
	## Define what catalogs are used
	Locale::Messages::textdomain("sympa");
	Locale::Messages::bindtextdomain('sympa',Sympa::Constants::LOCALEDIR);
	Locale::Messages::bindtextdomain('web_help',Sympa::Constants::LOCALEDIR);
	# Get translations by internal encoding.
	bind_textdomain_codeset sympa => 'utf-8';
	bind_textdomain_codeset web_help => 'utf-8';

	$current_lang = $lang;
	$current_locale = $locale;
	my $locale2charset = Sympa::Configuration::get_robot_conf('', 'locale2charset');
	$current_charset = $locale2charset->{$locale} || 'utf-8';

	return $locale;
}

=item get_lang_name($lang)

Get the name of the language, ie the one defined in the catalog

=cut

sub get_lang_name {
	my ($lang) = @_;

	my $saved_lang = $current_lang;
	set_lang($lang);
	my $name = gettext('_language_');
	set_lang($saved_lang);

	return $name;
}

=item get_lang()

FIXME.

=cut

sub get_lang {

	return $current_lang;
}

=item get_charset()

FIXME.

=cut

sub get_charset {

	return $current_charset;
}

=item locale2lang($locale)

FIXME.

=cut

sub locale2lang {
	my ($locale) = @_;

	my $lang;

	if (defined $language_equiv{$locale}) {
		$lang = $language_equiv{$locale};
	} else {
		## remove the country part
		$lang = $locale;
		$lang =~ s/_\w{2}$//;
	}

	return $lang;
}

=item lang2locale($lang)

FIXME.

=cut

sub lang2locale {
	my ($lang) = @_;

	return $lang2locale{$lang} || $lang;
}

=item maketext($template_file, $msg)

FIXME.

=cut

sub maketext {
	my ($template_file, $msg) = @_;

#    Sympa::Log::Syslog::do_log('notice','Maketext: %s', $msg);

	my $translation;
	my $textdomain = $template2textdomain{$template_file};

	if ($textdomain) {
		$translation = sympa_dgettext ($textdomain, $msg);
	} else {
		$translation = gettext ($msg);
	}
#    $translation = gettext ($msg);

	## replace parameters in string
	$translation =~ s/\%\%/'_ESCAPED_'.'%_'/eg; ## First escape '%%'
	$translation =~ s/\%(\d+)/$_[$1-1]/eg;
	$translation =~ s/_ESCAPED_%\_/'%'/eg; ## Unescape '%%'

	return $translation;
}

=item sympa_dgettext($textdomain, @param)

FIXME.

=cut

sub sympa_dgettext {
	my ($textdomain, @param) = @_;
	Sympa::Log::Syslog::do_log('debug3', '(%s)', $param[0]);

	## This prevents meta information to be returned if the string to translate is empty
	if ($param[0] eq '') {
		return '';

		## return meta information on the catalogue (language, charset, encoding,...)
	} elsif ($param[0] =~ '^_(\w+)_$') {
		my $var = $1;
		foreach (split /\n/,Locale::Messages::gettext('')) {
			if ($var eq 'language') {
				if (/^Language-Team:\s*(.+)$/i) {
					my $language = $1;
					$language =~ s/\<\S+\>//;

					return $language;
				}
			} elsif ($var eq 'charset') {
				if (/^Content-Type:\s*.*charset=(\S+)$/i) {
					return $1;
				}
			} elsif ($var eq 'encoding') {
				if (/^Content-Transfer-Encoding:\s*(.+)$/i) {
					return $1;
				}
			}
		}
		return '';
	}

	return Locale::Messages::dgettext($textdomain, @param);

}

=item gettext(@param)

FIXME.

=cut

sub gettext {
	my (@param) = @_;
	Sympa::Log::Syslog::do_log('debug3', '(%s)', $param[0]);

	## This prevents meta information to be returned if the string to translate is empty
	if ($param[0] eq '') {
		return '';

		## return meta information on the catalogue (language, charset, encoding,...)
	} elsif ($param[0] =~ '^_(\w+)_$') {
		my $var = $1;
		foreach (split /\n/,Locale::Messages::gettext('')) {
			if ($var eq 'language') {
				if (/^Language-Team:\s*(.+)$/i) {
					my $language = $1;
					$language =~ s/\<\S+\>//;

					return $language;
				}
			} elsif ($var eq 'charset') {
				if (/^Content-Type:\s*.*charset=(\S+)$/i) {
					return $1;
				}
			} elsif ($var eq 'encoding') {
				if (/^Content-Transfer-Encoding:\s*(.+)$/i) {
					return $1;
				}
			}
		}
		return '';
	}

	return Locale::Messages::gettext(@param);

}

=item gettext_strftime($format)

FIXME.

=cut

sub gettext_strftime {
	my ($format) = @_;

	return POSIX::strftime($format, @_) unless $current_charset;

	$format = gettext($format);
	my $datestr = POSIX::strftime($format, @_);
	return $datestr;
}

=back

=cut

1;
