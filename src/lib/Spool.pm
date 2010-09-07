# list.pm - This module includes all list processing functions
# RCS Identication ; $Revision: 6646 $ ; $Date: 2010-08-19 10:32:08 +0200 (jeu 19 aoû 2010) $ 
#
# Sympa - SYsteme de Multi-Postage Automatique
# Copyrigh (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
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

package Spool;

use strict;
use POSIX;
use Datasource;
use SQLSource qw(create_db %date_format);
use Upgrade;
use Lock;
use Task;
use Scenario;
use Fetch;
use WebAgent;
use Exporter;
require Encode;

use tt2;
use Sympa::Constants;

our @ISA = qw(Exporter);

use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN);


use Carp;

use IO::Scalar;
use Storable;
use Mail::Header;
use Archive;
use Language;
use Log;
use Conf;
use mail;
use Ldap;
use Time::Local;
use MIME::Entity;
use MIME::EncWords;
use MIME::Parser;
use Message;
use Family;
use PlainDigest;


## Database and SQL statement handlers
my ($dbh, $sth, $db_connected, @sth_stack, $use_db);

## Creates an object.
sub new {
    my($pkg, $spoolname) = @_;
    my $spool={};
    do_log('debug2', 'Spool::new(%s)', $spoolname);
    
    unless ($spoolname =~ /^(auth)|(bad)|(bounce)|(digest)|(bulk)|(expire)|(moderation)|(msg)|(outgoing)|(subscribe)|(topic)$/){
	do_log('err','unknown spool');
	exit;
    }
    $spool->{'spoolname'} = $spoolname;

    bless $spool, $pkg;

    return $spool;
}

#######################
#
#  get_content return the content an array of hash describing the spool content
# 
sub get_content {

    my $self = shift;

    &do_log('debug', 'Spool::get_content(%s)',$self->{'spoolname'});
    
    $dbh = &List::db_get_handler();

    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }
    my $statement = sprintf "SELECT lock_spool AS spool, messagekey_spool AS messagekey, list_spool AS list, robot_spool AS robot, receptiondate_spool as receptiondate, priority_spool AS priority, sender_spool AS sender, subject_spool AS subject, messageid_spool AS messageid, size_spool AS size FROM spool_table WHERE spoolname_spool = %s",$dbh->quote($self->{'spoolname'});

    do_log('trace',"statement = $statement");
    push @sth_stack, $sth;
    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    
    my @messages;
    while (my $message = $sth->fetchrow_hashref('NAME_lc')) {
	$message->{'receptiondate_asstring'} = 	&tools::epoch2yyyymmjj_hhmmss($message->{'receptiondate'});
	push @messages, $message;
    }
    $sth->finish();
    $sth = pop @sth_stack;
    return \@messages    ;
}

sub _sqlselector {
	
    my $selector = shift; 
 
    my $sqlselector = '';
    if ($selector->{'listname'}) {
	$sqlselector = 'list_spool ='.$dbh->quote($selector->{'listname'}).' AND ';
    }else{
	$sqlselector = "list_spool = '' AND ";
    }
    if ($selector->{'robot'}) {		
	$sqlselector = $sqlselector.' robot_spool ='.$dbh->quote($selector->{'robot'}).' AND ';
    }else{
	$sqlselector = $sqlselector." robot_spool = '' AND ";
    }
    
    if ($selector->{'messagekey'}) {
	$sqlselector = $sqlselector.' messagekey_spool ='.$dbh->quote($selector->{'messagekey'});
    }else{
	return undef;
    }
    return $sqlselector;
}
#################"
# return one message from related spool using a specified selector
#  
sub get_message {

    my $self = shift;
    my $selector = shift;


    &do_log('debug', "Spool::get_message($self->{'spoolname'},messagekey = $selector->{'messagekey'}, listname = $selector->{'listname'},robot = $selector->{'robot'})");
    
    $dbh = &List::db_get_handler();

    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }
    my $sqlselector = '';
    if ($selector->{'listname'}) {
	$sqlselector = 'list_spool ='.$dbh->quote($selector->{'listname'});
    }
    if ($selector->{'robot'}) {
	$sqlselector = $sqlselector.' AND ' unless ($sqlselector eq '');
	$sqlselector = $sqlselector.' robot_spool ='.$dbh->quote($selector->{'robot'}); 
    }
    if ($selector->{'messagekey'}) {
	$sqlselector = $sqlselector.' AND ' unless ($sqlselector eq '');
	$sqlselector = $sqlselector.' messagekey_spool ='.$dbh->quote($selector->{'messagekey'});
    }

