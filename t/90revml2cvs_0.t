#!/usr/local/bin/perl -w

=head1 NAME

90revml2cvs_0.t - testing of vcp cvs i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use Test ;
use VCP::Utils qw( start_dir_rel2abs );
use VCP::TestUtils;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $module = 'foo' ;  ## Must match the rev_root in the testrevml files
my $infile_0 = $t . "test-cvs-in-0.revml";
my $cvsroot_0 = $t . "cvsroot_0";
my $cvsstate_0 = $t . "cvsstate_0";
my $cvs_spec_0 = "cvs:$cvsroot_0:$module/" ;
my $repo_id = "cvs:test_repository";

my $abs_cvsroot_0 = start_dir_rel2abs( $cvsroot_0 );

my @vcp_options = (
   $cvs_spec_0,
   "--init-cvsroot",
   "--delete-cvsroot",
   "--db-dir=$cvsstate_0",
   "--repo-id=$repo_id",
);

## I'd like to just diff the RCS files between the one we're
## creating here and some known good ones, but
## I'm worried that different versions of cvs on different systems
## might have slightly different formats.  Note that we can't compare
## to t/cvsroot_[01] because those are created with this tool and that
## would overlook any errors!
##
## We can, however, use direct read, since 90cvs2revml tests that
## against --use-cvs.

my @tests = (

##
## Empty import
##
sub {
   run [ @vcp, "revml:-", @vcp_options ],
      \"<revml/>"; #"# de-confuse emacs' cperl mode
   ok $?, 0, "`vcp revml:- $cvs_spec_0` return value"  ;
},

sub {
   ok -d $cvsroot_0, 1, "$cvsroot_0 exists";
},


##
## revml->cvs import
##
sub {
   run [ @vcp, "revml:$infile_0", @vcp_options ];
   ok 1;
},

## slurp revml files and analyze with regexps find highest change number
## for each file.  compare this to what's in the head_revs_db.
sub {
   my $got = parse_files_and_revids_from_head_revs_db
      { 
        state_dir => $cvsstate_0,
        repo_id => $repo_id, 
        remove_rev_root => "/ignored/",
      };
   my $expected = parse_files_and_revids_from_revml $infile_0 ;

   # TODO: This will have to be fixed in the way vcp builds the head_revs_db.
   # so a no-change branch appears there too.
   # For now just excise the line from the revml parse output.
   $expected =~ s/^branched-no-change =>.*\n//m ;

   ok_or_diff $got, $expected;
},

) ;


plan tests => scalar( @tests ) ;

my $why_skip ;

$why_skip .= cvs_borken ;
$why_skip ? skip( $why_skip, 0 ) : $_->() for @tests ;
