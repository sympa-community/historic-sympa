# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014 GIP RENATER
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

package Task;

use strict;
use warnings;

use List;
use Log;
use Sympa::Regexps;

my @task_list;
my %task_by_list;
my %task_by_model;

## Creates a new Task object
sub new {
    my($pkg, $file) = @_;
    my $task;
    &Log::do_log('debug2', 'Task::new(%s)',$file);
    
    $task->{'filepath'} = $file;

    ## We might get a filepath
    ## Extract filename from path
    my @path = split /\//, $file;
    $task->{'filename'} = $path[$#path];
    my $listname_regexp = Sympa::Regexps::listname();
    my $host_regexp = Sympa::Regexps::host();

    ## File including the list domain
    if ($task->{'filename'} =~ /^(\d+)\.(\w*)\.(\w+)\.($listname_regexp|_global)\@($host_regexp)$/) {
	$task->{'date'} = $1;
	$task->{'label'} = $2;
	$task->{'model'} = $3;
	$task->{'object'} = $4;
	$task->{'domain'} = $5;
	
	if ($task->{'object'} ne '_global') { # list task
	    $task->{'list_object'} = new List ($task->{'object'},$task->{'domain'});
	    $task->{'domain'} = $task->{'list_object'}{'domain'};
	}

    }elsif ($task->{'filename'} =~ /^(\d+)\.(\w*)\.(\w+)\.($listname_regexp|_global)$/) {
	$task->{'date'} = $1;
	$task->{'label'} = $2;
	$task->{'model'} = $3;
	$task->{'object'} = $4;

	if ($task->{'object'} ne '_global') { # list task
	    $task->{'list_object'} = new List ($task->{'object'});
	    $task->{'domain'} = $task->{'list_object'}{'domain'};
	}
    }else {
	&Log::do_log('err', "Unknown format for task '%s'", $task->{'filename'});
	return undef;
    }

    $task->{'id'} = $task->{'list_object'}{'name'};
    $task->{'id'} .= '@'.$task->{'domain'} if (defined $task->{'domain'});

    ## Bless Task object
    bless $task, $pkg;

    return $task;
}

## Build all Task objects
sub list_tasks {
    my $spool_task = shift;

    ## Create required tasks
    unless (opendir(DIR, $spool_task)) {
	&Log::do_log ('err', "error : can't open dir %s: %m", $spool_task);
    }
    my @task_files = sort epoch_sort (grep !/^\.\.?$/, readdir DIR); # @tasks updating
    closedir DIR;

    &Log::do_log('debug',"Listing all tasks");
    ## Reset the list of tasks
    undef @task_list;
    undef %task_by_list;
    undef %task_by_model;

    ## Create Task objects
    foreach my $t (@task_files) {
	next if ($t =~ /^\./);
	my $task = new Task ($spool_task.'/'.$t);
	
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
    my $list_id = shift;
    &Log::do_log('debug',"Getting tasks for list '%s'",$list_id);
    return () unless (defined $task_by_list{$list_id});
    return values %{$task_by_list{$list_id}};
}

sub get_used_models {
    ## Optional list parameter
    my $list_id = shift;
    &Log::do_log('debug',"Getting used models for list '%s'",$list_id);

    if (defined $list_id) {
	if (defined $task_by_list{$list_id}) {
	    &Log::do_log('debug2',"Found used models for list '%s'",$list_id);
	    return keys %{$task_by_list{$list_id}}
	}else {
	    &Log::do_log('debug2',"Did not find any used models for list '%s'",$list_id);
	    return ();
	}
	
    }else {
	return keys %task_by_model;
    }
}

sub get_task_list {
    &Log::do_log('debug',"Getting tasks list");
    return @task_list;
}

## sort task name by their epoch date
sub epoch_sort {

    $a =~ /(\d+)\..+/;
    my $date1 = $1;
    $b =~ /(\d+)\..+/;
    my $date2 = $1;
    
    $date1 <=> $date2;
}


1;
