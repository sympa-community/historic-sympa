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

package Sympa::User;

use strict;
use warnings;

use Carp qw(carp croak);

use Sympa::DatabaseDescription;
use Sympa::Logger;
use Sympa::Tools;
use Sympa::Tools::Data;
use Sympa::Tools::Password;

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

=encoding utf-8

=head1 NAME

User - All Users Identified by Sympa

=head1 DESCRIPTION

=head2 CONSTRUCTOR

=over 4

=item new ( EMAIL, [ KEY => VAL, ... ] )

Create new Sympa::User object.

=back

=cut

sub new {
    my $pkg         = shift;
    my $who         = Sympa::Tools::clean_email(shift || '');
    my $user_fields = shift;
    my %values      = @_;
    my $self;
    return undef unless $who;

    ## Canonicalize lang if possible
    $values{'lang'} = Sympa::Language::canonic_lang($values{'lang'})
        || $values{'lang'}
        if $values{'lang'};

    if (!($self = get_global_user($who, $user_fields))) {
        ## unauthenticated user would not be added to database.
        $values{'email'} = $who;
        if (scalar grep { $_ ne 'lang' and $_ ne 'email' } keys %values) {
            unless (defined add_global_user(\%values)) {
                return undef;
            }
        }
        $self = \%values;
    }

    bless $self => $pkg;
}

=head2 METHODS

=over 4

=item expire

Remove user information from user_table.

=back

=cut

sub expire {
    delete_global_user(shift->email);
}

=over 4

=item get_id

Get unique identifier of object.

=back

=cut

sub get_id {
    ## DO NOT use accessors since $self may not have been fully initialized.
    shift->{'email'} || '';
}

=over 4

=item moveto

Change email of user.

=back

=cut

sub moveto {
    my $self = shift;
    my $newemail = Sympa::Tools::clean_email(shift || '');

    unless ($newemail) {
        $main::logger->do_log(Sympa::Logger::ERR, 'No email');
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
        $main::logger->do_log(Sympa::Logger::ERR, 'Can\'t move user %s to %s',
            $self, $newemail);
        $sth = pop @sth_stack;
        return undef;
    }

    $sth = pop @sth_stack;

    $self->{'email'} = $newemail;

    return 1;
}

=over 4

=item save

Save user information to user_table.

=back

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

=head3 ACCESSORS

=over 4

=item E<lt>attributeE<gt>

=item E<lt>attributeE<gt>C<( VALUE )>

I<Getters/Setters>.
Get or set user attributes.
For example C<$user-E<gt>gecos> returns "gecos" parameter of the user,
and C<$user-E<gt>gecos("foo")> also changes it.
Basic user profile "email" have only getter,
so it is read-only.

=back

=cut

our $AUTOLOAD;

sub DESTROY { }   # "sub DESTROY;" may cause segfault with Perl around 5.10.1.

sub AUTOLOAD {
    $AUTOLOAD =~ m/^(.*)::(.*)/;

    my $attr = $2;

    if (scalar grep { $_ eq $attr } qw(email)) {
        ## getter for user attribute.
        no strict "refs";
        *{$AUTOLOAD} = sub {
            my $self = shift;
            croak "Can't call method \"$attr\" on uninitialized "
                . ref($self)
                . " object"
                unless $self->{'email'};
            croak "Can't modify \"$attr\" attribute"
                if scalar @_ > 1;
            $self->{$attr};
        };
    } elsif (exists $map_field{$attr}) {
        ## getter/setter for user attributes.
        no strict "refs";
        *{$AUTOLOAD} = sub {
            my $self = shift;
            croak "Can't call method \"$attr\" on uninitialized "
                . ref($self)
                . " object"
                unless $self->{'email'};
            $self->{$attr} = shift
                if scalar @_ > 1;
            $self->{$attr};
        };
    } else {
        croak "Can't locate object method \"$2\" via package \"$1\"";
    }
    goto &$AUTOLOAD;
}

=head2 FUNCTIONS

=over 4

=item get_users ( ... )

=back

=cut

sub get_users {
    croak();
}

############################################################################
## Old-style functions
############################################################################

=head2 OLD STYLE FUNCTIONS

=over 4

=item add_global_user

=item delete_global_user

=item is_global_user

=item get_global_user

=item get_all_global_user

=item update_global_user

=back

=cut

