#!/usr/local/bin/perl -w

=head1 NAME

identity.t - test VCP::Filter::identity

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;


my $t = -d 't' ? 't/' : '' ;

my @tests = (
##
## Empty imports, used here just to see if commad line parsing is ok and
## that a really simple file can make it through the XML parser ok.
##
sub {
   run [ @vcp, qw( - identity: - ) ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- identiry: revml:` return value"  ;
},

sub {
   run [ @vcp, qw( - identity: - ) ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- identiry: revml:` return value"  ;
},

sub {
  eval {
     my $out ;
     my $infile  = $t . "test-revml-in-0-no-big-files.revml" ;
     ## $in and $out allow us to avoide execing diff most of the time.
     run [ @vcp, $infile, qw( sort: -- identity: - ) ],
        \undef, \$out;

     my $in = slurp( $infile ) ;
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},

sub {
  eval {
     my $out ;
     my $infile  = $t . "test-revml-in-0-no-big-files.revml" ;
     ## $in and $out allow us to avoide execing diff most of the time.
     run [ @vcp, $infile, qw( sort: -- identity: identity: - )],
        \undef, \$out;

     my $in = slurp( $infile ) ;
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
