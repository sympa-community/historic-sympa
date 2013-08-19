# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

=encoding utf-8

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

=head1 INSTANCE METHODS

=over

=item $formatter->img_start($node)

Called foreach img element found.

=cut

sub img_start   {
	my($self,$node) = @_;
	my $alt = $node->attr('alt');
	$self->out(  defined($alt) ? sprintf(Sympa::Language::gettext("[ Image%s ]"), ": " . $alt) : sprintf(Sympa::Language::gettext("[Image%s]"),""));
}

=back

=cut

1;
