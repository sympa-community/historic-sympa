# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: Log.pm 8882 2013-03-15 16:55:11Z rousse $

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

Sympa::Log::Database - Database-oriented log functions

=head1 DESCRIPTION

This module provides database-oriented logging functions

=cut

package Sympa::Log::Database;

use strict;

use English qw(-no_match_vars);
use POSIX qw();

use Sympa::SDM;
use Sympa::Log::Syslog;

my ($sth, @sth_stack, $rows_nb);

my %action_type = (
	message => [ qw/
		arc_delete	arc_download	d_remove_arc	distribute
		DoCommand	DoFile		DoForward	DoMessage
		reject		rebuildarc	record_email	remind
		remove		send_me		send_mail	SendDigest
		sendMessage
	/ ],
	authentication => [ qw/
		choosepasswd	login			logout
		loginrequest	remindpasswd		sendpasswd
		ssologin	ssologin_succeses
	/ ],
	subscription => [ qw/
		add		del	ignoresub	signoff
		subscribe	subindex
	/ ],
	list_management => [ qw/
		admin		blacklist		close_list
		copy_template	create_list		edit_list
		edit_template	install_pending_list	purge_list
		remove_template	rename_list
	/ ],
	bounced => [ qw/
		get_bounce	resetbounce
	/ ],
	preferences => [ qw/
		change_email	editsubscriber	pref
		set		setpasswd	setpref
	/ ],
	shared => [ qw/
		change_email	creation_shared_file	d_admin
		d_change_access	d_control		d_copy_file
		d_copy_rec_dir	d_create_dir		d_delete
		d_describe	d_editfile		d_install_shared
		d_overwrite	d_properties		d_reject_shared
		d_rename	d_savefile		d_set_owner
		d_upload	d_unzip			d_unzip_shared_file
		d_read		install_file_hierarchy	new_d_read
		set_lang
	/ ],
);

=head1 FUNCTIONS

=head2 get_log_date()

=head3 Parameters

None.

=head3 Return

=cut

sub get_log_date {
	my $sth;
	my @dates;
	foreach my $query('MIN','MAX') {
		$sth = Sympa::SDM::do_query(
			"SELECT $query(date_logs) FROM logs_table"
		);
		unless ($sth) {
			Sympa::Log::Syslog::do_log('err','Unable to get %s date from logs_table',$query);
			return undef;
		}
		while (my $d = ($sth->fetchrow_array) [0]) {
			push @dates, $d;
		}
	}

	return @dates;
}

=head2 do_log(%parameters)

Add log in RDBMS.

=head3 Parameters

=over

=item * I<list>: FIXME

=item * I<robot>: FIXEM

=item * I<action>: FIXME

=item * I<parameter>: FIXME

=item * I<target_email>: FIXME

=item * I<user_email>: FIXME

=item * I<msg_id>: FIXME

=item * I<status>: FIXME

=item * I<error_type>: FIXME

=item * I<client>: FIXME

=item * I<daemon>: FIXME

=back

=head3 Return

=cut

sub do_log {
	my (%params) = @_;

	unless ($params{daemon} =~ /^(task|archived|sympa|wwsympa|bounced|sympa_soap)$/) {
		Sympa::Log::Syslog::do_log ('err',"Internal_error : incorrect process value $params{daemon}");
		return undef;
	}

	$params{parameters} = Sympa::Tools::clean_msg_id($params{parameters});
	$params{msg_id}     = Sympa::Tools::clean_msg_id($params{msg_id});
	$params{user_email} = Sympa::Tools::clean_msg_id($params{user_email});

	my $date   = time;
	my $random = int(rand(1000000));
	my $id     = $date.$random;

	unless($params{user_email}) {
		$params{user_email} = 'anonymous';
	}
	unless($params{list}) {
		$params{list} = '';
	}
	#remove the robot name of the list name
	if($params{list} =~ /(.+)\@(.+)/) {
		$params{list} = $1;
		unless($params{robot}) {
			$params{robot} = $2;
		}
	}

	## Insert in log_table

	my $result = Sympa::SDM::do_query(
		'INSERT INTO logs_table (id_logs,date_logs,robot_logs,list_logs,action_logs,parameters_logs,target_email_logs,msg_id_logs,status_logs,error_type_logs,user_email_logs,client_logs,daemon_logs) VALUES (%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
		$id,
		$date,
		Sympa::SDM::quote($params{robot}),
		Sympa::SDM::quote($params{list}),
		Sympa::SDM::quote($params{action}),
		Sympa::SDM::quote(substr($params{parameters},0,100)),
		Sympa::SDM::quote($params{target_email}),
		Sympa::SDM::quote($params{msg_id}),
		Sympa::SDM::quote($params{status}),
		Sympa::SDM::quote($params{error_type}),
		Sympa::SDM::quote($params{user_email}),
		Sympa::SDM::quote($params{client}),
		Sympa::SDM::quote($params{daemon})
	);
	unless($result) {
		Sympa::Log::Syslog::do_log('err','Unable to insert new db_log entry in the database');
		return undef;
	}

	return 1;
}

