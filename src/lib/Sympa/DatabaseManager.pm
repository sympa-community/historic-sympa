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

package Sympa::DatabaseManager;

use strict;
use warnings;

use Conf;
use Sympa::Constants;
use Sympa::Database;
use Sympa::DatabaseDescription;
use Log;
use tools;
use Sympa::Tools::Data;

use base qw(Class::Singleton);

# Constructor for Class::Singleton.
# NOTE: This method actually returns an instance of Sympa::DatabaseDriver
# subclass not inheriting this class.  That's why probe_db() isn't the method
# but a static function.
sub _new_instance {
    my $class = shift;

    my $self;
    my $db_conf = Conf::get_parameters_group('*', 'Database related');

    return undef
        unless $self = Sympa::Database->new($db_conf->{'db_type'}, %$db_conf)
            and $self->connect;

    # At once connection succeeded, we keep trying to connect.
    # Unless in a web context, because we can't afford long response time on
    # the web interface.
    $self->set_persistent(1) unless $ENV{'GATEWAY_INTERFACE'};

    return $self;
}

# db structure description has moved in Sympa::DatabaseDescription.
my %db_struct     = Sympa::DatabaseDescription::db_struct();
my %not_null      = Sympa::DatabaseDescription::not_null();
my %primary       = Sympa::DatabaseDescription::primary();
my %autoincrement = Sympa::DatabaseDescription::autoincrement();

# List the required INDEXES
#   1st key is the concerned table
#   2nd key is the index name
#   the table lists the field on which the index applies
my %indexes = %Sympa::DatabaseDescription::indexes;

# table indexes that can be removed during upgrade process
my @former_indexes = @Sympa::DatabaseDescription::former_indexes;

