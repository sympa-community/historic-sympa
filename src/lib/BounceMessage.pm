# BounceMessage.pm - This module includes specialized sub to handle bounce messages.

package BounceMessage;

use strict;
use Message;
use Log;

our @ISA = qw(Message);

## Creates a new object
sub new {
    
    my $pkg =shift;
    my $datas = shift;
	my $self;
    return undef unless ($self = new Message($datas));
    unless ($self->get_message_as_string) {
		Log::do_log ('notice',"Ignoring bounce where %s  because it is empty",$self->{'messagekey'});
		return undef;
    }
    bless $self,$pkg;
    return $self;
}

