#!/usr/local/bin/perl -w

=head1 NAME

09config_file_utils.t - testing of VCP::ConfigFileUtils services

=cut

use strict ;

use Test ;
use File::Temp qw( tmpnam );
use VCP::ConfigFileUtils qw(
   config_file_quote
   parse_config_file
   write_config_file
);

my $fn;
my @cleanup;

END {
   for ( @cleanup ) {
       unlink $_ or warn "$!: $_";
    }
}

my @tests = (
sub { ok config_file_quote( qq{a}  ), qq{a} },
sub { ok config_file_quote( qq{ }  ), qq{" "} },
sub { ok config_file_quote( qq{\$} ), qq{\$} },
sub { ok config_file_quote( qq{\n} ), qq{"\n"} },

sub {
   $fn = tmpnam;
   push @cleanup, $fn;
   write_config_file $fn;
   ok -f $fn;
},

sub {  ## see if we can overwrite it.
   write_config_file $fn;
   ok -f $fn;
},

sub {
   my $sections = parse_config_file( $fn );
   ok ! @$sections;  ## It's empty!
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
