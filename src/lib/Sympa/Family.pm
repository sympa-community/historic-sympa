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

Sympa::Family - List family class

=head1 DESCRIPTION

This class implements a list family, a set of lists sharing common properties.

=cut

package Sympa::Family;

use strict;

use File::Copy;
use Term::ProgressBar;
use XML::LibXML;

use Sympa::Admin;
use Sympa::Configuration;
use Sympa::Configuration::XML;
use Sympa::Constants;
use Sympa::Language;
use Sympa::List;
use Sympa::Log;
use Sympa::Scenario;

my %list_of_families;
my @uncompellable_param = ('msg_topic.keywords','owner_include.source_parameters', 'editor_include.source_parameters');

=head1 FUNCTIONS

=head2 get_available_families($robot)

Returns the list of existing families in the Sympa installation.

=head3 Parameters

=over 

=item * I<$robot>: the name of the robot the family list of which we want to
get

=back 

=head3 Return 

An array  containing all the robot's families names.

=cut

sub get_available_families {
    my $robot = shift;

    my %families;

    foreach my $dir (
        Sympa::Constants::DEFAULTDIR . "/families",
        $Sympa::Configuration::Conf{'etc'}           . "/families",
        $Sympa::Configuration::Conf{'etc'}           . "/$robot/families"
     ) {
	next unless (-d $dir);

	unless (opendir FAMILIES, $dir) {
	    &Sympa::Log::do_log ('err', "error : can't open dir %s: %s", $dir, $!);
	    next;
	}

	## If we can create a Family object with what we find in the family
	## directory, then it is worth being added to the list.
	foreach my $subdir (grep !/^\.\.?$/, readdir FAMILIES) {
	    if (my $family = new Sympa::Family($subdir, $robot)) { 
		$families{$subdir} = 1;
	    }
	}
    }
    
    return keys %families;
}

=head1 CLASS METHODS

=head2 Sympa::Family->new($name, $robot)

Creates a new L<Sympa::Family> object of name $name, belonging to the robot
$robot.

=head3 Parameters

=over

=item * I<$name>: the family name

=item * I<$robot>: the robot which the family is/will be installed in

=back

=head3 Return value

A new L<Sympa::Family> object.

=cut

sub new {
    my $class = shift;
    my $name = shift;
    my $robot = shift;
    &Sympa::Log::do_log('debug2','%s::new(%s,%s)',__PACKAGE__,$name,$robot);
    
    my $self = {};

    
    if ($list_of_families{$robot}{$name}) {
        # use the current family in memory and update it
	$self = $list_of_families{$robot}{$name};
###########
	# the robot can be different from latest new ...
	if ($robot eq $self->{'robot'}) {
	    return $self;
	}else {
	    $self = {};
	}
    }
    # create a new object family
    bless $self, $class;
    $list_of_families{$robot}{$name} = $self;

    my $family_name_regexp = &Sympa::Tools::get_regexp('family_name');

    ## family name
    unless ($name && ($name =~ /^$family_name_regexp$/io) ) {
	&Sympa::Log::do_log('err', 'Incorrect family name "%s"',  $name);
	return undef;
    }

    ## Lowercase the family name.
    $name =~ tr/A-Z/a-z/;
    $self->{'name'} = $name;

    $self->{'robot'} = $robot;

    ## Adding configuration related to automatic lists.
    my $all_families_config = &Sympa::Configuration::get_robot_conf($robot,'automatic_list_families');
    my $family_config = $all_families_config->{$name};
    foreach my $key (keys %{$family_config}) {
	$self->{$key} = $family_config->{$key};
    }

    ## family directory
    $self->{'dir'} = $self->_get_directory();
    unless (defined $self->{'dir'}) {
	&Sympa::Log::do_log('err','%s::new(%s,%s) : the family directory does not exist',__PACKAGE__,$name,$robot);
	return undef;
    }

    ## family files
    if (my $file_names = $self->_check_mandatory_files()) {
	&Sympa::Log::do_log('err','%s::new(%s,%s) : Definition family files are missing : %s',__PACKAGE__,$name,$robot,$file_names);
	return undef;
    }

    ## file mtime
    $self->{'mtime'}{'param_constraint_conf'} = undef;
    
    ## hash of parameters constraint
    $self->{'param_constraint_conf'} = undef;

    ## state of the family for the use of check_param_constraint : 'no_check' or 'normal'
    ## check_param_constraint  only works in state "normal"
    $self->{'state'} = 'normal';
    return $self;
}

=head1 INSTANCE METHODS

=head2 $family->add_list($data, $abort_on_error)

Adds a list to the family. List description can be passed either through a hash of data or through a file handle.

=head3 Parameters

=over

=item * I<$data>: a file handle on an XML B<list> description file or a hash of data

=item * I<$abort_on_error>: if true, the function won't create lists in status error_config

=back

=head3 Return value

An hash containing the execution state of the method. If everything went well,
the "ok" key must be associated to the value "1".

=cut

sub add_list {
    my ($self, $data, $abort_on_error) = @_;

    &Sympa::Log::do_log('info','%s::add_list(%s)',__PACKAGE__,$self->{'name'});

    $self->{'state'} = 'no_check';
    my $return;
    $return->{'ok'} = undef;
    $return->{'string_info'} = undef; ## info and simple errors
    $return->{'string_error'} = undef; ## fatal errors

    my $hash_list;

    if (ref($data) eq "HASH") {
        $hash_list = {config=>$data};
    } else {
	#copy the xml file in another file
	unless (open (FIC, '>', "$self->{'dir'}/_new_list.xml")) {
	    &Sympa::Log::do_log('err','%s::add_list(%s) : impossible to create the temp file %s/_new_list.xml : %s',__PACKAGE__,$self->{'name'},$self->{'dir'},$!);
	}
	while (<$data>) {
	    print FIC ($_);
	}
	close FIC;
	
	# get list data
	open (FIC, '<:raw', "$self->{'dir'}/_new_list.xml");
	my $config = new Sympa::Configuration::XML(\*FIC);
	close FIC;
	unless (defined $config->createHash()) {
	    push @{$return->{'string_error'}}, "Error in representation data with these xml data";
	    return $return;
	} 
	
	$hash_list = $config->getHash();
    }
 
    #list creation
    my $result = &Sympa::Admin::create_list($hash_list->{'config'},$self,$self->{'robot'}, $abort_on_error);
    unless (defined $result) {
	push @{$return->{'string_error'}}, "Error during list creation, see logs for more information";
	return $return;
    }
    unless (defined $result->{'list'}) {
	push @{$return->{'string_error'}}, "Errors : no created list, see logs for more information";
	return $return;
    }
    my $list = $result->{'list'};
	    
    ## aliases
    if ($result->{'aliases'} == 1) {
	push @{$return->{'string_info'}}, "List $list->{'name'} has been created in $self->{'name'} family";
    }else {
	push @{$return->{'string_info'}}, "List $list->{'name'} has been created in $self->{'name'} family, required aliases : $result->{'aliases'} ";
    }
	    
    # config_changes
    unless (open FILE, '>', "$list->{'dir'}/config_changes") {
	$list->set_status_error_config('error_copy_file',$list->{'name'},$self->{'name'});
	push @{$return->{'string_info'}}, "Impossible to create file $list->{'dir'}/config_changes : $!, the list is set in status error_config";
    }
    close FILE;
 
    my $host = &Sympa::Configuration::get_robot_conf($self->{'robot'}, 'host');

    # info parameters
    $list->{'admin'}{'latest_instantiation'}{'email'} = "listmaster\@$host";
    $list->{'admin'}{'latest_instantiation'}{'date'} = gettext_strftime "%d %b %Y at %H:%M:%S", localtime(time);
    $list->{'admin'}{'latest_instantiation'}{'date_epoch'} = time;
    $list->save_config("listmaster\@$host");
    $list->{'family'} = $self;
    
    ## check param_constraint.conf 
    $self->{'state'} = 'normal';
    my $error = $self->check_param_constraint($list);
    $self->{'state'} = 'no_check';
    
    unless (defined $error) {
	$list->set_status_error_config('no_check_rules_family',$list->{'name'},$self->{'name'});
	push @{$return->{'string_error'}}, "Impossible to check parameters constraint, see logs for more information. The list is set in status error_config";
	return $return;
    }
    
    if (ref($error) eq 'ARRAY') {
	$list->set_status_error_config('no_respect_rules_family',$list->{'name'},$self->{'name'});
	push @{$return->{'string_info'}}, "The list does not respect the family rules : ".join(", ",@{$error});
    }
    
    ## copy files in the list directory : xml file
    unless ( ref($data) eq "HASH" ) {
    unless ($self->_copy_files($list->{'dir'},"_new_list.xml")) {
	$list->set_status_error_config('error_copy_file',$list->{'name'},$self->{'name'});
	push @{$return->{'string_info'}}, "Impossible to copy the xml file in the list directory, the list is set in status error_config.";
    }
    }

    ## Synchronize list members if required
    if ($list->has_include_data_sources()) {
	&Sympa::Log::do_log('notice', "Synchronizing list members...");
	$list->sync_include();
    }

    ## END
    $self->{'state'} = 'normal';
    $return->{'ok'} = 1;

    return $return;
}

