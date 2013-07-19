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

Sympa::Message - Message object

=head1 DESCRIPTION

This class implement a message.

=cut

package Sympa::Message;

use strict;

use English qw(-no_match_vars);
use Mail::Address;
use MIME::EncWords;
use MIME::Parser;

use Sympa::Configuration;
use Sympa::Log::Syslog;
use Sympa::Scenario;
use Sympa::Tools;
use Sympa::Tools::File;
use Sympa::Tools::SMIME;

=head1 CLASS METHODS

=over

=item Sympa::Message->new(%parameters)

Creates a new L<Sympa::Message> object.

Parameters:

=over

=item C<file> => string

The message source.

=item C<string> => string

The message source.

=item C<entity> => L<MIME::Entity>

The message source.

=item C<noxsympato> => boolean

=item C<messagekey> => FIXME

=item C<spoolname> => FIXME

=item C<create_list_if_needed> => FIXME

=back

Return:

A new L<Sympa::Message> object, or I<undef>, if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	my $file       = $params{'file'};
	my $string     = $params{'string'};
	my $entity     = $params{'entity'};
	my $noxsympato = $params{'noxsympato'};

	my $input =
		$file    ? 'file'   :
		$string  ? 'string' :
		$entity  ? 'entity' :
		undef    ;
	Sympa::Log::Syslog::do_log('debug2', '(input= %s, noxsympato= %s)',$input,$noxsympato);

	if ($entity) {
		my $self = {
			msg     => $entity,
			altered => '_ALTERED'
		};

		bless $self, $class;

		return $self;
	}

	my $parser = MIME::Parser->new();
	$parser->output_to_core(1);

	my $msg;
	my $self = {
		messagekey            => $params{messagekey},
		spoolname             => $params{spoolname},
		create_list_if_needed => $params{create_list_if_needed}
	};

	if ($file) {
		## Parse message as a MIME::Entity
		$self->{'filename'} = $file;
		$string = Sympa::Tools::File::slurp_file($file);
	}
	if($string){
		if (ref ($string)){
			$msg = $parser->parse_data($string);
		} else {
			$msg = $parser->parse_data(\$string);
		}
	}

	unless ($msg){
		Sympa::Log::Syslog::do_log('err',"could not parse message");
		return undef;
	}
	$self->{'msg'} = $msg;
	#    $message->{'msg_as_string'} = $msg->as_string();
	$self->{'msg_as_string'} = $string;
	$self->{'size'} = length($msg->as_string());

	my $hdr = $self->{'msg'}->head();

	## Extract sender address
	unless ($hdr->get('From')) {
		Sympa::Log::Syslog::do_log('err', 'No From found in message %s, skipping.', $file);
		return undef;
	}
	my @sender_hdr = Mail::Address->parse($hdr->get('From'));
	if ($#sender_hdr == -1) {
		Sympa::Log::Syslog::do_log('err', 'No valid address in From: field in %s, skipping', $file);
		return undef;
	}
	$self->{'sender'} = lc($sender_hdr[0]->address);

	unless (Sympa::Tools::valid_email($self->{'sender'})) {
		Sympa::Log::Syslog::do_log('err', "Invalid From: field '%s'", $self->{'sender'});
		return undef;
	}

	## Store decoded subject and its original charset
	my $subject = $hdr->get('Subject');
	if ($subject =~ /\S/) {
		my @decoded_subject = MIME::EncWords::decode_mimewords($subject);
		$self->{'subject_charset'} = 'US-ASCII';
		foreach my $token (@decoded_subject) {
			unless ($token->[1]) {
				# don't decode header including raw 8-bit bytes.
				if ($token->[0] =~ /[^\x00-\x7F]/) {
					$self->{'subject_charset'} = undef;
					last;
				}
				next;
			}
			my $cset = MIME::Charset->new($token->[1]);
			# don't decode header encoded with unknown charset.
			unless ($cset->decoder) {
				$self->{'subject_charset'} = undef;
				last;
			}
			unless ($cset->output_charset eq 'US-ASCII') {
				$self->{'subject_charset'} = $token->[1];
			}
		}
	} else {
		$self->{'subject_charset'} = undef;
	}
	if ($self->{'subject_charset'}) {
		$self->{'decoded_subject'} =
		MIME::EncWords::decode_mimewords($subject, Charset => 'utf8');
	} else {
		$self->{'decoded_subject'} = $subject;
	}
	chomp $self->{'decoded_subject'};

	## Extract recepient address (X-Sympa-To)
	$self->{'rcpt'} = $hdr->get('X-Sympa-To');
	chomp $self->{'rcpt'};
	unless (defined $noxsympato) { # message.pm can be used not only for message comming from queue
		unless ($self->{'rcpt'}) {
			Sympa::Log::Syslog::do_log('err', 'no X-Sympa-To found, ignoring message file %s', $file);
			return undef;
		}

		## get listname & robot
		my ($listname, $robot) = split(/\@/,$self->{'rcpt'});

		$robot = lc($robot);
		$listname = lc($listname);
		$robot ||= Site->domain;
		my $spam_status =
		Sympa::Scenario::request_action('spam_status','smtp',$robot, {'message' => $self});
		$self->{'spam_status'} = 'unkown';
		if(defined $spam_status) {
			if (ref($spam_status ) eq 'HASH') {
				$self->{'spam_status'} =  $spam_status ->{'action'};
			} else {
				$self->{'spam_status'} = $spam_status;
			}
		}

		my $conf_email = $robot->email;
		my $conf_host = $robot->host;
		unless ($listname =~ /^(sympa|Site->listmaster_email|$conf_email)(\@$conf_host)?$/i) {
			my $list_check_regexp = $robot->list_check_regexp;
			if ($listname =~ /^(\S+)-($list_check_regexp)$/) {
				$listname = $1;
			}

			$self->{'listname'} = $listname;
		}
		# verify DKIM signature
		if ($robot->dkim_feature eq 'on'){
			# assume Sympa::Tools::DKIM can be loaded if the setting is still on
			require Sympa::Tools::DKIM;
			$self->{'dkim_pass'} = Sympa::Tools::DKIM::dkim_verifier($self->{'msg_as_string'}, Site->tmpdir);
		}
	}

	## valid X-Sympa-Checksum prove the message comes from web interface with authenticated sender
	if ( $hdr->get('X-Sympa-Checksum')) {
		my $chksum = $hdr->get('X-Sympa-Checksum'); chomp $chksum;
		my $rcpt = $hdr->get('X-Sympa-To'); chomp $rcpt;

		if ($chksum eq Sympa::Tools::sympa_checksum($rcpt, Site->cookie)) {
			$self->{'md5_check'} = 1;
		} else {
			Sympa::Log::Syslog::do_log('err',"incorrect X-Sympa-Checksum header");
		}
	}

	## S/MIME
	if (Site->openssl) {

		## Decrypt messages
		if (($hdr->get('Content-Type') =~ /application\/(x-)?pkcs7-mime/i) &&
			($hdr->get('Content-Type') !~ /signed-data/)){
			my ($dec, $dec_as_string) = Sympa::Tools::SMIME::decrypt_message(
				entity     => $self->{'msg'},
				cert_dir   => Site->ssl_cert_dir,
				key_passwd => Site->key_passwd,
				openssl    => Site->openssl
			);

			unless (defined $dec) {
				Sympa::Log::Syslog::do_log('debug', "Message %s could not be decrypted", $file);
				return undef;
				## We should the sender and/or the listmaster
			}

			$self->{'smime_crypted'} = 'smime_crypted';
			$self->{'orig_msg'} = $self->{'msg'};
			$self->{'msg'} = $dec;
			$self->{'msg_as_string'} = $dec_as_string;
			$hdr = $dec->head();
			Sympa::Log::Syslog::do_log('debug', "message %s has been decrypted", $file);
		}

		## Check S/MIME signatures
		if ($hdr->get('Content-Type') =~ /multipart\/signed|application\/(x-)?pkcs7-mime/i) {
			$self->{'protected'} = 1; ## Messages that should not be altered (no footer)
			my $signed = Sympa::Tools::SMIME::check_signature(
				message  => $self,
				cafile   => Site->cafile,
				capath   => Site->capath,
				openssl  => Site->openssl,
				cert_dir => Site->ssl_cert_dir
			);
			if ($signed->{'body'}) {
				$self->{'smime_signed'} = 1;
				$self->{'smime_subject'} = $signed->{'subject'};
				Sympa::Log::Syslog::do_log('debug', "message %s is signed, signature is checked", $file);
			}
			## Il faudrait traiter les cas d'erreur (0 différent de undef)
		}
	}
	## TOPICS
	my $topics;
	if ($topics = $hdr->get('X-Sympa-Topic')){
		$self->{'topic'} = $topics;
	}

	bless $self, $class;

	return $self;
}

