#!/usr/local/bin/perl -w

=head1 NAME

cvs.t - testing of vcp cvs i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use File::Spec ;
use IPC::Run qw( run ) ;
use Test ;
use VCP::TestUtils ;

## CVS, when batch commiting, does the commits in an order I don't
## understand.  So we need to sort the results by running them
## back through a revml->revml conversion with the time field
## stripped out, because if the system clock ticks over while CVS is
## doing a batch import, then we'll get them in the wrong order when
## they come back out of the repository.  I think.

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $module = 'foo' ;  ## Must match the rev_root in the testrevml files

my $cvs_spec ;

my @revml_out_spec = ( "revml:", "--sort-by=name,rev_id" ) ;

my $max_change_id ;

my $p4_spec_base ;
my $p4d_borken = p4d_borken ;

my @tests = (
sub {
   my $cvs_options = init_cvs "cvs_", $module ;
   $cvs_spec = "cvs:$cvs_options->{repo}:$module" ;
   $ENV{CVSROOT} = "foobar" ;
   ok 1 ;
},

##
## Empty import
##
sub {
   run [ @vcp, "revml:-", $cvs_spec ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- $cvs_spec` return value"  ;
},

##
## revml->cvs->revml idempotency
##
sub {},  ## Mult. ok()s in next sub{}.

sub {
   eval {
      my $infile  = $t . "test-cvs-in-0.revml" ;
      ## $in and $out allow us to avoide execing diff most of the time.
      run [ @vcp, "revml:$infile", $cvs_spec ], \undef
	 or die "`vcp revml:$infile $cvs_spec` returned $?" ;

      ok 1 ;
      my $out ;
      run [ @vcp, $cvs_spec, qw( -r 1.1: ), @revml_out_spec ], \undef, \$out
         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;

      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id          ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $module ;
      rm_elts    qw( mod_time change_id cvs_info    ), \$in        ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff ';
},

##
## cvs->revml, re-rooting a dir tree
##
sub {
   eval {
      ## Hide global $cvs_spec for the nonce
      my $cvs_spec = "$cvs_spec/a/deeply/..." ;

      my $out ;
      run [ @vcp, $cvs_spec, qw( -r 1.1: ), @revml_out_spec ], \undef, \$out
         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;

      my $infile  = $t . "test-cvs-in-0.revml" ;
      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id                   ), \$in, \$out ;
      rm_elts    qw( mod_time change_id cvs_info             ), \$in, \$out ;
      rm_elts    qw( label ),          qr/r_\w+|ch_\w+/,              \$out ;


      ## Strip out all files from $in that shouldn't be there
      rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

      ## Adjust the $in paths to look like the result paths.  $in is
      ## now the "expected" output.
      s_content  qw( rev_root ),                       \$in, "foo/a/deeply" ;
      $in =~ s{<name>a/deeply/}{<name>}g ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

##
## cvs->p4->revml
##
sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   $ENV{P4USER}   = "foobar_user" ;
   $ENV{P4PORT}   = "foobar_port" ;
   $ENV{P4CLIENT} = "foobar_client" ;
   $ENV{P4PASSWD} = "foobar_passwd" ;

   my $p4_options = launch_p4d "cvs_" ;
   $p4_spec_base = "p4:$p4_options->{user}:\@$p4_options->{port}:" ;
   ok 1 ;
},

sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   my $p4_spec = "$p4_spec_base//depot" ;

   eval {
      run [ @vcp, $cvs_spec, qw( -r 1.1: ), "$p4_spec/..." ], \undef
         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;

      my $out ;
      run [ @vcp, "$p4_spec/...", @revml_out_spec ], \undef, \$out ;

      my $infile  = $t . "test-cvs-in-0.revml" ;
      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id rep_type ), \$in, \$out ;
      s_content  qw( rev_root                       ), \$in, "depot" ;
      rm_elts    qw( cvs_info mod_time change_id    ), \$in        ;
      rm_elts    qw( p4_info                        ),       \$out ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      $out =~ s{<rev_id>}{<rev_id>1.}g ;
      $out =~ s{<base_rev_id>}{<base_rev_id>1.}g ;

      $out =~ s{^.*<change_id>(.*?)</change_id>.*(\r\n|\n\r|\n)}{
	 $max_change_id = $1
	    if ! defined $max_change_id || $1 > $max_change_id ;
	 "" ;
      }gem ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;
   ok $max_change_id, 3, "Max change_id in cvs->p4 transfer" ;
},

##
## cvs->p4->revml, re-rooting a dir tree
##
sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   ## Hide global $cvs_spec for the nonce
   my $cvs_spec = "$cvs_spec/a/deeply/..." ;

   my $p4_spec = "$p4_spec_base//depot/new/..." ;
   eval {
      run [ @vcp, $cvs_spec, qw( -r 1.1: ), $p4_spec ], \undef
         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;

      my $out ;
      run [ @vcp, $p4_spec, @revml_out_spec ], \undef, \$out
         or die "`vcp $p4_spec` returned $?" ;

      my $infile  = $t . "test-cvs-in-0.revml" ;
      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id rep_type  ), \$in, \$out ;
      s_content  qw( rev_root                        ), \$in, "depot/new" ;
      rm_elts    qw( cvs_info mod_time change_id     ), \$in ;
      rm_elts    qw( p4_info                         ),       \$out ;
      rm_elts    qw( label ),  qr/r_\w+|ch_\w+/,              \$out ;


      $out =~ s{<rev_id>}{<rev_id>1.}g ;
      $out =~ s{<base_rev_id>}{<base_rev_id>1.}g ;

      ## Strip out all files from $in that shouldn't be there
      rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

      ## Adjust the $in paths to look like the result paths.  $in is
      ## now the "expected" output.
      $in =~ s{<name>a/deeply/}{<name>}g ;

      $out =~ s{^.*<change_id>(.*?)</change_id>.*(\r\n|\n\r|\n)}{
	 $max_change_id = $1
	    if ! defined $max_change_id || $1 > $max_change_id ;
	 "" ;
      }gem ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;
   ok $max_change_id, 6, "Max change_id in cvs->p4 transfer" ;
},

##
## Idempotency test for an incremental revml->cvs->revml update
##
sub {},  ## Mult. ok()s in next sub{}.

sub {
   my $infile  = $t . "test-cvs-in-1.revml" ;

   eval {
      ## $in and $out allow us to avoid execing diff most of the time.
      run [ @vcp, "revml:$infile", $cvs_spec ], \undef
	 or die "`vcp revml:$infile $cvs_spec` returned $?" ;

      ok 1 ;

      my $out ;
      run [ @vcp, $cvs_spec, qw( -r ch_4: ), @revml_out_spec ], \undef, \$out
         or die "`vcp $cvs_spec -r ch_4:` returned $?" ;

      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id          ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $module ;
      rm_elts    qw( mod_time change_id cvs_info    ), \$in        ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

##
## Incremental cvs->p4->revml update
##
sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   my $p4_spec = "$p4_spec_base//depot" ;

   eval {
      run [ @vcp, $cvs_spec, "-r", "ch_4:", "$p4_spec/..." ], \undef
         or die "`vcp $cvs_spec -r ch_4:` returned $?" ;

      my $out ;
      my $first_change = $max_change_id + 1 ;
      run [ @vcp, "$p4_spec/...\@$first_change,#head", @revml_out_spec ],
         \undef, \$out
         or die "`vcp $p4_spec/...\@$first_change,#head` returned $?" ;

      my $infile  = $t . "test-cvs-in-1.revml" ;
      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id rep_type ), \$in, \$out ;
      s_content  qw( rev_root                       ), \$in, "depot" ;
      rm_elts    qw( cvs_info mod_time change_id    ), \$in        ;
      rm_elts    qw( p4_info                        ),       \$out ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      $out =~ s{<rev_id>}{<rev_id>1.}g ;
      $out =~ s{<base_rev_id>}{<base_rev_id>1.}g ;

      $out =~ s{^.*<change_id>(.*?)</change_id>.*(\r\n|\n\r|\n)}{
	 $max_change_id = $1
	    if ! defined $max_change_id || $1 > $max_change_id ;
	 "" ;
      }gem ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;
   ok $max_change_id, 9, "Max change_id in cvs->p4 transfer" ;
},

##
## revml->cvs->revml Idempotency test, bootstrapping the second set of changes
##
sub {
   my $infile  = $t . "test-cvs-in-1-bootstrap.revml" ;
   eval {
      my $out ;
      run [ @vcp, $cvs_spec, qw( -r ch_4: --bootstrap=** ), @revml_out_spec ],
         \undef, \$out
         or die "`vcp $cvs_spec -r ch_4:` returned $?" ;

      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id          ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $module ;
      rm_elts    qw( mod_time change_id cvs_info    ), \$in        ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

##
## revml->cvs, re-rooting a dir tree
##
## Do this after the above tests so that we don't accidently introduce
## a bunch of additional changes, especially for the cvs->p4 tests.
##
sub {}, ## Two ok()'s in next sub.

sub {
   eval {
      ## Hide global $cvs_spec for the nonce
      my $cvs_spec = "$cvs_spec/newdir/..." ;

      my $infile  = $t . "test-cvs-in-0.revml" ;
      ## $in and $out allow us to avoide execing diff most of the time.
      run [ @vcp, "revml:$infile", $cvs_spec ], \undef
	 or die "`vcp revml:$infile $cvs_spec` returned $?" ;

      ok 1 ;

      my $out ;
      run [ @vcp, $cvs_spec, qw( -r 1.1: ), @revml_out_spec ], \undef, \$out
         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;

      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id                   ), \$in, \$out ;
      rm_elts    qw( mod_time change_id cvs_info             ), \$in, \$out ;
      rm_elts    qw( label ),          qr/r_\w+|ch_\w+/,              \$out ;


      ## Adjust the $in rev_root to look like the result paths.  $in is
      ## now the "expected" output.
      s_content  qw( rev_root ),                       \$in, "foo/newdir" ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

###
### cvs->revml, using the VCP::Source::cvs --cd option
### (also depends on being able to reroot on input.
#sub {
#   eval {
#      my $infile  = $t . "test-cvs-in-0.revml" ;
#      ## $in and $out allow us to avoide execing diff most of the time.
#      my $cvs_spec = "$cvs_spec/cd_test" ;
#      run [ @vcp, "revml:$infile", $cvs_spec ], \undef
#	 or die "`vcp revml:$infile $cvs_spec` returned $?" ;
#
#      ok 1 ;
#
#      my $out ;
#      run [ @vcp, $cvs_spec, qw( -r 1.1: ) ], \undef, \$out
#         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;
#
#      my $in = slurp $infile ;
#
#      s_content  qw( rep_desc time user_id          ), \$in, \$out ;
#      s_content  qw( rev_root ),                       \$in, $module ;
#      rm_elts    qw( mod_time change_id cvs_info    ), \$in        ;
#      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;
#
#      assert_eq $infile, $in, $out ;
#   } ;
#   ok $@ || '', '', 'diff ';
#},
#
) ;

plan tests => scalar( @tests ) ;

my $why_skip ;

$why_skip .= "cvs command not found\n" unless `cvs -v` =~ /Concurrent Versions System/ ;
$why_skip ? skip( $why_skip, 0 ) : $_->() for @tests ;
