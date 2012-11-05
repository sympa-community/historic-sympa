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

package Sympa::Tools::SMIME;

use strict;

use Exporter;
use MIME::Parser;

use Sympa::List;
use Sympa::Log;
use Sympa::Tools;

our @ISA = qw(Exporter);
our @EXPORT = qw(
    smime_sign
    smime_sign_check
    smime_encrypt
    smime_decrypt
    smime_find_keys
    smime_parse_cert
    smime_extract_certs
);

my %openssl_errors = (1 => 'an error occurred parsing the command options',
		      2 => 'one of the input files could not be read',
		      3 => 'an error occurred creating the PKCS#7 file or when reading the MIME message',
		      4 => 'an error occurred decrypting or verifying the message',
		      5 => 'the message was verified correctly but an error occurred writing out the signers certificates');

# input object msg and listname, output signed message object
sub smime_sign {
    my $in_msg = shift;
    my $list = shift;
    my $robot = shift;
    my $tmpdir = shift;
    my $key_passwd = shift;
    my $openssl = shift;

    &Sympa::Log::do_log('debug2', 'Tools::SMIME::smime_sign (%s,%s,%s,%s)',$in_msg,$list,$robot,$tmpdir);

    my $self = new Sympa::List($list, $robot);
    my($cert, $key) = &smime_find_keys($self->{dir}, 'sign');
    my $temporary_file = $tmpdir."/".$self->get_list_id().".".$$ ;    
    my $temporary_pwd = $tmpdir.'/pass.'.$$;

    my ($signed_msg,$pass_option );
    $pass_option = "-passin file:$temporary_pwd" if ($key_passwd ne '') ;

    ## Keep a set of header fields ONLY
    ## OpenSSL only needs content type & encoding to generate a multipart/signed msg
    my $dup_msg = $in_msg->dup;
    foreach my $field ($dup_msg->head->tags) {
         next if ($field =~ /^(content-type|content-transfer-encoding)$/i);
         $dup_msg->head->delete($field);
    }
	    

    ## dump the incomming message.
    if (!open(MSGDUMP,"> $temporary_file")) {
	&Sympa::Log::do_log('info', 'Can\'t store message in file %s', $temporary_file);
	return undef;
    }
    $dup_msg->print(\*MSGDUMP);
    close(MSGDUMP);

    if ($key_passwd ne '') {
	unless ( mkfifo($temporary_pwd,0600)) {
	    &Sympa::Log::do_log('notice', 'Unable to make fifo for %s',$temporary_pwd);
	}
    }
    &Sympa::Log::do_log('debug', "$openssl smime -sign -rand $tmpdir/rand -signer $cert $pass_option -inkey $key -in $temporary_file");    
    unless (open (NEWMSG, "$openssl smime -sign -rand $tmpdir/rand -signer $cert $pass_option -inkey $key -in $temporary_file |")) {
    	&Sympa::Log::do_log('notice', 'Cannot sign message (open pipe)');
	return undef;
    }

    if ($key_passwd ne '') {
	unless (open (FIFO,"> $temporary_pwd")) {
	    &Sympa::Log::do_log('notice', 'Unable to open fifo for %s', $temporary_pwd);
	}

	print FIFO $key_passwd;
	close FIFO;
	unlink ($temporary_pwd);
    }

    my $parser = new MIME::Parser;

    $parser->output_to_core(1);
    unless ($signed_msg = $parser->read(\*NEWMSG)) {
	&Sympa::Log::do_log('notice', 'Unable to parse message');
	return undef;
    }
    unless (close NEWMSG){
	&Sympa::Log::do_log('notice', 'Cannot sign message (close pipe)');
	return undef;
    } 

    my $status = $?/256 ;
    unless ($status == 0) {
	&Sympa::Log::do_log('notice', 'Unable to S/MIME sign message : status = %d', $status);
	return undef;	
    }

    unlink ($temporary_file) unless ($main::options{'debug'}) ;
    
    ## foreach header defined in  the incomming message but undefined in the
    ## crypted message, add this header in the crypted form.
    my $predefined_headers ;
    foreach my $header ($signed_msg->head->tags) {
	$predefined_headers->{lc $header} = 1
	    if ($signed_msg->head->get($header));
    }
    foreach my $header (split /\n(?![ \t])/, $in_msg->head->as_string) {
	next unless $header =~ /^([^\s:]+)\s*:\s*(.*)$/s;
	my ($tag, $val) = ($1, $2);
	$signed_msg->head->add($tag, $val)
	    unless $predefined_headers->{lc $tag};
    }
    
    my $messageasstring = $signed_msg->as_string ;

    return $signed_msg;
}


