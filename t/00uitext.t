#!/usr/local/bin/perl -w

=head1 NAME

00uitext.t - unit testing of VCP::UI::Text

=cut

use strict ;

use Carp ;
use Test ;
use VCP::UI::Text;

my $t = VCP::UI::Text->new;

sub _v {
   my @result = eval { $t->validate( @_ ) };
   return @result
       ? @result > 1
           ? join "=>", $result[0], $result[1]->[0]
           : $result[0]
       : $@;
}


my @tests = (
sub { ok $t->build_prompt( "A", undef, [] ),              "A?";            },
sub { ok $t->build_prompt( "A", undef, [qw( B   )] ),     "A (B)?";        },
sub { ok $t->build_prompt( "A", undef, ["", qw( B )] ),   "A (B)?";        },
sub { ok $t->build_prompt( "A", undef, [qw( B C )] ),     "A (B, C)?";     },
sub { ok $t->build_prompt( "A", undef, ["", qw( B C )] ), "A (B, C)?";     },
sub { ok $t->build_prompt( "A", "A",   ["", qw( B C )] ), "A (B, C) [A]?"; },

sub { ok _v( "A", [] ), 0 },
sub { ok _v( "A", [ [qw( x A )], [qw( y B )] ] ), "A=>x" },
sub { ok _v( "B", [ [qw( x A )], [qw( y B )] ] ), "B=>y" },
sub { ok _v( "C", [ [qw( x A )], [qw( y B )] ] ), 0 },

sub { ok _v( "A", [ [ x => qr/a/ ], [y => qr/b/], [z => qr/a/i] ] ), "A=>z" },
);

plan tests => scalar( @tests ) ;

$_->() for @tests ;
