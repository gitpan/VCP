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
my $infile_1 = $t . "test-cvs-in-1.revml";

my $cvsroot_1  = "${t}cvsroot_1";
my $cvsstate_1 = "${t}cvsstate_1";

my $cvs_spec_1 = "cvs:$cvsroot_1:$module/" ;

my @tests = (

sub {
   my $cvsroot_0  = "${t}cvsroot_0";
   my $cvsstate_0 = "${t}cvsstate_0";
   rmtree [ grep -e, $cvsroot_1, $cvsstate_1 ];
   copy_dir_tree $cvsroot_0, $cvsroot_1;
   copy_dir_tree $cvsstate_0, $cvsstate_1;
   my $out;
   run [ @vcp, "revml:$infile_1", $cvs_spec_1,
      "--db-dir=$cvsstate_1", "--repo-id=cvs:test_repository" ], \undef, \$out;

   ok 1;
},

) ;

plan tests => scalar( @tests ) ;

my $why_skip ;

$why_skip .= cvs_borken ;
$why_skip ? skip( $why_skip, 0 ) : $_->() for @tests ;
