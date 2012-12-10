#!/usr/bin/perl

use strict;
use warnings;
use lib 'src/lib';

use Test::More;
use English qw(-no_match_vars);
use File::Temp;
use File::stat;
use Fcntl qw(:mode);

use Sympa::Tools::File;

plan tests => 21;

my $user  = getpwuid($UID);
my $group = getgrgid($GID);
my $file  = File::Temp->new();

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
ok(!-d "$dir/foo", 'mkdir_all first element, no mode');
ok(!-d "$dir/foo/bar", 'mkdir_all second element, no mode');

$dir = File::Temp->newdir();
Sympa::Tools::File::mkdir_all($dir . '/foo/bar/baz', 0777);
ok(-d "$dir/foo", 'mkdir_all first element');
ok(-d "$dir/foo/bar", 'mkdir_all second element');
is(get_perms("$dir/foo"), "0777", "first element, expected mode");
is(get_perms("$dir/foo/bar"), "0777", "second element, expected mode");

sub touch {
    my ($file) = @_;
    open (my $fh, '>', $file) or die "Can't create file: $ERRNO";
    close $fh;
}

sub get_perms {
    my ($file) = @_;
    return sprintf("%04o", stat($file)->mode() & 07777);
}
