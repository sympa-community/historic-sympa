package Sympa::Plugin::Manager;
use warnings;
use strict;

use Sympa::Plugin::Util qw/:functions/;
use JSON  qw/encode_json decode_json/;

my %required_plugins = qw/
 /;

my %optional_plugins = qw/
 Sympa::VOOT     0
 Sympa::OAuth1   0
 /;

=head1 NAME

Sympa::Plugin::Manager - module loader

=head1 SYNOPSIS

  use Sympa::Plugin::Manager;

  my $plugins = Sympa::Plugin::Manager->new;
  $plugins->start;

  $plugins->start(upgrade => 1);

=head1 DESCRIPTION

This module manages the loading of the code of plug-ins.  It does not
instantiate plugin objects.

=head1 METHODS

=head2 Constructors

=head2 class method: new OPTIONS

=over 4

=item * I<state_file> =E<gt> FILENAME

=item * I<state> =E<gt> HASH, by default read from C<state_file>

=back

=cut

sub new($%) { my ($class, %args) = @_; (bless {}, $class)->init(\%args) }
sub init($)
{   my ($self, $args) = @_;

    $self->{SPM_loaded} = {};

    my $fn = $self->{SPM_state_fn}
       = $args->{state_file} || Site->etc.'/plugins.conf';

    $self->{SPM_state}  = $args->{state} ||= $self->readState($fn);
    $self;
}


=head2 Accessors

=head3 method: loaded

=head3 method: stateFilename

=head3 method: state

=cut

sub loaded()        { shift->{SPM_loaded}   }
sub stateFilename() { shift->{SPM_state_fn} }
sub state()         { shift->{SPM_state}    }


=head2 Loading

=head3 method: start OPTIONS

Start an application with plugins.  Die() when some plug-in is new, so
the tables need to be upgraded.

Options:

=over 4

=item * I<upgrade> =E<gt> BOOLEAN

=item * I<only> =E<gt> PACKAGE|ARRAY-of-PACKAGE, empty means 'all'

=back

=cut

sub start(%)
{   my ($self, %args) = @_;

    #
    ### Load the plugins
    #

    my $need = $args{only} || [];
    my %need = map +($_ => 1), ref $need ? @$need : $need;

    while(my ($pkg, $version) = each %required_plugins)
    {   next if keys %need && $need{$pkg};
        $self->loadPlugin($pkg, version => $version, required => 1);
    }

    while(my ($pkg, $version) = each %optional_plugins)
    {   next if keys %need && $need{$pkg};
        $self->loadPlugin($pkg, version => $version, required => 0);
    }

    # Upgrade when there is new software
    $self->checkVersions(upgrade => $args{upgrade});

    # Start using the plugins
    $_->registerPlugin( {} ) for $self->list;

    $self;
}


=head3 method: loadPlugin PACKAGE, OPTIONS

Load a single plugin.  This can be used to load a new package during
development.  Returned is whether loading was successful.  When the
PACKAGE is required, the routine will exit the program on errors.

Options:

=over 4

=item C<version> =E<gt> VSTRING (default undef), the minimal version required.

=item C<required> =E<gt> BOOLEAN (default true)

=back

Example:

  Sympa::Plugin::Manager->loadPlugin('Sympa::VOOT', version => '3.0.0');

=cut

