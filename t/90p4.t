#!/usr/local/bin/perl -w

=head1 NAME

p4.t - testing of vcp p4 i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use File::Spec ;
use IPC::Run qw( run ) ;
use POSIX ':sys_wait_h' ;
use Test ;
use VCP::TestUtils ;

my $cwd = cwd ;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $p4_options = p4_options "p4_" ;
my $p4_spec = "p4:$p4_options->{user}:\@$p4_options->{port}://depot/foo" ;

my $incr_change ; # what change number to start incremental export at

my @tests = (
sub {
   $ENV{P4USER}   = "foobar_user" ;
   $ENV{P4PORT}   = "foobar_port" ;
   $ENV{P4CLIENT} = "foobar_client" ;
   $ENV{P4PASSWD} = "foobar_passwd" ;

   launch_p4d $p4_options ;
   ok 1 ;
},

sub {}, ## Two ok's in next test.

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

      ok 1 ;

      my $out ;
      run [ @vcp, "$p4_spec/..." ], \undef, \$out 
	 or die "`vcp $p4_spec/...` returned $?" ;

      my $in = slurp $infile ;
      s_content  qw( rep_desc time user_id p4_info ), \$in, \$out ;
      s_content  qw( rev_root ),                      \$in, "depot/foo" ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,       \$in, \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', "diff"  ;
},

sub {
   ## Test a single file extraction from a p4 repo.  This file exists in
   ## change 1.
   my $out ;
   run [@vcp, "$p4_spec/add/f1"], \undef, \$out ;
   ok(
      $out,
      qr{<rev_root>depot/foo/add</.+<name>f1<.+<rev_id>1<.+<rev_id>2<.+</revml>}s
   ) ;
},

sub {
   ## Test a single file extraction from a p4 repo.  This file does not exist
   ## in change 1.
   my $out ;
   run( [@vcp, "$p4_spec/add/f2"], \undef, \$out ) ;
   ok(
      $out,
      qr{<rev_root>depot/foo/add</.+<name>f2<.+<change_id>2<.+<change_id>3<.+</revml>}s
   ) ;

},

##
## p4->revml, re-rooting a dir tree
##
sub {
   eval {
      ## Hide global $p4_spec for the nonce
      my $p4_spec =
         "p4:$p4_options->{user}:\@$p4_options->{port}://depot/foo/a/deeply" ;

      my $out ;
      run [ @vcp, "$p4_spec/..." ], \undef, \$out
         or die "`vcp $p4_spec/...` returned $?" ;

      chdir $cwd or die $! ;

      my $infile  = $t . "test-p4-in-0.revml" ;
      my $in = slurp $infile ;

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
   ok $@ || '', '', 'diff' ;
},

##
## p4->cvs->revml bootstrap
##
sub {}, ## Two ok's in next test.

sub {
   my $cvs_options = cvs_options "p4_" ;
   mk_tmp_dir $cvs_options->{work} ;

   my $cvs_module = 'foo' ;
   init_cvs $cvs_options, $cvs_module ;

   $ENV{CVSROOT} = $cvs_options->{repo};
   my $infile  = $t . "test-p4-in-0.revml" ;

   eval {
      run [ @vcp, "$p4_spec/...", "cvs:$cvs_module" ], \undef
	 or die "`vcp $p4_spec/... cvs:$cvs_module` returned $?" ;

      ok 1 ;

      ## Gotta use a working directory with a checked-out version
      chdir $cvs_options->{work} or die $! . ": '$cvs_options->{work}'" ;
      run [qw( cvs checkout ), $cvs_module], \undef, \*STDERR
	 or die $! ;

      my $out ;
      run [ @vcp, "cvs:$cvs_module", qw( -r 1.1: ) ], \undef, \$out
	 or die "`vcp cvs:foo -r 1.1: ` returned $?" ;

      chdir $cwd or die $! ;

      my $in = slurp $infile ;

      s_content  qw( rep_desc rep_type time user_id ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $cvs_module ;
      rm_elts    qw( p4_info change_id ),              \$in ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,        \$in, \$out ;

      $out =~ s{<rev_id>1.}{<rev_id>}g ;
      $out =~ s{<base_rev_id>1.}{<base_rev_id>}g ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub {}, ## Two ok's in next test.
sub {
   ## revml -> p4 -> revml, incremental export
   my $infile  = $t . "test-p4-in-1.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-1.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   eval {
      run
         [ qw( p4 -u ), $p4_options->{user}, "-p", $p4_options->{port}, qw( counter change ) ],
	 \undef, \$incr_change ;
      chomp $incr_change ;
      die "Invalid change counter value: '$incr_change'"
         unless $incr_change =~ /^\d+$/ ;

      ++$incr_change ;

      run [ @vcp, "revml:$infile", "$p4_spec" ], \undef
	 or die "`vcp revml:$infile $p4_spec` returned $?" ;

      ok 1 ;

      my $out ;
      run [ @vcp, "$p4_spec/...\@$incr_change,#head" ], \undef, \$out
	 or die "`vcp $p4_spec/...\@$incr_change,#head` returned $?" ;

      my $in = slurp $infile ;

      $in =~ s{</rev_root>}{/foo</rev_root>} ;
      s_content  qw( rep_desc time user_id p4_info ), \$in, \$out ;
      s_content  qw( rev_root ),                      \$in, "depot/foo" ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,       \$in, \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub {
   ## p4 -> revml, incremental export in bootstrap mode
   my $infile  = $t . "test-p4-in-1-bootstrap.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-0.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   eval {
      my $out ;

      run( [ @vcp, "$p4_spec/...\@$incr_change,#head", "--bootstrap=**" ],
         \undef, \$out
      ) or die(
	 "`vcp $p4_spec/...\@$incr_change,#head --bootstrap=**` returned $?"
      ) ;

      my $in = slurp $infile ;

      $in =~ s{</rev_root>}{/foo</rev_root>} ;
      s_content  qw( rep_desc time user_id p4_info ), \$in, \$out ;
      s_content  qw( rev_root ),                      \$in, "depot/foo" ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,       \$in, \$out ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

) ;

plan tests => scalar @tests ;

my $p4d_borken = p4d_borken ;

my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
