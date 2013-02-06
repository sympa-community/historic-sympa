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
use Sympa::Log;

=head1 CLASS METHODS

=head2 Sympa::Robot->new($name)

Creates a new L<Sympa::Robot> object.

=head3 Parameters

=over

=item * I<$name>

=back

=head3 Return

A new L<Sympa::Robot> object, or I<undef>, if something went wrong.

=cut

sub new {
    my ($class, $name) = @_;

    my $robot = {'name' => $name};
    Sympa::Log::do_log('debug2', '');

    unless (defined $name && $Sympa::Configuration::Conf{'robots'}{$name}) {
	Sympa::Log::do_log('err',"Unknown robot '$name'");
	return undef;
    }

    ## The default robot
    if ($name eq $Sympa::Configuration::Conf{'domain'}) {
	$robot->{'home'} = $Sympa::Configuration::Conf{'home'};
    }else {
	$robot->{'home'} = $Sympa::Configuration::Conf{'home'}.'/'.$name;
	unless (-d $robot->{'home'}) {
	    Sympa::Log::do_log('err', "Missing directory '$robot->{'home'}' for robot '$name'");
	    return undef;
	}
    }

    ## Initialize internal list cache
    undef %Sympa::List::list_cache;

    # create a new Robot object
    bless $robot, $class;

    return $robot;
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
