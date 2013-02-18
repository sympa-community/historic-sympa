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

Sympa::Tools::File - File-related functions

=head1 DESCRIPTION

This module provides various file-releated functions.

=cut

package Sympa::Tools::File;

use strict;

use Encode::Guess;
use English qw(-no_match_vars);
use File::Copy::Recursive;
use File::Find;
use POSIX qw();

use Sympa::Log;

=head1 FUNCTIONS

=head2 set_file_rights(%param)

Sets owner and/or access rights on a file.

=cut

sub set_file_rights {
    my (%params) = @_;

    my ($uid, $gid);

    if ($params{'user'}){
	unless ($uid = (getpwnam($params{'user'}))[2]) {
	    Sympa::Log::do_log('err', "User %s can't be found in passwd file",$params{'user'});
	    return undef;
	}
    }else {
	$uid = -1;# "A value of -1 is interpreted by most systems to leave that value unchanged".
    }
    if ($params{'group'}) {
	unless ($gid = (getgrnam($params{'group'}))[2]) {
	    Sympa::Log::do_log('err', "Group %s can't be found",$params{'group'});
	    return undef;
	}
    }else {
	$gid = -1;# "A value of -1 is interpreted by most systems to leave that value unchanged".
    }
    unless (chown($uid,$gid, $params{'file'})){
	Sympa::Log::do_log('err', "Can't give ownership of file %s to %s.%s: %s",$params{'file'},$params{'user'},$params{'group'}, $ERRNO);
	return undef;
    }
    if ($params{'mode'}){
	unless (chmod($params{'mode'}, $params{'file'})){
	    Sympa::Log::do_log('err', "Can't change rights of file %s: %s",$params{'file'}, $ERRNO);
	    return undef;
	}
    }
    return 1;
}

=head2 copy_dir($dir1, $dir2)

Copy a directory and its content

=cut

sub copy_dir {
    my ($dir1, $dir2) = @_;
    Sympa::Log::do_log('debug','Copy directory %s to %s',$dir1,$dir2);

    unless (-d $dir1){
	Sympa::Log::do_log('err',"Directory source '%s' doesn't exist. Copy impossible",$dir1);
	return undef;
    }
    return (File::Copy::Recursive::dircopy($dir1,$dir2)) ;
}

=head2 del_dir($dir)

Delete a directory and its content.

=cut

sub del_dir {
    my ($dir) = @_;
    Sympa::Log::do_log('debug','%s',$dir);

    if(opendir DIR, $dir){
	for (readdir DIR) {
	    next if /^\.{1,2}$/;
	    my $path = "$dir/$_";
	    unlink $path if -f $path;
	    del_dir($path) if -d $path;
	}
	closedir DIR;
	unless(rmdir $dir) {Sympa::Log::do_log('err','Unable to delete directory %s: $ERRNO',$dir);}
    }else{
	Sympa::Log::do_log('err','Unable to open directory %s to delete the files it contains: $ERRNO',$dir);
    }
}

=head2 mk_parent_dir($file)

To be used before creating a file in a directory that may not exist already.

=cut

sub mk_parent_dir {
    my ($file) = @_;

    $file =~ /^(.*)\/([^\/])*$/ ;
    my $dir = $1;

    return 1 if (-d $dir);
    mkdir_all($dir, 0755);
}

=head2 mkdir_all($path, $mode)

Recursively create directory and all parent directories

=cut

sub mkdir_all {
    my ($path, $mode) = @_;

    my $status = 1;

    ## Change umask to fully apply modes of mkdir()
    my $saved_mask = umask;
    umask 0000;

    return undef if ($path eq '');
    return 1 if (-d $path);

    ## Compute parent path
    my @token = split /\//, $path;
    pop @token;
    my $parent_path = join '/', @token;

    unless (-d $parent_path) {
	unless (mkdir_all($parent_path, $mode)) {
	    $status = undef;
	}
    }

    if (defined $status) { ## Don't try if parent dir could not be created
	unless (mkdir ($path, $mode)) {
	    $status = undef;
	}
    }

    ## Restore umask
    umask $saved_mask;

    return $status;
}

=head2 shift_file($file, $count)

Shift file renaming it with date. If count is defined, keep $count file and
unlink others

=cut

sub shift_file {
    my ($file, $count) = @_;
    Sympa::Log::do_log('debug', "($file,$count)");

    unless (-f $file) {
	Sympa::Log::do_log('info', "unknown file $file");
	return undef;
    }

    my @date = localtime (time);
    my $file_extention = POSIX::strftime("%Y:%m:%d:%H:%M:%S", @date);

    unless (rename ($file,$file.'.'.$file_extention)) {
	Sympa::Log::do_log('err', "Cannot rename file $file to $file.$file_extention" );
	return undef;
    }
    if ($count) {
	$file =~ /^(.*)\/([^\/])*$/ ;
	my $dir = $1;

	unless (opendir(DIR, $dir)) {
	    Sympa::Log::do_log('err', "Cannot read dir $dir" );
	    return ($file.'.'.$file_extention);
	}
	my $i = 0 ;
	foreach my $oldfile (reverse (sort (grep (/^$file\./,readdir(DIR))))) {
	    $i ++;
	    if ($count lt $i) {
		if (unlink ($oldfile)) {
		    Sympa::Log::do_log('info', "unlink $oldfile");
		}else{
		    Sympa::Log::do_log('info', "unable to unlink $oldfile");
		}
	    }
	}
    }
    return ($file.'.'.$file_extention);
}

