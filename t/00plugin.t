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
   my ( $obj ) = @_ ;

   return join(
      ' ',
      map(
         {
            local $_ = $obj->$_();
            defined $_ ? $_ : '-' ;
         }
         qw( repo_scheme repo_user repo_password repo_server repo_filespec )
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
sub { $p = VCP::Plugin->new() ; ok ref $p, 'VCP::Plugin' },
sub { ok $p->tmp_dir },
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
