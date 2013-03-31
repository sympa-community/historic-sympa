
package Sympa::Plugin::ListSource;
use warnings;
use strict;

use Sympa::Plugin::Util qw/:functions/;

# From Sympa core
# be sure they are loaded before me!
use Datasource          ();

=head1 NAME

Sympa::Plugin::ListSource - list source interface for Sympa::List plugins

=head1 SYNOPSIS

  package Sympa::VOOT;
  use base 'Sympa::Plugin', 'Sympa::Plugin::ListSource';

  my $source = Sympa::VOOT->listSource;
  my $count  = $source->getUsers(...);

=head1 DESCRIPTION

When a plugin implements this module, it can be called by Sympa's the List
object to perform some tasks: it is the interface description of pluggable
data-sources.

=head1 METHODS

=head2 Constructors

=head3 $class->new(OPTIONS)

Options:

=over 4

=item * may_sync =E<gt> BOOLEAN  (default true)

=back

=cut

# The new is provided by Sympa::Plugin.

sub init($)
{   my ($self, $args) = @_;
    $self->{SPL_sync} = exists $args->{may_sync} ? $args->{may_sync} : 1;
    $self;
}

=head2 Accessors

=head3 $self->listSourceName

=head3 $self->isAllowedToSync

=cut

sub listSourceName()  { die }
sub isAllowedToSync() { shift->{SPL_sync} }

=head2 Action

=head3 $obj->getSourceId(PARAMS)

=cut

sub getSourceId($)    { Datasource::_get_datasource_id($_[1]) }

=head3 $obj->getUsers(OPTIONS)

Options:

=over 4

=item * list =E<gt> List object

=item * users =E<gt> HASH, found members added to this

=item * source_id =E<gt> UNIQUE

=item * settings =E<gt> HASH

=item * keep_tied =E<gt> BOOLEAN, pack user info into string

=item * user_defaults =E<gt> HASH

=item * admin_only =E<gt> BOOLEAN

=back

=cut

sub getUsers(%) { die }

=head3 $obj->reportListError(LIST, NAME)

The NAME is the given name to this resource.  If you need anything
special to be done in case of an error, then extend this.  Returns
the success.

=cut

sub reportListError($$) { 1 }

1;
