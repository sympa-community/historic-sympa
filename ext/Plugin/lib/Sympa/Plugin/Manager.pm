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

my %plugins;

=head1 NAME

Sympa::Plugin::Manager - module loader

=head1 SYNOPSIS

  use Sympa::Plugin::Manager;

  Sympa::Plugin::Manager->load_plugins;

=head1 DESCRIPTION

This module manages the loading of the code of plug-ins.  It does not
instantiate plugin objects.

=head1 METHODS

=head2 Loading

=head3 class method: load_plugins OPTIONS

Load all known plugins, unless a sub-set is specified.

Options:

=over 4

=item C<only> =E<gt> PACKAGE|ARRAY-of-PACKAGE, empty means 'all'

=back

=cut

sub load_plugins(%)
{   my ($class, %args) = @_;

    my $need = $args{only} || [];
    my %need = map +($_ => 1), ref $need ? @$need : $need;

    while(my ($pkg, $version) = each %required_plugins)
    {   next if keys %need && $need{$pkg};
        $class->load_plugin($pkg, version => $version, required => 1);
    }

    while(my ($pkg, $version) = each %optional_plugins)
    {   next if keys %need && $need{$pkg};
        $class->load_plugin($pkg, version => $version, required => 0);
    }
}

=head3 class method: load_plugin PACKAGE, OPTIONS

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
{   my ($class, $pkg, %args) = @_;
    return if $plugins{$pkg};  # already loaded

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

        $plugins{$pkg}++;
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

=head3 class method: list

Returns a list class names for all loaded plugins.

=cut

sub list(%)
{   my ($class, %args) = @_;
    keys %plugins;
}

=head3 class method: has PACKAGE

Returns the class names of loaded plug-ins, which extend (or are equal
to) the requested PACKAGE name.

Example:

  if(Sympa::Plugin::Manager->has('Sympa::VOOT')) ...

=cut

sub has($)
{   my ($class, $pkg) = @_;
    grep $_->isa($pkg), keys %plugins;
}

1;
