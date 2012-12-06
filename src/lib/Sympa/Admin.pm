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

Sympa::Admin - Administrative functions

=head1 DESCRIPTION 

This module provides creation and edition functions.

=cut 

package Sympa::Admin;

use strict;

use File::Copy;

use Sympa::Configuration;
use Sympa::Constants;
use Sympa::Language;
use Sympa::List;
use Sympa::Lock;
use Sympa::Log;
use Sympa::Scenario;
use Sympa::SDM;
use Sympa::Template;
use Sympa::Tools;
use Sympa::Tools::File;

=head1 FUNCTIONS

=head2 create_list_old($param, $template, $robot, $origin, $user_mail)

Creates a list, without family concept.

=head3 Parameters

=over 

=item * I<$param>: an hashref containing configuration parameters, as the
following keys:

=over 4

=item - I<listname>,

=item - I<subject>,

=item - I<owner>: array of hashes, with key email mandatory

=item - I<owner_include>: array of hashes, with key source mandatory

=back

=item * I<$template>: the list creation template

=item * I<$robot>: the list robot

=item * I<$origin>: the source of the command : web, soap or command_line (no
longer used)

=back 

=head3 Return value

An hashref with the following keys, or I<undef> if something went wrong:

=over 

=item * I<list>: the just created L<Sympa::List> object

=item * I<aliases>: I<undef> if not applicable; 1 (if ok) or $aliases : concatenated string of aliases if they are not installed or 1 (in status open)

=back

=cut 

sub create_list_old{
    my ($param,$template,$robot,$origin, $user_mail) = @_;
    &Sympa::Log::do_log('debug', '%s::create_list_old(%s,%s)',__PACKAGE__,$param->{'listname'},$robot,$origin);

     ## obligatory list parameters 
    foreach my $arg ('listname','subject') {
	unless ($param->{$arg}) {
	    &Sympa::Log::do_log('err','%s::create_list_old : missing list param %s', __PACKAGE__, $arg);
	    return undef;
	}
    }
    # owner.email || owner_include.source
    unless (&check_owner_defined($param->{'owner'},$param->{'owner_include'})) {
	&Sympa::Log::do_log('err','%s::create_list_old : problem in owner definition in this list creation', __PACKAGE__);
	return undef;
    }


    # template
    unless ($template) {
	&Sympa::Log::do_log('err','%s::create_list_old : missing param "template"', __PACKAGE__, $template);
	return undef;
    }
    # robot
    unless ($robot) {
	&Sympa::Log::do_log('err','%s::create_list_old : missing param "robot"', __PACKAGE__, $robot);
	return undef;
    }
   
    ## check listname
    $param->{'listname'} = lc ($param->{'listname'});
    my $listname_regexp = &Sympa::Tools::get_regexp('listname');

    unless ($param->{'listname'} =~ /^$listname_regexp$/i) {
	&Sympa::Log::do_log('err','%s::create_list_old : incorrect listname %s', __PACKAGE__, $param->{'listname'});
	return undef;
    }

    my $regx = &Sympa::Configuration::get_robot_conf($robot,'list_check_regexp');
    if( $regx ) {
	if ($param->{'listname'} =~ /^(\S+)-($regx)$/) {
	    &Sympa::Log::do_log('err','%s::create_list_old : incorrect listname %s matches one of service aliases', __PACKAGE__, $param->{'listname'});
	    return undef;
	}
    }    

    if ($param->{'listname'} eq &Sympa::Configuration::get_robot_conf($robot,'email')) {
	&do_log('err','%s::create_list : incorrect listname %s matches one of service aliases', __PACKAGE__, $param->{'listname'});
	return undef;
    }

    ## Check listname on SMTP server
    my $res = &list_check_smtp($param->{'listname'}, $robot);
    unless (defined $res) {
	&Sympa::Log::do_log('err', "%s::create_list_old : can't check list %.128s on %s", __PACKAGE__,
		$param->{'listname'}, $robot);
	return undef;
    }
    
    ## Check this listname doesn't exist already.
    if( $res || new Sympa::List ($param->{'listname'}, $robot, {'just_try' => 1})) {
	&Sympa::Log::do_log('err', '%s::create_list_old : could not create already existing list %s on %s for ', __PACKAGE__, 
		$param->{'listname'}, $robot);
	foreach my $o (@{$param->{'owner'}}){
	    &Sympa::Log::do_log('err',$o->{'email'});
	}
	return undef;
    }


    ## Check the template supposed to be used exist.
    my $template_file = &Sympa::Tools::get_filename('etc',{},'create_list_templates/'.$template.'/config.tt2', $robot, undef, $Sympa::Configuration::Conf{'etc'});
    unless (defined $template_file) {
	&Sympa::Log::do_log('err', 'no template %s found',$template);
	return undef;
    }

     ## Create the list directory
     my $list_dir;

     # a virtual robot
     if (-d "$Sympa::Configuration::Conf{'home'}/$robot") {
	 unless (-d $Sympa::Configuration::Conf{'home'}.'/'.$robot) {
	     unless (mkdir ($Sympa::Configuration::Conf{'home'}.'/'.$robot,0777)) {
		 &Sympa::Log::do_log('err', '%s::create_list_old : unable to create %s/%s : %s', __PACKAGE__,$Sympa::Configuration::Conf{'home'},$robot,$?);
		 return undef;
	     }    
	 }
	 $list_dir = $Sympa::Configuration::Conf{'home'}.'/'.$robot.'/'.$param->{'listname'};
     }else {
	 $list_dir = $Sympa::Configuration::Conf{'home'}.'/'.$param->{'listname'};
     }

    ## Check the privileges on the list directory
     unless (mkdir ($list_dir,0777)) {
	 &Sympa::Log::do_log('err', '%s::create_list_old : unable to create %s : %s',__PACKAGE__,$list_dir,$?);
	 return undef;
     }    
    
    ## Check topics
    if ($param->{'topics'}){
	unless (&check_topics($param->{'topics'},$robot)){
	    &Sympa::Log::do_log('err', '%s::create_list_old : topics param %s not defined in topics.conf',__PACKAGE__,$param->{'topics'});
	}
    }
      
    ## Creation of the config file
    my $host = &Sympa::Configuration::get_robot_conf($robot, 'host');
    $param->{'creation'}{'date'} = Sympa::Language::gettext_strftime "%d %b %Y at %H:%M:%S", localtime(time);
    $param->{'creation'}{'date_epoch'} = time;
    $param->{'creation_email'} = "listmaster\@$host" unless ($param->{'creation_email'});
    $param->{'status'} = 'open'  unless ($param->{'status'});
       
    my $tt2_include_path = &Sympa::Tools::make_tt2_include_path($robot,'create_list_templates/'.$template,'','',$Sympa::Configuration::Conf{'etc'},$Sympa::Configuration::Conf{'viewmaildir'},$Sympa::Configuration::Conf{'domain'});

    ## Lock config before openning the config file
    my $lock = new Sympa::Lock ($list_dir.'/config');
    unless (defined $lock) {
	&Sympa::Log::do_log('err','Lock could not be created');
	return undef;
    }
    $lock->set_timeout(5); 
    unless ($lock->lock('write')) {
	return undef;
    }
    unless (open CONFIG, '>', "$list_dir/config") {
	&do_log('err','Impossible to create %s/config : %s', $list_dir, $!);
	$lock->unlock();
	return undef;
    }
    ## Use an intermediate handler to encode to filesystem_encoding
    my $config = '';
    my $fd = new IO::Scalar \$config;    
    &Sympa::Template::parse_tt2($param, 'config.tt2', $fd, $tt2_include_path);
#    Encode::from_to($config, 'utf8', $Sympa::Configuration::Conf{'filesystem_encoding'});
    print CONFIG $config;

    close CONFIG;
    
    ## Unlock config file
    $lock->unlock();

    ## Creation of the info file 
    # remove DOS linefeeds (^M) that cause problems with Outlook 98, AOL, and EIMS:
    $param->{'description'} =~ s/\r\n|\r/\n/g;

    ## info file creation.
    unless (open INFO, '>', "$list_dir/info") {
	&Sympa::Log::do_log('err','Impossible to create %s/info : %s',$list_dir,$!);
    }
    if (defined $param->{'description'}) {
	Encode::from_to($param->{'description'}, 'utf8', $Sympa::Configuration::Conf{'filesystem_encoding'});
	print INFO $param->{'description'};
    }
    close INFO;
    
    ## Create list object
    my $list;
    unless ($list = new Sympa::List ($param->{'listname'}, $robot)) {
	&Sympa::Log::do_log('err','%s::create_list_old : unable to create list %s', __PACKAGE__,$param->{'listname'});
	return undef;
    }

    ## Create shared if required
    if (defined $list->{'admin'}{'shared_doc'}) {
	$list->create_shared();
    }

    #log in stat_table to make statistics

    if($origin eq "web"){
	&Sympa::Log::db_stat_log({'robot' => $robot, 'list' => $param->{'listname'}, 'operation' => 'create list', 'parameter' => '', 'mail' => $user_mail, 'client' => '', 'daemon' => 'wwsympa.fcgi'});
    }

    my $return = {};
    $return->{'list'} = $list;

    if ($list->{'admin'}{'status'} eq 'open') {
	$return->{'aliases'} = &install_aliases($list,$robot);
    }else{
    $return->{'aliases'} = 1;
    }

    ## Synchronize list members if required
    if ($list->has_include_data_sources()) {
	&Sympa::Log::do_log('notice', "Synchronizing list members...");
	$list->sync_include();
    }
    
    $list->save_config;
   return $return;
}

