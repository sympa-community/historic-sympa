# Datasource.pm - This module includes external datasources related functions
#<!-- RCS Identication ; $Revision$ --> 

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

package Datasource;

use strict;

use Carp;
use Log;
use Data::Dumper;

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
    my($pkg, $param) = @_;
    &Log::do_log('debug', '');
    my $self = $param;
    ## Bless Message object
    bless $self, $pkg;
    return $self;
}

# Returns a unique ID for an include datasource
sub _get_datasource_id {
    my ($source) = shift;
	&Log::do_log('debug2',"Getting datasource id for source '%s'",$source);
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

sub is_allowed_to_sync {
	my $self = shift;
	my $starthour = $self->{'starthour'};
	my $startminute = $self->{'startminute'};
	my $endhour = $self->{'endhour'};
	my $endminute = $self->{'endminute'};
	my @currtime = localtime(time);
	my $currhour = $currtime[2];
	my $currminute = $currtime[1];
	
	&Log::do_log('debug2',"Checking whether sync is allowed at current date");
	#test if an hour is empty
	unless ( $starthour && $endhour) {
		return 1;
	}
	unless (!$startminute || !$endminute ) {
		&Log::do_log('debug2',"Missing both start minute and end minute. Assuming their value is 0.");
		$startminute ||= 0;
		$endminute ||= 0;
	}
		

	#test if both hours are equal
	if ($starthour == $endhour) {
		# if we don't have both minute infos, we can't decide anything, as hours are equal.
		# Authorizing the sync as it is probably a config error.
		if ($startminute == $endminute) {
			return 1;
		}
		# If current hour is different from start hour, we are definitely out of the forbidden period. It's OK to sync.
		if ($starthour != $currhour) {
			return 1;
		# If current minute is between start and end minute, we are in the forbidden period. NOT OK to sync.
		}elsif ($startminute <= $currminute  && $currminute <= $endminute) {
			return 0;
		## Otherwise, we are out of the forbidden period. OK to sync.
		}else {
			return 1;
		}
	#Use case: start hour = 18, end hour = 6: the forbidden period is jumping from one day to the next
	}elsif ($starthour > $endhour) {
		# If start hour > current hour > end hour, we are sure to be out of the forbidden period. OK to sync
		if( $starthour > $currhour && $currhour > $endhour) {
			return 1;
		#if current hour is equal to starthour, we have to test startminute & endminute
		}elsif($currhour == $starthour) {
			# if current minute > start minute, we are after the beginning of the forbidden period. NOT OK to sync
			if($currminute >= $startminute) {
				return 0;
			# Otherwise, we are just before the beginning of the forbidden period. OK to sync.
			}else{
				return 1;
			}
		#if current hour is equal to endhour, we have to test startminute & endminute	
		}elsif($currhour == $endhour) {
			# if current minute <= end minute, we are before the end of the forbidden period. NOT OK to sync
			if($currminute <= $endminute) {
				return 0;
			# Otherwise, we are just after the end of the forbidden period. OK to sync.
			}else{
				return 1;
			}
		# Any other case for current hour value means that current hour > start hour and current hour < end hour
		# We are therefore in the forbidden period. NOT OK to sync.
		}else{
			return 0;
		}	
	#Use case: start hour = 6, end hour = 18: the forbidden period is during a single day
	}else{
		# if the current hour is strictly between start and end hour, we are sure to be in the forbidden period. NOT OK to sync.
		if ($starthour < $currhour && $currhour < $endhour) {
			return 0;
		#if current hour is equal to start hour, we have to do the test on startminute & endminute
		}elsif($currhour == $starthour) {
			# if current minute >= start minute, we are after the beginning of the forbidden period. NOT OK to sync.
			if($currminute >= $startminute) {
				return 0;
			# Otherwise, we are before the beginning of the forbidden period. OK to sync.
			}else{
				return 1;
			}
		#if current hour is equal to endhour, we have to do the test on startminute & endminute
		}elsif($currhour == $endhour) {
			# if current minute <= end minute, we are before the end of the forbidden period. NOT OK to sync.
			if($currminute <= $endminute) {
				return 0;
			# Otherwise, we are after the end of the forbidden period. OK to sync.
			}else{
				return 1;
			}
		# Any other case for current hour value means that current hour < start hour and current hour > end hour
		# We are therefore out of the forbidden period. OK to sync.
		}else{
			return 1;
		}
	}	
}

## Packages must return true.
1;
