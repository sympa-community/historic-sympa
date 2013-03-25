package Sympa::Plugin;
use warnings;
use strict;

# FIXME: clean interface needed for these:
use tt2;
*wwslog = \&main::wwslog;

=head1 NAME

Sympa::Plugin - add plugin system to Sympa

=head1 SYNOPSIS

  # in the main program
  use Sympa::Plugins;
  Sympa::Plugins->load;

  # each plugin
  package Sympa::VOOT;  # example
  use parent 'Sympa::Plugin';

=head1 DESCRIPTION

In the Sympa system (version 6.2), each component has facts listed
all over the code.  This hinders a pluggable interface.  This module
implements a few tricky hacks to move towards accepting optional modules
which can get upgraded between major Sympa releases.

=head1 METHODS

=head2 Constructors

=head3 new OPTIONS
=cut

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($) {shift}


=head2 Plugin loader

The follow code is really tricky: it tries to separate the components
from the existing interface.

=head3 class method: register_plugin HASH

This method takes a HASH.  The supported keys are

over 4

=item C<url_commands> =E<gt> PAIRS

=item C<validate> =E<gt> PAIRS

=item C<web_tt2> =E<gt> DIRECTORY

=back

See the source of L<Sympa::VOOT> for an extended example.

=cut

sub register_plugin($)
{   my ($class, $args) = @_;

    if(my $url = $args->{url_commands})
    {   my @url = @$url;
        while(@url)
        {   my ($command, $settings) = (shift @url, shift @url);
            my $handler = $settings->{handler};

            $main::comm{$command} = sub
              { wwslog(info => "$command(@_)");
                $handler->
                  ( in       => \%main::in
                  , param    => $main::param
                  , session  => $main::session
                  , list     => $main::list
                  , robot_id => $main::robot_id
                  , @_
                  );
              };

            if(my $a = $settings->{path_args})
            {   $main::action_args{$command} = ref $a ? $a : [ $a ];
            }
            if(my $r = $settings->{required})
            {   $main::required_args{$command} = ref $r ? $r : [ $r ];
            }
	    if(my $p = $settings->{privilege})
            {   # default is 'everybody'
                $main::required_privileges{$command} = ref $p ? $p : [$p];
            }
        }
    }
    if(my $val = $args->{validate})
    {   my @val = @$val;
        while(@val)
        {   my $param = shift @val;
            $main::in_regexp{$param} = shift @val;
        }
    }
    if(my $templ = $args->{web_tt2})
    {   $main::plugins->add_web_tt2_path(ref $templ ? @$templ : $templ);
    }
}

1;
