#!/usr/local/bin/perl -w

=head1 NAME

00filter.t - testing of VCP::Filter services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Filter;
use VCP::Utils qw( start_dir_rel2abs );

my $r ;

my $f = VCP::Filter->new;
my $rules;

my @tests = (
sub {
    $rules = $f->parse_rules_list(
       [(1..6), "--", "NONONO" ],
       "A", "B", "C"
    );
    ok $rules;
},

sub { ok @$rules, 2; },
sub { ok ! grep @$_ != 3, @$rules; },
sub { ok $rules->[0]->[0], 1 },
sub { ok $rules->[0]->[1], 2 },
sub { ok $rules->[0]->[2], 3 },
sub { ok $rules->[1]->[0], 4 },
sub { ok $rules->[1]->[1], 5 },
sub { ok $rules->[1]->[2], 6 },

sub {
   @VCP::Filter::foo::ISA = qw( VCP::Filter );
   bless $f, "VCP::Filter::foo";
   $INC{"VCP/Filter/foo.pm"} = start_dir_rel2abs $0; ## To make the POD scanner happy.
   ok $f->config_file_section_as_string, qr/Foo:.*1 *2 *3.*\n.*4 *5 *6.*\n\n/s;
},
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
