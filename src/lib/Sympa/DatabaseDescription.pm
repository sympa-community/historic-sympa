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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::DatabaseDescription

=head1 DESCRIPTION

=cut

package Sympa::DatabaseDescription;

use strict;

## List the required INDEXES
##   1st key is the concerned table
##   2nd key is the index name
##   the table lists the field on which the index applies
our %indexes = (
	'admin_table'      => {'admin_user_index'      => ['user_admin']},
	'subscriber_table' => {'subscriber_user_index' => ['user_subscriber']},
	'stat_table'       => {'stats_user_index'      => ['email_stat']}
);

# table indexes that can be removed during upgrade process
our @former_indexes = (
	'user_subscriber',
	'list_subscriber',
	'subscriber_idx',
	'admin_idx',
	'netidmap_idx',
	'user_admin',
	'list_admin',
	'role_admin',
	'admin_table_index',
	'logs_table_index',
	'netidmap_table_index',
	'subscriber_table_index',
	'user_index'
);

1;
