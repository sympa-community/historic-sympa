# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
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

package Sympa::Spool::File::Task;

use strict;
use base qw(Sympa::Spool::File);

use Sympa::Logger;
use Sympa::Task;

our $filename_regexp = '^(\d+)\.([^\.]+)?\.([^\.]+)\.(\S+)$';
## list of list task models
#my @list_models = ('expire', 'remind', 'sync_include');
our @list_models = ('sync_include', 'remind');

## hash of the global task models
our %global_models = (    #'crl_update_task' => 'crl_update',
        #'chk_cert_expiration_task' => 'chk_cert_expiration',
    'expire_bounce_task'               => 'expire_bounce',
    'purge_user_table_task'            => 'purge_user_table',
    'purge_logs_table_task'            => 'purge_logs_table',
    'purge_session_table_task'         => 'purge_session_table',
    'purge_tables_task'                => 'purge_tables',
    'purge_one_time_ticket_table_task' => 'purge_one_time_ticket_table',
    'purge_orphan_bounces_task'        => 'purge_orphan_bounces',
    'eval_bouncers_task'               => 'eval_bouncers',
    'process_bouncers_task'            => 'process_bouncers',

    #,'global_remind_task' => 'global_remind'
);

#### Spool level subs ####
##########################

sub _get_file_name {
    my ($self, $param) = @_;
    my $filename;
    my $date = $param->{'task_date'} || time();
    $filename =
          $date . '.'
        . $param->{'task_label'} . '.'
        . $param->{'task_model'} . '.'
        . $param->{'task_object'};
    return $filename;
}

sub analyze_file_name {
    $main::logger->do_log(Sympa::Logger::DEBUG3, '(%s, %s, %s)', @_);
    my $self = shift;
    my $key  = shift;
    my $data = shift;

    unless ($key =~ /$filename_regexp/) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'File %s name does not have the proper format', $key);
        return undef;
    }
    $data->{'task_date'}   = $1;
    $data->{'task_label'}  = $2;
    $data->{'task_model'}  = $3;
    $data->{'task_object'} = $4;
    $main::logger->do_log(
        Sympa::Logger::DEBUG3,              'date %s, label %s, model %s, object %s',
        $data->{'task_date'},  $data->{'task_label'},
        $data->{'task_model'}, $data->{'task_object'}
    );
    unless ($data->{'task_object'} eq '_global') {
        ($data->{'list'}, $data->{'robot'}) =
            split /\@/, $data->{'task_object'};
    }

    $data->{'list'}  = lc($data->{'list'});
    $data->{'robot'} = lc($data->{'robot'});
    require Sympa::Robot;
    return undef
        unless $data->{'robot_object'} = Sympa::Robot->new($data->{'robot'});

    my $listname;

    #FIXME: is this needed?
    ($listname, $data->{'type'}) =
        $data->{'robot_object'}->split_listname($data->{'list'});
    if (defined $listname) {
        require Sympa::List;
        $data->{'list_object'} =
            Sympa::List->new($listname, $data->{'robot_object'}, {'just_try' => 1});
    }

    return $data;
}

=head1 INSTANCE METHODS

=over 4

=item $spool->create_required_tasks($date)

Checks that all the required tasks at the server level are defined. Create
them if needed.

=back

=cut

sub create_required_tasks {
    my ($self, $current_date) = @_;
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);

    # create tasks objects for every task already present in the spool
    # indexing them by list and model
    my (%tasks_by_list, %tasks_by_model);

    my @tasks = $self->get_entries();

    foreach my $task (@tasks) {
        my $list_id = $task->{'id'};
        my $model   = $task->{'model'};

        $tasks_by_model{$model}{$list_id} = $task;
        $tasks_by_list{$list_id}{$model}  = $task;
    }

    # hash of datas necessary to the creation of tasks
    my %default_data = (
        'creation_date'  => $current_date,
        'execution_date' => 'execution_date'
    );

    $self->_create_required_global_tasks(
        'data'         => \%default_data,
        'current_date' => $current_date,
        'tasks_index'  => \%tasks_by_model
    );
    $self->_create_required_lists_tasks(
        'data'         => \%default_data,
        'current_date' => $current_date,
        'tasks_index'  => \%tasks_by_list
    );
}

## Checks that all the required GLOBAL tasks at the serever level are defined.
## Create them if needed.
sub _create_required_global_tasks {
    my ($self, %params) = @_;
    $main::logger->do_log(Sympa::Logger::DEBUG,
        'Creating required tasks from global models');

    # models for which a task exists
    my %used_models;
    foreach my $model (keys %{$params{tasks_index}}) {
        $used_models{$model} = 1;
    }

    foreach my $key (keys %global_models) {
        $main::logger->do_log(Sympa::Logger::DEBUG2, "global_model : $key");
        next if $used_models{$global_models{$key}};
        next unless Sympa::Site->$key;

        my $task = Sympa::Task->new(
            'date'          => $params{'current_date'},
            'model'         => $global_models{$key},
            'flavour'       => Sympa::Site->$key,
            'data'          => $params{'data'}
        );
        if ($task && $task->init()) {
            $self->store(
                $task->{'messageastring'},
                $task->get_metadata()
            );
        } else {
            creation_error(
                sprintf
                    'Unable to create task with parameters creation_date = "%s", model = "%s", flavour = "%s", data = "%s"',
                $params{'current_date'},
                $global_models{$key},
                Sympa::Site->$key,
                $params{data}
            );
        }
        $used_models{$1} = 1;
    }
}

