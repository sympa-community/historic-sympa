
package User;

use strict;
use Exporter;

use Auth;

## Database and SQL statement handlers
my ($sth, @sth_stack);

## DB fields with numeric type
## We should not do quote() for these while inserting data
my %numeric_field = ('cookie_delay_user' => 1,
                     'bounce_score_subscriber' => 1,
                     'subscribed_subscriber' => 1,
                     'included_subscriber' => 1,
                     'subscribed_admin' => 1,
                     'included_admin' => 1,
                     'wrong_login_count' => 1,
    );

=head2 CONSTRUCTOR

=over 4

=item new ( EMAIL, [ KEY => VAL, ... ] )

XXX @todo doc

=back

=cut

sub new {
    my $pkg = shift;
    my $who = tools::clean_email(shift || '');
    my %values = @_;
    my $self;
    return undef unless $who;

    if (! ($self = get_global_user($who))) {
	## unauthenticated user would not be added to database.
	if (scalar grep { $_ ne 'lang' and $_ ne 'email' } keys %values) {
	    $values{'email'} = $who;
	    add_global_user(\%values);
	}
	$self = \%values;
    }

    bless $self => $pkg;
}

=head2 METHODS

=over 4

=item del

XXX

=back

=cut

sub expire {
    croak()
}

=over 4

=item save

XXX

=back

=cut

sub save {
    croak()
}

=head3 ACCESSORS

=over 4

...

=back

=cut



=head2 FUNCTIONS

=over 4

=item get_users ( ... )

=back

=cut

sub get_users {
    croak()
}

############################################################################
## Old-style functions
############################################################################