=head2 create_list($param, $family, $robot, $abort_on_error)

Create a list, with family concept.

=head3 Parameters

=over 

=item * I<$param>: an hashref containing configuration parameters, as the
following keys:

=over 4

=item - I<listname>,

=item - I<subject>,

=item - I<owner>: array of hashes, with key email mandatory

=item - I<owner_include>: array of hashes, with key source mandatory

=back

=item * I<$family>: the list family (L<Sympa::Family> object)

=item * I<$robot>: the list robot

=item * I<$abort_on_error>:  won't create the list directory on tt2 process
error (usefull for dynamic lists that throw exceptions)

=back 

=head3 Return value

An hashref with the following keys, or I<undef> if something went wrong:

=over 

=item * I<list>: the just created L<Sympa::List> object

=item * I<aliases>: I<undef> if not applicable; 1 (if ok) or $aliases : concatenated string of aliases if they are not installed or 1 (in status open)

=back

=cut 

sub create_list{
    my ($param,$family,$robot, $abort_on_error) = @_;
    &Sympa::Log::do_log('info', '%s::create_list(%s,%s,%s)',__PACKAGE__,$param->{'listname'},$family->{'name'},$param->{'subject'});

    ## mandatory list parameters 
    foreach my $arg ('listname') {
	unless ($param->{$arg}) {
	    &Sympa::Log::do_log('err','%s::create_list : missing list param %s', __PACKAGE__, $arg);
	    return undef;
	}
    }

    unless ($family) {
	&Sympa::Log::do_log('err','%s::create_list : missing param "family"', __PACKAGE__);
	return undef;
    }

    #robot
    unless ($robot) {
	&Sympa::Log::do_log('err','%s::create_list : missing param "robot"', __PACKAGE__, $robot);
	return undef;
    }
   
    ## check listname
    $param->{'listname'} = lc ($param->{'listname'});
    my $listname_regexp = &Sympa::Tools::get_regexp('listname');

    unless ($param->{'listname'} =~ /^$listname_regexp$/i) {
	&Sympa::Log::do_log('err','%s::create_list : incorrect listname %s', __PACKAGE__, $param->{'listname'});
	return undef;
    }

    my $regx = &Sympa::Configuration::get_robot_conf($robot,'list_check_regexp');
    if( $regx ) {
	if ($param->{'listname'} =~ /^(\S+)-($regx)$/) {
	    &Sympa::Log::do_log('err','%s::create_list : incorrect listname %s matches one of service aliases', __PACKAGE__, $param->{'listname'});
	    return undef;
	}
    }    
    if ($param->{'listname'} eq &Sympa::Configuration::get_robot_conf($robot,'email')) {
	&do_log('err','%s::create_list : incorrect listname %s matches one of service aliases', __PACKAGE__, $param->{'listname'});
	return undef;
    }

    ## Check listname on SMTP server
    my $res = &list_check_smtp($param->{'listname'}, $robot);
    unless (defined $res) {
	&Sympa::Log::do_log('err', "%s::create_list : can't check list %.128s on %s", __PACKAGE__,
		$param->{'listname'}, $robot);
	return undef;
    }

    if ($res) {
	&Sympa::Log::do_log('err', '%s::create_list : could not create already existing list %s on %s for ', __PACKAGE__, $param->{'listname'}, $robot);
	foreach my $o (@{$param->{'owner'}}){
	    &Sympa::Log::do_log('err',$o->{'email'});
	}
	return undef;
    }

    ## template file
    my $template_file = &Sympa::Tools::get_filename('etc',{},'config.tt2', $robot,$family, $Sympa::Configuration::Conf{'etc'});
    unless (defined $template_file) {
	&Sympa::Log::do_log('err', '%s::create_list : no config template from family %s@%s',__PACKAGE__,$family->{'name'},$robot);
	return undef;
    }

    my $family_config = &Sympa::Configuration::get_robot_conf($robot,'automatic_list_families');
    $param->{'family_config'} = $family_config->{$family->{'name'}};
    my $conf;
    my $tt_result = &Sympa::Template::parse_tt2($param, 'config.tt2', \$conf, [$family->{'dir'}]);
    unless (defined $tt_result || !$abort_on_error) {
      &Sympa::Log::do_log('err', '%s::create_list : abort on tt2 error. List %s from family %s@%s', __PACKAGE__,
                $param->{'listname'}, $family->{'name'},$robot);
      return undef;
    }
    
     ## Create the list directory
     my $list_dir;

    if (-d "$Sympa::Configuration::Conf{'home'}/$robot") {
	unless (-d $Sympa::Configuration::Conf{'home'}.'/'.$robot) {
	    unless (mkdir ($Sympa::Configuration::Conf{'home'}.'/'.$robot,0777)) {
		&Sympa::Log::do_log('err', '%s::create_list : unable to create %s/%s : %s',__PACKAGE__,$Sympa::Configuration::Conf{'home'},$robot,$?);
		return undef;
	    }    
	}
	$list_dir = $Sympa::Configuration::Conf{'home'}.'/'.$robot.'/'.$param->{'listname'};
    }else {
	$list_dir = $Sympa::Configuration::Conf{'home'}.'/'.$param->{'listname'};
    }

     unless (-r $list_dir || mkdir ($list_dir,0777)) {
	 &Sympa::Log::do_log('err', '%s::create_list : unable to create %s : %s',__PACKAGE__,$list_dir,$?);
	 return undef;
     }    
    
    ## Check topics
    if (defined $param->{'topics'}){
	unless (&check_topics($param->{'topics'},$robot)){
	    &Sympa::Log::do_log('err', '%s::create_list : topics param %s not defined in topics.conf',__PACKAGE__,$param->{'topics'});
	}
    }
      
    ## Lock config before openning the config file
    my $lock = new Sympa::Lock ($list_dir.'/config');
    unless (defined $lock) {
	&Sympa::Log::do_log('err','Lock could not be created');
	return undef;
    }
    $lock->set_timeout(5); 
    unless ($lock->lock('write')) {
	return undef;
    }

    ## Creation of the config file
    unless (open CONFIG, '>', "$list_dir/config") {
	&do_log('err','Impossible to create %s/config : %s', $list_dir, $!);
	$lock->unlock();
	return undef;
    }
    #&Sympa::Template::parse_tt2($param, 'config.tt2', \*CONFIG, [$family->{'dir'}]);
    print CONFIG $conf;
    close CONFIG;
    
    ## Unlock config file
    $lock->unlock();

    ## Creation of the info file 
    # remove DOS linefeeds (^M) that cause problems with Outlook 98, AOL, and EIMS:
    $param->{'description'} =~ s/\r\n|\r/\n/g;

    unless (open INFO, '>', "$list_dir/info") {
	&Sympa::Log::do_log('err','Impossible to create %s/info : %s', $list_dir, $!);
    }
    if (defined $param->{'description'}) {
	print INFO $param->{'description'};
    }
    close INFO;

    ## Create associated files if a template was given.
    for my $file ('message.footer','message.header','message.footer.mime','message.header.mime','info') {
	my $template_file = &Sympa::Tools::get_filename('etc',{},$file.".tt2", $robot,$family, $Sympa::Configuration::Conf{'etc'});
	if (defined $template_file) {
	    my $file_content;
	    my $tt_result = &Sympa::Template::parse_tt2($param, $file.".tt2", \$file_content, [$family->{'dir'}]);
	    unless (defined $tt_result) {
		&Sympa::Log::do_log('err', '%s::create_list : tt2 error. List %s from family %s@%s, file %s', __PACKAGE__,
			$param->{'listname'}, $family->{'name'},$robot,$file);
	    }
	    unless (open FILE, '>', "$list_dir/$file") {
		&Sympa::Log::do_log('err','Impossible to create %s/%s : %s',$list_dir,$file,$!);
	    }
	    print FILE $file_content;
	    close FILE;
	}
    }

    ## Create list object
    my $list;
    unless ($list = new Sympa::List ($param->{'listname'}, $robot)) {
	&Sympa::Log::do_log('err','%s::create_list : unable to create list %s', __PACKAGE__, $param->{'listname'});
	return undef;
    }

    ## Create shared if required
    if (defined $list->{'admin'}{'shared_doc'}) {
	$list->create_shared();
    }   
    
    $list->{'admin'}{'creation'}{'date'} = Sympa::Language::gettext_strftime "%d %b %Y at %H:%M:%S", localtime(time);
    $list->{'admin'}{'creation'}{'date_epoch'} = time;
    if ($param->{'creation_email'}) {
	$list->{'admin'}{'creation'}{'email'} = $param->{'creation_email'};
    } else {
	my $host = &Sympa::Configuration::get_robot_conf($robot, 'host');
	$list->{'admin'}{'creation'}{'email'} = "listmaster\@$host";
    }
    if ($param->{'status'}) {
	$list->{'admin'}{'status'} = $param->{'status'};
    } else {
	$list->{'admin'}{'status'} = 'open';
    }
    $list->{'admin'}{'family_name'} = $family->{'name'};

    my $return = {};
    $return->{'list'} = $list;

    if ($list->{'admin'}{'status'} eq 'open') {
	$return->{'aliases'} = &install_aliases($list,$robot);
    }else{
    $return->{'aliases'} = 1;
    }

    ## Synchronize list members if required
    if ($list->has_include_data_sources()) {
	&Sympa::Log::do_log('notice', "Synchronizing list members...");
	$list->sync_include();
    }

    return $return;
}

