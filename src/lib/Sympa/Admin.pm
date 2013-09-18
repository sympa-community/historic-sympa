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
# along with this program. If not, see <http://www.gnu.org/licenses/>.

=encoding utf-8

=head1 NAME

Sympa::Admin - Administrative functions

=head1 DESCRIPTION

This module provides creation and edition functions.

=cut

package Sympa::Admin;

use strict;

use English qw(-no_match_vars);
use File::Copy;
use IO::Scalar;

use Sympa::Configuration;
use Sympa::Constants;
use Sympa::Database;
use Sympa::Language;
use Sympa::List;
use Sympa::Lock;
use Sympa::Log::Syslog;
use Sympa::Log::Database;
use Sympa::Scenario;
use Sympa::Template;
use Sympa::Tools;
use Sympa::Tools::File;

=head1 FUNCTIONS

=over

=item create_list_old($params, $template, $robot, $origin, $user_mail)

Creates a list, without family concept.

Parameters:

=over

=item C<$params> => an hashref containing configuration parameters, as the
following keys:

=over 4

=item - I<listname>,

=item - I<subject>,

=item - I<owner>: array of hashes, with key email mandatory

=item - I<owner_include>: array of hashes, with key source mandatory

=back

=item C<$template> => the list creation template

=item C<$robot> => the list robot

=item C<$origin> => the source of the command : web, soap or command_line (no
longer used)

=back

Return value:

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item C<list> => the just created L<Sympa::List> object

=item C<aliases> => I<undef> if not applicable; 1 (if ok) or $aliases : concatenated string of aliases if they are not installed or 1 (in status open)

=back

=cut

sub create_list_old{
	my ($params, $template, $robot, $origin, $user_mail) = @_;
	Sympa::Log::Syslog::do_log('debug', '(%s,%s)',$params->{'listname'},$robot,$origin);

	## obligatory list parameters
	foreach my $arg ('listname','subject') {
		unless ($params->{$arg}) {
			Sympa::Log::Syslog::do_log('err','missing list param %s', $arg);
			return undef;
		}
	}
	# owner.email || owner_include.source
	unless (check_owner_defined($params->{'owner'},$params->{'owner_include'})) {
		Sympa::Log::Syslog::do_log('err','problem in owner definition in this list creation');
		return undef;
	}


	# template
	unless ($template) {
		Sympa::Log::Syslog::do_log('err','missing param "template"', $template);
		return undef;
	}
	# robot
	unless ($robot) {
		Sympa::Log::Syslog::do_log('err','missing param "robot"', $robot);
		return undef;
	}

	## check listname
	$params->{'listname'} = lc ($params->{'listname'});
	my $listname_regexp = Sympa::Tools::get_regexp('listname');

	unless ($params->{'listname'} =~ /^$listname_regexp$/i) {
		Sympa::Log::Syslog::do_log('err','incorrect listname %s', $params->{'listname'});
		return undef;
	}

	my $regx = $robot->list_check_regexp;
	if( $regx ) {
		if ($params->{'listname'} =~ /^(\S+)-($regx)$/) {
			Sympa::Log::Syslog::do_log('err','incorrect listname %s matches one of service aliases', $params->{'listname'});
			return undef;
		}
	}

	if ($params->{'listname'} eq $robot->email) {
		Sympa::Log::Syslog::do_log('err','incorrect listname %s matches one of service aliases', $params->{'listname'});
		return undef;
	}

	## Check listname on SMTP server
	my $res = list_check_smtp($params->{'listname'}, $robot);
	unless (defined $res) {
		Sympa::Log::Syslog::do_log('err', "can't check list %.128s on %s",
			$params->{'listname'}, $robot);
		return undef;
	}

	## Check this listname doesn't exist already.
	my $new_list = Sympa::List->new(
		name    => $params->{'listname'},
		robot   => $robot,
		base    => Sympa::Database->get_singleton(),
		options => {'just_try' => 1}
	);
	if( $res || $new_list) {
		Sympa::Log::Syslog::do_log('err', 'could not create already existing list %s on %s for ',
			$params->{'listname'}, $robot);
		foreach my $o (@{$params->{'owner'}}){
			Sympa::Log::Syslog::do_log('err',$o->{'email'});
		}
		return undef;
	}


	## Check the template supposed to be used exist.
	my $template_file = Sympa::Tools::get_etc_filename('create_list_templates/'.$template.'/config.tt2', $robot, undef, Site->etc);
	unless (defined $template_file) {
		Sympa::Log::Syslog::do_log('err', 'no template %s found',$template);
		return undef;
	}

	## Create the list directory
	my $list_dir = $robot->home.'/'.$params->{'listname'};

	## Check the privileges on the list directory
	unless (mkdir ($list_dir,0777)) {
		Sympa::Log::Syslog::do_log('err', 'unable to create %s : %s',$list_dir,$CHILD_ERROR);
		return undef;
	}

	## Check topics
	if ($params->{'topics'}){
		unless ($robot->is_available_topic($param->{'topics'})) {
			Sympa::Log::Syslog::do_log('err', 'topics param %s not defined in topics.conf',
			$param->{'topics'});
		}
	}

	## Creation of the config file
    my $time = time;
    $param->{'creation'}{'date'} = gettext_strftime "%d %b %Y at %H:%M:%S", localtime $time;
    $param->{'creation'}{'date_epoch'} = $time;
    $param->{'creation_email'} ||= $robot->get_address('listmaster');
    $param->{'status'} ||= 'open';

	my $tt2_include_path = Sympa::Tools::make_tt2_include_path($robot,'create_list_templates/'.$template,'','',Site->etc,Site->viewmaildir,Site->domain);

	## Lock config before openning the config file
	my $lock = Sympa::Lock->new(
		path   => $list_dir.'/config',
		method => Site->lock_method
	);
	unless (defined $lock) {
		Sympa::Log::Syslog::do_log('err','Lock could not be created');
		return undef;
	}
	$lock->set_timeout(5);
	unless ($lock->lock('write')) {
		return undef;
	}
	unless (open CONFIG, '>', "$list_dir/config") {
		Sympa::Log::Syslog::do_log('err','Impossible to create %s/config : %s', $list_dir, $ERRNO);
		$lock->unlock();
		return undef;
	}
	## Use an intermediate handler to encode to filesystem_encoding
	my $config = '';
	my $fd = IO::Scalar->new(\$config);
	Sympa::Template::parse_tt2($params, 'config.tt2', $fd, $tt2_include_path);
	#    Encode::from_to($config, 'utf8', Site->filesystem_encoding);
	print CONFIG $config;

	close CONFIG;

	## Unlock config file
	$lock->unlock();

	## Creation of the info file
	# remove DOS linefeeds (^M) that cause problems with Outlook 98, AOL, and EIMS:
	$params->{'description'} =~ s/\r\n|\r/\n/g;

	## info file creation.
	unless (open INFO, '>', "$list_dir/info") {
		Sympa::Log::Syslog::do_log('err','Impossible to create %s/info : %s',$list_dir,$ERRNO);
	}
	if (defined $params->{'description'}) {
		Encode::from_to($params->{'description'}, 'utf8', Site->filesystem_encoding);
		print INFO $params->{'description'};
	}
	close INFO;

	## Create list object
	my $list = Sympa::List->new(
		name  => $params->{'listname'},
		robot => $robot,
		base  => Sympa::Database->get_singleton(),
	);
	unless ($list) {
		Sympa::Log::Syslog::do_log('err','unable to create list %s', $params->{'listname'});
		return undef;
	}

	## Create shared if required
	##FIXME: add "shared_doc.enabled" parameter then use it.
	if (scalar keys %{$list->shared_doc}) {
		$list->create_shared();
	}

	#log in stat_table to make statistics

	if($origin eq "web"){
		Sympa::Log::Database::add_stat(
			robot     => $robot,
			list      => $params->{'listname'},
			operation => 'create list',
			mail      => $user_mail,
			daemon    => 'wwsympa.fcgi'
		);
	}

	my $return = {};
	$return->{'list'} = $list;

	if ($list->{'admin'}{'status'} eq 'open') {
		$return->{'aliases'} = install_aliases($list,$robot);
	} else {
		$return->{'aliases'} = 1;
	}

	## Synchronize list members if required
	if ($list->has_include_data_sources()) {
		Sympa::Log::Syslog::do_log('notice', "Synchronizing list members...");
		$list->sync_include();
	}

	$list->save_config();
	return $return;
}

