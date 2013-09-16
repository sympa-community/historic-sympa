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

Sympa::Tools - Generic functions

=head1 DESCRIPTION

This module provides various generic functions.

=cut

package Sympa::Tools;

use strict;

use Carp qw(croak);
use Digest::MD5;
use Encode::Guess; ## Useful when encoding should be guessed
use English;
use File::Copy::Recursive;
use File::Find;
use File::Temp;
use HTML::StripScripts::Parser;
use MIME::EncWords;
use MIME::Lite::HTML;
use Sys::Hostname;
use Text::LineFold;

use Sympa::Language qw(gettext_strftime);
use Sympa::Tools::File;

my $separator="------- CUT --- CUT --- CUT --- CUT --- CUT --- CUT --- CUT -------";

## Regexps for list params
## Caution : if this regexp changes (more/less parenthesis), then regexp using it should
## also be changed
my $time_regexp = '[012]?[0-9](?:\:[0-5][0-9])?';
my $time_range_regexp = $time_regexp.'-'.$time_regexp;
my %regexp = (
	'email'                   => '([\w\-_./+=\'&]+|".*")@[\w\-]+(\.[\w\-]+)+',
	'family_name'             => '[a-z0-9][a-z0-9\-.+_]*',
	'template_name'           => '[a-zA-Z0-9][a-zA-Z0-9\-.+_\s]*', ## Allow \s
	'host'                    => '[\w.\-]+',
	'multiple_host_with_port' => '[\w.\-]+(:\d+)?(,[\w.\-]+(:\d+)?)*',
	'listname'                => '[a-z0-9][a-z0-9\-.+_]{0,49}',
	'sql_query'               => '(SELECT|select).*',
	'scenario'                => '[\w,.\-]+',
	'task'                    => '\w+',
	'datasource'              => '[\w-]+',
	'uid'                     => '[\w\-.+]+',
	'time'                    => $time_regexp,
	'time_range'              => $time_range_regexp,
	'time_ranges'             => $time_range_regexp.'(?:\s+'.$time_range_regexp.')*',
	're'                      => '(?i)(?:AW|(?:\xD0\x9D|\xD0\xBD)(?:\xD0\x90|\xD0\xB0)|Re(?:\^\d+|\*\d+|\*\*\d+|\[\d+\])?|Rif|SV|VS)\s*:',
);

## Sets owner and/or access rights on a file.
sub set_file_rights {
	my %param = @_;
	my ($uid, $gid);

	if ($param{'user'}) {
		unless ($uid = (getpwnam($param{'user'}))[2]) {
			Sympa::Log::Syslog::do_log('err', "User %s can't be found in passwd file",
				$param{'user'});
			return undef;
		}
	} else {
		# A value of -1 is interpreted by most systems to leave that value
		# unchanged.
		$uid = -1;
	}
	if ($param{'group'}) {
		unless ($gid = (getgrnam($param{'group'}))[2]) {
			Sympa::Log::Syslog::do_log('err', "Group %s can't be found", $param{'group'});
			return undef;
		}
	} else {
		# A value of -1 is interpreted by most systems to leave that value
		# unchanged.
		$gid = -1;
	}
	unless (chown($uid, $gid, $param{'file'})) {
		Sympa::Log::Syslog::do_log('err', "Can't give ownership of file %s to %s.%s: %s",
			$param{'file'}, $param{'user'}, $param{'group'}, "$!");
		return undef;
	}
	if ($param{'mode'}) {
		unless (chmod($param{'mode'}, $param{'file'})) {
			Sympa::Log::Syslog::do_log('err', "Can't change rights of file %s to %o: %s",
				$param{'file'}, $param{'mode'}, "$!");
			return undef;
		}
	}
	return 1;
}

