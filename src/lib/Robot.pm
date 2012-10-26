## This package handles Sympa virtual robots
## It should :
##   * provide access to global conf parameters,
##   * deliver the list of lists
##   * determine the current robot, given a host
package Robot;

use Carp qw(croak);
use Conf;

our %list_of_robots = ();
our %listmaster_messages_stack;

## Croak if Robot object is used where robot name shall be used.
use overload
    'bool' => sub { 1 },
    '""' => sub { croak "object Robot <$_[0]->{'name'}> is not a string"; };

=encoding utf-8

=head1 NAME

Robot - robot of mailing list service

=head1 DESCRIPTION

=head2 CONSTRUCTOR

=over 4

=item new( NAME, [ OPTIONS ] )

Creates a new object named as NAME.
Returns a Robot object, or undef on errors.

=back

=cut

## Constructor of a Robot instance
sub new {
    &Log::do_log('debug2', '(%s, %s, %s)', @_);
    my $pkg = shift;
    my $name = shift;
    my $options = shift || {};

    $name = '*' unless defined $name and length $name;

    ## load global config if needed
    &Conf::load() unless %Conf::Conf;

    my $robot;
    ## If robot already in memory
    if ($list_of_robots{$name}) {
	# use the current robot in memory and update it
	$robot = $list_of_robots{$name};
    } else {
	# create a new object robot
	$robot = bless { } => $pkg;
    } 
    my $status = $robot->load($name, $options);
    unless (defined $status) {
	delete Conf->robots->{$name} if defined Conf->robots;
	delete $list_of_robots{$name};
	return undef;
    }

    ## Initialize internal list cache
    undef %list_cache; #FIXME

    return $robot;
}

=head2 METHODS

=over 4

=item load ( NAME, [ OPTIONS ] )

Loads the indicated robot into the object.

=over 4

=item NAME

Name of robot.
This is the name of subdirectory under Sympa config & home directory.
The name C<'*'> (it is the default) indicates default robot.

=back

=back

=cut

sub load {
    my $self = shift;
    my $name = shift;
    my $options = shift || {};

    $name = Conf->domain
	unless defined $name and length $name and $name ne '*';

    ## load global config if needed
    &Conf::load() unless %Conf::Conf;

    unless ($self->{'name'} and $self->{'etc'}) {
	my $vhost_etc = Conf->etc . '/' . $name;

	if (-f $vhost_etc . '/robot.conf') {
	    ## virtual robot, even if its domain is same as that of main conf
	    $self->{'etc'} = $vhost_etc;
	} elsif ($name eq Conf->domain) {
	    ## robot of main conf
	    $self->{'etc'} = Conf->etc;
	} else {
	    &Log::do_log(
		'err', 'Unknown robot "%s": config directory was not found',
		$name
	    );
	    return undef;
	}

	$self->{'name'} = $name;
    }

    unless ($self->{'name'} eq $name) {
        &Log::do_log('err', 'Bug in logic.  Ask developer');
        return undef;
    }

    unless ($self->{'etc'} eq Conf->etc) {
	## the robot uses per-robot config
	my $config_file = $self->{'etc'} . '/robot.conf';

	unless (-r $config_file) {
	    &Log::do_log('err', 'No read access on %s', $config_file);
	    send_notify_to_listmaster(
		Conf->domain,
		'cannot_access_robot_conf',
		["No read access on $config_file. you should change privileges on this file to activate this virtual host. "]
	    );
            return undef;
	}

	unless (defined Conf::load_robot_conf({ %$options,
	    'config_file' => $config_file, 'robot' => $name })) {
	    return undef;
	}

	##
	## From now on, accessors such as "$self->domain" can be used.
	##

	## FIXME: Check if robot name is same as domain parameter.
	## Sympa might be wanted to allow arbitrary robot names  used
	## for config & home directories, though.
	unless ($self->domain eq $name) {
	    &Log::do_log('err', 'Robot name "%s" is not same as domain "%s"',
			 $name, $self->domain);
	    delete Conf->robots->{$self->domain};
	    delete $list_of_robots{$name};
	    return undef;
	}
    }

    unless ($self->{'home'}) {
	my $vhost_home = Conf->home . '/' . $name;

	if (-d $vhost_home) {
	    $self->{'home'} = $vhost_home;
	} elsif ($self->domain eq Conf->domain) {
	    $self->{'home'} = Conf->home;
	} else {
	    &Log::do_log(
		'err', 'Unknown robot "%s": home directory was not found',
		$name
	    );
	    return undef;
	}
    }

    $list_of_robots{$name} = $self;
    return 1;
}