#	$sqlselector = &_sqlselector($selector); 
    my $statement = sprintf "SELECT lock_spool, messagekey_spool AS messagekey, list_spool AS list, robot_spool AS robot, receptiondate_spool as receptiondate, priority_spool AS priority, sender_spool AS sender, subject_spool AS subject, messageid_spool AS messageid, message_spool AS messageasstring, dkim_header_list_spool AS dkim_header_list, dkim_privatekey_spool AS dkim_privatekey, dkim_d_spool AS dkim_d, dkim_i_spool AS dkim_i, dkim_selector_spool AS dkim_selector FROM spool_table WHERE spoolname_spool = %s AND ".$sqlselector.' LIMIT 1',$dbh->quote($self->{'spoolname'});

    do_log('trace',"statement = $statement");
    push @sth_stack, $sth;
    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }   
    my $message = $sth->fetchrow_hashref('NAME_lc');
    if ($message) {
	$message->{'lock'} =  $message->{'lock_spool'}; # lock is SQL key word so "SELECT lock_spool as lock" make a sql error  
	$message->{'messageasstring'} = MIME::Base64::decode($message->{'messageasstring'});
    }
    $sth-> finish;
    $sth = pop @sth_stack;
    return $message;
}

################
# test if a keyword is a valid information for an spool entry
sub _is_valid_message_info {

    my $meta = shift;
    unless ($meta =~ /^(lock)|(messagekey)|(list)|(robot)|(priority)|(receptiondate)|(spoolname)|(subject)|(sender)|(messageid)|(dkim_header_list)|(dkim_privatekey)|(dkim_d)|(dkim_i)|(dkim_selector)$/) {
	do_log ('err', "improper meta name information for a message in spool : $meta");
	return undef;
    }
    return 1;
}

#################"
# lock one message from related spool using a specified selector
#  
sub lock_message {

    my $self = shift;
    my $selector = shift;

    &do_log('debug', 'Spool::lock_message(%s)',$self->{'spoolname'});
    &do_log('trace', "Spool::lock_message($self->{'spoolname'}, list = $selector->{'list'}, 'robot' => $selector->{'robot'}, 'messagekey' => $selector->{'messagekey'}");
    return ( $self->update({'list' => $selector->{'list'}, 'robot' => $selector->{'robot'}, 'messagekey' => $selector->{'messagekey'}},
			   {'lock' => '1'}));
}

#################"
# lock one message from related spool using a specified selector
#  
sub unlock_message {

    my $self = shift;
    my $selector = shift;

    &do_log('debug', 'Spool::unlock_message(%s)',$self->{'spoolname'}, $selector->{'list'}, $selector->{'robot'}, $selector->{'messagekey'});
    &do_log('trace', "Spool::unlock_message($self->{'spoolname'}, list = $selector->{'list'}, 'robot' => $selector->{'robot'}, 'messagekey' => $selector->{'messagekey'}");
    return ( $self->update({'list' => $selector->{'list'}, 'robot' => $selector->{'robot'}, 'messagekey' => $selector->{'messagekey'}},
			   {'lock' => '0'}));
}

