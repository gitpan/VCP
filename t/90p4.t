#!/usr/local/bin/perl -w

=head1 NAME

p4.t - testing of vcp p4 i/o

=cut

use strict ;

use Carp ;
use File::Spec ;
use IPC::Run qw( run ) ;
use POSIX ':sys_wait_h' ;
use Test ;
use VCP::TestUtils ;

sub __ok { die unless ok @_ }

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $p4_options ;
my $p4_spec_base ;
my $p4_spec ;

my $incr_change ; # what change number to start incremental export at

my $cvs_options ;
my $cvs_module ;

my $cvs_borken = cvs_borken;

my @tests = (
sub {
   return skip $cvs_borken, "" if $cvs_borken ;
   # init_cvs before initting p4d, since it may need to set the uid and euid.
   $cvs_module = 'p4_t_module' ;
   $cvs_options = init_cvs "p4_", $cvs_module ;
   __ok 1 ;
},
sub {
   $ENV{P4USER}   = "foobar_user" ;
   $ENV{P4PORT}   = "foobar_port" ;
   $ENV{P4CLIENT} = "foobar_client" ;
   $ENV{P4PASSWD} = "foobar_passwd" ;

   $p4_options = launch_p4d "p4_" ;
   $p4_spec_base = "p4:$p4_options->{user}:\@$p4_options->{port}:" ;
   $p4_spec = "$p4_spec_base//depot/foo" ;
   __ok 1 ;
},

##
## Empty import
##
sub {
   run [ @vcp, "revml:-", $p4_spec ], \"<revml/>" ;
   __ok $?, 0, "`vcp revml:- $p4_spec` return value"  ;
},

sub {}, ## Two __ok's in next test.

sub {
   ## revml -> p4 -> revml, bootstrap export
   my $infile  = $t . "test-p4-in-0.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-0.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   ## We are also testing to see if we can re-root the files under foo/...
   ##
   eval {
      run [ @vcp, "revml:$infile", $p4_spec ], \undef
	 or die "`vcp revml:$infile $p4_spec` returned $?" ;

      __ok 1 ;

      my $in  = slurp $infile ;
      my $out = get_vcp_output "$p4_spec/..." ;
      s_content  qw( rep_desc time user_id p4_info ), \$in, \$out ;
      s_content  qw( rev_root ),                      \$in, "depot/foo" ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,       \$in, \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   __ok $@ || '', '', "diff"  ;
},

sub {
   ## Test a single file extraction from a p4 repo.  This file exists in
   ## change 1.
   __ok(
      get_vcp_output( "$p4_spec/add/f1" ),
      qr{<rev_root>depot/foo/add</.+<name>f1<.+<rev_id>1<.+<rev_id>2<.+</revml>}s
   ) ;
},

sub {
   ## Test a single file extraction from a p4 repo.  This file does not exist
   ## in change 1.
   __ok(
      get_vcp_output( "$p4_spec/add/f2" ),
      qr{<rev_root>depot/foo/add</.+<name>f2<.+<change_id>2<.+<change_id>3<.+</revml>}s
   ) ;

},

##
## p4->revml, re-rooting a dir tree
##
sub {
   eval {
      ## Hide global $p4_spec for the nonce
      my $p4_spec = "$p4_spec_base//depot/foo/a/deeply" ;

      my $infile  = $t . "test-p4-in-0.revml" ;
      my $in  = slurp $infile ;
      my $out = get_vcp_output "$p4_spec/..." ;

      s_content qw( rep_desc time user_id       ), \$in, \$out ;
      s_content qw( rev_root ),                    \$in, "depot/foo/a/deeply" ;
      rm_elts   qw( mod_time change_id p4_info ),  \$in, \$out ;
      rm_elts   qw( label ), qr/r_\w+|ch_\w+/,           \$out ;


      ## Strip out all files from $in that shouldn't be there
      rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

      ## Adjust the $in paths to look like the result paths.  $in is
      ## now the "expected" output.
      $in =~ s{<name>a/deeply/}{<name>}g ;

      assert_eq $infile, $in, $out ;
   } ;
   __ok $@ || '', '', 'diff' ;
},

##
## p4->cvs->revml bootstrap
##
sub { ## Two __ok's in next test.
   return skip $cvs_borken, "" if $cvs_borken ;
},

sub {
   return skip $cvs_borken, "" if $cvs_borken ;

   $ENV{CVSROOT} = $cvs_options->{repo};

   eval {
      run [ @vcp, "$p4_spec/...", "cvs:$cvs_module" ], \undef
	 or die "`vcp $p4_spec/... cvs:$cvs_module` returned $?" ;

      __ok 1 ;

      my $infile  = $t . "test-p4-in-0.revml" ;
      my $in = slurp $infile ;
      my $out = get_vcp_output "cvs:$cvs_module", qw( -r 1.1: ) ;

      s_content  qw( rep_desc rep_type time user_id ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $cvs_module ;
      rm_elts    qw( p4_info change_id ),              \$in ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,        \$in, \$out ;

      $out =~ s{<rev_id>1.}{<rev_id>}g ;
      $out =~ s{<base_rev_id>1.}{<base_rev_id>}g ;

      assert_eq $infile, $in, $out ;
   } ;
   __ok $@ || '', '', 'diff' ;
},

##
## revml -> p4 -> revml, incremental export
##
sub {}, ## Two __ok's in next test.
sub {
   eval {
      my $p4_binary = $^O =~ /Win32/ ? "p4.exe" : "p4" ;
      run
         [ $p4_binary, "-u", $p4_options->{user}, "-p", $p4_options->{port}, qw( counter change ) ],
	 \undef, \$incr_change ;
      chomp $incr_change ;
      die "Invalid change counter value: '$incr_change'"
         unless $incr_change =~ /^\d+$/ ;

      ++$incr_change ;

      my $infile  = $t . "test-p4-in-1.revml" ;
      run [ @vcp, "revml:$infile", "$p4_spec" ], \undef
	 or die "`vcp revml:$infile $p4_spec` returned $?" ;

      __ok 1 ;

      my $in  = slurp $infile ;
      my $out = get_vcp_output "$p4_spec/...\@$incr_change,#head" ;

      $in =~ s{</rev_root>}{/foo</rev_root>} ;
      s_content  qw( rep_desc time user_id p4_info ), \$in, \$out ;
      s_content  qw( rev_root ),                      \$in, "depot/foo" ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,       \$in, \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   __ok $@ || '', '', 'diff' ;
},

##
## p4->cvs->revml incremental export
##
sub { ## Two __ok's in next test.
   return skip $cvs_borken, "" if $cvs_borken ;
},

sub {
   return skip $cvs_borken, "" if $cvs_borken ;

   $ENV{CVSROOT} = $cvs_options->{repo};

   eval {
      run [ @vcp, "$p4_spec/...\@$incr_change,#head", "cvs:$cvs_module" ], \undef
	 or die "`vcp $p4_spec/...\@$incr_change,#head cvs:$cvs_module` returned $?" ;

      __ok 1 ;

      my $infile  = $t . "test-p4-in-1.revml" ;
      my $in = slurp $infile ;
      my $out = get_vcp_output "cvs:$cvs_module", "-r", "ch_$incr_change:" ;

      s_content  qw( rep_desc rep_type time user_id ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $cvs_module ;
      rm_elts    qw( p4_info change_id ),              \$in ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,        \$in, \$out ;

      $out =~ s{<rev_id>1.}{<rev_id>}g ;
      $out =~ s{<base_rev_id>1.}{<base_rev_id>}g ;

      assert_eq $infile, $in, $out ;
   } ;
   __ok $@ || '', '', 'diff' ;
},

##
## p4 -> revml, incremental export in bootstrap mode
##
sub {
   eval {
      my $infile  = $t . "test-p4-in-1-bootstrap.revml" ;
      my $in  = slurp $infile ;
      my $out = get_vcp_output
         "$p4_spec/...\@$incr_change,#head", "--bootstrap=**" ;

      $in =~ s{</rev_root>}{/foo</rev_root>} ;
      s_content  qw( rep_desc time user_id p4_info ), \$in, \$out ;
      s_content  qw( rev_root ),                      \$in, "depot/foo" ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,       \$in, \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   __ok $@ || '', '', 'diff' ;
},

) ;

plan tests => scalar @tests ;

my $p4d_borken = p4d_borken ;

my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
