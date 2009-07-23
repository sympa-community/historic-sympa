#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use Test::Pod qw(no_plan);
use File::Find;

my $test = sub {
    return unless $_ =~ /\.pod$/;
    my $file = $File::Find::name;
    $file =~ s/\.\///;
    pod_file_ok($file);
};
chdir "$Bin/../doc/man8";
find($test, '.');
