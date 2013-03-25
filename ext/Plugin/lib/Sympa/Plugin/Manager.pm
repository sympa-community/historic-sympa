package Sympa::Plugin::Manager;
use warnings;
use strict;

#use Log;

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
  $plugins->load_plugins;

=head1 DESCRIPTION

This module manages the loading of the code of plug-ins.  It does not
instantiate plugin objects.

=head1 METHODS

=head2 Constructors

=head2 class method: new OPTIONS

=cut

sub new($%) { my ($class, %args) = @_; (bless {}, $class)->init(\%args) }
sub init($) {shift}

=head2 Loading

=head3 method: load_plugins OPTIONS

Load all known plugins, unless a sub-set is specified.

Options:

=over 4

=item C<only> =E<gt> PACKAGE|ARRAY-of-PACKAGE, empty means 'all'

=back

=cut

sub load_plugins(%)
{   my ($self, %args) = @_;

    my $need = $args{only} || [];
    my %need = map +($_ => 1), ref $need ? @$need : $need;

    while(my ($pkg, $version) = each %required_plugins)
    {   next if keys %need && $need{$pkg};
        $self->load_plugin($pkg, version => $version, required => 1);
    }

    while(my ($pkg, $version) = each %optional_plugins)
    {   next if keys %need && $need{$pkg};
        $self->load_plugin($pkg, version => $version, required => 0);
    }
}

=head3 method: load_plugin PACKAGE, OPTIONS

Load a single plugin.  This can be used to load a new package during
development.  Returned is whether loading was successful.  When the
PACKAGE is required, the routine will exit the program on errors.

Options:

=over 4

=item C<version> =E<gt> VSTRING (default undef), the minimal version required.

=item C<required> =E<gt> BOOLEAN (default true)

=back

Example:

  Sympa::Plugin::Manager->load_plugin('Sympa::VOOT', version => '3.0.0');

=cut

sub load_plugin($%)
{   my ($self, $pkg, %args) = @_;
    return if $self->{SPM_plugins}{$pkg};  # already loaded

    my $required = exists $args{required} ? $args{required} : 1;
    my $version  = $args{version};

    if(eval "require $pkg")
    {   if(defined $version)
        {   eval { $pkg->VERSION($version) };
            if($@ && $required)
            {   Log::fatal_err("required plugin $pkg is too old: $@");
            }
            elsif($@)
            {   Log::do_log(notice => "installed optional plugin $pkg too old: $@");
            }
        }

        Log::do_log(info => "loaded plugin $pkg");

        $pkg->register_plugin( {} )
            if $pkg->can('register_plugin');

        $self->{SPM_plugins}{$pkg}++;
        return 1;
    }

    if($@ =~ m/^Can't locate /)
    {   Log::fatal_err("cannot find required plugin $pkg")
           if $required;

        Log::do_log(notice => "optional plugin $pkg is not (completely) installed");
    }
    elsif($required)
    {   Log::fatal_error("compilation errors in required plugin $pkg: $@");
    }
    else
    {   Log::do_log(alert => "compilation errors in optional module $pkg: $@");
    }

    return 0;
}

=head2 Administration

=head3 method: list

Returns a list class names for all loaded plugins.

=cut

sub list(%)
{   my ($self, %args) = @_;
    keys %{$self->{SPM_plugins}};
}

=head3 method: has PACKAGE

Returns the class names of loaded plug-ins, which extend (or are equal
to) the requested PACKAGE name.

Example:

  if($plugins->has('Sympa::VOOT')) ...

=cut

sub has($)
{   my ($self, $pkg) = @_;
    grep $_->isa($pkg), $self->list;
}

=head3 method: add_templates OPTIONS

=over 4

=item C<tt2_path> =E<gt> DIRECTORY|ARRAY

=item C<tt2_fragments> =E<gt> PAIRS

=back

=cut

sub add_templates(%)
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

=head3 method: tt2_paths

=cut

sub tt2_paths() { @{shift->{SPM_tt2_paths} || []} }

=head3 method: tt2_fragments LOCATION

=cut

sub tt2_fragments($)
{   my ($self, $location) = @_;
    Log::do_log(err => "tt2_fragments(@_)");
    $self->{SPM_tt2_frag}{$location} || [];
}

1;
