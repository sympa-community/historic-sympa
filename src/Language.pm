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

sub GetHash { return %msghash;}

sub LoadLang {
#############
#To Load all files in MsgHash

    my $msgdir = shift;
    &do_log('debug', "Language::LoadLang(%s)", $msgdir);

    unless (-d $msgdir && -r $msgdir){
	
	do_log('err','Cannot read Locale directory %s', $msgdir);
	return undef;
    }
   
    unless (opendir MSGDIR, $msgdir) {
	do_log('err','Unable to open directory %s', $msgdir);
	return undef;
    }
    
    foreach my $file (grep /\.msg$/, readdir(MSGDIR)) {    

	$file =~ /^([\w-]+)\.msg$/;
	
	my $lang_name = $1;
	
	unless (Msg_file_open($msgdir.'/'.$file,$lang_name)) {
	    do_log('err','Error while calling Msg_file_Open(%s, %s)', $msgdir.'/'.$file,$lang_name);
	    return undef;
	}
    }
    closedir MSGDIR;
    
    return 1;
}#sub Load_Lang


sub Msg_file_open {
#################

    my $msgfile = shift; #Messages File name
    my $lang = shift;    #Language
    my $set_num;           # Section Number
    my $msg_num;        # Message Number in Section
    my $msg_value;     # Message content

    #Opening   ##
    chomp($msgfile);
    do_log('info', 'Loading locale file %s version', $msgfile);	
    unless (-r $msgfile) { #check if file exists
	do_log('err','Cannot read file %s', $msgfile);
        return undef;
    }

    unless (open(MSGFILE,$msgfile)) { 
	do_log('err','Cannot open message File %s', $msgfile);
	return undef;
    }

    #Process  ##
    while (<MSGFILE>) {  
   	my $current_line = $_;
	chomp($current_line);

	next if ($current_line =~ /^\s*$/) || ($current_line =~ /^\$(\s+|quote)/);         # for empty or comments Lines

	if ($current_line =~ /^\$set\s+(\d+)\s+(.+)$/i){	                           # When it's a Section-separation  Line
	    $set_num = $1;
	    $set_comment{$set_num} = $2;	                                                 
	
	}elsif ($current_line =~ /^(\d+)\s+\"(.*)(\\|\")\s*$/i){                          # When it's a Begin of Message
	    $msg_num = $1;  
	    $msghash{$lang}{$set_num}{$msg_num} = $2;

     	}elsif ($current_line =~ /^(.+)(\\|\")\s*$/i){                                   # When it's the follow or End of a message
	    $msghash{$lang}{$set_num}{$msg_num} .= $1;
	}   

	$msghash{$lang}{$set_num}{$msg_num} =~ s/(\\n)/\n/g;                            #some sequences need to be substitute:
	$msghash{$lang}{$set_num}{$msg_num} =~ s/(\\t)/\t/g;                           # \n, \t
	$msghash{$lang}{$set_num}{$msg_num} =~ s/(\\\\)/\\/g;

	
    }# while
    #############
    close(MSGFILE);
    return 1;
}#sub Msg_file_open

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
   
    unless (defined ($msghash{$lang})) {
	do_log('err','unknown Locale %s', $lang);
	return undef;
    }
	
    ## Set Locale::Messages context
    setlocale(LC_MESSAGES, $locale);
    textdomain "sympa";
    bindtextdomain sympa => '--DIR--/locale';
    bind_textdomain_codeset sympa => 'iso-8859-1';

    $current_lang = $lang;
    $current_locale = $locale;
    return 1;
}#SetLang

sub Msg{
#######

    my $set = shift;
    my $msg = shift;
    my $msg_default = shift;
  
    unless (defined($msghash{$current_lang}{$set}{$msg})) {
	return $msg_default;
	do_log('info','%s-Message %d of set %d not found, using user Message : %s ',$current_lang, $msg, $set, $msg_default);
    }

    return $msghash{$current_lang}{$set}{$msg};

}#sub Msg

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

