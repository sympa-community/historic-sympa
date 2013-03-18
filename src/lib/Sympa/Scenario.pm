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

Sympa::Scenario - Authorization scenario object

=head1 DESCRIPTION

This class implement an authorization scenario.

=cut

package Sympa::Scenario;

use strict;

use English qw(-no_match_vars);
use Net::Netmask;

use Sympa::Configuration;
use Sympa::Constants;
use Sympa::List;
use Sympa::Log;
use Sympa::Tools;
use Sympa::Tools::Time;
use Sympa::Tools::Data;

my %all_scenarios;
my %persistent_cache;

=head1 CLASS METHODS

=head2 Sympa::Scenario->new(%parameters)

Creates a new L<Sympa::Scenario> object.

=head3 Parameters

=over

=item * I<function>: FIXME

=item * I<robot>: FIXME

=item * I<name>: FIXME

=item * I<directory>: FIXME

=item * I<file_path>: FIXME

=item * I<options>: FIXME

=back

=head3 Return

A new L<Sympa::Scenario> object, or I<undef>, if something went wrong.

=cut

sub new {
   my ($class, %params) = @_;
    Sympa::Log::do_log('debug2', '');

    my $self = {};

    ## Check parameters
    ## Need either file_path or function+name
    ## Parameter 'directory' is optional, used in List context only
    unless ($params{'robot'} &&
	    ($params{'file_path'} || ($params{'function'} && $params{'name'}))) {
	Sympa::Log::do_log('err', 'Missing parameter');
	return undef;
    }

    ## Determine the file path of the scenario

    if ($params{'file_path'} eq 'ERROR') {
	return $all_scenarios{$self->{'file_path'}};
    }

    if (defined $params{'file_path'}) {
	$self->{'file_path'} = $params{'file_path'};
	my @tokens = split /\//, $params{'file_path'};
	my $filename = $tokens[$#tokens];
	unless ($filename =~ /^([^\.]+)\.(.+)$/) {
	    Sympa::Log::do_log('err',"Failed to determine scenario type and name from '$params{'file_path'}'");
	    return undef;
	}
	($params{'function'}, $params{'name'}) = ($1, $2);

    }else {
	## We can't use Sympa::Tools::get_filename() because we don't have a List object yet ; it's being constructed
	my @dirs = ($Sympa::Configuration::Conf{'etc'}.'/'.$params{'robot'}, $Sympa::Configuration::Conf{'etc'}, Sympa::Constants::DEFAULTDIR);
	unshift @dirs, $params{'directory'} if (defined $params{'directory'});
	foreach my $dir (@dirs) {
	    my $tmp_path = $dir.'/scenari/'.$params{'function'}.'.'.$params{'name'};
	    if (-r $tmp_path) {
		$self->{'file_path'} = $tmp_path;
		last;
	    }else {
		Sympa::Log::do_log('debug','Unable to read file %s',$tmp_path);
	    }
	}
    }

    ## Load the scenario if previously loaded in memory
    if (defined $all_scenarios{$self->{'file_path'}}) {

	## Option 'dont_reload_scenario' prevents scenario reloading
	## Usefull for performances reasons
	if ($params{'options'}{'dont_reload_scenario'}) {
	    return $all_scenarios{$self->{'file_path'}};
	}

	## Use cache unless file has changed on disk
	if ($all_scenarios{$self->{'file_path'}}{'date'} >= (stat($self->{'file_path'}))[9]) {
	    return $all_scenarios{$self->{'file_path'}};
	}
    }

    ## Load the scenario
    my $scenario_struct;
    if (defined $self->{'file_path'}) {
	## Get the data from file
	unless (open SCENARIO, $self->{'file_path'}) {
	    Sympa::Log::do_log('err',"Failed to open scenario '$self->{'file_path'}'");
	    return undef;
	}
	my $data = join '', <SCENARIO>;
	close SCENARIO;

	## Keep rough scenario
	$self->{'data'} = $data;

	$scenario_struct = _parse_scenario($params{'function'}, $params{'robot'}, $params{'name'}, $data, $params{'directory'});
    }elsif ($params{'function'} eq 'include') {
	## include.xx not found will not raise an error message
	return undef;

    }else {
	## Default rule is 'true() smtp -> reject'
	Sympa::Log::do_log('err',"Unable to find scenario file '$params{'function'}.$params{'name'}', please report to listmaster");
	$scenario_struct = _parse_scenario($params{'function'}, $params{'robot'}, $params{'name'}, 'true() smtp -> reject', $params{'directory'});
	$self->{'file_path'} = 'ERROR'; ## special value
	$self->{'data'} = 'true() smtp -> reject';
    }

    ## Keep track of the current time ; used later to reload scenario files when they changed on disk
    $self->{'date'} = time;

    unless (ref($scenario_struct) eq 'HASH') {
	Sympa::Log::do_log('err',"Failed to load scenario '$params{'function'}.$params{'name'}'");
	return undef;
    }

    $self->{'name'} = $scenario_struct->{'name'};
    $self->{'rules'} = $scenario_struct->{'rules'};
    $self->{'title'} = $scenario_struct->{'title'};
    $self->{'struct'} = $scenario_struct;


    ## Keep the scenario in memory
    $all_scenarios{$self->{'file_path'}} = $self;

    bless $self, $class;
    return $self;
}

## Parse scenario rules
sub _parse_scenario {
    my ($function, $robot, $scenario_name, $paragraph) = @_;
    Sympa::Log::do_log('debug2', "($function, $scenario_name, $robot)");

    my $structure = {};
    $structure->{'name'} = $scenario_name ;
    my @scenario;
    my @rules = split /\n/, $paragraph;

    foreach my $current_rule (@rules) {
	my @auth_methods_list;
	next if ($current_rule =~ /^\s*\w+\s*$/o); # skip paragraph name
	my $rule = {};
	$current_rule =~ s/\#.*$//;         # remove comments
        next if ($current_rule =~ /^\s*$/); # skip empty lines
	if ($current_rule =~ /^\s*title\.gettext\s+(.*)\s*$/i) {
	    $structure->{'title'}{'gettext'} = $1;
	    next;
	}elsif ($current_rule =~ /^\s*title\.(\w+)\s+(.*)\s*$/i) {
	    $structure->{'title'}{$1} = $2;
	    next;
	}

	if ($current_rule =~ /\s*(include\s*\(?\'?(.*)\'?\)?)\s*$/i) {
	    $rule->{'condition'} = $1;
	    push(@scenario, $rule);
	}elsif ($current_rule =~ /^\s*(.*?)\s+((\s*(md5|pgp|smtp|smime|dkim)\s*,?)*)\s*->\s*(.*)\s*$/gi) {
	    $rule->{'condition'} = $1;
	    $rule->{'action'} = $5;
	    my $auth_methods = $2 || 'smtp';
	    $auth_methods=~ s/\s//g;
	    @auth_methods_list = split ',', $auth_methods;
	}else {
	    Sympa::Log::do_log('err', "error rule syntaxe in scenario
		    $function rule line $NR expected : <condition> <auth_mod> -> <action>");
	    Sympa::Log::do_log('err',"error parsing $current_rule");
	    return undef;
	}

	## Duplicate the rule for each mentionned authentication method
	foreach my $auth_method (@auth_methods_list) {
	    push(@scenario,{'condition' => $rule->{condition},
                            'auth_method' => $auth_method,
                            'action' => $rule->{action}});
	}
    }

    $structure->{'rules'} = \@scenario;

    return $structure;
}


####################################################
# request_action
####################################################
# Return the action to perform for 1 sender
# using 1 auth method to perform 1 operation
#
# IN : -$operation (+) : scalar
#      -$auth_method (+) : 'smtp'|'md5'|'pgp'|'smime'|'dkim'
#      -$robot (+) : scalar
#      -$context (+) : ref(HASH) containing information
#        to evaluate scenario (scenario var)
#      -$debug : adds keys in the returned HASH
#
# OUT : undef | ref(HASH) containing keys :
#        -action : 'do_it'|'reject'|'request_auth'
#           |'owner'|'editor'|'editorkey'|'listmaster'
#        -reason : defined if action == 'reject'
#           and in scenario : reject(reason='...')
#           key for template authorization_reject.tt2
#        -tt2 : defined if action == 'reject'
#           and in scenario : reject(tt2='...') or reject('...tt2')
#           match a key in authorization_reject.tt2
#        -condition : the checked condition
#           (defined if $debug)
#        -auth_method : the checked auth_method
#           (defined if $debug)
######################################################
sub request_action {
    my ($operation, $auth_method, $robot, $context, $debug) = @_;
    Sympa::Log::do_log('debug', '%s,%s,%s',$operation,$auth_method,$robot);

    my $trace_scenario ;

    ## Defining default values for parameters.
    $context->{'sender'} ||= 'nobody' ;
    $context->{'email'} ||= $context->{'sender'};
    $context->{'remote_host'} ||= 'unknown_host' ;
    $context->{'robot_domain'} = $robot ;
    $context->{'msg'} = $context->{'message'}->{'msg'} if (defined $context->{'message'});
    $context->{'msg_encrypted'} = 'smime' if (defined $context->{'message'} &&
					      $context->{'message'}->{'smime_crypted'} eq 'smime_crypted');
    ## Check that authorization method is one of those known by Sympa
    unless ( $auth_method =~ /^(smtp|md5|pgp|smime|dkim)/) {
	Sympa::Log::do_log('info',"fatal error : unknown auth method $auth_method");
	return undef;
    }
    my (@rules, $name, $scenario) ;

    my $log_it ; # this var is defined to control if log scenario is activated or not
    my $loging_targets = Sympa::Configuration::get_robot_conf($robot,'loging_for_module');
    if ($loging_targets->{'scenario'} == 1){
	#activate log if no condition is defined
	unless (Sympa::Configuration::get_robot_conf($robot,'loging_condition')) {
	    $log_it = 1;
	}else {
	    #activate log if ip or email match
	    my $loging_conditions = Sympa::Configuration::get_robot_conf($robot,'loging_condition');
	    if ($loging_conditions->{'ip'} =~ /$context->{'remote_addr'}/ || $loging_conditions->{'email'} =~ /$context->{'email'}/i) {
		Sympa::Log::do_log('info','Will log scenario process for user with email: "%s", IP: "%s"',$context->{'email'},$context->{'remote_addr'});
		$log_it = 1;
	    }
	}
    }

    if ($log_it) {
	if ($context->{'list_object'}) {
	    $trace_scenario = 'scenario request '.$operation.' for list '.$context->{'list_object'}{'name'}.'@'.$robot.' :';
	    Sympa::Log::do_log('info','Will evaluate scenario %s for list %s@%s',$operation,$context->{'list_object'}{'name'},$robot);
	}else{
	    $trace_scenario = 'scenario request '.$operation.' for robot '.$robot.' :';
	    Sympa::Log::do_log('info','Will evaluate scenario %s for robot %s',$operation,$robot);
	}
    }

    ## The current action relates to a list
    if (defined $context->{'list_object'}) {
	my $list = $context->{'list_object'};

	## The $operation refers to a list parameter of the same name
	## The list parameter might be structured ('.' is a separator)
	my @operations = split /\./, $operation;
	my $scenario_path;

	if ($#operations == 0) {
	    ## Simple parameter
	    $scenario_path = $list->{'admin'}{$operation}{'file_path'};
	}else{
	    ## Structured parameter
	    $scenario_path = $list->{'admin'}{$operations[0]}{$operations[1]}{'file_path'} if (defined $list->{'admin'}{$operations[0]});
	}

	## List parameter might not be defined (example : web_archive.access)
	unless (defined $scenario_path) {
	    my $return = {'action' => 'reject',
			  'reason' => 'parameter-not-defined',
			  'auth_method' => '',
			  'condition' => ''
			  };
	    if ($log_it){
		 Sympa::Log::do_log('info',"$trace_scenario rejected reason parameter not defined");
	    }
	    return $return;
	}

	## Prepares custom_vars in $context
	if (defined $list->{'admin'}{'custom_vars'}) {
	    foreach my $var (@{$list->{'admin'}{'custom_vars'}}) {
		$context->{'custom_vars'}{$var->{'name'}} = $var->{'value'};
	    }
	}

	## Create Scenario object
	$scenario = Sympa::Scenario->new('robot' => $robot,
				  'directory' => $list->{'dir'},
				  'file_path' => $scenario_path,
				  'options' => $context->{'options'});

	## pending/closed lists => send/visibility are closed
	unless ($list->{'admin'}{'status'} eq 'open') {
	    if ($operation =~ /^(send|visibility)$/) {
		my $return = {'action' => 'reject',
			      'reason' => 'list-no-open',
			      'auth_method' => '',
			      'condition' => ''
			      };
		if ($log_it){
		    Sympa::Log::do_log('info',"$trace_scenario rejected reason list not open");
		}
		return $return;
	    }
	}

	### the following lines are used by the document sharing action
	if (defined $context->{'scenario'}) {

	    # loading of the structure
	    $scenario = Sympa::Scenario->new('robot' => $robot,
				      'directory' => $list->{'dir'},
				      'function' => $operations[$#operations],
				      'name' => $context->{'scenario'},
				      'options' => $context->{'options'});
	}

    }elsif ($context->{'topicname'}) {
	## Topics

	$scenario = Sympa::Scenario->new('robot' => $robot,
				  'function' => 'topics_visibility',
				  'name' => $Sympa::List::list_of_topics{$robot}{$context->{'topicname'}}{'visibility'},
				  'options' => $context->{'options'});

    }else{
	## Global scenario (ie not related to a list) ; example : create_list

	my $p = Sympa::Configuration::get_robot_conf($robot, $operation);
	$scenario = Sympa::Scenario->new('robot' => $robot,
				  'function' => $operation,
				  'name' => $p,
				  'options' => $context->{'options'});
    }

    unless ((defined $scenario) && (defined $scenario->{'rules'})) {
	Sympa::Log::do_log('err',"Failed to load scenario for '$operation'");
	return undef ;
    }

    push @rules, @{$scenario->{'rules'}};
    $name = $scenario->{'name'};

    unless ($name) {
	Sympa::Log::do_log('err',"internal error : configuration for operation $operation is not yet performed by scenario");
	return undef;
    }

    ## Include include.<action>.header if found
    my %params = ('function' => 'include',
		 'robot' => $robot,
		 'name' => $operation.'.header',
		 'options' => $context->{'options'});
    $params{'directory'} = $context->{'list_object'}{'dir'} if (defined $context->{'list_object'});
    my $include_scenario = Sympa::Scenario->new(%params);
    if (defined $include_scenario) {
	## Add rules at the beginning of the array
	unshift @rules, @{$include_scenario->{'rules'}};
    }
    ## Look for 'include' directives amongst rules first
    foreach my $index (0..$#rules) {
	if ($rules[$index]{'condition'} =~ /^\s*include\s*\(?\'?([\w\.]+)\'?\)?\s*$/i) {
	    my $include_file = $1;
	    my %params = ('function' => 'include',
			 'robot' => $robot,
			 'name' => $include_file,
			 'options' => $context->{'options'});
	    $params{'directory'} = $context->{'list_object'}{'dir'} if (defined $context->{'list_object'});
	    my $include_scenario = Sympa::Scenario->new(%params);
	    if (defined $include_scenario) {
		## Removes the include directive and replace it with included rules
		splice @rules, $index, 1, @{$include_scenario->{'rules'}};
	    }
	}
    }

    ## Include a Blacklist rules if configured for this action
    if ($Sympa::Configuration::Conf{'blacklist'}{$operation}) {
	foreach my $auth ('smtp','dkim','md5','pgp','smime'){
	    my $blackrule = {'condition' => "search('blacklist.txt',[sender])",
			     'action' => 'reject,quiet',
			     'auth_method' => $auth};
	    ## Add rules at the beginning of the array
	    unshift @rules, ($blackrule);
	}
    }


    my $return = {};
    foreach my $rule (@rules) {
	if ($log_it){
	     Sympa::Log::do_log('info', 'Verify rule %s, auth %s, action %s',$rule->{'condition'},$rule->{'auth_method'},$rule->{'action'});
	}
	if ($auth_method eq $rule->{'auth_method'}) {
	    if ($log_it){
		 Sympa::Log::do_log('info', 'Context uses auth method %s',$rule->{'auth_method'});
	    }
	    my $result =  verify ($context,$rule->{'condition'},$log_it);

	    ## Cope with errors
	    if (! defined ($result)) {
		Sympa::Log::do_log('info',"error in $rule->{'condition'},$rule->{'auth_method'},$rule->{'action'}" );
		Sympa::Log::do_log('info', 'Error in %s scenario, in list %s', $context->{'scenario'}, $context->{'listname'});

		if ($debug) {
		    $return = {'action' => 'reject',
			       'reason' => 'error-performing-condition',
			       'auth_method' => $rule->{'auth_method'},
			       'condition' => $rule->{'condition'}
			   };
		    return $return;
		}
		unless (Sympa::List::send_notify_to_listmaster('error-performing-condition', $robot, [$context->{'listname'}."  ".$rule->{'condition'}] )) {
		    Sympa::Log::do_log('notice',"Unable to send notify 'error-performing-condition' to listmaster");
		}
		return undef;
	    }

	    ## Rule returned false
	    if ($result == -1) {
		if ($log_it){
		    Sympa::Log::do_log('info',"$trace_scenario condition $rule->{'condition'} with authentication method $rule->{'auth_method'} not verified.");
		}
		next;
	    }

	    my $action = $rule->{'action'};

            ## reject : get parameters
	    if ($action =~ /^(ham|spam|unsure)/) {
		$action = $1 ;
	    }
	    if ($action =~/^reject(\((.+)\))?(\s?,\s?(quiet))?/) {

		if ($4 eq 'quiet') {
		    $action = 'reject,quiet';
		} else{
		    $action = 'reject';
		}
		my @param = split /,/,$2;

       		foreach my $p (@param){
		    if  ($p =~ /^reason=\'?(\w+)\'?/){
			$return->{'reason'} = $1;
			next;

		    }elsif ($p =~ /^tt2=\'?(\w+)\'?/){
			$return->{'tt2'} = $1;
			next;

		    }
		    if ($p =~ /^\'?[^=]+\'?/){
			$return->{'tt2'} = $p;
			# keeping existing only, not merging with reject parameters in scenarios
			last;
		    }
		}
	    }

	    $return->{'action'} = $action;

	    if ($log_it){
		Sympa::Log::do_log('info',"$trace_scenario condition $rule->{'condition'} with authentication method $rule->{'auth_method'} issued result : $action");
	    }

	    if ($result == 1) {
		if ($log_it){
		     Sympa::Log::do_log('info',"rule '%s %s -> %s' accepted",$rule->{'condition'},$rule->{'auth_method'},$rule->{'action'});
		}
		if ($debug) {
		    $return->{'auth_method'} = $rule->{'auth_method'};
		    $return->{'condition'} = $rule->{'condition'};
		    return $return;
		}

		## Check syntax of returned action
		unless ($action =~ /^(do_it|reject|request_auth|owner|editor|editorkey|listmaster|ham|spam|unsure)/) {
		    Sympa::Log::do_log('err', "Matched unknown action '%s' in scenario", $rule->{'action'});
		    return undef;
		}
		return $return;
	    }
	}else {
	    if ($log_it){
		 Sympa::Log::do_log('info', 'Context does not use auth method %s',$rule->{'auth_method'});
	    }
	}
    }
    Sympa::Log::do_log('info',"no rule match, reject");

    if ($log_it){
	Sympa::Log::do_log('info',"$trace_scenario : no rule match request rejected");
    }

    $return = {'action' => 'reject',
	       'reason' => 'no-rule-match',
			   'auth_method' => 'default',
			   'condition' => 'default'
			   };
    return $return;
}

## check if email respect some condition
sub verify {
    my ($context, $condition, $log_it) = @_;
    Sympa::Log::do_log('debug2', 'condition %s, log %s', $condition, $log_it);

    my $robot = $context->{'robot_domain'};

#    while (my($k,$v) = each %{$context}) {
#	Sympa::Log::do_log('debug3',"verify: context->{$k} = $v");
#    }

    unless (defined($context->{'sender'} )) {
	Sympa::Log::do_log('info',"internal error, no sender find, report authors");
	return undef;
    }

    $context->{'execution_date'} = time unless ( defined ($context->{'execution_date'}) );

    my $list;
    if ($context->{'listname'} && ! defined $context->{'list_object'}) {
        $context->{'list_object'} = Sympa::List->new(
		name  => $context->{'listname'},
		robot => $robot
	);
        unless ($context->{'list_object'}) {
	    Sympa::Log::do_log('info',"Unable to create List object for list $context->{'listname'}");
	    return undef ;
	}
    }

    if (defined ($context->{'list_object'})) {
	$list = $context->{'list_object'};
	$context->{'listname'} = $list->{'name'};

	$context->{'host'} = $list->{'admin'}{'host'};
    }

    if (defined ($context->{'msg'})) {
	my $header = $context->{'msg'}->head;
	unless (($header->get('to') && (join(', ', $header->get('to')) =~ /$context->{'listname'}/i)) ||
		($header->get('cc') && (join(', ', $header->get('cc')) =~ /$context->{'listname'}/i))) {
	    $context->{'is_bcc'} = 1;
	}else{
	    $context->{'is_bcc'} = 0;
	}

    }
    unless ($condition =~ /(\!)?\s*(true|is_listmaster|verify_netmask|is_editor|is_owner|is_subscriber|less_than|match|equal|message|older|newer|all|search|customcondition\:\:\w+)\s*\(\s*(.*)\s*\)\s*/i) {
	Sympa::Log::do_log('err', "error rule syntaxe: unknown condition $condition");
	return undef;
    }
    my $negation = 1 ;
    if ($1 eq '!') {
	$negation = -1 ;
    }

    my $condition_key = lc($2);
    my $arguments = $3;
    my @args;

    ## The expression for regexp is tricky because we don't allow the '/' character (that indicates the end of the regexp
    ## but we allow any number of \/ escape sequence)
    while ($arguments =~ s/^\s*(
				\[\w+(\-\>[\w\-]+)?\]
				|
				([\w\-\.]+)
				|
				'[^,)]*'
				|
				"[^,)]*"
				|
				\/([^\/]*((\\\/)*[^\/]+))*\/
				|(\w+)\.ldap
				|(\w+)\.sql
				)\s*,?//x) {
	my $value=$1;

	## Custom vars
	if ($value =~ /\[custom_vars\-\>([\w\-]+)\]/i) {
	    $value =~ s/\[custom_vars\-\>([\w\-]+)\]/$context->{'custom_vars'}{$1}/;
	}

	## Family vars
	if ($value =~ /\[family\-\>([\w\-]+)\]/i) {
	    $value =~ s/\[family\-\>([\w\-]+)\]/$context->{'family'}{$1}/;
	}

	## Config param
	elsif ($value =~ /\[conf\-\>([\w\-]+)\]/i) {
	    if (my $conf_value = Sympa::Configuration::get_robot_conf($robot, $1)) {

		$value =~ s/\[conf\-\>([\w\-]+)\]/$conf_value/;
	    }else{
		Sympa::Log::do_log('debug',"undefine variable context $value in rule $condition");
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"undefine variable context $value in rule $condition");
		}
		# a condition related to a undefined context variable is always false
		return -1 * $negation;
	    }

	    ## List param
	}elsif ($value =~ /\[list\-\>([\w\-]+)\]/i) {
	    my $param = $1;

	    if ($param =~ /^(name|total)$/) {
		$value =~ s/\[list\-\>([\w\-]+)\]/$list->{$param}/;
	    }elsif ($param eq 'address') {
		my $list_address = $list->get_list_address();
		$value =~ s/\[list\-\>([\w\-]+)\]/$list_address/;

	    }elsif ($list->{'admin'}{$param} and (!ref($list->{'admin'}{$param})) ) {
		$value =~ s/\[list\-\>([\w\-]+)\]/$list->{'admin'}{$param}/;
	    }else{
		Sympa::Log::do_log('err','Unknown list parameter %s in rule %s', $value, $condition);
		if ($log_it == 1) {
		    Sympa::Log::do_log('info','Unknown list parameter %s in rule %s', $value, $condition);
		}
		return undef;
	    }

	}elsif ($value =~ /\[env\-\>([\w\-]+)\]/i) {

	    $value =~ s/\[env\-\>([\w\-]+)\]/$ENV{$1}/;

	    ## Sender's user/subscriber attributes (if subscriber)
	}elsif ($value =~ /\[user\-\>([\w\-]+)\]/i) {

	    $context->{'user'} ||= Sympa::List::get_global_user($context->{'sender'});
	    $value =~ s/\[user\-\>([\w\-]+)\]/$context->{'user'}{$1}/;

	}elsif ($value =~ /\[user_attributes\-\>([\w\-]+)\]/i) {

	    $context->{'user'} ||= Sympa::List::get_global_user($context->{'sender'});
	    $value =~ s/\[user_attributes\-\>([\w\-]+)\]/$context->{'user'}{'attributes'}{$1}/;

	}elsif (($value =~ /\[subscriber\-\>([\w\-]+)\]/i) && defined ($context->{'sender'} ne 'nobody')) {

	    $context->{'subscriber'} ||= $list->get_list_member($context->{'sender'});
	    $value =~ s/\[subscriber\-\>([\w\-]+)\]/$context->{'subscriber'}{$1}/;

	    ## SMTP Header field
	}elsif ($value =~ /\[(msg_header|header)\-\>([\w\-]+)\]/i) {
	    my $field_name = $2;
	    if (defined ($context->{'msg'})) {
		my $header = $context->{'msg'}->head;
		my @fields = $header->get($field_name);
		## Defaulting empty or missing fields to '', so that we can test
		## their value in Scenario, considering that, for an incoming message,
		## a missing field is equivalent to an empty field : the information it
		## is supposed to contain isn't available.
		unless (@fields) {
		    @fields = ('');
		}

		$value = \@fields;
	    }else {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info','no message object found to evaluate rule %s', $condition);
		}
		return -1 * $negation;
	    }

	}elsif ($value =~ /\[msg_body\]/i) {
	    unless (defined ($context->{'msg'}) && defined ($context->{'msg'}->effective_type() =~ /^text/) && defined ($context->{'msg'}->bodyhandle)) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info','no proper textual message body to evaluate rule %s', $condition);
		}
		return -1 * $negation;
	    }

	    $value = $context->{'msg'}->bodyhandle->as_string();

	}elsif ($value =~ /\[msg_part\-\>body\]/i) {
	    unless (defined ($context->{'msg'})) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info','no message to evaluate rule %s', $condition);
		}
		return -1 * $negation;
	    }

	    my @bodies;
	    ## FIXME:Should be recurcive...
	    foreach my $part ($context->{'msg'}->parts) {
		next unless ($part->effective_type() =~ /^text/);
		next unless (defined $part->bodyhandle);

		push @bodies, $part->bodyhandle->as_string();
	    }
	    $value = \@bodies;

	}elsif ($value =~ /\[msg_part\-\>type\]/i) {
	    unless (defined ($context->{'msg'})) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info','no message to evaluate rule %s', $condition);
		}
		return -1 * $negation;
	    }

	    my @types;
	    foreach my $part ($context->{'msg'}->parts) {
		push @types, $part->effective_type();
	    }
	    $value = \@types;

	}elsif ($value =~ /\[current_date\]/i) {
	    my $time = time;
	    $value =~ s/\[current_date\]/$time/;

	    ## Quoted string
	}elsif ($value =~ /\[(\w+)\]/i) {

	    if (defined ($context->{$1})) {
		$value =~ s/\[(\w+)\]/$context->{$1}/i;
	    }else{
		Sympa::Log::do_log('debug',"undefine variable context $value in rule $condition");
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"undefine variable context $value in rule $condition");
		}
		# a condition related to a undefined context variable is always false
		return -1 * $negation;
	    }

	}elsif ($value =~ /^'(.*)'$/ || $value =~ /^"(.*)"$/) {
	    $value = $1;
	}
	push (@args,$value);

    }
    # Getting rid of spaces.
    $condition_key =~ s/^\s*//g;
    $condition_key =~ s/\s*$//g;
    # condition that require 0 argument
    if ($condition_key =~ /^(true|all)$/i) {
	unless ($#args == -1){
	    Sympa::Log::do_log('err',"error rule syntaxe : incorrect number of argument or incorrect argument syntaxe $condition") ;
	    return undef ;
	}
	# condition that require 1 argument
    }elsif ($condition_key =~ /^(is_listmaster|verify_netmask)$/) {
	unless ($#args == 0) {
	     Sympa::Log::do_log('err',"error rule syntaxe : incorrect argument number for condition $condition_key") ;
	    return undef ;
	}
	# condition that require 1 or 2 args (search : historical reasons)
    }elsif ($condition_key =~ /^search$/o) {
	unless ($#args == 1 || $#args == 0) {
	    Sympa::Log::do_log('err',"error rule syntaxe : Incorrect argument number for condition $condition_key") ;
	    return undef ;
	}
	# condition that require 2 args
    }elsif ($condition_key =~ /^(is_owner|is_editor|is_subscriber|less_than|match|equal|message|newer|older)$/o) {
	unless ($#args == 1) {
	    Sympa::Log::do_log('err',"error rule syntaxe : incorrect argument number (%d instead of %d) for condition $condition_key", $#args+1, 2) ;
	    return undef ;
	}
    }elsif ($condition_key !~ /^customcondition::/o) {
	Sympa::Log::do_log('err', "error rule syntaxe : unknown condition $condition_key");
	return undef;
    }

    ## Now eval the condition
    ##### condition : true
    if ($condition_key =~ /^(true|any|all)$/i) {
	if ($log_it == 1) {
	    Sympa::Log::do_log('info','Condition %s is always true (rule %s)',$condition_key,$condition);
	}
	return $negation;
    }
    ##### condition is_listmaster
    if ($condition_key eq 'is_listmaster') {

	if ($args[0] eq 'nobody') {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','%s is not listmaster of robot %s (rule %s)',$args[0],$robot,$condition);
	    }
	    return -1 * $negation ;
	}

	if ( Sympa::List::is_listmaster($args[0],$robot)) {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','%s is listmaster of robot %s (rule %s)',$args[0],$robot,$condition);
	    }
	    return $negation;
	}else{
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','%s is not listmaster of robot %s (rule %s)',$args[0],$robot,$condition);
	    }
	    return -1 * $negation;
	}
    }

    ##### condition verify_netmask
    if ($condition_key eq 'verify_netmask') {

	## Check that the IP address of the client is available
	## Means we are in a web context
	unless (defined $ENV{'REMOTE_ADDR'}) {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','REMOTE_ADDR env variable not set (rule %s)',$condition);
	    }
	    return -1; ## always skip this rule because we can't evaluate it
	}
	my $block;
	unless ($block = new2 Net::Netmask ($args[0])) {
	    Sympa::Log::do_log('err', "error rule syntaxe : failed to parse netmask '$args[0]'");
	    return undef;
	}
	if ($block->match ($ENV{'REMOTE_ADDR'})) {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','REMOTE_ADDR %s matches %s (rule %s)',$ENV{'REMOTE_ADDR'},$args[0],$condition);
	    }
	    return $negation;
	}else{
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','REMOTE_ADDR %s does not match %s (rule %s)',$ENV{'REMOTE_ADDR'},$args[0],$condition);
	    }
	    return -1 * $negation;
	}
    }

    ##### condition older
    if ($condition_key =~ /^(older|newer)$/) {

	$negation *= -1 if ($condition_key eq 'newer');
 	my $arg0 = Sympa::Tools::Time::epoch_conv($args[0]);
 	my $arg1 = Sympa::Tools::Time::epoch_conv($args[1]);

	Sympa::Log::do_log('debug3', '%s(%d, %d)', $condition_key, $arg0, $arg1);
 	if ($arg0 <= $arg1 ) {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','%s is smaller than %s (rule %s)',$arg0, $arg1,$condition);
	    }
 	    return $negation;
 	}else{
	    if ($log_it == 1) {
		Sympa::Log::do_log('info','%s is NOT smaller than %s (rule %s)',$arg0, $arg1,$condition);
	    }
 	    return -1 * $negation;
 	}
     }


    ##### condition is_owner, is_subscriber and is_editor
    if ($condition_key =~ /^(is_owner|is_subscriber|is_editor)$/i) {
	my ($list2);

	if ($args[1] eq 'nobody') {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info',"%s can't be used to evaluate (rule %s)",$args[1],$condition);
	    }
	    return -1 * $negation ;
	}

	## The list is local or in another local robot
	if ($args[0] =~ /\@/) {
	    $list2 = Sympa::List->new(name => $args[0]);
	}else {
	    $list2 = Sympa::List->new(name => $args[0], robot => $robot);
	}

	if (! $list2) {
	    Sympa::Log::do_log('err',"unable to create list object \"$args[0]\"");
	    return -1 * $negation ;
	}

	if ($condition_key eq 'is_subscriber') {

	    if ($list2->is_list_member($args[1])) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"%s is member of list %s (rule %s)",$args[1],$args[0],$condition);
		}
		return $negation ;
	    }else{
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"%s is NOT member of list %s (rule %s)",$args[1],$args[0],$condition);
		}
		return -1 * $negation ;
	    }

	}elsif ($condition_key eq 'is_owner') {
	    if ($list2->am_i('owner',$args[1])) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"%s is owner of list %s (rule %s)",$args[1],$args[0],$condition);
		}
		return $negation ;
	    }else{
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"%s is NOT owner of list %s (rule %s)",$args[1],$args[0],$condition);
		}
		return -1 * $negation ;
	    }

	}elsif ($condition_key eq 'is_editor') {
	    if ($list2->am_i('editor',$args[1])) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"%s is editor of list %s (rule %s)",$args[1],$args[0],$condition);
		}
		return $negation ;
	    }else{
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"%s is NOT editor of list %s (rule %s)",$args[1],$args[0],$condition);
		}
		return -1 * $negation ;
	    }
	}
    }
    ##### match
    if ($condition_key eq 'match') {
	unless ($args[1] =~ /^\/(.*)\/$/) {
	    Sympa::Log::do_log('err', 'Match parameter %s is not a regexp', $args[1]);
	    return undef;
	}
	my $regexp = $1;

	# Nothing can match an empty regexp.
	if ($regexp =~ /^$/) {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info',"regexp '%s' is empty (rule %s)",$regexp,$condition);
	    }
	    return -1 * $negation;
	}

	if ($regexp =~ /\[host\]/) {
	    my $reghost = Sympa::Configuration::get_robot_conf($robot, 'host');
            $reghost =~ s/\./\\./g ;
            $regexp =~ s/\[host\]/$reghost/g ;
	}

	# wrap matches with eval{} to avoid crash by malformed regexp.
	my $r = 0;
	if (ref($args[0])) {
	    eval {
		foreach my $arg (@{$args[0]}) {
		    if ($arg =~ /$regexp/i) {
			$r = 1;
			last;
		    }
		}
	    };
	} else {
	    eval {
		if ($args[0] =~ /$regexp/i) {
		    $r = 1;
		}
	    };
	}
	if ($EVAL_ERROR) {
	    Sympa::Log::do_log('err', 'cannot evaluate match: %s', $EVAL_ERROR);
	    return undef;
	}
	if ($r) {
	    if ($log_it == 1) {
		my $args_as_string = '';
		if (ref($args[0])) {
		    foreach my $arg (@{$args[0]}) {
			$args_as_string .= "$arg, ";
		    }
		}else{
		    $args_as_string = $args[0];
		}
		Sympa::Log::do_log('info',"'%s' matches regexp '%s' (rule %s)",$args_as_string,$regexp,$condition);
	    }
	    return $negation;
	}else{
	    if ($log_it == 1) {
		my $args_as_string = '';
		if (ref($args[0])) {
		    foreach my $arg (@{$args[0]}) {
			$args_as_string .= "$arg, ";
		    }
		}else{
		    $args_as_string = $args[0];
		}
		Sympa::Log::do_log('info',"'%s' does not match regexp '%s' (rule %s)",$args_as_string,$regexp,$condition);
	    }
	    return -1 * $negation ;
	}
    }

    ## search rule
    if ($condition_key eq 'search') {
	my $val_search;
 	# we could search in the family if we got ref on Family object
 	if (defined $list){
 	    $val_search = search($args[0],$context,$robot,$list);
 	}else {
 	    $val_search = search($args[0],$context,$robot);
 	}
	return undef unless defined $val_search;
	if($val_search == 1) {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info',"'%s' found in '%s', robot %s (rule %s)",$context->{'sender'},$args[0],$robot,$condition);
	    }
	    return $negation;
	}else {
	    if ($log_it == 1) {
		Sympa::Log::do_log('info',"'%s' NOT found in '%s', robot %s (rule %s)",$context->{'sender'},$args[0],$robot,$condition);
	    }
	    return -1 * $negation;
    	}
    }

    ## equal
    if ($condition_key eq 'equal') {
	if (ref($args[0])) {
	    foreach my $arg (@{$args[0]}) {
		Sympa::Log::do_log('debug3', 'ARG: %s', $arg);
		    if (lc($arg) eq lc($args[1])) {
			if ($log_it == 1) {
			    Sympa::Log::do_log('info',"'%s' equals '%s' (rule %s)",lc($arg),lc($args[1]),$condition);
			}
			return $negation;
		    }
	    }
	} else {
	    if (lc($args[0]) eq lc($args[1])) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"'%s' equals '%s' (rule %s)",lc($args[0]),lc($args[1]),$condition);
		}
		return $negation;
	    }
	}
	if ($log_it == 1) {
	    Sympa::Log::do_log('info',"'%s' does NOT equal '%s' (rule %s)",lc($args[0]),lc($args[1]),$condition);
	}
	return -1 * $negation ;
    }

    ## custom perl module
    if ($condition_key =~ /^customcondition::(\w+)/o ) {
    	my $condition = $1;

    	my $res = verify_custom($condition, \@args, $robot, $list);
	unless (defined $res) {
	    if ($log_it == 1) {
		my $args_as_string = '';
		foreach my $arg (@args) {
		    $args_as_string .= ", $arg";
		}
		Sympa::Log::do_log('info',"custom condition '%s' returned an undef value with arguments '%s' (rule %s)",$condition,$args_as_string,$condition);
	    }
	    return undef;
	}
	if ($log_it == 1) {
	    my $args_as_string = '';
	    foreach my $arg (@args) {
		$args_as_string .= ", $arg";
	    }
	    if ($res == 1) {
		Sympa::Log::do_log('info',"'%s' verifies custom condition '%s' (rule %s)",$args_as_string,$condition,$condition);
	    }else {
		Sympa::Log::do_log('info',"'%s' does not verify custom condition '%s' (rule %s)",$args_as_string,$condition,$condition);
	    }
	}
	return $res * $negation ;
    }

    ## less_than
    if ($condition_key eq 'less_than') {
	if (ref($args[0])) {
	    foreach my $arg (@{$args[0]}) {
		Sympa::Log::do_log('debug3', 'ARG: %s', $arg);
		    if (Sympa::Tools::Data::smart_lessthan($arg, $args[1])){
			if ($log_it == 1) {
			    Sympa::Log::do_log('info',"'%s' is less than '%s' (rule %s)",$arg, $args[1],$condition);
			}
			return $negation;
		    }
	    }
	}else {
	    if (Sympa::Tools::Data::smart_lessthan($args[0], $args[1])) {
		if ($log_it == 1) {
		    Sympa::Log::do_log('info',"'%s' is less than '%s' (rule %s)",$args[0], $args[1],$condition);
		}
		return $negation ;
	    }
	}

	if ($log_it == 1) {
	    Sympa::Log::do_log('info',"'%s' is NOT less than '%s' (rule %s)",$args[0], $args[1],$condition);
	}
	return -1 * $negation ;
    }
    return undef;
}

