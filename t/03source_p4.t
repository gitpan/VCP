#!/usr/local/bin/perl -w

=head1 NAME

03source_p4.t - testing of VCP::Source::p4 services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Source::p4;

my $p;
my $o;

my @options = (
   "--repo-id=repo-idfoo",
   "--db-dir=db-dirfoo",

   "--bootstrap=bootfoo",
   "--continue",

   "--follow-branch-into",
   "--rev-root=rootfoo",
   "--run-p4d",
);

my @tests = (
sub {
   $p = VCP::Source::p4->new( "p4" ) ;
   ok ref $p, 'VCP::Source::p4';
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
