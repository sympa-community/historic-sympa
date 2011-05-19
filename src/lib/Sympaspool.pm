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

package Sympaspool;

use strict;
use POSIX;
use Sys::Hostname;
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
use Sympa::DatabaseDescription;

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
use Data::Dumper;
use Message;
use Family;
use PlainDigest;


## Database and SQL statement handlers
my ($dbh, $sth, $db_connected, @sth_stack, $use_db);


## Creates an object.
sub new {
    my($pkg, $spoolname, $selection_status) = @_;
    my $spool={};
    do_log('debug2', 'Spool::new(%s)', $spoolname);
    
    unless ($spoolname =~ /^(auth)|(bounce)|(digest)|(bulk)|(expire)|(mod)|(msg)|(archive)|(automatic)|(subscribe)|(topic)|(validated)$/){
	do_log('err','internal error unknown spool %s',$spoolname);
	return undef;
    }
    $spool->{'spoolname'} = $spoolname;
    if (($selection_status eq 'bad')||($selection_status eq 'ok')) {
	$spool->{'selection_status'} = $selection_status;
    }else{
	$spool->{'selection_status'} =  'ok';
    }

    bless $spool, $pkg;

    return $spool;
}


sub count {
    my $self = shift;
    return ($self->get_content({'selection'=>'count'}));
}

#######################
#
#  get_content return the content an array of hash describing the spool content
# 
sub get_content {

    my $self = shift;
    my $data= shift;
    my $selector=$data->{'selector'};     # hash field->value used as filter  WHERE sql query 
    my $selection=$data->{'selection'};   # the list of field to select. possible values are :
                                          #    -  a comma separated list of field to select. 
                                          #    -  '*'  is the default .
                                          #    -  '*_but_message' mean any field except message which may be hugue and unusefull while listing spools
                                          #    - 'count' mean the selection is just a count.
                                          # should be used mainly to select all but 'message' that may be huge and may be unusefull
    my $ofset = $data->{'ofset'};         # for pagination, start fetch at element number = $ofset;
    my $page_size = $data->{'page_size'}; # for pagination, limit answers to $page_size
    my $orderby = $data->{'sortby'};      # sort
    my $way = $data->{'way'};             # asc or desc 

    &do_log('debug', 'Spool::get_content(%s)',$self->{'spoolname'});
    &do_log('trace', 'Spool::get_content(%s,selector : %s)',$self->{'spoolname'},$selector);
    
    $dbh = &List::db_get_handler();
    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }

    my $sql_where = _sqlselector($selector);
    if ($self->{'selection_status'} eq 'bad') {
	$sql_where = $sql_where."AND message_status_spool = 'bad' " ;
    }else{
	$sql_where = $sql_where."AND message_status_spool != 'bad' " ;
    }
    $sql_where =~s/^AND//;

    my $statement ;
    if ($selection eq 'count'){
	# just return the selected count, not all the values
	$statement = 'SELECT COUNT(*) ';
    }else{
	$statement = 'SELECT '.&_selectfields($selection);
    }

    $statement = $statement . sprintf " FROM spool_table WHERE %s AND spoolname_spool = %s ",$sql_where,$dbh->quote($self->{'spoolname'});

    if ($orderby) {
	$statement = $statement. ' ORDER BY '.$orderby.'_spool ';
	$statement = $statement. ' DESC' if ($way eq 'desc') ;
    }
    if ($page_size) {
	$statement = $statement . ' LIMIT '.$ofset.' , '.$page_size;
    }
    do_log('trace',"statement $statement");

    push @sth_stack, $sth;
    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    if($selection eq 'count') {
	my @result = $sth->fetchrow_array();
	do_log('trace',"comptage %s",$result[0]);
	return $result[0];
    }else{
	my @messages;
	while (my $message = $sth->fetchrow_hashref('NAME_lc')) {
	    $message->{'date_asstring'} = &tools::epoch2yyyymmjj_hhmmss($message->{'date'});
	    $message->{'lockdate_asstring'} = &tools::epoch2yyyymmjj_hhmmss($message->{'lockdate'});
	    $message->{'messageasstring'} = MIME::Base64::decode($message->{'message'}) if ($message->{'message'}) ;
	    $message->{'listname'} = $message->{'list'}; # duplicated because "list" is a tt2 method that convert a string to an array of chars so you can't test  [% IF  message.list %] because it is always defined!!!
	    $message->{'status'} = $self->{'selection_status'}; 
	    push @messages, $message;
	    do_log('trace',"contenu message de %s subject: %s",$message->{'sender'},$message->{'subject'});
	}
	$sth->finish();
	$sth = pop @sth_stack;
	return @messages;
    }
}

