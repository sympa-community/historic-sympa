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

Sympa::Tools::SMIME - SMIME-related functions

=head1 DESCRIPTION

This module provides various functions for managing SMIME messages.

=cut

package Sympa::Tools::SMIME;

use strict;

use English qw(-no_match_vars);
use File::Temp;
use MIME::Parser;
use POSIX qw();

use Sympa::Log;
use Sympa::Tools;

my %openssl_errors = (1 => 'an error occurred parsing the command options',
		      2 => 'one of the input files could not be read',
		      3 => 'an error occurred creating the PKCS#7 file or when reading the MIME message',
		      4 => 'an error occurred decrypting or verifying the message',
		      5 => 'the message was verified correctly but an error occurred writing out the signers certificates');

=head1 FUNCTIONS

=head2 sign_message(%parameters)

Sign a message.

=head3 Parameters

=over

=item * I<entity>:

=item * I<certdir>:

=item * I<key_passwd>:

=item * I<openssl>: path to openssl binary

=back

=cut

sub sign_message {
    my (%params) = @_;

    Sympa::Log::do_log('debug2', '(%s)', join('/',%params));

    my($cert, $key) = smime_find_keys($params{certdir}, 'sign');

    my $signed_msg;

    ## Keep a set of header fields ONLY
    ## OpenSSL only needs content type & encoding to generate a multipart/signed msg
    my $dup_msg = $params{entity}->dup();
    foreach my $field ($dup_msg->head()->tags()) {
         next if ($field =~ /^(content-type|content-transfer-encoding)$/i);
         $dup_msg->head->delete($field);
    }


    ## dump the incomming message.
    my $unsigned_message_file = File::Temp->new(
	    CLEANUP => $main::options{'debug'} ? 0 : 1
    );
    $dup_msg->print($unsigned_message_file);
    close($unsigned_message_file);

    my $password_file;
    if ($params{key_passwd}) {
	my $umask = umask;
	umask 0077;
	$password_file = File::Temp->new(
		CLEANUP => $main::options{'debug'} ? 0 : 1
	);

	print $password_file $params{key_passwd};
	close $password_file;
	umask $umask;
    }

    my $command =
	    "$params{openssl} smime -sign " .
	    "-signer $cert -inkey $key -in $unsigned_message_file" .
	    ($password_file ? " -passin file:$password_file" : "" );
    Sympa::Log::do_log('debug', $command);
    unless (open (NEWMSG, "$command |")) {
    	Sympa::Log::do_log('notice', 'Cannot sign message (open pipe)');
	return undef;
    }

    my $parser = MIME::Parser->new();

    $parser->output_to_core(1);
    unless ($signed_msg = $parser->read(\*NEWMSG)) {
	Sympa::Log::do_log('notice', 'Unable to parse message');
	return undef;
    }
    unless (close NEWMSG){
	Sympa::Log::do_log('notice', 'Cannot sign message (close pipe)');
	return undef;
    }

    my $status = $CHILD_ERROR/256 ;
    unless ($status == 0) {
	Sympa::Log::do_log('notice', 'Unable to S/MIME sign message : status = %d', $status);
	return undef;
    }

    ## foreach header defined in  the incomming message but undefined in the
    ## crypted message, add this header in the crypted form.
    my $predefined_headers ;
    foreach my $header ($signed_msg->head()->tags()) {
	$predefined_headers->{lc $header} = 1
	    if ($signed_msg->head()->get($header));
    }
    foreach my $header (split /\n(?![ \t])/,
	    $params{entity}->head()->as_string()) {
	next unless $header =~ /^([^\s:]+)\s*:\s*(.*)$/s;
	my ($tag, $val) = ($1, $2);
	$signed_msg->head->add($tag, $val)
	    unless $predefined_headers->{lc $tag};
    }

    return $signed_msg;
}

=head2 check_signature(%parameters)

