#!/usr/local/bin/perl -w

=head1 NAME

p4.t - testing of vcp p4 i/o

=cut

use strict ;

use Carp ;
use Test ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $p4root_0  = "${t}p4root_0";
my $p4state_0 = "${t}p4state_0";
my $p4_spec = "p4:revml2p4\@$p4root_0://depot/foo/..." ;
my $p4_repo_id = "p4:test_repository";

my $infile  = $t . "test-p4-in-0.revml" ;

my @tests = (

##
## Empty import
##
sub {
   run [ @vcp, "revml:-", $p4_spec,
         "--init-p4d",
         "--delete-p4d-dir", 
         "--db-dir=$p4state_0",
         "--repo-id=$p4_repo_id",
       ],
       \"<revml/>" ;
   ok $?, 0, "`vcp revml:- $p4_spec` return value"  ;
},

##
## revml -> p4 bootstrap transfer
##
sub {
   ok run [ @vcp, "revml:$infile", $p4_spec,
            "--init-p4d",
            "--delete-p4d-dir",
            "--db-dir=$p4state_0",
            "--repo-id=$p4_repo_id",
         ];
},

## slurp $infile and analyze with regexps to count number of unique
## named files and the highest change number for each file, then check
## state db to see if the repository really contains all that.

## detailed analysis of this import is left to 91p42revml.t             

sub {
   my $revs1 = parse_files_and_revids_from_head_revs_db {
      state_dir => $p4state_0,
      repo_id => $p4_repo_id,
      remove_rev_root => "/ignored/",
   };
   my $revs2 = parse_files_and_revids_from_revml $infile ;

   ok_or_diff $revs1, $revs2;
},

) ;



plan tests => scalar @tests ;

my $p4d_borken = p4d_borken ;

my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
