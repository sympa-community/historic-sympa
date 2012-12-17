# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:wrap:textwidth=78
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

Sympa::Configuration::XML - XML configuration file handling

=head1 DESCRIPTION

This class implements an XML configuration file parser.

=cut

package Sympa::Configuration::XML;

use strict;

use XML::LibXML;

use Sympa::Log;

=head1 CLASS METHODS

=head2 Sympa::Configuration::XML->new($handle)

Creates a new L<Sympa::Configuration::XML> object.

=head3 Parameters

=over

=item * I<$handle>: file handler on the xml file 

=back

=head3 Return

A new L<Sympa::Configuration::XML> object, or I<undef>, if something went wrong.

=cut

sub new {
    my $class = shift;
    my $fh = shift;
    &Sympa::Log::do_log('debug2','()');
    
    my $self = {};
    my $parser = XML::LibXML->new();
    $parser->line_numbers(1);
    my $doc = $parser->parse_fh($fh);
    
    $self->{'root'} = $doc->documentElement();
    
    bless $self, $class;
    return $self;
}


################################################
# createHash                                   
################################################
# Create a hash used to create a list. Check 
#  elements unicity when their are not 
#  declared multiple
#
# IN : -$self
# OUT : -1 or undef
################################################
sub createHash {
    my $self = shift;
    &Sympa::Log::do_log('debug2','()');

    unless ($self->{'root'}->nodeName eq 'list') {
	&Sympa::Log::do_log('err',"the root element must be called \"list\" ");
	return undef;
    }

    unless (defined $self->_getRequiredElements()){
	&Sympa::Log::do_log('err',"error in required elements ");
	return undef;
    }
    
    if ($self->{'root'}->hasChildNodes()) {
	my $hash = &_getChildren($self->{'root'});
	unless (defined $hash){
	    &Sympa::Log::do_log('err',"error in list elements ");
	    return undef;
	}
	if (ref($hash) eq "HASH") {
	    foreach my $k (keys %$hash) {
		if ($k eq "type") { ## the list template creation without family context
		    $self->{'type'} = $hash->{'type'};  
		}else {
		    $self->{'config'}{$k} = $hash->{$k};
		}
	    }
	}elsif ($hash ne "") { # a string
	    &Sympa::Log::do_log('err','the list\'s children are not homogeneous');
	    return undef;
	}
    }
    return 1;
}


#########################################
# getHash                                 
#########################################
# return the hash structure containing :
#   type, config
#
# IN  : -$self
# OUT : -$hash
#########################################
sub getHash {
    my $self = shift;
    &Sympa::Log::do_log('debug2','()');

    my $hash = {};

    $hash->{'type'} = $self->{'type'} if (defined $self->{'type'}); ## the list template creation without family context
    $hash->{'config'} = $self->{'config'}; 
  
    return $hash;
}


############################# PRIVATE METHODS ##############################


#################################################################
# _getRequiredElements                                 
#################################################################
# get all obligatory elements and store them :
#  single : listname 
# remove it in order to the later recursive call
#
# IN : -$self
# OUT : -1 or undef
#################################################################
sub _getRequiredElements {
    my $self = shift;
    &Sympa::Log::do_log('debug3','()');

    # listname element is obligatory
    unless ($self->_getRequiredSingle('listname')){
	return undef;
    }
    return 1;
}