#######################
#
#  next : return next spool entry ordered by priority next lock the message_in_spool that is returned
# 
sub next {

    my $self = shift;
    my $selector = shift;

    &do_log('debug', 'Spool::next(%s,%s)',$self->{'spoolname'},$self->{'selection_status'});
    
    $dbh = &List::db_get_handler();

    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }
    my $sql_where = _sqlselector($selector);

    if ($self->{'selection_status'} eq 'bad') {
	$sql_where = $sql_where."AND message_status_spool = 'bad' " ;
    }else{
	$sql_where = $sql_where."AND message_status_spool != 'bad' " ;
    }
    $sql_where =~ s/^\s*AND//;

    my $lock = $$.'@'.hostname(); 
    my $epoch=time; # should we use milli or nano seconds ? 

    my $statement = sprintf "UPDATE spool_table SET messagelock_spool=%s, lockdate_spool =%s WHERE messagelock_spool IS NULL AND spoolname_spool =%s AND %s ORDER BY priority_spool, date_spool LIMIT 1", $dbh->quote($lock),$dbh->quote($epoch),$dbh->quote($self->{'spoolname'}),$sql_where;
    push @sth_stack, $sth;

    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    return undef unless ($sth->rows); # spool is empty

    my $star_select = &_selectfields();
    my $statement = sprintf "SELECT %s FROM spool_table WHERE spoolname_spool = %s AND message_status_spool= %s AND messagelock_spool = %s AND lockdate_spool = %s AND (priority_spool != 'z' OR priority_spool IS NULL) ORDER by priority_spool LIMIT 1", $star_select ,$dbh->quote($self->{'spoolname'}),$dbh->quote($self->{'selection_status'}),$dbh->quote($lock),$dbh->quote($epoch);

    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    my $message = $sth->fetchrow_hashref('NAME_lc');
    $sth->finish();
    $sth = pop @sth_stack;

    unless ($message->{'message'}){
	do_log('err',"INTERNAL Could not find message previouly locked");
	return undef;
    }
    $message->{'messageasstring'} = MIME::Base64::decode($message->{'message'});
    unless ($message->{'messageasstring'}){
	do_log('err',"Could not decode %s",$message->{'message'});
	return undef;
    }
    return $message  ;
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
    my %db_struct  = &Sympa::DatabaseDescription::db_struct();

    foreach my $field (keys %$selector){
#	unless (defined %{$db_struct{'mysql'}{'spool_table'}{$field.'_spool'}}) {
#	    do_log ('err',"internal error : invalid selector field $field locking for message in spool_table");
#	    return undef;
#	} 

	$sqlselector = $sqlselector.' AND ' unless ($sqlselector eq '');

	if ($field eq 'messageid') {
	    $selector->{'messageid'} = substr $selector->{'messageid'}, 0, 95;
	}
	$sqlselector = $sqlselector.' '.$field.'_spool = '.$dbh->quote($selector->{$field}); 
    }
    my $all = &_selectfields();
    my $statement = sprintf "SELECT %s FROM spool_table WHERE spoolname_spool = %s AND ".$sqlselector.' LIMIT 1',$all,$dbh->quote($self->{'spoolname'});

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
	$message->{'lock'} =  $message->{'messagelock'}; 
	$message->{'messageasstring'} = MIME::Base64::decode($message->{'message'});
    }

    $sth-> finish;
    $sth = pop @sth_stack;
    return $message;
}


#################"
# lock one message from related spool using a specified selector
#  
sub unlock_message {

    my $self = shift;
    my $messagekey = shift;

    &do_log('debug', 'Spool::unlock_message(%s,%s)',$self->{'spoolname'}, $messagekey);
    return ( $self->update({'messagekey' => $messagekey},
			   {'messagelock' => 'NULL'}));
}

