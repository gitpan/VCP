#!/usr/local/bin/perl -w

=head1 NAME

80rcs_parser.t - test VCP::Source::cvs's RCS file parser

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Source::cvs;
use VCP::Dest::null;

sub check {
   goto &die if $ENV{FATALTEST} && ! $_[0];
}


my $s;

my @tests = (
(
   map {
      my $size = $_;
      (
         sub {
            $s = VCP::Source::cvs->new( "cvs:t:...", [] );
            $s->init;

            $s->{CVS_READ_SIZE} = $size;
            check ok
               eval { $s->parse_rcs_file( "rcs_file" ); 1 } || $@,
               1,
               "READ_SIZE = $size";
         },
         sub {
            check ok $s->sent_rev_count, 8;
               ## 8= 4 main branch revs
               ##    1 branch rev
               ##    1 rev on main-branch-1
               ##    1 branch rev cloned to main-branch-2
               ##    1 rev on main-branch-1 cloned to main-branch-2
         },
      );
   } ( 1_000_000, 1, 2, 3, 5, 7, 11, 13, 17, 19, 23, 29 )
),

sub {
   my $s = VCP::Source::cvs->new( "cvs:t:rcs_file", [] );
   my $d = VCP::Dest::null->new;
   $s->dest( $d );
   $d->{NULL_GET_REVS} = 0;  ## Don't try to actually copy the revs,
                             ## t/ is not a real repository.  We just want
                             ## to make sure that all the metadata can be
                             ## extracted to test parsing of vendor branch
                             ## rev numbers (at least).  It's a regression
                             ## thing.
   $s->init;
   $s->copy_revs;
   ok 1;
},

sub {
   my $s = VCP::Source::cvs->new( "cvs:t:buildpss.ksh", [] );
   my $d = VCP::Dest::null->new;
   $s->dest( $d );
   $d->{NULL_GET_REVS} = 0;  ## Don't try to actually copy the revs,
                             ## t/ is not a real repository.  We just want
                             ## to make sure that all the metadata can be
                             ## extracted to test parsing of vendor branch
                             ## rev numbers (at least).  It's a regression
                             ## thing.
   $s->init;
   $s->copy_revs;
   ok 1;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
