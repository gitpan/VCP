#!/usr/local/bin/perl -w

=head1 NAME

61sort.t - test VCP::Filter::sort

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Rev ;
use VCP::Dest ;
use VCP::Filter::sort ;

my @field_names= qw( name change_id rev_id comment source_rev_id );

## the sort specs for the test.
my @specs = (
   [],
   [ "name", "ascending" ],
   [ "name", "ascending", "rev_id", "ascending" ],
   [ "change_id", "ascending" ],
) ;

## Notes:
##    - columns are in order of @field_names
##    - Each column is in reverse expected order here.
##    - For name: '-' < '/' < 'a' in ASCII.
my @rev_data = (
[qw( aa/b/c         5 1.20   d  6 )],
[qw( a-c            4 1.10   c  5 )],
[qw( a/b/c          3 1.2    b  4 )],
[qw( a/b/a          2 1.1.1  aa 3 )],
[qw( a/b/a          2 1.1    aa 2 )],
[qw( a              1 1.0    a  1 )],
[( "0",            0,"",    "", 0 )],
) ;

my @revs = map {
   my @a ;
   for my $i ( 0..$#field_names ) {
      push @a, $field_names[$i], $_->[$i] ;
   }
   VCP::Rev->new( @a ) ;
} @rev_data ;

my $d = __PACKAGE__->new;
my @out_revs;
sub new { return bless {}, __PACKAGE__ }
sub handle_header { @out_revs = () }
sub handle_rev    { push @out_revs, $_[1] }
sub rev_count     {}
sub handle_footer {}

sub _get_field {
    my $field_name = shift ;
    my $sub = VCP::Rev->can( $field_name ) ;
    die "Can't call VCP::Rev->$field_name()" unless defined $sub ;
    map defined $_ ? length $_ ? $_ : '""' : "<undef>", map $sub->( $_ ), @_ ;
}



my @tests = (
(
   map {
      my $sort_spec  = $_;
      sub {
	 my $f = VCP::Filter::sort->new( "", $sort_spec );
         $f->dest( $d );
         $f->handle_header( {} );
         $f->handle_rev( $_ ) for @revs;
         $f->handle_footer( {} );

	 my $exp_order = join",", reverse _get_field "name", @revs;
	 my $got_order = join",",         _get_field "name", @out_revs;
	 ok $got_order, $exp_order, "sort by " . join ",", @$sort_spec;
      },
   } @specs
),

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
