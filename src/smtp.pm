# smtp.pm - This module does the SMTP job, it does send messages
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

package smtp;

use POSIX;
use Mail::Internet;
use Conf;
use Language;
use Log;

require 'tools.pl';

use strict;

## RCS identification.
#my $id = '@(#)$Id$';

my $opensmtp = 0;
my $fh = 'fh0000000000';	## File handle for the stream.

my $max_arg = eval { &POSIX::_SC_ARG_MAX; };
if ($@) {
    $max_arg = 4096;
    print STDERR gettext("Your system does not conform to the POSIX P1003.1 standard, or\nyour Perl system does not define the _SC_ARG_MAX constant in its POSIX\nlibrary. You must modify the smtp.pm module in order to set a value\nfor variable $max_arg.\n");
} else {
    $max_arg = POSIX::sysconf($max_arg);
}

my %pid = ();

## Reaper - Non blocking function called by the main loop, just to
## clean the defuncts list by waiting to any processes and decrementing
## the counter.
sub reaper {
   my $block = shift;
   my $i;

   $block = 1 unless (defined($block));
   while (($i = waitpid(-1, $block ? &POSIX::WNOHANG : 0)) > 0) {
      $block = 1;
      if (!defined($pid{$i})) {
         &do_log('debug2', "Reaper waited $i, unknown process to me");
         next;
      }
      $opensmtp--;
      delete($pid{$i});
   }
   &do_log('debug2', "Reaper unwaited pids : %s\nOpen = %s\n", join(' ', sort keys %pid), $opensmtp);
   return $i;
}

## Makes a sendmail ready for the recipients given as
## argument, uses a file descriptor in the smtp table
## which can be imported by other parties.
sub smtpto {
   my($from, $rcpt, $sign_mode) = @_;

   unless ($from) {
       &do_log('err', 'Missing Return-Path in smtp::smtpto()');
   }
   
   if (ref($rcpt) eq 'SCALAR') {
       do_log('debug2', 'smtp::smtpto(%s, %s, %s )', $from, $$rcpt,$sign_mode);
   }else {
       do_log('debug2', 'smtp::smtpto(%s, %s, %s)', $from, join(',', @{$rcpt}), $sign_mode);
   }

   my($pid, $str);

   ## Escape "-" at beginning of recepient addresses
   ## prevent sendmail from taking it as argument

   if (ref($rcpt) eq 'SCALAR') {
       $$rcpt =~ s/^-/\\-/;
   }else {
       my @emails = @$rcpt;
       foreach my $i (0..$#emails) {
	   $rcpt->[$i] =~ s/^-/\\-/;
       }
   }
   
   ## Check how many open smtp's we have, if too many wait for a few
   ## to terminate and then do our job.

   do_log('debug3',"Open = $opensmtp");
   while ($opensmtp > $Conf{'maxsmtp'}) {
       do_log('debug3',"Smtpto: too many open SMTP ($opensmtp), calling reaper" );
       last if (&reaper(0) == -1); ## Blocking call to the reaper.
   }

   *IN = ++$fh; *OUT = ++$fh;
   

   if (!pipe(IN, OUT)) {
       fatal_err(gettext("Unable to create a channel in smtpto: %m")); ## No return
   }
   $pid = &tools::safefork();
   $pid{$pid} = 0;
   if ($pid == 0) {
       close(OUT);
       open(STDIN, "<&IN");

       if (ref($rcpt) eq 'SCALAR') {
	   exec $Conf{'sendmail'}, split(/\s+/,$Conf{'sendmail_args'}), '-f', $from, $$rcpt;
       }else{
	   exec $Conf{'sendmail'}, split(/\s+/,$Conf{'sendmail_args'}), '-f', $from, @$rcpt;
       }
       exit 1; ## Should never get there.
   }
   if ($main::options{'mail'}) {
       $str = "safefork: $Conf{'sendmail'} $Conf{'sendmail_args'} -f $from ";
       if (ref($rcpt) eq 'SCALAR') {
	   $str .= $$rcpt;
       } else {
	   $str .= join(' ', @$rcpt);
       }
       do_log('debug3', $str);
   }
   close(IN);
   $opensmtp++;
   select(undef, undef,undef, 0.3) if ($opensmtp < $Conf{'maxsmtp'});
   return("smtp::$fh"); ## Symbol for the write descriptor.
}


## Makes a sendmail ready for the recipients given as
## argument, uses a file descriptor in the smtp table
## which can be imported by other parties.
sub smime_sign {
    my $from = shift;
    my $temporary_file  = shift;
    
    do_log('debug2', 'smtp::smime_sign (%s)', $from);

    exec "$Conf{'openssl'} smime -sign -signer cert.pem -inkey private_key -out $temporary_file";
    exit 1; ## Should never get there.
}


