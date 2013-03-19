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

Sympa::Tools::DKIM - DKIM-related functions

=head1 DESCRIPTION

This module provides various functions for managing DKIM.

=cut

package Sympa::Tools::DKIM;

use strict;

use English qw(-no_match_vars);
use Mail::DKIM::Verifier;
use Mail::DKIM::Signer;
use Mail::DKIM::TextWrap;
use MIME::Parser;

use Sympa::Message;
use Sympa::List;
use Sympa::Log::Syslog;

=head1 FUNCTIONS

=head2 get_dkim_parameters(%parameters)

=head3 Parameters

=over

=item * I<robot>

=item * I<listname>

=back

=head3 Return value

=cut

sub get_dkim_parameters {
    my (%params) = @_;

    my $robot = $params{'robot'};
    my $listname = $params{'listname'};
    Sympa::Log::Syslog::do_log('debug2',"get_dkim_parameters (%s,%s)",$robot, $listname);

    my $data ; my $keyfile ;
    if ($listname) {
	# fetch dkim parameter in list context
	my $list = Sympa::List->new(name => $listname, robot => $robot);
	unless ($list){
	    Sympa::Log::Syslog::do_log('err',"Could not load list %s@%s",$listname, $robot);
	    return undef;
	}

	$data->{'d'} = $list->{'admin'}{'dkim_parameters'}{'signer_domain'};
	if ($list->{'admin'}{'dkim_parameters'}{'signer_identity'}) {
	    $data->{'i'} = $list->{'admin'}{'dkim_parameters'}{'signer_identity'};
	}else{
	    # RFC 4871 (page 21)
	    $data->{'i'} = $list->{'name'}.'-request@'.$robot;
	}

	$data->{'selector'} = $list->{'admin'}{'dkim_parameters'}{'selector'};
	$keyfile = $list->{'admin'}{'dkim_parameters'}{'private_key_path'};
    }else{
	# in robot context
	$data->{'d'} = $params{'signer_domain'};
	$data->{'i'} = $params{'signer_identity'};
	$data->{'selector'} = $params{'selector'};
	$keyfile = $params{'keyfile'};
    }
    unless (open (KEY, $keyfile)) {
	Sympa::Log::Syslog::do_log('err',"Could not read dkim private key %s",$keyfile);
	return undef;
    }
    while (<KEY>){
	$data->{'private_key'} .= $_;
    }
    close (KEY);

    return $data;
}

=head2 dkim_verifier($msg, $tmpdir)

Input a msg as string, output the dkim status

=cut

sub dkim_verifier {
    my ($msg_as_string, $tmpdir, $dkim) = @_;

    Sympa::Log::Syslog::do_log('debug',"dkim verifier");

    unless ( $dkim = Mail::DKIM::Verifier->new() ){
	Sympa::Log::Syslog::do_log('err', 'Could not create Mail::DKIM::Verifier');
	return undef;
    }

    my $temporary_file = $tmpdir."/dkim.".$PID ;
    if (!open(MSGDUMP,"> $temporary_file")) {
	Sympa::Log::Syslog::do_log('err', 'Can\'t store message in file %s', $temporary_file);
	return undef;
    }
    print MSGDUMP $msg_as_string ;

    unless (close(MSGDUMP)){
	Sympa::Log::Syslog::do_log('err',"unable to dump message in temporary file $temporary_file");
	return undef;
    }

    unless (open (MSGDUMP, "$temporary_file")) {
	Sympa::Log::Syslog::do_log('err', 'Can\'t read message in file %s', $temporary_file);
	return undef;
    }

    # this documented method is pretty but dont validate signatures, why ?
    # $dkim->load(\*MSGDUMP);
    while (<MSGDUMP>){
	chomp;
	s/\015$//;
	$dkim->PRINT("$_\015\012");
    }

    $dkim->CLOSE;
    close(MSGDUMP);
    unlink ($temporary_file);

    foreach my $signature ($dkim->signatures) {
	return 1 if  ($signature->result_detail eq "pass");
    }
    return undef;
}

=head2 remove_invalid_dkim_signature($tmpdir, $msg)

Input a msg as string, output idem without signature if invalid

=cut

sub remove_invalid_dkim_signature {
    my ($tmpdir, $msg_as_string) = @_;
    Sympa::Log::Syslog::do_log('debug',"removing invalide dkim signature");

    unless (dkim_verifier($msg_as_string, $tmpdir)){
	my $body_as_string = Sympa::Message::get_body_from_msg_as_string ($msg_as_string);

	my $parser = MIME::Parser->new;
	$parser->output_to_core(1);
	my $entity = $parser->parse_data($msg_as_string);
	unless($entity) {
	    Sympa::Log::Syslog::do_log('err','could not parse message');
	    return $msg_as_string ;
	}
	$entity->head->delete('DKIM-Signature');
Sympa::Log::Syslog::do_log('debug',"removing invalide dkim signature header");
	return $entity->head->as_string."\n".$body_as_string;
    }else{
	return ($msg_as_string); # sgnature is valid.
    }
}