=over 4

=item get_id

Get unique name of robot.

=back

=cut

sub get_id {
    ## DO NOT use accessors since $self may not have been fully initialized.
    shift->{'name'};
}

=over 4

=item is_listmaster ( WHO )

Is the user listmaster

=back

=cut

sub is_listmaster {
    my $self = shift;
    my $who = tools::clean_email(shift || '');
    return 0 unless $who;

    foreach my $listmaster (($self->listmasters,)) {
	return 1 if $listmaster eq $who;
    }
    foreach my $listmaster ((Conf->listmasters,)) {
	return 1 if $listmaster eq $who;
    }    

    return 0;
}

=over 4

=item send_global_file ( ... )

Send a global (not relative to a list)
message to a user.
Find the tt2 file according to $tpl, set up
$data for the next parsing (with $context and
configuration )

IN :
      -$tpl (+): template file name (file.tt2),
	without tt2 extension
      -$who (+): SCALAR |ref(ARRAY) - recipient(s)
      -$context : ref(HASH) - for the $data set up
       to parse file tt2, keys can be :
         -user : ref(HASH), keys can be :
           -email
           -lang
           -password
         -auto_submitted auto-generated|auto-replied|auto-forwarded
         -...
      -$options : ref(HASH) - options

OUT : 1 | undef

=back

=cut

sub send_global_file {
    &Log::do_log('debug2', '(%s, %s, %s, ...)', @_);
    my $self = shift;
    my $tpl = shift;
    my $who = shift;
    my ($context, $options) = @_;

    ## For compatibility: $robot may be either object or string.
    my $robot;
    if (ref $self) {
	$robot = $self->domain;
    } else {
	$robot = $self;
    }

    my $data = &tools::dup_var($context);

    unless ($data->{'user'}) {
	$data->{'user'} = &List::get_global_user($who)
	    unless ($options->{'skip_db'});
	$data->{'user'}{'email'} = $who unless (defined $data->{'user'});
    }
    unless ($data->{'user'}{'lang'}) {
	$data->{'user'}{'lang'} = $Language::default_lang;
    }

    unless ($data->{'user'}{'password'}) {
	$data->{'user'}{'password'} = &tools::tmp_passwd($who);
    }

    ## Lang
    $data->{'lang'} 
	= $data->{'lang'}
	|| $data->{'user'}{'lang'}
	|| &Conf::get_robot_conf($robot, 'lang');

    ## What file
    my $lang = &Language::Lang2Locale($data->{'lang'});
    my $tt2_include_path =
	&tools::make_tt2_include_path($robot, 'mail_tt2', $lang, '');

    foreach my $d (@{$tt2_include_path}) {
	&tt2::add_include_path($d);
    }

    my @path = &tt2::get_include_path();
    my $filename = &tools::find_file($tpl . '.tt2', @path);

    unless (defined $filename) {
	&Log::do_log('err', 'Could not find template %s.tt2 in %s',
	    $tpl, join(':', @path));
	return undef;
    }

    foreach my $p (
	'email',       'email_gecos',
	'host',        'sympa',
	'request',     'listmaster',
	'wwsympa_url', 'title',
	'listmaster_email'
	) {
	$data->{'conf'}{$p} = &Conf::get_robot_conf($robot, $p);
    }

    $data->{'sender'} = $who;
    $data->{'conf'}{'version'} = $main::Version;
    $data->{'from'} = "$data->{'conf'}{'email'}\@$data->{'conf'}{'host'}"
	unless ($data->{'from'});
    $data->{'robot_domain'} = $robot;
    $data->{'return_path'}  = &Conf::get_robot_conf($robot, 'request');
    $data->{'boundary'}     = '----------=_' . &tools::get_message_id($robot)
	unless ($data->{'boundary'});

    if ((&Conf::get_robot_conf($robot, 'dkim_feature') eq 'on') &&
	(&Conf::get_robot_conf($robot, 'dkim_add_signature_to') =~ /robot/)) {
	$data->{'dkim'} = &tools::get_dkim_parameters({ 'robot' => $robot });
    }

    # use verp excepted for alarms. We should make this configurable in
    # order to support Sympa server on a machine without any MTA service
    $data->{'use_bulk'} = 1
	unless ($data->{'alarm'}); 

    my $r = &mail::mail_file($filename, $who, $data, $robot,
	$options->{'parse_and_return'});
    return $r if ($options->{'parse_and_return'});

    unless ($r) {
	&Log::do_log(
	    'err', 'Could not send template "%s" to %s',
	    $filename, $who
	);
	return undef;
    }

    return 1;
}

