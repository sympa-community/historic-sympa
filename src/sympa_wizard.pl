#!--PERL--

# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
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

sympa_wizard.pl - help perform sympa initial setup

=head1 SYNOPSIS

sympa_wizard.pl [options]

Options:

    --create <sympa.conf|wwsympa.conf> create given configuration file
    --check                            check CPAN modules
    --help                             display help

=head1 AUTHORS

=over

=item Serge Aumont <sa@cru.fr>

=item Olivier Salaün <os@cru.fr>

=back

=cut

## Change this to point to your Sympa bin directory
use lib '--LIBDIR--';

use strict;
use POSIX;
use Getopt::Long;
use Pod::Usage;
require 'tools.pl';

## Configuration

my $new_wwsympa_conf = '/tmp/wwsympa.conf';
my $new_sympa_conf = '/tmp/sympa.conf';

my $wwsconf = {};

## Change to your wwsympa.conf location
my $wwsympa_conf = "--WWSCONFIG--";
my $sympa_conf = "--CONFIG--";
my $somechange = 0;

## parameters that can be edited with this script

## Only parameters listes in @params will be saved

## This defines the parameters to be edited :
##   title  : Title for the group of parameters following
##   name   : Name of the parameter
##   file   : Conf file where the param. is defined
##   edit   : 1|0
##   query  : Description of the parameter
##   advice : Additionnal advice concerning the parameter