=head2 update_list($list, $param, $family, $robot)

Update a list with family concept when the list already exists.

=head3 Parameters

=over 

=item * I<$list>: the list to update

=item * I<$param>: an hashref containing the new config parameters, as the following keys:

=over 4

=item - I<listname>,

=item - I<subject>,

=item - I<owner>: array of hashes, with key email mandatory

=item - I<owner_include>: array of hashes, with key source mandatory

=back

=item * I<$family>: the list family (L<Sympa::Family> object)

=item * I<$robot>: the list robot

=back

=head3 Return value

The updated L<Sympa::List> object.

=cut 

sub update_list{
    my ($list,$param,$family,$robot) = @_;
    &Sympa::Log::do_log('info', '%s::update_list(%s,%s,%s)',__PACKAGE__,$param->{'listname'},$family->{'name'},$param->{'subject'});

    ## mandatory list parameters
    foreach my $arg ('listname') {
	unless ($param->{$arg}) {
	    &Sympa::Log::do_log('err','%s::update_list : missing list param %s', __PACKAGE__, $arg);
	    return undef;
	}
    }

    ## template file
    my $template_file = &Sympa::Tools::get_filename('etc',{}, 'config.tt2', $robot,$family, $Sympa::Configuration::Conf{'etc'});
    unless (defined $template_file) {
	&Sympa::Log::do_log('err', '%s::update_list : no config template from family %s@%s',__PACKAGE__,$family->{'name'},$robot);
	return undef;
    }

    ## Check topics
    if (defined $param->{'topics'}){
	unless (&check_topics($param->{'topics'},$robot)){
	    &Sympa::Log::do_log('err', '%s::update_list : topics param %s not defined in topics.conf',__PACKAGE__,$param->{'topics'});
	}
    }

    ## Lock config before openning the config file
    my $lock = new Sympa::Lock ($list->{'dir'}.'/config');
    unless (defined $lock) {
	&Sympa::Log::do_log('err','Lock could not be created');
	return undef;
    }
    $lock->set_timeout(5); 
    unless ($lock->lock('write')) {
	return undef;
    }

    ## Creation of the config file
    unless (open CONFIG, '>', "$list->{'dir'}/config") {
	&do_log('err','Impossible to create %s/config : %s', $list->{'dir'}, $!);
	$lock->unlock();
	return undef;
    }
    &Sympa::Template::parse_tt2($param, 'config.tt2', \*CONFIG, [$family->{'dir'}]);
    close CONFIG;

    ## Unlock config file
    $lock->unlock();

    ## Create list object
    unless ($list = new Sympa::List ($param->{'listname'}, $robot)) {
	&Sympa::Log::do_log('err','%s::create_list : unable to create list %s', __PACKAGE__, $param->{'listname'});
	return undef;
    }
############## ? update
    $list->{'admin'}{'creation'}{'date'} = Sympa::Language::gettext_strftime "%d %b %Y at %H:%M:%S", localtime(time);
    $list->{'admin'}{'creation'}{'date_epoch'} = time;
    if ($param->{'creation_email'}) {
	$list->{'admin'}{'creation'}{'email'} = $param->{'creation_email'};
    } else {
	my $host = &Sympa::Configuration::get_robot_conf($robot, 'host');
	$list->{'admin'}{'creation'}{'email'} = "listmaster\@$host";
    }

    if ($param->{'status'}) {
	$list->{'admin'}{'status'} = $param->{'status'};
    } else {
	$list->{'admin'}{'status'} = 'open';
    }
    $list->{'admin'}{'family_name'} = $family->{'name'};

    ## Synchronize list members if required
    if ($list->has_include_data_sources()) {
	&Sympa::Log::do_log('notice', "Synchronizing list members...");
	$list->sync_include();
    }

    return $list;
}