=item create_list($params, $family, $robot, $abort_on_error)

Create a list, with family concept.

Parameters:

=over

=item C<$param> => an hashref containing configuration parameters, as the
following keys:

=over 4

=item - I<listname>,

=item - I<subject>,

=item - I<owner>: array of hashes, with key email mandatory

=item - I<owner_include>: array of hashes, with key source mandatory

=back

=item C<$family> => the list family (L<Sympa::Family> object)

=item C<$robot> => the list robot

=item C<$abort_on_error> =>  won't create the list directory on tt2 process
error (usefull for dynamic lists that throw exceptions)

=back

Return value:

An hashref with the following keys, or I<undef> if something went wrong:

=over

=item C<list> => the just created L<Sympa::List> object

=item C<aliases> => I<undef> if not applicable; 1 (if ok) or $aliases : concatenated string of aliases if they are not installed or 1 (in status open)

=back

=cut

sub create_list{
	my ($params, $family, $robot, $abort_on_error) = @_;
	Sympa::Log::Syslog::do_log('info', '(%s,%s,%s)',$params->{'listname'},$family->{'name'},$params->{'subject'});

	## mandatory list parameters
	foreach my $arg ('listname') {
		unless ($params->{$arg}) {
			Sympa::Log::Syslog::do_log('err','missing list param %s', $arg);
			return undef;
		}
	}

	unless ($family) {
		Sympa::Log::Syslog::do_log('err','missing param "family"');
		return undef;
	}

	#robot
	$robot = $family->robot;
	unless ($robot) {
		Sympa::Log::Syslog::do_log('err','missing param "robot"', $robot);
		return undef;
	}

	## check listname
	$params->{'listname'} = lc ($params->{'listname'});
	my $listname_regexp = Sympa::Tools::get_regexp('listname');

	unless ($params->{'listname'} =~ /^$listname_regexp$/i) {
		Sympa::Log::Syslog::do_log('err','incorrect listname %s', $params->{'listname'});
		return undef;
	}

	my $regx = $robot->list_check_regexp;
	if( $regx ) {
		if ($params->{'listname'} =~ /^(\S+)-($regx)$/) {
			Sympa::Log::Syslog::do_log('err','incorrect listname %s matches one of service aliases', $params->{'listname'});
			return undef;
		}
	}
	if ($params->{'listname'} eq $robot->email) {
		Sympa::Log::Syslog::do_log('err','incorrect listname %s matches one of service aliases', $params->{'listname'});
		return undef;
	}

	## Check listname on SMTP server
	my $res = list_check_smtp($params->{'listname'}, $robot);
	unless (defined $res) {
		Sympa::Log::Syslog::do_log('err', "can't check list %.128s on %s",
			$params->{'listname'}, $robot);
		return undef;
	}

	if ($res) {
		Sympa::Log::Syslog::do_log('err', 'could not create already existing list %s on %s for ', $params->{'listname'}, $robot);
		foreach my $o (@{$params->{'owner'}}){
			Sympa::Log::Syslog::do_log('err',$o->{'email'});
		}
		return undef;
	}

	## template file
	my $template_file = $family->get_etc_filename('config.tt2');
	unless (defined $template_file) {
		Sympa::Log::Syslog::do_log('err', 'no config template from family %s@%s',$family->{'name'},$robot);
		return undef;
	}

	my $family_config = $robot->automatic_list_families || {};
	$params->{'family_config'} = $family_config->{$family->{'name'}};
	my $conf;
	my $tt_result = Sympa::Template::parse_tt2($params, 'config.tt2', \$conf, [$family->{'dir'}]);
	unless (defined $tt_result || !$abort_on_error) {
		Sympa::Log::Syslog::do_log('err', 'abort on tt2 error. List %s from family %s@%s',
			$params->{'listname'}, $family->{'name'},$robot);
		return undef;
	}

	## Create the list directory
    my $list_dir = $robot->home . '/' . $param->{'listname'};

	unless (-r $list_dir || mkdir ($list_dir,0777)) {
		Sympa::Log::Syslog::do_log('err', 'unable to create %s : %s',$list_dir,$CHILD_ERROR);
		return undef;
	}

	## Check topics
    if (defined $param->{'topics'}){
		unless ($robot->is_available_topic($param->{'topics'})) {
			Sympa::Log::Syslog::do_log('err', 'topics param %s not defined in topics.conf',
			$param->{'topics'});
		}
    }

	## Lock config before openning the config file
	my $lock = Sympa::Lock->new(
		path   => $list_dir.'/config',
		method => Site->lock_method
	);
	unless (defined $lock) {
		Sympa::Log::Syslog::do_log('err','Lock could not be created');
		return undef;
	}
	$lock->set_timeout(5);
	unless ($lock->lock('write')) {
		return undef;
	}

	## Creation of the config file
	unless (open CONFIG, '>', "$list_dir/config") {
		Sympa::Log::Syslog::do_log('err','Impossible to create %s/config : %s', $list_dir, $ERRNO);
		$lock->unlock();
		return undef;
	}
	#Sympa::Template::parse_tt2($params, 'config.tt2', \*CONFIG, [$family->{'dir'}]);
	print CONFIG $conf;
	close CONFIG;

	## Unlock config file
	$lock->unlock();

	## Creation of the info file
	# remove DOS linefeeds (^M) that cause problems with Outlook 98, AOL, and EIMS:
	$params->{'description'} =~ s/\r\n|\r/\n/g;

	unless (open INFO, '>', "$list_dir/info") {
		Sympa::Log::Syslog::do_log('err','Impossible to create %s/info : %s', $list_dir, $ERRNO);
	}
	if (defined $params->{'description'}) {
		print INFO $params->{'description'};
	}
	close INFO;

	## Create associated files if a template was given.
	for my $file ('message.footer','message.header','message.footer.mime','message.header.mime','info') {
		my $template_file = $family->get_etc_filename($file . ".tt2");
		if (defined $template_file) {
			my $file_content;
			my $tt_result = Sympa::Template::parse_tt2($params, $file.".tt2", \$file_content, [$family->{'dir'}]);
			unless (defined $tt_result) {
				Sympa::Log::Syslog::do_log('err', 'tt2 error. List %s from family %s@%s, file %s',
				$params->{'listname'}, $family,$file);
			}
			unless (open FILE, '>', "$list_dir/$file") {
				Sympa::Log::Syslog::do_log('err','Impossible to create %s/%s : %s',$list_dir,$file,$ERRNO);
			}
			print FILE $file_content;
			close FILE;
		}
	}

	## Create list object
	my $list = Sympa::List->new(
		name  => $params->{'listname'},
		robot => $robot,
		base  => Sympa::Database->get_singleton(),
	);
	unless ($list) {
		Sympa::Log::Syslog::do_log('err','unable to create list %s', $params->{'listname'});
		return undef;
	}

	## Create shared if required
	## #FIXME: add "shared_doc.enabled" option then refer it.
	if (scalar keys %{$list->shared_doc}) {
		$list->create_shared();
	}

    my $time = time;
    $list->creation({
	'date' => (gettext_strftime "%d %b %Y at %H:%M:%S", localtime $time),
	'date_epoch' => $time,
	'email' => ($param->{'creation_email'} || $robot->get_address('listmaster'))
    });
    $list->status($param->{'status'} || 'open');
    $list->family($family);

	my $return = {};
	$return->{'list'} = $list;

	if ($list->status eq 'open') {
		$return->{'aliases'} = install_aliases($list,$robot);
	} else {
		$return->{'aliases'} = 1;
	}

	## Synchronize list members if required
	if ($list->has_include_data_sources()) {
		Sympa::Log::Syslog::do_log('notice', "Synchronizing list members...");
		$list->sync_include();
	}

	return $return;
}

