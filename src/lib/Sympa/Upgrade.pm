# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997-2011 Comite Reseau des Universites
# Copyright (c) 2011-2014 GIP RENATER
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

package Sympa::Upgrade;

use strict;

use English qw(-no_match_vars);
use Carp qw(croak);
use File::Copy::Recursive;
use POSIX qw(strftime);

# tentative
use Data::Dumper;

use Sympa::Site;

#use Conf; # used in Site
#use Sympa::Log::Syslog; # used in Conf
#use Sympa::Constants; # used in Conf - confdef
#use Sympa::DatabaseManager; # used in Conf

## Return the previous Sympa version, ie the one listed in
## data_structure.version
sub get_previous_version {
    my $version_file = Sympa::Site->etc . '/data_structure.version';
    my $previous_version;

    if (-f $version_file) {
        unless (open VFILE, $version_file) {
            Sympa::Log::Syslog::do_log('err', "Unable to open %s : %s",
                $version_file, $ERRNO);
            return undef;
        }
        while (<VFILE>) {
            next if /^\s*$/;
            next if /^\s*\#/;
            chomp;
            $previous_version = $_;
            last;
        }
        close VFILE;

        return $previous_version;
    }

    return undef;
}

sub update_version {
    my $version_file = Sympa::Site->etc . '/data_structure.version';

    ## Saving current version if required
    unless (open VFILE, ">$version_file") {
        Sympa::Log::Syslog::do_log(
            'err',
            "Unable to write %s ; sympa.pl needs write access on %s directory : %s",
            $version_file,
            Sympa::Site->etc,
            $ERRNO
        );
        return undef;
    }
    print VFILE
        "# This file is automatically created by sympa.pl after installation\n# Unless you know what you are doing, you should not modify it\n";
    printf VFILE "%s\n", Sympa::Constants::VERSION;
    close VFILE;

    return 1;
}

