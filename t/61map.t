#!/usr/local/bin/perl -w

=head1 NAME

map.t - test VCP::Filter::map

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

## These next few are for in vitro testing
use VCP::Filter::map;
use VCP::Rev;

my @vcp = vcp_cmd ;

sub r {
   my ( $name, $branch_id ) = $_[0] =~ /\A(?:(.+?))?(?:<(.*)>)?\z/
      or die "Couldn't parse '$_[0]'";

   VCP::Rev->new(
      id        => $_[0],
      name      => $name,
      branch_id => $branch_id,
   )
}

my $sub;

my $r_out;

# HACK
sub VCP::Filter::map::dest {
    return "main";
}

sub handle_rev {
    my $self = shift;
    my ( $rev ) = @_;
    $r_out = join "", $rev->name || "", "<", $rev->branch_id || "", ">";
}

sub t {
    return skip "compilation failed", 1 unless $sub;

    my ( $expr, $expected ) = @_;

    $r_out = undef;

    $sub->( "VCP::Filter::map", r $expr );

    @_ = ( $r_out || "<<deleted>>", $expected || "<<deleted>>" );
    goto &ok;
}

my @tests = (
## In vitro tests
sub {
   $sub = eval { VCP::Filter::map->_compile_rules( [
      [ '<b>',          '<B>'          ],
      [ 'a',            'A'            ],
      [ 'a',            'NONONO'       ],
      [ 'c<d>',         'C<D>'         ],
      [ 'xyz',          '<<keep>>'     ],
      [ 'x*',           '<<delete>>'   ],
      [ 's(*)v<(...)>', 'S$1V${2}Y<>'  ],
      [ 's(*)v<>',      'NONONO'       ],
   ] ) }; 
   ok defined $sub || $@, 1;
},

sub { t "a<b>",     "a<B>"       },
sub { t "a<c>",     "A<c>"       },
sub { t "c<d>",     "C<D>"       },
sub { t "c<e>",     "c<e>"       },
sub { t "e<d>",     "e<d>"       },
sub { t "xab",      undef        },
sub { t "xyz",      "xyz<>"      },
sub { t "Z<Z>",     "Z<Z>"       },
sub { t "stuv<wx>", "StuVwxY<>"  },

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

Map:
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

Map:
    add/f(1)   hey/a$1b
    add/f(2)   hey/a${1}b
    add/f(*)   hey/a${1}b
END_VCP
     my $in = slurp $infile;

     $in =~ s{(<name>)add/f([^<]*)}{$1hey/a$2b}g;
     
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
