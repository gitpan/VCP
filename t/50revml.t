#!/usr/local/bin/perl -w

=head1 NAME

revml.t - testing of vcp revml in and out

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;
use constant is_win32 => $^O =~ /Win32/;

my @vcp = vcp_cmd ;

my @sort = qw( sort: -- );


my $t = -d 't' ? 't/' : '' ;

my $in_revml         = $t . "test-revml-in-0-no-big-files.revml" ;
my $compressed_revml = "/tmp/50revml_$$.revml.gz";

my @tests = (
##
## Empty imports, used here just to see if commad line parsing is ok and
## that a really simple file can make it through the XML parser ok.
##
sub {
   run [ @vcp, "revml:-", "revml:" ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- revml:` return value"  ;
},

sub {
   run [ @vcp, "-", "-" ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- revml:` return value"  ;
},

sub {
   run [ @vcp, "-", ], \"<revml/>" ;
   ok $?, 0, "`vcp revml:- revml:` return value"  ;
},

# create gzipped revml
sub {
   return skip 1, "gzip not normally found on Win32" if is_win32;
   run [ @vcp, "revml:$in_revml", "revml:$compressed_revml", "--compress" ];
   ok $?, 0, "vcp return value"  ;
},

# check that gzipped revml exists
sub {
   return skip 1, "gzip not normally found on Win32" if is_win32;
   ok -z $compressed_revml, '', "gzipped file $compressed_revml created";
},

# uncompress the gzipped revml
sub {
   return skip 1, "gzip not normally found on Win32" if is_win32;
   my $out;
   run [ @vcp, "revml:$compressed_revml", "--uncompress", @sort, "revml:-", ],
      \undef, \$out;
   unlink $compressed_revml or warn "failed to unlink $compressed_revml";

   my $expected = slurp $in_revml;
   ok_or_diff $out, $expected;
},

# two ok's in next test
sub {},

# create non-indented revml
sub {
   my $out;
   run [ @vcp, "revml:$in_revml", "revml:-", "--no-indent" ],
      \undef, \$out;

   # there should be no leading whitespace on any line
   ok $out !~ /^\s/m ;

   # re-indent the result, to check against original
   my $re_indented_out;
   run [ @vcp, "revml:-", @sort, "revml:-" ],
      \$out, # now the input
      \$re_indented_out;

   my $expected = slurp $in_revml;

   ok_or_diff $re_indented_out, $expected;
},

( map {
   my $source_spec = $_;
   sub {
     my $out ;
     my $infile  = $t . "test-revml-in-0.revml" ;
     $source_spec =~ s/INFILE/$infile/;
     run [ @vcp, $source_spec, @sort, "-" ], \undef, \$out;
     my $in = slurp( $infile ) ;
     ok_or_diff $out, $in, $source_spec;
   };
} qw( INFILE revml:INFILE revml:INFILE: revml:INFILE:/... )
),

( map {
   my $type = $_ ;

   ##
   ## Idempotency tests
   ##
   ## These depend on the "test-foo-in.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   sub {
      my $out ;
      my $infile  = $t . "test-$type-in-0.revml" ;
      ## $in and $out allow us to avoide execing diff most of the time.
      run [ @vcp, "$infile", @sort, "-" ], \undef, \$out;

      my $in = slurp( $infile );

      ok_or_diff $out, $in, $type;
   },
} qw( revml cvs p4 ) )
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