## Upgrade data structure from one version to another
sub upgrade {
    Sympa::Log::Syslog::do_log('debug3', '(%s, %s)', @_);
    my ($previous_version, $new_version) = @_;

    if (Sympa::Tools::lower_version($new_version, $previous_version)) {
        Sympa::Log::Syslog::do_log('notice',
            'Installing  older version of Sympa ; no upgrade operation is required'
        );
        return 1;
    }

    ## Check database connectivity and probe database
    unless (Sympa::DatabaseManager::check_db_connect('just_try') and Sympa::DatabaseManager::probe_db()) {
        Sympa::Log::Syslog::do_log(
            'err',
            'Database %s defined in sympa.conf has not the right structure or is unreachable. verify db_xxx parameters in sympa.conf',
            Sympa::Site->db_name
        );
        return undef;
    }

    ## Always update config.bin files while upgrading
    Sympa::Conf::delete_binaries();
    ## Always update config.bin files while upgrading
    ## This is especially useful for character encoding reasons
    Sympa::Log::Syslog::do_log('notice',
        'Rebuilding config.bin files for ALL lists...it may take a while...');
    my $all_lists = Sympa::List::get_lists('Site', {'reload_config' => 1});

    ## Empty the admin_table entries and recreate them
    Sympa::Log::Syslog::do_log('notice', 'Rebuilding the admin_table...');
    Sympa::List::delete_all_list_admin();
    foreach my $list (@$all_lists) {
        $list->sync_include_admin();
    }

    ## Migration to tt2
    if (Sympa::Tools::lower_version($previous_version, '4.2b')) {

        Sympa::Log::Syslog::do_log('notice',
            'Migrating templates to TT2 format...');

        my $tpl_script = Sympa::Constants::SCRIPTDIR . '/tpl2tt2.pl';
        unless (open EXEC, "$tpl_script|") {
            Sympa::Log::Syslog::do_log('err', "Unable to run $tpl_script");
            return undef;
        }
        close EXEC;

        Sympa::Log::Syslog::do_log('notice', 'Rebuilding web archives...');
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            next unless %{$list->web_archive};    #FIXME: always success
            my $file = Sympa::Site->queueoutgoing . '/.rebuild.' . $list->get_id();

            unless (open REBUILD, ">$file") {
                Sympa::Log::Syslog::do_log('err', 'Cannot create %s', $file);
                next;
            }
            print REBUILD ' ';
            close REBUILD;
        }
    }

    ## Initializing the new admin_table
    if (Sympa::Tools::lower_version($previous_version, '4.2b.4')) {
        Sympa::Log::Syslog::do_log('notice',
            'Initializing the new admin_table...');
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            $list->sync_include_admin();
        }
    }

    ## Move old-style web templates out of the include_path
    if (Sympa::Tools::lower_version($previous_version, '5.0.1')) {
        Sympa::Log::Syslog::do_log('notice',
            'Old web templates HTML structure is not compliant with latest ones.'
        );
        Sympa::Log::Syslog::do_log('notice',
            'Moving old-style web templates out of the include_path...');

        my @directories;

        if (-d Sympa::Site->etc . '/web_tt2') {
            push @directories, Sympa::Site->etc . '/web_tt2';
        }

        ## Go through Virtual Robots
        foreach my $vr (@{Sympa::Robot::get_robots()}) {
            if (-d $vr->etc . '/web_tt2') {
                push @directories, $vr->etc . '/web_tt2';
            }
        }

        ## Search in V. Robot Lists
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            if (-d $list->dir . '/web_tt2') {
                push @directories, $list->dir . '/web_tt2';
            }
        }

        my @templates;

        foreach my $d (@directories) {
            unless (opendir DIR, $d) {
                printf STDERR "Error: Cannot read %s directory : %s", $d, $ERRNO;
                next;
            }

            foreach my $tt2 (sort grep(/\.tt2$/, readdir DIR)) {
                push @templates, "$d/$tt2";
            }

            closedir DIR;
        }

        foreach my $tpl (@templates) {
            unless (rename $tpl, "$tpl.oldtemplate") {
                printf STDERR
                    "Error : failed to rename %s to %s.oldtemplate : %s\n",
                    $tpl, $tpl, $ERRNO;
                next;
            }

            Sympa::Log::Syslog::do_log('notice', 'File %s renamed %s',
                $tpl, "$tpl.oldtemplate");
        }
    }

    ## Clean buggy list config files
    if (Sympa::Tools::lower_version($previous_version, '5.1b')) {
        Sympa::Log::Syslog::do_log('notice',
            'Cleaning buggy list config files...');
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            $list->save_config($list->robot->get_address('listmaster'));
        }
    }

    ## Fix a bug in Sympa 5.1
    if (Sympa::Tools::lower_version($previous_version, '5.1.2')) {
        Sympa::Log::Syslog::do_log('notice', 'Rename archives/log. files...');
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            my $l = $list->name;
            if (-f $list->dir . '/archives/log.') {
                rename $list->dir . '/archives/log.',
                    $list->dir . '/archives/log.00';
            }
        }
    }

    if (Sympa::Tools::lower_version($previous_version, '5.2a.1')) {

        ## Fill the robot_subscriber and robot_admin fields in DB
        Sympa::Log::Syslog::do_log('notice',
            'Updating the new robot_subscriber and robot_admin  Db fields...'
        );

        foreach my $r (@{Sympa::Robot::get_robots()}) {
            my $all_lists = Sympa::List::get_lists($r, {'skip_sync_admin' => 1});
            foreach my $list (@$all_lists) {
                foreach my $table ('subscriber', 'admin') {
                    unless (
                        Sympa::DatabaseManager::do_query(
                            q{UPDATE %s_table
			  SET robot_%s = %s
			  WHERE list_%s = %s},
                            $table,
                            $table,
                            Sympa::DatabaseManager::quote($list->domain),
                            $table,
                            Sympa::DatabaseManager::quote($list->name)
                        )
                        ) {
                        Sympa::Log::Syslog::do_log(
                            'err',
                            'Unable to fille the robot_admin and robot_subscriber fields in database for robot %s.',
                            $r
                        );
                        Sympa::Site->send_notify_to_listmaster(
                            'upgrade_failed',
                            {   'error' =>
                                    $Sympa::DatabaseManager::db_source->{'db_handler'}->errstr
                            }
                        );
                        return undef;
                    }
                }

                ## Force Sync_admin
                $list =
                    Sympa::List->new($list->name, $list->robot,
                    {'force_sync_admin' => 1});
            }
        }

        ## Rename web archive directories using 'domain' instead of 'host'
        Sympa::Log::Syslog::do_log('notice',
            'Renaming web archive directories with the list domain...');

        my $root_dir = Sympa::Site->arc_path;
        unless (opendir ARCDIR, $root_dir) {
            Sympa::Log::Syslog::do_log('err',
                "Unable to open $root_dir : $ERRNO");
            return undef;
        }

        foreach my $dir (sort readdir(ARCDIR)) {
            ## Skip files and entries starting with '.'
            next
                if (($dir =~ /^\./o) || (!-d $root_dir . '/' . $dir));

            my ($listname, $listdomain) = split /\@/, $dir;

            next unless $listname and $listdomain;

            my $list = Sympa::List->new($listname);
            unless (defined $list) {
                Sympa::Log::Syslog::do_log('notice',
                    "Skipping unknown list $listname");
                next;
            }

            if ($listdomain ne $list->domain) {
                my $old_path =
                    $root_dir . '/' . $listname . '@' . $listdomain;
                my $new_path =
                    $root_dir . '/' . $listname . '@' . $list->domain;

                if (-d $new_path) {
                    Sympa::Log::Syslog::do_log(
                        'err',
                        "Could not rename %s to %s ; directory already exists",
                        $old_path,
                        $new_path
                    );
                    next;
                } else {
                    unless (rename $old_path, $new_path) {
                        Sympa::Log::Syslog::do_log('err',
                            "Failed to rename %s to %s : %s",
                            $old_path, $new_path, $ERRNO);
                        next;
                    }
                    Sympa::Log::Syslog::do_log('notice', "Renamed %s to %s",
                        $old_path, $new_path);
                }
            }
        }
        close ARCDIR;

    }

    ## DB fields of enum type have been changed to int
    if (Sympa::Tools::lower_version($previous_version, '5.2a.1')) {

        if (Sympa::DatabaseManager::use_db && Sympa::Site->db_type eq 'mysql') {
            my %check = (
                'subscribed_subscriber' => 'subscriber_table',
                'included_subscriber'   => 'subscriber_table',
                'subscribed_admin'      => 'admin_table',
                'included_admin'        => 'admin_table'
            );

            foreach my $field (keys %check) {
                my $statement;
                my $sth;

                $sth = Sympa::DatabaseManager::do_query(q{SELECT max(%s) FROM %s},
                    $field, $check{$field});
                unless ($sth) {
                    Sympa::Log::Syslog::do_log('err',
                        'Unable to execute SQL statement');
                    return undef;
                }

                my $max = $sth->fetchrow();
                $sth->finish();

                ## '0' has been mapped to 1 and '1' to 2
                ## Restore correct field value
                if ($max > 1) {
                    ## 1 to 0
                    Sympa::Log::Syslog::do_log('notice',
                        'Fixing DB field %s ; turning 1 to 0...', $field);
                    my $rows;
                    $sth =
                        Sympa::DatabaseManager::do_query(q{UPDATE %s SET %s = %d WHERE %s = %d},
                        $check{$field}, $field, 0, $field, 1);
                    unless ($sth) {
                        Sympa::Log::Syslog::do_log('err',
                            'Unable to execute SQL statement');
                        return undef;
                    }
                    $rows = $sth->rows;
                    Sympa::Log::Syslog::do_log('notice', 'Updated %d rows',
                        $rows);

                    ## 2 to 1
                    Sympa::Log::Syslog::do_log('notice',
                        'Fixing DB field %s ; turning 2 to 1...', $field);

                    $statement = sprintf "UPDATE %s SET %s=%d WHERE (%s=%d)",
                        $check{$field}, $field, 1, $field, 2;

                    $sth =
                        Sympa::DatabaseManager::do_query(q{UPDATE %s SET %s = %d WHERE %s = %d},
                        $check{$field}, $field, 1, $field, 2);
                    unless ($sth) {
                        Sympa::Log::Syslog::do_log('err',
                            'Unable to execute SQL statement');
                        return undef;
                    }
                    $rows = $sth->rows;
                    Sympa::Log::Syslog::do_log('notice', 'Updated %d rows',
                        $rows);
                }

                ## Set 'subscribed' data field to '1' is none of 'subscribed'
                ## and 'included' is set
                Sympa::Log::Syslog::do_log('notice',
                    'Updating subscribed field of the subscriber table...');
                my $rows;
                $sth = Sympa::DatabaseManager::do_query(
                    q{UPDATE subscriber_table
		      SET subscribed_subscriber = 1
		      WHERE (included_subscriber IS NULL OR
			     included_subscriber <> 1) AND
			    (subscribed_subscriber IS NULL OR
			     subscribed_subscriber <> 1)}
                );
                unless ($sth) {
                    Sympa::Log::Syslog::do_log('err',
                        'Unable to execute SQL statement');
                    return undef;
                }
                $rows = $sth->rows;
                Sympa::Log::Syslog::do_log('notice',
                    '%d rows have been updated', $rows);
            }
        }
    }

    ## Rename bounce sub-directories
    if (Sympa::Tools::lower_version($previous_version, '5.2a.1')) {

        Sympa::Log::Syslog::do_log('notice',
            'Renaming bounce sub-directories adding list domain...');

        my $root_dir = Sympa::Site->bounce_path;
        unless (opendir BOUNCEDIR, $root_dir) {
            Sympa::Log::Syslog::do_log('err',
                "Unable to open $root_dir : $ERRNO");
            return undef;
        }

        foreach my $dir (sort readdir(BOUNCEDIR)) {
            ## Skip files and entries starting with '.'
            next if (($dir =~ /^\./o) || (!-d $root_dir . '/' . $dir));
            ## Directory already include the list domain
            next if ($dir =~ /\@/);

            my $listname = $dir;
            my $list     = Sympa::List->new($listname);
            unless (defined $list) {
                Sympa::Log::Syslog::do_log('notice',
                    'Skipping unknown list %s', $listname);
                next;
            }

            my $old_path = $root_dir . '/' . $listname;
            my $new_path = $root_dir . '/' . $list->get_id;

            if (-d $new_path) {
                Sympa::Log::Syslog::do_log('err',
                    "Could not rename %s to %s ; directory already exists",
                    $old_path, $new_path);
                next;
            } else {
                unless (rename $old_path, $new_path) {
                    Sympa::Log::Syslog::do_log('err',
                        "Failed to rename %s to %s : %s",
                        $old_path, $new_path, $ERRNO);
                    next;
                }
                Sympa::Log::Syslog::do_log('notice', "Renamed %s to %s",
                    $old_path, $new_path);
            }
        }
        close BOUNCEDIR;
    }

    ## Update lists config using 'include_list'
    if (Sympa::Tools::lower_version($previous_version, '5.2a.1')) {

        Sympa::Log::Syslog::do_log('notice',
            'Update lists config using include_list parameter...');

        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            if (@{$list->include_list}) {
                my $include_lists = $list->include_list;
                my $changed       = 0;
                foreach my $index (0 .. $#{$include_lists}) {
                    my $incl      = $include_lists->[$index];
                    my $incl_list = Sympa::List->new($incl);

                    if (defined $incl_list
                        and $incl_list->domain ne $list->domain) {
                        Sympa::Log::Syslog::do_log(
                            'notice',
                            'Update config file of list %s, including list %s',
                            $list,
                            $incl_list
                        );
                        $include_lists->[$index] = $incl_list->get_id();
                        $changed = 1;
                    }
                }
                if ($changed) {
                    $list->include_list($include_lists);
                    $list->save_config(
                        $list->robot->get_address('listmaster'));
                }
            }
        }
    }

    ## New mhonarc ressource file with utf-8 recoding
    if (Sympa::Tools::lower_version($previous_version, '5.3a.6')) {

        Sympa::Log::Syslog::do_log('notice',
            'Looking for customized mhonarc-ressources.tt2 files...');
        foreach my $vr (@{Sympa::Robot::get_robots()}) {
            my $etc_dir = $vr->etc;

            if (-f $etc_dir . '/mhonarc-ressources.tt2') {
                my $new_filename =
                    $etc_dir . '/mhonarc-ressources.tt2' . '.' . time;
                rename $etc_dir . '/mhonarc-ressources.tt2', $new_filename;
                Sympa::Log::Syslog::do_log(
                    'notice',
                    "Custom %s file has been backed up as %s",
                    $etc_dir . '/mhonarc-ressources.tt2',
                    $new_filename
                );
                Sympa::Site->send_notify_to_listmaster('file_removed',
                    [$etc_dir . '/mhonarc-ressources.tt2', $new_filename]);
            }
        }

        Sympa::Log::Syslog::do_log('notice', 'Rebuilding web archives...');
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            next unless %{$list->web_archive};    #FIXME: always true
            my $file = Sympa::Site->queueoutgoing . '/.rebuild.' . $list->get_id();

            unless (open REBUILD, ">$file") {
                Sympa::Log::Syslog::do_log('err', 'Cannot create %s', $file);
                next;
            }
            print REBUILD ' ';
            close REBUILD;
        }

    }

    ## Changed shared documents name encoding
    ## They are Q-encoded therefore easier to store on any filesystem with any
    ## encoding
    if (Sympa::Tools::lower_version($previous_version, '5.3a.8')) {
        Sympa::Log::Syslog::do_log('notice',
            'Q-Encoding web documents filenames...');

        Sympa::Language::PushLang(Sympa::Site->lang);
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            if (-d $list->dir . '/shared') {
                Sympa::Log::Syslog::do_log('notice',
                    '  Processing list %s...', $list);

                ## Determine default lang for this list
                ## It should tell us what character encoding was used for
                ## filenames
                Sympa::Language::SetLang($list->lang);
                my $list_encoding = Sympa::Language::GetCharset();

                my $count = Sympa::Tools::qencode_hierarchy($list->dir . '/shared',
                    $list_encoding);

                if ($count) {
                    Sympa::Log::Syslog::do_log('notice',
                        'List %s : %d filenames has been changed',
                        $list, $count);
                }
            }
        }
        Sympa::Language::PopLang();
    }

    ## We now support UTF-8 only for custom templates, config files, headers
    ## and footers, info files
    ## + web_tt2, scenari, create_list_templates, families
    if (Sympa::Tools::lower_version($previous_version, '5.3b.3')) {
        Sympa::Log::Syslog::do_log('notice',
            'Encoding all custom files to UTF-8...');

        my (@directories, @files);

        ## Site level
        foreach my $type (
            'mail_tt2', 'web_tt2',
            'scenari',  'create_list_templates',
            'families'
            ) {
            if (-d Sympa::Site->etc . '/' . $type) {
                push @directories, [Sympa::Site->etc . '/' . $type, Sympa::Site->lang];
            }
        }

        foreach my $f (
            Sympa::Conf::get_sympa_conf(),     Sympa::Conf::get_wwsympa_conf(),
            Sympa::Site->etc . '/topics.conf', Sympa::Site->etc . '/auth.conf'
            ) {
            if (-f $f) {
                push @files, [$f, Sympa::Site->lang];
            }
        }

        ## Go through Virtual Robots
        foreach my $vr (@{Sympa::Robot::get_robots()}) {
            foreach my $type (
                'mail_tt2', 'web_tt2',
                'scenari',  'create_list_templates',
                'families'
                ) {
                if (-d $vr->etc . '/' . $type) {
                    push @directories, [$vr->etc . '/' . $type, $vr->lang];
                }
            }

            foreach my $f ('robot.conf', 'topics.conf', 'auth.conf') {
                if (-f $vr->etc . '/' . $f) {
                    push @files, [$vr->etc . '/' . $f, $vr->lang];
                }
            }
        }

        ## Search in Lists
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            foreach my $f (
                'config',   'info',
                'homepage', 'message.header',
                'message.footer'
                ) {
                if (-f $list->dir . '/' . $f) {
                    push @files, [$list->dir . '/' . $f, $list->lang];
                }
            }

            foreach my $type ('mail_tt2', 'web_tt2', 'scenari') {
                my $directory = $list->dir . '/' . $type;
                if (-d $directory) {
                    push @directories, [$directory, $list->lang];
                }
            }
        }

        ## Search language directories
        foreach my $pair (@directories) {
            my ($d, $lang) = @$pair;
            unless (opendir DIR, $d) {
                next;
            }

            if ($d =~ /(mail_tt2|web_tt2)$/) {
                foreach
                    my $subdir (grep(/^[a-z]{2}(_[A-Z]{2})?$/, readdir DIR)) {
                    if (-d "$d/$subdir") {
                        push @directories, ["$d/$subdir", $subdir];
                    }
                }
                closedir DIR;

            } elsif ($d =~ /(create_list_templates|families)$/) {
                foreach my $subdir (grep(/^\w+$/, readdir DIR)) {
                    if (-d "$d/$subdir") {
                        push @directories, ["$d/$subdir", Sympa::Site->lang];
                    }
                }
                closedir DIR;
            }
        }

        foreach my $pair (@directories) {
            my ($d, $lang) = @$pair;
            unless (opendir DIR, $d) {
                next;
            }
            foreach my $file (readdir DIR) {
                next
                    unless (
                    (   $d =~
                        /mail_tt2|web_tt2|create_list_templates|families/
                        && $file =~ /\.tt2$/
                    )
                    || ($d =~ /scenari$/ && $file =~ /\w+\.\w+$/)
                    );
                push @files, [$d . '/' . $file, $lang];
            }
            closedir DIR;
        }

        ## Do the encoding modifications
        ## Previous versions of files are backed up with the date extension
        my $total = &to_utf8(\@files);
        Sympa::Log::Syslog::do_log('notice', '%d files have been modified',
            $total);
    }

    ## giving up subscribers flat files ; moving subscribers to the DB
    ## Also giving up old 'database' mode
    if (Sympa::Tools::lower_version($previous_version, '5.4a.1')) {

        Sympa::Log::Syslog::do_log('notice',
            'Looking for lists with user_data_source parameter set to file or database...'
        );

        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            if ($list->user_data_source eq 'file') {
                Sympa::Log::Syslog::do_log(
                    'notice',
                    'List %s ; changing user_data_source from file to include2...',
                    $list
                );

                my @users = Sympa::List::_load_list_members_file(
                    $list->dir . '/subscribers');

                $list->user_data_source = 'include2';
                $list->total(0);

                ## Add users to the DB
                $list->add_list_member(@users);
                my $total = $list->{'add_outcome'}{'added_members'};
                if (defined $list->{'add_outcome'}{'errors'}) {
                    Sympa::Log::Syslog::do_log(
                        'err',
                        'Failed to add users: %s',
                        $list->{'add_outcome'}{'errors'}{'error_message'}
                    );
                }

                Sympa::Log::Syslog::do_log('notice',
                    '%d subscribers have been loaded into the database',
                    $total);

                unless ($list->save_config('automatic')) {
                    Sympa::Log::Syslog::do_log('err',
                        'Failed to save config file for list %s', $list);
                }
            } elsif ($list->user_data_source eq 'database') {

                Sympa::Log::Syslog::do_log(
                    'notice',
                    'List %s ; changing user_data_source from database to include2...',
                    $list
                );

                unless ($list->update_list_member('*', {'subscribed' => 1})) {
                    Sympa::Log::Syslog::do_log('err',
                        'Failed to update subscribed DB field');
                }

                $list->user_data_source = 'include2';

                unless ($list->save_config('automatic')) {
                    Sympa::Log::Syslog::do_log('err',
                        'Failed to save config file for list %s', $list);
                }
            }
        }
    }

    if (Sympa::Tools::lower_version($previous_version, '5.5a.1')) {

        ## Remove OTHER/ subdirectories in bounces
        Sympa::Log::Syslog::do_log('notice',
            "Removing obsolete OTHER/ bounce directories");
        if (opendir BOUNCEDIR, Sympa::Site->bounce_path) {

            foreach my $subdir (sort grep (!/^\.+$/, readdir(BOUNCEDIR))) {
                my $other_dir = Sympa::Site->bounce_path . '/' . $subdir . '/OTHER';
                if (-d $other_dir) {
                    Sympa::Tools::remove_dir($other_dir);
                    Sympa::Log::Syslog::do_log('notice',
                        "Directory $other_dir removed");
                }
            }

            close BOUNCEDIR;

        } else {
            Sympa::Log::Syslog::do_log('err',
                "Failed to open directory Sympa::Site->queuebounce : $ERRNO");
        }

    }

    if (Sympa::Tools::lower_version($previous_version, '6.1b.5')) {
        ## Encoding of shared documents was not consistent with recent
        ## versions of MIME::Encode
        ## MIME::EncWords::encode_mimewords() used to encode characters -!*+/
        ## Now these characters are preserved, according to RFC 2047 section 5
        ## We change encoding of shared documents according to new algorithm
        Sympa::Log::Syslog::do_log('notice',
            'Fixing Q-encoding of web document filenames...');
        my $all_lists = Sympa::List::get_lists('Site');
        foreach my $list (@$all_lists) {
            if (-d $list->dir . '/shared') {
                Sympa::Log::Syslog::do_log('notice',
                    '  Processing list %s...', $list);

                my @all_files;
                Sympa::Tools::list_dir($list->dir, \@all_files, 'utf-8');

                my $count;
                foreach my $f_struct (reverse @all_files) {
                    my $new_filename = $f_struct->{'filename'};

                    ## Decode and re-encode filename
                    $new_filename =
                        Sympa::Tools::qencode_filename(
                        Sympa::Tools::qdecode_filename($new_filename));

                    if ($new_filename ne $f_struct->{'filename'}) {
                        ## Rename file
                        my $orig_f =
                              $f_struct->{'directory'} . '/'
                            . $f_struct->{'filename'};
                        my $new_f =
                            $f_struct->{'directory'} . '/' . $new_filename;
                        Sympa::Log::Syslog::do_log('notice',
                            "Renaming %s to %s",
                            $orig_f, $new_f);
                        unless (rename $orig_f, $new_f) {
                            Sympa::Log::Syslog::do_log('err',
                                "Failed to rename %s to %s : %s",
                                $orig_f, $new_f, $ERRNO);
                            next;
                        }
                        $count++;
                    }
                }
                if ($count) {
                    Sympa::Log::Syslog::do_log('notice',
                        'List %s : %d filenames has been changed',
                        $list->name, $count);
                }
            }
        }

    }
    if (Sympa::Tools::lower_version($previous_version, '6.3a')) {

        # move spools from file to database.
        my %spools_def = (
            'queue'           => 'msg',
            'queuebounce'     => 'bounce',
            'queuedistribute' => 'msg',
            'queuedigest'     => 'digest',
            'queuemod'        => 'mod',
            'queuesubscribe'  => 'subscribe',
            'queuetopic'      => 'topic',
            'queueautomatic'  => 'automatic',
            'queueauth'       => 'auth',
            'queueoutgoing'   => 'archive',
            'queuetask'       => 'task'
        );
        if (Sympa::Tools::lower_version($previous_version, '6.1.11')) {
            ## Exclusion table was not robot-enabled.
            Sympa::Log::Syslog::do_log('notice',
                'fixing robot column of exclusion table.');
            my $sth = Sympa::DatabaseManager::do_query(q{SELECT * FROM exclusion_table});
            unless ($sth) {
                Sympa::Log::Syslog::do_log('err',
                    'Unable to gather informations from the exclusions table.'
                );
            }
            my @robots = @{Sympa::Robot::get_robots() || []};
            while (my $data = $sth->fetchrow_hashref) {
                next
                    if defined $data->{'robot_exclusion'}
                        and $data->{'robot_exclusion'} ne '';
                ## Guessing right robot for each exclusion.
                my $valid_robot = '';
                my @valid_robot_candidates;
                foreach my $robot (@robots) {
                    if (my $list =
                        Sympa::List->new($data->{'list_exclusion'}, $robot)) {
                        if ($list->is_list_member($data->{'user_exclusion'}))
                        {
                            push @valid_robot_candidates, $robot;
                        }
                    }
                }
                if ($#valid_robot_candidates == 0) {
                    $valid_robot = $valid_robot_candidates[0];
                    my $sth = Sympa::DatabaseManager::do_query(
                        q{UPDATE exclusion_table
			  SET robot_exclusion = %s
			  WHERE list_exclusion = %s AND user_exclusion = %s},
                        Sympa::DatabaseManager::quote($valid_robot->domain),
                        Sympa::DatabaseManager::quote($data->{'list_exclusion'}),
                        Sympa::DatabaseManager::quote($data->{'user_exclusion'})
                    );
                    unless ($sth) {
                        Sympa::Log::Syslog::do_log(
                            'err',
                            'Unable to update entry (%s,%s) in exclusions table (trying to add robot %s)',
                            $data->{'list_exclusion'},
                            $data->{'user_exclusion'},
                            $valid_robot
                        );
                    }
                } else {
                    Sympa::Log::Syslog::do_log(
                        'err',
                        "Exclusion robot could not be guessed for user '%s' in list '%s'. Either this user is no longer subscribed to the list or the list appears in more than one robot (or the query to the database failed). Here is the list of robots in which this list name appears: '%s'",
                        $data->{'user_exclusion'},
                        $data->{'list_exclusion'},
                        join(
                            ', ', map { $_->domain } @valid_robot_candidates
                        )
                    );
                }
            }
            ## Caching all list config
            Sympa::Log::Syslog::do_log('notice',
                'Caching all list config to database...');
            Sympa::List::get_lists('Site', {'reload_config' => 1});
            Sympa::Log::Syslog::do_log('notice', '...done');
        }

        foreach my $spoolparameter (keys %spools_def) {

            # task is to be done later
            next if ($spoolparameter eq 'queuetask');

            my $spooldir = Sympa::Site->$spoolparameter;

            unless (-d $spooldir) {
                Sympa::Log::Syslog::do_log(
                    'info',
                    "Could not perform migration of spool %s because it is not a directory",
                    $spoolparameter
                );
                next;
            }
            Sympa::Log::Syslog::do_log('notice',
                'Performing upgrade for spool %s', $spooldir);

            my $spool = Sympa::Spool->new($spools_def{$spoolparameter});
            if (!opendir(DIR, $spooldir)) {
                croak sprintf("Can't open dir %s: %s", $spooldir, $ERRNO);
                ## No return.
            }
            my @qfile = sort Sympa::Tools::by_date grep (!/^\./, readdir(DIR));
            closedir(DIR);
            my $filename;
            my $listname;
            my $robot_id;

            my $ignored   = '';
            my $performed = '';

            ## Scans files in queue
            foreach my $filename (sort @qfile) {
                my $type;
                my $list;
                my ($listname, $robot_id, $robot);
                my %meta;

                Sympa::Log::Syslog::do_log('notice',
                    " spool : $spooldir, file $filename");
                if (-d $spooldir . '/' . $filename) {
                    Sympa::Log::Syslog::do_log('notice',
                        "%s/%s est un répertoire",
                        $spooldir, $filename);
                    next;
                }

                if (($spoolparameter eq 'queuedigest')) {
                    unless ($filename =~ /^([^@]*)\@([^@]*)$/) {
                        $ignored .= ',' . $filename;
                        next;
                    }
                    $listname     = $1;
                    $robot_id     = $2;
                    $meta{'date'} = (stat($spooldir . '/' . $filename))[9];
                } elsif ($spoolparameter eq 'queueauth'
                    or $spoolparameter eq 'queuemod') {
                    unless ($filename =~ /^([^@]*)\@([^@]*)\_(.*)$/) {
                        $ignored .= ',' . $filename;
                        next;
                    }
                    $listname        = $1;
                    $robot_id        = $2;
                    $meta{'authkey'} = $3;
                    $meta{'date'}    = (stat($spooldir . '/' . $filename))[9];
                } elsif ($spoolparameter eq 'queuetopic') {
                    unless ($filename =~ /^([^@]*)\@([^@]*)\_(.*)$/) {
                        $ignored .= ',' . $filename;
                        next;
                    }
                    $listname        = $1;
                    $robot_id        = $2;
                    $meta{'authkey'} = $3;
                    $meta{'date'}    = (stat($spooldir . '/' . $filename))[9];
                } elsif ($spoolparameter eq 'queuesubscribe') {
                    my $match = 0;
                    foreach my $robot (@{Sympa::Robot::get_robots()}) {
                        my $robot_id = $robot->domain;
                        Sympa::Log::Syslog::do_log('notice', 'robot : %s',
                            $robot_id);
                        if ($filename =~ /^([^@]*)\@$robot_id\.(.*)$/) {
                            $listname = $1;
                            $meta{'authkey'} = $2;
                            $meta{'date'} =
                                (stat($spooldir . '/' . $filename))[9];
                            $match = 1;
                        }
                    }
                    unless ($match) { $ignored .= ',' . $filename; next; }
                } elsif ($spoolparameter eq 'queue'
                    or $spoolparameter eq 'queuebounce') {
                    ## Don't process temporary files created by queue
                    ## bouncequeue queueautomatic (T.xxx)
                    next if ($filename =~ /^T\./);

                    unless ($filename =~ /^(\S+)\.(\d+)\.\w+$/) {
                        $ignored .= ',' . $filename;
                        next;
                    }
                    my $recipient = $1;
                    ($listname, $robot_id) = split /\@/, $recipient;
                    $meta{'date'} = $2;
                    $robot_id = lc($robot_id || Sympa::Site->domain);
                    ## check if robot exists
                    unless ($robot = Sympa::Robot->new($robot_id)) {
                        $ignored .= ',' . $filename;
                        next;
                    }

                    if ($spoolparameter eq 'queue') {
                        my ($name, $type) = $robot->split_listname($listname);
                        if ($name) {
                            $listname = $name;
                            $meta{'type'} = $type if $type;

                            my $email = $robot->email;
                            my $host  = Sympa::Site->host;

                            my $priority;

                            if ($listname eq $robot->listmaster_email) {
                                $priority = 0;
                            } elsif ($type eq 'request') {
                                $priority = $robot->request_priority;
                            } elsif ($type eq 'owner') {
                                $priority = $robot->owner_priority;
                            } elsif (
                                $listname =~ /^(sympa|$email)(\@$host)?$/i) {
                                $priority = $robot->sympa_priority;
                                $listname = '';
                            }
                            $meta{'priority'} = $priority;
                        }
                    }
                }

                $listname = lc($listname);
                $robot_id = lc($robot_id || Sympa::Site->domain);
                ## check if robot exists
                unless ($robot = Sympa::Robot->new($robot_id)) {
                    $ignored .= ',' . $filename;
                    next;
                }

                $meta{'robot'} = $robot_id if $robot_id;
                $meta{'list'}  = $listname if $listname;
                $meta{'priority'} = 1 unless $meta{'priority'};

                unless (open FILE, $spooldir . '/' . $filename) {
                    Sympa::Log::Syslog::do_log('err',
                        'Cannot open message file %s : %s',
                        $filename, $ERRNO);
                    return undef;
                }
                my $messageasstring;
                while (<FILE>) {
                    $messageasstring = $messageasstring . $_;
                }
                close(FILE);

                ## Store into DB spool
                unless ($spoolparameter eq 'queue'
                    or $spoolparameter eq 'queueautomatic'
                    or $spoolparameter eq 'queuebounce'
                    or $spoolparameter eq 'queuemod'
                    or $spoolparameter eq 'queueoutgoing') {
                    my $messagekey = $spool->store($messageasstring, \%meta);
                    unless ($messagekey) {
                        Sympa::Log::Syslog::do_log('err',
                            'Could not load message %s/%s in db spool',
                            $spooldir, $filename);
                        next;
                    }
                }

                ## Move HTML view of pending messages
                if ($spoolparameter eq 'queuemod') {
                    my $html_view_dir = $spooldir . '/.' . $filename;
                    my $list_html_view_dir =
                          Sympa::Site->viewmail_dir . '/mod/'
                        . $listname . '@'
                        . $robot_id;
                    my $new_html_view_dir =
                        $list_html_view_dir . '/' . $meta{'authkey'};
                    unless (Sympa::Tools::mkdir_all($list_html_view_dir, 0755)) {
                        Sympa::Log::Syslog::do_log(
                            'err',
                            'Could not create list html view directory %s: %s',
                            $list_html_view_dir,
                            $ERRNO
                        );
                        exit 1;
                    }
                    unless (
                        File::Copy::Recursive::dircopy(
                            $html_view_dir, $new_html_view_dir
                        )
                        ) {
                        Sympa::Log::Syslog::do_log('err',
                            'Could not rename %s to %s: %s',
                            $html_view_dir, $new_html_view_dir, $ERRNO);
                        exit 1;
                    }
                }

                ## Clear filesystem spool
                unless ($spoolparameter eq 'queue'
                    or $spoolparameter eq 'queueautomatic'
                    or $spoolparameter eq 'queuebounce'
                    or $spoolparameter eq 'queuemod'
                    or $spoolparameter eq 'queueoutgoing') {
                    mkdir $spooldir . '/copy_by_upgrade_process/'
                        unless -d $spooldir . '/copy_by_upgrade_process/';

                    my $source = $spooldir . '/' . $filename;
                    my $goal =
                        $spooldir . '/copy_by_upgrade_process/' . $filename;

                    Sympa::Log::Syslog::do_log('notice', 'source %s, goal %s',
                        $source, $goal);

                    # unless (File::Copy::copy($spooldir.'/'.$filename,
                    #     $spooldir.'/copy_by_upgrade_process/'.$filename)) {
                    unless (File::Copy::copy($source, $goal)) {
                        Sympa::Log::Syslog::do_log('err',
                            'Could not rename %s to %s: %s',
                            $source, $goal, $ERRNO);
                        exit 1;
                    }

                    unless (unlink($spooldir . '/' . $filename)) {
                        Sympa::Log::Syslog::do_log('err',
                            'Could not unlink message %s/%s. Exiting',
                            $spooldir, $filename);
                    }
                    $performed .= ',' . $filename;
                }
            }
            Sympa::Log::Syslog::do_log('info',
                "Upgrade process for spool %s : ignored files %s",
                $spooldir, $ignored);
            Sympa::Log::Syslog::do_log('info',
                "Upgrade process for spool %s : performed files %s",
                $spooldir, $performed);
        }
    }

    ## We have obsoleted wwsympa.conf.  It would be migrated to sympa.conf.
    if (Sympa::Tools::lower_version($previous_version, '6.2a.33')) {
        my $sympa_conf   = Sympa::Conf::get_sympa_conf();
        my $wwsympa_conf = Sympa::Conf::get_wwsympa_conf();
        my $fh;
        my %migrated = ();
        my @newconf  = ();
        my $date;

        ## Some sympa.conf parameters were overridden by wwsympa.conf.
        ## Others prefer sympa.conf.
        my %wwsconf_override = (
            'arc_path'                   => 'yes',
            'archive_default_index'      => 'yes',
            'bounce_path'                => 'yes',
            'cookie_domain'              => 'NO',
            'cookie_expire'              => 'yes',
            'cookie_refresh'             => 'yes',    # 6.1.17+
            'custom_archiver'            => 'yes',
            'default_home'               => 'NO',
            'export_topics'              => 'yes',
            'html_editor_file'           => 'NO',     # 6.2a
            'html_editor_init'           => 'NO',
            'ldap_force_canonical_email' => 'NO',
            'log_facility'               => 'yes',
            'mhonarc'                    => 'yes',
            'password_case'              => 'NO',
            'review_page_size'           => 'yes',
            'title'                      => 'NO',
            'use_fast_cgi'               => 'yes',
            'use_html_editor'            => 'NO',
            'viewlogs_page_size'         => 'yes',
            'wws_path'                   => undef,
        );
        ## Old params
        my %old_param = (
            'alias_manager' => 'No more used, using ' . Sympa::Site->alias_manager,
            'wws_path'      => 'No more used',
            'icons_url' =>
                'No more used. Using static_content/icons instead.',
            'robots' =>
                'Not used anymore. Robots are fully described in their respective robot.conf file.',
            'htmlarea_url'         => 'No longer supported',
            'archived_pidfile'     => 'No more used',
            'bounced_pidfile'      => 'No more used',
            'task_manager_pidfile' => 'No more used',
        );

        ## Set language of new file content
        Sympa::Language::PushLang(Sympa::Site->lang);
        $date =
            Sympa::Language::gettext_strftime("%d.%b.%Y-%H.%M.%S", localtime time);

        if (-r $wwsympa_conf) {
            ## load only sympa.conf
            my $conf = Sympa::Conf::load_robot_conf(
                {'robot' => '*', 'no_db' => 1, 'return_result' => 1});

            my %infile = ();
            ## load defaults
            foreach my $p (@Sympa::ConfDef::params) {
                next unless $p->{'name'};
                next unless $p->{'file'};
                next unless $p->{'file'} eq 'wwsympa.conf';
                $infile{$p->{'name'}} = $p->{'default'};
            }
            ## get content of wwsympa.conf
            open my $fh, '<', $wwsympa_conf;
            while (<$fh>) {
                next if /^\s*#/;
                chomp $_;
                next unless /^\s*(\S+)\s+(.+)$/i;
                my ($k, $v) = ($1, $2);
                $infile{$k} = $v;
            }
            close $fh;

            my $name;
            foreach my $p (@Sympa::ConfDef::params) {
                next unless $p->{'name'};
                $name = $p->{'name'};
                next unless exists $infile{$name};

                unless ($p->{'file'} and $p->{'file'} eq 'wwsympa.conf') {
                    ## may it exist in wwsympa.conf?
                    $migrated{'unknown'} ||= {};
                    $migrated{'unknown'}->{$name} = [$p, $infile{$name}];
                } elsif (exists $conf->{$name}) {
                    if ($wwsconf_override{$name} eq 'yes') {
                        ## does it override sympa.conf?
                        $migrated{'override'} ||= {};
                        $migrated{'override'}->{$name} = [$p, $infile{$name}];
                    } elsif (defined $conf->{$name}) {
                        ## or, is it there in sympa.conf?
                        $migrated{'duplicate'} ||= {};
                        $migrated{'duplicate'}->{$name} =
                            [$p, $infile{$name}];
                    } else {
                        ## otherwise, use values in wwsympa.conf
                        $migrated{'add'} ||= {};
                        $migrated{'add'}->{$name} = [$p, $infile{$name}];
                    }
                } else {
                    ## otherwise, use values in wwsympa.conf
                    $migrated{'add'} ||= {};
                    $migrated{'add'}->{$name} = [$p, $infile{$name}];
                }
                delete $infile{$name};
            }
            ## obsoleted or unknown parameters
            foreach my $name (keys %infile) {
                if ($old_param{$name}) {
                    $migrated{'obsolete'} ||= {};
                    $migrated{'obsolete'}->{$name} = [
                        {'name' => $name, 'gettext_id' => $old_param{$name}},
                        $infile{$name}
                    ];
                } else {
                    $migrated{'unknown'} ||= {};
                    $migrated{'unknown'}->{$name} = [
                        {   'name'       => $name,
                            'gettext_id' => "Unknown parameter"
                        },
                        $infile{$name}
                    ];
                }
            }
        }

        ## Add contents to sympa.conf
        if (%migrated) {
            open $fh, '<', $sympa_conf or die $ERRNO;
            @newconf = <$fh>;
            close $fh;
            $newconf[$#newconf] .= "\n" unless $newconf[$#newconf] =~ /\n\z/;

            push @newconf,
                  "\n"
                . ('#' x 76) . "\n" . '#### '
                . Sympa::Language::gettext("Migration from wwsympa.conf") . "\n"
                . '#### '
                . $date . "\n"
                . ('#' x 76) . "\n\n";

            foreach my $type (qw(duplicate add obsolete unknown)) {
                my %newconf = %{$migrated{$type} || {}};
                next unless scalar keys %newconf;

                push @newconf,
                    Sympa::Tools::wrap_text(
                    Sympa::Language::gettext(
                        "Migrated Parameters\nFollowing parameters were migrated from wwsympa.conf."
                    ),
                    '#### ', '#### '
                    )
                    . "\n"
                    if $type eq 'add';
                push @newconf,
                    Sympa::Tools::wrap_text(
                    Sympa::Language::gettext(
                        "Overriding Parameters\nFollowing parameters existed both in sympa.conf and wwsympa.conf.  Previous release of Sympa used those in wwsympa.conf.  Comment-out ones you wish to be disabled."
                    ),
                    '#### ', '#### '
                    )
                    . "\n"
                    if $type eq 'override';
                push @newconf,
                    Sympa::Tools::wrap_text(
                    Sympa::Language::gettext(
                        "Duplicate of sympa.conf\nThese parameters were found in both sympa.conf and wwsympa.conf.  Previous release of Sympa used those in sympa.conf.  Uncomment ones you wish to be enabled."
                    ),
                    '#### ', '#### '
                    )
                    . "\n"
                    if $type eq 'duplicate';
                push @newconf,
                    Sympa::Tools::wrap_text(
                    Sympa::Language::gettext(
                        "Old Parameters\nThese parameters are no longer used."
                    ),
                    '#### ', '#### '
                    )
                    . "\n"
                    if $type eq 'obsolete';
                push @newconf,
                    Sympa::Tools::wrap_text(
                    Sympa::Language::gettext(
                        "Unknown Parameters\nThough these parameters were found in wwsympa.conf, they were ignored.  You may simply remove them."
                    ),
                    '#### ', '#### '
                    )
                    . "\n"
                    if $type eq 'unknown';

                foreach my $k (sort keys %newconf) {
                    my ($param, $v) = @{$newconf{$k}};

                    push @newconf,
                        Sympa::Tools::wrap_text(
                        Sympa::Language::gettext($param->{'gettext_id'}),
                        '## ', '## ')
                        if defined $param->{'gettext_id'};
                    push @newconf,
                        Sympa::Tools::wrap_text(
                        Sympa::Language::gettext($param->{'gettext_comment'}),
                        '## ', '## ')
                        if defined $param->{'gettext_comment'};
                    if (defined $v
                        and ($type eq 'add' or $type eq 'override')) {
                        push @newconf,
                            sprintf("%s\t%s\n\n", $param->{'name'}, $v);
                    } else {
                        push @newconf,
                            sprintf("#%s\t%s\n\n", $param->{'name'}, $v);
                    }
                }
            }
        }

        ## Restore language
        Sympa::Language::PopLang();

        if (%migrated) {
            warn sprintf("Unable to rename %s : %s", $sympa_conf, $ERRNO)
                unless rename $sympa_conf, "$sympa_conf.$date";
            ## Write new config files
            my $umask = umask 037;
            unless (open $fh, '>', $sympa_conf) {
                umask $umask;
                die sprintf("Unable to open %s : %s", $sympa_conf, $ERRNO);
            }
            umask $umask;
            chown [getpwnam(Sympa::Constants::USER)]->[2],
                [getgrnam(Sympa::Constants::GROUP)]->[2], $sympa_conf;
            print $fh @newconf;
            close $fh;

            ## Keep old config file
            printf
                "%s has been updated.\nPrevious version has been saved as %s.\n",
                $sympa_conf, "$sympa_conf.$date";
        }

        if (-r $wwsympa_conf) {
            ## Keep old config file
            warn sprintf("Unable to rename %s : %s", $wwsympa_conf, $ERRNO)
                unless rename $wwsympa_conf, "$wwsympa_conf.$date";
            printf
                "%s will NO LONGER be used.\nPrevious version has been saved as %s.\n",
                $wwsympa_conf, "$wwsympa_conf.$date";
        }
    }

    return 1;
}

