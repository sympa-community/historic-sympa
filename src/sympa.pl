#! --PERL--
##
## Sympa - Main Program

## Load the modules and whatever we need.
use strict;

use lib '--DIR--/bin';
#use Getopt::Std;
use Getopt::Long;

use Mail::Address;
use Mail::Internet;
use MIME::Parser;
use MIME::Entity;
use MIME::Words;
use File::Path;

use Commands;
use Conf;
use Language;
use Log;
use Version;
use smtp;
use MIME::QuotedPrint;
use List;

use mail;
require 'tools.pl';
require 'msg.pl';
require 'parser.pl';

# durty global variables
my $is_signed = {}; 
my $is_crypted ;

## Internal tuning
# delay between each read of the expirequeue
my $expiresleep = 50 ; 

# delay between each read of the digestqueue
my $digestsleep = 5; 

## Options :  d		-> debug
##            D         -> Debug with many logs
##            f		-> name of configuration file
##            m		-> log invocations to sendmail.
##            l		-> language
##            F		-> Foreground and log to stderr also.
##            s         -> Dump subscribers list (listname or 'ALL' required)

#Getopt::Std::getopts('DdFf:ml:s:');

## Check --dump option
my %options;
&GetOptions(\%main::options, 'dump|s:s', 'debug|d', 'foreground|f', 'config|f=s', 'lang|l=s', 'messages|m');

## Trace options
#foreach my $k (keys %main::options) {
#    printf "%s = %s\n", $k, $main::options{$k};
#}

$main::options{'debug2'} = 1 if ($main::options{'debug'});

my @parser_param = ($*, $/);
my %loop_info;
my %msgid_table;

my $config_file = $main::options{'config'} || '--CONFIG--';
## Load configuration file
unless (Conf::load($config_file)) {
   print Msg(1, 1, "Configuration file $config_file has errors.\n");
   exit(1);
}

## Open the syslog and say we're read out stuff.
do_openlog($Conf{'syslog'}, $Conf{'log_socket_type'}, 'sympa');
do_log('info', 'Configuration file read'); 

## Probe Db if defined
if ($Conf{'db_name'} and $Conf{'db_type'}) {
    unless ($List::use_db = &List::probe_db()) {
	&fatal_err('Database %s defined in sympa.conf has not the right structure or is unreachable. If you don\'t use any database, comment db_xxx parameters in sympa.conf', $Conf{'db_name'});
    }
}

## Apply defaults to %List::pinfo
&List::_apply_defaults();

## Set locale configuration
$main::options{'lang'} =~ s/\.cat$//; ## Compatibility with version < 2.3.3
$Language::default_lang = $main::options{'lang'} || $Conf{'lang'};
&Language::LoadLang($Conf{'msgcat'});

## Check locale version
#if (Msg(1, 102, $Version) ne $Version){
#    &do_log('info', 'NLS message file version %s different from src version %s', Msg(1, 102,""), $Version);
#} 

## Main program
if (!chdir($Conf{'home'})) {
   fatal_err("Can't chdir to %s: %m", $Conf{'home'});
   ## Function never returns.
}

## Sets the UMASK
umask($Conf{'umask'});

## Set the UserID & GroupID for the process
$< = $> = (getpwnam('--USER--'))[2];
$( = $) = (getpwnam('--GROUP--'))[2];

## Check for several files.
unless (&Conf::checkfiles()) {
   fatal_err("Missing files. Aborting.");
   ## No return.
}

## Daemon called for dumping subscribers list
if ($main::options{'dump'}) {
    
    my @listnames;
    if ($main::options{'dump'} eq 'ALL') {
	@listnames = &List::get_lists();
    }else {
	@listnames = ($main::options{'dump'});
    }

    &List::dump(@listnames);

    exit 0;
}

## Put ourselves in background if we're not in debug mode. That method
## works on many systems, although, it seems that Unix conceptors have
## decided that there won't be a single and easy way to detach a process
## from its controlling tty.
unless ($main::options{'debug'} || $main::options{'foreground'}) {
   if (open(TTY, "/dev/tty")) {
       ioctl(TTY, 0x20007471, 0);         # XXX s/b &TIOCNOTTY
#       ioctl(TTY, &TIOCNOTTY, 0);
       close(TTY);
   }
   open(STDERR, ">> /dev/null");
   open(STDOUT, ">> /dev/null");
   setpgrp(0, 0);
   if (($_ = fork) != 0) {
      do_log('debug', "Starting server, pid $_");
      exit(0);
   }
   do_openlog($Conf{'syslog'}, $Conf{'log_socket_type'}, 'sympa');
}

