# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

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
# along with this program. If not, see <http://www.gnu.org/licenses/>.

=encoding utf-8

=head1 NAME

Sympa::Log::Database - Database-oriented log functions

=head1 DESCRIPTION

This module provides database-oriented logging functions.

=cut

package Sympa::Log::Database;

use strict;

use English qw(-no_match_vars);

use Sympa::Log::Syslog;

my %queries = (
	get_min_date => "SELECT min(date_logs) FROM logs_table",
	get_max_date => "SELECT max(date_logs) FROM logs_table",

	get_subscriber    =>
		'SELECT number_messages_subscriber ' .
		'FROM subscriber_table '             .
		'WHERE ('                            .
			'robot_subscriber = ? AND '  .
			'list_subscriber  = ? AND '  .
			'user_subscriber  = ?'       .
		')',
	update_subscriber =>
		'UPDATE subscriber_table '            .
		'SET number_messages_subscriber = ? ' .
		'WHERE ('                             .
			'robot_subscriber = ? AND '   .
			'list_subscriber  = ? AND '   .
			'user_subscriber  = ?'        .
		')',

	get_data =>
		'SELECT * '                                .
		'FROM stat_table '                         .
		'WHERE '                                   .
			'(date_stat BETWEEN ? AND ?) AND ' .
			'(read_stat = 0)',
	update_data =>
		'UPDATE stat_table '                     .
		'SET read_stat = 1 '                     .
		'WHERE (date_stat BETWEEN ? AND ?)',

	add_log_message =>
		'INSERT INTO logs_table ('                                  .
			'id_logs, date_logs, robot_logs, list_logs, '       .
			'action_logs, parameters_logs, target_email_logs, ' .
			'msg_id_logs, status_logs, error_type_logs, '       .
			'user_email_logs, client_logs, daemon_logs'         .
		') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
	delete_log_message =>
		'DELETE FROM logs_table '           .
		'WHERE (logs_table.date_logs <= ?)',

	add_stat_message =>
		'INSERT INTO stat_table ('                                   .
			'id_stat, date_stat, email_stat, operation_stat, '   .
			'list_stat, daemon_stat, user_ip_stat, robot_stat, ' .
			'parameter_stat, read_stat'                          .
		') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
	add_counter_message =>
		'INSERT INTO stat_counter_table ('                        .
			'id_counter, beginning_date_counter, '            .
			'end_date_counter, data_counter, robot_counter, ' .
			'list_counter, variation_counter'                 .
		') VALUES (?, ?, ?, ?, ?, ?, ?)',
);

my $base;

=head1 FUNCTIONS

=over

=cut

sub init {
	my (%params) = @_;

	$base = $params{base};
}

=item get_log_date()

Parameters:

None.

Return:

=cut

sub get_log_date {
	my @dates;

	my $min_handle = $base->get_query_handle($queries{get_min_date});
	my $min_result = $min_handle->execute();
	unless ($min_result) {
		Sympa::Log::Syslog::do_log('err','Unable to get minimal date from logs_table');
		return undef;
	}
	push @dates, ($min_handle->fetchrow_array)[0];

	my $max_handle = $base->get_query_handle($queries{get_max_date});
	my $max_result = $max_handle->execute();
	unless ($max_result) {
		Sympa::Log::Syslog::do_log('err','Unable to get maximal date from logs_table');
		return undef;
	}
	push @dates, ($max_handle->fetchrow_array)[0];

	return @dates;
}

=item add_event(%parameters)

Add event entry in database.

Parameters:

=over

=item C<list> => FIXME

=item C<robot> => FIXEM

=item C<action> => FIXME

=item C<parameter> => FIXME

=item C<target_email> => FIXME

=item C<user_email> => FIXME

=item C<msg_id> => FIXME

=item C<status> => FIXME

=item C<error_type> => FIXME

=item C<client> => FIXME

=item C<daemon> => FIXME

=back

Return:

=cut

sub add_event {
	my (%params) = @_;

	$params{parameters} = Sympa::Tools::clean_msg_id($params{parameters});
	$params{msg_id}     = Sympa::Tools::clean_msg_id($params{msg_id});
	$params{user_email} = Sympa::Tools::clean_msg_id($params{user_email});

	my $date   = time();
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

	my $handle = $base->get_query_handle(
		$queries{add_log_message},
	);
	my $result = $handle->execute(
		$id,
		$date,
		$params{robot},
		$params{list},
		$params{action},
		substr($params{parameters},0,100),
		$params{target_email},
		$params{msg_id},
		$params{status},
		$params{error_type},
		$params{user_email},
		$params{client},
		$params{daemon}
	);
	unless($result) {
		Sympa::Log::Syslog::do_log('err','Unable to insert new db_log entry in the database');
		return undef;
	}

	return 1;
}

