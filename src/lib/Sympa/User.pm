# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014, 2015 GIP RENATER
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

Sympa::User - An identified user

=head1 DESCRIPTION

A L<Sympa::User> object has the following attributes:

=over

=item * email: email address

=item * gecos: full name

=item * password: password

=item * last_login_date: last login date, as a timestamp

=item * last_login_host: last login host

=item * wrong_login_count: failed login attempts count

=item * cookie_delay: FIXME

=item * lang: prefered language

=item * attributes: FIXME

=item * data: FIXME

=back

=cut

package Sympa::User;

use strict;
use warnings;
use Carp qw();

use Sympa::Auth;
use Sympa::DatabaseDescription;
use Sympa::DatabaseManager;
use Sympa::Language;
use Sympa::Log;
use tools;
use Sympa::Tools::Data;

my $log = Sympa::Log->instance;

## Database and SQL statement handlers
my ($sth, @sth_stack);

## mapping between var and field names
my %db_struct = Sympa::DatabaseDescription::full_db_struct();
my %map_field;
foreach my $k (keys %{$db_struct{'user_table'}->{'fields'}}) {
    if ($k =~ /^(.+)_user$/) {
        $map_field{$1} = $k;
    }
}

## DB fields with numeric type
## We should not do quote() for these while inserting data
my %numeric_field;
foreach my $k (keys %{$db_struct{'user_table'}->{'fields'}}) {
    if ($db_struct{'user_table'}->{'fields'}{$k}{'struct'} =~ /^int/) {
        $numeric_field{$k} = 1;
    }
}

=head1 CLASS METHODS

=over 4

Sympa::User - All Users Identified by Sympa

Creates a new L<Sympa::User> object.

Parameters:

=over 4

=item * I<email>: email attribute (mandatory)

=item * I<gecos>: gecos attribute

=item * I<lang>: lang attribute

=item * I<password>: password attributes

=item * I<fields>: additional custom fields

=back

Returns a new L<Sympa::User> object, or I<undef> for failure.

=cut

sub new {
    my $pkg    = shift;
    my $who    = tools::clean_email(shift || '');
    my $user_fields = shift;
    my %values      = @_;
    my $self;
    return undef unless $who;

    my $email    = Sympa::Tools::clean_email($params{email});
    my $lang     = Sympa::Language::canonic_lang($params{lang}) ||
                   $params{lang};
    my $gecos    = $params{gecos};
    my $password = $params{password};
    my $fields   = $params{fields};

    return undef unless $email;

    # try to fetch user from the database
    my $self = get_global_user($email, $fields);

    if (!$self) {
        # create a new user
        $self = {
            email    => $email,
            lang     => $lang,
            gecos    => $gecos,
            password => $password
        };

        # try to save it immediatly
        return undef unless add_global_user($self);
    }

    bless $self, $class;

    return $self;
}

=back

=head1 INSTANCE METHODS

=over 4

=item $user->expire()

Remove user information from user_table.

=cut

sub expire {
    delete_global_user(shift->email);
}

=item $user->get_id()

Get unique identifier of object.

=cut

sub get_id {
    ## DO NOT use accessors since $self may not have been fully initialized.
    shift->{'email'} || '';
}

=item $user->get_email()

Get email attribute.

=cut

sub get_email {
    my ($self) = @_;
    return $self->{email};
}

=item $user->moveto()

Change email of user.

=cut

sub moveto {
    my $self = shift;
    my $newemail = tools::clean_email(shift || '');

    unless ($newemail) {
        $log->syslog('err', 'No email');
        return undef;
    }
    if ($self->email eq $newemail) {
        return 0;
    }

    push @sth_stack, $sth;

    unless (
        $sth = do_prepared_query(
            q{UPDATE user_table
              SET email_user = ?
              WHERE email_user = ?},
            $newemail, $self->email
        )
        and $sth->rows
        ) {
        $log->syslog('err', 'Can\'t move user %s to %s', $self, $newemail);
        $sth = pop @sth_stack;
        return undef;
    }

    $sth = pop @sth_stack;

    $self->{'email'} = $newemail;

    return 1;
}

=item $user->get_gecos()

Get gecos attribute.

=cut

sub get_gecos {
    my ($self) = @_;
    return $self->{gecos};
}

=item $user->set_gecos()

Set gecos attribute.

=cut

