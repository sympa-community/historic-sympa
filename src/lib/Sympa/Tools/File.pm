# RCS Identication ; $Revision: 7745 $ ; $Date: 2012-10-15 18:08:04 +0200 (lun. 15 oct. 2012) $ 
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

package Sympa::Tools::File;

use strict;

use Encode::Guess;
use File::Copy::Recursive;
use File::Find;
use POSIX qw();

use Sympa::Log;

sub set_file_rights {
    my %param = @_;
    my ($uid, $gid);

    if ($param{'user'}){
	unless ($uid = (getpwnam($param{'user'}))[2]) {
	    &Sympa::Log::do_log('err', "User %s can't be found in passwd file",$param{'user'});
	    return undef;
	}
    }else {
	$uid = -1;# "A value of -1 is interpreted by most systems to leave that value unchanged".
    }
    if ($param{'group'}) {
	unless ($gid = (getgrnam($param{'group'}))[2]) {
	    &Sympa::Log::do_log('err', "Group %s can't be found",$param{'group'});
	    return undef;
	}
    }else {
	$gid = -1;# "A value of -1 is interpreted by most systems to leave that value unchanged".
    }
    unless (chown($uid,$gid, $param{'file'})){
	&Sympa::Log::do_log('err', "Can't give ownership of file %s to %s.%s: %s",$param{'file'},$param{'user'},$param{'group'}, $!);
	return undef;
    }
    if ($param{'mode'}){
	unless (chmod($param{'mode'}, $param{'file'})){
	    &Sympa::Log::do_log('err', "Can't change rights of file %s: %s",$param{'file'}, $!);
	    return undef;
	}
    }
    return 1;
}

sub copy_dir {
    my $dir1 = shift;
    my $dir2 = shift;
    &Sympa::Log::do_log('debug','Copy directory %s to %s',$dir1,$dir2);

    unless (-d $dir1){
	&Sympa::Log::do_log('err',"Directory source '%s' doesn't exist. Copy impossible",$dir1);
	return undef;
    }
    return (&File::Copy::Recursive::dircopy($dir1,$dir2)) ;
}

sub del_dir {
    my $dir = shift;
    &Sympa::Log::do_log('debug','del_dir %s',$dir);
    
    if(opendir DIR, $dir){
	for (readdir DIR) {
	    next if /^\.{1,2}$/;
	    my $path = "$dir/$_";
	    unlink $path if -f $path;
	    del_dir($path) if -d $path;
	}
	closedir DIR;
	unless(rmdir $dir) {&Sympa::Log::do_log('err','Unable to delete directory %s: $!',$dir);}
    }else{
	&Sympa::Log::do_log('err','Unable to open directory %s to delete the files it contains: $!',$dir);
    }
}

sub mk_parent_dir {
    my $file = shift;
    $file =~ /^(.*)\/([^\/])*$/ ;
    my $dir = $1;

    return 1 if (-d $dir);
    &mkdir_all($dir, 0755);
}

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
	unless (&mkdir_all($parent_path, $mode)) {
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

sub shift_file {
    my $file = shift;
    my $count = shift;
    &Sympa::Log::do_log('debug', "shift_file ($file,$count)");

    unless (-f $file) {
	&Sympa::Log::do_log('info', "shift_file : unknown file $file");
	return undef;
    }
    
    my @date = localtime (time);
    my $file_extention = POSIX::strftime("%Y:%m:%d:%H:%M:%S", @date);
    
    unless (rename ($file,$file.'.'.$file_extention)) {
	&Sympa::Log::do_log('err', "shift_file : Cannot rename file $file to $file.$file_extention" );
	return undef;
    }
    if ($count) {
	$file =~ /^(.*)\/([^\/])*$/ ;
	my $dir = $1;

	unless (opendir(DIR, $dir)) {
	    &Sympa::Log::do_log('err', "shift_file : Cannot read dir $dir" );
	    return ($file.'.'.$file_extention);
	}
	my $i = 0 ;
	foreach my $oldfile (reverse (sort (grep (/^$file\./,readdir(DIR))))) {
	    $i ++;
	    if ($count lt $i) {
		if (unlink ($oldfile)) { 
		    &Sympa::Log::do_log('info', "shift_file : unlink $oldfile");
		}else{
		    &Sympa::Log::do_log('info', "shift_file : unable to unlink $oldfile");
		}
	    }
	}
    }
    return ($file.'.'.$file_extention);
}

sub find_file {
    my ($filename, @directories) = @_;
    &Sympa::Log::do_log('debug3','tools::find_file(%s,%s)', $filename, join(':',@directories));

    foreach my $d (@directories) {
	if (-f "$d/$filename") {
	    return "$d/$filename";
	}
    }
    
    return undef;
}

sub list_dir {
    my $dir = shift;
    my $all = shift;
    my $original_encoding = shift; ## Suspected original encoding of filenames

    my $size=0;

    if (opendir(DIR, $dir)) {
	foreach my $file ( sort grep (!/^\.\.?$/,readdir(DIR))) {

	    ## Guess filename encoding
	    my ($encoding, $guess);
	    my $decoder = &Encode::Guess::guess_encoding($file, $original_encoding, 'utf-8');
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
		&list_dir($dir.'/'.$file, $all, $original_encoding);
	    }
	}
        closedir DIR;
    }

    return 1;
}

