#!/usr/local/bin/perl -w

=head1 NAME

revml2cvs.t - testing of vcp cvs i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use File::Path qw( rmtree );
use Test ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $module = 'foo' ;  ## Must match the rev_root in the testrevml files

my $infile_0 = $t . "test-cvs-in-0.revml";

my $cvsroot_2  = "${t}cvsroot_2";
my $cvsstate_2 = "${t}cvsstate_2";
my $cvs_spec_2 = "cvs:$cvsroot_2:$module/newdir/" ;

my @tests = (

##
## revml->cvs, re-rooting a dir tree
##
sub {
   my $out;
   run [ @vcp, "revml:$infile_0", $cvs_spec_2,
      "--init-cvsroot", "--delete-cvsroot", "--db-dir=$cvsstate_2", "--repo-id=cvs:test_repository"
      ], \undef, \$out
      or die "`vcp revml:$infile_0 $cvs_spec_2` returned $?" ;

   ok 1;
},

);



plan tests => scalar( @tests ) ;

my $why_skip ;

$why_skip .= cvs_borken ;
$why_skip ? skip( $why_skip, 0 ) : $_->() for @tests ;
