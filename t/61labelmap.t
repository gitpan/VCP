#!/usr/local/bin/perl -w

=head1 NAME

61labelmap.t - test VCP::Filter::labelmap

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

## These next few are for in vitro testing
use VCP::Filter::labelmap;
use VCP::Rev;

my @vcp = vcp_cmd ;

sub r {
   VCP::Rev->new(
      labels    => [qw( aaa bbb ccc ddd eee )],
   )
}

my $sub;

my $r_out;

# HACK
sub VCP::Filter::labelmap::dest {
    return "main";
}

sub handle_rev {
    my $self = shift;
    my ( $rev ) = @_;
    $r_out = join ",", sort { lc $a cmp lc $b } $rev->labels;
}

sub t {
    return skip "compilation failed", 1 unless $sub;

    my ( $expected ) = @_;

    $r_out = undef;

    $sub->( "VCP::Filter::labelmap", r );

    @_ = ( $r_out || "<<deleted>>", $expected || "<<deleted>>" );
    goto &ok;
}

my @tests = (
## In vitro tests
sub {
   $sub = eval { VCP::Filter::labelmap->_compile_rules( [
      [ 'aaa',          'AAA'          ],
      [ 'a',            'NONONO'       ],
      [ 'bbb',          '<<keep>>'     ],
      [ 'ddd',          '<<delete>>'   ],
      [ 'e(...)e',      'E$1E'         ],
   ] ) }; 
   ok defined $sub || $@, 1;
},

sub { t "AAA,bbb,ccc,EeE" },

## In vivo tests
sub {
  eval {
     my $out ;
     my $infile = "t/test-revml-in-0-no-big-files.revml";
     ## $in and $out allow us to avoide execing diff most of the time.
     run [ @vcp, "vcp:-" ], \<<'END_VCP', \$out;
Source: t/test-revml-in-0-no-big-files.revml

Sort:

Destination: -

LabelMap:
END_VCP

     my $in = slurp $infile;
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},

sub {
  eval {
     my $out ;
     my $infile = "t/test-revml-in-0-no-big-files.revml";
     ## $in and $out allow us to avoid execing diff most of the time.
     run [ @vcp, "vcp:-" ], \<<'END_VCP', \$out;
Source: t/test-revml-in-0-no-big-files.revml

Sort:

Destination: -

LabelMap:
    achoo(...)   ACHOO$1
    blessyou...  <<delete>>
END_VCP
     my $in = slurp $infile;

     $in =~ s{achoo(\w+)}{ACHOO$1}g;
     $in =~ s{^.*blessyou.*\r?\n}{}gm;
     
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