=head2 $family->modify_list($fh)

Adds a list to the family.

=head3 Parameters

=over

=item * I<$fh>: a file handle on the XML B<list> configuration file

=back

=head3 Return value

An hash containing the execution state of the method. If everything went well,
the "ok" key must be associated to the value "1".

=cut

sub modify_list {
    my $self = shift;
    my $fh = shift;
    &Sympa::Log::do_log('info','%s::modify_list(%s)',__PACKAGE__,$self->{'name'});

    $self->{'state'} = 'no_check';
    my $return;
    $return->{'ok'} = undef;
    $return->{'string_info'} = undef; ## info and simple errors
    $return->{'string_error'} = undef; ## fatal errors

    #copy the xml file in another file
    unless (open (FIC, '>', "$self->{'dir'}/_mod_list.xml")) {
	&Sympa::Log::do_log('err','%s::modify_list(%s) : impossible to create the temp file %s/_mod_list.xml : %s',__PACKAGE__,$self->{'name'},$self->{'dir'},$!);
    }
    while (<$fh>) {
	print FIC ($_);
    }
    close FIC;

    # get list data
    open (FIC, '<:raw', "$self->{'dir'}/_mod_list.xml");
    my $config = new Sympa::Configuration::XML(\*FIC);
    close FIC;
    unless (defined $config->createHash()) {
	push @{$return->{'string_error'}}, "Error in representation data with these xml data";
	return $return;
    } 

    my $hash_list = $config->getHash();

    #getting list
    my $list;
    unless ($list = new Sympa::List($hash_list->{'config'}{'listname'}, $self->{'robot'})) {
	push @{$return->{'string_error'}}, "The list $hash_list->{'config'}{'listname'} does not exist.";
	return $return;
    }
    
    ## check family name
    if (defined $list->{'admin'}{'family_name'}) {
	unless ($list->{'admin'}{'family_name'} eq $self->{'name'}) {
	  push @{$return->{'string_error'}}, "The list $list->{'name'} already belongs to family $list->{'admin'}{'family_name'}.";
	  return $return;
	} 
    } else {
	push @{$return->{'string_error'}}, "The orphan list $list->{'name'} already exists.";
	return $return;
    }

    ## get allowed and forbidden list customizing
    my $custom = $self->_get_customizing($list);
    unless (defined $custom) {
	&Sympa::Log::do_log('err','impossible to get list %s customizing',$list->{'name'});
	push @{$return->{'string_error'}}, "Error during updating list $list->{'name'}, the list is set in status error_config."; 
	$list->set_status_error_config('modify_list_family',$list->{'name'},$self->{'name'});
	return $return;
    }
    my $config_changes = $custom->{'config_changes'}; 
    my $old_status = $list->{'admin'}{'status'};

    ## list config family updating
    my $result = &Sympa::Admin::update_list($list,$hash_list->{'config'},$self,$self->{'robot'});
    unless (defined $result) {
	&Sympa::Log::do_log('err','No object list resulting from updating list %s',$list->{'name'});
	push @{$return->{'string_error'}}, "Error during updating list $list->{'name'}, the list is set in status error_config."; 
	$list->set_status_error_config('modify_list_family',$list->{'name'},$self->{'name'});
	return $return;
    }
    $list = $result;
 
    ## set list customizing
    foreach my $p (keys %{$custom->{'allowed'}}) {
	$list->{'admin'}{$p} = $custom->{'allowed'}{$p};
	delete $list->{'admin'}{'defaults'}{$p};
	&Sympa::Log::do_log('info',"Customizing : keeping values for parameter $p");
    }

    ## info file
    unless ($config_changes->{'file'}{'info'}) {
	$hash_list->{'config'}{'description'} =~ s/\r\n|\r/\n/g;
	
	unless (open INFO, '>', "$list->{'dir'}/info") {
	    push @{$return->{'string_info'}}, "Impossible to create new $list->{'dir'}/info file : $!";
	}
	print INFO $hash_list->{'config'}{'description'};
	close INFO; 
    }

    foreach my $f (keys %{$config_changes->{'file'}}) {
	&Sympa::Log::do_log('info',"Customizing : this file has been changed : $f");
    }
    
    ## rename forbidden files
#    foreach my $f (@{$custom->{'forbidden'}{'file'}}) {
#	unless (rename ("$list->{'dir'}"."/"."info","$list->{'dir'}"."/"."info.orig")) {
	    ################
#	}
#	if ($f eq 'info') {
#	    $hash_list->{'config'}{'description'} =~ s/\r\n|\r/\n/g;
#	    unless (open INFO, '>', "$list_dir/info") {
		################
#	    }
#	    print INFO $hash_list->{'config'}{'description'};
#	    close INFO; 
#	}
#    }

    ## notify owner for forbidden customizing
    if (#(scalar $custom->{'forbidden'}{'file'}) ||
	(scalar @{$custom->{'forbidden'}{'param'}})) {
#	my $forbidden_files = join(',',@{$custom->{'forbidden'}{'file'}});
	my $forbidden_param = join(',',@{$custom->{'forbidden'}{'param'}});
	&Sympa::Log::do_log('notice',"These parameters aren't allowed in the new family definition, they are erased by a new instantiation family : \n $forbidden_param");

	unless ($list->send_notify_to_owner('erase_customizing',[$self->{'name'},$forbidden_param])) {
	    &Sympa::Log::do_log('notice','the owner isn\'t informed from erased customizing of the list %s',$list->{'name'});
	}
    }

    ## status
    $result = $self->_set_status_changes($list,$old_status);

    if ($result->{'aliases'} == 1) {
	push @{$return->{'string_info'}}, "The $list->{'name'} list has been modified.";
    
    }elsif ($result->{'install_remove'} eq 'install') {
	push @{$return->{'string_info'}}, "List $list->{'name'} has been modified, required aliases :\n $result->{'aliases'} ";
	
    }else {
	push @{$return->{'string_info'}}, "List $list->{'name'} has been modified, aliases need to be removed : \n $result->{'aliases'}";
	
    }

    ## config_changes
    foreach my $p (@{$custom->{'forbidden'}{'param'}}) {

	if (defined $config_changes->{'param'}{$p}  ) {
	    delete $config_changes->{'param'}{$p};
	}

    }

    unless (open FILE, '>', "$list->{'dir'}/config_changes") {
	$list->set_status_error_config('error_copy_file',$list->{'name'},$self->{'name'});
	push @{$return->{'string_info'}}, "Impossible to create file $list->{'dir'}/config_changes : $!, the list is set in status error_config.";
    }
    close FILE;

    my @kept_param = keys %{$config_changes->{'param'}};
    $list->update_config_changes('param',\@kept_param);
    my @kept_files = keys %{$config_changes->{'file'}};
    $list->update_config_changes('file',\@kept_files);


    my $host = &Sympa::Configuration::get_robot_conf($self->{'robot'}, 'host');

    $list->{'admin'}{'latest_instantiation'}{'email'} = "listmaster\@$host";
    $list->{'admin'}{'latest_instantiation'}{'date'} = gettext_strftime "%d %b %Y at %H:%M:%S", localtime(time);
    $list->{'admin'}{'latest_instantiation'}{'date_epoch'} = time;
    $list->save_config("listmaster\@$host");
    $list->{'family'} = $self;
    
    ## check param_constraint.conf 
    $self->{'state'} = 'normal';
    my $error = $self->check_param_constraint($list);
    $self->{'state'} = 'no_check';
    
    unless (defined $error) {
	$list->set_status_error_config('no_check_rules_family',$list->{'name'},$self->{'name'});
	push @{$return->{'string_error'}}, "Impossible to check parameters constraint, see logs for more information. The list is set in status error_config";
	return $return;
    }
    
    if (ref($error) eq 'ARRAY') {
	$list->set_status_error_config('no_respect_rules_family',$list->{'name'},$self->{'name'});
	push @{$return->{'string_info'}}, "The list does not respect the family rules : ".join(", ",@{$error});
    }
    
    ## copy files in the list directory : xml file

    unless ($self->_copy_files($list->{'dir'},"_mod_list.xml")) {
	$list->set_status_error_config('error_copy_file',$list->{'name'},$self->{'name'});
	push @{$return->{'string_info'}}, "Impossible to copy the xml file in the list directory, the list is set in status error_config.";
    }

    ## Synchronize list members if required
    if ($list->has_include_data_sources()) {
	&Sympa::Log::do_log('notice', "Synchronizing list members...");
	$list->sync_include();
    }

    ## END
    $self->{'state'} = 'normal';
    $return->{'ok'} = 1;

    return $return;
}