sub smime_sign_check {
    my $message = shift;
    my $tmpdir = shift;
    my $cafile = shift;
    my $capath = shift;
    my $openssl = shift;
    my $ssl_cert_dir = shift;

    my $sender = $message->{'sender'};

    &Sympa::Log::do_log('debug', 'Tools::SMIME::smime_sign_check (message, %s, %s)', $sender, $message->{'filename'});

    my $is_signed = {};
    $is_signed->{'body'} = undef;   
    $is_signed->{'subject'} = undef;

    my $verify ;

    ## first step is the msg signing OK ; /tmp/sympa-smime.$$ is created
    ## to store the signer certificat for step two. I known, that's durty.

    my $temporary_file = $tmpdir."/".'smime-sender.'.$$ ;
    my $trusted_ca_options = '';
    $trusted_ca_options = "-CAfile $cafile " if ($cafile);
    $trusted_ca_options .= "-CApath $capath " if ($capath);
    &Sympa::Log::do_log('debug', "$openssl smime -verify  $trusted_ca_options -signer  $temporary_file");

    unless (open (MSGDUMP, "| $openssl smime -verify  $trusted_ca_options -signer $temporary_file > /dev/null")) {

	&Sympa::Log::do_log('err', "unable to verify smime signature from $sender $verify");
	return undef ;
    }
    
    if ($message->{'smime_crypted'}){
	$message->{'msg'}->head->print(\*MSGDUMP);
	print MSGDUMP "\n";
	print MSGDUMP $message->{'msg_as_string'};
    }elsif (! $message->{'filename'}) {
	print MSGDUMP $message->{'msg_as_string'};
    }else{
	unless (open MSG, $message->{'filename'}) {
	    &Sympa::Log::do_log('err', 'Unable to open file %s: %s', $message->{'filename'}, $!);
	    return undef;

	}
	print MSGDUMP <MSG>;
	close MSG;
    }
    close MSGDUMP;

    my $status = $?/256 ;
    unless ($status == 0) {
	&Sympa::Log::do_log('err', 'Unable to check S/MIME signature : %s', $openssl_errors{$status});
	return undef ;
    }
    ## second step is the message signer match the sender
    ## a better analyse should be performed to extract the signer email. 
    my $signer = smime_parse_cert({tmpdir => $tmpdir, file => $temporary_file, openssl => $openssl});

    unless ($signer->{'email'}{lc($sender)}) {
	unlink($temporary_file) unless ($main::options{'debug'}) ;
	&Sympa::Log::do_log('err', "S/MIME signed message, sender(%s) does NOT match signer(%s)",$sender, join(',', keys %{$signer->{'email'}}));
	return undef;
    }

    &Sympa::Log::do_log('debug', "S/MIME signed message, signature checked and sender match signer(%s)", join(',', keys %{$signer->{'email'}}));
    ## store the signer certificat
    unless (-d $ssl_cert_dir) {
	if ( mkdir ($ssl_cert_dir, 0775)) {
	    &Sympa::Log::do_log('info', "creating spool $ssl_cert_dir");
	}else{
	    &Sympa::Log::do_log('err', "Unable to create user certificat directory $ssl_cert_dir");
	}
    }

    ## It gets a bit complicated now. openssl smime -signer only puts
    ## the _signing_ certificate into the given file; to get all included
    ## certs, we need to extract them from the signature proper, and then
    ## we need to check if they are for our user (CA and intermediate certs
    ## are also included), and look at the purpose:
    ## "S/MIME signing : Yes/No"
    ## "S/MIME encryption : Yes/No"
    my $certbundle = "$tmpdir/certbundle.$$";
    my $tmpcert = "$tmpdir/cert.$$";
    my $nparts = $message->{msg}->parts;
    my $extracted = 0;
    &Sympa::Log::do_log('debug2', "smime_sign_check: parsing $nparts parts");
    if($nparts == 0) { # could be opaque signing...
	$extracted +=&smime_extract_certs($message->{msg}, $certbundle, $openssl);
    } else {
	for (my $i = 0; $i < $nparts; $i++) {
	    my $part = $message->{msg}->parts($i);
	    $extracted += &smime_extract_certs($part, $certbundle, $openssl);
	    last if $extracted;
	}
    }
    
    unless($extracted) {
	&Sympa::Log::do_log('err', "No application/x-pkcs7-* parts found");
	return undef;
    }

    unless(open(BUNDLE, $certbundle)) {
	&Sympa::Log::do_log('err', "Can't open cert bundle $certbundle: $!");
	return undef;
    }
    
    ## read it in, split on "-----END CERTIFICATE-----"
    my $cert = '';
    my(%certs);
    while(<BUNDLE>) {
	$cert .= $_;
	if(/^-----END CERTIFICATE-----$/) {
	    my $workcert = $cert;
	    $cert = '';
	    unless(open(CERT, ">$tmpcert")) {
		&Sympa::Log::do_log('err', "Can't create $tmpcert: $!");
		return undef;
	    }
	    print CERT $workcert;
	    close(CERT);
	    my($parsed) = &smime_parse_cert({tmpdir => $tmpdir, file => $tmpcert, openssl => $openssl});
	    unless($parsed) {
		&Sympa::Log::do_log('err', 'No result from smime_parse_cert');
		return undef;
	    }
	    unless($parsed->{'email'}) {
		&Sympa::Log::do_log('debug', "No email in cert for $parsed->{subject}, skipping");
		next;
	    }
	    
	    &Sympa::Log::do_log('debug2', "Found cert for <%s>", join(',', keys %{$parsed->{'email'}}));
	    if ($parsed->{'email'}{lc($sender)}) {
		if ($parsed->{'purpose'}{'sign'} && $parsed->{'purpose'}{'enc'}) {
		    $certs{'both'} = $workcert;
		    &Sympa::Log::do_log('debug', 'Found a signing + encryption cert');
		}elsif ($parsed->{'purpose'}{'sign'}) {
		    $certs{'sign'} = $workcert;
		    &Sympa::Log::do_log('debug', 'Found a signing cert');
		} elsif($parsed->{'purpose'}{'enc'}) {
		    $certs{'enc'} = $workcert;
		    &Sympa::Log::do_log('debug', 'Found an encryption cert');
		}
	    }
	    last if(($certs{'both'}) || ($certs{'sign'} && $certs{'enc'}));
	}
    }
    close(BUNDLE);
    if(!($certs{both} || ($certs{sign} || $certs{enc}))) {
	&Sympa::Log::do_log('err', "Could not extract certificate for %s", join(',', keys %{$signer->{'email'}}));
	return undef;
    }
    ## OK, now we have the certs, either a combined sign+encryption one
    ## or a pair of single-purpose. save them, as email@addr if combined,
    ## or as email@addr@sign / email@addr@enc for split certs.
    foreach my $c (keys %certs) {
	my $fn = "$ssl_cert_dir/" . &escape_chars(lc($sender));
	if ($c ne 'both') {
	    unlink($fn); # just in case there's an old cert left...
	    $fn .= "\@$c";
	}else {
	    unlink("$fn\@enc");
	    unlink("$fn\@sign");
	}
	&Sympa::Log::do_log('debug', "Saving $c cert in $fn");
	unless (open(CERT, ">$fn")) {
	    &Sympa::Log::do_log('err', "Unable to create certificate file $fn: $!");
	    return undef;
	}
	print CERT $certs{$c};
	close(CERT);
    }

    unless ($main::options{'debug'}) {
	unlink($temporary_file);
	unlink($tmpcert);
	unlink($certbundle);
    }

    $is_signed->{'body'} = 'smime';
    
    # futur version should check if the subject was part of the SMIME signature.
    $is_signed->{'subject'} = $signer;
    return $is_signed;
}