=item $message->dump($output)

Dump this object to a stream.

Parameters:

=over

=item filehandle

the stream to which dump the object

=back

Return value:

A true value.

=cut

sub dump {
	my ($self, $output) = @_;
#    my $output ||= \*STDERR;

	my $old_output = select;
	select $output;

	foreach my $key (keys %{$self}) {
		if (ref($self->{$key}) && $self->{$key}->isa('MIME::Entity')) {
			printf "%s =>\n", $key;
			$self->{$key}->print;
		} else {
			printf "%s => %s\n", $key, $self->{$key};
		}
	}

	select $old_output;

	return 1;
}

=item $message->add_topic($topic)

Add topic and put header X-Sympa-Topic.

Parameters:

=over

=item FIXME

The topic to add

=back

Return value:

A true value.

=cut

sub add_topic {
	my ($self, $topic) = @_;

	$self->{'topic'} = $topic;
	my $hdr = $self->{'msg'}->head();
	$hdr->add('X-Sympa-Topic', $topic);

	return 1;
}


=item $message->get_topic()

Get topic.

=cut

sub get_topic {
	my ($self) = @_;

	if (defined $self->{'topic'}) {
		return $self->{'topic'};

	} else {
		return '';
	}
}

=item $message->clean_html()

FIXME.

