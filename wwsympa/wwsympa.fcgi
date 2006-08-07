#!--PERL-- --PERLOPT--

# wwsympa.fcgi - This script provides the web interface to Sympa 
# RCS Identication ; $Revision$ ; $Date$ 
#
# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997-2003 Comite Reseau des Universites
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

## Copyright 1999 Comité Réseaux des Universités
## web interface to Sympa mailing lists manager
## Sympa: http://www.sympa.org/

## Authors :
##           Serge Aumont <sa AT cru.fr>
##           Olivier Salaün <os AT cru.fr>

use wwsympa;

#unless ( $wwsconf->{'exec_mode'} eq 'mod_perl' ) {
#    #Main loop for FastCgi or Cgi
#    while ($query = &new_loop()) {
#	&main_ops($query);
#    }
#}

