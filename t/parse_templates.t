# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

use strict;
use warnings;
use Cwd qw();
use English qw(-no_match_vars);
use Test::More;
use XML::LibXML;

use Sympa::Template;

my $params = {
    all_lists   => {size => 2},
    languages   => {size => 2},
    total_group => 2,
    rows        => 2,
    reply_to_header => {value => 'all', other_email => 'xxx@xxx',},
};

my @def_tt2 = _templates('default', '*.tt2 sympa.wsdl');
my @list_tt2 = _templates('default/create_list_templates', '*/*.tt2');
my @mail_tt2 = _templates('default/mail_tt2',              '*.tt2 */*.tt2');
my @web_tt2  = _templates('default/web_tt2',               '*.tt2 */*.tt2');

plan tests => scalar @def_tt2 + scalar @list_tt2 + scalar @mail_tt2 +
    scalar @web_tt2;

map { is _do_test('default',                       $_), '', $_ } @def_tt2;
map { is _do_test('default/create_list_templates', $_), '', $_ } @list_tt2;
map { is _do_test('default/mail_tt2',              $_), '', $_ } @mail_tt2;
map { is _do_test('default/web_tt2',               $_), '', $_ } @web_tt2;

sub _templates {
    my $dir = shift;
    my $pattern = shift || '*.tt2';

    my $cwd = Cwd::getcwd();
    chdir $dir or die $ERRNO;
    my @files = glob $pattern;
    chdir $cwd;
    return @files;
}

sub _do_test {
    my $dir = shift;
    my $tpl = shift;

    if ($tpl eq 'mhonarc-ressources.tt2') {
        open my $fh, '<', $dir . '/' . $tpl;
        $tpl = do { local $RS; <$fh> };
        close $fh;
        $tpl =~ s/\$(PAGENUM|NUMOFPAGES)\$/2/g;
        $tpl = [split /(?<=\n)/, $tpl];
    }

    my $template = Sympa::Template->new('*', include_path => [$dir]);
    my $scalar;
    if ($template->parse($params, $tpl, \$scalar)) {
        # Also check XML syntax.
        if (not ref $tpl and $tpl eq 'sympa.wsdl') {
            eval { XML::LibXML->load_xml(string => $scalar) }
                or return $EVAL_ERROR;
        }
        return '';
    } else {
        return $template->{last_error};
    }
}
