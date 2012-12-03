# $Id$

package Sympa::HTML::FormatText;

# This is a subclass of the HTML::FormatText object. 
# This subclassing is done to allow internationalisation of some strings

our @ISA = qw(HTML::FormatText);
     
use Sympa::Language;
use strict;

sub img_start   {
  my($self,$node) = @_;
  my $alt = $node->attr('alt');
  $self->out(  defined($alt) ? sprintf(gettext("[ Image%s ]"), ": " . $alt) : sprintf(gettext("[Image%s]"),""));
}

1;
