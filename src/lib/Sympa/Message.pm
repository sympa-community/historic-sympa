#<!-- RCS Identication ; $Revision$ ; $Date$ --> 

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

=head1 NAME 

Sympa::Message - Message object

=head1 DESCRIPTION 

This class implement a message.

=cut 

package Sympa::Message;

use strict;

use Mail::Header;
use Mail::Address;
use MIME::Entity;
use MIME::EncWords;
use MIME::Parser;

use Sympa::Configuration;
use Sympa::List;
use Sympa::Log;
use Sympa::Scenario;
use Sympa::Tools;
use Sympa::Tools::DKIM;
use Sympa::Tools::SMIME;

=head1 CLASS METHODS

=head2 Sympa::Message->new()

Creates a new L<Sympa::Message> object.

=head3 Arguments 

=over 

=item * I<$pkg>, a package name 

=item * I<$file>, the message file

=item * I<$noxsympato>, a boolean

=back 

=head3 Return 

A new L<Sympa::Message> object, or I<undef>, if something went wrong.

=cut 

sub new {
    
    my $pkg =shift;
    my $datas = shift;

    my $file = $datas->{'file'};
    my $noxsympato = $datas->{'noxsympato'};
    my $messageasstring = $datas->{'messageasstring'};
    my $mimeentity = $datas->{'mimeentity'};
    my $message_in_spool= $datas->{'message_in_spool'};

    my $message;
    my $input = 'file' if $file;
    $input = 'messageasstring' if $messageasstring; 
    $input = 'message_in_spool' if $message_in_spool; 
    $input = 'mimeentity' if $mimeentity; 
    &Sympa::Log::do_log('debug2', '%s::new(input= %s, noxsympato= %s)',__PACKAGE__,$input,$noxsympato);
    
    if ($mimeentity) {
	$message->{'msg'} = $mimeentity;
	$message->{'altered'} = '_ALTERED';

	## Bless Message object
	bless $message, $pkg;
	
	return $message;
    }

    my $parser = new MIME::Parser;
    $parser->output_to_core(1);
    
    my $msg;

    if ($message_in_spool){
	$messageasstring = $message_in_spool->{'messageasstring'};
	$message->{'messagekey'}= $message_in_spool->{'messagekey'};
	$message->{'spoolname'}= $message_in_spool->{'spoolname'};
	$message->{'create_list_if_needed'}= $message_in_spool->{'create_list_if_needed'};
    }
    if ($file) {
	## Parse message as a MIME::Entity
	$message->{'filename'} = $file;
	unless (open FILE, "$file") {
	    &Sympa::Log::do_log('err', 'Cannot open message file %s : %s',  $file, $!);
	    return undef;
	}
	while (<FILE>){
	    $messageasstring = $messageasstring.$_;
	}
	close(FILE);
        # use Data::Dumper;
	# my $dump = &Dumper($messageasstring); open (DUMP,">>/tmp/dumper"); printf DUMP 'lecture du fichier \n%s',$dump ; close DUMP; 
    }
    if($messageasstring){
	if (ref ($messageasstring)){
	    $msg = $parser->parse_data($messageasstring);
	}else{
	    $msg = $parser->parse_data(\$messageasstring);
	}
    }  
     
    unless ($msg){
	&Sympa::Log::do_log('err',"could not parse message"); 
	return undef;
    }
    $message->{'msg'} = $msg;
#    $message->{'msg_as_string'} = $msg->as_string; 
    $message->{'msg_as_string'} = $messageasstring; 
    $message->{'size'} = length($msg->as_string);

    my $hdr = $message->{'msg'}->head;

    ## Extract sender address
    unless ($hdr->get('From')) {
	&Sympa::Log::do_log('err', 'No From found in message %s, skipping.', $file);
	return undef;
    }   
    my @sender_hdr = Mail::Address->parse($hdr->get('From'));
    if ($#sender_hdr == -1) {
	&Sympa::Log::do_log('err', 'No valid address in From: field in %s, skipping', $file);
	return undef;
    }
    $message->{'sender'} = lc($sender_hdr[0]->address);

    unless (&Sympa::Tools::valid_email($message->{'sender'})) {
	&Sympa::Log::do_log('err', "Invalid From: field '%s'", $message->{'sender'});
	return undef;
    }

    ## Store decoded subject and its original charset
    my $subject = $hdr->get('Subject');
    if ($subject =~ /\S/) {
	my @decoded_subject = MIME::EncWords::decode_mimewords($subject);
	$message->{'subject_charset'} = 'US-ASCII';
	foreach my $token (@decoded_subject) {
	    unless ($token->[1]) {
		# don't decode header including raw 8-bit bytes.
		if ($token->[0] =~ /[^\x00-\x7F]/) {
		    $message->{'subject_charset'} = undef;
		    last;
		}
		next;
	    }
	    my $cset = MIME::Charset->new($token->[1]);
	    # don't decode header encoded with unknown charset.
	    unless ($cset->decoder) {
		$message->{'subject_charset'} = undef;
		last;
	    }
	    unless ($cset->output_charset eq 'US-ASCII') {
		$message->{'subject_charset'} = $token->[1];
	    }
	}
    } else {
	$message->{'subject_charset'} = undef;
    }
    if ($message->{'subject_charset'}) {
	$message->{'decoded_subject'} =
	    MIME::EncWords::decode_mimewords($subject, Charset => 'utf8');
    } else {
	$message->{'decoded_subject'} = $subject;
    }
    chomp $message->{'decoded_subject'};

    ## Extract recepient address (X-Sympa-To)
    $message->{'rcpt'} = $hdr->get('X-Sympa-To');
    chomp $message->{'rcpt'};
    unless (defined $noxsympato) { # message.pm can be used not only for message comming from queue
	unless ($message->{'rcpt'}) {
	    &Sympa::Log::do_log('err', 'no X-Sympa-To found, ignoring message file %s', $file);
	    return undef;
	}
	    
	## get listname & robot
	my ($listname, $robot) = split(/\@/,$message->{'rcpt'});
	
	$robot = lc($robot);
	$listname = lc($listname);
	$robot ||= $Sympa::Configuration::Conf{'domain'};
	my $spam_status = &Sympa::Scenario::request_action('spam_status','smtp',$robot, {'message' => $message});
	$message->{'spam_status'} = 'unkown';
	if(defined $spam_status) {
	    if (ref($spam_status ) eq 'HASH') {
		$message->{'spam_status'} =  $spam_status ->{'action'};
	    }else{
		$message->{'spam_status'} = $spam_status ;
	    }
	}
	
	my $conf_email = &Sympa::Configuration::get_robot_conf($robot, 'email');
	my $conf_host = &Sympa::Configuration::get_robot_conf($robot, 'host');
	unless ($listname =~ /^(sympa|$Sympa::Configuration::Conf{'listmaster_email'}|$conf_email)(\@$conf_host)?$/i) {
	    my $list_check_regexp = &Sympa::Configuration::get_robot_conf($robot,'list_check_regexp');
	    if ($listname =~ /^(\S+)-($list_check_regexp)$/) {
		$listname = $1;
	    }
	    
	    my $list = new Sympa::List ($listname, $robot, {'just_try' => 1});
	    if ($list) {
		$message->{'list'} = $list;
	    }	
	}
	# verify DKIM signature
	if (&Sympa::Configuration::get_robot_conf($robot, 'dkim_feature') eq 'on'){
	    $message->{'dkim_pass'} = dkim_verifier($message->{'msg_as_string'}, $Sympa::Configuration::Conf{'tmpdir'});
	}
    }
        
    ## valid X-Sympa-Checksum prove the message comes from web interface with authenticated sender
    if ( $hdr->get('X-Sympa-Checksum')) {
	my $chksum = $hdr->get('X-Sympa-Checksum'); chomp $chksum;
	my $rcpt = $hdr->get('X-Sympa-To'); chomp $rcpt;

	if ($chksum eq &Sympa::Tools::sympa_checksum($rcpt, $Sympa::Configuration::Conf{'cookie'})) {
	    $message->{'md5_check'} = 1 ;
	}else{
	    &Sympa::Log::do_log('err',"incorrect X-Sympa-Checksum header");	
	}
    }

    ## S/MIME
    if ($Sympa::Configuration::Conf{'openssl'}) {

	## Decrypt messages
	if (($hdr->get('Content-Type') =~ /application\/(x-)?pkcs7-mime/i) &&
	    ($hdr->get('Content-Type') !~ /signed-data/)){
	    my ($dec, $dec_as_string) = smime_decrypt ($message->{'msg'}, $message->{'list'}, $Sympa::Configuration::Conf{'tmpdir'}, $Sympa::Configuration::Conf{'home'}, $Sympa::Configuration::Conf{'key_passwd'}, $Sympa::Configuration::Conf{'openssl'});
	    
	    unless (defined $dec) {
		&Sympa::Log::do_log('debug', "Message %s could not be decrypted", $file);
		return undef;
		## We should the sender and/or the listmaster
	    }

	    $message->{'smime_crypted'} = 'smime_crypted';
	    $message->{'orig_msg'} = $message->{'msg'};
	    $message->{'msg'} = $dec;
	    $message->{'msg_as_string'} = $dec_as_string;
	    $hdr = $dec->head;
	    &Sympa::Log::do_log('debug', "message %s has been decrypted", $file);
	}
	
	## Check S/MIME signatures
	if ($hdr->get('Content-Type') =~ /multipart\/signed|application\/(x-)?pkcs7-mime/i) {
	    $message->{'protected'} = 1; ## Messages that should not be altered (no footer)
	    my $signed = smime_sign_check ($message, $Sympa::Configuration::Conf{'tmpdir'},$Sympa::Configuration::Conf{'cafile'},$Sympa::Configuration::Conf{'capath'}, $Sympa::Configuration::Conf{'openssl'}, $Sympa::Configuration::Conf{'ssl_cert_dir'});
	    if ($signed->{'body'}) {
		$message->{'smime_signed'} = 1;
		$message->{'smime_subject'} = $signed->{'subject'};
		&Sympa::Log::do_log('debug', "message %s is signed, signature is checked", $file);
	    }
	    ## Il faudrait traiter les cas d'erreur (0 différent de undef)
	}
    }
    ## TOPICS
    my $topics;
    if ($topics = $hdr->get('X-Sympa-Topic')){
	$message->{'topic'} = $topics;
    }

    bless $message, $pkg;
    return $message;
}

