#!/usr/local/bin/perl -w

=head1 NAME

03dest_topo_table.t - testing of VCP::Dest::topo_table services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Dest::topo_table;

my $p;
my $o;

my @options = ();

my @tests = (
sub {
   $p = VCP::Dest::topo_table->new( "topo_table" ) ;
   ok ref $p, 'VCP::Dest::topo_table';
},

sub {
   $o = join( " ", map "'$_'", $p->options_as_strings );
   ok !length $o;
},

sub {
   $p->parse_options( [] );
   $o = join( " ", map "'$_'", $p->options_as_strings );
   ok !length $o;
},

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

);

plan tests => scalar( @tests ) ;

$_->() for @tests ;
