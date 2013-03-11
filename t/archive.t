#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use File::Copy;
use File::Temp;
use Test::More;

use Sympa::Archive;

plan tests => 1;

my $archive_root = File::Temp->newdir();
my $archive_dir = $archive_root . '/foo';
mkdir $archive_dir;
foreach my $file (<t/samples/*.eml>) {
	copy($file, $archive_dir);
}

my $result = Sympa::Archive::clean_archive_directory({
	arc_root       => $archive_root,
	dir_to_rebuild => 'foo',
	tmpdir         => '/tmp'
});
ok($result);
