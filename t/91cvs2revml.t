#!/usr/local/bin/perl -w

=head1 NAME

cvs.t - testing of vcp cvs i/o

=cut

use strict ;

use Carp ;
use Test ;
use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $module = 'foo' ;  ## Must match the rev_root in the testrevml files

my @revml_out_spec = ( "sort:", "--", "revml:", ) ;

my $max_change_id ;

sub check {
   goto &die if $ENV{FATALTEST} && ! $_[0];
}

my $infile_0 = $t . "test-cvs-in-0.revml";
my $cvsroot_0 = $t . "cvsroot_0";
my $infile_1 = $t . "test-cvs-in-1.revml";
my $cvsroot_1 = $t . "cvsroot_1";
my $cvsroot_2 = $t . "cvsroot_2";

my $cvs_spec_0 = "cvs:$cvsroot_0:$module/" ;
my $cvs_spec_1 = "cvs:$cvsroot_1:$module/" ;
my $cvs_spec_2 = "cvs:$cvsroot_2:$module/newdir/" ;

my @options;

my @tests = (
##
## cvs->revml (using cvs command) idempotency
##
sub {
   my $infile   = $infile_0;
   my $cvs_spec = $cvs_spec_0;

   my $state = "${t}91cvs2revml_state_A";
   rm_dir_tree $state;
   my @revml_out_spec = ( 
      @revml_out_spec, 
      "--db-dir=$state",
      "--repo-id=cvs:test_repository",
   );
   run [ @vcp, $cvs_spec, @options, @revml_out_spec ], \undef, \my $out;

   my $in = slurp $infile ;

   s_content  qw( rep_desc time user_id          ), \$in, \$out ;
   s_content  qw( rev_root                       ), \$in, $module ;
   s_content  qw( source_repo_id                 ), \$in, "cvs";
   rm_elts    qw( mod_time change_id source_change_id cvs_info    ), \$in ;

   $in =~ s{(id="|id>)/ignored}{$1/foo}g;
   $in =~ s{(id="|id>)ignored}{$1/foo}g;

   ok_or_diff $out, $in;
},


##
## cvs->revml, re-rooting a dir tree
##
sub {
   ## Hide global $cvs_spec for the nonce
   my $cvs_spec = "$cvs_spec_0/a/deeply/..." ;

   my $state = "${t}91cvs2revml_state_B";
   rm_dir_tree $state;
   my @revml_out_spec = (
      @revml_out_spec,
      "--db-dir=$state",
      "--repo-id=cvs:test_repository",
   );
   run [ @vcp, $cvs_spec, @options, @revml_out_spec ], \undef, \my $out;

   my $infile  = $t . "test-cvs-in-0.revml" ;
   my $in = slurp $infile ;

   s_content  qw( rep_desc time user_id                   ), \$in, \$out ;
   s_content  qw( source_repo_id                          ), \$in, "cvs";
   rm_elts    qw( mod_time change_id source_change_id cvs_info ), \$in, \$out ;


   ## Strip out all files from $in that shouldn't be there
   rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

   ## Adjust the $in paths to look like the result paths.  $in is
   ## now the "expected" output.
   s_content  qw( rev_root ),                       \$in, "foo/a/deeply" ;
   $in =~ s{(<name>)a/deeply/}{$1}g ;
   $in =~ s{(<source_name>)a/deeply/}{$1}g ;
   $in =~ s{(id="|id>)/ignored}{$1/foo}g;
   $in =~ s{(id="|id>)ignored}{$1/foo}g;

   ok_or_diff $out, $in;
},


##
## incremental cvs->revml
##
sub {
   my $infile   = $infile_1;
   my $cvs_spec = $cvs_spec_1;

   my $state = "${t}91cvs2revml_state_C";
   rm_dir_tree $state;
   copy_dir_tree "${t}91cvs2revml_state_A" => $state;

   my @options = ( @options, "--continue" );
   my @revml_out_spec = (
      @revml_out_spec,
      "--db-dir=$state",
      "--repo-id=cvs:test_repository",
   );
   run [ @vcp, $cvs_spec, @options, @revml_out_spec ], \undef, \my $out;

   my $in = slurp $infile ;

   s_content  qw( rep_desc time user_id          ), \$in, \$out ;
   s_content  qw( rev_root                       ), \$in, $module ;
   s_content  qw( source_repo_id                 ), \$in, "cvs";
   rm_elts    qw( mod_time change_id source_change_id cvs_info    ), \$in ;

   $in =~ s{(id="|id>)/ignored}{$1/foo}g;
   $in =~ s{(id="|id>)ignored}{$1/foo}g;
   
   ok_or_diff $out, $in;
},

##
## cvs->revml Idempotency test, bootstrapping the second set of changes
##
sub {
   my $infile  = $t . "test-cvs-in-1-bootstrap.revml" ;
   my $cvs_spec = $cvs_spec_1;

   my $state = "${t}91cvs2revml_state_D";
   rm_dir_tree $state;
   copy_dir_tree "${t}91cvs2revml_state_A" => $state;

   my @options = ( @options, "--continue", "--bootstrap=..." );
   my @revml_out_spec = (
      @revml_out_spec,
      "--db-dir=$state",
      "--repo-id=cvs:test_repository",
   );
   run [ @vcp, $cvs_spec, @options, @revml_out_spec ], \undef, \my $out;

   my $in = slurp $infile ;

   s_content  qw( rep_desc time user_id          ), \$in, \$out ;
   s_content  qw( rev_root                       ), \$in, $module ;
   s_content  qw( source_repo_id                 ), \$in, "cvs";
   rm_elts    qw( mod_time change_id source_change_id cvs_info    ), \$in ;

   $in =~ s{(id="|id>)/ignored}{$1/foo}g;
   $in =~ s{(id="|id>)ignored}{$1/foo}g;

   ok_or_diff $out, $in;
},



## Check contents of t/cvsroot_2
##   extract cvs to revml
##   build expected from revml
##
## cvs->revml, re-rooting a dir tree
##
sub {
   ## Hide global $cvs_spec for the nonce
   my $cvs_spec_2 = "cvs:$cvsroot_2:$module/newdir/" ;

   run [ @vcp, $cvs_spec_2, @options, @revml_out_spec ], \undef, \my $out;

   my $infile  = $t . "test-cvs-in-0.revml" ;
   my $in = slurp $infile ;

   s_content  qw( rep_desc time user_id ), \$in, \$out ;
   s_content  qw( source_repo_id        ), \$in, "cvs";
   rm_elts    qw( mod_time change_id source_change_id cvs_info ), \$in, \$out ;

   ## Adjust the $in paths to look like the result paths.  $in is
   ## now the "expected" output.
   s_content  qw( rev_root ), \$in, "foo/newdir" ;
   $in =~ s{(id="|id>)/ignored}{$1/foo/newdir}g;
   $in =~ s{(id="|id>)ignored}{$1/foo/newdir}g;

   ok_or_diff $out, $in;
},

) ;


plan tests => 2 * @tests;


use vars qw( $why_skip );  # use vars because we local()ize.

$why_skip .= cvs_borken ;

my $test_num = 0;
for my $t ( @tests ) {
   @options = qw( --repo-id=cvs --use-cvs );
   {
      ## gentrevml does not beleive in \r yet, so force CVS in to
      ## binary extraction mode so that its output agrees with
      ## gentrevml's.
      push @options, "-kb" if $^O =~ /Win32/;
      ++$test_num;
      local $why_skip ||= "test not selected" 
         if $ENV{TESTNUM} && $ENV{TESTNUM} != $test_num;
      $why_skip ? skip( $why_skip, 0 ) : $t->();
   }

   @options = qw( --repo-id=cvs );
   {
      ## gentrevml does not beleive in \r yet, so force CVS in to
      ## binary extraction mode so that its output agrees with
      ## gentrevml's.
      push @options, "-kb" if $^O =~ /Win32/;

      ++$test_num;
      local $why_skip ||= "test not selected" 
         if $ENV{TESTNUM} && $ENV{TESTNUM} != $test_num;
      $why_skip ? skip( $why_skip, 0 ) : $t->();
   }
}
