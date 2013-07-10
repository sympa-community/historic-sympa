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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Spool - Mail spool object

=head1 DESCRIPTION

This class implements a mail spool.

=cut

package Sympa::Spool;

use strict;

use Carp;
use English qw(-no_match_vars);
use MIME::Base64;
use Sys::Hostname;

use Sympa::Log::Syslog;
use Sympa::Message;
use Sympa::Tools::Time;

=head1 CLASS METHODS

=over

=item Sympa::Spool->new(%parameters)

Creates a new L<Sympa::Spool> object.

Parameters:

=over

=item C<name> => string

=item C<status> => C<bad> | C<ok>

=item C<source> => L<Sympa::Datasource::SQL>

=back

Return:

A new L<Sympa::Spool> object, or I<undef>, if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $params{name});

	croak "invalid status parameter" if 
		$params{status} &&
		$params{status} ne 'bad' &&
		$params{status} ne 'ok';

	croak "missing source parameter" unless $params{source};
	croak "invalid source parameter" unless
		$params{source}->isa('Sympa::Datasource::SQL');

	my $self = {
		name   => $params{name},
		status => $params{status},
		source => $params{source}
	};

	bless $self, $class;

	return $self;
}

=item Sympa::Spool->global_count(%parameters)

FIXME

Parameters:

=over

=item C<source> => L<Sympa::Datasource::SQL>

=item C<status> => C<bad> | C<ok>

=back

=cut

sub global_count {
	my ($class, %params) = @_;

	my $query =
		'SELECT COUNT(*) ' .
		'FROM spool_table '.
		'WHERE message_status_spool = ?';
	my $handle = $params{source}->get_query_handle($query);
	$handle->execute($params{status});

	my @result = $handle->fetchrow_array();
	$handle->finish();

	return $result[0];
}

=back

=head1 INSTANCE METHODS

=over

=item $spool->get_count()

Return the spool content count.

Parameters:

=over

=item C<selector> => hashref

Hash field->value used as filter WHERE sql query.

=back

=cut

sub get_count {
	my ($self, %params) = @_;

	my $filter_clause = $self->_get_filter_clause($params{selector});
	if ($self->{status} eq 'bad') {
		$filter_clause .= " AND message_status_spool = 'bad'" ;
	} else {
		$filter_clause .= " AND message_status_spool != 'bad'" ;
	}
	$filter_clause =~ s/^AND//;

	my $query =
		"SELECT COUNT(*) " .
		"FROM spool_table " .
		"WHERE $filter_clause AND spoolname_spool=?";

	my $handle = $self->{source}->get_query_handle($query);
	$handle->execute($self->{name});
	my @result = $handle->fetchrow_array();
	return $result[0];
}

=item $spool->get_content(%parameters)

Return the spool content, as a list of hashref.

Parameters:

=over

=item C<selector> => hashref

Hash field->value used as filter WHERE sql query.

=item C<selection> => string

The list of field to select. possible values are :
	#    -  a comma separated list of field to select.
	#    -  '*'  is the default .
	#    -  '*_but_message' mean any field except message which may be hugue and unusefull while listing spools
	# should be used mainly to select all but 'message' that may be huge and may be unusefull

=item C<ofset> => number

For pagination, start fetch at given number.

=item C<page_size> => number

For pagination, limit answers to given size.

=item C<sortby> =>

sort

=item C<way> =>

asc or desc 

=back

=cut

sub get_content {
	my ($self, %params) = @_;

	my $filter_clause = $self->_get_filter_clause($params{selector});
	if ($self->{status} eq 'bad') {
		$filter_clause .= " AND message_status_spool = 'bad'" ;
	} else {
		$filter_clause .= " AND message_status_spool != 'bad'" ;
	}
	$filter_clause =~s/^AND//;

	my $select_clause = $self->_selectfields($params{selection});

	my $query =
		"SELECT $select_clause " .
		"FROM spool_table WHERE $filter_clause AND spoolname_spool=?";

	if ($params{orderby}) {
		$query .= " ORDER BY $params{orderby}_spool";
		$query .= " DESC" if $params{way} eq 'desc';
	}
	if ($params{page_size}) {
		$query .= " LIMIT $params{ofset}, $params{page_size}";
	}

	my $handle = $self->{source}->get_query_handle($query);
	$handle->execute($self->{name});
	my @messages;
	while (my $message = $handle->fetchrow_hashref('NAME_lc')) {
		$message->{'date_asstring'} = Sympa::Tools::Time::epoch2yyyymmjj_hhmmss($message->{'date'});
		$message->{'lockdate_asstring'} = Sympa::Tools::Time::epoch2yyyymmjj_hhmmss($message->{'lockdate'});
		$message->{'messageasstring'} = MIME::Base64::decode($message->{'message'}) if ($message->{'message'}) ;
		$message->{'listname'} = $message->{'listname'}; # duplicated because "list" is a tt2 method that convert a string to an array of chars so you can't test  [% IF  message.list %] because it is always defined!!!
		$message->{'status'} = $self->{status};
		push @messages, $message;
	}
	return @messages;
}

