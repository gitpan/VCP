#!/usr/local/bin/perl -w

=head1 NAME

00default_filter.t - testing of VCP::DefaultFilter services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::DefaultFilters;


my $f = VCP::DefaultFilters->new;


my @tests = (

sub {   
   my @filters = $f->cvs2p4_default_filters;
   my $res = join "\n", @filters;
   my $exp = join "\n", qw( Map: (...)<> main/$1 (...)<(*)> $2/$1 );
   ok $res, $exp;
},
   
);



plan tests => scalar( @tests );

$_->() for @tests;
