#!/usr/local/bin/perl -w

=head1 NAME

00rev.t - testing of VCP::Rev services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Rev ;

## TODO: Add lots of tests to 00rev.t

my $r ;

my @tests = (
sub { $r = VCP::Rev->new() ; ok( ref $r, "VCP::Rev" ) },

sub { ok( ! $r->labels, ! 0 ) },

sub {
   $r->add_label( "l1" ) ;
   ok( join( ",", $r->labels ), "l1" ) ;
},

sub {
   $r->add_label( "l2", "l3" ) ;
   ok( join( ",", $r->labels ), "l1,l2,l3" ) ;
},

sub {
   $r->add_label( "l2", "l3" ) ;
   ok( join( ",", $r->labels ), "l1,l2,l3" ) ;
},

sub {
   $r->labels( "l4", "l5" ) ;
   ok( join( ",", $r->labels ), "l4,l5" ) ;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
