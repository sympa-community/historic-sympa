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
	return undef unless ($entity) ;

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

	# X400
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

	} elsif ($adr =~ /\@/) {

		return $adr;

	} elsif ($adr =~ /\!/) {

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
	return undef unless ($entity) ;

	my %info;

	# header
	my $head = $entity->head();

	my $from = $head->get('From');
	$from =~ s/^.*<(.+)[\>]$/$1/;
	$from =~  y/[A-Z]/[a-z]/;

	my $subject = $head->get('Subject');
	if ($subject =~ /^Returned mail: Quota exceeded for user (\S+)$/) {
		$info{$1}{error} = 'Quota exceeded for user';
	} elsif ($subject =~ /^Returned mail: message not deliverable: <(\S+)>$/) {
		$info{$1}{error} = 'message not deliverable';
	}

	my $recipients = $head->get('X-Failed-Recipients');
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
	my @paragraphes = split /\r\n\r\n/, (join '', @$body);
	while (my $paragraph = shift @paragraphes) {

		if ($paragraph =~ /^\s*-+ The following addresses (?:had permanent fatal errors|had transient non-fatal errors|have delivery notifications) -+/m) {
			my $adr;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /^(\S[^\(]*)/) {
					$adr = $1;
					my $error = $2;
					$adr =~ s/^["<](.+)[">]\s*$/$1/;
					$info{$adr}{error} = $error;
				} elsif ($line =~ /^\s+\(expanded from: (.+)\)/) {
					$info{$adr}{expanded} = $1;
					$info{$adr}{expanded} =~ s/^["<](.+)[">]$/$1/;
				}
			}

		} elsif ($paragraph =~ /^\s+-+\sTranscript of session follows\s-+/m) {
			my $adr;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /^(\d{3}\s)?(\S+|".*")\.{3}\s(.+)$/) {
					$adr = $2;
					my $cause = $3;
					$cause =~ s/^(.*) [\(\:].*$/$1/;
					foreach $a(split /,/, $adr) {
						$a =~ s/^["<]([^">]+)[">]$/$1/;
						$info{$a}{error} = $cause;
					}
				} elsif ($line =~ /^\d{3}\s(too many hops).*to\s(.*)$/i) {
					$adr = $2;
					my $cause = $1;
					foreach $a (split /,/, $adr) {
						$a =~ s/^["<](.+)[">]$/$1/;
						$info{$a}{error} = $cause;
					}
				} elsif ($line =~ /^\d{3}\s.*\s([^\s\)]+)\.{3}\s(.+)$/) {
					$adr = $1;
					my $cause = $2;
					$cause =~ s/^(.*) [\(\:].*$/$1/;
					foreach $a (split /,/, $adr) {
						$a =~ s/^["<](.+)[">]$/$1/;
						$info{$a}{error} = $cause;
					}
				}
			}

		} elsif ($paragraph =~ /^Receiver not found:/m) {
			# Compuserve
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				$info{$2}{error} = $1 if /^(.*): (\S+)/;
			}

		} elsif ($paragraph =~ /^\s*-+ Special condition follows -+/m) {
			my ($cause, $adr);
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /^Unknown QuickMail recipient\(s\):/) {
					$cause = 'Unknown QuickMail recipient(s)';
				} elsif ($line =~ /^\s+(.*)$/ and $cause) {
					$adr = $1;
					$adr =~ s/^["<](.+)[">]$/$1/;
					$info{$adr}{error} = $cause;
				}
			}

		} elsif ($paragraph =~ /^Your message adressed to .* couldn\'t be delivered/m) {
			my $adr;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($paragraph =~ /^Your message adressed to (.*) couldn\'t be delivered, for the following reason :/) {
					$adr = $1;
					$adr =~ s/^["<](.+)[">]$/$1/;
				} else {
					/^(.*)$/;
					$info{$adr}{error} = $1;
				}
			}

		} elsif ($paragraph =~ /^Your message was not delivered to:\s+(\S+)\s+for the following reason:\s+(.+)$/m) {
			# X400
			my ($adr, $error) = ($1, $2);
			$error =~ s/Your message.*$//;
			$info{$adr}{error} = $error;

		} elsif ($paragraph =~ /^Your message was not delivered to\s+(\S+)\s+for the following reason:\s+(.+)$/m) {
			# X400
			my ($adr, $error) = ($1, $2);
			$error =~ s/\(.*$//;
			$info{$adr}{error} = $error;

		} elsif ($paragraph =~/^Original-Recipient: rfc822; (\S+)\s+Action: (.*)$/m) {
			# X400
			$info{$1}{error} = $2;

		} elsif ($paragraph =~ /^The requested destination was:\s+/m) {
			# NTMail
			while ($paragraph = shift @paragraphes) {
				next unless $paragraph =~ /^\s+(\S+)/;
				my $adr = $1;
				$adr =~ s/^["<](.+)[">]$/$1/;
				next unless $adr;
				$info{$adr}{'error'} = '';
				last;
			}

		} elsif ($paragraph =~ /^Hi\. This is the qmail-send program/m) {
			# Qmail
			while ($paragraph = shift @paragraphes) {
				if ($paragraph =~ /^<(\S+)>:\n(.*)/m) {
					$info{$1}{error} = $2;
				}
				last if $paragraph =~ /^[^<]/;
			}

		} elsif ($paragraph =~ /^Your message was not delivered to the following recipients:/m) {
			## Sendmail
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^\s*(\S+):\s+(.*)$/m) {
				$info{$1}{error} = $2;
			}

		} elsif (
			$paragraph =~ /^The following recipient\(s\) could not be reached:/m ||
			$paragraph =~ /^did not reach the following recipient\(s\):/m
		) {
			# Exchange
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^\s*(\S+).*\n\s+(.*)$/m) {
				$info{$1}{error} = $2;
			}

		} elsif ($paragraph =~ /^Your mail item could not be delivered to the following users/m) {
			## IBM VM
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^(.*)\s+\---->\s(\S+)$/m) {
				$info{$2}{error} = $1;
			}

		} elsif ($paragraph =~ /^-+\s+Failure Reasons\s+-+/m) {
			# Lotus SMTP
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^(.*)\n(\S+)$/m) {
				$info{$2}{error} = $1;
			}

		} elsif ($paragraph =~ /^\-+\sTranscript of session follows\s\-+/m) {
			# Sendmail 5
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /<(\S+)>\n\S+, (.*)$/m) {
				$info{$1}{error} = $2;
			}

		} elsif ($paragraph =~ /^\s+-+ Transcript of Report follows -+/) {
			# Smap
			my $adr;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /^Rejected-For: (\S+),/) {
					$adr = $1;
					$info{$adr}{error} = "";
				} elsif ($line =~ /^\s+explanation (.*)$/) {
					$info{$adr}{error} = $1;
				}
			}
		} elsif ($paragraph =~ /^\s*-+Message not delivered to the following:/) {
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~/^\s*(\S+)\s+(.*)$/) {
					$info{$1}{error} = $2;
				}
			}

		} elsif ($paragraph =~ /unable to deliver following mail to recipient\(s\):/m) {
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /^\d+ <(\S+)>\.{3} (.+)$/) {
					$info{$1}{error} = $2;
				}
			}

		} elsif ($paragraph =~ /^Unable to deliver message to the following address\(es\)/m) {
			# Yahoo
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^<(\S+)>:\s(.+)$/m) {
				$info{$1}{error} = $2;
			}
		} elsif ($paragraph =~ /^Content-Description: Session Transcript/m) {
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /<(\S+)>\.{3} (.*)$/) {
					$info{$1}{error} = $2;
				}
			}

		} elsif (
			$paragraph =~ /^Your message has encountered delivery problems\s+to local user \S+\.\s+\(Originally addressed to (\S+)\)/m ||
			$paragraph =~ /^Your message has encountered delivery problems\s+to (\S+)\.$/m ||
			$paragraph =~ /^Your message has encountered delivery problems\s+to the following recipient\(s\):\s+(\S+)$/m
		) {
			my $adr = $2 || $1;
			$info{$adr}{error} = "";

		} elsif ($paragraph =~ /^(The user return_address (\S+) does not exist)/) {
			$info{$2}{error} = $1;

		} elsif (
			$paragraph =~ /^A message that you sent could not be delivered to all of its recipients/m ||
			$paragraph =~ /^The following address\(es\) failed:/m
		) {
			# Exim
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^\s*(\S+):\s+(.*)$/m) {
				$info{$1}{error} = $2;
			} elsif ($paragraph =~ /^\s*(\S+)$/m) {
				$info{$1}{error} = "";
			}

		} elsif ($paragraph =~ /^Message not delivered to recipients below/m) {
			# VINES-ISMTP
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^\s+\S+:.*\s+(\S+)$/m) {
				$info{$1}{error} = "";
			}

		} elsif ($paragraph =~ /^The local mail transport system has reported the following problems/m) {
			# Mercury 1.43
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /<(\S+)>\s+(.*)$/) {
					$info{$1}{error} = $2;
				}
			}

		} elsif ($paragraph =~ /unable to deliver mail to the following recipient\(s\):/m) {
			$paragraph = shift @paragraphes;
			# AltaVista Mail
			if ($paragraph =~ /^(\S+):\n.*\n\s*(.*)$/m) {
				$info{$1}{error} = $2;
			}

		} elsif ($paragraph =~ /^(User mailbox exceeds allowed size): (\S+)$/m) {
			# SMTP32
			$info{$2}{error} = $1;

		} elsif ($paragraph =~ /^The following recipients did not receive this message:$/m) {
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^\s+<(\S+)>/) {
				$info{$1}{error} = "";
			}

		} elsif ($paragraph =~ /^One or more addresses in your message have failed with the following/m) {
			# Mercury 1.31
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /<(\S+)>\s+(.*)$/) {
					$info{$1}{error} = $2;
				}
			}

		} elsif ($paragraph =~ /^The following recipients haven\'t received this message:/m) {
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /(\S+)$/) {
					$info{$1}{error} = "";
				}
			}

		} elsif ($paragraph =~ /^The following destination addresses were unknown/m) {
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /<(\S+)>/) {
					$info{$1}{error} = "";
				}
			}

		} elsif ($paragraph =~ /^-+Transcript of session follows\s-+$/m) {
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /^(\S+)$/) {
					$info{$1}{error} = "";
				} elsif ($line =~ /<(\S+)>\.{3} (.*)$/) {
					$info{$1}{error} = $2;
				}
			}

		} elsif ($paragraph =~ /^The message you tried to send to <(\S+)>/m) {
			# Bigfoot
			$info{$1}{error} = "destination mailbox unavailable";
		} elsif ($paragraph =~ /^The destination mailbox (\S+) is unavailable/m) {
			$info{$1}{error} = "destination mailbox unavailable";
		} elsif ($paragraph =~ /^The following message could not be delivered because the address (\S+) does not exist/m) {
			$info{$1}{error} = "user unknown";
		} elsif ($paragraph =~ /^Error-For:\s+(\S+)\s/) {
			$info{$1}{error} = "";

		} elsif ($paragraph =~ /^The address to which the message has not yet been delivered is:/m) {
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /(\S+)/) {
					$info{$1}{error} = "";
				}
			}

		} elsif ($paragraph =~ /^This Message was undeliverable due to the following reason:/m) {
			while ($paragraph = shift @paragraphes) {
				my @lines = split(/\n/, $paragraph);
				foreach my $line (@lines) {
					if ($line =~ /\s+Recipient:\s+<(\S+)>/) {
						$info{$1}{error} = "";
					} elsif ($line =~ /\s+Reason:\s+<(\S+)>\.{3} (.*)/) {
						$info{$1}{error} = $2;
					}
				}
				last if $paragraph =~ /Recipient:/;
			}

		} elsif ($paragraph =~ /Your message could not be delivered to:/m) {
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^(\S+)/) {
				$info{$1}{error} = "";
			}
		} elsif ($paragraph =~ /Session Transcription follow:/m) {
			if ($paragraph =~ /^<+\s+\d+\s+(.*) for \((.*)\)$/m) {
				$info{$2}{error} = $1;
			}
		} elsif ($paragraph =~ /^This message was returned to you for the following reasons:/m) {
			$paragraph = shift @paragraphes;
			if ($paragraph =~ /^\s+(.*): (\S+)/) {
				$info{$2}{error} = $1;
			}

		} elsif (
			$paragraph =~ /^Your message cannot be delivered to the following recipients:/m ||
			$paragraph =~ /^Your message has been enqueued and undeliverable for \d day\s*to the following recipients/m
		) {
			# PMDF
			$paragraph = shift @paragraphes;
			my $adr;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /\s+Recipient address:\s+(\S+)/) {
					$adr = $1;
					$info{$adr}{error} = "";
				} elsif ($line =~ /\s+Reason:\s+(.*)$/) {
					$info{$adr}{error} = $1;
				}
			}

		} elsif ($paragraph =~ /^(\S+) - (no such user here)\.$/m) {
			# MDaemon
			$info{$1}{error} = $2;

		} elsif (
			$paragraph =~ /^This is the Postfix program/m ||
			$paragraph =~ /^This is the mail system at host/m
		) {
			# Postfix
			while ($paragraph = shift @paragraphes) {
				if ($paragraph =~ /^<(\S+)>:\s(.*)/m) {
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
				last if $paragraph =~ /THIS IS A WARNING/;
			}

		} elsif ($paragraph =~ /^The message that you sent was undeliverable to the following:/ ) {
			$paragraph = shift @paragraphes;
			my @lines = split(/\n/, $paragraph);
			foreach my $line (@lines) {
				if ($line =~ /^\s+(\S*) \((.+)\)/ ) {
					$info{$1}{error} = $2;
				}
			}

		} elsif ($paragraph =~ /^(\S+); Action: Failed; Status: \d.\d.\d \((.*)\)/m) {
			# Wanadoo
			$info{$1}{error} = $2;
		}
	}

	my $result;
	foreach my $a1 (keys %info) {
		next unless ($a1 and ref ($info{$a1}));
		my ($a2, $a3);
		$a2 = $a1;
		unless (! $info{$a1}{expanded} || ($a1 =~ /\@/ and $info{$a1}{expanded} !~ /\@/) ) {
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
