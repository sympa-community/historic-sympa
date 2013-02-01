# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:wrap:textwidth=78
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

Sympa::WWSympa - WWSympa functions

=head1 DESCRIPTION

This module provides functions for wwsympa.

=cut

package Sympa::WWSympa;

use English qw(-no_match_vars);

use Sympa::Configuration;
use Sympa::Constants;
use Sympa::Log;
use Sympa::List;
use Sympa::Report;
use Sympa::Tools::Password;

%reception_mode = ('mail' => {'gettext_id' => 'standard (direct reception)'},
		   'digest' => {'gettext_id' => 'digest MIME format'},
		   'digestplain' => {'gettext_id' => 'digest plain text format'},
		   'summary' => {'gettext_id' => 'summary mode'},
		   'notice' => {'gettext_id' => 'notice mode'},
		   'txt' => {'gettext_id' => 'text-only mode'},
		   'html'=> {'gettext_id' => 'html-only mode'},
		   'urlize' => {'gettext_id' => 'urlize mode'},
		   'nomail' => {'gettext_id' => 'no mail (useful for vacations)'},
		   'not_me' => {'gettext_id' => 'you do not receive your own posts'}
		   );

## Cookie expiration periods with corresponding entry in NLS
%cookie_period = (0     => {'gettext_id' => "session"},
		  10    => {'gettext_id' => "10 minutes"},
		  30    => {'gettext_id' => "30 minutes"},
		  60    => {'gettext_id' => "1 hour"},
		  360   => {'gettext_id' => "6 hours"},
		  1440  => {'gettext_id' => "1 day"},
		  10800 => {'gettext_id' => "1 week"},
		  43200 => {'gettext_id' => "30 days"});

%visibility_mode = ('noconceal' => {'gettext_id' => "listed in the list review page"},
		    'conceal' => {'gettext_id' => "concealed"}
		    );

## Filenames with corresponding entry in NLS set 15
%filenames = ('welcome.tt2'             => {'gettext_id' => "welcome message"},
	      'bye.tt2'                 => {'gettext_id' => "unsubscribe message"},
	      'removed.tt2'             => {'gettext_id' => "deletion message"},
	      'message.footer'          => {'gettext_id' => "message footer"},
	      'message.header'          => {'gettext_id' => "message header"},
	      'remind.tt2'              => {'gettext_id' => "remind message"},
	      'reject.tt2'              => {'gettext_id' => "editor rejection message"},
	      'invite.tt2'              => {'gettext_id' => "subscribing invitation message"},
	      'helpfile.tt2'            => {'gettext_id' => "help file"},
	      'lists.tt2'               => {'gettext_id' => "directory of lists"},
	      'global_remind.tt2'       => {'gettext_id' => "global remind message"},
	      'summary.tt2'             => {'gettext_id' => "summary message"},
	      'info'                    => {'gettext_id' => "list description"},
	      'homepage'                => {'gettext_id' => "list homepage"},
	      'create_list_request.tt2' => {'gettext_id' => "list creation request message"},
	      'list_created.tt2'        => {'gettext_id' => "list creation notification message"},
	      'your_infected_msg.tt2'   => {'gettext_id' => "virus infection message"},
	      'list_aliases.tt2'        => {'gettext_id' => "list aliases template"}
	      );

## Defined in RFC 1893
%bounce_status = ('1.0' => 'Other address status',
		  '1.1' => 'Bad destination mailbox address',
		  '1.2' => 'Bad destination system address',
		  '1.3' => 'Bad destination mailbox address syntax',
		  '1.4' => 'Destination mailbox address ambiguous',
		  '1.5' => 'Destination mailbox address valid',
		  '1.6' => 'Mailbox has moved',
		  '1.7' => 'Bad sender\'s mailbox address syntax',
		  '1.8' => 'Bad sender\'s system address',
		  '2.0' => 'Other or undefined mailbox status',
		  '2.1' => 'Mailbox disabled, not accepting messages',
		  '2.2' => 'Mailbox full',
		  '2.3' => 'Message length exceeds administrative limit',
		  '2.4' => 'Mailing list expansion problem',
		  '3.0' => 'Other or undefined mail system status',
		  '3.1' => 'Mail system full',
		  '3.2' => 'System not accepting network messages',
		  '3.3' => 'System not capable of selected features',
		  '3.4' => 'Message too big for system',
		  '4.0' => 'Other or undefined network or routing status',
		  '4.1' => 'No answer from host',
		  '4.2' => 'Bad connection',
		  '4.3' => 'Routing server failure',
		  '4.4' => 'Unable to route',
		  '4.5' => 'Network congestion',
		  '4.6' => 'Routing loop detected',
		  '4.7' => 'Delivery time expired',
		  '5.0' => 'Other or undefined protocol status',
		  '5.1' => 'Invalid command',
		  '5.2' => 'Syntax error',
		  '5.3' => 'Too many recipients',
		  '5.4' => 'Invalid command arguments',
		  '5.5' => 'Wrong protocol version',
		  '6.0' => 'Other or undefined media error',
		  '6.1' => 'Media not supported',
		  '6.2' => 'Conversion required and prohibited',
		  '6.3' => 'Conversion required but not supported',
		  '6.4' => 'Conversion with loss performed',
		  '6.5' => 'Conversion failed',
		  '7.0' => 'Other or undefined security status',
		  '7.1' => 'Delivery not authorized, message refused',
		  '7.2' => 'Mailing list expansion prohibited',
		  '7.3' => 'Security conversion required but not possible',
		  '7.4' => 'Security features not supported',
		  '7.5' => 'Cryptographic failure',
		  '7.6' => 'Cryptographic algorithm not supported',
		  '7.7' => 'Message integrity failure');



