#!/usr/local/bin/perl -w

=head1 NAME

90vss.t - testing of vcp vss i/o

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

my $project = "90vss.t" ;  ## Must match the rev_root in the testrevml files

my $vss_spec = "vss:$project" ;

my @revml_out_spec = ( "revml:", "--sort-by=name,rev_id" ) ;

my $max_change_id ;

my $p4_spec_base ;
my $p4d_borken = p4d_borken ;

my @tests = (
sub {
   system( "ss destroy \$/$project -I-y -O-" );
   system( "ss create  \$/$project -C- -I- -O-") and die "command failed";
   ok 1;
},
## Empty import
##
sub {
   run [ @vcp, "revml:-", $vss_spec ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- $vss_spec` return value"  ;
},
##
## revml->vss->revml idempotency
##
sub {},  ## Mult. ok()s in next sub{}.

sub {
   eval {
      my $infile  = $t . "test-vss-in-0.revml" ;
      ## $in and $out allow us to avoide execing diff most of the time.
      run [ @vcp, "revml:$infile", $vss_spec ], \undef
	 or die "`vcp revml:$infile $vss_spec` returned $?" ;
      ok 1 ;
      my $out ;
      run [ @vcp, "$vss_spec/...", @revml_out_spec ], \undef, \$out
         or die "`vcp $vss_spec` returned $?" ;

      my $in = slurp $infile ;

      s_content  qw( rep_desc time user_id          ), \$in, \$out ;
      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rev_root ),                       \$in, $project ;
      rm_elts    qw( mod_time change_id vss_info    ), \$in           ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out    ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff ';
},

##
## vss->revml, re-rooting a dir tree
##
sub {
   eval {
      ## Hide global $vss_spec for the nonce
      my $vss_spec = "$vss_spec/a/deeply/..." ;

      my $out ;
      run [ @vcp, $vss_spec, @revml_out_spec ], \undef, \$out
         or die "`vcp $vss_spec` returned $?" ;

      my $infile  = $t . "test-vss-in-0.revml" ;
      my $in = slurp $infile ;

      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rep_desc time user_id                   ), \$in, \$out ;
      rm_elts    qw( mod_time change_id vss_info             ), \$in, \$out ;
      rm_elts    qw( label ),          qr/r_\w+|ch_\w+/,              \$out ;


      ## Strip out all files from $in that shouldn't be there
      rm_elts    qw( rev ), qr{(?:(?!a/deeply).)*?}s, \$in ;

      ## Adjust the $in paths to look like the result paths.  $in is
      ## now the "expected" output.
      s_content  qw( rev_root ),                    \$in, "$project/a/deeply" ;
      $in =~ s{<name>a/deeply/}{<name>}g ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},
##
## vss->p4->revml
##
#);@tests=(
sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   $ENV{P4USER}   = "foobar_user" ;
   $ENV{P4PORT}   = "foobar_port" ;
   $ENV{P4CLIENT} = "foobar_client" ;
   $ENV{P4PASSWD} = "foobar_passwd" ;

   my $p4_options = launch_p4d "vss_" ;
   $p4_spec_base = "p4:$p4_options->{user}:\@$p4_options->{port}:" ;
   ok 1 ;
},

sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   my $p4_spec = "$p4_spec_base//depot" ;

   eval {
      run [ @vcp, "$vss_spec/...", "$p4_spec/..." ], \undef
         or die "`vcp $vss_spec` returned $?" ;
      my $out ;
      run [ @vcp, "$p4_spec/...", @revml_out_spec ], \undef, \$out ;

      my $infile  = $t . "test-vss-in-0.revml" ;
      my $in = slurp $infile ;

      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rep_desc time user_id rep_type ), \$in, \$out ;
      s_content  qw( rev_root                       ), \$in, "depot" ;
      rm_elts    qw( vss_info mod_time change_id    ), \$in        ;
      rm_elts    qw( p4_info                        ),       \$out ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      ## p4 generates more info than VSS on deletes.
      $out =~ s{
         (<name>del/[^<]*</name>      [^<]*)
         (?:(?!</rev>).)*(<rev_id>(?:(?!</rev>).)*?</rev_id>[^<]*)
         (?:(?!</rev>).)*(<delete\s*/>[^<]*)
      }{$1$2$3}sxg;

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
   ok $max_change_id, 3, "Max change_id in vss->p4 transfer" ;
},

#);my @foo=(
##
## vss->p4->revml, re-rooting a dir tree
##
sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   ## Hide global $vss_spec for the nonce
   my $vss_spec = "$vss_spec/a/deeply/..." ;

   my $p4_spec = "$p4_spec_base//depot/new/..." ;
   eval {
      run [ @vcp, $vss_spec, $p4_spec ], \undef
         or die "`vcp $vss_spec` returned $?" ;

      my $out ;
      run [ @vcp, $p4_spec, @revml_out_spec ], \undef, \$out
         or die "`vcp $p4_spec` returned $?" ;

      my $infile  = $t . "test-vss-in-0.revml" ;
      my $in = slurp $infile ;

      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rep_desc time user_id rep_type  ), \$in, \$out ;
      s_content  qw( rev_root                        ), \$in, "depot/new" ;
      rm_elts    qw( vss_info mod_time change_id     ), \$in ;
      rm_elts    qw( p4_info                         ),       \$out ;
      rm_elts    qw( label ),  qr/r_\w+|ch_\w+/,              \$out ;

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
## No clean way to verify this, I think
sub {
## MAY BREAK WHEN I UNCOMMENT THIS
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;
   ok $max_change_id, 6, "Max change_id in vss->p4 transfer" ;
},
##
## Idempotency test for an incremental revml->vss->revml update
##
sub {},  ## Mult. ok()s in next sub{}.

sub {
   my $infile  = $t . "test-vss-in-1.revml" ;
   eval {
      ## $in and $out allow us to avoid execing diff most of the time.
      run [ @vcp, "revml:$infile", $vss_spec ], \undef
	 or die "`vcp revml:$infile $vss_spec` returned $?" ;

      ok 1 ;

      my $out ;
      run [ @vcp, "$vss_spec/...", qw( -V ~Lch_4 ), @revml_out_spec ], \undef, \$out
         or die "`vcp $vss_spec/... -V ~Lch_4` returned $?" ;

      my $in = slurp $infile ;

      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rep_desc time user_id          ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $project ;
      rm_elts    qw( mod_time change_id vss_info    ), \$in        ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      ## vss adds in more "delete"s that other reps because
      ## it can't tell when something was deleted relative
      ## to a label.
      $out =~ s{^\s*<rev>\s*<name>del/(?:f2|f3).*?</rev>\r?\n}{}smg;

      ## we don't get the base rev for del/f4, since it doesn't
      ## carry the ch_4 label.  Perhaps we should.
      $in =~ s{^\s*<rev>\s*<name>del/f4.*?</rev>\r?\n}{}sm;

      ## readd does not carry a ch_4 label and we don't force missing
      ## revisions like cvs does.  we probably should.
      $in =~ s{^\s*<rev>\s*<name>readd.*?</rev>\r?\n}{}sm;
      $in =~ s{^\s*<rev>\s*<name>readd.*?</rev>\r?\n}{}sm;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},
#); push @tests, (
##
## Incremental vss->p4->revml update
##
sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;

   my $p4_spec = "$p4_spec_base//depot" ;

   eval {
      run [ @vcp, "$vss_spec/...", qw( -V ~Lch_4 ), "$p4_spec/..." ], \undef
         or die "`vcp $vss_spec/... -V ~Lch_4` returned $?" ;

      my $out ;
      my $first_change = $max_change_id + 1 ;
      run [ @vcp, "$p4_spec/...\@$first_change,#head", @revml_out_spec ],
         \undef, \$out
         or die "`vcp $p4_spec/...\@$first_change,#head` returned $?" ;

      my $infile  = $t . "test-vss-in-1.revml" ;
      my $in = slurp $infile ;

      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rep_desc time user_id rep_type ), \$in, \$out ;
      s_content  qw( rev_root                       ), \$in, "depot" ;
      rm_elts    qw( vss_info mod_time change_id    ), \$in        ;
      rm_elts    qw( p4_info                        ),       \$out ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      $out =~ s{^.*<change_id>(.*?)</change_id>.*(\r\n|\n\r|\n)}{
	 $max_change_id = $1
	    if ! defined $max_change_id || $1 > $max_change_id ;
	 "" ;
      }gem ;

      ## readd does not carry a ch_4 label and we don't force missing
      ## revisions like cvs does.  we probably should.
      $in =~ s{(<name>readd.*?)^\s*<rev>\s*<name>readd.*?</rev>\r?\n}{$1}sm;

      ## p4 generates more info than VSS on deletes.
      $out =~ s{
         (<name>(?:del/|readd)[^<]*</name>      [^<]*)
         (?:(?!</rev>).)*(<rev_id>(?:(?!</rev>).)*?</rev_id>[^<]*)
         (?:(?!</rev>).)*(<delete\s*/>[^<]*)
      }{$1$2$3}sxg;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub {
   return skip $p4d_borken, 1, 1, $p4d_borken if $p4d_borken ;
   ok $max_change_id, 9, "Max change_id in vss->p4 transfer" ;
},

##
## revml->vss->revml Idempotency test, bootstrapping the second set of changes
##
sub {
   my $infile  = $t . "test-vss-in-1-bootstrap.revml" ;
   eval {
      my $out ;
      run [ @vcp, "$vss_spec/...", qw( -V ~Lch_4 --bootstrap=... ), @revml_out_spec ],
         \undef, \$out
         or die "`vcp $vss_spec/... -V ~Lch_4` returned $?" ;

      my $in = slurp $infile ;

      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rep_desc time user_id          ), \$in, \$out ;
      s_content  qw( rev_root ),                       \$in, $project ;
      rm_elts    qw( mod_time change_id vss_info    ), \$in        ;
      rm_elts    qw( label ), qr/r_\w+|ch_\w+/,              \$out ;

      ## readd does not carry a ch_4 label and we don't force missing
      ## revisions like cvs does.  we probably should.
      $in =~ s{^\s*<rev>\s*<name>readd.*?</rev>\r?\n}{}sm;

      ## vss adds in more "delete"s that other reps because
      ## it can't tell when something was deleted relative
      ## to a label.
      $out =~ s{^\s*<rev>\s*<name>del/(?:f2|f3).*?</rev>\r?\n}{}smg;

      ## p4 generates more info than VSS on deletes.
      $out =~ s{
         (<name>(?:del/|readd)[^<]*</name>      [^<]*)
         (?:(?!</rev>).)*(<rev_id>(?:(?!</rev>).)*?</rev_id>[^<]*)
         (?:(?!</rev>).)*(<delete\s*/>[^<]*)
      }{$1$2$3}sxg;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

##
## revml->vss, re-rooting a dir tree
##
## Do this after the above tests so that we don't accidently introduce
## a bunch of additional changes, especially for the vss->p4 tests.
##
sub {}, ## Two ok()'s in next sub.

sub {
   eval {
      ## Hide global $vss_spec for the nonce
      my $vss_spec = "$vss_spec/newdir/..." ;

      my $infile  = $t . "test-vss-in-0.revml" ;
      ## $in and $out allow us to avoide execing diff most of the time.
      run [ @vcp, "revml:$infile", $vss_spec ], \undef
	 or die "`vcp revml:$infile $vss_spec` returned $?" ;

      ok 1 ;

      my $out ;
      run [ @vcp, $vss_spec, @revml_out_spec ], \undef, \$out
         or die "`vcp $vss_spec` returned $?" ;

      my $in = slurp $infile ;

      ## I didn't want to emulate VSS's "bump the version
      ## for every little thing" in bin/gentrevml, so I just
      ## blow rev_id and base_rev_id away.
      s_content  qw( rev_id base_rev_id ),             \$in, \$out    ;
      s_content  qw( rep_desc time user_id                   ), \$in, \$out ;
      rm_elts    qw( mod_time change_id vss_info             ), \$in, \$out ;
      rm_elts    qw( label ),          qr/r_\w+|ch_\w+/,              \$out ;

      ## Adjust the $in rev_root to look like the result paths.  $in is
      ## now the "expected" output.
      s_content  qw( rev_root ),                       \$in, "$project/newdir" ;

      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

) ;

plan tests => scalar( @tests ) ;

my $why_skip ;

$why_skip .= vss_borken ;
$why_skip ? skip( $why_skip, 0 ) : $_->() for @tests ;