=item $spool->next($selector)

Return next spool entry ordered by priority next lock the message_in_spool that is returned

=cut

sub next {
	my ($self, $selector) = @_;

	Sympa::Log::Syslog::do_log('debug', '(%s,%s)',$self->{name},$self->{status});

	my $filter_clause = $self->_get_filter_clause($selector);

	if ($self->{status} eq 'bad') {
		$filter_clause .= " AND message_status_spool = 'bad'" ;
	} else {
		$filter_clause .= " AND message_status_spool != 'bad'" ;
	}
	$filter_clause =~ s/^\s*AND//;

	my $lock = $PID.'@'.hostname();
	my $epoch = time(); # should we use milli or nano seconds ?

	my $update_query = 
		"UPDATE spool_table "                        .
		"SET messagelock_spool=?, lockdate_spool=? " .
		"WHERE "                                     .
			"messagelock_spool IS NULL AND "     .
			"spoolname_spool=? AND "             .
			$filter_clause                       .
		"ORDER BY priority_spool, date_spool LIMIT 1";

	my $rows = $self->{source}->execute_query(
		$update_query,
		$lock,
		$epoch,
		$self->{name},
	);
	return undef unless $rows; # spool is empty

	my $select_clause = $self->_selectfields();
	my $select_query =
		"SELECT $select_clause "                                     .
		"FROM spool_table "                                          .
		"WHERE "                                                     .
			"spoolname_spool=? AND "                             .
			"message_status_spool=? AND "                        .
			"messagelock_spool=? AND "                           .
			"lockdate_spool=? AND "                              .
			"(priority_spool != 'z' OR priority_spool IS NULL) " .
		"ORDER by priority_spool LIMIT 1";

	my $handle = $self->{source}->get_query_handle($select_query);
	$handle->execute(
		$self->{name},
		$self->{status},
		$lock,
		$epoch
	);
	my $message = $handle->fetchrow_hashref('NAME_lc');

	unless ($message->{'message'}){
		Sympa::Log::Syslog::do_log('err',"INTERNAL Could not find message previouly locked");
		return undef;
	}
	$message->{'messageasstring'} = MIME::Base64::decode($message->{'message'});
	unless ($message->{'messageasstring'}){
		Sympa::Log::Syslog::do_log('err',"Could not decode %s",$message->{'message'});
		return undef;
	}
	return $message  ;
}

=item $spool->get_message($selector)

Return one message using a specified selector

=cut
sub get_message {
	my ($self, $selector) = @_;
	Sympa::Log::Syslog::do_log('debug', "($self->{name},messagekey = $selector->{'messagekey'}, listname = $selector->{'listname'},robot = $selector->{'robot'})");

	my (@filter_clauses, @values);
	foreach my $field (keys %$selector){
		if ($field eq 'messageid') {
			$selector->{'messageid'} = substr $selector->{'messageid'}, 0, 95;
		}
		push @filter_clauses,  $field . '_spool = ?';
		push @values, $selector->{$field};
	}

	my $filter_clause = join(' AND ', @filter_clauses);

	my $select_clause = $self->_selectfields();
	my $query = 
		"SELECT $select_clause " .
		"FROM spool_table " .
		"WHERE spoolname_spool=? AND $filter_clause LIMIT 1";

	my $handle = $self->{source}->get_query_handle($query);
	$handle->execute($self->{name}, @values);

	my $message = $handle->fetchrow_hashref('NAME_lc');
	if ($message) {
		$message->{'lock'} =  $message->{'messagelock'};
		$message->{'messageasstring'} = MIME::Base64::decode($message->{'message'});
	}

	return $message;
}

=item $spool->unlock_message($messagekey)

FIXME.

=cut

sub unlock_message {
	my ($self, $messagekey) = @_;

	Sympa::Log::Syslog::do_log('debug', '(%s,%s)', $self->{name}, $messagekey);
	return ( $self->update({'messagekey' => $messagekey},
			{'messagelock' => 'NULL'}));
}

=item $spool->update($selector, $values)

Update spool entries that match selector with values.

=cut