## if Crypt::CipherSaber installed store the cipher object
my $cipher;

## Load WWSympa configuration file
sub load_config {
    my ($file) = @_;

    ## Old params
    my %old_param = ('alias_manager' => 'No more used, using '.$Sympa::Configuration::Conf{'alias_manager'},
		     'wws_path' => 'No more used',
		     'icons_url' => 'No more used. Using static_content/icons instead.',
		     'robots' => 'Not used anymore. Robots are fully described in their respective robot.conf file.',
		     );

    my %default_conf = ();

    ## Valid params
    foreach my $key (keys %Sympa::Configuration::params) {
	if (defined $Sympa::Configuration::params{$key}{'file'} && $Sympa::Configuration::params{$key}{'file'} eq 'wwsympa.conf') {
	    $default_conf{$key} = $Sympa::Configuration::params{$key}{'default'};
	}
    }

    my $conf = \%default_conf;

    unless (open (FILE, $file)) {
	Sympa::Log::do_log('err',"unable to open $file");
	return undef;
    }

    while (<FILE>) {
	next if /^\s*\#/;

	if (/^\s*(\S+)\s+(.+)$/i) {
	    my ($k, $v) = ($1, $2);
	    $v =~ s/\s*$//;
	    if (defined ($conf->{$k})) {
		$conf->{$k} = $v;
	    }elsif (defined $old_param{$k}) {
		Sympa::Log::do_log('err',"Parameter %s in %s no more supported : %s", $k, $file, $old_param{$k});
	    }else {
		Sympa::Log::do_log('err',"Unknown parameter %s in %s", $k, $file);
	    }
	}
	next;
    }

    close FILE;

    ## Check binaries and directories
    if ($conf->{'arc_path'} && (! -d $conf->{'arc_path'})) {
	Sympa::Log::do_log('err',"No web archives directory: %s\n", $conf->{'arc_path'});
    }

    if ($conf->{'bounce_path'} && (! -d $conf->{'bounce_path'})) {
	Sympa::Log::do_log('err',"Missing directory '%s' (defined by 'bounce_path' parameter)", $conf->{'bounce_path'});
    }

    if ($conf->{'mhonarc'} && (! -x $conf->{'mhonarc'})) {
	Sympa::Log::do_log('err',"MHonArc is not installed or %s is not executable.", $conf->{'mhonarc'});
    }

    return $conf;
}

sub init_passwd {
    my ($email, $data) = @_;

    my ($passwd, $user);

    if (Sympa::List::is_global_user($email)) {
	$user = Sympa::List::get_global_user($email);

	$passwd = $user->{'password'};

	unless ($passwd) {
	    $passwd = Sympa::Tools::Password::new_passwd();

	    unless ( Sympa::List::update_global_user($email,
					   {'password' => $passwd,
					    'lang' => $user->{'lang'} || $data->{'lang'}} )) {
		Sympa::Report::reject_report_web('intern','update_user_db_failed',{'user'=>$email},'','',$email,$robot);
		Sympa::Log::do_log('info','update failed');
		return undef;
	    }
	}
    }else {
	$passwd = Sympa::Tools::Password::new_passwd();
	unless ( Sympa::List::add_global_user({'email' => $email,
				     'password' => $passwd,
				     'lang' => $data->{'lang'},
				     'gecos' => $data->{'gecos'}})) {
	    Sympa::Report::reject_report_web('intern','add_user_db_failed',{'user'=>$email},'','',$email,$robot);
	    Sympa::Log::do_log('info','add failed');
	    return undef;
	}
    }

    return 1;
}

sub get_my_url {


    my $return_url;

    ## Mod_ssl sets SSL_PROTOCOL ; apache-ssl sets SSL_PROTOCOL_VERSION
    if ($ENV{'HTTPS'} eq 'on') {
	$return_url = 'https';
    }else{
	$return_url = 'http';
    }

    $return_url .= '://'.&main::get_header_field('HTTP_HOST');
    $return_url .= ':'.$ENV{'SERVER_PORT'} unless (($ENV{'SERVER_PORT'} eq '80')||($ENV{'SERVER_PORT'} eq '443'));
    $return_url .= $ENV{'REQUEST_URI'};
    return ($return_url);
}

# Uploade source file to the destination on the server
sub upload_file_to_server {
    my ($params) = @_;
    Sympa::Log::do_log('debug',"Uploading file from field %s to destination %s",$params->{'file_field'},$params->{'destination'});

    my $fh;
    unless ($fh = $params->{'query'}->upload($params->{'file_field'})) {
	Sympa::Log::do_log('debug',"Cannot upload file from field $params->{'file_field'}");
	return undef;
    }

    unless (open FILE, ">:bytes", $params->{'destination'}) {
	Sympa::Log::do_log('debug',"Cannot open file $params->{'destination'} : $ERRNO");
	return undef;
    }
    while (<$fh>) {
	print FILE;
    }
    close FILE;
    return 1;
}

1;
