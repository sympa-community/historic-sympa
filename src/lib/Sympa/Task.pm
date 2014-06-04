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

package Sympa::Task;

use strict;

use Carp qw(croak);
use English qw(-no_match_vars);
use Template;

use Sympa::Log::Syslog;
use Sympa::Site;
use Sympa::Instruction;
use Sympa::Tools::Time;

=head1 CLASS METHODS

=item Sympa::Task->new(%parameters)

Creates a new L<Sympa::Task> subclass object.

The exact subclass depends on the presence of a I<list> parameter:

=over 4

=item * if present, L<Sympa::Task::List> is used

=item * if absent, L<Sympa::Task::Global> is used

=back

Parameters:

=over 4

=item * I<messageasstring>: FIXME

=item * I<date>: FIXME

=item * I<label>: FIXME

=item * I<model>: FIXME

=item * I<flavour>: FIXME

=item * I<data>: FIXME

=item * I<list>: FIXME

=back

Returns a new L<Sympa::Task> subclass object, or I<undef> for failure.

=cut

sub new {
    my ($class, %params) = @_;

    if ($params{list}) {
        require Sympa::Task::List;
        return Sympa::Task::List->new(%params);
    } else {
        require Sympa::Task::Global;
        return Sympa::Task::Global->new(%params);
    }
}

# private constructor used by subclasses
sub _new {
    my ($class, %params) = @_;

    Sympa::Log::Syslog::do_log(
        'debug2',
        'Sympa::Task::new  messagekey = %s',
        $params{'messagekey'}
    );

    my $self = bless {
        'messageasstring' => $params{'messageasstring'},
        'date'            => $params{'date'} || time(),
        'label'           => $params{'label'},
        'model'           => $params{'model'},
        'flavour'         => $params{'flavour'},
        'description'     => $params{'model'} . '.' . $params{'flavour'},
        'Rdata'           => $params{'data'},
    }, $class;

    return $self;
}

=back

=head1 INSTANCE METHODS

=over

=item $task->init()

Initialize a task.

Returns a true value for success, I<undef> for failure.

=cut

sub init {
    my ($self) = @_;

    unless ($self->{'model'}) {
        Sympa::Log::Syslog::do_log('err',
            'Missing a model name. Impossible to get a template. Aborting.');
        return undef;
    }
    unless ($self->{'flavour'}) {
        Sympa::Log::Syslog::do_log(
            'err',
            'Missing a flavour name for model %s name. Impossible to get a template. Aborting.',
            $self->{'model'}
        );
        return undef;
    }

    ## model recovery
    my $model_name = 
        $self->{'model'} . '.' . $self->{'flavour'} . '.' . 'task';

    my $template = $self->_get_template($model_name);
    unless ($template) {
        Sympa::Log::Syslog::do_log(
            'err',
            'Unable to find task model %s. Creation aborted',
            $model_name);
        return undef;
    }

    ## Task as string generation
    my $result = $self->_generate_from_template($template);
    return unless $result;

    ## In case a label is specified, ensure we won't use anything in the task
    ## prior to this label.
    if ($self->{'label'}) {
        return undef unless ($self->_crop_after_label($self->{'label'}));
    }

    return 1;
}

## Uses the template of this task to generate the task as string.
sub _generate_from_template {
    my ($self, $template) = @_;

    Sympa::Log::Syslog::do_log('debug',
        "Generate task content with tt2 template %s",
        $template);

    ## creation
    my $tt2 = Template->new(
        {   'START_TAG' => quotemeta('['),
            'END_TAG'   => quotemeta(']'),
            'ABSOLUTE'  => 1
        }
    );
    my $messageasstring = '';
    if ($self->{'model'} eq 'sync_include') {
        $self->{'Rdata'}{'list'}{'ttl'} = $self->{'list'}->ttl;
    }
    unless (
        defined $tt2
        && $tt2->process(
            $template, $self->{'Rdata'}, \$messageasstring
        )
        ) {
        Sympa::Log::Syslog::do_log('err',
            "Failed to parse task template '%s' : %s",
            $template, $tt2->error());
        return undef;
    }
    $self->{'messageasstring'} = $messageasstring;

    if (!$self->check) {
        Sympa::Log::Syslog::do_log('err',
            'error : syntax error in task %s, you should check %s',
            $self->get_description, $template);
        Sympa::Log::Syslog::do_log('notice',
            "Ignoring creation task request");
        return undef;
    }
    Sympa::Log::Syslog::do_log('debug2', 'Resulting task_as_string: %s',
        $self->as_string());
    return 1;
}