## Delete a user in the user_table
sub delete_global_user {
    my @users = @_;

    $main::logger->do_log(Sympa::Logger::DEBUG2, '');

    return undef unless ($#users >= 0);

    foreach my $who (@users) {
        $who = Sympa::Tools::clean_email($who);
        ## Update field

        unless (
            Sympa::DatabaseManager::do_prepared_query(
                q{DELETE FROM user_table WHERE email_user = ?}, $who
            )
            ) {
            $main::logger->do_log(Sympa::Logger::ERR,
                'Unable to delete user %s', $who);
            next;
        }
    }

    return $#users + 1;
}

## Returns a hash for a given user
sub get_global_user {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '(%s)', @_);
    my $who         = Sympa::Tools::clean_email(shift);
    my $user_fields = shift;

    ## Additional subscriber fields
    my $additional = $user_fields ? ', ' . $user_fields : '';

    push @sth_stack, $sth;

    unless (
        $sth = Sympa::DatabaseManager::do_prepared_query(
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
        $main::logger->do_log(Sympa::Logger::ERR,
            'Failed to prepare SQL query');
        $sth = pop @sth_stack;
        return undef;
    }

    my $user = $sth->fetchrow_hashref('NAME_lc');
    $sth->finish();

    $sth = pop @sth_stack;

    if (defined $user) {
        ## decrypt password
        if ($user->{'password'}) {
            $user->{'password'} =
                Sympa::Tools::Password::decrypt_password($user->{'password'});
        }

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

## Returns an array of all users in User table hash for a given user
sub get_all_global_user {
    $main::logger->do_log(Sympa::Logger::DEBUG2, '()');

    my @users;

    push @sth_stack, $sth;

    unless (
        $sth = Sympa::DatabaseManager::do_prepared_query(
            'SELECT email_user FROM user_table')
        ) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to gather all users in DB');
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

## Is the person in user table (db only)
sub is_global_user {
    my $who = Sympa::Tools::clean_email(pop);
    $main::logger->do_log(Sympa::Logger::DEBUG3, '(%s)', $who);

    return undef unless ($who);

    push @sth_stack, $sth;

    ## Query the Database
    unless (
        $sth = Sympa::DatabaseManager::do_prepared_query(
            q{SELECT count(*) FROM user_table WHERE email_user = ?}, $who
        )
        ) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Unable to check whether user %s is in the user table.');
        $sth = pop @sth_stack;
        return undef;
    }

    my $is_user = $sth->fetchrow();
    $sth->finish();

    $sth = pop @sth_stack;

    return $is_user;
}

## Sets new values for the given user in the Database
sub update_global_user {
    $main::logger->do_log(Sympa::Logger::DEBUG, '(%s, ...)', @_);
    my $who    = shift;
    my $values = $_[0];
    if (ref $values) {
        $values = {%$values};
    } else {
        $values = {@_};
    }

    $who = Sympa::Tools::clean_email($who);

    ## use md5 fingerprint to store password
    $values->{'password'} =
        Sympa::Auth::password_fingerprint($values->{'password'})
        if ($values->{'password'});

    ## Canonicalize lang if possible.
    $values->{'lang'} = Sympa::Language::canonic_lang($values->{'lang'})
        || $values->{'lang'}
        if $values->{'lang'};

    my ($field, $value);

    ## Update each table
    my @set_list;

    while (($field, $value) = each %{$values}) {
        unless ($map_field{$field}) {
            $main::logger->do_log('error',
                "unknown field $field in map_field internal error");
            next;
        }
        my $set;

        if ($numeric_field{$map_field{$field}}) {
            $value ||= 0;    ## Can't have a null value
            $set = sprintf '%s=%s', $map_field{$field}, $value;
        } else {
            $set = sprintf '%s=%s', $map_field{$field},
                Sympa::DatabaseManager::quote($value);
        }
        push @set_list, $set;
    }

    return undef unless @set_list;

    ## Update field

    push @sth_stack, $sth;

    $sth = Sympa::DatabaseManager::do_query(
        "UPDATE user_table SET %s WHERE (email_user=%s)",
        join(',', @set_list),
        Sympa::DatabaseManager::quote($who)
    );
    unless (defined $sth) {
        $main::logger->do_log(Sympa::Logger::ERR,
            'Could not update informations for user %s in user_table', $who);
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

## Adds a user to the user_table
sub add_global_user {
    $main::logger->do_log(Sympa::Logger::DEBUG3, '(...)');
    my $values = $_[0];
    if (ref $values) {
        $values = {%$values};
    } else {
        $values = {@_};
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

    return undef
        unless (my $who = Sympa::Tools::clean_email($values->{'email'}));
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
            $insert = sprintf "%s", Sympa::DatabaseManager::quote($value);
        }
        push @insert_value, $insert;
        push @insert_field, $map_field{$field};
    }

    unless (@insert_field) {
        $main::logger->do_log(
            Sympa::Logger::ERR,
            'The fields (%s) do not correspond to anything in the database',
            join(',', keys(%{$values}))
        );
        return undef;
    }

    push @sth_stack, $sth;

    ## Update field
    $sth = Sympa::DatabaseManager::do_query(
        "INSERT INTO user_table (%s) VALUES (%s)",
        join(',', @insert_field),
        join(',', @insert_value)
    );
    unless (defined $sth) {
        $main::logger->do_log(Sympa::Logger::ERR,
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

1;