#################"
# 
#  update spool entries that match selector with values
sub update {

    my $self = shift;
    my $selector = shift;
    my $values = shift;

    &do_log('debug', "Spool::update($self->{'spoolname'}, list = $selector->{'list'}, robot = $selector->{'robot'}, messagekey = $selector->{'messagekey'}");

    my $where = _sqlselector($selector);

    my $set = '';

    # hidde B64 encoding inside spool database.    
    if ($values->{'message'}) {
	$values->{'size'} =  length($values->{'message'});
	$values->{'message'} =  MIME::Base64::encode($values->{'message'})  ;
    }
    # update can used in order to move a message from a spool to another one
    $values->{'spoolname'} = $self->{'spoolname'} unless($values->{'spoolname'});

    foreach my $meta (keys %$values) {
	next if ($meta =~ /^(messagekey)$/); 
	if ($set) {
	    $set = $set.',';
	}
	if (($meta eq 'messagelock')&&($values->{$meta} eq 'NULL')){
	    # SQL set  xx = NULL and set xx = 'NULL' is not the same !
	    $set = $set .$meta.'_spool = NULL';
	}else{	
	    $set = $set .$meta.'_spool = '.$dbh->quote($values->{$meta});
	}
	if ($meta eq 'messagelock') {
	    if ($values->{'messagelock'} eq 'NULL'){
		# when unlock always reset the lockdate
		$set =  $set .', lockdate_spool = NULL ';
	    }else{		
		# when setting a lock always set the lockdate
		$set =  $set .', lockdate_spool = '.$dbh->quote(time);
	    }    
	}
    }

    unless ($set) {
	do_log('err',"No value to update"); return undef;
    }
    unless ($where) {
	do_log('err',"No selector for an update"); return undef;
    }

    ## Updating Db
    my $statement = sprintf "UPDATE spool_table SET %s WHERE (%s)", $set,$where ;

    unless ($dbh->do($statement)) {
	do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }    
    return 1;
}

