#!/usr/local/bin/perl -w

=head1 NAME

91p42revml.t - testing of vcp p4 i/o

=cut

use strict ;

use Carp ;
use Test ;
use VCP::TestUtils ;

my $t = -d 't' ? 't/' : '' ;

my $p4root_0 = "${t}p4root_0";
my $p4root_1 = "${t}p4root_1";
my $p4root_2 = "${t}p4root_2";
my $p4root_3 = "${t}p4root_3";

my $p4spec_0 = "p4:revml2p4\@$p4root_0:";
my $p4spec_1 = "p4:revml2p4\@$p4root_1:";
my $p4spec_2 = "p4:revml2p4\@$p4root_2:";
my $p4spec_3 = "p4:revml2p4\@$p4root_3:";

my $deepdir = "one/two/three/four/five";

# what change number to start incremental export at
## my $first_import_1_change; # was called $incr_change

my @tests = (
##
## revml -> p4 -> revml, bootstrap export
##
sub {
   my $infile  = $t . "test-p4-in-0.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-0.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   ## We are also testing to see if we can re-root the files under foo/...
   ##

   my $state = "${t}91p42revml_state_A";
   rm_dir_tree $state;

   my $in  = slurp $infile ;
   my $out = get_vcp_output(
      "$p4spec_0//depot/foo/...",
      "--repo-id=p4:test_repository",
      "--run-p4d",
      { revml_out_spec => [ "--db-dir=$state", "--repo-id=revml:test_repository" ] } 
   );

   s_content qw( rep_desc time p4_info ), \$in, \$out ;
   s_content qw( rev_root ),              \$in, "depot/foo" ;

   $in =~ s{(id="|_id>)/+ignored}{$1//depot/foo}g;
   $in =~ s{(id="|_id>)ignored}{$1depot/foo}g;

   ok_or_diff $out, $in;
},


## Test a single file extraction from a p4 repo.  This file exists in
## change 1.

sub {
   my $state = "${t}91p42revml_state_B";
   rm_dir_tree $state;
   ok(
      get_vcp_output(
         "$p4spec_0//depot/foo/main/add/f1",
         "--repo-id=p4:test_repository",
         "--run-p4d",
         { revml_out_spec => [ "--db-dir=$state", "--repo-id=revml:test_repository" ] },
      ),
      qr{<rev_root>depot/foo/main/add</.+<name>f1<.+<rev_id>1<.+<rev_id>2<.+</revml>}s
   ) ;
},

## Test a single file extraction from a p4 repo.  This file does not exist
## in change 1.
sub {
   my $state = "${t}91p42revml_state_C";
   rm_dir_tree $state;
   ok(
      get_vcp_output(
         "$p4spec_0//depot/foo/main/add/f2",
         "--repo-id=p4:test_repository",
         "--run-p4d",
         { revml_out_spec => [ "--db-dir=$state", "--repo-id=revml:test_repository" ] },
      ),
      qr{<rev_root>depot/foo/main/add</.+<name>f2<.+<change_id>2<.+<change_id>3<.+</revml>}s
   ) ;

},

##
## p4->revml, re-rooting a dir tree 
## copies //depot/foo/main/a/deeply/ as if it was a whole repo
## into a target dir as if it were a complete repository.             
##
sub {
   my $state = "${t}91p42revml_state_D";
   rm_dir_tree $state;

   my $infile  = $t . "test-p4-in-0.revml" ;
   my $in  = slurp $infile ;
   my $out = get_vcp_output(
      "$p4spec_0//depot/foo/main/a/deeply/...",
      "--repo-id=p4:test_repository",
      "--run-p4d",
      { revml_out_spec => [ "--db-dir=$state", "--repo-id=revml:test_repository" ] } 
   );
   
   s_content qw( rep_desc time ), \$in, \$out ;
   s_content qw( rev_root ),                    \$in, "depot/foo/main/a/deeply" ;
   rm_elts   qw( mod_time change_id p4_info ),  \$in, \$out ;

   ## Strip out all files from $in that shouldn't be there
   rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;
   
   ## Adjust the $in paths to look like the result paths.  $in is
   ## now the "expected" output.
   $in =~ s{<(name|source_name)>main/a/deeply/}{<$1>}g ;
   $in =~ s{(id="|_id>)/+ignored}{$1//depot/foo}g;
   $in =~ s{(id="|_id>)ignored}{$1depot/foo}g;

   ok_or_diff $out, $in;
},


##
## revml -> p4 -> revml, incremental export
##

sub {
   my $infile  = $t . "test-p4-in-1.revml" ;

   my $state = "${t}91p42revml_state_E";
   rm_dir_tree $state;
   copy_dir_tree "${t}91p42revml_state_A" => $state;

   # see if got the right # of files, changes
   # p42revml will do detailed checking (the following code)
   my $in  = slurp $infile ;
   my $out = get_vcp_output(
       "$p4spec_1//depot/foo/...",
       "--repo-id=p4:test_repository",
       "--continue",
       "--run-p4d",
      { revml_out_spec => [ "--db-dir=$state", "--repo-id=revml:test_repository" ] }
   );

   $in =~ s{</rev_root>}{/foo</rev_root>} ;
   s_content  qw( rep_desc time p4_info ), \$in, \$out ;
   s_content  qw( rev_root ),              \$in, "depot/foo" ;

   $in =~ s{(id="|_id>)/+ignored}{$1//depot/foo}g;
   $in =~ s{(id="|_id>)ignored}{$1depot/foo}g;
   
   ok_or_diff $out, $in;
},


##
## p4 -> revml, incremental export in bootstrap mode
##
sub {
   my $infile  = $t . "test-p4-in-1-bootstrap.revml" ;

   my $state = "${t}91p42revml_state_F";
   rm_dir_tree $state;
   copy_dir_tree "${t}91p42revml_state_A" => $state;

   my $in  = slurp $infile ;
   my $out = get_vcp_output(
      "$p4spec_1//depot/foo/...",
      "--repo-id=p4:test_repository",
      "--continue",
      "--bootstrap=...",
      "--run-p4d",
      { revml_out_spec => [ "--db-dir=$state", "--repo-id=revml:test_repository" ] } 
   );

   $in =~ s{</rev_root>}{/foo</rev_root>} ;
   s_content  qw( rep_desc time p4_info ), \$in, \$out ;
   s_content  qw( rev_root ),              \$in, "depot/foo" ;

   $in =~ s{(id="|_id>)/+ignored}{$1//depot/foo}g;
   $in =~ s{(id="|_id>)ignored}{$1depot/foo}g;

   ok_or_diff $out, $in;
},

## Check contents of t/p4root_2
##   extract p4 to revml
##   build expected from revml
##
## p4->revml, re-rooting a dir tree
##
sub {
   my $infile  = $t . "test-p4-in-0.revml" ;
   my $in = slurp $infile;
   my $out = get_vcp_output(
      "$p4spec_2//depot/foo/...",
      "--repo-id=p4:test_repository",
      "--run-p4d"
   );

   s_content  qw( rep_desc time ), \$in, \$out ;
   rm_elts    qw( p4_info       ), \$in, \$out ;

   ## Adjust the $in paths to look like the result paths.  $in is
   ## now the "expected" output.
   s_content  qw( rev_root ), \$in, "depot/foo" ;
   $in =~ s{(<(?:source_)?name>)}{${1}${deepdir}/}g;
   $in =~ s{(id="|id>)/ignored}{$1//depot/foo/${deepdir}}g;
   $in =~ s{(_id>)ignored}{$1//depot/foo/${deepdir}}g;

   ok_or_diff $out, $in;
},

## We don't check the contents of t/p4root_3 because that's hard and
## not incredibly necessary.

) ;

plan tests => scalar @tests ;

my $p4d_borken = p4d_borken ;

my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
