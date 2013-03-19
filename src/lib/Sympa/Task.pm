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

Sympa::Task - Task object

=head1 DESCRIPTION

This class implement a task.

=cut

package Sympa::Task;

use strict;

use Sympa::List;
use Sympa::Log::Syslog;
use Sympa::Spool;
use Sympa::Tools;

my @task_list;
my %task_by_list;
my %task_by_model;

my $taskspool ;

sub set_spool {
    $taskspool = Sympa::Spool->new(name => 'task');
}

=head1 CLASS METHODS

=head2 Sympa::Task->new(%parameters)

Creates a new L<Sympa::Task> object.

=head3 Parameters

=over

=item * I<messagekey>: FIXME

=item * I<taskasstring>: FIXME

=item * I<task_date>: FIXME

=item * I<task_label>: FIXME

=item * I<task_model>: FIXME

=item * I<robot>: FIXME

=item * I<list>: FIXME

=back

=head3 Return

A new L<Sympa::Task> object, or I<undef>, if something went wrong.

=cut

sub new {
    my ($class, %params) = @_;
    Sympa::Log::Syslog::do_log('debug2', 'messagekey = %s', $params{'messagekey'});

    my $self = {
	    messagekey   => $params{'messagekey'},
	    taskasstring => $params{'messageasstring'},
	    date         => $params{'task_date'},
	    label        => $params{'task_label'},
	    model        => $params{'task_model'},
	    domain       => $params{'robot'}
    };

    if ($params{'list'}) { # list task
	$self->{'list_object'} = Sympa::List->new(
		name  => $params{'list'},
		robot => $params{'robot'}
	);
	$self->{'domain'} = $self->{'list_object'}{'domain'};
    }

    $self->{'id'} = $self->{'list_object'}{'name'};
    $self->{'id'} .= '@'.$self->{'domain'} if (defined $self->{'domain'});

    bless $self, $class;

    return $self;
}


##remove a task using message key
sub remove {
    my ($self) = @_;
    Sympa::Log::Syslog::do_log('debug',"Removing task '%s'",$self->{'messagekey'});

    unless ($taskspool->remove_message({'messagekey'=>$self->{'messagekey'}})){
	Sympa::Log::Syslog::do_log('err', 'Unable to remove task (messagekey = %s)', $self->{'messagekey'});
	return undef;
    }
}


## Build all Task objects
sub list_tasks {

    Sympa::Log::Syslog::do_log('debug',"Listing all tasks");
    ## Reset the list of tasks
    undef @task_list;
    undef %task_by_list;
    undef %task_by_model;

    # fetch all task
    my $taskspool = Sympa::Spool->new(name => 'task');
    my @tasks = $taskspool->get_content({'selector'=>{}});

    ## Create Task objects
    foreach my $t (@tasks) {
	my $task = Sympa::Task->new(%$t);
	## Maintain list of tasks
	push @task_list, $task;

	my $list_id = $task->{'id'};
	my $model = $task->{'model'};

	$task_by_model{$model}{$list_id} = $task;
	$task_by_list{$list_id}{$model} = $task;
    }
    return 1;
}

## Return a list tasks for the given list
sub get_tasks_by_list {
    my ($list_id) = @_;
    Sympa::Log::Syslog::do_log('debug',"Getting tasks for list '%s'",$list_id);

    return () unless (defined $task_by_list{$list_id});
    return values %{$task_by_list{$list_id}};
}

sub get_used_models {
    ## Optional list parameter
    my ($list_id) = @_;
    Sympa::Log::Syslog::do_log('debug',"Getting used models for list '%s'",$list_id);


    if (defined $list_id) {
	if (defined $task_by_list{$list_id}) {
	    Sympa::Log::Syslog::do_log('debug2',"Found used models for list '%s'",$list_id);
	    return keys %{$task_by_list{$list_id}}
	}else {
	    Sympa::Log::Syslog::do_log('debug2',"Did not find any used models for list '%s'",$list_id);
	    return ();
	}

    }else {
	return keys %task_by_model;
    }
}

sub get_task_list {
    Sympa::Log::Syslog::do_log('debug',"Getting tasks list");
    return @task_list;
}

1;
