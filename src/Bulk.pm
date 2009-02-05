# Bulk.pm - This module includes bulk mailer subroutines
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
# You should have received a copy of the GNU General Public License# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

package Bulk;

use strict;
use Datasource;
use SQLSource qw(create_db %date_format);
use Lock;
use Task;
require Fetch;
require Exporter;
require Encode;
require 'tools.pl';
require "--LIBDIR--/tt2.pl";

my @ISA = qw(Exporter);

use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN);



use Carp;

use IO::Scalar;
use Storable;
use Mail::Header;
use Language;
use Log;
use Conf;
use mail;
use Ldap;
use Time::Local;
use MIME::Entity;
use MIME::EncWords;
use MIME::WordDecoder;
use MIME::Parser;
use Message;
use List;

## Database and SQL statement handlers
my ($dbh, $sth, $db_connected, @sth_stack, $use_db);


# fingerprint of last message stored in bulkspool
my $message_fingerprint;

# create an empty Bulk
#sub new {
#    my $pkg = shift;
#    my $packet = &Bulk::next();;
#    bless \$packet, $pkg;
#    return $packet
#}
## 
# get next packet to process, order is controled by priority then by creation date. 
# Next lock the packetb to prevent multiple proccessing of a single packet 

sub next {

    &do_log('debug', 'Bulk::next');


    $dbh = &List::db_get_handler();

    # lock next packet
    my $lock = &tools::get_lockname();
    my $order = 'ORDER BY priority_bulkmailer DESC, date_bulkmailer ASC, verp_bulkmailer ASC LIMIT 1';
	my $statement = sprintf "UPDATE bulkmailer_table SET lock_bulkmailer=%s WHERE lock_bulkmailer IS NULL %s",$dbh->quote($lock), $order ;

       ## Check database connection
    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }
    
    unless ($dbh->do($statement)) {
	do_log('err','Unable to select and lock bulk packet  SQL statement "%s"; error : %s', $statement, $dbh->errstr);
	return undef;
    }

    # select the packet that as been locked previously
    $statement = sprintf "SELECT messagekey_bulkmailer AS messagekey, packetid_bulkmailer AS packetid, receipients_bulkmailer AS receipients, returnpath_bulkmailer AS returnpath, listname_bulkmailer AS listname, robot_bulkmailer AS robot, priority_bulkmailer AS priority, verp_bulkmailer AS verp, date_bulkmailer AS date FROM bulkmailer_table WHERE lock_bulkmailer=%s %s",$dbh->quote($lock), $order;

    unless ($sth = $dbh->prepare($statement)) {
	do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    
    unless ($sth->execute) {
	do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }

    my $result = $sth->fetchrow_hashref;
    $sth->finish();
    return $result;

}


# remove a packet from database by packet id. return undef if packet does not exist

sub remove {
    my $messagekey = shift;
    my $packetid= shift;
    #
    &do_log('debug', "Bulk::remove(%s,%s)",$messagekey,$packetid);

    my $statement = sprintf "DELETE FROM bulkmailer_table WHERE packetid_bulkmailer = %s AND messagekey_bulkmailer = %s",$dbh->quote($packetid),$dbh->quote($messagekey),;
    unless ($dbh and $dbh->ping) {
	return undef unless &db_connect();
    }	   
    return ($dbh->do($statement));
}

