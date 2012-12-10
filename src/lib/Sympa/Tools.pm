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

Sympa::Tools - Generic functions

=head1 DESCRIPTION

This module provides various generic functions.

=cut

package Sympa::Tools;

use strict;

use Digest::MD5;
use Encode::Guess; ## Useful when encoding should be guessed
use File::Copy::Recursive;
use File::Find;
use HTML::StripScripts::Parser;
use MIME::EncWords;
use MIME::Lite::HTML;
use Sys::Hostname;
use Text::LineFold;

use Sympa::Constants;
use Sympa::Language;
use Sympa::Log;
use Sympa::Tools::File;

## global var to store a CipherSaber object 
my $cipher;

my $separator="------- CUT --- CUT --- CUT --- CUT --- CUT --- CUT --- CUT -------";

## Regexps for list params
## Caution : if this regexp changes (more/less parenthesis), then regexp using it should 
## also be changed
my $time_regexp = '[012]?[0-9](?:\:[0-5][0-9])?';
my $time_range_regexp = $time_regexp.'-'.$time_regexp;
my %regexp = ('email' => '([\w\-\_\.\/\+\=\'\&]+|\".*\")\@[\w\-]+(\.[\w\-]+)+',
	      'family_name' => '[a-z0-9][a-z0-9\-\.\+_]*', 
	      'template_name' => '[a-zA-Z0-9][a-zA-Z0-9\-\.\+_\s]*', ## Allow \s
	      'host' => '[\w\.\-]+',
	      'multiple_host_with_port' => '[\w\.\-]+(:\d+)?(,[\w\.\-]+(:\d+)?)*',
	      'listname' => '[a-z0-9][a-z0-9\-\.\+_]{0,49}',
	      'sql_query' => '(SELECT|select).*',
	      'scenario' => '[\w,\.\-]+',
	      'task' => '\w+',
	      'datasource' => '[\w-]+',
	      'uid' => '[\w\-\.\+]+',
	      'time' => $time_regexp,
	      'time_range' => $time_range_regexp,
	      'time_ranges' => $time_range_regexp.'(?:\s+'.$time_range_regexp.')*',
	      're' => '(?i)(?:AW|(?:\xD0\x9D|\xD0\xBD)(?:\xD0\x90|\xD0\xB0)|Re(?:\^\d+|\*\d+|\*\*\d+|\[\d+\])?|Rif|SV|VS)\s*:',
	      );

## Returns an HTML::StripScripts::Parser object built with  the parameters provided as arguments.
sub _create_xss_parser {
    my %parameters = @_;
    &Sympa::Log::do_log('debug3', '(%s)', $parameters{'robot'});
    my $hss = HTML::StripScripts::Parser->new({ Context => 'Document',
						AllowSrc        => 1,
						Rules => {
						    '*' => {
							src => '^http://'. $parameters{'host'},
						    },
						},
					    });
    return $hss;
}

=head1 FUNCTIONS

=head2 pictures_filename(%parameters)

Return the type of a pictures according to the user.

=head3 Parameters

=over

=item * I<email>

=item * I<list>

=item * I<path>

=back

=cut

sub pictures_filename {
    my %parameters = @_;
    
    my $login = &md5_fingerprint($parameters{'email'});
    my ($listname, $robot) = ($parameters{'list'}{'name'}, $parameters{'list'}{'domain'});
    
    my $filetype;
    my $filename = undef;
    foreach my $ext ('.gif','.jpg','.jpeg','.png') {
 	if (-f $parameters{'path'}.'/'.$listname.'@'.$robot.'/'.$login.$ext) {
 	    my $file = $login.$ext;
 	    $filename = $file;
 	    last;
 	}
    }
    return $filename;
}

=head2 make_pictures_url(%parameters)

Creation of pictures url.

=head3 Parameters

=over

=item * I<url>

=item * I<email>

=item * I<list>

=item * I<path>

=back

=cut

sub make_pictures_url {
    my %parameters = @_;

    my ($listname, $robot) = ($parameters{'list'}{'name'}, $parameters{'list'}{'domain'});

    my $filename = pictures_filename(%parameters);
    return $filename ?
 	$parameters{'url'}.$listname.'@'.$robot.'/'.$filename : undef;
}

=head2 sanitize_html(%parameters)

Returns sanitized version (using StripScripts) of the string provided as
argument.

=head3 Parameters

=over

=item * I<string>

=item * I<robot>

=item * I<host>

=back

=cut

sub sanitize_html {
    my %parameters = @_;
    &Sympa::Log::do_log('debug3','(%s,%s,%s)',$parameters{'string'},$parameters{'robot'},$parameters{'host'});

    unless (defined $parameters{'string'}) {
	&Sympa::Log::do_log('err',"No string provided.");
	return undef;
    }

    my $hss = &_create_xss_parser('robot' => $parameters{'robot'}, 'host' => $parameters{'host'});
    unless (defined $hss) {
	&Sympa::Log::do_log('err',"Can't create StripScript parser.");
	return undef;
    }
    my $string = $hss -> filter_html($parameters{'string'});
    return $string;
}

=head2 sanitize_html_file(%parameters)

Returns sanitized version (using StripScripts) of the content of the file whose
path is provided as argument.

=head3 Parameters

=over

=item * I<file>

=item * I<robot>

=item * I<host>

=back

=cut

sub sanitize_html_file {
    my %parameters = @_;
    &Sympa::Log::do_log('debug3','(%s,%s)',$parameters{'robot'},$parameters{'host'});

    unless (defined $parameters{'file'}) {
	&Sympa::Log::do_log('err',"No path to file provided.");
	return undef;
    }

    my $hss = &_create_xss_parser('robot' => $parameters{'robot'}, 'host' => $parameters{'host'});
    unless (defined $hss) {
	&Sympa::Log::do_log('err',"Can't create StripScript parser.");
	return undef;
    }
    $hss -> parse_file($parameters{'file'});
    return $hss -> filtered_document;
}

=head2 sanitize_var(%parameters)

Sanitize all values in the hash $var, starting from $level

=head3 Parameters

=over

=item * I<var>

=item * I<level>

=item * I<robot>

=item * I<htmlAllowedParam>

=item * I<htmlToFilter>

=back

=cut

