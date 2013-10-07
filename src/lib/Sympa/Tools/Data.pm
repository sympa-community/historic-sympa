# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:et:sw=4:textwidth=78
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

=encoding utf-8

=head1 NAME

Sympa::Tools::Data - Datastructures-related functions

=head1 DESCRIPTION

This module provides various functions for managing data structures.

=cut

package Sympa::Tools::Data;

use strict;

use English qw(-no_match_vars);
use POSIX qw();

=head1 FUNCTIONS

=over

=item recursive_transformation($var, $subref)

This applies recursively to a data structure. The transformation subroutine is
passed as a ref.

=cut

sub recursive_transformation {
    my ($var, $subref) = @_;

    return unless (ref($var));

    if (ref($var) eq 'ARRAY') {
        foreach my $index (0..$#{$var}) {
            if (ref($var->[$index])) {
                recursive_transformation($var->[$index], $subref);
            } else {
                $var->[$index] = &{$subref}($var->[$index]);
            }
        }
    } elsif (ref($var) eq 'HASH') {
        foreach my $key (sort keys %{$var}) {
            if (ref($var->{$key})) {
                recursive_transformation($var->{$key}, $subref);
            } else {
                $var->{$key} = &{$subref}($var->{$key});
            }
        }
    }

    return;
}

=item dump_var($var, $level, $fd)

Dump a variable's content

=cut

sub dump_var {
    my ($var, $level, $fd) = @_;

    return undef unless ($fd);

    if (ref($var)) {
        if (ref($var) eq 'ARRAY') {
            foreach my $index (0..$#{$var}) {
                print $fd "\t"x$level.$index."\n";
                dump_var($var->[$index], $level+1, $fd);
            }
        } elsif (ref($var) eq 'HASH' || $var->isa('Sympa::Scenario') || $var->isa('Sympa::List') || $var->isa('CGI::Fast')) {
            foreach my $key (sort keys %{$var}) {
                print $fd "\t"x$level.'_'.$key.'_'."\n";
                dump_var($var->{$key}, $level+1, $fd);
            }
        } else {
            printf $fd "\t"x$level."'%s'"."\n", ref($var);
        }
    } else {
        if (defined $var) {
            print $fd "\t"x$level."'$var'"."\n";
        } else {
            print $fd "\t"x$level."UNDEF\n";
        }
    }
}

=item dump_html_var($var)

Dump a variable's content

=cut

sub dump_html_var {
    my ($var) = @_;

    my $html = '';


    if (ref($var)) {

        if (ref($var) eq 'ARRAY') {
            $html .= '<ul>';
            foreach my $index (0..$#{$var}) {
                $html .= '<li> '.$index.':';
                $html .= dump_html_var($var->[$index]);
                $html .= '</li>';
            }
            $html .= '</ul>';
        } elsif (ref($var) eq 'HASH' || $var->isa('Sympa::Scenario') || $var->isa('Sympa::List')) {
            $html .= '<ul>';
            foreach my $key (sort keys %{$var}) {
                $html .= '<li>'.$key.'=';
                $html .=  dump_html_var($var->{$key});
                $html .= '</li>';
            }
            $html .= '</ul>';
        } else {
            $html .= 'EEEEEEEEEEEEEEEEEEEEE'.ref($var);
        }
    } else {
        if (defined $var) {
            $html .= escape_html($var);
        } else {
            $html .= 'UNDEF';
        }
    }
    return $html;
}

=item dup_var($var)

Duplicate a complex variable

=cut

sub dup_var {
    my ($var) = @_;

    if (ref($var)) {
        if (ref($var) eq 'ARRAY') {
            my $new_var = [];
            foreach my $index (0..$#{$var}) {
                $new_var->[$index] = dup_var($var->[$index]);
            }
            return $new_var;
        } elsif (ref($var) eq 'HASH') {
            my $new_var = {};
            foreach my $key (sort keys %{$var}) {
                $new_var->{$key} = dup_var($var->{$key});
            }
            return $new_var;
        }
    }

    return $var;
}

sub remove_empty_entries {
    my ($var) = @_;    
    my $not_empty = 0;

    if (ref($var)) {
        if (ref($var) eq 'ARRAY') {
            foreach my $index (0..$#{$var}) {
                my $status = &remove_empty_entries($var->[$index]);
                $var->[$index] = undef unless ($status);
                $not_empty ||= $status
            }	    
        } elsif (ref($var) eq 'HASH') {
            foreach my $key (sort keys %{$var}) {
                my $status = &remove_empty_entries($var->{$key});
                $var->{$key} = undef unless ($status);
                $not_empty ||= $status;
            }    
        }
    } else {
        if (defined $var && $var) {
            $not_empty = 1
        }
    }

    return $not_empty;
}

