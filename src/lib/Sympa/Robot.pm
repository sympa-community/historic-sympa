# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

=head1 NAME

Sympa::Robot - Virtual robot object

=head1 DESCRIPTION

This class implement a virtual robot.

=cut

package Sympa::Robot;

use strict;
use warnings;
use Carp qw(carp croak);

use Sympa::Log::Syslog;

use Sympa::listdef;
use Sympa::Site;

use base qw(Sympa::Site);

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
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s, ...)', @_);
	my ($class, %params) = @_;

	unless (defined $params{name} && Sympa::Site->robots($params{name})) {
		Sympa::Log::Syslog::do_log('err',"Unknown robot '$params{name}'");
		return undef;
	}

	## load global config if needed
	Sympa::Site->load(%params)
	if !$Sympa::Site::is_initialized or
	$params{'force_reload'};
	return undef unless $Sympa::Site::is_initialized;

	my $robot;
	## If robot already in memory
	if (Sympa::Site->robots($params{name})) {

		# use the current robot in memory and update it
		$robot = Sympa::Site->robots($params{name});
	} else {

		# create a new object robot
		$robot = bless {} => $class;
		my $status = $robot->load($params{name}, %params);
		unless (defined $status) {
			Sympa::Site->robots($params{name}, undef);
			return undef;
		}
	}

##    ## Initialize internal list cache
##    $robot->init_list_cache();

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

	$name = Sympa::Site->domain
	unless defined $name and
	length $name and
	$name ne '*';

	## load global config if needed
	Sympa::Site->load(%options)
	if !$Sympa::Site::is_initialized or
	$options{'force_reload'};
	return undef unless $Sympa::Site::is_initialized;

	unless ($self->{'name'} and $self->{'etc'}) {
		my $vhost_etc = Sympa::Site->etc . '/' . $name;

		if (-f $vhost_etc . '/robot.conf') {
			## virtual robot, even if its domain is same as that of main conf
			$self->{'etc'} = $vhost_etc;
		} elsif ($name eq Sympa::Site->domain) {
			## robot of main conf
			$self->{'etc'} = Sympa::Site->etc;
		} else {
			Sympa::Log::Syslog::do_log('err',
				'Unknown robot "%s": config directory was not found', $name)
			unless ($options{'just_try'});
			return undef;
		}

		$self->{'name'} = $name;
	}

	unless ($self->{'name'} eq $name) {
		Sympa::Log::Syslog::do_log('err', 'Bug in logic.  Ask developer');
		return undef;
	}

	unless ($self->{'etc'} eq Sympa::Site->etc) {
		## the robot uses per-robot config
		my $config_file = $self->{'etc'} . '/robot.conf';

		unless (-r $config_file) {
			Sympa::Log::Syslog::do_log('err', 'No read access on %s', $config_file);
			Sympa::Site->send_notify_to_listmaster(
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
			Sympa::Log::Syslog::do_log('err', 'Robot name "%s" is not same as domain "%s"',
				$name, $self->domain);
			Sympa::Site->robots($name, undef);
			##delete Sympa::Site->robots_config->{$self->domain};
			return undef;
		}
	}

	unless ($self->{'home'}) {
		my $vhost_home = Sympa::Site->home . '/' . $name;

		if (-d $vhost_home) {
			$self->{'home'} = $vhost_home;
		} elsif ($self->domain eq Sympa::Site->domain) {
			$self->{'home'} = Sympa::Site->home;
		} else {
			Sympa::Log::Syslog::do_log('err',
				'Unknown robot "%s": home directory was not found', $name);
			return undef;
		}
	}

	Sympa::Site->robots($name, $self);
	return 1;
}

=head2 METHODS

=over 4

=item get_address ( [ TYPE ] )

Returns the robot email address.
See L<Site/get_address>.

=back

=cut

##Inherited from Site class.

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

=item get_etc_include_path

make an array of include path for tt2 parsing.
See L<Site/get_etc_include_path>.

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

=head3 Lists

=over 4

=item is_available_topic ( TOPIC )

Check $topic in the $self conf

IN  : - $topic : id of the topic

OUT : - 1 if the topic is in the robot conf or undef

=back

=cut

sub is_available_topic {
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s)', @_);
	my $self  = shift;
	my $topic = shift;

	my ($top, $subtop) = split /\//, $topic;

	my %topics;
	unless (%topics = %{$self->topics || {}}) {
		Sympa::Log::Syslog::do_log('err', 'unable to load list of topics');
	}

	if ($subtop) {
		return 1
		if defined $topics{$top} and
		defined $topics{$top}{'sub'}{$subtop};
	} else {
		return 1 if defined $topics{$top};
	}

	return undef;
}

