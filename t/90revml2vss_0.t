#!/usr/local/bin/perl -w

=head1 NAME

90vss.t - testing of vcp vss i/o

=cut

use strict ;

use Carp ;
use Test ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '';

my $project = "revml2vss" ;

my $vssroot_0  = "${t}vssroot_0";
my $vssstate_0 = "${t}vssstate_0";
my $vss_spec = "vss:Admin\@$vssroot_0:$project/..." ;
my $vss_repo_id = "vss:test_repository";

my $infile  = $t . "test-vss-in-0.revml" ;

my @tests = (
##
## Empty import
##
sub {
   run [ @vcp, "revml:-", $vss_spec,
         "--mkss-ssdir",
         "--delete-ssdir",
         "--db-dir=$vssstate_0",
         "--repo-id=$vss_repo_id",
      ],
      \"<revml/>" ;
   ok $?, 0, "`vcp revml:- $vss_spec` return value"  ;
},

##
## revml->vss bootstrap transfer
##
sub {
local $ENV{VCPDEBUG}=1;
local $ENV{IPCRUN3DEBUG}=10;
   ok run [ @vcp, "revml:$infile", $vss_spec,
         "--mkss-ssdir",
         "--dont-recover-deleted-files",
         "--delete-ssdir",
         "--db-dir=$vssstate_0",
         "--repo-id=$vss_repo_id",
      ];
},

## slurp $infile and analyze with regexps to count number of unique
## named files and the highest change number for each file, then check
## state db to see if the repository really contains all that.

## detailed analysis of this import is left to 91p42revml.t             

sub {
   my $revs1 = parse_files_and_revids_from_head_revs_db {
      state_dir => $vssstate_0,
      repo_id => $vss_repo_id,
      remove_rev_root => "/ignored/",
   };
   my $revs2 = parse_files_and_revids_from_revml $infile ;

   ok_or_diff $revs1, $revs2;
},

) ;

plan tests => scalar( @tests ) ;

my $why_skip = vss_borken ;
$why_skip ? skip $why_skip, 1 : $_->() for @tests ;
