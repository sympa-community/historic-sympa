## This package handles Sympa global site
## It should :
##   * provide access to global conf parameters,
##   * deliver the list of robots

package Site;

use Carp qw(croak);
use Exporter;

use Conf;
use Language;

our @ISA = qw(Exporter);
our @EXPORT = qw(%list_of_robots);

our %list_of_robots = ();
our %listmaster_messages_stack;

=head1 NAME

Site - Sympa site

=head1 DESCRIPTION

=head2 CLASS METHODS

=over 4

=item load ( OBJECT, [ OPT => VAL, ... ] )

Loads and parses the configuration file.  Reports errors if any.

do not try to load database values if 'no_db' option is set;
do not change global hash %Conf if 'return_result' option is set;

##we known that's dirty, this proc should be rewritten without this global var %Conf

NOTE: To load entire robots config, use C<Robot::get_robots('force_reload' =E<gt> 1)>.

=back

=cut

sub load {
    my $self = shift;
    my %opts = @_;

    if (ref $self and ref $self eq 'Robot') {
	unless ($self->{'name'} and $self->{'etc'}) {
	    &Log::do_log('err', 'object %s has not been initialized', $self);
	    return undef;
	}
	$opts{'config_file'} = $self->{'etc'} . '/robot.conf';
	$opts{'robot'} = $self->{'name'};
    } elsif ($self eq __PACKAGE__) {
	$opts{'config_file'} ||= Conf::get_sympa_conf();
	$opts{'robot'} = '*';
    } else {
	&Log::do_log(
	    'err', 'bug in logic.  Ask developer: Unknown object %s', $self
	);
	return undef;
    }

    my $result = Conf::load_robot_conf(\%opts);
    return undef unless defined $result;
    return $result if $opts{'return_result'};
    return 1;
}

=over 4

=item send_file                              

Send a site-global (not relative to a list or a robot) message to a user.
Find the tt2 file according to $tpl, set up 
$data for the next parsing (with $context and
configuration)
Message is signed if the list has a key and a 
certificate

IN :
      -$self (+): ref(List) | ref(Robot) | ref(conf)
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

## This method proxies site-global, robot-global and list-local methods,
## i.e. Site->send_file(), $robot->send_file() and $list->send_file().