=over 4

=item send_notify_to_listmaster ( OPERATION, DATA, CHECKSTACK, PURGE )

Sends a notice to listmaster by parsing
listmaster_notification.tt2 template

IN :
       -$operation (+): notification type
       -$param(+) : ref(HASH) | ref(ARRAY)
	values for template parsing

OUT : 1 | undef

=back

=cut

sub send_notify_to_listmaster {
    &Log::do_log('debug2', '(%s, %s, ...)', @_);
    my $self = shift;
    my ($operation, $data, $checkstack, $purge) = @_;

    ## For compatibility: $robot may be either object or string.
    my $robot;
    if (ref $self) {
	$robot = $self->domain;
    } else {
	$robot = $self;
    }

    if ($checkstack or $purge) {
	foreach my $robot (keys %listmaster_messages_stack) {
	    foreach my $operation (
		keys %{ $listmaster_messages_stack{$robot} }) {
		my $first_age = time -
		    $listmaster_messages_stack{$robot}{$operation}{'first'};
		my $last_age = time -
		    $listmaster_messages_stack{$robot}{$operation}{'last'};
		# not old enough to send and first not too old
		next
		    unless ($purge or ($last_age > 30) or ($first_age > 60));
		next
		    unless (
		    $listmaster_messages_stack{$robot}{$operation}{'messages'});

		my %messages =
		    %{ $listmaster_messages_stack{$robot}{$operation}{'messages'} };
		&Log::do_log(
		    'info', 'got messages about "%s" (%s)',
		    $operation, join(', ', keys %messages)
		);

		##### bulk send
		foreach my $email (keys %messages) {
		    my $param = {
			to                    => $email,
			auto_submitted        => 'auto-generated',
			alarm                 => 1,
			operation             => $operation,
			notification_messages => $messages{$email},
			boundary              =>
			    '----------=_' . &tools::get_message_id($robot)
		    };

		    my $options = {};
		    $options->{'skip_db'} = 1
			if (($operation eq 'no_db') ||
			($operation eq 'db_restored'));

		    &Log::do_log('info', 'send messages to %s', $email);
		    unless (
			&send_global_file(
			    'listmaster_groupednotifications',
			    $email, $robot, $param, $options
			)
			) {
			&Log::do_log('notice',
			    "Unable to send template 'listmaster_notification' to $email"
			) unless ($operation eq 'logs_failed');
			return undef;
		    }
		}

		&Log::do_log('info', 'cleaning stacked notifications');
		delete $listmaster_messages_stack{$robot}{$operation};
	    }
	}
	return 1;
    }

    my $stack = 0;
    $listmaster_messages_stack{$robot}{$operation}{'first'} = time
	unless ($listmaster_messages_stack{$robot}{$operation}{'first'});
    $listmaster_messages_stack{$robot}{$operation}{'counter'}++;
    $listmaster_messages_stack{$robot}{$operation}{'last'} = time;
    if ($listmaster_messages_stack{$robot}{$operation}{'counter'} > 3)
    {    # stack if too much messages w/ same code
	$stack = 1;
    }

    unless (defined $operation) {
	&Log::do_log('err', 'Missing incoming parameter "$operation"');
	return undef;
    }

    unless ($operation eq 'logs_failed') {
	unless (defined $robot) {
	    &Log::do_log('err', 'Missing incoming parameter "$robot"');
	    return undef;
	}
    }

    my $host       = &Conf::get_robot_conf($robot, 'host');
    my $listmaster = &Conf::get_robot_conf($robot, 'listmaster');
    my $to         = "$Conf::Conf{'listmaster_email'}\@$host";
    my $options = {};    ## options for send_global_file()

    unless (ref $data eq 'HASH' or ref $data eq 'ARRAY') {
	&Log::do_log('err', 'Error on incoming parameter "$data", it must be a ref on HASH or a ref on ARRAY')
	    unless $operation eq 'logs_failed';
	return undef;
    }

    if (ref($data) ne 'HASH') {
	my $d = {};
	for my $i (0 .. $#{$data}) {
	    $d->{"param$i"} = $data->[$i];
	}
	$data = $d;
    }

    $data->{'to'}             = $to;
    $data->{'type'}           = $operation;
    $data->{'auto_submitted'} = 'auto-generated';
    $data->{'alarm'}          = 1;

    if ($data->{'list'} && ref($data->{'list'}) eq 'List') {
	my $list = $data->{'list'};
	$data->{'list_object'} = $list;
	$data->{'list'} = {
	    'name'    => $list->name,
	    'host'    => $list->domain, #FIXME: robot name or mail hostname?
	    'subject' => $list->subject,
	};
    }

    my @tosend;

    if ($operation eq 'automatic_bounce_management') {
	## Automatic action done on bouncing adresses
	delete $data->{'alarm'};
	my $list = $data->{'list_object'};
	unless (defined $list and ref $list eq 'List') {
	    &Log::do_log( 'err', 'Parameter %s is not a valid list', $list);
	    return undef;
	}
	unless (
	    $list->send_file(
		'listmaster_notification',
		$listmaster, $robot, $data, $options
	    )
	    ) {
	    &Log::do_log('notice',
		'Unable to send template "listmaster_notification" to %s',
		$listmaster
	    );
	    return undef;
	}
	return 1;
    }

    if (($operation eq 'no_db') || ($operation eq 'db_restored')) {
	## No DataBase |  DataBase restored
	$data->{'db_name'} = &Conf::get_robot_conf($robot, 'db_name');
	$options->{'skip_db'}
	    = 1;    ## Skip DB access because DB is not accessible
    }

    if ($operation eq 'loop_command') {
	## Loop detected in Sympa
	$data->{'boundary'} = '----------=_' . &tools::get_message_id($robot);
	&tt2::allow_absolute_path();
    }

    if (   ($operation eq 'request_list_creation')
	or ($operation eq 'request_list_renaming')) {
	foreach my $email (split(/\,/, $listmaster)) {
	    my $cdata = &tools::dup_var($data);
	    $cdata->{'one_time_ticket'}
		= &Auth::create_one_time_ticket($email, $robot,
		'get_pending_lists', $cdata->{'ip'});
	    push @tosend,
		{
		email => $email,
		data  => $cdata
		};
	}
    } else {
	push @tosend,
	    {
	    email => $listmaster,
	    data  => $data
	    };
    }

    foreach my $ts (@tosend) {
	$options->{'parse_and_return'} = 1 if ($stack);
	my $r = &send_global_file('listmaster_notification', $ts->{'email'},
	    $robot, $ts->{'data'}, $options);
	if ($stack) {
	    &Log::do_log('info', 'stacking message about "%s" for %s (%s)',
		$operation, $ts->{'email'}, $robot);
	    push @{ $listmaster_messages_stack{$robot}{$operation}{'messages'}{ $ts->{'email'} } }, $r;
	    return 1;
	}

	unless ($r) {
	    &Log::do_log('notice',
		"Unable to send template 'listmaster_notification' to $listmaster"
	    ) unless ($operation eq 'logs_failed');
	    return undef;
	}
    }

    return 1;
}

