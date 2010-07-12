# Tracking.pm - this module does the mail tracking processing
# RCS Identication ; mar, 15 septembre 2009 

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

package tracking;

use strict;

use DBI;
use CGI;
use Email::Simple;
use Log;
use MIME::Base64;



our $status = "Waiting";   


##############################################
#  format_msg_id
##############################################
# Parses the argument and format it in order to 
# get an adequate message-id value. 
# 
# IN :-$message_id (+): the message-id to format
#
# OUT : $msgID | undef
#      
##############################################
sub format_msg_id{
	my $msgID = shift;
	
	unless ($msgID) {
        	&do_log('err', "Can't find message-id");
                return undef;	
	}
	if($msgID =~ /<(\S+@\S+)>/){
		($msgID)= $msgID =~ /<(\S+@\S+)>/;			
	}
	return $msgID;			
}

##############################################
#  format_from_address
##############################################
# Parses the argument and format it in order to 
# get an adequate mail address form. 
# 
# IN :-$from_header (+): the address to format
#
# OUT : $from_header | undef
#      
##############################################
sub format_from_address{
	my $from_header = shift;

	my @from;

	unless ($from_header) {
                &do_log('err', "Can't find from address");
                return undef;
	} 
	if($from_header =~ /\s.*/){
		@from = split /\s+/,$from_header;
		foreach my $from (@from){
			if($from =~ /<(\S+\@\S+)>/){
				($from)= $from =~ /<(\S+@\S+)>/;			
				$from_header = $from;
			}
		}
	}
	elsif($from_header =~ /<(\S+\@\S+)>/){
		($from_header)= $from_header =~ /<(\S+@\S+)>/;			
	}
	return $from_header;
}

##############################################
#   connection
##############################################
# Function use to connect to a database 
# with the given arguments. 
# 
# IN :-$database (+): the database name
#     -$hostname (+): the hostname of the database
#     -$port (+): port to use
#     -$login (+): user identifiant
#     -$mdp (+): password for identification
#
# OUT : $dbh |undef
#      
##############################################
sub connection{
	my ($database, $hostname, $port, $login, $mdp) = @_;
	
	my $dsn = "DBI:mysql:database=$database:host=$hostname:port=$port";
	my $dbh;

	unless ($dbh = DBI->connect($dsn, $login, $mdp)) {
		&do_log('err', "Can't connect to the database");
		return undef;
	}
	return $dbh;
}

##############################################
#   get_pk_message
##############################################
# Function use to get the pk identificator of 
# a mail in a mysql database with the given message-id.
# A connection must already exist 
# 
# IN :-$dbh (+): the database connection
#     -$id (+): the message-id of the mail
#     -$listname (+): the name of the list to which the 
#		      mail has been sent
#     -$robot : the robot of the list
#
# OUT : $pk |undef
#      
##############################################
sub get_pk_message_to_be_removed {
	my ($dbh, $id, $listname,$robot) = @_;

	my $sth;
	my $pk;
	my $request = "SELECT pk_mail FROM mail_table WHERE `message_id_mail` = '$id' AND `list_mail` = '$listname' AND `robot_mail` = '$robot'";

        &do_log('trace', ' proceduer à virer Request For Message Table : : %s', $request);

	unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
                return undef;
	}
	unless ($sth->execute) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
	}

	my @pk_mail = $sth->fetchrow_array;
	$pk = $pk_mail[0];
	$sth->finish();
	return $pk;
}

