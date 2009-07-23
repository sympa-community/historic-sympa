#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use Test::Simple tests => 9;
use IPC::Run3;

chdir "$Bin/..";

my @src_scripts = map { "src/$_" } qw/
    sympa.pl sympa_wizard.pl task_manager.pl alias_manager.pl
/;

my @wwsympa_scripts = map { "wwsympa/$_" } qw/
    archived.pl bounced.pl wwsympa.fcgi
/;

my @soap_scripts = map { "soap/$_" } qw/
    sympa_soap_client.pl sympa_soap_server.fcgi
/;

foreach my $script (
    @src_scripts, @wwsympa_scripts, @soap_scripts
) {
    my $cmd = [
        $^X, '-c',
        '-I', "src/lib",
        '-I', "wwsympa",
        $script
    ];
    my $stderr = '';
    my $rv = IPC::Run3::run3($cmd, \undef, \undef, \$stderr);
	my $ok = $stderr =~ /syntax OK\s+$/si;
	ok($ok, "$script compiles");
}