sub probe_db {
    Log::do_log('debug3', 'Checking database structure');

    my $sdm = __PACKAGE__->instance;
    unless ($sdm) {
        Log::do_log('err',
            'Could not check the database structure.  Make sure that database connection is available'
        );
        return undef;
    }

    my (%checked, $table);
    my $db_type = Conf::get_robot_conf('*', 'db_type');
    my $update_db_field_types =
        Conf::get_robot_conf('*', 'update_db_field_types') || 'off';

    # Does the driver support probing database structure?
    foreach my $method (
        qw(is_autoinc get_tables get_fields get_primary_key get_indexes)) {
        unless ($sdm->can($method)) {
            Log::do_log('notice',
                'Could not check the database structure: required methods have not been implemented'
            );
            return 1;
        }
    }

    # Does the driver support updating database structure?
    my $may_update;
    unless ($update_db_field_types eq 'auto') {
        $may_update = 0;
    } else {
        $may_update = 1;
        foreach my $method (
            qw(set_autoinc add_table update_field add_field delete_field
            unset_primary_key set_primary_key unset_index set_index)
            ) {
            unless ($sdm->can($method)) {
                $may_update = 0;
                last;
            }
        }
    }

    ## Database structure
    ## Report changes to listmaster
    my @report;

    ## Get tables
    my @tables;
    my $list_of_tables;
    if ($list_of_tables = $sdm->get_tables()) {
        @tables = @{$list_of_tables};
    } else {
        @tables = ();
    }

    my ($fields, %real_struct);
    ## Check required tables
    foreach my $t1 (keys %{$db_struct{'mysql'}}) {
        my $found;
        foreach my $t2 (@tables) {
            $found = 1 if ($t1 eq $t2);
        }
        unless ($found) {
            my $rep;
            if (    $may_update
                and $rep = $sdm->add_table({'table' => $t1})) {
                push @report, $rep;
                Log::do_log(
                    'notice', 'Table %s created in database %s',
                    $t1, Conf::get_robot_conf('*', 'db_name')
                );
                push @tables, $t1;
                $real_struct{$t1} = {};
            }
        }
    }
    ## Get fields
    foreach my $t (keys %{$db_struct{'mysql'}}) {
        $real_struct{$t} = $sdm->get_fields({'table' => $t});
    }
    ## Check tables structure if we could get it
    ## Only performed with mysql , Pg and SQLite
    if (%real_struct) {
        foreach my $t (keys %{$db_struct{'mysql'}}) {
            unless ($real_struct{$t}) {
                Log::do_log(
                    'err',
                    'Table "%s" not found in database "%s"; you should create it with create_db.%s script',
                    $t,
                    Conf::get_robot_conf('*', 'db_name'),
                    $db_type
                );
                return undef;
            }
            unless (
                _check_fields(
                    $sdm,
                    {   'table'       => $t,
                        'report'      => \@report,
                        'real_struct' => \%real_struct,
                        'may_update'  => $may_update,
                    }
                )
                ) {
                Log::do_log(
                    'err',
                    'Unable to check the validity of fields definition for table %s. Aborting',
                    $t
                );
                return undef;
            }
            ## Remove temporary DB field
            if ($may_update and $real_struct{$t}{'temporary'}) {
                $sdm->delete_field(
                    {   'table' => $t,
                        'field' => 'temporary',
                    }
                );
                delete $real_struct{$t}{'temporary'};
            }

            ## Check that primary key has the right structure.
            unless (
                _check_primary_key(
                    $sdm,
                    {   'table'      => $t,
                        'report'     => \@report,
                        'may_update' => $may_update
                    }
                )
                ) {
                Log::do_log(
                    'err',
                    'Unable to check the validity of primary key for table %s. Aborting',
                    $t
                );
                return undef;
            }

            unless (
                _check_indexes(
                    $sdm,
                    {   'table'      => $t,
                        'report'     => \@report,
                        'may_update' => $may_update
                    }
                )
                ) {
                Log::do_log(
                    'err',
                    'Unable to check the valifity of indexes for table %s. Aborting',
                    $t
                );
                return undef;
            }
        }
        # add autoincrement if needed
        foreach my $table (keys %autoincrement) {
            unless (
                $sdm->is_autoinc(
                    {'table' => $table, 'field' => $autoincrement{$table}}
                )
                ) {
                if ($may_update
                    and $sdm->set_autoinc(
                        {   'table'      => $table,
                            'field'      => $autoincrement{$table},
                            'field_type' => $db_struct{$db_type}->{$table}
                                ->{$autoincrement{$table}},
                        }
                    )
                    ) {
                    Log::do_log('notice',
                        "Setting table $table field $autoincrement{$table} as autoincrement"
                    );
                } else {
                    Log::do_log('err',
                        "Could not set table $table field $autoincrement{$table} as autoincrement"
                    );
                    return undef;
                }
            }
        }
    } else {
        Log::do_log('err',
            "Could not check the database structure. consider verify it manually before launching Sympa."
        );
        return undef;
    }

    ## Notify listmaster
    tools::send_notify_to_listmaster('*', 'db_struct_updated',
        {'report' => \@report})
        if @report;

    return 1;
}