sub sendto {
    my($msg_header, $msg_body, $from, $rcpt, $encrypt) = @_;
    do_log('debug2', 'smtp::sendto(%s, %s, %s)', $from, $rcpt, $encrypt);

    my $msg;

    ## Encode subject before sending
    $msg_header->replace('Subject', MIME::Words::encode_mimewords($msg_header->get('Subject')));

    if ($encrypt eq 'smime_crypted') {
	my $email ;
	if (ref($rcpt) eq 'SCALAR') {
	    $email = lc ($$rcpt) ;
	}else{
	    my @rcpts = @$rcpt;
	    if ($#rcpts != 0) {
		do_log('err',"incorrect call for encrypt with $#rcpts recipient(s)"); 
		return undef;
	    }
	    $email = lc ($rcpt->[0]); 
	}
	$msg = &tools::smime_encrypt ($msg_header, $msg_body, $email);
    }else {
        $msg = $msg_header->as_string . "\n" . $msg_body;
    }
    
    if ($msg) {
	*SMTP = &smtpto($from, $rcpt);
        print SMTP $msg;
	close SMTP;
	return 1;
    }else{    
	my $param = {'from' => "$from",
		     'email' => "$rcpt"
		     };   

	my $filename;
	if (-r "x509-user-cert-missing.tpl") {
	    $filename = "x509-user-cert-missing.tpl";
	}elsif (-r "$Conf{'etc'}/templates/x509-user-cert-missing.tpl") {
	    $filename = "$Conf{'etc'}/templates/x509-user-cert-missing.tpl";
	}elsif (-r "--ETCBINDIR--/templates/x509-user-cert-missing.tpl") {
	    $filename = "--ETCBINDIR--/templates/x509-user-cert-missing.tpl";
	}else {
	    # $filename = '';
	    do_log ('err',"Unable to open file x509-user-cert-missing.tpl in list directory NOR $Conf{'etc'}/templates/x509-user-cert-missing.tpl NOR --ETCBINDIR--/templates/x509-user-cert-missing.tpl");
	    return undef;
	}
    
	## Should provide the $robot ; too many changes
	&mail::mailfile ($filename, $rcpt, $param, '', 'none');

	return undef;
    }
}

sub mailto {
   my($message, $from, @rcpt) = @_;
   do_log('debug2', 'smtp::mailto(from: %s, , file:%s, %s, %d rcpt)', $from, $message->{'filename'}, $message->{'smime_crypted'}, $#rcpt+1);

   my($i, $j, $nrcpt, $size, @sendto);
   my $numsmtp = 0;
   
   ## If message contain a footer or header added by Sympa  use the object message else
   ## Extract body from original file to preserve signature
   my ($msg_body, $msg_header);

   $msg_header = $message->{'msg'}->head;

   if ($message->{'altered'}) {
       $msg_body = $message->{'msg'}->body_as_string;
       
   }elsif ($message->{'smime_crypted'}) {
       $msg_body = ${$message->{'msg_as_string'}};
       
   }else {
       ## Get body from original file
       unless (open MSG, $message->{'filename'}) {
	   do_log ('notice',"Unable to open %s:%s",$message->{'filename'},$!);
	   last;
       }
       my $in_header = 1 ;
       while (<MSG>) {
	   if ( !$in_header)  { 
	       $msg_body .= $_;       
	   }else {
	       $in_header = 0 if (/^$/); 
	   }
       }
       close (MSG);
   }
   
   ## if the message must be crypted,  we need to send it using one smtp session for each rcpt
   if ($message->{'smime_crypted'}){
       $numsmtp = 0;
       while ($i = shift(@rcpt)) {
	   &sendto($msg_header, $msg_body, $from, [$i], $message->{'smime_crypted'});
	   $numsmtp++
	   }
       
       return ($numsmtp);
   }

   while ($i = shift(@rcpt)) {
       my @k = reverse(split(/[\.@]/, $i));
       my @l = reverse(split(/[\.@]/, $j));
       if ($j && $#sendto >= $Conf{'avg'} && lc("$k[0] $k[1]") ne lc("$l[0] $l[1]")) {
           &sendto($msg_header, $msg_body, $from, \@sendto);
           $numsmtp++;
           $nrcpt = $size = 0;
           @sendto = ();
       }
       if ($#sendto >= 0 && (($size + length($i)) > $max_arg || $nrcpt >= $Conf{'nrcpt'})) {
           &sendto($msg_header, $msg_body, $from, \@sendto);
           $numsmtp++;
           $nrcpt = $size = 0;
           @sendto = ();
       }
       $nrcpt++; $size += length($i) + 5;
       push(@sendto, $i);
       $j = $i;
   }
   if ($#sendto >= 0) {
       &sendto($msg_header, $msg_body, $from, \@sendto) if ($#sendto >= 0);
       $numsmtp++;
   }
   
   return $numsmtp;
}

1;





