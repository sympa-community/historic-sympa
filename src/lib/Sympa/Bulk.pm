# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 NAME

Sympa::Bulk - Bulk mailer functions

=head1 DESCRIPTION

This module provides bulk mailer functions.

=cut

package Sympa::Bulk;

use strict;
use warnings;
use constant MAX => 100_000;

use Carp;
use Encode;
use English qw(-no_match_vars);
use IO::Scalar;
use Mail::Address;
use MIME::WordDecoder;
use MIME::Parser;
use MIME::Base64;
use MIME::Charset;
use Sys::Hostname;
use URI::Escape;

use Sympa::Configuration;
use Sympa::Language;
use Sympa::List;

## Database and SQL statement handlers
my $sth;


# last message stored in spool, this global var is used to prevent multiple stored of the same message in spool table 
my $last_stored_message_key;

=head1 CLASS METHODS

=over

=item Sympa::Bulk->new(%parameters)

Creates a new L<Sympa::Bulk> object.

Parameters:

=over

=item C<base> => L<Sympa::Database>

=back

Return:

A new L<Sympa::Bulk> object, or I<undef>, if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	croak "missing base parameter" unless $params{base};
	croak "invalid base parameter" unless
		$params{base}->isa('Sympa::Database');

	my $self = {
		base => $params{base}
	};

	bless $self, $class;

	return $self;
}

=back

=head1 INSTANCE METHODS

=over

=item $bulk->next()

Get next packet to process, order is controled by priority_message, then by
priority_packet, then by creation date.

Packets marked as being sent with VERP will be treated last.
Next lock the packetb to prevent multiple proccessing of a single packet

=cut

sub next {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug', 'Bulk::next');

	# lock next packet
	my $lock = Sympa::Tools::get_lockname();

	## Only the first record found is locked, thanks to the "LIMIT 1" clause
	my $order_clause =
		"ORDER BY "                                 .
			"priority_message_bulkmailer ASC, " .
			"priority_packet_bulkmailer ASC, "  .
			"reception_date_bulkmailer ASC, "   .
			"verp_bulkmailer ASC";
	my $limit_oracle='';
	my $limit_sybase='';
	my $db_type = $self->{base}->get_type();
	if ($db_type eq 'mysql' ||$db_type eq 'Pg' || $db_type eq 'SQLite'){
		$order_clause .= ' LIMIT 1';
	} elsif ($db_type eq 'Oracle'){
		$limit_oracle = 'AND rownum<=1';
	} elsif ($db_type eq 'Sybase'){
		$limit_sybase = 'TOP 1';
	}

	# Select the most prioritary packet to lock.
	my $handle = $self->{base}->get_query_handle(
		"SELECT $limit_sybase "                         .
			"messagekey_bulkmailer AS messagekey, " .
			"packetid_bulkmailer AS packetid "      .
		"FROM bulkmailer_table "                        .
		"WHERE "                                        .
			"lock_bulkmailer IS NULL AND "          .
			"delivery_date_bulkmailer <= ? "        .
			$limit_oracle .
		$order_clause
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to get the most prioritary packet from database');
		return undef;
	}
	$handle->execute(int(time()));

	my $packet;
	unless($packet = $handle->fetchrow_hashref('NAME_lc')){
		return undef;
	}

	# Lock the packet previously selected.
	my $rows = $self->{base}->execute_query(
		"UPDATE bulkmailer_table "             .
		"SET lock_bulkmailer=? "               .
		"WHERE "                               .
			"messagekey_bulkmailer=? AND " .
			"packetid_bulkmailer=? AND "   .
			"lock_bulkmailer IS NULL",
		$lock,
		$packet->{'messagekey'},
		$packet->{'packetid'}
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to lock packet %s for message %s',$packet->{'packetid'}, $packet->{'messagekey'});
		return undef;
	}

	if ($rows < 0) {
		Sympa::Log::Syslog::do_log('err','Unable to lock packet %s for message %s, though the query succeeded',$packet->{'packetid'}, $packet->{'messagekey'});
		return undef;
	}
	unless ($rows) {
		Sympa::Log::Syslog::do_log('info','Bulk packet is already locked');
		return undef;
	}

	# select the packet that has been locked previously
	my $handle = $self->{base}->get_query_handle(
		"SELECT " .
			"messagekey_bulkmailer AS messagekey, "   .
			"messageid_bulkmailer AS messageid, "     .
			"packetid_bulkmailer AS packetid, "       .
			"receipients_bulkmailer AS receipients, " .
			"returnpath_bulkmailer AS returnpath, "   .
			"listname_bulkmailer AS listname, "       .
			"robot_bulkmailer AS robot, " .
			"priority_message_bulkmailer AS priority_message, " .
			"priority_packet_bulkmailer AS priority_packet, " .
			"verp_bulkmailer AS verp, " .
			"tracking_bulkmailer AS tracking, " .
			"merge_bulkmailer as merge, " .
			"reception_date_bulkmailer AS reception_date, " .
			"delivery_date_bulkmailer AS delivery_date " .
		"FROM bulkmailer_table WHERE lock_bulkmailer=? " .
		$order_clause
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve informations for packet %s of message %s',$packet->{'packetid'}, $packet->{'messagekey'});
		return undef;
	}
	$handle->execute($lock);

	my $result = $handle->fetchrow_hashref('NAME_lc');

    ## add objects
    my $robot_id = $result->{'robot'};
    my $listname = $result->{'listname'};
    my $robot;

    if ($robot_id and $robot_id ne '*') {
	$robot = Robot->new($robot_id);
    }
    if ($robot) {
	if ($listname and length $listname) {
	    $result->{'list_object'} = List->new($listname, $robot);
	}
	$result->{'robot_object'} = $robot;
    }
   
    return $result;
}

