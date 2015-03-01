# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014, 2015 GIP RENATER
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

package Log;

use strict;
use warnings;
use English qw(-no_match_vars);
use POSIX qw();
use Scalar::Util;
use Sys::Syslog qw();

use SDM;
use Sympa::Tools::Time;

my ($log_facility, $log_socket_type, $log_service, $sth, @sth_stack,
    $rows_nb);
# When logs are not available, period of time to wait before sending another
# warning to listmaster.
my $warning_timeout = 600;
# Date of the last time a message was sent to warn the listmaster that the
# logs are unavailable.
my $warning_date = 0;

our $log_level = undef;

my %levels = (
    err    => 0,
    info   => 0,
    notice => 0,
    trace  => 0,
    debug  => 1,
    debug2 => 2,
    debug3 => 3,
);

# Deprecated: No longer used.
#sub fatal_err;

sub do_log {
    my $level   = shift;
    my $message = shift;
    my $errno   = $ERRNO;

    unless (exists $levels{$level}) {
        do_log('err', 'Invalid $level: "%s"', $level);
        $level = 'info';
    }

    # do not log if log level is too high regarding the log requested by user
    return if defined $log_level  and $levels{$level} > $log_level;
    return if !defined $log_level and $levels{$level} > 0;

    ## Do not display variables which are references.
    my @param = ();
    foreach my $fstring (($message =~ /(%.)/g)) {
        next if $fstring eq '%%' or $fstring eq '%m';

        my $p = shift @_;
        unless (defined $p) {
            # prevent 'Use of uninitialized value' warning
            push @param, '';
        } elsif (Scalar::Util::blessed($p) and $p->can('get_id')) {
            push @param, sprintf('%s <%s>', ref $p, $p->get_id);
        } elsif (ref $p eq 'Regexp') {
            push @param, "qr<$p>";
        } elsif (ref $p) {
            push @param, ref $p;
        } else {
            push @param, $p;
        }
    }
    $message =~ s/(%.)/($1 eq '%m') ? '%%%%errno%%%%' : $1/eg;
    $message = sprintf $message, @param;
    $message =~ s/%%errno%%/$errno/g;

    ## If in 'err' level, build a stack trace,
    ## except if syslog has not been setup yet.
    if (defined $log_level and $level eq 'err') {
        my $go_back = 0;
        my @calls;

        my @f = caller($go_back);
        #if ($f[3] and $f[3] =~ /wwslog$/) {
        #    ## If called via wwslog, go one step ahead
        #    @f = caller(++$go_back);
        #}
        @calls = '#' . $f[2];
        while (@f = caller(++$go_back)) {
            if ($f[3] and $f[3] =~ /\ASympa::Crash::/) {
                # Discard trace inside crash handler.
                @calls = '#' . $f[2];
            } else {
                $calls[0] = ($f[3] || '') . $calls[0];
                unshift @calls, '#' . $f[2];
            }
        }
        $calls[0] = 'main::' . $calls[0];

        my $caller_string = join ' > ', @calls;
        $message = "$caller_string $message";
    } else {
        my @call = caller(1);
        ## If called via wwslog, go one step ahead
        #if ($call[3] and $call[3] =~ /wwslog$/) {
        #    @call = caller(2);
        #}

        my $caller_string = $call[3];
        if (defined $caller_string and length $caller_string) {
            if ($message =~ /\A[(].*[)]/) {
                $message = "$caller_string$message";
            } else {
                $message = "$caller_string() $message";
            }
        } else {
            $message = "main:: $message";
        }
    }

    ## Add facility to log entry
    $message = "$level $message";

    # map to standard syslog facility if needed
    if ($level eq 'trace') {
        $message = "###### TRACE MESSAGE ######:  " . $message;
        $level   = 'notice';
    } elsif ($level eq 'debug2' or $level eq 'debug3') {
        $level = 'debug';
    }

    ## Output to STDERR if needed
    if (   !defined $log_level
        or ($main::options{'foreground'} and $main::options{'log_to_stderr'})
        or (    $main::options{'foreground'}
            and $main::options{'batch'}
            and $level eq 'err')
        ) {
        print STDERR "$message\n";
    }
    return unless defined $log_level;

    # Output to syslog
    # Note: Sys::Syslog <= 0.07 which are bundled in Perl <= 5.8.7 pass
    # $message to sprintf() even when no arguments are given.  As a
    # workaround, always pass format string '%s' along with $message.
    eval {
        unless (Sys::Syslog::syslog($level, '%s', $message)) {
            _do_connect();
            Sys::Syslog::syslog($level, '%s', $message);
        }
    };
    if ($EVAL_ERROR and $warning_date < time - $warning_timeout) {
        warn sprintf 'No logs available: %s', $EVAL_ERROR;
        $warning_date = time + $warning_timeout;
    }
}