=item update_list($list, $params, $family, $robot)

Update a list with family concept when the list already exists.

Parameters:

=over

=item C<$list> => the list to update

=item C<$param> => an hashref containing the new config parameters, as the following keys:

=over 4

=item - I<listname>,

=item - I<subject>,

=item - I<owner>: array of hashes, with key email mandatory

=item - I<owner_include>: array of hashes, with key source mandatory

=back

=item C<$family> => the list family (L<Sympa::Family> object)

=item C<$robot> => the list robot

=back

Return value:

The updated L<Sympa::List> object.

=cut

sub update_list{
	my ($list, $params, $family, $robot) = @_;
	Sympa::Log::Syslog::do_log('info', '(%s,%s,%s)',$params->{'listname'},$family->{'name'},$params->{'subject'});

	## mandatory list parameters
	foreach my $arg ('listname') {
		unless ($params->{$arg}) {
			Sympa::Log::Syslog::do_log('err','missing list param %s', $arg);
			return undef;
		}
	}

	## template file
	my $template_file = $family->get_etc_filename('config.tt2');
	unless (defined $template_file) {
		Sympa::Log::Syslog::do_log('err', 'no config template from family %s@%s',$family->{'name'},$robot);
		return undef;
	}

	## Check topics
	if (defined $params->{'topics'}){
		unless ($robot->is_available_topic($param->{'topics'})) {
			Sympa::Log::Syslog::do_log('err', 'topics param %s not defined in topics.conf',
			$param->{'topics'});
		}
	}

	## Lock config before openning the config file
	my $lock = Sympa::Lock->new(
		path   => $list->{'dir'}.'/config',
		method => Site->lock_method
	);
	unless (defined $lock) {
		Sympa::Log::Syslog::do_log('err','Lock could not be created');
		return undef;
	}
	$lock->set_timeout(5);
	unless ($lock->lock('write')) {
		return undef;
	}

	## Creation of the config file
	unless (open CONFIG, '>', "$list->{'dir'}/config") {
		Sympa::Log::Syslog::do_log('err','Impossible to create %s/config : %s', $list->{'dir'}, $ERRNO);
		$lock->unlock();
		return undef;
	}
	Sympa::Template::parse_tt2($params, 'config.tt2', \*CONFIG, [$family->{'dir'}]);
	close CONFIG;

	## Unlock config file
	$lock->unlock();

	## Create list object
	$list = Sympa::List->new(
		name  => $params->{'listname'},
		robot => $robot,
		base  => Sympa::Database->get_singleton(),
	);
	unless ($list) {
		Sympa::Log::Syslog::do_log('err','unable to create list %s',  $params->{'listname'});
		return undef;
	}
	############## ? update
    my $time = time;
    $list->creation({
	'date' => (gettext_strftime "%d %b %Y at %H:%M:%S", localtime $time),
	'date_epoch' => $time,
	'email' => ($param->{'creation_email'} || $list->robot->get_address('listmaster'))
    });
    $list->status($param->{'status'} || 'open');
    $list->family($family);

	## Synchronize list members if required
	if ($list->has_include_data_sources()) {
		Sympa::Log::Syslog::do_log('notice', "Synchronizing list members...");
		$list->sync_include();
	}

	return $list;
}

