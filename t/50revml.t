#!/usr/local/bin/perl -w

=head1 NAME

revml.t - testing of vcp revml in and out

=cut

use strict ;

use Carp ;
use IPC::Run qw( run ) ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

my %seen ;
my @perl = ( $^X, map {
      my $s = $_ ;
      $s = File::Spec->rel2abs( $_ ) ;
      "-I$s" ;
   } grep ! $seen{$_}++, @INC
) ;

## We always run vcp by doing a @perl, vcp, to make sure that vcp runs under
## the same version of perl that we are running under.
my $vcp = 'vcp' ;
$vcp = "bin/$vcp"    if -e "bin/$vcp" ;
$vcp = "../bin/$vcp" if -e "../bin/$vcp" ;

$vcp = File::Spec->rel2abs( $vcp ) ;

my @vcp = ( @perl, $vcp ) ;


my $t = -d 't' ? 't/' : '' ;

my @tests = (
##
## Empty "import"
##
sub {
   run [ @vcp, "revml:-", "revml:" ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- revml:` return value"  ;
},

( map {
   my $type = $_ ;

   ##
   ## Idempotency tests
   ##
   ## These depend on the "test-foo-in.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   sub {
      eval {
	 my $out ;
	 my $infile  = $t . "test-$type-in-0.revml" ;
	 ## $in and $out allow us to avoide execing diff most of the time.
	 run( [ @vcp, "revml:$infile", "revml:", "--sort-by=name,rev_id" ], \undef, \$out )
	    or die "`$vcp revml:$infile revml` returned $?" ;

	 my $in = slurp( $infile ) ;
	 assert_eq $infile, $in, $out ;
      } ;
      ok $@ || '', '', 'diff' ;
   },
} qw( revml cvs p4 ) )
) ;

plan tests => scalar( @tests ) ;

unless ( -e $vcp ) {
   print STDERR "# '$vcp' not found\n" ;
   skip( 1, '' ) for @tests ;
   exit ;
}

$_->() for @tests ;
