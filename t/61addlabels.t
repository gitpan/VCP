#!/usr/local/bin/perl -w

=head1 NAME

addlabels.t - test VCP::Filter::addlabels

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

## These next few are for in vitro testing
use VCP::Filter::addlabels;
use VCP::Rev;

my @vcp = vcp_cmd ;

sub r {
   my ( $name, $rev_id, $change_id, $branch_id ) = split ",", $_[0];

   VCP::Rev->new(
      id        => $_[0],
      name      => $name,
      rev_id    => $rev_id,
      change_id => $change_id,
      branch_id => $branch_id,
   );
}

my $sub;

my $r_out;

# HACK so V:F:a calls main::handle_rev()
sub VCP::Filter::addlabels::dest {
    return "main";
}

sub handle_rev {
    my $self = shift;
    my ( $rev ) = @_;
    $r_out = join ",", $rev->labels;
}

sub t {
    return skip "compilation failed", 1 unless $sub;

    my ( $expr, $expected ) = @_;

    $r_out = undef;

    $sub->( "VCP::Filter::addlabels", r $expr );

    @_ = ( $r_out, $expected );
    goto &ok;
}

my @tests = (
## In vitro tests
sub {
   $sub = VCP::Filter::addlabels->_compile_label_add_routine(
      [ map [$_], 'rev_$rev_id', 'change_$change_id', 'branch_$branch_id' ]
   );
   ok defined $sub || $@, 1;
},

sub {
   my $f = VCP::Filter::addlabels->new(
      "Addlabels:",
      [ map [$_], 'rev_$rev_id', 'change_$change_id', 'branch_$branch_id' ],
   );

   ok $f->config_file_section_as_string, qr/rev_\$.*change_\$.*branch_\$/s;
},

sub { t "a,r,c,b",  "rev_r,change_c,branch_b" },
sub { t "a,r,c",    "rev_r,change_c"          },

### In vivo tests
sub {
   eval {
      my $out ;
      my $infile = "t/test-revml-in-0-no-big-files.revml";
      ## $in and $out allow us to avoide execing diff most of the time.
      run [ @vcp, "vcp:-" ], \<<'END_VCP', \$out;
Source: t/test-revml-in-0-no-big-files.revml

Sort:

Destination: -

AddLabels:
END_VCP

      my $in = slurp $infile;
      assert_eq $infile, $in, $out ;
   } ;
   ok $@ || '', '', 'diff' ;
},

sub {
   my $out ;
   my $infile = "t/test-revml-in-0-no-big-files.revml";
   ## $in and $out allow us to avoide execing diff most of the time.
   run [ @vcp, "vcp:-" ], \<<'END_VCP', \$out;
Source: t/test-revml-in-0-no-big-files.revml

Sort:

Destination: -

AddLabels:
    rev_$rev_id
    change_$change_id
    branch_$branch_id
END_VCP
   my $r_count = () = $out =~ m{<label>rev_}g;
   my $c_count = () = $out =~ m{<label>change_}g;
   my $b_count = () = $out =~ m{<label>branch_}g;

   my $in = slurp $infile;

   my $rev_id_count    = () = $in =~ m{<rev_id}g;
   my $change_id_count = () = $in =~ m{<change_id}g;
   my $branch_id_count = () = $in =~ m{<branch_id}g;

   ok "$r_count,$c_count,$b_count",
      "$rev_id_count,$change_id_count,$branch_id_count";
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