=item rename_list(%parameters)

Rename a list or move a list to another virtual host.

Parameters:

=over

=item C<list> =>

=item C<new_listname> =>

=item C<new_robot> =>

=item C<mode> => 'copy'

=item C<auth_method> =>

=item C<user_email> =>

=item C<remote_host> =>

=item C<remote_addr> =>

=item C<options> => 'skip_authz' to skip authorization scenarios eval

=back

Return value:

I<1> in case of success, an error string otherwise.

=cut

sub rename_list{
	my (%params) = @_;
	Sympa::Log::Syslog::do_log('info', '',);

	my $list = $params{'list'};
	my $robot = $list->{'domain'};
	my $old_listname = $list->{'name'};

	# check new listname syntax
	my $new_listname = lc ($params{'new_listname'});
	my $listname_regexp = Sympa::Tools::get_regexp('listname');

	unless ($new_listname =~ /^$listname_regexp$/i) {
		Sympa::Log::Syslog::do_log('err','incorrect listname %s', $new_listname);
		return 'incorrect_listname';
	}

    unless ($new_listname =~ /^$listname_regexp$/i) {
      Sympa::Log::Syslog::do_log('err','incorrect listname %s', $new_listname);
      return 'incorrect_listname';
    }

    my $new_robot_id = $param{'new_robot'};
    my $new_robot = Robot->new($new_robot_id);

    unless ($new_robot) {
	Sympa::Log::Syslog::do_log('err', 'incorrect robot %s', $new_robot_id);
	return 'unknown_robot';
    }

	## Evaluate authorization scenario unless run as listmaster (sympa.pl)
	my ($result, $r_action, $reason);
	unless ($params{'options'}{'skip_authz'}) {
		$result = Sympa::Scenario::request_action($new_robot,'create_list', $param{'auth_method'},
			{   'sender'      => $param{'user_email'},
				'remote_host' => $param{'remote_host'},
				'remote_addr' => $param{'remote_addr'}
			}
		);
 
		if (ref($result) eq 'HASH') {
			$r_action = $result->{'action'};
			$reason = $result->{'reason'};
		}

		unless ($r_action =~ /do_it|listmaster/) {
			Sympa::Log::Syslog::do_log('err','authorization error');
			return 'authorization';
		}
	}

	## Check listname on SMTP server
    my $res = list_check_smtp($param{'new_listname'},
	$new_robot);
    unless ( defined($res) ) {
      Sympa::Log::Syslog::do_log('err', "can't check list %.128s on %s",
	      $param{'new_listname'}, $new_robot);
      return 'internal';
    }

    if ($res || 
	($list->name ne $param{'new_listname'}) && ## Do not test if listname did not change
	(Sympa::List->new($param{'new_listname'}, $new_robot, {'just_try' => 1}))) {
		Sympa::Log::Syslog::do_log('err',
			'Could not rename list %s: new list %s on %s already existing list',
			$list, $param{'new_listname'}, $new_robot);
		return 'list_already_exists';
    }
    
    my ($name, $type) = $new_robot->split_listname($param{'new_listname'});
    if ($type) {
		Sympa::Log::Syslog::do_log('err',
			'Incorrect listname %s matches one of service aliases',
			$param{'new_listname'}
		);
		return 'incorrect_listname';
    }

	unless ($params{'mode'} eq 'copy') {
		$list->savestats();

		## Dump subscribers
		$list->_save_list_members_file("$list->{'dir'}/subscribers.closed.dump");

		$params{'aliases'} = remove_aliases($list, $list->{'domain'});
	}

	## Rename or create this list directory itself
    my $new_dir = $new_robot->home . '/' . $param{'new_listname'};

	## If we are in 'copy' mode, create en new list
	if ($params{'mode'} eq 'copy') {
		unless ( $list = clone_list_as_empty($list->{'name'},$list->{'domain'},$params{'new_listname'},$params{'new_robot'},$params{'user_email'})){
			Sympa::Log::Syslog::do_log('err',"Unable to load $params{'new_listname'} while renaming");
			return 'internal';
		}
	}

	# set list status to pending if creation list is moderated
	if ($r_action =~ /listmaster/) {
		$list->status('pending');
		Sympa::List::send_notify_to_listmaster('request_list_renaming',
			{'list' => $list,
				'new_listname' => $params{'new_listname'},
				'old_listname' => $old_listname,
				'email' => $params{'user_email'},
				'mode' => $params{'mode'}});
		$params{'status'} = 'pending';
	}

	## Save config file for the new() later to reload it
	$list->save_config($params{'user_email'});

	## This code should be in Sympa::List::rename()
	unless ($params{'mode'} eq 'copy') {
		unless (move ($list->{'dir'}, $new_dir )){
			Sympa::Log::Syslog::do_log('err',"Unable to rename $list->{'dir'} to $new_dir : $ERRNO");
			return 'internal';
		}

		## Rename archive
	 my $arc_dir = $list->robot->arc_path . '/' . $list->get_id();
	 my $new_arc_dir = $new_robot->arc_path . '/' . $param{'new_listname'}.'@'.$param{'new_robot'};
	 if (-d $arc_dir && $arc_dir ne $new_arc_dir) {
	     unless (move ($arc_dir,$new_arc_dir)) {
		 Sympa::Log::Syslog::do_log('err',"Unable to rename archive $arc_dir");
		 # continue even if there is some troubles with archives
		 # return undef;
	     }
	 }

		## Rename bounces
		my $bounce_dir = $list->get_bounce_dir();
		my $new_bounce_dir = Sympa::Configuration::get_robot_conf($params{'new_robot'}, 'bounce_path').'/'.$params{'new_listname'}.'@'.$params{'new_robot'};
		if (-d $bounce_dir && $bounce_dir ne $new_bounce_dir) {
			unless (move ($bounce_dir,$new_bounce_dir)) {
				Sympa::Log::Syslog::do_log('err',"Unable to rename bounces from $bounce_dir to $new_bounce_dir");
			}
		}

		# if subscribtion are stored in database rewrite the database
		unless (&SDM::do_prepared_query('UPDATE subscriber_table SET list_subscriber = ?, robot_subscriber = ? WHERE list_subscriber = ? AND robot_subscriber = ?', 
						$param{'new_listname'},
						$param{'new_robot'},
						$list->name, $list->domain)) {
			Sympa::Log::Syslog::do_log('err','Unable to rename list %s to %s@%s in the database', $list, $param{'new_listname'}, $param{'new_robot'});
			return 'internal';
		 }
		unless (&SDM::do_prepared_query('UPDATE admin_table SET list_admin = ?, robot_admin = ? WHERE list_admin = ? AND robot_admin = ?', 
						$param{'new_listname'}, 
						$param{'new_robot'},
						$list->name, $list->domain)) {
			Sympa::Log::Syslog::do_log('err','Unable to change admins in database while renaming list %s to %s@%s', $list, $param{'new_listname'}, $param{'new_robot'});
			return 'internal';
		}

		# clear old list cache on database if any
		$list->list_cache_purge;
	}

	my $base = Sympa::Database->get_singleton();

	## Move stats
	my $stat_rows = $base->execute_query(
		"UPDATE stat_table "                .
		"SET list_stat=?, robot_stat=? "    .
		"WHERE list_stat=? AND robot_stat=?",
		$params{'new_listname'},
		$params{'new_robot'},
		$list->{'name'},
		$robot
	);
	unless ($stat_rows) {
		Sympa::Log::Syslog::do_log('err','Unable to transfer stats from list %s@%s to list %s@%s',$params{'new_listname'}, $params{'new_robot'}, $list->{'name'}, $robot);
	}

	## Move stat counters
	my $stat_counters_rows = $base->execute_query(
		"UPDATE stat_counter_table "              .
		"SET list_counter=?, robot_counter=? "    .
		"WHERE list_counter=? AND robot_counter=?",
		$params{'new_listname'},
		$params{'new_robot'},
		$list->{'name'},
		$robot
	);
	unless ($stat_counters_rows) {
		Sympa::Log::Syslog::do_log('err','Unable to transfer stat counter from list %s@%s to list %s@%s',$params{'new_listname'}, $params{'new_robot'}, $list->{'name'}, $robot);
	}

	## Install new aliases
	$params{'listname'} = $params{'new_listname'};

	$list = Sympa::List->new(
		name    => $params{'new_listname'},
		robot   => $params{'new_robot'},
		base    => Sympa::Database->get_singleton(),
		options => {'reload_config' => 1}
	);
	unless ($list) {
		Sympa::Log::Syslog::do_log('err',"Unable to load $params{'new_listname'} while renaming");
		return 'internal';
	}

	## Check custom_subject
     ## Check custom_subject
     if (my $c = $list->custom_subject)
     {   # FIXME MO: this is unsave: check/replace full listname
         if($c =~ /$old_listname/) {
             $c =~ s/$old_listname/$param{new_listname}/g;
	     $list->custom_subject($c);
	     $list->save_config($param{'user_email'});	
         }
     }

	if ($list->{'admin'}{'status'} eq 'open') {
		$params{'aliases'} = install_aliases($list,$robot);
	}

	unless ($params{'mode'} eq 'copy') {

		## Rename files in spools
		## Auth & Mod  spools
		foreach my $spool ('queueauth','queuemod','queuetask','queuebounce',
			'queue','queueoutgoing','queuesubscribe','queueautomatic') {
			unless (opendir(DIR, Site->$spool)) {
				Sympa::Log::Syslog::do_log('err', "Unable to open '%s' spool : %s", Site->$spool, $ERRNO);
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
					$newfile =~ s/^$old_listname\_/$params{'new_listname'}\_/;
				} elsif ($file =~ /^$old_listname\./) {
					$newfile =~ s/^$old_listname\./$params{'new_listname'}\./;
				} elsif ($file =~ /^$old_listname\@$robot\./) {
					$newfile =~ s/^$old_listname\@$robot\./$params{'new_listname'}\@$params{'new_robot'}\./;
				} elsif ($file =~ /^$old_listname\@$robot\_/) {
					$newfile =~ s/^$old_listname\@$robot\_/$params{'new_listname'}\@$params{'new_robot'}\_/;
				} elsif ($file =~ /^\.$old_listname\@$robot\_/) {
					$newfile =~ s/^\.$old_listname\@$robot\_/\.$params{'new_listname'}\@$params{'new_robot'}\_/;
				} elsif ($file =~ /\.$old_listname$/) {
					$newfile =~ s/\.$old_listname$/\.$params{'new_listname'}/;
				}

				## Rename file
				unless (move(Site->$spool . "/$file",
					Site->$spool . "/$newfile")) {
					 Sympa::Log::Syslog::do_log('err', "Unable to rename %s to %s : %s",
					Site->$spool . "/$file",
					Site->$spool . "/$newfile", $!);
					 next;
				 }
				 
				 ## Change X-Sympa-To
				 Sympa::Tools::change_x_sympa_to(Site->$spool . "/$newfile",
					"$param{'new_listname'}\@$param{'new_robot'}");
			}

			close DIR;
		}
		## Digest spool
		 if (-f Site->queuedigest . "/$old_listname") {
			 unless (move(Site->queuedigest . "/$old_listname",
			Site->queuedigest . "/$param{'new_listname'}")) {
			 Sympa::Log::Syslog::do_log('err', "Unable to rename %s to %s : %s", Site->queuedigest . "/$old_listname", Site->queuedigest . "/$param{'new_listname'}", $!);
			 next;
			 }
		 }elsif (-f Site->queuedigest . "/$old_listname\@$robot") {
			 unless (move(Site->queuedigest . "/$old_listname\@$robot",
			Site->queuedigest . "/$param{'new_listname'}\@$param{'new_robot'}")) {
			 Sympa::Log::Syslog::do_log('err', "Unable to rename %s to %s : %s", Site->queuedigest . "/$old_listname\@$robot", Site->queuedigest . "/$param{'new_listname'}\@$param{'new_robot'}", $!);
			 next;
			 }
		 }     
		}

	return 1;
}

