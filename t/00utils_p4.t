#!/usr/local/bin/perl -w

=head1 NAME

00utils_p4.t - testing of VCP::Utils::p4

=cut

use strict ;

use Carp ;
use Test ;
use File::Temp qw( tmpnam );
use VCP::Utils::p4 qw( p4_get_settings );
use constant is_win32 => $^O =~ /Win32/;

my @tests = (

sub { ok VCP::Utils::p4::underscorify_name( "a"  ), "a"   },
sub { ok VCP::Utils::p4::underscorify_name( "ab" ), "ab"  },
sub { ok VCP::Utils::p4::underscorify_name( "a1" ), "a1"  },
sub { ok VCP::Utils::p4::underscorify_name( "a(" ), "a("  },
sub { ok VCP::Utils::p4::underscorify_name( "a/" ), "a/"  },

sub { ok VCP::Utils::p4::underscorify_name( "a b"), "a_20_b"   },
sub { ok VCP::Utils::p4::underscorify_name( "a#b"), "a_23_b"   },
sub { ok VCP::Utils::p4::underscorify_name( "a\@b"), "a_40_b"   },
sub { ok VCP::Utils::p4::underscorify_name( " a" ), "_20_a" },

sub {
   $ENV{P4EDITOR} = 'vituperated_eczema';
   my $h = p4_get_settings;
   ok $h->{P4EDITOR}, 'vituperated_eczema';
},

sub {
   return skip 1, "P4USER registry overrided P4CONFIG setting on Win32"
      if is_win32;
   my $tmpfile = tmpnam();
   `echo 'P4USER=pigdog' > $tmpfile`;
   die "temporary file '$tmpfile' not written"
      unless -f $tmpfile;
   $ENV{P4CONFIG} = $tmpfile;
   my $h = p4_get_settings;
   ok $h->{P4USER}, "pigdog";
   unlink $tmpfile or warn "Couldn't delete temporary file '$tmpfile'"
      if -e $tmpfile;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
