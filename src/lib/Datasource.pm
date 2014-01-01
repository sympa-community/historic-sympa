# Datasource.pm - This module includes external datasources related functions
#<!-- RCS Identication ; $Revision$ --> 

#
# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014 GIP RENATER
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

package Datasource;

use strict;

use Carp;

use Conf;
use Log;

############################################################
#  constructor
############################################################
#  Create a new datasource object. Handle SQL source only
#  at this moment. 
#  
# IN : -$type (+): the type of datasource to create
#         'SQL' or 'MAIN' for main sympa database
#      -$param_ref (+): ref to a Hash of config data
#
# OUT : instance of Datasource
#     | undef
#
##############################################################
sub new {
    my($pkg, $type, $param_ref) = @_;
    my $datasrc;
    &do_log('debug2', 'Datasource::new(%s)',$type);
    
    # import the desirable subs
    eval "use ${type}Source qw(connect query disconnect fetch ping quote set_fetch_timeout)";
    return undef if ($@);

    $datasrc->{'param'} = $param_ref;

    ## Bless Message object
    bless $datasrc, $pkg;
    return $datasrc;
}

# Returns a unique ID for an include datasource
sub _get_datasource_id {
    my ($source) = shift;
    if (ref($source) eq 'Datasource') {
    	$source = shift;
    }

    if (ref ($source)) {
	## Ordering values so that order of keys in a hash don't mess the value comparison
	## Warning: Only the first level of the hash is ordered. Should a datasource 
	## be described with a hash containing more than one level (a hash of hash) we should transform
	## the following algorithm into something that would be recursive. Unlikely it happens.
	my @orderedValues;
	foreach my $key (sort (keys %{$source})) {
	    @orderedValues = (@orderedValues,$key,$source->{$key});
	}
	return substr(Digest::MD5::md5_hex(join('/', @orderedValues)), -8);
    }else {
	return substr(Digest::MD5::md5_hex($source), -8);
    }
	
}

## Packages must return true.
1;