=head2 $message->dump($output)

Dump this object to a stream.

=head3 Parameters

=over 

=item * I<$output>: the stream to which dump the object

=back 

=head3 Return value

A true value.

=cut 

sub dump {
    my ($self, $output) = @_;
#    my $output ||= \*STDERR;

    my $old_output = select;
    select $output;

    foreach my $key (keys %{$self}) {
	if (ref($self->{$key}) eq 'MIME::Entity') {
	    printf "%s =>\n", $key;
	    $self->{$key}->print;
	}else {
	    printf "%s => %s\n", $key, $self->{$key};
	}
    }
    
    select $old_output;

    return 1;
}

=head2 $message->add_topic($topic)

Add topic and put header X-Sympa-Topic.

=head3 Parameters

=over 

=item * I<$topic>: the topic to add

=back 

=head3 Return value

A true value.

=cut 

sub add_topic {
    my ($self,$topic) = @_;

    $self->{'topic'} = $topic;
    my $hdr = $self->{'msg'}->head;
    $hdr->add('X-Sympa-Topic', $topic);

    return 1;
}


=head2 sub $message->get_topic()

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

sub clean_html {
    my $self = shift;
    my ($listname, $robot) = split(/\@/,$self->{'rcpt'});
    $robot = lc($robot);
    $listname = lc($listname);
    $robot ||= $Sympa::Configuration::Conf{'host'};
    my $new_msg;
    if($new_msg = &fix_html_part($self->{'msg'},$robot)) {
	$self->{'msg'} = $new_msg;
	return 1;
    }
    return 0;
}