=head2 rename_list(%parameters)

Rename a list or move a list to another virtual host.

=head3 Parameters

=over

=item * I<list>

=item * I<new_listname>

=item * I<new_robot>

=item * I<mode>: 'copy' 

=item * I<auth_method>

=item * I<user_email>

=item * I<remote_host>

=item * I<remote_addr>

=item * I<options>: 'skip_authz' to skip authorization scenarios eval

=back

=head3 Return value
      
I<1> in case of success, an error string otherwise.

=cut

sub rename_list{
    my (%param) = @_;
    &Sympa::Log::do_log('info', '',);

    my $list = $param{'list'};
    my $robot = $list->{'domain'};
    my $old_listname = $list->{'name'};

    # check new listname syntax
    my $new_listname = lc ($param{'new_listname'});
    my $listname_regexp = &Sympa::Tools::get_regexp('listname');
    
    unless ($new_listname =~ /^$listname_regexp$/i) {
      &Sympa::Log::do_log('err','incorrect listname %s', $new_listname);
      return 'incorrect_listname';
    }
    
    ## Evaluate authorization scenario unless run as listmaster (sympa.pl)
    my ($result, $r_action, $reason); 
    unless ($param{'options'}{'skip_authz'}) {
      $result = &Sympa::Scenario::request_action ('create_list',$param{'auth_method'},$param{'new_robot'},
					   {'sender' => $param{'user_email'},
					    'remote_host' => $param{'remote_host'},
					    'remote_addr' => $param{'remote_addr'}});
      
      if (ref($result) eq 'HASH') {
	$r_action = $result->{'action'};
	$reason = $result->{'reason'};
      }
      
      unless ($r_action =~ /do_it|listmaster/) {
	&Sympa::Log::do_log('err','authorization error');
	return 'authorization';
      }
    }

    ## Check listname on SMTP server
    my $res = list_check_smtp($param{'new_listname'}, $param{'new_robot'});
    unless ( defined($res) ) {
      &Sympa::Log::do_log('err', "can't check list %.128s on %.128s",
	      $param{'new_listname'}, $param{'new_robot'});
      return 'internal';
    }

    if( $res || 
	($list->{'name'} ne $param{'new_listname'}) && ## Do not test if listname did not change
	(new Sympa::List ($param{'new_listname'}, $param{'new_robot'}, {'just_try' => 1}))) {
      &Sympa::Log::do_log('err', 'Could not rename list %s on %s: new list %s on %s already existing list', $list->{'name'}, $robot, $param{'new_listname'}, 	$param{'new_robot'});
      return 'list_already_exists';
    }
    
    my $regx = &Sympa::Configuration::get_robot_conf($param{'new_robot'},'list_check_regexp');
    if( $regx ) {
      if ($param{'new_listname'} =~ /^(\S+)-($regx)$/) {
	&Sympa::Log::do_log('err','Incorrect listname %s matches one of service aliases', $param{'new_listname'});
	return 'incorrect_listname';
      }
    }

     unless ($param{'mode'} eq 'copy') {
         $list->savestats();
	 
	 ## Dump subscribers
	 $list->_save_list_members_file("$list->{'dir'}/subscribers.closed.dump");
	 
	 $param{'aliases'} = &remove_aliases($list, $list->{'domain'});
     }

     ## Rename or create this list directory itself
     my $new_dir;
     ## Default robot
     if (-d "$Sympa::Configuration::Conf{'home'}/$param{'new_robot'}") {
	 $new_dir = $Sympa::Configuration::Conf{'home'}.'/'.$param{'new_robot'}.'/'.$param{'new_listname'};
     }elsif ($param{'new_robot'} eq $Sympa::Configuration::Conf{'domain'}) {
	 $new_dir = $Sympa::Configuration::Conf{'home'}.'/'.$param{'new_listname'};
     }else {
	 &Sympa::Log::do_log('err',"Unknown robot $param{'new_robot'}");
	 return 'unknown_robot';
     }

    ## If we are in 'copy' mode, create en new list
    if ($param{'mode'} eq 'copy') {	 
	 unless ( $list = &clone_list_as_empty($list->{'name'},$list->{'domain'},$param{'new_listname'},$param{'new_robot'},$param{'user_email'})){
	     &Sympa::Log::do_log('err',"Unable to load $param{'new_listname'} while renaming");
	     return 'internal';
	 }	 
     }

    # set list status to pending if creation list is moderated
    if ($r_action =~ /listmaster/) {
      $list->{'admin'}{'status'} = 'pending' ;
      &Sympa::List::send_notify_to_listmaster('request_list_renaming',$list->{'domain'}, 
				       {'list' => $list,
					'new_listname' => $param{'new_listname'},
					'old_listname' => $old_listname,
					'email' => $param{'user_email'},
					'mode' => $param{'mode'}});
      $param{'status'} = 'pending';
    }
     
    ## Save config file for the new() later to reload it
    $list->save_config($param{'user_email'});
     
    ## This code should be in Sympa::List::rename()
    unless ($param{'mode'} eq 'copy') {     
	 unless (move ($list->{'dir'}, $new_dir )){
	     &Sympa::Log::do_log('err',"Unable to rename $list->{'dir'} to $new_dir : $!");
	     return 'internal';
	 }
     
	 ## Rename archive
	 my $arc_dir = &Sympa::Configuration::get_robot_conf($robot, 'arc_path').'/'.$list->get_list_id();
	 my $new_arc_dir = &Sympa::Configuration::get_robot_conf($param{'new_robot'}, 'arc_path').'/'.$param{'new_listname'}.'@'.$param{'new_robot'};
	 if (-d $arc_dir && $arc_dir ne $new_arc_dir) {
	     unless (move ($arc_dir,$new_arc_dir)) {
		 &Sympa::Log::do_log('err',"Unable to rename archive $arc_dir");
		 # continue even if there is some troubles with archives
		 # return undef;
	     }
	 }

	 ## Rename bounces
	 my $bounce_dir = $list->get_bounce_dir();
	 my $new_bounce_dir = &Sympa::Configuration::get_robot_conf($param{'new_robot'}, 'bounce_path').'/'.$param{'new_listname'}.'@'.$param{'new_robot'};
	 if (-d $bounce_dir && $bounce_dir ne $new_bounce_dir) {
	     unless (move ($bounce_dir,$new_bounce_dir)) {
		 &Sympa::Log::do_log('err',"Unable to rename bounces from $bounce_dir to $new_bounce_dir");
	     }
	 }
	 
	 # if subscribtion are stored in database rewrite the database
	 &Sympa::List::rename_list_db($list, $param{'new_listname'},
			       $param{'new_robot'});
     }
     ## Move stats
    unless (&Sympa::SDM::do_query("UPDATE stat_table SET list_stat=%s, robot_stat=%s WHERE (list_stat = %s AND robot_stat = %s )", 
    &Sympa::SDM::quote($param{'new_listname'}), 
    &Sympa::SDM::quote($param{'new_robot'}), 
    &Sympa::SDM::quote($list->{'name'}), 
    &Sympa::SDM::quote($robot)
    )) {
	&Sympa::Log::do_log('err','Unable to transfer stats from list %s@%s to list %s@%s',$param{'new_listname'}, $param{'new_robot'}, $list->{'name'}, $robot);
    }

     ## Move stat counters
    unless (&Sympa::SDM::do_query("UPDATE stat_counter_table SET list_counter=%s, robot_counter=%s WHERE (list_counter = %s AND robot_counter = %s )", 
    &Sympa::SDM::quote($param{'new_listname'}), 
    &Sympa::SDM::quote($param{'new_robot'}), 
    &Sympa::SDM::quote($list->{'name'}), 
    &Sympa::SDM::quote($robot)
    )) {
	&Sympa::Log::do_log('err','Unable to transfer stat counter from list %s@%s to list %s@%s',$param{'new_listname'}, $param{'new_robot'}, $list->{'name'}, $robot);
    }

     ## Install new aliases
     $param{'listname'} = $param{'new_listname'};
     
     unless ($list = new Sympa::List ($param{'new_listname'}, $param{'new_robot'},{'reload_config' => 1})) {
	 &Sympa::Log::do_log('err',"Unable to load $param{'new_listname'} while renaming");
	 return 'internal';
     }
     
     ## Check custom_subject
     if (defined $list->{'admin'}{'custom_subject'} &&
	 $list->{'admin'}{'custom_subject'} =~ /$old_listname/) {
	 $list->{'admin'}{'custom_subject'} =~ s/$old_listname/$param{'new_listname'}/g;

	 $list->save_config($param{'user_email'});	
     }

     if ($list->{'admin'}{'status'} eq 'open') {
      	 $param{'aliases'} = &install_aliases($list,$robot);
     } 
     
     unless ($param{'mode'} eq 'copy') {

	 ## Rename files in spools
	 ## Auth & Mod  spools
	 foreach my $spool ('queueauth','queuemod','queuetask','queuebounce',
			'queue','queueoutgoing','queuesubscribe','queueautomatic') {
	     unless (opendir(DIR, $Sympa::Configuration::Conf{$spool})) {
		 &Sympa::Log::do_log('err', "Unable to open '%s' spool : %s", $Sympa::Configuration::Conf{$spool}, $!);
	     }
	     
	     foreach my $file (sort readdir(DIR)) {
		 next unless ($file =~ /^$old_listname\_/ ||
			      $file =~ /^$old_listname\./ ||
			      $file =~ /^$old_listname\@$robot\./ ||
			      $file =~ /^\.$old_listname\@$robot\_/ ||
			      $file =~ /^$old_listname\@$robot\_/ ||
			      $file =~ /\.$old_listname$/);
		 
		 my $newfile = $file;
		 if ($file =~ /^$old_listname\_/) {
		     $newfile =~ s/^$old_listname\_/$param{'new_listname'}\_/;
		 }elsif ($file =~ /^$old_listname\./) {
		     $newfile =~ s/^$old_listname\./$param{'new_listname'}\./;
		 }elsif ($file =~ /^$old_listname\@$robot\./) {
		     $newfile =~ s/^$old_listname\@$robot\./$param{'new_listname'}\@$param{'new_robot'}\./;
		 }elsif ($file =~ /^$old_listname\@$robot\_/) {
		     $newfile =~ s/^$old_listname\@$robot\_/$param{'new_listname'}\@$param{'new_robot'}\_/;
		 }elsif ($file =~ /^\.$old_listname\@$robot\_/) {
		     $newfile =~ s/^\.$old_listname\@$robot\_/\.$param{'new_listname'}\@$param{'new_robot'}\_/;
		 }elsif ($file =~ /\.$old_listname$/) {
		     $newfile =~ s/\.$old_listname$/\.$param{'new_listname'}/;
		 }
		 
		 ## Rename file
		 unless (move "$Sympa::Configuration::Conf{$spool}/$file", "$Sympa::Configuration::Conf{$spool}/$newfile") {
		     &Sympa::Log::do_log('err', "Unable to rename %s to %s : %s", "$Sympa::Configuration::Conf{$spool}/$newfile", "$Sympa::Configuration::Conf{$spool}/$newfile", $!);
		     next;
		 }
		 
		 ## Change X-Sympa-To
		 &Sympa::Tools::change_x_sympa_to("$Sympa::Configuration::Conf{$spool}/$newfile", "$param{'new_listname'}\@$param{'new_robot'}");
	     }
	     
	     close DIR;
	 } 
	 ## Digest spool
	 if (-f "$Sympa::Configuration::Conf{'queuedigest'}/$old_listname") {
	     unless (move "$Sympa::Configuration::Conf{'queuedigest'}/$old_listname", "$Sympa::Configuration::Conf{'queuedigest'}/$param{'new_listname'}") {
		 &Sympa::Log::do_log('err', "Unable to rename %s to %s : %s", "$Sympa::Configuration::Conf{'queuedigest'}/$old_listname", "$Sympa::Configuration::Conf{'queuedigest'}/$param{'new_listname'}", $!);
		 next;
	     }
	 }elsif (-f "$Sympa::Configuration::Conf{'queuedigest'}/$old_listname\@$robot") {
	     unless (move "$Sympa::Configuration::Conf{'queuedigest'}/$old_listname\@$robot", "$Sympa::Configuration::Conf{'queuedigest'}/$param{'new_listname'}\@$param{'new_robot'}") {
		 &Sympa::Log::do_log('err', "Unable to rename %s to %s : %s", "$Sympa::Configuration::Conf{'queuedigest'}/$old_listname\@$robot", "$Sympa::Configuration::Conf{'queuedigest'}/$param{'new_listname'}\@$param{'new_robot'}", $!);
		 next;
	     }
	 }     
     }

    return 1;
  }