# input : msg object, return a new message object encrypted
sub smime_encrypt {
    my $msg_header = shift;
    my $msg_body = shift;
    my $email = shift ;
    my $list = shift ;
    my $tmpdir = shift ;
    my $ssl_cert_dir = shift ;
    my $openssl = shift ;

    my $usercert;
    my $dummy;
    my $cryptedmsg;
    my $encrypted_body;    

    &Sympa::Log::do_log('debug2', 'Tools::SMIME::smime_encrypt( %s, %s', $email, $list);
    if ($list eq 'list') {
	my $self = new Sympa::List($email);
	($usercert, $dummy) = smime_find_keys($self->{dir}, 'encrypt');
    }else{
	my $base = "$ssl_cert_dir/".&Sympa::Tools::escape_chars($email);
	if(-f "$base\@enc") {
	    $usercert = "$base\@enc";
	} else {
	    $usercert = "$base";
	}
    }
    if (-r $usercert) {
	my $temporary_file = $tmpdir."/".$email.".".$$ ;

	## encrypt the incomming message parse it.
        &Sympa::Log::do_log ('debug3', "Tools::SMIME::smime_encrypt : $openssl smime -encrypt -out $temporary_file -des3 $usercert");

	if (!open(MSGDUMP, "| $openssl smime -encrypt -out $temporary_file -des3 $usercert")) {
	    &Sympa::Log::do_log('info', 'Can\'t encrypt message for recipient %s', $email);
	}
## don't; cf RFC2633 3.1. netscape 4.7 at least can't parse encrypted stuff
## that contains a whole header again... since MIME::Tools has got no function
## for this, we need to manually extract only the MIME headers...
##	$msg_header->print(\*MSGDUMP);
##	printf MSGDUMP "\n%s", $msg_body;
	my $mime_hdr = $msg_header->dup();
	foreach my $t ($mime_hdr->tags()) {
	  $mime_hdr->delete($t) unless ($t =~ /^(mime|content)-/i);
	}
	$mime_hdr->print(\*MSGDUMP);

	printf MSGDUMP "\n%s", $msg_body;
	close(MSGDUMP);

	my $status = $?/256 ;
	unless ($status == 0) {
	    &Sympa::Log::do_log('err', 'Unable to S/MIME encrypt message : %s', $openssl_errors{$status});
	    return undef ;
	}

        ## Get as MIME object
	open (NEWMSG, $temporary_file);
	my $parser = new MIME::Parser;
	$parser->output_to_core(1);
	unless ($cryptedmsg = $parser->read(\*NEWMSG)) {
	    &Sympa::Log::do_log('notice', 'Unable to parse message');
	    return undef;
	}
	close NEWMSG ;

        ## Get body
	open (NEWMSG, $temporary_file);
        my $in_header = 1 ;
	while (<NEWMSG>) {
	   if ( !$in_header)  { 
	     $encrypted_body .= $_;       
	   }else {
	     $in_header = 0 if (/^$/); 
	   }
	}						    
	close NEWMSG;

unlink ($temporary_file) unless ($main::options{'debug'}) ;

	## foreach header defined in  the incomming message but undefined in the
        ## crypted message, add this header in the crypted form.
	my $predefined_headers ;
	foreach my $header ($cryptedmsg->head->tags) {
	    $predefined_headers->{lc $header} = 1 
	        if ($cryptedmsg->head->get($header)) ;
	}
	foreach my $header (split /\n(?![ \t])/, $msg_header->as_string) {
	    next unless $header =~ /^([^\s:]+)\s*:\s*(.*)$/s;
	    my ($tag, $val) = ($1, $2);
	    $cryptedmsg->head->add($tag, $val) 
	        unless $predefined_headers->{lc $tag};
	}

    }else{
	&Sympa::Log::do_log ('notice','unable to encrypt message to %s (missing certificat %s)',$email,$usercert);
	return undef;
    }
        
    return $cryptedmsg->head->as_string . "\n" . $encrypted_body;
}

