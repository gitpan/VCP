#!/usr/local/bin/perl -w

=head1 NAME

vcp.t - testing of vcp command

=cut

use strict ;

use Carp ;
use Test ;
use IPC::Run qw( run ) ;

## We always run vcp by doing a $^X vcp, to make sure that vcp runs under
## the same version of perl that we are running under.
my $vcp = 'bin/vcp' ? 'bin/vcp' : 'vcp' ;

sub vcp {
   my $exp_results = shift ;
   my $out ;
   my $pid = run( [ $^X, $vcp, @_ ], \undef, '>&', \$out ) ;
   confess "$vcp ", join( ' ', @_ ), " returned $?"
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