## WITHDRAWN: use List::get_lists().
##sub get_lists {
##    return &List::get_lists(shift->domain);
##}

=head2 ACCESSORS

=over 4

=item E<lt>config parameterE<gt>

I<Getters>.
Get robot config parameter.
For example C<$robot-E<gt>listmaster> returns "listmaster" parameter of the
robot.

=item etc

=item home

=item name

I<Getters>.
Get profile of robot.

=back

=cut

our $AUTOLOAD;

sub DESTROY;

sub AUTOLOAD {
    $AUTOLOAD =~ m/^(.*)::(.*)/;

    my $attr = $2;
    my @p;
    if (ref $_[0] and
	grep { $_ eq $attr } qw(etc home name)) {
	## getter for list attributes.
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    croak "Can't modify \"$attr\" attribute" if scalar @_ > 1;
	    shift->{$attr};
	};
    } elsif (ref $_[0] and
	     grep { ! defined $_->{'title'} and $_->{'name'} eq $attr }
		  @confdef::params) {
	## getters for robot parameters.
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    my $self = shift;
	    unless ($self->{'etc'} eq Conf->etc or
		    defined Conf->robots->{$self->{'name'}}) {
		croak "Can't call method \"$attr\" on uninitialized " .
		    (ref $self) . " object";
	    }
	    croak "Can't modify \"$attr\" attribute" if scalar @_;
	    if (defined Conf->robots and
		defined Conf->robots->{$self->{'name'}} and
		defined Conf->robots->{$self->{'name'}}{$attr}) {
		##FIXME: Might "exists" be used?
		Conf->robots->{$self->{'name'}}{$attr};
	    } else {
		$Conf::Conf{$attr};
	    }
	};
    } else {
	croak "Can't locate object method \"$2\" via package \"$1\"";
    }

    goto &$AUTOLOAD;
}

