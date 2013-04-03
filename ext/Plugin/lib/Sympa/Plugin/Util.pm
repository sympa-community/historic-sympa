package Sympa::Plugin::Util;
use base 'Exporter';

use warnings;
use strict;

my @http = qw/HTTP_OK HTTP_BAD HTTP_UNAUTH HTTP_INTERN/;
my @time = qw/SECOND MINUTE HOUR DAY MONTH/;
my @obj  = qw/default_db robot this_list plugin/;
my @log  = qw/trace_call log fatal wwslog web_db_log/;

our @EXPORT      = ();
our @EXPORT_OK   = (@http, @time, @obj, @log);

our %EXPORT_TAGS =
  ( http      => \@http
  , time      => \@time
  , log       => \@log
  , functions => \@EXPORT
  );

=head1 NAME

Sympa::Plugin::Util - simplify connections to Sympa

=head1 SYNOPSIS

  use Sympa::Plugin::Util qw/default_db :http/;

=head1 DESCRIPTION

The Sympa core is under heavy development.  To be able to let plugins
work with different releases of Sympa, we add some abstractions.  More
will follow.

=head1 CONSTANTS

=head2 export tag C<:http>

A few used HTTP codes.

=head2 export tag C<:time>

Some constants to express time periods more clearly.

=cut

use constant SECOND => 1;
use constant MINUTE => 60 * SECOND;
use constant HOUR   => 60 * MINUTE;
use constant DAY    => 24 * HOUR;
use constant MONTH  => 30 * DAY;

# HTTP::Status is nowhere loaded in "core", so let's  keep it that
# way; just define the values we use.

use constant
  { HTTP_OK     => 200
  , HTTP_BAD    => 400
  , HTTP_UNAUTH => 401
  , HTTP_INTERN => 500
  };


=head1 FUNCTIONS

All functions are exported by default, or with tag C<:function>.

=head2 Database pseudo-object

Sympa "code" let all other modules call directly into the SDM package.
That is not clean and overly complicated.  It is much easier to have
a C<db> object.

=head3 $db = default_db()

Returns an object which handles database queries.  This can be removed
when Sympa-core profives access to the databases via clean objects.

The object returned offers the following methods:

=head3 $db->prepared(DBH, QUERY, BINDS)

=head3 $db->do(DBH, QUERY, BINDS)

In "core" named SDM::do_query(), but here with bindings, to remove the need
for SDM::quote().

=cut

{  package SPU_db;

   sub prepared($$@)
   {   my $db = shift;
       SDM::do_prepared_query(@_);
   }

   sub do($$@)               # I want automatic quoting
   {   my $db  = shift;
       my $sth = $db->prepared(@_);
       1;
   }
}

my $default_db;
sub default_db() { $default_db || (bless {}, 'SPU_db') }


=head2 Globals

These globals will probably change name in the near future.  We do not
want to update the plugins, all the time.

=head3 robot()

=head3 this_list()

=cut

sub robot() { $main::robot_object }

sub this_list() { $main::list }

=head3 plugin NAME, [INSTANCE]

Each plugin has an instance, which is started by the L<Sympa::Plugin::Manager>.
You can ask for them by NAME (of the base class).

=cut

my %plugins;
sub plugin($;$) { @_==2 ? ($plugins{$_[0]} = $_[1]) :  $plugins{$_[0]} }


=head2 Logging

=head3 trace_call(PARAMETERS)

=head3 log()

=head3 fatal()

=head3 wsslog()

=head3 web_db_log()

=cut

sub log(@)   { goto &Log::do_log }
sub fatal(@) { goto &Log::fatal_err }

sub trace_call(@)          # simplification of method logging
{   my $sub = (caller 1)[3];
    local $" =  ',';
    @_ = (debug2 => "$sub(@_)");
    goto &Log::do_log;
}

# These should (have been) modularized via Log::
*wwslog     = \&main::wwslog;
*web_db_log = \&main::web_db_log;

1;