=item add_stat($parameters)

Add stat entry in database.

Parameters:

=over

=item C<list> => FIXME

=item C<robot> => FIXEM

=item C<mail> => FIXME

=item C<operation> => FIXME

=item C<daemon> => FIXME

=item C<ip> => FIXME

=item C<parameter> => FIXME

=back

Return:

=cut

sub add_stat {
	my (%params) = @_;

	my $date   = time();
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

	my $handle = $base->get_query_handle(
		$queries{add_stat_message},
	);
	my $result = $handle->execute(
		$id,
		$date,
		$params{mail},
		$params{operation},
		$params{list},
		$params{daemon},
		$params{ip},
		$params{robot},
		$params{parameter},
		0
	);
	unless($result) {
		Sympa::Log::Syslog::do_log('err','Unable to insert new stat entry in the database');
		return undef;
	}
	return 1;
}

sub _add_stat_counter {
	my (%params) = @_;

	my $random = int(rand(1000000));
	my $id = $params{begin_date}.$random;

	if($params{list} =~ /(.+)\@(.+)/) {#remove the robot name of the list name
		$params{list} = $1;
		unless($params{robot}) {
			$params{robot} = $2;
		}
	}

	my $handle = $base->get_query_handle(
		$queries{add_counter_message},
	);
	my $result = $handle->execute(
		$id,
		$params{begin_date},
		$params{end_date},
		$params{data},
		$params{robot},
		$params{list},
		$params{variation},
	);
	unless($result) {
		Sympa::Log::Syslog::do_log('err','Unable to insert new stat counter entry in the database');
		return undef;
	}
	return 1;

}

=item delete_events($age)

Delete event entry from database.

Parameters:

=over

=item number

The minimum age of events to delete (in months)

=back

Return:

A true value on success.

=cut

sub delete_events {
	my ($age) = @_;
	my $date = time() - ($age * 30 * 24 * 60 * 60);

	my $handle = $base->get_query_handle(
		$queries{delete_log_message},
	);
	my $result = $handle->execute(
		$date
	);
	unless ($result) {
		Sympa::Log::Syslog::do_log('err','Unable to delete db_log entry from the database');
		return undef;
	}
	return 1;

}

=item aggregate_stats($begin_date, $end_date)

Aggregate stats entries in database.

Parameters:

=over

=item timestamp

=item timestamp

=back

Return:

A true value on success

=cut

sub aggregate_stats {
	my ($begin_date, $end_date) = @_;

	# retrieve new stats (read_stat value is 0)
	my $get_handle = $base->get_query_handle(
		$queries{get_data},
	);
	my $get_result = $get_handle->execute(
		$begin_date,
		$end_date
	);
	unless ($get_result) {
		Sympa::log::Syslog::do_log('err','Unable to retrieve stat entries between date % and date %s', $begin_date, $end_date);
		return undef;
	}

	my $raw_stats = $get_handle->fetchall_hashref('id_stat');

	# mark stats as read (flip read_stat value to 1)
	my $update_handle = $base->get_query_handle(
		$queries{update_data},
	);
	my $update_result = $update_handle->execute(
		$begin_date,
		$end_date
	);
	unless ($update_result) {
		Sympa::Log::Syslog::do_log('err','Unable to set stat entries between date % and date %s as read', $begin_date, $end_date);
		return undef;
	}

	my $aggregated_stats = _get_aggregated_stats($raw_stats);
	_store_aggregated_stats($aggregated_stats, $begin_date, $end_date);

	my $local_begin_date = localtime($begin_date);
	my $local_end_date   = localtime($end_date);
	Sympa::Log::Syslog::do_log('debug2', 'data aggregated from %s to %s', $local_begin_date, $local_end_date);

	return 1;
}