##DEPRECATED: Use Sympa::DatabaseManager::probe_db().
##sub probe_db {
##    Sympa::DatabaseManager::probe_db();
##}

##DEPRECATED: Use Sympa::DatabaseManager::data_structure_uptodate().
##sub data_structure_uptodate {
##    Sympa::DatabaseManager::data_structure_uptodate();
##}

## used to encode files to UTF-8
## also add X-Attach header field if template requires it
## IN : - arrayref with list of filepath/lang pairs
sub to_utf8 {
    my $files = shift;

    my $with_attachments =
        qr{ archive.tt2 | digest.tt2 | get_archive.tt2 | listmaster_notification.tt2 | 
				   message_report.tt2 | moderate.tt2 |  modindex.tt2 | send_auth.tt2 }x;
    my $total;

    foreach my $pair (@{$files}) {
        my ($file, $lang) = @$pair;
        unless (open(TEMPLATE, $file)) {
            Sympa::Log::Syslog::do_log('err', "Cannot open template %s",
                $file);
            next;
        }

        my $text     = '';
        my $modified = 0;

        ## If filesystem_encoding is set, files are supposed to be encoded
        ## according to it
        my $charset;
        if ((defined $Sympa::Conf::Ignored_Conf{'filesystem_encoding'}) &
            ($Sympa::Conf::Ignored_Conf{'filesystem_encoding'} ne 'utf-8')) {
            $charset = $Sympa::Conf::Ignored_Conf{'filesystem_encoding'};
        } else {
            Sympa::Language::PushLang($lang);
            $charset = Sympa::Language::GetCharset;
            Sympa::Language::PopLang;
        }

        # Add X-Sympa-Attach: headers if required.
        if (($file =~ /mail_tt2/) && ($file =~ /\/($with_attachments)$/)) {
            while (<TEMPLATE>) {
                $text .= $_;
                if (m/^Content-Type:\s*message\/rfc822/i) {
                    while (<TEMPLATE>) {
                        if (m{^X-Sympa-Attach:}i) {
                            $text .= $_;
                            last;
                        }
                        if (m/^[\r\n]+$/) {
                            $text .= "X-Sympa-Attach: yes\n";
                            $modified = 1;
                            $text .= $_;
                            last;
                        }
                        $text .= $_;
                    }
                }
            }
        } else {
            $text = join('', <TEMPLATE>);
        }
        close TEMPLATE;

        # Check if template is encoded by UTF-8.
        if ($text =~ /[^\x20-\x7E]/) {
            my $t = $text;
            eval { Encode::decode('UTF-8', $t, Encode::FB_CROAK); };
            if ($EVAL_ERROR) {
                eval {
                    $t = $text;
                    Encode::from_to($t, $charset, "UTF-8", Encode::FB_CROAK);
                };
                if ($EVAL_ERROR) {
                    Sympa::Log::Syslog::do_log('err',
                        "Template %s cannot be converted from %s to UTF-8",
                        $charset, $file);
                } else {
                    $text     = $t;
                    $modified = 1;
                }
            }
        }

        next unless $modified;

        my $date = strftime("%Y.%m.%d-%H.%M.%S", localtime(time));
        unless (rename $file, $file . '@' . $date) {
            Sympa::Log::Syslog::do_log('err', "Cannot rename old template %s",
                $file);
            next;
        }
        unless (open(TEMPLATE, ">$file")) {
            Sympa::Log::Syslog::do_log('err', "Cannot open new template %s",
                $file);
            next;
        }
        print TEMPLATE $text;
        close TEMPLATE;
        unless (
            Sympa::Tools::set_file_rights(
                file  => $file,
                user  => Sympa::Constants::USER,
                group => Sympa::Constants::GROUP,
                mode  => 0644,
            )
            ) {
            Sympa::Log::Syslog::do_log('err', 'Unable to set rights on %s',
                $file);
            next;
        }
        Sympa::Log::Syslog::do_log('notice',
            'Modified file %s ; original file kept as %s',
            $file, $file . '@' . $date);

        $total++;
    }

    return $total;
}