##############################################
#   get_recipients_number
##############################################
# Function use to ask the number of recipients
# of a message. Use the pk identifiant of the mail
# 
# IN :-$dbh (+): the database connection
#     -$pk_mail (+): the identifiant of the stored mail
#
# OUT : $pk |undef
#      
##############################################
sub get_recipients_number {
        my $dbh = shift;
        my $pk_mail = shift;

        my $sth;
        my $pk;
        # my $request = "SELECT COUNT(*) FROM notification_table WHERE `pk_mail_notification` = '$pk_mail' AND `type_notification` = 'DSN'";
	my $request = "SELECT COUNT(*) FROM notification_table WHERE `pk_mail_notification` = '$pk_mail'";

        &do_log('trace', 'Request For Message Table : : %s', $request);
        unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement : %s (%s)', $dbh->errstr,$request);
                return undef;
        }
        unless ($sth->execute) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
        }
        my @pk_notif = $sth->fetchrow_array;
        $pk = $pk_notif[0];
        $sth->finish();
        return $pk;
}
##############################################
#   get_recipients_status
##############################################
# Function use to get mail addresses and status of 
# the recipients who have a different DSN status than "delivered"
# Use the pk identifiant of the mail
# 
# IN :-$dbh (+): the database connection
#     -$pk_mail (+): the identifiant of the stored mail
#
# OUT : @pk_notifs |undef
#      
##############################################
sub get_recipients_status {
#        my $dbh = shift;
        my $msgid  = shift;
	my $listname = shift;
        my $robot =shift;

        &do_log('debug2', 'get_recipients_status(%s,%s,%s)', $msgid,$listname,$robot);

	my $dbh = &List::db_get_handler();

	## Check database connection
	unless ($dbh and $dbh->ping) {
	    return undef unless &List::db_connect();
	}
	
        my $sth;
        my $pk;

	# the message->head method return message-id including <blabla@dom> where mhonarc return blabla@dom that's why we test both of them
        my $request = sprintf "SELECT recipient_notification AS recipient,  reception_option_notification AS reception_option, status_notification AS status, arrival_date_notification AS arrival_date, type_notification as type, message_notification as notification_message FROM notification_table WHERE (list_notification = %s AND robot_notification = %s AND (message_id_notification = %s OR CONCAT('<',message_id_notification,'>') = %s OR message_id_notification = %s ))",$dbh->quote($listname),$dbh->quote($robot),$dbh->quote($msgid),$dbh->quote($msgid),$dbh->quote('<'.$msgid.'>');
	
        &do_log('trace', 'Request For Message Table : : %s', $request);
        unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
                return undef;
        }
        &do_log('trace', 'post prepare');
        unless ($sth->execute) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
        }
        my @pk_notifs;
       &do_log('trace', 'post execute');
        while (my $pk_notif = $sth->fetchrow_hashref){
	    if ($pk_notif->{'notification_message'}) { 
		$pk_notif->{'notification_message'} = MIME::Base64::decode($pk_notif->{'notification_message'});
	    }else{
		$pk_notif->{'notification_message'} = '';
	    }	    
	    push @pk_notifs, $pk_notif;
        }
        $sth->finish();
        return \@pk_notifs;	
}

##############################################
#   get_not_displayed_recipients
##############################################
# Function use to get mail addresses and status of 
# the recipients who have a different MDN status than "displayed"
# Use the pk identifiant of the mail
# 
# IN :-$dbh (+): the database connection
#     -$pk_mail (+): the identifiant of the stored mail
#
# OUT : @pk_notifs |undef
#      
##############################################
sub get_not_displayed_recipients {
        my $dbh = shift;
        my $pk_mail = shift;

        my $sth;
        my $pk;
        my $request = "SELECT recipient_notification FROM notification_table WHERE `pk_mail_notification` = '$pk_mail' AND `type_notification` = 'MDN' AND `status_notification` != 'displayed'";

        &do_log('debug2', 'Request For Message Table : : %s', $request);
        unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
                return undef;
        }
        unless ($sth->execute) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
        }
        my @pk_notif;
        my @pk_notifs;
        my $i = 0;
        while (@pk_notif = $sth->fetchrow_array){
                $pk_notifs[$i++] = $pk_notif[0];
        }
        $sth->finish();
        return @pk_notifs;
}

##############################################
#   get_pk_notifications
##############################################
# Function use a pk mail identifiant to get the list of corresponding 
# notification identifiants. 
# Use the pk identifiant of the mail.
# 
# IN :-$dbh (+): the database connection
#     -$pk_mail (+): the identifiant of the stored mail
#
# OUT : @pk_notifs |undef
#      
##############################################
sub get_pk_notifications {
        my $dbh = shift;
        my $pk_mail = shift;	

        my $sth;
        my $pk;
        my $request = "SELECT pk_notification FROM notification_table WHERE `pk_mail_notification` = '$pk_mail'";

        &do_log('debug2', 'Request For Message Table : : %s', $request);
        unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
                return undef;
        }
        unless ($sth->execute) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
        }
	my @pk_notif;
	my @pk_notifs;
	my $i = 0;
        while (@pk_notif = $sth->fetchrow_array){
		$pk_notifs[$i++] = $pk_notif[0];
	}
        $sth->finish();
        return @pk_notifs;
}

