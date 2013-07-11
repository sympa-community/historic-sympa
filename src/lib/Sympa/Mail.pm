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

Sympa::Mail - Mail-related functions

=head1 DESCRIPTION

This module provides mail-related functions

=cut

package Sympa::Mail;

use strict;

use English qw(-no_match_vars);
use MIME::Charset;
use MIME::Tools;
use POSIX qw();
use Time::Local;

use Sympa::Constants;
use Sympa::Language;
use Sympa::Log::Syslog;
use Sympa::List;
use Sympa::Message;
use Sympa::Template;
use Sympa::Tools;
use Sympa::Tools::SMIME;

my $opensmtp = 0;
my $fh = 'fh0000000000';	## File handle for the stream.

my $max_arg = eval { POSIX::_SC_ARG_MAX; };
if ($EVAL_ERROR) {
	$max_arg = 4096;
	printf STDERR Sympa::Language::gettext("Your system does not conform to the POSIX P1003.1 standard, or\nyour Perl system does not define the _SC_ARG_MAX constant in its POSIX\nlibrary. You must modify the smtp.pm module in order to set a value\nfor variable %s.\n"), $max_arg;
} else {
	$max_arg = POSIX::sysconf($max_arg);
}

my %pid = ();

=head1 FUNCTIONS

=over

=item mail_file(%parameters)

send a tt2 file.

Parameters:

=over

=item C<filename> => string

The template filename (with .tt2).

=item C<recipient> => string|arrayref

SMTP "RCPT To:" field

=item C<data> => hashref

Data passed to the template:

=over

=item C<return_path> => SMTP "MAIL From:" field if send by smtp,
			   "X-Sympa-From:" field if send by spool

=item C<to> => "To:" header field

=item C<lang> => tt2 language if $filename

=item C<list> =>  ref(HASH) if $sign_mode = 'smime', keys are :
	-name
	-dir

=item C<from> => "From:" field if not a full msg

=item C<subject> => "Subject:" field if not a full msg

=item C<replyto> => "Reply-to:" field if not a full msg

=item C<body> => body message if not $filename

=item C<headers> => : ref(HASH) with keys are headers mail

=item C<dkim> => a set of parameters for appying DKIM signature
	-d : d=tag
	-i : i=tag (optionnal)
	-selector : dkim dns selector
	-key : the RSA private key

=back

=item C<robot> => FIXME

=item C<return_message_as_string> => FIXME

=item C<priority> => FIXME

=item C<priority_packet> => FIXME

=item C<sympa> => FIXME

=item C<sendmail> => FIXME

=item C<sendmail_args> => FIXME

=item C<maxsmtp> => FIXME

=item C<openssl> => FIXME

=item C<key_passwd> => FIXME

=item C<cookie> => FIXME

=back

Return value:

A true value on sucess, I<undef> otherwise.

=cut

