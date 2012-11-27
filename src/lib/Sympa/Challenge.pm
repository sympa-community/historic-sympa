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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 NAME

Sympa::Challenge - Email challenges functions

=head1 DESCRIPTION

This module provides email challenges functions.

=cut

package Sympa::Challenge;

use strict;
no strict "vars";

use CGI::Cookie;
use Digest::MD5;
use Time::Local;

use Sympa::Conf;
use Sympa::Log;
use Sympa::SDM;
use Sympa::Tools::Time;
use Sympa::Tools::Data;

# this structure is used to define which session attributes are stored in a dedicated database col where others are compiled in col 'data_session'
my %challenge_hard_attributes = ('id_challenge' => 1, 'date' => 1, 'robot'  => 1,'email' => 1, 'list' => 1);

=head1 FUNCTIONS

=head2 create($robot, $email, $context)

Create a challenge context and store it in challenge table.

=cut

sub create {
    my ($robot, $email, $context) = @_;

    &Sympa::Log::do_log('debug', '%s::new(%s, %s, %s)', __PACKAGE__, $challenge_id, $email, $robot);

    my $challenge={};
    
    unless ($robot) {
	&Sympa::Log::do_log('err', 'Missing robot parameter, cannot create challenge object') ;
	return undef;
    }
    
    unless ($email) {
	&Sympa::Log::do_log('err', 'Missing email parameter, cannot create challenge object') ;
	return undef;
    }

    $challenge->{'id_challenge'} = &get_random();
    $challenge->{'email'} = $email;
    $challenge->{'date'} = time;
    $challenge->{'robot'} = $robot; 
    $challenge->{'data'} = $context;
    return undef unless (&store($challenge));
    return $challenge->{'id_challenge'}     
}

sub load {

    my $id_challenge = shift;

    &Sympa::Log::do_log('debug', '%s::load(%s)', __PACKAGE__, $id_challenge);

    unless ($challenge_id) {
	&Sympa::Log::do_log('err', '%s::load() : internal error, Sympa::Session::load called with undef id_challenge', __PACKAGE__);
	return undef;
    }
    
    my $sth;

    unless($sth = &Sympa::SDM::do_query("SELECT id_challenge AS id_challenge, date_challenge AS 'date', remote_addr_challenge AS remote_addr, robot_challenge AS robot, email_challenge AS email, data_challenge AS data, hit_challenge AS hit, start_date_challenge AS start_date FROM challenge_table WHERE id_challenge = %s", $cookie)) {
	&Sympa::Log::do_log('err','Unable to retrieve challenge %s from database',$cookie);
	return undef;
    }

    my $challenge = $sth->fetchrow_hashref('NAME_lc');
    
    unless ($challenge) {
	return 'not_found';
    }
    my $challenge_datas;

    my %datas= &Sympa::Tools::Data::string_2_hash($challenge->{'data'});
    foreach my $key (keys %datas) {$challenge_datas->{$key} = $datas{$key};} 

    $challenge_datas->{'id_challenge'} = $challenge->{'id_challenge'};
    $challenge_datas->{'date'} = $challenge->{'date'};
    $challenge_datas->{'robot'} = $challenge->{'robot'};
    $challenge_datas->{'email'} = $challenge->{'email'};

    &Sympa::Log::do_log('debug3', '%s::load(): removing existing challenge del_statement = %s',__PACKAGE__,$del_statement);	
    unless(&Sympa::SDM::do_query("DELETE FROM challenge_table WHERE (id_challenge=%s)",$id_challenge)) {
	&Sympa::Log::do_log('err','Unable to delete challenge %s from database',$id_challenge);
	return undef;
    }

    return ('expired') if (time - $challenge_datas->{'date'} >= &Sympa::Tools::Time::duration_conv($Conf{'challenge_table_ttl'}));
    return ($challenge_datas);
}

sub store {

    my $challenge = shift;
    &Sympa::Log::do_log('debug', '%s::store()', __PACKAGE__);

    return undef unless ($challenge->{'id_challenge'});

    my %hash ;    
    foreach my $var (keys %$challenge ) {
	next if ($challenge_hard_attributes{$var});
	next unless ($var);
	$hash{$var} = $challenge->{$var};
    }
    my $data_string = &Sympa::Tools::Data::hash_2_string (\%hash);
    my $sth;

    unless(&Sympa::SDM::do_query("INSERT INTO challenge_table (id_challenge, date_challenge, robot_challenge, email_challenge, data_challenge) VALUES ('%s','%s','%s','%s','%s'')",$challenge->{'id_challenge'},$challenge->{'date'},$challenge->{'robot'},$challenge->{'email'},$data_string)) {
	&Sympa::Log::do_log('err','Unable to store challenge %s informations in database (robot: %s, user: %s)',$challenge->{'id_challenge'},$challenge->{'robot'},$challenge->{'email'});
	return undef;
    }
}

1;

