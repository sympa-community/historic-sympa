# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
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

Sympa::Tools::Bounce - Bounce-related functions

=head1 DESCRIPTION

This module provides functions for analysing non-delivery reports.

=cut

package Sympa::Tools::Bounce;

use strict;

use English qw(-no_match_vars);
use MIME::Parser;

use Sympa::Log;

=head1 FUNCTIONS

=head2 parse_compliant_notification($message)

Parse a RFC1891-compliant non-delivery notification.

=head3 Parameters

=over

=item * I<$message>: message object

=back

=head3 Return value

A list of recipients/status pairs, as an hasref.

=cut

sub parse_rfc1891_notification {
    my ($message) = @_;

    my $entity = $message->{'msg'};
    return undef    unless ($entity) ;

    my @parts = $entity->parts();

    my $result;

    foreach my $part ($entity->parts()) {
	my $head = $part->head();
	my $content = $head->get('Content-type');

	next unless ($content =~ /message\/delivery-status/i);

	my $body = $part->body();
	# the body is a list of CRLF-separated lines, with each
	# paragraph separated by an empty line
	foreach my $paragraph (split /\r\n\r\n/, (join '', @$body)) {
		my ($status, $recipient);

		if ($paragraph =~ /^Status: \s+ (\d+\.\d+\.\d+)/mx) {
		    $status = $1;
		}

		if (
			$paragraph =~ /^Original-Recipient: \s+ rfc822; \s* (\S+)/mx ||
			$paragraph =~ /^Final-Recipient: \s+ rfc822; \s* (\S+)/mx
		) {
		    $recipient = $1;
		    if ($recipient =~ /\@.+:(.+)$/) {
			$recipient = $1;
		    }
		    $recipient =~ s/^<(.*)>$/$1/;
		    $recipient =~ y/[A-Z]/[a-z]/;
		}

		if ($recipient and $status) {
		    $result->{$recipient} = $status;
		}
	}
    }

    return $result;
}

# fix an SMTP address
sub _fix_address {
    my ($adr, $from) = @_;

    ## adresse X400
    if ($adr =~ /^\//) {

	my (%x400, $newadr);

	my @detail = split /\//, $adr;
	foreach (@detail) {

	    my ($var, $val) = split /=/;
	    $x400{$var} = $val;

	}

	$newadr = $x400{PN} || "$x400{s}";
	$newadr = "$x400{g}.".$newadr if $x400{g};
	my (undef, $d) =  split /\@/, $from;

	$newadr .= "\@$d";

	return $newadr;

    }elsif ($adr =~ /\@/) {

	return $adr;

    }elsif ($adr =~ /\!/) {

	my ($dom, $loc) = split /\!/, $adr;
	return "$loc\@$dom";

    }else {

	my (undef, $d) =  split /\@/, $from;
	my $newadr = "$adr\@$d";

	return $newadr;

    }
}

=head2 parse_notification($message)

Parse a non-delivery notification.

=head3 Parameters

=over

=item * I<$message>: message object

=back

=head3 Return value

A list of recipients/status pairs, as an hasref.

=cut

