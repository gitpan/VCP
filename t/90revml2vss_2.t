#!/usr/local/bin/perl -w

=head1 NAME

revml2vss_2.t - testing of vcp vss i/o

=cut

use strict ;

use Carp ;
use Test ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $project = 'revml2vss';

my $vssroot_2  = "${t}vssroot_2";
my $vssstate_2 = "${t}vssstate_2";

my $deepdir = "one/two/three/four/five";
my $vss_spec = "vss:Admin\@$vssroot_2:$project/${deepdir}/...";
my $vss_repo_id = "vss:test_repository";

my $infile = "${t}test-vss-in-0.revml";

my @tests = (

##
## revml->vss, re-rooting a dir tree deeply
##
sub {
   ok run [ @vcp, "revml:$infile", $vss_spec, 
         "--mkss-ssdir",
         "--delete-ssdir",
         "--dont-recover-deleted-files",
         "--db-dir=$vssstate_2",
         "--repo-id=$vss_repo_id",
       ];
},


##
## check result previous sub
##
sub {
   my $got = parse_files_and_revids_from_head_revs_db {
      state_dir => $vssstate_2,
      repo_id => $vss_repo_id,
      remove_rev_root => "/ignored/"
   };
   my $exp = parse_files_and_revids_from_revml $infile ;

   my $re = quotemeta "$deepdir/";
   $got =~ s/^$re//mg ;

   ok_or_diff $got, $exp;
},

);

plan tests => scalar @tests ;

my $why_skip = vss_borken ;

$why_skip ? skip $why_skip, 1 : $_->() for @tests ;