sub update {
	my ($self, $selector, $values) = @_;
	Sympa::Log::Syslog::do_log('debug', "($self->{name}, list = $selector->{'list'}, robot = $selector->{'robot'}, messagekey = $selector->{'messagekey'}");

	my $filter_clause = $self->_get_filter_clause($selector);

	# hidde B64 encoding inside spool database.
	if ($values->{'message'}) {
		$values->{'size'} =  length($values->{'message'});
		$values->{'message'} =  MIME::Base64::encode($values->{'message'})  ;
	}
	# update can used in order to move a message from a spool to another one
	$values->{name} = $self->{name} unless($values->{'spoolname'});

	my (@set_clauses, @values);
	foreach my $meta (keys %$values) {
		next if ($meta =~ /^(messagekey)$/);
		if (($meta eq 'messagelock')&&($values->{$meta} eq 'NULL')){
			# SQL set  xx = NULL and set xx = 'NULL' is not the same !
			push @set_clauses, $meta .'_spool = NULL';
		} else {
			push @set_clauses, $meta . '_spool = ?';
			push @values, $values->{$meta};
		}
		if ($meta eq 'messagelock') {
			if ($values->{'messagelock'} eq 'NULL'){
				# when unlock always reset the lockdate
				push @set_clauses, 'lockdate_spool = NULL';
			} else {
				# when setting a lock always set the lockdate
				push @set_clauses, 'lockdate_spool = ?';
				push @values, time();
			}
		}
	}

	my $set_clause = join(', ', @set_clauses);

	unless ($set_clause) {
		Sympa::Log::Syslog::do_log('err',"No value to update"); return undef;
	}
	unless ($filter_clause) {
		Sympa::Log::Syslog::do_log('err',"No selector for an update"); return undef;
	}

	## Updating Db
	my $query =
		"UPDATE spool_table SET $set_clause WHERE $filter_clause";

	my $rows = $self->{source}->execute_query($query, @values);
	unless ($rows) {
		Sympa::Log::Syslog::do_log('err','Unable to execute SQL statement');
		return undef;
	}
	return 1;
}

=item $spool->store(%parameters)

Store a message in database spool.

Parameters:

=over

=item C<string> => string

FIXME.

=item C<message> => L<Sympa::Message>

FIXME.

=item C<metadata> => hashref

A set of attributes related to the spool

=item C<locked> => boolean

If define message must stay locked after store

=back


=cut

sub store {
	my ($self, %params) = @_;

	my $sender = $params{metadata}->{'sender'};
	$sender |= '';

	Sympa::Log::Syslog::do_log('debug',"($self->{name},$self->{status}, <message_asstring> ,list : $params{metadata}->{'list'},robot : $params{metadata}->{'robot'} , date: $params{metadata}->{'date'}), lock : $params{locked}");

	my $message = $params{message} ?
		$params{message} :
		Sympa::Message->new(string => $params{string});
	my $string  = $params{message} ?
		$params{message}->{'msg_as_string'} :
		MIME::Base64::encode($params{string});

	if($message) {
		$params{metadata}->{'spam_status'} = $message->{'spam_status'};
		$params{metadata}->{'subject'} = $message->{'msg'}->head()->get('Subject');
		chomp $params{metadata}->{'subject'} ;
		$params{metadata}->{'subject'} = substr $params{metadata}->{'subject'}, 0, 109;
		$params{metadata}->{'messageid'} = $message->{'msg'}->head()->get('Message-Id');
		chomp $params{metadata}->{'messageid'} ;
		$params{metadata}->{'messageid'} = substr $params{metadata}->{'messageid'}, 0, 295;
		$params{metadata}->{'headerdate'} = substr $message->{'msg'}->head()->get('Date'), 0, 78;

		my @sender_hdr = Mail::Address->parse($message->{'msg'}->get('From'));
		if ($#sender_hdr >= 0){
			$params{metadata}->{'sender'} = lc($sender_hdr[0]->address) unless ($sender);
			$params{metadata}->{'sender'} = substr $params{metadata}->{'sender'}, 0, 109;
		}
	} else {
		$params{metadata}->{'subject'} = '';
		$params{metadata}->{'messageid'} = '';
		$params{metadata}->{'sender'} = $sender;
	}
	$params{metadata}->{'date'}= int(time()) unless ($params{metadata}->{'date'}) ;
	$params{metadata}->{'size'}= length($params{message}) unless ($params{metadata}->{'size'}) ;
	$params{metadata}->{'message_status'} = 'ok';

	my @meta = qw/
		list robot message_status priority date type subject sender
		messageid size headerdate spam_status dkim_privatekey dkim_d
		dkim_i dkim_selector create_list_if_needed task_label task_date
		task_model task_object
	/;
	my $field_clause = join(', ', map { $_ . '_spool' } @meta);
	my $value_clause = join(', ', map { '?' } @meta);
	my @values = map { $params{metadata}->{$_} } @meta;

	my $lock = $PID.'@'.hostname() ;

	my $insert_query =
		"INSERT INTO spool_table ("                    .
			"spoolname_spool, "   .
			"messagelock_spool, " .
			"message_spool, "     .
			$field_clause         .
		") "                                           .
		"VALUES (?, ?, ?, $value_clause)";

	my $insert_handle = $self->{source}->get_query_handle($insert_query);
	$insert_handle->execute(
		$self->{name},
		$lock,
		$string,
		@values,
	);

	my $select_query =
		'SELECT messagekey_spool as messagekey '    .
		'FROM spool_table '                         .
		'WHERE messagelock_spool=? AND date_spool=?';
	my $select_handle = $self->{source}->get_query_handle($select_query);
	$select_handle->execute(
		$lock,
		$params{metadata}->{'date'}
	);
	# this query returns the autoinc primary key as result of this insert

	my $inserted_message = $select_handle->fetchrow_hashref('NAME_lc');
	my $messagekey = $inserted_message->{'messagekey'};

	$insert_handle->finish();
	$select_handle->finish();

	unless ($params{locked}) {
		$self->unlock_message($messagekey);
	}
	return $messagekey;
}