=item $bulk->remove($messagekey, $packetid)

Remove a packet from database by packet id. return undef if packet does not
exist

=cut

sub remove {
	my ($self, $messagekey, $packetid) = @_;
	Sympa::Log::Syslog::do_log('debug', "Bulk::remove(%s,%s)",$messagekey,$packetid);

	my $rows = $self->{base}->execute_query(
		"DELETE FROM bulkmailer_table " .
		"WHERE packetid_bulkmailer=? AND messagekey_bulkmailer=?",
		$packetid,
		$messagekey
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to delete packet %s of message %s', $packetid,$messagekey);
		return undef;
	}
	return $rows;
}

=item $bulk->messageasstring($messagekey)

FIXME.

=cut

# No longer used
sub messageasstring {
	my ($self, $messagekey) = @_;
	Sympa::Log::Syslog::do_log('debug', 'Bulk::messageasstring(%s)',$messagekey);

	my $handle = $self->{base}->get_query_handle(
		"SELECT message_bulkspool AS message " .
		"FROM bulkspool_table " .
		"WHERE messagekey_bulkspool = ?",
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve message %s text representation from database', $messagekey);
		return undef;
	}
	$handle->execute($messagekey);

	my $messageasstring = $handle->fetchrow_hashref('NAME_lc');

	unless ($messageasstring ){
		Sympa::Log::Syslog::do_log('err',"could not fetch message $messagekey from spool");
		return undef;
	}
	my $msg = MIME::Base64::decode($messageasstring->{'message'});
	unless ($msg){
		Sympa::Log::Syslog::do_log('err',"could not decode message $messagekey extrated from spool (base64)");
		return undef;
	}
	return $msg;
}

=item $bulk->message_from_spool($messagekey)

Fetch message from bulkspool_table by key.

=cut

