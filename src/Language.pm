# Language.pm - This module does just the initial setup for the international messages
# RCS Identication ; $Revision$ ; $Date$ 
#
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

package Language;

require Exporter;
use Carp;
@ISA = qw(Exporter);
@EXPORT = qw(Msg gettext);

use strict;
use Log;
use Version;
use Locale::Messages qw (:locale_h :libintl_h);
use POSIX qw (setlocale);

my %msghash;     # Hash organization is like Messages file: File>>Sections>>Messages
my %set_comment; #sets-of-messages comment   

## The lang is the NLS catalogue name ; locale is the locale preference
## Ex: lang = fr ; locale = fr_FR
my ($current_lang, $current_locale);
my $default_lang;
## This was the old style locale naming, used for templates, nls, scenario
my %language_equiv = ( 'zh_CN' => 'cn',
		       'zh_TW' => 'tw',
		       'cs'    => 'cz',
		       'en_us' => 'us',
		       );

## Supported languages
@supported_languages = ('cs_CZ','de_DE','en_US','es_ES','et_EE',
	      'fi_FI','fr_FR','hu_HU','it_IT','nl_NL',
	      'pl_PL','pt_PT','ro_RO','zh_CN','zh_TW');

sub SetLang {
###########
    my $locale = shift;
    do_log('debug', 'Language::SetLang(%s)', $locale);

    my $lang = $locale;

    ## Get the NLS equivalent for the lang
    if (defined $language_equiv{$lang}) {
	$lang = $language_equiv{$lang};
    }else {
	## remove the country part 
	$lang =~ s/_\w{2}$//;
    }
   
    ## Set Locale::Messages context
    setlocale(LC_MESSAGES, $locale);
    textdomain "sympa";
    bindtextdomain sympa => '--DIR--/locale';
    #bind_textdomain_codeset sympa => 'iso-8859-1';

    $current_lang = $lang;
    $current_locale = $locale;
    return 1;
}#SetLang

sub GetLang {
############

    return $current_lang;
}

sub maketext {
    my $msg = shift;

#    &do_log('notice','Maketext: %s', $msg);

    #$msg =~ s/%(\d)/[_$1]/g;
    setlocale(LC_MESSAGES, $current_locale);
    textdomain "sympa";
    bindtextdomain sympa => '--DIR--/locale';
    bind_textdomain_codeset sympa => 'iso-8859-1';

    ## xgettext.pl bug adds a \n to multi-lined strings
    if ($msg =~ /\n.+/m) {
	$msg .= "\n";
    }

    my $translation = gettext ($msg);

    ## replace parameters in string
    $translation =~ s/\%(\d+)/$_[$1-1]/eg;

    return $translation;
}

1;