=item $spool->remove_message($selector)

Remove a message in database spool using (messagekey,list,robot) which are a unique id in the spool

=cut

sub remove_message {
	my ($self, $selector) = @_;

	my $robot = $selector->{'robot'};
	my $messagekey = $selector->{'messagekey'};
	my $listname = $selector->{'listname'};
	Sympa::Log::Syslog::do_log('debug',"remove_message ($self->{name},$listname,$robot,$messagekey)");

	## search if this message is already in spool database : mailfile may perform multiple submission of exactly the same message
	unless ($self->get_message($selector)){
		Sympa::Log::Syslog::do_log('err',"message not in spool");
		return undef;
	}

	my $filter_clause = $self->_get_filter_clause($selector);
	my $query = 
		"DELETE FROM spool_table " .
		"WHERE spoolname_spool=? AND $filter_clause";

	$self->{source}->execute_query($query, $self->{name});
	return 1;
}

=item $spool->clean(%parameters)

Remove old messages.

Parameters:

=over

=item C<delay> => number

FIXME.

=item C<bad> => FIXME

FIXME.

=back

=cut

sub clean {
	my ($self, %params) = @_;

	return undef unless $params{delay};
	Sympa::Log::Syslog::do_log('debug', '(%s,$delay)',$self->{name},$params{delay});

	my $freshness_date = time() - ($params{delay} * 60 * 60 * 24);

	my $query = 'DELETE FROM spool_table WHERE spoolname_spool = ? AND date_spool < ?';

	if ($params{bad}) {
		$query .= ' AND bad_spool IS NOTNULL';
	} else {
		$query .= ' AND bad_spool IS NULL';
	}

	my $handle = $self->{source}->get_query_handle($query);
	$handle->execute($self->{name}, $freshness_date);
	$handle->finish();

	Sympa::Log::Syslog::do_log('debug',"%s entries older than %s days removed from spool %s" ,$handle->rows(),$params{delay},$self->{name});
	return 1;
}

# Internal to ease SQL
# return a SQL SELECT substring in ordder to select choosen fields from spool table
# selction is comma separated list of field, '*' or '*_but_message'. in this case skip message_spool field
sub _selectfields{
	my ($self, $selection) = @_;

	$selection = '*' unless $selection;
	my $select ='';

	if (($selection eq '*_but_message')||($selection eq '*')) {

		my $structure = $self->{source}->get_structure();

		foreach my $field (keys %{$structure->{spool_table}{fields}}) {
			next if (($selection eq '*_but_message') && ($field eq 'message_spool')) ;
			my $var = $field;
			$var =~ s/\_spool//;
			$select = $select . $field .' AS '.$var.',';
		}
	} else {
		my @fields = split (/,/,$selection);
		foreach my $field (@fields){
			$select = $select . $field .'_spool AS '.$field.',';
		}
	}

	$select =~ s/\,$//;
	return $select;
}

# return a SQL WHERE substring in order to select chosen fields from the spool table
# selector is a hash where key is a column name and value is column value expected.****
#   **** value can be prefixed with <,>,>=,<=, in that case the default comparator operator (=) is changed, I known this is dirty but I'm lazy :-(
sub _get_filter_clause {
	my ($self, $selector) = @_;

	my $sqlselector = '';

	foreach my $field (keys %$selector) {
		my $compare_operator = '=';
		my $select_value = $selector->{$field};
		if ($select_value =~ /^([\<\>]\=?)\.(.*)$/){
			$compare_operator = $1;
			$select_value = $2;
		}

		if ($sqlselector) {
			$sqlselector .= ' AND '.$field.'_spool '.$compare_operator.' '.$self->{source}->quote($selector->{$field});
		} else {
			$sqlselector = ' '.$field.'_spool '.$compare_operator.' '.$self->{source}->quote($selector->{$field});
		}
	}
	return $sqlselector;
}

=back

=cut

1;
