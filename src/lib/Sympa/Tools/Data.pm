# RCS Identication ; $Revision: 7745 $ ; $Date: 2012-10-15 18:08:04 +0200 (lun. 15 oct. 2012) $ 
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

package Sympa::Tools::Data;

use strict;

use POSIX qw();

sub recursive_transformation {
    my ($var, $subref) = @_;
    
    return unless (ref($var));

    if (ref($var) eq 'ARRAY') {
	foreach my $index (0..$#{$var}) {
	    if (ref($var->[$index])) {
		&recursive_transformation($var->[$index], $subref);
	    }else {
		$var->[$index] = &{$subref}($var->[$index]);
	    }
	}
    }elsif (ref($var) eq 'HASH') {
	foreach my $key (sort keys %{$var}) {
	    if (ref($var->{$key})) {
		&recursive_transformation($var->{$key}, $subref);
	    }else {
		$var->{$key} = &{$subref}($var->{$key});
	    }
	}    
    }
    
    return;
}

sub dump_encoding {
    my $out = shift;

    $out =~ s/./sprintf('%02x', ord($&)).' '/eg;
    return $out;
}

sub dump_var {
    my ($var, $level, $fd) = @_;

    return undef unless ($fd);

    if (ref($var)) {
	if (ref($var) eq 'ARRAY') {
	    foreach my $index (0..$#{$var}) {
		print $fd "\t"x$level.$index."\n";
		&dump_var($var->[$index], $level+1, $fd);
	    }
	}elsif (ref($var) eq 'HASH' || ref($var) eq 'Scenario' || ref($var) eq 'List' || ref($var) eq 'CGI::Fast') {
	    foreach my $key (sort keys %{$var}) {
		print $fd "\t"x$level.'_'.$key.'_'."\n";
		&dump_var($var->{$key}, $level+1, $fd);
	    }    
	}else {
	    printf $fd "\t"x$level."'%s'"."\n", ref($var);
	}
    }else {
	if (defined $var) {
	    print $fd "\t"x$level."'$var'"."\n";
	}else {
	    print $fd "\t"x$level."UNDEF\n";
	}
    }
}

sub dump_html_var {
    my ($var) = shift;
	my $html = '';

    
    if (ref($var)) {

	if (ref($var) eq 'ARRAY') {
	    $html .= '<ul>';
	    foreach my $index (0..$#{$var}) {
		$html .= '<li> '.$index.':';
		$html .= &dump_html_var($var->[$index]);
		$html .= '</li>';
	    }
	    $html .= '</ul>';
	}elsif (ref($var) eq 'HASH' || ref($var) eq 'Scenario' || ref($var) eq 'List') {
	    $html .= '<ul>';
	    foreach my $key (sort keys %{$var}) {
		$html .= '<li>'.$key.'=' ;
		$html .=  &dump_html_var($var->{$key});
		$html .= '</li>';
	    }
	    $html .= '</ul>';
	}else {
	    $html .= 'EEEEEEEEEEEEEEEEEEEEE'.ref($var);
	}
    }else{
	if (defined $var) {
	    $html .= &escape_html($var);
	}else {
	    $html .= 'UNDEF';
	}
    }
    return $html;
}

sub dump_html_var2 {
    my ($var) = shift;

    my $html = '' ;
    
    if (ref($var)) {
	if (ref($var) eq 'ARRAY') {
	    $html .= 'ARRAY <ul>';
	    foreach my $index (0..$#{$var}) {
		$html .= '<li> '.$index;
		$html .= &dump_html_var($var->[$index]);
		$html .= '</li>'
	    }
	    $html .= '</ul>';
	}elsif (ref($var) eq 'HASH' || ref($var) eq 'Scenario' || ref($var) eq 'List') {
	    #$html .= " (".ref($var).') <ul>';
	    $html .= '<ul>';
	    foreach my $key (sort keys %{$var}) {
		$html .= '<li>'.$key.'=' ;
		$html .=  &dump_html_var($var->{$key});
		$html .= '</li>'
	    }    
	    $html .= '</ul>';
	}else {
	    $html .= sprintf "<li>'%s'</li>", ref($var);
	}
    }else{
	if (defined $var) {
	    $html .= '<li>'.$var.'</li>';
	}else {
	    $html .= '<li>UNDEF</li>';
	}
    }
    return $html;
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
	}elsif (ref($var) eq 'HASH') {
	    foreach my $key (sort keys %{$var}) {
		my $status = &remove_empty_entries($var->{$key});
		$var->{$key} = undef unless ($status);
		$not_empty ||= $status;
	    }    
	}
    }else {
	if (defined $var && $var) {
	    $not_empty = 1
	}
    }
    
    return $not_empty;
}

sub dup_var {
    my ($var) = @_;    

    if (ref($var)) {
	if (ref($var) eq 'ARRAY') {
	    my $new_var = [];
	    foreach my $index (0..$#{$var}) {
		$new_var->[$index] = &dup_var($var->[$index]);
	    }	    
	    return $new_var;
	}elsif (ref($var) eq 'HASH') {
	    my $new_var = {};
	    foreach my $key (sort keys %{$var}) {
		$new_var->{$key} = &dup_var($var->{$key});
	    }    
	    return $new_var;
	}
    }
    
    return $var; 
}

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

