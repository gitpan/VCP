#!/usr/local/bin/perl -w

=head1 NAME

03dest_branch_diagram.t - testing of VCP::Dest::branch_diagram services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Dest::branch_diagram;

my $p;
my $o;

my @options = (
   "--repo-id=repo-idfoo",
   "--db-dir=db-dirfoo",

   "--skip=skipfoo",
);

my @tests = (
sub {
   $p = VCP::Dest::branch_diagram->new( "branch_diagram" ) ;
   ok ref $p, 'VCP::Dest::branch_diagram';
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
