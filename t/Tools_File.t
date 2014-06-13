#!/usr/bin/perl
# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id: tools_file.t 8606 2013-02-06 08:44:02Z rousse $

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;
use Test::Exception;
use English qw(-no_match_vars);
use File::Temp;
use File::stat;
use Fcntl qw(:mode);

use Sympa::Logger::Memory;
use Sympa::Tools::File;

plan tests => 26;

our $logger = Sympa::Logger::Memory->new();

my $user  = getpwuid($UID);
my $group = getgrgid($GID);
my $file  = File::Temp->new(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);

ok(
    Sympa::Tools::File::set_file_rights(file => $file),
    'file, nothing else: ok'
);

ok(
    !Sympa::Tools::File::set_file_rights(file => $file, user => 'none'),
    'file, invalid user: ko'
);

ok(
    !Sympa::Tools::File::set_file_rights(file => $file, group => 'none'),
    'file, invalid group: ko'
);

ok(
    Sympa::Tools::File::set_file_rights(file => $file, mode => 999),
    'file, invalid mode: ok (fixme)'
);

ok(
    !Sympa::Tools::File::set_file_rights(file => $file, user => $user, group => 'none'),
    'file, valid user, invalid group: ko'
);

ok(
    !Sympa::Tools::File::set_file_rights(file => $file, user => 'none', group => $group),
    'file, invalid user, valid group: ko'
);

ok(
    Sympa::Tools::File::set_file_rights(file => $file, user => $user, group => $group),
    'file, valid user, valid group: ok'
);

ok(
    Sympa::Tools::File::set_file_rights(file => $file, user => $user, group => $group, mode => 0666),
    'file, valid user, valid group, valid mode: ok'
);

is(get_perms($file), "0666", "expected mode");

POSIX::setlocale( &POSIX::LC_ALL, "C" );
my $text = "Sympa rulez!";
my $filename;
{
    my $new_file = File::Temp->new(CLEANUP => $ENV{TEST_DEBUG} ? 0 : 1);
    print $new_file $text;
    $new_file->flush();
    $filename = $new_file->filename();

    is(Sympa::Tools::File::slurp_file($filename), $text, "slurp_file()");

    chmod 0000, $new_file;
    throws_ok {
        my $content = Sympa::Tools::File::slurp_file($filename);
    } qr/^Cannot open file \S+: Permission denied/,
    'slurp_file(), unreadable file';
}

throws_ok {
    my $content = Sympa::Tools::File::slurp_file($filename);
} qr/^Cannot open file \S+: No such file or directory/,
'slurp_file(), non-existing file';

my $dir;

$dir = File::Temp->newdir();
Sympa::Tools::File::del_dir($dir);
ok(!-d $dir, 'del_dir with empty dir');

$dir = File::Temp->newdir();
Sympa::Tools::File::remove_dir($dir);
ok(!-d $dir, 'remove_dir with empty dir');

$dir = File::Temp->newdir();
touch($dir .'/foo');
Sympa::Tools::File::del_dir($dir);
ok(!-d $dir, 'del_dir with non empty dir');

$dir = File::Temp->newdir();
touch($dir .'/foo');
Sympa::Tools::File::remove_dir($dir);
ok(!-d $dir, 'remove_dir with non empty dir');

$dir = File::Temp->newdir();
Sympa::Tools::File::mk_parent_dir($dir . '/foo/bar/baz');
ok(-d "$dir/foo", 'mk_parent_dir first element');
ok(-d "$dir/foo/bar", 'mk_parent_dir second element');

$dir = File::Temp->newdir();
Sympa::Tools::File::mkdir_all($dir . '/foo/bar/baz');
ok(-d "$dir/foo", 'mkdir_all first directory presence');
is(get_perms("$dir/foo"), "0777", "mkdir_all first directory expected mode");
ok(-d "$dir/foo/bar", 'mkdir_all second directory presence');
is(get_perms("$dir/foo/bar"), "0777", "mkdir_all second directory expected mode");

$dir = File::Temp->newdir();
Sympa::Tools::File::mkdir_all($dir . '/foo/bar/baz', 0755);
ok(-d "$dir/foo", 'mkdir_all first directory presence');
is(get_perms("$dir/foo"), "0755", "mkdir_all first directory expected mode");
ok(-d "$dir/foo/bar", 'mkdir_all second directory presence');
is(get_perms("$dir/foo/bar"), "0755", "mkdir_all second directory expected mode");

sub touch {
    my ($file) = @_;
    open (my $fh, '>', $file) or die "Can't create file: $ERRNO";
    close $fh;
}

sub get_perms {
    my ($file) = @_;
    return sprintf("%04o", stat($file)->mode() & 07777);
}