#################"
# lock one message from related spool using a specified selector
#  
sub update {

    my $self = shift;
    my $selector = shift;
    my $values = shift;

    &do_log('debug', "Spool::update($self->{'spoolname'}, list = $selector->{'list'}, robot = $selector->{'robot'}, messagekey = $selector->{'messagekey'}");

    my $where = '';
    foreach my $meta (keys %$selector) {
	do_log('trace',"meta : $meta");
	next unless (&_is_valid_message_info($meta));
	do_log('trace',"where : $where");
	$where = $where.' AND '. $meta.'_spool = '.$dbh->quote($selector->{$meta});	
    }

    $where = "spoolname_spool = '".$self->{'spoolname'}."'".$where;
    do_log('trace',"where : $where");

    my $set = '';
    foreach my $meta (keys %$values) {
	do_log('trace',"xx values-> $meta = $values->{$meta}");
	next unless (&_is_valid_message_info($meta));
	next if ($meta =~ /^(messagekey)|(message)$/); 
	if ($set) {
	    $set = $set.',';
	}
	$set = $set .$meta.'_spool = '.$dbh->quote($values->{$meta});
    }
    do_log('trace'," set = $set");

    unless ($set) {
	do_log('err',"No value to update"); return undef;
    }
    unless ($where) {
	do_log('err',"No selector for an update"); return undef;
    }

    ## Updating Db
    my $statement = sprintf "UPDATE spool_table SET %s WHERE (%s)", $set,$where ;

    do_log('trace',"update: $statement");

    unless ($dbh->do($statement)) {
	do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }    
    return 1;
}

################
#
sub _get_messagekey {
    my $message_asstring = shift;
    return &tools::md5_fingerprint($message_asstring);
}

################"
# store a message in database spool 
#
sub store {  

    my $self = shift;
    my $message_asstring = shift;
    my $metadata = shift;
    
    do_log('trace',"Spool::store yyyyyy   ($self->{'spoolname'}, le message as string ,$metadata->{'list'},$metadata->{'robot'} )");
    do_log('debug',"Spool::store ($self->{'spoolname'}, <message_asstring> ,list : $metadata->{'list'},robot : $metadata->{'robot'} )");

    $dbh = &List::db_get_handler();

    unless ($dbh and $dbh->ping) {
		do_log('trace',"not connected try to connect to database");
		return undef unless &List::db_connect();
    };

    my $messagesize = length($message_asstring);
    my $b64msg = MIME::Base64::encode($message_asstring);
    my $messagekey = &_get_messagekey($message_asstring);

    ## search if this message is already in spool database : mailfile may perform multiple submission of exactly the same message 
    if ($self->get_message({list => $metadata->{'list'}, robot => $metadata->{'robot'}, messagekey => $messagekey})){
		do_log('trace',"message already in spool table");
		return undef;
    }
    
    do_log('trace',"messageasstring : $message_asstring");
    ### Prepare message meta data.
    my $parser = new MIME::Parser;
    my $entity = $parser->parse_data($message_asstring); 

    if($entity) {
	$metadata->{'subject'} = $entity->head->get('Subject');
	$metadata->{'subject'} = substr $metadata->{'subject'}, 0, 110;
	$metadata->{'messageid'} = $entity->head->get('Message-Id');
	$metadata->{'messageid'} = substr $metadata->{'messageid'}, 0, 95;
	my @sender_hdr = Mail::Address->parse($entity->get('From'));
	if ($#sender_hdr >= 0){
	    $metadata->{'sender'} = lc($sender_hdr[0]->address);
	    $metadata->{'sender'} = substr $metadata->{'sender'}, 0, 110;
	}
    }else{
	$metadata->{'subject'} = '';
	$metadata->{'messageid'} = '';
	$metadata->{'sender'} = '';
    }

    do_log('trace',"sender = $metadata->{'sender'} ; subject = $metadata->{'subject'}, $metadata->{'messageid'}");

    my $insertpart1; my $insertpart2;
    foreach my $meta ('list','robot','priority','subject','sender','messageid','dkim_header_list','dkim_privatekey','dkim_d','dkim_i','dkim_selector') {
	$insertpart1 = $insertpart1. ', '.$meta.'_spool';
	$insertpart2 = $insertpart2. ', '.$dbh->quote($metadata->{$meta});   
    }
    my $dateepoch = int(time) ; 
    my $statement        = sprintf "INSERT INTO spool_table (messagekey_spool, spoolname_spool, lock_spool, message_spool, receptiondate_spool, size_spool %s ) VALUES (%s, %s, %s, %s, %s, %s %s)",$insertpart1,$dbh->quote($messagekey),$dbh->quote($self->{'spoolname'}),$dbh->quote('0'),$dbh->quote($b64msg),       $dbh->quote($dateepoch),$dbh->quote($messagesize), $insertpart2;
    my $statement_trace  = sprintf "INSERT INTO spool_table (messagekey_spool, spoolname_spool, lock_spool, message_spool, receptiondate_spool, size_spool %s ) VALUES (%s, %s, %s, %s, %s, %s %s)",$insertpart1,$dbh->quote($messagekey),$dbh->quote($self->{'spoolname'}),$dbh->quote('0'),$dbh->quote('...b64msg...'),$dbh->quote($dateepoch),$dbh->quote($messagesize),$insertpart2;
        
    do_log('trace',"insert : $statement_trace");

    push @sth_stack, $sth;
    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }   
    $sth-> finish;
    $sth = pop @sth_stack;

    return 1;
}

