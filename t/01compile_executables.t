#!/usr/bin/perl

use strict;
use warnings;
use lib 'src/lib';

use English qw(-no_match_vars);
use Test::More;

eval {
    require Test::Compile;
    Test::Compile->import();
};
if ($EVAL_ERROR) {
    my $msg = 'Test::Compile required';
    plan(skip_all => $msg);
}

my @files = map { './src/sbin/' . $_ } qw/
    alias_manager.pl bulk.pl spooler.pl sympa.pl sympa_wizard.pl
/;

$ENV{PERL5LIB} = $ENV{PERL5LIB} ? "$ENV{PERL5LIB}:src/lib" : "src/lib";
all_pl_files_ok(@files);