=head2 do_stat_log($parameters)

Insert data in stats table.

=head3 Parameters

=over

=item * I<list>: FIXME

=item * I<robot>: FIXEM

=item * I<mail>: FIXME

=item * I<operation>: FIXME

=item * I<daemon>: FIXME

=item * I<ip>: FIXME

=item * I<parameter>: FIXME

=item * I<read>: FIXME

=back

=head3 Return

=cut

sub do_stat_log {
	my (%params) = @_;

	my $read   = 0;
	my $date   = time;
	my $random = int(rand(1000000));
	my $id     = $date.$random;

	if (ref($params{list}) && $params{list}->isa('Sympa::List')) {
		$params{list} = $params{list}->{'name'};
	}
	if($params{list} =~ /(.+)\@(.+)/) {#remove the robot name of the list name
		$params{list} = $1;
		unless($params{robot}) {
			$params{robot} = $2;
		}
	}

	##insert in stat table
	my $result = Sympa::SDM::do_query(
		'INSERT INTO stat_table (id_stat, date_stat, email_stat, operation_stat, list_stat, daemon_stat, user_ip_stat, robot_stat, parameter_stat, read_stat) VALUES (%s, %d, %s, %s, %s, %s, %s, %s, %s, %d)',
		$id,
		$date,
		Sympa::SDM::quote($params{mail}),
		Sympa::SDM::quote($params{operation}),
		Sympa::SDM::quote($params{list}),
		Sympa::SDM::quote($params{daemon}),
		Sympa::SDM::quote($params{ip}),
		Sympa::SDM::quote($params{robot}),
		Sympa::SDM::quote($params{parameter}),
		Sympa::SDM::quote($params{read})
	);
	unless($result) {
		Sympa::Log::Syslog::do_log('err','Unable to insert new stat entry in the database');
		return undef;
	}
	return 1;
}

sub _db_stat_counter_log {
	my (%params) = @_;

	my $random = int(rand(1000000));
	my $id = $params{begin_date}.$random;

	if($params{list} =~ /(.+)\@(.+)/) {#remove the robot name of the list name
		$params{list} = $1;
		unless($params{robot}) {
			$params{robot} = $2;
		}
	}

	my $result = Sympa::SDM::do_query(
		'INSERT INTO stat_counter_table (id_counter, beginning_date_counter, end_date_counter, data_counter, robot_counter, list_counter, variation_counter, total_counter) VALUES (%s, %d, %d, %s, %s, %s, %d, %d)',
		$id,
		$params{begin_date},
		$params{end_date},
		Sympa::SDM::quote($params{data}),
		Sympa::SDM::quote($params{robot}),
		Sympa::SDM::quote($params{list}),
		$params{variation},
		$params{total}
	);
	unless($result) {
		Sympa::Log::Syslog::do_log('err','Unable to insert new stat counter entry in the database');
		return undef;
	}
	return 1;

}

=head2 delete_messages($parameters)

Delete logs in RDBMS.

=head3 Parameters

=head3 Return

=cut

sub delete_messages {
	my ($exp) = @_;
	my $date = time - ($exp * 30 * 24 * 60 * 60);

	my $result = Sympa::SDM::do_query(
		"DELETE FROM logs_table WHERE (logs_table.date_logs <= %s)",
		Sympa::SDM::quote($date)
	);
	unless ($result) {
		Sympa::Log::Syslog::do_log('err','Unable to delete db_log entry from the database');
		return undef;
	}
	return 1;

}