sub _check_fields {
    my $sdm         = shift;
    my $param       = shift;
    my $t           = $param->{'table'};
    my %real_struct = %{$param->{'real_struct'}};
    my $report_ref  = $param->{'report'};
    my $may_update  = $param->{'may_update'};

    my $db_type = Conf::get_robot_conf('*', 'db_type');

    foreach my $f (sort keys %{$db_struct{$db_type}{$t}}) {
        unless ($real_struct{$t}{$f}) {
            push @{$report_ref},
                sprintf(
                "Field '%s' (table '%s' ; database '%s') was NOT found. Attempting to add it...",
                $f, $t, Conf::get_robot_conf('*', 'db_name'));
            Log::do_log(
                'notice',
                'Field "%s" (table "%s"; database "%s") was NOT found. Attempting to add it...',
                $f,
                $t,
                Conf::get_robot_conf('*', 'db_name')
            );

            my $rep;
            if ($may_update
                and $rep = $sdm->add_field(
                    {   'table'   => $t,
                        'field'   => $f,
                        'type'    => $db_struct{$db_type}{$t}{$f},
                        'notnull' => $not_null{$f},
                        'autoinc' =>
                            ($autoincrement{$t} and $autoincrement{$t} eq $f),
                        'primary' => (
                            scalar @{$primary{$t} || []} == 1
                                and $primary{$t}->[0] eq $f
                        ),
                    }
                )
                ) {
                push @{$report_ref}, $rep;
            } else {
                Log::do_log('err',
                    'Addition of fields in database failed. Aborting');
                return undef;
            }
            next;
        }

        ## Change DB types if different and if update_db_types enabled
        if ($may_update) {
            unless (
                _check_db_field_type(
                    effective_format => $real_struct{$t}{$f},
                    required_format  => $db_struct{$db_type}{$t}{$f}
                )
                ) {
                push @{$report_ref},
                    sprintf(
                    "Field '%s'  (table '%s' ; database '%s') does NOT have awaited type (%s). Attempting to change it...",
                    $f, $t,
                    Conf::get_robot_conf('*', 'db_name'),
                    $db_struct{$db_type}{$t}{$f}
                    );

                Log::do_log(
                    'notice',
                    'Field "%s" (table "%s"; database "%s") does NOT have awaited type (%s) where type in database seems to be (%s). Attempting to change it...',
                    $f,
                    $t,
                    Conf::get_robot_conf('*', 'db_name'),
                    $db_struct{$db_type}{$t}{$f},
                    $real_struct{$t}{$f}
                );

                my $rep;
                if ($may_update
                    and $rep = $sdm->update_field(
                        {   'table'   => $t,
                            'field'   => $f,
                            'type'    => $db_struct{$db_type}{$t}{$f},
                            'notnull' => $not_null{$f},
                        }
                    )
                    ) {
                    push @{$report_ref}, $rep;
                } else {
                    Log::do_log('err',
                        'Fields update in database failed. Aborting');
                    return undef;
                }
            }
        } else {
            unless ($real_struct{$t}{$f} eq $db_struct{$db_type}{$t}{$f}) {
                Log::do_log(
                    'err',
                    'Field "%s" (table "%s"; database "%s") does NOT have awaited type (%s)',
                    $f,
                    $t,
                    Conf::get_robot_conf('*', 'db_name'),
                    $db_struct{$db_type}{$t}{$f}
                );
                Log::do_log('err',
                    'Sympa\'s database structure may have change since last update ; please check RELEASE_NOTES'
                );
                return undef;
            }
        }
    }
    return 1;
}

sub _check_primary_key {
    my $sdm        = shift;
    my $param      = shift;
    my $t          = $param->{'table'};
    my $report_ref = $param->{'report'};
    my $may_update = $param->{'may_update'};

    my $list_of_keys = join ',', @{$primary{$t}};
    my $key_as_string = "$t [$list_of_keys]";
    Log::do_log('debug',
        'Checking primary keys for table %s expected_keys %s',
        $t, $key_as_string);

    my $should_update = _check_key(
        $sdm,
        {   'table'         => $t,
            'key_name'      => 'primary',
            'expected_keys' => $primary{$t}
        }
    );
    if ($should_update) {
        my $list_of_keys = join ',', @{$primary{$t}};
        my $key_as_string = "$t [$list_of_keys]";
        if ($should_update->{'empty'}) {
            Log::do_log('notice', 'Primary key %s is missing. Adding it',
                $key_as_string);
            ## Add primary key
            my $rep = undef;
            if ($may_update
                and $rep = $sdm->set_primary_key(
                    {'table' => $t, 'fields' => $primary{$t}}
                )
                ) {
                push @{$report_ref}, $rep;
            } else {
                return undef;
            }
        } elsif ($should_update->{'existing_key_correct'}) {
            Log::do_log('debug',
                "Existing key correct (%s) nothing to change",
                $key_as_string);
        } else {
            ## drop previous primary key
            my $rep = undef;
            if (    $may_update
                and $rep = $sdm->unset_primary_key({'table' => $t})) {
                push @{$report_ref}, $rep;
            } else {
                return undef;
            }
            ## Add primary key
            $rep = undef;
            if ($may_update
                and $rep = $sdm->set_primary_key(
                    {'table' => $t, 'fields' => $primary{$t}}
                )
                ) {
                push @{$report_ref}, $rep;
            } else {
                return undef;
            }
        }
    } else {
        Log::do_log('err', 'Unable to evaluate table %s primary key', $t);
        return undef;
    }
    return 1;
}

