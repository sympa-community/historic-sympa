# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
# Copyright (c) 1997,1998, 1999 Institut pasteur & Christophe Wolfhugel
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

Sympa::SharedDocument - Shared document object

=head1 DESCRIPTION

This class implements a web-shared document.

=cut

package Sympa::SharedDocument;

use strict;

use Carp;
use English qw(-no_match_vars);
use POSIX qw();

use Sympa::Log;
use Sympa::Tools;
use Sympa::Tools::Data;

=head1 CLASS METHODS

=head2 Sympa::SharedDocument->new($list, $path, $params)

Creates a new L<Sympa::SharedDocument> object.

=head3 Parameters

=over

=item * I<$list>

=item * I<$path>

=item * I<$params>

=back

=head3 Return

A new L<Sympa::SharedDocument> object, or I<undef>, if something went wrong.

=cut

sub new {
    my ($class, $list, $path, $params) = @_;

    my $email = $params->{'user'}{'email'};
    #$email ||= 'nobody';
    Sympa::Log::do_log('debug2', '(%s, %s)', $list->{'name'}, $path);

    unless (ref($list) && $list->isa('Sympa::List')) {
	Sympa::Log::do_log('err', 'incorrect list parameter');
	return undef;
    }

    $path = main::no_slash_end($path);

    my $self = {
	    root_path    => $list->{'dir'}.'/shared',
	    path         => $path,
	    escaped_path => Sympa::Tools::escape_chars($path, '/')
    };

    ### Document isn't a description file
    if ($self->{path} =~ /\.desc/) {
	Sympa::Log::do_log('err',"%s: description file", $self->{path});
	return undef;
    }

    ## absolute path
    # my $doc;
    $self->{'absolute_path'} = $self->{'root_path'};
    if ($self->{'path'}) {
	$self->{'absolute_path'} .= '/'.$self->{'path'};
    }

    ## Check access control
    check_access_control($self, $params);

    ###############################
    ## The path has been checked ##
    ###############################

    ### Document exist ?
    unless (-r $self->{'absolute_path'}) {
	Sympa::Log::do_log('err',"unable to read %s : no such file or directory", $self->{'absolute_path'});
	return undef;
    }

    ### Document has non-size zero?
    unless (-s $self->{'absolute_path'}) {
	Sympa::Log::do_log('err',"unable to read %s : empty document", $self->{'absolute_path'});
	return undef;
    }

    $self->{'visible_path'} = main::make_visible_path($self->{'path'});

    ## Date
    my @info = stat $self->{'absolute_path'};
    $self->{'date'} =  POSIX::strftime("%d %b %Y", localtime($info[9]));
    $self->{'date_epoch'} =  $info[9];

    # Size of the doc
    $self->{'size'} = (-s $self->{'absolute_path'}) / 1000;

    ## Filename
    my @tokens = split /\//, $self->{'path'};
    $self->{'filename'} = $self->{'visible_filename'} = $tokens[$#tokens];

    ## Moderated document
    if ($self->{'filename'} =~ /^\.(.*)(\.moderate)$/) {
	$self->{'moderate'} = 1;
	$self->{'visible_filename'} = $1;
    }

    $self->{'escaped_filename'} =  Sympa::Tools::escape_chars($self->{'filename'});

    ## Father dir
    if ($self->{'path'} =~ /^(([^\/]*\/)*)([^\/]+)$/) {
	$self->{'father_path'} = $1;
    }else {
	$self->{'father_path'} = '';
    }
    $self->{'escaped_father_path'} = Sympa::Tools::escape_chars($self->{'father_path'}, '/');


    ### File, directory or URL ?
    if (! (-d $self->{'absolute_path'})) {

	if ($self->{'filename'} =~ /^\..*\.(\w+)\.moderate$/) {
	    $self->{'file_extension'} = $1;
	}elsif ($self->{'filename'} =~ /^.*\.(\w+)$/) {
	    $self->{'file_extension'} = $1;
	 }

	if ($self->{'file_extension'} eq 'url') {
	    $self->{'type'} = 'url';
	}else {
	    $self->{'type'} = 'file';
	}
    }else {
	$self->{'type'} = 'directory';
    }

    ## Load .desc file unless root directory
    my $desc_file;
    if ($self->{'type'} eq 'directory') {
	$desc_file = $self->{'absolute_path'}.'/.desc';
    }else {
	if ($self->{'absolute_path'} =~ /^(([^\/]*\/)*)([^\/]+)$/) {
	    $desc_file = $1.'.desc.'.$3;
	}else {
	    Sympa::Log::do_log('err',"cannot determine desc file for %s", $self->{'absolute_path'});
	    return undef;
	}
    }

    if ($self->{'path'} && (-e $desc_file)) {
	my @info = stat $desc_file;
	$self->{'serial_desc'} = $info[9];

	my %desc_hash = main::get_desc_file($desc_file);
	$self->{'owner'} = $desc_hash{'email'};
	    $self->{'title'} = $desc_hash{'title'};
	$self->{'escaped_title'} = Sympa::Tools::escape_html($self->{'title'});

	# Author
	if ($desc_hash{'email'}) {
	    $self->{'author'} = $desc_hash{'email'};
	    $self->{'author_mailto'} = main::mailto($list,$desc_hash{'email'});
	    $self->{'author_known'} = 1;
	}
    }


   ### File, directory or URL ?
    if ($self->{'type'} eq 'url') {

	$self->{'icon'} = main::get_icon('url');

	open DOC, $self->{'absolute_path'};
	my $url = <DOC>;
	close DOC;
	chomp $url;
	$self->{'url'} = $url;

	if ($self->{'filename'} =~ /^(.+)\.url/) {
	    $self->{'anchor'} = $1;
	}
    }elsif ($self->{'type'} eq 'file') {

	if (my $type = main::get_mime_type($self->{'file_extension'})) {
	    # type of the file and apache icon
	    if ($type =~ /^([\w\-]+)\/([\w\-]+)$/) {
		my ($mimet, $subt) = ($1, $2);
		    if ($subt) {
			if ($subt =~  /^octet-stream$/) {
			    $mimet = 'octet-stream';
			    $subt = 'binary';
			}
			$type = "$subt file";
		    }
		$self->{'icon'} = main::get_icon($mimet) || main::get_icon('unknown');
	    }
	} else {
	    # unknown file type
	    $self->{'icon'} = main::get_icon('unknown');
	}

	## HTML file
	if ($self->{'file_extension'} =~ /^html?$/i) {
	    $self->{'html'} = 1;
	    $self->{'icon'} = main::get_icon('text');
	}

	## Directory
    }else {

	$self->{'icon'} = main::get_icon('folder');

	# listing of all the shared documents of the directory
	unless (opendir DIR, $self->{'absolute_path'}) {
	    Sympa::Log::do_log('err',"cannot open %s : %s", $self->{'absolute_path'}, $ERRNO);
	    return undef;
	}

	# array of entry of the directory DIR
	my @tmpdir = readdir DIR; closedir DIR;

	my $dir = main::get_directory_content(\@tmpdir, $email, $list, $self->{'absolute_path'});

	foreach my $d (@{$dir}) {

	    my $sub_document = Sympa::SharedDocument->new($list,
		    $self->{'path'}.'/'.$d, $params);
	    push @{$self->{'subdir'}}, $sub_document;
	}
    }

    $self->{'list'} = $list;

    bless $self, $class;

    return $self;
}

sub dump {
    my ($self, $fd) = @_;

    Sympa::Tools::Data::dump_var($self, 0, $fd);

}

sub dup {
    my ($self) = @_;

    my $copy = {};

    foreach my $k (keys %$self ) {
	$copy->{$k} = $self->{$k};
    }

    return $copy;
}

 ## Regulars
 #  read(/) = default (config list)
 #  edit(/) = default (config list)
 #  control(/) = not defined
#  read(A/B)= (read(A) && read(B)) ||
 #             (author(A) || author(B))
 #  edit = idem read
 #  control (A/B) : author(A) || author(B)
 #  + (set owner A/B) if (empty directory &&
 #                        control A)


sub check_access_control {
    my ($self, $params) = @_;
    Sympa::Log::do_log('debug', "check_access_control(%s)", $self->{'path'});

    # Arguments:
    # (\%mode,$path)
    # if mode->{'read'} control access only for read
    # if mode->{'edit'} control access only for edit
    # if mode->{'control'} control access only for control

    # return the hash (
    # $result{'may'}{'read'} == $result{'may'}{'edit'} == $result{'may'}{'control'}  if is_author else :
    # $result{'may'}{'read'} = 0 or 1 (right or not)
    # $result{'may'}{'edit'} = 0(not may edit) or 0.5(may edit with moderation) or 1(may edit ) : it is not a boolean anymore
    # $result{'may'}{'control'} = 0 or 1 (right or not)
    # $result{'reason'}{'read'} = string for authorization_reject.tt2 when may_read == 0
    # $result{'reason'}{'edit'} = string for authorization_reject.tt2 when may_edit == 0
    # $result{'scenario'}{'read'} = scenario name for the document
    # $result{'scenario'}{'edit'} = scenario name for the document

    # Result
    my %result;
    $result{'reason'} = {};

    # Control

    my $list = $self->{'list'};

    # Control for editing
    my $may_read = 1;
    my $why_not_read = '';
    my $may_edit = 1;
    my $why_not_edit = '';

    ## First check privileges on the root shared directory
    $result{'scenario'}{'read'} = $list->{'admin'}{'shared_doc'}{'d_read'}{'name'};
    $result{'scenario'}{'edit'} = $list->{'admin'}{'shared_doc'}{'d_edit'}{'name'};

    ## Privileged owner has all privileges
    if ($params->{'is_privileged_owner'}) {
	$result{'may'}{'read'} = 1;
	$result{'may'}{'edit'} = 1;
	$result{'may'}{'control'} = 1;

	$self->{'access'} = \%result;
	return 1;
    }

    # if not privileged owner
    if (1) {
	my $result = $list->check_list_authz('shared_doc.d_read',$params->{'auth_method'},
					     {'sender' => $params->{'user'}{'email'},
					      'remote_host' => $params->{'remote_host'},
					      'remote_addr' => $params->{'remote_addr'}});
	my $action;
	if (ref($result) eq 'HASH') {
	    $action = $result->{'action'};
	    $why_not_read = $result->{'reason'};
	}

	$may_read = ($action =~ /do_it/i);
    }

    if (1) {
	my $result = $list->check_list_authz('shared_doc.d_edit',$params->{'auth_method'},
					     {'sender' => $params->{'user'}{'email'},
					      'remote_host' => $params->{'remote_host'},
					      'remote_addr' => $params->{'remote_addr'}});
	my $action;
	if (ref($result) eq 'HASH') {
	    $action = $result->{'action'};
	    $why_not_edit = $result->{'reason'};
	}

	#edit = 0, 0.5 or 1
	$may_edit = main::find_edit_mode($action);
	$why_not_edit = '' if ($may_edit);
    }

    ## Only authenticated users can edit files
    unless ($params->{'user'}{'email'}) {
	$may_edit = 0;
	$why_not_edit = 'not_authenticated';
    }

    my $current_path = $self->{'path'};
    my $current_document;
    my %desc_hash;
    my $user = $params->{'user'}{'email'} || 'nobody';

    while ($current_path ne "") {
	# no description file found yet
	my $def_desc_file = 0;
	my $desc_file;

	$current_path =~ /^(([^\/]*\/)*)([^\/]+)(\/?)$/;
	$current_document = $3;
	my $next_path = $1;

	# opening of the description file appropriated
	if (-d $self->{'root_path'}.'/'.$current_path) {
	    # case directory

	    #		unless ($slash) {
	    $current_path = $current_path.'/';
	    #		}

	    if (-e "$self->{'root_path'}/$current_path.desc"){
		$desc_file = $self->{'root_path'}.'/'.$current_path.".desc";
		$def_desc_file = 1;
	    }

	}else {
	    # case file
	    if (-e "$self->{'root_path'}/$next_path.desc.$3"){
		$desc_file = $self->{'root_path'}.'/'.$next_path.".desc.".$3;
		$def_desc_file = 1;
	    }
	}

	if ($def_desc_file) {
	    # a description file was found
	    # loading of acces information

	    %desc_hash = main::get_desc_file($desc_file);

	    ## Author has all privileges
	    if ($user eq $desc_hash{'email'}) {
		$result{'may'}{'read'} = 1;
		$result{'may'}{'edit'} = 1;
		$result{'may'}{'control'} = 1;

		$self->{'access'} = \%result;
		return 1;
	    }

	    if (1) {

		my $result =
		$list->check_list_authz('shared_doc.d_read',$params->{'auth_method'},
						     {'sender' => $params->{'user'}{'email'},
						      'remote_host' => $params->{'remote_host'},
						      'remote_addr' => $params->{'remote_addr'},
						      'scenario'=> $desc_hash{'read'}});
		my $action;
		if (ref($result) eq 'HASH') {
		    $action = $result->{'action'};
		    $why_not_read = $result->{'reason'};
		}

		$may_read = $may_read && ( $action=~ /do_it/i);
		$why_not_read = '' if ($may_read);
	    }

	    if (1) {
		my $result =
		$list->check_list_authz('shared_doc.d_edit',$params->{'auth_method'},
						     {'sender' => $params->{'user'}{'email'},
						      'remote_host' => $params->{'remote_host'},
						      'remote_addr' => $params->{'remote_addr'},
						      'scenario'=> $desc_hash{'edit'}});
		my $action_edit;
		if (ref($result) eq 'HASH') {
		    $action_edit = $result->{'action'};
		    $why_not_edit = $result->{'reason'};
		}


		# $may_edit = 0, 0.5 or 1
		my $may_action_edit = main::find_edit_mode($action_edit);
		$may_edit = main::merge_edit($may_edit,$may_action_edit);
		$why_not_edit = '' if ($may_edit);


	    }

	    ## Only authenticated users can edit files
	    unless ($params->{'user'}{'email'}) {
		$may_edit = 0;
		$why_not_edit = 'not_authenticated';
	    }

	    unless (defined $result{'scenario'}{'read'}) {
		$result{'scenario'}{'read'} = $desc_hash{'read'};
		$result{'scenario'}{'edit'} = $desc_hash{'edit'};
	    }

	}

	# truncate the path for the while
	$current_path = $next_path;
    }

    if (1) {
	$result{'may'}{'read'} = $may_read;
	$result{'reason'}{'read'} = $why_not_read;
    }

    if (1) {
	  $result{'may'}{'edit'} = $may_edit;
	  $result{'reason'}{'edit'} = $why_not_edit;
      }

    $self->{'access'} = \%result;
    return 1;
}

1;
