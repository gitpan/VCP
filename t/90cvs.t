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

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $module = 'foo' ;  ## Must match the rev_root in the testrevml files

my $cvs_options = cvs_options "cvs_" ;
my $cvs_spec = "cvs:$cvs_options->{repo}:$module" ;

my $max_change_id ;

my $p4d_borken = p4d_borken ;
my $p4_options = p4_options "cvs_" ;

my @tests = (
sub {
   mk_tmp_dir $cvs_options->{work} ;
   init_cvs $cvs_options, $module ;
   $ENV{CVSROOT} = "foobar" ;
   ok 1 ;
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
      run [ @vcp, $cvs_spec, qw( -r 1.1: ) ], \undef, \$out
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
      my $cvs_spec = "cvs:$cvs_options->{repo}:$module/a/deeply/..." ;

      my $out ;
      run [ @vcp, $cvs_spec, qw( -r 1.1: ) ], \undef, \$out
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
   if ( $p4d_borken ) {
      skip( $p4d_borken, 1, 1, $p4d_borken ) ;
      return ;
   }
   $ENV{P4USER}   = "foobar_user" ;
   $ENV{P4PORT}   = "foobar_port" ;
   $ENV{P4CLIENT} = "foobar_client" ;
   $ENV{P4PASSWD} = "foobar_passwd" ;

   launch_p4d $p4_options ;
   ok 1 ;
},

sub {
   if ( $p4d_borken ) {
      skip( $p4d_borken, 1, 1, $p4d_borken ) ;
      skip( $p4d_borken, 1, 1, $p4d_borken ) ;
      return ;
   }

   my $p4_spec = "p4:$p4_options->{user}:\@$p4_options->{port}://depot" ;

   my $infile  = $t . "test-cvs-in-0.revml" ;
   eval {
      run [ @vcp, $cvs_spec, qw( -r 1.1: ), "$p4_spec/..." ], \undef
         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;

      my $out ;
      run [ @vcp, "$p4_spec/..." ], \undef, \$out ;

      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id rep_type ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, "depot" ;
      rm_elts    qw( mod_time change_id cvs_info    ), \$in        ;
      rm_elts    qw( cvs_info p4_info               ),       \$out ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      $out =~ s{<rev_id>}{<rev_id>1.}g ;
      $out =~ s{<base_rev_id>}{<base_rev_id>1.}g ;

$out =~ s{^.*<change_id>(.*?)</change_id>.*(\r\n|\n\r|\n)}{
   $max_change_id = $1 if ! defined $max_change_id || $1 > $max_change_id ;
   ""
}gem ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub { skip( ! defined $max_change_id, $max_change_id, 3, "Max change_id in cvs->p4 transfer" ) },

##
## cvs->p4->revml, re-rooting a dir tree
##
sub {
   if ( $p4d_borken ) {
      skip( $p4d_borken, 1, 1, $p4d_borken ) ;
      skip( $p4d_borken, 1, 1, $p4d_borken ) ;
      return ;
   }

   ## Hide global $cvs_spec for the nonce
   my $cvs_spec = "cvs:$cvs_options->{repo}:$module/a/deeply/..." ;

   my $p4_spec = "p4:$p4_options->{user}:\@$p4_options->{port}://depot/new/..." ;
   eval {
      run [ @vcp, $cvs_spec, qw( -r 1.1: ), $p4_spec ], \undef
         or die "`vcp $cvs_spec -r 1.1:` returned $?" ;

      my $out ;
      run [ @vcp, $p4_spec ], \undef, \$out ;

      my $infile  = $t . "test-cvs-in-0.revml" ;
      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id rep_type  ), \$in, \$out ;
      s_content  qw( rev_root ),                        \$in, "depot/new" ;
      rm_elts    qw( mod_time change_id cvs_info     ), \$in, \$out ;
      rm_elts    qw( cvs_info p4_info                ),       \$out ;
      rm_elts    qw( label ),  qr/r_\w+|ch_\w+/,              \$out ;


      $out =~ s{<rev_id>}{<rev_id>1.}g ;
      $out =~ s{<base_rev_id>}{<base_rev_id>1.}g ;

      ## Strip out all files from $in that shouldn't be there
      rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

      ## Adjust the $in paths to look like the result paths.  $in is
      ## now the "expected" output.
      $in =~ s{<name>a/deeply/}{<name>}g ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
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
      run [ @vcp, $cvs_spec, qw( -r ch_4: ) ], \undef, \$out
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
## Idempotency test, bootstrapping the second set of changes
##
sub {
   my $infile  = $t . "test-cvs-in-1-bootstrap.revml" ;
   eval {
      my $out ;
      run [ @vcp, $cvs_spec, qw( -r ch_4: --bootstrap=** ) ], \undef, \$out
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

) ;

plan tests => scalar( @tests ) ;

my $why_skip ;

$why_skip .= "cvs command not found\n" unless `cvs -v` =~ /Concurrent Versions System/ ;
$why_skip ? skip( $why_skip, 0 ) : $_->() for @tests ;