##############################################
#   get_pk_notification
##############################################
# Function use to get a specific notification identifiant 
# depending of the given message identifiant, the recipient name
# and the notification type.
# 
# IN :-$dbh (+): the database connection
#     -$id (+): the storage identifiant of the corresponding mail
#     -$recipient (+): the address of one of the list subscribers
#     -$type (+): the notification type (DSN | MDN)
#
# OUT : $pk |undef
#      
##############################################
sub get_pk_notification {
        my ($dbh, $id, $recipient, $type) = @_;

        my $sth;
        my $pk;
#        my $request = "SELECT pk_notification FROM notification_table WHERE `pk_mail_notification` = '$id' AND `recipient_notification` = '$recipient' AND `type_notification`= '$type'";
	do_log('trace',"eclaicir pourquoi le WHERE portait aussi sur le type ??? ");
        my $request = "SELECT pk_notification FROM notification_table WHERE `pk_mail_notification` = '$id' AND `recipient_notification` = '$recipient'";
        &do_log('debug2', 'Request For Message Table : : %s', $request);
        unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
                return undef;
        }
        unless ($sth->execute) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
        }

        my @pk_mail = $sth->fetchrow_array;
        $pk = $pk_mail[0];
        $sth->finish();
        return $pk;
}

##############################################
#   store_notification
##############################################
# Function used to add a notification entry 
# corresponding to a subscriber of a mail.
# One entry for each subscriber.
# The entry is added in the given table 
# using the given database connection. 
# The status value is fixed to waiting
#
# IN :-$dbh (+): the database connection
#     -$table (+): the given table to store
#     -$id (+): the mail identifiant of the initial mail
#     -$status (+): the current state of the recipient entry. 
#		    Will change after a notification reception for this recipient.
#     -$recipient (+): the mail address of the recipient
#     -$list (+): the list to which the mail has been initially sent
#     -$notif_type (+): the kind of notification representing this entry (DSN|MDN).
#
# OUT : $sth | undef
#      
##############################################
sub store_notification_to_be_removed{
	my ($dbh, $key_track,$id, $status, $recipient, $list, $robot, $notif_type) = @_;
	
	my $sth;
	my $request = sprintf "INSERT INTO notification_table (pk_mail_notification,recipient_notification,status_notification,type_notification,list_notification,robot_notification) VALUES (%s,%s,%s,%s,%s,%s)",$dbh->quote($id),$dbh->quote($recipient), $dbh->quote($status),$dbh->quote($notif_type),$dbh->quote($list),$dbh->quote($robot);
	
	&do_log('trace', 'Request For Notification Table : : %s', $request);
	unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement "%s": %s', $request, $dbh->errstr);
                return undef;
	}
	unless ($sth->execute()) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
	}
	return $sth;
}

##############################################
#   update_notification
##############################################
# Function used to update a notification entry 
# corresponding to a subscriber of a mail. This function
# is called when a mail report has been received.
# One entry for each subscriber.
# The entry is updated in the given table 
# using the given database connection. 
# The status value is changed according to the 
# report data.
#
# IN :-$dbh (+): the database connection
#     -$table (+): the given table to update
#     -$pk (+): the notification entry identifiant
#     -$msg_id (+): the report message-id
#     -$status (+): the new state of the recipient entry. 
#     -$date (+): the mail arrival date
#     -$notification_as_string : the DSN or the MDM message as string
#
# OUT : $sth | undef
#      
##############################################
sub update_notification_to_be_removed{
	my ($dbh, $msgid, $status, $date,$notification_as_string) = @_;

	my $sth;
	chomp $date;

	$notification_as_string = MIME::Base64::encode($notification_as_string);
    #    my $request = sprintf "UPDATE notification_table SET  `status_notification` = %s, `arrival_date_notification` = %s, `message_notification` = %s WHERE `message_id_notification` = %s AND list_notification = %s AND robot_notification = %s", $dbh->quote($status),$dbh->quote($date),$dbh->quote($notification_as_string);$dbh->quote($msgid),$dbh->quote($listname),$dbh->quote($robot);
    my $request = sprintf "UPDATE notification_table SET  `status_notification` = %s, `arrival_date_notification` = %s, `message_notification` = %s WHERE `message_id_notification` = %s AND list_notification = %s AND robot_notification = %s"; #$dbh->quote($status),$dbh->quote($date),$dbh->quote($notification_as_string);$dbh->quote($msgid),$dbh->quote($listname),$dbh->quote($robot);

        &do_log('debug2', 'Request For Notification Table : : %s', $request);
        unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement "%s": %s', $request, $dbh->errstr);
                return undef;
        }
        unless ($sth->execute()) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
        }
	return $sth;
}