## Create and write the pidfile
unless (open(LOCK, "+>> $Conf{'pidfile'}")) {
   fatal_err("Could not open %s, exiting", $Conf{'pidfile'});
   ## No return.
}
unless (flock(LOCK, 6)) {
   fatal_err("Could not lock %s: Sympa is probably already running.", $Conf{'pidfile'});
   ## No return.
}

unless (open(LCK, "> $Conf{'pidfile'}")) {
   fatal_err("Could not open %s, exiting", $Conf{'pidfile'});
   ## No return.
}

unless (truncate(LCK, 0)) {
   fatal_err("Could not truncate %s, exiting.", $Conf{'pidfile'});
   ## No return.
}
print LCK "$$\n";
close(LCK);

## Most initializations have now been done.
do_log('notice', "Sympa $Version Started");
printf "Sympa $Version Started\n";

## Catch SIGTERM, in order to exit cleanly, whenever possible.
$SIG{'TERM'} = 'sigterm';

my $end = 0;
my $index_queuedigest = 0; # verify the digest queue
my $index_queueexpire = 0; # verify the expire queue
my @qfile;

## This is the main loop : look after files in the directory, handles
## them, sleeps a while and continues the good job.
while (!$end) {

    &Language::SetLang($Language::default_lang);

    &List::init_list_cache();

    if (!opendir(DIR, $Conf{'queue'})) {
	fatal_err("Can't open dir %s: %m", $Conf{'queue'}); ## No return.
    }
    @qfile = sort grep (!/^\./,readdir(DIR));
    closedir(DIR);
    
    ## Scan queuedigest
    if ($index_queuedigest++ >=$digestsleep){
	$index_queuedigest=0;
	&SendDigest();
    }
    ## Scan the queueexpire
    if ($index_queueexpire++ >=$expiresleep){
	$index_queueexpire=0;
	&ProcessExpire();
    }

    my $filename;
    my $listname;
    my $highest_priority = 'z'; ## lowest priority
    
    ## Scans files in queue
    ## Search file with highest priority
    foreach my $t_filename (sort @qfile) {
	my $priority;
	my $type;
	my $list;

	# trying to fix a bug (perl bug ??) of solaris version
	($*, $/) = @parser_param;

	## test ever if it is an old bad file
	if ($t_filename =~ /^BAD\-/i){
	    if ((stat "$Conf{'queue'}/$t_filename")[9] < (time - $Conf{'clean_delay_queue'}*86400) ){
		unlink ("$Conf{'queue'}/$t_filename") ;
		do_log('notice', "Deleting bad message %s because too old", $t_filename);
	    };
	    next;
	}

	## z and Z are a null priority, so file stay in queue and are processed
	## only if renamed by administrator
	next unless ($t_filename =~ /^(\S+)\.\d+\.\d+$/);

	## Don't process temporary files created by queue (T.xxx)
	next if ($t_filename =~ /^T\./);

	## Extract listname from filename
	$listname = $1;
	$listname =~ s/\@.*$//;
	$listname =~ y/A-Z/a-z/;
	if ($listname =~ /^(\S+)-(request|owner|editor|subscribe|unsubscribe)$/) {
	    ($listname, $type) = ($1, $2);
	}

	unless ($listname =~ /^(sympa|listmaster|$Conf{'email'})(\@$Conf{'host'})?$/i) {
	    unless ($list = new List ($listname)) {
		rename("$Conf{'queue'}/$t_filename", "$Conf{'queue'}/BAD-$t_filename");
		do_log('notice', "Renaming bad file %s to BAD-%s", $t_filename, $t_filename);
	    }
	    next unless $list;
	}
	
	if ($listname eq 'listmaster') {
	    ## highest priority
	    $priority = 0;
	}elsif ($type eq 'request') {
	    $priority = $Conf{'request_priority'};
	}elsif ($type eq 'owner') {
	    $priority = $Conf{'owner_priority'};
	}elsif ($listname =~ /^(sympa|$Conf{'email'})(\@$Conf{'host'})?$/i) {	
	    $priority = $Conf{'sympa_priority'};
	}else {
	    $priority = $list->{'admin'}{'priority'};
	}
	
	if (ord($priority) < ord($highest_priority)) {
	    $highest_priority = $priority;
	    $filename = $t_filename;
	}
    } ## END of spool lookup

    &smtp::reaper;

    unless ($filename) {
	sleep($Conf{'sleep'});
	next;
    }

    do_log('debug', "Processing %s with priority %s", "$Conf{'queue'}/$filename", $highest_priority) 
	if ($main::options{'debug'});

    my $status = &DoFile($listname, "$Conf{'queue'}/$filename");
    
    if (defined($status)) {
	do_log('debug', "Finished %s", "$Conf{'queue'}/$filename") if ($main::options{'debug'});
	unlink("$Conf{'queue'}/$filename");
    }else {
	rename("$Conf{'queue'}/$filename", "$Conf{'queue'}/BAD-$filename");
	do_log('notice', "Renaming bad file %s to BAD-%s", $filename, $filename);
    }

} ## END of infinite loop