sub mail_file {
	my (%params) = @_;

	my $data = $params{data};
	my $header_possible = $data->{'header_possible'};
	my $sign_mode = $data->{'sign_mode'};

	Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s)', $params{filename}, $params{recipient}, $sign_mode);

	my ($to,$message_as_string);

	## boolean
	$header_possible = 0 unless (defined $header_possible);
	my %header_ok;           # hash containing no missing headers
	my $existing_headers = 0;# the message already contains headers

	## We may receive a list a recepients
	if (ref ($params{recipient})) {
		unless (ref ($params{recipient}) eq 'ARRAY') {
			Sympa::Log::Syslog::do_log('notice', 'Wrong type of reference for rcpt');
			return undef;
		}
	}

	## Charset for encoding
	Sympa::Language::push_lang($data->{'lang'}) if defined $data->{'lang'};
	$data->{'charset'} ||= Sympa::Language::get_charset();
	Sympa::Language::pop_lang() if defined $data->{'lang'};

	## TT2 file parsing
	if ($params{filename} =~ /\.tt2$/) {
		my $output;
		my @path = split /\//, $params{filename};
		Sympa::Language::push_lang($data->{'lang'}) if (defined $data->{'lang'});
		Sympa::Template::parse_tt2($data, $path[$#path], \$output);
	Sympa::Language::pop_lang() if (defined $data->{'lang'});
	$message_as_string .= join('',$output);
	$header_possible = 1;

	} else { # or not
		$message_as_string .= $data->{'body'};
	}

	## ## Does the message include headers ?
	if ($header_possible) {
		foreach my $line (split(/\n/,$message_as_string)) {
			last if ($line=~/^\s*$/);
			if ($line=~/^[\w-]+:\s*/) { ## A header field
				$existing_headers=1;
			} elsif ($existing_headers && ($line =~ /^\s/)) { ## Following of a header field
				next;
			} else {
				last;
			}

			foreach my $header ('date', 'to','from','subject','reply-to','mime-version', 'content-type','content-transfer-encoding') {
				if ($line=~/^$header:/i) {
					$header_ok{$header} = 1;
					last;
				}
			}
		}
	}

	## ADD MISSING HEADERS
	my $headers="";

	unless ($header_ok{'date'}) {
		my $now = time();
		my $tzoff = timegm(localtime($now)) - $now;
		my $sign;
		if ($tzoff < 0) {
			($sign, $tzoff) = ('-', -$tzoff);
		} else {
			$sign = '+';
		}
		$tzoff = sprintf '%s%02d%02d',
		$sign, int($tzoff / 3600), int($tzoff / 60) % 60;
		Sympa::Language::push_lang('en');
		$headers .= 'Date: ' .
		POSIX::strftime("%a, %d %b %Y %H:%M:%S $tzoff",
			localtime $now) .
		"\n";
		Sympa::Language::pop_lang();
	}

	unless ($header_ok{'to'}) {
		# Currently, bare e-mail address is assumed.  Complex ones such as
		# "phrase" <email> won't be allowed.
		if (ref ($params{recipient})) {
			if ($data->{'to'}) {
				$to = $data->{'to'};
			} else {
				$to = join(",\n   ", @{$params{recipient}});
			}
		} else {
			$to = $params{recipient};
		}
		$headers .= "To: $to\n";
	}

	unless ($header_ok{'from'}) {
		if ($data->{'from'} eq 'sympa') {
			$headers .= "From: ".MIME::EncWords::encode_mimewords(
				sprintf("SYMPA <%s>", $params{sympa}),
				'Encoding' => 'A', 'Charset' => "US-ASCII", 'Field' => 'From'
			)."\n";
		} else {
			$headers .= "From: ".MIME::EncWords::encode_mimewords(
				Encode::decode('utf8', $data->{'from'}),
				'Encoding' => 'A', 'Charset' => $data->{'charset'}, 'Field' => 'From'
			)."\n";
		}
	}

	unless ($header_ok{'subject'}) {
		$headers .= "Subject: ".MIME::EncWords::encode_mimewords(
			Encode::decode('utf8', $data->{'subject'}),
			'Encoding' => 'A', 'Charset' => $data->{'charset'}, 'Field' => 'Subject'
		)."\n";
	}

	unless ($header_ok{'reply-to'}) {
		$headers .= "Reply-to: ".MIME::EncWords::encode_mimewords(
			Encode::decode('utf8', $data->{'replyto'}),
			'Encoding' => 'A', 'Charset' => $data->{'charset'}, 'Field' => 'Reply-to'
		)."\n" if ($data->{'replyto'})
	}

	if ($data->{'headers'}) {
		foreach my $field (keys %{$data->{'headers'}}) {
			$headers .= $field.': '.MIME::EncWords::encode_mimewords(
				Encode::decode('utf8', $data->{'headers'}{$field}),
				'Encoding' => 'A', 'Charset' => $data->{'charset'}, 'Field' => $field
			)."\n";
		}
	}

	unless ($header_ok{'mime-version'}) {
		$headers .= "MIME-Version: 1.0\n";
	}

	unless ($header_ok{'content-type'}) {
		$headers .= "Content-Type: text/plain; charset=".$data->{'charset'}."\n";
	}

	unless ($header_ok{'content-transfer-encoding'}) {
		$headers .= "Content-Transfer-Encoding: 8bit\n";
	}

	## Determine what value the Auto-Submitted header field should take
	## See http://www.tools.ietf.org/html/draft-palme-autosub-01
	## the header filed can have one of the following values : auto-generated, auto-replied, auto-forwarded
	## The header should not be set when wwsympa sends a command/mail to sympa.pl through its spool
	unless ($data->{'not_auto_submitted'} ||  $header_ok{'auto_submitted'}) {
		## Default value is 'auto-generated'
		my $header_value = $data->{'auto_submitted'} || 'auto-generated';
		$headers .= "Auto-Submitted: $header_value\n";
	}

	unless ($existing_headers) {
		$headers .= "\n";
	}

	## All these data provide mail attachements in service messages
	my @msgs = ();
	if (ref($data->{'msg_list'}) eq 'ARRAY') {
		@msgs = map {$_->{'msg'} || $_->{'full_msg'}} @{$data->{'msg_list'}};
	} elsif ($data->{'spool'}) {
		@msgs = @{$data->{'spool'}};
	} elsif ($data->{'msg'}) {
		push @msgs, $data->{'msg'};
	} elsif ($data->{'msg_path'} and open IN, '<'.$data->{'msg_path'}) {
		push @msgs, join('', <IN>);
		close IN;
	} elsif ($data->{'file'} and open IN, '<'.$data->{'file'}) {
		push @msgs, join('', <IN>);
		close IN;
	}

	my $listname = '';
	if (ref($data->{'list'}) eq "HASH") {
		$listname = $data->{'list'}{'name'};
	} elsif ($data->{'list'}) {
		$listname = $data->{'list'};
	}

	unless ($message_as_string = _reformat_message("$headers"."$message_as_string", \@msgs, $data->{'charset'})) {
		Sympa::Log::Syslog::do_log('err', 'Failed to reformat message');
	}

	return $message_as_string if($params{return_message_as_string});

	my $message = Sympa::Message->new(
		string     => $message_as_string,
		noxsympato =>'noxsympato'
	);

	my $result = _sending(
		message         => $message,
		rcpt            => $params{recipient},
		from            => $data->{'return_path'},
		robot           => $params{robot},
		listname        => $listname,
		priority        => $params{priority},
		priority_packet => $params{priority_packet},
		sign_mode       => $params{sign_mode},
		bulk            => $params{bulk},
		spool           => $params{spool},
		dkim            => $data->{'dkim'},
		sendmail        => $params{sendmail},
		sendmail_args   => $params{sendmail_args},
		maxsmtp         => $params{maxsmtp},
		openssl         => $params{openssl},
		key_passwd      => $params{key_passwd},
		cookie          => $params{cookie},
		sympa           => $params{sympa},
	);

	return defined $result ? 1 : undef;
}

=item mail_message(%parameters)

Distribute a message to a list, crypting if needed.

Parameters:

=over

=item C<message> => FIXME

The message

=item C<from> => FIXME

The message sender.

=item C<rcpt> => arrayref

The message recipients.

=item C<robot> => FIXME

The robot.

=item C<verp> => hashref

The verp parameters.

=item C<priority_packet> =>

=item C<return_path_suffix> =>

=item C<sendmail> =>

=item C<sendmail_args> =>

=item C<maxsmtp> =>

=item C<avg> =>

=item C<nrcpt> =>

=item C<nrcpt_by_dom> =>

=item C<db_type> =>

=item C<ssl_cert_dir> =>

=item C<openssl> =>

=item C<key_passwd> =>

=item C<cookie> =>

=back

Return value:

A number of sendmail process on success, I<undef> otherwise.

=cut

sub mail_message {

	my %params = @_;
	my $message =  $params{'message'};
	my $list =  $params{'list'};
	my $verp = $params{'verp'};
	my @rcpt =  @{$params{'rcpt'}};
	my $dkim  =  $params{'dkim_parameters'};
	my $tag_as_last = $params{'tag_as_last'};
	my $priority_packet = $params{'priority_packet'};
	my $host = $list->{'admin'}{'host'};
	my $robot = $list->{'domain'};

	unless (ref($message) && $message->isa('Sympa::Message')) {
		Sympa::Log::Syslog::do_log('err', 'Invalid message parameter');
		return undef;
	}


	# normal return_path (ie used if verp is not enabled)
	my $from = $list->{'name'}. $params{return_path_suffix} . '@' . $host;

	Sympa::Log::Syslog::do_log('debug', '(from: %s, , file:%s, %s, verp->%s, %d rcpt, last: %s)', $from, $message->{'filename'}, $message->{'smime_crypted'}, $verp, $#rcpt+1, $tag_as_last);
	return 0 if ($#rcpt == -1);

	my($i, $j, $nrcpt, $size);
	my $numsmtp = 0;

	## If message contain a footer or header added by Sympa  use the object message else
	## Extract body from original file to preserve signature
	my $msg_body; my $msg_header;
	$msg_header = $message->{'msg'}->head();
	if (!($message->{'protected'})) {
		$msg_body = $message->{'msg'}->body_as_string();
	} elsif ($message->{'smime_crypted'}) {
		$msg_body = ${$message->{'msg_as_string'}}; # why is object message msg_as_string contain a body _as_string ? wrong name for this mesage property
	} else {
		## Get body from original message body
		my @bodysection =split("\n\n",$message->{'msg_as_string'});  # convert it as a tab with headers as first element
		shift @bodysection;                                          # remove headers
		$msg_body = join ("\n\n",@bodysection);                      # convert it back as string
	}
	$message->{'body_as_string'} = $msg_body;

	my %rcpt_by_dom;

	my @sendto;
	my @sendtobypacket;

	my $cmd_size = length($params{sendmail}) + 1 +
	length($params{sendmail_args}) +
	length(' -N success,delay,failure -V ') + 32 +
	length(" -f $from ");

	while (defined ($i = shift(@rcpt))) {
		my @k = reverse(split(/[\.@]/, $i));
		my @l = reverse(split(/[\.@]/, $j));

		my $dom;
		if ($i =~ /\@(.*)$/) {
			$dom = $1;
			chomp $dom;
		}
		$rcpt_by_dom{$dom} += 1;
		Sympa::Log::Syslog::do_log('debug2', "domain: $dom ; rcpt by dom: $rcpt_by_dom{$dom} ; limit for this domain: $params{nrcpt_by_domain}{$dom}");

		if (
			# number of recipients by each domain
			(defined $params{nrcpt_by_domain}{$dom} and
				$rcpt_by_dom{$dom} >= $params{nrcpt_by_domain}{$dom}) or
			# number of different domains
			($j and $#sendto >= $params{avg} and
				lc "$k[0] $k[1]" ne lc "$l[0] $l[1]") or
			# number of recipients in general, and ARG_MAX limitation
			($#sendto >= 0 and
				($cmd_size + $size + length($i) + 5 > $max_arg or
					$nrcpt >= $params{nrcpt})) or
			# length of recipients field stored into bulkmailer table
			# (these limits might be relaxed by future release of Sympa)
			($params{db_type} eq 'mysql' and $size + length($i) + 5 > 65535) or
			($params{db_type} !~ /^(mysql|SQLite)$/ and $size + length($i) + 5 > 500)
		) {
			undef %rcpt_by_dom;
			# do not replace this line by "push @sendtobypacket, \@sendto" !!!
			my @tab =  @sendto; push @sendtobypacket, \@tab;
			$numsmtp++;
			$nrcpt = $size = 0;
			@sendto = ();
		}

		$nrcpt++; $size += length($i) + 5;
		push(@sendto, $i);
		$j = $i;
	}

	if ($#sendto >= 0) {
		$numsmtp++;
		my @tab =  @sendto;
		push @sendtobypacket, \@tab ;# do not replace this line by push @sendtobypacket, \@sendto !!!
	}

	my $result = _sendto(
		message         => $message,
		from            => $from,
		rcpt            => \@sendtobypacket,
		listname        => $list->{'name'},
		priority        => $list->{'admin'}{'priority'},
		priority_packet => $priority_packet,
		delivery_date   => $list->get_next_delivery_date,
		robot           => $robot,
		encrypt         => $message->{'smime_crypted'},
		bulk            => $params{bulk},
		verp            => $verp,
		dkim            => $dkim,
		merge           => $list->{'admin'}{'merge_feature'},
		tag_as_last     => $tag_as_last,
		sendmail        => $params{sendmail},
		sendmail_args   => $params{sendmail_args},
		maxsmtp         => $params{maxsmtp},
		openssl         => $params{openssl},
		key_passws      => $params{key_passwd},
		ssl_cert_dir    => $params{ssl_cert_dir},
		cookie          => $params{cookie},
		sympa           => $params{sympa},
	);

	if (!defined $result) {
		Sympa::Log::Syslog::do_log('err',"Failed to send message to list %s", $list->{'name'});
	return undef;
	}

	return $numsmtp;
}

=item mail_forward(%parameters)

Forward a message.

Parameters:

=over

=item C<message> => the message

=item C<from> => message sender

=item C<recipient> => message recipients, as a listref

=item C<robot> => the robot

=item C<priority> =>

=item C<priority_packet> =>

=item C<sendmail> =>

=item C<sendmail_args> =>

=item C<maxsmtp> =>

=item C<openssl> =>

=item C<key_passwd> =>

=item C<cookie> =>

=back

Return value:

A true value on success, I<undef> otherwise.

=cut

sub mail_forward {
	my (%params) = @_;
	Sympa::Log::Syslog::do_log('debug2', "($params{from},$params{recipient})");

	my $message = $params{message};

	unless (ref($message) && $message->('Sympa::Message')) {
		Sympa::Log::Syslog::do_log('err',"Unespected parameter type: %s.",ref($message));
		return undef;
	}
	## Add an Auto-Submitted header field according to  http://www.tools.ietf.org/html/draft-palme-autosub-01
	$message->{'msg'}->head()->add('Auto-Submitted', 'auto-forwarded');

	my $result = _sending(
		message         => $message,
		rcpt            => $params{recipient},
		from            => $params{from},
		robot           => $params{robot},
		priority        => $params{priority},
		priority_packet => $params{priority_packet},
		sendmail        => $params{sendmail},
		sendmail_args   => $params{sendmail_args},
		maxsmtp         => $params{maxsmtp},
		openssl         => $params{openssl},
		key_passwd      => $params{key_passwd},
		cookie          => $params{cookie},
		sympa           => $params{sympa},
	);

	if (!defined $result) {
		Sympa::Log::Syslog::do_log('err', 'forward from %s impossible to send', $params{from});
		return undef;
	}

	return 1;
}

=item reaper($block)

Non blocking function called to clean the defuncts list by waiting to any
processes and decrementing the counter.

Parameters:

=over

=item FiXME

=back

Return value:

=cut

sub reaper {
	my ($block) = @_;

	my $i;

	$block = 1 unless (defined($block));
	while (($i = waitpid(-1, $block ? POSIX::WNOHANG : 0)) > 0) {
		$block = 1;
		if (!defined($pid{$i})) {
			Sympa::Log::Syslog::do_log('debug2', "Reaper waited $i, unknown process to me");
			next;
		}
		$opensmtp--;
		delete($pid{$i});
	}
	Sympa::Log::Syslog::do_log('debug2', "Reaper unwaited pids : %s\nOpen = %s\n", join(' ', sort keys %pid), $opensmtp);
	return $i;
}

# _sendto(%parameters)
#
# send messages, S/MIME encryption if needed,
# grouped sending (or not if encryption)
#
# Parameters:
# * msg_header (+): message header : MIME::Head object
# * msg_body (+): message body
# * from (+): message from
# * rcpt(+) : ref(SCALAR) | ref(ARRAY) - message recepients
# * listname : use only to format return_path if VERP on
# * robot(+) : robot
# * encrypt : 'smime_crypted' | undef
# * verp : 1| undef
# * bulk : if defined,  send message using bulk
#
# Return value:
# 1 - call to sending

sub _sendto {
	my (%params) = @_;

	my $message = $params{'message'};
	my $msg_header = $message->{'msg'}->head();
	my $msg_body = $message->{'body_as_string'};
	my $from = $params{'from'};
	my $rcpt = $params{'rcpt'};
	my $listname = $params{'listname'};
	my $robot = $params{'robot'};
	my $priority =  $params{'priority'};
	my $priority_packet =  $params{'priority_packet'};
	my $encrypt = $params{'encrypt'};
	my $verp = $params{'verp'};
	my $merge = $params{'merge'};
	my $dkim = $params{'dkim'};
	my $bulk = $params{'bulk'};
	my $tag_as_last = $params{'tag_as_last'};

	Sympa::Log::Syslog::do_log('debug', '(from : %s,listname: %s, encrypt : %s, verp : %s, priority = %s, last: %s, bulk: %s', $from, $listname, $encrypt, $verp, $priority, $tag_as_last, $params{bulk});

	my $delivery_date =  $params{'delivery_date'};
	$delivery_date = time() unless $delivery_date; # if not specified, delivery tile is right now (used for sympa messages etc)

	if ($encrypt eq 'smime_crypted') {
		# encrypt message for each rcpt and send the message
		# this MUST be moved to the bulk mailer. This way, merge will be applied after the SMIME encryption is applied ! This is a bug !
		foreach my $bulk_of_rcpt (@{$rcpt}) {
			# trace foreach my $unique_rcpt (@{$bulk_of_rcpt}) {
			foreach my $email (@{$bulk_of_rcpt}) {
				if ($email !~ /@/) {
					Sympa::Log::Syslog::do_log('err',"incorrect call for encrypt with incorrect number of recipient");
					return undef;
				}
				$message->{'msg_as_string'} =
				Sympa::Tools::SMIME::encrypt_message(
					entity   => $message->{'msg'},
					email    => $email,
					cert_dir => $params{ssl_cert_dir},
					openssl  => $params{openssl}
				)->as_string();
				unless ($message->{'msg_as_string'}) {
					Sympa::Log::Syslog::do_log('err',"Failed to encrypt message");
					return undef;
				}

				my $result = _sending(
					message         => $message,
					rcpt            => $email,
					from            => $from,
					listname        => $listname,
					robot           => $robot,
					priority        => $priority,
					priority_packet => $priority_packet,
					delivery_date   => $delivery_date,
					bulk            => $bulk,
					tag_as_last     => $tag_as_last,
					sendmail        => $params{sendmail},
					sendmail_args   => $params{sendmail_args},
					maxsmtp         => $params{maxsmtp},
					openssl         => $params{openssl},
					key_passwd      => $params{key_passwd},
					cookie          => $params{cookie},
					sympa           => $params{sympa},
				);

				if (!defined $result) {
					Sympa::Log::Syslog::do_log('err',"Failed to send encrypted message");
					return undef;
				}
				$tag_as_last = 0;
			}
		}
	} else {
		$message->{'msg_as_string'} = $msg_header->as_string . "\n" . $msg_body;
		my $result = _sending(
			message         => $message,
			rcpt            => $rcpt,
			from            => $from,
			listname        => $listname,
			robot           => $robot,
			priority        => $priority,
			priority_packet => $priority_packet,
			delivery_date   => $delivery_date,
			verp            => $verp,
			merge           => $merge,
			bulk            => $bulk,
			dkim            => $dkim,
			tag_as_last     => $tag_as_last,
			sendmail        => $params{sendmail},
			sendmail_args   => $params{sendmail_args},
			maxsmtp         => $params{maxsmtp},
			openssl         => $params{openssl},
			key_passwd      => $params{key_passwd},
			cookie          => $params{cookie},
			sympa           => $params{sympa},
		);
		return $result;

	}
	return 1;
}

# _sending(%parameters)
#
# send a message using smpto function or puting it
# in spool according to the context
# Signing if needed
#
# Parameters:
# * msg(+) : ref(MIME::Entity) | string - message to send
# * rcpt(+) : ref(SCALAR) | ref(ARRAY) - recepients
#   (for SMTP : "RCPT To:" field)
# * from(+) : for SMTP "MAIL From:" field , for spool sending : "X-Sympa-From" field
# * robot(+) : robot
# * listname : listname | ''
# * sign_mode(+) : 'smime' | 'none' for signing
# * verp
# * kim : a hash for dkim parameters
#
# Return value:
# 1 - call to smtpto (sendmail) | 0 - push in spool | undef

sub _sending {
	my (%params) = @_;

	my $message = $params{'message'};
	$params{delivery_date} = time() unless $params{delivery_date};

	if ($params{sign_mode} eq 'smime') {
		my $list = Sympa::List->new(
			name  => $params{listname},
			robot => $params{robot}
		);
		my $signed_msg = Sympa::Tools::SMIME::sign_message(
			entity     => $message->{'msg'},
			cert_dir   => $list->{dir},
			key_passwd => $params{key_passwd},
			openssl    => $params{openssl}
		);
		if ($signed_msg) {
			$message->{'msg'} = $signed_msg->dup;
		} else {
			Sympa::Log::Syslog::do_log('notice', 'unable to sign message from %s', $params{listname});
			return undef;
		}
	}
	# my $msg_id = $message->{'msg'}->head()->get('Message-ID'); chomp $msg_id;

	if ($params{bulk}) {
		# in that case use bulk tables to prepare message distribution
		my $mergefeature = $params{merge} eq 'on';
		my $verpfeature =
			$params{verp} eq 'on'  ||
			$params{verp} eq 'mdn' ||
			$params{verp} eq 'dsn';
		my $trackingfeature =
			$params{verp} eq 'mdn' || $params{verp} eq 'dsn' ?
			$params{verp} : '';
		my $bulk_code = $params{bulk}->store(
			'message'          => $message,
			'rcpts'            => $params{rcpt},
			'from'             => $params{from},
			'robot'            => $params{robot},
			'listname'         => $params{listname},
			'priority_message' => $params{priority_message},
			'priority_packet'  => $params{priority_packet},
			'delivery_date'    => $params{delivery_date},
			'verp'             => $verpfeature,
			'tracking'         => $trackingfeature,
			'merge'            => $mergefeature,
			'dkim'             => $params{dkim},
			'tag_as_last'      => $params{tag_as_last},
		);

		unless (defined $bulk_code) {
			Sympa::Log::Syslog::do_log('err', 'Failed to store message for list %s', $params{listname});
			Sympa::List::send_notify_to_listmaster(
				'bulk_error',
				$params{robot},
				{'listname' => $params{listname}}
			);
			return undef;
		}
	} elsif ($params{spool}) {
		Sympa::Log::Syslog::do_log('debug',"NOT USING BULK");
		$params{spool}->store(message => $message);
	} else {
		# send it now
		Sympa::Log::Syslog::do_log('debug',"NOT USING BULK");
		*SMTP = _smtpto($params{from}, $params{rcpt}, $params{robot}, undef, undef, $params{sendmail}, $params{sendmail_args}, $params{maxsmtp});
		print SMTP $message->{'msg'}->as_string;
		unless (close SMTP) {
			Sympa::Log::Syslog::do_log('err', 'could not close safefork to sendmail');
			return undef;
		};
	}
	return 1;
}

# _smtpto($from, $rcpt, $robot, $msgkey, $sign_mode)
#
# Makes a sendmail ready for the recipients given as argument, uses a file
# descriptor in the smtp table which can be imported by other parties.
# Before, waits for number of children process < number allowed by sympa.conf
#
# Parameters:
# * $from: for SMTP "MAIL From:" field
# * $rcpt: ref(SCALAR)|ref(ARRAY)- for SMTP "RCPT To:" field
# * $robot: robot
# * $msgkey: a id of this message submission in notification table
#
# Return value:
# $fh - file handle on opened file for ouput, for SMTP "DATA" field | undef

sub _smtpto {
	my($from, $rcpt, $robot, $msgkey, $sign_mode, $sendmail, $sendmail_args, $maxsmtp) = @_;

	Sympa::Log::Syslog::do_log('debug2', 'smtpto( from :%s, rcpt:%s, robot:%s,  msgkey:%s, sign_mode: %s  )', $from, $rcpt, $robot, $msgkey, $sign_mode);

	unless ($from) {
		Sympa::Log::Syslog::do_log('err', 'Missing Return-Path');
	}

	if (ref($rcpt) eq 'SCALAR') {
		Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s )', $from, $$rcpt,$sign_mode);
	} elsif (ref($rcpt) eq 'ARRAY')  {
		Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s)', $from, join(',', @{$rcpt}), $sign_mode);
	}

	my($pid, $str);

	## Escape "-" at beginning of recepient addresses
	## prevent sendmail from taking it as argument

	if (ref($rcpt) eq 'SCALAR') {
		$$rcpt =~ s/^-/\\-/;
	} elsif (ref($rcpt) eq 'ARRAY') {
		my @emails = @$rcpt;
		foreach my $i (0..$#emails) {
			$rcpt->[$i] =~ s/^-/\\-/;
		}
	}

	## Check how many open smtp's we have, if too many wait for a few
	## to terminate and then do our job.

	Sympa::Log::Syslog::do_log('debug3',"Open = $opensmtp");
	while ($opensmtp > $maxsmtp) {
		Sympa::Log::Syslog::do_log('debug3', "too many open SMTP ($opensmtp), calling reaper");
		last if (reaper(0) == -1); ## Blocking call to the reaper.
	}

	*IN = ++$fh; *OUT = ++$fh;


	if (!pipe(IN, OUT)) {
		Sympa::Log::fatal_err(sprintf Sympa::Language::gettext("Unable to create a channel in smtpto: %s"), "$ERRNO"); ## No return
	}
	$pid = Sympa::Tools::safefork();
	$pid{$pid} = 0;

	if ($msgkey) {
		$sendmail_args .= ' -N success,delay,failure -V '.$msgkey;
	}
	if ($pid == 0) {

		close(OUT);
		open(STDIN, "<&IN");

		if (! ref($rcpt)) {
			exec $sendmail, split(/\s+/,$sendmail_args),'-f', $from, $rcpt;
		} elsif (ref($rcpt) eq 'SCALAR') {
			exec $sendmail, split(/\s+/,$sendmail_args), '-f', $from, $$rcpt;
		} elsif (ref($rcpt) eq 'ARRAY'){
			exec $sendmail, split(/\s+/,$sendmail_args), '-f', $from, @$rcpt;
		}

		exit 1; ## Should never get there.
	}
	if ($main::options{'mail'}) {
		$str = "safefork: $sendmail $sendmail_args -f $from ";
		if (! ref($rcpt)) {
			$str .= $rcpt;
		} elsif (ref($rcpt) eq 'SCALAR') {
			$str .= $$rcpt;
		} else {
			$str .= join(' ', @$rcpt);
		}
		Sympa::Log::Syslog::do_log('notice', $str);
	}
	unless (close(IN)){
		Sympa::Log::Syslog::do_log('err', "could not close safefork");
		return undef;
	}
	$opensmtp++;
	select(undef, undef,undef, 0.3) if ($opensmtp < $maxsmtp);
	return("$fh"); ## Symbol for the write descriptor.
}

# _reformat_message($message, $attachments, $defcharset)
#
# Reformat bodies of text parts contained in the message using
# recommended encoding schema and/or charsets defined by MIME::Charset.
#
# MIME-compliant headers are appended / modified.  And custom X-Mailer:
# header is appended :).
#
# Parameters:
# * $msg: ref(MIME::Entity) | string - message to reformat
# * $attachments: ref(ARRAY) - messages to be attached as subparts.
# * $defcharset
#
# Return value:
# a string

####################################################
## Comments from Soji Ikeda below
##  Some paths of message processing in Sympa can't recognize Unicode strings.
##  At least MIME::Parser::parse_data() and Template::proccess(): these methods
## occationalily break strings containing Unicode characters.
##
##  My mail_utf8 patch expects the behavior as following ---
##
##  Sub-messages to be attached (into digests, moderation notices etc.) will passed
##  to reformat_message() separately then attached to reformatted parent message
##  again.  As a result, sub-messages won't be broken.  Since they won't cause mixture
##  of Unicode string (parent message generated by Sympa::Template::parse_tt2()) and byte string (sub-messages).
##
##  Note: For compatibility with old style, data passed to reformat_message() already includes
##  sub-message(s).  Then:
##   - When a part has an `X-Sympa-Attach:' header field for internal use, new style,
##     reformat_message() attaches raw sub-message to reformatted parent message again;
##   - When a part doesn't have any `X-Sympa-Attach:' header fields, sub-messages generated by
##     [% INSERT %] directive(s) in the template will be used.
##
##  More Note: Latter behavior above will give expected result only if contents of sub-messages are
##  US-ASCII or ISO-8859-1. In other cases customized templates (if any) should be modified so that they
##  have appropriate `X-Sympa-Attach:' header fileds.
##
##  Sub-messages are gathered from template context paramenters.

sub _reformat_message($;$$) {
	my ($message, $attachments, $defcharset) = @_;
	$attachments ||= [];

	my $msg;

	my $parser = MIME::Parser->new();
	unless (defined $parser) {
		Sympa::Log::Syslog::do_log('err', "Failed to create MIME parser");
		return undef;
	}
	$parser->output_to_core(1);

	if (ref($message) && $message->isa('MIME::Entity')) {
		$msg = $message;
	} else {
		eval {
			$msg = $parser->parse_data($message);
		};
		if ($EVAL_ERROR) {
			Sympa::Log::Syslog::do_log('err', "Failed to parse MIME data");
			return undef;
		}
	}
	$msg->head()->delete("X-Mailer");
	$msg = _fix_part($msg, $parser, $attachments, $defcharset);
	$msg->head()->add("X-Mailer", sprintf "Sympa %s", Sympa::Constants::VERSION);
	return $msg->as_string();
}

sub _fix_part($$$$) {
	my ($part, $parser, $attachments, $defcharset) = @_;
	$attachments ||= [];

	return $part unless $part;

	my $enc = $part->head()->mime_attr("Content-Transfer-Encoding");
	# Parts with nonstandard encodings aren't modified.

	if ($enc and $enc !~ /^(?:base64|quoted-printable|[78]bit|binary)$/i) {
		return $part;
	}
	my $eff_type = $part->effective_type;

	if ($eff_type =~ m{^multipart/(signed|encrypted)$}){
		return $part;
	}

	if ($part->head()->get('X-Sympa-Attach')) { # Need re-attaching data.

		my $data = shift @{$attachments};
		if (ref($data) ne 'MIME::Entity') {
			eval {
				$data = $parser->parse_data($data);
			};
			if ($EVAL_ERROR) {
				Sympa::Log::Syslog::do_log('notice',"Failed to parse MIME data");
				$data = $parser->parse_data('');
			}
		}
		$part->head()->delete('X-Sympa-Attach');
		$part->parts([$data]);
	} elsif ($part->parts) {
		my @newparts = ();
		foreach ($part->parts) {
			push @newparts, _fix_part($_, $parser, $attachments, $defcharset);
		}
		$part->parts(\@newparts);
	} elsif ($eff_type =~ m{^(?:multipart|message)(?:/|\Z)}i) {
		# multipart or message types without subparts.

		return $part;
	} elsif (MIME::Tools::textual_type($eff_type)) {
		my $bodyh = $part->bodyhandle();
		# Encoded body or null body won't be modified.
		return $part if !$bodyh or $bodyh->is_encoded;

		my $head = $part->head();
		my $body = $bodyh->as_string();
		my $wrap = $body;
		if ($head->get('X-Sympa-NoWrap')) { # Need not wrapping
			$head->delete('X-Sympa-NoWrap');
		} elsif ($eff_type eq 'text/plain' and
			lc($head->mime_attr('Content-type.Format')||'') ne 'flowed') {
			$wrap = Sympa::Tools::wrap_text($body);
		}
		my $charset = $head->mime_attr("Content-Type.Charset") || $defcharset;

		my ($newbody, $newcharset, $newenc) =
		MIME::Charset::body_encode(Encode::decode('utf8', $wrap), $charset,
			Replacement => 'FALLBACK');
		if ($newenc eq $enc and $newcharset eq $charset and
			$newbody eq $body) {
			$head->add("MIME-Version", "1.0") unless $head->get("MIME-Version");
			return $part;
		}

		# Fix headers and body.
		$head->mime_attr("Content-Type", "TEXT/PLAIN")
		unless $head->mime_attr("Content-Type");
		$head->mime_attr("Content-Type.Charset", $newcharset);
		$head->mime_attr("Content-Transfer-Encoding", $newenc);
		$head->add("MIME-Version", "1.0") unless $head->get("MIME-Version");
		my $io = $bodyh->open("w");

		unless (defined $io) {
			Sympa::Log::Syslog::do_log('err', "Failed to save message : $ERRNO");
			return undef;
		}

		$io->print($newbody);
		$io->close;
		$part->sync_headers(Length => 'COMPUTE');
	} else {
		# Binary or text with long lines will be suggested to be BASE64.
		$part->head()->mime_attr("Content-Transfer-Encoding",
			$part->suggest_encoding);
		$part->sync_headers(Length => 'COMPUTE');
	}
	return $part;
}

=back

=cut

1;
