# Archive.pm - This module does the archiving job for a mailing lists.
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

package Archive;

use Mail::Internet;
use POSIX;
use Log;
use strict;

my $serial_number = 0; # incremented on each archived mail

## RCS identification.

## copie a message in $dir using a unique file name based on liSTNAME

sub outgoing {
    my($dir,$listname,$msg) = @_;
    
    do_log ('debug2',"outgoing for list $listname to directory $dir");
    
    return 1 if ($dir eq '/dev/null');

    ## ignoring message with a no-archive flag
    if (ref($msg) && (($msg->head->get('X-no-archive') =~ /yes/i) || ($msg->head->get('Restrict') =~ /no\-external\-archive/i))) {
	do_log('info',"Do not archive message with no-archive flag for list $listname");
	return 1;
    }

    
    ## Create the archive directory if needed
    
    unless (-d $dir) {
	mkdir ($dir, 0775);
	chmod 0774, $dir;
	do_log('info',"creating $dir");
    }
    
    my @now  = localtime(time);
#    my $prefix= sprintf("%04d-%02d-%02d-%02d-%02d-%02d",1900+$now[5],$now[4]+1,$now[3],$now[2],$now[1],$now[0]);
#    my $filename = "$dir"."/"."$prefix-$listname";
    my $filename = sprintf '%s/%s.%d.%d.%d', $dir, $listname, time, $$, $serial_number;
    $serial_number = ($serial_number+1)%100000;
    unless ( open(OUT, "> $filename")) {
	do_log('info',"error unable open outgoing dir $dir for list $listname");
	return undef;
    }
    do_log('debug',"put message in $filename");
    if (ref ($msg)) {
  	$msg->print(\*OUT);
    }else {
 	print OUT $msg;
    }
    close (OUT);
}

## Does the real job : stores the message given as an argument into
## the indicated directory.

sub store {
    my($dir, $period, $msg) = @_;
    
    do_log ('debug2','archive::store (%s,%s)',$dir, $period);
    
    my($filename, $newfile);
    
    return unless $period;
    
    ## Create the archive directory if needed
    mkdir ($dir, "0775") if !(-d $dir);
    chmod 0774, $dir;
    
    my $separator = $tools::separator;  
    
    my @now  = localtime(time);
    
    if ($period eq 'day') {
	$filename = sprintf("%04d%02d%02d", 1900 + $now[5], $now[4] + 1, $now[3]);
    } elsif ($period eq 'year') {
	$filename = sprintf("%04d", 1900 + $now[5]);
    } elsif ($period eq 'month') {
	$filename = sprintf("%04d%02d", 1900 + $now[5], $now[4] + 1);
    } elsif ($period eq 'quarter') {
	$filename = sprintf("%04dq%1d", 1900 + $now[5], $now[4] / 3 + 1);
    } elsif ($period eq 'week') {
	$filename = sprintf("%04dw%02d", 1900 + $now[5], int($now[7] / 7) + 1);
    }
    $filename = "$dir/log.$filename";
    $newfile = !(-e $filename);
    
    ## add the message to the current archive
    
    open(OUT, ">> $filename") || return;
    if ($newfile) {
	printf OUT "\nThis digest for list has been created on %s\n\n",
      POSIX::strftime("%a %b %e %H:%M:%S %Y", @now);
	print OUT "------- THIS IS A RFC934 COMPLIANT DIGEST, YOU CAN BURST IT -------\n\n";
    }
    #   xxxxx we should leave the Received headers isn't ?
    if (ref ($msg)) {
  	$msg->print(\*OUT);
    }else {
 	print OUT $msg;
    }
    printf OUT "\n%s\n\n", $tools::separator;
    close(OUT);
    
    ## erase the last  message and replace it by the current one
    open(OUT, "> $dir/last_message");
    if (ref ($msg)) {
  	$msg->print(\*OUT);
    }else {
 	print OUT $msg;
    }
    close(OUT);
    
}

## Lists the files included in the archive, preformatted for printing
## Returns an array.
sub list {
    my $name = shift;

    do_log ('debug',"archive::list($name)");

    my($filename, $newfile);
    my(@l, $i);
        
    unless (-d "$name") {
      @l = ($msg::no_archives_available);
      return @l;
  }
    unless (opendir(DIR, "$name")) {
	@l = ($msg::no_archives_available);
	return @l;
    }
   foreach $i (sort readdir(DIR)) {
       next if ($i =~ /^\./o);

       my(@s) = stat("$name/$i");
       my $a = localtime($s[9]);
       push(@l, sprintf("%-40s %7d   %s\n", $i, $s[7], $a));
   }
    return @l;
}

sub exist {
    my($name, $file) = @_;
    my $fn = "$name/$file";
    
    return $fn if (-r $fn && -f $fn);
    return undef;
}

1;




