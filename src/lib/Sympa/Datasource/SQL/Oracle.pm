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
# along with this program; if not, write to the Free Softwarec
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Datasource::SQL::Oracle - Oracle data source object

=head1 DESCRIPTION

This class implements an Oracle data source.

=cut

package Sympa::Datasource::SQL::Oracle;

use strict;
use base qw(Sympa::Datasource::SQL);

use Carp;

use Sympa::Log::Syslog;

our %date_format = (
	'read' => {
		'Oracle' => '((to_number(to_char(%s,\'J\')) - to_number(to_char(to_date(\'01/01/1970\',\'dd/mm/yyyy\'), \'J\'))) * 86400) +to_number(to_char(%s,\'SSSSS\'))',
	},
	'write' => {
		'Oracle' => 'to_date(to_char(round(%s/86400) + to_number(to_char(to_date(\'01/01/1970\',\'dd/mm/yyyy\'), \'J\'))) || \':\' ||to_char(mod(%s,86400)), \'J:SSSSS\')',
	}
);

sub new {
	my ($class, %params) = @_;

	croak "missing db_host parameter" unless $params{db_host};
	croak "missing db_user parameter" unless $params{db_user};

	return $class->SUPER::new(%params, db_type => 'oracle');
}

sub connect {
	my ($self, %params) = @_;

	my $result = $self->SUPER::connect(%params);
	return unless $result;
	
	$ENV{'NLS_LANG'} = 'UTF8';

	return 1;
}

sub get_connect_string{
	my ($self) = @_;

	my $string = "DBI:Oracle:";
	if ($self->{'db_host'} && $self->{'db_name'}) {
		$string .= "host=$self->{'db_host'};sid=$self->{'db_name'}";
	}

	return $string;
}

sub get_substring_clause {
	my ($self, %params) = @_;

	return sprintf
		"substr(%s,instr(%s,'%s')+1)",
		$params{'source_field'},
		$params{'source_field'},
		$params{'separator'};
}

sub get_limit_clause {
	my ($self, %params) = @_;

	return "";
}

sub get_formatted_date {
	my ($self, %params) = @_;

	my $mode = lc($params{'mode'});
	if ($mode eq 'read') {
		return sprintf 'UNIX_TIMESTAMP(%s)',$params{'target'};
	} elsif ($mode eq 'write') {
		return sprintf 'FROM_UNIXTIME(%d)',$params{'target'};
	} else {
		Sympa::Log::Syslog::do_log(
			'err',
			"Unknown date format mode %s",
			$params{'mode'}
		);
		return undef;
	}
}

sub get_tables {
	my ($self) = @_;

	Sympa::Log::Syslog::do_log(
		'debug',
		'Getting tables list',
	);

	my $query = "SELECT table_name FROM user_tables";
	my $sth = $self->{dbh}->prepare($query);
	unless ($sth) {
		Sympa::Log::Syslog::do_log(
			'err',
			'Unable to get tables list',
		);
		return undef;
	}
	$sth->execute();

	my @tables;
	while (my $row = $sth->fetchrow_arrayref()) {
		push @tables, lc($row->[0]);
	}

	return @tables;
}

sub _get_native_type {
	my ($self, $type) = @_;

	return 'number'        if $type =~ /^int/;
	return 'number'        if $type =~ /^bigint/;
	return 'number'        if $type =~ /^smallint/;
	return "varchar2($1)"  if $type =~ /^varchar\((\d+)\)/;
	return "varchar2(20)"  if $type =~ /^enum/;
	return "varchar2(500)" if $type =~ /^text/;
	return 'long'          if $type =~ /^longtext/;
	return 'date'          if $type =~ /^datetime/;
	return $type;
}

1;