sub save {
    my $self = shift;
    unless (add_global_user('email' => $self->email, %$self)
        or update_global_user($self->email, %$self)) {
        $log->syslog('err', 'Cannot save user %s', $self);
        return undef;
    }

=item $user->get_password()

Get password attribute.

=cut

sub get_password {
    my ($self) = @_;
    return $self->{password};
}

=item $user->set_password()

Set password attribute.

=cut

sub set_password {
    my ($self, $value) = @_;
    $self->{password} = $value;
}

=item $user->get_last_login_date()

Get last_login_date attribute.

=cut

sub get_last_login_date {
    my ($self) = @_;
    return $self->{last_login_date};
}

=item $user->set_last_login_date()

Set last_login_date attribute.

=cut

    if (scalar grep { $_ eq $attr } qw(email)) {
        ## getter for user attribute.
        no strict "refs";
        *{$AUTOLOAD} = sub {
            my $self = shift;
            Carp::croak "Can't call method \"$attr\" on uninitialized "
                . ref($self)
                . " object"
                unless $self->{'email'};
            Carp::croak "Can't modify \"$attr\" attribute"
                if scalar @_ > 1;
            $self->{$attr};
        };
    } elsif (exists $map_field{$attr}) {
        ## getter/setter for user attributes.
        no strict "refs";
        *{$AUTOLOAD} = sub {
            my $self = shift;
            Carp::croak "Can't call method \"$attr\" on uninitialized "
                . ref($self)
                . " object"
                unless $self->{'email'};
            $self->{$attr} = shift
                if scalar @_ > 1;
            $self->{$attr};
        };
    } else {
        Carp::croak "Can't locate object method \"$2\" via package \"$1\"";
    }
    goto &$AUTOLOAD;
}

=item $user->get_last_login_host()

Get last_login_host attribute.

=cut

sub get_last_login_host {
    my ($self) = @_;
    return $self->{last_login_host};
}

=item $user->set_last_login_host()

Set last_login_host attribute.

=cut

sub get_users {
    die;
}

=item $user->get_wrong_login_count()

Get wrong_login_count attribute.

=cut

sub get_wrong_login_count {
    my ($self) = @_;
    return $self->{wrong_login_count};
}

=item $user->set_wrong_login_count()

Set wrong_login_count attribute.

=cut

sub set_wrong_login_count {
    my ($self, $value) = @_;
    $self->{wrong_login_count} = $value;
}

I<Obsoleted>.

=item update_global_user

Get cookie_delay attribute.

=cut

sub get_cookie_delay {
    my ($self) = @_;
    return $self->{cookie_delay};
}

=item $user->set_cookie_delay()

Set cookie_delay attribute.

=cut

sub set_cookie_delay {
    my ($self, $value) = @_;
    $self->{cookie_delay} = $value;
}

=item $user->get_lang()

Get lang attribute.

=cut

sub get_lang {
    my ($self) = @_;
    return $self->{lang};
}

=item $user->set_lang()

Set lang attribute.

=cut

sub set_lang {
    my ($self, $value) = @_;
    $self->{lang} = $value;
}

=item $user->get_attributes()

Get attributes attribute.

=cut

sub get_attributes {
    my ($self) = @_;
    return $self->{attributes};
}

=item $user->set_attributes()

Set attributes attribute.

=cut

sub set_attributes {
    my ($self, $value) = @_;
    $self->{attributes} = $value;
}

=item $user->get_data()

Get data attribute.

=cut

sub get_data {
    my ($self) = @_;
    return $self->{data};
}

=item $user->set_data()

Set data attribute.

=cut

sub set_data {
    my ($self, $value) = @_;
    $self->{data} = $value;
}

=item $user->save()

Save user information to user_table.

=cut

sub save {
    my $self = shift;
    unless (add_global_user('email' => $self->email, %$self)
        or update_global_user($self->email, %$self)) {
        $main::logger->do_log(Sympa::Logger::ERR, 'Cannot save user %s',
            $self);
        return undef;
    }

    return 1;
}

=back

=head1 FUNCTIONS

=over 4

=item get_users

=cut

sub get_users {
    croak();
}

=item delete_global_user

Delete a user in the user_table

=cut