sub sanitize_var {
    my %parameters = @_;
    &Sympa::Log::do_log('debug3','(%s,%s,%s)',$parameters{'var'},$parameters{'level'},$parameters{'robot'});
    unless (defined $parameters{'var'}){
	&Sympa::Log::do_log('err','Missing var to sanitize.');
	return undef;
    }
    unless (defined $parameters{'htmlAllowedParam'} && $parameters{'htmlToFilter'}){
	&Sympa::Log::do_log('err','Missing var *** %s *** %s *** to ignore.',$parameters{'htmlAllowedParam'},$parameters{'htmlToFilter'});
	return undef;
    }
    my $level = $parameters{'level'};
    $level |= 0;
    
    if(ref($parameters{'var'})) {
	if(ref($parameters{'var'}) eq 'ARRAY') {
	    foreach my $index (0..$#{$parameters{'var'}}) {
		if ((ref($parameters{'var'}->[$index]) eq 'ARRAY') || (ref($parameters{'var'}->[$index]) eq 'HASH')) {
		    &sanitize_var('var' => $parameters{'var'}->[$index],
				  'level' => $level+1,
				  'robot' => $parameters{'robot'},
				  'htmlAllowedParam' => $parameters{'htmlAllowedParam'},
				  'htmlToFilter' => $parameters{'htmlToFilter'},
				  );
		}
		else {
		    if (defined $parameters{'var'}->[$index]) {
			$parameters{'var'}->[$index] = &escape_html($parameters{'var'}->[$index]);
		    }
		}
	    }
	}
	elsif(ref($parameters{'var'}) eq 'HASH') {
	    foreach my $key (keys %{$parameters{'var'}}) {
		if ((ref($parameters{'var'}->{$key}) eq 'ARRAY') || (ref($parameters{'var'}->{$key}) eq 'HASH')) {
		    &sanitize_var('var' => $parameters{'var'}->{$key},
				  'level' => $level+1,
				  'robot' => $parameters{'robot'},
				  'htmlAllowedParam' => $parameters{'htmlAllowedParam'},
				  'htmlToFilter' => $parameters{'htmlToFilter'},
				  );
		}
		else {
		    if (defined $parameters{'var'}->{$key}) {
			unless ($parameters{'htmlAllowedParam'}{$key}||$parameters{'htmlToFilter'}{$key}) {
			    $parameters{'var'}->{$key} = &escape_html($parameters{'var'}->{$key});
			}
			if ($parameters{'htmlToFilter'}{$key}) {
			    $parameters{'var'}->{$key} = &sanitize_html('string' => $parameters{'var'}->{$key},
									'robot' =>$parameters{'robot'} );
			}
		    }
		}
		
	    }
	}
    }
    else {
	&Sympa::Log::do_log('err','Variable is neither a hash nor an array.');
	return undef;
    }
    return 1;
}

=head2 by_date()

Sort subroutine to order files in sympa spool by date

=cut