sub send_file {
    &Log::do_log('debug2', '(%s, %s, %s, ...)', @_);
    my $self = shift;
    my $tpl  = shift;
    my $who  = shift;
    my $context = shift || {};
    my $options = shift || {};

    my ($robot, $list, $robot_id);
    if (ref $self and ref $self eq 'List') {
	$robot = $self->robot;
	$list = $self;
	$robot_id = $self->robot->name;
    } elsif (ref $self and ref $self eq 'Robot') {
	$robot = $self;
	$list = '';
	$robot_id = $self->name;
    } elsif ($self eq __PACKAGE__) {
	$robot = $self;
	$list = '';
	$robot_id = '*';
    } else {
	croak 'bug in logic.  Ask developer';
    }

    my $data = &tools::dup_var($context);

    ## Any recipients
    if (!defined $who or
	ref $who and !scalar @$who or
	!ref $who and !length $who) {
	&Log::do_log('err', 'No recipient for sending %s', $tpl);
	return undef;
    }

    ## Unless multiple recipients
    unless (ref $who) {
	$who = tools::clean_email($who);
	unless ($data->{'user'}) {
	    if ($options->{'skip_db'}) {
		$data->{'user'} = bless { 'email' => $who } => 'User';
	    } else {
		$data->{'user'} = User->new($who);
	    }
	}
	unless ($data->{'user'}{'lang'}) {
	    if (ref $self eq 'List') {
		$data->{'user'}{'lang'} = $self->lang;
	    } else {
		$data->{'user'}{'lang'} = $Language::default_lang;
	    }
	}

	if (ref $self eq 'List') {
	    $data->{'subscriber'} = $self->get_list_member($who);

	    if ($data->{'subscriber'}) {
		$data->{'subscriber'}{'date'} = gettext_strftime "%d %b %Y",
		    localtime($data->{'subscriber'}{'date'});
		$data->{'subscriber'}{'update_date'} =
		    gettext_strftime "%d %b %Y",
		    localtime($data->{'subscriber'}{'update_date'});
		if ($data->{'subscriber'}{'bounce'}) {
		    $data->{'subscriber'}{'bounce'} =~
			/^(\d+)\s+(\d+)\s+(\d+)(\s+(.*))?$/;

		    $data->{'subscriber'}{'first_bounce'} =
			gettext_strftime "%d %b %Y", localtime($1);
		}
	    }
	}

	unless ($data->{'user'}{'password'}) {
	    $data->{'user'}{'password'} = &tools::tmp_passwd($who);
	}

	if (ref $self eq 'List') {
	    ## Unique return-path VERP
	    if ($self->welcome_return_path eq 'unique' and $tpl eq 'welcome')
	    {
		$data->{'return_path'} = $self->get_bounce_address($who, 'w');
	    } elsif ($self->remind_return_path eq 'unique' and
		$tpl eq 'remind') {
		$data->{'return_path'} = $self->get_bounce_address($who, 'r');
	    }
	}
    }

    $data->{'return_path'} ||= $self->get_list_address('return_path')
	if ref $self eq 'List';

    ## Lang
    if (ref $self eq 'List') {
	$data->{'lang'} = $data->{'user'}{'lang'} || $self->lang ||
	    $robot->lang;
    } else {
	$data->{'lang'} = $data->{'user'}{'lang'} || $robot->lang;
    }

    if (ref $self eq 'List') {
	## Trying to use custom_vars
	if (defined $self->custom_vars) {
	    $data->{'custom_vars'} = {};
	    foreach my $var (@{$self->custom_vars}) {
		$data->{'custom_vars'}{$var->{'name'}} = $var->{'value'};
	    }
	}
    }

    ## What file
    my $lang = &Language::Lang2Locale($data->{'lang'});
    my $tt2_include_path =
	&tools::make_tt2_include_path($robot_id, 'mail_tt2', $lang, $list);
    if (ref $self eq 'List') {
	## list directory to get the 'info' file
	push @{$tt2_include_path}, $self->dir;
	## list archives to include the last message
	push @{$tt2_include_path}, $self->dir . '/archives';
    }

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

    $data->{'conf'} ||= {};
    $data->{'conf'}{'email'} = $robot->email;
    $data->{'conf'}{'email_gecos'} = $robot->email_gecos;
    $data->{'conf'}{'host'} = $robot->host;
    $data->{'conf'}{'sympa'} = $robot->sympa;
    $data->{'conf'}{'request'} = $robot->request;
    $data->{'conf'}{'listmaster'} = $robot->listmaster;
    $data->{'conf'}{'wwsympa_url'} = $robot->wwsympa_url;
    $data->{'conf'}{'title'} = $robot->title;
    $data->{'conf'}{'listmaster_email'} = $robot->listmaster_email;

    $data->{'sender'} ||= $who;

    $data->{'conf'}{'version'} = $main::Version;
    $data->{'robot_domain'} = $robot_id;
    if (ref $self eq 'List') {
	$data->{'list'}{'lang'}   = $self->lang;
	$data->{'list'}{'name'}   = $self->name;
	$data->{'list'}{'domain'} = $self->domain;
	$data->{'list'}{'host'}    = $self->host;
	$data->{'list'}{'subject'} = $self->subject;
	$data->{'list'}{'owner'}   = $self->get_owners();
	$data->{'list'}{'dir'}     = $self->dir;

	## Sign mode
	my $sign_mode;
	if (Site->openssl and
	    -r $self->dir . '/cert.pem' and -r $self->dir . '/private_key') {
	    $sign_mode = 'smime';
	}
	$data->{'sign_mode'} = $sign_mode;

	# if the list have it's private_key and cert sign the message
	# . used only for the welcome message, could be usefull in other case?
	# . a list should have several certificats and use if possible a
	#   certificat issued by the same CA as the receipient CA if it exists
	if ($sign_mode and $sign_mode eq 'smime') {
	    $data->{'fromlist'} = $self->get_list_address();
	    $data->{'replyto'}  = $self->get_list_address('owner');
	} else {
	    $data->{'fromlist'} = $self->get_list_address('owner');
	}
	$data->{'from'} = $data->{'fromlist'} unless $data->{'from'};
    } else {
	$data->{'from'} = $self->email . '@' . $self->host
	    unless $data->{'from'};
	$data->{'return_path'}  = $self->request;
    }

    $data->{'boundary'} = '----------=_' . &tools::get_message_id($robot_id)
	unless ($data->{'boundary'});

    my $dkim_feature = $robot->dkim_feature;
    my $dkim_add_signature_to = $robot->dkim_add_signature_to;
    if ($dkim_feature eq 'on' and $dkim_add_signature_to =~ /robot/) {
	$data->{'dkim'} = &tools::get_dkim_parameters({'robot' => $robot_id});
    }

    # use verp excepted for alarms. We should make this configurable in
    # order to support Sympa server on a machine without any MTA service
    $data->{'use_bulk'} = 1
	unless ($data->{'alarm'});
    my $r = &mail::mail_file($filename, $who, $data, $robot_id,
	$options->{'parse_and_return'});
    return $r if $options->{'parse_and_return'};

    unless ($r) {
	&Log::do_log('err', 'Could not send template "%s" to %s',
	    $filename, $who);
	return undef;
    }

    return 1;
}

