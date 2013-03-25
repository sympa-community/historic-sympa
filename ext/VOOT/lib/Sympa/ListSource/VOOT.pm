package Sympa::ListSource::VOOT;
use base 'Sympa::ListSource';

use warnings;
use strict;

use List::Util   qw/first/;
use JSON         qw/decode_json/;
use HTTP::Status qw/HTTP_BAD_REQUEST HTTP_UNAUTHORIZED/;

=head1 NAME
Sympa::ListSource::VOOT - collect information from VOOT

=head1 SYNOPSIS

  my $source = Sympa::ListSource::VOOT->new
   ( provider => $name
   , voot     => $voot
   );

  my $source = Sympa::ListSource::VOOT->fromConfig
   ( $file
   , provider => $name
   );

=head1 DESCRIPTION
Sympa use of VOOT installations.

=head1 METHODS

=section Constructors

=c_method new OPTIONS

=requires voot M<Net::VOOT> object
=requires provider NAME
=cut

sub init($)
{   my ($self, $args) = @_;

    $self->{SLV_provider} = $args->{provider}
        or Log::fatal_err("no VOOT provider name provided for ".ref $self);

    $self->{SLV_voot}     = $args->{voot}
        or Log::fatal_err("no VOOT object provided for ".ref $self);

    $self->SUPER::init($args);
}

=c_method fromConfig FILENAME|HASH, OPTIONS
All OPTIONS are passed to M<new()> when the configuration is selected.
=requires provider NAME
=cut

sub fromConfig($%)
{   my ($class, $c, %args) = @_;

    my $provider = $args{provider}
        or Log::fatal_err("no VOOT provider name provided to load from config");

    my $info     = first {$_->{ProviderID} eq $provider} @$config;
    $info or Log::fatal_err("provider $provider not found in configuration ".
            (ref $c eq 'HASH' ? 'HASH' : $c));

#XXX MO: based on the $info, how can we decide between Net::VOOT::*
#XXX     server alternatives?

    my $voot_class = 'Net::VOOT::SURFnet';
#   my $voot_class = 'Net::VOOT::Renater';
    eval "require $voot_class"
        or Log::fatal_err("cannot load VOOT implementation $voot_class");

    my $voot = $voot_class->new(info => $info)
        or return;

    $class->new(%args, voot => $voot);
}

#---------------------------
=section Attributes
=method provider
=method voot
=cut

sub provider() {shift->{SLV_provider}}
sub voot()     {shift->{SLV_voot}}

#---------------------------
=section Actions

=method getContent URL, PARAMS
Decode the response of M<get()>.  It will trigger the flow (????) when
authenication is needed.  When successful,
=cut

sub getContent($;$)
{   my $self = shift;
    my $resp = $self->get(@_);

    return $resp->decoded_content || $resp->content
        if $resp->is_success;

    if($resp->code==HTTP_BAD_REQUEST || $resp->code==HTTP_UNAUTHORIZED)
    {    if(my $rule = $resp->header('WWW-Authenticate'))
         {   $self->triggerFlow if $rule =~ m/^OAuth /;
#XXX MO ???
         }
    }

    undef;
}

#---------------------------
=section Helpers

=c_method getProviders CONFIG
List the names of all provides.
=example
  my @names = Sympa::ListSource::VOOT->getproviders($config);
=cut

sub getProviders($)
{   my $class  = shift;
    my $config = $class->readConfig(shift);
    map $_->{'voot.ProviderID'}, @$config;
}

1;