sub by_date {
    my @a_tokens = split /\./, $a;
    my @b_tokens = split /\./, $b;

    ## File format : list@dom.date.pid
    my $a_time = $a_tokens[$#a_tokens -1];
    my $b_time = $b_tokens[$#b_tokens -1];

    return $a_time <=> $b_time;

}

=head2 safefork($i, $pid);

Safefork does several tries before it gives up. Do 3 trials and wait 10 seconds
* $i between each. Exit with a fatal error is fork failed after all tests have
been exhausted.

=cut

sub safefork {
   my($i, $pid);
   
   for ($i = 1; $i < 4; $i++) {
      my($pid) = fork;
      return $pid if (defined($pid));
      &Sympa::Log::do_log ('warning', "Can't create new process in safefork: %m");
      ## should send a mail to the listmaster
      sleep(10 * $i);
   }
   &Sympa::Log::fatal_err("Can't create new process in safefork: %m");
   ## No return.
}

=head2 checkcommand($msg, $sender, $robot, $regexp)

Checks for no command in the body of the message. If there are some command in
it, it return true and send a message to $sender.

=head3 Parameters

=over

=item * I<$msg>: message to check (MIME::Entity object)

=item * I<$sender>: the sender

=item * I<$robot>: the robot

=back

=head3 Return value

true if there are some command in $msg, false otherwise.

=cut

sub checkcommand {
   my($msg, $sender, $robot, $regexp) = @_;

   my($avoid, $i);

   my $hdr = $msg->head;

   ## Check for commands in the subject.
   my $subject = $msg->head->get('Subject');

   &Sympa::Log::do_log('debug3', '(msg->head->get(subject): %s,%s)', $subject, $sender);

   if ($subject) {
       if ($regexp && ($subject =~ /^$regexp\b/im)) {
	   return 1;
       }
   }

   return 0 if ($#{$msg->body} >= 5);  ## More than 5 lines in the text.

   foreach $i (@{$msg->body}) {
       if ($regexp && ($i =~ /^$regexp\b/im)) {
	   return 1;
       }

       ## Control is only applied to first non-blank line
       last unless $i =~ /^\s*$/;
   }
   return 0;
}

=head2 load_edit_list_conf($robot, $list, $basedir)

Return a hash from the edit_list_conf file

=head3 Parameters

=over

=item * I<$robot>

=item * I<$list>

=item * I<$basedir>

=back

=cut

sub load_edit_list_conf {
    my $robot = shift;
    my $list = shift;
    my $basedir = shift;
    &Sympa::Log::do_log('debug2', '(%s, %s, %s)', $robot, $list, $basedir);

    my $file;
    my $conf ;
    
    return undef 
	unless ($file = get_filename('etc',{},'edit_list.conf',$robot,$list,$basedir));

    unless (open (FILE, $file)) {
	&Sympa::Log::do_log('info','Unable to open config file %s', $file);
	return undef;
    }

    my $error_in_conf;
    my $roles_regexp = 'listmaster|privileged_owner|owner|editor|subscriber|default';
    while (<FILE>) {
	next if /^\s*(\#.*|\s*)$/;

	if (/^\s*(\S+)\s+(($roles_regexp)\s*(,\s*($roles_regexp))*)\s+(read|write|hidden)\s*$/i) {
	    my ($param, $role, $priv) = ($1, $2, $6);
	    my @roles = split /,/, $role;
	    foreach my $r (@roles) {
		$r =~ s/^\s*(\S+)\s*$/$1/;
		if ($r eq 'default') {
		    $error_in_conf = 1;
		    &Sympa::Log::do_log('notice', '"default" is no more recognised');
		    foreach my $set ('owner','privileged_owner','listmaster') {
			$conf->{$param}{$set} = $priv;
		    }
		    next;
		}
		$conf->{$param}{$r} = $priv;
	    }
	}else{
	    &Sympa::Log::do_log ('info', 'unknown parameter in %s  (Ignored) %s', "$basedir/edit_list.conf",$_ );
	    next;
	}
    }

    if ($error_in_conf) {
        require Sympa::List;
	unless (&Sympa::List::send_notify_to_listmaster('edit_list_error', $robot, [$file])) {
	    &Sympa::Log::do_log('notice',"Unable to send notify 'edit_list_error' to listmaster");
	}
    }
    
    close FILE;
    return $conf;
}

=head2 load_create_list_conf($robot, $basedir)

Return a hash from the create_list_conf file

=head3 Parameters

=over

=item * I<$robot>

=item * I<$basedir>

=back

=cut

sub load_create_list_conf {
    my $robot = shift;
    my $basedir = shift;

    my $file;
    my $conf ;
    
    $file = get_filename('etc',{}, 'create_list.conf', $robot,undef,$basedir);
    unless ($file) {
	&Sympa::Log::do_log('info', 'unable to read %s', Sympa::Constants::DEFAULTDIR . '/create_list.conf');
	return undef;
    }

    unless (open (FILE, $file)) {
	&Sympa::Log::do_log('info','Unable to open config file %s', $file);
	return undef;
    }

    while (<FILE>) {
	next if /^\s*(\#.*|\s*)$/;

	if (/^\s*(\S+)\s+(read|hidden)\s*$/i) {
	    $conf->{$1} = lc($2);
	}else{
	    &Sympa::Log::do_log ('info', 'unknown parameter in %s  (Ignored) %s', $file,$_ );
	    next;
	}
    }
    
    close FILE;
    return $conf;
}

sub _add_topic {
    my ($name, $title) = @_;
    my $topic = {};

    my @tree = split '/', $name;
    if ($#tree == 0) {
	return {'title' => $title};
    }else {
	$topic->{'sub'}{$name} = &_add_topic(join ('/', @tree[1..$#tree]), $title);
	return $topic;
    }
}

sub get_list_list_tpl {
    my $robot = shift;
    my $directory = shift;

    my $list_conf;
    my $list_templates ;
    unless ($list_conf = &load_create_list_conf($robot)) {
	return undef;
    }
    
    foreach my $dir (
        Sympa::Constants::DEFAULTDIR . '/create_list_templates',
        "$directory/create_list_templates",
        "$directory/$robot/create_list_templates"
    ) {
	if (opendir(DIR, $dir)) {
	    foreach my $template ( sort grep (!/^\./,readdir(DIR))) {

		my $status = $list_conf->{$template} || $list_conf->{'default'};

		next if ($status eq 'hidden') ;

		$list_templates->{$template}{'path'} = $dir;

		my $locale = &Sympa::Language::Lang2Locale( &Sympa::Language::GetLang());
		## Look for a comment.tt2 in the appropriate locale first
		if (-r $dir.'/'.$template.'/'.$locale.'/comment.tt2') {
		    $list_templates->{$template}{'comment'} = $dir.'/'.$template.'/'.$locale.'/comment.tt2';
		}elsif (-r $dir.'/'.$template.'/comment.tt2') {
		    $list_templates->{$template}{'comment'} = $dir.'/'.$template.'/comment.tt2';
		}
	    }
	    closedir(DIR);
	}
    }

    return ($list_templates);
}

sub get_templates_list {

    my $type = shift;
    my $robot = shift;
    my $list = shift;
    my $options = shift;
    my $basedir = shift;

    my $listdir;

    &Sympa::Log::do_log('debug', "get_templates_list ($type, $robot, $list)");
    unless (($type eq 'web')||($type eq 'mail')) {
	&Sympa::Log::do_log('info', 'get_templates_list () : internal error incorrect parameter');
    }

    my $distrib_dir = Sympa::Constants::DEFAULTDIR . '/'.$type.'_tt2';
    my $site_dir = $basedir.'/'.$type.'_tt2';
    my $robot_dir = $basedir.'/'.$robot.'/'.$type.'_tt2';

    my @try;

    ## The 'ignore_global' option allows to look for files at list level only
    unless ($options->{'ignore_global'}) {
	push @try, $distrib_dir ;
	push @try, $site_dir ;
	push @try, $robot_dir;
    }    

    if (defined $list) {
	$listdir = $list->{'dir'}.'/'.$type.'_tt2';	
	push @try, $listdir ;
    }

    my $i = 0 ;
    my $tpl;

    foreach my $dir (@try) {
	next unless opendir (DIR, $dir);
	foreach my $file ( grep (!/^\./,readdir(DIR))) {	    
	    ## Subdirectory for a lang
	    if (-d $dir.'/'.$file) {
		my $lang = $file;
		next unless opendir (LANGDIR, $dir.'/'.$lang);
		foreach my $file (grep (!/^\./,readdir(LANGDIR))) {
		    next unless ($file =~ /\.tt2$/);
		    if ($dir eq $distrib_dir){$tpl->{$file}{'distrib'}{$lang} = $dir.'/'.$lang.'/'.$file;}
		    if ($dir eq $site_dir)   {$tpl->{$file}{'site'}{$lang} =  $dir.'/'.$lang.'/'.$file;}
		    if ($dir eq $robot_dir)  {$tpl->{$file}{'robot'}{$lang} = $dir.'/'.$lang.'/'.$file;}
		    if ($dir eq $listdir)    {$tpl->{$file}{'list'}{$lang} = $dir.'/'.$lang.'/'.$file;}
		}
		closedir LANGDIR;

	    }else {
		next unless ($file =~ /\.tt2$/);
		if ($dir eq $distrib_dir){$tpl->{$file}{'distrib'}{'default'} = $dir.'/'.$file;}
		if ($dir eq $site_dir)   {$tpl->{$file}{'site'}{'default'} =  $dir.'/'.$file;}
		if ($dir eq $robot_dir)  {$tpl->{$file}{'robot'}{'default'} = $dir.'/'.$file;}
		if ($dir eq $listdir)    {$tpl->{$file}{'list'}{'default'}= $dir.'/'.$file;}
	    }
	}
	closedir DIR;
    }
    return ($tpl);

}

=head2 get_template_path($type, $robot, $scope, $tpl, $lang, $list, $basedir)

Return the path for a specific template

=head3 Parameters

=over

=item * I<$type>

=item * I<$robot>

=item * I<$scope>

=item * I<$tpl>

=item * I<$lang>

=item * I<$list>

=item * I<$basedir>

=back

=cut

sub get_template_path {

    my $type = shift;
    my $robot = shift;
    my $scope = shift;
    my $tpl = shift;
    my $lang = shift || 'default';
    my $list = shift;
    my $basedir = shift;

    &Sympa::Log::do_log('debug', "get_templates_path ($type,$robot,$scope,$tpl,$lang,%s)", $list->{'name'});

    my $listdir;
    if (defined $list) {
	$listdir = $list->{'dir'};
    }

    unless (($type == 'web')||($type == 'mail')) {
	&Sympa::Log::do_log('info', 'get_templates_path () : internal error incorrect parameter');
    }

    my $distrib_dir = Sympa::Constants::DEFAULTDIR . '/'.$type.'_tt2';
    my $site_dir = $basedir.'/'.$type.'_tt2';
    $site_dir .= '/'.$lang unless ($lang eq 'default');
    my $robot_dir = $basedir.'/'.$robot.'/'.$type.'_tt2';
    $robot_dir .= '/'.$lang unless ($lang eq 'default');    

    if ($scope eq 'list')  {
	my $dir = $listdir.'/'.$type.'_tt2';
	$dir .= '/'.$lang unless ($lang eq 'default');
	return $dir.'/'.$tpl ;

    }elsif ($scope eq 'robot')  {
	return $robot_dir.'/'.$tpl;

    }elsif ($scope eq 'site') {
	return $site_dir.'/'.$tpl;

    }elsif ($scope eq 'distrib') {
	return $distrib_dir.'/'.$tpl;

    }

    return undef;
}

=head2 as_singlepart($msg, $preferred_type, $loops)

Make a multipart/alternative, a singlepart

=head3 Parameters

=over

=item * I<$msg>

=item * I<$preferred_type>

=item * I<$loops>

=back

=cut

sub as_singlepart {
    &Sympa::Log::do_log('debug2', '()');
    my ($msg, $preferred_type, $loops) = @_;
    my $done = 0;
    $loops++;
    
    unless (defined $msg) {
	&Sympa::Log::do_log('err', "Undefined message parameter");
	return undef;
    }

    if ($loops > 4) {
	&Sympa::Log::do_log('err', 'Could not change multipart to singlepart');
	return undef;
    }

    if ($msg->effective_type() =~ /^$preferred_type$/) {
	$done = 1;
    }elsif ($msg->effective_type() =~ /^multipart\/alternative/) {
	foreach my $part ($msg->parts) {
	    if (($part->effective_type() =~ /^$preferred_type$/) ||
		(
		 ($part->effective_type() =~ /^multipart\/related$/) &&
		 $part->parts &&
		 ($part->parts(0)->effective_type() =~ /^$preferred_type$/))) {
		## Only keep the first matching part
		$msg->parts([$part]);
		$msg->make_singlepart();
		$done = 1;
		last;
	    }
	}
    }elsif ($msg->effective_type() =~ /multipart\/signed/) {
	my @parts = $msg->parts();
	## Only keep the first part
	$msg->parts([$parts[0]]);
	$msg->make_singlepart();       

	$done ||= &as_singlepart($msg, $preferred_type, $loops);

    }elsif ($msg->effective_type() =~ /^multipart/) {
	foreach my $part ($msg->parts) {
            
            next unless (defined $part); ## Skip empty parts
 
	    if ($part->effective_type() =~ /^multipart\/alternative/) {
		if (&as_singlepart($part, $preferred_type, $loops)) {
		    $msg->parts([$part]);
		    $msg->make_singlepart();
		    $done = 1;
		}
	    }
	}    
    }

    return $done;
}

=head2 escape_regexp($string)

Escape characters before using a string within a regexp parameter
Escaped characters are : @ $ [ ] ( ) ' ! '\' * . + ?

=cut

sub escape_regexp {
    my $s = shift;
    my @escaped = ("\\",'@','$','[',']','(',')',"'",'!','*','.','+','?');
    my $backslash = "\\"; ## required in regexp

    foreach my $escaped_char (@escaped) {
	$s =~ s/$backslash$escaped_char/\\$escaped_char/g;
    }

    return $s;
}

=head2 escape_chars()

Escape weird characters.

=cut

sub escape_chars {
    my $s = shift;    
    my $except = shift; ## Exceptions
    my $ord_except = ord($except) if (defined $except);

    ## Escape chars
    ##  !"#$%&'()+,:;<=>?[] AND accented chars
    ## escape % first
    foreach my $i (0x25,0x20..0x24,0x26..0x2c,0x3a..0x3f,0x5b,0x5d,0x80..0x9f,0xa0..0xff) {
	next if ($i == $ord_except);
	my $hex_i = sprintf "%lx", $i;
	$s =~ s/\x$hex_i/%$hex_i/g;
    }
    $s =~ s/\//%a5/g unless ($except eq '/');  ## Special traetment for '/'

    return $s;
}

=head2 escape_docname($filename, $except)

Escape shared document file name
Q-decode it first

=cut

sub escape_docname {
    my $filename = shift;
    my $except = shift; ## Exceptions

    ## Q-decode
    $filename = MIME::EncWords::decode_mimewords($filename);

    ## Decode from FS encoding to utf-8
    #$filename = &Encode::decode($Sympa::Configuration::Conf{'filesystem_encoding'}, $filename);

    ## escapesome chars for use in URL
    return &escape_chars($filename, $except);
}

=head2 unicode_to_utf8($string)

Convert from Perl unicode encoding to UTF8

=cut

sub unicode_to_utf8 {
    my $s = shift;
    
    if (&Encode::is_utf8($s)) {
	return &Encode::encode_utf8($s);
    }

    return $s;
}

=head2 qencode_filename($filename)

Q-Encode web file name

=cut

sub qencode_filename {
    my $filename = shift;

    ## We don't use MIME::Words here because it does not encode properly Unicode
    ## Check if string is already Q-encoded first
    ## Also check if the string contains 8bit chars
    unless ($filename =~ /\=\?UTF-8\?/ ||
	    $filename =~ /^[\x00-\x7f]*$/) {

	## Don't encode elements such as .desc. or .url or .moderate or .extension
	my $part = $filename;
	my ($leading, $trailing);
	$leading = $1 if ($part =~ s/^(\.desc\.)//); ## leading .desc
	$trailing = $1 if ($part =~ s/((\.\w+)+)$//); ## trailing .xx

	my $encoded_part = MIME::EncWords::encode_mimewords($part, Charset => 'utf8', Encoding => 'q', MaxLineLen => 1000, Minimal => 'NO');
	

	$filename = $leading.$encoded_part.$trailing;
    }
    
    return $filename;
}

=head2 qdecode_filename($filename)

Q-Decode web file name

=cut

sub qdecode_filename {
    my $filename = shift;
    
    ## We don't use MIME::Words here because it does not encode properly Unicode
    ## Check if string is already Q-encoded first
    #if ($filename =~ /\=\?UTF-8\?/) {
    $filename = Encode::encode_utf8(&Encode::decode('MIME-Q', $filename));
    #}
    
    return $filename;
}

=head2 unescape_chars($string, $except)

Unescape weird characters

=cut

sub unescape_chars {
    my $s = shift;

    $s =~ s/%a5/\//g;  ## Special traetment for '/'
    foreach my $i (0x20..0x2c,0x3a..0x3f,0x5b,0x5d,0x80..0x9f,0xa0..0xff) {
	my $hex_i = sprintf "%lx", $i;
	my $hex_s = sprintf "%c", $i;
	$s =~ s/%$hex_i/$hex_s/g;
    }

    return $s;
}

sub escape_html {
    my $s = shift;

    $s =~ s/\"/\&quot\;/gm;
    $s =~ s/\</&lt\;/gm;
    $s =~ s/\>/&gt\;/gm;
    
    return $s;
}

sub unescape_html {
    my $s = shift;

    $s =~ s/\&quot\;/\"/g;
    $s =~ s/&lt\;/\</g;
    $s =~ s/&gt\;/\>/g;
    
    return $s;
}

sub tmp_passwd {
    my $email = shift;
    my $cookie = shift;

    return ('init'.substr(Digest::MD5::md5_hex(join('/', $cookie, $email)), -8)) ;
}

=head2 sympa_checksum($rcpt, $cookie)

Check sum used to authenticate communication from wwsympa to sympa

=cut

sub sympa_checksum {
    my $rcpt = shift;
    my $cookie = shift;
    return (substr(Digest::MD5::md5_hex(join('/', $cookie, $rcpt)), -10)) ;
}

=head2 ciphersaber_installed($cookie)

Create a cipher.

=cut

sub ciphersaber_installed {
    my $cookie = shift;

    my $is_installed;
    foreach my $dir (@INC) {
	if (-f "$dir/Crypt/CipherSaber.pm") {
	    $is_installed = 1;
	    last;
	}
    }

    if ($is_installed) {
	require Crypt::CipherSaber;
	$cipher = Crypt::CipherSaber->new($cookie);
    }else{
	$cipher = 'no_cipher';
    }
}

=head2 cookie_changed($current, $basedir)

Create a cipher.

=cut

sub cookie_changed {
    my $current=shift;
    my $basedir = shift;

    my $changed = 1 ;
    if (-f "$basedir/cookies.history") {
	unless (open COOK, "$basedir/cookies.history") {
	    &Sympa::Log::do_log('err', "Unable to read $basedir/cookies.history") ;
	    return undef ; 
	}
	my $oldcook = <COOK>;
	close COOK;

	my @cookies = split(/\s+/,$oldcook );
	

	if ($cookies[$#cookies] eq $current) {
	    &Sympa::Log::do_log('debug2', "cookie is stable") ;
	    $changed = 0;
#	}else{
#	    push @cookies, $current ;
#	    unless (open COOK, ">$basedir/cookies.history") {
#		&Sympa::Log::do_log('err', "Unable to create $basedir/cookies.history") ;
#		return undef ; 
#	    }
#	    printf COOK "%s",join(" ",@cookies) ;
#	    
#	    close COOK;
	}
	return $changed ;
    }else{
	my $umask = umask 037;
	unless (open COOK, ">$basedir/cookies.history") {
	    umask $umask;
	    &Sympa::Log::do_log('err', "Unable to create $basedir/cookies.history") ;
	    return undef ; 
	}
	umask $umask;
	chown [getpwnam(Sympa::Constants::USER)]->[2], [getgrnam(Sympa::Constants::GROUP)]->[2], "$basedir/cookies.history";
	print COOK "$current ";
	close COOK;
	return(0);
    }
}

=head2 crypt_password($inpasswd, $cookie)

Encrypt a password.

=cut

sub crypt_password {
    my $inpasswd = shift ;
    my $cookie = shift;

    unless (defined($cipher)){
	$cipher = ciphersaber_installed($cookie);
    }
    return $inpasswd if ($cipher eq 'no_cipher') ;
    return ("crypt.".&MIME::Base64::encode($cipher->encrypt ($inpasswd))) ;
}

=head2 decrypt_password($inpasswd, $cookie)

Decrypt a password.

=cut

sub decrypt_password {
    my $inpasswd = shift ;
    my $cookie = shift;
    Sympa::Log::do_log('debug2', '(%s,%s)', $inpasswd, $cookie);

    return $inpasswd unless ($inpasswd =~ /^crypt\.(.*)$/) ;
    $inpasswd = $1;

    unless (defined($cipher)){
	$cipher = ciphersaber_installed($cookie);
    }
    if ($cipher eq 'no_cipher') {
	&Sympa::Log::do_log('info','password seems crypted while CipherSaber is not installed !');
	return $inpasswd ;
    }
    return ($cipher->decrypt(&MIME::Base64::decode($inpasswd)));
}

sub load_mime_types {
    my $types = {};

    my @localisation = ('/etc/mime.types',
			'/usr/local/apache/conf/mime.types',
			'/etc/httpd/conf/mime.types','mime.types');

    foreach my $loc (@localisation) {
        next unless (-r $loc);

        unless(open (CONF, $loc)) {
            print STDERR "load_mime_types: unable to open $loc\n";
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

sub split_mail {
    my $message = shift ; 
    my $pathname = shift ;
    my $dir = shift ;

    my $head = $message->head ;
    my $body = $message->body ;
    my $encoding = $head->mime_encoding ;

    if ($message->is_multipart
	|| ($message->mime_type eq 'message/rfc822')) {

        for (my $i=0 ; $i < $message->parts ; $i++) {
            &split_mail ($message->parts ($i), $pathname.'.'.$i, $dir) ;
        }
    }
    else { 
	    my $fileExt ;

	    if ($head->mime_attr("content_type.name") =~ /\.(\w+)\s*\"*$/) {
		$fileExt = $1 ;
	    }
	    elsif ($head->recommended_filename =~ /\.(\w+)\s*\"*$/) {
		$fileExt = $1 ;
	    }
	    else {
		my $mime_types = &load_mime_types();

		$fileExt=$mime_types->{$head->mime_type};
		my $var=$head->mime_type;
	    }
	
	    

	    ## Store body in file 
	    unless (open OFILE, ">$dir/$pathname.$fileExt") {
		&Sympa::Log::do_log('err', "Unable to create $dir/$pathname.$fileExt : $!") ;
		return undef ; 
	    }
	    
	    if ($encoding =~ /^(binary|7bit|8bit|base64|quoted-printable|x-uu|x-uuencode|x-gzip64)$/ ) {
		open TMP, ">$dir/$pathname.$fileExt.$encoding";
		$message->print_body (\*TMP);
		close TMP;

		open BODY, "$dir/$pathname.$fileExt.$encoding";

		my $decoder = new MIME::Decoder $encoding;
		unless (defined $decoder) {
		    &Sympa::Log::do_log('err', 'Cannot create decoder for %s', $encoding);
		    return undef;
		}
		$decoder->decode(\*BODY, \*OFILE);
		close BODY;
		unlink "$dir/$pathname.$fileExt.$encoding";
	    }else {
		$message->print_body (\*OFILE) ;
	    }
	    close (OFILE);
	    printf "\t-------\t Create file %s\n", $pathname.'.'.$fileExt ;
	    
	    ## Delete files created twice or more (with Content-Type.name and Content-Disposition.filename)
	    $message->purge ;	
    }
    
    return 1;
}

sub virus_infected {
    my $mail = shift ;
    my $path = shift;
    my $args = shift;
    my $tmpdir = shift;
    my $domain = shift;

    my $file = int(rand(time)) ; # in, version previous from db spools, $file was the filename of the message 
    &Sympa::Log::do_log('debug2', 'Scan virus in %s', $file);
    
    unless ($path) {
        &Sympa::Log::do_log('debug', 'Sympa not configured to scan virus in message');
	return 0;
    }
    my @name = split(/\//,$file);
    my $work_dir = $tmpdir.'/antivirus';
    
    unless ((-d $work_dir) ||( mkdir $work_dir, 0755)) {
	&Sympa::Log::do_log('err', "Unable to create tmp antivirus directory $work_dir");
	return undef;
    }

    $work_dir = $tmpdir.'/antivirus/'.$name[$#name];
    
    unless ( (-d $work_dir) || mkdir ($work_dir, 0755)) {
	&Sympa::Log::do_log('err', "Unable to create tmp antivirus directory $work_dir");
	return undef;
    }

    #$mail->dump_skeleton;

    ## Call the procedure of spliting mail
    unless (&split_mail ($mail,'msg', $work_dir)) {
	&Sympa::Log::do_log('err', 'Could not split mail %s', $mail);
	return undef;
    }

    my $virusfound = 0; 
    my $error_msg;
    my $result;

    ## McAfee
    if ($path =~  /\/uvscan$/) {

	# impossible to look for viruses with no option set
	unless ($args) {
	    &Sympa::Log::do_log('err', "Missing 'antivirus_args' in sympa.conf");
	    return undef;
	}
    
	open (ANTIVIR,"$path $args $work_dir |") ; 
		
	while (<ANTIVIR>) {
	    $result .= $_; chomp $result;
	    if ((/^\s*Found the\s+(.*)\s*virus.*$/i) ||
		(/^\s*Found application\s+(.*)\.\s*$/i)){
		$virusfound = $1;
	    }
	}
	close ANTIVIR;
    
	my $status = $? / 256 ; # /

        ## uvscan status =12 or 13 (*256) => virus
        if (( $status == 13) || ($status == 12)) { 
	    $virusfound ||= "unknown";
	}

	## Meaning of the codes
	##  12 : The program tried to clean a file, and that clean failed for some reason and the file is still infected.
	##  13 : One or more viruses or hostile objects (such as a Trojan horse, joke program,  or  a  test file) were found.
	##  15 : The programs self-check failed; the program might be infected or damaged.
	##  19 : The program succeeded in cleaning all infected files.

	$error_msg = $result
	    if ($status != 0 && $status != 12 && $status != 13 && $status != 19);

    ## Trend Micro
    }elsif ($path =~  /\/vscan$/) {

	open (ANTIVIR,"$path $args $work_dir |") ; 
		
	while (<ANTIVIR>) {
	    if (/Found virus (\S+) /i){
		$virusfound = $1;
	    }
	}
	close ANTIVIR;
    
	my $status = $?/256 ;

        ## uvscan status = 1 | 2 (*256) => virus
        if ((( $status == 1) or ( $status == 2)) and not($virusfound)) { 
	    $virusfound = "unknown";
	}

    ## F-Secure
    } elsif($path =~  /\/fsav$/) {
	my $dbdir=$` ;

	# impossible to look for viruses with no option set
	unless ($args) {
	    &Sympa::Log::do_log('err', "Missing 'antivirus_args' in sympa.conf");
	    return undef;
	}

	open (ANTIVIR,"$path --databasedirectory $dbdir $args $work_dir |") ;

	while (<ANTIVIR>) {

	    if (/infection:\s+(.*)/){
		$virusfound = $1;
	    }
	}
	
	close ANTIVIR;
    
	my $status = $?/256 ;

        ## fsecure status =3 (*256) => virus
        if (( $status == 3) and not($virusfound)) { 
	    $virusfound = "unknown";
	}    
    }elsif($path =~ /f-prot\.sh$/) {

        &Sympa::Log::do_log('debug2', 'f-prot is running');    

        open (ANTIVIR,"$path $args $work_dir |") ;
        
        while (<ANTIVIR>) {
        
            if (/Infection:\s+(.*)/){
                $virusfound = $1;
            }
        }
        
        close ANTIVIR;
        
        my $status = $?/256 ;
        
        &Sympa::Log::do_log('debug2', 'Status: '.$status);    
        
        ## f-prot status =3 (*256) => virus
        if (( $status == 3) and not($virusfound)) { 
            $virusfound = "unknown";
        }    
    }elsif ($path =~ /kavscanner/) {

	# impossible to look for viruses with no option set
	unless ($args) {
	    &Sympa::Log::do_log('err', "Missing 'antivirus_args' in sympa.conf");
	    return undef;
	}
    
	open (ANTIVIR,"$path $args $work_dir |") ; 
		
	while (<ANTIVIR>) {
	    if (/infected:\s+(.*)/){
		$virusfound = $1;
	    }
	    elsif (/suspicion:\s+(.*)/i){
		$virusfound = $1;
	    }
	}
	close ANTIVIR;
    
	my $status = $?/256 ;

        ## uvscan status =3 (*256) => virus
        if (( $status >= 3) and not($virusfound)) { 
	    $virusfound = "unknown";
	}

        ## Sophos Antivirus... by liuk@publinet.it
    }elsif ($path =~ /\/sweep$/) {
	
        # impossible to look for viruses with no option set
	unless ($args) {
	    &Sympa::Log::do_log('err', "Missing 'antivirus_args' in sympa.conf");
	    return undef;
	}
    
        open (ANTIVIR,"$path $args $work_dir |") ;
	
	while (<ANTIVIR>) {
	    if (/Virus\s+(.*)/) {
		$virusfound = $1;
	    }
	}       
	close ANTIVIR;
        
	my $status = $?/256 ;
        
	## sweep status =3 (*256) => virus
	if (( $status == 3) and not($virusfound)) {
	    $virusfound = "unknown";
	}

	## Clam antivirus
    }elsif ($path =~ /\/clamd?scan$/) {
	
        open (ANTIVIR,"$path $args $work_dir |") ;
	
	my $result;
	while (<ANTIVIR>) {
	    $result .= $_; chomp $result;
	    if (/^\S+:\s(.*)\sFOUND$/) {
		$virusfound = $1;
	    }
	}       
	close ANTIVIR;
        
	my $status = $?/256 ;
        
	## Clamscan status =1 (*256) => virus
	if (( $status == 1) and not($virusfound)) {
	    $virusfound = "unknown";
	}

	$error_msg = $result
	    if ($status != 0 && $status != 1);

    }         

    ## Error while running antivir, notify listmaster
    if ($error_msg) {
        require Sympa::List;
	unless (&Sympa::List::send_notify_to_listmaster('virus_scan_failed', $domain,
						 {'filename' => $file,
						  'error_msg' => $error_msg})) {
	    &Sympa::Log::do_log('notice',"Unable to send notify 'virus_scan_failed' to listmaster");
	}

    }

    ## if debug mode is active, the working directory is kept
    unless ($main::options{'debug'}) {
	opendir (DIR, ${work_dir});
	my @list = readdir(DIR);
	closedir (DIR);
        foreach (@list) {
	    my $nbre = unlink ("$work_dir/$_")  ;
	}
	rmdir ($work_dir) ;
    }
   
    return $virusfound;
   
}

=head2 get_filename($type, $options, $name, $robot, $object, $basedir)

Look for a file in the list > robot > server > default locations
Possible values for $options : order=all

=head3 Parameters

=over

=item * I<$type>

=item * I<$options>

=item * I<$name>

=item * I<$robot>

=item * I<$object>

=item * I<$basedir>

=back

=cut

sub get_filename {
    my ($type, $options, $name, $robot, $object,$basedir) = @_;
    my $list;
    my $family;
    &Sympa::Log::do_log('debug3','(%s,%s,%s,%s,%s,%s)', $type, join('/',keys %$options), $name, $robot, $object->{'name'},$basedir);

    
    if (ref($object) eq 'Sympa::List') {
 	$list = $object;
 	if ($list->{'admin'}{'family_name'}) {
 	    unless ($family = $list->get_family()) {
 		&Sympa::Log::do_log('err', 'Impossible to get list %s family : %s. The list is set in status error_config',$list->{'name'},$list->{'admin'}{'family_name'});
 		$list->set_status_error_config('no_list_family',$list->{'name'}, $list->{'admin'}{'family_name'});
 		return undef;
 	    }  
 	}
    }elsif (ref($object) eq 'Sympa::Family') {
 	$family = $object;
    }
    
    if ($type eq 'etc') {
	my (@try, $default_name);
	
	## template refers to a language
	## => extend search to default tpls
	if ($name =~ /^(\S+)\.([^\s\/]+)\.tt2$/) {
	    $default_name = $1.'.tt2';
	    
	    @try = (
            $basedir . "/$robot/$name",
		    $basedir . "/$robot/$default_name",
		    $basedir . "/$name",
		    $basedir . "/$default_name",
		    Sympa::Constants::DEFAULTDIR . "/$name",
		    Sympa::Constants::DEFAULTDIR . "/$default_name");
	}else {
	    @try = (
            $basedir . "/$robot/$name",
		    $basedir . "/$name",
		    Sympa::Constants::DEFAULTDIR . "/$name"
        );
	}
	
	if ($family) {
 	    ## Default tpl
 	    if ($default_name) {
		unshift @try, $family->{'dir'}.'/'.$default_name;
	    }
	}
	
	unshift @try, $family->{'dir'}.'/'.$name;
    
	if ($list->{'name'}) {
	    ## Default tpl
	    if ($default_name) {
		unshift @try, $list->{'dir'}.'/'.$default_name;
	    }
	    
	    unshift @try, $list->{'dir'}.'/'.$name;
	}
	my @result;
	foreach my $f (@try) {
	    &Sympa::Log::do_log('debug3','get_filename : name: %s ; dir %s', $name, $f  );
	    if (-r $f) {
		if ($options->{'order'} eq 'all') {
		    push @result, $f;
		}else {
		    return $f;
		}
	    }
	}
	if ($options->{'order'} eq 'all') {
	    return @result ;
	}
    }
    
    #&Sympa::Log::do_log('notice','Cannot find %s in %s', $name, join(',',@try));
    return undef;
}

=head2 make_tt2_include_path($robot, $dir, $lang, $list, $basedir, $viewmaildir, $domain)

Make an array of include path for tt2 parsing.

=head3 Parameters

=over

=item * I<$robot>: robot

=item * I<$dir>: directory ending each path

=item * I<$lang>: lang

=item * I<$list>: list

=item * I<$basedir> 

=item * I<$viewmaildir> 

=item * I<$domain>

=back

=head3 Return value

An arrayref of tt2 include path

=cut

sub make_tt2_include_path {
    my ($robot,$dir,$lang,$list,$basedir,$viewmaildir,$domain) = @_;

    my $listname;
    if (ref $list eq 'Sympa::List') {
	$listname = $list->{'name'};
    } else {
	$listname = $list;
    }
    &Sympa::Log::do_log('debug3', '(%s,%s,%s,%s,%s,%s,%s)', $robot, $dir, $lang, $listname, $basedir,$viewmaildir,$domain);

    my @include_path;

    my $path_etcbindir;
    my $path_etcdir;
    my $path_robot;  ## optional
    my $path_list;   ## optional
    my $path_family; ## optional

    if ($dir) {
	$path_etcbindir = Sympa::Constants::DEFAULTDIR . "/$dir";
	$path_etcdir = "$basedir/".$dir;
	$path_robot = "$basedir/".$robot.'/'.$dir if (lc($robot) ne lc($domain));
	if (ref($list) eq 'Sympa::List'){
	    $path_list = $list->{'dir'}.'/'.$dir;
	    if (defined $list->{'admin'}{'family_name'}) {
		my $family = $list->get_family();
	        $path_family = $family->{'dir'}.'/'.$dir;
	    }
	} 
    }else {
	$path_etcbindir = Sympa::Constants::DEFAULTDIR;
	$path_etcdir = $basedir;
	$path_robot = "$basedir/".$robot if (lc($robot) ne lc($domain));
	if (ref($list) eq 'Sympa::List') {
	    $path_list = $list->{'dir'} ;
	    if (defined $list->{'admin'}{'family_name'}) {
		my $family = $list->get_family();
	        $path_family = $family->{'dir'};
	    }
	}
    }
    if ($lang) {
	@include_path = ($path_etcdir.'/'.$lang,
			 $path_etcdir,
			 $path_etcbindir.'/'.$lang,
			 $path_etcbindir);
	if ($path_robot) {
	    unshift @include_path,$path_robot;
	    unshift @include_path,$path_robot.'/'.$lang;
	}
	if ($path_list) {
	    unshift @include_path,$path_list;
	    unshift @include_path,$path_list.'/'.$lang;

	    if ($path_family) {
		unshift @include_path,$path_family;
		unshift @include_path,$path_family.'/'.$lang;
	    }	
	    
	}
    }else {
	@include_path = ($path_etcdir,
			 $path_etcbindir);

	if ($path_robot) {
	    unshift @include_path,$path_robot;
	}
	if ($path_list) {
	    unshift @include_path,$path_list;
	   
	    if ($path_family) {
		unshift @include_path,$path_family;
	    }
	}
    }

    unshift @include_path,$viewmaildir;
    return \@include_path;

}

=head2 qencode_hierarchy($dir)

Q-encode a complete file hierarchy. Useful to Q-encode subshared documents

=cut

sub qencode_hierarchy {
    my $dir = shift; ## Root directory
    my $original_encoding = shift; ## Suspected original encoding of filenames

    my $count;
    my @all_files;
    &Sympa::Tools::File::list_dir($dir, \@all_files, $original_encoding);

    foreach my $f_struct (reverse @all_files) {
    
	next unless ($f_struct->{'filename'} =~ /[^\x00-\x7f]/); ## At least one 8bit char

	my $new_filename = $f_struct->{'filename'};
	my $encoding = $f_struct->{'encoding'};
	Encode::from_to($new_filename, $encoding, 'utf8') if $encoding;
    
	## Q-encode filename to escape chars with accents
	$new_filename = qencode_filename($new_filename);
    
	my $orig_f = $f_struct->{'directory'}.'/'.$f_struct->{'filename'};
	my $new_f = $f_struct->{'directory'}.'/'.$new_filename;

	## Rename the file using utf8
	&Sympa::Log::do_log('notice', "Renaming %s to %s", $orig_f, $new_f);
	unless (rename $orig_f, $new_f) {
	    &Sympa::Log::do_log('err', "Failed to rename %s to %s : %s", $orig_f, $new_f, $!);
	    next;
	}
	$count++;
    }

    return $count;
}

sub get_message_id {
    my $robot = shift;

    my $id = sprintf '<sympa.%d.%d.%d@%s>', time, $$, int(rand(999)), $robot;

    return $id;
}

=head2 valid_email($email)

Basic check of an email address

=cut

sub valid_email {
    my $email = shift;
    
    unless ($email =~ /^$regexp{'email'}$/) {
	&Sympa::Log::do_log('err', "Invalid email address '%s'", $email);
	return undef;
    }
    
    ## Forbidden characters
    if ($email =~ /[\|\$\*\?\!]/) {
	&Sympa::Log::do_log('err', "Invalid email address '%s'", $email);
	return undef;
    }

    return 1;
}

=head2 clean_email($email)

Clean email address

=cut

sub clean_email {
    my $email = shift;

    ## Lower-case
    $email = lc($email);

    ## remove leading and trailing spaces
    $email =~ s/^\s*//;
    $email =~ s/\s*$//;

    return $email;
}

=head2 get_canonical_email($email)

Return canonical email address (lower-cased + space cleanup)
It could also support alternate email

=cut

sub get_canonical_email {
    my $email = shift;

    ## Remove leading and trailing white spaces
    $email =~ s/^\s*(\S.*\S)\s*$/$1/;

    ## Lower-case
    $email = lc($email);

    return $email;
}

=head2 clean_msg_id($msg_id)

clean msg_id to use it without  \n, \s or <,>

=head3 Parameters

=over

=item * I<$msg_id>: the message id.

=back

=head3 Return value

The clean message id.

=cut

sub clean_msg_id {
    my $msg_id = shift;
    
    chomp $msg_id;

    if ($msg_id =~ /\<(.+)\>/) {
	$msg_id = $1;
    }

    return $msg_id;
}

=head2 change_x_sympa_to($file, $value)

Change X-Sympa-To: header field in the message

=cut

sub change_x_sympa_to {
    my ($file, $value) = @_;
    
    ## Change X-Sympa-To
    unless (open FILE, $file) {
	&Sympa::Log::do_log('err', "Unable to open '%s' : %s", $file, $!);
	next;
    }	 
    my @content = <FILE>;
    close FILE;
    
    unless (open FILE, ">$file") {
	&Sympa::Log::do_log('err', "Unable to open '%s' : %s", "$file", $!);
	next;
    }	 
    foreach (@content) {
	if (/^X-Sympa-To:/i) {
	    $_ = "X-Sympa-To: $value\n";
	}
	print FILE;
    }
    close FILE;
    
    return 1;
}

sub add_in_blacklist {
    my $entry = shift;
    my $robot = shift;
    my $list =shift;

    &Sympa::Log::do_log('info',"(%s,%s,%s)",$entry,$robot,$list->{'name'});
    $entry = lc($entry);
    chomp $entry;

    # robot blacklist not yet availible 
    unless ($list) {
	 &Sympa::Log::do_log('info',"robot blacklist not yet availible, missing list parameter");
	 return undef;
    }
    unless (($entry)&&($robot)) {
	 &Sympa::Log::do_log('info',"missing parameters");
	 return undef;
    }
    if ($entry =~ /\*.*\*/) {
	&Sympa::Log::do_log('info',"incorrect parameter $entry");
	return undef;
    }
    my $dir = $list->{'dir'}.'/search_filters';
    unless ((-d $dir) || mkdir ($dir, 0755)) {
	&Sympa::Log::do_log('info','do_blacklist : unable to create dir %s',$dir);
	return undef;
    }
    my $file = $dir.'/blacklist.txt';
    
    if (open BLACKLIST, "$file"){
	while(<BLACKLIST>) {
	    next if (/^\s*$/o || /^[\#\;]/o);
	    my $regexp= $_ ;
	    chomp $regexp;
	    $regexp =~ s/\*/.*/ ; 
	    $regexp = '^'.$regexp.'$';
	    if ($entry =~ /$regexp/i) { 
		&Sympa::Log::do_log('notice','do_blacklist : %s already in blacklist(%s)',$entry,$_);
		return 0;
	    }	
	}
	close BLACKLIST;
    }   
    unless (open BLACKLIST, ">> $file"){
	&Sympa::Log::do_log('info','do_blacklist : append to file %s',$file);
	return undef;
    }
    print BLACKLIST "$entry\n";
    close BLACKLIST;

}

=head2 md5_fingerprint($string)

The algorithm MD5 (Message Digest 5) is a cryptographic hash function which
permit to obtain the fingerprint of a file/data.

Returns the md5 digest in hexadecimal format of given string.

=cut

sub md5_fingerprint {
    
    my $input_string = shift;
    return undef unless (defined $input_string);
    chomp $input_string;
    
    my $digestmd5 = new Digest::MD5;
    $digestmd5->reset;
    $digestmd5->add($input_string);
    return (unpack("H*", $digestmd5->digest));
}

sub get_separator {
    return $separator;
}

=head2 get_regexp($type)

Return the Sympa regexp corresponding to the given type.

=cut

sub get_regexp {
    my $type = shift;

    if (defined $regexp{$type}) {
	return $regexp{$type};
    }else {
	return '\w+'; ## default is a very strict regexp
    }

}

=head2 CleanSpool($spool_dir, $clean_delay)

Clean all messages in spool $spool_dir older than $clean_delay.

=head3 Parameters

=over

=item * I<$spool_dir>: a string corresponding to the path to the spool to clean;

=item * I<$clean_delay>: the delay between the moment we try to clean spool and the last modification date of a file.

=back

=head3 Return value

A true value if the spool was cleaned, a false value otherwise. 

=head2 CleanDir($dir, $clean_delay)

Cleans files older than $clean_delay from spool $spool_dir

Returns a true value.

=cut

sub CleanDir {
    my ($dir, $clean_delay) = @_;
    &Sympa::Log::do_log('debug', 'CleanSpool(%s,%s)', $dir, $clean_delay);

    unless (opendir(DIR, $dir)) {
	&Sympa::Log::do_log('err', "Unable to open '%s' spool : %s", $dir, $!);
	return undef;
    }

    my @qfile = sort grep (!/^\.+$/,readdir(DIR));
    closedir DIR;
    
    my ($curlist,$moddelay);
    foreach my $f (sort @qfile) {

	if ((stat "$dir/$f")[9] < (time - $clean_delay * 60 * 60 * 24)) {
	    if (-f "$dir/$f") {
		unlink ("$dir/$f") ;
		&Sympa::Log::do_log('notice', 'Deleting old file %s', "$dir/$f");
	    }elsif (-d "$dir/$f") {
		unless (&Sympa::Tools::File::remove_dir("$dir/$f")) {
		    &Sympa::Log::do_log('err', 'Cannot remove old directory %s : %s', "$dir/$f", $!);
		    next;
		}
		&Sympa::Log::do_log('notice', 'Deleting old directory %s', "$dir/$f");
	    }
	}
    }
    return 1;
}

=head2 get_lockname()

Return a lockname that is a uniq id of a processus (hostname + pid) ; hostname
(20) and pid(10) are truncated in order to store lockname in database
varchar(30)

=cut

sub get_lockname (){
    return substr(substr(hostname(), 0, 20).$$,0,30);   
}

=head2 wrap_text($text, $init, $subs, $cols)

Return line-wrapped text.

=cut

sub wrap_text {
    my $text = shift;
    my $init = shift;
    my $subs = shift;
    my $cols = shift;
    $cols = 78 unless defined $cols;
    return $text unless $cols;

    $text = Text::LineFold->new(
	    Language => &Sympa::Language::GetLang(),
	    OutputCharset => (&Encode::is_utf8($text)? '_UNICODE_': 'utf8'),
	    Prep => 'NONBREAKURI',
	    ColumnsMax => $cols
	)->fold($init, $subs, $text);

    return $text;
}

=head2 addrencode($addr, $phrase, $charset)

Return formatted (and encoded) name-addr as RFC5322 3.4.

=head3 Parameters

=over

=item * I<$addr>

=item * I<$phrase>

=item * I<$charset> (default: utf8)

=back

=cut

sub addrencode {
    my $addr = shift;
    my $phrase = (shift || '');
    my $charset = (shift || 'utf8');

    return undef unless $addr =~ /\S/;

    if ($phrase =~ /[^\s\x21-\x7E]/) {
	# Minimal encoding leaves special characters unencoded.
	# In this case do maximal encoding for workaround.
	my $minimal =
	    ($phrase =~ /(\A|\s)[\x21-\x7E]*[\"(),:;<>\@\\][\x21-\x7E]*(\s|\z)/)?
	    'NO': 'YES';
	$phrase = MIME::EncWords::encode_mimewords(
	    Encode::decode('utf8', $phrase),
	    'Encoding' => 'A', 'Charset' => $charset,
	    'Replacement' => 'FALLBACK',
	    'Field' => 'Resent-Sender', # almost longest
	    'Minimal' => $minimal
            );
	return "$phrase <$addr>";
    } elsif ($phrase =~ /\S/) {
	$phrase =~ s/([\\\"])/\\$1/g;
	return "\"$phrase\" <$addr>";
    } else {
	return "<$addr>";
    }
}

=head2 create_html_part_from_web_page($param)

Generate a newsletter from an HTML URL or a file path.

=cut

sub create_html_part_from_web_page {
    my $param = shift;
    &Sympa::Log::do_log('debug',"Creating HTML MIME part. Source: %s",$param->{'source'});
    my $mailHTML = new MIME::Lite::HTML(
					{
					    From => $param->{'From'},
					    To => $param->{'To'},
					    Headers => $param->{'Headers'},
					    Subject => $param->{'Subject'},
					    HTMLCharset => 'utf-8',
					    TextCharset => 'utf-8',
					    TextEncoding => '8bit',
					    HTMLEncoding => '8bit',
					    remove_jscript => '1', #delete the scripts in the html
					}
					);
    # parse return the MIME::Lite part to send
    my $part = $mailHTML->parse($param->{'source'});
    unless (defined($part)) {
	&Sympa::Log::do_log('err', 'Unable to convert file %s to a MIME part',$param->{'source'});
	return undef;
    }
    return $part->as_string;
}

=head2 decode_header($msg, $tag, $sep)

Return header value decoded to UTF-8 or undef.
trailing newline will be removed.
If sep is given, return all occurrances joined by it.

=cut

sub decode_header {
    my $msg = shift;
    my $tag = shift;
    my $sep = shift || undef;

    my $head;
    if (ref $msg eq 'Sympa::Message') {
	$head = $msg->{'msg'}->head;
    } elsif (ref $msg eq 'MIME::Entity') {
	$head = $msg->head;
    } elsif (ref $msg eq 'MIME::Head' or ref $msg eq 'Mail::Header') {
	$head = $msg;
    }
    if (defined $sep) {
	my @values = $head->get($tag);
	return undef unless scalar @values;
	foreach my $val (@values) {
	    $val = MIME::EncWords::decode_mimewords($val, Charset => 'UTF-8');
	    chomp $val;
	}
	return join $sep, @values;
    } else {
	my $val = $head->get($tag);
	return undef unless defined $val;
	$val = MIME::EncWords::decode_mimewords($val, Charset => 'UTF-8');
	chomp $val;
	return $val;
    }
}

1;