sub delete_global_user {
    my @users = @_;

    $log->syslog('debug2', '');

    return undef unless ($#users >= 0);

    my $sdm = Sympa::DatabaseManager->instance;
    foreach my $who (@users) {
        $who = tools::clean_email($who);
        ## Update field

        unless (
            $sdm
            and $sdm->do_prepared_query(
                q{DELETE FROM user_table WHERE email_user = ?}, $who
            )
            ) {
            $log->syslog('err', 'Unable to delete user %s', $who);
            next;
        }
    }

    return $#users + 1;
}

=item get_global_user

Returns a hash for a given user

=cut

sub get_global_user {
    $log->syslog('debug2', '(%s)', @_);
    my $who = tools::clean_email(shift);
    my $user_fields = shift;

    ## Additional subscriber fields
    my $additional = '';
    if ($Conf::Conf{'db_additional_user_fields'}) {
        $additional = ', ' . $Conf::Conf{'db_additional_user_fields'};
    }

    push @sth_stack, $sth;
    my $sdm = Sympa::DatabaseManager->instance;

    unless (
        $sdm
        and $sth = $sdm->do_prepared_query(
            sprintf(
                q{SELECT email_user AS email, gecos_user AS gecos,
                         password_user AS password,
                         cookie_delay_user AS cookie_delay, lang_user AS lang,
                         attributes_user AS attributes, data_user AS data,
                         last_login_date_user AS last_login_date,
                         wrong_login_count_user AS wrong_login_count,
                         last_login_host_user AS last_login_host%s
                  FROM user_table
                  WHERE email_user = ?},
                $additional
            ),
            $who
        )
        ) {
        $log->syslog('err', 'Failed to prepare SQL query');
        $sth = pop @sth_stack;
        return undef;
    }

    my $user = $sth->fetchrow_hashref('NAME_lc');
    $sth->finish();

    $sth = pop @sth_stack;

    if (defined $user) {
        ## Canonicalize lang if possible
        if ($user->{'lang'}) {
            $user->{'lang'} = Sympa::Language::canonic_lang($user->{'lang'})
                || $user->{'lang'};
        }

        ## Turn user_attributes into a hash
        my $attributes = $user->{'attributes'};
        if (defined $attributes and length $attributes) {
            $user->{'attributes'} = {};
            foreach my $attr (split(/__ATT_SEP__/, $attributes)) {
                my ($key, $value) = split(/__PAIRS_SEP__/, $attr);
                $user->{'attributes'}{$key} = $value;
            }
            delete $user->{'attributes'}
                unless scalar keys %{$user->{'attributes'}};
        } else {
            delete $user->{'attributes'};
        }
        ## Turn data_user into a hash
        if ($user->{'data'}) {
            my %prefs = Sympa::Tools::Data::string_2_hash($user->{'data'});
            $user->{'prefs'} = \%prefs;
        }
    }

    return $user;
}

=item get_all_global_user

Returns an array of all users in User table hash for a given user

=cut

# OBSOLETED: No longer used.
sub get_all_global_user {
    $log->syslog('debug2', '');

    my @users;

    push @sth_stack, $sth;
    my $sdm = Sympa::DatabaseManager->instance;

    unless ($sdm
        and $sth =
        $sdm->do_prepared_query('SELECT email_user FROM user_table')) {
        $log->syslog('err', 'Unable to gather all users in DB');
        $sth = pop @sth_stack;
        return undef;
    }

    while (my $email = ($sth->fetchrow_array)[0]) {
        push @users, $email;
    }
    $sth->finish();

    $sth = pop @sth_stack;

    return @users;
}
=item is_global_user

Is the person in user table (db only)

=cut

sub is_global_user {
    my $who = tools::clean_email(pop);
    $log->syslog('debug3', '(%s)', $who);

    return undef unless ($who);

    push @sth_stack, $sth;
    my $sdm = Sympa::DatabaseManager->instance;

    ## Query the Database
    unless (
        $sdm
        and $sth = $sdm->do_prepared_query(
            q{SELECT COUNT(*) FROM user_table WHERE email_user = ?}, $who
        )
        ) {
        $log->syslog('err',
            'Unable to check whether user %s is in the user table');
        $sth = pop @sth_stack;
        return undef;
    }

    my $is_user = $sth->fetchrow();
    $sth->finish();

    $sth = pop @sth_stack;

    return $is_user;
}

=item update_global_user

Sets new values for the given user in the Database

=cut

sub update_global_user {
    $log->syslog('debug', '(%s, ...)', @_);
    my $who    = shift;
    my $values = $_[0];
    if (ref $values) {
        $values = {%$values};
    } else {
        $values = {@_};
    }

    $who = tools::clean_email($who);

    ## use md5 fingerprint to store password
    $values->{'password'} =
        Sympa::Auth::password_fingerprint($values->{'password'})
        if ($values->{'password'});

    ## Canonicalize lang if possible.
    $values->{'lang'} = Sympa::Language::canonic_lang($values->{'lang'})
        || $values->{'lang'}
        if $values->{'lang'};

    my $sdm = Sympa::DatabaseManager->instance;
    unless ($sdm) {
        $log->syslog('err', 'Unavailable database connection');
        return undef;
    }

    my ($field, $value);

    ## Update each table
    my @set_list;

    while (($field, $value) = each %{$values}) {
        unless ($map_field{$field}) {
            $log->syslog('err',
                'Unknown field %s in map_field internal error', $field);
            next;
        }
        my $set;

        if ($numeric_field{$map_field{$field}}) {
            $value ||= 0;    ## Can't have a null value
            $set = sprintf '%s=%s', $map_field{$field}, $value;
        } else {
            $set = sprintf '%s=%s', $map_field{$field}, $sdm->quote($value);
        }
        push @set_list, $set;
    }

    return undef unless @set_list;

    ## Update field

    push @sth_stack, $sth;

    $sth = $sdm->do_query(
        "UPDATE user_table SET %s WHERE (email_user=%s)",
        join(',', @set_list),
        $sdm->quote($who)
    );
    unless (defined $sth) {
        $log->syslog('err',
            'Could not update information for user %s in user_table', $who);
        $sth = pop @sth_stack;
        return undef;
    }
    unless ($sth->rows) {
        $sth = pop @sth_stack;
        return 0;
    }

    $sth = pop @sth_stack;

    return 1;
}

=item add_global_user

Adds a user to the user_table

=cut

sub add_global_user {
    $log->syslog('debug3', '(...)');
    my $values = $_[0];
    if (ref $values) {
        $values = {%$values};
    } else {
        $values = {@_};
    }

    my $sdm = Sympa::DatabaseManager->instance;
    unless ($sdm) {
        $log->syslog('err', 'Unavailable databse connection');
        return undef;
    }

    my ($field, $value);

    ## encrypt password
    $values->{'password'} =
        Sympa::Auth::password_fingerprint($values->{'password'})
        if ($values->{'password'});

    ## Canonicalize lang if possible
    $values->{'lang'} = Sympa::Language::canonic_lang($values->{'lang'})
        || $values->{'lang'}
        if $values->{'lang'};

    return undef unless (my $who = tools::clean_email($values->{'email'}));
    return undef if (is_global_user($who));

    ## Update each table
    my (@insert_field, @insert_value);
    while (($field, $value) = each %{$values}) {

        next unless ($map_field{$field});

        my $insert;
        if ($numeric_field{$map_field{$field}}) {
            $value ||= 0;    ## Can't have a null value
            $insert = $value;
        } else {
            $insert = $sdm->quote($value);
        }
        push @insert_value, $insert;
        push @insert_field, $map_field{$field};
    }

    unless (@insert_field) {
        $log->syslog(
            'err',
            'The fields (%s) do not correspond to anything in the database',
            join(',', keys(%{$values}))
        );
        return undef;
    }

    push @sth_stack, $sth;

    ## Update field
    $sth = $sdm->do_query(
        "INSERT INTO user_table (%s) VALUES (%s)",
        join(',', @insert_field),
        join(',', @insert_value)
    );
    unless (defined $sth) {
        $log->syslog('err',
            'Unable to add user %s to the DB table user_table',
            $values->{'email'});
        $sth = pop @sth_stack;
        return undef;
    }
    unless ($sth->rows) {
        $sth = pop @sth_stack;
        return 0;
    }

    $sth = pop @sth_stack;

    return 1;
}

=head2 Miscelaneous

=over 4

=item clean_user ( USER_OR_HASH )

=item clean_users ( ARRAYREF_OF_USERS_OR_HASHES )

I<Function>.
Warn if the argument is not a Sympa::User object.
Return Sympa::User object, if any.

I<TENTATIVE>.
These functions will be used during transition between old and object-oriented
styles.  At last modifications have been done, they shall be removed.

=back

=cut

sub clean_user {
    my $user = shift;

    unless (ref $user eq 'Sympa::User') {
        local $Carp::CarpLevel = 1;
        Carp::carp("Deprecated usage: user should be a Sympa::User object");

        if (ref $user eq 'HASH') {
            $user = bless $user => __PACKAGE__;
        } else {
            $user = undef;
        }
    }
    $user;
}

sub clean_users {
    my $users = shift;
    return $users unless ref $users eq 'ARRAY';

    my $warned = 0;
    foreach my $user (@$users) {
        unless (ref $user eq 'Sympa::User') {
            unless ($warned) {
                local $Carp::CarpLevel = 1;
                Carp::carp(
                    "Deprecated usage: user should be a Sympa::User object");

                $warned = 1;
            }
            if (ref $user eq 'HASH') {
                $user = bless $user => __PACKAGE__;
            } else {
                $user = undef;
            }
        }
    }
    return $users;
}

1;