=head2 find_file($filename, @directories)

Find a file in an ordered list of directories

=cut

sub find_file {
    my ($filename, @directories) = @_;
    Sympa::Log::do_log('debug3','(%s,%s)', $filename, join(':',@directories));

    foreach my $d (@directories) {
	if (-f "$d/$filename") {
	    return "$d/$filename";
	}
    }

    return undef;
}

=head2 list_dir($dir, $all)

Recursively list the content of a directory
Return an array of hash, each entry with directory + filename + encoding

=cut

sub list_dir {
    my ($dir, $all, $original_encoding) = @_;

    if (opendir(DIR, $dir)) {
	foreach my $file ( sort grep (!/^\.\.?$/,readdir(DIR))) {

	    ## Guess filename encoding
	    my ($encoding, $guess);
	    my $decoder = Encode::Guess::guess_encoding($file, $original_encoding, 'utf-8');
	    if (ref $decoder) {
		$encoding = $decoder->name;
	    }else {
		$guess = $decoder;
	    }

	    push @$all, {'directory' => $dir,
			 'filename' => $file,
			 'encoding' => $encoding,
			 'guess' => $guess};
	    if (-d "$dir/$file") {
		list_dir($dir.'/'.$file, $all, $original_encoding);
	    }
	}
        closedir DIR;
    }

    return 1;
}

=head2 get_dir_size($dir)

Get the total size for the given directory.

=cut

sub get_dir_size {
    my ($dir) = @_;

    my $size=0;

    if (opendir(DIR, $dir)) {
	foreach my $file ( sort grep (!/^\./,readdir(DIR))) {
	    if (-d "$dir/$file") {
		$size += get_dir_size("$dir/$file");
	    }
	    else{
		my @info = stat "$dir/$file" ;
		$size += $info[7];
	    }
	}
        closedir DIR;
    }

    return $size;
}

=head2 remove_dir(@directories)

Function for Removing a non-empty directory.
It takes a variale number of arguments :
it can be a list of directory
or few direcoty paths

=cut

sub remove_dir {

    Sympa::Log::do_log('debug2','()');

    my $callback = sub  {
	my $name = $File::Find::name;

	if (!-l && -d _) {
	    unless (rmdir($name)) {
		Sympa::Log::do_log('err','Error while removing dir %s',$name);
	    }
	}else{
	    unless (unlink($name)) {
		Sympa::Log::do_log('err','Error while removing file  %s',$name);
	    }
	}
    };

    foreach my $current_dir (@_){
	finddepth({wanted => $callback, no_chdir => 1},$current_dir);
    }

    return 1;
}

=head2 a_is_older_than_b($parameters)

Compares the last modifications date of two files

=head3 Parameters

=over

=item * I<a_file>: full path to a file

=item * I<b_file>: full path to a file

=back

=head3 Return value

The string 'true' if the last modification date of first file is older
than second file, the 'false' string otherwise, and undef if the comparison
could not be carried on.

=cut

sub a_is_older_than_b {
    my ($params) = @_;

    my ($a_file_readable, $b_file_readable) = (0,0);
    my $answer = undef;
    if (-r $params->{'a_file'}) {
	$a_file_readable = 1;
    }else{
	Sympa::Log::do_log('err', 'Could not read file "%s". Comparison impossible', $params->{'a_file'});
    }
    if (-r $params->{'b_file'}) {
	$b_file_readable = 1;
    }else{
	Sympa::Log::do_log('err', 'Could not read file "%s". Comparison impossible', $params->{'b_file'});
    }
    if ($a_file_readable && $b_file_readable) {
	my @a_stats = stat ($params->{'a_file'});
	my @b_stats = stat ($params->{'b_file'});
	if($a_stats[9] < $b_stats[9]){
	    $answer = 1;
	}else{
	    $answer = 0;
	}
    }
    return $answer;
}

=head2 slurp_file($file)

Read the whole content of a file.

=head3 Parameters

=over

=item * I<$file>: file to read

=back

=head3 Return value

The file content as a string on success, I<undef> otherwise.

=cut

sub slurp_file {
	my ($file) = @_;

	open(my $handle, '<', $file)
		or return undef;
	local $RS; # enable localized slurp mode
	my $content = <$handle>;
	close($handle);

	return $content;
}

1;
