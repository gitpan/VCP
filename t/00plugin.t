#!/usr/local/bin/perl -w

=head1 NAME

plugin.t - testing of VCP::Plugin services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Plugin ;

my $p ;

sub flatten_spec {
   my ( $parsed_spec ) = @_ ;

   return join(
      ' ',
      map(
         defined $_ ? $_ : '-' ,
         @$parsed_spec{qw( SCHEME USER PASSWORD SERVER FILES )}
      )
   ) ;
}

my @repo_vectors = (
[ 'scheme:user:password@server:files',
  'scheme user password server files' ],   

[ 'scheme:user:password@ser@:ver:files',
  'scheme user password ser@:ver files' ],   

[ 'scheme:files',
  'scheme - - - files' ],   

[ 'scheme:user@files',
  'scheme - - - user@files' ],   

[ 'scheme:user@:files',
  'scheme user - - files' ],   

) ;

my @tests = (
sub { $p = VCP::Plugin->new() ; ok( ref $p, 'VCP::Plugin' ) },

##
## rev_root cleanup
##
sub { $p->rev_root( '\\//foo\\//bar\\//' )     ; ok( $p->rev_root, 'foo/bar' )},
sub { $p->deduce_rev_root( '\\foo/bar/blah*blop/baz' ) ;   ok( $p->rev_root, 'foo/bar' )},
sub { $p->deduce_rev_root( '\\foo/bar/blah?blop/baz' ) ;   ok( $p->rev_root, 'foo/bar' )},
sub { $p->deduce_rev_root( '\\foo/bar/blah...blop/baz' ) ; ok( $p->rev_root, 'foo/bar' )},

##
## Normalization & de-normalization
##
sub { ok( $p->normalize_name( '/foo/bar/baz' ), 'baz' ) },
sub { eval {$p->normalize_name( '/foo/hmmm/baz' ) }, ok( $@ ) },
sub { ok( $p->denormalize_name( 'barf' ), 'foo/bar/barf' ) },

( map {
      my ( $spec, $flattened ) = @$_ ;
      sub { ok( flatten_spec( $p->parse_repo_spec( $spec ) ), $flattened ) },
   } @repo_vectors
),

sub {
   $p->parse_repo_spec( 'scheme:user:password@server:files' ) ;
   ok( $p->repo_user, 'user' ) ;
},

sub {
   ok( $p->repo_password, 'password' ) ;
},

sub {
   ok( $p->repo_server, 'server' ) ;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
