## This package handles Sympa virtual robots
## It should :
##   * provide access to global conf parameters,
##   * deliver the list of lists
##   * determine the current robot, given a host
package Robot;

use Carp qw(croak);
use Conf;

our %list_of_robots = ();

## Croak if Robot object is used where robot name shall be used.
use overload
    'bool' => sub { 1 },
    '""' => sub { croak "object Robot <$_[0]->{'name'}> is not a string"; };

## Constructor of a Robot instance
sub new {
    &Log::do_log('debug2', '(%s, %s)', @_);
    my($pkg, $name) = @_;

    unless (defined $name && $Conf::Conf{'robots'}{$name}) {
	&Log::do_log('err', 'Unknown robot "%s"', $name);
	return undef;
    }

    my $robot;
    ## If robot already in memory
    if ($list_of_robots{$name}) {
	# use the current robot in memory and update it
	$robot = $list_of_robots{$name};
    } else {
	# create a new object robot
	$robot = bless { 'name' => $name } => $pkg;
    } 

    ## The default robot
    if ($name eq $Conf::Conf{'domain'}) {
	$robot->{'home'} = $Conf::Conf{'home'};
    }else {
	$robot->{'home'} = $Conf::Conf{'home'}.'/'.$name;
	unless (-d $robot->{'home'}) {
	    &Log::do_log('err', 'Missing directory "%s" for robot "%s"',
			 $robot->{'home'}, $name);
	    return undef;
	}
    }

    ## Initialize internal list cache
    undef %list_cache; #FIXME

    return $robot;
}

## load all lists belonging to this robot
sub get_lists {
    my $self = shift;

    return &List::get_lists($self->{'name'});
}


###### END of the Robot package ######

## Packages must return true.
1;
