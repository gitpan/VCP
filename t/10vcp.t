#!/usr/local/bin/perl -w

=head1 NAME

vcp.t - testing of vcp command

=cut

use strict ;

use Carp ;
use Test ;
use IPC::Run qw( run ) ;

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
$vcp = "bin/$vcp"    if -x "bin/$vcp" ;
$vcp = "../bin/$vcp" if -x "../bin/$vcp" ;

$vcp = File::Spec->rel2abs( $vcp ) ;

my @vcp = ( @perl, $vcp ) ;


sub vcp {
   my $exp_results = shift ;
   my $out ;
   my $pid = run( [ @vcp, @_ ], \undef, '>&', \$out ) ;
   confess "$vcp ", join( ' ', @_ ), " returned $?\n$out"
      if defined $exp_results && ! grep $? == $_ << 8, @$exp_results ;
   return $out ;
}


my @tests = (
sub { ok( vcp( [ 0 ], 'help' ),  qr/OPTIONS/s ) },
sub { ok( vcp( [ 2 ], 'foo' ),   qr/unknown source scheme/s ) },
sub { ok( vcp( [ 2 ], 'p4', 'foo' ),   qr/unknown destination scheme/s ) },
sub { ok( vcp( [ 1 ], '--foo' ), qr/Usage:.*Options/s ) },
) ;

plan tests => scalar( @tests ) ;

unless ( -x $vcp ) {
   print STDERR "# '$vcp' not found\n" ;
   skip( 1, '' ) for @tests ;
   exit ;
}

$_->() for @tests ;