# input : msg object for a list, return a new message object decrypted
sub smime_decrypt {
    my $msg = shift;
    my $list = shift ; ## the recipient of the msg
    my $tmpdir = shift;
    my $home = shift;
    my $key_passwd = shift;
    my $openssl = shift;
    my $from = $msg->head->get('from');

    &Sympa::Log::do_log('debug2', 'Tools::SMIME::smime_decrypt message msg from %s,%s', $from, $list->{'name'});

    ## an empty "list" parameter means mail to sympa@, listmaster@...
    my $dir = $list->{'dir'};
    unless ($dir) {
	$dir = $home . '/sympa';
    }
    my ($certs,$keys) = smime_find_keys($dir, 'decrypt');
    unless (defined $certs && @$certs) {
	&Sympa::Log::do_log('err', "Unable to decrypt message : missing certificate file");
	return undef;
    }

    my $temporary_file = $tmpdir."/".$list->get_list_id().".".$$ ;
    my $temporary_pwd = $tmpdir.'/pass.'.$$;

    ## dump the incomming message.
    if (!open(MSGDUMP,"> $temporary_file")) {
	&Sympa::Log::do_log('info', 'Can\'t store message in file %s',$temporary_file);
    }
    $msg->print(\*MSGDUMP);
    close(MSGDUMP);
    
    my ($decryptedmsg, $pass_option, $msg_as_string);
    if ($key_passwd ne '') {
	# if password is define in sympa.conf pass the password to OpenSSL using
	$pass_option = "-passin file:$temporary_pwd";	
    }

    ## try all keys/certs until one decrypts.
    while (my $certfile = shift @$certs) {
	my $keyfile = shift @$keys;
	&Sympa::Log::do_log('debug', "Trying decrypt with $certfile, $keyfile");
	if ($key_passwd ne '') {
	    unless (mkfifo($temporary_pwd,0600)) {
		&Sympa::Log::do_log('err', 'Unable to make fifo for %s', $temporary_pwd);
		return undef;
	    }
	}

	&Sympa::Log::do_log('debug',"$openssl smime -decrypt -in $temporary_file -recip $certfile -inkey $keyfile $pass_option");
	open (NEWMSG, "$openssl smime -decrypt -in $temporary_file -recip $certfile -inkey $keyfile $pass_option |");

	if ($key_passwd ne '') {
	    unless (open (FIFO,"> $temporary_pwd")) {
		&Sympa::Log::do_log('notice', 'Unable to open fifo for %s', $temporary_pwd);
		return undef;
	    }
	    print FIFO $key_passwd;
	    close FIFO;
	    unlink ($temporary_pwd);
	}
	
	while (<NEWMSG>) {
	    $msg_as_string .= $_;
	}
	close NEWMSG ;
	my $status = $?/256;
	
	unless ($status == 0) {
	    &Sympa::Log::do_log('notice', 'Unable to decrypt S/MIME message : %s', $openssl_errors{$status});
	    next;
	}
	
	unlink ($temporary_file) unless ($main::options{'debug'}) ;
	
	my $parser = new MIME::Parser;
	$parser->output_to_core(1);
	unless ($decryptedmsg = $parser->parse_data($msg_as_string)) {
	    &Sympa::Log::do_log('notice', 'Unable to parse message');
	    last;
	}
    }
	
    unless (defined $decryptedmsg) {
      &Sympa::Log::do_log('err', 'Message could not be decrypted');
      return undef;
    }

    ## Now remove headers from $msg_as_string
    my @msg_tab = split(/\n/, $msg_as_string);
    my $line;
    do {$line = shift(@msg_tab)} while ($line !~ /^\s*$/);
    $msg_as_string = join("\n", @msg_tab);
    
    ## foreach header defined in the incomming message but undefined in the
    ## decrypted message, add this header in the decrypted form.
    my $predefined_headers ;
    foreach my $header ($decryptedmsg->head->tags) {
	$predefined_headers->{lc $header} = 1
	    if ($decryptedmsg->head->get($header));
    }
    foreach my $header (split /\n(?![ \t])/, $msg->head->as_string) {
	next unless $header =~ /^([^\s:]+)\s*:\s*(.*)$/s;
	my ($tag, $val) = ($1, $2);
	$decryptedmsg->head->add($tag, $val)
	    unless $predefined_headers->{lc $tag};
    }
    ## Some headers from the initial message should not be restored
    ## Content-Disposition and Content-Transfer-Encoding if the result is multipart
    $decryptedmsg->head->delete('Content-Disposition') if ($msg->head->get('Content-Disposition'));
    if ($decryptedmsg->head->get('Content-Type') =~ /multipart/) {
	$decryptedmsg->head->delete('Content-Transfer-Encoding') if ($msg->head->get('Content-Transfer-Encoding'));
    }

    return ($decryptedmsg, \$msg_as_string);
}