sub fix_html_part {
    my $part = shift;
    my $robot = shift;
    return $part unless $part;
    my $eff_type = $part->head->mime_attr("Content-Type");
    if ($part->parts) {
	my @newparts = ();
	foreach ($part->parts) {
	    push @newparts, &fix_html_part($_,$robot);
	}
	$part->parts(\@newparts);
    } elsif ($eff_type =~ /^text\/html/i) {
	my $bodyh = $part->bodyhandle;
	# Encoded body or null body won't be modified.
	return $part if !$bodyh or $bodyh->is_encoded;

	my $body = $bodyh->as_string;
	# Re-encode parts with 7-bit charset (ISO-2022-*), since
	# StripScripts cannot handle them correctly.
	my $cset = MIME::Charset->new($part->head->mime_attr('Content-Type.Charset') || '');
	unless ($cset->decoder) {
	    # Charset is unknown.  Detect 7-bit charset.
	    my ($dummy, $charset) =
		MIME::Charset::body_encode($body, '', Detect7Bit => 'YES');
	    $cset = MIME::Charset->new($charset);
	}
	if ($cset->decoder and $cset->as_string =~ /^ISO-2022-/i) {
	    $part->head->mime_attr('Content-Type.Charset', 'UTF-8');
	    $cset->encoder('UTF-8');
	    $body = $cset->encode($body);
	}

	my $filtered_body = &Sympa::Tools::sanitize_html(
            'string' => $body,
            'robot'=> $robot,
            'host' => Sympa::Configuration::get_robot_conf($robot,'http_host')
        );

	my $io = $bodyh->open("w");
	unless (defined $io) {
	    &Sympa::Log::do_log('err', "Failed to save message : $!");
	    return undef;
	}
	$io->print($filtered_body);
	$io->close;
    }
    return $part;
}

=head1 FUNCTIONS

=head2 get_body_from_msg_as_string($message)

Extract body as string from I<$message>. Do NOT use Mime::Entity in order to
preserveB64 encoding form and so preserve S/MIME signature.

=cut 
sub get_body_from_msg_as_string {
    my $msg =shift;

    my @bodysection =split("\n\n",$msg );    # convert it as a tab with headers as first element
    shift @bodysection;                      # remove headers
    return (join ("\n\n",@bodysection));  # convert it back as string
}


## Packages must return true.
1;
=head1 AUTHORS 

=over 

=item * Serge Aumont <sa AT cru.fr> 

=item * Olivier Salaün <os AT cru.fr> 

=back 

=cut 
