#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'CPC::Palmer' ) || print "Bail out!\n";
}

diag( "Testing CPC::Palmer $CPC::Palmer::VERSION, Perl $], $^X" );