=head2 get_first_db_log($parameters)

Scan log_table with appropriate select.

=head3 Parameters

=head3 Return

=cut

sub get_first_db_log {
	my ($select) = @_;


	my $statement = sprintf "SELECT date_logs, robot_logs AS robot, list_logs AS list, action_logs AS action, parameters_logs AS parameters, target_email_logs AS target_email,msg_id_logs AS msg_id, status_logs AS status, error_type_logs AS error_type, user_email_logs AS user_email, client_logs AS client, daemon_logs AS daemon FROM logs_table WHERE robot_logs=%s ", Sympa::SDM::quote($select->{'robot'});

	#if a type of target and a target are specified
	if (($select->{'target_type'}) && ($select->{'target_type'} ne 'none')) {
		if($select->{'target'}) {
			$select->{'target_type'} = lc ($select->{'target_type'});
			$select->{'target'} = lc ($select->{'target'});
			$statement .= 'AND ' . $select->{'target_type'} . '_logs = ' . Sympa::SDM::quote($select->{'target'}).' ';
		}
	}

	#if the search is between two date
	if ($select->{'date_from'}) {
		my @tab_date_from = split(/\//,$select->{'date_from'});
		my $date_from = POSIX::mktime(0,0,-1,$tab_date_from[0],$tab_date_from[1]-1,$tab_date_from[2]-1900);
		unless($select->{'date_to'}) {
			my $date_from2 = POSIX::mktime(0,0,25,$tab_date_from[0],$tab_date_from[1]-1,$tab_date_from[2]-1900);
			$statement .= sprintf "AND date_logs BETWEEN '%s' AND '%s' ",$date_from, $date_from2;
		}
		if($select->{'date_to'}) {
			my @tab_date_to = split(/\//,$select->{'date_to'});
			my $date_to = POSIX::mktime(0,0,25,$tab_date_to[0],$tab_date_to[1]-1,$tab_date_to[2]-1900);

			$statement .= sprintf "AND date_logs BETWEEN '%s' AND '%s' ",$date_from, $date_to;
		}
	}

	#if the search is on a precise type
	if ($select->{'type'}) {
		if(($select->{'type'} ne 'none') && ($select->{'type'} ne 'all_actions')) {
			my $first = 'false';
			foreach my $type(@{$action_type{$select->{'type'}}}) {
				if($first eq 'false') {
					#if it is the first action, put AND on the statement
					$statement .= sprintf "AND (logs_table.action_logs = '%s' ",$type;
					$first = 'true';
				}
				#else, put OR
				else {
					$statement .= sprintf "OR logs_table.action_logs = '%s' ",$type;
				}
			}
			$statement .= ')';
		}

	}

	#if the listmaster want to make a search by an IP adress.    if($select->{'ip'}) {
	$statement .= sprintf "AND client_logs = '%s'",$select->{'ip'};


	## Currently not used
	#if the search is on the actor of the action
	if ($select->{'user_email'}) {
		$select->{'user_email'} = lc ($select->{'user_email'});
		$statement .= sprintf "AND user_email_logs = '%s' ",$select->{'user_email'};
	}

	#if a list is specified -just for owner or above-
	if($select->{'list'}) {
		$select->{'list'} = lc ($select->{'list'});
		$statement .= sprintf "AND list_logs = '%s' ",$select->{'list'};
	}

	$statement .= sprintf "ORDER BY date_logs ";

	push @sth_stack, $sth;
	$sth = Sympa::SDM::do_query($statement);
	unless($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve logs entry from the database');
		return undef;
	}

	my $log = $sth->fetchrow_hashref('NAME_lc');
	$rows_nb = $sth->rows;

	## If no rows returned, return an empty hash
	## Required to differenciate errors and empty results
	if ($rows_nb == 0) {
		return {};
	}

	## We can't use the "AS date" directive in the SELECT statement because "date" is a reserved keywork with Oracle
	$log->{date} = $log->{date_logs} if defined($log->{date_logs});
	return $log;


}

=head2 return_rows_nb()

=head3 Parameters

None.

=head3 Return

=cut

sub return_rows_nb {
	return $rows_nb;
}

=head2 get_next_db_log()

=head3 Parameters

None.

=head3 Return

=cut

sub get_next_db_log {

	my $log = $sth->fetchrow_hashref('NAME_lc');

	unless (defined $log) {
		$sth->finish;
		$sth = pop @sth_stack;
	}

	## We can't use the "AS date" directive in the SELECT statement because "date" is a reserved keywork with Oracle
	$log->{date} = $log->{date_logs} if defined($log->{date_logs});

	return $log;
}

=head2 aggregate_data($begin_date, $end_date)

Aggregate date from stat_table to stat_counter_table.

Dates must be in epoch format.

=head3 Parameters

=head3 Return

=cut

sub aggregate_data {
	my ($begin_date, $end_date) = @_;

	my $aggregated_data; # the hash containing aggregated data that the sub deal_data will return.

	$sth = Sympa::SDM::do_query(
		"SELECT * FROM stat_table WHERE (date_stat BETWEEN '%s' AND '%s') AND (read_stat = 0)",
		$begin_date,
		$end_date
	);
	unless ($sth) {
		Sympa::log::Syslog::do_log('err','Unable to retrieve stat entries between date % and date %s', $begin_date, $end_date);
		return undef;
	}


	my $res = $sth->fetchall_hashref('id_stat');


	$aggregated_data = _deal_data($res);

	#the line is read, so update the read_stat from 0 to 1
	$sth = Sympa::SDM::do_query(
		"UPDATE stat_table SET read_stat = 1 WHERE (date_stat BETWEEN '%s' AND '%s')",
		$begin_date,
		$end_date
	);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to set stat entries between date % and date %s as read', $begin_date, $end_date);
		return undef;
	}


	#store reslults in stat_counter_table
	foreach my $key_op (keys (%$aggregated_data)) {

		#open TMP2, ">/tmp/digdump"; Sympa::Tools::Data::dump_var($aggregated_data->{$key_op}, 0, \*TMP2); close TMP2;

		#store send mail data
		if($key_op eq 'send_mail'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				foreach my $key_list (keys (%{$aggregated_data->{$key_op}->{$key_robot}})){


					_db_stat_counter_log(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $key_op,
						list       => $key_list,
						variation  => $aggregated_data->{$key_op}->{$key_robot}->{$key_list}->{'count'},
						total => '',
						robot => $key_robot
					);

					#updating susbcriber_table
					foreach my $key_mail (keys (%{$aggregated_data->{$key_op}->{$key_robot}->{$key_list}})){

						if (($key_mail ne 'count') && ($key_mail ne 'size')){
							_update_subscriber_msg_send(
								mail    => $key_mail,
								list    => $key_list,
								robot   => $key_robot,
								counter => $aggregated_data->{$key_op}->{$key_robot}->{$key_list}->{$key_mail}
							);
						}
					}
				}
			}
		}

		#store added subscribers--------------------------------
		if($key_op eq 'add_subscriber'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				foreach my $key_list (keys (%{$aggregated_data->{$key_op}->{$key_robot}})){

					_db_stat_counter_log(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $key_op,
						list       => $key_list,
						variation  => $aggregated_data->{$key_op}->{$key_robot}->{$key_list}->{'count'},
						total      =>   '',
						robot      => $key_robot
					);
				}
			}
		}
		#store deleted subscribers--------------------------------------
		if($key_op eq 'del_subscriber'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				foreach my $key_list (keys (%{$aggregated_data->{$key_op}->{$key_robot}})){

					foreach my $key_param (keys (%{$aggregated_data->{$key_op}->{$key_robot}->{$key_list}})){

						_db_stat_counter_log(
							begin_date => $begin_date,
							end_date   => $end_date,
							data       => $key_param,
							list       => $key_list,
							variation => $aggregated_data->{$key_op}->{$key_robot}->{$key_list}->{$key_param},
							total     => '',
							robot     => $key_robot
						);

					}
				}
			}
		}
		#store lists created--------------------------------------------
		if($key_op eq 'create_list'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				_db_stat_counter_log(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $key_op,
					list       => '',
					variation  => $aggregated_data->{$key_op}->{$key_robot},
					total      => '',
					robot      => $key_robot
				);
			}
		}
		#store lists copy-----------------------------------------------
		if($key_op eq 'copy_list'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				_db_stat_counter_log(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $key_op,
					list       => '',
					variation  => $aggregated_data->{$key_op}->{$key_robot},
					total      => '',
					robot      => $key_robot
				);
			}
		}
		#store lists closed----------------------------------------------
		if($key_op eq 'close_list'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				_db_stat_counter_log(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $key_op,
					list       => '',
					variation  => $aggregated_data->{$key_op}->{$key_robot},
					total      => '',
					robot      => $key_robot
				);
			}
		}
		#store lists purged-------------------------------------------------
		if($key_op eq 'purge_list'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				_db_stat_counter_log(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $key_op,
					list       => '',
					variation  => $aggregated_data->{$key_op}->{$key_robot},
					total      => '',
					robot      => $key_robot
				);
			}
		}
		#store messages rejected-------------------------------------------
		if($key_op eq 'reject'){

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				foreach my $key_list (keys (%{$aggregated_data->{$key_op}->{$key_robot}})){

					_db_stat_counter_log(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $key_op,
						list       => $key_list,
						variation  => $aggregated_data->{$key_op}->{$key_robot}->{$key_list},
						total      => '',
						robot      => $key_robot
					);
				}
			}
		}
		#store lists rejected----------------------------------------------
		if($key_op eq 'list_rejected') {

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				_db_stat_counter_log(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $key_op,
					list       => '',
					variation  => $aggregated_data->{$key_op}->{$key_robot},
					total      => '',
					robot      => $key_robot
				);
			}
		}
		#store documents uploaded------------------------------------------
		if($key_op eq 'd_upload') {

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				foreach my $key_list (keys (%{$aggregated_data->{$key_op}->{$key_robot}})){

					_db_stat_counter_log(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $key_op,
						list       => $key_list,
						variation  => $aggregated_data->{$key_op}->{$key_robot}->{$key_list},
						total      => '',
						robot      => $key_robot
					);
				}
			}

		}
		#store folder creation in shared-----------------------------------
		if($key_op eq 'd_create_directory') {

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				foreach my $key_list (keys (%{$aggregated_data->{$key_op}->{$key_robot}})){

					_db_stat_counter_log(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $key_op,
						list       => $key_list,
						variation  => $aggregated_data->{$key_op}->{$key_robot}->{$key_list},
						total      => '',
						robot      => $key_robot
					);
				}
			}

		}
		#store file creation in shared-------------------------------------
		if($key_op eq 'd_create_file') {

			foreach my $key_robot (keys (%{$aggregated_data->{$key_op}})){

				foreach my $key_list (keys (%{$aggregated_data->{$key_op}->{$key_robot}})){

					_db_stat_counter_log(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $key_op,
						list       => $key_list,
						variation  => $aggregated_data->{$key_op}->{$key_robot}->{$key_list},
						total      => '',
						robot      => $key_robot
					);
				}
			}

		}

	}#end of foreach

	my $d_deb = localtime($begin_date);
	my $d_fin = localtime($end_date);
	Sympa::Log::Syslog::do_log('debug2', 'data aggregated from %s to %s', $d_deb, $d_fin);
}

