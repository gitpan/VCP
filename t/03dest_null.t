#!/usr/local/bin/perl -w

=head1 NAME

03dest_null.t - testing of VCP::Dest::null services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Dest::null;

my $p;
my $o;

my @options = ();

my @tests = (
sub {
   $p = VCP::Dest::null->new() ;
   ok ref $p, 'VCP::Dest::null';
},

sub {
   $o = join( " ", map "'$_'", $p->options_as_strings );
   ok length $o;
},

sub {
   $p->parse_options( [] );
   $o = join( " ", map "'$_'", $p->options_as_strings );
   ok length $o;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