################"
# store a message in database spool 
#
sub store {  

    my $self = shift;
    my $message_asstring = shift;  
    my $metadata = shift; # a set of attributes related to the spool
    my $locked = shift;   # if define message must stay locked after store

    do_log('debug',"Spool::store ($self->{'spoolname'},$self->{'selection_status'}, <message_asstring> ,list : $metadata->{'list'},robot : $metadata->{'robot'} , date: $metadata->{'date'}), lock : $locked");

    $dbh = &List::db_get_handler();

    unless ($dbh and $dbh->ping) {
		return undef unless &List::db_connect();
    };

    my $b64msg = MIME::Base64::encode($message_asstring);

    my $message = new Message({'messageasstring'=>$message_asstring});
    
    if($message) {
	$metadata->{'spam_status'} = $message->{'spam_status'};
	$metadata->{'subject'} = $message->{'msg'}->head->get('Subject'); chomp $metadata->{'subject'} ;
	$metadata->{'subject'} = substr $metadata->{'subject'}, 0, 109;
	$metadata->{'messageid'} = $message->{'msg'}->head->get('Message-Id'); chomp $metadata->{'messageid'} ;
	$metadata->{'messageid'} = substr $metadata->{'messageid'}, 0, 295;
	$metadata->{'headerdate'} = substr $message->{'msg'}->head->get('Date'), 0, 78;

	my @sender_hdr = Mail::Address->parse($message->{'msg'}->get('From'));
	if ($#sender_hdr >= 0){
	    $metadata->{'sender'} = lc($sender_hdr[0]->address);
	    $metadata->{'sender'} = substr $metadata->{'sender'}, 0, 109;
	}
    }else{
	$metadata->{'subject'} = '';
	$metadata->{'messageid'} = '';
	$metadata->{'sender'} = '';
    }
    $metadata->{'date'}= int(time) unless ($metadata->{'date'}) ;
    $metadata->{'size'}= length($message_asstring) unless ($metadata->{'size'}) ;
    $metadata->{'message_status'} = 'ok';

    my $insertpart1; my $insertpart2;
    foreach my $meta ('list','robot','message_status','priority','date','type','subject','sender','messageid','size','headerdate','spam_status','dkim_header_list','dkim_privatekey','dkim_d','dkim_i','dkim_selector') {
	$insertpart1 = $insertpart1. ', '.$meta.'_spool';
	$insertpart2 = $insertpart2. ', '.$dbh->quote($metadata->{$meta});   
    }
    my $lock = $$.'@'.hostname() ;

    push @sth_stack, $sth;

    my $statement        = sprintf "INSERT INTO spool_table (spoolname_spool, messagelock_spool, message_spool %s ) VALUES (%s,%s,%s %s )",$insertpart1,$dbh->quote($self->{'spoolname'}),$dbh->quote($lock),$dbh->quote($b64msg), $insertpart2;
    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    $statement = sprintf "SELECT messagekey_spool as messagekey FROM spool_table WHERE messagelock_spool = %s AND date_spool = %s",$dbh->quote($lock),$dbh->quote($metadata->{'date'});

    # this query return the autoinc primary key as result of this insert

    unless ($sth = $dbh->prepare($statement)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    my $inserted_message = $sth->fetchrow_hashref('NAME_lc');
    my $messagekey = $inserted_message->{'messagekey'};
    
    $sth-> finish;
    $sth = pop @sth_stack;

    unless ($locked) {
	$self->unlock_message($messagekey);	
    }
    return $messagekey;
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
    #my $statement  = sprintf "DELETE FROM spool_table WHERE spoolname_spool = %s AND messagekey_spool = %s AND list_spool = %s AND robot_spool = %s AND bad_spool IS NULL",$dbh->quote($self->{'spoolname'}),$dbh->quote($messagekey),$dbh->quote($listname),$dbh->quote($robot);
    my $statement  = sprintf "DELETE FROM spool_table WHERE spoolname_spool = %s AND %s",$dbh->quote($self->{'spoolname'}),$sqlselector;
    
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
# Clean a spool by removing old messages
#

sub clean {  
    my $self = shift;
    my $filter = shift;

    my $delay = $filter->{'delay'};
    my $bad =  $filter->{'bad'};
    

    &do_log('debug', 'Spool::clean(%s,$delay)',$self->{'spoolname'},$delay);
    my $spoolname = $self->{'spoolname'};
    return undef unless $spoolname;
    return undef unless $delay;
    
    my $freshness_date = time - ($delay * 60 * 60 * 24);

    my $sqlquery = "DELETE FROM 'spool_table' WHERE spoolname_spool ='$spoolname' AND date_spool < '$freshness_date' ";
    if ($bad) {	
	$sqlquery  = 	$sqlquery . " AND bad_spool IS NOTNULL ";
    }else{
	$sqlquery  = 	$sqlquery . " AND bad_spool IS NULL ";
    }
    
    push @sth_stack, $sth;
    unless ($sth = $dbh->prepare($sqlquery)) {
	&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $sqlquery, $dbh->errstr);
	return undef;
    }   
    $sth-> finish;
    do_log('debug',"%s entries older than %s days removed from spool %s" ,$sth->rows,$delay,$self->{'spoolname'});
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




#######################
# Internal to ease SQL
# return a SQL SELECT substring in ordder to select choosen fields from spool table
# selction is comma separated list of field, '*' or '*_but_message'. in this case skip message_spool field 
sub _selectfields{
    my $selection = shift;  # default all valid fields from spool table

    $selection = '*' unless $selection;
    my $select ='';

    if (($selection eq '*_but_message')||($selection eq '*')) {
	my %db_struct = &Sympa::DatabaseDescription::db_struct();

	foreach my $field ( keys %{ $db_struct{'mysql'}{'spool_table'}} ) {
	    next if (($selection eq '*_but_message') && ($field eq 'message_spool')) ;
	    my $var = $field;
	    $var =~ s/\_spool//;
	    $select = $select . $field .' AS '.$var.',';
	}
    }else{
	my @fields = split (/,/,$selection);
	foreach my $field (@fields){
	    $select = $select . $field .'_spool AS '.$field.',';
	}
    }

    $select =~ s/\,$//;
    return $select;
}

#######################
# Internal to ease SQL
# return a SQL WHERE substring in ordder to select choosen fields from spool table 
sub _sqlselector {
	
    my $selector = shift; 
    do_log('trace',"_selector %s",$selector);
    my $sqlselector = '';
    
    foreach my $field (keys %$selector) {
	if ($sqlselector) {
	    $sqlselector .= ' AND '.$field.'_spool = '.$dbh->quote($selector->{$field});
	}else{
	    $sqlselector = ' '.$field.'_spool = '.$dbh->quote($selector->{$field});
	}
    }
    return $sqlselector;
}


###### END of the Sympapool package ######

## Packages must return true.
1;