# No longer used
sub message_from_spool {
	my ($self, $messagekey) = @_;
	Sympa::Log::Syslog::do_log('debug', '(messagekey : %s)',$messagekey);

	my $handle = $self->{base}->get_query_handle(
		"SELECT "                                                .
			"message_bulkspool AS message, "                 .
			"messageid_bulkspool AS messageid, "             .
			"dkim_d_bulkspool AS dkim_d,  "                  .
			"dkim_i_bulkspool AS dkim_i, "                   .
			"dkim_privatekey_bulkspool AS dkim_privatekey, " .
			"dkim_selector_bulkspool AS dkim_selector "      .
		"FROM bulkspool_table "                                  .
		"WHERE messagekey_bulkspool = ?",
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve message %s full data from database', $messagekey);
		return undef;
	}
	$handle->execute($messagekey);

	my $message_from_spool = $handle->fetchrow_hashref('NAME_lc');

	return {
		'messageasstring' => MIME::Base64::decode($message_from_spool->{'message'}),
		'messageid'       => $message_from_spool->{'messageid'},
		'dkim_d'          => $message_from_spool->{'dkim_d'},
		'dkim_i'          => $message_from_spool->{'dkim_i'},
		'dkim_selector'   => $message_from_spool->{'dkim_selector'},
		'dkim_privatekey' => $message_from_spool->{'dkim_privatekey'}
	};

}

## DEPRECATED: Use $message->personalize().
#sub merge_msg ($entity, $rcpt, $bulk, $data)

## DEPRECATED: Use Message::personalize_text().
##sub merge_data ($rcpt, $listname, $robot_id, $data, $body, \$message_output)


=item $bulk->store(%parameterss)

FIXME.

=cut

