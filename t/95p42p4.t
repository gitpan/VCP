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
my $destroot = tmpdir "destp4root";

my $state_location = tmpdir "vcp_state";

## where to write to in the destination repo
my $dest_spec = "p4:$destroot://depot/...";

my $repo_id;

sub _clean_up_in_and_out {
   my ( $in_ref, $out_ref ) = @_;

   ##TODO: allow dest spec to not need //depot/...
   s_content qw( rev_root ),                       $in_ref, "depot";
   s_content qw( p4_info rep_desc time mod_time ), $in_ref, $out_ref ;
   s_content qw( source_repo_id ),                 $in_ref,
                                                      "p4:test_repository";
   $$in_ref =~ s{(id="|_id>)/+ignored}{$1//depot}g;

}

my @tests = (
##
## p4->p4 bootstrap
##
## read p4root_0 into destroot
sub {
   my $vcp_spec = <<VCP_FILE;
Source:      p4:revml2p4\@$p4root_0://depot/foo/...
               --run-p4d
               --repo-id=p4:test_repository

Destination: $dest_spec
               --init-p4d
               --delete-p4d-dir
               --db-dir=$state_location
               --repo-id=p4:dest_test_repository

VCP_FILE

   eval { run \@vcp, \$vcp_spec };
   ok $@ || '', '';
},

## read repository built in previous test, and compare it to the
## test-p4-in-0.revml to see how it compares to a file that hasn't been
## through a revml->p4->p4->revml pipeline.
sub {
   return skip "previous test failed", 1 if $@;

   my $infile  = $t . "test-p4-in-0.revml" ;
   my $in = slurp $infile ;
   my $out = get_vcp_output $dest_spec, "--run-p4d",
      "--repo-id=p4:test_repository",
      { revml_out_spec => [ "--db-dir=$state_location", "--repo-id=revml:test_repository" ] } ;

   _clean_up_in_and_out \$in, \$out;

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
## p4->p4 incremental export
##
## read from p4root_1 repository into p4.
##
sub {
   eval { run \@vcp, \<<VCP_END; } or die $@;
Source:       p4:revml2p4\@$p4root_1://depot/foo/...
                --continue
                --run-p4d
                --repo-id=p4:test_repository

Destination: $dest_spec
               --run-p4d
               --db-dir=$state_location
               --repo-id=p4:dest_test_repository

VCP_END

   ok 1;
},


## extract stuff inserted into cvs in the previous test and compare
## to the source revml to see that it got there ok.
sub {
   my $infile  = $t . "test-p4-in-1.revml" ;
   my $in = slurp $infile ;
   my $out = get_vcp_output $dest_spec, "--continue", "--run-p4d",
      "--repo-id=p4:test_repository",
      { revml_out_spec => [ "--db-dir=$state_location", "--repo-id=revml:test_repository" ] } ;
   
   _clean_up_in_and_out \$in, \$out;

   ok_or_diff $out, $in;
},

);  # end @tests.


plan tests => scalar @tests;

my $p4d_borken = $ENV{P4BORKEN}  || p4d_borken ;


my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