sub parse_notification {
    my ($message) = @_;

    my $entity = $message->{'msg'};
    return undef    unless ($entity) ;

    my $type;
    my %info;
    my ($qmail, $type_9, $type_18, $exchange, $ibm_vm, $lotus, $sendmail_5, $yahoo, $type_21, $exim, $vines,
	$mercury_143, $altavista, $mercury_131, $type_31, $type_32,$exim_173, $type_38, $type_39,
	$type_40, $pmdf, $following_recipients, $postfix, $groupwise7);

    # header
    my $head = $entity->head();

    my $from = $head->get('From');
    $from =~ s/^.*<(.+)[\>]$/$1/;
    $from =~  y/[A-Z]/[a-z]/;

    my $subject = $head->get('Subject');
    if ($subject =~ /^Returned mail: (Quota exceeded for user (\S+))$/) {
	$info{$2}{error} = $1;
	$type = 27;
    } elsif ($subject =~ /^Returned mail: (message not deliverable): \<(\S+)\>$/) {
	$info{$2}{error} = $1;
	$type = 34;
    }

    my $recipients =  $head->get('X-Failed-Recipients');
    if ($recipients) {
       if ($recipients =~ /^\s*(\S+)$/) {
	   $info{$1}{error} = "";
       } elsif ($recipients =~ /^\s*(\S+),/) {
	   for my $xfr (split (/\s*,\s*/, $recipients)) {
	       $info{$xfr}{error} = "";
	   }
       }
    }

   my $body = $entity->body();
   # the body is a list of CRLF-separated lines, with each
   # paragraph separated by an empty line
   foreach my $paragraph (split /\r\n\r\n/, (join '', @$body)) {

	if ($paragraph =~ /^\s*-+ The following addresses (had permanent fatal errors|had transient non-fatal errors|have delivery notifications) -+/m) {
	    my $adr;
 	    my @lines = split(/\n/, $paragraph);
	    foreach my $line (@lines) {
		if ($line =~ /^(\S[^\(]*)/) {
		    $adr = $1;
		    my $error = $2;
		    $adr =~ s/^[\"\<](.+)[\"\>]\s*$/$1/;
		    $info{$adr}{error} = $error;
		    $type = 1;
		}elsif ($line =~ /^\s+\(expanded from: (.+)\)/) {
		    $info{$adr}{expanded} = $1;
		    $info{$adr}{expanded} =~ s/^[\"\<](.+)[\"\>]$/$1/;
	        }
	    }
	} elsif ($paragraph =~ /^\s+-+\sTranscript of session follows\s-+/m) {
	    my $adr;
 	    my @lines = split(/\n/, $paragraph);
	    foreach my $line (@lines) {
		if ($line =~ /^(\d{3}\s)?(\S+|\".*\")\.{3}\s(.+)$/) {
		    $adr = $2;
		    my $cause = $3;
		    $cause =~ s/^(.*) [\(\:].*$/$1/;
		    foreach $a(split /,/, $adr) {
			$a =~ s/^[\"\<]([^\"\>]+)[\"\>]$/$1/;
			       $info{$a}{error} = $cause;
			       $type = 2;
			}
		}elsif ($line =~ /^\d{3}\s(too many hops).*to\s(.*)$/i) {
		    $adr = $2;
		    my $cause = $1;
		    foreach $a (split /,/, $adr) {
			$a =~ s/^[\"\<](.+)[\"\>]$/$1/;
			$info{$a}{error} = $cause;
			$type = 2;
		    }
		}elsif ($line =~ /^\d{3}\s.*\s([^\s\)]+)\.{3}\s(.+)$/) {
		    $adr = $1;
		    my $cause = $2;
		    $cause =~ s/^(.*) [\(\:].*$/$1/;
		    foreach $a(split /,/, $adr) {
			$a =~ s/^[\"\<](.+)[\"\>]$/$1/;
			$info{$a}{error} = $cause;
			 $type = 2;
		    }
		}
	    }

	    ## Rapport Compuserve
	}elsif ($paragraph =~ /^Receiver not found:/m) {

 	    my @lines = split(/\n/, $paragraph);
	    foreach my $line (@lines) {

		$info{$2}{error} = $1 if /^(.*): (\S+)/;
		$type = 3;

	    }

	}elsif ($paragraph =~ /^\s*-+ Special condition follows -+/m) {

	    my ($cause,$adr);

 	    my @lines = split(/\n/, $paragraph);
	    foreach my $line (@lines) {

		if ($line =~ /^(Unknown QuickMail recipient\(s\)):/) {
		    $cause = $1;
		    $type = 4;

		}elsif ($line =~ /^\s+(.*)$/ and $cause) {

		    $adr = $1;
		    $adr =~ s/^[\"\<](.+)[\"\>]$/$1/;
		    $info{$adr}{error} = $cause;
		    $type = 4;

		}
	    }

	}elsif ($paragraph =~ /^Your message adressed to .* couldn\'t be delivered/m) {

	    my $adr;

 	    my @lines = split(/\n/, $paragraph);
	    foreach my $line (@lines) {

		if (/^Your message adressed to (.*) couldn\'t be delivered, for the following reason :/) {
		    $adr = $1;
		    $adr =~ s/^[\"\<](.+)[\"\>]$/$1/;
		    $type = 5;

		}else{

		    /^(.*)$/;
		    $info{$adr}{error} = $1;
		    $type = 5;

		}
	    }

	## Rapport X400
	} elsif ($paragraph =~ /^Your message was not delivered to:\s+(\S+)\s+for the following reason:\s+(.+)$/m) {

	    my ($adr, $error) = ($1, $2);
	    $error =~ s/Your message.*$//;
	    $info{$adr}{error} = $error;
	    $type = 6;

	## Rapport X400
	} elsif ($paragraph =~ /^Your message was not delivered to\s+(\S+)\s+for the following reason:\s+(.+)$/m) {

	    my ($adr, $error) = ($1, $2);
	    $error =~ s/\(.*$//;
	    $info{$adr}{error} = $error;
	    $type = 6;

	## Rapport X400
	} elsif ($paragraph =~/^Original-Recipient: rfc822; (\S+)\s+Action: (.*)$/m) {

	    $info{$1}{error} = $2;
	    $type = 16;

        ## Rapport NTMail
	} elsif ($paragraph =~ /^The requested destination was:\s+(.*)$/m) {
	    $type = 7;
	} elsif (($type == 7) && (/^\s+(\S+)/)) {
	    undef $type;
	    my $adr =$1;
	    $adr =~ s/^[\"\<](.+)[\"\>]$/$1/;
	    next unless $adr;
	    $info{$adr}{'error'} = '';
	## Rapport Qmail dans prochain paragraphe
	}elsif ($paragraph =~ /^Hi\. This is the qmail-send program/m) {
	    $qmail = 1;
	## Rapport Qmail
	}elsif ($qmail) {
	     undef $qmail if /^[^<]/;
	     if (/^<(\S+)>:\n(.*)/m) {
		 $info{$1}{error} = $2;
		 $type = 8;
	     }
	## Sendmail
	}elsif ($paragraph =~ /^Your message was not delivered to the following recipients:/m) {
	     $type_9 = 1;
	}elsif ($type_9) {
	    undef $type_9;
	     if (/^\s*(\S+):\s+(.*)$/m) {
		 $info{$1}{error} = $2;
		 $type = 9;
	     }

        ## Rapport Exchange dans prochain paragraphe
	}elsif ($paragraph =~ /^The following recipient\(s\) could not be reached:/m or /^did not reach the following recipient\(s\):/m) {
	     $exchange = 1;
	 ## Rapport Exchange
	 }elsif ($exchange) {
	     undef $exchange;
	     if (/^\s*(\S+).*\n\s+(.*)$/m) {
		 $info{$1}{error} = $2;
		 $type = 10;
	     }

	 ## IBM VM dans prochain paragraphe
         }elsif ($paragraph =~ /^Your mail item could not be delivered to the following users/m) {
	     $ibm_vm = 1;
	 ## Rapport IBM VM
	 }elsif ($ibm_vm) {
	     undef $ibm_vm;
	     if (/^(.*)\s+\---->\s(\S+)$/m) {
		 $info{$2}{error} = $1;
		 $type = 12;
	     }
	 ## Rapport Lotus SMTP dans prochain paragraphe
         }elsif ($paragraph =~ /^-+\s+Failure Reasons\s+-+/m) {
	     $lotus = 1;
	 ## Rapport Lotus SMTP
	 }elsif ($lotus) {
	     undef $lotus;
	     if (/^(.*)\n(\S+)$/m) {
		 $info{$2}{error} = $1;
		 $type = 13;
	     }
	 ## Rapport Sendmail 5 dans prochain paragraphe
	 }elsif ($paragraph =~ /^\-+\sTranscript of session follows\s\-+/m) {
	     $sendmail_5 = 1;
	 ## Rapport  Sendmail 5
         }elsif ($sendmail_5) {
	     undef $sendmail_5;
	     if (/<(\S+)>\n\S+, (.*)$/m) {
		 $info{$1}{error} = $2;
		 $type = 14;
	     }
	 ## Rapport Smap
	 }elsif ($paragraph =~ /^\s+-+ Transcript of Report follows -+/) {
	     my $adr;
 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {
		 if ($line =~ /^Rejected-For: (\S+),/) {
		     $adr = $1;
		     $info{$adr}{error} = "";
		     $type = 17;
		 }elsif ($line =~ /^\s+explanation (.*)$/) {
		     $info{$adr}{error} = $1;
		 }
	     }
	 }elsif ($paragraph =~ /^\s*-+Message not delivered to the following:/) {
	     $type_18 = 1;
	 }elsif ($type_18) {
	     undef $type_18;
 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {

		 if ($line =~/^\s*(\S+)\s+(.*)$/) {

		     $info{$1}{error} = $2;
		     $type = 18;

		 }
	     }
	 }elsif ($paragraph =~ /unable to deliver following mail to recipient\(s\):/m) {
 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {
		 if ($line =~ /^\d+ <(\S+)>\.{3} (.+)$/) {
		     $info{$1}{error} = $2;
		     $type = 19;
		 }
	     }
	 ## Rapport de Yahoo dans paragraphe suivant
	 }elsif ($paragraph =~ /^Unable to deliver message to the following address\(es\)/m) {
	     $yahoo = 1;
	 ## Rapport Yahoo
	 }elsif ($yahoo) {
	     undef $yahoo;
	     if (/^<(\S+)>:\s(.+)$/m) {

		 $info{$1}{error} = $2;
		 $type = 20;

	     }
	 }elsif ($paragraph =~ /^Content-Description: Session Transcript/m) {
	     $type_21 = 1;
	 }elsif ($type_21) {
	     undef $type_21;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {
		 if ($line =~ /<(\S+)>\.{3} (.*)$/) {
		     $info{$1}{error} = $2;
		     $type = 21;
		 }
	     }
	 }elsif ( $paragraph =~ /^Your message has encountered delivery problems\s+to local user \S+\.\s+\(Originally addressed to (\S+)\)/m or $paragraph =~ /^Your message has encountered delivery problems\s+to (\S+)\.$/m or $paragraph =~ /^Your message has encountered delivery problems\s+to the following recipient\(s\):\s+(\S+)$/m) {

	     my $adr = $2 || $1;
	     $info{$adr}{error} = "";
	     $type = 22;
           }elsif ($paragraph =~ /^(The user return_address (\S+) does not exist)/) {
	     $info{$2}{error} = $1;
	     $type = 23;
	 ## Rapport Exim paragraphe suivant
	 }elsif ($paragraph =~ /^A message that you sent could not be delivered to all of its recipients/m or /^The following address\(es\) failed:/m) {
	     $exim = 1;
	 ## Rapport Exim
	 }elsif ($exim) {
	     undef $exim;
	     if (/^\s*(\S+):\s+(.*)$/m) {

		 $info{$1}{error} = $2;
		 $type = 24;

	     }elsif (/^\s*(\S+)$/m) {
		 $info{$1}{error} = "";
	     }

	 ## Rapport VINES-ISMTP par. suivant
	 }elsif ($paragraph =~ /^Message not delivered to recipients below/m) {

	     $vines = 1;

	 ## Rapport VINES-ISMTP
	 }elsif ($vines) {

	     undef $vines;

	     if (/^\s+\S+:.*\s+(\S+)$/m) {

		 $info{$1}{error} = "";
		 $type = 25;

	     }

	 ## Rapport Mercury 1.43 par. suivant
	 }elsif ($paragraph =~ /^The local mail transport system has reported the following problems/m) {

	     $mercury_143 = 1;

	 ## Rapport Mercury 1.43
	 }elsif ($mercury_143) {

	     undef $mercury_143;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {

		 if ($line =~ /<(\S+)>\s+(.*)$/) {

		     $info{$1}{error} = $2;
		     $type = 26;
		 }
	     }

	 ## Rapport de AltaVista Mail dans paragraphe suivant
	 }elsif ($paragraph =~ /unable to deliver mail to the following recipient\(s\):/m) {

	     $altavista = 1;

	 ## Rapport AltaVista Mail
	 }elsif ($altavista) {

	     undef $altavista;

	     if (/^(\S+):\n.*\n\s*(.*)$/m) {

		 $info{$1}{error} = $2;
		 $type = 27;

	     }

	 ## Rapport SMTP32
	 }elsif ($paragraph =~ /^(User mailbox exceeds allowed size): (\S+)$/m) {

	     $info{$2}{error} = $1;
	     $type = 28;

	 }elsif ($paragraph =~ /^The following recipients did not receive this message:$/m) {

	     $following_recipients = 1;

	 }elsif ($following_recipients) {

	     undef $following_recipients;

	     if (/^\s+<(\S+)>/) {

		 $info{$1}{error} = "";
		 $type = 29;

	     }

	 ## Rapport Mercury 1.31 par. suivant
	 }elsif ($paragraph =~ /^One or more addresses in your message have failed with the following/m) {

	     $mercury_131 = 1;

	 ## Rapport Mercury 1.31
	 }elsif ($mercury_131) {

	     undef $mercury_131;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {

		 if ($line =~ /<(\S+)>\s+(.*)$/) {

		     $info{$1}{error} = $2;
		     $type = 30;
		 }
	     }

	 }elsif ($paragraph =~ /^The following recipients haven\'t received this message:/m) {

	     $type_31 = 1;

	 }elsif ($type_31) {

	     undef $type_31;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {

		 if ($line =~ /(\S+)$/) {

		     $info{$1}{error} = "";
		     $type = 31;
		 }
	     }

	 }elsif ($paragraph =~ /^The following destination addresses were unknown/m) {

	     $type_32 = 1;

	 }elsif ($type_32) {

	     undef $type_32;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {

		 if ($line =~ /<(\S+)>/) {

		     $info{$1}{error} = "";
		     $type = 32;
		 }
	     }

         }elsif ($paragraph =~ /^-+Transcript of session follows\s-+$/m) {
 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {
		 if ($line =~ /^(\S+)$/) {

		     $info{$1}{error} = "";
		     $type = 33;

		 }elsif ($line =~ /<(\S+)>\.{3} (.*)$/) {

		     $info{$1}{error} = $2;
		     $type = 33;

		 }
	     }

          ## Rapport Bigfoot
         }elsif ($paragraph =~ /^The message you tried to send to <(\S+)>/m) {
	      $info{$1}{error} = "destination mailbox unavailable";

	  }elsif ($paragraph =~ /^The destination mailbox (\S+) is unavailable/m) {

	     $info{$1}{error} = "destination mailbox unavailable";

	 }elsif ($paragraph =~ /^The following message could not be delivered because the address (\S+) does not exist/m) {

	     $info{$1}{error} = "user unknown";

	 }elsif ($paragraph =~ /^Error-For:\s+(\S+)\s/) {

             $info{$1}{error} = "";

         ## Rapport Exim 1.73 dans proc. paragraphe
	 }elsif ($paragraph =~ /^The address to which the message has not yet been delivered is:/m) {

	     $exim_173 = 1;

         ## Rapport Exim 1.73
	 }elsif ($exim_173) {

	     undef $exim_173;
 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {
		 if ($line =~ /(\S+)/) {

		     $info{$1}{error} = "";
		     $type = 37;
		 }
	     }

	 }elsif ($paragraph =~ /^This Message was undeliverable due to the following reason:/m) {

	     $type_38 = 1;

	 }elsif ($type_38) {

	     undef $type_38 if /Recipient:/;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {
		 if ($line =~ /\s+Recipient:\s+<(\S+)>/) {

		     $info{$1}{error} = "";
		     $type = 38;

		 }elsif ($line =~ /\s+Reason:\s+<(\S+)>\.{3} (.*)/) {

		     $info{$1}{error} = $2;
		     $type = 38;

		 }
	     }

	 }elsif ($paragraph =~ /Your message could not be delivered to:/m) {

	     $type_39 = 1;

	 }elsif ($type_39) {

	     undef $type_39;

             if (/^(\S+)/) {

		 $info{$1}{error} = "";
		 $type = 39;

	     }
	 }elsif ($paragraph =~  /Session Transcription follow:/m) {

             if (/^<+\s+\d+\s+(.*) for \((.*)\)$/m) {

		 $info{$2}{error} = $1;
		 $type = 43;

	     }

	 }elsif ($paragraph =~ /^This message was returned to you for the following reasons:/m) {

	     $type_40 = 1;

	 }elsif ($type_40) {

	     undef $type_40;

             if (/^\s+(.*): (\S+)/) {

		 $info{$2}{error} = $1;
		 $type = 40;

	     }

         ## Rapport PMDF dans proc. paragraphe
	 }elsif ($paragraph =~ /^Your message cannot be delivered to the following recipients:/m or /^Your message has been enqueued and undeliverable for \d day\s*to the following recipients/m) {

         $pmdf = 1;

         ## Rapport PMDF
	 }elsif ($pmdf) {

             my $adr;
             undef $pmdf;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {

		 if ($line =~ /\s+Recipient address:\s+(\S+)/) {

		     $adr = $1;
		     $info{$adr}{error} = "";
		     $type = 41;

		 }elsif ($line =~ /\s+Reason:\s+(.*)$/) {

		     $info{$adr}{error} = $1;
		     $type = 41;

		 }
	     }

         ## Rapport MDaemon
	 }elsif ($paragraph =~ /^(\S+) - (no such user here)\.$/m) {

	     $info{$1}{error} = $2;
	     $type = 42;

         # Postfix dans le prochain paragraphe
         }elsif ($paragraph =~ /^This is the Postfix program/m || /^This is the mail system at host/m) {
             $postfix = 1;
	 ## Rapport Postfix
         }elsif ($postfix) {

	     undef $postfix if /THIS IS A WARNING/; # Pas la peine de le traiter

	     if (/^<(\S+)>:\s(.*)/m) {
		 my ($addr,$error) = ($1,$2);

		 if ($error =~ /^host\s[^:]*said:\s(\d+)/) {
		     $info{$addr}{error} = $1;
		 }
		 elsif ($error =~ /^([^:]+):/) {
		     $info{$addr}{error} = $1;
		 }else {
		     $info{$addr}{error} = $error;
		 }
	     }
	 }elsif ($paragraph =~ /^The message that you sent was undeliverable to the following:/ ) {

             $groupwise7 = 1;

         }elsif ($groupwise7) {

             undef $groupwise7;

 	     my @lines = split(/\n/, $paragraph);
	     foreach my $line (@lines) {

		if ($line =~ /^\s+(\S*) \((.+)\)/ ) {

		     $info{$1}{error} = $2;

		}
	     }

	 ## Wanadoo
	 }elsif ($paragraph =~ /^(\S+); Action: Failed; Status: \d.\d.\d \((.*)\)/m) {
	     $info{$1}{error} = $2;
	 }
    }

    my $result;
    ## On met les adresses au clair
    foreach my $a1 (keys %info) {

	next unless ($a1 and ref ($info{$a1}));

	my ($a2, $a3);

	$a2 = $a1;

	unless (! $info{$a1}{expanded} or ($a1 =~ /\@/ and $info{$a1}{expanded} !~ /\@/) ) {

	    $a2 = $info{$a1}{expanded};

	}

	$a3 = _fix_address($a2, $from);

        $a3 =~ y/[A-Z]/[a-z]/;
        $a3 =~ s/^<(.*)>$/$1/;

         $result->{$a3} = lc ($info{$a1}{error});
    }

    return $result;
}

1;
