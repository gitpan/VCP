#!/usr/local/bin/perl -w

=head1 NAME

cvs.t - testing of vcp cvs i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use File::Spec ;
use Test ;

use VCP::TestUtils ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $module = 'foo' ;  ## Must match the rev_root in the testrevml files

my @revml_out_spec = ( "sort:", "--", "revml:" ) ;

my $p4d_borken = $ENV{P4DBORKEN} || p4d_borken ;

sub check {
   croak "test failed and FATALTEST set" if ! $_[0];
}


my $infile_0  = "${t}test-cvs-in-0.revml";
my $infile_1  = "${t}test-cvs-in-1.revml";
my $cvsroot_0 = "${t}cvsroot_0";
my $cvsroot_1 = "${t}cvsroot_1";

my $cvs_spec_0        = "cvs:$cvsroot_0:$module/" ;
my $cvs_spec_1        = "cvs:$cvsroot_1:$module/" ;

## Where to put the destination repository
my $p4root = tmpdir "p4root";

my $state_location = tmpdir "vcp_state";

my $p4_spec = "p4:p4_t_user\@$p4root:";

my $repo_id;

my @tests = (
##
## cvs to p4
##
sub {
   return skip $p4d_borken, 1 if $p4d_borken ;

   my $cvs_spec = $cvs_spec_0;

   eval { run [ @vcp, "vcp:-" ], \<<TOHERE; };
Source:      $cvs_spec_0 --repo-id=cvs:test_repository --kb

StringEdit:
        comment /.*create\\sbranch.*/   "comment 2\\n"

Destination: $p4_spec//depot/...
                --init-p4d
                --db-dir=$state_location
                --repo-id=p4:test_repository

Map:
	(...)<>         main/\$1  # Match files on main branch (only)
        (...)<(...)>    \$2/\$1    # Match files on branches

TOHERE
   ok $@ || '', '';  # next sub checks this better
},

##
## check previous test by reading resulting p4 into revml,
## and comparing to the p4 version of the generated source revml.
##
sub {
   return skip $p4d_borken, 1 if $p4d_borken ;

   my $out;
   eval {
      run [ @vcp,
         "$p4_spec//depot/...",
         "--repo-id=p4:test_repository",
         "--run-p4d",
         @revml_out_spec,
         "--db-dir=$state_location",
         "--repo-id=revml:test_repository",
      ], \undef, \$out;
   };
   die $@ if $@;

   my $infile  = $t . "test-p4-in-0.revml";
   my $in = slurp $infile ;

   s_content  qw( rep_desc time user_id rep_type ), \$in, \$out ;
   s_content  qw( rev_root                       ), \$in, "depot" ;
   rm_elts    qw( p4_info                        ), \$in, \$out ;

   $in =~ s{(id="|id>)/ignored}{$1//depot}g;

   ok_or_diff $out, $in;
},

##
## Incremental cvs->p4->revml update (cvs to p4 part)
##
sub {
   return skip $p4d_borken, 1 if $p4d_borken ;

   eval { run [ @vcp, "vcp:-" ], \<<TOHERE; };
Source:      $cvs_spec_1 
                --repo-id=cvs:test_repository
                --continue
                --kb

Destination: $p4_spec//depot/... 
                --run-p4d
                --db-dir=$state_location
                --repo-id=p4:test_repository

Map:
	(...)<>         main/\$1  # Match files on main branch (only)
        (...)<(...)>    \$2/\$1    # Match files on branches
TOHERE
   ok $@ || '', '';  # next sub checks this better
},

##
## part 2 of Incremental cvs->p4->revml update (p4 to revml, check result)
##
sub {
   return skip $p4d_borken, 1 if $p4d_borken ;
   return skip 'last test did not complete', 1 if $@;
   
   my $out ;
   
   eval {
      run [ @vcp,
         "$p4_spec//depot/...",
            "--repo-id=p4:test_repository",
            "--continue",
            "--run-p4d",
         @revml_out_spec,
            "--db-dir=$state_location",
            "--repo-id=revml:test_repository",
      ], \undef, \$out;
   };
   die $@ if $@;
   
   my $infile  = $t . "test-p4-in-1.revml";
   my $in = slurp $infile ;
   
   s_content  qw( rep_desc time user_id rep_type ), \$in, \$out ;
   s_content  qw( rev_root                       ), \$in, "depot" ;
   rm_elts    qw( p4_info                        ), \$in, \$out ;
   
   $in =~ s{(id="|id>)/ignored}{$1//depot}g;
   
   ok_or_diff $out, $in;
},

##
## cvs->p4->revml, re-rooting a dir tree
##
## Do this after the above tests so that we can start with an empty repo.
##
sub {
   return skip $p4d_borken, 1 if $p4d_borken ;

   ## Start anew
   rm_dir_tree $p4root;
   rm_dir_tree $state_location;

   eval {
      run [ @vcp,
         "$cvs_spec_0/a/deeply/...",
         "--kb",
         "$p4_spec//depot/new/...",
            "--db-dir=$state_location",
            "--repo-id=p4:test_repository",
            "--init-p4d",
      ],
         \undef;
   };
   ok $@ || '', '';  # next sub checks this better
},

sub {   
   return skip $p4d_borken, 1 if $p4d_borken ;
   my $out ;

   eval {
      run [ @vcp,
         "$p4_spec//depot/new/...",
            "--repo-id=p4:test_repository",
            "--run-p4d",
         @revml_out_spec,
            "--db-dir=$state_location",
            "--repo-id=revml:test_repository",
      ], \undef, \$out;
   };
   die $@ if $@;

   my $infile  = $t . "test-p4-in-0.revml";
   my $in = slurp $infile ;

   s_content  qw( rep_desc time user_id rep_type  ), \$in, \$out ;
   s_content  qw( rev_root                        ), \$in, "depot/new" ;
   rm_elts    qw( p4_info                         ), \$in, \$out ;

   ## Strip out all files from $in that shouldn't be there
   rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

   ## Adjust the $in paths to look like the result paths.  $in is
   ## now the "expected" output.
   $in =~ s{<(name|source_name)>main/a/deeply/}{<$1>}g ;

   $in =~ s{(id="|id>)/ignored/main/a/deeply}{$1//depot/new}g;  #"# cperl syntax highlight fix

   ok_or_diff $out, $in;
},

) ;

plan tests => scalar( @tests ) ;

my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= cvs_borken ;
$why_skip ? skip( $why_skip, 0 ) : $_->() for @tests ;