## Checks that all the required LIST tasks are defined. Create them if needed.
sub _create_required_lists_tasks {
    my ($self, %params) = @_;
    $main::logger->do_log(Sympa::Logger::DEBUG,
        'Creating required tasks from list models');

    foreach my $robot (@{Sympa::Robot::get_robots()}) {
        $main::logger->do_log(Sympa::Logger::DEBUG3,
            'creating list task : current bot is %s', $robot);
        my $all_lists = Sympa::List::get_lists($robot);
        foreach my $list (@$all_lists) {
            $main::logger->do_log(Sympa::Logger::DEBUG3,
                'creating list task : current list is %s', $list);
            my %data = %{$params{'data'}};
            $data{'list'} = {'name' => $list->name, 'robot' => $list->domain};

            my %used_list_models;    # stores which models already have a task
            foreach my $model (@list_models) {
                $used_list_models{$model} = undef;
            }
            my $tasks_index = $params{tasks_index}->{$list->getid()};
            if ($tasks_index) {
                foreach my $model (keys %$tasks_index) {
                    $used_list_models{$model} = 1;
                }
            }
            $main::logger->do_log(Sympa::Logger::DEBUG3,
                'creating list task using models');
            my $tt = 0;

            foreach my $model (@list_models) {
                next if $used_list_models{$model};

                my $model_task_parameter = "$model" . '_task';

                if ($model eq 'sync_include') {
                    next
                        unless $list->has_include_data_sources()
                            and $list->status eq 'open';
                    my $task = Sympa::Task->new(
                        'date'          => $params{'current_date'},
                        'label'         => 'INIT',
                        'model'         => $model,
                        'flavour'       => 'ttl',
                        'data'          => \%data
                    );
                    if ($task && $task->init()) {
                        $self->store(
                            $task->{'messageastring'},
                            $task->get_metadata()
                        );
                    } else {
                        creation_error(
                            sprintf
                                'Unable to create task with parameters list = "%s", creation_date = "%s", label = "%s", model = "%s", flavour = "%s", data = "%s"',
                            $list->get_list_id,
                            $params{'current_date'},
                            'INIT',
                            $model,
                            'ttl',
                            \%data
                        );
                    }
                    $main::logger->do_log(Sympa::Logger::DEBUG3,
                        'sync_include task creation done');
                    $tt++;

                } elsif (%{$list->$model_task_parameter}
                    and defined $list->$model_task_parameter->{'name'}
                    and $list->status eq 'open') {
                    my $task = Sympa::Task->new(
                        'date'          => $params{'current_date'},
                        'model'         => $model,
                        'flavour'       =>
                            $list->$model_task_parameter->{'name'},
                        'data'          => \%data
                    );
                    if ($task && $task->init()) {
                        $self->store(
                            $task->{'messageastring'},
                            $task->get_metadata()
                        );
                    } else {
                        creation_error(
                            sprintf
                                'Unable to create task with parameters list = "%s", creation_date = "%s", model = "%s", flavour = "%s", data = "%s"',
                            $list->get_id,
                            $params{'current_date'},
                            $model,
                            $list->$model_task_parameter->{'name'},
                            \%data
                        );
                    }
                    $tt++;
                }
            }
        }
    }
}

sub creation_error {
    my $message = shift;
    $main::logger->do_log(Sympa::Logger::ERR, $message);
    Sympa::Site->send_notify_to_listmaster('task_creation_error', $message);
}

sub get_entries {
    my ($self, %params) = @_;

    my @tasks;
    foreach my $task_in_spool ($self->get_raw_entries(%params)) {
        next unless $task_in_spool; # is this really needed ?

        my $list;
        if ($task_in_spool->{'list'}) {
            $list = Sympa::List->new(
                $task_in_spool->{'list'},
                $task_in_spool->{'domain'},
                {'skip_sync_admin' => 1}
            );
        }
            
        my $task = Sympa::Task->new(
            messageasstring => $task_in_spool->{'messageasstring'},
            date            => $task_in_spool->{'task_date'},
            label           => $task_in_spool->{'task_label'},
            model           => $task_in_spool->{'task_model'},
            flavour         => $task_in_spool->{'task_flavour'},
            object          => $task_in_spool->{'task_object'},
            list            => $list
        );
        next unless $task; # is this really needed ?

        push @tasks, $task;
    }

    return @tasks;
}

1;