=head2 $family->close_family()

Closes every list family.

=head3 Parameters

None.

=head3 Return value

A character string containing a message to display describing the results of
the methods.

=cut

sub close_family {
    my $self = shift;
    &Sympa::Log::do_log('info','(%s)',$self->{'name'});

    my $family_lists = $self->get_family_lists();
    my @impossible_close;
    my @close_ok;

    foreach my $list (@{$family_lists}) {
	my $listname = $list->{'name'};
	
	unless (defined $list){
	    &Sympa::Log::do_log('err','The %s list belongs to %s family but the list does not exist',$listname,$self->{'name'});
	    next;
	}
	
	unless ($list->set_status_family_closed('close_list',$self->{'name'})) {
	    push (@impossible_close,$list->{'name'});
	    next
	}
	push (@close_ok,$list->{'name'});
    }
    my $string = "\n\n******************************************************************************\n"; 
    $string .= "\n******************** CLOSURE of $self->{'name'} FAMILY ********************\n";
    $string .= "\n******************************************************************************\n\n"; 

    unless ($#impossible_close <0) {
	$string .= "\nImpossible list closure for : \n  ".join(", ",@impossible_close)."\n"; 
    }
    
    $string .= "\n****************************************\n";    

    unless ($#close_ok <0) {
	$string .= "\nThese lists are closed : \n  ".join(", ",@close_ok)."\n"; 
    }

    $string .= "\n******************************************************************************\n";
    
    return $string;
}

=head2 $family->instantiate($fh, $close_unknown)

Creates family lists or updates them if they exist already.

=head3 Parameters

=over

=item * I<$fh>: a file handle on the XML B<list> configuration file

=item * I<$close_unknown>: if true, the function will close old lists undefined in the new instantiation

=back

=head3 Return value

A true value, or I<undef> if something went wrong.

=cut

sub instantiate {
    my $self = shift;
    my $xml_file = shift;
    my $close_unknown = shift;
    &Sympa::Log::do_log('debug2','%s::instantiate(%s)',__PACKAGE__,$self->{'name'});

    ## all the description variables are emptied.
    $self->_initialize_instantiation();
    
    ## set impossible checking (used by list->load)
    $self->{'state'} = 'no_check';
	
    ## get the currently existing lists in the family
    my $previous_family_lists = $self->get_hash_family_lists();

    ## Splits the family description XML file into a set of list description xml files
    ## and collects lists to be created in $self->{'list_to_generate'}.
    unless ($self->_split_xml_file($xml_file)) {
	&Sympa::Log::do_log('err','Errors during the parsing of family xml file');
	return undef;
    }

	my $created = 0;
	my $total = $#{@{$self->{'list_to_generate'}}} + 1;
	my $progress = Term::ProgressBar->new({
		name  => 'Creating lists',
		count => $total,
		ETA   => 'linear'
	});
	$progress->max_update_rate(1);
	my $next_update = 0;
    my $aliasmanager_output_file = $Sympa::Configuration::Conf{'tmpdir'}.'/aliasmanager.stdout.'.$$;
    my $output_file = $Sympa::Configuration::Conf{'tmpdir'}.'/instantiate_family.stdout.'.$$;
	my $output = '';
                                         
    ## EACH FAMILY LIST
    foreach my $listname (@{$self->{'list_to_generate'}}) {

	my $list = new Sympa::List($listname, $self->{'robot'});
	
        ## get data from list XML file. Stored into $config (class Sympa::Configuration::XML).
	my $xml_fh;
	open $xml_fh, '<:raw', "$self->{'dir'}"."/".$listname.".xml";
	my $config = new Sympa::Configuration::XML($xml_fh);
	close $xml_fh;
	unless (defined $config->createHash()) {
	    push (@{$self->{'errors'}{'create_hash'}},"$self->{'dir'}/$listname.xml");
	    if ($list) {
 		$list->set_status_error_config('instantiation_family',$list->{'name'},$self->{'name'});
 	    }
	    next;
	} 

	## stores the list config into the hash referenced by $hash_list.
	my $hash_list = $config->getHash();

	## LIST ALREADY EXISTING
	if ($list) {

	    delete $previous_family_lists->{$list->{'name'}};

	    ## check family name
	    if (defined $list->{'admin'}{'family_name'}) {
		unless ($list->{'admin'}{'family_name'} eq $self->{'name'}) {
		    push (@{$self->{'errors'}{'listname_already_used'}},$list->{'name'});
		    &Sympa::Log::do_log('err','The list %s already belongs to family %s',$list->{'name'},$list->{'admin'}{'family_name'});
		    next;
		} 
	    } else {
		push (@{$self->{'errors'}{'listname_already_used'}},$list->{'name'});
		&Sympa::Log::do_log('err','The orphan list %s already exists',$list->{'name'});
		next;
	    }

	    ## Update list config
	    my $result = $self->_update_existing_list($list,$hash_list);
	    unless (defined $result) {
		push (@{$self->{'errors'}{'update_list'}},$list->{'name'});
		$list->set_status_error_config('instantiation_family',$list->{'name'},$self->{'name'});
		next;
	    }
	    $list = $result;
	    
	## FIRST LIST CREATION    
	} else{

	    ## Create the list
	    my $result = &Sympa::Admin::create_list($hash_list->{'config'},$self,$self->{'robot'});
	    unless (defined $result) {
		push (@{$self->{'errors'}{'create_list'}}, $hash_list->{'config'}{'listname'});
		next;
	    }
	    unless (defined $result->{'list'}) {
		push (@{$self->{'errors'}{'create_list'}}, $hash_list->{'config'}{'listname'});
		next;
	    }
	    $list = $result->{'list'};
	    
	    ## aliases
	    if ($result->{'aliases'} == 1) {
		push (@{$self->{'created_lists'}{'with_aliases'}}, $list->{'name'});
		
	    }else {
		$self->{'created_lists'}{'without_aliases'}{$list->{'name'}} = $result->{'aliases'};
	    }
	    
	    # config_changes
	    unless (open FILE, '>', "$list->{'dir'}/config_changes") {
		&Sympa::Log::do_log('err','%s::instantiate : impossible to create file %s/config_changes : %s',__PACKAGE__,$list->{'dir'},$!);
		push (@{$self->{'generated_lists'}{'file_error'}},$list->{'name'});
		$list->set_status_error_config('error_copy_file',$list->{'name'},$self->{'name'});
	    }
	    close FILE;
	}
	
	## ENDING : existing and new lists
	unless ($self->_end_update_list($list,1)) {
	    &Sympa::Log::do_log('err','Instantiation stopped on list %s',$list->{'name'});
	    return undef;
	}
		$created++;
		$progress->message(sprintf("List \"%s\" (%i/%i) created/updated", $list->{'name'}, $created, $total));
		$next_update = $progress->update($created) if($created > $next_update);
		
		if(-f $aliasmanager_output_file) {
			open OUT, $aliasmanager_output_file;
			while(<OUT>) {
				$output .= $_;
			}
			close OUT;
			unlink $aliasmanager_output_file; # remove file to catch next call
		}
    }
    
	$progress->update($total);
	
	if($output && !$main::options{'quiet'}) {
		print STDOUT "There is unread output from the instantiation proccess (aliasmanager messages ...), do you want to see it ? (y or n)";
	    my $answer = <STDIN>;
	    chomp($answer);
	    $answer ||= 'n';
	    print $output if($answer eq 'y');
	    
		if(open OUT, '>'.$output_file) {
			print OUT $output;
			close OUT;
			print STDOUT "\nOutput saved in $output_file\n";
		}else{
			print STDERR "\nUnable to save output in $output_file\n";
		}
	}

    ## PREVIOUS LIST LEFT
    foreach my $l (keys %{$previous_family_lists}) {
	my $list;
	unless ($list = new Sympa::List ($l,$self->{'robot'})) {
	    push (@{$self->{'errors'}{'previous_list'}},$l);
	    next;
	}
	
	my $answer;
	unless ($close_unknown) {
#	while (($answer ne 'y') && ($answer ne 'n')) {
	    print STDOUT "The list $l isn't defined in the new instantiation family, do you want to close it ? (y or n)";
	    $answer = <STDIN>;
	    chomp($answer);
#######################
	    $answer ||= 'y';
	#}
	}
	if ($close_unknown || $answer eq 'y'){

	    unless ($list->set_status_family_closed('close_list',$self->{'name'})) {
		push (@{$self->{'family_closed'}{'impossible'}},$list->{'name'});
	    }
	    push (@{$self->{'family_closed'}{'ok'}},$list->{'name'});
	
	} else {
	    ## get data from list xml file
	    my $xml_fh;
	    open $xml_fh, '<:raw', "$list->{'dir'}/instance.xml";
	    my $config = new Sympa::Configuration::XML($xml_fh);
	    close $xml_fh;
	    unless (defined $config->createHash()) {
		push (@{$self->{'errors'}{'create_hash'}},"$list->{'dir'}/instance.xml");
		$list->set_status_error_config('instantiation_family',$list->{'name'},$self->{'name'});
		next;
	    } 
	    my $hash_list = $config->getHash();
	    
	    my $result = $self->_update_existing_list($list,$hash_list);
	    unless (defined $result) {
		push (@{$self->{'errors'}{'update_list'}},$list->{'name'});
		$list->set_status_error_config('instantiation_family',$list->{'name'},$self->{'name'});
		next;
	    }
	    $list = $result;

	    unless ($self->_end_update_list($list,0)) {
		&Sympa::Log::do_log('err','Instantiation stopped on list %s',$list->{'name'});
		return undef;
	    }
	}
    }
    $self->{'state'} = 'normal';
    return 1;
}