sub _check_indexes {
    my $sdm        = shift;
    my $param      = shift;
    my $t          = $param->{'table'};
    my $report_ref = $param->{'report'};
    my $may_update = $param->{'may_update'};
    Log::do_log('debug', 'Checking indexes for table %s', $t);

    ## drop previous index if this index is not a primary key and was defined
    ## by a previous Sympa version
    my %index_columns = %{$sdm->get_indexes({'table' => $t})};
    foreach my $idx (keys %index_columns) {
        Log::do_log('debug', 'Found index %s', $idx);
        ## Remove the index if obsolete.
        foreach my $known_index (@former_indexes) {
            if ($idx eq $known_index) {
                my $rep;
                Log::do_log('notice', 'Removing obsolete index %s', $idx);
                if (    $may_update
                    and $rep =
                    $sdm->unset_index({'table' => $t, 'index' => $idx})) {
                    push @{$report_ref}, $rep;
                }
                last;
            }
        }
    }

    ## Create required indexes
    foreach my $idx (keys %{$indexes{$t}}) {
        ## Add indexes
        unless ($index_columns{$idx}) {
            my $rep;
            Log::do_log('notice',
                'Index %s on table %s does not exist. Adding it',
                $idx, $t);
            if ($may_update
                and $rep = $sdm->set_index(
                    {   'table'      => $t,
                        'index_name' => $idx,
                        'fields'     => $indexes{$t}{$idx}
                    }
                )
                ) {
                push @{$report_ref}, $rep;
            }
        }
        my $index_check = _check_key(
            $sdm,
            {   'table'         => $t,
                'key_name'      => $idx,
                'expected_keys' => $indexes{$t}{$idx}
            }
        );
        if ($index_check) {
            my $list_of_fields = join ',', @{$indexes{$t}{$idx}};
            my $index_as_string = "$idx: $t [$list_of_fields]";
            if ($index_check->{'empty'}) {
                ## Add index
                my $rep = undef;
                Log::do_log('notice', 'Index %s is missing. Adding it',
                    $index_as_string);
                if ($may_update
                    and $rep = $sdm->set_index(
                        {   'table'      => $t,
                            'index_name' => $idx,
                            'fields'     => $indexes{$t}{$idx}
                        }
                    )
                    ) {
                    push @{$report_ref}, $rep;
                } else {
                    return undef;
                }
            } elsif ($index_check->{'existing_key_correct'}) {
                Log::do_log('debug',
                    "Existing index correct (%s) nothing to change",
                    $index_as_string);
            } else {
                ## drop previous index
                Log::do_log('notice',
                    'Index %s has not the right structure. Changing it',
                    $index_as_string);
                my $rep = undef;
                if (    $may_update
                    and $rep =
                    $sdm->unset_index({'table' => $t, 'index' => $idx})) {
                    push @{$report_ref}, $rep;
                }
                ## Add index
                $rep = undef;
                if ($may_update
                    and $rep = $sdm->set_index(
                        {   'table'      => $t,
                            'index_name' => $idx,
                            'fields'     => $indexes{$t}{$idx}
                        }
                    )
                    ) {
                    push @{$report_ref}, $rep;
                } else {
                    return undef;
                }
            }
        } else {
            Log::do_log('err', 'Unable to evaluate index %s in table %s',
                $idx, $t);
            return undef;
        }
    }
    return 1;
}