=over 4

=item send_notify_to_listmaster ( OPERATION, DATA, CHECKSTACK, PURGE )

Sends a notice to super listmaster by parsing
listmaster_notification.tt2 template

IN :
       -$operation (+): notification type
       -$param(+) : ref(HASH) | ref(ARRAY)
        values for template parsing

OUT : 1 | undef

=back

=cut

## This method proxies site-global and robot-global methods, i.e.
## Site->send_notify_to_listmaster() and $robot->send_notify_to_listmaster().

sub send_notify_to_listmaster {
    &Log::do_log('debug2', '(%s, %s, ...)', @_);
    my $self       = shift;
    my $operation  = shift;
    my $data       = shift;
    my $checkstack = shift;
    my $purge      = shift;

    my $robot_id;
    if (ref $self and ref $self eq 'Robot') {
	$robot_id = $self->name;
    } elsif ($self eq __PACKAGE__) {
	$robot_id = '*';
    } else {
	&Log::do_log('err', 'bug in logic.  Ask developer');
	return undef;
    }

    if ($checkstack or $purge) {
	foreach my $robot_id (keys %listmaster_messages_stack) {
	    my $robot;
	    if (! $robot_id or $robot_id eq '*') {
		$robot = __PACKAGE__;
	    } else {
		$robot = Robot->new($robot_id);
	    }

	    foreach
		my $operation (keys %{$listmaster_messages_stack{$robot_id}})
	    {
		my $first_age =
		    time -
		    $listmaster_messages_stack{$robot_id}{$operation}
		    {'first'};
		my $last_age = time -
		    $listmaster_messages_stack{$robot_id}{$operation}{'last'};

		# not old enough to send and first not too old
		next
		    unless ($purge or ($last_age > 30) or ($first_age > 60));
		next
		    unless ($listmaster_messages_stack{$robot_id}{$operation}
		    {'messages'});

		my %messages =
		    %{$listmaster_messages_stack{$robot_id}{$operation}
			{'messages'}};
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
			boundary              => '----------=_' .
			    &tools::get_message_id($robot_id)
		    };

		    my $options = {};
		    $options->{'skip_db'} = 1
			if (($operation eq 'no_db') ||
			($operation eq 'db_restored'));

		    &Log::do_log('info', 'send messages to %s', $email);
		    unless (
			$robot->send_file(
			    'listmaster_groupednotifications',
			    $email, $param, $options
			)
			) {
			&Log::do_log('notice',
			    "Unable to send template 'listmaster_notification' to $email"
			) unless ($operation eq 'logs_failed');
			return undef;
		    }
		}

		&Log::do_log('info', 'cleaning stacked notifications');
		delete $listmaster_messages_stack{$robot_id}{$operation};
	    }
	}
	return 1;
    }

    my $stack = 0;
    $listmaster_messages_stack{$robot_id}{$operation}{'first'} = time
	unless ($listmaster_messages_stack{$robot_id}{$operation}{'first'});
    $listmaster_messages_stack{$robot_id}{$operation}{'counter'}++;
    $listmaster_messages_stack{$robot_id}{$operation}{'last'} = time;
    if ($listmaster_messages_stack{$robot_id}{$operation}{'counter'} > 3) {

	# stack if too much messages w/ same code
	$stack = 1;
    }

    unless (defined $operation) {
	&Log::do_log('err', 'Missing incoming parameter "$operation"');
	return undef;
    }

    unless ($operation eq 'logs_failed') {
	unless (defined $robot_id) {
	    &Log::do_log('err', 'Missing incoming parameter "$robot_id"');
	    return undef;
	}
    }

    my $host       = $self->host;
    my $listmaster = $self->listmaster;
    my $to         = $self->listmaster_email . '@' . $host;
    my $options = {};    ## options for send_file()

    if (!ref $data and length $data) {
	$data = [$data];
    }
    unless (ref $data eq 'HASH' or ref $data eq 'ARRAY') {
	&Log::do_log(
	    'err',
	    'Error on incoming parameter "%s", it must be a ref on HASH or a ref on ARRAY',
	    $data
	) unless $operation eq 'logs_failed';
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

    my $list = undef;
    if ($data->{'list'} and ref($data->{'list'}) eq 'List') {
	$list = $data->{'list'};
	$data->{'list'} = {
	    'name'    => $list->name,
	    'host'    => $list->domain,   #FIXME: robot name or mail hostname?
	    'subject' => $list->subject,
	};
    }

    my @tosend;

    if ($operation eq 'automatic_bounce_management') {
	## Automatic action done on bouncing adresses
	delete $data->{'alarm'};
	unless (defined $list and ref $list eq 'List') {
	    &Log::do_log('err', 'Parameter %s is not a valid list', $list);
	    return undef;
	}
	unless (
	    $list->send_file(
		'listmaster_notification',
		$listmaster, $data, $options
	    )
	    ) {
	    &Log::do_log('notice',
		'Unable to send template "listmaster_notification" to %s',
		$listmaster);
	    return undef;
	}
	return 1;
    }

    if ($operation eq 'no_db' or $operation eq 'db_restored') {
	## No DataBase |  DataBase restored
	$data->{'db_name'} = $self->db_name;
	## Skip DB access because DB is not accessible
	$options->{'skip_db'} = 1;
    }

    if ($operation eq 'loop_command') {
	## Loop detected in Sympa
	$data->{'boundary'} =
	    '----------=_' . &tools::get_message_id($robot_id);
	&tt2::allow_absolute_path();
    }

    if (($operation eq 'request_list_creation') or
	($operation eq 'request_list_renaming')) {
	foreach my $email (split(/\,/, $listmaster)) {
	    my $cdata = &tools::dup_var($data);
	    $cdata->{'one_time_ticket'} =
		&Auth::create_one_time_ticket($email, $robot_id,
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
	my $r =
	    $self->send_file('listmaster_notification', $ts->{'email'},
	    $ts->{'data'}, $options);
	if ($stack) {
	    &Log::do_log('info', 'stacking message about "%s" for %s (%s)',
		$operation, $ts->{'email'}, $robot_id);
	    ## stack robot object and parsed message.
	    push @{$listmaster_messages_stack{$robot_id}{$operation}
		    {'messages'}{$ts->{'email'}}}, $r;
	    return 1;
	}

	unless ($r) {
	    &Log::do_log('notice',
		'Unable to send template "listmaster_notification" to %s',
		$listmaster
	    ) unless $operation eq 'logs_failed';
	    return undef;
	}
    }

    return 1;
}

=head3 ACCESSORS

=over 4

=item E<lt>config parameterE<gt>

I<Getters>.
Gets global or default config parameters.
For example: C<Site-E<gt>syslog> returns "syslog" global parameter;
C<Site-E<gt>domain> returns default "domain" parameter.

Some parameters may be vary by each robot from default value given by these
methods.  Use C<$robot-E<gt>>E<lt>config parameterE<gt> accessors instead.
See L<Robot/ACCESSORS>.

=item locale2charset

=item pictures_path

=item request

=item robots

=item sympa

I<Getters>.
Gets config parameters for internal use.

=back

=cut

our $AUTOLOAD;

sub DESTROY;

sub AUTOLOAD {
    $AUTOLOAD =~ m/^(.*)::(.*)/;

    my $attr = $2;
    if (scalar grep { $_ eq $attr }
		    qw(locale2charset pictures_path request robots sympa) or
	scalar grep { ! defined $_->{'title'} and $_->{'name'} eq $attr }
		    @confdef::params) {
	## getter for internal config parameters.
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    my $pkg = shift;
	    croak "Can't call method \"$attr\" on uninitialized $pkg class"
		unless %Conf::Conf;
	    croak "Can't modify \"$attr\" attribute"
		if scalar @_ > 1;
	    $Conf::Conf{$attr};
	};
    } else {
	croak "Can't locate object method \"$2\" via package \"$1\"";
    }
    goto &$AUTOLOAD;
}

=over 4

=item listmasters

I<Getter>.
Gets default listmasters.
In array context, returns array of default listmasters.
In scalar context, returns arrayref to them.

=back

=cut

sub listmasters {
    my $pkg = shift;
    croak "Can't call method \"listmasters\" on uninitialized $pkg class"
	unless %Conf::Conf;
    croak "Can't modify \"listmasters\" attribute" if scalar @_ > 1;
    if (wantarray) {
	return @{$Conf::Conf{'listmasters'} || []};
    } else {
	return $Conf::Conf{'listmasters'};
    }
}

## Packages must return true.
1;