## find the appropriate S/MIME keys/certs for $oper in $dir.
## $oper can be:
## 'sign' -> return the preferred signing key/cert
## 'decrypt' -> return a list of possible decryption keys/certs
## 'encrypt' -> return the preferred encryption key/cert
## returns ($certs, $keys)
## for 'sign' and 'encrypt', these are strings containing the absolute filename
## for 'decrypt', these are arrayrefs containing absolute filenames
sub smime_find_keys {
    my($dir, $oper) = @_;
    &Sympa::Log::do_log('debug', 'Tools::SMIME::smime_find_keys(%s, %s)', $dir, $oper);

    my(%certs, %keys);
    my $ext = ($oper eq 'sign' ? 'sign' : 'enc');

    unless (opendir(D, $dir)) {
	&Sympa::Log::do_log('err', "unable to opendir $dir: $!");
	return undef;
    }

    while (my $fn = readdir(D)) {
	if ($fn =~ /^cert\.pem/) {
	    $certs{"$dir/$fn"} = 1;
	}elsif ($fn =~ /^private_key/) {
	    $keys{"$dir/$fn"} = 1;
	}
    }
    closedir(D);

    foreach my $c (keys %certs) {
	my $k = $c;
	$k =~ s/\/cert\.pem/\/private_key/;
	unless ($keys{$k}) {
	    &Sympa::Log::do_log('notice', "$c exists, but matching $k doesn't");
	    delete $certs{$c};
	}
    }

    foreach my $k (keys %keys) {
	my $c = $k;
	$c =~ s/\/private_key/\/cert\.pem/;
	unless ($certs{$c}) {
	    &Sympa::Log::do_log('notice', "$k exists, but matching $c doesn't");
	    delete $keys{$k};
	}
    }

    my ($certs, $keys);
    if ($oper eq 'decrypt') {
	$certs = [ sort keys %certs ];
	$keys = [ sort keys %keys ];
    }else {
	if($certs{"$dir/cert.pem.$ext"}) {
	    $certs = "$dir/cert.pem.$ext";
	    $keys = "$dir/private_key.$ext";
	} elsif($certs{"$dir/cert.pem"}) {
	    $certs = "$dir/cert.pem";
	    $keys = "$dir/private_key";
	} else {
	    &Sympa::Log::do_log('info', "$dir: no certs/keys found for $oper");
	    return undef;
	}
    }

    return ($certs,$keys);
}

