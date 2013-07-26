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

=head1 FUNCTIONS

=over

=item fatal_err(@parameters)

FIXME

Parameters:

FIXME

=cut

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
		unless(Sympa::List::send_notify_to_listmaster('logs_failed', Site->domain, [$EVAL_ERROR])) {
			print STDERR "No logs available, can't send warning message";
		}
	};
	$m =~ s/%m/$errno/g;

	my $full_msg = sprintf $m,@_;

	## Notify listmaster
	unless (Sympa::List::send_notify_to_listmaster('sympa_died', Site->domain, [$full_msg])) {
		do_log('err',"Unable to send notify 'sympa died' to listmaster");
	}


	printf STDERR "$m\n", @_;
	exit(1);
}

=item do_log($level, $message, @parameters)

FIXME

Parameters:

=over

=item string

FIXME

=item string

FIXME

=item ...

FIXME

=back

=cut

sub do_log {
    unless (defined $levels{$level}) {
	&do_log('err', 'Invalid $level: "%s"', $level);
	$level = 'info';
    }

    # do not log if log level is too high regarding the log requested by user 
    return if defined $log_level and $levels{$level} > $log_level;
    return if ! defined $log_level and $levels{$level} > 0;

    my $message = shift;
    my @param = ();

    my $errno = $!;

    ## Do not display variables which are references.
    my @n = ($message =~ /(%[^%])/g);
    for (my $i = 0; $i < scalar @n; $i++) {
	my $p = $_[$i];
	unless (defined $p) {
	    # prevent 'Use of uninitialized value' warning
	    push @param, '';
	} elsif (ref $p) {
	    if (ref $p eq 'ARRAY') {
		push @param, '[...]';
	    } elsif (ref $p eq 'HASH') {
		push @param, sprintf('{%s}', join('/', keys %{$p}));
	    } elsif (ref $p eq 'Regexp' or ref $p eq uc ref $p) {
		# other unblessed references
		push @param, ref $p;
	    } elsif ($p->can('get_id')) {
		push @param, sprintf('%s <%s>', ref $p, $p->get_id);
	    } else {
		push @param, ref $p;
	    }
	} else {
	    push @param, $p;
	}
    }

    ## Determine calling function
    my $caller_string;
   
    ## If in 'err' level, build a stack trace,
    ## except if syslog has not been setup yet.
    if (defined $log_level and $level eq 'err'){
	my $go_back = 1;
	my @calls;

	my @f = caller($go_back);
	if ($f[3] =~ /wwslog$/) { ## If called via wwslog, go one step ahead
	    @f = caller(++$go_back);
	}
	@calls = ('#'.$f[2]);
	while (@f = caller(++$go_back)) {
	    $calls[0] = $f[3].$calls[0];
	    unshift @calls, '#'.$f[2];
	}
	$calls[0] = '(top-level)'.$calls[0];

	$caller_string = join(' > ',@calls);
    }else {
	my @call = caller(1);
	
	## If called via wwslog, go one step ahead
	if ($call[3] and $call[3] =~ /wwslog$/) {
	    @call = caller(2);
	}
	
	$caller_string = ($call[3] || '').'()';
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

    ## Output to STDERR if needed
    if (! defined $log_level or
	($main::options{'foreground'} and $main::options{'log_to_stderr'}) or
	($main::options{'foreground'} and $main::options{'batch'} and
	 $level eq 'err')) {
	$message =~ s/%m/$errno/g;
	printf STDERR "$message\n", @param;
    }

    return unless defined $log_level;
    eval {
        unless (syslog($level, $message, @param)) {
            do_connect();
            syslog($level, $message, @param);
        }
    };

    if ($@ && ($warning_date < time - $warning_timeout)) {
	$warning_date = time + $warning_timeout;
	Site->send_notify_to_listmaster('logs_failed', [$@]);
    }
}

=item do_openlog($fac, $socket_type, $service)

FIXME

Parameters:

=over

=item string

FIXME

=item string

FIXME

=item string

FIXME

=back

Return value:

FIXME

=cut

sub do_openlog {
	my ($fac, $socket_type, $service) = @_;
	$service ||= 'sympa';

	($log_facility, $log_socket_type, $log_service) = ($fac, $socket_type, $service);

#   foreach my $k (keys %options) {
#       printf "%s = %s\n", $k, $options{$k};
#   }

	do_connect();
}

=item do_connect()

FIXME

Parameters:

None.

Return value:

FIXME

=cut

sub do_connect {
	if ($log_socket_type =~ /^(unix|inet)$/i) {
		Sys::Syslog::setlogsock(lc($log_socket_type));
	}
	# close log may be usefull : if parent processus did open log child process inherit the openlog with parameters from parent process
	closelog;
	eval {openlog("$log_service\[$PID\]", 'ndelay,nofatal', $log_facility)};
	if($EVAL_ERROR && ($warning_date < time - $warning_timeout)) {
		$warning_date = time + $warning_timeout;
		require Sympa::List;
		unless(Sympa::List::send_notify_to_listmaster('logs_failed', Site->domain, [$EVAL_ERROR])) {
			print STDERR "No logs available, can't send warning message";
		}
	};
}

=item agregate_daily_data($parameters)

FIXME.

Parameters:

=over

=item C<first_date> => number

FIXME

=item C<last_date> => number

FIXME

=item C<hourly_data> => hashref

FIXME

=back

Return value:

FIXME

=cut

sub agregate_daily_data {
	my ($params) = @_;
	do_log('debug2','Agregating data');

	my $result;
	my $first_date = $params->{'first_date'} || time();
	my $last_date = $params->{'last_date'} || time();
	foreach my $begin_date (sort keys %{$params->{'hourly_data'}}) {
		my $reftime = Sympa::Tools::Time::get_midnight_time($begin_date);
		unless (defined $params->{'first_date'}) {
			$first_date = $reftime if ($reftime < $first_date);
		}
		next if ($begin_date < $first_date || $params->{'hourly_data'}{$begin_date}{'end_date_counter'} > $last_date);
		if(defined $result->{$reftime}) {
			$result->{$reftime} += $params->{'hourly_data'}{$begin_date}{'variation_counter'};
		} else {
			$result->{$reftime} = $params->{'hourly_data'}{$begin_date}{'variation_counter'};
		}
	}
	for (my $date = $first_date; $date < $last_date; $date += 86400) {
		$result->{$date} = 0 unless(defined $result->{$date});
	}
	return $result;
}

=item set_log_level($level)

Set the global log level.

FIXME.

Parameters:

=over

=item string

The log level.

=back

Return value:

None.

=cut

sub set_log_level {
	my ($level) = @_;

	$log_level = $level;
}

=item get_log_level()

Get the global log level.

Parameters:

None.

Return value:

The log level.

=cut

sub get_log_level {
	return $log_level;
}

=back

=cut

1;
