#!/usr/bin/perl

use strict;
use warnings;
use lib 'src/lib';

use Test::More;

use Sympa::Tools::Data;

my @array_from_string_tests = (
    [ 'foo,bar,baz'       => [ qw/foo bar baz/ ] ],
    [ ' foo, bar, baz'    => [ qw/foo bar baz/ ] ],
    [ 'foo ,bar ,baz '    => [ qw/foo bar baz/ ] ],
    [ ' foo , bar , baz ' => [ qw/foo bar baz/ ] ],
);

my @string_2_hash_tests = (
    [ 'var1="value1";var2="value2";' => { var1 => "value1", var2 => "value2" } ],
    [ ';var1="value1";var2="value2"' => { var1 => "value1", var2 => "value2" } ]
);

my @hash_2_string_tests = (
    [ { var1 => "value1", var2 => "value2" } => ';var1="value1";var2="value2"' ]
);

my @lower_version_ok_tests = (
    [ [ qw/1.0  2.0 / ] ],
    [ [ qw/2.0  2.1 / ] ],
    [ [ qw/2.1  2.10/ ] ],
    [ [ qw/1.0a 1.0 / ] ],
    [ [ qw/1.0b 1.0 / ] ],
    [ [ qw/1.0a 1.0b/ ] ],
);

my @lower_version_nok_tests = (
    [ [ qw/2.0  1.0 / ] ],
    [ [ qw/2.1  2.0 / ] ],
    [ [ qw/2.10 2.1 / ] ],
    [ [ qw/1.0  1.0a/ ] ],
    [ [ qw/1.0  1.0b/ ] ],
    [ [ qw/1.0b 1.0a/ ] ],
    [ [ qw/1.0  1.0 / ] ],
);

my @smart_lessthan_ok_tests = (
    [ [ "", "1" ] ],
    [ [ "1", "2" ] ],
    [ [ " 1 ", " 2 " ] ],
);

my @smart_lessthan_nok_tests = (
    [ [ "", "" ] ],
    [ [ "1", "" ] ],
    [ [ "1", "1" ] ],
    [ [ "2", "1" ] ],
    [ [ " 2 ", " 1 " ] ],
);

my @diff_on_arrays_tests = (
    [ 
        [ [], [] ] => {
            intersection => [],
            union        => [],
            added        => [],
            deleted      => []
        }
    ],
    [
        [ [ 'a' ], [ 'a' ] ] => {
            intersection => [ 'a' ],
            union        => [ 'a' ],
            added        => [ ],
            deleted      => [ ]
        }
    ],
    [ 
        [ [ 'a' ], [ 'b' ] ] => {
            intersection => [],
            union        => [ 'a', 'b' ],
            added        => [ 'b' ],
            deleted      => [ 'a' ]
        }
    ] 
);

my @remove_empty_entries_tests = (
    [ ''                     => [ 0, ''                       ] ],
    [ 'a'                    => [ 1, 'a'                      ] ],
    [ [                    ] => [ 0, [                      ] ] ],
    [ [ 'a'                ] => [ 1, [ 'a'                  ] ] ],
    [ [ 'a', ''            ] => [ 1, [ 'a', undef           ] ] ],
    [ [ 'a', '', 'b'       ] => [ 1, [ 'a', undef, 'b'      ] ] ],
    [ {                    } => [ 0, {                      } ] ],
    [ { a => 'a'           } => [ 1, { a => 'a'             } ] ],
    [ { a => 'a', b => ''  } => [ 1, { a => 'a', b => undef } ] ],
    [ { a => 'a', b => 'b' } => [ 1, { a => 'a', b => 'b'   } ] ],
);

my @recursive_transformation_tests = (
    [ ''                              => ''                                ],
    [ 'a'                             => 'a'                               ],
    [ [                    ]          => [                               ] ],
    [ [ 'a'                ]          => [ 'aa'                          ] ],
    [ [ 'a', ''            ]          => [ 'aa', ''                      ] ],
    [ [ 'a', '', 'b'       ]          => [ 'aa', '', 'bb'                ] ],
    [ {                    }          => {                               } ],
    [ { a => 'a'           }          => { a => 'aa'                     } ],
    [ { a => 'a', b => ''  }          => { a => 'aa', b => ''            } ],
    [ { a => 'a', b => 'b' }          => { a => 'aa', b => 'bb'          } ],
    [ [ 'a', [ 'a' ], {  a => 'a' } ] => [ 'aa', [ 'aa' ], { a => 'aa' } ] ],
);

plan tests =>
    @array_from_string_tests       +
    @string_2_hash_tests           +
    @hash_2_string_tests           +
    @lower_version_ok_tests        +
    @lower_version_nok_tests       +
    @smart_lessthan_ok_tests       +
    @smart_lessthan_nok_tests      +
    @diff_on_arrays_tests          +
    @recursive_transformation_tests ;

foreach my $test (@array_from_string_tests) {
    is_deeply(
    Sympa::Tools::Data::get_array_from_splitted_string($test->[0]),
        $test->[1],
        "get_array_from_splitted_string $test->[0]"
    );
}

foreach my $test (@string_2_hash_tests) {
    is_deeply(
        { Sympa::Tools::Data::string_2_hash($test->[0]) },
        $test->[1],
        "string_2_hash $test->[0]"
    );
}

foreach my $test (@hash_2_string_tests) {
    is(
        Sympa::Tools::Data::hash_2_string($test->[0]),
        $test->[1],
        "hash_2_string $test->[0]"
    );
}

foreach my $test (@lower_version_ok_tests) {
    ok(
        Sympa::Tools::Data::lower_version(@{$test->[0]}),
        "lower_version $test->[0]->[0], $test->[0]->[1]"
    );
}

foreach my $test (@lower_version_nok_tests) {
    ok(
        !Sympa::Tools::Data::lower_version(@{$test->[0]}),
        "!lower_version $test->[0]->[0], $test->[0]->[1]"
    );
}

foreach my $test (@smart_lessthan_ok_tests) {
    ok(
        Sympa::Tools::Data::smart_lessthan(@{$test->[0]}),
        "smart_lessthan $test->[0]->[0], $test->[0]->[1]"
    );
}

foreach my $test (@smart_lessthan_nok_tests) {
    ok(
        !Sympa::Tools::Data::smart_lessthan(@{$test->[0]}),
        "smart_lessthan $test->[0]->[0], $test->[0]->[1]"
    );
}

foreach my $test (@diff_on_arrays_tests) {
    is_deeply(
        Sympa::Tools::Data::diff_on_arrays(@{$test->[0]}),
        $test->[1],
        "diff_in_arrays $test->[0]"
    );
}

my $transformation = sub { return $_[0] . $_[0] };
foreach my $test (@recursive_transformation_tests) {
    Sympa::Tools::Data::recursive_transformation($test->[0], $transformation);
    is_deeply(
        $test->[0],
        $test->[1],
        "recursive_transformation $test->[0]"
   );
}
