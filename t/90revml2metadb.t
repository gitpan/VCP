#!/usr/local/bin/perl -w

=head1 NAME

90revml2metadb.t - testing of vcp metadb i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use Test ;
use VCP::Utils qw( start_dir_rel2abs );
use VCP::TestUtils;

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

my $infile = "${t}test-revml-in-0.revml";
my $metadbstate = "${t}metadbstate";
my $repo_id = "revml:test_repository";

my @tests = (

##
## Empty scan
##
sub {
   run [ @vcp, "scan", "revml:-", "revml:-" ],
      \"<revml/>"; #"# de-confuse emacs' cperl mode
   ok $?, 0, "`vcp scan revml:- revml:-` return value"  ;
},

sub {
   ok run [ @vcp, "scan", "revml:$infile", "revml:-" ];
},

sub {
   ok run [ @vcp, "filter", "revml:$infile", "revml:-" ];
},

sub {
   run [ @vcp, "transfer", "revml:$infile", "revml:-" ], \undef, \my $out;

   my $in = slurp $infile;
   ok_or_diff $in, $out;
},

) ;


plan tests => scalar( @tests ) ;

$_->() for @tests ;