Check if a message is signed, and store the sender certificates in certificate storage directory.

=head3 Parameters

=over

=item * I<message>:

=item * I<cafile>:

=item * I<capath>:

=item * I<openssl>: path to openssl binary

=item * I<ssl_cert_dir>:

=back

=head3 Return value

A data structure corresponding to the signer certificate on success, I<undef> otherwise.

=cut

sub check_signature {
    my (%params) = @_;

    my $message = $params{message};

    Sympa::Log::do_log('debug', '(message, %s, %s)', $message->{sender}, $message->{'filename'});

    # extract the signer certificate in a file
    my $signer_cert_file = File::Temp->new(
	    CLEANUP => $main::options{'debug'} ? 0 : 1
    );
    my $command = 
	    "$params{openssl} smime -verify -signer $signer_cert_file " .
	    ($params{cafile} ? "-CAfile $params{cafile}" : '')          .
	    ($params{capath} ? "-CApath $params{capath}" : '')          .
	    ">/dev/null 2>&1";
    Sympa::Log::do_log('debug', $command);

    my $command_handle;
    unless (open ($command_handle, '|-', $command)) {

	Sympa::Log::do_log('err', "unable to verify smime signature from $message->{sender}");
	return undef ;
    }

    if ($message->{'smime_crypted'}){
	$message->{'msg'}->head->print($command_handle);
	print $command_handle "\n";
    }
    print $command_handle $message->{'msg_as_string'};
    close $command_handle;

    my $status = $CHILD_ERROR/256 ;
    unless ($status == 0) {
	Sympa::Log::do_log('err', 'Unable to check S/MIME signature : %s', $openssl_errors{$status});
	return undef ;
    }

    # check if the certificate matches the sender
    # a better analyse should be performed to extract the signer email.
    my $signer_cert = _parse_cert(
	    file    => $signer_cert_file,
	    openssl => $params{openssl}
    );

    unless ($signer_cert->{'email'}{lc($message->{sender})}) {
	Sympa::Log::do_log('err', "S/MIME signed message, sender(%s) does NOT match signer(%s)",$message->{sender}, join(',', keys %{$signer_cert->{'email'}}));
	return undef;
    }

    Sympa::Log::do_log('debug', "S/MIME signed message, signature checked and sender match signer(%s)", join(',', keys %{$signer_cert->{'email'}}));

    # openssl smime -signer only extract the signature certificate
    # In order to also retrieve encryption certificate, if distinct,
    # we need to extract to extract and analyse certificates manually
    my $certs_bundle_file = File::Temp->new(
	    CLEANUP => $main::options{'debug'} ? 0 : 1
    );
    my $nparts = $message->{msg}->parts;
    my $extracted = 0;
    Sympa::Log::do_log('debug2', "smime_sign_check: parsing $nparts parts");
    if($nparts == 0) { # could be opaque signing...
	$extracted += _extract_certs(
		entity  => $message->{msg},
		file    => $certs_bundle_file,
		openssl => $params{openssl}
	);
    } else {
	for (my $i = 0; $i < $nparts; $i++) {
	    my $part = $message->{msg}->parts($i);
	    $extracted += _extract_certs(
		    entity  => $part,
		    file    => $certs_bundle_file,
		    openssl => $params{openssl}
	    );
	    last if $extracted;
	}
    }

    unless($extracted) {
	Sympa::Log::do_log('err', "No application/x-pkcs7-* parts found");
	return undef;
    }

    my $bundle_handle;
    unless(open($bundle_handle, '<', $certs_bundle_file)) {
	Sympa::Log::do_log('err', "Can't open cert bundle $certs_bundle_file: $ERRNO");
	return undef;
    }

    ## read it in, split on "-----END CERTIFICATE-----"
    my $cert_string = '';
    my %certs;
    while (my $line = <$bundle_handle>) {
	$cert_string .= $line;

	next unless $line =~ /^-----END CERTIFICATE-----$/;

	my $cert = _parse_cert(
		text    => $cert_string,
		openssl => $params{openssl}
	);
	unless($cert) {
		Sympa::Log::do_log('err', 'No result from _parse_cert');
		return undef;
	}
	unless($cert->{'email'}) {
		Sympa::Log::do_log('debug', "No email in cert for $cert->{subject}, skipping");
		next;
	}

	Sympa::Log::do_log('debug2', "Found cert for <%s>", join(',', keys
			%{$cert->{'email'}}));
	if ($cert->{'email'}{lc($message->{sender})}) {
		if ($cert->{'purpose'}{'sign'} && $cert->{'purpose'}{'enc'}) {
		 $certs{'both'} = $cert_string;
		    Sympa::Log::do_log('debug', 'Found a signing + encryption cert');
		}elsif ($cert->{'purpose'}{'sign'}) {
		    $certs{'sign'} = $cert_string;
		    Sympa::Log::do_log('debug', 'Found a signing cert');
		} elsif($cert->{'purpose'}{'enc'}) {
		    $certs{'enc'} = $cert_string;
		    Sympa::Log::do_log('debug', 'Found an encryption cert');
		}
	}

	last if(($certs{'both'}) || ($certs{'sign'} && $certs{'enc'}));
	$cert_string = '';
    }
    close($bundle_handle);

    if(!($certs{both} || ($certs{sign} || $certs{enc}))) {
	Sympa::Log::do_log('err', "Could not extract certificate for %s", join(',', keys %{$signer_cert->{'email'}}));
	return undef;
    }

    # create certificate storage directory if needed
    unless (-d $params{cert_dir}) {
	if ( mkdir ($params{cert_dir}, 0775)) {
	    Sympa::Log::do_log('info', "creating spool $params{cert_dir}");
	}else{
	    Sympa::Log::do_log('err', "Unable to create user certificat directory $params{cert_dir}");
	}
    }


    # store all extracted certs in certificate storage directory,
    # in a single file for dual-purpose certificates,
    # or as distinct files for single-purpose certificates
    foreach my $category (keys %certs) {
	my $cert_file = 
		"$params{cert_dir}/" .
		Sympa::Tools::escape_chars(lc($message->{sender}));
	if ($category ne 'both') {
	    unlink($cert_file); # just in case there's an old cert left...
	    $cert_file .= "\@$category";
	}else {
	    unlink("$cert_file\@enc");
	    unlink("$cert_file\@sign");
	}
	Sympa::Log::do_log('debug', "Saving $category cert in $cert_file");
	my $cert_handle;
	unless (open($cert_handle, '>', $cert_file)) {
	    Sympa::Log::do_log('err', "Unable to create certificate file $cert_file: $ERRNO");
	    return undef;
	}
	print $cert_handle $certs{$category};
	close($cert_handle);
    }

    # futur version should check if the subject was part of the SMIME signature.
    
    return {
	    body    => 'smime',
	    subject => $signer_cert
    };
}

