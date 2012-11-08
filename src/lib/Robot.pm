## This package handles Sympa virtual robots
## It should :
##   * provide access to robot conf parameters,
##   * determine the current robot, given a domain
##   * deliver the list of robots
package Robot;

use strict;
use warnings;
use Carp qw(carp croak);

use Site;

our @ISA = qw(Site);

## Croak if Robot object is used where robot name shall be used.
## It may be removed when refactoring has finished.
use overload
    'bool' => sub {1},
    '""'   => sub { croak "object Robot <$_[0]->{'name'}> is not a string"; };

=encoding utf-8

=head1 NAME

Robot - robot of mailing list service

=head1 DESCRIPTION

=head2 CONSTRUCTOR AND INITIALIZER

=over 4

=item new( NAME, [ OPTIONS ] )

Creates a new object named as NAME.
Returns a Robot object, or undef on errors.

=back

=cut

## Constructor of a Robot instance
sub new {
    &Log::do_log('debug2', '(%s, %s, ...)', @_);
    my $pkg     = shift;
    my $name    = shift;
    my %options = @_;

    $name = '*' unless defined $name and length $name;

    ## load global config if needed
    Site->load(%options)
	if !$Site::is_initialized or
	    $options{'force_reload'};
    return undef unless $Site::is_initialized;

    my $robot;
    ## If robot already in memory
    if ($Site::list_of_robots{$name}) {

	# use the current robot in memory and update it
	$robot = $Site::list_of_robots{$name};
    } else {

	# create a new object robot
	$robot = bless {} => $pkg;
    }
    my $status = $robot->load($name, %options);
    unless (defined $status) {
	delete Site->robots->{$name} if defined Site->robots;
	delete $Site::list_of_robots{$name};
	return undef;
    }

    ## Initialize internal list cache
##    undef %list_cache;    #FIXME

    return $robot;
}

=over 4

=item load ( NAME, [ KEY => VAL, ... ] )

Loads the indicated robot into the object.

=over 4

=item NAME

Name of robot.
This is the name of subdirectory under Sympa config & home directory.
The name C<'*'> (it is the default) indicates default robot.

=back

Note: To load site default, use C<Site-E<gt>load()>.
See also L<Site/load>.

=back

=cut

sub load {
    my $self    = shift;
    my $name    = shift;
    my %options = @_;

    $name = Site->domain
	unless defined $name and
	    length $name and
	    $name ne '*';

    ## load global config if needed
    Site->load(%options)
	if !$Site::is_initialized or
	    $options{'force_reload'};
    return undef unless $Site::is_initialized;

    unless ($self->{'name'} and $self->{'etc'}) {
	my $vhost_etc = Site->etc . '/' . $name;

	if (-f $vhost_etc . '/robot.conf') {
	    ## virtual robot, even if its domain is same as that of main conf
	    $self->{'etc'} = $vhost_etc;
	} elsif ($name eq Site->domain) {
	    ## robot of main conf
	    $self->{'etc'} = Site->etc;
	} else {
	    &Log::do_log('err',
		'Unknown robot "%s": config directory was not found', $name);
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
	    Site->send_notify_to_listmaster(
		'cannot_access_robot_conf',
		[   "No read access on $config_file. you should change privileges on this file to activate this virtual host. "
		]
	    );
	    return undef;
	}

	unless (defined $self->SUPER::load(%options)) {
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
	    delete $Site::list_of_robots{$name};
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
	    &Log::do_log('err',
		'Unknown robot "%s": home directory was not found', $name);
	    return undef;
	}
    }

    $Site::list_of_robots{$name} = $self;
    return 1;
}

=head2 METHODS

=over 4

=item get_id

Get unique name of robot.

=back

=cut

sub get_id {
    ## DO NOT use accessors since $self may not have been fully initialized.
    shift->{'name'} || '';
}

=over 4

=item is_listmaster

See L<Site/is_listmaster>.

=item make_tt2_include_path

make an array of include path for tt2 parsing.
See L<Site/make_tt2_include_path>.

=item send_dsn

Sends an delivery status notification (DSN).
See L<Site/send_dsn>.

=item send_file ( ... )

Send a global (not relative to a list, but relative to a robot)
message to user(s).
See L<Site/send_file>.

Note: List::send_global_file() was deprecated.

=item send_notify_to_listmaster ( OPERATION, DATA, CHECKSTACK, PURGE )

Sends a notice to normal listmaster by parsing
listmaster_notification.tt2 template
See L<Site/send_notify_to_listmaster>.

Note: List::send_notify_to_listmaster() was deprecated.

=back

=cut

## Inherited from Site class.

=head3 Handling netidmap table

=over 4

=item get_netidtoemail_db

get idp xref to locally validated email address

=item set_netidtoemail_db

set idp xref to locally validated email address

=item update_email_netidmap_db

Update netidmap table when user email address changes

=back

=cut

sub get_netidtoemail_db {
    my $self = shift;
    return List::get_netidtoemail_db($self->domain, @_);
}

sub set_netidtoemail_db {
    my $self = shift;
    return List::set_netidtoemail_db($self->domain, @_);
}

sub update_email_netidmap_db {
    my $self = shift;
    return List::update_netidtoemail_db($self->domain, @_);
}

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

=item list_check_regexp

=item pictures_path

=item request

=item sympa

I<Getters>.
Gets derived config parameters.

=back

=cut

#XXXour $AUTOLOAD;
## AUTOLOAD method will be inherited from Site class

sub DESTROY;

=over 4

=item listmasters

I<Getter>.
In scalar context, returns arrayref of listmasters of robot.
In array context, returns array of them.

=back

=cut

## Inherited from Site class

=head2 FUNCTIONS

=over 4

=item clean_robot ( ROBOT_OR_NAME )

I<Function>.
Warns if the argument is not a Robot object.
Returns a Robot object, if any.

I<TENTATIVE>.
This function will be used during transition between old and object-oriented
styles.  At last modifications have been done, this shall be removed.

=back

=cut

sub clean_robot {
    my $robot = shift;
    my $maybe_site = shift;

    unless (ref $robot or
	($maybe_site and !ref $robot and $robot eq 'Site')) {
	my $level = $Carp::CarpLevel;
	$Carp::CarpLevel = 1;
	carp "Deprecated usage: \"$robot\" should be a Robot object";
	$Carp::CarpLevel = $level;

	if ($robot and $robot ne '*') {
	    $robot = Robot->new($robot);
	} else {
	    $robot = undef;
	}
    }
    $robot;
}

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
    my $exiting = 0;

    ## load global config if needed
    Site->load(%options)
	if !$Site::is_initialized or
	    $options{'force_reload'};
    return undef unless $Site::is_initialized;

    ## get all robots
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

	unless ($robot = Robot->new($name, %options)) {
	    closedir $dir;
	    return undef;
	    $exiting = 1;
	    next;
	} else {
	    $got_default = 1 if $robot->domain eq Site->domain;
	    push @robots, $robot;
	    delete $orphan{$robot->domain};
	}
    }
    closedir $dir;

    unless ($got_default) {
	unless ($robot = Robot->new(Site->domain, %options)) {
	    return undef;
	    $exiting = 1;
	} else {
	    push @robots, $robot;
	    delete $orphan{$robot->domain};
	}
    }

    ## purge orphan robots
    foreach my $domain (keys %orphan) {
	&Log::do_log('debug3', 'removing orphan robot %s', $orphan{$domain});
	delete Site->robots->{$domain} if defined Site->robots;
	delete $Site::list_of_robots{$domain};
    }

    return \@robots;
}

###### END of the Robot package ######

## Packages must return true.
1;