####################################################
# _getMultipleAndRequiredChild  : no used anymore                          
####################################################
# get all nodes with name $nodeName and check if
#  they contain the child $childName and store them
#
# IN : -$self
#      -$nodeName 
#      -$childName 
# OUT : - the number of node with the name $nodeName
####################################################
sub _getMultipleAndRequiredChild {
    my $self = shift;
    my $nodeName = shift;
    my $childName = shift;
    &Sympa::Log::do_log('debug3','(%s,%s)',$nodeName,$childName);

    my @nodes = $self->{'root'}->getChildrenByTagName($nodeName);

    unless (defined &_verify_single_nodes(\@nodes)) {
	return undef;
    }

    foreach my $o (@nodes) {
	my @child = $o->getChildrenByTagName($childName);
	if ($#child < 0){
	    &Sympa::Log::do_log('err','Element "%s" is required for element "%s", line : %s',$childName,$nodeName,$o->line_number());
	    return undef;
	}
	
	my $hash = &_getChildren($o);	    
	unless (defined $hash) {
	     &Sympa::Log::do_log('err','error on _getChildren(%s) ',$o->nodeName);
	     return undef;
	 } 
	    
	push @{$self->{'config'}{$nodeName}},$hash;
	$self->{'root'}->removeChild($o);
    }
    return ($#nodes + 1);
}


############################################
# _getRequiredSingle                                
############################################
# get the node with name $nodeName and check 
#  its unicity and store it
#
# IN : -$self
#      -$nodeName
# OUT : -1 or undef
############################################
sub _getRequiredSingle {
    my $self = shift;
    my $nodeName = shift;
    &Sympa::Log::do_log('debug3','(%s)',$nodeName);

    my @nodes = $self->{'root'}->getChildrenByTagName($nodeName);
 
    unless (&_verify_single_nodes(\@nodes)) {
	return undef;
    }

    if ($#nodes <0) {
	&Sympa::Log::do_log('err','Element "%s" is required for the list ',$nodeName);
	return undef;
    }
	
    if ($#nodes > 0) {
	my @error;
	foreach my $i (@nodes) {
	    push (@error,$i->line_number());    
	}
	&Sympa::Log::do_log('err','Only one element "%s" is allowed for the list, lines : %s',$nodeName,join(", ",@error));
	return undef;
    }

    my $node = shift(@nodes);
    
    if ($node->getAttribute('multiple')){
	&Sympa::Log::do_log('err','Attribute multiple=1 not allowed for the element "%s"',$nodeName);
	return undef;
    }
    
    if ($nodeName eq "type") {## the list template creation without family context

	my $value = $node->textContent;
	$value =~ s/^\s*//;
	$value =~ s/\s*$//;
	$self->{$nodeName} = $value;
    
    }else {
	my $values = &_getChildren($node);
	unless (defined $values) {
	     &Sympa::Log::do_log('err','error on _getChildren(%s) ',$node->nodeName);
	     return undef;
	 } 

	if (ref($values) eq "HASH") {
	    foreach my $k (keys %$values) {
		$self->{'config'}{$nodeName}{$k} = $values->{$k};
	    }
	}else {
	    $self->{'config'}{$nodeName} = $values;
	}   
    }	
    
    $self->{'root'}->removeChild($node);
    return 1;
}


##############################################
# _getChildren                                   
##############################################
# get $node's children (elements, text, 
# cdata section) and their values
#  it is a recursive call
# 
# IN :  -$node 
# OUT : -$hash : hash of children and 
#         their contents if elements
#        or
#        $string : value of cdata section 
#         or of text content
##############################################
sub _getChildren {
    my $node = shift;
    &Sympa::Log::do_log('debug3','(%s)',$node->nodeName);

    ## return value
    my $hash = {};
    my $string = "";
    my $return = "empty"; # "hash", "string", "empty"
    
    my $error = 0; # children not homogeneous
    my $multiple_nodes = {};

    my @nodeList = $node->childNodes();

    unless (&_verify_single_nodes(\@nodeList)) {
	return undef;
    }

    foreach my $child (@nodeList) {
	my $type = $child->nodeType;
	my $childName = $child->nodeName; 

        # ELEMENT_NODE
	if ($type == 1) {
	    my $values = &_getChildren($child);
	    unless (defined $values) {
		&Sympa::Log::do_log('err','error on _getChildren(%s)',$childName);
		return undef;
	    } 
	    
	    ## multiple 
	    if ($child->getAttribute('multiple')){
		push @{$multiple_nodes->{$childName}},$values;

	    ## single	
	    }else {
		if (ref($values) eq "HASH") {
		    foreach my $k (keys %$values) {
			$hash->{$childName}{$k} = $values->{$k};
		    }
		}else {
		    $hash->{$childName} = $values;
		}
	    }
	    
	    if ($return eq "string") {
		$error = 1;
	    }
	    $return = "hash";
	    
	# TEXT_NODE
	}elsif ($type == 3) {
	    my $value = Encode::encode_utf8($child->nodeValue);
	    $value =~ s/^\s+//;
	    unless ($value eq "") {
		$string = $string.$value;
		if ($return eq "hash") {
		    $error = 1;
		}
		$return = "string";
	    }


	# CDATA_SECTION_NODE
	}elsif ($type == 4) { 
	    $string = $string . Encode::encode_utf8($child->nodeValue);
	    if ($return eq "hash") {
		$error = 1;
	    }
	    $return = "string";
	}
	
	## error
	if ($error) {
	    &Sympa::Log::do_log('err','(%s): the children are not homogeneous, line %s',$node->nodeName,$node->line_number());
	    return undef;
	}
    }

    ## return
    foreach my $array (keys %$multiple_nodes){
	$hash->{$array} = $multiple_nodes->{$array};
    }

    if ($return eq "hash") {
	return $hash;
    } elsif ($return eq "string") {
	$string =~ s/^\s*//;
	$string =~ s/\s*$//;
	return $string;
    } else { # "empty"
	return "";
    }
}


##################################################
# _verify_single_nodes                        
##################################################
# check the uniqueness(in a node list) for a node not 
#  declared  multiple.
# (no attribute multiple = "1") 
# 
# IN :  -$nodeList : ref on the array of nodes
# OUT : -1 or undef
##################################################
sub _verify_single_nodes {
    my $nodeList = shift;
    &Sympa::Log::do_log('debug3','()');
    
    my $error = 0;
    my %error_nodes;
    my $nodeLines = &_find_lines($nodeList);

    foreach my $node (@$nodeList) {
	if ($node->nodeType == 1) { # ELEMENT_NODE
	    unless ($node->getAttribute("multiple")) {
		my $name = $node->nodeName;
		if ($#{$nodeLines->{$name}} > 0) {
		    $error_nodes{$name} = 1; 
		}
	    }
	}
    }
    foreach my $node (keys %error_nodes) {
	my $lines = join ', ',@{$nodeLines->{$node}};
	&Sympa::Log::do_log('err','Element %s is not declared in multiple but it is : lines %s',$node,$lines);
	$error = 1;
    }

    if ($error) {
	return undef;
    }
    return 1;
}


###############################################
# _find_lines                             
###############################################
# make a hash : keys are node names, values 
#  are arrays of their line occurrences 
#  
# IN  : - $nodeList : ref on a array of nodes
# OUT : - $hash : ref on the hash defined
###############################################
sub _find_lines {
    my $nodeList = shift;
    &Sympa::Log::do_log('debug3','()');
    my $hash = {};

    foreach my $node (@$nodeList) {
	if ($node->nodeType == 1){ # ELEMENT_NODE
	    push @{$hash->{$node->nodeName}},$node->line_number();
	}
    }
    return $hash;
}

 
######################################################
1;