=head2 encrypt_message(%parameters)

Encrypt a message.

=head3 Parameters

=over

=item * I<header>:

=item * I<body>:

=item * I<email>:

=item * I<tmpdir>: temporary directory

=item * I<ssl_cert_dir>:

=item * I<openssl>: path to openssl binary

=back

=cut

sub encrypt_message {
    my (%params) = @_;

    Sympa::Log::do_log('debug2', '(%s)', join('/',%params));

    my $usercert;
    my $dummy;
    my $cryptedmsg;
    my $encrypted_body;

    my $base = "$params{ssl_cert_dir}/".Sympa::Tools::escape_chars($params{email});
    if(-f "$base\@enc") {
	$usercert = "$base\@enc";
    } else {
	$usercert = "$base";
    }

    if (-r $usercert) {
	my $temporary_file = $params{tmpdir}."/".$params{email}.".".$PID ;

	## encrypt the incomming message parse it.
        Sympa::Log::do_log ('debug3', "$params{openssl} smime -encrypt -out $temporary_file -des3 $usercert");

	if (!open(MSGDUMP, "| $params{openssl} smime -encrypt -out $temporary_file -des3 $usercert")) {
	    Sympa::Log::do_log('info', 'Can\'t encrypt message for recipient %s', $params{email});
	}
## don't; cf RFC2633 3.1. netscape 4.7 at least can't parse encrypted stuff
## that contains a whole header again... since MIME::Tools has got no function
## for this, we need to manually extract only the MIME headers...
##	$msg_header->print(\*MSGDUMP);
##	printf MSGDUMP "\n%s", $msg_body;
	my $mime_hdr = $params{header}->dup();
	foreach my $t ($mime_hdr->tags()) {
	  $mime_hdr->delete($t) unless ($t =~ /^(mime|content)-/i);
	}
	$mime_hdr->print(\*MSGDUMP);

	printf MSGDUMP "\n%s", $params{body};
	close(MSGDUMP);

	my $status = $CHILD_ERROR/256 ;
	unless ($status == 0) {
	    Sympa::Log::do_log('err', 'Unable to S/MIME encrypt message : %s', $openssl_errors{$status});
	    return undef ;
	}

        ## Get as MIME object
	open (NEWMSG, $temporary_file);
	my $parser = MIME::Parser->new;
	$parser->output_to_core(1);
	unless ($cryptedmsg = $parser->read(\*NEWMSG)) {
	    Sympa::Log::do_log('notice', 'Unable to parse message');
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
	foreach my $header (split /\n(?![ \t])/, $params{header}->as_string) {
	    next unless $header =~ /^([^\s:]+)\s*:\s*(.*)$/s;
	    my ($tag, $val) = ($1, $2);
	    $cryptedmsg->head->add($tag, $val)
	        unless $predefined_headers->{lc $tag};
	}

    }else{
	Sympa::Log::do_log ('notice','unable to encrypt message to %s (missing certificat %s)',$params{email},$usercert);
	return undef;
    }

    return $cryptedmsg->head->as_string . "\n" . $encrypted_body;
}

=head2 decrypt_message(%parameters)

Decrypt a message.

=head3 Parameters

=over

=item * I<message>:

=item * I<listid>:

=item * I<certdir>:

=item * I<tmpdir>: temporary directory

=item * I<key_passwd>:

=item * I<openssl>: path to openssl binary

=back

=head3 Return value

=cut

sub decrypt_message {
    my (%params) = @_;

    Sympa::Log::do_log('debug2', '(%s)', join('/',%params));

    my ($certs,$keys) = smime_find_keys($params{certdir}, 'decrypt');
    unless (defined $certs && @$certs) {
	Sympa::Log::do_log('err', "Unable to decrypt message : missing certificate file");
	return undef;
    }

    my $temporary_file = $params{tmpdir}."/".$params{listid}.".".$PID ;
    my $temporary_pwd = $params{tmpdir}.'/pass.'.$PID;

    ## dump the incomming message.
    if (!open(MSGDUMP,"> $temporary_file")) {
	Sympa::Log::do_log('info', 'Can\'t store message in file %s',$temporary_file);
    }
    $params{message}->print(\*MSGDUMP);
    close(MSGDUMP);

    my ($decryptedmsg, $pass_option, $msg_as_string);
    if ($params{key_passwd} ne '') {
	# if password is define in sympa.conf pass the password to OpenSSL using
	$pass_option = "-passin file:$temporary_pwd";
    }

    ## try all keys/certs until one decrypts.
    while (my $certfile = shift @$certs) {
	my $keyfile = shift @$keys;
	Sympa::Log::do_log('debug', "Trying decrypt with $certfile, $keyfile");
	if ($params{key_passwd} ne '') {
	    unless (POSIX::mkfifo($temporary_pwd,0600)) {
		Sympa::Log::do_log('err', 'Unable to make fifo for %s', $temporary_pwd);
		return undef;
	    }
	}

	Sympa::Log::do_log('debug',"$params{openssl} smime -decrypt -in $temporary_file -recip $certfile -inkey $keyfile $pass_option");
	open (NEWMSG, "$params{openssl} smime -decrypt -in $temporary_file -recip $certfile -inkey $keyfile $pass_option |");

	if ($params{key_passwd} ne '') {
	    unless (open (FIFO,"> $temporary_pwd")) {
		Sympa::Log::do_log('notice', 'Unable to open fifo for %s', $temporary_pwd);
		return undef;
	    }
	    print FIFO $params{key_passwd};
	    close FIFO;
	    unlink ($temporary_pwd);
	}

	while (<NEWMSG>) {
	    $msg_as_string .= $_;
	}
	close NEWMSG ;
	my $status = $CHILD_ERROR/256;

	unless ($status == 0) {
	    Sympa::Log::do_log('notice', 'Unable to decrypt S/MIME message : %s', $openssl_errors{$status});
	    next;
	}

	unlink ($temporary_file) unless ($main::options{'debug'}) ;

	my $parser = MIME::Parser->new;
	$parser->output_to_core(1);
	unless ($decryptedmsg = $parser->parse_data($msg_as_string)) {
	    Sympa::Log::do_log('notice', 'Unable to parse message');
	    last;
	}
    }

    unless (defined $decryptedmsg) {
      Sympa::Log::do_log('err', 'Message could not be decrypted');
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
    foreach my $header (split /\n(?![ \t])/, $params{message}->head->as_string) {
	next unless $header =~ /^([^\s:]+)\s*:\s*(.*)$/s;
	my ($tag, $val) = ($1, $2);
	$decryptedmsg->head->add($tag, $val)
	    unless $predefined_headers->{lc $tag};
    }
    ## Some headers from the initial message should not be restored
    ## Content-Disposition and Content-Transfer-Encoding if the result is multipart
    $decryptedmsg->head->delete('Content-Disposition') if ($params{message}->head->get('Content-Disposition'));
    if ($decryptedmsg->head->get('Content-Type') =~ /multipart/) {
	$decryptedmsg->head->delete('Content-Transfer-Encoding') if ($params{message}->head->get('Content-Transfer-Encoding'));
    }

    return ($decryptedmsg, \$msg_as_string);
}

=head2 smime_find_keys($dir, $oper)

find the appropriate S/MIME keys/certs for $oper in $dir.

$oper can be:

=over

=item sign

Return the preferred signing key/cert

=item decrypt

return a list of possible decryption keys/certs

=item encrypt

return the preferred encryption key/cert

=back

returns ($certs, $keys)
for 'sign' and 'encrypt', these are strings containing the absolute filename
for 'decrypt', these are arrayrefs containing absolute filenames

=cut

sub smime_find_keys {
    my($dir, $oper) = @_;
    Sympa::Log::do_log('debug', '(%s, %s)', $dir, $oper);

    my(%certs, %keys);
    my $ext = ($oper eq 'sign' ? 'sign' : 'enc');

    unless (opendir(D, $dir)) {
	Sympa::Log::do_log('err', "unable to opendir $dir: $ERRNO");
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
	    Sympa::Log::do_log('notice', "$c exists, but matching $k doesn't");
	    delete $certs{$c};
	}
    }

    foreach my $k (keys %keys) {
	my $c = $k;
	$c =~ s/\/private_key/\/cert\.pem/;
	unless ($certs{$c}) {
	    Sympa::Log::do_log('notice', "$k exists, but matching $c doesn't");
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
	    Sympa::Log::do_log('info', "$dir: no certs/keys found for $oper");
	    return undef;
	}
    }

    return ($certs,$keys);
}

# _parse_cert($parameters)
#
# Parameters:
# * file: filename
# * text: PEM-encoded cert
#
# Return value
# An hashref with the following keys:
# * email: email address from cert
# * subject: distinguished name
# * purpose: hashref with the following keys:
#  - enc: true if v3 purpose is encryption
#  - sign: true if v3 purpose is signing

sub _parse_cert {
    my (%params) = @_;
    Sympa::Log::do_log('debug', '(%s)', join('/',%params));

    ## Load certificate
    my $cert_string;
    if($params{'text'}) {
	$cert_string = $params{'text'};
    }elsif ($params{file}) {
	$cert_string = Sympa::Tools::File::slurp_file($params{file});
	unless ($cert_string) {
	    Sympa::Log::do_log('err', "unable to read %s: $ERRNO", $params{file});
	    return undef;
	}
    }else {
	Sympa::Log::do_log('err', '_parse_cert: neither "text" nor "file" given');
	return undef;
    }

    ## Extract information from cert
    my $file = File::Temp->new(CLEANUP => 1);
    my $command =
	    "$params{openssl} x509 -email -subject -purpose -noout > $file";
    my $pipe_handle;
    unless (open($pipe_handle, '|-', $command)) {
	Sympa::Log::do_log('err', "_parse_cert: open |openssl: $ERRNO");
	return undef;
    }
    print $pipe_handle $cert_string;
    close($pipe_handle);

    my $file_handle;
    unless (open($file_handle, '<', $file)) {
	Sympa::Log::do_log('err', "_parse_cert: open $file: $ERRNO");
	return undef;
    }

    my (%res, $purpose_section);

    while (my $line = <$file_handle>) {
      ## First lines before subject are the email address(es)

      if ($line =~ /^subject=\s+(\S.+)\s*$/) {
	$res{'subject'} = $1;

      }elsif (! $res{'subject'} && $line =~ /\@/) {
	my $email_address = lc($line);
	chomp $email_address;
	$res{'email'}{$email_address} = 1;

	  ## Purpose section appears at the end of the output
	  ## because options order matters for openssl
      }elsif ($line =~ /^Certificate purposes:/) {
		  $purpose_section = 1;
	  }elsif ($purpose_section) {
		if ($line =~ /^S\/MIME signing : (\S+)/) {
			$res{purpose}->{sign} = ($1 eq 'Yes');

		}elsif ($line =~ /^S\/MIME encryption : (\S+)/) {
			$res{purpose}->{enc} = ($1 eq 'Yes');
		}
      }
    }

    ## OK, so there's CAs which put the email in the subjectAlternateName only
    ## and ones that put it in the DN only...
    if(!$res{email} && ($res{subject} =~ /\/email(address)?=([^\/]+)/)) {
	$res{email} = $1;
    }
    close($file_handle);
    return \%res;
}

# _extract_certs(%parameters)
#
# Extract certificate from message.
#
# Parameters:
# * entity: (MIME::Entity instance)
# * file:
# * openssl: path to openssl binary

sub _extract_certs {
    my (%params) = @_;
    Sympa::Log::do_log('debug', '(%s)', join('/',%params));

    my $entity = $params{entity};

    return unless $entity->mime_type() =~ /application\/(x-)?pkcs7-/;

    my $command =
	    "$params{openssl} pkcs7 -print_certs -inform der " .
	    "> $params{file}";
    my $handle;
    unless (open($handle, '|-', $command)) {
	Sympa::Log::do_log('err', "unable to run openssl pkcs7: $ERRNO");
	return 0;
    }

    print $handle $entity->bodyhandle()->as_string();
    close($handle);

    if ($CHILD_ERROR) {
	Sympa::Log::do_log('err', "openssl pkcs7 returned an error: ", $CHILD_ERROR/256);
	return 0;
    }

    return 1;
}
1;
