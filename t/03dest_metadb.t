#!/usr/local/bin/perl -w

=head1 NAME

03dest_metadb.t - testing of VCP::Dest::metadb services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Dest::metadb;

my $p;
my $o;

my @options = (
   "--repo-id=repo-idfoo",
   "--db-dir=db-dirfoo",
);

my @tests = (
sub {
   $p = VCP::Dest::metadb->new( "metadb" ) ;
   ok ref $p, 'VCP::Dest::metadb';
},

sub {
   $o = join( " ", map "'$_'", $p->options_as_strings );
   ok length $o;
},

(
   map {
      my $option = $_;
      $option =~ s/=.*//;
      sub {
         ok 0 <= index( $o, "'#$option" ), 1, $option;
      };
   } @options
),

sub {
   $p->parse_options( [ @options ] );
   $o = join( " ", map "'$_'", $p->options_as_strings );
   ok length $o;
},

(
   map {
      my $option = $_;
      sub {
         ok 0 <= index( $o, "'$option'" ), 1, $option;
      };
   } @options
),

sub {
   $o = $p->config_file_section_as_string;
   ok $o;
},

(
   map {
      my $option = $_;
      $option =~ s/^--?//;
      $option =~ s/=.*//;
      sub {
         ok 0 <= index( $o, $option ), 1, "$option documented";
      };
   } @options
),

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
