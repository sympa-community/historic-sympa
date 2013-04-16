# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id: Database.pm 9105 2013-04-16 12:56:53Z rousse $

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

Sympa::Log::Database::Iterator - Iterator Database-oriented log functions

=head1 DESCRIPTION

This module provides database-oriented logging functions.

=cut

package Sympa::Log::Database::Iterator;

use strict;

use English qw(-no_match_vars);
use POSIX qw();

use Sympa::Datasource::SQL;
use Sympa::Log::Syslog;

my %action_type = (
	message => [ qw/
		arc_delete	arc_download	d_remove_arc	distribute
		DoCommand	DoFile		DoForward	DoMessage
		reject		rebuildarc	record_email	remind
		remove		send_me		send_mail	SendDigest
		sendMessage
	/ ],
	authentication => [ qw/
		choosepasswd	login			logout
		loginrequest	remindpasswd		sendpasswd
		ssologin	ssologin_succeses
	/ ],
	subscription => [ qw/
		add		del	ignoresub	signoff
		subscribe	subindex
	/ ],
	list_management => [ qw/
		admin		blacklist		close_list
		copy_template	create_list		edit_list
		edit_template	install_pending_list	purge_list
		remove_template	rename_list
	/ ],
	bounced => [ qw/
		get_bounce	resetbounce
	/ ],
	preferences => [ qw/
		change_email	editsubscriber	pref
		set		setpasswd	setpref
	/ ],
	shared => [ qw/
		change_email	creation_shared_file	d_admin
		d_change_access	d_control		d_copy_file
		d_copy_rec_dir	d_create_dir		d_delete
		d_describe	d_editfile		d_install_shared
		d_overwrite	d_properties		d_reject_shared
		d_rename	d_savefile		d_set_owner
		d_upload	d_unzip			d_unzip_shared_file
		d_read		install_file_hierarchy	new_d_read
		set_lang
	/ ],
);

=item Sympa::Log::Database::Iterator->new(%parameters)

Create a new L<Sympa::Log::Database::Iterator> object.

Parameters:

=over

=item C<source> => L<Sympa::Datasource::SQL>

=item C<robot> => FIXME

=item C<list> => FIXME

=item C<user_email> => FIXME

=item C<ip> => FIXME

=item C<date_from> => FIXME

=item C<date_to> => FIXME

=item C<type> => FIXME

=item C<target_type> => FIXME

=back

Return:

A new L<Sympa::Log::Database::Iterator> object, or I<undef> if something went wrong.

=cut

sub new {
	my ($class, %params) = @_;

	my $statement = sprintf "SELECT date_logs, robot_logs AS robot, list_logs AS list, action_logs AS action, parameters_logs AS parameters, target_email_logs AS target_email,msg_id_logs AS msg_id, status_logs AS status, error_type_logs AS error_type, user_email_logs AS user_email, client_logs AS client, daemon_logs AS daemon FROM logs_table WHERE robot_logs=%s ", $params{source}->quote($params{robot});

	#if a type of target and a target are specified
	if ($params{target_type} && $params{target_type} ne 'none') {
		if($params{target}) {
			$params{target_type} = lc ($params{target_type});
			$params{target} = lc ($params{target});
			$statement .= 'AND ' . $params{target_type} . '_logs = ' . $params{source}->quote($params{target}).' ';
		}
	}

	#if the search is between two date
	if ($params{date_from}) {
		my @tab_date_from = split(/\//,$params{date_from});
		my $date_from = POSIX::mktime(0,0,-1,$tab_date_from[0],$tab_date_from[1]-1,$tab_date_from[2]-1900);
		unless($params{date_to}) {
			my $date_from2 = POSIX::mktime(0,0,25,$tab_date_from[0],$tab_date_from[1]-1,$tab_date_from[2]-1900);
			$statement .= sprintf "AND date_logs BETWEEN '%s' AND '%s' ",$date_from, $date_from2;
		}
		if($params{date_to}) {
			my @tab_date_to = split(/\//,$params{date_to});
			my $date_to = POSIX::mktime(0,0,25,$tab_date_to[0],$tab_date_to[1]-1,$tab_date_to[2]-1900);

			$statement .= sprintf "AND date_logs BETWEEN '%s' AND '%s' ",$date_from, $date_to;
		}
	}

	#if the search is on a precise type
	if ($params{type}) {
		if($params{type} ne 'none' && $params{type} ne 'all_actions') {
			my $first = 'false';
			foreach my $type(@{$action_type{$params{type}}}) {
				if($first eq 'false') {
					#if it is the first action, put AND on the statement
					$statement .= sprintf "AND (logs_table.action_logs = '%s' ",$type;
					$first = 'true';
				} else {
					#else, put OR
					$statement .= sprintf "OR logs_table.action_logs = '%s' ",$type;
				}
			}
			$statement .= ')';
		}

	}

	#if the listmaster want to make a search by an IP adress.
	$statement .= sprintf "AND client_logs = '%s'",$params{ip};


	## Currently not used
	#if the search is on the actor of the action
	if ($params{user_email}) {
		$params{user_email} = lc ($params{user_email});
		$statement .= sprintf "AND user_email_logs = '%s' ",$params{user_email};
	}

	#if a list is specified -just for owner or above-
	if($params{list}) {
		$params{list} = lc ($params{list});
		$statement .= sprintf "AND list_logs = '%s' ",$params{list};
	}

	$statement .= sprintf "ORDER BY date_logs ";

	my $sth = $params{source}->get_query_handle($statement);
	unless($sth) {
		Sympa::Log::Syslog::do_log('err','Unable to retrieve logs entry from the database');
		return undef;
	}
	$sth->execute();

	my $self = {
		sth => $sth,
	};

	bless $self, $class;
	return $self;
}

=item $iterator->get_next()

Parameters:

None.

Return:

The next event, as an hashref, or I<undef> if there is no more event.

=cut

sub get_next {
	my ($self) = @_;

	my $event = $self->{sth}->fetchrow_hashref('NAME_lc');

	# We can't use the "AS date" directive in the SELECT statement because "date"
	# is a reserved keyword with Oracle
	$event->{date} = $event->{date_logs}
		if $event && $event->{date_logs};

	return $event;
}

=back

=cut

1;