sub do_openlog {
    my $facility    = shift;
    my $socket_type = shift;
    my %options     = @_;

    $log_service = $options{service} || _daemon_name() || 'sympa';
    ($log_facility, $log_socket_type) = ($facility, $socket_type);

    return _do_connect();
}

# Old names: Log::set_daemon(), Sympa::Tools::Daemon::get_daemon_name().
sub _daemon_name {
    my @path = split /\//, $PROGRAM_NAME;
    my $service = $path[$#path];
    $service =~ s/(\.[^\.]+)$//;
    return $service;
}

# Old name: Log::do_connect().
sub _do_connect {
    if ($log_socket_type =~ /^(unix|inet)$/i) {
        Sys::Syslog::setlogsock(lc($log_socket_type));
    }
    # close log may be usefull : if parent processus did open log child
    # process inherit the openlog with parameters from parent process
    Sys::Syslog::closelog;
    eval {
        Sys::Syslog::openlog("$log_service\[$PID\]", 'ndelay,nofatal',
            $log_facility);
    };
    if ($EVAL_ERROR && ($warning_date < time - $warning_timeout)) {
        warn sprintf 'No logs available: %s', $EVAL_ERROR;
        $warning_date = time + $warning_timeout;
        return undef;
    }

    return 1;
}

sub get_log_date {
    my $sth;
    my @dates;
    foreach my $query ('MIN', 'MAX') {
        unless ($sth =
            SDM::do_query("SELECT $query(date_logs) FROM logs_table")) {
            do_log('err', 'Unable to get %s date from logs_table', $query);
            return undef;
        }
        while (my $d = ($sth->fetchrow_array)[0]) {
            push @dates, $d;
        }
    }

    return @dates;
}

# add log in RDBMS
sub db_log {
    my $arg = shift;

    my $list         = $arg->{'list'};
    my $robot        = $arg->{'robot'};
    my $action       = $arg->{'action'};
    my $parameters   = $arg->{'parameters'};
    my $target_email = $arg->{'target_email'};
    my $msg_id       = $arg->{'msg_id'};
    my $status       = $arg->{'status'};
    my $error_type   = $arg->{'error_type'};
    my $user_email   = $arg->{'user_email'};
    my $client       = $arg->{'client'};
    my $daemon       = $log_service || 'sympa';
    my $date         = time;
    my $random       = int(rand(1000000));
    # my $id = $date * 1000000 + $random;
    my $id = $date . $random;

    unless ($user_email) {
        $user_email = 'anonymous';
    }
    unless (defined $list and length $list) {
        $list = '';
    } elsif ($list =~ /(.+)\@(.+)/) {
        #remove the robot name of the list name
        $list = $1;
        unless ($robot) {
            $robot = $2;
        }
    }

    # Insert in log_table
    unless (
        SDM::do_prepared_query(
            q{INSERT INTO logs_table
              (id_logs, date_logs, robot_logs, list_logs, action_logs,
               parameters_logs,
               target_email_logs, msg_id_logs, status_logs, error_type_logs,
               user_email_logs, client_logs, daemon_logs)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
            $id, $date, $robot, $list, $action,
            substr($parameters || '', 0, 100),
            $target_email, $msg_id, $status, $error_type,
            $user_email,   $client, $daemon
        )
        ) {
        do_log('err', 'Unable to insert new db_log entry in the database');
        return undef;
    }

    return 1;
}

#insert data in stats table
sub db_stat_log {
    my $arg = shift;

    my $list      = $arg->{'list'};
    my $operation = $arg->{'operation'};
    my $date      = time;
    my $mail      = $arg->{'mail'};
    my $daemon    = $log_service || 'sympa';
    my $ip        = $arg->{'client'};
    my $robot     = $arg->{'robot'};
    my $parameter = $arg->{'parameter'};
    my $random    = int(rand(1000000));
    my $id        = $date . $random;
    my $read      = 0;

    if (ref $list eq 'Sympa::List') {
        $list = $list->{'name'};
    } elsif ($list and $list =~ /(.+)\@(.+)/) {
        #remove the robot name of the list name
        $list = $1;
        unless ($robot) {
            $robot = $2;
        }
    }

    ##insert in stat table
    unless (
        SDM::do_prepared_query(
            q{INSERT INTO stat_table
              (id_stat, date_stat, email_stat, operation_stat, list_stat,
               daemon_stat, user_ip_stat, robot_stat, parameter_stat,
               read_stat)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
            $id,     $date, $mail,  $operation, $list,
            $daemon, $ip,   $robot, $parameter,
            $read
        )
        ) {
        do_log('err', 'Unable to insert new stat entry in the database');
        return undef;
    }
    return 1;
}

# delete logs in RDBMS
# MOVED to _db_log_del() in task_manager.pl.
#sub db_log_del;

# Scan log_table with appropriate select
sub get_first_db_log {
    my $select = shift;

    my %action_type = (
        'message' => [
            'reject',       'distribute',  'arc_delete',   'arc_download',
            'sendMessage',  'remove',      'record_email', 'send_me',
            'd_remove_arc', 'rebuildarc',  'remind',       'send_mail',
            'DoFile',       'sendMessage', 'DoForward',    'DoMessage',
            'DoCommand',    'SendDigest'
        ],
        'authentication' => [
            'login',        'logout',
            'loginrequest', 'requestpasswd',
            'ssologin',     'ssologin_succeses',
            'remindpasswd', 'choosepasswd'
        ],
        'subscription' =>
            ['subscribe', 'signoff', 'add', 'del', 'ignoresub', 'subindex'],
        'list_management' => [
            'create_list',          'rename_list',
            'close_list',           'edit_list',
            'admin',                'blacklist',
            'install_pending_list', 'purge_list',
            'edit_template',        'copy_template',
            'remove_template'
        ],
        'bounced'     => ['resetbounce', 'get_bounce'],
        'preferences' => [
            'set',       'setpref', 'pref', 'change_email',
            'setpasswd', 'editsubscriber'
        ],
        'shared' => [
            'd_unzip',                'd_upload',
            'd_read',                 'd_delete',
            'd_savefile',             'd_overwrite',
            'd_create_dir',           'd_set_owner',
            'd_change_access',        'd_describe',
            'd_rename',               'd_editfile',
            'd_admin',                'd_install_shared',
            'd_reject_shared',        'd_properties',
            'creation_shared_file',   'd_unzip_shared_file',
            'install_file_hierarchy', 'd_copy_rec_dir',
            'd_copy_file',            'change_email',
            'set_lang',               'new_d_read',
            'd_control'
        ],
    );

    my $statement =
        sprintf
        "SELECT date_logs, robot_logs AS robot, list_logs AS list, action_logs AS action, parameters_logs AS parameters, target_email_logs AS target_email,msg_id_logs AS msg_id, status_logs AS status, error_type_logs AS error_type, user_email_logs AS user_email, client_logs AS client, daemon_logs AS daemon FROM logs_table WHERE robot_logs=%s ",
        SDM::quote($select->{'robot'});

    #if a type of target and a target are specified
    if (($select->{'target_type'}) && ($select->{'target_type'} ne 'none')) {
        if ($select->{'target'}) {
            $select->{'target_type'} = lc($select->{'target_type'});
            $select->{'target'}      = lc($select->{'target'});
            $statement .= 'AND '
                . $select->{'target_type'}
                . '_logs = '
                . SDM::quote($select->{'target'}) . ' ';
        }
    }

    #if the search is between two date
    if ($select->{'date_from'}) {
        my ($yyyy, $mm, $dd) = split /[^\da-z]/i, $select->{'date_from'};
        ($dd, $mm, $yyyy) = ($yyyy, $mm, $dd) if 31 < $dd;
        $yyyy += ($yyyy < 50 ? 2000 : $yyyy < 100 ? 1900 : 0);

        my $date_from = POSIX::mktime(0, 0, -1, $dd, $mm - 1, $yyyy - 1900);
        unless ($select->{'date_to'}) {
            my $date_from2 =
                POSIX::mktime(0, 0, 25, $dd, $mm - 1, $yyyy - 1900);
            $statement .= sprintf "AND date_logs >= %s AND date_logs <= %s ",
                $date_from, $date_from2;
        } else {
            my ($yyyy, $mm, $dd) = split /[^\da-z]/i, $select->{'date_to'};
            ($dd, $mm, $yyyy) = ($yyyy, $mm, $dd) if 31 < $dd;
            $yyyy += ($yyyy < 50 ? 2000 : $yyyy < 100 ? 1900 : 0);

            my $date_to = POSIX::mktime(0, 0, 25, $dd, $mm - 1, $yyyy - 1900);
            $statement .= sprintf "AND date_logs >= %s AND date_logs <= %s ",
                $date_from, $date_to;
        }
    }

    #if the search is on a precise type
    if ($select->{'type'}) {
        if (   ($select->{'type'} ne 'none')
            && ($select->{'type'} ne 'all_actions')) {
            my $first = 'false';
            foreach my $type (@{$action_type{$select->{'type'}}}) {
                if ($first eq 'false') {
                    #if it is the first action, put AND on the statement
                    $statement .=
                        sprintf "AND (logs_table.action_logs = '%s' ", $type;
                    $first = 'true';
                }
                #else, put OR
                else {
                    $statement .= sprintf "OR logs_table.action_logs = '%s' ",
                        $type;
                }
            }
            $statement .= ')';
        }

    }

    # if the listmaster want to make a search by an IP address.
    if ($select->{'ip'}) {
        $statement .= sprintf ' AND client_logs = %s ',
            SDM::quote($select->{'ip'});
    }

    ## Currently not used
    #if the search is on the actor of the action
    if ($select->{'user_email'}) {
        $select->{'user_email'} = lc($select->{'user_email'});
        $statement .= sprintf "AND user_email_logs = '%s' ",
            $select->{'user_email'};
    }

    #if a list is specified -just for owner or above-
    if ($select->{'list'}) {
        $select->{'list'} = lc($select->{'list'});
        $statement .= sprintf "AND list_logs = '%s' ", $select->{'list'};
    }

    $statement .= sprintf "ORDER BY date_logs ";

    push @sth_stack, $sth;
    unless ($sth = SDM::do_query($statement)) {
        do_log('err', 'Unable to retrieve logs entry from the database');
        return undef;
    }

    my $log = $sth->fetchrow_hashref('NAME_lc');

    ## If no rows returned, return an empty hash
    ## Required to differenciate errors and empty results
    unless ($log) {
        return {};
    }

    ## We can't use the "AS date" directive in the SELECT statement because
    ## "date" is a reserved keywork with Oracle
    $log->{date} = $log->{date_logs} if defined($log->{date_logs});
    return $log;

}

sub return_rows_nb {
    return $rows_nb;
}

sub get_next_db_log {

    my $log = $sth->fetchrow_hashref('NAME_lc');

    unless (defined $log) {
        $sth->finish;
        $sth = pop @sth_stack;
    }

    ## We can't use the "AS date" directive in the SELECT statement because
    ## "date" is a reserved keywork with Oracle
    $log->{date} = $log->{date_logs} if defined($log->{date_logs});

    return $log;
}

sub set_log_level {
    $log_level = shift;
}

#OBSOLETED: No longer used.
sub get_log_level {
    return $log_level;
}

# Aggregate data from stat_table to stat_counter_table.
# Dates must be in epoch format.
my @robot_operations = qw{close_list copy_list create_list list_rejected
    login logout purge_list restore_list};

sub aggregate_data {
    my ($begin_date, $end_date) = @_;

    # Store reslults in stat_counter_table.
    my $cond;

    # Store data by each list.
    $cond = join ' AND ', map {"operation_stat <> '$_'"} @robot_operations;
    SDM::do_prepared_query(
        sprintf(
            q{INSERT INTO stat_counter_table
              (beginning_date_counter, end_date_counter, data_counter,
               robot_counter, list_counter, count_counter)
              SELECT ?, ?, operation_stat, robot_stat, list_stat, COUNT(*)
              FROM stat_table
              WHERE ? <= date_stat AND date_stat < ?
                    AND list_stat IS NOT NULL AND list_stat <> ''
                    AND read_stat = 0 AND %s
              GROUP BY robot_stat, list_stat, operation_stat},
            $cond
        ),
        $begin_date,
        $end_date,
        $begin_date,
        $end_date
    );

    # Store data by each robot.
    $cond = join ' OR ', map {"operation_stat = '$_'"} @robot_operations;
    SDM::do_prepared_query(
        sprintf(
            q{INSERT INTO stat_counter_table
              (beginning_date_counter, end_date_counter, data_counter,
               robot_counter, list_counter, count_counter)
              SELECT ?, ?, operation_stat, robot_stat, '', COUNT(*)
              FROM stat_table
              WHERE ? <= date_stat AND date_stat < ?
                    AND read_stat = 0 AND (%s)
              GROUP BY robot_stat, operation_stat},
            $cond
        ),
        $begin_date,
        $end_date,
        $begin_date,
        $end_date
    );

    # Update subscriber_table about messages sent, upgrade field
    # number_messages_subscriber.
    my $sth;
    my $row;
    if ($sth = SDM::do_prepared_query(
            q{SELECT COUNT(*) AS "count",
                     robot_stat AS robot, list_stat AS list,
                     email_stat AS email
              FROM stat_table
              WHERE ? <= date_stat AND date_stat < ?
                    AND read_stat = 0 AND operation_stat = 'send_mail'
              GROUP BY robot_stat, list_stat, email_stat},
            $begin_date, $end_date
        )
        ) {
        while ($row = $sth->fetchrow_hashref('NAME_lc')) {
            SDM::do_prepared_query(
                q{UPDATE subscriber_table
                      SET number_messages_subscriber =
                          number_messages_subscriber + ?
                      WHERE robot_subscriber = ? AND list_subscriber = ? AND
                            email_subscriber = ?},
                $row->{'count'},
                $row->{'robot'}, $row->{'list'},
                $row->{'email'}
            );
        }
        $sth->finish;
    }

    # The rows were read, so update the read_stat from 0 to 1.
    unless (
        $sth = SDM::do_prepared_query(
            q{UPDATE stat_table
              SET read_stat = 1
              WHERE ? <= date_stat AND date_stat < ?},
            $begin_date, $end_date
        )
        ) {
        Log::do_log('err',
            'Unable to set stat entries between date % and date %s as read',
            $begin_date, $end_date);
        return undef;
    }

    my $d_deb = localtime($begin_date);
    my $d_fin = localtime($end_date) if defined $end_date;
    Log::do_log('debug2', 'data aggregated from %s to %s', $d_deb, $d_fin);
}

#get date of the last time we have aggregated data
# Never used.
#sub get_last_date_aggregation;

sub aggregate_daily_data {
    Log::do_log('debug2', '(%s, %s)', @_);
    my $list      = shift;
    my $operation = shift;

    my $result;

    my $sth;
    my $row;
    unless (
        $sth = SDM::do_prepared_query(
            q{SELECT beginning_date_counter AS "date",
                     count_counter AS "count"
              FROM stat_counter_table
              WHERE data_counter = ? AND
                    robot_counter = ? AND list_counter = ?},
            $operation,
            $list->{'domain'}, $list->{'name'}
        )
        ) {
        Log::do_log('err', 'Unable to get stat data %s for list %s',
            $operation, $list);
        return;
    }
    while ($row = $sth->fetchrow_hashref('NAME_lc')) {
        my $midnight = Sympa::Tools::Time::get_midnight_time($row->{'date'});
        $result->{$midnight} = 0 unless defined $result->{$midnight};
        $result->{$midnight} += $row->{'count'};
    }
    $sth->finish;

    my @dates = sort { $a <=> $b } keys %$result;
    return {} unless @dates;

    for (my $date = $dates[0]; $date < $dates[-1]; $date += 86400) {
        my $midnight = Sympa::Tools::Time::get_midnight_time($date);
        $result->{$midnight} = 0 unless defined $result->{$midnight};
    }
    return $result;
}

1;
