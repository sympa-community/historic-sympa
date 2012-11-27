=head1 NAME 

Sympa::Robot - Virtual robot object

=head1 DESCRIPTION 

This class implement a virtual robot.

=cut 

package Sympa::Robot;

use Sympa::Conf;
use Sympa::List;
use Sympa::Log;

## Constructor of a Robot instance
sub new {
    my($pkg, $name) = @_;

    my $robot = {'name' => $name};
    &Sympa::Log::do_log('debug2', '');
    
    unless (defined $name && $Sympa::Conf::Conf{'robots'}{$name}) {
	&Sympa::Log::do_log('err',"Unknown robot '$name'");
	return undef;
    }

    ## The default robot
    if ($name eq $Sympa::Conf::Conf{'domain'}) {
	$robot->{'home'} = $Sympa::Conf::Conf{'home'};
    }else {
	$robot->{'home'} = $Sympa::Conf::Conf{'home'}.'/'.$name;
	unless (-d $robot->{'home'}) {
	    &Sympa::Log::do_log('err', "Missing directory '$robot->{'home'}' for robot '$name'");
	    return undef;
	}
    }

    ## Initialize internal list cache
    undef %list_cache;

    # create a new Robot object
    bless $robot, $pkg;

    return $robot;
}

## load all lists belonging to this robot
sub get_lists {
    my $self = shift;

    return &Sympa::List::get_lists($self->{'name'});
}


###### END of the Robot package ######

## Packages must return true.
1;
