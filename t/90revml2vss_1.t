#!/usr/local/bin/perl -w

=head1 NAME

vss.t - testing of vcp vss i/o

=cut

use strict ;

use Test ;
use File::Path ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '';

my $project = "revml2vss";

my $vssroot_1  = "${t}vssroot_1";
my $vssstate_1 = "${t}vssstate_1";
my $vss_spec = "vss:Admin\@$vssroot_1:$project/...";
my $vss_repo_id = "vss:test_repository";

my $infile  = $t . "test-vss-in-1.revml" ;

my @tests = (
## copy vssroot_0 to vssroot_1
sub {
   my $vssroot_0  = "${t}vssroot_0";
   my $vssstate_0 = "${t}vssstate_0";
   rmtree [ grep -e, $vssroot_1, $vssstate_1 ];
   copy_dir_tree $vssroot_0, $vssroot_1;
   copy_dir_tree $vssstate_0, $vssstate_1;
   ok 1;
},

## revml -> vss 
sub {
   ok run [ @vcp, "revml:$infile", $vss_spec,
      "--db-dir=$vssstate_1",
      "--repo-id=$vss_repo_id",
   ];
},


## slurp revml files and analyze with regexps to count number of
## unique named files and the highest change number for each file,
## then look at the head_revs_db to see if the repository really
## contains all that.

## detailed analysis of this import is left to 91vss2revml.t             

sub {
   my $infile0  = "${t}test-vss-in-0.revml" ;

   my $revs1 = parse_files_and_revids_from_head_revs_db {
      state_dir => $vssstate_1,
      repo_id => $vss_repo_id,
      remove_rev_root => "/ignored/"
   };
   my $revs2 = parse_files_and_revids_from_revml $infile0, $infile;

   ok_or_diff $revs1, $revs2;
},

) ;  # end @tests



plan tests => scalar @tests ;

my $why_skip = vss_borken ;

$why_skip ? skip $why_skip, 1 : $_->() for @tests ;
