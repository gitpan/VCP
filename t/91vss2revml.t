#!/usr/local/bin/perl -w

=head1 NAME

91vss2revml.t - testing of vss output

=cut

use strict ;

use Carp ;
use Test ;
use VCP::TestUtils ;

my $t = -d 't' ? 't/' : '' ;

my $project = "revml2vss";

my $vssroot_0 = "${t}vssroot_0";
my $vssroot_1 = "${t}vssroot_1";
my $vssroot_2 = "${t}vssroot_2";
my $vssroot_3 = "${t}vssroot_3";

my $vssspec_0 = "vss:Admin\@$vssroot_0:$project";
my $vssspec_1 = "vss:Admin\@$vssroot_1:$project";
my $vssspec_2 = "vss:Admin\@$vssroot_2:$project";
my $vssspec_3 = "vss:Admin\@$vssroot_3:$project";

my $deepdir = "one/two/three/four/five";

sub _clean_up_in_and_out {
   my ( $in_ref, $out_ref ) = @_;

   s_content qw( rep_desc time vss_info ), $in_ref, $out_ref ;
   s_content qw( rev_root ),               $in_ref, $project ;

   $$in_ref =~ s{(id="|_id>)/+ignored}{$1/$project}g;
   $$in_ref =~ s{(id="|_id>)ignored}{$1/$project}g;

   $$in_ref =~ s{(user_id>)(?!unknown_VSS_user).*(</user_id>)}{$1Admin$2}g;

   rm_elts    qw( mod_time change_id source_change_id ), $in_ref, $out_ref ;

}

my @tests = (
##
## vss -> revml, bootstrap export
##
sub {
   my $infile  = $t . "test-vss-in-0.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-0.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   ## We are also testing to see if we can re-root the files under foo/...
   ##

   my $state = "${t}91vss2revml_state_A";
   rm_dir_tree $state;

   my $in  = slurp $infile ;
   my $out = get_vcp_output(
      "$vssspec_0/...",
      "--repo-id=vss:test_repository",
      {
         revml_out_spec => [
            "--db-dir=$state", "--repo-id=revml:test_repository"
         ]
      } 
   );

   _clean_up_in_and_out \$in, \$out;

   ok_or_diff $out, $in;
},

## Test a single file extraction from a vss repo.  This file exists in
## change 1.
sub {
   my $state = "${t}91vss2revml_state_B";
   rm_dir_tree $state;
   ok(
      get_vcp_output(
         "$vssspec_0/main/add/f1",
         "--repo-id=vss:test_repository",
         {
            revml_out_spec => [
               "--db-dir=$state", "--repo-id=revml:test_repository"
            ]
         },
      ),
      qr{<rev_root>revml2vss/main/add</.+<name>f1<.+<rev_id>0\.1<.+<rev_id>0\.4<.+</revml>}s
   ) ;
},

## Test a single file extraction from a vss repo.  This file does not exist
## in change 1.
sub {
   my $state = "${t}91vss2revml_state_C";
   rm_dir_tree $state;
   ok(
      get_vcp_output(
         "$vssspec_0/main/add/f2",
         "--repo-id=vss:test_repository",
         {
            revml_out_spec => [
               "--db-dir=$state", "--repo-id=revml:test_repository"
            ],
         },
      ),
      qr{<rev_root>revml2vss/main/add</.+<name>f2<.+<rev_id>0\.1<.+<rev_id>0\.4<.+</revml>}s
   ) ;

},

##
## vss->revml, re-rooting a dir tree 
## copies //depot/foo/main/a/deeply/ as if it was a whole repo
## into a target dir as if it were a complete repository.             
##
sub {
   my $state = "${t}91vss2revml_state_D";
   rm_dir_tree $state;

   my $infile  = $t . "test-vss-in-0.revml" ;
   my $in  = slurp $infile ;
   my $out = get_vcp_output(
      "$vssspec_0/main/a/deeply/...",
      "--repo-id=vss:test_repository",
      { 
         revml_out_spec => [
            "--db-dir=$state", "--repo-id=revml:test_repository"
         ]
      } 
   );
   
   _clean_up_in_and_out \$in, \$out;

   rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

   $in =~ s{</rev_root>}{/main/a/deeply</rev_root>};
   $in =~ s{((<source_)?name>)main/a/deeply/}{$1}g;

   ok_or_diff $out, $in;
},

##
## t/vssroot_1
##
sub {
   my $infile  = $t . "test-vss-in-1.revml" ;

   my $state = "${t}91vss2revml_state_E";
   rm_dir_tree $state;
   copy_dir_tree "${t}91vss2revml_state_A" => $state;

   # see if got the right # of files, changes
   # vss2revml will do detailed checking (the following code)
   my $in  = slurp $infile ;
   my $out = get_vcp_output(
      "$vssspec_1/...",
      "--repo-id=vss:test_repository",
      "--continue",
      {
         revml_out_spec => [
            "--db-dir=$state", "--repo-id=revml:test_repository"
         ],
      }
   );

   _clean_up_in_and_out \$in, \$out;

   ok_or_diff $out, $in, { context => 20};
},

##
## vss -> revml, incremental export in bootstrap mode
##
sub {
   my $infile  = $t . "test-vss-in-1-bootstrap.revml" ;

   my $state = "${t}91vss2revml_state_F";
   rm_dir_tree $state;
   copy_dir_tree "${t}91vss2revml_state_A" => $state;

   my $in  = slurp $infile ;
   my $out = get_vcp_output(
      "$vssspec_1/...",
      "--repo-id=vss:test_repository",
      "--continue",
      "--bootstrap=...",
      {
         revml_out_spec => [
            "--db-dir=$state", "--repo-id=revml:test_repository"
         ]
      }
   );

   _clean_up_in_and_out \$in, \$out;

   ok_or_diff $out, $in;
},

##
## Check contents of t/vssroot_2 (which is a rerooted directory tree
## to deep in a hierarchy).
##
sub {
   my $infile  = $t . "test-vss-in-0.revml" ;

   my $state = "${t}91vss2revml_state_G";
   rm_dir_tree $state;

   my $in = slurp $infile;
   my $out = get_vcp_output(
      "$vssspec_2/...",
      "--repo-id=vss:test_repository",
      {
         revml_out_spec => [
            "--db-dir=$state", "--repo-id=revml:test_repository"
         ]
      }
   );

   _clean_up_in_and_out \$in, \$out;

   $in =~ s{
      (
         (?:<
            (?:
               (?:source_)?(?:name|(?:file)?branch_id)|previous_id
            )>
            |id="
         )
         (?:/revml2vss/)?
      )
   }{${1}${deepdir}/}gx;
   
   ok_or_diff $out, $in;
},

## We don't check the contents of t/vssroot_3 because that's hard and
## not incredibly necessary.

) ;

plan tests => scalar @tests ;

my $why_skip = vss_borken ;

$why_skip ? skip $why_skip, 1 : $_->() for @tests ;
