#!/usr/local/bin/perl -w

=head1 NAME

10compile_dtd.t - testing of compile_dtd command

=cut

use strict ;

use Carp ;
use Test ;
use IPC::Run3 ;
use VCP::TestUtils qw( compile_dtd_cmd );

## 2.29's content model as object tree code for compiling DTDs
my $have_expat = eval "require XML::Parser; \$XML::Parser::VERSION >= 2.29";

my @compile_dtd = compile_dtd_cmd ;

# run compile_dtd command line with given parameters
sub compile_dtd {
   my $exp_results = shift ;
   my $out ;
   my $err ;
   my $pid = IPC::Run3::run3 [ @compile_dtd, @_ ], \undef, \$out, \$err ;
   confess "compile_dtd ", join( ' ', @_ ), " returned $?\n$out$err"
      if defined $exp_results && ! grep $? == $_ << 8, @$exp_results ;
   return $err . $out ;
}


my @tests = (
sub { ok compile_dtd( [ 0 ], "revml.dtd", "-" ) },
) ;

plan tests => scalar( @tests ) ;

$have_expat ? $_->() : skip "Need XML::Expat >= 2.29", 1 for @tests ;
