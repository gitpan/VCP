#!/usr/local/bin/perl -w

=head1 NAME

00rev.t - testing of VCP::Rev services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Rev ;
use VCP::Utils qw( empty );

## TODO: Add lots of tests to 00rev.t

my $r1 ;
my @r1;  ## we serialize to/from this

my $r1a;

my @tests = (
## Test some utility functions first
sub { ok join( ",", VCP::Rev->split_id( "1"       ) ), "1"       },
sub { ok join( ",", VCP::Rev->split_id( "1a"      ) ), "1,a"     },
sub { ok join( ",", VCP::Rev->split_id( "1.2"     ) ), "1,,2"    },
sub { ok join( ",", VCP::Rev->split_id( "1a.2"    ) ), "1,a,2"   },
sub { ok join( ",", VCP::Rev->split_id( "1a.2b"   ) ), "1,a,2,b" },

sub { ok( VCP::Rev->cmp_id( [qw( 1 a 2 )], [qw( 1 b 1 )] ) < 0 ) },
sub { ok( VCP::Rev->cmp_id( "1a2", "1b1" ) < 0 ) },
sub { ok( VCP::Rev->cmp_id( [qw( 1 a 2 )], [qw( 1 a 1 )] ) > 0 ) },
sub { ok( VCP::Rev->cmp_id( [qw( 1 b 2 )], [qw( 1 a 1 )] ) > 0 ) },
sub { ok( VCP::Rev->cmp_id( [qw( 10 )],    [qw( 1 )] ) > 0 ) },

## now test methods
sub { $r1 = VCP::Rev->new() ; ok( ref $r1, "VCP::Rev" ) },

( map {
      my $field = lc $_;
      (
         sub {
            ok ! defined $r1->$field, 1, "! defined $field";
         },
         sub {
            $r1->$field( 10 );
            ok $r1->$field, 10, "$field";
         },
         sub {
            $r1->$field( undef );
            ok ! defined $r1->$field, 1, "! defined $field #2";
         },
      );
   } (
   ## 'ID',  ## this has a default value, tested below
   'NAME',
   'SOURCE_NAME',
   'SOURCE_FILEBRANCH_ID',
   'SOURCE_REPO_ID',
   'TYPE',
   'BRANCH_ID',
   'SOURCE_BRANCH_ID',
   'REV_ID',
   'SOURCE_REV_ID',
   'CHANGE_ID',
   'SOURCE_CHANGE_ID',
   'P4_INFO',
   'CVS_INFO',
   'TIME',
   'MOD_TIME',
   'USER_ID',
   #'LABELS',  ## different beast, tested below
   'COMMENT',
   'ACTION',
   'PREVIOUS_ID',
   )
),

sub { ok ! $r1->labels },

sub {
   $r1->add_label( "l1" ) ;
   ok( join( ",", $r1->labels ), "l1" ) ;
},

sub {
   $r1->add_label( "l2", "l3" ) ;
   ok( join( ",", $r1->labels ), "l1,l2,l3" ) ;
},

sub {
   $r1->add_label( "l2", "l3" ) ;
   ok( join( ",", $r1->labels ), "l1,l2,l3" ) ;
},

sub {
   $r1->set_labels( [ "l4", "l5" ] ) ;
   ok( join( ",", $r1->labels ), "l4,l5" ) ;
},

sub {
   $r1->name( "foo" );
   ok $r1->name, "foo";
},

sub {
   $r1->source_name( "foo" );
   ok $r1->source_name, "foo";
},

sub {
   $r1->source_rev_id( "1" );
   ok $r1->source_rev_id, "1";
},

sub {
   ok $r1->id, "foo#1";
},

## Excercise an integer field

sub {
   $r1->set_time( 0 );
   ok $r1->time, 0;
},

sub {
   $r1->set_time( 1 );
   ok $r1->time, 1;
},

sub {
   $r1->set_time( undef );
   ok ! defined $r1->time;
},

## Excercise a string field

sub {
   $r1->set_name( "foo" );
   ok $r1->name, "foo";
},

sub {
   $r1->set_name( "bar" );
   ok $r1->name, "bar";
},

sub {
   $r1->set_name( undef );
   ok ! defined $r1->name;
},

## now test setting a few things in the ctor
sub {
   $r1 = VCP::Rev->new(
      name   => "Name",
      labels => [ "l1", "l2" ],
      type   => "Type",
   );
   ok ref $r1, "VCP::Rev";
},

sub { ok $r1->name, "Name" },
sub { ok join( ",", $r1->labels ), "l1,l2" },
sub { ok $r1->type, "Type" },
sub { ok ! defined $r1->user_id, 1, "! defined user_id" },
sub { ok ! defined $r1->comment, 1, "! defined comment" },

sub {
   $r1->id( "a rev" );
   $r1->comment( "a comment\nwith a newline\nor three\n" );
   @r1 = $r1->serialize;
   ok @r1;
},

sub {
   ok grep( ! defined, @r1 ), 0;
},

sub {
   $r1a = VCP::Rev->deserialize( @r1 );
   ok $r1a;
},

sub {
   ok $r1a->id, $r1->id;
},

sub {
   ok $r1a->comment, $r1->comment;
},

sub {
   ok join( "|", sort $r1a->labels ), join( "|", $r1->labels );
},

sub {
   my @r1a = $r1a->serialize;
   ok join( "|", @r1 ), join( "|", @r1a );
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
