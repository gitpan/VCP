#!/usr/local/bin/perl -w

=head1 NAME

p4.t - testing of vcp p4 i/o

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

my @vcp = ( vcp_cmd, "vcp:-" );

my $t = -d 't' ? 't/' : '' ;

## Repositories to read from
my $p4root_0 = "${t}p4root_0";
my $p4root_1 = "${t}p4root_1";

## where to put the destination repository
my $cvsroot = tmpdir "cvsroot";

my $state_location = tmpdir "vcp_state";

## where to write to in the destination repo
my $cvs_module = "p4_t_module";

my $cvs_spec = "cvs:$cvsroot:$cvs_module/";

my $repo_id;

## -kb is used when extracting from CVS to get \n-only lineends
## because that's what bin/gentrevml generates and \rs would be
## encoded as <char.../> elements (so we can't just let perl
## or an XML parser hide linending issues).

my @tests = (
##
## p4->cvs->revml bootstrap
##
## read p4root_0 into cvs
sub {
   my $vcp_spec = <<VCP_FILE;
Source:      p4:revml2p4\@$p4root_0://depot/foo/...
               --run-p4d
               --repo-id=p4:test_repository

Destination: $cvs_spec
               --init-cvsroot
               --delete-cvsroot
               --db-dir=$state_location
               --repo-id=cvs:test_repository

Map:
## ASSumes directories under //depot/foo/ are the main and branch
## dirs.
        */(...)<(...)>  \$1<\$2>
VCP_FILE

   eval { run \@vcp, \$vcp_spec };
   ok $@ || '', '';
},

## read cvs repository built in previous test, and compare it to the
## test-cvs-in-0.revml to see how it compares to a file that hasn't been
## through a revml->p4->cvs->revml pipeline.
sub {
   return skip "previous test failed", 1 if $@;

   my $infile  = $t . "test-cvs-in-0.revml" ;
   my $in = slurp $infile ;
   #my $out = get_vcp_output $cvs_spec, qw( -kb -r 1.1: ) ;
   my $out = get_vcp_output $cvs_spec, "-kb",
      { revml_out_spec => [ "--db-dir=$state_location", "--repo-id=revml:test_repository" ] } ;


   s_content  qw( rep_desc time user_id ),   \$in, \$out ;
   s_content  qw( rev_root ),                \$in, $cvs_module ;
   ## TODO can we get the real repo_id here?
   s_content qw( source_repo_id ),          \$out, "cvs:test_repository";
   rm_elts    qw( cvs_info change_id source_change_id mod_time ), \$in ;
   rm_elts    qw( label ), qr/vcp_.*/, \$out ;

   $in =~ s{(id="|_id>)/+ignored}{$1/$cvs_module}g;
   $in =~ s{<(.*branch_id)>main-branch-1</\1>}{<$1>tag_//depot/foo/main-branch-1/</$1>}g;

   $in =~ s{(create branch ')(.*?)(')}{${1}tag_//depot/foo/$2/$3}g;

   ok_or_diff $out, $in;
},


## --repo-id here should agree with the other one above that writes to
## the same destination.  because we are faking by reading from two
## different repositories that are really for test purposes snapshots
## of the same repository at two different moments in time.  
##
## because vcp would by default use the paths to these two
## repositories as the repo_ids, vcp would refuse to add an
## incremental export from the second repository on top of the
## revisions from the first repository.  by specifying the same
## repo_id in both places, we make vcp think that the revisions came
## from the same repository.

##
## p4->cvs->revml incremental export
##
## read from p4root_1 repository into cvs.
##
sub {
   eval { run \@vcp, \<<VCP_END; } or die $@;
Source:       p4:revml2p4\@$p4root_1://depot/foo/...
                --continue
                --run-p4d
                --repo-id=p4:test_repository

Destination:  $cvs_spec
                --db-dir=$state_location
                --repo-id=cvs:test_repository

Map:
## ASSumes directories under //depot/foo/ are the main and branch
## dirs.
        */(...)<(...)>  \$1<\$2>
VCP_END

   ok 1;
},


## extract stuff inserted into cvs in the previous test and compare
## to the source revml to see that it got there ok.
sub {
   my $infile  = $t . "test-cvs-in-1.revml" ;
   my $in = slurp $infile ;
   my $out = get_vcp_output $cvs_spec, "-kb", "--continue",
      { revml_out_spec => [ "--db-dir=$state_location", "--repo-id=revml:test_repository" ] } ;
   
   s_content qw( rep_desc time user_id ),   \$in, \$out ;
   s_content qw( rev_root ),                \$in, $cvs_module ;
   s_content qw( source_repo_id ),          \$out, "cvs:test_repository";
   rm_elts   qw( cvs_info change_id source_change_id mod_time ), \$in ;
   rm_elts   qw( label ), qr/vcp_.*/, \$out ;

#      $out =~ s{<rev_id>1.}{<rev_id>}g ;
#      $out =~ s{<base_rev_id>1.}{<base_rev_id>}g ;
#      $out =~ s{((id="|_id>)?[^>]*#)1\.}{$1}g;
#
   $in =~ s{(id="|_id>)/+ignored}{$1/$cvs_module}g;
   $in =~ s{<(.*branch_id)>main-branch-1</\1>}{<$1>tag_//depot/foo/main-branch-1/</$1>}g;

   ok_or_diff $out, $in;
},

);  # end @tests.


plan tests => scalar @tests;

my $p4d_borken = $ENV{P4BORKEN}  || p4d_borken ;
my $cvs_borken = $ENV{CVSBORKEN} || cvs_borken;


my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;
$why_skip .= "$cvs_borken\n"           if $cvs_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