sub get_dir_size {
    my $dir =shift;
    
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

sub remove_dir {
    
    &Sympa::Log::do_log('debug2','remove_dir()');
    
    foreach my $current_dir (@_){
	finddepth({wanted => \&del, no_chdir => 1},$current_dir);
    }
    sub del {
	my $name = $File::Find::name;

	if (!-l && -d _) {
	    unless (rmdir($name)) {
		&Sympa::Log::do_log('err','Error while removing dir %s',$name);
	    }
	}else{
	    unless (unlink($name)) {
		&Sympa::Log::do_log('err','Error while removing file  %s',$name);
	    }
	}
    }
    return 1;
}


sub LOCK_SH {1};
sub LOCK_EX {2};
sub LOCK_NB {4};
sub LOCK_UN {8};

sub lock {
    my $lock_file = shift;
    my $mode = shift; ## read or write
    
    my $operation; # 
    my $open_mode;

    if ($mode eq 'read') {
	$operation = LOCK_SH;
    }else {
	$operation = LOCK_EX;
	$open_mode = '>>';
    }
    
    ## Read access to prevent "Bad file number" error on Solaris
    unless (open FH, $open_mode.$lock_file) {
	&Sympa::Log::do_log('err', 'Cannot open %s: %s', $lock_file, $!);
	return undef;
    }
    
    my $got_lock = 1;
    unless (flock (FH, $operation | LOCK_NB)) {
	&Sympa::Log::do_log('notice','Waiting for %s lock on %s', $mode, $lock_file);

	## If lock was obtained more than 20 minutes ago, then force the lock
	if ( (time - (stat($lock_file))[9] ) >= 60*20) {
	    &Sympa::Log::do_log('notice','Removing lock file %s', $lock_file);
	    unless (unlink $lock_file) {
		&Sympa::Log::do_log('err', 'Cannot remove %s: %s', $lock_file, $!);
		return undef;	    		
	    }
	    
	    unless (open FH, ">$lock_file") {
		&Sympa::Log::do_log('err', 'Cannot open %s: %s', $lock_file, $!);
		return undef;	    
	    }
	}

	$got_lock = undef;
	my $max = 10;
	$max = 2 if ($ENV{'HTTP_HOST'}); ## Web context
	for (my $i = 1; $i < $max; $i++) {
	    sleep (10 * $i);
	    if (flock (FH, $operation | LOCK_NB)) {
		$got_lock = 1;
		last;
	    }
	    &Sympa::Log::do_log('notice','Waiting for %s lock on %s', $mode, $lock_file);
	}
    }
	
    if ($got_lock) {
	&Sympa::Log::do_log('debug2', 'Got lock for %s on %s', $mode, $lock_file);

	## Keep track of the locking PID
	if ($mode eq 'write') {
	    print FH "$$\n";
	}
    }else {
	&Sympa::Log::do_log('err', 'Failed locking %s: %s', $lock_file, $!);
	return undef;
    }

    return \*FH;
}

sub unlock {
    my $lock_file = shift;
    my $fh = shift;
    
    unless (flock($fh,LOCK_UN)) {
	&Sympa::Log::do_log('err', 'Failed UNlocking %s: %s', $lock_file, $!);
	return undef;
    }
    close $fh;
    &Sympa::Log::do_log('debug2', 'Release lock on %s', $lock_file);
    
    return 1;
}

sub a_is_older_than_b {
    my $param = shift;
    my ($a_file_readable, $b_file_readable) = (0,0);
    my $answer = undef;
    if (-r $param->{'a_file'}) {
	$a_file_readable = 1;
    }else{
	&Sympa::Log::do_log('err', 'Could not read file "%s". Comparison impossible', $param->{'a_file'});
    }
    if (-r $param->{'b_file'}) {
	$b_file_readable = 1;
    }else{
	&Sympa::Log::do_log('err', 'Could not read file "%s". Comparison impossible', $param->{'b_file'});
    }
    if ($a_file_readable && $b_file_readable) {
	my @a_stats = stat ($param->{'a_file'});
	my @b_stats = stat ($param->{'b_file'});
	if($a_stats[9] < $b_stats[9]){
	    $answer = 1;
	}else{
	    $answer = 0;
	}
    }
    return $answer;
}

1;
__END__
=head1 NAME

Sympa::Tools::File - File-related functions

=head1 DESCRIPTION

This module provides various file-releated functions.

=head1 FUNCTIONS

=head2 set_file_rights(%param)

Sets owner and/or access rights on a file.

=head2 copy_dir($dir1, $dir2)

Copy a directory and its content

=head2 del_dir($dir)

Delete a directory and its content.

=head2 mk_parent_dir($file)

To be used before creating a file in a directory that may not exist already. 

=head2 mkdir_all($path, $mode)

Recursively create directory and all parent directories

=head shift_file($file, $count)

Shift file renaming it with date. If count is defined, keep $count file and
unlink others

=head2 find_file($filename, @directories)

Find a file in an ordered list of directories

=head2 list_dir($dir, $all)

Recursively list the content of a directory
Return an array of hash, each entry with directory + filename + encoding

=head2 remove_dir(@directories)

Function for Removing a non-empty directory.
It takes a variale number of arguments : 
it can be a list of directory
or few direcoty paths

=head2 lock($file)

Lock a file.

=head2 unlock($file, $handle)

Unlock a file. 

=head2 a_is_older_than_b($param)

Compares the last modifications date of two files

Parameters (hashref keys):

=over

=item I<a_file>

full path to a file

=item I<b_file>

full path to a file

=back

Returns the string 'true' if the last modification date of first file is older
than second file, the 'false' string otherwise, and undef if the comparison
could not be carried on.
