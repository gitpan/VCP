#!/usr/local/bin/perl -w

=head1 NAME

revml.t - testing of vcp revml in and out

=cut

use strict ;

use Carp ;
use Test ;
use IPC::Run qw( run ) ;

## We always run vcp by doing a $^X vcp, to make sure that vcp runs under
## the same version of perl that we are running under.
my $vcp = 'bin/vcp' ;

my $t = -d 't' ? 't/' : '' ;

sub slurp {
   my ( $fn ) = @_ ;
   open F, "<$fn" or die "$!: $fn" ;
   local $/ ;
   return <F> ;
}


my @tests = (
( map {
   my $type = $_ ;
   my $infile  = $t . "test-$type-in-0.revml" ;
   my $outfile = $t . "test-$type-out-0.revml" ;

   ##
   ## Idempotency tests
   ##
   ## These depend on the "test-foo-in.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   sub {
      my $diff = '' ;
      eval {
	 my $out ;
	 ## $in and $out allow us to avoide execing diff most of the time.
	 run( [ $^X, $vcp, "revml:$infile", "revml" ], \undef, \$out )
	    or die "`$vcp revml:$infile revml` returned $?" ;

	 my $in = slurp( $infile ) ;
	 if (
	    $in ne $out
	    && run( [ 'diff', '-u', $infile, '-' ], \$out, '>', \$diff )
	    && $? != 256
	 ) {
	    die "`diff -u $infile -` returned $?" ;
	 }
      } ;
      $diff = $@ if $@ ;
      chomp $diff ;
      ok( $diff, '' ) ;
      if ( -e $outfile ) { unlink $outfile or warn "$!: $outfile" ; }
   },
} qw( revml cvs p4 ) )
) ;

plan tests => scalar( @tests ) ;

unless ( -x $vcp ) {
   print STDERR "# '$vcp' not found\n" ;
   skip( 1, '' ) for @tests ;
   exit ;
}

$_->() for @tests ;