=head2 clone_list_as_empty($source_list_name, $source_robot, $new_listname,
$new_robot, $email)

Clone a list config including customization, templates, scenario config
but without archives, subscribers and shared

=head3 Parameters

=over

=item * I<$source_list_name>: the list to clone

=item * I<$source_robot>: robot of the list to clone

=item * I<$new_listname>: the target list name         

=item * I<$new_robot>: the target list robot

=item * I<$email>: the email of the requestor : used in config as
admin->last_update->email         

=back

=head3 Return value

The updated L<Sympa::List> object.

=cut

sub clone_list_as_empty {
    
    my $source_list_name =shift;
    my $source_robot =shift;
    my $new_listname = shift;
    my $new_robot = shift;
    my $email = shift;

    my $list;
    unless ($list = new Sympa::List ($source_list_name, $source_robot)) {
	&Sympa::Log::do_log('err','Admin::clone_list_as_empty : new list failed %s %s',$source_list_name, $source_robot);
	return undef;;
    }    
    
    &Sympa::Log::do_log('info',"Admin::clone_list_as_empty ($source_list_name, $source_robot,$new_listname,$new_robot,$email)");
    
    my $new_dir;
    if (-d $Sympa::Configuration::Conf{'home'}.'/'.$new_robot) {
	$new_dir = $Sympa::Configuration::Conf{'home'}.'/'.$new_robot.'/'.$new_listname;
    }elsif ($new_robot eq $Sympa::Configuration::Conf{'domain'}) {
	$new_dir = $Sympa::Configuration::Conf{'home'}.'/'.$new_listname;
    }else {
	&Sympa::Log::do_log('err',"Admin::clone_list_as_empty : unknown robot $new_robot");
	return undef;
    }
    
    unless (mkdir $new_dir, 0775) {
	&Sympa::Log::do_log('err','Admin::clone_list_as_empty : failed to create directory %s : %s',$new_dir, $!);
	return undef;;
    }
    chmod 0775, $new_dir;
    foreach my $subdir ('etc','web_tt2','mail_tt2','data_sources' ) {
	if (-d $new_dir.'/'.$subdir) {
	    unless (&Sympa::Tools::File::copy_dir($list->{'dir'}.'/'.$subdir, $new_dir.'/'.$subdir)) {
		&Sympa::Log::do_log('err','Admin::clone_list_as_empty :  failed to copy_directory %s : %s',$new_dir.'/'.$subdir, $!);
		return undef;
	    }
	}
    }
    # copy mandatory files
    foreach my $file ('config') {
	    unless (&File::Copy::copy ($list->{'dir'}.'/'.$file, $new_dir.'/'.$file)) {
		&Sympa::Log::do_log('err','Admin::clone_list_as_empty : failed to copy %s : %s',$new_dir.'/'.$file, $!);
		return undef;
	    }
    }
    # copy optional files
    foreach my $file ('message.footer','message.header','info','homepage') {
	if (-f $list->{'dir'}.'/'.$file) {
	    unless (&File::Copy::copy ($list->{'dir'}.'/'.$file, $new_dir.'/'.$file)) {
		&Sympa::Log::do_log('err','Admin::clone_list_as_empty : failed to copy %s : %s',$new_dir.'/'.$file, $!);
		return undef;
	    }
	}
    }

    my $new_list;
    # now switch List object to new list, update some values
    unless ($new_list = new Sympa::List ($new_listname, $new_robot,{'reload_config' => 1})) {
	&Sympa::Log::do_log('info',"Admin::clone_list_as_empty : unable to load $new_listname while renamming");
	return undef;
    }
    $new_list->{'admin'}{'serial'} = 0 ;
    $new_list->{'admin'}{'creation'}{'email'} = $email if ($email);
    $new_list->{'admin'}{'creation'}{'date_epoch'} = time;
    $new_list->{'admin'}{'creation'}{'date'} = Sympa::Language::gettext_strftime "%d %b %y at %H:%M:%S", localtime(time);
    $new_list->save_config($email);
    return $new_list;
}