sub loadPlugin($%)
{   my ($self, $pkg, %args) = @_;
    my $loaded = $self->loaded;
    return if $loaded->{$pkg};  # already loaded

    my $required = exists $args{required} ? $args{required} : 1;
    my $version  = $args{version};

    if(eval "require $pkg")
    {   if(defined $version)
        {   eval { $pkg->VERSION($version) };
            if($@ && $required)
            {   fatal("required plugin $pkg is too old: $@");
            }
            elsif($@)
            {   log(notice => "installed optional plugin $pkg too old: $@");
            }
        }

        log(info => "loaded plugin $pkg");

        $loaded->{$pkg} = $pkg->VERSION;
        return 1;
    }

    if($@ =~ m/^Can't locate /)
    {   fatal("cannot find required plugin $pkg")
           if $required;

        log(notice => "optional plugin $pkg is not (completely) installed: $@");
    }
    elsif($required)
    {   fatalor("compilation errors in required plugin $pkg: $@");
    }
    else
    {   log(alert => "compilation errors in optional module $pkg: $@");
    }

    return 0;
}

=head3 method: checkVersions OPTIONS

Check whether the version of a certain plugin is equivalent to the
version on last run.  If not, we need to call the upgrade on the
plugin or die.

=over 4

=item * I<upgrade> =E<gt> BOOLEAN   (default false)

=cut

sub checkVersions(%)
{   my ($self, %args) = @_;

    my $old     = $self->state->{plugin_versions} ||= {};
    my $too_old = 0;
    my $upgrade = $args{upgrade} || 0;
$upgrade = 1;

  PLUGIN:
    foreach my $plugin ($self->list)
    {   my $old_version = $old->{$plugin};
        my $new_version = $self->versionOf($plugin);
        next if $old_version && $new_version eq $old_version;

        unless($upgrade)
        {   my $old = $old_version || 'scratch';
            log(notice => "plugin $plugin new version $new_version requires upgrade from $old");
            $too_old++;
            next PLUGIN;
        }

        # upgrade best in many small steps.
        until($old_version eq $new_version)
        {   $old_version = $old->{$plugin}
              = $plugin->upgrade(from_version => $old_version);

            $self->writeState;
        }
    }

    fatal("new software, data of $too_old plugins need conversion")
        if $too_old;

    $self;
}


=head2 Administration

=head3 method: list

Returns a list class names for all loaded plugins.

=cut

sub list(%) { keys %{shift->loaded} }

=head3 method: hasPlugin PACKAGE

Returns the class names of loaded plug-ins, which extend (or are equal
to) the requested PACKAGE name.

Example:

  if($plugins->hasPlugin('Sympa::VOOT')) ...

=cut

sub hasPlugin($)
{   my ($self, $pkg) = @_;
    grep $_->isa($pkg), $self->list;
}

=head3 method: versionOf PACKAGE

=cut

sub versionOf($)
{   my ($self, $package) = @_;
    $self->loaded->{$package};
}

=head3 method: addTemplates OPTIONS

=over 4

=item * I<tt2_path> =E<gt> DIRECTORY|ARRAY

=item * I<tt2_fragments> =E<gt> PAIRS

=back

=cut

sub addTemplates(%)
{   my ($self, %args) = @_;

    my $path  = $args{tt2_path} || [];
    push @{$self->{SPM_tt2_paths}}, ref $path ? @$path : $path;

    my $table = $self->{SPM_tt2_frag} ||= {};
    my @frag  = @{$args{tt2_fragments} || []};
    while(@frag)
    {   my $loc = shift @frag;
        push @{$table->{$loc}}, shift @frag;
    }
}

=head3 method: tt2Paths

=cut

sub tt2Paths() { @{shift->{SPM_tt2_paths} || []} }

=head3 method: tt2Fragments LOCATION

=cut

sub tt2Fragments($)
{   my ($self, $location) = @_;
    $self->{SPM_tt2_frag}{$location} || [];
}


=head2 State

The state file is used to track the behavior of the plug-in manager.
By default, this is the C<plugin.conf> file in the etc directory.

=head3 readState FILENAME

=head3 writeState

=cut

sub readState($)
{   my ($self, $fn) = @_;
    trace_call($fn);

    -f $fn or return {};

    open my $fh, "<:raw", $fn
        or fatal "cannot read plugin state from $fn";

    my $state = eval { local $/; decode_json <$fh> }
        or fatal "failed to read json from $fn: $@";

    $state;
}

sub writeState()
{   my $self = shift;
    my $fn   = $self->stateFilename;

    trace_call("write plugin state from $fn");
    open my $fh, ">:raw", $fn
        or fatal "cannot write plugin state to $fn: $!";

    $fh->print(JSON->new->pretty->encode($self->state));

    close $fh
        or fatal "failed to write plugin state to $fn: $!";
}

1;
