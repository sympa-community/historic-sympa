## This package handles Sympa virtual robots
## It should :
##   * provide access to robot conf parameters,
##   * deliver the list of lists
##   * determine the current robot, given a host
package Robot;

use Carp qw(croak);

use Site;

our @ISA = qw(Site);

## Croak if Robot object is used where robot name shall be used.
## It may be removed when refactoring has finished.
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
    &Log::do_log('debug2', '(%s, %s, ...)', @_);
    my $pkg = shift;
    my $name = shift;
    my @options = @_;

    $name = '*' unless defined $name and length $name;

    ## load global config if needed
    Site->load(@options) unless %Conf::Conf;

    my $robot;
    ## If robot already in memory
    if ($list_of_robots{$name}) {
	# use the current robot in memory and update it
	$robot = $list_of_robots{$name};
    } else {
	# create a new object robot
	$robot = bless { } => $pkg;
    } 
    my $status = $robot->load($name, @options);
    unless (defined $status) {
	delete Site->robots->{$name} if defined Site->robots;
	delete $list_of_robots{$name};
	return undef;
    }

    ## Initialize internal list cache
    undef %list_cache; #FIXME

    return $robot;
}

=head2 METHODS

=over 4

=item load ( NAME, [ KEY => VAL, ... ] )

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
    my @options = @_;

    $name = Site->domain
	unless defined $name and length $name and $name ne '*';

    ## load global config if needed
    Site->load(@options) unless %Conf::Conf;

    unless ($self->{'name'} and $self->{'etc'}) {
	my $vhost_etc = Site->etc . '/' . $name;

	if (-f $vhost_etc . '/robot.conf') {
	    ## virtual robot, even if its domain is same as that of main conf
	    $self->{'etc'} = $vhost_etc;
	} elsif ($name eq Site->domain) {
	    ## robot of main conf
	    $self->{'etc'} = Site->etc;
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

    unless ($self->{'etc'} eq Site->etc) {
	## the robot uses per-robot config
	my $config_file = $self->{'etc'} . '/robot.conf';

	unless (-r $config_file) {
	    &Log::do_log('err', 'No read access on %s', $config_file);
	    send_notify_to_listmaster(
		Site->domain,
		'cannot_access_robot_conf',
		["No read access on $config_file. you should change privileges on this file to activate this virtual host. "]
	    );
            return undef;
	}

	unless (defined $self->SUPER::load(@options)) {
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
	    delete Site->robots->{$self->domain};
	    delete $list_of_robots{$name};
	    return undef;
	}
    }

    unless ($self->{'home'}) {
	my $vhost_home = Site->home . '/' . $name;

	if (-d $vhost_home) {
	    $self->{'home'} = $vhost_home;
	} elsif ($self->domain eq Site->domain) {
	    $self->{'home'} = Site->home;
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
    foreach my $listmaster ((Site->listmasters,)) {
	return 1 if $listmaster eq $who;
    }    

    return 0;
}

=over 4

=item send_file ( ... )

Send a global (not relative to a list, but relative to a robot)
message to user(s).
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

## Inherited from Site::send_file().

=over 4

=item send_notify_to_listmaster ( OPERATION, DATA, CHECKSTACK, PURGE )

Sends a notice to normal listmaster by parsing
listmaster_notification.tt2 template

IN :
       -$operation (+): notification type
       -$param(+) : ref(HASH) | ref(ARRAY)
	values for template parsing

OUT : 1 | undef

=back

=cut

## Inherited from Site::send_notify_to_listmaster().

## WITHDRAWN: use List::get_lists().
##sub get_lists {
##    return &List::get_lists(shift->domain);
##}

=head3 ACCESSORS

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

=item pictures_path

=item request

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
    my @p;
    if (ref $_[0] and
	grep { $_ eq $attr } qw(etc home name)) {
	## getter for list attributes.
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    croak "Can't modify \"$attr\" attribute" if scalar @_ > 1;
	    shift->{$attr};
	};
    } elsif (
	ref $_[0] and
	    grep { $_ eq $attr }
		 qw(pictures_path request sympa) or
	ref $_[0] and
	    grep { ! defined $_->{'title'} and $_->{'name'} eq $attr }
		 @confdef::params
    ) {
	## getters for robot parameters.
	no strict "refs";
	*{$AUTOLOAD} = sub {
	    my $self = shift;
	    unless ($self->{'etc'} eq Site->etc or
		    defined Site->robots->{$self->{'name'}}) {
		croak "Can't call method \"$attr\" on uninitialized " .
		    (ref $self) . " object";
	    }
	    croak "Can't modify \"$attr\" attribute" if scalar @_;
	    if (defined Site->robots and
		defined Site->robots->{$self->{'name'}} and
		defined Site->robots->{$self->{'name'}}{$attr}) {
		##FIXME: Might "exists" be used?
		Site->robots->{$self->{'name'}}{$attr};
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
	@{Site->robots->{$self->domain}{'listmasters'} || []};
    } else {
	Site->robots->{$self->domain}{'listmasters'};
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
    my @options = @_;
    my $robot;
    my @robots = ();
    my %orphan;
    my $got_default = 0;
    my $dir;

    ## load global config if needed
    Site->load(@options) unless %Conf::Conf;

    %orphan = map { $_ => 1 } keys %{Site->robots || {}};

    unless (opendir $dir, Site->etc) {
	&Log::do_log('err',
		     'Unable to open directory %s for virtual robots config',
		     Site->etc);
	return undef;
    }
    foreach my $name (readdir $dir) {
	next if $name =~ /^\./;
	my $vhost_etc = Site->etc . '/' . $name;
	next unless -d $vhost_etc;
	next unless -f $vhost_etc . '/robot.conf';

	unless ($robot = __PACKAGE__->new($name, @options)) {
	    return undef;
	}
	$got_default = 1 if $robot->domain eq Site->domain;
	push @robots, $robot;
	delete $orphan{$robot->domain};
    }
    closedir $dir;

    unless ($got_default) {
	unless ($robot = __PACKAGE__->new(Site->domain, @options)) {
	    return undef;
	}
	push @robots, $robot;
	delete $orphan{$robot->domain};
    }

    foreach my $domain (keys %orphan) {
	&Log::do_log('debug3', 'removing orphan robot %s', $orphan{$domain});
	delete Site->robots->{$domain} if defined Site->robots;
	delete $list_of_robots{$name};
    }

    return \@robots;
}

###### END of the Robot package ######

## Packages must return true.
1;
