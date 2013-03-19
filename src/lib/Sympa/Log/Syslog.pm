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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Log::Syslog - Syslog-oriented log functions

=head1 DESCRIPTION

This module provides syslog-oriented logging functions

=cut

package Sympa::Log::Syslog;

use strict;

use English qw(-no_match_vars);
use POSIX qw();
use Sys::Syslog;

#use Sympa::Configuration; # FIXME
use Sympa::Tools::Time;

my ($log_facility, $log_socket_type, $log_service);
# When logs are not available, period of time to wait before sending another warning to listmaster.
my $warning_timeout = 600;
# Date of the last time a message was sent to warn the listmaster that the logs are unavailable.
my $warning_date = 0;

my $log_level = 0;

our %levels = (
	err    => 0,
	info   => 0,
	notice => 0,
	trace  => 0,
	debug  => 1,
	debug2 => 2,
	debug3 => 3,
);

sub fatal_err {
	my ($m) = @_;

	my $errno  = $ERRNO;

	require Sympa::List;

	eval {
		syslog('err', $m, @_);
		syslog('err', "Exiting.");
	};
	if($EVAL_ERROR && ($warning_date < time - $warning_timeout)) {
		$warning_date = time + $warning_timeout;
		unless(Sympa::List::send_notify_to_listmaster('logs_failed', $Sympa::Configuration::Conf{'domain'}, [$EVAL_ERROR])) {
			print STDERR "No logs available, can't send warning message";
		}
	};
	$m =~ s/%m/$errno/g;

	my $full_msg = sprintf $m,@_;

	## Notify listmaster
	unless (Sympa::List::send_notify_to_listmaster('sympa_died', $Sympa::Configuration::Conf{'domain'}, [$full_msg])) {
		do_log('err',"Unable to send notify 'sympa died' to listmaster");
	}


	printf STDERR "$m\n", @_;
	exit(1);
}

sub do_log {
	my ($level, $message, @param) = @_;

	# do not log if log level if too high regarding the log requested by user
	return if ($levels{$level} > $log_level);

	my $errno = $ERRNO;

	## Do not display variables which are references.
	foreach my $p (@param) {
		unless (defined $p) {
			$p = ''; # prevent 'Use of uninitialized value' warning
		} elsif (ref $p) {
			$p = ref $p;
		}
	}

	## Determine calling function
	my $caller_string;

	## If in 'err' level, build a stack trace
	if ($level eq 'err'){
		my $go_back = 1;
		my @calls;
		while (my @call = caller($go_back)) {
			unshift @calls, $call[3].'#'.$call[2];
			$go_back++;
		}

		$caller_string = join(' > ',@calls);
	}else {
		my @call = caller(1);

		## If called via wwslog, go one step ahead
		if ($call[3] =~ /wwslog$/) {
			my @call = caller(2);
		}

		$caller_string = $call[3].'()';
	}

	$message = $caller_string. ' ' . $message if ($caller_string);

	## Add facility to log entry
	$message = $level.' '.$message;

	# map to standard syslog facility if needed
	if ($level eq 'trace' ) {
		$message = "###### TRACE MESSAGE ######:  " . $message;
		$level = 'notice';
	} elsif ($level eq 'debug2' || $level eq 'debug3') {
		$level = 'debug';
	}

	eval {
		unless (syslog($level, $message, @param)) {
			do_connect();
			syslog($level, $message, @param);
		}
	};

	if ($EVAL_ERROR && ($warning_date < time - $warning_timeout)) {
		$warning_date = time + $warning_timeout;
		require Sympa::List;
		Sympa::List::send_notify_to_listmaster(
			'logs_failed', $Sympa::Configuration::Conf{'domain'}, [$EVAL_ERROR]
		);
	};

	if ($main::options{'foreground'}) {
		if (
			$main::options{'log_to_stderr'} ||
			($main::options{'batch'} && $level eq 'err')
		) {
			$message =~ s/%m/$errno/g;
			printf STDERR "$message\n", @param;
		}
	}
}


sub do_openlog {
	my ($fac, $socket_type, $service) = @_;
	$service ||= 'sympa';

	($log_facility, $log_socket_type, $log_service) = ($fac, $socket_type, $service);

#   foreach my $k (keys %options) {
#       printf "%s = %s\n", $k, $options{$k};
#   }

	do_connect();
}

sub do_connect {
	if ($log_socket_type =~ /^(unix|inet)$/i) {
		Sys::Syslog::setlogsock(lc($log_socket_type));
	}
	# close log may be usefull : if parent processus did open log child process inherit the openlog with parameters from parent process
	closelog ;
	eval {openlog("$log_service\[$PID\]", 'ndelay,nofatal', $log_facility)};
	if($EVAL_ERROR && ($warning_date < time - $warning_timeout)) {
		$warning_date = time + $warning_timeout;
		require Sympa::List;
		unless(Sympa::List::send_notify_to_listmaster('logs_failed', $Sympa::Configuration::Conf{'domain'}, [$EVAL_ERROR])) {
			print STDERR "No logs available, can't send warning message";
		}
	};
}

# return the name of the used daemon
sub set_daemon {
	my ($daemon_tmp) = @_;

	my @path = split(/\//, $daemon_tmp);
	my $daemon = $path[$#path];
	$daemon =~ s/(\.[^\.]+)$//;
	return $daemon;
}

sub agregate_daily_data {
	my ($params) = @_;
	do_log('debug2','Agregating data');

	my $result;
	my $first_date = $params->{'first_date'} || time;
	my $last_date = $params->{'last_date'} || time;
	foreach my $begin_date (sort keys %{$params->{'hourly_data'}}) {
		my $reftime = Sympa::Tools::Time::get_midnight_time($begin_date);
		unless (defined $params->{'first_date'}) {
			$first_date = $reftime if ($reftime < $first_date);
		}
		next if ($begin_date < $first_date || $params->{'hourly_data'}{$begin_date}{'end_date_counter'} > $last_date);
		if(defined $result->{$reftime}) {
			$result->{$reftime} += $params->{'hourly_data'}{$begin_date}{'variation_counter'};
		}else{
			$result->{$reftime} = $params->{'hourly_data'}{$begin_date}{'variation_counter'};
		}
	}
	for (my $date = $first_date; $date < $last_date; $date += 86400) {
		$result->{$date} = 0 unless(defined $result->{$date});
	}
	return $result;
}

sub set_log_level {
	my ($level) = @_;

	$log_level = $level;
}

sub get_log_level {
	return $log_level;
}

1;
