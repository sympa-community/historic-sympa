# $Id$

=head1 NAME

Sympa::HTML::FormatText - HTML::FormatText extension

=head1 DESCRIPTION

This class implements a specialized HTML formatter, to allow
internationalisation of some strings.

=cut

package Sympa::HTML::FormatText;

use strict;

use base qw(HTML::FormatText);

use Sympa::Language;

sub img_start   {
  my($self,$node) = @_;
  my $alt = $node->attr('alt');
  $self->out(  defined($alt) ? sprintf(Sympa::Language::gettext("[ Image%s ]"), ": " . $alt) : sprintf(Sympa::Language::gettext("[Image%s]"),""));
}

1;
