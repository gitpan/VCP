#!/usr/local/bin/perl -w

=head1 NAME

02dest.t - testing of VCP::Dest services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Dest;

my $p ;

my @tests = (
sub {
   $p = VCP::Dest->new();
   ok ref $p, 'VCP::Dest';
},

sub {
   ok length $p->digest( $0 );
},
sub {
   ok 0+$p->options_as_strings;
},
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
