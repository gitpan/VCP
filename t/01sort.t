#!/usr/local/bin/perl -w

=head1 NAME

01sort.t - test sorting of VCP::Rev

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Rev ;
use VCP::Dest ;

my @field_names=
(qw( name   change_id rev_id comment )) ;

## This defines the sort specs for the test and maps them to field names
## that are used to test the result order.  This allows us to do multiple
## sort-by keys and check some field that is unique in every rev, as well
## testing aliases for real fields, like "rev" is for "rev_id".
my %specs = (
   qw(
      name         name
      change       change_id
      change_id    change_id
      rev          rev_id
      rev_id       rev_id
      revision     rev_id
      revision_id  rev_id
      comment      comment
   ),
   "name,rev" => "rev_id",
) ;

## Notes:
##    - columns are in order of @field_names
##    - Each column is in reverse expected order here.
##    - For name: '-' < '/' < 'a' in ASCII.
my @rev_data = (
[qw( aa/b/c         5 1.20   d  )],
[qw( a-c            4 1.10   c  )],
[qw( a/b/c          3 1.2    b  )],
[qw( a/b/a          2 1.1.1  aa )],
[qw( a/b/a          2 1.1    aa )],
[qw( a              1 1.0    a  )],
[("") x @field_names],
[], ## All fields undefined.
) ;


my @revs = map {
   my @a ;
   for my $i ( 0..$#field_names ) {
      push @a, $field_names[$i], $_->[$i] ;
   }
   VCP::Rev->new( @a ) ;
} @rev_data ;

my $d = VCP::Dest->new ;

sub _get_field {
    my $field_name = shift ;
    my $sub = VCP::Rev->can( $field_name ) ;
    die "Can't call VCP::Rev->$field_name()" unless defined $sub ;
    map defined $_ ? length $_ ? $_ : '""' : "<undef>", map $sub->( $_ ), @_ ;
}

sub _do_split { join ",", VCP::Dest::_split_rev_id shift }

my @tests = (
(
## check that %specs has at least one alias for every field.
map {
   my $field_name = $_ ;
   sub {
      my %aliased_names = map { ( $field_name => 1 ) ; } values %specs ;
      ok $aliased_names{$field_name} || 0, 1, "$_ in \%specs" ;
   },
} @field_names
),
sub { ok _do_split      "10",        "10",     "_split_rev-id" },
sub { ok _do_split   "20.10",     "20,10",     "_split_rev-id" },
sub { ok _do_split   "20a10",   "20,a,10",     "_split_rev-id" },
sub { ok _do_split "20.a.10",   "20,a,10",     "_split_rev-id" },
sub { ok _do_split  "20..10",    "20,,10",     "_split_rev-id" },
(
   map {
      my $sort_spec  = ( $_ ) ;
      my $field_name = $specs{$_} ;
      sub {
	 $d->set_sort_spec( $sort_spec ) ;

	 my @r = @revs ;
	 my $revs = VCP::Revs->new ;
	 $revs->set( @r ) ;
	 $d->sort_revs( $revs ) ;
	 my $exp_order = join",", reverse _get_field $field_name, @revs ;
	 my $got_order = join",",         _get_field $field_name, $revs->get ;
	 ok $got_order, $exp_order, "sort by $sort_spec" ;
      },
   } keys %specs
),

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
