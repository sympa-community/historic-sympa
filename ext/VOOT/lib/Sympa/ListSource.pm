#### stub for currently unspecified interface
package Sympa::ListSource;

# The next two probably in a base-class of this one
sub new(%)  {my $class = shift; (bless {}, $class)->init({@_}) }
sub init($) {shift}

1;
