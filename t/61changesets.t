#!/usr/local/bin/perl -w

=head1 NAME

61changesets.t - test VCP::Filter::changesets

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Rev ;
use VCP::Dest ;
use VCP::Utils qw( empty );
use VCP::Filter::changesets;

## the sort specs for the test.
my @specs = (
   [ [],                                  "(a#1)(a#2)(a#3)(a#4)(a#5)(a#6)" ],
   [ [ "name", "equal" ],                 "(a#1)(a#2)(a#3,a#4)(a#5)(a#6)"  ],
   [ [ "comment", "equal" ],              "(a#1)(a#2)(a#3)(a#4)(a#5)(a#6)" ],
) ;


my @field_names= qw( source_name time rev_id comment source_rev_id previous_id );
my @rev_data = (
## NOTE: revs are in reverse order to see if they do get sorted
[qw( a 6 1.20   a   6 )],
[qw( a 5 1.10   a   5 )],
[qw( a 4 1.2    a   4 )],
[qw( a 3 1.1.1  aa  3 ), "a#2" ],
[qw( a 2 1.1    aa  2 )],
[qw( a 1 1.0    a   1 )],
) ;

my @revs = map {
   my @a ;
   for my $i ( 0..$#field_names ) {
      push @a, $field_names[$i], $_->[$i] ;
   }
   VCP::Rev->new( @a ) ;
} @rev_data ;

my $prev_id;
for ( reverse @revs ) {
    if ( empty $_->previous_id ) {
        $_->previous_id( $prev_id );
        $prev_id = $_->id;
    }
}


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
      my ( $conditions, $exp ) = @$_;
      sub {
         $_->change_id( undef ) for @revs;
	 my $f = VCP::Filter::changesets->new( "", $conditions );
         $f->dest( $d );
         $f->handle_header( {} );
         $f->handle_rev( $_ ) for @revs;
         $f->handle_footer( {} );

         my @changes;
         push @{$changes[$_->change_id]}, $_->id for @out_revs;

         my $got = join "", map "(" . join( ",", @$_ ) . ")", grep defined, @changes;

	 ok $got, $exp, "changesets: " . join " ", @$conditions;
      },
   } @specs
),

sub {
   ## Force the revs in to reverse order using change_id, but with one
   ## minor exception just to make sure the sort is really happening.
   my $i = 0;
   $_->change_id( ++$i ) for @revs;
   $revs[2]->change_id(99);
   $revs[0]->change_id($revs[-1]->change_id);

   my $f = VCP::Filter::changesets->new( "" );
   $f->dest( $d );
   $f->handle_header( {} );
   $f->handle_rev( $_ ) for @revs;
   $f->handle_footer( {} );

   my @changes;
   push @{$changes[$_->change_id]}, $_->id for @out_revs;

   my $got = join "", map "(" . join( ",", @$_ ) . ")", grep defined, @changes;

   ok $got, "(a#5)(a#3)(a#2)(a#1,a#6)(a#4)";
},
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
