use Test;
use VCP::Utils qw(
   empty
   escape_filename
   is_win32
   program_name
   start_dir_rel2abs
   shell_quote
   start_dir
);

use strict;

my @tests = (
sub { ok empty undef },
sub { ok empty "" },
sub { ok !empty 0 },
sub { ok !empty " " },
sub { ok !empty "a" },

sub { ok length start_dir },
sub { ok 0 == index start_dir_rel2abs( "a" ), start_dir },
sub { ok shell_quote " ", is_win32 ? q{" "} : q{' '} },
sub { ok escape_filename( chr 1 ), "%1%" },
sub { ok escape_filename( chr 255 ), "%255%" },

sub { ok 0 <= index $0, program_name },
);

plan tests => 0+@tests;

$_->() for @tests;