##############################################
#   db_insert_message
##############################################
# Function used to add a message entry 
# corresponding to a new mail send to a list. This function
# is called when a mail has been received.
# One entry for each mail.
# The entry is added in the given table 
# creating a new database connection. 
#
# IN :-$message (+): the input message to store
#     -$robot (+): the robot correponding to the given message
#     -$list (+): the list to which the message has been initially sent
#
# OUT : 1 | undef
#      
##############################################
sub db_insert_message_to_be_removed{
    my ($message, $robot, $list) = @_;

    my $rcpt;
    my $hdr = $message->{'msg'}->head or &do_log('err', "Error : Extract header failed");
    my $cpt = $list->get_total();
    
    &do_log('debug2', "Message extracted  list name : %s  addresses number : %s", $list->{'name'}, $cpt);
    my $subject = $hdr->get('subject');    chomp($subject);
    my $send_date = $hdr->get('date');    chomp($send_date);
    my $msgid = $hdr->get('Message-Id')or &do_log('notice', "Error : Extract msgID failed");    chomp($msgid);
    my $content_type = $hdr->get('Content-Type');    chomp($content_type);
    &do_log('trace', "Message extracted : %s", $content_type);
 
    my $key_track = &tracking::next_tracking_key();
    
    unless($content_type =~ /.*delivery\-status.*/){

	#my $message_id = format_msg_id($msgid) or &do_log('err', "Error : Format msgID failed"); 
	#unless ($message_id) {
	#    &do_log('err', 'Notification message without message-id');
	#    return undef;
	#}
	
        my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
	unless ($dbh and $dbh->ping) {
		&do_log('err', "Error : Can't join database");
		return undef;
	}

	my $sth;

	for (my $user=$list->get_first_user(); $user; $user=$list->get_next_user()) {
	    my $to= lc($user->{'email'});
	    
	    &do_log('trace', 'Recipient Address :%s', $to );
	    unless ($sth = &store_notification($dbh, $key_track,$msgid, $status, $to, $list->{'name'},$robot,'')) {
		&do_log('err', 'Unable to execute message storage in notification table"%s"', $msgid);
		return undef;
	    }
	} 
	$sth -> finish;
	$dbh -> disconnect;
	&do_log('notice', 'Successful Mail Treatment :%s', $subject );
    }
    return 1;
}

##############################################
#   db_init_notification_table
##############################################
# Function used to initialyse notification table for each subscriber
# IN : 
#   listname
#   robot,
#   msgid  : the messageid of the original message
#   rcpt : a tab ref of recipients
#   reception_option : teh reception option of thoses subscribers
# OUT : 1 | undef
#      
##############################################
sub db_init_notification_table{

    my %params = @_;
    my $msgid =  $params{'msgid'}; chomp $msgid;
    my $listname =  $params{'listname'};
    my $robot =  $params{'robot'};
    my $reception_option =  $params{'reception_option'};
    my @rcpt =  @{$params{'rcpt'}};
    
    &do_log('debug2', "db_init_notification_table (msgid = %s, listname = %s, reception_option = %s",$msgid,$listname,$reception_option);
    &do_log('trace', "db_init_notification_table (msgid = %s, listname = %s, reception_option = %s",$msgid,$listname,$reception_option);

    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    unless ($dbh and $dbh->ping) {
	&do_log('err', "Error : Can't join database");
	return undef;
    }
    
    my $sth;
    
    foreach my $email (@rcpt){
	my $email= lc($email);
	
	&do_log('trace', 'Recipient Address :%s', $email );
#	unless ($sth = &store_notification($dbh, $msgid,$listname,$robot,$email,$reception_option)) {
#	    &do_log('err', 'Unable to execute message storage in notification table for message "%s"', $msgid);
#	    return undef;
#	}

	my $request = sprintf "INSERT INTO notification_table (message_id_notification,recipient_notification,reception_option_notification,list_notification,robot_notification) VALUES (%s,%s,%s,%s,%s)",$dbh->quote($msgid),$dbh->quote($email),$dbh->quote($reception_option),$dbh->quote($listname),$dbh->quote($robot);
	
	&do_log('trace', 'Request %s', $request);
	unless ($sth = $dbh->prepare($request)) {
                &do_log('err','Unable to prepare SQL statement "%s": %s', $request, $dbh->errstr);
                return undef;
	}
	unless ($sth->execute()) {
                &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
                return undef;
	}


    } 
    $sth -> finish;
    $dbh -> disconnect;
    return 1;
}

