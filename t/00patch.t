#!/usr/local/bin/perl -w

=head1 NAME

00patch.t - testing of VCP::Patch

=cut

use strict ;

use Test ;

use constant SOURCE => 0 ;
use constant RESULT => 1 ;
use constant PATCH  => 2 ;

use Text::Diff qw( diff ) ;
use File::Spec::Functions qw( catfile tmpdir );
use VCP::Patch ;

my @lines = (
   [ map( "$_\n", qw( 1 2 3 4 5d 6 7 8 9 10 11 11d 12 13 ) ) ],
   [ map( "$_\n", qw( 1 2 3 4 5a 6 7 8 9 9a 10 11  12 13 ) ) ],
) ;

my @contents = map join( "", @$_ ), @lines ;

my @fns = map catfile( tmpdir, "vcp${$}_patch_$_" ), qw( source result patch ) ;

my $p_fn = $fns[PATCH];

sub slurp {
    my $fn = shift ;
    local $/ = undef ;
    open SLURP, "<$fn" or die "$!: $fn" ;
    my $guts = <SLURP> ;
    close SLURP        or die "$!: $fn" ;
    return $guts ;
}

my @tests = (
sub {
   my $fn = $fns[SOURCE] ;
   open F, ">$fn"        or die "$!: $fn" ;
   print F $contents[SOURCE] or die "$!: $fn" ;
   close F ;
   ok( 1 ) ;
},

sub {
   my $patch = "" ;
   open P, ">$p_fn" or die "$!: $p_fn";
   diff( @lines, { OUTPUT => \*P } ) ;
   close P;
   vcp_patch( @fns ) ;
   my $got = slurp $fns[RESULT] ;
   ok $got, $contents[RESULT], "diff" ;
},

sub {
   my $patch = "" ;
   open P, ">$p_fn" or die "$!: $p_fn";
   diff( @lines, { OUTPUT => \*P, CONTEXT_LINES => 3  } ) ;
   close P;
   vcp_patch( @fns ) ;
   my $got = slurp $fns[RESULT] ;
   ok $got, $contents[RESULT], "diff -U 3" ;
},

sub {
   my $patch = "" ;
   open P, ">$p_fn" or die "$!: $p_fn";
   diff( @lines, { OUTPUT => \*P, CONTEXT_LINES => 5  } ) ;
   close P;
   vcp_patch( @fns ) ;
   my $got = slurp $fns[RESULT] ;
   ok $got, $contents[RESULT], "diff -U 5" ;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;

for ( @fns ) {
   next unless -e $_ ;
   unlink $_ or warn "$! unlinking $_" ;
}