=item clone_list_as_empty($source_list_name, $source_robot, $new_listname,
$new_robot, $email)

Clone a list config including customization, templates, scenario config
but without archives, subscribers and shared

Parameters:

=over

=item C<$source_list_name> => the list to clone

=item C<$source_robot> => robot of the list to clone

=item C<$new_listname> => the target list name

=item C<$new_robot> => the target list robot

=item C<$email> => the email of the requestor : used in config as
admin->last_update->email

=back

Return value:

The updated L<Sympa::List> object.

=cut

sub clone_list_as_empty {
	my ($source_list_name, $source_robot, $new_listname, $new_robot, $email)
	= @_;

	my $list = Sympa::List->new(
		name  => $source_list_name,
		robot => $source_robot,
		base  => Sympa::Database->get_singleton(),
	);
	unless ($list) {
		Sympa::Log::Syslog::do_log('err','Admin::clone_list_as_empty : new list failed %s %s',$source_list_name, $source_robot);
		return undef;;
	}

	Sympa::Log::Syslog::do_log('info',"Admin::clone_list_as_empty ($source_list_name, $source_robot,$new_listname,$new_robot,$email)");

	my $new_dir;
	if (-d Site->home.'/'.$new_robot) {
		$new_dir = Site->home.'/'.$new_robot.'/'.$new_listname;
	} elsif ($new_robot eq Site->domain) {
		$new_dir = Site->home.'/'.$new_listname;
	} else {
		Sympa::Log::Syslog::do_log('err',"Admin::clone_list_as_empty : unknown robot $new_robot");
		return undef;
	}

	unless (mkdir $new_dir, 0775) {
		Sympa::Log::Syslog::do_log('err','Admin::clone_list_as_empty : failed to create directory %s : %s',$new_dir, $ERRNO);
		return undef;;
	}
	chmod 0775, $new_dir;
	foreach my $subdir ('etc','web_tt2','mail_tt2','data_sources' ) {
		if (-d $new_dir.'/'.$subdir) {
			unless (Sympa::Tools::File::copy_dir($list->{'dir'}.'/'.$subdir, $new_dir.'/'.$subdir)) {
				Sympa::Log::Syslog::do_log('err','Admin::clone_list_as_empty :  failed to copy_directory %s : %s',$new_dir.'/'.$subdir, $ERRNO);
				return undef;
			}
		}
	}
	# copy mandatory files
	foreach my $file ('config') {
		unless (File::Copy::copy ($list->{'dir'}.'/'.$file, $new_dir.'/'.$file)) {
			Sympa::Log::Syslog::do_log('err','Admin::clone_list_as_empty : failed to copy %s : %s',$new_dir.'/'.$file, $ERRNO);
			return undef;
		}
	}
	# copy optional files
	foreach my $file ('message.footer','message.header','info','homepage') {
		if (-f $list->{'dir'}.'/'.$file) {
			unless (File::Copy::copy ($list->{'dir'}.'/'.$file, $new_dir.'/'.$file)) {
				Sympa::Log::Syslog::do_log('err','Admin::clone_list_as_empty : failed to copy %s : %s',$new_dir.'/'.$file, $ERRNO);
				return undef;
			}
		}
	}

	my $new_list = Sympa::List->new(
		name    => $new_listname,
		robot   => $new_robot,
		base    => Sympa::Database->get_singleton(),
		options => {'reload_config' => 1}
	);
	# now switch List object to new list, update some values
	unless ($new_list) {
		Sympa::Log::Syslog::do_log('info',"Admin::clone_list_as_empty : unable to load $new_listname while renamming");
		return undef;
	}
    $new_list->serial(0);
    my $time = time;
    my $creation = {
		'date_epoch' => $time,
		'date' => (gettext_strftime "%d %b %y at %H:%M:%S", localtime $time)
    };
    ##FIXME: creation.email may be empty
    $creation->{'email'} = $email if $email;
    $new_list->creation($creation);
    $new_list->save_config($email);
    return $new_list;
}


