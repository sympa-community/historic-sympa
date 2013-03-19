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

use Sympa::Configuration;
use Sympa::List;
use Sympa::Log::Syslog;

=head1 CLASS METHODS

=head2 Sympa::Robot->new(%parameters)

Creates a new L<Sympa::Robot> object.

=head3 Parameters

=over

=item * I<name>: FIXME

=back

=head3 Return

A new L<Sympa::Robot> object, or I<undef> if something went wrong.

=cut

sub new {
    my ($class, %params) = @_;

    unless (defined $params{name} && $Sympa::Configuration::Conf{'robots'}{$params{name}}) {
	Sympa::Log::Syslog::do_log('err',"Unknown robot '$params{name}'");
	return undef;
    }

    my $home = $params{name} eq $Sympa::Configuration::Conf{'domain'} ?
	$Sympa::Configuration::Conf{'home'} :
	$Sympa::Configuration::Conf{'home'}.'/'.$params{name};

    unless (-d $home) {
	    Sympa::Log::Syslog::do_log('err', "Missing directory $home for robot '$params{name}'");
	    return undef;
    }

    Sympa::Log::Syslog::do_log('debug2', '');

    my $self = {
	    name => $params{name},
	    home => $home,
    };

    ## Initialize internal list cache
    undef %Sympa::List::list_cache;

    bless $self, $class;

    return $self;
}

=head1 INSTANCE METHODS

=head2 $robot->get_lists()

Load all lists belonging to this robot

=head3 Parameters

None.

=cut

sub get_lists {
    my ($self) = @_;

    return Sympa::List::get_lists($self->{'name'});
}

1;
