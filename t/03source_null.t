#!/usr/local/bin/perl -w

=head1 NAME

03source_null.t - testing of VCP::Source::null services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Source::null;

my $p;
my $o;

my @options = ();

my @tests = (
sub {
   $p = VCP::Source::null->new() ;
   ok ref $p, 'VCP::Source::null';
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

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