# Chop whetever content the task as string could contain (except titles)
# before the label of the task.
sub _crop_after_label {
    my $self  = shift;
    my $label = shift;

    Sympa::Log::Syslog::do_log(
        'debug',
        'Cropping task content to keep only the content located starting label %s',
        $label
    );

    # If this variable still contains 0 at the end of the sub, that means that
    # the label after which we want to crop does not exist in the task. We
    # will therefore not crop anything and return the task with the same
    # content.
    my $label_found_in_task = 0;
    my @new_parsed_instructions;
    $self->_parse
        unless (defined $self->{'parsed_instructions'}
        && $#{$self->{'parsed_instructions'}} > -1);
    foreach my $line (@{$self->{'parsed_instructions'}}) {
        if ($line->{'nature'} eq 'label' && $line->{'label'} eq $label) {
            $label_found_in_task = 1;
            push @new_parsed_instructions,
                {'nature' => 'empty line', 'line_as_string' => ''};
        }
        if ($label_found_in_task || $line->{'nature'} eq 'title') {
            push @new_parsed_instructions, $line;
        }
    }
    unless ($label_found_in_task) {
        Sympa::Log::Syslog::do_log('err',
            'The label %s does not exist in task %s. We can not crop after it.'
        );
        return undef;
    } else {
        $self->{'parsed_instructions'} = \@new_parsed_instructions;
        $self->_stringify_parsed_instructions;
    }

    return 1;
}

## Builds a string giving the name of the model of the task, along with its
## flavour and, if the task is in list context, the name of the list.
sub get_description {
    my $self = shift;
    return $self->{'description'};
}

## Uses the parsed instructions to build a new task as string. If no parsed
## instructions are found, returns the original task as string.
sub _stringify_parsed_instructions {
    my $self = shift;
    Sympa::Log::Syslog::do_log(
        'debug2',
        'Resetting messageasstring key of task object from the parsed content of %s',
        $self->get_description
    );

    my $new_string = $self->as_string();
    unless (defined $new_string) {
        Sympa::Log::Syslog::do_log(
            'err',
            'task %s has no parsed content. Leaving messageasstring key unchanged',
            $self->get_description
        );
        return undef;
    } else {
        $self->{'messageasstring'} = $new_string;
        if (Sympa::Log::Syslog::get_log_level() > 1) {
            Sympa::Log::Syslog::do_log('debug2',
                'task %s content recreated. Content:',
                $self->get_description);
            foreach (split "\n", $self->{'messageasstring'}) {
                Sympa::Log::Syslog::do_log('debug2', '%s', $_);
            }
        }
    }
    return 1;
}

## Returns a string built from parsed isntructions or undef if no parsed
## instructions exist.
## This sub reprensents what we obtain when concatenating the lines found in
## the parsed
## instructions only. we don't try to save anything. If there are no parsed
## instructions,
## You end up with an undef value and that's it. If you want to obtain the
## task as a string
## and don't know whether the instructions were parsed before or not, use
## stringify_parsed_instructions().
sub as_string {
    my $self = shift;
    Sympa::Log::Syslog::do_log('debug2',
        'Generating task string from the parsed content of task %s',
        $self->get_description);

    my $task_as_string = '';
    if (defined $self->{'parsed_instructions'}
        && $#{$self->{'parsed_instructions'}} > -1) {
        foreach my $line (@{$self->{'parsed_instructions'}}) {
            $task_as_string .= "$line->{'line_as_string'}\n";
        }
        $task_as_string =~ s/\n\n$/\n/;
    } else {
        Sympa::Log::Syslog::do_log('err',
            'Task %s appears to have no parsed instructions.');
        $task_as_string = undef;
    }
    return $task_as_string;
}

## Returns the local part of the list name of the task if the task is in list
## context, undef otherwise.
sub _get_short_listname {
    my $self = shift;
    if (defined $self->{'list'}) {
        return $self->{'list'}{'name'};
    }
    return undef;
}

## Returns the full list name of the task if the task is in list context,
## undef otherwise.
sub _get_full_listname {
    my $self = shift;
    if (defined $self->{'list'}) {
        return $self->{'list'}->get_list_id;
    }
    return undef;
}

## Check the syntax of a task
sub _check {
    my $self = shift;    # the task to check
    Sympa::Log::Syslog::do_log('debug2', 'check %s', $self->get_description);

    $self->_parse;

    # are all labels used ?
    foreach my $label (keys %{$self->{'labels'}}) {
        Sympa::Log::Syslog::do_log('debug2',
            'Warning : label %s exists but is not used in %s',
            $label, $self->get_description)
            unless (defined $self->{'used_labels'}{$label});
    }

    # do all used labels exist ?
    foreach my $label (keys %{$self->{'used_labels'}}) {
        unless (defined $self->{'labels'}{$label}) {
            Sympa::Log::Syslog::do_log('err',
                'Error : label %s is used but does not exist in %s',
                $label, $self->get_description);
            return undef;
        }
    }

    # are all variables used ?
    foreach my $var (keys %{$self->{'vars'}}) {
        Sympa::Log::Syslog::do_log('debug2',
            'Warning : var %s exists but is not used in %s',
            $var, $self->get_description)
            unless (defined $self->{'used_vars'}{$var});
    }

    # do all used variables exist ?
    foreach my $var (keys %{$self->{'used_vars'}}) {
        unless (defined $self->{'vars'}{$var}) {
            Sympa::Log::Syslog::do_log('err',
                'Error : var %s is used but does not exist in %s',
                $var, $self->get_description);
            return undef;
        }
    }
    return 1;
}

## Executes the task
sub execute {

    my $self = shift;
    Sympa::Log::Syslog::do_log('notice', 'Running task id = %s, %s)',
        $self->{'messagekey'}, $self->get_description);
    if (!$self->_parse) {
        $self->{'error'} = 'parse';
        $self->_error_report;
        return undef;
    } elsif (!$self->_process_all) {
        $self->{'error'} = 'execution';
        $self->_error_report;
        return undef;
    } else {
        Sympa::Log::Syslog::do_log(
            'notice',
            'The task %s has been correctly executed. Removing it (messagekey=%s)',
            $self->get_description,
            $self->{'messagekey'}
        );
    }
    return 1;
}

## Parses the task as string into parsed instructions.
sub _parse {
    my $self = shift;
    Sympa::Log::Syslog::do_log('debug2', "Parsing task id = %s : %s",
        $self->{'messagekey'}, $self->get_description);

    my $messageasstring = $self->{'messageasstring'};    # task to execute
    unless ($messageasstring) {
        Sympa::Log::Syslog::do_log('err',
            'No string describing the task available in %s',
            $self->get_description);
        return undef;
    }
    my $lnb = 0;                                         # line number
    foreach my $line (split('\n', $messageasstring)) {
        $lnb++;
        my $instruction;
        eval {
            $instruction = Sympa::Instruction->new(
                line_as_string => $line,
                line_number    => $lnb,
            );
        };
        if ($EVAL_ERROR) {
            my $error = {
                message => $EVAL_ERROR,
                type    => 'parsing',
                line    => $lnb
            };
            push @{$self->{errors}}, $error;
            $self->_error_report;
            return undef;
        }
        push @{$self->{'parsed_instructions'}}, $instruction;
    }
    $self->_make_summary;
    return 1;
}

## Processes all parsed instructions sequentially.
sub _process_all {
    my $self = shift;
    my $variables;
    Sympa::Log::Syslog::do_log('debug',
        'Processing all instructions found in task %s',
        $self->get_description);

    foreach my $instruction (@{$self->{'parsed_instructions'}}) {
        if (defined $self->{'must_stop'}) {
            Sympa::Log::Syslog::do_log('debug', 'Stopping here for task %s',
                $self->get_description);
            last;
        }

        my $result;
        eval {
            $result = $instruction->execute($self, $variables);
        };
        if ($EVAL_ERROR) {
            my $error = {
                message => $EVAL_ERROR,
                type    => 'execution',
                line    => $instruction->{'line_number'},
            };
            push @{$self->{errors}}, $error;
            Sympa::Log::Syslog::do_log(
                'err',
                'Error while executing %s at line %s, task %s',
                $instruction->{'line_as_string'},
                $instruction->{'line_number'},
                $self->get_description
            );
            return undef;
        }

        if (ref $result && $result->{'type'} eq 'variables') {
            $variables = $result->{'variables'};
        }
    }
    return 1;
}

## Changes the label of a task file
sub change_label {
    my $task_file = $_[0];
    my $new_label = $_[1];

    my $new_task_file = $task_file;
    $new_task_file =~ s/(.+\.)(\w*)(\.\w+\.\w+$)/$1$new_label$3/;

    if (rename($task_file, $new_task_file)) {
        Sympa::Log::Syslog::do_log('notice',
            "$task_file renamed in $new_task_file");
        return 1;
    } else {
        Sympa::Log::Syslog::do_log('err',
            "error ; can't rename $task_file in $new_task_file");
        return undef;
    }
}

=item $task->check_validity()

Check that a task is still legitimate.

=cut

sub _make_summary {
    my $self = shift;
    Sympa::Log::Syslog::do_log('debug2',
        'Computing general informations about the task %s',
        $self->get_description);

    $self->{'labels'}      = {};
    $self->{'used_labels'} = {};
    $self->{'vars'}        = {};
    $self->{'used_vars'}   = {};

    foreach my $instruction (@{$self->{'parsed_instructions'}}) {
        if ($instruction->{'nature'} eq 'label') {
            $self->{'labels'}{$instruction->{'label'}} = 1;
        } elsif ($instruction->{'nature'} eq 'assignment'
            && $instruction->{'var'}) {
            $self->{'vars'}{$instruction->{'var'}} = 1;
        } elsif ($instruction->{'nature'} eq 'command') {
            foreach my $used_var (keys %{$instruction->{'used_vars'}}) {
                $self->{'used_vars'}{$used_var} = 1;
            }
            foreach my $used_label (keys %{$instruction->{'used_labels'}}) {
                $self->{'used_labels'}{$used_label} = 1;
            }
        }
    }

}

sub _error_report {
    my $self = shift;
    Sympa::Log::Syslog::do_log('debug2', 'Producing error report for task %s',
        $self->get_description);

    my $data;
    if (defined $self->{'list'}) {
        $data->{'list'} = $self->{'list'};
    }
    $self->{'human_date'} = Sympa::Tools::Time::adate($self->{'date'});
    $data->{'task'}       = $self;
    Sympa::Log::Syslog::do_log(
        'err',
        'Execution of task %s failed. sending detailed report to listmaster',
        $self->get_description
    );
    Sympa::Site->send_notify_to_listmaster('task_error', $data);
}

## Get unique ID.
sub get_id {
    return shift->get_description() || '';
}

=back

=cut

1;