## Dump of User files in DB
#List::dump();

## Disconnect from Database
List::db_disconnect if ($List::dbh);

do_log('notice', 'Sympa exited normally due to signal');
unless (unlink $Conf{'pidfile'}) {
    fatal_err("Could not delete %s, exiting", $Conf{'pidfile'});
    ## No return.
}
exit(0);

## When we catch SIGTERM, just change the value of the loop
## variable.
sub sigterm {
    do_log('notice', 'signal TERM received, still processing current task');

    $end = 1;
}

## Handles a file received and files in the queue directory. This will
## read the file, separate the header and the body of the message and
## call the adequate function wether we have received a command or a
## message to be redistributed to a list.
sub DoFile {
    my ($listname, $file) = @_;
    &do_log('debug2', 'DoFile(%s)', $file);
    
    my $status;
    
    ## Open and parse the file   
    if (!open(IN, $file)) {
	&do_log('info', 'Can\'t open %s: %m', $file);
	return undef;
    }
    
    my $parser = new MIME::Parser;
    $parser->output_to_core(1);
#    $parser->output_under('/tmp', (DirName => "MIMEParser.$$",
#				   Purge => 1)
#			  );

    my $msg;
    unless ($msg = $parser->read(\*IN)) {
	do_log('notice', 'Unable to parse message %s', $file);
	return undef;
    }
    my $hdr = $msg->head;
    
    # message prepared by wwsympa and distributed by sympa
    if ( $hdr->get('X-Sympa-Checksum')) {
	return (&DoSendMessage ($msg)) ;
    }

    ## Ignoring messages without From: field
    unless ($hdr->get('From')) {
	do_log('notice', 'No From found in message, skipping.');
	return undef;
    }    

    my @sender_hdr = Mail::Address->parse($hdr->get('From'));
    
    if ($#sender_hdr == -1) {
	do_log('notice', 'No valid address in From: field, skipping');
	return undef;
    }

    my $sender = $sender_hdr[0]->address;

    ## Loop prevention
    if ($sender =~ /^(mailer-daemon|sympa|listserv|mailman|majordomo|smartlist|$Conf{'email'})/mio) {
	do_log('notice','Ignoring message which would cause a loop, sent by %s', $sender);
	return undef;
    }

    ## Initialize command report
    undef @msg::report;  
    
    ## Q- and B-decode subject
    my $subject_field = &MIME::Words::decode_mimewords($hdr->get('Subject'));
    chomp $subject_field;
#    $hdr->replace('Subject', $subject_field);
    
    my $bytes = -s $file;
    
    my ($list, $host, $name);   
    if ($listname =~ /^(sympa|listmaster|$Conf{'email'})(\@$Conf{'host'})?$/i) {
	$host = $Conf{'host'};
	$name = $listname;
    }else {
	$list = new List ($listname);
	$host = $list->{'admin'}{'host'};
	$name = $list->{'name'};
    }

    ## Search the X-Sympa-To header.
    my $rcpt = $hdr->get('X-Sympa-To');
    unless ($rcpt) {
	do_log('notice', 'no X-Sympa-To found, ignoring message file %s', $file);
	return undef;
    }
    
    ## Strip of the initial X-Sympa-To field
    $hdr->delete('X-Sympa-To');
    
    ## Loop prevention
    my $loop;
    foreach $loop ($hdr->get('X-Loop')) {
	chomp $loop;
	&do_log('debug','X-Loop: %s', $loop);
	#foreach my $l (split(/[\s,]+/, lc($loop))) {
	    if ($loop eq lc("$name\@$host")) {
		do_log('notice', "Ignoring message which would cause a loop (X-Loop: $loop)");
		return undef;
	    }
	#}
    }
    
    ## Content-Identifier: Auto-replied is generated by some non standard 
    ## X400 mailer
    if ($hdr->get('Content-Identifier') =~ /Auto-replied/i) {
	do_log('notice', "Ignoring message which would cause a loop (Content-Identifier: Auto-replied)");
	return undef;
    }

    ## encrypted message
    $is_crypted = 'not_crypted';
    if ($hdr->get('Content-Type') =~ /application\/x-pkcs7-mime/i) {
	do_log('debug2', "message is crypted");

	if ($Conf{'openssl'}) {
	    $is_crypted = 'smime_crypted';
	    unless ($msg = &tools::smime_decrypt ($msg,$name)) {
		do_log('debug','unable to decrypt message');
		## xxxxx traitement d'erreur ?
		return undef;
	    };
	    $hdr = $msg->head;
	    do_log('debug2', "message succefully decrypted");
	    # do_log('debug2', "xxxx dumped in /tmp/decrypted");
	    # open (XXDUMP, ">/tmp/decrypted");
	    # $msg->print(\*XXDUMP);
	    # close(XXDUMP);
	}

    }

    ## S/MIME signed messages
    undef $is_signed;
    if ($Conf{'openssl'} && $hdr->get('Content-Type') =~ /multipart\/signed/i) {
	$is_signed = &tools::smime_sign_check ($msg,$sender);
	do_log('debug2', "message is signed, signature is checked");
    }

    if ($rcpt =~ /^listmaster(\@(\S+))?$/) {
	
	$status = &DoForward('sympa', 'listmaster', $msg);

	## Mail adressed to the robot and mail 
	## to <list>-subscribe or <list>-unsubscribe are commands
    }elsif (($rcpt =~ /^(sympa|$Conf{'email'})(\@$Conf{'host'})?$/i) || ($rcpt =~ /^(\S+)-(subscribe|unsubscribe)(\@(\S+))?$/o)) {
	$status = &DoCommand($rcpt, $msg);
	
	## forward mails to <list>-request <list>-owner etc
    }elsif ($rcpt =~ /^(\S+)-(request|owner|editor)(\@(\S+))?$/o) {
	my ($name, $function) = ($1, $2);
	
	## Simulate Smartlist behaviour with command in subject
        ## xxxxxxxxxxx  �tendre le jeu de command reconnue sous cette forme ?
        ## 
	if (($function eq 'request') and ($subject_field =~ /^\s*(subscribe|unsubscribe)(\s*$name)?\s*$/i) ) {
	    my $command = $1;
	    
	    $status = &DoCommand("$name-$command", $msg);
	}else {
	    $status = &DoForward($name, $function, $msg);
	}       
    }else {
	$status =  &DoMessage($rcpt, $msg, $bytes, $file, $is_crypted);
    }
    

    ## Mail back the result.
    if (@msg::report) {

	## Loop prevention

	## Count reports sent to $sender
	$loop_info{$sender}{'count'}++;
	
	## Sampling delay 
	if ((time - $loop_info{$sender}{'date_init'}) < $Conf{'loop_command_sampling_delay'}) {

	    ## Notify listmaster of first rejection
	    if ($loop_info{$sender}{'count'} == $Conf{'loop_command_max'}) {
		## Notify listmaster
		&List::send_notify_to_listmaster('loop_command', $file);
	    }
	    
	    ## Too many reports sent => message skipped !!
	    if ($loop_info{$sender}{'count'} >= $Conf{'loop_command_max'}) {
		&do_log('notice', 'Ignoring message which would cause a loop, %d messages sent to %s', $loop_info{$sender}{'count'}, $sender);
		
		return undef;
	    }
	}else {
	    ## Sampling delay is over, reinit
	    $loop_info{$sender}{'date_init'} = time;

	    ## We apply Decrease factor if a loop occured
	    $loop_info{$sender}{'count'} *= $Conf{'loop_command_decrease_factor'};
	}

	## Prepare the reply message
	my $reply_hdr = new Mail::Header;
	$reply_hdr->add('From', sprintf Msg(12, 4, 'SYMPA <%s>'), $Conf{'sympa'});
	$reply_hdr->add('To', $sender);
	$reply_hdr->add('Subject', Msg(4, 17, 'Output of your commands'));
	$reply_hdr->add('X-Loop', $Conf{'sympa'});
	$reply_hdr->add('MIME-Version', Msg(12, 1, '1.0'));
	$reply_hdr->add('Content-type', sprintf 'text/plain; charset=%s', 
			Msg(12, 2, 'us-ascii'));
	$reply_hdr->add('Content-Transfer-Encoding', Msg(12, 3, '7bit'));
	
	## Open the SMTP process for the response to the command.
	*FH = &smtp::smtpto($Conf{'request'}, \$sender);
	$reply_hdr->print(\*FH);
	
	foreach (@msg::report) {
	    print FH;
	}
	
	print FH "\n";

	close(FH);
    }
    
    return $status;
}

