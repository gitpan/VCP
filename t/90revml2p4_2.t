#!/usr/local/bin/perl -w

=head1 NAME

revml2p4_2.t - testing of vcp p4 i/o

=cut

use strict ;

use Carp ;
use File::Path qw( rmtree );
use Test ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $module = 'foo' ;  ## Must match the rev_root in the testrevml files

my $infile_0 = $t . "test-p4-in-0.revml";

my $p4root_2  = "${t}p4root_2";
my $p4state_2 = "${t}p4state_2";

my $deepdir = "one/two/three/four/five";
my $p4_spec = "p4:revml2p4\@$p4root_2://depot/foo/${deepdir}/...";
my $p4_repo_id = "p4:test_repository";


my @tests = (

##
## revml->p4, re-rooting a dir tree deeply
##
sub {
   my $out;
   run [ @vcp, "revml:$infile_0", $p4_spec, 
         "--init-p4d",
         "--delete-p4d-dir",
         "--db-dir=$p4state_2",
         "--repo-id=$p4_repo_id",
       ], \undef, \$out
      or die "`vcp revml:$infile_0 $p4_spec` returned $?" ;

   ok 1;
},


##
## check result previous sub
##
sub {
   my $got = parse_files_and_revids_from_head_revs_db {
      state_dir => $p4state_2,
      repo_id => $p4_repo_id,
      remove_rev_root => "/ignored/"
   };
   my $exp = parse_files_and_revids_from_revml $infile_0 ;

   my $re = quotemeta "$deepdir/";
   $got =~ s/^$re//mg ;

   ok_or_diff $got, $exp;
},

);

plan tests => scalar @tests ;

my $p4d_borken = p4d_borken ;

my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;