# md5_encode_password : Version later than 5.4 uses MD5 fingerprint instead of
# symetric crypto to store password.
#  This require to rewrite paassword in database. This upgrade IS NOT
#  REVERSIBLE
sub md5_encode_password {

    my $total = 0;

    Sympa::Log::Syslog::do_log('notice',
        'Upgrade::md5_encode_password() recoding password using MD5 fingerprint'
    );

    unless (Sympa::DatabaseManager::check_db_connect('just_try')) {
        return undef;
    }

    my $sth =
        Sympa::DatabaseManager::do_query(q{SELECT email_user, password_user FROM user_table});
    unless ($sth) {
        Sympa::Log::Syslog::do_log('err', 'Unable to execute SQL statement');
        return undef;
    }

    $total = 0;
    my $total_md5 = 0;

    while (my $user = $sth->fetchrow_hashref('NAME_lc')) {
        my $clear_password;
        if ($user->{'password_user'} =~ /^[0-9a-f]{32}/) {
            Sympa::Log::Syslog::do_log('info',
                'password from %s already encoded as MD5 fingerprint',
                $user->{'email_user'});
            $total_md5++;
            next;
        }

        ## Ignore empty passwords
        next if ($user->{'password_user'} =~ /^$/);

        if ($user->{'password_user'} =~ /^crypt.(.*)$/) {
            $clear_password =
                Sympa::Tools::decrypt_password($user->{'password_user'});
        } else {    ## Old style cleartext passwords
            $clear_password = $user->{'password_user'};
        }

        $total++;

        ## Updating Db
        unless (
            Sympa::DatabaseManager::do_query(
                q{UPDATE user_table
	      SET password_user = %s
	      WHERE email_user = %s},
                Sympa::DatabaseManager::quote(Sympa::Auth::password_fingerprint($clear_password)),
                Sympa::DatabaseManager::quote($user->{'email_user'})
            )
            ) {
            Sympa::Log::Syslog::do_log('err',
                'Unable to execute SQL statement');
            return undef;
        }
    }
    $sth->finish();

    Sympa::Log::Syslog::do_log(
        'info',
        "Updating password storage in table user_table using MD5 for %d users",
        $total
    );
    if ($total_md5) {
        Sympa::Log::Syslog::do_log(
            'info',
            "Found in table user %d password stored using MD5, did you run Sympa before upgrading ?",
            $total_md5
        );
    }
    return $total;
}

1;