##############################################
#   db_insert_notification
##############################################
# Function used to add a notification entry 
# corresponding to a new report. This function
# is called when a report has been received.
# It build a new connection with the database
# using the default database parameter. Then it
# search the notification entry identifiant which 
# correspond to the received report. Finally it 
# update the recipient entry concerned by the report.
#
# IN :-$id (+): the identifiant entry of the initial mail
#     -$type (+): the notification entry type (DSN|MDN)
#     -$recipient (+): the list subscriber who correspond to this entry
#     -$msg_id (+): the report message-id
#     -$status (+): the new state of the recipient entry depending of the report data 
#     -$arrival_date (+): the mail arrival date.
#     -$notification_as_string : the DSN or the MDM as string
#
# OUT : 1 | undef
#      
##############################################
sub db_insert_notification {
    my ($notification_id, $type, $status, $arrival_date ,$notification_as_string  ) = @_;
    
    &do_log('debug2', "db_insert_notification  :notification_id : %s, type : %s, recipient : %s, msgid : %s, status :%s",$notification_id, $type, $status); 
    
    chomp $arrival_date;
    
    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    
    unless ($dbh and $dbh->ping) { 
	&do_log('err', "Error : Can't join database"); 
	return undef; 
    } 
    
    $notification_as_string = MIME::Base64::encode($notification_as_string);
    
    my $request = sprintf "UPDATE notification_table SET  `status_notification` = %s, `arrival_date_notification` = %s, `message_notification` = %s WHERE (pk_notification = %s)",$dbh->quote($status),$dbh->quote($arrival_date),$dbh->quote($notification_as_string),$dbh->quote($notification_id);

        my $request_trace = sprintf "UPDATE notification_table SET  `status_notification` = %s, `arrival_date_notification` = %s, WHERE (pk_notification = %s)",$dbh->quote($status),$dbh->quote($arrival_date),$dbh->quote($notification_id);

    &do_log('trace','db_insert_notification request_trace  %s', $request_trace);
    
    my $sth;
    
    unless ($sth = $dbh->prepare($request)) {
	&do_log('err','Unable to prepare SQL statement "%s": %s', $request, $dbh->errstr);
	return undef;
    }
    unless ($sth->execute()) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
	return undef;
    }
    
    $sth -> finish;
    $dbh -> disconnect;

    return 1;
}