## Delete a user in the user_table
sub delete_global_user {
    my @users = @_;
    
    &Log::do_log('debug2', '');
    
    return undef unless ($#users >= 0);
    
    foreach my $who (@users) {
	$who = &tools::clean_email($who);
	## Update field
	
	unless (&SDM::do_query("DELETE FROM user_table WHERE (email_user =%s)", &SDM::quote($who))) {
	    &Log::do_log('err','Unable to delete user %s', $who);
	    next;
	}
    }

    return $#users + 1;
}


## Returns a hash for a given user
sub get_global_user {
    &Log::do_log('debug2', '(%s)', @_);
    my $who = &tools::clean_email(shift);

    ## Additional subscriber fields
    my $additional = '';
    if ($Conf::Conf{'db_additional_user_fields'}) {
	$additional = ', ' . $Conf::Conf{'db_additional_user_fields'};
    }

    push @sth_stack, $sth;

    unless ($sth = &SDM::do_prepared_query(sprintf('SELECT email_user AS email, gecos_user AS gecos, password_user AS password, cookie_delay_user AS cookie_delay, lang_user AS lang, attributes_user AS attributes, data_user AS data, last_login_date_user AS last_login_date, wrong_login_count_user AS wrong_login_count, last_login_host_user AS last_login_host%s FROM user_table WHERE email_user = ?',
						   $additional),
					   $who)) {
	&Log::do_log('err', 'Failed to prepare SQL query');
	$sth = pop @sth_stack;
	return undef;
    }

    my $user = $sth->fetchrow_hashref('NAME_lc');
    $sth->finish();

    $sth = pop @sth_stack;

    if (defined $user) {
	## decrypt password
	if ($user->{'password'}) {
	    $user->{'password'} = &tools::decrypt_password($user->{'password'});
	}

	## Turn user_attributes into a hash
	my $attributes = $user->{'attributes'};
	$user->{'attributes'} = undef;
	foreach my $attr (split (/\;/, $attributes)) {
	    my ($key, $value) = split (/\=/, $attr);
	    $user->{'attributes'}{$key} = $value;
	}    
	## Turn data_user into a hash
	 if ($user->{'data'}) {
	     my %prefs = &tools::string_2_hash($user->{'data'});
	     $user->{'prefs'} = \%prefs;
	 }
    }

    return $user;
}

## Returns an array of all users in User table hash for a given user
sub get_all_global_user {
    &Log::do_log('debug2', '()');

    my @users;

    push @sth_stack, $sth;

    unless ($sth = &SDM::do_prepared_query('SELECT email_user FROM user_table')) {
	&Log::do_log('err','Unable to gather all users in DB');
	$sth = pop @sth_stack;
	return undef;
    }

    while (my $email = ($sth->fetchrow_array)[0]) {
	push @users, $email;
    }
    $sth->finish();

    $sth = pop @sth_stack;

    return @users;
}

## Is the person in user table (db only)
sub is_global_user {
   my $who = &tools::clean_email(pop);
   &Log::do_log('debug3', '(%s)', $who);

   return undef unless ($who);
   
   push @sth_stack, $sth;

   ## Query the Database
   unless($sth = &SDM::do_query("SELECT count(*) FROM user_table WHERE email_user = %s", &SDM::quote($who))) {
	&Log::do_log('err','Unable to check whether user %s is in the user table.');
	$sth = pop @sth_stack;
	return undef;
   }
   
   my $is_user = $sth->fetchrow();
   $sth->finish();
   
   $sth = pop @sth_stack;

   return $is_user;
}

## Sets new values for the given user in the Database
sub update_global_user {
    my($who, $values) = @_;
    &Log::do_log('debug', '(%s)', $who);

    $who = &tools::clean_email($who);

    ## use md5 fingerprint to store password   
    $values->{'password'} = &Auth::password_fingerprint($values->{'password'}) if ($values->{'password'});

    my ($field, $value);
    
    my ($user, $statement, $table);
    
    ## mapping between var and field names
    my %map_field = ( gecos => 'gecos_user',
		      password => 'password_user',
		      cookie_delay => 'cookie_delay_user',
		      lang => 'lang_user',
		      attributes => 'attributes_user',
		      email => 'email_user',
		      data => 'data_user',
		      last_login_date => 'last_login_date_user',
		      last_login_host => 'last_login_host_user',
		      wrong_login_count => 'wrong_login_count_user'
		      );
    
    ## Update each table
    my @set_list;

    while (($field, $value) = each %{$values}) {
	unless ($map_field{$field}) {
	    &Log::do_log('error',"unkown field $field in map_field internal error");
	    next;
	};
	my $set;
	
	if ($numeric_field{$map_field{$field}})  {
	    $value ||= 0; ## Can't have a null value
	    $set = sprintf '%s=%s', $map_field{$field}, $value;
	}else { 
	    $set = sprintf '%s=%s', $map_field{$field}, &SDM::quote($value);
	}
	push @set_list, $set;
    }
    
    return undef unless @set_list;
    
    ## Update field

    unless ($sth = &SDM::do_query("UPDATE user_table SET %s WHERE (email_user=%s)"
	    , join(',', @set_list), &SDM::quote($who))) {
	&Log::do_log('err','Could not update informations for user %s in user_table',$who);
	return undef;
    }
    
    return 1;
}

## Adds a user to the user_table
sub add_global_user {
    my($values) = @_;
    &Log::do_log('debug2', '');

    my ($field, $value);
    my ($user, $statement, $table);
    
    ## encrypt password   
    $values->{'password'} = &Auth::password_fingerprint($values->{'password'}) if ($values->{'password'});
    
    return undef unless (my $who = &tools::clean_email($values->{'email'}));
    
    return undef if (is_global_user($who));
    
    ## mapping between var and field names
    my %map_field = ( email => 'email_user',
		      gecos => 'gecos_user',
		      custom_attribute => 'custom_attribute',
		      password => 'password_user',
		      cookie_delay => 'cookie_delay_user',
		      lang => 'lang_user',
		      attributes => 'attributes_user'
		      );
    
    ## Update each table
    my (@insert_field, @insert_value);
    while (($field, $value) = each %{$values}) {
	
	next unless ($map_field{$field});
	
	my $insert;
	if ($numeric_field{$map_field{$field}}) {
	    $value ||= 0; ## Can't have a null value
	    $insert = $value;
	}else {
	    $insert = sprintf "%s", &SDM::quote($value);
	}
	push @insert_value, $insert;
	push @insert_field, $map_field{$field}
    }
    
    unless (@insert_field) {
	&Log::do_log('err','The fields (%s) do not correspond to anything in the database',join (',',keys(%{$values})));
	return undef;
    }
    
    ## Update field
    unless($sth = &SDM::do_query("INSERT INTO user_table (%s) VALUES (%s)"
	, join(',', @insert_field), join(',', @insert_value))) {
	    &Log::do_log('err','Unable to add user %s to the DB table user_table', $values->{'email'});
	    return undef;
	}
    
    return 1;
}

###### END of the User package ######

## Packages must return true.
1;
