# SympaTransport - SOAP HTTP transport for Sympa
# RCS Identication ; $Revision: 10088 $ ; $Date: 2014-01-02 12:26:38 +0100 (jeu. 02 janv. 2014) $

package SOAP::Transport::HTTP::FCGI::Sympa;

use strict;
use vars qw(@ISA);
use SympaSession;

use SOAP::Transport::HTTP;
@ISA = qw(SOAP::Transport::HTTP::FCGI);

sub request {
    my $self = shift;

    if (my $request = $_[0]) {	
	## Select appropriate robot
	if (Site->robot_by_soap_url->{$ENV{'SERVER_NAME'}.$ENV{'SCRIPT_NAME'}}) {
	    $ENV{'SYMPA_ROBOT'} =
		Site->robot_by_soap_url->{$ENV{'SERVER_NAME'}.$ENV{'SCRIPT_NAME'}};
	    Sympa::Log::Syslog::do_log('debug2', 'Robot : %s', $ENV{'SYMPA_ROBOT'});
	} else {
	    Sympa::Log::Syslog::do_log('debug2', 'URL : %s',
		$ENV{'SERVER_NAME'}.$ENV{'SCRIPT_NAME'});
	    $ENV{'SYMPA_ROBOT'} = Site->domain;
	}

	## Empty list cache of the robot
	my $robot = Robot->new($ENV{'SYMPA_ROBOT'});
	$robot->init_list_cache();
	
	my $session;
	## Existing session or new one
	if (SympaSession::get_session_cookie($ENV{'HTTP_COOKIE'})) {
	    $session = SympaSession->new($robot,
		{'cookie' =>
		 SympaSession::get_session_cookie($ENV{'HTTP_COOKIE'})}
	    );
	} else {
	    $session = SympaSession->new($robot, {});
	    $session->store() if defined $session;
	    ## Note that id_session changes each time it is saved in the DB
	    $session->renew() if defined $session;
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
	    my $expire =
		$main::param->{'user'}{'cookie_delay'} || Site->cookie_expire;
	    my $cookie = SympaSession::soap_cookie2(
		$ENV{'SESSION_ID'}, $ENV{'SERVER_NAME'}, $expire
	    );
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