################"
# remove a message in database spool using (messagekey,list,robot) which are a unique id in the spool
#
sub remove_message {  

    my $self = shift;
    my $selector = shift;
    my $robot = $selector->{'robot'};
    my $messagekey = $selector->{'messagekey'};
    my $listname = $selector->{'listname'};
    do_log('trace',"remove_message ($self->{'spoolname'},$listname,$robot,$messagekey)");
    do_log('debug',"remove_message ($self->{'spoolname'},$listname,$robot,$messagekey)");
    $dbh = &List::db_get_handler();

    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    };
    
    ## search if this message is already in spool database : mailfile may perform multiple submission of exactly the same message 
    unless ($self->get_message($selector)){
		do_log('err',"message not in spool"); 
		return undef;
    }
    
    my $sqlselector = &_sqlselector($selector);
    #my $statement  = sprintf "DELETE FROM spool_table WHERE spoolname_spool = %s AND messagekey_spool = %s AND list_spool = %s AND robot_spool = %s",$dbh->quote($self->{'spoolname'}),$dbh->quote($messagekey),$dbh->quote($listname),$dbh->quote($robot);
    my $statement  = sprintf "DELETE FROM spool_table WHERE spoolname_spool = %s AND %s",$dbh->quote($self->{'spoolname'}),$sqlselector;
    
    do_log('trace',"remove_message : $statement");

    push @sth_stack, $sth;
    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }   
    
    $sth-> finish;
    $sth = pop @sth_stack;
    return 1;
}

# test the maximal message size the database will accept
sub store_test { 
    my $value_test = shift;
    my $divider = 100;
    my $steps = 50;
    my $maxtest = $value_test/$divider;
    my $size_increment = $divider*$maxtest/$steps;
    my $barmax = $size_increment*$steps*($steps+1)/2;
    my $even_part = $barmax/$steps;
    
    &do_log('debug', 'Spool::store_test()');

    print "maxtest: $maxtest\n";
    print "barmax: $barmax\n";
    my $progress = Term::ProgressBar->new({name  => 'Total size transfered',
                                         count => $barmax,
                                         ETA   => 'linear', });

    my $testing = new Spool('bad');
    
    my $msg = sprintf "From: justeatester\@notadomain\nMessage-Id:yep\@notadomain\nSubject: this a test\n\n";
    $progress->max_update_rate(1);
    my $next_update = 0;
    my $total = 0;

    my $result = 0;
    
    for (my $z=1;$z<=$steps;$z++){	
	for(my $i=1;$i<=1024*$size_increment;$i++){
	    $msg .=  'a';
	}
	my $time = time();
        $progress->message(sprintf "Test storing and removing of a %5d kB message (step %s out of %s)", $z*$size_increment, $z, $steps);
	# 
	unless ($testing->store($msg,{list=>'notalist',robot=>'notaboot'})) {
	    return (($z-1)*$size_increment);
	}
	my $messagekey = &Spool::_get_messagekey($msg);
	unless ( $testing->remove_message({'messagekey'=>$messagekey,'listname'=>'notalist','robot'=>'notarobot'}) ) {
	    &do_log('err','Unable to remove test message (key = %s) from spool_table',$messagekey);	    
	}
	$total += $z*$size_increment;
        $progress->message(sprintf ".........[OK. Done in %.2f sec]", time() - $time);
	$next_update = $progress->update($total+$even_part)
	    if $total > $next_update && $total < $barmax;
	$result = $z*$size_increment;
    }
    $progress->update($barmax)
	if $barmax >= $next_update;
    return $result;
}

###### END of the Spool package ######

## Packages must return true.
1;