# Checks the compliance of a key of a table compared to what it is supposed to
# reference.
#
# IN: A ref to hash containing the following keys:
# * 'table' : the name of the table for which we want to check the primary key
# * 'key_name' : the kind of key tested:
#   - if the value is 'primary', the key tested will be the table primary key
#   - for any other value, the index whose name is this value will be tested.
# * 'expected_keys' : A ref to an array containing the list of fields that we
#   expect to be part of the key.
#
# OUT: - Returns a ref likely to contain the following values:
# * 'empty': if this key is defined, then no key was found for the table
# * 'existing_key_correct': if this key's value is 1, then a key
#   exists and is fair to the structure defined in the 'expected_keys'
#   parameter hash.
#   Otherwise, the key is not correct.
# * 'missing_key': if this key is defined, then a part of the key was missing.
#   The value associated to this key is a hash whose keys are the names
#   of the fields missing in the key.
# * 'unexpected_key': if this key is defined, then we found fields in the
#   actual key that don't belong to the list provided in the 'expected_keys'
#   parameter hash.
#   The value associated to this key is a hash whose keys are the names of the
#   fields unexpectedely found.
sub _check_key {
    my $sdm   = shift;
    my $param = shift;
    Log::do_log('debug', 'Checking %s key structure for table %s',
        $param->{'key_name'}, $param->{'table'});
    my $keysFound;
    my $result;
    if (lc($param->{'key_name'}) eq 'primary') {
        return undef
            unless ($keysFound =
            $sdm->get_primary_key({'table' => $param->{'table'}}));
    } else {
        return undef
            unless ($keysFound =
            $sdm->get_indexes({'table' => $param->{'table'}}));
        $keysFound = $keysFound->{$param->{'key_name'}};
    }

    my @keys_list = keys %{$keysFound};
    if ($#keys_list < 0) {
        $result->{'empty'} = 1;
    } else {
        $result->{'existing_key_correct'} = 1;
        my %expected_keys;
        foreach my $expected_field (@{$param->{'expected_keys'}}) {
            $expected_keys{$expected_field} = 1;
        }
        foreach my $field (@{$param->{'expected_keys'}}) {
            unless ($keysFound->{$field}) {
                Log::do_log('info',
                    'Table %s: Missing expected key part %s in %s key',
                    $param->{'table'}, $field, $param->{'key_name'});
                $result->{'missing_key'}{$field} = 1;
                $result->{'existing_key_correct'} = 0;
            }
        }
        foreach my $field (keys %{$keysFound}) {
            unless ($expected_keys{$field}) {
                Log::do_log('info',
                    'Table %s: Found unexpected key part %s in %s key',
                    $param->{'table'}, $field, $param->{'key_name'});
                $result->{'unexpected_key'}{$field} = 1;
                $result->{'existing_key_correct'} = 0;
            }
        }
    }
    return $result;
}

## Compare required DB field type
## Input : required_format, effective_format
## Output : return 1 if field type is appropriate AND size >= required size
sub _check_db_field_type {
    my %param = @_;

    my ($required_type, $required_size, $effective_type, $effective_size);

    if ($param{'required_format'} =~ /^(\w+)(\((\d+)\))?$/) {
        ($required_type, $required_size) = ($1, $3);
    }

    if ($param{'effective_format'} =~ /^(\w+)(\((\d+)\))?$/) {
        ($effective_type, $effective_size) = ($1, $3);
    }

    if (Sympa::Tools::Data::smart_eq($effective_type, $required_type)
        and (not defined $required_size or $effective_size >= $required_size))
    {
        return 1;
    }

    return 0;
}

1;

=encoding utf-8

=head1 NAME

Sympa::DatabaseManager - Managing schema of Sympa core database

=head1 SYNOPSIS

  use Sympa::DatabaseManager;
  
  $sdm = Sympa::DatabaseManager->instance or die 'Cannot connect to database';

  Sympa::DatabaseManager::probe_db() or die 'Database is not up-to-date';

=head1 DESCRIPTION

L<Sympa::DatabaseManager> provides functions to manage schema of Sympa core
database.

=head2 Constructor

=over

=item instance ( )

I<Constructor>.
Gets singleton instance of Sympa::Database class managing Sympa core database.

=back

=head2 Function

=over

=item probe_db ( )

I<Function>.
TBD.

=back

=head1 SEE ALSO

L<Sympa::Database>, L<Sympa::DatabaseDriver>.

=head1 HISTORY

Sympa Database Manager appeared on Sympa 6.2.

=cut