## send a message as prepared by wwsympa
sub DoSendMessage {
    my $msg = shift;
    &do_log('debug2', 'DoSendMessage()');

    my $hdr = $msg->head;
    
    my ($chksum, $rcpt, $from) = ($hdr->get('X-Sympa-Checksum'), $hdr->get('X-Sympa-To'), $hdr->get('From'));
    chomp $rcpt; chomp $chksum; chomp $from;

    do_log('info', "Processing web message for %s", $rcpt);

    unless ($chksum eq &tools::sympa_checksum($rcpt)) {
	&do_log('notice', 'Message ignored because incorrect checksum');
	return undef ;
    }

    $hdr->delete('X-Sympa-Checksum');
    $hdr->delete('X-Sympa-To');
    
    ## Multiple recepients
    my @rcpts = split /,/,$rcpt;
    
    *MSG = &smtp::smtpto($from,\@rcpts); 
    $msg->print(\*MSG);
    close (MSG);

    do_log('info', "Message for %s sent", $rcpt);

    return 1;
}

## Handles a message sent to [list]-editor, [list]-owner or [list]-request
sub DoForward {
    my($name,$function,$msg) = @_;
    &do_log('debug2', 'DoForward(%s, %s)', $name, $function);

    my $hdr = $msg->head;
    my $messageid = $hdr->get('Message-Id');

    ##  Search for the list
    my ($list, $admin, $host, $recepient, $priority);

    if ($function eq 'listmaster') {
	$recepient="$function";
	$host = $Conf{'host'};
	$priority = 0;
    }else {
	unless ($list = new List ($name)) {
	    do_log('notice', "Message for %s-%s ignored, unknown list %s",$name, $function, $name );
	    return undef;
	}
	
	$admin = $list->{'admin'};
	$host = $admin->{'host'};
        $recepient="$name-$function";
	$priority = $admin->{'priority'};
    }

    my @rcpt;
    
    do_log('info', "Processing message for %s with priority %s, %s", $recepient, $priority, $messageid );
    
    $hdr->add('X-Loop', "$name-$function\@$host");
    $hdr->delete('X-Sympa-To:');

    if ($function eq "listmaster") {
	@rcpt = @{$Conf{'listmasters'}};
	do_log('notice', 'Warning : no listmaster defined in sympa.conf') 
	    unless (@rcpt);
	
    }elsif ($function eq "request") {
	foreach my $i (@{$admin->{'owner'}}) {
	    next if ($i->{'reception'} eq 'nomail');
	    push(@rcpt, $i->{'email'}) if ($i->{'email'});
	}
	do_log('notice', 'Warning : no owner defined or all of them use nomail option in list %s', $name ) 
	    unless (@rcpt);

    }elsif ($function eq "editor") {
	foreach my $i (@{$admin->{'editor'}}) {
	    next if ($i->{'reception'} eq 'nomail');
	    push(@rcpt, $i->{'email'}) if ($i->{'email'});
	}
	unless (@rcpt) {
	    do_log('notice', 'No editor defined in list %s (unless they use NOMAIL), use owners', $name ) ;
	    foreach my $i (@{$admin->{'owner'}}) {
		next if ($i->{'reception'} eq 'nomail');
		push(@rcpt, $i->{'email'}) if ($i->{'email'});
	    }
	}
    }
    
    if ($#rcpt < 0) {
	do_log('notice', "Message for %s-%s ignored, %s undefined in list %s", $name, $function, $function, $name);
	return undef;
    }
    *SIZ = smtp::smtpto($Conf{'request'}, \@rcpt);
    $msg->print(\*SIZ);
    close(SIZ);
    
    do_log('info',"Message for %s forwarded", $recepient);
    return 1;
}


