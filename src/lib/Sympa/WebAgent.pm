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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::WebAgent - LWP::UserAgent extension

=head1 DESCRIPTION

This class implements a specialized LWP user agent.

=cut

package Sympa::WebAgent;

use strict "vars";
use base qw(LWP::UserAgent);

## Good documentation : http://articles.mongueurs.net/magazines/linuxmag57.html

my ($web_user, $web_passwd);

sub get_basic_credentials {
    my ( $self, $realm, $uri ) = @_;

    return ( $web_user, $web_passwd );
}

sub set_basic_credentials {
    ($web_user, $web_passwd ) = @_;
}

1;