=item check_owner_defined($owner,$owner_include)

Verify if they are any owner defined : it must exist at least one param
owner(in I<$owner>) or one param owner_include (in I<$owner_include>) the owner
param must have sub param email the owner_include param must have sub param
source

Parameters:

=over

=item I<$owner>: arrayref of hashes or hashref

=item I<$owner_include>: arrayref of hashes

=back

Return value:

A true value if the owner exists, I<undef> otherwise.

=cut

sub check_owner_defined {
	my ($owner, $owner_include) = @_;
	Sympa::Log::Syslog::do_log('debug2',"()");

	if (ref($owner) eq "ARRAY") {
		if (ref($owner_include) eq "ARRAY") {
			if (($#{$owner} < 0) && ($#{$owner_include} <0)) {
				Sympa::Log::Syslog::do_log('err','missing list param owner or owner_include');
				return undef;
			}
		} else {
			if (($#{$owner} < 0) && !($owner_include)) {
				Sympa::Log::Syslog::do_log('err','missing list param owner or owner_include');
				return undef;
			}
		}
	} else {
		if (ref($owner_include) eq "ARRAY") {
			if (!($owner) && ($#{$owner_include} <0)) {
				Sympa::Log::Syslog::do_log('err','missing list param owner or owner_include');
				return undef;
			}
		} else {
			if (!($owner) && !($owner_include)) {
				Sympa::Log::Syslog::do_log('err','missing list param owner or owner_include');
				return undef;
			}
		}
	}

	if (ref($owner) eq "ARRAY") {
		foreach my $o (@{$owner}) {
			unless($o){
				Sympa::Log::Syslog::do_log('err','empty param "owner"');
				return undef;
			}
			unless ($o->{'email'}) {
				Sympa::Log::Syslog::do_log('err','missing sub param "email" for param "owner"');
				return undef;
			}
		}
	} elsif (ref($owner) eq "HASH"){
		unless ($owner->{'email'}) {
			Sympa::Log::Syslog::do_log('err','missing sub param "email" for param "owner"');
			return undef;
		}
	} elsif (defined $owner) {
		Sympa::Log::Syslog::do_log('err','missing sub param "email" for param "owner"');
		return undef;
	}

	if (ref($owner_include) eq "ARRAY") {
		foreach my $o (@{$owner_include}) {
			unless($o){
				Sympa::Log::Syslog::do_log('err','empty param "owner_include"');
				return undef;
			}
			unless ($o->{'source'}) {
				Sympa::Log::Syslog::do_log('err','missing sub param "source" for param "owner_include"');
				return undef;
			}
		}
	} elsif (ref($owner_include) eq "HASH"){
		unless ($owner_include->{'source'}) {
			Sympa::Log::Syslog::do_log('err','missing sub param "source" for param "owner_include"');
			return undef;
		}
	} elsif (defined $owner_include) {
		Sympa::Log::Syslog::do_log('err','missing sub param "source" for param "owner_include"');
		return undef;
	}
	return 1;
}


=item list_check_smtp($list, $robot)

Check if the requested list exists already using smtp 'rcpt to'

Parameters:

=over

=item C<$list> => list name

=item C<$robot> => list robot

=back

Return value:

Net::SMTP object or 0

=cut

sub list_check_smtp {
	my $list = shift;
	my $robot = Robot::clean_robot(shift);
	Sympa::Log::Syslog::do_log('debug2', '(%s,%s)',$list,$robot);

	my $conf = '';
	my $smtp;
	my (@suf, @addresses);

	my $smtp_relay = $robot->list_check_smtp;
	my $smtp_helo = $robot->list_check_helo || $smtp_relay;
	$smtp_helo =~ s/:[-\w]+$//;
	my $suffixes = $robot->list_check_suffixes;
	return 0
	unless ($smtp_relay && $suffixes);
	my $domain = $robot->host;
	Sympa::Log::Syslog::do_log('debug2', 'list_check_smtp(%s,%s)', $list, $robot);
	@suf = split(/\s*,\s*/, $suffixes);
	return 0 if ! @suf;
	for(@suf) {
		push @addresses, $list."-$_\@".$domain;
	}
	push @addresses,"$list\@" . $domain;

	eval {
		require Net::SMTP;
	};
	if ($EVAL_ERROR) {
		Sympa::Log::Syslog::do_log ('err',"Unable to use Net library, Net::SMTP required, install it (CPAN) first");
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

=item install_aliases($list, $robot)

Install sendmail aliases for I<$list>.

Parameters:

=over

=item C<$list> => list

=item C<$robot> => list robot

=back

Return value:

A true value if the alias have been installed, I<undef> otherwise.

=cut

sub install_aliases {
	my ($list, $robot) = @_;
	Sympa::Log::Syslog::do_log('debug', "($list->{'name'},$robot)");

	return 1
	if (Site->sendmail_aliases =~ /^none$/i);

    my $alias_manager     = Site->alias_manager;
    my $output_file       = Site->tmpdir . '/aliasmanager.stdout.' . $$;
    my $error_output_file = Site->tmpdir . '/aliasmanager.stderr.' . $$;
    Sympa::Log::Syslog::do_log('debug3', '%s add alias %s@%s for list %s',
	$alias_manager, $list->name, $list->host, $list);

	unless (-x $alias_manager) {
		Sympa::Log::Syslog::do_log('err','Failed to install aliases: %s', $ERRNO);
		return undef;
	}
	system ("$alias_manager add $list->{'name'} $list->{'admin'}{'host'} >$output_file 2>  $error_output_file");
	my $status = $CHILD_ERROR / 256;
	if ($status == 0) {
		Sympa::Log::Syslog::do_log('info','Aliases installed successfully');
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
		Sympa::Log::Syslog::do_log('err','Configuration file %s has errors : %s', Sympa::Constants::CONFIG, $error_output);
	} elsif ($status == 2)  {
		Sympa::Log::Syslog::do_log('err','Internal error : Incorrect call to alias_manager : %s', $error_output);
	} elsif ($status == 3)  {
		Sympa::Log::Syslog::do_log('err','Could not read sympa config file, report to httpd error_log: %s', $error_output);
	} elsif ($status == 4)  {
		Sympa::Log::Syslog::do_log('err','Could not get default domain, report to httpd error_log: %s', $error_output);
	} elsif ($status == 5)  {
		Sympa::Log::Syslog::do_log('err','Unable to append to alias file: %s', $error_output);
	} elsif ($status == 6)  {
		Sympa::Log::Syslog::do_log('err','Unable to run newaliases: %s', $error_output);
	} elsif ($status == 7)  {
		Sympa::Log::Syslog::do_log('err','Unable to read alias file, report to httpd error_log: %s', $error_output);
	} elsif ($status == 8)  {
		Sympa::Log::Syslog::do_log('err','Could not create temporay file, report to httpd error_log: %s', $error_output);
	} elsif ($status == 13) {
		Sympa::Log::Syslog::do_log('info','Some of list aliases already exist: %s', $error_output);
	} elsif ($status == 14) {
		Sympa::Log::Syslog::do_log('err','Can not open lock file, report to httpd error_log: %s', $error_output);
	} elsif ($status == 15) {
		Sympa::Log::Syslog::do_log('err','The parser returned empty aliases: %s', $error_output);
	} else {
		Sympa::Log::Syslog::do_log('err',"Unknown error $status while running alias manager $alias_manager : %s", $error_output);
	}

	return undef;
}


=item remove_aliases($list, $robot)

Remove sendmail aliases for I<$list>.

Parameters:

=over

=item C<$list> => list

=item C<$robot> => list robot

=back

Return value:

I<1> in case of success, the aliases definition as a string otherwise.

=cut

sub remove_aliases {
	my $list = shift;
	Sympa::Log::Syslog::do_log('debug3', '(%s)', @_);

	return 1
	if (Site->sendmail_aliases =~ /^none$/i);

	my $status = $list->remove_aliases();
	my $suffix = $list->robot->return_path_suffix;
	my $aliases;

	unless ($status == 1) {
		Sympa::Log::Syslog::do_log('err','Failed to remove aliases for list %s', $list->{'name'});

		## build a list of required aliases the listmaster should install
		my $libexecdir = Sympa::Constants::LIBEXECDIR;
		my $name = $list->name;
		$aliases = <<EOF;
#----------------- $name
$name: "$libexecdir/queue $name"
$name-request: "|$libexecdir/queue $name-request"
$name$suffix: "|$libexecdir/bouncequeue $name"
$name-unsubscribe: "|$libexecdir/queue $name-unsubscribe"
# $name-subscribe: "|$libexecdir/queue $name-subscribe"
EOF

		return $aliases;
	}

	Sympa::Log::Syslog::do_log('info','Aliases removed successfully');

	return 1;
}

=item check_topics($topic, $robot)

OBSOLETED: Use $robot->is_available_topic().

Parameters:

=over

=item C<$topic> => topic id

=item C<$robot> => the list robot

=back

Return value:

A true value if the topic is in the robot conf, I<undef> otherwise.

=cut

sub check_topics {
    my $topic = shift;
    my $robot = Robot::clean_robot(shift);
    return $robot->is_available_topic($topic);
}

=item change_user_email(%parameters)

Change a user email address for both his memberships and ownerships.

Parameters:

=over

=item C<current_email> => string

The current user email address.

=item C<new_email> => string

The new user email address.

=item C<$robot> => string

The virtual robot

=back

Return value:

I<1>, and the list of lists for which the changes could not be achieved.

=cut

sub change_user_email {
	my (%in) = @_;

	my @failed_for;

	unless ($in{'current_email'} && $in{'new_email'} && $in{'robot'}) {
		Sympa::Log::Syslog::do_log('err','Missing incoming parameter');
		return undef;
	}

	my $robot = Robot::clean_robot($in{'robot'});
	
	## Change email as list MEMBER
	foreach my $list ( Sympa::List::get_which($in{'current_email'},$in{'robot'}, 'member') ) {

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
				if (!defined $datasource || $datasource->{'type'} ne 'include_list' || ($datasource->{'def'} =~ /\@(.+)$/ && $1 ne $robot->domain)) {
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
				Sympa::Log::Syslog::do_log('err', 'could not change member email for list %s because member is included', $l);
				next;
			}
		}

		## Check if user is already member of the list with his new address
		## then we just need to remove the old address
		if ($list->is_list_member($in{'new_email'})) {
			unless ($list->delete_list_member('users' => [$in{'current_email'}]) ) {
				push @failed_for, $list;
				Sympa::Log::Syslog::do_log('info', 'could not remove email from list %s', $l);
			}

		} else {

			unless ($list->update_list_member($in{'current_email'}, {'email' => $in{'new_email'}, 'update_date' => time}) ) {
				push @failed_for, $list;
				Sympa::Log::Syslog::do_log('err', 'could not change email for list %s', $l);
			}
		}
	}

	## Change email as list OWNER/MODERATOR
	my %updated_lists;
	foreach my $role ('owner', 'editor') {
		foreach my $list ( Sympa::List::get_which($in{'current_email'},$in{'robot'}, $role) ) {

			## Check if admin is include via an external datasource
			my $admin_user = $list->get_list_admin($role, $in{'current_email'});
			if ($admin_user->{'included'}) {
				## Notify listmaster
				$robot->send_notify_to_listmaster('failed_to_change_included_admin',{'list' => $list,
						'current_email' => $in{'current_email'},
						'new_email' => $in{'new_email'},
						'datasource' => $list->get_datasource_name($admin_user->{'id'})});
				push @failed_for, $list;
				Sympa::Log::Syslog::do_log('err', 'could not change %s email for list %s because admin is included', $role, $list->{'name'});
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
		$robot->send_notify_to_listmaster('listowner_email_changed',
			{'previous_email' => $in{'current_email'},
				'new_email' => $in{'new_email'},
				'updated_lists' => keys %updated_lists})
	}

    ## Update User_table and remove existing entry first (to avoid duplicate entries)
    my $oldu = User->new($in{'new_email'});
    $oldu->expire if $oldu;
    my $u = User->new($in{'current_email'});
    unless ($u and $u->moveto($in{'new_mail'})) {
		Sympa::Log::Syslog::do_log('err','change_email: update failed');
		return undef;
    }
    
    ## Update netidmap_table
    unless ( $robot->update_email_netidmap_db($in{'current_email'}, $in{'new_email'}) ){
		Sympa::Log::Syslog::do_log('err','change_email: update failed');
		return undef;
	}


	return (1,\@failed_for);
}

=back

=head1 AUTHORS

=over

=item * Serge Aumont <sa AT cru.fr>

=item * Olivier Salaun <os AT cru.fr>

=back

=cut

1;