## Handles a message sent to a list.
sub DoMessage{
    my($which, $msg, $bytes, $file, $encrypt ) = @_;
    &do_log('debug2', 'DoMessage(%s, %s, msg from %s, %s, %s)', $which, $msg, $msg->head->get('From'), $bytes, $file, $encrypt);
    
    ## List and host.
    my($listname, $host) = split(/[@\s]+/, $which);

    ## Search for the list
    my $list = new List ($listname);
    return undef unless $list;
 
    my ($name, $host) = ($list->{'name'}, $list->{'admin'}{'host'});

    my $start_time = time;
    
    ## Now check if the sender is an authorized address.
    my $hdr = $msg->head;
    
    my $from_field = $hdr->get('From');
    my $messageid = $hdr->get('Message-Id');

    do_log('info', "Processing message for %s with priority %s, %s", $name,$list->{'admin'}{'priority'}, $messageid );
    
    my @sender_hdr = Mail::Address->parse($from_field);

    my $sender = $sender_hdr[0]->address || '';
    if ($sender =~ /^(mailer-daemon|sympa|listserv|majordomo|smartlist|mailman|$Conf{'email'})/mio) {
	do_log('notice', 'Ignoring message which would cause a loop');
	return undef;
    }

    if ($msgid_table{$listname}{$messageid}) {
	do_log('notice', 'Found known Message-ID, ignoring message which would cause a loop');
	return undef;
    }
    
    
    ## Check the message for commands and catch them.
    return undef if (tools::checkcommand($msg, $sender));
       
    my $admin = $list->{'admin'};
    return undef unless $admin;
    
    my $customheader = $admin->{'custom_header'};
#    $host = $admin->{'host'} if ($admin->{'host'});

    ## Check if the message is a return receipt
    if ($hdr->get('multipart/report')) {
	do_log('notice', 'Message for %s from %s ignored because it is a report', $name, $sender);
	return undef;
    }
    
    ## Check if the message is too large
    my $max_size = $list->get_max_size() || $Conf{'max_size'};
    if ($max_size && $bytes > $max_size) {
	do_log('notice', 'Message for %s from %s too large (%d > %d)', $name, $sender, $bytes, $max_size);
	*SIZ  = smtp::smtpto($Conf{'request'}, \$sender);
	print SIZ "From: " . sprintf (Msg(12, 4, 'SYMPA <%s>'), $Conf{'request'}) . "\n";
	printf SIZ "To: %s\n", $sender;
	printf SIZ "Subject: " . Msg(4, 11, "Your message for list %s has been rejected") . "\n", $name;
	printf SIZ "MIME-Version: %s\n", Msg(12, 1, '1.0');
	printf SIZ "Content-Type: text/plain; charset=%s\n", Msg(12, 2, 'us-ascii');
	printf SIZ "Content-Transfer-Encoding: %s\n\n", Msg(12, 3, '7bit');
	print SIZ Msg(4, 12, $msg::msg_too_large);
	$msg->print(\*SIZ);
	close(SIZ);
	return undef;
    }
    
    ## Call scenarii : auth_method MD5 do not have any sense in send
    ## scenarii because auth is perfom by distribute or reject command.
 
    
    my $action ;
    if ($is_signed->{'body'}) {
	$action = &List::get_action ('send',$name,$sender,'smime',$hdr);
    }else{
	$action = &List::get_action ('send',$name,$sender,'smtp',$hdr);
    }

    if ($action =~ /^do_it/) {
	
	my $numsmtp = $list->distribute_msg($msg, $bytes, $encrypt);

	$msgid_table{$listname}{$messageid}++;
	
	unless (defined($numsmtp)) {
	    do_log('info','Unable to send message to list %s', $name);
	    return undef;
	}

	do_log('info', 'Message for %s from %s accepted (%d seconds, %d sessions), size=%d', $name, $sender, time - $start_time, $numsmtp, $bytes);
	
	## Everything went fine, return TRUE in order to remove the file from
	## the queue.
	return 1;
    }elsif($action =~ /^request_auth/){
    	my $key = $list->send_auth($sender, $msg);
	do_log('notice', 'Message for %s from %s kept for authentication with key %s', $name, $sender, $key);
	return 1;
    }elsif($action =~ /^editorkey(\s?,\s?(quiet))?/){
	my $key = $list->send_to_editor('md5',$msg,$file,$encrypt);
	do_log('info', 'Key %s for list %s from %s sent to editors, %s', $key, $name, $sender, $file, $encrypt);
	$list->notify_sender($sender) unless ($2 eq 'quiet');
	return 1;
    }elsif($action =~ /^editor(\s?,\s?(quiet))?/){
	my $key = $list->send_to_editor('smtp',$msg);
	do_log('info', 'Message for %s from %s sent to editors', $name, $sender);
	$list->notify_sender($sender) unless ($2 eq 'quiet');
	return 1;
    }elsif($action =~ /^reject(\s?,\s?(quiet))?/) {
    
	do_log('notice', 'Message for %s from %s rejected because sender not allowed', $name, $sender);
	unless ($2 eq 'quiet') {
	    *SIZ  = smtp::smtpto($Conf{'request'}, \$sender);
	    print SIZ "From: " . sprintf (Msg(12, 4, 'SYMPA <%s>'), $Conf{'request'}) . "\n";
	    printf SIZ "To: %s\n", $sender;
	    printf SIZ "Subject: " . Msg(4, 11, "Your message for list %s has been rejected")."\n", $name ;
	    printf SIZ "MIME-Version: %s\n", Msg(12, 1, '1.0');
	    printf SIZ "Content-Type: text/plain; charset=%s\n", Msg(12, 2, 'us-ascii');
	    printf SIZ "Content-Transfer-Encoding: %s\n\n", Msg(12, 3, '7bit');
	    printf SIZ Msg(4, 15, $msg::list_is_private), $name;
	    $msg->print(\*SIZ);
	    close(SIZ);
	}
	return undef;
    }
}