=cut

sub clean_html {
	my ($self) = @_;

	my ($listname, $robot) = split(/\@/,$self->{'rcpt'});
	$robot = lc($robot);
	$listname = lc($listname);
	$robot ||= Site->host;
	my $new_msg;
	if($new_msg = fix_html_part($self->{'msg'},$robot)) {
		$self->{'msg'} = $new_msg;
		return 1;
	}
	return 0;
}

=item $message->fix_html_part($part, $robot)

FIXME.

=cut

sub fix_html_part {
	my ($part, $robot) = @_;

	return $part unless $part;
	my $eff_type = $part->head()->mime_attr("Content-Type");
	if ($part->parts) {
		my @newparts = ();
		foreach ($part->parts) {
			push @newparts, fix_html_part($_,$robot);
		}
		$part->parts(\@newparts);
	} elsif ($eff_type =~ /^text\/html/i) {
		my $bodyh = $part->bodyhandle();
		# Encoded body or null body won't be modified.
		return $part if !$bodyh or $bodyh->is_encoded();

		my $body = $bodyh->as_string();
		# Re-encode parts with 7-bit charset (ISO-2022-*), since
		# StripScripts cannot handle them correctly.
		my $cset = MIME::Charset->new($part->head()->mime_attr('Content-Type.Charset') || '');
		unless ($cset->decoder) {
			# Charset is unknown.  Detect 7-bit charset.
			my (undef, $charset) =
			MIME::Charset::body_encode($body, '', Detect7Bit => 'YES');
			$cset = MIME::Charset->new($charset);
		}
		if ($cset->decoder and $cset->as_string() =~ /^ISO-2022-/i) {
			$part->head()->mime_attr('Content-Type.Charset', 'UTF-8');
			$cset->encoder('UTF-8');
			$body = $cset->encode($body);
		}

		my $filtered_body = Sympa::Tools::sanitize_html(
			'string' => $body,
			'robot'=> $robot,
			'host' => $robot->http_host
		);

		my $io = $bodyh->open("w");
		unless (defined $io) {
			Sympa::Log::Syslog::do_log('err', "Failed to save message : $ERRNO");
			return undef;
		}
		$io->print($filtered_body);
		$io->close;
	}
	return $part;
}

=back

=encoding utf8

=head1 AUTHORS

=over

=item * Serge Aumont <sa AT cru.fr>

=item * Olivier Salaün <os AT cru.fr>

=back

=cut

1;
