# $Id$

=head1 NAME

Sympa::Transport - SOAP::Transport::HTTP::FCGI extension

=head1 DESCRIPTION

This class implements a specialized SOAP HTTP transport. 

=cut

package Sympa::Transport;

use strict;
use vars qw(@ISA);

use SOAP::Transport::HTTP;

use Sympa::Configuration;
use Sympa::List;
use Sympa::Log;
use Sympa::Session;
use Sympa::Tools::Cookie;

@ISA = qw(SOAP::Transport::HTTP::FCGI);

sub request {
    my $self = shift;
    
    
    if (my $request = $_[0]) {	
	
	## Select appropriate robot
	if ($Sympa::Configuration::Conf{'robot_by_soap_url'}{$ENV{'SERVER_NAME'}.$ENV{'SCRIPT_NAME'}}) {
	  $ENV{'SYMPA_ROBOT'} = $Sympa::Configuration::Conf{'robot_by_soap_url'}{$ENV{'SERVER_NAME'}.$ENV{'SCRIPT_NAME'}};
	  &Sympa::Log::do_log('debug2', 'Robot : %s', $ENV{'SYMPA_ROBOT'});
	}else {
	  &Sympa::Log::do_log('debug2', 'URL : %s', $ENV{'SERVER_NAME'}.$ENV{'SCRIPT_NAME'});
	  $ENV{'SYMPA_ROBOT'} =  $Sympa::Configuration::Conf{'host'} ;
	}

	## Empty cache of the List.pm module
	&Sympa::List::init_list_cache();
	
	my $session;
	## Existing session or new one
	if (&Sympa::Session::get_session_cookie($ENV{'HTTP_COOKIE'})) {
	  $session = new Sympa::Session ($ENV{'SYMPA_ROBOT'}, {'cookie'=>&Sympa::Session::get_session_cookie($ENV{'HTTP_COOKIE'})});
	}else {
	  $session = new Sympa::Session ($ENV{'SYMPA_ROBOT'},{});
	  $session->store() if (defined $session);
	  $session->renew() if (defined $session);## Note that id_session changes each time it is saved in the DB
	}

	delete $ENV{'USER_EMAIL'};	
	if (defined $session) {	  
	  $ENV{'SESSION_ID'} = $session->{'id_session'};
	  if ($session->{'email'} ne 'nobody') {
	    $ENV{'USER_EMAIL'} = $session->{'email'};
	  }
	}
    }

    $self->SUPER::request(@_);
}

sub response {
    my $self = shift;
    
    if (my $response = $_[0]) {
	if (defined $ENV{'SESSION_ID'}) {
	    my $expire = $main::param->{'user'}{'cookie_delay'} || $main::wwsconf->{'cookie_expire'};
	    my $cookie = &Sympa::Tools::Cookie::set_cookie_soap($ENV{'SESSION_ID'}, $ENV{'SERVER_NAME'}, $expire);
	
	    $response->headers->push_header('Set-Cookie2' => $cookie);
	  }
    }
    
    $self->SUPER::request(@_);
}

## Redefine FCGI's handle subroutine
sub handle ($$) {
    my $self = shift->new;
    my $birthday = shift;
    
    my ($r1, $r2);
    my $fcgirq = $self->{_fcgirq};
    
    ## If fastcgi changed on disk, die
    ## Apache will restart the process
    while (($r1 = $fcgirq->Accept()) >= 0) {	

	$r2 = $self->SOAP::Transport::HTTP::CGI::handle;

	if ((stat($ENV{'SCRIPT_FILENAME'}))[9] > $birthday ) {
	    exit(0);
	}
	#print "Set-Cookie: sympa_altemails=olivier.salaun%40cru.fr; path=/; expires=Tue , 19-Oct-2004 14 :08:19 GMT\n";
    }
    return undef;
}

1;