=head2 check_owner_defined($owner,$owner_include)

Verify if they are any owner defined : it must exist at least one param
owner(in I<$owner>) or one param owner_include (in I<$owner_include>) the owner
param must have sub param email the owner_include param must have sub param
source

=head3 Parameters

=over

=item I<$owner>: arrayref of hashes or hashref

=item I<$owner_include>: arrayref of hashes

=back

=head3 Return value

A true value if the owner exists, I<undef> otherwise.

=cut

sub check_owner_defined {
    my ($owner,$owner_include) = @_;
    &Sympa::Log::do_log('debug2',"%s::check_owner_defined()", __PACKAGE__);
    
    if (ref($owner) eq "ARRAY") {
	if (ref($owner_include) eq "ARRAY") {
	    if (($#{$owner} < 0) && ($#{$owner_include} <0)) {
		&Sympa::Log::do_log('err','missing list param owner or owner_include');
		return undef;
	    }
	} else {
	    if (($#{$owner} < 0) && !($owner_include)) {
		&Sympa::Log::do_log('err','missing list param owner or owner_include');
		return undef;
	    }
	}
    } else {
	if (ref($owner_include) eq "ARRAY") {
	    if (!($owner) && ($#{$owner_include} <0)) {
		&Sympa::Log::do_log('err','missing list param owner or owner_include');
		return undef;
	    }
	}else {
	    if (!($owner) && !($owner_include)) {
		&Sympa::Log::do_log('err','missing list param owner or owner_include');
		return undef;
	    }
	}
    }
    
    if (ref($owner) eq "ARRAY") {
	foreach my $o (@{$owner}) {
	    unless($o){ 
		&Sympa::Log::do_log('err','empty param "owner"');
		return undef;
	    }
	    unless ($o->{'email'}) {
		&Sympa::Log::do_log('err','missing sub param "email" for param "owner"');
		return undef;
	    }
	}
    } elsif (ref($owner) eq "HASH"){
	unless ($owner->{'email'}) {
	    &Sympa::Log::do_log('err','missing sub param "email" for param "owner"');
	    return undef;
	}
    } elsif (defined $owner) {
	&Sympa::Log::do_log('err','missing sub param "email" for param "owner"');
	return undef;
    }	
    
    if (ref($owner_include) eq "ARRAY") {
	foreach my $o (@{$owner_include}) {
	    unless($o){ 
		&Sympa::Log::do_log('err','empty param "owner_include"');
		return undef;
	    }
	    unless ($o->{'source'}) {
		&Sympa::Log::do_log('err','missing sub param "source" for param "owner_include"');
		return undef;
	    }
	} 
    }elsif (ref($owner_include) eq "HASH"){
	unless ($owner_include->{'source'}) {
	    &Sympa::Log::do_log('err','missing sub param "source" for param "owner_include"');
	    return undef;
	}
    } elsif (defined $owner_include) {
	&Sympa::Log::do_log('err','missing sub param "source" for param "owner_include"');
	return undef;
    }	
    return 1;
}


=head2 list_check_smtp($list, $robot)

Check if the requested list exists already using smtp 'rcpt to'

=head3 Parameters

=over

=item * I<$list>: list name

=item * I<$robot>: list robot

=back

=head3 Return value

Net::SMTP object or 0 

=cut

 sub list_check_smtp {
     my $list = shift;
     my $robot = shift;
     &Sympa::Log::do_log('debug2', '%s::list_check_smtp(%s,%s)',__PACKAGE__,$list,$robot);

     my $conf = '';
     my $smtp;
     my (@suf, @addresses);

     my $smtp_relay = &Sympa::Configuration::get_robot_conf($robot, 'list_check_smtp');
     my $smtp_helo = &Sympa::Configuration::get_robot_conf($robot, 'list_check_helo') || $smtp_relay;
     $smtp_helo =~ s/:[-\w]+$//;
     my $suffixes = &Sympa::Configuration::get_robot_conf($robot, 'list_check_suffixes');
     return 0 
	 unless ($smtp_relay && $suffixes);
     my $domain = &Sympa::Configuration::get_robot_conf($robot, 'host');
     &Sympa::Log::do_log('debug2', 'list_check_smtp(%s,%s)', $list, $robot);
     @suf = split(/,/,$suffixes);
     return 0 if ! @suf;
     for(@suf) {
	 push @addresses, $list."-$_\@".$domain;
     }
     push @addresses,"$list\@" . $domain;

     eval {
         require Net::SMTP;
     };
     if ($@) {
	 &Sympa::Log::do_log ('err',"%s::list_check_smtp : Unable to use Net library, Net::SMTP required, install it (CPAN) first", __PACKAGE__);
	 return undef;
     }
     if( $smtp = Net::SMTP->new($smtp_relay,
				Hello => $smtp_helo,
				Timeout => 30) ) {
	 $smtp->mail('');
	 for(@addresses) {
		 $conf = $smtp->to($_);
		 last if $conf;
	 }
	 $smtp->quit();
	 return $conf;
    }
    return undef;
 }

=head2 install_aliases($list, $robot)

Install sendmail aliases for I<$list>.

=head3 Parameters

=over

=item * I<$list>: list 

=item * I<$robot>: list robot

=back

=head3 Return value

A true value if the alias have been installed, I<undef> otherwise.

=cut

sub install_aliases {
    my $list = shift;
    my $robot = shift;
    &Sympa::Log::do_log('debug', "%s::install_aliases($list->{'name'},__PACKAGE__,$robot)");

    return 1
	if ($Sympa::Configuration::Conf{'sendmail_aliases'} =~ /^none$/i);

    my $alias_manager = $Sympa::Configuration::Conf{'alias_manager' };
    my $output_file = $Sympa::Configuration::Conf{'tmpdir'}.'/aliasmanager.stdout.'.$$;
    my $error_output_file = $Sympa::Configuration::Conf{'tmpdir'}.'/aliasmanager.stderr.'.$$;
    &Sympa::Log::do_log('debug2',"%s::install_aliases : $alias_manager add $list->{'name'} $list->{'admin'}{'host'}", __PACKAGE__);
 
    unless (-x $alias_manager) {
		&Sympa::Log::do_log('err','%s::install_aliases : Failed to install aliases: %s', __PACKAGE__, $!);
		return undef;
	}
	 system ("$alias_manager add $list->{'name'} $list->{'admin'}{'host'} >$output_file 2>  $error_output_file") ;
	 my $status = $? / 256;
	 if ($status == 0) {
	     &Sympa::Log::do_log('info','%s::install_aliases : Aliases installed successfully', __PACKAGE__) ;
	     return 1;
     }

	## get error code
	my $error_output;
	open ERR, $error_output_file;
	while (<ERR>) {
		$error_output .= $_;
	}
	close ERR;
	unlink $error_output_file;

     if ($status == 1) {
		&Sympa::Log::do_log('err','Configuration file %s has errors : %s', Sympa::Constants::CONFIG, $error_output);
     }elsif ($status == 2)  {
         &Sympa::Log::do_log('err','%s::install_aliases : Internal error : Incorrect call to alias_manager : %s', __PACKAGE__, $error_output);
     }elsif ($status == 3)  {
	     &Sympa::Log::do_log('err','%s::install_aliases : Could not read sympa config file, report to httpd error_log: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 4)  {
	     &Sympa::Log::do_log('err','%s::install_aliases : Could not get default domain, report to httpd error_log: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 5)  {
	     &Sympa::Log::do_log('err','%s::install_aliases : Unable to append to alias file: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 6)  {
	     &Sympa::Log::do_log('err','%s::install_aliases : Unable to run newaliases: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 7)  {
	     &Sympa::Log::do_log('err','%s::install_aliases : Unable to read alias file, report to httpd error_log: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 8)  {
	     &Sympa::Log::do_log('err','%s::install_aliases : Could not create temporay file, report to httpd error_log: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 13) {
	     &Sympa::Log::do_log('info','%s::install_aliases : Some of list aliases already exist: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 14) {
	     &Sympa::Log::do_log('err','%s::install_aliases : Can not open lock file, report to httpd error_log: %s', __PACKAGE__, $error_output) ;
	 }elsif ($status == 15) {
	     &Sympa::Log::do_log('err','The parser returned empty aliases: %s', $error_output) ;
	 }else {
	     &Sympa::Log::do_log('err',"%s::install_aliases : Unknown error $status while running alias manager $alias_manager : %s", __PACKAGE__, $error_output);
	 } 
    
    return undef;
}


=head2 remove_aliases($list, $robot)

Remove sendmail aliases for I<$list>.

=head3 Parameters

=over

=item * I<$list>: list 

=item * I<$robot>: list robot

=back

=head3 Return value

I<1> in case of success, the aliases definition as a string otherwise.

=cut

 sub remove_aliases {
     my $list = shift;
     my $robot = shift;
     &Sympa::Log::do_log('info', "_remove_aliases($list->{'name'},$robot");

    return 1
	if ($Sympa::Configuration::Conf{'sendmail_aliases'} =~ /^none$/i);

     my $status = $list->remove_aliases();
     my $suffix = &Sympa::Configuration::get_robot_conf($robot, 'return_path_suffix');
     my $aliases;

     unless ($status == 1) {
	 &Sympa::Log::do_log('err','Failed to remove aliases for list %s', $list->{'name'});

	 ## build a list of required aliases the listmaster should install
     my $libexecdir = Sympa::Constants::LIBEXECDIR;
	 $aliases = <<EOF;
#----------------- $list->{'name'}
$list->{'name'}: "$libexecdir/queue $list->{'name'}"
$list->{'name'}-request: "|$libexecdir/queue $list->{'name'}-request"
$list->{'name'}$suffix: "|$libexecdir/bouncequeue $list->{'name'}"
$list->{'name'}-unsubscribe: "|$libexecdir/queue $list->{'name'}-unsubscribe"
# $list->{'name'}-subscribe: "|$libexecdir/queue $list->{'name'}-subscribe"
EOF
	 
	 return $aliases;
     }

     &Sympa::Log::do_log('info','Aliases removed successfully');

     return 1;
 }

=head2 check_topics($topic, $robot)

Check $topic in the $robot conf

=head3 Parameters

=over

=item * I<$topic>: topic id

=item * I<$robot>: the list robot

=back

=head3 Return value

A true value if the topic is in the robot conf, I<undef> otherwise.

=cut

sub check_topics {
    my $topic = shift;
    my $robot = shift;
    &Sympa::Log::do_log('info', "%s::check_topics($topic,$robot)", __PACKAGE__);

    my ($top, $subtop) = split /\//, $topic;

    my %topics;
    unless (%topics = &Sympa::List::load_topics($robot)) {
	&Sympa::Log::do_log('err','%s::check_topics : unable to load list of topics', __PACKAGE__);
    }

    if ($subtop) {
	return 1 if (defined $topics{$top} && defined $topics{$top}{'sub'}{$subtop});
    }else {
	return 1 if (defined $topics{$top});
    }

    return undef;
}

=head2 change_user_email(%parameters)

Change a user email address for both his memberships and ownerships.

=head3 Parameters

=over

=item * I<current_email>: current user email address

=item * I<new_email>: new user email address

=item * I<$robot>: virtual robot

=back

=head3 Return value

I<1>, and the list of lists for which the changes could not be achieved.

=cut

sub change_user_email {
    my %in = @_;

    my @failed_for;

    unless ($in{'current_email'} && $in{'new_email'} && $in{'robot'}) {
	&Sympa::Log::do_log('err','Missing incoming parameter');
	return undef;
    }

    ## Change email as list MEMBER
    foreach my $list ( &Sympa::List::get_which($in{'current_email'},$in{'robot'}, 'member') ) {
	 
	 my $l = $list->{'name'};
	 
	 my $user_entry = $list->get_list_member($in{'current_email'});
	 
	 if ($user_entry->{'included'} == 1) {
	     ## Check the type of data sources
	     ## If only include_list of local mailing lists, then no problem
	     ## Otherwise, notify list owner
	     ## We could also force a sync_include for local lists
	     my $use_external_data_sources;
	     foreach my $datasource_id (split(/,/, $user_entry->{'id'})) {
		 my $datasource = $list->search_datasource($datasource_id);
		 if (!defined $datasource || $datasource->{'type'} ne 'include_list' || ($datasource->{'def'} =~ /\@(.+)$/ && $1 ne $in{'robot'})) {
		     $use_external_data_sources = 1;
		     last;
		 }
	     }
	     if ($use_external_data_sources) {
		 ## Notify list owner
		 $list->send_notify_to_owner('failed_to_change_included_member',
					     {'current_email' => $in{'current_email'}, 
					      'new_email' => $in{'new_email'},
					      'datasource' => $list->get_datasource_name($user_entry->{'id'})});
		 push @failed_for, $list;
		 &Sympa::Log::do_log('err', 'could not change member email for list %s because member is included', $l);
		 next;
	     }
	 }

	 ## Check if user is already member of the list with his new address
	 ## then we just need to remove the old address
	 if ($list->is_list_member($in{'new_email'})) {
	     unless ($list->delete_list_member('users' => [$in{'current_email'}]) ) {
		 push @failed_for, $list;
		 &Sympa::Log::do_log('info', 'could not remove email from list %s', $l);		 
	     }
	     
	 }else {
	     
	     unless ($list->update_list_member($in{'current_email'}, {'email' => $in{'new_email'}, 'update_date' => time}) ) {
		 push @failed_for, $list;
		 &Sympa::Log::do_log('err', 'could not change email for list %s', $l);
	     }
	 }
     }
    
    ## Change email as list OWNER/MODERATOR
    my %updated_lists;
    foreach my $role ('owner', 'editor') { 
	foreach my $list ( &Sympa::List::get_which($in{'current_email'},$in{'robot'}, $role) ) {
	    
	    ## Check if admin is include via an external datasource
	    my $admin_user = $list->get_list_admin($role, $in{'current_email'});
	    if ($admin_user->{'included'}) {
		## Notify listmaster
		&Sympa::List::send_notify_to_listmaster('failed_to_change_included_admin',$in{'robot'},{'list' => $list,
											   'current_email' => $in{'current_email'}, 
											   'new_email' => $in{'new_email'},
											   'datasource' => $list->get_datasource_name($admin_user->{'id'})});
		push @failed_for, $list;
		&Sympa::Log::do_log('err', 'could not change %s email for list %s because admin is included', $role, $list->{'name'});
		next;
	    }
	    
	    ## Go through owners/editors of the list
	    foreach my $admin (@{$list->{'admin'}{$role}}) {
		next unless (lc($admin->{'email'}) eq lc($in{'current_email'}));
		
		## Update entry with new email address
		$admin->{'email'} = $in{'new_email'};
		$updated_lists{$list->{'name'}}++;
	    }
	    
	    ## Update Db cache for the list
	    $list->sync_include_admin();
	    $list->save_config();
	}
    }
    ## Notify listmasters that list owners/moderators email have changed
    if (keys %updated_lists) {
	&Sympa::List::send_notify_to_listmaster('listowner_email_changed',$in{'robot'}, 
					 {'previous_email' => $in{'current_email'},
					  'new_email' => $in{'new_email'},
					  'updated_lists' => keys %updated_lists})
    }
    
    ## Update User_table and remove existing entry first (to avoid duplicate entries)
    &Sympa::List::delete_global_user($in{'new_email'},);
    
    unless ( &Sympa::List::update_global_user($in{'current_email'},
				       {'email' => $in{'new_email'},					
				       })) {
	&Sympa::Log::do_log('err','change_email: update failed');
	return undef;
    }
    
    ## Update netidmap_table
    unless ( &Sympa::List::update_email_netidmap_db($in{'robot'}, $in{'current_email'}, $in{'new_email'}) ){
	&Sympa::Log::do_log('err','change_email: update failed');
	return undef;
    }
    
    
    return (1,\@failed_for);
}

=head1 AUTHORS 

=over 

=item * Serge Aumont <sa AT cru.fr> 

=item * Olivier Salaun <os AT cru.fr> 

=back 

=cut 

1;
