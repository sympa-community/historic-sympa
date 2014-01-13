# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4:textwidth=78
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997-2011 Comite Reseau des Universites
# Copyright (c) 2011-2014 GIP RENATER
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

package Sympaspool;

use strict;
#use Carp; # not yet used
#require Encode; # not used
use Exporter;
#use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN); # no longer used
use Mail::Address;
use MIME::Base64;
#use POSIX; # not used
use Sys::Hostname qw(hostname);
# tentative
use Data::Dumper;

use Message;
use SDM;

our @ISA = qw(Exporter);

## Database and SQL statement handlers
my ($sth, @sth_stack);


## Creates an object.
sub new {
    Sympa::Log::Syslog::do_log('debug2', '(%s, %s, %s)', @_);
    my($pkg, $spoolname, $selection_status, %opts) = @_;

    my $self;

    unless ($spoolname =~ /^(auth)|(bounce)|(digest)|(bulk)|(expire)|(mod)|(msg)|(archive)|(automatic)|(subscribe)|(signoff)|(topic)|(validated)|(task)$/){
Sympa::Log::Syslog::do_log('err','internal error unknown spool %s',$spoolname);
	return undef;
    }
    unless ($selection_status and
	($selection_status eq 'bad' or $selection_status eq 'ok')) {
	$selection_status = 'ok';
    }

    $self = bless {
	'spoolname'        => $spoolname,
	'selection_status' => $selection_status,
    } => $pkg;
    $self->{'selector'} = $opts{'selector'} if $opts{'selector'};
    $self->{'sortby'}   = $opts{'sortby'} if $opts{'sortby'};
    $self->{'way'}      = $opts{'way'} if $opts{'way'};

    return $self;
}