=over 4

=item split_listname ( MAILBOX )

XXX @todo doc

Note:
For C<-request> and C<-owner> suffix, this function returns
C<owner> and C<return_path> type, respectively.

=back

=cut

sub split_listname {
	my $self    = shift;
	my $mailbox = shift;
	return () unless defined $mailbox and length $mailbox;

	my $return_path_suffix = $self->return_path_suffix;
	my $regexp = join('|',
		map { s/(\W)/\\$1/g; $_ }
		grep { $_ and length $_ }
		split(/[\s,]+/, $self->list_check_suffixes));

	if ($mailbox eq 'sympa' and $self->domain eq Sympa::Site->domain) { # compat.
		return (undef, 'sympa');
	} elsif ($mailbox eq $self->email or
		$self->domain eq Sympa::Site->domain and $mailbox eq Sympa::Site->email) {
		return (undef, 'sympa');
	} elsif ($mailbox eq $self->listmaster_email or
		$self->domain eq Sympa::Site->domain and $mailbox eq Sympa::Site->listmaster_email) {
		return (undef, 'listmaster');
	} elsif ($mailbox =~ /^(\S+)$return_path_suffix$/) { # -owner
		return ($1, 'return_path');
	} elsif (!$regexp) {
		return ($mailbox);
	} elsif ($mailbox =~ /^(\S+)-($regexp)$/) {
		my ($name, $suffix) = ($1, $2);
		my $type;

		if ($suffix eq 'request') {
			$type = 'owner';
		} elsif ($suffix eq 'editor') {
			$type = 'editor';
		} elsif ($suffix eq 'subscribe') {
			$type = 'subscribe';
		} elsif ($suffix eq 'unsubscribe') {
			$type = 'unsubscribe';
		} else {
			$name = $mailbox;
			$type = 'UNKNOWN';
		}
		return ($name, $type);
	} else {
		return ($mailbox);
	}
}

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
	my ($self) = @_;
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

=head3 Handling Memory Caches

=over 4

=item families ( [ NAME, [ FAMILY ] ] )

Handles cached information of families on memory.

I<Getter>.
Gets cached family/ies on memory.  If memory cache is missed, returns C<undef>.

I<Setter>.
Updates memory cache.
If C<undef> was given as FAMILY, cache entry on the memory will be removed.

=back

=cut

sub families {
	my $self = shift;
	my $name = shift;

	if (scalar @_) {
		my $v = shift;
		unless (defined $v) {
			delete $self->{'families'}{$name};
		} else {
			$self->{'families'} ||= {};
			$self->{'families'}{$name} = $v;
		}
	}
	$self->{'families'}{$name};
}

=over 4

=item init_list_cache

Clear list cache on memory.

=back

=cut

sub init_list_cache {
	my $self = shift;
	delete $self->{'lists'};
	delete $self->{'lists_ok'};
}

=over 4

=item lists ( [ NAME, [ LIST ] ] )

Handles cached information of lists on memory.

I<Getter>.
Gets cached list(s) on memory.

When NAME and LIST are not given, returns an array of all cached lists.
Note: To ensure all lists are cached, check L<lists_ok>.

When NAME is given, returns cached list.
If memory cache is missed, returns C<undef>.

I<Setter>.
Updates memory cache.
If C<undef> was given as LIST, cache entry on the memory will be removed.

=back

=cut

sub lists {
	my $self = shift;
	unless (scalar @_) {
		return map { $self->{'lists'}->{$_} }
		sort keys %{$self->{'lists'} || {}};
	}

	my $name = shift;
	if (scalar @_) {
		my $v = shift;
		unless (defined $v) {
			delete $self->{'lists'}{$name};
		} else {
			$self->{'lists'} ||= {};
			$self->{'lists'}{$name} = $v;
		}
	}
	$self->{'lists'}{$name};
}

=over 4

=item lists_ok

I<Setter>, I<internal use>.
XXX @todo doc

=back

=cut

