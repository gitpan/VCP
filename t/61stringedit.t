#!/usr/local/bin/perl -w

=head1 NAME

61stringedit.t - test VCP::Filter::stringedit

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

## These next few are for in vitro testing
use VCP::Filter::stringedit;
use VCP::Rev;

my @vcp = vcp_cmd ;

sub r {
   VCP::Rev->new(
      name      => "abcABC",
      labels    => [qw( aAa bBb cCc )],
   )
}

my $sub;

my $r_out;

# HACK
sub VCP::Filter::stringedit::dest {
    return "main";
}

sub handle_rev {
    my $self = shift;
    my ( $rev ) = @_;
    $r_out = join ",", $rev->name, sort { lc $a cmp lc $b } $rev->labels;
}

sub t {
    return skip "compilation failed", 1 unless $sub;

    my ( $expected ) = @_;

    $r_out = undef;

    $sub->( "VCP::Filter::stringedit", r );

    @_ = ( $r_out || "<<empty>>", $expected || "<<empty>>" );
    goto &ok;
}

my @tests = (
## In vitro tests
sub {
   $sub = eval { VCP::Filter::stringedit->_compile_rules( [
   ] ) }; 
   ok defined $sub || $@, 1;
},

sub { t "abcABC,aAa,bBb,cCc" },

sub {
   $sub = eval { VCP::Filter::stringedit->_compile_rules( [
      [ 'name',         '/(A)/', 'a' ],
      [ 'labels',       '/(A)/', 'a' ],
      [ 'name,labels',  '/(B)/', 'b' ],
   ] ) }; 
   ok defined $sub || $@, 1;
},

sub { t "abcabC,aaa,bbb,cCc" },

sub {
   $sub = eval { VCP::Filter::stringedit->_compile_rules( [
      [ 'name',         '/(A)/',          '\%%03d' ],
      [ 'name',         '/(B)/',          '\%%03o' ],
      [ 'name',         '/(C)/',          '\%%02x' ],
   ] ) }; 
   ok defined $sub || $@, 1;
},

sub { t "abc%065%102%43,aAa,bBb,cCc" },

sub {
   $sub = eval { VCP::Filter::stringedit->_compile_rules( [
      [ 'name',         '/(A)/',          '\\n' ],
      [ 'name',         '/(B)/',          '\\t' ],
      [ 'name',         '/(C)/',          '\\a' ],
   ] ) }; 
   ok defined $sub || $@, 1;
},

sub { t "abc\n\t\a,aAa,bBb,cCc" },

sub {
   $sub = eval { VCP::Filter::stringedit->_compile_rules( [
      [ 'name',         '/(a).*(A)/',      '\U%c\E\%%x' ],
   ] ) }; 
   ok defined $sub || $@, 1;
},

sub { t "A%41BC,aAa,bBb,cCc" },

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

StringEdit:
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

StringEdit:
    labels    "achoo"   ACHOO
END_VCP
     my $in = slurp $infile;

     $in =~ s{achoo(\w+)}{ACHOO$1}g;
     
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
