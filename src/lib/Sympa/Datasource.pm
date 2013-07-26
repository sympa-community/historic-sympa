# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 NAME

Sympa::Datasource - Abstract data source object

=head1 DESCRIPTION

This class implements a generic mechanism to populate a mailing list
subscribers from an external data source.

=cut

package Sympa::Datasource;

use strict;

use Sympa::Log::Syslog;

# Returns a unique ID for an include datasource
sub _get_datasource_id {
	my ($source, $other_source) = @_;
	Sympa::Log::Syslog::do_log('debug2',"Getting datasource id for source '%s'",$source);
	if (ref($source) && $source->isa('Sympa::Datasource')) {
		$source = $other_source;
	}

	if (ref ($source)) {
		## Ordering values so that order of keys in a hash don't mess the value comparison
		## Warning: Only the first level of the hash is ordered. Should a datasource
		## be described with a hash containing more than one level (a hash of hash) we should transform
		## the following algorithm into something that would be recursive. Unlikely it happens.
		my @orderedValues;
		foreach my $key (sort (keys %{$source})) {
			@orderedValues = (@orderedValues,$key,$source->{$key});
		}
		return substr(Digest::MD5::md5_hex(join('/', @orderedValues)), -8);
	} else {
		return substr(Digest::MD5::md5_hex($source), -8);
	}

}

=head1 INSTANCE METHODS

=over

=item $source->is_allowed_to_sync()

FIXME.

Parameters:

None.

=cut

sub is_allowed_to_sync {
	my ($self) = @_;

	my $ranges = $self->{'nosync_time_ranges'};
	$ranges =~ s/^\s+//;
	$ranges =~ s/\s+$//;
	my $rsre = Sympa::Tools::get_regexp('time_ranges');
	return 1 unless($ranges =~ /^$rsre$/);

	Sympa::Log::Syslog::do_log('debug', "Checking whether sync is allowed at current time");

	my (undef, $min, $hour) = localtime(time());
	my $now = 60 * int($hour) + int($min);

	foreach my $range (split(/\s+/, $ranges)) {
		next unless($range =~ /^([012]?[0-9])(?:\:([0-5][0-9]))?-([012]?[0-9])(?:\:([0-5][0-9]))?$/);
		my $start = 60 * int($1) + int($2);
		my $end = 60 * int($3) + int($4);
		$end += 24 * 60 if($end < $start);

		Sympa::Log::Syslog::do_log('debug', "Checking for range from ".sprintf('%02d', $start / 60)."h".sprintf('%02d', $start % 60)." to ".sprintf('%02d', ($end / 60) % 24)."h".sprintf('%02d', $end % 60));

		next if($start == $end);

		if($now >= $start && $now <= $end) {
			Sympa::Log::Syslog::do_log('debug', "Failed, sync not allowed.");
			return 0;
		}

		Sympa::Log::Syslog::do_log('debug', "Pass ...");
	}

	Sympa::Log::Syslog::do_log('debug', "Sync allowed");
	return 1;
}

=item $source->disconnect()

Parameters:

None.

Return value:

None.

=back

=cut

1;