sub _store_aggregated_stats {
	my ($stats, $begin_date, $end_date) = @_;

	foreach my $operation (keys %{$stats}) {
		my $stat = $stats->{$operation};

		if ($operation eq 'send_mail') {
			foreach my $robot (keys %{$stat}) {
				foreach my $list (keys %{$stat->{$robot}}) {
					_add_stat_counter(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $operation,
						list       => $list,
						variation  => $stat->{$robot}->{$list}->{'count'},
						robot      => $robot
					);

					foreach my $mail (keys %{$stat->{$robot}->{$list}}) {
						next if $mail eq 'count';
						next if $mail eq 'size';

						_update_subscriber_msg_send(
							mail    => $mail,
							list    => $list,
							robot   => $robot,
							counter => $stat->{$robot}->{$list}->{$mail}
						);
					}
				}
			}
		}

		if ($operation eq 'add_subscriber') {
			foreach my $robot (keys %{$stat}) {
				foreach my $list (keys %{$stat->{$robot}}) {
					_add_stat_counter(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $operation,
						list       => $list,
						variation  => $stat->{$robot}->{$list}->{count},
						robot      => $robot
					);
				}
			}
		}

		if ($operation eq 'del_subscriber') {
			foreach my $robot (keys %{$stat}) {
				foreach my $list (keys %{$stat->{$robot}}) {
					foreach my $param (keys %{$stat->{$robot}->{$list}}) {
						_add_stat_counter(
							begin_date => $begin_date,
							end_date   => $end_date,
							data       => $param,
							list       => $list,
							variation  => $stat->{$robot}->{$list}->{$param},
							robot      => $robot
						);
					}
				}
			}
		}

		if ($operation eq 'create_list') {
			foreach my $robot (keys %{$stat}) {
				_add_stat_counter(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $operation,
					variation  => $stat->{$robot},
					robot      => $robot
				);
			}
		}

		if ($operation eq 'copy_list') {
			foreach my $robot (keys %{$stat}) {
				_add_stat_counter(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $operation,
					variation  => $stat->{$robot},
					robot      => $robot
				);
			}
		}

		if ($operation eq 'close_list') {
			foreach my $robot (keys %{$stat}) {
				_add_stat_counter(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $operation,
					variation  => $stat->{$robot},
					robot      => $robot
				);
			}
		}

		if ($operation eq 'purge_list') {
			foreach my $robot (keys %{$stat}) {
				_add_stat_counter(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $operation,
					variation  => $stat->{$robot},
					robot      => $robot
				);
			}
		}

		if ($operation eq 'reject') {
			foreach my $robot (keys %{$stat}) {
				foreach my $list (keys %{$stat->{$robot}}) {
					_add_stat_counter(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $operation,
						list       => $list,
						variation  => $stat->{$robot}->{$list},
						robot      => $robot
					);
				}
			}
		}

		if ($operation eq 'list_rejected') {
			foreach my $robot (keys %$stat) {
				_add_stat_counter(
					begin_date => $begin_date,
					end_date   => $end_date,
					data       => $operation,
					variation  => $stat->{$robot},
					robot      => $robot
				);
			}
		}

		if ($operation eq 'd_upload') {
			foreach my $robot (keys %{$stat}) {
				foreach my $list (keys %{$stat->{$robot}}) {
					_add_stat_counter(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $operation,
						list       => $list,
						variation  => $stat->{$robot}->{$list},
						robot      => $robot
					);
				}
			}
		}

		if ($operation eq 'd_create_directory') {
			foreach my $robot (keys %{$stat}) {
				foreach my $list (keys %{$stat->{$robot}}) {
					_add_stat_counter(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $operation,
						list       => $list,
						variation  => $stat->{$robot}->{$list},
						robot      => $robot
					);
				}
			}
		}

		if ($operation eq 'd_create_file') {
			foreach my $robot (keys %{$stat}) {
				foreach my $list (keys %{$stat->{$robot}}) {
					_add_stat_counter(
						begin_date => $begin_date,
						end_date   => $end_date,
						data       => $operation,
						list       => $list,
						variation  => $stat->{$robot}->{$list},
						robot      => $robot
					);
				}
			}
		}
	}
}