sub store {
    my %data = @_;
    
    my $message = $data{'message'};
    my $msg_id = $message->get_header('Message-Id');
    my $rcpts = $data{'rcpts'};
    my $from = $data{'from'};
    my $robot = Robot::clean_robot($data{'robot'}, 1); # maybe Site
    my $listname = $data{'listname'};
    my $priority_message = $data{'priority_message'};
    my $priority_packet = $data{'priority_packet'};
    my $delivery_date = $data{'delivery_date'};
    my $verp  = $data{'verp'};
    my $tracking  = $data{'tracking'};
    $tracking  = '' unless (($tracking  eq 'dsn')||($tracking  eq 'mdn'));
    $verp=0 unless($verp);
    my $merge  = $data{'merge'};
    $merge=0 unless($merge);
    my $dkim = $data{'dkim'};
    my $tag_as_last = $data{'tag_as_last'};

    #Sympa::Log::Syslog::do_log('trace',
    #    'Bulk::store(<msg>,rcpts: %s,from = %s,robot = %s,listname= %s,priority_message = %s, delivery_date= %s,verp = %s, tracking = %s, merge = %s, dkim: d= %s i=%s, last: %s)',
    #    $rcpts, $from, $robot, $listname, $priority_message, $delivery_date,
    #    $verp,$tracking, $merge, $dkim->{'d'}, $dkim->{'i'}, $tag_as_last);

    $priority_message = $robot->sympa_priority unless $priority_message;
    $priority_packet = $robot->sympa_packet_priority unless $priority_packet;
    
    my $messageasstring = $message->to_string;
    my $message_sender = $message->get_sender_email();

    # first store the message in spool_table 
    # because as soon as packet are created bulk.pl may distribute the
    # $last_stored_message_key is a global var used in order to detect if a message as been already stored    
    my $message_already_on_spool ;
    my $bulkspool = new Sympaspool ('bulk');

    if (defined $last_stored_message_key and
	defined $message->{'messagekey'} and
	$message->{'messagekey'} eq $last_stored_message_key) {
	$message_already_on_spool = 1;
    } else {
	my $lock = $$.'@'.hostname() ;
	if ($message->{'messagekey'}) {
	    # move message to spool bulk and keep it locked
	    $bulkspool->update(
		{'messagekey' => $message->{'messagekey'}},
		{   'messagelock' => $lock, 'spoolname' => 'bulk',
		    'message' => $messageasstring}
	    );
	} else {
	    $message->{'messagekey'} = $bulkspool->store(
		$messageasstring,
		{   'dkim_d'=>$dkim->{d},
		    'dkim_i'=>$dkim->{i},
		    'dkim_selector'=>$dkim->{selector},
		    'dkim_privatekey'=>$dkim->{private_key},
		    'dkim_header_list'=>$dkim->{header_list}
		},
		$lock
	    );
	    unless ($message->{'messagekey'}) {
		Sympa::Log::Syslog::do_log('err',
		    'Could not store message in spool distribute. Message lost?'
		);
		return undef;
	    }
	}
	$last_stored_message_key = $message->{'messagekey'};
	
	#log in stat_table to make statistics...
	my $robot_domain = $robot->domain;
	unless (index($message_sender, "$robot_domain\@") >= 0) {
	    #ignore messages sent by robot
	    unless (index($message_sender, "$listname-request") >= 0) {
		#ignore messages of requests			
		Sympa::Log::Syslog::db_stat_log({
		    'robot' => $robot->name, 'list' => $listname,
		    'operation' => 'send_mail',
		    'parameter' => $message->{'size'},
		    'mail' => $message_sender,
		    'client' => '', 'daemon' => 'sympa.pl'
		});
	    }
	}
    }

    my $current_date = int(time);
    
    # second : create each recipient packet in bulkpacket_table
    my $type = ref $rcpts;

    unless (ref $rcpts) {
	my @tab = ($rcpts);
	my @tabtab;
	push @tabtab, \@tab;
	$rcpts = \@tabtab;
    }

    my $priority_for_packet;
    my $already_tagged = 0;
    my $packet_rank = 0; # Initialize counter used to check whether we are copying the last packet.
    foreach my $packet (@{$rcpts}) {
	$priority_for_packet = $priority_packet;
	if($tag_as_last && !$already_tagged){
	    $priority_for_packet = $priority_packet + 5;
	    $already_tagged = 1;
	}
	$type = ref $packet;
	my $rcptasstring ;
	if  (ref $packet eq 'ARRAY'){
	    $rcptasstring  = join ',',@{$packet};
	}else{
	    $rcptasstring  = $packet;
	}
	my $packetid =  &tools::md5_fingerprint($rcptasstring);
	my $packet_already_exist;
	if (ref $listname eq 'List') {
	    $listname = $listname->name;
	}
	if ($message_already_on_spool) {
	    ## search if this packet is already in spool database : mailfile may perform multiple submission of exactly the same message 
	    unless ($sth = SDM::do_prepared_query(
		q{SELECT count(*)
		  FROM bulkpacket_table
		  WHERE messagekey_bulkpacket = ? AND packetid_bulkpacket = ?},
		$message->{'messagekey'}, $packetid
	    )) {
		Sympa::Log::Syslog::do_log('err','Unable to check presence of packet %s of message %s in database', $packetid, $message->{'messagekey'});
		return undef;
	    }	
	    $packet_already_exist = $sth->fetchrow;
	    $sth->finish();
	}
	
	if ($packet_already_exist) {
	    Sympa::Log::Syslog::do_log('err','Duplicate message not stored in bulmailer_table');
	    
	}else {
	    unless (SDM::do_prepared_query(
		q{INSERT INTO bulkpacket_table
		  (messagekey_bulkpacket, messageid_bulkpacket,
		   packetid_bulkpacket,
		   recipients_bulkpacket, returnpath_bulkpacket,
		   robot_bulkpacket,
		   listname_bulkpacket,
		   verp_bulkpacket, tracking_bulkpacket, merge_bulkpacket,
		   priority_message_bulkpacket, priority_packet_bulkpacket,
		   reception_date_bulkpacket, delivery_date_bulkpacket)
		  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
		$message->{'messagekey'}, $msg_id,
		$packetid,
		$rcptasstring, $from,
		$robot->name, ## '*' for Site
		$listname,
		$verp, $tracking, $merge,
		$priority_message, $priority_for_packet,
		$current_date, $delivery_date
	    )) {
		Sympa::Log::Syslog::do_log('err',
		    'Unable to add packet %s of message %s to database spool',
		    $packetid, $msg_id
		);
		return undef;
	    }
	}
	$packet_rank++;
    }
    $bulkspool->unlock_message($message->{'messagekey'});
    return 1;
}

=item $bulk->purge_bulkspool()

Remove file that are not referenced by any packet.

Parameters:

None.

=cut

sub purge_bulkspool {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug', 'purge_bulkspool');

	my $handle = $self->{base}->get_query_handle(
		"SELECT messagekey_bulkspool AS messagekey "               .
		"FROM bulkspool_table LEFT JOIN bulkmailer_table "         .
			"ON messagekey_bulkspool = messagekey_bulkmailer " .
		"WHERE messagekey_bulkmailer IS NULL AND lock_bulkspool = 0"
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to check messages unreferenced by packets in database');
		return undef;
	}
	$handle->execute();

	my $count = 0;
	while (my $key = $handle->fetchrow_hashref('NAME_lc')) {
		if ($self->remove_bulkspool_message('bulkspool',$key->{'messagekey'}) ) {
			$count++;
		} else {
			Sympa::Log::Syslog::do_log('err','Unable to remove message (key = %s) from bulkspool_table',$key->{'messagekey'});
		}
	}

	return $count;
}

=item $bulk->remove_bulkspool_message($spool, $messagekey)

FIXME.

=cut

sub remove_bulkspool_message {
	my ($self, $spool, $messagekey) = @_;

	my $table = $spool.'_table';
	my $key = 'messagekey_'.$spool;

	my $rows = $self->{base}->execute_query(
		"DELETE FROM $table WHERE $key=?",
		$$messagekey
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to delete %s %s from %s',$table,$key,$messagekey);
		return undef;
	}

	return 1;
}

=item $bulk->get_remaining_packets_count()

Return the number of remaining packets in the bulkmailer table.

Parameters:

None.

=cut

sub get_remaining_packets_count {
	my ($self) = @_;
	Sympa::Log::Syslog::do_log('debug3', 'get_remaining_packets_count');

	my $handle = $self->{base}->get_query_handle(
		"SELECT COUNT(*) " .
		"FROM bulkmailer_table " .
		"WHERE lock_bulkmailer IS NULL"
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to count remaining packets in bulkmailer_table');
		return undef;
	}
	$handle->execute();

	my @result = $handle->fetchrow_array();

	return $result[0];
}

=item $bulk->there_is_too_much_remaining_packets($max)

Returns a true value if the number of remaining packets in the bulkmailer
table exceeds given maximum.

Parameters:

None.

=cut

sub there_is_too_much_remaining_packets {
	my ($self, $max) = @_;
	Sympa::Log::Syslog::do_log('debug3', 'there_is_too_much_remaining_packets');
	my $remaining_packets = $self->get_remaining_packets_count();
	if ($remaining_packets > $max) {
		return $remaining_packets;
	} else {
		return 0;
	}
}

=item $bulk->get_db_random()

This function returns $random which is stored in the database.

Parameters:

None.

Return value:

The random stored in the database, or I<undef> if something went wrong.

=cut

sub get_db_random {
	my ($self) = @_;

	my $handle = $self->{base}->get_query_handle(
		"SELECT random FROM fingerprint_table"
	);
	unless ($handle) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve random value from fingerprint_table');
		return undef;
	}
	$handle->execute();
	my $random = $handle->fetchrow_hashref('NAME_lc');

	return $random;

}

=item $bulk->init_db_random()

This function initializes $random used in get_fingerprint if there is no value
in the database.

Parameters:

None.

Return value:

The random initialized in the database, or I<undef> if something went wrong.

=cut

sub init_db_random {
	my ($self) = @_;

	my $range = 89999999999999999999;
	my $minimum = 10000000000000000000;

	my $random = int(rand($range)) + $minimum;

	my $rows = $self->{base}->execute_query(
		"INSERT INTO fingerprint_table VALUES ($random)",
	);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to set random value in fingerprint_table');
		return undef;
	}
	return $random;
}

=back

=cut

1;