## Returns an HTML::StripScripts::Parser object built with  the parameters provided as arguments.
sub _create_xss_parser {
	my %parameters = @_;
	my $robot = $parameters{'robot'};
	Sympa::Log::Syslog::do_log('debug3', '(%s)', $robot);

	my $http_host_re = $robot->http_host;
	$http_host_re =~ s/([^\s\w\x80-\xFF])/\\$1/g;
	my $hss = HTML::StripScripts::Parser->new({ Context => 'Document',
			AllowSrc        => 1,
			Rules => {
				'*' => {
					src => qr{^http://$http_host_re},
				},
			},
		});
	return $hss;
}

=head1 FUNCTIONS

=over

=item pictures_filename(%parameters)

Return the type of a pictures according to the user.

Parameters:

=over

=item C<email> => FIXME

=item C<list> => FIXME

=item C<path> => FIXME

=back

=cut

# OBSOLETED: use $list->find_picture_filenames().
sub pictures_filename {
	my %parameters = @_;
	my $email = $parameters{'email'};
	my $list = $parameters{'list'};

	my $ret = $list->find_picture_filenames($email);
	return $ret;
}

=item make_pictures_url(%parameters)

Creation of pictures url.

Parameters:

=over

=item C<url> => FIXME

=item C<email> => FIXME

=item C<list> => FIXME

=item C<path> => FIXME

=back

=cut

# OBSOLETED: Use $list->find_picture_url().
sub make_pictures_url {
	my %parameters = @_;
	my $email = $parameters{'email'};
	my $list = $parameters{'list'};

	my $ret = $list->find_picture_url($email);
	return $ret;
}

=item sanitize_html(%parameters)

Returns sanitized version (using StripScripts) of the string provided as
argument.

Parameters:

=over

=item C<string> => FIXME

=item C<robot> => FIXME

=item C<host> => FIXME

=back

=cut

sub sanitize_html {
	my %parameters = @_;
	my $robot = $parameters{'robot'};
	Sympa::Log::Syslog::do_log('debug3', '(string=%s, robot=%s)',
		$parameters{'string'}, $robot);

	unless (defined $parameters{'string'}) {
		Sympa::Log::Syslog::do_log('err',"No string provided.");
		return undef;
	}

	my $hss = _create_xss_parser('robot' => $robot);
	unless (defined $hss) {
		Sympa::Log::Syslog::do_log('err',"Can't create StripScript parser.");
		return undef;
	}
	my $string = $hss -> filter_html($parameters{'string'});
	return $string;
}

=item sanitize_html_file(%parameters)

Returns sanitized version (using StripScripts) of the content of the file whose
path is provided as argument.

Parameters:

=over

=item C<file> => FIXME

=item C<robot> => FIXME

=item C<host> => FIXME

=back

=cut

sub sanitize_html_file {
	my %parameters = @_;
	my $robot = $parameters{'robot'};
	Sympa::Log::Syslog::do_log('debug3', '(file=%s, robot=%s)',
		$parameters{'file'}, $robot);

	unless (defined $parameters{'file'}) {
		Sympa::Log::Syslog::do_log('err',"No path to file provided.");
		return undef;
	}

	my $hss = _create_xss_parser('robot' => $robot);
	unless (defined $hss) {
		Sympa::Log::Syslog::do_log('err',"Can't create StripScript parser.");
		return undef;
	}
	$hss -> parse_file($parameters{'file'});
	return $hss -> filtered_document;
}

=item sanitize_var(%parameters)

Sanitize all values in the hash $var, starting from $level

Parameters:

=over

=item C<var> => FIXME

=item C<level> => FIXME

=item C<robot> => FIXME

=item C<htmlAllowedParam> => FIXME

=item C<htmlToFilter> => FIXME

=back

=cut

sub sanitize_var {
	my %parameters = @_;
	Sympa::Log::Syslog::do_log('debug3','(%s,%s,%s)',$parameters{'var'},$parameters{'level'},$parameters{'robot'});
	unless (defined $parameters{'var'}){
		Sympa::Log::Syslog::do_log('err','Missing var to sanitize.');
		return undef;
	}
	unless (defined $parameters{'htmlAllowedParam'} && $parameters{'htmlToFilter'}){
		Sympa::Log::Syslog::do_log('err','Missing var *** %s *** %s *** to ignore.',$parameters{'htmlAllowedParam'},$parameters{'htmlToFilter'});
		return undef;
	}
	my $level = $parameters{'level'};
	$level |= 0;

	if(ref($parameters{'var'})) {
		if(ref($parameters{'var'}) eq 'ARRAY') {
			foreach my $index (0..$#{$parameters{'var'}}) {
				if ((ref($parameters{'var'}->[$index]) eq 'ARRAY') || (ref($parameters{'var'}->[$index]) eq 'HASH')) {
					sanitize_var('var' => $parameters{'var'}->[$index],
						'level' => $level+1,
						'robot' => $parameters{'robot'},
						'htmlAllowedParam' => $parameters{'htmlAllowedParam'},
						'htmlToFilter' => $parameters{'htmlToFilter'},
					);
				} elsif (ref($parameters{'var'}->[$index])) {
					$parameters{'var'}->[$index] =
					ref($parameters{'var'}->[$index]);
				} elsif (defined $parameters{'var'}->[$index]) {
					$parameters{'var'}->[$index] =
					escape_html($parameters{'var'}->[$index]);
				}
			}
		}
		elsif(ref($parameters{'var'}) eq 'HASH') {
			foreach my $key (keys %{$parameters{'var'}}) {
				if ((ref($parameters{'var'}->{$key}) eq 'ARRAY') || (ref($parameters{'var'}->{$key}) eq 'HASH')) {
					&sanitize_var('var' => $parameters{'var'}->{$key},
						'level' => $level+1,
						'robot' => $parameters{'robot'},
						'htmlAllowedParam' => $parameters{'htmlAllowedParam'},
						'htmlToFilter' => $parameters{'htmlToFilter'},
					);
				} elsif (ref($parameters{'var'}->{$key})) {
					$parameters{'var'}->{$key} =
					ref($parameters{'var'}->{$key});
				} elsif (defined $parameters{'var'}->{$key}) {
					unless ($parameters{'htmlAllowedParam'}{$key} or
						$parameters{'htmlToFilter'}{$key}) {
						$parameters{'var'}->{$key} =
						escape_html($parameters{'var'}->{$key});
					}
					if ($parameters{'htmlToFilter'}{$key}) {
						$parameters{'var'}->{$key} = sanitize_html(
							'string' => $parameters{'var'}->{$key},
							'robot' => $parameters{'robot'}
						);
					}
				}
			}
		}
	}
	else {
		Sympa::Log::Syslog::do_log('err','Variable is neither a hash nor an array.');
		return undef;
	}
	return 1;
}

=item by_date()

Sort subroutine to order files in sympa spool by date

=cut

sub by_date {
	my @a_tokens = split /\./, $a;
	my @b_tokens = split /\./, $b;

	## File format : list@dom.date.pid
	my $a_time = $a_tokens[$#a_tokens -1];
	my $b_time = $b_tokens[$#b_tokens -1];

	return $a_time <=> $b_time;

}

=item safefork()

Safefork does several tries before it gives up. Do 3 trials and wait 10 seconds
* $i between each. Exit with a fatal error is fork failed after all tests have
been exhausted.

=cut

sub safefork {
	my($i, $pid);

	my $err;
	for ($i = 1; $i < 4; $i++) {
		my($pid) = fork;
		return $pid if (defined($pid));

		$err = "$!";
		Sympa::Log::Syslog::do_log('warn', 'Cannot create new process in safefork: %s', $err);
		## FIXME:should send a mail to the listmaster
		sleep(10 * $i);
	}
	croak sprintf('Exiting because cannot create new process in safefork: %s',
		$err);
	## No return.
}

=item checkcommand($msg, $sender, $robot, $regexp)

Checks for no command in the body of the message. If there are some command in
it, it return true and send a message to $sender.

Parameters:

=over

=item L<MIME::Entity>

The message to check.

=item string

The sender

=item string

The robot

=item string

The regexp

=back

Return value:

true if there are some command in $msg, false otherwise.

=cut

sub checkcommand {
	my($msg, $sender, $robot) = @_;

	my($avoid, $i);

	## Check for commands in the subject.
	my $subject = $msg->head->get('Subject');
	chomp $subject if $subject;

	Sympa::Log::Syslog::do_log('debug3', 'tools::checkcommand(msg->head->get(subject): %s,%s)', $subject, $sender);

	if ($subject) {
		if (Site->misaddressed_commands_regexp) {
			my $misaddressed_commands_regexp =
			Site->misaddressed_commands_regexp;
			if ($subject =~ /^$misaddressed_commands_regexp\b/im) {
				return 1;
			}
		}
	}

	return 0 if ($#{$msg->body} >= 5);  ## More than 5 lines in the text.

	foreach $i (@{$msg->body}) {
		if (Site->misaddressed_commands_regexp) {
			my $misaddressed_commands_regexp =
			Site->misaddressed_commands_regexp;
			if ($i =~ /^$misaddressed_commands_regexp\b/im) {
				return 1;
			}
		}

		## Control is only applied to first non-blank line
		last unless $i =~ /^\s*$/;
	}
	return 0;
}

=item load_edit_list_conf($robot, $list, $basedir)

Return a hash from the edit_list_conf file

Parameters:

=over

=item FIXME

=item FIXME

=item FIXME

=back

=cut

## NOTE: this might be moved to List only where this is used.
sub load_edit_list_conf {
	Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
	my $self  = shift;
	my $robot = $self->robot;

	my $file;
	my $conf;

	return undef
	unless ($file = $self->get_etc_filename('edit_list.conf'));

	my $fh;
	unless (open $fh, '<', $file) {
		Sympa::Log::Syslog::do_log('info', 'Unable to open config file %s', $file);
		return undef;
	}

	my $error_in_conf;
	my $roles_regexp =
	'listmaster|privileged_owner|owner|editor|subscriber|default';
	while (<$fh>) {
		next if /^\s*(\#.*|\s*)$/;

		if (/^\s*(\S+)\s+(($roles_regexp)\s*(,\s*($roles_regexp))*)\s+(read|write|hidden)\s*$/i
		) {
			my ($param, $role, $priv) = ($1, $2, $6);
			my @roles = split /,/, $role;
			foreach my $r (@roles) {
				$r =~ s/^\s*(\S+)\s*$/$1/;
				if ($r eq 'default') {
					$error_in_conf = 1;
					Sympa::Log::Syslog::do_log('notice', '"default" is no more recognised');
					foreach
					my $set ('owner', 'privileged_owner', 'listmaster') {
						$conf->{$param}{$set} = $priv;
					}
					next;
				}
				$conf->{$param}{$r} = $priv;
			}
		} else {
			Sympa::Log::Syslog::do_log('info', 'unknown parameter in %s  (Ignored) %s',
				$file, $_);
			next;
		}
	}

	if ($error_in_conf) {
		$robot->send_notify_to_listmaster('edit_list_error', $file);
	}

	close $fh;
	return $conf;
}


=item load_create_list_conf($robot, $basedir)

Return a hash from the create_list_conf file

Parameters:

=over

=item FIXME

=item FIXME

=back

=cut

## NOTE: This might be moved to WWSympa along with get_list_list_tpl().
sub load_create_list_conf {
	my $robot = Robot::clean_robot(shift);

	my $file;
	my $conf ;

	$file = $robot->get_etc_filename('create_list.conf');
	unless ($file) {
		Sympa::Log::Syslog::do_log('info', 'unable to read %s', Sympa::Constants::DEFAULTDIR . '/create_list.conf');
		return undef;
	}

	unless (open (FILE, $file)) {
		Sympa::Log::Syslog::do_log('info','Unable to open config file %s', $file);
		return undef;
	}

	while (<FILE>) {
		next if /^\s*(\#.*|\s*)$/;

		if (/^\s*(\S+)\s+(read|hidden)\s*$/i) {
			$conf->{$1} = lc($2);
		}else{
			Sympa::Log::Syslog::do_log ('info', 'unknown parameter in %s  (Ignored) %s',
				$file, $_);
			next;
		}
	}

	close FILE;
	return $conf;
}

=item get_list_list_tpl($robot, $directory)

FIXME.

=cut

## NOTE: This might be moved to WWSympa along with load_create_list_conf().
sub get_list_list_tpl {
	my $robot = Robot::clean_robot(shift);

	my $list_conf;
	my $list_templates ;
	unless ($list_conf = &load_create_list_conf($robot)) {
		return undef;
	}

	foreach my $dir (
		reverse @{$robot->get_etc_include_path('create_list_templates')}
	) {
		if (opendir(DIR, $dir)) {
			foreach my $template ( sort grep (!/^\./,readdir(DIR))) {

				my $status = $list_conf->{$template} || $list_conf->{'default'};

				next if ($status eq 'hidden') ;

				$list_templates->{$template}{'path'} = $dir;

				my $locale = Language::Lang2Locale_old(Language::GetLang());
				## FIXME: lang should be used instead of "locale".
				## Look for a comment.tt2 in the appropriate locale first
				if (-r $dir.'/'.$template.'/'.$locale.'/comment.tt2') {
					$list_templates->{$template}{'comment'} =
					$template.'/'.$locale.'/comment.tt2';
				}elsif (-r $dir.'/'.$template.'/comment.tt2') {
					$list_templates->{$template}{'comment'} =
					$template.'/comment.tt2';
				}
			}
			closedir(DIR);
		}
	}

	return ($list_templates);
}

=item get_templates_list($type, $robot, $list, $options, $basedir)

FIXME.

=cut

sub get_templates_list {

	my $type = shift;
	my $robot = shift;
	my $list = shift;
	my $options = shift;

	my $listdir;

	Sympa::Log::Syslog::do_log('debug', "get_templates_list ($type, $robot, $list)");
	unless (($type eq 'web')||($type eq 'mail')) {
		Sympa::Log::Syslog::do_log('info', 'get_templates_list () : internal error incorrect parameter');
	}

	my $distrib_dir = Sympa::Constants::DEFAULTDIR . '/'.$type.'_tt2';
	my $site_dir = Site->etc.'/'.$type.'_tt2';
	my $robot_dir = Site->etc.'/'.$robot.'/'.$type.'_tt2';

	my @try;

	## The 'ignore_global' option allows to look for files at list level only
	unless ($options->{'ignore_global'}) {
		push @try, $distrib_dir;
		push @try, $site_dir;
		push @try, $robot_dir;
	}    

	if (defined $list) {
		$listdir = $list->dir.'/'.$type.'_tt2';	
		push @try, $listdir;
	}

	my $i = 0 ;
	my $tpl;

	foreach my $dir (@try) {
		next unless opendir (DIR, $dir);
		foreach my $file (grep (!/^\./, readdir(DIR))) {
			## Subdirectory for a lang
			if (-d $dir.'/'.$file) {
				my $lang_dir = $file;
				my $lang = Sympa::Language::CanonicLang($lang_dir);
				next unless $lang;
				next unless opendir (LANGDIR, $dir . '/' . $lang_dir);

				foreach my $file (grep (!/^\./, readdir(LANGDIR))) {
					next unless $file =~ /\.tt2$/;
					if ($dir eq $distrib_dir) {
						$tpl->{$file}{'distrib'}{$lang} =
						$dir . '/' . $lang_dir . '/' . $file;
					}
					if ($dir eq $site_dir) {
						$tpl->{$file}{'site'}{$lang} =
						$dir . '/' . $lang_dir . '/' . $file;
					}
					if ($dir eq $robot_dir) {
						$tpl->{$file}{'robot'}{$lang} =
						$dir . '/' . $lang_dir . '/' . $file;
					}
					if ($dir eq $listdir) {
						$tpl->{$file}{'list'}{$lang} =
						$dir . '/' . $lang_dir . '/' . $file;
					}
				}
				closedir LANGDIR;

			}else {
				next unless ($file =~ /\.tt2$/);
				if ($dir eq $distrib_dir) {
					$tpl->{$file}{'distrib'}{'default'} = $dir . '/' . $file;
				}
				if ($dir eq $site_dir) {
					$tpl->{$file}{'site'}{'default'} = $dir . '/' . $file;
				}
				if ($dir eq $robot_dir) {
					$tpl->{$file}{'robot'}{'default'} = $dir . '/' . $file;
				}
				if ($dir eq $listdir) {
					$tpl->{$file}{'list'}{'default'} = $dir . '/' . $file;
				}
			}
		}
		closedir DIR;
	}
	return ($tpl);

}

=item get_template_path($type, $robot, $scope, $tpl, $lang, $list, $basedir)

Return the path for a specific template

Parameters:

=over

=item FIXME

=item FIXME

=item FIXME

=item FIXME

=item FIXME

=item FIXME

=item FIXME

=back

=cut

sub get_template_path {
	Sympa::Log::Syslog::do_log('debug2', '(%s, %s. %s, %s, %s, %s)', @_);
	my $type = shift;
	my $robot = shift;
	my $scope = shift;
	my $tpl = shift;
	my $lang = shift || 'default';
	my $list = shift;

	##FIXME: path is fixed to older "locale".
	my $locale;
	$locale = Sympa::Language::Lang2Locale_old($lang) unless $lang eq 'default';

	unless ($type eq 'web' or $type eq 'mail') {
		Sympa::Log::Syslog::do_log('info', 'internal error incorrect parameter');
		return undef;
	}

	my $dir;
	if ($scope eq 'list')  {
		unless (ref $list) {
			Sympa::Log::Syslog::do_log('err', 'missing parameter "list"');
			return undef;
		}
		$dir = $list->dir;
	} elsif ($scope eq 'robot' and $robot->etc ne Site->etc)  {
		$dir = $robot->etc;
	} elsif ($scope eq 'site') {
		$dir = Site->etc;
	} elsif ($scope eq 'distrib') {
		$dir = Sympa::Constants::DEFAULTDIR;
	} else {
		return undef;
	}

	$dir .= '/'.$type.'_tt2';
	$dir .= '/' . $locale unless $lang eq 'default';
	return $dir.'/'.$tpl;
}

##NOTE: This might be moved to Site module as mutative method.
sub get_dkim_parameters {
	Sympa::Log::Syslog::do_log('debug2', '(%s)', @_);
	my $self = shift;

	my $data;
	my $keyfile;
	if (ref $self and ref $self eq 'List') {
		$data->{'d'} = $self->dkim_parameters->{'signer_domain'};
		if ($self->dkim_parameters->{'signer_identity'}) {
			$data->{'i'} = $self->dkim_parameters->{'signer_identity'};
		}else{
			# RFC 4871 (page 21) 
			$data->{'i'} = $self->get_address('owner');
		}

		$data->{'selector'} = $self->dkim_parameters->{'selector'};
		$keyfile = $self->dkim_parameters->{'private_key_path'};
	} elsif (ref $self and ref $self eq 'Robot' or $self eq 'Site') {
		# in robot context
		$data->{'d'} = $self->dkim_signer_domain;
		$data->{'i'} = $self->dkim_signer_identity;
		$data->{'selector'} = $self->dkim_selector;
		$keyfile = $self->dkim_private_key_path;
	} else {
		croak 'bug in logic.  Ask developer';
	}
	unless (open (KEY, $keyfile)) {
		Sympa::Log::Syslog::do_log('err', "Could not read DKIM private key %s", $keyfile);
		return undef;
	}
	while (<KEY>){
		$data->{'private_key'} .= $_;
	}
	close (KEY);

	return $data;
}

=item as_singlepart($msg, $preferred_type, $loops)

Make a multipart/alternative, a singlepart

Parameters:

=over

=item FIXME

=item FIXME

=item FIXME

=back

=cut

sub as_singlepart {
	my ($msg, $preferred_type, $loops) = @_;
	Sympa::Log::Syslog::do_log('debug2', '()');
	my $done = 0;
	$loops++;

	unless (defined $msg) {
		Sympa::Log::Syslog::do_log('err', "Undefined message parameter");
		return undef;
	}

	if ($loops > 4) {
		Sympa::Log::Syslog::do_log('err', 'Could not change multipart to singlepart');
		return undef;
	}

	if ($msg->effective_type() =~ /^$preferred_type$/) {
		$done = 1;
	} elsif ($msg->effective_type() =~ /^multipart\/alternative/) {
		foreach my $part ($msg->parts) {
			if (($part->effective_type() =~ /^$preferred_type$/) ||
				(
					($part->effective_type() =~ /^multipart\/related$/) &&
					$part->parts &&
					($part->parts(0)->effective_type() =~ /^$preferred_type$/))) {
				## Only keep the first matching part
				$msg->parts([$part]);
				$msg->make_singlepart();
				$done = 1;
				last;
			}
		}
	} elsif ($msg->effective_type() =~ /multipart\/signed/) {
		my @parts = $msg->parts();
		## Only keep the first part
		$msg->parts([$parts[0]]);
		$msg->make_singlepart();

		$done ||= as_singlepart($msg, $preferred_type, $loops);

	} elsif ($msg->effective_type() =~ /^multipart/) {
		foreach my $part ($msg->parts) {

			next unless (defined $part); ## Skip empty parts

			if ($part->effective_type() =~ /^multipart\/alternative/) {
				if (as_singlepart($part, $preferred_type, $loops)) {
					$msg->parts([$part]);
					$msg->make_singlepart();
					$done = 1;
				}
			}
		}
	}

	return $done;
}

## Escape characters before using a string within a regexp parameter
## Escaped characters are : @ $ [ ] ( ) ' ! '\' * . + ?
sub escape_regexp {
	my $s = shift;
	my @escaped = ("\\",'@','$','[',']','(',')',"'",'!','*','.','+','?');
	my $backslash = "\\"; ## required in regexp

	foreach my $escaped_char (@escaped) {
		$s =~ s/$backslash$escaped_char/\\$escaped_char/g;
	}

	return $s;
}

=item escape_chars()

Escape weird characters.

=cut

sub escape_chars {
	my ($s, $except) = @_;

	my $ord_except = ord($except) if (defined $except);

	## Escape chars
	##  !"#$%&'()+,:;<=>?[] AND accented chars
	## escape % first
	foreach my $i (0x25,0x20..0x24,0x26..0x2c,0x3a..0x3f,0x5b,0x5d,0x80..0x9f,0xa0..0xff) {
		next if ($i == $ord_except);
		my $hex_i = sprintf "%lx", $i;
		$s =~ s/\x$hex_i/%$hex_i/g;
	}
	$s =~ s/\//%a5/g unless ($except eq '/');  ## Special traetment for '/'

	return $s;
}

=item escape_docname($filename, $except)

Escape shared document file name
Q-decode it first

=cut

sub escape_docname {
	my ($filename, $except) = @_;

	## Q-decode
	$filename = MIME::EncWords::decode_mimewords($filename);

	## Decode from FS encoding to utf-8
	#$filename = Encode::decode(Site->filesystem_encoding, $filename);

	## escapesome chars for use in URL
	return escape_chars($filename, $except);
}

=item unicode_to_utf8($string)

Convert from Perl unicode encoding to UTF8

=cut

sub unicode_to_utf8 {
	my ($s) = @_;

	if (Encode::is_utf8($s)) {
		return Encode::encode_utf8($s);
	}

	return $s;
}

=item qencode_filename($filename)

Q-Encode web file name

=cut

sub qencode_filename {
	my ($filename) = @_;

	## We don't use MIME::Words here because it does not encode properly Unicode
	## Check if string is already Q-encoded first
	## Also check if the string contains 8bit chars
	unless ($filename =~ /\=\?UTF-8\?/ ||
		$filename =~ /^[\x00-\x7f]*$/) {

		## Don't encode elements such as .desc. or .url or .moderate or .extension
		my $part = $filename;
		my ($leading, $trailing);
		$leading = $1 if ($part =~ s/^(\.desc\.)//); ## leading .desc
		$trailing = $1 if ($part =~ s/((\.\w+)+)$//); ## trailing .xx

		my $encoded_part = MIME::EncWords::encode_mimewords($part, Charset => 'utf8', Encoding => 'q', MaxLineLen => 1000, Minimal => 'NO');


		$filename = $leading.$encoded_part.$trailing;
	}

	return $filename;
}

=item qdecode_filename($filename)

Q-Decode web file name

=cut

sub qdecode_filename {
	my ($filename) = @_;

	## We don't use MIME::Words here because it does not encode properly Unicode
	## Check if string is already Q-encoded first
	#if ($filename =~ /\=\?UTF-8\?/) {
	$filename = Encode::encode_utf8(Encode::decode('MIME-Q', $filename));
	#}

	return $filename;
}

=item unescape_chars($string, $except)

Unescape weird characters

=cut

sub unescape_chars {
	my ($s) = @_;

	$s =~ s/%a5/\//g;  ## Special traetment for '/'
	foreach my $i (0x20..0x2c,0x3a..0x3f,0x5b,0x5d,0x80..0x9f,0xa0..0xff) {
		my $hex_i = sprintf "%lx", $i;
		my $hex_s = sprintf "%c", $i;
		$s =~ s/%$hex_i/$hex_s/g;
	}

	return $s;
}

=item escape_html($string)

FIXME.

=cut

sub escape_html {
	my ($s) = @_;

	$s =~ s/\"/\&quot\;/gm;
	$s =~ s/\</&lt\;/gm;
	$s =~ s/\>/&gt\;/gm;

	return $s;
}

=item unescape_html($string)

FIXME.

=cut

sub unescape_html {
	my ($s) = @_;

	$s =~ s/\&quot\;/\"/g;
	$s =~ s/&lt\;/\</g;
	$s =~ s/&gt\;/\>/g;

	return $s;
}

=item sympa_checksum($rcpt, $cookie)

Check sum used to authenticate communication from wwsympa to sympa

=cut

sub sympa_checksum {
	my $rcpt = shift;
	my $checksum = (substr(Digest::MD5::md5_hex(join('/', Site->cookie, $rcpt)), -10)) ;
	return $checksum;
}

=item cookie_changed($current, $basedir)

Create a cipher.

=cut

sub cookie_changed {
	my $current=shift;
	my $changed = 1 ;
	if (-f Site->etc . '/cookies.history') {
		unless (open COOK, '<', Site->etc . '/cookies.history') {
			Sympa::Log::Syslog::do_log('err', 'Unable to read %s/cookies.history',
				Site->etc);
			return undef ; 
		}
		my $oldcook = <COOK>;
		close COOK;

		my @cookies = split(/\s+/,$oldcook );


		if ($cookies[$#cookies] eq $current) {
			Sympa::Log::Syslog::do_log('debug2', "cookie is stable") ;
			$changed = 0;
			#	}else{
			#	    push @cookies, $current ;
			#	    unless (open COOK, '>', Site->etc . '/cookies.history') {
			#		Sympa::Log::Syslog::do_log('err', "Unable to create %s/cookies.history", Site->etc);
			#		return undef ; 
			#	    }
			#	    print COOK join(" ", @cookies);
			#	    
			#	    close COOK;
		}
		return $changed ;
	}else{
		my $umask = umask 037;
		unless (open COOK, '>', Site->etc . '/cookies.history') {
			umask $umask;
			Sympa::Log::Syslog::do_log('err', 'Unable to create %s/cookies.history',
				Site->etc);
			return undef ; 
		}
		umask $umask;
		chown [getpwnam(Sympa::Constants::USER)]->[2], [getgrnam(Sympa::Constants::GROUP)]->[2], Site->etc . '/cookies.history';
		print COOK "$current ";
		close COOK;
		return(0);
	}
}

=item load_mime_types($confdir)

FIXME.

=cut

sub load_mime_types {
	my ($confdir) = @_;

	my $types = {};

	my @localisation = ('/etc/mime.types',
		'/usr/local/apache/conf/mime.types',
		'/etc/httpd/conf/mime.types',$confdir . '/mime.types');

	foreach my $loc (@localisation) {
		next unless (-r $loc);

		unless(open (CONF, $loc)) {
			print STDERR "load_mime_types: unable to open $loc\n";
			return undef;
		}
	}

	while (<CONF>) {
		next if /^\s*\#/;

		if (/^(\S+)\s+(.+)\s*$/i) {
			my ($k, $v) = ($1, $2);

			my @extensions = split / /, $v;

			## provides file extention, given the content-type
			if ($#extensions >= 0) {
				$types->{$k} = $extensions[0];
			}

			foreach my $ext (@extensions) {
				$types->{$ext} = $k;
			}
			next;
		}
	}

	close FILE;
	return $types;
}

=item split_mail($message, $pathname, $dir, $confdir)

FIXME.

=cut

sub split_mail {
	my ($message, $pathname, $dir, $confdir) = @_;

	my $head = $message->head();
	my $encoding = $head->mime_encoding();

	if ($message->is_multipart
		|| ($message->mime_type eq 'message/rfc822')) {

		for (my $i=0 ; $i < $message->parts ; $i++) {
			split_mail ($message->parts ($i), $pathname.'.'.$i, $dir, $confdir);
		}
	}
	else {
		my $fileExt;

		if ($head->mime_attr("content_type.name") =~ /\.(\w+)\s*\"*$/) {
			$fileExt = $1;
		}
		elsif ($head->recommended_filename =~ /\.(\w+)\s*\"*$/) {
			$fileExt = $1;
		}
		else {
			my $mime_types = load_mime_types($confdir);

			$fileExt=$mime_types->{$head->mime_type};
		}



		## Store body in file
		unless (open OFILE, ">$dir/$pathname.$fileExt") {
			Sympa::Log::Syslog::do_log('err', "Unable to create $dir/$pathname.$fileExt : $ERRNO");
			return undef;
		}

		if ($encoding =~ /^(binary|7bit|8bit|base64|quoted-printable|x-uu|x-uuencode|x-gzip64)$/ ) {
			open TMP, ">$dir/$pathname.$fileExt.$encoding";
			$message->print_body (\*TMP);
			close TMP;

			open BODY, "$dir/$pathname.$fileExt.$encoding";

			my $decoder = MIME::Decoder->new($encoding);
			unless (defined $decoder) {
				Sympa::Log::Syslog::do_log('err', 'Cannot create decoder for %s', $encoding);
				return undef;
			}
			$decoder->decode(\*BODY, \*OFILE);
			close BODY;
			unlink "$dir/$pathname.$fileExt.$encoding";
		} else {
			$message->print_body (\*OFILE);
		}
		close (OFILE);
		printf "\t-------\t Create file %s\n", $pathname.'.'.$fileExt;

		## Delete files created twice or more (with Content-Type.name and Content-Disposition.filename)
		$message->purge;
	}

	return 1;
}

=item virus_infected($mail, $path, $args, $domain, $confdir)

FIXME.

=cut

sub virus_infected {
	my $mail = shift ;

	my $file = int(rand(time)) ; # in, version previous from db spools, $file was the filename of the message 
	Sympa::Log::Syslog::do_log('debug2', 'Scan virus in %s', $file);

	unless (Site->antivirus_path) {
		Sympa::Log::Syslog::do_log('debug', 'Sympa not configured to scan virus in message');
		return 0;
	}
	my @name = split(/\//,$file);
	my $work_dir = Site->tmpdir.'/antivirus';

	unless ((-d $work_dir) ||( mkdir $work_dir, 0755)) {
		Sympa::Log::Syslog::do_log('err', "Unable to create tmp antivirus directory $work_dir");
		return undef;
	}

	$work_dir = Site->tmpdir.'/antivirus/'.$name[$#name];

	unless ( (-d $work_dir) || mkdir ($work_dir, 0755)) {
		Sympa::Log::Syslog::do_log('err', "Unable to create tmp antivirus directory $work_dir");
		return undef;
	}

	#$mail->dump_skeleton;

	## Call the procedure of splitting mail
	unless (&split_mail ($mail,'msg', $work_dir)) {
		Sympa::Log::Syslog::do_log('err', 'Could not split mail %s', $mail);
		return undef;
	}

	my $virusfound = 0; 
	my $error_msg;
	my $result;

	## McAfee
	if (Site->antivirus_path =~ /\/uvscan$/) {
		# impossible to look for viruses with no option set
		unless (Site->antivirus_args) {
			Sympa::Log::Syslog::do_log('err', "Missing 'antivirus_args' in sympa.conf");
			return undef;
		}

		my $cmd = sprintf '%s %s %s',
		Site->antivirus_path, Site->antivirus_args, $work_dir;
		open (ANTIVIR, "$cmd |");

		while (<ANTIVIR>) {
			$result .= $_; chomp $result;
			if ((/^\s*Found the\s+(.*)\s*virus.*$/i) ||
				(/^\s*Found application\s+(.*)\.\s*$/i)){
				$virusfound = $1;
			}
		}
		close ANTIVIR;

		my $status = $? >> 8;

		## uvscan status =12 or 13 (*256) => virus
		if (( $status == 13) || ($status == 12)) { 
			$virusfound ||= "unknown";
		}

		## Meaning of the codes
		##  12 : The program tried to clean a file, and that clean failed for some reason and the file is still infected.
		##  13 : One or more viruses or hostile objects (such as a Trojan horse, joke program,  or  a  test file) were found.
		##  15 : The programs self-check failed; the program might be infected or damaged.
		##  19 : The program succeeded in cleaning all infected files.

		$error_msg = $result
		if ($status != 0 && $status != 12 && $status != 13 && $status != 19);

		## Trend Micro
	}elsif (Site->antivirus_path =~ /\/vscan$/) {
		my $cmd = sprintf '%s %s %s',
		Site->antivirus_path, Site->antivirus_args, $work_dir;
		open (ANTIVIR, "$cmd |");

		while (<ANTIVIR>) {
			if (/Found virus (\S+) /i){
				$virusfound = $1;
			}
		}
		close ANTIVIR;

		my $status = $? >> 8;

		## uvscan status = 1 | 2 (*256) => virus
		if ((( $status == 1) or ( $status == 2)) and not($virusfound)) { 
			$virusfound = "unknown";
		}

		## F-Secure
	} elsif(Site->antivirus_path =~ /\/fsav$/) {
		my $dbdir=$` ;

		# impossible to look for viruses with no option set
		unless (Site->antivirus_args) {
			Sympa::Log::Syslog::do_log('err', "Missing 'antivirus_args' in sympa.conf");
			return undef;
		}
		my $cmd = sprintf '%s --databasedirectory %s %s %s',
		Site->antivirus_path, $dbdir, Site->antivirus_args, $work_dir;
		open (ANTIVIR, "$cmd |");

		while (<ANTIVIR>) {

			if (/infection:\s+(.*)/){
				$virusfound = $1;
			}
		}

		close ANTIVIR;

		my $status = $? >> 8;

		## fsecure status =3 (*256) => virus
		if (( $status == 3) and not($virusfound)) { 
			$virusfound = "unknown";
		}    
	}elsif(Site->antivirus_path =~ /f-prot\.sh$/) {

		Sympa::Log::Syslog::do_log('debug2', 'f-prot is running');    
		my $cmd = sprintf '%s %s %s',
		Site->antivirus_path, Site->antivirus_args, $work_dir;
		open (ANTIVIR, "$cmd |");

		while (<ANTIVIR>) {
			if (/Infection:\s+(.*)/){
				$virusfound = $1;
			}
		}

		close ANTIVIR;

		my $status = $? >> 8;

		Sympa::Log::Syslog::do_log('debug2', 'Status: '.$status);    

		## f-prot status =3 (*256) => virus
		if (( $status == 3) and not($virusfound)) { 
			$virusfound = "unknown";
		}    
	}elsif (Site->antivirus_path =~ /kavscanner/) {
		# impossible to look for viruses with no option set
		unless (Site->antivirus_args) {
			Sympa::Log::Syslog::do_log('err', "Missing 'antivirus_args' in sympa.conf");
			return undef;
		}
		my $cmd = sprintf '%s %s %s',
		Site->antivirus_path, Site->antivirus_args, $work_dir;
		open (ANTIVIR,"$cmd |");

		while (<ANTIVIR>) {
			if (/infected:\s+(.*)/){
				$virusfound = $1;
			}
			elsif (/suspicion:\s+(.*)/i){
				$virusfound = $1;
			}
		}
		close ANTIVIR;

		my $status = $? >> 8;

		## uvscan status =3 (*256) => virus
		if (( $status >= 3) and not($virusfound)) { 
			$virusfound = "unknown";
		}

		## Sophos Antivirus... by liuk@publinet.it
	}elsif (Site->antivirus_path =~ /\/sweep$/) {
		# impossible to look for viruses with no option set
		unless (Site->antivirus_args) {
			Sympa::Log::Syslog::do_log('err', "Missing 'antivirus_args' in sympa.conf");
			return undef;
		}
		my $cmd = sprintf '%s %s %s',
		Site->antivirus_path, Site->antivirus_args, $work_dir;
		open (ANTIVIR, "$cmd |");

		while (<ANTIVIR>) {
			if (/Virus\s+(.*)/) {
				$virusfound = $1;
			}
		}       
		close ANTIVIR;

		my $status = $? >> 8;

		## sweep status =3 (*256) => virus
		if (( $status == 3) and not($virusfound)) {
			$virusfound = "unknown";
		}

		## Clam antivirus
	}elsif (Site->antivirus_path =~ /\/clamd?scan$/) {
		my $cmd = sprintf '%s %s %s',
		Site->antivirus_path, Site->antivirus_args, $work_dir;
		open (ANTIVIR, "$cmd |");

		my $result;
		while (<ANTIVIR>) {
			$result .= $_; chomp $result;
			if (/^\S+:\s(.*)\sFOUND$/) {
				$virusfound = $1;
			}
		}       
		close ANTIVIR;

		my $status = $? >> 8;

		## Clamscan status =1 (*256) => virus
		if (( $status == 1) and not($virusfound)) {
			$virusfound = "unknown";
		}

		$error_msg = $result
		if ($status != 0 && $status != 1);

	}         

	## Error while running antivir, notify listmaster
	if ($error_msg) {
		Site->send_notify_to_listmaster('virus_scan_failed',
			{'filename' => $file, 'error_msg' => $error_msg});
	}

	## if debug mode is active, the working directory is kept
	unless ($main::options{'debug'}) {
		opendir (DIR, ${work_dir});
		my @list = readdir(DIR);
		closedir (DIR);
		foreach (@list) {
			my $nbre = unlink ("$work_dir/$_")  ;
		}
		rmdir ($work_dir) ;
	}

	return $virusfound;

}

=item get_filename($type, $options, $name, $robot, $object, $basedir)

Look for a file in the list > robot > server > default locations
Possible values for $options : order=all

Parameters:

=over

=item FIXME

=item FIXME

=item FIXME

=item FIXME

=item FIXME

=item FIXME

=back

=cut

## OBSOLETED: use $list->get_etc_filename(), $family->get_etc_filename(),
##   $robot->get_etc_filaname() or Site->get_etc_filename().
sub get_filename {
	my ($type, $options, $name, $robot, $object) = @_;

	if (ref $object) {
		return $object->get_etc_filename($name, $options);
	} elsif (ref $robot) {
		return $robot->get_etc_filename($name, $options);
	} elsif ($robot and $robot ne '*') {
		return Robot->new($robot)->get_etc_filename($name, $options);
	} else {
		return Site->get_etc_filename($name, $options);
	}
}


## DEPRECATED: use $list->get_etc_include_path(),
##    $robot->get_etc_include_path() or Site->get_etc_include_path().

=item qencode_hierarchy($dir, $original_encoding)

Q-encode a complete file hierarchy. Useful to Q-encode subshared documents

Parameters:

=over

=item FIXME

The root directory

=item FIXME

The suspected original encoding of filenames.

=back

=cut

sub qencode_hierarchy {
	my ($dir, $original_encoding) = @_;

	my $count;
	my @all_files;
	Sympa::Tools::File::list_dir($dir, \@all_files, $original_encoding);

	foreach my $f_struct (reverse @all_files) {

		next unless ($f_struct->{'filename'} =~ /[^\x00-\x7f]/); ## At least one 8bit char

		my $new_filename = $f_struct->{'filename'};
		my $encoding = $f_struct->{'encoding'};
		Encode::from_to($new_filename, $encoding, 'utf8') if $encoding;

		## Q-encode filename to escape chars with accents
		$new_filename = qencode_filename($new_filename);

		my $orig_f = $f_struct->{'directory'}.'/'.$f_struct->{'filename'};
		my $new_f = $f_struct->{'directory'}.'/'.$new_filename;

		## Rename the file using utf8
		Sympa::Log::Syslog::do_log('notice', "Renaming %s to %s", $orig_f, $new_f);
		unless (rename $orig_f, $new_f) {
			Sympa::Log::Syslog::do_log('err', "Failed to rename %s to %s : %s", $orig_f, $new_f, $ERRNO);
			next;
		}
		$count++;
	}

	return $count;
}

=item get_message_id($robot)

FIXME.

=cut

sub get_message_id {
	my $robot = shift;
	my $domain;
	unless ($robot) {
		$domain = Site->domain;
	} elsif (ref $robot and ref $robot eq 'Robot') {
		$domain = $robot->domain;
	} elsif ($robot eq 'Site') {
		$domain = Site->domain;
	} else {
		$domain = $robot;
	}
	my $id = sprintf '<sympa.%d.%d.%d@%s>', time, $$, int(rand(999)), $domain;

	return $id;
}


=item valid_email($email)

Basic check of an email address

=cut

sub valid_email {
	my ($email) = @_;

	unless (defined $email and $email =~ /^$regexp{'email'}$/) {
		Sympa::Log::Syslog::do_log('err', "Invalid email address '%s'", $email);
		return undef;
	}

	## Forbidden characters
	if ($email =~ /[\|\$\*\?\!]/) {
		Sympa::Log::Syslog::do_log('err', "Invalid email address '%s'", $email);
		return undef;
	}

	return 1;
}

=item clean_email($email)

Clean email address

=cut

sub clean_email {
	my ($email) = @_;

	## Lower-case
	$email = lc($email);

	## remove leading and trailing spaces
	$email =~ s/^\s*//;
	$email =~ s/\s*$//;

	return $email;
}

=item get_canonical_email($email)

Return canonical email address (lower-cased + space cleanup)
It could also support alternate email

=cut

sub get_canonical_email {
	my ($email) = @_;

	## Remove leading and trailing white spaces
	$email =~ s/^\s*(\S.*\S)\s*$/$1/;

	## Lower-case
	$email = lc($email);

	return $email;
}

=item clean_msg_id($msg_id)

clean msg_id to use it without  \n, \s or <,>

Parameters:

=over

=item FIXME

The message id.

=back

Return value:

The clean message id.

=cut

sub clean_msg_id {
	my ($msg_id) = @_;

	chomp $msg_id;

	if ($msg_id =~ /\<(.+)\>/) {
		$msg_id = $1;
	}

	return $msg_id;
}

=item change_x_sympa_to($file, $value)

Change X-Sympa-To: header field in the message

=cut

sub change_x_sympa_to {
	my ($file, $value) = @_;

	## Change X-Sympa-To
	unless (open FILE, $file) {
		Sympa::Log::Syslog::do_log('err', "Unable to open '%s' : %s", $file, $ERRNO);
		next;
	}
	my @content = <FILE>;
	close FILE;

	unless (open FILE, ">$file") {
		Sympa::Log::Syslog::do_log('err', "Unable to open '%s' : %s", "$file", $ERRNO);
		next;
	}
	foreach (@content) {
		if (/^X-Sympa-To:/i) {
			$_ = "X-Sympa-To: $value\n";
		}
		print FILE;
	}
	close FILE;

	return 1;
}

=item add_in_blacklist($entry, $robot, $list)

FIXME.

=cut

sub add_in_blacklist {
	my ($entry, $robot, $list) = @_;

	Sympa::Log::Syslog::do_log('info',"(%s,%s,%s)",$entry,$robot,$list->{'name'});
	$entry = lc($entry);
	chomp $entry;

	# robot blacklist not yet availible
	unless ($list) {
		Sympa::Log::Syslog::do_log('info',"robot blacklist not yet availible, missing list parameter");
		return undef;
	}
	unless (($entry)&&($robot)) {
		Sympa::Log::Syslog::do_log('info',"missing parameters");
		return undef;
	}
	if ($entry =~ /\*.*\*/) {
		Sympa::Log::Syslog::do_log('info',"incorrect parameter $entry");
		return undef;
	}
	my $dir = $list->{'dir'}.'/search_filters';
	unless ((-d $dir) || mkdir ($dir, 0755)) {
		Sympa::Log::Syslog::do_log('info','do_blacklist : unable to create dir %s',$dir);
		return undef;
	}
	my $file = $dir.'/blacklist.txt';

	if (open BLACKLIST, "$file"){
		while(<BLACKLIST>) {
			next if (/^\s*$/o || /^[\#\;]/o);
			my $regexp= $_;
			chomp $regexp;
			$regexp =~ s/\*/.*/;
			$regexp = '^'.$regexp.'$';
			if ($entry =~ /$regexp/i) {
				Sympa::Log::Syslog::do_log('notice','do_blacklist : %s already in blacklist(%s)',$entry,$_);
				return 0;
			}
		}
		close BLACKLIST;
	}
	unless (open BLACKLIST, ">> $file"){
		Sympa::Log::Syslog::do_log('info','do_blacklist : append to file %s',$file);
		return undef;
	}
	print BLACKLIST "$entry\n";
	close BLACKLIST;

}

############################################################
#  get_fingerprint                                         #
############################################################
#  Used in 2 cases :                                       #
#  - check the MD5 in the URL                              #
#  - create an MD5 to put in a URL                         #
#                                                          #
#  Use : get_db_random()                                   #
#        init_db_random()                                  #
#        md5_fingerprint()                                 #
#                                                          #  
# IN : $email : email of the subscriber                    #
#      $fingerprint : the fingerprint in the URL (1st case)#
#                                                          # 
# OUT : $fingerprint : a MD5 for create an URL             #
#     | 1 : if the MD5 in the URL is true                  #
#     | undef                                              #
#                                                          #
############################################################
sub get_fingerprint {

	my $email = shift;
	my $fingerprint = shift;
	my $random;
	my $random_email;

	unless($random = &get_db_random()){ # si un random existe : get_db_random
		$random = &init_db_random(); # sinon init_db_random
	}

	$random_email = ($random.$email);

	if( $fingerprint ) { #si on veut vérifier le fingerprint dans l'url

		if($fingerprint eq &md5_fingerprint($random_email)){
			return 1;
		}else{
			return undef;
		}

	}else{ #si on veut créer une url de type http://.../sympa/unsub/$list/$email/&get_fingerprint($email)

		$fingerprint = &md5_fingerprint($random_email);
		return $fingerprint;

	}
}

=item md5_fingerprint($string)

The algorithm MD5 (Message Digest 5) is a cryptographic hash function which
permit to obtain the fingerprint of a file/data.

Returns the md5 digest in hexadecimal format of given string.

=cut

sub md5_fingerprint {
	my ($input_string) = @_;

	return undef unless (defined $input_string);
	chomp $input_string;

	my $digestmd5 = Digest::MD5->new();
	$digestmd5->reset;
	$digestmd5->add($input_string);
	return (unpack("H*", $digestmd5->digest));
}

=item get_separator()

FIXME.

=cut

sub get_separator {
	return $separator;
}

=item get_regexp($type)

Return the Sympa regexp corresponding to the given type.

=cut

sub get_regexp {
	my ($type) = @_;

	if (defined $regexp{$type}) {
		return $regexp{$type};
	} else {
		return '\w+'; ## default is a very strict regexp
	}

}

=item CleanDir($dir, $clean_delay)

Clean all messages in spool $spool_dir older than $clean_delay.

Parameters:

=over

=item string

The path to the spool to clean.

=item FIXME

The delay between the moment we try to clean spool and the last modification date of a file.

=back

Return value:

A true value if the spool was cleaned, a false value otherwise.

=cut

sub CleanDir {
	my ($dir, $clean_delay) = @_;
	Sympa::Log::Syslog::do_log('debug', 'CleanSpool(%s,%s)', $dir, $clean_delay);

	unless (opendir(DIR, $dir)) {
		Sympa::Log::Syslog::do_log('err', "Unable to open '%s' spool : %s", $dir, $ERRNO);
		return undef;
	}

	my @qfile = sort grep (!/^\.+$/,readdir(DIR));
	closedir DIR;

	foreach my $f (sort @qfile) {

		if ((stat "$dir/$f")[9] < (time() - $clean_delay * 60 * 60 * 24)) {
			if (-f "$dir/$f") {
				unlink ("$dir/$f");
				Sympa::Log::Syslog::do_log('notice', 'Deleting old file %s', "$dir/$f");
			} elsif (-d "$dir/$f") {
				unless (Sympa::Tools::File::remove_dir("$dir/$f")) {
					Sympa::Log::Syslog::do_log('err', 'Cannot remove old directory %s : %s', "$dir/$f", $ERRNO);
					next;
				}
				Sympa::Log::Syslog::do_log('notice', 'Deleting old directory %s', "$dir/$f");
			}
		}
	}
	return 1;
}

=item get_lockname()

Return a lockname that is a uniq id of a processus (hostname + pid) ; hostname
(20) and pid(10) are truncated in order to store lockname in database
varchar(30)

=cut

sub get_lockname {
	return substr(substr(hostname(), 0, 20).$PID,0,30);
}

=item wrap_text($text, $init, $subs, $cols)

Return line-wrapped text.

=cut

sub wrap_text {
	my ($text, $init, $subs, $cols) = @_;

	$cols = 78 unless defined $cols;
	return $text unless $cols;

	$text = Text::LineFold->new(
		Language => Sympa::Language::get_lang(),
		OutputCharset => (Encode::is_utf8($text)? '_UNICODE_': 'utf8'),
		Prep => 'NONBREAKURI',
		ColumnsMax => $cols
	)->fold($init, $subs, $text);

	return $text;
}

=item addrencode($addr, $phrase, $charset)

Return formatted (and encoded) name-addr as RFC5322 3.4.

Parameters:

=over

=item FIXME

=item FIXME

=item FIXME

(default: utf8)

=back

=cut

sub addrencode {
	my ($addr, $phrase, $charset) = @_;
	$phrase = '' unless $phrase;
	$charset = 'utf8' unless $charset;

	return undef unless $addr =~ /\S/;

	if ($phrase =~ /[^\s\x21-\x7E]/) {
		# Minimal encoding leaves special characters unencoded.
		# In this case do maximal encoding for workaround.
		my $minimal =
		($phrase =~ /(\A|\s)[\x21-\x7E]*[\"(),:;<>\@\\][\x21-\x7E]*(\s|\z)/)?
		'NO': 'YES';
		$phrase = MIME::EncWords::encode_mimewords(
			Encode::decode('utf8', $phrase),
			'Encoding' => 'A', 'Charset' => $charset,
			'Replacement' => 'FALLBACK',
			'Field' => 'Resent-Sender', # almost longest
			'Minimal' => $minimal
		);
		return "$phrase <$addr>";
	} elsif ($phrase =~ /\S/) {
		$phrase =~ s/([\\\"])/\\$1/g;
		return "\"$phrase\" <$addr>";
	} else {
		return "<$addr>";
	}
}

=item create_html_part_from_web_page(%parameters)

Generate a newsletter from an HTML URL or a file path.

Parameters:

=over

=item C<from> => FIXME

=item C<to> => FIXME

=item C<headers> => FIXME

=item C<subject> => FIXME

=item C<source> => FIXME

=back

=cut

sub create_html_part_from_web_page {
	my (%params) = @_;
	Sympa::Log::Syslog::do_log('debug',"Creating HTML MIME part. Source: %s",$params{source});

	my $mailHTML = MIME::Lite::HTML->new({
			From           => $params{from},
			To             => $params{to},
			Headers        => $params{headers},
			Subject        => $params{subject},
			HTMLCharset    => 'utf-8',
			TextCharset    => 'utf-8',
			TextEncoding   => '8bit',
			HTMLEncoding   => '8bit',
			remove_jscript => '1', #delete the scripts in the html
		});
	# parse return the MIME::Lite part to send
	my $part = $mailHTML->parse($params{source});
	unless (defined($part)) {
		Sympa::Log::Syslog::do_log('err', 'Unable to convert file %s to a MIME part',$params{source});
		return undef;
	}
	return $part->as_string();
}

=item decode_header($msg, $tag, $sep)

Return header value decoded to UTF-8 or undef.
trailing newline will be removed.
If sep is given, return all occurrances joined by it.

=cut

sub decode_header {
	my $msg = shift;
	my $tag = shift;
	my $sep = shift || undef;

	my $head;
	if (ref $msg and $msg->isa('Message')) {
		$head = $msg->as_entity()->head;
	} elsif (ref $msg eq 'MIME::Entity') {
		$head = $msg->head;
	} elsif (ref $msg eq 'MIME::Head' or ref $msg eq 'Mail::Header') {
		$head = $msg;
	} else {
		croak 'bug in logic.  Ask developer';
	}

	if (defined $sep) {
		my @values = $head->get($tag);
		return undef unless scalar @values;
		foreach my $val (@values) {
			$val = MIME::EncWords::decode_mimewords($val, Charset => 'UTF-8');
			chomp $val;
			$val =~ s/(\r\n|\r|\n)([ \t])/$2/g; #unfold
			$val =~ s/\0|\r\n|\r|\n//g; # remove newline & nul
		}
		return join $sep, @values;
	} else {
		my $val = $head->get($tag, 0);
		return undef unless defined $val;
		$val = MIME::EncWords::decode_mimewords($val, Charset => 'UTF-8');
		chomp $val;
		$val =~ s/(\r\n|\r|\n)([ \t])/$2/g; #unfold
		$val =~ s/\0|\r\n|\r|\n//g; # remove newline & nul

		return $val;
	}
}

#*******************************************
## Function : foldcase
## Description : returns "fold-case" string suitable for case-insensitive match.
### IN : str
##*******************************************
sub foldcase {
	my $str = shift;
	return '' unless defined $str and length $str;

	if ($] <= 5.008) {
		# Perl 5.8.0 does not support Unicode::CaseFold. Use lc() instead.
		return Encode::encode_utf8(lc(Encode::decode_utf8($str)));
	} else {
		# later supports it. Perl 5.16.0 and later have built-in fc().
		return Encode::encode_utf8(fc(Encode::decode_utf8($str)));
	}
}

=back

=cut

1;
