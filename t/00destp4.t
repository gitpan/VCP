#!/usr/local/bin/perl -w

=head1 NAME

destp4.t - testing for VCP::Dest::p4 routines (not overal functionality).

=cut

use strict ;

use Carp ;
use Test ;
require VCP::Dest::p4 ;

my $p = "VCP::Dest::p4" ;

my @tests = (
sub {                  ok $p->strip_p4_where( "//a //b /c\n"        ), "/c"   },
sub {                  ok $p->strip_p4_where( "//a //b b /c c\n"    ), "/c c" },
sub {local$^O="Win32"; ok $p->strip_p4_where( "//a //b b /c c\n"    ), "/c c" },
sub {local$^O="Win32"; ok $p->strip_p4_where( "//a //b C: C:/c c\n" ), "C:/c c"},
sub {
    ok ! defined $p->strip_p4_where( "//a //b C: C:/c c\n" ) ;
},
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
