#!/usr/local/bin/perl -w

=head1 NAME

00p4form.t - Testing of p4 form parsing.

=cut

use strict;

use Carp;
use Test;
use VCP::TestUtils;
use VCP::Utils::p4;

# Note the literal tabs and the space after "Block:"
my $f = <<END_OF_FORM;
# comment 1

Foo: Bar
Biz: -

Hic: up
	up

Block: 

# comment 2
	Tackle    # comment 3
	Offense   # comment 4

# comment 5
# comment 6

END_OF_FORM

my @f;
my %f;

## It's a mix in, but we don't need that since we're not testing the
## forms of these methods that invoce the p4 command.
my $p4 = bless {}, "VCP::Utils::p4";

my @tests = (

sub {
   %f = @f = $p4->parse_p4_form( $f );
   ok 0+@f, 8, "names+values from form";
},

sub { ok $f{Foo},   "Bar" },
sub { ok $f{Biz},   "-" },
sub { ok_or_diff $f{Hic},   "up\nup" },
sub { ok_or_diff $f{Block}, "\nTackle\nOffense" },

sub {
   ( my $f2 = $f ) =~ s/(?<!:)\n\n+/\n/g;
   $f2 =~ s/(Block: )/$1\n/g;
   my @f2 = $p4->parse_p4_form( $f2 );
   ok_or_diff \@f2, \@f;
},

sub {
   my $fout = $p4->build_p4_form( @f );
   ## build_p4_form always makes multiline values start on an indented line
   ## and always inserts a single tab char.  So our Hic: test needs to be
   ## tweaked a bit.
   ( my $munged_f = $f ) =~ s/: up/:\n\tup/;
   $munged_f =~ s/[ \t]+#.*//gm;    # kill EOL comments
   $munged_f =~ s/^#.*(\r?\n)+//gm; # kill whole line comments
   $munged_f =~ s/(Block:)[ \t]+/$1/;
   $fout =~ s/\nBiz/Biz/;
   ok_or_diff $fout, $munged_f;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
