#!/usr/local/bin/perl -w

=head1 NAME

00revs.t - testing of VCP::Revs

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Rev;
use VCP::Revs;
use VCP::TestUtils qw( tmpdir );

## TODO: Add lots of tests to 00revs.t

my $rs ;

my $foo = VCP::Rev->new( source_name => "foo", source_rev_id => 0 );


my @tests = (
sub { $rs = VCP::Revs->new( STORE_LOC => tmpdir ) ; ok( ref $rs, "VCP::Revs" ) },

sub {
   $rs->add( VCP::Rev->new( source_name => "foo", source_rev_id => 1 ) );
   ok 1;
},

sub { ok $rs->get( "foo#1" )->id, "foo#1" },

sub {
   $rs->add( VCP::Rev->new( source_name => "foo", source_rev_id => 2 ) );
   ok 1;
},

sub { ok $rs->get( "foo#1" )->id, "foo#1" },
sub { ok $rs->get( "foo#2" )->id, "foo#2" },

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;

$rs = undef;
