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
$vcp = "bin/$vcp"    if -e "bin/$vcp" ;
$vcp = "../bin/$vcp" if -e "../bin/$vcp" ;

$vcp = File::Spec->rel2abs( $vcp ) ;

my @vcp = ( @perl, $vcp ) ;


sub vcp {
   my $exp_results = shift ;
   my $out ;
   my $err ;
   my $pid = run( [ @vcp, @_ ], \undef, \$out, \$err ) ;
   confess "$vcp ", join( ' ', @_ ), " returned $?\n$out$err"
      if defined $exp_results && ! grep $? == $_ << 8, @$exp_results ;
   return $err . $out ;
}


my @tests = (
#perldoc now complains when run as root, causing this test to fail
#sub { ok( vcp( [ 0 ], 'help' ),  qr/OPTIONS/s ) },
sub { ok( vcp( [ 2 ], 'foo:' ),   qr/unknown source scheme/s ) },
sub { ok( vcp( [ 2 ], 'p4:', 'foo:' ),   qr/unknown destination scheme/s ) },
sub { ok( vcp( [ 1 ], '--foo' ), qr/foo.*Usage/s ) },
) ;

plan tests => scalar( @tests ) ;

unless ( -e $vcp ) {
   print STDERR "# '$vcp' not found\n" ;
   skip( 1, '' ) for @tests ;
   exit ;
}

$_->() for @tests ;
