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

=head1 NAME

Sympa::Archive - Archiving functions

=head1 DESCRIPTION

This module does the archiving job for a mailing lists.

=cut

package Sympa::Archive;

use strict;

use Cwd;
use Encode qw(decode_utf8 encode_utf8);
use HTML::Entities qw(decode_entities);

use Sympa::Conf;
use Sympa::Log;
use Sympa::Message;
use Sympa::Tools::File;

my $serial_number = 0; # incremented on each archived mail

## RCS identification.

=head1 FUNCTIONS

=head2 store_last($list, $msg)

Does the real job : stores the message given as an argument into
the indicated directory.

=cut

sub store_last {
    my($list, $msg) = @_;
    
    &Sympa::Log::do_log ('debug2','%s::store ()', __PACKAGE__);
    
    my($filename, $newfile);
    
    return unless $list->is_archived();
    my $dir = $list->{'dir'}.'/archives';
    
    ## Create the archive directory if needed
    mkdir ($dir, "0775") if !(-d $dir);
    chmod 0774, $dir;
    
    
    ## erase the last  message and replace it by the current one
    open(OUT, "> $dir/last_message");
    if (ref ($msg)) {
  	$msg->print(\*OUT);
    }else {
 	print OUT $msg;
    }
    close(OUT);
    
}

=head2 lists($name)

Lists the files included in the archive, preformatted for printing.

Returns an array.

=cut

sub list {
    my $name = shift;

    &Sympa::Log::do_log ('debug',"%s::list($name)", __PACKAGE__);

    my($filename, $newfile);
    my(@l, $i);
    
    unless (-d "$name") {
	&Sympa::Log::do_log ('warning',"%s::list($name) failed, no directory $name", __PACKAGE__);
#      @l = ($msg::no_archives_available);
      return @l;
  }
    unless (opendir(DIR, "$name")) {
	&Sympa::Log::do_log ('warning',"%s::list($name) failed, cannot open directory $name", __PACKAGE__);
#	@l = ($msg::no_archives_available);
	return @l;
    }
   foreach $i (sort readdir(DIR)) {
       next if ($i =~ /^\./o);
       next unless  ($i =~ /^\d\d\d\d\-\d\d$/);
       my(@s) = stat("$name/$i");
       my $a = localtime($s[9]);
       push(@l, sprintf("%-40s %7d   %s\n", $i, $s[7], $a));
   }
    return @l;
}

sub scan_dir_archive {
    
    my($dir, $month) = @_;
    
    &Sympa::Log::do_log ('info',"%s::scan_dir_archive($dir, $month)", __PACKAGE__);

    unless (opendir (DIR, "$dir/$month/arctxt")){
	&Sympa::Log::do_log ('info',"%s::scan_dir_archive($dir, $month): unable to open dir $dir/$month/arctxt", __PACKAGE__);
	return undef;
    }
    
    my $all_msg = [];
    my $i = 0 ;
    foreach my $file (sort readdir(DIR)) {
	next unless ($file =~ /^\d+$/);
	&Sympa::Log::do_log ('debug',"%s::scan_dir_archive($dir, $month): start parsing message $dir/$month/arctxt/$file", __PACKAGE__);

	my $mail = new Sympa::Message({'file'=>"$dir/$month/arctxt/$file",'noxsympato'=>'noxsympato'});
	unless (defined $mail) {
	    &Sympa::Log::do_log('err', 'Unable to create Message object %s', $file);
	    return undef;
	}
	
	&Sympa::Log::do_log('debug',"MAIL object : $mail");

	$i++;
	my $msg = {};
	$msg->{'id'} = $i;

	$msg->{'subject'} = &Sympa::Tools::decode_header($mail, 'Subject');
	$msg->{'from'} = &Sympa::Tools::decode_header($mail, 'From');
	$msg->{'date'} = &Sympa::Tools::decode_header($mail, 'Date');

	$msg->{'full_msg'} = $mail->{'msg'}->as_string;

	&Sympa::Log::do_log('debug','%s::scan_dir_archive adding message %s in archive to send', __PACKAGE__, $msg->{'subject'});

	push @{$all_msg}, $msg ;
    }
    closedir DIR ;

    return $all_msg;
}

=head2 search_msgid($dir, $msgid)

Find a message in archive specified by I<$dir> and I<$msgid>.

=head3 Parameters

=over

=item * I<$dir>

=item * I<$msgid>

=back

=head3 Return value

undef | #message in arctxt

=cut

