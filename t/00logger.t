#!/usr/local/bin/perl -w

=head1 NAME

00logger.t - See if the logger compiles properly.

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Logger qw( lg );

## TODO: Add lots of tests to 00rev.t

my @tests = (
## Test some utility functions first
sub { lg "logger test"; ok 1; },
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