my @params = ({'title' => 'Directories and file location'},
    {'name' => 'home',
        'default' => '--EXPLDIR--',
        'query' => 'Directory containing mailing lists subdirectories',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'etc',
        'default' => '--ETCDIR--',
        'query' => 'Directory for configuration files ; it also contains scenari/ and templates/ directories',
        'file' => 'sympa.conf'},

    {'name' => 'pidfile',
        'default' => '--PIDDIR--/sympa.pid',
        'query' => 'File containing Sympa PID while running.',
        'file' => 'sympa.conf',
        'advice' =>'Sympa also locks this file to ensure that it is not running more than once. Caution : user sympa need to write access without special privilegee.'},

    {'name' => 'umask',
        'default' => '027',
        'query' => 'Umask used for file creation by Sympa',
        'file' => 'sympa.conf'},

    {'name' => 'archived_pidfile',
        'query' => 'File containing archived PID while running.',
        'file' => 'wwsympa.conf',
        'advice' =>''},

    {'name' => 'bounced_pidfile',
        'query' => 'File containing bounced PID while running.',
        'file' => 'wwsympa.conf',
        'advice' =>''},

    {'name' => 'task_manager_pidfile',
        'query' => 'File containing task_manager PID while running.',
        'file' => 'wwsympa.conf',
        'advice' =>''},

    {'name' => 'arc_path',
        'default' => '--prefix--/arc',
        'query' => 'Where to store HTML archives',
        'file' => 'wwsympa.conf','edit' => '1',
        'advice' =>'Better if not in a critical partition'},

    {'name' => 'bounce_path',
        'default' => '--prefix--/bounce',
        'query' => 'Where to store bounces',
        'file' => 'wwsympa.conf',
        'advice' =>'Better if not in a critical partition'},

    {'name' => 'localedir',
        'default' => '--LOCALEDIR--',
        'query' => 'Directory containing available NLS catalogues (Message internationalization)',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'spool',
        'default' => '--SPOOLDIR--',
        'query' => 'The main spool containing various specialized spools',
        'file' => 'sympa.conf',
        'advice' => 'All spool are created at runtime by sympa.pl'},

    {'name' => 'queue',
        'default' => '--SPOOLDIR--/msg',
        'query' => 'Incoming spool',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'queuebounce',
        'default' => '--SPOOLDIR--/bounce',
        'query' => 'Bounce incoming spool',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'static_content_path',
        'default' => '--prefix--/static_content',
        'query' => 'The directory where Sympa stores static contents (CSS, members pictures, documentation) directly delivered by Apache',
        'file' => 'sympa.conf',
        'advice' =>''},	      

    {'name' => 'static_content_url',
        'default' => '--prefix--/static-sympa',
        'query' => 'The URL mapped with the static_content_path directory defined above',
        'file' => 'sympa.conf',
        'advice' =>''},	      

    {'title' => 'Syslog'},

    {'name' => 'syslog',
        'default' => 'LOCAL1',
        'query' => 'The syslog facility for sympa',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'Do not forget to edit syslog.conf'},

    {'name' => 'log_socket_type',
        'default' => '--LOG_SOCKET_TYPE--',
        'query' => 'Communication mode with syslogd is either unix (via Unix sockets) or inet (use of UDP)',
        'file' => 'sympa.conf'},

    {'name' => 'log_facility',
        'query' => 'The syslog facility for wwsympa, archived and bounced',
        'file' => 'wwsympa.conf','edit' => '1',
        'advice' =>'default is to use previously defined sympa log facility'},

    {'name' => 'log_level',
        'default' => '0',
        'query' => 'Log intensity',
        'file' => 'sympa.conf',
        'advice' =>'0 : normal, 2,3,4 for debug'},

    {'title' => 'General definition'},

    {'name' => 'domain',
        'default' => '--HOST--',
        'query' => 'Main robot hostname',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'listmaster',
        'default' => 'your_email_address@--HOST--',
        'query' => 'Listmasters email list comma separated',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'Sympa will associate listmaster privileges to these email addresses (mail and web interfaces). Some error reports may also be sent to these addresses.'},

    {'name' => 'email',
        'default' => 'sympa',
        'query' => 'Local part of sympa email adresse',
        'file' => 'sympa.conf',
        'advice' =>"Effective address will be \[EMAIL\]@\[HOST\]"},

    {'name' => 'create_list',
        'default' => 'public_listmaster',
        'query' => 'Who is able to create lists',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'This parameter is a scenario, check sympa documentation about scenarios if you want to define one'},

    {'title' => 'Tuning'},


    {'name' => 'cache_list_config',
        'default' => 'none',
        'query' => 'Use of binary version of the list config structure on disk: none | binary_file',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'Set this parameter to "binary_file" if you manage a big amount of lists (1000+) ; it should make the web interface startup faster'},

    {'name' => 'sympa_priority',
        'query' => 'Sympa commands priority',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'default_list_priority',
        'query' => 'Default priority for list messages',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'cookie',
        'default' => '123456789',
        'query' => 'Secret used by Sympa to make MD5 fingerprint in web cookies secure',
        'file' => 'sympa.conf',
        'advice' =>'Should not be changed ! May invalid all user password'},

    {'name' => 'password_case',
        'query' => 'Password case (insensitive | sensitive)',
        'file' => 'wwsympa.conf',
        'advice' =>'Should not be changed ! May invalid all user password'},

    {'name' => 'cookie_expire',
        'query' => 'HTTP cookies lifetime',
        'file' => 'wwsympa.conf',
        'advice' =>''},

    {'name' => 'cookie_domain',
        'query' => 'HTTP cookies validity domain',
        'file' => 'wwsympa.conf',
        'advice' =>''},

    {'name' => 'max_size',
        'query' => 'The default maximum size (in bytes) for messages (can be re-defined for each list)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'use_blacklist',
        'query' => 'comma separated list of operation for which blacklist filter is applyed', 
        'default' => 'send,create_list',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'set this parameter to "none" hidde blacklist feature'},

    {'name'  => 'rfc2369_header_fields',
        'query' => 'Specify which rfc2369 mailing list headers to add',
        'file' => 'sympa.conf',
        'advice' => '' },


    {'name'  => 'remove_headers',
        'query' => 'Specify header fields to be removed before message distribution',
        'file' => 'sympa.conf',
        'advice' => '' },

    {'title' => 'Internationalization'},

    {'name' => 'lang',
        'default' => 'en_US',
        'query' => 'Default lang (ca | cs | de | el | es | et_EE | en_US | fr | hu | it | ja_JP | ko | nl | oc | pt_BR | ru | sv | tr | zh_CN | zh_TW)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'This is the default language used by Sympa'},

    {'name' => 'supported_lang',
        'default' => 'ca,cs,de,el,es,et_EE,en_US,fr,hu,it,ja_JP,ko,nl,oc,pt_BR,ru,sv,tr,zh_CN,zh_TW',
        'query' => 'Supported languages',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'This is the set of language that will be proposed to your users for the Sympa GUI. Don\'t select a language if you don\'t have the proper locale packages installed.'},

    {'title' => 'Errors management'},

    {'name'  => 'bounce_warn_rate',
        'sample' => '20',
        'query' => 'Bouncing email rate for warn list owner',
        'file' => 'sympa.conf','edit' => '1',
        'advice' => '' },

    {'name'  => 'bounce_halt_rate',
        'sample' => '50',
        'query' => 'Bouncing email rate for halt the list (not implemented)',
        'file' => 'sympa.conf',
        'advice' => 'Not yet used in current version, Default is 50' },


    {'name'  => 'expire_bounce_task',
        'sample' => 'daily',
        'query' => 'Task name for expiration of old bounces',
        'file' => 'sympa.conf',
        'advice' => '' },

    {'name'  => 'welcome_return_path',
        'sample' => 'unique',
        'query' => 'Welcome message return-path',
        'file' => 'sympa.conf',
        'advice' => 'If set to unique, new subcriber is removed if welcome message bounce' },

    {'name'  => 'remind_return_path',
        'query' => 'Remind message return-path',
        'file' => 'sympa.conf',
        'advice' => 'If set to unique, subcriber is removed if remind message bounce, use with care' },

    {'title' => 'MTA related'},

    {'name' => 'sendmail',
        'default' => '/usr/sbin/sendmail',
        'query' => 'Path to the MTA (sendmail, postfix, exim or qmail)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' => "should point to a sendmail-compatible binary (eg: a binary named \'sendmail\' is distributed with Postfix)"},

    {'name' => 'nrcpt',
        'default' => '25',
        'query' => 'Maximum number of recipients per call to Sendmail. The nrcpt_by_domain.conf file allows a different tuning per destination domain.',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'avg',
        'default' => '10',
        'query' => 'Max. number of different domains per call to Sendmail',
        'file' => 'sympa.conf',
        'advice' =>''},


    {'name' => 'maxsmtp',
        'default' => '40',
        'query' => 'Max. number of Sendmail processes (launched by Sympa) running simultaneously',
        'file' => 'sympa.conf',
        'advice' =>'Proposed value is quite low, you can rise it up to 100, 200 or even 300 with powerfull systems.'},

    {'title' => 'Pluggin'},

    {'name' => 'antivirus_path',
        'sample' => '/usr/local/uvscan/uvscan',
        'query' => 'Path to the antivirus scanner engine',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'supported antivirus : McAfee/uvscan, Fsecure/fsav, Sophos, AVP and Trend Micro/VirusWall'},


    {'name' => 'antivirus_args',
        'sample' => '--secure --summary --dat /usr/local/uvscan',
        'query' => 'Antivirus pluggin command argument',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'mhonarc',
        'default' => '/usr/bin/mhonarc',
        'query' => 'Path to MhOnarc mail2html pluggin',
        'file' => 'wwsympa.conf','edit' => '1',
        'advice' =>'This is required for HTML mail archiving'},

    {'title' => 'S/MIME pluggin'},
    {'name' => 'openssl',
        'sample' => '--OPENSSL--',
        'query' => 'Path to OpenSSL',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'Sympa knowns S/MIME if openssl is installed'},

    {'name' => 'capath',
        'sample' => '--ETCDIR--/ssl.crt',
        'query' => 'The directory path use by OpenSSL for trusted CA certificates',
        'file' => 'sympa.conf','edit' => '1'},

    {'name' => 'cafile',
        'sample' => '/usr/local/apache/conf/ssl.crt/ca-bundle.crt',
        'query' => ' This parameter sets the all-in-one file where you can assemble the Certificates of Certification Authorities (CA)',
        'file' => 'sympa.conf','edit' => '1'},

    {'name' => 'ssl_cert_dir',
        'default' => '--SSLCERTDIR--',
        'query' => 'User CERTs directory',
        'file' => 'sympa.conf'},

    {'name' => 'key_passwd',
        'sample' => 'your_password',
        'query' => 'Password used to crypt lists private keys',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'title' => 'Database'},

    {'name' => 'db_type',
        'default' => 'mysql',
        'query' => 'Database type (mysql | Pg | Oracle | Sybase | SQLite)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'be carefull to the case'},

    {'name' => 'db_name',
        'default' => 'sympa',
        'query' => 'Name of the database',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'with SQLite, the name of the DB corresponds to the DB file'},

    {'name' => 'db_host',
        'sample' => 'localhost',
        'query' => 'The host hosting your sympa database',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'db_port',
        'query' => 'The database port',
        'file' => 'sympa.conf',
        'advice' =>''},

    {'name' => 'db_user',
        'sample' => 'sympa',
        'query' => 'Database user for connexion',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'db_passwd',
        'sample' => 'your_passwd',
        'query' => 'Database password (associated to the db_user)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>'What ever you use a password or not, you must protect the SQL server (is it a not a public internet service ?)'},

    {'name' => 'db_env',
        'query' => 'Environment variables setting for database',
        'file' => 'sympa.conf',
        'advice' =>'This is usefull for definign ORACLE_HOME '},

    {'name'  => 'db_additional_user_fields',
        'sample' => 'age,address',
        'query' => 'Database private extention to user table',
        'file' => 'sympa.conf',
        'advice' => 'You need to extend the database format with these fields' },

    {'name'  => 'db_additional_subscriber_fields',
        'sample' => 'billing_delay,subscription_expiration',
        'query' => 'Database private extention to subscriber table',
        'file' => 'sympa.conf',
        'advice' => 'You need to extend the database format with these fields' },

    {'title' => 'Web interface'},

    {'name' => 'use_fast_cgi',
        'default' => '1',
        'query' => 'Is fast_cgi module for Apache (or Roxen) installed (0 | 1)',
        'file' => 'wwsympa.conf','edit' => '1',
        'advice' =>'This module provide much faster web interface'},

    {'name' => 'wwsympa_url',
        'default' => 'http://--HOST--/sympa',
        'query' => "Sympa\'s main page URL",
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'title',
        'default' => 'Mailing lists service',
        'query' => 'Title of main web page',
        'file' => 'wwsympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'default_home',
        'sample' => 'lists',
        'query' => 'Main page type (lists | home)',
        'file' => 'wwsympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'default_shared_quota',
        'query' => 'Default disk quota for shared repository',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'antispam_tag_header_name',
        'query' => 'If a spam filter (like spamassassin or j-chkmail) add a smtp headers to tag spams, name of this header (example X-Spam-Status)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'antispam_tag_header_spam_regexp',
        'query' => 'The regexp applied on this header to verify message is a spam (example \s*Yes)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},

    {'name' => 'antispam_tag_header_ham_regexp',
        'query' => 'The regexp applied on this header to verify message is NOT a spam (example \s*No)',
        'file' => 'sympa.conf','edit' => '1',
        'advice' =>''},


);

my %options;
GetOptions(
    \%options, 
    'create=s',
    'check',
    'help'
);

if ($options{help}) {
    pod2usage();
} elsif ($options{create}) {
    create_configuration($options{create});
} elsif ($options{check}) {
    check_cpan();
} else {
    edit_configuration();
}

exit 0;

sub create_configuration {
    my ($file) = @_;

    my $conf;
    if ($file eq 'sympa.conf') {
        $conf = $sympa_conf;
    }elsif ($file eq 'wwsympa.conf') {
        $conf = $wwsympa_conf;
    }else {
        pod2usage("$file is not a valid argument");
        exit 1;
    }

    if (-f $conf) {
        print STDERR "$conf file already exists, exiting\n";
        exit 1;
    }

    unless (open (NEWF,"> $conf")){
        die "Unable to open $conf : $!";
    };

    if ($file eq 'sympa.conf') {
        print NEWF "## Configuration file for Sympa\n## many parameters are optional (defined in src/Conf.pm)\n## refer to the documentation for a detailed list of parameters\n\n";
    }elsif ($file eq 'wwsympa.conf') {

    }

    foreach my $i (0..$#params) {

        if ($params[$i]->{'title'}) {
            printf NEWF "###\\\\\\\\ %s ////###\n\n", $params[$i]->{'title'};
            next;
        }

        next unless ($params[$i]->{'file'} eq $file);

        next unless ((defined $params[$i]->{'default'}) ||
            (defined $params[$i]->{'sample'}));

        printf NEWF "## %s\n", $params[$i]->{'query'}
        if (defined $params[$i]->{'query'});

        printf NEWF "## %s\n", $params[$i]->{'advice'}
        if ($params[$i]->{'advice'});

        printf NEWF "%s\t%s\n\n", $params[$i]->{'name'}, $params[$i]->{'default'}
        if (defined $params[$i]->{'default'});

        printf NEWF "#%s\t%s\n\n", $params[$i]->{'name'}, $params[$i]->{'sample'}
        if (defined $params[$i]->{'sample'});
    }

    close NEWF;
    print STDERR "$conf file has been created\n";
}


sub edit_configuration {
    require 'Conf.pm';

    ## Load config 
    unless ($wwsconf = wwslib::load_config($wwsympa_conf)) {
        die("Unable to load config file $wwsympa_conf");
    }

    ## Load sympa config
    unless (Conf::load( $sympa_conf )) {
        die("Unable to load sympa config file $sympa_conf");
    }

    my (@new_wwsympa_conf, @new_sympa_conf);

    ## Edition mode
    foreach my $i (0..$#params) {
        my $desc;

        if ($params[$i]->{'title'}) {
            my $title = $params[$i]->{'title'};
            printf "\n\n** $title **\n";

            ## write to conf file
            push @new_wwsympa_conf, sprintf "###\\\\\\\\ %s ////###\n\n", $params[$i]->{'title'};
            push @new_sympa_conf, sprintf "###\\\\\\\\ %s ////###\n\n", $params[$i]->{'title'};

            next;
        }    

        my $file = $params[$i]->{'file'} ;
        my $name = $params[$i]->{'name'} ; 
        my $query = $params[$i]->{'query'} ;
        my $advice = $params[$i]->{'advice'} ;
        my $sample = $params[$i]->{'sample'} ;
        my $current_value ;
        if ($file eq 'wwsympa.conf') {	
            $current_value = $wwsconf->{$name} ;
        }elsif ($file eq 'sympa.conf') {
            $current_value = $Conf::Conf{$name}; 
        }else {
            printf STDERR "incorrect definition of $name\n";
        }
        my $new_value;
        if ($params[$i]->{'edit'} eq '1') {
            printf "... $advice\n" unless ($advice eq '') ;
            printf "$name: $query \[$current_value\] : ";
            $new_value = <STDIN> ;
            chomp $new_value;
        }
        if ($new_value eq '') {
            $new_value = $current_value;
        }

        ## SKip empty parameters
        next if (($new_value eq '') &&
            ! $sample);

        ## param is an ARRAY
        if (ref($new_value) eq 'ARRAY') {
            $new_value = join ',',@{$new_value};
        }

        if ($file eq 'wwsympa.conf') {
            $desc = \@new_wwsympa_conf;
        }elsif ($file eq 'sympa.conf') {
            $desc = \@new_sympa_conf;
        }else{
            printf STDERR "incorrect parameter $name definition \n";
        }

        if ($new_value eq '') {
            next unless $sample;

            push @{$desc}, sprintf "## $query\n";

            unless ($advice eq '') {
                push @{$desc}, sprintf "## $advice\n";
            }

            push @{$desc}, sprintf "# $name\t$sample\n\n";
        }else {
            push @{$desc}, sprintf "## $query\n";
            unless ($advice eq '') {
                push @{$desc}, sprintf "## $advice\n";
            }

            if ($current_value ne $new_value) {
                push @{$desc}, sprintf "# was $name $current_value\n";
                $somechange = 1;
            }

            push @{$desc}, sprintf "$name\t$new_value\n\n";
        }
    }

    if ($somechange) {

        my $date = POSIX::strftime("%d.%b.%Y-%H.%M.%S", localtime(time));

        ## Keep old config files
        unless (rename $wwsympa_conf, $wwsympa_conf.'.'.$date) {
            warn "Unable to rename $wwsympa_conf : $!";
        }

        unless (rename $sympa_conf, $sympa_conf.'.'.$date) {
            warn "Unable to rename $sympa_conf : $!";
        }

        ## Write new config files
        unless (open (WWSYMPA,"> $wwsympa_conf")){
            die "unable to open $new_wwsympa_conf : $!";
        };

        unless (open (SYMPA,"> $sympa_conf")){
            die "unable to open $new_sympa_conf : $!";
        };

        print SYMPA @new_sympa_conf;
        print WWSYMPA @new_wwsympa_conf;

        close SYMPA;
        close WWSYMPA;

        printf "$sympa_conf and $wwsympa_conf have been updated.\nPrevious versions have been saved as $sympa_conf.$date and $wwsympa_conf.$date\n";
    }
}

sub check_cpan {
    require CPAN;

    ## assume version = 1.0 if not specified.
    ## 
    my %versions = (
        'perl' => '5.008',
        'Net::LDAP' =>, '0.27', 
        'perl-ldap' => '0.10',
        'Mail::Internet' => '1.51', 
        'DBI' => '1.48',
        'DBD::Pg' => '0.90',
        'DBD::Sybase' => '0.90',
        'DBD::mysql' => '2.0407',
        'FCGI' => '0.67',
        'HTML::StripScripts::Parser' => '1.0',
        'MIME::Tools' => '5.423',
        'File::Spec' => '0.8',
        'Crypt::CipherSaber' => '0.50',
        'CGI' => '3.35',
        'Digest::MD5' => '2.00',
        'DB_File' => '1.75',
        'IO::Socket::SSL' => '0.90',
        'Net::SSLeay' => '1.16',
        'Archive::Zip' => '1.05',
        'Bundle::LWP' => '1.09',
        'SOAP::Lite' => '0.60',
        'MHonArc::UTF8' => '2.6.0',
        'MIME::Base64' => '3.03',
        'MIME::Charset' => '0.04.1',
        'MIME::EncWords' => '0.040',
        'File::Copy::Recursive' => '0.36',
    );

    ### key:left "module" used by SYMPA, 
    ### right CPAN module.		     
    my %req_CPAN = (
        'DB_File' => 'DB_FILE',
        'Digest::MD5' => 'Digest-MD5',
        'Mail::Internet' =>, 'MailTools',
        'IO::Scalar' => 'IO-stringy',
        'MIME::Tools' => 'MIME-tools',
        'MIME::Base64' => 'MIME-Base64',
        'CGI' => 'CGI',
        'File::Spec' => 'File-Spec',
        'Regexp::Common' => 'Regexp-Common',
        'Locale::TextDomain' => 'libintl-perl',
        'Template' => 'Template-Toolkit',
        'Archive::Zip' => 'Archive-Zip',
        'LWP' => 'libwww-perl',
        'XML::LibXML' => 'XML-LibXML',
        'MHonArc::UTF8' => 'MHonArc',
        'FCGI' => 'FCGI',
        'DBI' => 'DBI',
        'DBD::mysql' => 'Msql-Mysql-modules',
        'Crypt::CipherSaber' => 'CipherSaber',
        'Encode' => 'Encode',
        'MIME::Charset' => 'MIME-Charset',
        'MIME::EncWords' => 'MIME-EncWords',
        'HTML::StripScripts::Parser' => 'HTML-StripScripts-Parser',
        'File::Copy::Recursive' => 'File-Copy-Recursive',
    );

    my %opt_CPAN = (
        'DBD::Pg' => 'DBD-Pg',
        'DBD::Oracle' => 'DBD-Oracle',
        'DBD::Sybase' => 'DBD-Sybase',
        'DBD::SQLite' => 'DBD-SQLite',
        'Net::LDAP' =>   'perl-ldap',
        'CGI::Fast' => 'CGI',
        'Net::SMTP' => 'libnet',
        'IO::Socket::SSL' => 'IO-Socket-SSL',
        'Net::SSLeay' => 'NET-SSLeay',
        'Bundle::LWP' => 'LWP',
        'SOAP::Lite' => 'SOAP-Lite',
        'File::NFSLock' => 'File-NFSLock',
        'File::Copy::Recursive' => 'File-Copy-Recursive',
    );

    my %opt_features = (
        'DBI' => 'a generic Database Driver, required by Sympa to access Subscriber information and User preferences. An additional Database Driver is required for each database type you wish to connect to.',
        'DBD::mysql' => 'Mysql database driver, required if you connect to a Mysql database.\nYou first need to install the Mysql server and have it started before installing the Perl DBD module.',
        'DBD::Pg' => 'PostgreSQL database driver, required if you connect to a PostgreSQL database.',
        'DBD::Oracle' => 'Oracle database driver, required if you connect to a Oracle database.',
        'DBD::Sybase' => 'Sybase database driver, required if you connect to a Sybase database.',
        'DBD::SQLite' => 'SQLite database driver, required if you connect to a SQLite database.',
        'Net::LDAP' =>   'required to query LDAP directories. Sympa can do LDAP-based authentication ; it can also build mailing lists with LDAP-extracted members.',
        'CGI::Fast' => 'WWSympa, Sympa\'s web interface can run as a FastCGI (ie: a persistent CGI). If you install this module, you will also need to install the associated mod_fastcgi for Apache.',
        'Crypt::CipherSaber' => 'this module provides reversible encryption of user passwords in the database.',
        'Archive::Zip ' => 'this module provides zip/unzip for archive and shared document download/upload',
        'FCGI' => 'WSympa, Sympa\'s web interface can run as a FastCGI (ie: a persistent CGI). If you install this module, you will also need to install the associated mod_fastcgi for Apache.',
        'Net::SMTP' => 'this is required if you set \'list_check_smtp\' sympa.conf parameter, used to check existing aliases before mailing list creation.',
        'IO::Socket::SSL' => 'required by CAS (single sign-on) and the \'include_remote_sympa_list\' feature that includes members of a list on a remote server, using X509 authentication',
        'Net::SSLeay' => 'required by the \'include_remote_sympa_list\' feature that includes members of a list on a remote server, using X509 authentication',
        'Bundle::LWP' => 'required by the \'include_remote_sympa_list\' feature that includes members of a list on a remote server, using X509 authentication',
        'SOAP::Lite' => 'required if you want to run the Sympa SOAP server that provides ML services via a "web service"',
        'File::NFSLock' => 'required to perform NFS lock ; see also lock_method sympa.conf parameter'
    );

    ### main:
    print "******* Check perl for SYMPA ********\n";
    ### REQ perl version
    print "\nChecking for PERL version:\n-----------------------------\n";
    my $rpv = $versions{"perl"};
    if ($] >= $versions{"perl"}){
        print "your version of perl is OK ($]  >= $rpv)\n";
    }else {
        print "Your version of perl is TOO OLD ($]  < $rpv)\nPlease INSTALL a new one !\n";
    }

    print "\nChecking for REQUIRED modules:\n------------------------------------------\n";
    check_modules('y', \%req_CPAN, \%versions, \%opt_features);
    print "\nChecking for OPTIONAL modules:\n------------------------------------------\n";
    check_modules('n', \%opt_CPAN, \%versions, \%opt_features);

    print <<EOM;
******* NOTE *******
You can retrive all theses modules from any CPAN server
(for example ftp://ftp.pasteur.fr/pub/computing/CPAN/CPAN.html)
EOM
###--------------------------
# reports modules status
###--------------------------
}

sub check_modules {
    my($default, $todo, $versions, $opt_features) = @_;
    my($vs, $v, $rv, $status);

    print "perl module          from CPAN       STATUS\n"; 
    print "-----------          ---------       ------\n";

    foreach my $mod (sort keys %$todo) {
        printf ("%-20s %-15s", $mod, $todo->{$mod});

        my $status = test_module($mod);
        if ($status == 1) {
            $vs = "$mod" . "::VERSION";

            $vs = 'mhonarc::VERSION' if $mod =~ /^mhonarc/i;

            $v = $$vs;
            my $rv = $versions->{$mod} || "1.0" ;
            ### OK: check version
            if ($v ge $rv) {
                printf ("OK (%-6s >= %s)\n", $v, $rv);
                next;
            }else {
                print "version is too old ($v < $rv).\n";
                print ">>>>>>> You must update \"$todo->{$mod}\" to version \"$versions->{$todo->{$mod}}\" <<<<<<.\n";
                install_module($mod, {'default' => $default}, $opt_features);
            }
        } elsif ($status eq "nofile") {
            ### not installed
            print "was not found on this system.\n";

            install_module($mod, {'default' => $default});

        } elsif ($status eq "pb_retval") {
            ### doesn't return 1;
            print "$mod doesn't return 1 (check it).\n";
        } else {
            print "$status\n";
        }
    }
}

##----------------------
# Install a CPAN module
##----------------------
sub install_module {
    my ($module, $options, $opt_features) = @_;

    my $default = $options->{'default'};

    unless ($ENV{'FTP_PASSIVE'} eq 1) {
        $ENV{'FTP_PASSIVE'} = 1;
        print "Setting FTP Passive mode\n";
    }

    ## This is required on RedHat 9 for DBD::mysql installation
    my $lang = $ENV{'LANG'};
    $ENV{'LANG'} = 'C' if ($ENV{'LANG'} =~ /UTF\-8/);

    unless ($> == 0) {
        print "\#\# You need root privileges to install $module module. \#\#\n";
        print "\#\# Press the Enter key to continue checking modules. \#\#\n";
        my $t = <STDIN>;
        return undef;
    }

    unless ($options->{'force'}) {
        printf "Description: %s\n", $opt_features->{$module};
        print "Install module $module ? [$default]";
        my $answer = <STDIN>; chomp $answer;
        $answer ||= $default;
        return unless ($answer =~ /^y$/i);
    }

    $CPAN::Config->{'inactivity_timeout'} = 4;
    $CPAN::Config->{'colorize_output'} = 1;

    #CPAN::Shell->clean($module) if ($options->{'force'});

    CPAN::Shell->make($module);

    if ($options->{'force'}) {
        CPAN::Shell->force('test', $module);
    }else {
        CPAN::Shell->test($module);
    }


    CPAN::Shell->install($module); ## Could use CPAN::Shell->force('install') if make test failed

    ## Check if module has been successfuly installed
    unless (test_module($module) == 1) {

        ## Prevent recusive calls if already in force mode
        if ($options->{'force'}) {
            print  "Installation of $module still FAILED. You should download the tar.gz from http://search.cpan.org and install it manually.";
            my $answer = <STDIN>;
        }else {
            print  "Installation of $module FAILED. Do you want to force the installation of this module? (y/N) ";
            my $answer = <STDIN>; chomp $answer;
            if ($answer =~ /^y/i) {
                install_module($module, {'force' => 1});
            }
        }
    }

    ## Restore lang
    $ENV{'LANG'} = $lang if (defined $lang);

}

###--------------------------
# test if module is there
# (from man perlfunc ...)
###--------------------------
sub test_module {
    my($filename) = @_;
    my($realfilename, $result);

    $filename =~ s/::/\//g;
    $filename .= ".pm";

    ## Exception for mhonarc
    $filename = 'mhamain.pl' if $filename =~ /^mhonarc/i;

    return 1 if $INC{$filename};

    ITER: {
        foreach my $prefix (@INC) {
            $realfilename = "$prefix/$filename";
            if (-f $realfilename) {
                $result = do $realfilename;
                last ITER;
            }
        }
        return "nofile";
    }
    return "pb_retval" unless $result;
    return $result;
}