## Handles a message sent to a list.

## Handles a command sent to the list manager.
sub DoCommand {
    my($rcpt, $msg) = @_;
    &do_log('debug2', 'DoCommand(%s)', $rcpt);

    ## Now check if the sender is an authorized address.
    my $hdr = $msg->head;
    
    ## Decode headers
    $hdr->decode();
    
    my $from_field = $hdr->get('From');
    my $messageid = $hdr->get('Message-Id');
    my ($success, $status);
    
    do_log('debug', "Processing command with priority %s, %s", $Conf{'sympa_priority'}, $messageid );
    
    my @sender_hdr = Mail::Address->parse($from_field);
    my $sender = $sender_hdr[0]->address;

    ## If X-Sympa-To = <listname>-<subscribe|unsubscribe> parse as a unique command
    if ($rcpt =~ /^(\S+)-(subscribe|unsubscribe)(\@(\S+))?$/o) {
	do_log('debug',"processing message for $1-$2");
	&Commands::parse($sender,"$2 $1");
	return 1; 
    }
    
    ## Process the Subject of the message
    ## Search and process a command in the Subject field
    my $subject_field = $hdr->get('Subject');
    chomp $subject_field;
    $subject_field =~ s/\n//mg; ## multiline subjects
    $subject_field =~ s/^\s*(Re:)?\s*(.*)\s*$/$2/i;

    $success ||= &Commands::parse($sender, $subject_field, $is_signed->{'subject'}) ;

    ## Make multipart singlepart
    if ($msg->is_multipart()) {
	if (&tools::as_singlepart($msg, 'text/plain')) {
	    do_log('notice', 'Multipart message changed to singlepart');
	}
    }

    ## check Content-type
    my $mime = $hdr->get('Mime-Version') ;
    my $content_type = $hdr->get('Content-type');
    my $transfert_encoding = $hdr->get('Content-transfer-encoding');
    
    unless (($content_type =~ /text/i and !$mime)
	    or !($content_type) 
	    or ($content_type =~ /text\/plain/i)) {
	do_log('notice', "Ignoring message body not in text/plain, Content-type: %s", $content_type);
	print Msg(4, 37, "Ignoring message body not in text/plain, please use text/plain only \n(or put your command in the subject).\n");
	
	return $success;
    }
        
    my @msgexpire;
    my ($expire, $i);
    my $size;

    ## Process the body of the message
    unless ($success == 1) { ## unless subject contained commands
#	foreach $i (@{$msg->body}) {
	my @body = $msg->bodyhandle->as_lines();
	foreach $i (@body) {
	    if ($transfert_encoding =~ /quoted-printable/i) {
		$i = MIME::QuotedPrint::decode($i);
	    }
	    if ($expire){
		if ($i =~ /^(quit|end|stop)/io){
		    last;
		}
		# store the expire message in @msgexpire
		push(@msgexpire, $i);
		next;
	    }
	    $i =~ s/^\s*>?\s*(.*)\s*$/$1/g;
	    next if ($i =~ /^$/); ## skip empty lines
	    
	    # exception in the case of command expire
	    if ($i =~ /^exp(ire)?\s/i){
		$expire = $i;
		print "> $i\n\n";
		next;
	    }
	    
	    push @msg::report, "> $i\n\n";
	    $size = $#msg::report;
	    

	    if ($i =~ /^(quit|end|stop|--)/io) {
		last;
	    }
	    &do_log('debug2',"is_signed->body $is_signed->{'body'}");

	    unless ($status = Commands::parse($sender, $i,$is_signed->{'body'})) {
		push @msg::report, sprintf Msg(4, 19, "Command not understood: ignoring end of message.\n");
		last;
	    }

	    if ($#msg::report > $size) {
		## There is a command report
		push @msg::report, "\n";
	    }else {
		## No command report
		pop @msg::report;
	    }
	    
	    $success ||= $status;
	}
	pop @msg::report unless ($#msg::report > $size);
    }

    ## No command found
    unless (defined($success)) {
	do_log('info', "No command found in message");
	push @msg::report, sprintf Msg(4, 39, "No command found in message");
    }
    
    # processing the expire function
    if ($expire){
	print STDERR "expire\n";
	unless (&Commands::parse($sender, $expire, @msgexpire)) {
	    print Msg(4, 19, "Command not understood: ignoring end of message.\n");
	}
    }

    return $success;
}

## Read the queue and send old digests to the subscribers with the digest option.
sub SendDigest{
    &do_log('debug2', 'SendDigest()');

    if (!opendir(DIR, $Conf{'queuedigest'})) {
	fatal_err(Msg(3, 1, "Can't open dir %s: %m"), $Conf{'queuedigest'}); ## No return.
    }
    my @dfile =( sort grep (!/^\./,readdir(DIR)));
    closedir(DIR);


    foreach my $digest (@dfile){

	my @timedigest= (stat "$Conf{'queuedigest'}/$digest")[9];
        my $listname = $digest;

	my $list = new List ($listname);
	unless ($list) {
	    &do_log('info', 'Unknown list, deleting digest file %s', $digest);
	    unlink "$Conf{'queuedigest'}/$digest";
	    return undef;
	}

	if ($list->get_nextdigest()){
	    ## Blindly send the message to all users.
	    do_log('info', "Sending digest to list %s", $digest);
	    my $start_time = time;
	    $list->send_msg_digest($digest);

	    unlink("$Conf{'queuedigest'}/$digest");
	    do_log('info', 'Digest of the list %s sent (%d seconds)', $digest,time - $start_time);
	}
    }
}


## Read the EXPIRE queue and check if a process has ended
sub ProcessExpire{
    &do_log('debug2', 'ProcessExpire()');

    my $edir = $Conf{'queueexpire'};
    if (!opendir(DIR, $edir)) {
	fatal_err("Can't open dir %s: %m", $edir); ## No return.
    }
    my @dfile =( sort grep (!/^\./,readdir(DIR)));
    closedir(DIR);
    my ($d1, $d2, $proprio, $user);

    foreach my $expire (@dfile) {
#   while ($expire=<@dfile>){	
	## Parse the expire configuration file
	if (!open(IN, "$edir/$expire")) {
	    next;
	}
	if (<IN> =~ /^(\d+)\s+(\d+)$/) {
	    $d1=$1;
	    $d2=$2;
	}	

	if (<IN>=~/^(.*)$/){
	    $proprio=$1; 
	}
	close(IN);

	## Is the EXPIRE process finished ?
	if ($d2 <= time){
	    my $list = new List ($expire);
	    my $listname = $list->{'name'};
	    unless ($list){
		unlink("$edir/$expire");
		next;
	    };
	
	    ## Prepare the reply message
	    my $reply_hdr = new Mail::Header;
	    $reply_hdr->add('From', sprintf Msg(12, 4, 'SYMPA <%s>'), $Conf{'sympa'});
	    $reply_hdr->add('To', $proprio);
 	    $reply_hdr->add('Subject',sprintf( Msg(4, 24, 'End of your command EXPIRE on list %s'),$expire));

	    $reply_hdr->add('MIME-Version', Msg(12, 1, '1.0'));
	    my $content_type = 'text/plain; charset='.Msg(12, 2, 'us-ascii');
	    $reply_hdr->add('Content-type', $content_type);
	    $reply_hdr->add('Content-Transfer-Encoding', Msg(12, 3, '7bit'));

	    ## Open the SMTP process for the response to the command.
	    *FH = &smtp::smtpto($Conf{'request'}, \$proprio);
	    $reply_hdr->print(\*FH);
	    my $fh = select(FH);
	    my $limitday=$d1;
	    #converting dates.....
	    $d1= int((time-$d1)/86400);
	    #$d2= int(($d2-time)/86400);
	
	    my $cpt_badboys;
	    ## Amount of unconfirmed subscription

	    unless ($user = $list->get_first_user()) {
		return undef;
}

	    while ($user = $list->get_next_user()) {
		$cpt_badboys++ if ($user->{'date'} < $limitday);
	    }

	    ## Message to the owner who launched the expire command
	    printf Msg(4, 28, "Among the subscribers of list %s for %d days, %d did not confirm their subscription.\n"), $listname, $d1, $cpt_badboys;
	    print "\n";
	    printf Msg(4, 26, "Subscribers who do not have confirm their subscription:\n");	
	    print "\n";
	
	    my $temp=0;

	    unless ($user = $list->get_first_user()) {
		return undef;
	    }

	    while ($user = $list->get_next_user()) {
		next unless ($user->{'date'} < $limitday);
		print "," if ($temp == 1);
		print " $user->{'email'} ";
		$temp=1 if ($temp == 0);
	    }
	    print "\n\n";
	    printf Msg(4, 27, "You must delete these subscribers from this list with the following commands :\n");
	    print "\n";

	    unless ($user = $list->get_first_user()) {
		return undef;
	    }
	    while ($user = $list->get_next_user()) {
		next unless ($user->{'date'} < $limitday);
		print "DEL   $listname   $user->{'email'}\n";
	    }
	    ## Mail back the result.
	    select($fh);
	    close(FH);
	    unlink("$edir/$expire");
	    next;
	}
    }
}


1;
