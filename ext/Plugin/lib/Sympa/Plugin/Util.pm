package Sympa::Plugin::Util;
use base 'Exporter';

use warnings;
use strict;

my @http = qw/HTTP_OK HTTP_BAD HTTP_UNAUTH HTTP_INTERN/;
my @time = qw/SECOND MINUTE HOUR DAY MONTH/;
my @func = qw/default_db trace_call log fatal/;

our @EXPORT      = @func;
our @EXPORT_OK   = (@http, @time, @func);

our %EXPORT_TAGS =
  ( http      => \@http
  , time      => \@time
  , functions => \@EXPORT
  );

=head1 NAME

Sympa::Plugin::Util - simplify connections to Sympa

=head1 SYNOPSIS

=head1 DESCRIPTION

The Sympa core is under heavy development.  To be able to let plugins
work with different releases of Sympa, we add some abstractions.

=head1 CONSTANTS

=head2 :http

=head2 :time

=cut

use constant SECOND => 1;
use constant MINUTE => 60 * SECOND;
use constant HOUR   => 60 * MINUTE;
use constant DAY    => 24 * HOUR;
use constant MONTH  => 30 * DAY;

use constant
  { HTTP_OK     => 200
  , HTTP_BAD    => 400
  , HTTP_UNAUTH => 401
  , HTTP_INTERN => 500
  };


=head1 FUNCTIONS

All functions are exported by default, or with tag C<:function>.

=head2 Database

=head3 default_db

Returns an object which handles database queries.  This can be removed
when Sympa-core accesses databases via clean objects.

The object returned offers the following methods:

=over 4

=item method: prepared DBH, QUERY, BINDS

=item method: do DBH, QUERY, BINDS

=back

=cut

{  package SPU_db;

   sub db_prepared($$@)
   {   my $db = shift;
       SDM::do_prepared_query(@_);
   }

   sub db_do($$@)               # I want automatic quoting
   {   my $db  = shift;
       my $sth = $db->prepared(@_);
       undef;
   }
}

my $default_db;
sub default_db() { $default_db || (bless {}, 'SPU_db') }

=head2 Logging

=head3 trace_call PARAMETERS

=head3 log

=head3 fatal

=cut

sub log(@)   { goto &Log::do_log }
sub fatal(@) { goto &Log::fatal_err }

sub trace_call(@)          # simplification of method logging
{   my $sub = (caller[1])[3];
    local $" =  ',';
    @_ = (debug2 => "$sub(@_)");
    goto &Log::do_log;
}

1;