sub diff_on_arrays {
    my ($setA,$setB) = @_;
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
	}else {
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

sub is_in_array {
    my ($set,$value) = @_;
    
    foreach my $elt (@$set) {
	return 1 if ($elt eq $value);
    }
    return undef;
}

sub higher_version {
    my ($v1, $v2) = @_;

    my @tab1 = split /\./,$v1;
    my @tab2 = split /\./,$v2;
    
    
    my $max = $#tab1;
    $max = $#tab2 if ($#tab2 > $#tab1);

    for my $i (0..$max) {
    
        if ($tab1[0] =~ /^(\d*)a$/) {
            $tab1[0] = $1 - 0.5;
        }elsif ($tab1[0] =~ /^(\d*)b$/) {
            $tab1[0] = $1 - 0.25;
        }

        if ($tab2[0] =~ /^(\d*)a$/) {
            $tab2[0] = $1 - 0.5;
        }elsif ($tab2[0] =~ /^(\d*)b$/) {
            $tab2[0] = $1 - 0.25;
        }

        if ($tab1[0] eq $tab2[0]) {
            #printf "\t%s = %s\n",$tab1[0],$tab2[0];
            shift @tab1;
            shift @tab2;
            next;
        }
        return ($tab1[0] > $tab2[0]);
    }

    return 0;
}

sub lower_version {
    my ($v1, $v2) = @_;

    my @tab1 = split /\./,$v1;
    my @tab2 = split /\./,$v2;
    
    
    my $max = $#tab1;
    $max = $#tab2 if ($#tab2 > $#tab1);

    for my $i (0..$max) {
    
        if ($tab1[0] =~ /^(\d*)a$/) {
            $tab1[0] = $1 - 0.5;
        }elsif ($tab1[0] =~ /^(\d*)b$/) {
            $tab1[0] = $1 - 0.25;
        }

        if ($tab2[0] =~ /^(\d*)a$/) {
            $tab2[0] = $1 - 0.5;
        }elsif ($tab2[0] =~ /^(\d*)b$/) {
            $tab2[0] = $1 - 0.25;
        }

        if ($tab1[0] eq $tab2[0]) {
            #printf "\t%s = %s\n",$tab1[0],$tab2[0];
            shift @tab1;
            shift @tab2;
            next;
        }
        return ($tab1[0] < $tab2[0]);
    }

    return 0;
}

sub string_2_hash {
    my $data = shift;
    my %hash ;
    
    pos($data) = 0;
    while ($data =~ /\G;?(\w+)\=\"((\\[\"\\]|[^\"])*)\"(?=(;|\z))/g) {
	my ($var, $val) = ($1, $2);
	$val =~ s/\\([\"\\])/$1/g;
	$hash{$var} = $val; 
    }    

    return (%hash);

}

sub hash_2_string { 
    my $refhash = shift;

    return undef unless ((ref($refhash))&& (ref($refhash) eq 'HASH')) ;

    my $data_string ;
    foreach my $var (keys %$refhash ) {
	next unless ($var);
	my $val = $refhash->{$var};
	$val =~ s/([\"\\])/\\$1/g;
	$data_string .= ';'.$var.'="'.$val.'"';
    }
    return ($data_string);
}

sub smart_lessthan {
    my ($stra, $strb) = @_;
    $stra =~ s/^\s+//; $stra =~ s/\s+$//;
    $strb =~ s/^\s+//; $strb =~ s/\s+$//;
    $! = 0;
    my($numa, $unparsed) = POSIX::strtod($stra);
    my $numb;
    $numb = POSIX::strtod($strb)
    	unless ($! || $unparsed !=0);
    if (($stra eq '') || ($strb eq '') || ($unparsed != 0) || $!) {
	return $stra lt $strb;
    } else {
        return $stra < $strb;
    } 
}

sub count_numbers_in_string {
    my $str = shift;
    my $count = 0;
    $count++ while $str =~ /(\d+\s+)/g;
    return $count;
}

1;
__END__
=head1 NAME

Sympa::Tools::Data - Datastructures-related functions

=head1 DESCRIPTION

This module provides various functions for managing data structures.

=head1 FUNCTIONS

=head2 recursive_transformation($var, $subref)

This applies recursively to a data structure. The transformation subroutine is
passed as a ref.

=head2 dump_encoding($out)

Dumps the value of each character of the inuput string

=head2 dump_var($var, $level, $fd)

Dump a variable's content

=head2 dump_html_var($var)

Dump a variable's content

=head2 dump_html_var2($var)

Dump a variable's content

=head2 dup_var($var)

Duplicate a complex variable

=head2 get_array_from_splitted_string($string)

return an array made on a string splited by ','.
It removes spaces.

=head2 diff_on_arrays($a, $b)

Makes set operation on arrays (seen as set, with no double).

Parameters:

=over

=item I<$a>

first set (arrayref)

=item I<$b>

second set (arrayref)

=back

Returns an hashref with following keys:

=over

=item deleted

=item added

=item intersection

=item union

=back

=head2 is_on_array($set, $value)

Returns a true value if value I<$value> if part of set I<$set>

=head2 higher_version($v1, $v2)

Compare 2 versions of Sympa

=head2 lower_version($v1, $v2)

Compare 2 versions of Sympa

=head2 string_2_hash($string)

convert a string formated as var1="value1";var2="value2"; into a hash.
Used when extracting from session table some session properties or when
extracting users preference from user table.
Current encoding is NOT compatible with encoding of values with '"'

=head2 hash_2_string($hash)

Convert a hash into a string formated as var1="value1";var2="value2"; into a
hash

=head2 smart_lessthan($a, $b)

compare 2 scalars, string/numeric independant

=head2 count_numbers_in_string($string)

Returns the counf of numbers found in the string given as argument.