sub lists_ok {
	my $self = shift;
	$self->{'lists_ok'} = shift if scalar @_;
	$self->{'lists_ok'};
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

=back

=cut

## AUTOLOAD method will be inherited from Site class

sub DESTROY { }   # "sub DESTROY;" may cause segfault with Perl around 5.10.1.

=over 4

=item list_params

I<Getter>.
Returns hashref to list parameter information.

=back

=cut

sub list_params {
	croak "Can't modify \"list_params\" attribute" if scalar @_ > 1;
	my $self = shift;

	return $self->{'list_params'} if $self->{'list_params'};

	my $pinfo = tools::dup_var(\%listdef::pinfo);
	$pinfo->{'lang'}{'format'} = [$self->supported_languages];

	return $self->{'list_params'} = $pinfo;
}

=over 4

=item topics

I<Getter>.
Get a hashref including information of list topics available on the robot.

=back

=cut

sub topics {
	my $self = shift;

	my $conf_file = $self->get_etc_filename('topics.conf');
	unless ($conf_file) {
		Sympa::Log::Syslog::do_log('err', 'No topics.conf defined');
		return undef;
	}

	my $list_of_topics;

	## Load if not loaded or changed on disk
	if (!$self->{'topics'} or
		!$self->{'mtime'}{'topics.conf'} or
		(stat($conf_file))[9] > $self->{'mtime'}{'topics.conf'}) {

		## delete previous list of topics
		$list_of_topics = {};

		unless (-r $conf_file) {
			Sympa::Log::Syslog::do_log('err', 'Unable to read %s', $conf_file);
			return undef;
		}

		unless (open(FILE, '<', $conf_file)) {
			Sympa::Log::Syslog::do_log('err', 'Unable to open config file %s', $conf_file);
			return undef;
		}

		## Rough parsing
		my $index = 0;
		my (@rough_data, $topic);
		while (<FILE>) {
			Encode::from_to($_, Sympa::Site->filesystem_encoding, 'utf8');
			if (/^([\-\w\/]+)\s*$/) {
				$index++;
				$topic = {
					'name'  => $1,
					'order' => $index
				};
			} elsif (/^([\w\.]+)\s+(.+)\s*$/) {
				next unless defined $topic->{'name'};

				$topic->{$1} = $2;
			} elsif (/^\s*$/) {
				if (defined $topic->{'name'}) {
					push @rough_data, $topic;
					$topic = {};
				}
			}
		}
		close FILE;

		## Last topic
		if (defined $topic->{'name'}) {
			push @rough_data, $topic;
			$topic = {};
		}

		$self->{'mtime'}{'topics.conf'} = (stat($conf_file))[9];

		unless ($#rough_data > -1) {
			Sympa::Log::Syslog::do_log('notice', 'No topic defined in %s', $conf_file);
			return undef;
		}

		## Analysis
		foreach my $topic (@rough_data) {
			my @tree = split '/', $topic->{'name'};

			if ($#tree == 0) {
				my $title = _get_topic_titles($topic);
				$list_of_topics->{$tree[0]}{'title'} = $title;
				$list_of_topics->{$tree[0]}{'visibility'} =
				$topic->{'visibility'} || 'default';

				#$list_of_topics->{$tree[0]}{'visibility'} =
				#    _load_scenario_file('topics_visibility', $self,
				#    $topic->{'visibility'} || 'default');
				$list_of_topics->{$tree[0]}{'order'} = $topic->{'order'};
			} else {
				my $subtopic = join('/', @tree[1 .. $#tree]);
				my $title = _get_topic_titles($topic);
				$list_of_topics->{$tree[0]}{'sub'}{$subtopic} =
				_add_topic($subtopic, $title);
			}
		}

		## Set undefined Topic (defined via subtopic)
		foreach my $t (keys %{$list_of_topics}) {
			unless (defined $list_of_topics->{$t}{'visibility'}) {

				#$list_of_topics->{$t}{'visibility'} =
				#    _load_scenario_file('topics_visibility', $self,
				#    'default');
			}

			unless (defined $list_of_topics->{$t}{'title'}) {
				$list_of_topics->{$t}{'title'} = {'default' => $t};
			}
		}

		$self->{'topics'} = $list_of_topics;
	}

	$list_of_topics = tools::dup_var($self->{'topics'});

	## Set the title in the current language
	foreach my $top (keys %{$list_of_topics}) {
		my $topic = $list_of_topics->{$top};
		$topic->{'current_title'} = _get_topic_current_title($topic) || $top;

		foreach my $subtop (keys %{$topic->{'sub'}}) {
			$topic->{'sub'}{$subtop}{'current_title'} =
			_get_topic_current_title($topic->{'sub'}{$subtop}) || $subtop;
		}
	}

	return $list_of_topics;
}

sub _get_topic_titles {
	my $topic = shift;

	my $title;
	foreach my $key (%{$topic}) {
		if ($key =~ /^title(.(\w+))?$/) {
			my $lang = $2 || 'default';
			if ($lang eq 'gettext') {    # new in 6.2a.34
				;
			} elsif ($lang eq 'default') {
				;
			} else {
				$lang = Language::CanonicLang($lang) || $lang;
			}
			$title->{$lang} = $topic->{$key};
		}
	}

	return $title;
}

sub _get_topic_current_title {
	my $topic = shift;
	foreach my $lang (Language::ImplicatedLangs()) {
		if ($topic->{'title'}{$lang}) {
			return $topic->{'title'}{$lang};
		}
	}
	if ($topic->{'title'}{'gettext'}) {
		return Language::gettext($topic->{'title'}{'gettext'});
	} elsif ($topic->{'title'}{'default'}) {
		return Language::gettext($topic->{'title'}{'default'});
	} else {
		return undef;
	}
}

## Inner sub used by load_topics()
sub _add_topic {
	my ($name, $title) = @_;
	my $topic = {};

	my @tree = split '/', $name;
	if ($#tree == 0) {
		return {'title' => $title};
	} else {
		$topic->{'sub'}{$name} =
		_add_topic(join('/', @tree[1 .. $#tree]), $title);
		return $topic;
	}
}

=head3 Derived parameters

These are accessors derived from robot/default parameters.
Some of them are obsoleted.

=over 4

=item request

=item sympa

I<Getters>.
Gets derived config parameters.

B<Obsoleted>.
See L<Site/request> and L<Site/sympa>.

=back

=cut

## Inherited from Site class

=over 4

=item listmasters

I<Getter>.
In scalar context, returns arrayref of listmasters of robot.
In array context, returns array of them.

=back

=cut

## Inherited from Site class

=over 4

=item supported_languages

I<Getter>.
In array context, returns array of supported languages by robot.
In scalar context, returns arrayref to them.

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
	my $robot      = shift;
	my $maybe_site = shift;

	#Sympa::Log::Syslog::do_log('debug3', 'robot "%s", maybe_site "%s"', $robot, $maybe_site);
	unless (ref $robot or
		($maybe_site and !ref $robot and $robot eq 'Site')) {
		my $level = $Carp::CarpLevel;
		$Carp::CarpLevel = 1;
		carp "Deprecated usage: \"$robot\" should be a Robot object" .
		($maybe_site ? ' or Site class' : '');
		$Carp::CarpLevel = $level;

		if ($robot and $robot eq '*' and $maybe_site) {
			$robot = 'Site';
		} elsif ($robot and $robot ne '*') {
			$robot = Robot->new($robot);
		} else {
			croak "Illegal robot argument: " . ($robot || '');
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
	Sympa::Log::Syslog::do_log('debug2', '(...)');
	my %options = @_;

	my $robot;
	my @robots = ();
	my %orphan;
	my $got_default = 0;
	my $dir;

	## load global config if needed
	Sympa::Site->load(%options)
	if !$Sympa::Site::is_initialized or
	$options{'force_reload'};
	return undef unless $Sympa::Site::is_initialized;

	## Check memory cache first.
	if (Sympa::Site->robots_ok) {
		@robots = Sympa::Site->robots;
		return \@robots;
	}

	## get all cached robots
	%orphan = map { $_->domain => 1 } Sympa::Site->robots;

	unless (opendir $dir, Sympa::Site->etc) {
		Sympa::Log::Syslog::do_log('err',
			'Unable to open directory %s for virtual robots config',
			Sympa::Site->etc);
		return undef;
	}
	foreach my $name (readdir $dir) {
		next if $name =~ /^\./;
		my $vhost_etc = Sympa::Site->etc . '/' . $name;
		next unless -d $vhost_etc;
		next unless -f $vhost_etc . '/robot.conf';

		if ($robot = Robot->new($name, %options)) {
			$got_default = 1 if $robot->domain eq Sympa::Site->domain;
			push @robots, $robot;
			delete $orphan{$robot->domain};
		}
	}
	closedir $dir;

	unless ($got_default) {
		if ($robot = Robot->new(Sympa::Site->domain, %options)) {
			push @robots, $robot;
			delete $orphan{$robot->domain};
		}
	}

	## purge orphan robots
	foreach my $domain (keys %orphan) {
		Sympa::Log::Syslog::do_log('debug3', 'removing orphan robot %s', $domain);
		Sympa::Site->robots($domain, undef);
	}

	Sympa::Site->robots_ok(1);

	return \@robots;
}

###### END of the Robot package ######

1;
