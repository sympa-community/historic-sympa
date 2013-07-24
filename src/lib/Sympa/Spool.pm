# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: SQL.pm 9637 2013-07-23 10:45:53Z rousse $

# Sympa - SYsteme de Multi-Postage Automatique
# Copyrigh (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
# Copyright (c) 1997,1998, 1999 Institut Pasteur & Christophe Wolfhugel
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Spool - Abstract spool object

=head1 DESCRIPTION

This class implements an abstract spool.

=cut

package Sympa::Spool;

use strict;

use Carp;

=head1 CLASS METHODS

=over

=item Sympa::Spool->new(%parameters)

Creates a new L<Sympa::Spool> object.

Parameters:

=over

=item C<name> => string

=item C<status> => C<bad> | C<ok>

=back

Return:

A new L<Sympa::Spool> object.

Throws an exception if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;
	Sympa::Log::Syslog::do_log('debug2', '(%s)', $params{name});

	croak "missing name parameter" unless $params{name};

	croak "invalid status parameter" if
		$params{status} &&
		$params{status} ne 'bad' &&
		$params{status} ne 'ok';

	my $self = {
		name   => $params{name},
		status => $params{status} || 'ok',
	};

	bless $self, $class;

	return $self;
}

=back

=cut

1;
