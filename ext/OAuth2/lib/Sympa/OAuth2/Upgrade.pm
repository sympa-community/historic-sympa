package Sympa::OAuth2::Upgrade;
use strict;
use warnings;

use Sympa::Plugin::Util qw/:functions/;

=head1 NAME 

Sympa::OAuth2::Upgrade - OAuth v2 plugin upgrade

=head1 SYNOPSIS

=head1 DESCRIPTION 

=head1 METHODS

=head2 Control

=head3 class method: upgrade

=over 4

=item * I<from> =E<gt> VERSION

=item * I<to> =E<gt> VERSION

=back

=cut

sub upgrade(%)
{   my ($self, %args) = @_;

    # no changes needed (yet)
    $args{to};
}


=head3 class method: setup OPTIONS

=cut

sub setup(%)
{    my ($self, %args) = @_;

     my $db      = $args{db} || default_db;
     my $db_type = Site->db_type;

     $create_tables{$db_type}
         or fatal "unsupported database type $db_type for ".__PACKAGE__;

     $db->do($create_tables{$db_type});
}

my %create_tables =
  ( mysql => <<'__CREATE_MYSQL'

CREATE TABLE oauth2_sessions ( 
	provider	VARCHAR(100), 
	user		VARCHAR(100), 
	session		BLOB,
	PRIMARY KEY (provider, user) 
) DEFAULT CHARACTER SET utf8;

__CREATE_MYSQL

  );

=head1 AUTHORS 

=over 4

=item * Mark Overmeer <mark AT overmeer.net >

=back 

=cut 

1;