# get in parameter the result of db request and put in an hash data we need.
sub _deal_data {
	my ($result_request) = @_;

	my %data;

	#on parcours caque ligne correspondant a un nuplet
	#each $id correspond to an hash
	foreach my $id (keys(%$result_request)) {
		# test about send_mail
		if($result_request->{$id}->{'operation_stat'} eq 'send_mail') {


			#test if send_mail value exists already or not, if not, create it
			unless(exists ($data{'send_mail'})){
				$data{'send_mail'} = undef;

			}

			my $r_name = $result_request->{$id}->{'robot_stat'};#get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'};#get name of list
			my $email = $result_request->{$id}->{'email_stat'}; #get the sender


			#if the listname and robot  dont exist in $data, create it, with size & count to zero
			unless(exists ($data{'send_mail'}{$r_name}{$l_name})) {
				$data{'send_mail'}{$r_name}{$l_name}{'size'} = 0;
				$data{'send_mail'}{$r_name}{$l_name}{'count'} = 0;
				$data{'send_mail'}{$r_name}{$l_name}{$email} = 0;

			}

			#on ajoute la taille du message
			$data{'send_mail'}{$r_name}{$l_name}{'size'} += $result_request->{$id}->{'parameter_stat'};
			#on ajoute +1 message envoyé
			$data{'send_mail'}{$r_name}{$l_name}{'count'}++;
			#et on incrémente le mail
			$data{'send_mail'}{$r_name}{$l_name}{$email}++;
		}
		#------------------------------test about add_susbcriber-----------------------
		if($result_request->{$id}->{'operation_stat'} eq 'add subscriber') {

			unless(exists ($data{'add_subscriber'})){
				$data{'add_subscriber'}=undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'}; #get name of list

			#if the listname and robot  dont exist in $data, create it, with  count to zero
			unless(exists ($data{'add_subscriber'}{$r_name}{$l_name})) {
				$data{'add_subscriber'}{$r_name}{$l_name}{'count'}=0;
			}

			#on incrémente le nombre d'inscriptions
			$data{'add_subscriber'}{$r_name}{$l_name}{'count'}++;


		}
		#-------------------------------test about del_subscriber-----------------------
		if($result_request->{$id}->{'operation_stat'} eq 'del subscriber') {

			unless(exists ($data{'del_subscriber'})){
				$data{'del_subscriber'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'}; #get name of list
			my $param = $result_request->{$id}->{'parameter_stat'}; #if del is usubcription, deleted by admin or bounce...

			unless(exists ($data{'del_subscriber'}{$r_name}{$l_name})){
				$data{'del_subscriber'}{$r_name}{$l_name}{$param} = 0;
			}

			#on incrémente les parametres
			$data{'del_subscriber'}{$r_name}{$l_name}{$param}++;
		}
		#------------------------------test about list creation-------------------
		if($result_request->{$id}->{'operation_stat'} eq 'create_list'){

			unless(exists ($data{'create_list'})){
				$data{'create_list'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get the name of the robot

			unless(exists ($data{'create_list'}{$r_name})){
				$data{'create_list'}{$r_name} = 0;
			}


			#on incrémente le nombre de création de listes
			$data{'create_list'}{$r_name}++;
		}
		#-------------------------------test about copy list-------------------------
		if($result_request->{$id}->{'operation_stat'} eq 'copy list'){

			unless(exists ($data{'copy_list'})){
				$data{'copy_list'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get the name of the robot

			unless(exists ($data{'copy_list'}{$r_name})){
				$data{'copy_list'}{$r_name} = 0;
			}


			#on incrémente le nombre de copies de listes
			$data{'copy_list'}{$r_name}++;
		}
		#-------------------------------test about closing list----------------------
		if($result_request->{$id}->{'operation_stat'} eq 'close_list'){

			unless(exists ($data{'close_list'})){
				$data{'close_list'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get the name of the robot

			unless(exists ($data{'close_list'}{$r_name})){
				$data{'close_list'}{$r_name} = 0;
			}

			#on incrémente le nombre de création de listes
			$data{'close_list'}{$r_name}++;
		}
		#--------------------------------test abount purge list-------------------
		if($result_request->{$id}->{'operation_stat'} eq 'purge list'){

			unless(exists ($data{'purge_list'})){
				$data{'purge_list'} = 0;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get the name of the robot

			unless(exists ($data{'purge_list'}{$r_name})){
				$data{'purge_list'}{$r_name} = 0;
			}

			#on incrémente le nombre de création de listes
			$data{'purge_list'}{$r_name}++;
		}
		#-----------------------------test about rejected messages-----------------
		if($result_request->{$id}->{'operation_stat'} eq 'reject') {

			unless (exists ($data{'reject'})){
				$data{'reject'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'}; #get name of list

			unless(exists ($data{'reject'}{$r_name}{$l_name})){
				$data{'reject'}{$r_name}{$l_name} = 0;
			}

			#on icrémente le nombre de messages rejetés pour une liste
			$data{'reject'}{$r_name}{$l_name}++;
		}
		#-----------------------------test about rejected creation lists-----------
		if($result_request->{$id}->{'operation_stat'} eq 'list_rejected') {

			unless (exists ($data{'list_rejected'})){
				$data{'list_rejected'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot

			unless (exists ($data{'list_rejected'}{$r_name})){
				$data{'list_rejected'}{$r_name} = 0;
			}

			#on incrémente le nombre de listes rejetées par robot
			$data{'list_rejected'}{$r_name}++;
		}
		#------------------------------test about upload sharing------------------
		if($result_request->{$id}->{'operation_stat'} eq 'd_upload'){

			unless (exists ($data{'d_upload'})){
				$data{'d_upload'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'}; #get name of list

			unless (exists ($data{'d_upload'}{$r_name}{$l_name})){
				$data{'d_upload'}{$r_name}{$l_name} = 0;
			}

			#on incrémente le nombre de docupents uploadés par liste
			$data{'d_upload'}{$r_name}{$l_name}++;
		}
		#------------------------------test about folder creation in shared----------------
		if($result_request->{$id}->{'operation_stat'} eq 'd_create_dir(directory)'){

			unless (exists ($data{'d_create_directory'})){
				$data{'d_create_directory'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'}; #get name of list

			unless (exists ($data{'d_create_directory'}{$r_name}{$l_name})){
				$data{'d_create_directory'}{$r_name}{$l_name} = 0;
			}

			#on incrémente le nombre de docupents uploadés par liste
			$data{'d_create_directory'}{$r_name}{$l_name}++;
		}

		#------------------------------test about file creation in shared------------------
		if($result_request->{$id}->{'operation_stat'} eq 'd_create_dir(file)'){

			unless (exists ($data{'d_create_file'})){
				$data{'d_create_file'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'}; #get name of list

			unless (exists ($data{'d_create_file'}{$r_name}{$l_name})){
				$data{'d_create_file'}{$r_name}{$l_name} = 0;
			}

			#on incrémente le nombre de docupents uploadés par liste
			$data{'d_create_file'}{$r_name}{$l_name}++;
		}
		#---------------------------------test about archive-----------------------------
		if($result_request->{$id}->{'operation_stat'} eq 'arc'){

			unless(exists ($data{'archive visited'})){
				$data{'archive_visited'} = undef;
			}

			my $r_name = $result_request->{$id}->{'robot_stat'}; #get name of robot
			my $l_name = $result_request->{$id}->{'list_stat'}; #get name of list

			unless (exists ($data{'archive_visited'}{$r_name}{$l_name})){
				$data{'archive_visited'}{$r_name}{$l_name} = 0;
			}

			#on incrémente le nombre de fois ou les archive sont visitées
			$data{'archive_visited'}{$r_name}{$l_name}++;
		}

	}#end of foreach
	return \%data;
}

# subroutine to Update subscriber_table about message send,
# upgrade field number_messages_subscriber
sub _update_subscriber_msg_send {
	my (%params) = @_;
	Sympa::Log::Syslog::do_log('debug2','%s,%s,%s,%s',$params{mail}, $params{list}, $params{robot}, $params{counter});

	$sth = Sympa::SDM::do_query(
		"SELECT number_messages_subscriber from subscriber_table WHERE (robot_subscriber = '%s' AND list_subscriber = '%s' AND user_subscriber = '%s')",
		$params{robot},
		$params{list},
		$params{mail}
	);
	unless ($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve message count for user %s, list %s@%s',$params{mail}, $params{list}, $params{robot});
		return undef;
	}

	my $nb_msg =
		$sth->fetchrow_hashref('number_messages_subscriber') +
		$params{counter};

	my $result = Sympa::SDM::do_query(
		"UPDATE subscriber_table SET number_messages_subscriber = '%d' WHERE (robot_subscriber = '%s' AND list_subscriber = '%s' AND user_subscriber = '%s')",
		$nb_msg,
		$params{robot},
		$params{list},
		$params{mail}
	);
	unless ($result) {
		Sympa::Log::Syslog::do_log('err','Unable to update message count for user %s, list %s@%s',$params{mail}, $params{list}, $params{robot});
		return undef;
	}
	return 1;

}

1;
