# $Id$

package Sympa::HTML::FormatText;

# This is a subclass of the HTML::FormatText object. 
# This subclassing is done to allow internationalisation of some strings
     
use strict;

use Sympa::Language;

our @ISA = qw(HTML::FormatText);

sub img_start   {
  my($self,$node) = @_;
  my $alt = $node->attr('alt');
  $self->out(  defined($alt) ? sprintf(Sympa::Language::gettext("[ Image%s ]"), ": " . $alt) : sprintf(Sympa::Language::gettext("[Image%s]"),""));
}

1;