## Verify if a given user is part of an LDAP, SQL or TXT search filter
sub search{
    my ($filter_file, $context, $robot, $list) = @_;

    my $sender = $context->{'sender'};
    Sympa::Log::do_log('debug2', '(%s,%s,%s)', $filter_file, $sender, $robot);

    if ($filter_file =~ /\.sql$/) {

	my $file = Sympa::Tools::get_filename('etc',{},"search_filters/$filter_file", $robot, $list, $Sympa::Configuration::Conf{'etc'});

        my $timeout = 3600;
        my $sql_conf;

        unless ($sql_conf = Sympa::Configuration::load_sql_filter($file)) {
            $list->send_notify_to_owner('named_filter',{'filter' => $filter_file})
                if (ref($list) && $list->isa('Sympa::List'));
            return undef;
        }
        $sql_conf->{domain} = $Sympa::Configuration::Conf{'domain'};

        my $statement = $sql_conf->{'sql_named_filter_query'}->{'statement'};
        my $filter = $statement;
	my @statement_args; ## Useful to later quote parameters

	## Minimalist variable parser ; only parse [x] or [x->y]
	## should be extended with the code from verify()
	while ($filter =~ /\[(\w+(\-\>[\w\-]+)?)\]/x) {
	    my ($full_var) = ($1);
	    my ($var, $key) = split /\-\>/, $full_var;

	    unless (defined $context->{$var}) {
		Sympa::Log::do_log('err', "Failed to parse variable '%s' in filter '%s'", $var, $file);
		return undef;
	    }

	    if (defined $key) { ## Should be a hash
		unless (defined $context->{$var}{$key}) {
		    Sympa::Log::do_log('err', "Failed to parse variable '%s.%s' in filter '%s'", $var, $key, $file);
		    return undef;
		}

		$filter =~ s/\[$full_var\]/$context->{$var}{$key}/;
		$statement =~ s/\[$full_var\]/\%s/;
		push @statement_args, $context->{$var}{$key};
	    }else { ## Scalar
		$filter =~ s/\[$full_var\]/$context->{$var}/;
		$statement =~ s/\[$full_var\]/\%s/;
		push @statement_args, $context->{$var};

	    }
	}

#        $statement =~ s/\[sender\]/%s/g;
#        $filter =~ s/\[sender\]/$sender/g;

        if (defined ($persistent_cache{'named_filter'}{$filter_file}{$filter}) &&
            (time <= $persistent_cache{'named_filter'}{$filter_file}{$filter}{'update'} + $timeout)){ ## Cache has 1hour lifetime
            Sympa::Log::do_log('notice', 'Using previous SQL named filter cache');
            return $persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'};
        }

	require Sympa::Datasource::SQL;
	my $ds = Sympa::Datasource::SQL->create($sql_conf->{'sql_named_filter_query'});
	unless (defined $ds && $ds->connect() && $ds->ping) {
            Sympa::Log::do_log('notice','Unable to connect to the SQL server %s:%d',$sql_conf->{'db_host'}, $sql_conf->{'db_port'});
            return undef;
        }

	## Quote parameters
	foreach (@statement_args) {
	    $_ = $ds->quote($_);
	}

        $statement = sprintf $statement, @statement_args;
        unless ($ds->query($statement)) {
            Sympa::Log::do_log('debug','%s named filter cancelled', $file);
            return undef;
        }

        my $res = $ds->fetch;
        $ds->disconnect();
        Sympa::Log::do_log('debug2','Result of SQL query : %d = %s', $res->[0], $statement);

        if ($res->[0] == 0){
            $persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'} = 0;
        }else {
            $persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'} = 1;
       }
        $persistent_cache{'named_filter'}{$filter_file}{$filter}{'update'} = time;
        return $persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'};

     }elsif ($filter_file =~ /\.ldap$/) {
	## Determine full path of the filter file
	my $file = Sympa::Tools::get_filename('etc',{},"search_filters/$filter_file", $robot, $list, $Sympa::Configuration::Conf{'etc'});

	unless ($file) {
	    Sympa::Log::do_log('err', 'Could not find search filter %s', $filter_file);
	    return undef;
	}
	my $timeout = 3600;
	my %ldap_conf;

	require Sympa::LDAP;
	return undef unless (%ldap_conf = Sympa::LDAP::load($file));

	my $filter = $ldap_conf{'filter'};

	## Minimalist variable parser ; only parse [x] or [x->y]
	## should be extended with the code from verify()
	while ($filter =~ /\[(\w+(\-\>[\w\-]+)?)\]/x) {
	    my ($full_var) = ($1);
	    my ($var, $key) = split /\-\>/, $full_var;

	    unless (defined $context->{$var}) {
		Sympa::Log::do_log('err', "Failed to parse variable '%s' in filter '%s'", $var, $file);
		return undef;
	    }

	    if (defined $key) { ## Should be a hash
		unless (defined $context->{$var}{$key}) {
		    Sympa::Log::do_log('err', "Failed to parse variable '%s.%s' in filter '%s'", $var, $key, $file);
		    return undef;
		}

		$filter =~ s/\[$full_var\]/$context->{$var}{$key}/;
	    }else { ## Scalar
		$filter =~ s/\[$full_var\]/$context->{$var}/;

	    }
	}

#	$filter =~ s/\[sender\]/$sender/g;

	if (defined ($persistent_cache{'named_filter'}{$filter_file}{$filter}) &&
	    (time <= $persistent_cache{'named_filter'}{$filter_file}{$filter}{'update'} + $timeout)){ ## Cache has 1hour lifetime
	    Sympa::Log::do_log('notice', 'Using previous LDAP named filter cache');
	    return $persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'};
	}

	my $ldap;
	my $params = Sympa::Tools::Data::dup_var(\%ldap_conf);
	require Sympa::Datasource::LDAP;
	my $ds = Sympa::Datasource::LDAP->new($params);

	unless (defined $ds && ($ldap = $ds->connect())) {
	    Sympa::Log::do_log('err',"Unable to connect to the LDAP server
		    '%s'", $params->{'ldap_host'});
	    return undef;
	    }

	## The 1.1 OID correponds to DNs ; it prevents the LDAP server from
	## preparing/providing too much data
	    my $mesg = $ldap->search(base => "$ldap_conf{'suffix'}" ,
				     filter => "$filter",
				 scope => "$ldap_conf{'scope'}",
				 attrs => ['1.1']);
	    unless ($mesg) {
		Sympa::Log::do_log('err',"Unable to perform LDAP search");
		return undef;
	    }
	    unless ($mesg->code == 0) {
		Sympa::Log::do_log('err','Ldap search failed');
		return undef;
	    }

	    if ($mesg->count() == 0){
		$persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'} = 0;

	    }else {
		$persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'} = 1;
	    }

	$ds->disconnect() or Sympa::Log::do_log('notice','Unbind impossible');
	    $persistent_cache{'named_filter'}{$filter_file}{$filter}{'update'} = time;

	    return $persistent_cache{'named_filter'}{$filter_file}{$filter}{'value'};

    }elsif($filter_file =~ /\.txt$/){
	# Sympa::Log::do_log('info', 'Sympa::List::search: eval %s', $filter_file);
	my @files = Sympa::Tools::get_filename('etc',{'order'=>'all'},"search_filters/$filter_file", $robot, $list, $Sympa::Configuration::Conf{'etc'});

	## Raise an error except for blacklist.txt
	unless (@files) {
	    if ($filter_file eq 'blacklist.txt') {
		return -1;
	    }else {
		Sympa::Log::do_log('err', 'Could not find search filter %s', $filter_file);
		return undef;
	    }
	}

	my $sender = lc($sender);
	foreach my $file (@files) {
	    Sympa::Log::do_log('debug3', 'found file  %s', $file);
	    unless (open FILE, $file) {
		Sympa::Log::do_log('err', 'Could not open file %s', $file);
		return undef;
	    }
	    while (<FILE>) {
		# Sympa::Log::do_log('debug3', 'Sympa::List::search: eval rule %s', $_);
		next if (/^\s*$/o || /^[\#\;]/o);
		my $regexp= $_ ;
		chomp $regexp;
		$regexp =~ s/\*/.*/ ;
		$regexp = '^'.$regexp.'$';
		# Sympa::Log::do_log('debug3', 'Sympa::List::search: eval  %s =~ /%s/i', $sender,$regexp);
		return 1  if ($sender =~ /$regexp/i);
	    }
	}
	return -1;
    } else {
	Sympa::Log::do_log('err',"Unknown filter file type %s", $filter_file);
    	return undef;
    }
}

# eval a custom perl module to verify a scenario condition
sub verify_custom {
	my ($condition, $args_ref, $robot, $list) = @_;
        my $timeout = 3600;

	my $filter = join ('*', @{$args_ref});
	Sympa::Log::do_log('debug2', '(%s,%s,%s,%s)', $condition, $filter, $robot, $list);
        if (defined ($persistent_cache{'named_filter'}{$condition}{$filter}) &&
            (time <= $persistent_cache{'named_filter'}{$condition}{$filter}{'update'} + $timeout)){ ## Cache has 1hour lifetime
            Sympa::Log::do_log('notice', 'Using previous custom condition cache %s', $filter);
            return $persistent_cache{'named_filter'}{$condition}{$filter}{'value'};
        }

    	# use this if your want per list customization (be sure you know what you are doing)
	#my $file = Sympa::Tools::get_filename('etc',{},"custom_conditions/${condition}.pm", $robot, $list, $Sympa::Configuration::Conf{'etc'});
	my $file = Sympa::Tools::get_filename('etc',{},"custom_conditions/${condition}.pm", $robot, undef, $Sympa::Configuration::Conf{'etc'});
	unless ($file) {
	    Sympa::Log::do_log('err', 'No module found for %s custom condition', $condition);
	    return undef;
	}
	Sympa::Log::do_log('notice', 'Use module %s for custom condition', $file);
	eval { require "$file"; };
	if ($EVAL_ERROR) {
	    Sympa::Log::do_log('err', 'Error requiring %s : %s (%s)', $condition, "$EVAL_ERROR", ref($EVAL_ERROR));
	    return undef;
	}
	my $res;
	eval "\$res = CustomCondition::${condition}::verify(\@{\$args_ref});";
	if ($EVAL_ERROR) {
	    Sympa::Log::do_log('err', 'Error evaluating %s : %s (%s)', $condition, "$EVAL_ERROR", ref($EVAL_ERROR));
	    return undef;
	}

	return undef unless defined $res;

        $persistent_cache{'named_filter'}{$condition}{$filter}{'value'} = ($res == 1 ? 1 : 0);
        $persistent_cache{'named_filter'}{$condition}{$filter}{'update'} = time;
        return $persistent_cache{'named_filter'}{$condition}{$filter}{'value'};
}

sub dump_all_scenarios {
    open TMP, ">/tmp/all_scenarios";
    Sympa::Tools::Data::dump_var(\%all_scenarios, 0, \*TMP);
    close TMP;
}

1;