sub search_msgid {
    
    my($dir, $msgid) = @_;
    
    &Sympa::Log::do_log ('info',"%s::search_msgid($dir, $msgid)", __PACKAGE__);

    
    if ($msgid =~ /NO-ID-FOUND\.mhonarc\.org/) {
	&Sympa::Log::do_log('err','remove_arc: no message id found');return undef;
    } 
    unless ($dir =~ /\d\d\d\d\-\d\d\/arctxt/) {
	&Sympa::Log::do_log ('err',"%s::search_msgid : dir $dir look unproper", __PACKAGE__);
	return undef;
    }
    unless (opendir (ARC, "$dir")){
	&Sympa::Log::do_log ('err',"%s::scan_dir_archive($dir, $msgid): unable to open dir $dir", __PACKAGE__);
	return undef;
    }
    chomp $msgid ;

    foreach my $file (grep (!/\./,readdir ARC)) {
	next unless (open MAIL,"$dir/$file") ;
	while (<MAIL>) {
	    last if /^$/ ; #stop parse after end of headers
	    if (/^Message-id:\s?<?([^>\s]+)>?\s?/i ) {
		my $id = $1;
		if ($id eq $msgid) {
		    close MAIL; closedir ARC;
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
    my($name, $file) = @_;
    my $fn = "$name/$file";
    
    return $fn if (-r $fn && -f $fn);
    return undef;
}


=head2 last_path($list)
    
Return path for latest message distributed in the list.

=cut

sub last_path {
    
    my $list = shift;

    &Sympa::Log::do_log('debug', '%s::last_path(%s)', __PACKAGE__, $list->{'name'});

    return undef unless ($list->is_archived());
    my $file = $list->{'dir'}.'/archives/last_message';

    return ($list->{'dir'}.'/archives/last_message') if (-f $list->{'dir'}.'/archives/last_message'); 
    return undef;

}

=head2 load_html_message(%parameters)

Load an archived message, returns the mhonarc metadata

=head3 Parameters

=over

=item * I<file_path>

=back

=head3 Return value

=cut 

sub load_html_message {
    my %parameters = @_;

    &Sympa::Log::do_log ('debug2',$parameters{'file_path'});
    my %metadata;

    unless (open ARC, $parameters{'file_path'}) {
	&Sympa::Log::do_log('err', "Failed to load message '%s' : $!", $parameters{'file_path'});
	return undef;
    }

    while (<ARC>) {
	last if /^\s*$/; ## Metadata end with an emtpy line

	if (/^<!--(\S+): (.*) -->$/) {
	    my ($key, $value) = ($1, $2);
	    $value = encode_utf8(decode_entities(decode_utf8($value)));
	    if ($key eq 'X-From-R13') {
		$metadata{'X-From'} = $value;
		$metadata{'X-From'} =~ tr/N-Z[@A-Mn-za-m/@A-Z[a-z/; ## Mhonarc protection of email addresses
		$metadata{'X-From'} =~ s/^.*<(.*)>/$1/g; ## Remove the gecos
	    }
	    $metadata{$key} = $value;
	}
    }

    close ARC;
    
    return \%metadata;
}


sub clean_archive_directory{
    my $params = shift;
    &Sympa::Log::do_log('debug',"Cleaning archives for directory '%s'.",$params->{'arc_root'}.'/'.$params->{'dir_to_rebuild'});
    my $answer;
    $answer->{'dir_to_rebuild'} = $params->{'arc_root'}.'/'.$params->{'dir_to_rebuild'};
    $answer->{'cleaned_dir'} = $Sympa::Conf::Conf{'tmpdir'}.'/'.$params->{'dir_to_rebuild'};
    unless(my $number_of_copies = &Sympa::Tools::File::copy_dir($answer->{'dir_to_rebuild'},$answer->{'cleaned_dir'})){
	&Sympa::Log::do_log('err',"Unable to create a temporary directory where to store files for HTML escaping (%s). Cancelling.",$number_of_copies);
	return undef;
    }
    if(opendir ARCDIR,$answer->{'cleaned_dir'}){
	my $files_left_uncleaned = 0;
	foreach my $file (readdir(ARCDIR)){
	    next if($file =~ /^\./);	    
	    $file = $answer->{'cleaned_dir'}.'/'.$file;
	    $files_left_uncleaned++ unless(&clean_archived_message({'input'=>$file ,'output'=>$file})); 
	}
	closedir DIR;
	if ($files_left_uncleaned) {
	    &Sympa::Log::do_log('err',"HTML cleaning failed for %s files in the directory %s.",$files_left_uncleaned,$answer->{'dir_to_rebuild'});
	}
	$answer->{'dir_to_rebuild'} = $answer->{'cleaned_dir'};
    }else{
	&Sympa::Log::do_log('err','Unable to open directory %s: %s',$answer->{'dir_to_rebuild'},$!);
	&Sympa::Tools::File::del_dir($answer->{'cleaned_dir'});
	return undef;
    }
    return $answer;
}

sub clean_archived_message{
    my $params = shift;
    &Sympa::Log::do_log('debug',"Cleaning HTML parts of a message input %s , output  %s ",$params->{'input'},$params->{'output'});

    my $input = $params->{'input'};
    my $output = $params->{'output'};


    if (my $msg = new Sympa::Message({'file'=>$input})){
	if($msg->clean_html()){
	    if(open TMP, ">$output") {
		print TMP $msg->{'msg'}->as_string;
		close TMP;
	    }else{
		&Sympa::Log::do_log('err','Unable to create a tmp file to write clean HTML to file %s',$output);
		return undef;
	    }
	}else{
	    &Sympa::Log::do_log('err','HTML cleaning in file %s failed.',$output);
	    return undef;
	}
    }else{
	&Sympa::Log::do_log('err','Unable to create a Message object with file %s',$input);
	exit;
	return undef;
    }
}

=head2 convert_single_msg_2_html($data)
    
Convert a messsage to html. 
Result is stored in $destination_dir
Attachement_url is used to link attachement

=cut

sub convert_single_msg_2_html {
    
    my $data =shift;
    my $msg_as_string = $data->{'msg_as_string'};
    my $destination_dir = $data->{'destination_dir'};
    my $attachement_url = $data->{'attachement_url'};
    my $list = $data->{'list'};
    my $robot = $data->{'robot'};
    my $messagekey = $data->{'messagekey'};

    my $listname =''; my $msg_file;
    my $host = $robot;
    if ($list) {
	$host = $list->{'admin'}{'host'};
	$robot = $list->{'robot'};
	$listname = $list->{'name'};
	$msg_file = &Sympa::Conf::get_robot_conf($robot, 'tmpdir').'/'.$list->get_list_id().'_'.$$;
    }else{
	$msg_file = &Sympa::Conf::get_robot_conf($robot, 'tmpdir').'/'.$messagekey.'_'.$$;
    }

    my $pwd = getcwd;  #  mhonarc require du change workdir so this proc must retore it    
    unless (open(OUT, ">$msg_file")) {
&Sympa::Log::do_log('notice', 'Could Not open %s', $msg_file);
	return undef;
    }
    printf OUT $msg_as_string ;
    close(OUT);

    unless (-d $destination_dir) {
	unless (&Sympa::Tools::File::mkdir_all($destination_dir, 0777)) {
	    &Sympa::Log::do_log('err','Unable to create %s', $destination_dir);
	    return undef;
	}
    }
    my $mhonarc_ressources = &Sympa::Tools::get_filename('etc',{},'mhonarc-ressources.tt2', $robot,$list,$Sympa::Conf::Conf{'etc'});
    
    unless ($mhonarc_ressources) {
&Sympa::Log::do_log('notice',"Cannot find any MhOnArc ressource file");
	return undef;
    }
    ## generate HTML
    unless (chdir $destination_dir) {
&Sympa::Log::do_log('err',"Could not change working directory to %s",$destination_dir);
    }
    my $tracepwd = getcwd ;


    my $mhonarc = &Sympa::Conf::get_robot_conf($robot, 'mhonarc');
    my $base_url = &Sympa::Conf::get_robot_conf($robot, 'wwsympa_url');
    #open ARCMOD, "$mhonarc  -single --outdir .. -rcfile $mhonarc_ressources -definevars listname=$listname -definevars hostname=$host -attachmenturl=$attachement_url $msg_file |";
    #open MSG, ">msg00000.html";
    #&Sympa::Log::do_log('debug', "$mhonarc  --outdir .. -single -rcfile $mhonarc_ressources -definevars listname=$listname -definevars hostname=$host $msg_file");
    #print MSG <ARCMOD>;
    #close MSG;
    #close ARCMOD;
    `$mhonarc  -single --outdir .. -rcfile $mhonarc_ressources -definevars listname=$listname -definevars hostname=$host -attachmenturl=$attachement_url $msg_file > msg00000.html`;

    # restore current wd 
    chdir $pwd;		

    return 1;
}

1;
