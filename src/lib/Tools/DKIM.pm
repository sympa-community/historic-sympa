# tools.pl - This module provides various tools for Sympa
# RCS Identication ; $Revision: 7686 $ ; $Date: 2012-10-08 17:37:46 +0200 (lun. 08 oct. 2012) $ 
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

package Tools::DKIM;

use strict;

use Exporter;
use Mail::DKIM::Verifier;
use Mail::DKIM::Signer;
use MIME::Parser;

use Conf;
use List;
use Log;
use Message;

our @ISA = qw(Exporter);
our @EXPORT = qw(
    get_dkim_parameters
    dkim_verifier
    remove_invalid_dkim_signature
    dkim_sign
);

sub get_dkim_parameters {

    my $params = shift;

    my $robot = $params->{'robot'};
    my $listname = $params->{'listname'};
    &Log::do_log('debug2',"get_dkim_parameters (%s,%s)",$robot, $listname);

    my $data ; my $keyfile ;
    if ($listname) {
	# fetch dkim parameter in list context
	my $list = new List ($listname,$robot);
	unless ($list){
	    &Log::do_log('err',"Could not load list %s@%s",$listname, $robot);
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
	$data->{'d'} = &Conf::get_robot_conf($robot, 'dkim_signer_domain');
	$data->{'i'} = &Conf::get_robot_conf($robot, 'dkim_signer_identity');
	$data->{'selector'} = &Conf::get_robot_conf($robot, 'dkim_selector');
	$keyfile = &Conf::get_robot_conf($robot, 'dkim_private_key_path');
    }
    unless (open (KEY, $keyfile)) {
	&Log::do_log('err',"Could not read dkim private key %s",&Conf::get_robot_conf($robot, 'dkim_signer_selector'));
	return undef;
    }
    while (<KEY>){
	$data->{'private_key'} .= $_;
    }
    close (KEY);

    return $data;
}

# input a msg as string, output the dkim status
sub dkim_verifier {
    my $msg_as_string = shift;
    my $dkim;

    &Log::do_log('debug',"dkim verifier");
    unless (eval "require Mail::DKIM::Verifier") {
	&Log::do_log('err', "Failed to load Mail::DKIM::verifier perl module, ignoring DKIM signature");
	return undef;
    }
    
    unless ( $dkim = Mail::DKIM::Verifier->new() ){
	&Log::do_log('err', 'Could not create Mail::DKIM::Verifier');
	return undef;
    }
   
    my $temporary_file = $Conf::Conf{'tmpdir'}."/dkim.".$$ ;  
    if (!open(MSGDUMP,"> $temporary_file")) {
	&Log::do_log('err', 'Can\'t store message in file %s', $temporary_file);
	return undef;
    }
    print MSGDUMP $msg_as_string ;

    unless (close(MSGDUMP)){ 
	&Log::do_log('err',"unable to dump message in temporary file $temporary_file"); 
	return undef; 
    }

    unless (open (MSGDUMP, "$temporary_file")) {
	&Log::do_log('err', 'Can\'t read message in file %s', $temporary_file);
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

# input a msg as string, output idem without signature if invalid
sub remove_invalid_dkim_signature {
    &Log::do_log('debug',"removing invalide dkim signature");
    my $msg_as_string = shift;

    unless (dkim_verifier($msg_as_string)){
	my $body_as_string = &Message::get_body_from_msg_as_string ($msg_as_string);

	my $parser = new MIME::Parser;
	$parser->output_to_core(1);
	my $entity = $parser->parse_data($msg_as_string);
	unless($entity) {
	    &Log::do_log('err','could not parse message');
	    return $msg_as_string ;
	}
	$entity->head->delete('DKIM-Signature');
&Log::do_log('debug',"removing invalide dkim signature header");
	return $entity->head->as_string."\n".$body_as_string;
    }else{
	return ($msg_as_string); # sgnature is valid.
    }
}

# input object msg and listname, output signed message object
sub dkim_sign {
    # in case of any error, this proc MUST return $msg_as_string NOT undef ; this would cause Sympa to send empty mail 
    my $msg_as_string = shift;
    my $data = shift;
    my $dkim_d = $data->{'dkim_d'};    
    my $dkim_i = $data->{'dkim_i'};
    my $dkim_selector = $data->{'dkim_selector'};
    my $dkim_privatekey = $data->{'dkim_privatekey'};

    &Log::do_log('debug2', 'Tools::DKIM::dkim_sign (msg:%s,dkim_d:%s,dkim_i%s,dkim_selector:%s,dkim_privatekey:%s)',substr($msg_as_string,0,30),$dkim_d,$dkim_i,$dkim_selector, substr($dkim_privatekey,0,30));

    unless ($dkim_selector) {
	&Log::do_log('err',"DKIM selector is undefined, could not sign message");
	return $msg_as_string;
    }
    unless ($dkim_privatekey) {
	&Log::do_log('err',"DKIM key file is undefined, could not sign message");
	return $msg_as_string;
    }
    unless ($dkim_d) {
	&Log::do_log('err',"DKIM d= tag is undefined, could not sign message");
	return $msg_as_string;
    }
    
    my $temporary_keyfile = $Conf::Conf{'tmpdir'}."/dkimkey.".$$ ;  
    if (!open(MSGDUMP,"> $temporary_keyfile")) {
	&Log::do_log('err', 'Can\'t store key in file %s', $temporary_keyfile);
	return $msg_as_string;
    }
    print MSGDUMP $dkim_privatekey ;
    close(MSGDUMP);

    unless (eval "require Mail::DKIM::Signer") {
	&Log::do_log('err', "Failed to load Mail::DKIM::signer perl module, ignoring DKIM signature");
	return ($msg_as_string); 
    }
    unless (eval "require Mail::DKIM::TextWrap") {
	&Log::do_log('err', "Failed to load Mail::DKIM::TextWrap perl module, signature will not be pretty");
    }
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
	&Log::do_log('err', 'Can\'t create Mail::DKIM::Signer');
	return ($msg_as_string); 
    }    
    my $temporary_file = $Conf::Conf{'tmpdir'}."/dkim.".$$ ;  
    if (!open(MSGDUMP,"> $temporary_file")) {
	&Log::do_log('err', 'Can\'t store message in file %s', $temporary_file);
	return ($msg_as_string); 
    }
    print MSGDUMP $msg_as_string ;
    close(MSGDUMP);

    unless (open (MSGDUMP , $temporary_file)){
	&Log::do_log('err', 'Can\'t read temporary file %s', $temporary_file);
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
	&Log::do_log('err', 'Cannot sign (DKIM) message');
	return ($msg_as_string); 
    }
    my $message = new Message({'file'=>$temporary_file,'noxsympato'=>'noxsympato'});
    unless ($message){
	&Log::do_log('err',"unable to load $temporary_file as a message objet");
	return ($msg_as_string); 
    }

    if ($main::options{'debug'}) {
	&Log::do_log('debug',"temporary file is $temporary_file");
    }else{
	unlink ($temporary_file);
    }
    unlink ($temporary_keyfile);
    
    $message->{'msg'}->head->add('DKIM-signature',$dkim->signature->as_string);

    return $message->{'msg'}->head->as_string."\n".&Message::get_body_from_msg_as_string($msg_as_string);
}

1;