sub messageasstring {
    my $messagekey = shift;
    &do_log('debug', 'Bulk::messageasstring(%s)',$messagekey);
    
    my $statement = sprintf "SELECT message_bulkspool AS message FROM bulkspool_table WHERE messagekey_bulkspool = %s",$dbh->quote($messagekey);
    
    unless ($dbh and $dbh->ping) {
	return undef unless &db_connect();
    }
    unless ($sth = $dbh->prepare($statement)) {
	do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    
    unless ($sth->execute) {
	do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    my $messageasstring = $sth->fetchrow_hashref ;
    $sth->finish;

    return($messageasstring->{'message'});
}
## 
sub store { 
    my %data = @_;
    &do_log('debug', 'Bulk::store');
    
    my $msg = $data{'msg'};
    my $rcpts = $data{'rcpts'};
    my $from = $data{'from'};
    my $robot = $data{'robot'};
    my $listname = $data{'listname'};
    my $priority = $data{'priority'};
    my $verp = $data{'verp'};

    $dbh = &List::db_get_handler();

    $priority |= &Conf::get_robot_conf($robot,'sympa_priority');
    
    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }
    
    my $messagekey = &tools::md5_fingerprint($msg);

    # first store the message in bulk_message_table (because as soon as packet are created bulk.pl may distribute them).
    # if messagekey is equal to message_fingerprint, the message is already stored in database
    
    my $message_already_on_spool;

    if ($messagekey ne $message_fingerprint) {

	## search if this message is already in spool database : mailfile may perform multiple submission of exactly the same message 
	my $statement = sprintf "SELECT count(*) FROM bulkspool_table WHERE ( messagekey_bulkspool = %s )", $dbh->quote($messagekey);
    
	unless ($sth = $dbh->prepare($statement)) {
	    do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	    return undef;
	}	
	unless ($sth->execute) {
	    do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	    return undef;
	}
	
	$message_already_on_spool = $sth->fetchrow;
	$sth->finish();
	
	# if message is not found in bulkspool_table store it
	if ($message_already_on_spool == 0) {	    
	    my $statement = sprintf "INSERT INTO bulkspool_table (messagekey_bulkspool, message_bulkspool, lock_bulkspool) VALUES (%s, %s, '1')",$dbh->quote($messagekey),$dbh->quote($msg);
	    my $statementtrace = sprintf "INSERT INTO bulkspool_table (messagekey_bulkspool, message_bulkspool, lock_bulkspool) VALUES (%s, %s, '1')",$dbh->quote($messagekey),$dbh->quote(substr($msg, 0, 100));	    
	    unless ($dbh->do($statement)) {
		do_log('err','Unable to add message in bulkspool_table "%s"; error : %s', $statementtrace, $dbh->errstr);
		return undef;
	    }
	    $message_fingerprint = $messagekey;
	}
    }

    my $current_date = time; 
    
    # second : create each receipient packet in bulkmailer_table
    my $type = ref $rcpts;

#    foreach my $packet (@{$rcpts}) {
    unless (ref $rcpts) {
	my @tab = ($rcpts);
	my @tabtab;
	push @tabtab, \@tab;
	$rcpts = \@tabtab;
    }
    foreach my $packet (@{$rcpts}) {
	$type = ref $packet;
	my $rcptasstring ;
	if  (ref $packet eq 'ARRAY'){
	    $rcptasstring  = join ',',@{$packet};
	}else{
	    $rcptasstring  = $packet;
	}
	my $packetid =  &tools::md5_fingerprint($rcptasstring);
	my $packet_already_exist;
	if ($message_already_on_spool) {
	    ## search if this packet is already in spool database : mailfile may perform multiple submission of exactly the same message 
	    my $statement = sprintf "SELECT count(*) FROM bulkmailer_table WHERE ( messagekey_bulkmailer = %s AND  packetid_bulkmailer = %s)", $dbh->quote($messagekey),$dbh->quote($packetid);
	    
	    unless ($sth = $dbh->prepare($statement)) {
		do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
		return undef;
	    }	
	    unless ($sth->execute) {
		do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
		return undef;
	    }	    
	    $packet_already_exist = $sth->fetchrow;
	    $sth->finish();
	}
	
	unless ($packet_already_exist) {
	    my $statement = sprintf "INSERT INTO bulkmailer_table (messagekey_bulkmailer,packetid_bulkmailer,receipients_bulkmailer,returnpath_bulkmailer,robot_bulkmailer,listname_bulkmailer, verp_bulkmailer, priority_bulkmailer, date_bulkmailer) VALUES (%s,%s,%s,%s,%s,%s,'%s','%s','%s')", $dbh->quote($messagekey),$dbh->quote($packetid),$dbh->quote($rcptasstring),$dbh->quote($from),$dbh->quote($robot),$dbh->quote($listname),$verp,$priority, $current_date;
	    
	    unless ($sth = $dbh->do($statement)) {
		do_log('err','Unable to add packet in bulkmailer_table "%s"; error : %s', $statement, $dbh->errstr);
		return undef;
	    }
	}
    }
    # last : unlock message in bulkspool_table so it is now possible to remove this message if no packet have a ref on it			
    my $statement = sprintf "UPDATE bulkspool_table SET lock_bulkspool='0' WHERE messagekey_bulkspool = %s",$dbh->quote($messagekey) ;                                        ;
    unless ($dbh->do($statement)) {
	do_log('err','Unable to unlock packet in bulkmailer_table "%s"; error : %s', $statement, $dbh->errstr);
	return undef;
    }
}

## remove file that are not referenced by any packet
sub purge_bulkspool {
    &do_log('debug', 'purge_bulkspool');

    my $dbh = &List::db_get_handler();
    my $sth;

    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }
    my $statement = "SELECT messagekey_bulkspool AS messagekey FROM bulkspool_table LEFT JOIN bulkmailer_table ON messagekey_bulkspool = messagekey_bulkmailer WHERE messagekey_bulkmailer IS NULL AND lock_bulkspool = 0";
    unless ($sth = $dbh->prepare($statement)) {
	do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }
    
    unless ($sth->execute) {
	do_log('err','Unable to execute SQL statement "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }

    my $count = 0;
    while (my $key = $sth->fetchrow_hashref) {	
	if ( &Bulk::remove_bulkspool_message('bulkspool',$key->{'messagekey'}) ) {
	    $count++;
	}else{
	    &do_log('err','Unable to remove message (key = %s) from bulkspool_table',$key->{'messagekey'});	    
	}
   }
    $sth->finish;
    return $count;
}

sub remove_bulkspool_message {
    my $spool = shift;
    my $messagekey = shift;

    my $table = $spool.'_table';
    my $key = 'messagekey_'.$spool ;
    my $dbh = &List::db_get_handler();
    my $sth;

    unless ($dbh and $dbh->ping) {
	return undef unless &List::db_connect();
    }

    my $statement = sprintf "DELETE FROM `%s` WHERE `%s` = '%s'",$table,$key,$messagekey;

    unless ($sth = $dbh->prepare($statement)) {
	do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
	return undef;
    }

    unless ($sth->execute) {
	do_log('err','Unable to execute SQL statement (while trying to remove packet from bulkmailer_table) "%s" : %s', $statement, $dbh->errstr);
	return undef;
    }
    return 1;
}

## Packages must return true.
1;