=head2 $family->get_instantiation_results()

Returns a string with information summarizing the instantiation results.

=head3 Parameters

None.

=head3 Return value

A string containing a message to display.

=cut

sub get_instantiation_results {
    my ($self, $result) = @_;
    &Sympa::Log::do_log('debug3','%s::get_instantiation_results(%s)',__PACKAGE__,$self->{'name'});
 
    $result->{'errors'} = ();
    $result->{'warn'} = ();
    $result->{'info'} = ();
    my $string;

    unless ($#{$self->{'errors'}{'create_hash'}} <0) {
        push(@{$result->{'errors'}}, "\nImpossible list generation because errors in xml file for : \n  ".join(", ",@{$self->{'errors'}{'create_hash'}})."\n");    }
        
    unless ($#{$self->{'errors'}{'create_list'}} <0) {
        push(@{$result->{'errors'}}, "\nImpossible list creation for : \n  ".join(", ",@{$self->{'errors'}{'create_list'}})."\n");
    }
    
    unless ($#{$self->{'errors'}{'listname_already_used'}} <0) {
        push(@{$result->{'errors'}}, "\nImpossible list creation because listname is already used (orphelan list or in another family) for : \n  ".join(", ",@{$self->{'errors'}{'listname_already_used'}})."\n");
    }
    
    unless ($#{$self->{'errors'}{'update_list'}} <0) {
        push(@{$result->{'errors'}}, "\nImpossible list updating for : \n  ".join(", ",@{$self->{'errors'}{'update_list'}})."\n");
    }
    
    unless ($#{$self->{'errors'}{'previous_list'}} <0) {
        push(@{$result->{'errors'}}, "\nExisted lists from the lastest instantiation impossible to get and not anymore defined in the new instantiation : \n  ".join(", ",@{$self->{'errors'}{'previous_list'}})."\n");
    }
    
    # $string .= "\n****************************************\n";    
    
    unless ($#{$self->{'created_lists'}{'with_aliases'}} <0) {
       push(@{$result->{'info'}}, "\nThese lists have been created and aliases are ok :\n  ".join(", ",@{$self->{'created_lists'}{'with_aliases'}})."\n");
    }
    
    my $without_aliases =  $self->{'created_lists'}{'without_aliases'};
    if (ref $without_aliases) {
	if (scalar %{$without_aliases}) {
            $string = "\nThese lists have been created but aliases need to be installed : \n";
	    foreach my $l (keys %{$without_aliases}) {
		$string .= " $without_aliases->{$l}";
	    }
            push(@{$result->{'warn'}}, $string."\n");
	}
    }
    
    unless ($#{$self->{'updated_lists'}{'aliases_ok'}} <0) {
        push(@{$result->{'info'}}, "\nThese lists have been updated and aliases are ok :\n  ".join(", ",@{$self->{'updated_lists'}{'aliases_ok'}})."\n");
    }
    
    my $aliases_to_install =  $self->{'updated_lists'}{'aliases_to_install'};
    if (ref $aliases_to_install) {
	if (scalar %{$aliases_to_install}) {
            $string = "\nThese lists have been updated but aliases need to be installed : \n";
	    foreach my $l (keys %{$aliases_to_install}) {
		$string .= " $aliases_to_install->{$l}";
	    }
            push(@{$result->{'warn'}}, $string."\n");
	}
    }
    
    my $aliases_to_remove =  $self->{'updated_lists'}{'aliases_to_remove'};
    if (ref $aliases_to_remove) {
	if (scalar %{$aliases_to_remove}) {
            $string = "\nThese lists have been updated but aliases need to be removed : \n";
	    foreach my $l (keys %{$aliases_to_remove}) {
		$string .= " $aliases_to_remove->{$l}";
	    }
            push(@{$result->{'warn'}}, $string."\n");
	}
    }
	    
    # $string .= "\n****************************************\n";    
    
    unless ($#{$self->{'generated_lists'}{'file_error'}} <0) {
        push(@{$result->{'errors'}}, "\nThese lists have been generated but they are in status error_config because of errors while creating list config files :\n  ".join(", ",@{$self->{'generated_lists'}{'file_error'}})."\n");
    }

    my $constraint_error = $self->{'generated_lists'}{'constraint_error'};
    if (ref $constraint_error) {
	if (scalar %{$constraint_error}) {
            $string ="\nThese lists have been generated but there are in status error_config because of errors on parameter constraint :\n";
	    foreach my $l (keys %{$constraint_error}) {
		$string .= " $l : ".$constraint_error->{$l}."\n";
	    }
            push(@{$result->{'errors'}}, $string);
	}
    }

    # $string .= "\n****************************************\n";    	
    
    unless ($#{$self->{'family_closed'}{'ok'}} <0) {
        push(@{$result->{'info'}}, "\nThese lists don't belong anymore to the family, they are in status family_closed :\n  ".join(", ",@{$self->{'family_closed'}{'ok'}})."\n");
    }

    unless ($#{$self->{'family_closed'}{'impossible'}} <0){
        push(@{$result->{'warn'}}, "\nThese lists don't belong anymore to the family, but they can't be set in status family_closed :\n  ".join(", ",@{$self->{'family_closed'}{'impossible'}})."\n");
    }

    unshift @{$result->{'errors'}}, "\n********** ERRORS IN INSTANTIATION of $self->{'name'} FAMILY ********************\n"       if ($#{$result->{'errors'}} > 0);
    unshift @{$result->{'warn'}}, "\n********** WARNINGS IN INSTANTIATION of $self->{'name'} FAMILY ********************\n"       if ($#{$result->{'warn'}} > 0);
    unshift @{$result->{'info'}},
          "\n\n******************************************************************************\n"
        . "\n******************** INSTANTIATION of $self->{'name'} FAMILY ********************\n"
        . "\n******************************************************************************\n\n";

    return $#{$result->{'errors'}};

}

=head2 $family->check_param_constraint($list)

Checks the parameter constraints taken from param_constraint.conf file for the List object $list.

=head3 Parameters

=over

=item * I<$list>: the list to check (L<Sympa::List> object)

=back

=head3 Return value

=over

=item * I<1> if everything goes well,

=item * I<undef> if something goes wrong,

=item * I<\@error>, a ref on an array containing parameters conflicting with constraints.

=back

=cut

sub check_param_constraint {
    my $self = shift;
    my $list = shift;
    &Sympa::Log::do_log('debug2','%s::check_param_constraint(%s,%s)',__PACKAGE__,$self->{'name'},$list->{'name'});

    if ($self->{'state'} eq 'no_check') {
	return 1;
	# because called by load(called by new that is called by instantiate) 
	# it is not yet the time to check param constraint, 
	# it will be called later by instantiate
    }

    my @error;

    ## checking
    my $constraint = $self->get_constraints();
    unless (defined $constraint) {
	&Sympa::Log::do_log('err','%s::check_param_constraint(%s,%s) : unable to get family constraints',__PACKAGE__,$self->{'name'},$list->{'name'});
	return undef;
    }
    foreach my $param (keys %{$constraint}) {
	my $constraint_value = $constraint->{$param};
	my $param_value;
	my $value_error;

	unless (defined $constraint_value) {
	    &Sympa::Log::do_log('err','No value constraint on parameter %s in param_constraint.conf',$param);
	    next;
	}

	$param_value = $list->get_param_value($param);

	# exception for uncompellable parameter
	foreach my $forbidden (@uncompellable_param) {
	    if ($param eq $forbidden) {
		next;
	    }  
	}



	$value_error = $self->check_values($param_value,$constraint_value);
	
	if (ref($value_error)) {
	    foreach my $v (@{$value_error}) {
		push (@error,$param);
		&Sympa::Log::do_log('err','Error constraint on parameter %s, value : %s',$param,$v);
	    }
	}
    }
    
    if (scalar @error) {
	return \@error;
    }else {
	return 1;
    }
}

=head2 $family->get_constraints()

Returns a hash containing the values found in the param_constraint.conf file.

=head3 Parameters

None.

=head3 Return value

An hash containing the values found in the param_constraint.conf file.

=cut

sub get_constraints {
    my $self = shift;
    &Sympa::Log::do_log('debug3','%s::get_constraints(%s)',__PACKAGE__,$self->{'name'});

    ## load param_constraint.conf
    my $time_file = (stat("$self->{'dir'}/param_constraint.conf"))[9];
    unless ((defined $self->{'param_constraint_conf'}) && ($self->{'mtime'}{'param_constraint_conf'} >= $time_file)) {
	$self->{'param_constraint_conf'} = $self->_load_param_constraint_conf();
	unless (defined $self->{'param_constraint_conf'}) {
	    &Sympa::Log::do_log('err','Cannot load file param_constraint.conf ');
	    return undef;
	}
	$self->{'mtime'}{'param_constraint_conf'} = $time_file;
    }
        
    return $self->{'param_constraint_conf'};
}

=head2 $family->check_values($param_value, $constraint_value)

Returns 0 if all the value(s) found in $param_value appear also in $constraint_value. Otherwise the function returns an array containing the unmatching values.

=head3 Parameters

=over

=item * I<$param_value>: a scalar or a ref to a list (which is also a scalar after all)

=item * I<$constraint_value>: a scalar or a ref to a list

=back

=head3 Return

=over

=item * I<\@error>, a ref to an array containing the values in $param_value which don't match those in $constraint_value.

=back

=cut

sub check_values {
    my ($self,$param_value,$constraint_value) = @_;
    &Sympa::Log::do_log('debug3','%s::check_values()', __PACKAGE__);
    
    my @param_values;
    my @error;
    
    # just in case
    if ($constraint_value eq '0') {
	return [];
    }
    
    if (ref($param_value) eq 'ARRAY') {
	@param_values = @{$param_value}; # for multiple parameters
    }
    else {
	push @param_values,$param_value; # for single parameters
    }
    
    foreach my $p_val (@param_values) { 
	
	my $found = 0;

	## multiple values
	if(ref($p_val) eq 'ARRAY') { 
	    
	    foreach my $p (@{$p_val}) {
		## controlled parameter
		if (ref($constraint_value) eq 'HASH') {
		    unless ($constraint_value->{$p}) {
			push (@error,$p);
		    }
		## fixed parameter    
		} else {
		    unless ($constraint_value eq $p) {
			push (@error,$p);
		    }
		}
	    }
	## single value
	} else {  
	    ## controlled parameter    
	    if (ref($constraint_value) eq 'HASH') {
		unless ($constraint_value->{$p_val}) {
		    push (@error,$p_val);
		}
	    ## fixed parameter    
	    } else {
		unless ($constraint_value eq $p_val) {
		    push (@error,$p_val);
		}
	    }
	}
    }

 
    return \@error;
}


=head2 $family->get_param_constraint($param)

Gets the constraints on parameter $param from the 'param_constraint.conf' file.

=head3 Parameters

=over

=item * I<$param>: the name of the parameter for which we want to gather constraints.

=back

=head3 Return value

=over

=item * I<0> if there are no constraints on the parameter,

=item * I<a scalar> containing the allowed value if the parameter has a fixed value,

=item * I<a ref to a hash> containing the allowed values if the parameter is controlled,

=item * I<undef> if something went wrong.

=back

=cut

sub get_param_constraint {
    my $self = shift;
    my $param  = shift;
    &Sympa::Log::do_log('debug3','%s::get_param_constraint(%s,%s)',__PACKAGE__,$self->{'name'},$param);
 
    unless(defined $self->get_constraints()) {
	return undef;
    }
 
    if (defined $self->{'param_constraint_conf'}{$param}) { ## fixed or controlled parameter
	return $self->{'param_constraint_conf'}{$param};
  
    } else { ## free parameter
	return '0';
    }
}
	
=head2 $family->get_family_lists()

Returns a ref to an array whose values are the family lists' names.

=head3 Parameters

None.

=head3 Return value

An arrayref containing the family lists names.

=cut

sub get_family_lists {
    my $self = shift;
    my @list_of_lists;
    &Sympa::Log::do_log('debug2','%s::get_family_lists(%s)',__PACKAGE__,$self->{'name'});

    my $all_lists = &Sympa::List::get_lists($self->{'robot'});
    foreach my $list ( @$all_lists ) {
	if ((defined $list->{'admin'}{'family_name'}) && ($list->{'admin'}{'family_name'} eq $self->{'name'})) {
	    push (@list_of_lists, $list);
	}
    }
    return \@list_of_lists;
}

=head2 $family->get_hash_family_lists()

Returns a ref to a hash whose keys are this family's lists' names. They are
associated to the value "1".

=head3 Parameters

None.

=head3 Return value

An hashref whose keys are the family's lists' names.

=cut

sub get_hash_family_lists {
    my $self = shift;
    my %list_of_lists;
    &Sympa::Log::do_log('debug2','%s::get_hash_family_lists(%s)',__PACKAGE__,$self->{'name'});

    my $all_lists = &Sympa::List::get_lists($self->{'robot'});
    foreach my $list ( @$all_lists ) {
	if ((defined $list->{'admin'}{'family_name'}) && ($list->{'admin'}{'family_name'} eq $self->{'name'})) {
	    $list_of_lists{$list->{'name'}} = 1;
	}
    }
    return \%list_of_lists;
}

=head2 $family->get_uncompellable_param()

Returns a reference to hash whose keys are the uncompellable parameters.

=head3 Parameters

None.

=head3 Return value

An hashref whose keys are the uncompellable parameters names.

=cut

sub get_uncompellable_param {
    my %list_of_param;
    &Sympa::Log::do_log('debug3','%s::get_uncompellable_param()', __PACKAGE__);

    foreach my $param (@uncompellable_param) {
	if ($param =~ /^([\w-]+)\.([\w-]+)$/) {
	    $list_of_param{$1} = $2;
	    
	} else {
	    $list_of_param{$param} = '';
	}
    }

    return \%list_of_param;
}

# $family->_get_directory()

# get the family directory, look for it in the robot,
# then in the site and finally in the distrib
#
# Return value:
# the directory name, or undef if the directory does not exist

sub _get_directory {
    my $self = shift;
    my $robot = $self->{'robot'};
    my $name = $self->{'name'};
    &Sympa::Log::do_log('debug3','%s::_get_directory(%s)',__PACKAGE__,$name);

    my @try = (
        $Sympa::Configuration::Conf{'etc'}           . "/$robot/families",
        $Sympa::Configuration::Conf{'etc'}           . "/families",
	    Sympa::Constants::DEFAULTDIR . "/families"
    );

    foreach my $d (@try) {
	if (-d "$d/$name") {
	    return "$d/$name";
	}
    }
    return undef;
}


# $family->_check_mandatory_files()
#
# check existence of mandatory files in the family
# directory:
#  - param_constraint.conf
#  - config.tt2
#
# Return value
# I<0> if everything is OK, the missing file names
# otherwise

sub _check_mandatory_files {
    my $self = shift;
    my $dir = $self->{'dir'};
    my $string = "";
    &Sympa::Log::do_log('debug3','%s::_check_mandatory_files(%s)',__PACKAGE__,$self->{'name'});

    foreach my $f ('config.tt2') {
	unless (-f "$dir/$f") {
	    $string .= $f." ";
	}
    }

    if ($string eq "") {
	return 0;
    } else {
	return $string;
    }
}

# $family->_initialize_instantiation()
#
# initialize vars for instantiation and result
# then to make a string result
#
# Return value
# A true value

sub _initialize_instantiation() {
    my $self = shift;
    &Sympa::Log::do_log('debug3','%s::_initialize_instantiation(%s)',__PACKAGE__,$self->{'name'});

    ### info vars for instantiate  ###
    ### returned by                ###
    ### get_instantiation_results  ### 
    
    ## array of list to generate
    $self->{'list_to_generate'}=(); 
    
    ## lists in error during creation or updating : LIST FATAL ERROR
    # array of xml file name  : error during xml data extraction
    $self->{'errors'}{'create_hash'} = ();
    ## array of list name : error during list creation
    $self->{'errors'}{'create_list'} = ();
    ## array of list name : error during list updating
    $self->{'errors'}{'update_list'} = ();
    ## array of list name : listname already used (in another family)
    $self->{'errors'}{'listname_already_used'} = ();
    ## array of list name : previous list impossible to get
    $self->{'errors'}{'previous_list'} = ();
    
    ## created or updated lists
    ## array of list name : aliases are OK (installed or not, according to status)
    $self->{'created_lists'}{'with_aliases'} = ();
    ## hash of (list name -> aliases) : aliases needed to be installed
    $self->{'created_lists'}{'without_aliases'} = {};
    ## array of list name : aliases are OK (installed or not, according to status)
    $self->{'updated_lists'}{'aliases_ok'} = ();
    ## hash of (list name -> aliases) : aliases needed to be installed
    $self->{'updated_lists'}{'aliases_to_install'} = {};
    ## hash of (list name -> aliases) : aliases needed to be removed
    $self->{'updated_lists'}{'aliases_to_remove'} = {};
    
    ## generated (created or updated) lists in error : no fatal error for the list
    ## array of list name : error during copying files
    $self->{'generated_lists'}{'file_error'} = ();
    ## hash of (list name -> array of param) : family constraint error
    $self->{'generated_lists'}{'constraint_error'} = {};
    
    ## lists isn't anymore in the family
    ## array of list name : lists in status family_closed
    $self->{'family_closed'}{'ok'} = ();
    ## array of list name : lists that must be in status family_closed but they aren't
    $self->{'family_closed'}{'impossible'} = ();
    
    return 1;
}


# $family->_split_xml_file($fh)
#
# split the xml family file into xml list files. New
# list names are put in the array reference
# $self->{'list_to_generate'} and new files are put in
# the family directory
#
# Parameters
# - $fh: file handle on xml file containing description
#               of the family lists 
# Return value
# A true value, or undef if something went wrong

sub _split_xml_file {
    my $self = shift;
    my $xml_file = shift;
    my $root;
    &Sympa::Log::do_log('debug2','%s::_split_xml_file(%s)',__PACKAGE__,$self->{'name'});

    ## parse file
    my $parser = XML::LibXML->new();
    $parser->line_numbers(1);
    my $doc;

    unless ($doc = $parser->parse_file($xml_file)) {
	&Sympa::Log::do_log('err',"%s::_split_xml_file() : failed to parse XML file", __PACKAGE__);
	return undef;
    }
    
    ## the family document
    $root = $doc->documentElement();
    unless ($root->nodeName eq 'family') {
	&Sympa::Log::do_log('err',"%s::_split_xml_file() : the root element must be called \"family\" ", __PACKAGE__);
	return undef;
    }

    ## lists : family's elements
    foreach my $list_elt ($root->childNodes()) {

	if ($list_elt->nodeType == 1) {# ELEMENT_NODE
	    unless ($list_elt->nodeName eq 'list') {
		&Sympa::Log::do_log('err','%s::_split_xml_file() : elements contained in the root element must be called "list", line %s',__PACKAGE__,$list_elt->line_number());
		return undef;
	    }
	}else {
	    next;
	}
	
	## listname 
	my @children = $list_elt->getChildrenByTagName('listname');

	if ($#children <0) {
	    &Sympa::Log::do_log('err','%s::_split_xml_file() : "listname" element is required in "list" element, line : %s',__PACKAGE__,$list_elt->line_number());
	    return undef;
	}
	if ($#children > 0) {
	    my @error;
	    foreach my $i (@children) {
		push (@error,$i->line_number());    
	    }
	    &Sympa::Log::do_log('err','%s::_split_xml_file() : Only one "listname" element is allowed for "list" element, lines : %s',__PACKAGE__,join(", ",@error));
	    return undef;
	    my $minor_param = $2;
	}
	my $listname_elt = shift @children;
	my $listname = $listname_elt->textContent();
	$listname =~ s/^\s*//;
	$listname =~ s/\s*$//;
	$listname = lc $listname;
	my $filename = $listname.".xml";
	
        ## creating list XML document 
	my $list_doc = XML::LibXML::Document->createDocument($doc->version(),$doc->encoding());
	$list_doc->setDocumentElement($list_elt);

	## creating the list xml file
	unless ($list_doc->toFile("$self->{'dir'}/$filename",0)) {
	    &Sympa::Log::do_log('err','%s::_split_xml_file() : cannot create list file %s', __PACKAGE__,
		    $self->{'dir'}.'/'.$filename,$list_elt->line_number());
	    return undef;
	}

	push (@{$self->{'list_to_generate'}},$listname);
    }
    return 1;
}

# $family->_update_existing_list($list, $hash_list)
#
# update an already existing list in the new family context
#
# Parameters
# - $list: the list to update
# - $hash_list: data to create the list config
#
# Return value
# The new list (or undef)

sub _update_existing_list {
    my ($self,$list,$hash_list) = @_;
    &Sympa::Log::do_log('debug3','%s::_update_existing_list(%s,%s)',__PACKAGE__,$self->{'name'},$list->{'name'});

    ## get allowed and forbidden list customizing
    my $custom = $self->_get_customizing($list);
    unless (defined $custom) {
	&Sympa::Log::do_log('err','impossible to get list %s customizing',$list->{'name'});
	return undef;
    }
    my $config_changes = $custom->{'config_changes'}; 
    my $old_status = $list->{'admin'}{'status'};
	    


    ## list config family updating
    my $result = &Sympa::Admin::update_list($list,$hash_list->{'config'},$self,$self->{'robot'});
    unless (defined $result) {
	&Sympa::Log::do_log('err','No object list resulting from updating list %s',$list->{'name'});
	return undef;
    }
    $list = $result;

    
    ## set list customizing
    foreach my $p (keys %{$custom->{'allowed'}}) {
	$list->{'admin'}{$p} = $custom->{'allowed'}{$p};
	delete $list->{'admin'}{'defaults'}{$p};
	&Sympa::Log::do_log('info','Customizing : keeping values for parameter %s',$p);
    }

    ## info file
    unless ($config_changes->{'file'}{'info'}) {
	$hash_list->{'config'}{'description'} =~ s/\r\n|\r/\n/g;
	
	unless (open INFO, '>', "$list->{'dir'}/info") {
	    &Sympa::Log::do_log('err','Impossible to open %s/info : %s',$list->{'dir'},$!);
	}
	print INFO $hash_list->{'config'}{'description'};
	close INFO; 
    }
    
    foreach my $f (keys %{$config_changes->{'file'}}) {
	&Sympa::Log::do_log('info','Customizing : this file has been changed : %s',$f);
    }
    
    ## rename forbidden files
#    foreach my $f (@{$custom->{'forbidden'}{'file'}}) {
#	unless (rename ("$list->{'dir'}"."/"."info","$list->{'dir'}"."/"."info.orig")) {
	    ################
#	}
#	if ($f eq 'info') {
#	    $hash_list->{'config'}{'description'} =~ s/\r\n|\r/\n/g;
#	    unless (open INFO, '>', "$list_dir/info") {
		################
#	    }
#	    print INFO $hash_list->{'config'}{'description'};
#	    close INFO; 
#	}
#    }


    ## notify owner for forbidden customizing
    if (#(scalar $custom->{'forbidden'}{'file'}) ||
	(scalar @{$custom->{'forbidden'}{'param'}})) {
#	my $forbidden_files = join(',',@{$custom->{'forbidden'}{'file'}});
	my $forbidden_param = join(',',@{$custom->{'forbidden'}{'param'}});
	&Sympa::Log::do_log('notice',"These parameters aren't allowed in the new family definition, they are erased by a new instantiation family : \n $forbidden_param");

	unless ($list->send_notify_to_owner('erase_customizing',[$self->{'name'},$forbidden_param])) {
	    &Sympa::Log::do_log('notice','the owner isn\'t informed from erased customizing of the list %s',$list->{'name'});
	}
    }

    ## status
    $result = $self->_set_status_changes($list,$old_status);

    if ($result->{'aliases'} == 1) {
	push (@{$self->{'updated_lists'}{'aliases_ok'}},$list->{'name'});
    
    }elsif ($result->{'install_remove'} eq 'install') {
	$self->{'updated_lists'}{'aliases_to_install'}{$list->{'name'}} = $result->{'aliases'};
	
    }else {
	$self->{'updated_lists'}{'aliases_to_remove'}{$list->{'name'}} = $result->{'aliases'};
	
    }

    ## config_changes
    foreach my $p (@{$custom->{'forbidden'}{'param'}}) {

	if (defined $config_changes->{'param'}{$p}  ) {
	    delete $config_changes->{'param'}{$p};
	}

    }

    unless (open FILE, '>', "$list->{'dir'}/config_changes") {
	&Sympa::Log::do_log('err','impossible to open file %s/config_changes : %s',$list->{'dir'},$!);
	push (@{$self->{'generated_lists'}{'file_error'}},$list->{'name'});
	$list->set_status_error_config('error_copy_file',$list->{'name'},$self->{'name'});
    }
    close FILE;

    my @kept_param = keys %{$config_changes->{'param'}};
    $list->update_config_changes('param',\@kept_param);
    my @kept_files = keys %{$config_changes->{'file'}};
    $list->update_config_changes('file',\@kept_files);
    
    
    return $list;
}

# $family->_get_customizing($list)
#
# gets list customizing from config_changes file and
# keep on changes that are allowed by param_constraint.conf 
#
# Parameters
# - $list: the list to check (Sympa::List object)
#
# Return value
# An hash with the following keys:
# - config_changes: the list config_changes
# - allowed: hash of allowed param : ($param,$values)

sub _get_customizing {
    my ($self,$list) = @_;
    &Sympa::Log::do_log('debug3','%s::_get_customizing(%s,%s)',__PACKAGE__,$self->{'name'},$list->{'name'});

    my $result;
    my $config_changes = $list->get_config_changes;
    
    unless (defined $config_changes) {
	&Sympa::Log::do_log('err','impossible to get config_changes');
	return undef;
    }

    ## FILES
#    foreach my $f (keys %{$config_changes->{'file'}}) {

#	my $privilege; # =may_edit($f)
	    
#	unless ($privilege eq 'write') {
#	    push @{$result->{'forbidden'}{'file'}},$f;
#	}
#    }

    ## PARAMETERS

    # get customizing values
    my $changed_values;
    foreach my $p (keys %{$config_changes->{'param'}}) {

	$changed_values->{$p} = $list->{'admin'}{$p}
    }

    # check these values
    my $constraint = $self->get_constraints();
    unless (defined $constraint) {
	&Sympa::Log::do_log('err','unable to get family constraints',$self->{'name'},$list->{'name'});
	return undef;
    }

    foreach my $param (keys %{$constraint}) {
	my $constraint_value = $constraint->{$param};
	my $param_value;
	my $value_error;

	unless (defined $constraint_value) {
	    &Sympa::Log::do_log('err','No value constraint on parameter %s in param_constraint.conf',$param);
	    next;
	}

	$param_value = &Sympa::List::_get_param_value_anywhere($changed_values,$param);
 
	$value_error = $self->check_values($param_value,$constraint_value);

	foreach my $v (@{$value_error}) {
	    push @{$result->{'forbidden'}{'param'}},$param;
	    &Sympa::Log::do_log('err','Error constraint on parameter %s, value : %s',$param,$v);
	}
	
    }
    
    # keep allowed values
    foreach my $param (@{$result->{'forbidden'}{'param'}}) {
	my $minor_p;
	if ($param =~ /^([\w-]+)\.([\w-]+)$/) {
	    $param = $1;
	}

	if (defined $changed_values->{$param}) {
	    delete $changed_values->{$param};
	}
    }
    $result->{'allowed'} = $changed_values;

    $result->{'config_changes'} = $config_changes;
    return $result;
}

# $family->_set_status_changes($list, $old_status)
#
# set changes (load the users, install or removes the
# aliases) dealing with the new and old_status (for 
# already existing lists)
#
# Parameters
# - $list: the new list
# - $old_status: the list status before instantiation family
#
# Return value
# An hash with the following keys:
# - install_remove: 'install' |  'remove'
# - aliases: 1 (if install or remove is done) or
#        a string of aliases needed to be installed or removed 

sub _set_status_changes {
    my ($self,$list,$old_status) = @_;
    &Sympa::Log::do_log('debug3','%s::_set_status_changes(%s,%s,%s)',__PACKAGE__,$self->{'name'},$list);

    my $result;

    $result->{'aliases'} = 1;

    unless (defined $list->{'admin'}{'status'}) {
	$list->{'admin'}{'status'} = 'open';
    }

    ## aliases
    if ($list->{'admin'}{'status'} eq 'open') {
	unless ($old_status eq 'open') {
	    $result->{'install_remove'} = 'install'; 
	    $result->{'aliases'} = &Sympa::Admin::install_aliases($list,$self->{'robot'});
	}
    }

    if (($list->{'admin'}{'status'} eq 'pending') && 
	(($old_status eq 'open') || ($old_status eq 'error_config'))) {
	$result->{'install_remove'} = 'remove'; 
	$result->{'aliases'} = &Sympa::Admin::remove_aliases($list,$self->{'robot'});
    }
    
##    ## subscribers
##    if (($old_status ne 'pending') && ($old_status ne 'open')) {
##	
##	if ($list->{'admin'}{'user_data_source'} eq 'file') {
##	    $list->{'users'} = &Sympa::List::_load_users_file("$list->{'dir'}/subscribers.closed.dump");
##	}elsif ($list->{'admin'}{'user_data_source'} eq 'database') {
##	    unless (-f "$list->{'dir'}/subscribers.closed.dump") {
##		&Sympa::Log::do_log('notice', 'No subscribers to restore');
##	    }
##	    my @users = &Sympa::List::_load_users_file("$list->{'dir'}/subscribers.closed.dump");
##	    
##	    ## Insert users in database
##	    foreach my $user (@users) {
##		$list->add_user($user);
##	    }
##	}
##    }

    return $result;
}

# $family->_end_update_list($list, $xml_file)
#
# finish to generate a list in a family context 
# (for a new or an already existing list)
# if there are error, list are set in status error_config
#
# Parameters:
# - $list list directory
# - $xml_file : 0 (no copy xml file)or 1 (copy xml file)
#
# Return value:
# A true value, or undef if something went wrong

sub _end_update_list {
    my ($self,$list,$xml_file) = @_;
    &Sympa::Log::do_log('debug3','%s::_end_update_list(%s,%s)',__PACKAGE__,$self->{'name'},$list->{'name'});
    
    my $host = &Sympa::Configuration::get_robot_conf($self->{'robot'}, 'host');
    $list->{'admin'}{'latest_instantiation'}{'email'} = "listmaster\@$host";
    $list->{'admin'}{'latest_instantiation'}{'date'} = gettext_strftime "%d %b %Y at %H:%M:%S", localtime(time);
    $list->{'admin'}{'latest_instantiation'}{'date_epoch'} = time;
    $list->save_config("listmaster\@$host");
    $list->{'family'} = $self;
    
    ## check param_constraint.conf 
    $self->{'state'} = 'normal';
    my $error = $self->check_param_constraint($list);
    $self->{'state'} = 'no_check';

    unless (defined $error) {
	&Sympa::Log::do_log('err', 'Impossible to check parameters constraint, it happens on list %s. It is set in status error_config',$list->{'name'});
	$list->set_status_error_config('no_check_rules_family',$list->{'name'},$self->{'name'});
	return undef;
    }
    if (ref($error) eq 'ARRAY') {
	$self->{'generated_lists'}{'constraint_error'}{$list->{'name'}} = join(", ",@{$error});
	$list->set_status_error_config('no_respect_rules_family',$list->{'name'},$self->{'name'});
    }
    
    ## copy files in the list directory
    if ($xml_file) { # copying the xml file
	unless ($self->_copy_files($list->{'dir'},"$list->{'name'}.xml")) {
	    push (@{$self->{'generated_lists'}{'file_error'}},$list->{'name'});
	    $list->set_status_error_config('error_copy_file',$list->{'name'},$self->{'name'});
	}
    }

    return 1;
}

# $family->_copy_files($list_dir, $file)
#
# copy files in the list directory :
#   - instance.xml (xml data defining list)
#
# Parameters
# - $list_dir: list directory
# - $file : xml file : optional
#
# Return value
# A true value, or undef if something went wrong

sub _copy_files {
    my $self = shift;
    my $list_dir = shift;
    my $file = shift;
    my $dir = $self->{'dir'};
    &Sympa::Log::do_log('debug3','%s::_copy_files(%s,%s)',__PACKAGE__,$self->{'name'},$list_dir);

    # instance.xml
    if (defined $file) {
	unless (&File::Copy::copy ("$dir/$file", "$list_dir/instance.xml")) {
	    &Sympa::Log::do_log('err','%s::_copy_files(%s) : impossible to copy %s/%s into %s/instance.xml : %s',__PACKAGE__,$self->{'name'},$dir,$file,$list_dir,$!);
	    return undef;
	}
    }



    return 1;
}

# $family->_load_param_constraint_conf()
#
# load the param_constraint.conf file in a hash
#  
# Return value
# An hashref containing the data found in param_constraint.conf, or undef if something went wrong.

sub _load_param_constraint_conf {
    my $self = shift;
    &Sympa::Log::do_log('debug2','%s::_load_param_constraint_conf(%s)',__PACKAGE__,$self->{'name'});

    my $file = "$self->{'dir'}/param_constraint.conf";
    
    my $constraint = {};

    unless (-e $file) {
	&Sympa::Log::do_log('err','No file %s. Assuming no constraints to apply.', $file);
	return $constraint;
    }

    unless (open (FILE, $file)) {
	&Sympa::Log::do_log('err','File %s exists, but unable to open it: %s', $file,$_);
	return undef;
    }

    my $error = 0;

    ## Just in case...
    local $/ = "\n";

    while (<FILE>) {
	next if /^\s*(\#.*|\s*)$/;

	if (/^\s*([\w\-\.]+)\s+(.+)\s*$/) {
	    my $param = $1;
	    my $value = $2;
	    my @values = split /,/, $value;
	    
	    unless(($param =~ /^([\w-]+)\.([\w-]+)$/) || ($param =~ /^([\w-]+)$/)) {
		&Sympa::Log::do_log ('err', '%s::_load_param_constraint_conf(%s) : unknown parameter "%s" in %s',__PACKAGE__,$self->{'name'},$_,$file);
		$error = 1;
		next;
	    }
	    
	    if (scalar(@values) == 1) {
		$constraint->{$param} = shift @values;
	    } else {
		foreach my $v (@values) {
		    $constraint->{$param}{$v} = 1;
		}
	    }
	} else {
	    &Sympa::Log::do_log ('err', '%s::_load_param_constraint_conf(%s) : bad line : %s in %s',__PACKAGE__,$self->{'name'},$_,$file);
	    $error = 1;
	    next;
	}
    }
    if ($error) {
	unless (&Sympa::List::send_notify_to_listmaster('param_constraint_conf_error', $self->{'robot'}, [$file])) {
	    &Sympa::Log::do_log('notice','the owner isn\'t informed from param constraint config errors on the %s family',$self->{'name'});
	}
    }
    close FILE;

 # Parameters not allowed in param_constraint.conf file :
    foreach my $forbidden (@uncompellable_param) {
 	if (defined $constraint->{$forbidden}) {
 	    delete $constraint->{$forbidden};
 	}
     }

###########################"
 #   open TMP, ">/tmp/dump1";
 #   &Sympa::Tools::Data::dump_var ($constraint, 0, \*TMP);
 #    close TMP;

    return $constraint;
}

sub create_automatic_list {
    my $self = shift;
    my %param = @_;
    my $auth_level = $param{'auth_level'};
    my $sender = $param{'sender'};
    my $message = $param{'message'};
    my $listname = $param{'listname'};

    unless ($self->is_allowed_to_create_automatic_lists(%param)){
	&Sympa::Log::do_log('err', 'Unconsistent scenario evaluation result for automatic list creation of list %s@%s by user %s.', $listname,$self->{'robot'},$sender);
	return undef;
    }
    my $result = $self->add_list({listname=>$listname}, 1);
    
    unless (defined $result->{'ok'}) {
	my $details = $result->{'string_error'} || $result->{'string_info'} || [];
	&Sympa::Log::do_log('err', "Failed to add a dynamic list to the family %s : %s", $self->{'name'}, join(';', @{$details}));
	return undef;
    }
    my $list = new Sympa::List ($listname, $self->{'robot'});
    unless (defined $list) {
	&Sympa::Log::do_log('err', 'sympa::DoFile() : dynamic list %s could not be created',$listname);
	return undef;
    }
    return $list;
}

=head2 $family->is_allowed_to_create_automatic_lists(%parameters)

Returns 1 if the user is allowed to create lists based on the family.

=cut

sub is_allowed_to_create_automatic_lists {
    my $self = shift;
    my %param = @_;
    
    my $auth_level = $param{'auth_level'};
    my $sender = $param{'sender'};
    my $message = $param{'message'};
    my $listname = $param{'listname'};
    
    # check authorization
    my $result = &Sympa::Scenario::request_action('automatic_list_creation',$auth_level,$self->{'robot'},
					   {'sender' => $sender, 
					    'message' => $message, 
					    'family'=>$self, 
					    'automatic_listname'=>$listname });
    my $r_action;
    unless (defined $result) {
	&Sympa::Log::do_log('err', 'Unable to evaluate scenario "automatic_list_creation" for family %s', $self->{'name'});
	return undef;
    }
    
    if (ref($result) eq 'HASH') {
	$r_action = $result->{'action'};
    }else {
	&Sympa::Log::do_log('err', 'Unconsistent scenario evaluation result for automatic list creation in family %s', $self->{'name'});
	return undef;
    }

    unless ($r_action =~ /do_it/) {
	&Sympa::Log::do_log('debug2', 'Automatic list creation refused to user %s for family %s', $sender, $self->{'name'});
	return undef;
    }
    
    return 1;
}
=head1 AUTHORS 

=over 

=item * Serge Aumont <sa AT cru.fr> 

=item * Olivier Salaun <os AT cru.fr> 

=back 

=cut

1;