##############################################
#   find_msg_key
##############################################
# Function used to get the key identificator of
# a mail by asking the database with an input message-id
# 
# IN :-$msgid (+): the input message-id
#     -$listname (+): the name of the list to which the mail
#			has been initially sent.
#
# OUT : $pk | undef
#      
##############################################
sub find_msg_key_to_be_removed{

    my $msgid = shift;	
    my $listname = shift;	
    my $robot = shift;

    my $pk;
    my $message_id = format_msg_id($msgid) or &do_log('err', "Error : Format msgID failed");

    return undef unless ($message_id);
    &do_log('trace', ' procedure à virer Message-Id Formated : %s', $message_id);

    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    unless ($dbh and $dbh->ping) {
          &do_log('err', "Error : Can't join database");
          return undef;
    }
    
    my $request = "SELECT pk_mail_notification FROM notification_table ORDER BY pk_mail_notification DESC LIMIT 1";
    
    my $sth;

    unless ($sth = $dbh->prepare($request)) {
	&do_log('err','Unable to prepare SQL statement %s : %s', $request, $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
	return undef;
    }
    
    my @pk_mail = $sth->fetchrow_array;
    $pk = $pk_mail[0];
    $sth->finish();
    $dbh -> disconnect;
    return ($pk+1); # should return 1 if table if empty
}

##############################################
#   find_notification_id_by_message
##############################################
# return the tracking_id find by recipeint,message-id,listname and robot
# tracking_id areinitialized by sympa.pl by List::distribute_msg
# 
# used by bulk.pl in order to set return_path when tracking is required.
#      
##############################################

sub find_notification_id_by_message{
    my $recipient = shift;	
    my $msgid = shift;	chomp $msgid;
    my $listname = shift;	
    my $robot = shift;

    do_log('debug2','find_notification_id_by_message(%s,%s,%s,%s)',$recipient,$msgid ,$listname,$robot );
    my $pk;

    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    unless ($dbh and $dbh->ping) {
          &do_log('err', "Error : Can't join database");
          return undef;
    }
    
    # the message->head method return message-id including <blabla@dom> where mhonarc return blabla@dom that's why we test both of them
    my $request = sprintf "SELECT pk_notification FROM notification_table WHERE ( recipient_notification = %s AND list_notification = %s AND robot_notification = %s AND (message_id_notification = %s OR CONCAT('<',message_id_notification,'>') = %s OR message_id_notification = %s ))", $dbh->quote($recipient),$dbh->quote($listname),$dbh->quote($robot),$dbh->quote($msgid),$dbh->quote($msgid),$dbh->quote('<'.$msgid.'>');
    
    my $sth;

    unless ($sth = $dbh->prepare($request)) {
	&do_log('err','Unable to prepare SQL statement %s : %s', $request, $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
	return undef;
    }
    
    my @pk_notifications = $sth->fetchrow_array;
    if ($#pk_notifications > 0){
	&do_log('err','Found more then one pk_notification maching  (recipient=%s,msgis=%s,listname=%s,robot%s)',$recipient,$msgid ,$listname,$robot );	
	# we should return undef...
    }
    $sth->finish();
    $dbh -> disconnect;
    return @pk_notifications[0];
}

##############################################
#   next_tracking_key 
##############################################
# OUT : return next unused tracking message key
#      
##############################################
sub next_tracking_key{


    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    unless ($dbh and $dbh->ping) {
          &do_log('err', "Error : Can't join database");
          return undef;
    }
    
    my $request = "SELECT pk_mail_notification FROM notification_table ORDER BY pk_mail_notification DESC LIMIT 1";
    
    my $sth;

    unless ($sth = $dbh->prepare($request)) {
	&do_log('err','Unable to prepare SQL statement %s : %s', $request, $dbh->errstr);
	return undef;
    }
    unless ($sth->execute) {
	&do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
	return undef;
    }
    
    my @pk_mail = $sth->fetchrow_array;
    $sth->finish();
    $dbh -> disconnect;
    return ($pk_mail[0]+1); # should return 1 if table if empty
}

##############################################
#   remove_notifications
##############################################
# Function use to remove notifications in argument to the given datatable
# 
# IN :-$dbh (+): the database connection
#    : $msgid : id of related message
#    : $listname
#    : $robot
#
# OUT : $sth | undef
#      
##############################################
sub remove_notifications{
    my $dbh = shift;
    my $msgid =shift;
    my $listname =shift;
    my $robot =shift;

    &do_log('debug2', 'Remove notification id =  %s, listname = %s, robot = %s', $msgid,$listname,$robot );
    my $sth;

    my $request = sprintf "DELETE FROM notification_table WHERE `message_id_notification` = %s AND list_notification = %s AND robot_notification = %s", $dbh->quote($msgid),$dbh->quote($listname),$dbh->quote($robot);


    &do_log('debug2', 'Request For Table : : %s', $request);
    unless ($sth = $dbh->prepare($request)) {
            &do_log('err','Unable to prepare SQL statement "%s": %s', $request, $dbh->errstr);
            return undef;
    }
    unless ($sth->execute()) {
            &do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
            return undef;
    }
    $sth -> finish;
    return 1;
}

1;