# total spool_table count : not object oriented, just a subroutine 
sub global_count {

    my $message_status = shift;

    push @sth_stack, $sth;
    $sth = &SDM::do_query ("SELECT COUNT(*) FROM spool_table where message_status_spool = '".$message_status."'");

    my @result = $sth->fetchrow_array();
    $sth->finish();
    $sth = pop @sth_stack;

    return $result[0];
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

    # hash field->value used as filter WHERE sql query
    my $selector = $data->{'selector'} || $self->{'selector'};

    # the list of field to select. possible values are :
    #    -  a comma separated list of field to select. 
    #    -  '*'  is the default .
    #    -  '*_but_message' mean any field except message which may be huge
    #       and unusefull while listing spools
    #    - 'count' mean the selection is just a count.
    # should be used mainly to select all but 'message' that may be huge and
    # may be unusefull
    my $selection=$data->{'selection'};

    # for pagination, start fetch at element number = $offset;
    my $offset = $data->{'offset'};

    # for pagination, limit answers to $page_size
    my $page_size = $data->{'page_size'};

    my $orderby = $data->{'sortby'} || $self->{'sortby'};  # sort
    my $way = $data->{'way'} || $self->{'way'};            # asc or desc 

    my $sql_where = _sqlselector($selector);
    if ($self->{'selection_status'} eq 'bad') {
	$sql_where = $sql_where." AND message_status_spool = 'bad' " ;
    }else{
	$sql_where = $sql_where." AND message_status_spool <> 'bad' " ;
    }
    $sql_where =~s/^\s*AND//;

    my $statement ;
    if ($selection eq 'count'){
	# just return the selected count, not all the values
	$statement = 'SELECT COUNT(*) ';
    }else{
	$statement = 'SELECT '.&_selectfields($selection);
    }

    $statement = $statement . sprintf " FROM spool_table WHERE %s AND spoolname_spool = %s ",$sql_where,&SDM::quote($self->{'spoolname'});

    if ($orderby) {
	$statement = $statement. ' ORDER BY '.$orderby.'_spool ';
	$statement = $statement. ' DESC' if ($way eq 'desc') ;
    }
    if ($page_size) {
	$statement .= SDM::get_limit_clause(
	    {'offset' => $offset, 'rows_count' => $page_size}
	);
    }

    push @sth_stack, $sth;
    unless ($sth = &SDM::do_query($statement)) {
	$sth = pop @sth_stack;
	return undef;
    }
    if($selection eq 'count') {
	my @result = $sth->fetchrow_array();
	$sth->finish;
	$sth = pop @sth_stack;
	return $result[0];
    }else{
	my @messages;
	while (my $message = $sth->fetchrow_hashref('NAME_lc')) {
	    $message->{'messageasstring'} = MIME::Base64::decode($message->{'message'}) if ($message->{'message'}) ;
	    $message->{'listname'} = $message->{'list'}; # duplicated because "list" is a tt2 method that convert a string to an array of chars so you can't test  [% IF  message.list %] because it is always defined!!!
	    $message->{'status'} = $self->{'selection_status'}; 
	    $message->{'spoolname'} = $self->{'spoolname'};
	    push @messages, $message;

	    last if $page_size and $page_size <= scalar @messages;
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
    Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
    my $self = shift;

    my $sql_where = _sqlselector($self->{'selector'});

    if ($self->{'selection_status'} eq 'bad') {
	$sql_where = $sql_where." AND message_status_spool = 'bad' " ;
    }else{
	$sql_where = $sql_where." AND message_status_spool <> 'bad' " ;
    }
    $sql_where =~ s/^\s*AND//;

    my $lock = $$.'@'.hostname(); 
    my $epoch=time; # should we use milli or nano seconds ? 

    push @sth_stack, $sth;

    my $messagekey;
    while (1) {
	unless ($sth = SDM::do_query(
	    q{SELECT messagekey_spool FROM spool_table
	      WHERE messagelock_spool IS NULL AND spoolname_spool = %s AND
		    (priority_spool <> 'z' OR priority_spool IS NULL) AND %s
	      ORDER by priority_spool, date_spool
	      %s},
	    SDM::quote($self->{'spoolname'}), $sql_where,
	    SDM::get_limit_clause({'rows_count' => 1})
	)) {
	    Sympa::Log::Syslog::do_log('err', 'Could not search spool %s',
			 $self->{'spoolname'});
	    $sth = pop @sth_stack;
	    return undef;
	}
	$messagekey = $sth->fetchrow_array();
	$sth->finish();

	unless (defined $messagekey) { # spool is empty
	    $sth = pop @sth_stack;
	    return undef;
	}

	unless ($sth = &SDM::do_prepared_query(
	    q{UPDATE spool_table
	      SET messagelock_spool = ?, lockdate_spool = ?
	      WHERE messagekey_spool = ? AND messagelock_spool IS NULL},
	    $lock, $epoch, $messagekey
	)) {
	    Sympa::Log::Syslog::do_log('err', 'Could not update spool %s',
			 $self->{'spoolname'});
	    $sth = pop @sth_stack;
	    return undef;
	}
	unless ($sth->rows) { # locked by another process?  retry.
	    next;
	}
	last;
    }

    unless ($sth = &SDM::do_prepared_query(
	sprintf(
	    q{SELECT %s
	      FROM spool_table
	      WHERE messagekey_spool = ? AND messagelock_spool = ?},
	    &_selectfields()
	), $messagekey, $lock
    )) {
	Sympa::Log::Syslog::do_log('err', 'Could not search message previously locked');
	$sth = pop @sth_stack;
	return undef;
    }
    my $message = $sth->fetchrow_hashref('NAME_lc');
    $sth->finish();

    $sth = pop @sth_stack;

    unless ($message and $message->{'message'}){
Sympa::Log::Syslog::do_log('err','INTERNAL Could not find message previouly locked');
	return undef;
    }
    $message->{'messageasstring'} = MIME::Base64::decode($message->{'message'});
    unless ($message->{'messageasstring'}){
Sympa::Log::Syslog::do_log('err',"Could not decode %s",$message->{'message'});
	return undef;
    }

    $message->{'spoolname'} = $self->{'spoolname'};

    ## add objects
    my $robot_id = $message->{'robot'};
    my $listname = $message->{'list'};
    my $robot;

    if ($robot_id and $robot_id ne '*') {
	$robot = Robot->new($robot_id);
    }
    if ($robot) {
	if ($listname and length $listname) {
	    $message->{'list_object'} = List->new($listname, $robot);
	}
	$message->{'robot_object'} = $robot;
    }

    return $message;
}

sub move_to_bad {
    my $self = shift;
    my $key = shift;
    Sympa::Log::Syslog::do_log('debug', 'Moving spooled entity with key %s to bad',$key);
    unless ($self->update({'messagekey' => $key},
			  {'message_status' => 'bad','messagelock'=> 'NULL'})) {
	Sympa::Log::Syslog::do_log('err', 'Unable to  to set status bad to spooled entity with key %s',$key);
	return undef;
    }
}

#################"
# return one message from related spool using a specified selector
# returns undef if message was not found.
#  
sub get_message {
    my $self = shift;
    my $selector = shift;
    Sympa::Log::Syslog::do_log('debug2', '(%s, messagekey=%s, list=%s, robot=%s)',
	$self, $selector->{'messagekey'},
	$selector->{'list'}, $selector->{'robot'});

    my $sqlselector = _sqlselector($selector || $self->{'selector'});
    my $all = _selectfields();

    push @sth_stack, $sth;

    unless ($sth = SDM::do_query(
	q{SELECT %s
	  FROM spool_table
	  WHERE spoolname_spool = %s%s
	  %s},
	$all, SDM::quote($self->{'spoolname'}),
	($sqlselector ? " AND $sqlselector" : ''),
	SDM::get_limit_clause({'rows_count' => 1})
    )) {
	Sympa::Log::Syslog::do_log('err',
	    'Could not get message from spool %s', $self);
	$sth = pop @sth_stack;
	return undef;
    }

    my $message = $sth->fetchrow_hashref('NAME_lc');

    $sth->finish;
    $sth = pop @sth_stack;

    unless ($message and %$message) {
	Sympa::Log::Syslog::do_log('err', 'No message: %s', $sqlselector);
	return undef;
    } else {
	Sympa::Log::Syslog::do_log('debug3', 'Success: %s', $sqlselector);
    }

    $message->{'lock'} =  $message->{'messagelock'}; 
    $message->{'messageasstring'} =
	MIME::Base64::decode($message->{'message'});
    $message->{'spoolname'} = $self->{'spoolname'};

    if ($message->{'list'} && $message->{'robot'}) {
	my $robot = Robot->new($message->{'robot'});
	if ($robot) {
	    my $list = List->new($message->{'list'}, $robot);
	    if ($list) {
		$message->{'list_object'} = $list;
	    }
	}
    }
    return $message;
}

#################"
# lock one message from related spool using a specified selector
#  
sub unlock_message {

    my $self = shift;
    my $messagekey = shift;

    Sympa::Log::Syslog::do_log('debug', 'Spool::unlock_message(%s,%s)',$self->{'spoolname'}, $messagekey);
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

    Sympa::Log::Syslog::do_log('debug2', "Spool::update($self->{'spoolname'}, list = $selector->{'list'}, robot = $selector->{'robot'}, messagekey = $selector->{'messagekey'}");

    my $where = _sqlselector($selector);

    my $set = '';

    # hidde B64 encoding inside spool database.    
    if ($values->{'message'}) {
	$values->{'size'} =  length($values->{'message'});
	$values->{'message'} =  MIME::Base64::encode($values->{'message'})  ;
    }
    # update can be used in order to move a message from a spool to another one
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
	    $set = $set .$meta.'_spool = '.&SDM::quote($values->{$meta});
	}
	if ($meta eq 'messagelock') {
	    if ($values->{'messagelock'} eq 'NULL'){
		# when unlock always reset the lockdate
		$set =  $set .', lockdate_spool = NULL ';
	    }else{		
		# when setting a lock always set the lockdate
		$set =  $set .', lockdate_spool = '.time;
	    }    
	}
    }

    unless ($set) {
Sympa::Log::Syslog::do_log('err',"No value to update"); return undef;
    }
    unless ($where) {
Sympa::Log::Syslog::do_log('err',"No selector for an update"); return undef;
    }

    ## Updating Db
    my $statement = sprintf "UPDATE spool_table SET %s WHERE (%s)", $set,$where ;

    unless (&SDM::do_query($statement)) {
	Sympa::Log::Syslog::do_log('err', 'Unable to execute SQL statement "%s"', $statement);
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
    my $sender = $metadata->{'sender'};
    $sender |= '';

    Sympa::Log::Syslog::do_log('debug2',
	'(%s, <message_asstring>, list=%s, robot=%s, date=%s, %s)',
	$self, $metadata->{'list'}, $metadata->{'robot'}, $metadata->{'date'},
	$locked);

    my $b64msg = MIME::Base64::encode($message_asstring);
    my $message;
    if ($self->{'spoolname'} ne 'task' && $message_asstring ne 'rebuild' && $self->{'spoolname'} ne 'digest' && $self->{'spoolname'} ne 'subscribe') {
	$message = Message->new({'messageasstring' => $message_asstring,'noxsympato'=>1});
    }
    
    if($message) {
	$metadata->{'spam_status'} = $message->{'spam_status'};
	$metadata->{'subject'} = $message->get_header('Subject');
	$metadata->{'subject'} = substr $metadata->{'subject'}, 0, 109
	    if defined $metadata->{'subject'};
	$metadata->{'messageid'} = $message->get_header('Message-Id');
	$metadata->{'messageid'} = substr $metadata->{'messageid'}, 0, 295
	    if defined $metadata->{'messageid'};
	$metadata->{'headerdate'} = substr $message->get_header('Date'), 0, 78;

	#FIXME: get_sender_email() ?
	my @sender_hdr = Mail::Address->parse($message->get_header('From'));
	if (@sender_hdr) {
	    $metadata->{'sender'} = lc($sender_hdr[0]->address) unless $sender;
	    $metadata->{'sender'} = substr $metadata->{'sender'}, 0, 109;
	}
    }else{
	$metadata->{'subject'} = '';
	$metadata->{'messageid'} = '';
	$metadata->{'sender'} = $sender;
    }
    $metadata->{'date'}= int(time) unless ($metadata->{'date'}) ;
    $metadata->{'size'}= length($message_asstring) unless ($metadata->{'size'}) ;
    $metadata->{'message_status'} = 'ok';

    my ($insertpart1, $insertpart2, @insertparts) = ('', '');
    foreach my $meta (
	qw(list authkey robot message_status priority date type subject sender
	messageid size headerdate spam_status dkim_privatekey dkim_d dkim_i
	dkim_selector task_label task_date task_model
	task_flavour task_object)
    ) {
	$insertpart1 .= ', ' . $meta . '_spool';
	$insertpart2 .= ', ?';
	push @insertparts, $metadata->{$meta};
    }
    my $lock = $$.'@'.hostname() ;

    push @sth_stack, $sth;

    $sth = SDM::do_prepared_query(
	sprintf(
	    q{INSERT INTO spool_table
	      (spoolname_spool, messagelock_spool, message_spool%s)
	      VALUES (?, ?, ?%s)},
	    $insertpart1, $insertpart2
	),
	$self->{'spoolname'}, $lock, $b64msg, @insertparts
    );
    # this query returns the autoinc primary key as result of this insert
    $sth = SDM::do_prepared_query(
	q{SELECT messagekey_spool as messagekey
	  FROM spool_table
	  WHERE messagelock_spool = ? AND date_spool = ?},
	$lock, $metadata->{'date'}
    );
    ##FIXME: should check error

    my $inserted_message = $sth->fetchrow_hashref('NAME_lc');
    my $messagekey = $inserted_message->{'messagekey'};
    
    $sth->finish;
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
    Sympa::Log::Syslog::do_log('debug2', '(%s, %s)', @_);
    my $self = shift;
    my $params = shift;

    my $just_try = $params->{'just_try'};
    my $sqlselector = _sqlselector($params);

    push @sth_stack, $sth;

    unless ($sth = SDM::do_query(
	q{DELETE FROM spool_table
	  WHERE spoolname_spool = %s%s},
	SDM::quote($self->{'spoolname'}),
	($sqlselector ? " AND $sqlselector" : '')
    )) {
	Sympa::Log::Syslog::do_log('err',
            'Could not remove message from spool %s', $self);
	$sth = pop @sth_stack;
	return undef;
    }
    ## search if this message is already in spool database : mailfile may
    ## perform multiple submission of exactly the same message
    unless ($sth->rows) {
	Sympa::Log::Syslog::do_log('err', 'message is not in spool: %s', $sqlselector)
	    unless $just_try;
	$sth = pop @sth_stack;
	return undef;
    }

    $sth = pop @sth_stack;
    return 1;
}


################"
# Clean a spool by removing old messages
#

sub clean {  
    my $self = shift;
    my $filter = shift;
    Sympa::Log::Syslog::do_log('debug','Cleaning spool %s (%s), delay: %s',$self->{'spoolname'},$self->{'selection_status'},$filter->{'delay'});
    my $bad = 0;
    my $delay = $filter->{'delay'};
    if ($self->{'selection_status'} eq 'bad') {
	$bad =  1;
    }

    my $spoolname = $self->{'spoolname'};
    return undef unless $spoolname;
    return undef unless $delay;
    
    my $freshness_date = time - ($delay * 60 * 60 * 24);

    my $sqlquery = sprintf "DELETE FROM spool_table WHERE spoolname_spool = %s AND date_spool < %s ",&SDM::quote($spoolname),$freshness_date;
    if ($bad) {	
	$sqlquery  = 	$sqlquery . " AND message_status_spool = 'bad' ";
    }else{
	$sqlquery  = 	$sqlquery . " AND message_status_spool <> 'bad'";
    }
    
    push @sth_stack, $sth;
    $sth = &SDM::do_query('%s', $sqlquery);
    $sth->finish;
   Sympa::Log::Syslog::do_log('debug',"%s entries older than %s days removed from spool %s" ,$sth->rows,$delay,$self->{'spoolname'});
    $sth = pop @sth_stack;
    return 1;
}


# test the maximal message size the database will accept
sub store_test { 
    Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
    my $value_test = shift;
    my $divider = 100;
    my $steps = 50;
    my $maxtest = $value_test/$divider;
    my $size_increment = $divider*$maxtest/$steps;
    my $barmax = $size_increment*$steps*($steps+1)/2;
    my $even_part = $barmax/$steps;

    print "maxtest: $maxtest\n";
    print "barmax: $barmax\n";
    my $progress = Term::ProgressBar->new({name  => 'Total size transfered',
                                         count => $barmax,
                                         ETA   => 'linear', });

    my $testing = __PACKAGE__->new('msg', 'bad');

    my $msg = <<'EOF';
From: justeatester@host.notadomain
Message-Id:yep@host.notadomain
Subject: this a test

EOF
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
	my $messagekey;
	unless ($messagekey = $testing->store($msg,
	    {'list' => 'notalist', 'robot' => 'notaboot'})) {
	    return (($z-1)*$size_increment);
	}
	$testing->remove_message({'messagekey' => $messagekey});
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
# return a SQL WHERE substring in order to select chosen fields from the spool table 
# selector is a hash where key is a column name and value is column value expected.**** 
#   **** value can be prefixed with <,>,>=,<=, in that case the default comparator operator (=) is changed, I known this is dirty but I'm lazy :-(
sub _sqlselector {
    my $selector = shift || {};
    my $sqlselector = '';

    $selector = {%$selector};
    if (ref $selector->{'list'}) {
	$selector->{'robot'} = $selector->{'list'}->domain;
	$selector->{'list'} = $selector->{'list'}->name;
    }
    if (ref $selector->{'robot'}) {
	$selector->{'robot'} = $selector->{'robot'}->domain;
    }

    foreach my $field (keys %$selector) {
	next if $field eq 'just_try';

	my $compare_operator = '=';
	my $select_value = $selector->{$field};
	if ($select_value =~ /^([\<\>]\=?)\.(.*)$/){ 
	    $compare_operator = $1;
	    $select_value = $2;
	}

	if ($sqlselector) {
	    $sqlselector .= ' AND '.$field.'_spool '.$compare_operator.' '.&SDM::quote($selector->{$field});
	}else{
	    $sqlselector = ' '.$field.'_spool '.$compare_operator.' '.&SDM::quote($selector->{$field});
	}
    }
    return $sqlselector;
}

## Get unique ID
sub get_id {
    my $self = shift;
    return sprintf '%s/%s', $self->{'spoolname'}, $self->{'selection_status'};
}

1;