=over 4

=item listmasters

I<Getter>.
In scalar context, returns arrayref of listmasters of robot.
In array context, returns array of them.

=back

=cut

sub listmasters {
    my $self = shift;
    croak "Can't modify \"listmasters\" attribute" if scalar @_;
    if (wantarray) {
	@{$Conf::Conf{'robots'}{$self->domain}{'listmasters'} || []};
    } else {
	$Conf::Conf{'robots'}{$self->domain}{'listmasters'};
    }
}

=head2 FUNCTIONS

=over 4

=item get_robots ( OPT => VALUE, ... )

I<Function>.
Get all robots hosted by Sympa.
Returns arrayref of Robot objects.

=back

=cut

sub get_robots {
    &Log::do_log('debug2', '(...)');
    my %options = @_;
    my $robot;
    my @robots = ();
    my %orphan;
    my $got_default = 0;
    my $dir;

    ## load global config if needed
    &Conf::load() unless %Conf::Conf;

    %orphan = map { $_ => 1 } keys %{Conf->robots || {}};

    unless (opendir $dir, Conf->etc) {
	&Log::do_log('err',
		     'Unable to open directory %s for virtual robots config',
		     Conf->etc);
	return undef;
    }
    foreach my $name (readdir $dir) {
	next if $name =~ /^\./;
	my $vhost_etc = Conf->etc . '/' . $name;
	next unless -d $vhost_etc;
	next unless -f $vhost_etc . '/robot.conf';

	unless ($robot = __PACKAGE__->new($name, \%options)) {
	    return undef;
	}
	$got_default = 1 if $robot->domain eq Conf->domain;
	push @robots, $robot;
	delete $orphan{$robot->domain};
    }
    closedir $dir;

    unless ($got_default) {
	unless ($robot = __PACKAGE__->new(Conf->domain, \%options)) {
	    return undef;
	}
	push @robots, $robot;
	delete $orphan{$robot->domain};
    }

    foreach my $domain (keys %orphan) {
	&Log::do_log('debug3', 'removing orphan robot %s', $orphan{$domain});
	delete Conf->robots->{$domain} if defined Conf->robots;
	delete $list_of_robots{$name};
    }

    return \@robots;
}

###### END of the Robot package ######

## Packages must return true.
1;
