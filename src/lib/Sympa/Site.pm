# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997-2011 Comite Reseau des Universites
# Copyright (c) 2011-2014 GIP RENATER
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

=encoding utf-8

=head1 NAME 

Sympa::Site - The Sympa server

=head1 DESCRIPTION

This class implements the global Sympa server. It should :

=over

=item * provide access to global server configuration

=back

=cut

package Sympa::Site;

use strict;
use warnings;
use base qw(Sympa::ConfigurableObject);

use Carp qw(croak carp);

use Sympa::Conf;
use Sympa::ConfDef;
use Sympa::Language;
use Sympa::Logger;

####
#### global variables
####
our $is_initialized;
our $use_db;

=head3 ACCESSORS

=over 4

=item E<lt>config parameterE<gt>

I<Getters>.
Gets global or default config parameters.
For example: C<Site-E<gt>syslog> returns "syslog" global parameter;
C<Site-E<gt>domain> returns default "domain" parameter.

Some parameters may be vary by each robot from default value given by these
methods.  Use C<$robot-E<gt>>E<lt>config parameterE<gt> accessors instead.
See L<Robot/ACCESSORS>.

=item locale2charset

=item robot_by_http_host

=item ... etc.

I<Getters>.
Gets derived config parameters.

=back

=cut

our $AUTOLOAD;

sub DESTROY;

sub AUTOLOAD {
    my ( undef, $file, $line ) = caller;
    die "Sympa::Site::AUTOLOAD is now verbotten, please fix\n$file:$line\n"
    , "@_";
    $main::logger->do_log(Sympa::Logger::DEBUG3, 'Autoloading %s', $AUTOLOAD);
    $AUTOLOAD =~ m/^(.*)::(.*)/;
    my $pkg  = $1;
    my $attr = $2;

    my $type = {};
    ## getters for site/robot attributes.
    $type->{'RobotAttribute'} = 1
        if grep { $_ eq $attr } qw(etc home name);
    ## getters for site/robot parameters.
    $type->{'RobotParameter'} = 1
        if grep { $_ eq $attr }
            qw(blacklist loging_condition loging_for_module
            trusted_applications)
            or grep { $_->{'name'} and $_->{'name'} eq $attr }
            @Sympa::ConfDef::params;
    ## getters for attributes specific to global config.
    $type->{'SiteAttribute'} = 1
        if grep { $_ eq $attr }
            qw(auth_services authentication_info_url
            cas_id cas_number crawlers_detection
            generic_sso_id generic_sso_number
            ldap ldap_export ldap_number
            locale2charset nrcpt_by_domain
            robot_by_http_host robot_by_soap_url
            use_passwd queue queueautomatic);

    unless (scalar keys %$type) {
        ## getter for unknwon list attributes.
        ## XXX This code would be removed later.
        if (index($attr, '_') != 0
            and ((ref $_[0] and exists $_[0]->{$attr})
                or exists $Sympa::Conf::Conf{$attr})
            ) {
            $main::logger->do_log(
                Sympa::Logger::ERR,
                'Unconcerned object method "%s" via package "%s".  Though it may not be fatal, you might want to report it developer',
                $attr,
                $pkg
            );
            no strict "refs";
            *{$AUTOLOAD} = sub {
                croak "Can't modify \"$attr\" attribute" if scalar @_ > 1;
                shift->{$attr};
            };
            goto &$AUTOLOAD;
        }
        ## XXX Code above would be removed later.

        croak "Can't locate object method \"$2\" via package \"$1\"";
    }

    no strict "refs";
    *{$AUTOLOAD} = sub {
        my $self = shift;

        if (ref $self and ref $self eq 'Sympa::VirtualHost') {
            if ($type->{'RobotAttribute'}) {
                ## getter for list attributes.
                croak "Can't modify \"$attr\" attribute" if scalar @_ > 1;
                return $self->{$attr};
            } elsif ($type->{'RobotParameter'}) {
                ## getters for robot parameters.
                unless ($self->{'etc'} eq Sympa::Site->etc
                    or defined Sympa::VirtualHost::get_robots()->{$self->{'name'}}) {
                    croak "Can't call method \"$attr\" on uninitialized "
                        . (ref $self)
                        . " object";
                }
                croak "Can't modify \"$attr\" attribute" if scalar @_;

                if ($self->{'etc'} ne Sympa::Site->etc
                    and defined Sympa::VirtualHost::get_robots()->{$self->{'name'}}{$attr})
                {
                    ##FIXME: Might "exists" be used?
                    Sympa::VirtualHost::get_robots()->{$self->{'name'}}{$attr};
                } else {
                    Sympa::Site->$attr;
                }
            } else {
                croak "Can't call method \"$attr\" on "
                    . (ref $self)
                    . " object";
            }
        } elsif ($self eq 'Site') {
            ## getter for internal config parameters.
            croak "Can't call method \"$attr\" on uninitialized $self class"
                unless $is_initialized;
            croak "Can't modify \"$attr\" attribute"
                if scalar @_ > 1;

            my $ret = $Sympa::Conf::Conf{$attr};

            # To avoid "Can't use an undefined value as a HASH reference"
            if (!defined $ret and $type->{'SiteAttribute'}) {
                return {};
            }
            $ret;
        } else {
            croak 'bug in logic.  Ask developer';
        }
    };
    goto &$AUTOLOAD;
}

