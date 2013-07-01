# DBManipulatorInformix.pm - This module contains the code specific to using a MySQL server.
#<!-- RCS Identication ; $Revision: 7016 $ --> 
#
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

package DBManipulatorInformix;

use strict;

use Carp;
use Log;

use DBManipulatorDefault;

our @ISA = qw(DBManipulatorDefault);

sub build_connect_string{
    my $self = shift;
    $self->{'connect_string'} = "DBI:Informix:".$self->{'db_name'}."@".$self->{'db_host'};
}

return 1;