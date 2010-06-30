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


our $message_table = "mail_table";
our $notif_table = "notification_table";
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
#     -$table (+): the database table to use
#     -$id (+): the message-id of the mail
#     -$listname (+): the name of the list to which the 
#		      mail has been sent
#     -$robot : the robot of the list
#
# OUT : $pk |undef
#      
##############################################
sub get_pk_message {
	my ($dbh, $table, $id, $listname,$robot) = @_;

        # xxx $table = "mail_table";
	my $sth;
	my $pk;
	my $request = "SELECT pk_mail FROM $table WHERE `message_id_mail` = '$id' AND `list_mail` = '$listname' AND `robot_mail` = '$robot'";

        &do_log('trace', 'Request For Message Table : : %s', $request);

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
        # my $request = "SELECT COUNT(*) FROM $notif_table WHERE `pk_mail_notification` = '$pk_mail' AND `type_notification` = 'DSN'";
	my $request = "SELECT COUNT(*) FROM $notif_table WHERE `pk_mail_notification` = '$pk_mail'";

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

        my $pk_mail; 

	unless($pk_mail = find_msg_key($msgid, $listname,$robot)) {
	    &do_log('err', "Unable to get the pk identificator for message %s list %s robot %s", $msgid,$listname,$robot);
	    return undef;
	}

        &do_log('debug2', 'get_recipients_status  %s', $pk_mail);

	my $dbh = &List::db_get_handler();

	## Check database connection
	unless ($dbh and $dbh->ping) {
	    return undef unless &List::db_connect();
	}
	
        my $sth;
        my $pk;

        my $request = "SELECT recipient_notification AS recipient, status_notification AS status, arrival_date_notification AS arrival_date, type_notification as type, message_notification as notification_message FROM $notif_table WHERE `pk_mail_notification` = '$pk_mail'";

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
        my $request = "SELECT recipient_notification FROM $notif_table WHERE `pk_mail_notification` = '$pk_mail' AND `type_notification` = 'MDN' AND `status_notification` != 'displayed'";

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
        my $request = "SELECT pk_notification FROM $notif_table WHERE `pk_mail_notification` = '$pk_mail'";

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
#     -$table (+): the given table to ask
#     -$id (+): the storage identifiant of the corresponding mail
#     -$recipient (+): the address of one of the list subscribers
#     -$type (+): the notification type (DSN | MDN)
#
# OUT : $pk |undef
#      
##############################################
sub get_pk_notification {
        my ($dbh, $table, $id, $recipient, $type) = @_;

        my $sth;
        my $pk;
#        my $request = "SELECT pk_notification FROM $table WHERE `pk_mail_notification` = '$id' AND `recipient_notification` = '$recipient' AND `type_notification`= '$type'";
	do_log('trace',"eclaicir pourquoi le WHERE portait aussi sur le type ??? ");
        my $request = "SELECT pk_notification FROM $table WHERE `pk_mail_notification` = '$id' AND `recipient_notification` = '$recipient'";
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
#   store_message
##############################################
# Function use to store mail informations in
# the given table using the given database connection. 
# 
# IN :-$dbh (+): the database connection
#     -$table (+): the given table to store
#     -$id (+): the message-id of the mail
#     -$from (+): the sender address of the mail
#     -$date (+): the sending date
#     -$subject (+): the subject of the mail
#     -$list (+): the diffusion list to which the mail has been initially sent
#     -$robot (+): the robot of diffusion list to which the mail has been initially sent
#
# OUT : 1 |undef
#      
##############################################

sub store_message{
	my ($dbh, $id, $from, $date, $subject, $list,$robot) = @_;
	
	&do_log('debug', "store_message_DB ($id, $from, $date,$subject,$list, $robot)");
	my $sth;
	my $request = sprintf "INSERT INTO mail_table (message_id_mail,from_mail,date_mail,subject_mail,list_mail,robot_mail)VALUES (%s, %s, %s, %s, %s, %s)", $dbh->quote($id),$dbh->quote($from),$dbh->quote($date),$dbh->quote($subject),$dbh->quote($list),$dbh->quote($robot);
	
	&do_log('debug', 'Request For Message Table : : %s', $request);
	unless ($sth = $dbh->prepare($request)) {
		&do_log('err','Unable to prepare SQL statement : %s', $dbh->errstr);
        	return undef;
	}
	unless ($sth->execute()) {
        	&do_log('err','Unable to execute SQL statement "%s" : %s', $request, $dbh->errstr);
        	return undef;
	}
        $sth->finish();
	return 1; 
}

##############################################
#   store_notif_DB
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
#     -$address (+): the mail address of the subscriber
#     -$list (+): the list to which the mail has been initially sent
#     -$notif_type (+): the kind of notification representing this entry (DSN|MDN).
#
# OUT : $sth | undef
#      
##############################################
sub store_notif_DB{
	my ($dbh, $id, $status, $address, $list, $robot, $notif_type) = @_;
	
	my $sth;
	my $request = sprintf "INSERT INTO notification_table (pk_mail_notification,recipient_notification,status_notification,type_notification,list_notification,robot_notification) VALUES (%s,%s,%s,%s,%s,%s)",$dbh->quote($id),$dbh->quote($address), $dbh->quote($status),$dbh->quote($notif_type),$dbh->quote($list),$dbh->quote($robot);
	
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
#   update_notif_table
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
sub update_notif_table{
	my ($dbh, $pk, $msg_id, $status, $date,$notification_as_string) = @_;

	my $sth;

	chomp $date;

	$notification_as_string = MIME::Base64::encode($notification_as_string);
        my $request = "UPDATE notification_table SET `message_id_notification` = '$msg_id', `status_notification` = '$status', `arrival_date_notification` = '$date', `message_notification` = '$notification_as_string' WHERE pk_notification = '$pk'";

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
sub db_insert_message{
    my ($message, $robot, $list) = @_;

    my $rcpt;
    my $hdr = $message->{'msg'}->head or &do_log('err', "Error : Extract header failed");
    my $cpt = $list->get_total();
    
    &do_log('debug2', "Message extracted  list name : %s  addresses number : %s", $list->{'name'}, $cpt);
    my $subject = $hdr->get('subject');    chomp($subject);
    my $send_date = $hdr->get('date');    chomp($send_date);
    my $row_msgid = $hdr->get('Message-Id')or &do_log('notice', "Error : Extract msgID failed");    chomp($row_msgid);
    my $content_type = $hdr->get('Content-Type');    chomp($content_type);
    &do_log('trace', "Message extracted : %s", $content_type);
 
    my $disposition_notif = $hdr->get('Disposition-Notification-To');
    if ($disposition_notif) {
	&do_log('debug', "Disposition-Notification = $disposition_notif");
    }else{ 
	&do_log('debug', "Disposition-Notification Not Asked");
    }
    chomp($disposition_notif);
 
    my $row_from = $hdr->get('from');    chomp($row_from);
    &do_log('trace', "Message extracted : %s", $row_from);

    my $msg_string = $message->{'msg'}->as_string;
    &do_log('trace', 'string message : %s', $msg_string);

    unless($content_type =~ /.*delivery\-status.*/){

	my $message_id = format_msg_id($row_msgid) or &do_log('err', "Error : Format msgID failed"); 
	unless ($message_id) {
	    &do_log('err', 'Notification message without message-id');
	    return undef;
	}
	
	my $from_address = format_from_address($row_from) or &do_log('err', "Error : Format From address failed"); 
	&do_log('trace', 'From Address Format : %s', $from_address);
	
        my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
	unless ($dbh and $dbh->ping) {
		&do_log('err', "Error : Can't join database");
		return undef;
	}
	do_log('trace',"call store_message");
	unless (&tracking::store_message($dbh, $message_id, $from_address, $send_date, $subject, $list->{'name'},$robot)) {
                &do_log('err', 'Unable to execute message storage in mail table "%s"', $message_id);
                return undef;
	}

	my $pk_message;
	unless ($pk_message = &get_pk_message($dbh, 'mail_table', $message_id, $list->{'name'},$robot )){
                &do_log('err', 'Unable to execute message key request on message : "%s"', $message_id);
                return undef;
	}
	do_log('trace',"pk_message :$pk_message");
	my $sth;

	for (my $user=$list->get_first_user(); $user; $user=$list->get_next_user()) {
	    my $to= lc($user->{'email'});
	    #	foreach my $to (@to_addresses) {
	    
	    &do_log('trace', 'Recipient Address :%s', $to );
	    unless ($sth = &store_notif_DB($dbh, $pk_message, $status, $to, $list->{'name'},$robot,'')) {
		&do_log('err', 'Unable to execute message storage in notification table"%s"', $message_id);
		return undef;
	    }
            # what is usage for the following block ??? 
	    #if(defined $disposition_notif) {
            #		unless ($sth = &store_notif_DB($dbh, $pk_message, $status, $to, $list->{'name'},$robot,'MDN')) {
	    #	    &do_log('err', 'Unable to execute message storage in notification table"%s"', $message_id);
            #		    return undef;
	    #	}
	    #}
	} 
	$sth -> finish;
	$dbh -> disconnect;
	&do_log('notice', 'Successful Mail Treatment :%s', $subject );
    }
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
	my ($id, $type, $recipient, $msg_id, $status, $arrival_date ,$notification_as_string  ) = @_;

        my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});

        unless ($dbh and $dbh->ping) { &do_log('err', "Error : Can't join database"); return undef; } my $pk_notif; unless
                ($pk_notif = get_pk_notification($dbh,
                "notification_table", $id, $recipient, $type)) {
                &do_log('err', 'Unable to get notification
                identificator : "%s"', $msg_id); return undef; }
                &do_log('debug2', "pk_notif value founded : %s",
                $pk_notif); my $sth;

        unless ($sth = update_notif_table($dbh, $pk_notif, $msg_id, $status, $arrival_date, $notification_as_string ) ) {
                &do_log('err', 'Unable to update the notification table : "%s"', $msg_id);
                return undef;
        }
        $sth -> finish;
        $dbh -> disconnect;
        &do_log('notice', 'Successful Notification Treatment :%s', $msg_id);
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
sub find_msg_key{

    my $msgid = shift;	
    my $listname = shift;	
    my $robot = shift;

    my $pk;
    my $message_id = format_msg_id($msgid) or &do_log('err', "Error : Format msgID failed");

    return undef unless ($message_id);
    &do_log('debug2', 'Message-Id Formated : %s', $message_id);

    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    unless ($dbh and $dbh->ping) {
          &do_log('err', "Error : Can't join database");
          return undef;
    }
    unless($pk = &get_pk_message($dbh, "mail_table", $message_id, $listname,$robot)) {
          &do_log('err', "Unable to get the pk identificator of the message %s", $message_id);
          return undef;
    }
    $dbh -> disconnect;
    return $pk;
}


##############################################
#   get_delivered_info
##############################################
# Function use to get all the tracking informations of an msg-id.
# Informations are return as a string.
# 
# IN :-$msgid (+): the given message-id
#     -$listname (+): the name of the list to which the mail has initially been sent.
#
# OUT : $infos | undef
#      
##############################################
sub get_delivered_info_to_be_removed{
	
    my $msgid = shift;
    my $listname = shift;
    my $robot=shift;

    my $pkmsg;
    my @pk_notifs;
    my @recipients;
    my @recipients2;
    my $infos = "Unusual Recipients Deliveries : ";
    my $tmp_infos = "";
    my $nb_rcpt;

    &do_log('debug', "get_delivered_info_to_be_removed (%s,%s)", $msgid,$listname);
    

    unless($pkmsg = find_msg_key($msgid, $listname,$robot)) {
	&do_log('err', "Unable to get the pk identificator of the message %s", $msgid);
       return undef;
    }
    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    unless ($dbh and $dbh->ping) {
         &do_log('err', "Error : Can't join database");
         return undef;
    }

    #unless(@pk_notifs = get_pk_notifications($dbh, $pkmsg)){
    #   &do_log('err', "Unable to get the pk identificators of the notifications for message : %s", $msgid);
    #   return undef;
    #}
    #&do_log('debug2', "PK notifications : %s", @pk_notifs);
    #foreach my $pk_notif (@pk_notifs){
    #   &do_log('debug2', "PK notifications founded : %s", $pk_notif);
    #}
    unless($nb_rcpt = get_recipients_number($dbh, $pkmsg)){
       &do_log('err', "Unable to get number of recipients for message : %s", $msgid);
       return undef;
    }

    unless(@recipients = get_undelivered_recipients($dbh, $pkmsg)){
       &do_log('err', "Unable to get the pk identificators of the notifications for message : %s", $msgid);
       return undef;
    }
    my $i = 0;
    foreach my $recipient (@recipients){
	if( ($i%2) == 0){
		&do_log('trace', "recipient : %s", $recipient);
		$tmp_infos .= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<li>ADDRESS : <em>".$recipient."</em>";
	}
	else{
		&do_log('trace', "status : %s", $recipient);
		$tmp_infos .= "&nbsp;&nbsp;&nbsp;&nbsp;STATUS : <em>".$recipient."</em></li>";
	} 
	$i++;
    }
    $i = $i/2;
    $infos .= "<strong>".$i."/".$nb_rcpt."</strong><br />".$tmp_infos;
    
    my $j = 0;
    if(@recipients2 = get_not_displayed_recipients($dbh, $pkmsg)){
        $infos .= "<br /><br />Recipients who did not read the message yet (or which has refused to send back a notification) :    ";
	$tmp_infos = "";
    	foreach my $recipient (@recipients2){
            &do_log('trace', "recipient : %s", $recipient);
            $tmp_infos .= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<li>ADDRESS : <em>".$recipient."</em></li>";
	    $j++;
	}
    $infos .= "<strong>".$j."/".$nb_rcpt."</strong><br />".$tmp_infos;
    }
    $dbh -> disconnect;
    return $infos;
 }

##############################################
#   remove_message
##############################################
# Function use to remove the message and the corresponding notifications.
# 
# IN :-$msgid (+): the given message-id
#     -$listname (+): the name of the list to which the mail has initially been sent.
#
# OUT : 1 | undef
#      
##############################################
sub remove_message{
    my $msgid = shift;
    my $listname = shift;
    my $robot = shift;

    my $pkmsg;
    my @pk_notifs;

   
    unless($pkmsg = find_msg_key($msgid, $listname,$robot)) {
       &do_log('err', "Unable to get the pk identificator of the message %s", $msgid);
       return undef;
    }
    my $dbh = connection($Conf::Conf{'db_name'}, $Conf::Conf{'db_host'}, $Conf::Conf{'db_port'}, $Conf::Conf{'db_user'}, $Conf::Conf{'db_passwd'});
    unless ($dbh and $dbh->ping) {
         &do_log('err', "Error : Can't join database");
         return undef;
    }
    unless(@pk_notifs = get_pk_notifications($dbh, $pkmsg)) {
        &do_log('err', "Unable to get the pk identificators of notifications corresponding to the message %s", $msgid);
	return undef;
    }
    unless(remove_entry($dbh, "mail", $pkmsg)) {
        &do_log('err', "Unable to remove %s", $pkmsg);
	return undef;
    }
    unless(remove_entries($dbh, "notification", @pk_notifs)) {
        &do_log('err', "Unable to remove %s", @pk_notifs);
	return undef;
    }
    $dbh -> disconnect;
    return 1;
}

##############################################
#   remove_entry
##############################################
# Function use to remove the entry in argument to the given datatable
# 
# IN :-$dbh (+): the database connection
#     -$table (+): the given table to update
#     -$pk (+): the entry identifiant
#
# OUT : $sth | undef
#      
##############################################
sub remove_entry{
    my $dbh = shift;
    my $table = shift;
    my $pk = shift;

    my $sth;
    my $table_name = $table."_table";
    my $pk_header = "pk_".$table;
    my $request = "DELETE FROM $table_name WHERE `$pk_header` = '$pk'";

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

##############################################
#   remove_entries
##############################################
# Function use to remove several entries in argument to the given datatable
# 
# IN :-$dbh (+): the database connection
#     -$table (+): the given table to update
#     -@pk (+): entry identifiants
#
# OUT : $sth | undef
#      
##############################################
sub remove_entries{
    my ($dbh, $table, @pks) = @_;

    foreach my $pk (@pks) {
    	unless(remove_entry($dbh, $table, $pk)){
            &do_log('err','Unable to remove entries; error on "%s"', $pk);
            return undef;
	}
    }
    return 1;
}

1;