sub _get_aggregated_stats {
	my ($input_stats) = @_;

	my $output_stats;

	foreach my $input_stat (values %{$input_stats}) {
		my $operation = $input_stat->{operation_stat};

		if ($operation eq 'send_mail') {
			my $robot = $input_stat->{robot_stat};
			my $list  = $input_stat->{list_stat};
			my $email = $input_stat->{email_stat};

			if (!$output_stats->{send_mail}{$robot}{$list}) {
				$output_stats->{send_mail}{$robot}{$list} = {
					size  => 0,
					count => 0,
				};
			}
			my $output_stat = $output_stats->{send_mail}{$robot}{$list};
			$output_stat->{size} += $input_stat->{parameter_stat};
			$output_stat->{count}++;
			$output_stat->{$email} = $output_stat->{$email} ?
				$output_stat->{$email} + 1 : 1;
			next;
		}

		if ($operation eq 'add_subscriber') {
			my $robot = $input_stat->{robot_stat};
			my $list  = $input_stat->{list_stat};
			my $count =
				$output_stats->{add_subscriber}{$robot}{$list}{count};
			$output_stats->{add_subscriber}{$robot}{$list}{count} =
				$count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'del subscriber') {
			my $robot = $input_stat->{robot_stat};
			my $list  = $input_stat->{list_stat};
			my $param = $input_stat->{parameter_stat};
			my $count =
				$output_stats->{del_subscriber}{$robot}{$list}{$param};
			$output_stats->{del_subscriber}{$robot}{$list}{$param} =
				$count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'create_list') {
			my $robot = $input_stat->{robot_stat};
			my $count = $output_stats->{create_list}{$robot};
			$output_stats->{create_list}{$robot} = $count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'copy_list') {
			my $robot = $input_stat->{robot_stat};
			my $count = $output_stats->{copy_list}{$robot};
			$output_stats->{copy_list}{$robot} = $count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'close_list') {
			my $robot = $input_stat->{robot_stat};
			my $count = $output_stats->{close_list}{$robot};
			$output_stats->{close_list}{$robot} = $count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'purge list') {
			my $robot = $input_stat->{robot_stat};
			my $count = $output_stats->{purge_list}{$robot};
			$output_stats->{purge_list}{$robot} = $count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'reject') {
			my $robot = $input_stat->{'robot_stat'};
			my $list  = $input_stat->{'list_stat'};
			my $count = $output_stats->{reject}{$robot}{$list};
			$output_stats->{reject}{$robot}{$list} = $count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'list_rejected') {
			my $robot = $input_stat->{robot_stat};
			my $count = $output_stats->{liste_rejected}{$robot};
			$output_stats->{list_rejected}{$robot} = $count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'd_upload') {
			my $robot = $input_stat->{robot_stat};
			my $list  = $input_stat->{list_stat};
			my $count = $output_stats->{d_upload}{$robot}{$list};
			$output_stats->{d_upload}{$robot}{$list} =
				$count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'd_create_dir(directory)') {
			my $robot = $input_stat->{robot_stat};
			my $list  = $input_stat->{list_stat};
			my $count = $output_stats->{d_create_directory}{$robot}{$list};
			$output_stats->{d_create_directory}{$robot}{$list} =
				$count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'd_create_dir(file)') {
			my $robot = $input_stat->{robot_stat};
			my $list  = $input_stat->{list_stat};
			my $count = $output_stats->{d_create_file}{$robot}{$list};
			$output_stats->{d_create_file}{$robot}{$list} =
				$count ? $count + 1 : 1;
			next;
		}

		if ($operation eq 'arc') {
			my $robot = $input_stat->{robot_stat};
			my $list  = $input_stat->{list_stat};
			my $count = $output_stats->{archive_visited}{$robot}{$list};
			$output_stats->{archive_visited}{$robot}{$list} =
				$count ? $count + 1 : 1;
			next;
		}
	}

	return $output_stats;
}

# subroutine to Update subscriber_table about message send,
# upgrade field number_messages_subscriber
sub _update_subscriber_msg_send {
	my (%params) = @_;
	Sympa::Log::Syslog::do_log('debug2','%s,%s,%s,%s',$params{mail}, $params{list}, $params{robot}, $params{counter});

	my $get_handle = $base->get_query_handle(
		$queries{get_subscribers},
	);
	my $get_result = $get_handle->execute(
		$params{robot},
		$params{list},
		$params{mail}
	);
	unless ($get_result) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve message count for user %s, list %s@%s',$params{mail}, $params{list}, $params{robot});
		return undef;
	}

	my $nb_msg =
		$get_handle->fetchrow_hashref('number_messages_subscriber') +
		$params{counter};

	my $update_handle = $base->get_query_handle(
		$queries{update_subscribers},
	);
	my $update_result = $update_handle->execute(
		$nb_msg,
		$params{robot},
		$params{list},
		$params{mail}
	);
	unless ($update_result) {
		Sympa::Log::Syslog::do_log('err','Unable to update message count for user %s, list %s@%s',$params{mail}, $params{list}, $params{robot});
		return undef;
	}
	return 1;

}

=back

=cut

1;
