#!/usr/local/bin/perl -w

=head1 NAME

03source_vss.t - testing of VCP::Source::vss services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Source::vss;

my $p;
my $o;

my @options = (
   "--repo-id=repo-idfoo",
   "--db-dir=db-dirfoo",

#   "--cd=cdfoo",
#   "--V=Vfoo1",
#   "--V=Vfoo2",
);

my @tests = (
sub {
   $p = VCP::Source::vss->new( "vss" ) ;
   ok ref $p, 'VCP::Source::vss';
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
         ok 0 <= index( $o, $option ), 1, $option;
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