# IN: hashref:
# file => filename
# text => PEM-encoded cert
# OUT: hashref
# email => email address from cert
# subject => distinguished name
# purpose => hashref
#  enc => true if v3 purpose is encryption
#  sign => true if v3 purpose is signing
sub smime_parse_cert {
    my($arg) = @_;
    &Sympa::Log::do_log('debug', 'Tools::SMIME::smime_parse_cert(%s)', join('/',%{$arg}));

    unless (ref($arg)) {
	&Sympa::Log::do_log('err', "smime_parse_cert: must be called with hashref, not %s", ref($arg));
	return undef;
    }

    ## Load certificate
    my @cert;
    if($arg->{'text'}) {
	@cert = ($arg->{'text'});
    }elsif ($arg->{file}) {
	unless (open(PSC, "$arg->{file}")) {
	    &Sympa::Log::do_log('err', "smime_parse_cert: open %s: $!", $arg->{file});
	    return undef;
	}
	@cert = <PSC>;
	close(PSC);
    }else {
	&Sympa::Log::do_log('err', 'smime_parse_cert: neither "text" nor "file" given');
	return undef;
    }

    ## Extract information from cert
    my ($tmpfile) = $arg->{tmpdir}."/parse_cert.$$";
    unless (open(PSC, "| $arg->{openssl} x509 -email -subject -purpose -noout > $tmpfile")) {
	&Sympa::Log::do_log('err', "smime_parse_cert: open |openssl: $!");
	return undef;
    }
    print PSC join('', @cert);

    unless (close(PSC)) {
	&Sympa::Log::do_log('err', "smime_parse_cert: close openssl: $!, $@");
	return undef;
    }

    unless (open(PSC, "$tmpfile")) {
	&Sympa::Log::do_log('err', "smime_parse_cert: open $tmpfile: $!");
	return undef;
    }

    my (%res, $purpose_section);

    while (<PSC>) {
      ## First lines before subject are the email address(es)

      if (/^subject=\s+(\S.+)\s*$/) {
	$res{'subject'} = $1;

      }elsif (! $res{'subject'} && /\@/) {
	my $email_address = lc($_);
	chomp $email_address;
	$res{'email'}{$email_address} = 1;

	  ## Purpose section appears at the end of the output
	  ## because options order matters for openssl
      }elsif (/^Certificate purposes:/) {
		  $purpose_section = 1;
	  }elsif ($purpose_section) {
		if (/^S\/MIME signing : (\S+)/) {
			$res{purpose}->{sign} = ($1 eq 'Yes');
	  
		}elsif (/^S\/MIME encryption : (\S+)/) {
			$res{purpose}->{enc} = ($1 eq 'Yes');
		}
      }
    }
    
    ## OK, so there's CAs which put the email in the subjectAlternateName only
    ## and ones that put it in the DN only...
    if(!$res{email} && ($res{subject} =~ /\/email(address)?=([^\/]+)/)) {
	$res{email} = $1;
    }
    close(PSC);
    unlink($tmpfile);
    return \%res;
}

sub smime_extract_certs {
    my($mime, $outfile, $openssl) = @_;
    &Sympa::Log::do_log('debug2', "Tools::SMIME::smime_extract_certs(%s)",$mime->mime_type);

    if ($mime->mime_type =~ /application\/(x-)?pkcs7-/) {
	unless (open(MSGDUMP, "| $openssl pkcs7 -print_certs ".
		     "-inform der > $outfile")) {
	    &Sympa::Log::do_log('err', "unable to run openssl pkcs7: $!");
	    return 0;
	}
	print MSGDUMP $mime->bodyhandle->as_string;
	close(MSGDUMP);
	if ($?) {
	    &Sympa::Log::do_log('err', "openssl pkcs7 returned an error: ", $?/256);
	    return 0;
	}
	return 1;
    }
}
1;