=over 4

=item config

XXX I<Not yet implemented>.

I<Getter/Setter>, I<internal use>.
Gets or sets configuration information, eliminating defaults.

B<Note>:
Use L</fullconfig> accessor to get full configuration informaton.

=back

=cut

sub config {
    croak 'Not implemented';
}

=over 4

=item fullconfig

I<Getter>.
Configuration information of the site, with defaults applied.

B<Note>:
Use L</config> accessor to get information without defaults.

B<Note>:
L<fullconfig> and L<config> accessors will return the copy of configuration
information.  Modification of them will never affect to actual site
parameters.
Use C<E<lt>config parameterE<gt>> accessors to get or set each site parameter.

=back

=cut

## TODO: expand scenario parameters.
sub fullconfig {
    my $self       = shift;
    my $fullconfig = {};

    foreach my $p (@Sympa::ConfDef::params) {
        next unless $p->{'name'};
        my $attr = $p->{'name'};
        $fullconfig->{$p->{'name'}} = $self->$attr;
    }
    return $fullconfig;
}

=over 4

=item lang

I<Getter>.
Gets "lang" parameter, canonicalized if possible.

=back

=cut

#FIXME: inefficient; would be cached.
sub lang {
    my $self = shift;
    my $lang;

    croak "Can't modify \"lang\" attribute" if scalar @_ > 1;
    if (    ref $self
        and ref $self eq 'Sympa::VirtualHost'
        and $self->{'etc'} ne Sympa::Site->etc
        and exists Sympa::VirtualHost::get_robots()->{$self->{'name'}}{'lang'}) {
        $lang = Sympa::VirtualHost::get_robots()->{$self->{'name'}}{'lang'};
    } elsif (ref $self and ref $self eq 'Sympa::VirtualHost'
        or !ref $self and $self eq 'Site') {
        croak "Can't call method \"lang\" on uninitialized $self class"
            unless $is_initialized;
        $lang = $Sympa::Conf::Conf{'lang'};
    } else {
        croak 'bug in loginc.  Ask developer';
    }

    if ($lang) {
        $lang = Sympa::Language::canonic_lang($lang) || $lang;
    }
    return $lang;
}

=head3 Derived parameters

These are accessors derived from default parameters.
Some of them are obsoleted.

=over 4

=item listmasters

I<Getter>.
Gets default listmasters.
In array context, returns array of default listmasters.
In scalar context, returns arrayref to them.

=back

=cut

sub listmasters {
    my $self = shift;

    croak "Can't modify \"listmasters\" attribute" if scalar @_ > 1;
    if (ref $self and ref $self eq 'Sympa::VirtualHost') {
        if (wantarray) {
            @{Sympa::VirtualHost::get_robots()->{$self->domain}{'listmasters'} || []};
        } else {
            Sympa::VirtualHost::get_robots()->{$self->domain}{'listmasters'};
        }
    } elsif ($self eq 'Site') {
        croak "Can't call method \"listmasters\" on uninitialized $self class"
            unless $is_initialized;

        if (wantarray) {
            @{$Sympa::Conf::Conf{'listmasters'} || []};
        } else {
            $Sympa::Conf::Conf{'listmasters'};
        }
    } else {
        croak 'bug in logic.  Ask developer';
    }
}

=over 4

=item supported_languages ( )

I<Getter>.
Gets supported languages, canonicalized.
In array context, returns array of supported languages.
In scalar context, returns arrayref to them.

=back

=cut

#FIXME: Inefficient.  Would be cached.
sub supported_languages {
    my $self = shift;

    my @lang_list = ();
    if ($Sympa::Site::is_initialized) {    # configuration loaded.
        my $supported_lang = $self->supported_lang;

        my $language = Sympa::Language->instance;
        $language->push_lang;
        @lang_list =
            grep { $_ and $_ = $language->set_lang($_) }
            split /[\s,]+/, $supported_lang;
        $language->pop_lang;
    }
    @lang_list = ('en') unless @lang_list;
    return @lang_list if wantarray;
    return \@lang_list;
}

=over

=item get_charset ( )

I<Class method>.
Gets charset for e-mail messages sent by Sympa according to current language
context.

Parameters:

None.

Returns:

Charset name.
If it is not known, returns default charset.

=back

=cut

sub get_charset {
    my $language = Sympa::Language->instance;
    my $lang     = shift || $language->get_lang;

    $language->push_lang($lang);
    my $locale2charset;
    if ($lang and $is_initialized   # configuration loaded
        and $locale2charset = Site->locale2charset
        ) {
        foreach my $l (Sympa::Language::implicated_langs($lang)) {
            if (exists $locale2charset->{$l}) {
                $language->pop_lang;
                return $locale2charset->{$l};
            }
        }
    }
    $language->pop_lang;
    return 'utf-8';                  # the last resort
}

1;