=item get_array_from_splitted_string($string)

return an array made on a string splited by ','.
It removes spaces.

=cut

sub get_array_from_splitted_string {
    my ($string) = @_;

    my @array;

    foreach my $word (split /,/,$string) {
        $word =~ s/^\s+//;
        $word =~ s/\s+$//;
        push @array, $word;
    }

    return \@array;
}

=item diff_on_arrays($a, $b)

Makes set operation on arrays (seen as set, with no double).

Parameters:

=over

=item arrayref

The first set.

=item arrayref

The second set.

=back

Return value:

An hashref with following keys:

=over

=item * I<deleted>

=item * I<added>

=item * I<intersection>

=item * I<union>

=back

=cut

sub diff_on_arrays {
    my ($setA, $setB) = @_;

    my $result = {'intersection' => [],
        'union' => [],
        'added' => [],
        'deleted' => []};
    my %deleted;
    my %added;
    my %intersection;
    my %union;

    my %hashA;
    my %hashB;

    foreach my $eltA (@$setA) {
        $hashA{$eltA} = 1;
        $deleted{$eltA} = 1;
        $union{$eltA} = 1;
    }

    foreach my $eltB (@$setB) {
        $hashB{$eltB} = 1;
        $added{$eltB} = 1;

        if ($hashA{$eltB}) {
            $intersection{$eltB} = 1;
            $deleted{$eltB} = 0;
        } else {
            $union{$eltB} = 1;
        }
    }

    foreach my $eltA (@$setA) {
        if ($hashB{$eltA}) {
            $added{$eltA} = 0;
        }
    }

    foreach my $elt (keys %deleted) {
        next unless $elt;
        push @{$result->{'deleted'}},$elt if ($deleted{$elt});
    }
    foreach my $elt (keys %added) {
        next unless $elt;
        push @{$result->{'added'}},$elt if ($added{$elt});
    }
    foreach my $elt (keys %intersection) {
        next unless $elt;
        push @{$result->{'intersection'}},$elt if ($intersection{$elt});
    }
    foreach my $elt (keys %union) {
        next unless $elt;
        push @{$result->{'union'}},$elt if ($union{$elt});
    }

    return $result;

}

=item is_in_array($set, $value)

Returns a true value if value I<$value> if part of set I<$set>

=cut

sub is_in_array {
    my ($set, $value) = @_;

    foreach my $elt (@$set) {
        return 1 if ($elt eq $value);
    }
    return undef;
}

=item string_2_hash($string)

convert a string formated as var1="value1";var2="value2"; into a hash.
Used when extracting from session table some session properties or when
extracting users preference from user table.
Current encoding is NOT compatible with encoding of values with '"'

=cut

sub string_2_hash {
    my ($data) = @_;

    my %hash;

    pos($data) = 0;
    while ($data =~ /\G;?(\w+)\=\"((\\[\"\\]|[^\"])*)\"(?=(;|\z))/g) {
        my ($var, $val) = ($1, $2);
        $val =~ s/\\([\"\\])/$1/g;
        $hash{$var} = $val;
    }

    return (%hash);

}

=item hash_2_string($hash)

Convert a hash into a string formated as var1="value1";var2="value2"; into a
hash

=cut

sub hash_2_string {
    my ($refhash) = @_;

    return undef unless ((ref($refhash))&& (ref($refhash) eq 'HASH'));

    my $data_string;
    foreach my $var (keys %$refhash ) {
        next unless ($var);
        my $val = $refhash->{$var};
        $val =~ s/([\"\\])/\\$1/g;
        $data_string .= ';'.$var.'="'.$val.'"';
    }
    return ($data_string);
}

=item smart_lessthan($a, $b)

compare 2 scalars, string/numeric independent

=cut

sub smart_lessthan {
    my ($stra, $strb) = @_;

    $stra =~ s/^\s+//; $stra =~ s/\s+$//;
    $strb =~ s/^\s+//; $strb =~ s/\s+$//;
    $ERRNO = 0;
    my(undef, $unparsed) = POSIX::strtod($stra);
    my $numb;
    $numb = POSIX::strtod($strb)
    unless ($ERRNO || $unparsed !=0);
    if (($stra eq '') || ($strb eq '') || ($unparsed != 0) || $ERRNO) {
        return $stra lt $strb;
    } else {
        return $stra < $strb;
    }
}

=item any {} @list

Returns a true value if any item in @list meets the criterion given through
code block.

Shamelessly imported from Sympa::List::MoreUtils to avoid a dependency.

=cut

sub any (&@) { ## no critic (SubroutinePrototypes)
    my $f = shift;
    foreach ( @_ ) {
        return 1 if $f->();
    }
    return 0;
}

=back

=cut

1;