=head2 dkim_sign($msg, $data, $tmpdir)

Input object msg and listname, output signed message object

=cut

sub dkim_sign {
    # in case of any error, this proc MUST return $msg_as_string NOT undef ; this would cause Sympa to send empty mail
    my ($msg_as_string, $data, $tmpdir) = @_;

    my $dkim_d = $data->{'dkim_d'};
    my $dkim_i = $data->{'dkim_i'};
    my $dkim_selector = $data->{'dkim_selector'};
    my $dkim_privatekey = $data->{'dkim_privatekey'};

    Sympa::Log::Syslog::do_log('debug2', '(msg:%s,dkim_d:%s,dkim_i%s,dkim_selector:%s,dkim_privatekey:%s)', substr($msg_as_string,0,30),$dkim_d,$dkim_i,$dkim_selector, substr($dkim_privatekey,0,30));

    unless ($dkim_selector) {
	Sympa::Log::Syslog::do_log('err',"DKIM selector is undefined, could not sign message");
	return $msg_as_string;
    }
    unless ($dkim_privatekey) {
	Sympa::Log::Syslog::do_log('err',"DKIM key file is undefined, could not sign message");
	return $msg_as_string;
    }
    unless ($dkim_d) {
	Sympa::Log::Syslog::do_log('err',"DKIM d= tag is undefined, could not sign message");
	return $msg_as_string;
    }

    my $temporary_keyfile = $tmpdir."/dkimkey.".$PID ;
    if (!open(MSGDUMP,"> $temporary_keyfile")) {
	Sympa::Log::Syslog::do_log('err', 'Can\'t store key in file %s', $temporary_keyfile);
	return $msg_as_string;
    }
    print MSGDUMP $dkim_privatekey ;
    close(MSGDUMP);

    my $dkim ;
    if ($dkim_i) {
    # create a signer object
	$dkim = Mail::DKIM::Signer->new(
					Algorithm => "rsa-sha1",
					Method    => "relaxed",
					Domain    => $dkim_d,
					Identity  => $dkim_i,
					Selector  => $dkim_selector,
					KeyFile   => $temporary_keyfile,
					);
    }else{
	$dkim = Mail::DKIM::Signer->new(
					Algorithm => "rsa-sha1",
					Method    => "relaxed",
					Domain    => $dkim_d,
					Selector  => $dkim_selector,
					KeyFile   => $temporary_keyfile,
					);
    }
    unless ($dkim) {
	Sympa::Log::Syslog::do_log('err', 'Can\'t create Mail::DKIM::Signer');
	return ($msg_as_string);
    }
    my $temporary_file = $tmpdir."/dkim.".$PID ;
    if (!open(MSGDUMP,"> $temporary_file")) {
	Sympa::Log::Syslog::do_log('err', 'Can\'t store message in file %s', $temporary_file);
	return ($msg_as_string);
    }
    print MSGDUMP $msg_as_string ;
    close(MSGDUMP);

    unless (open (MSGDUMP , $temporary_file)){
	Sympa::Log::Syslog::do_log('err', 'Can\'t read temporary file %s', $temporary_file);
	return undef;
    }

    while (<MSGDUMP>)
    {
	# remove local line terminators
	chomp;
	s/\015$//;
	# use SMTP line terminators
	$dkim->PRINT("$_\015\012");
    }
    close MSGDUMP;
    unless ($dkim->CLOSE) {
	Sympa::Log::Syslog::do_log('err', 'Cannot sign (DKIM) message');
	return ($msg_as_string);
    }
    my $message = Sympa::Message->new(
	    file       => $temporary_file,
	    noxsympato => 'noxsympato'
    );
    unless ($message){
	Sympa::Log::Syslog::do_log('err',"unable to load $temporary_file as a message objet");
	return ($msg_as_string);
    }

    if ($main::options{'debug'}) {
	Sympa::Log::Syslog::do_log('debug',"temporary file is $temporary_file");
    }else{
	unlink ($temporary_file);
    }
    unlink ($temporary_keyfile);

    $message->{'msg'}->head->add('DKIM-signature',$dkim->signature->as_string);

    # Do NOT use Mime::Entity in order to preserve base 64 encoding and S/MIME
    # signature.
    my @sections = split(/\n\n/, $msg_as_string);
    shift @sections;
    my $body = join("\n\n", @sections);

    return $message->{'msg'}->head->as_string."\n".$body;
}

1;
