#!/usr/local/bin/perl -w

=head1 NAME

test_vcp_executable.pl

=head1 SYNOPSIS

    cd VCP
    bin/test_vcp_executable.pl
    bin/test_vcp_executable.pl t/foo.t t/bar.t ...

=head1 DESCRIPTION

Tests the VCP executable vcp.exe using t\*.t test scripts or, if provided,
the test scripts listed on the command line.

Creates a tmp/vcp_executable_test directory, removes all PERL and P4
environment variables and cds to the tmp directory to run the tests
found in t/*.t.

=cut


use strict;
use lib "lib";

use File::Basename qw( dirname );
use File::Copy qw( cp );
use File::Path qw( rmtree mkpath );
use File::Spec::Functions qw( catdir rel2abs );
use Test::Harness;
use VCP::Utils qw( is_win32 shell_quote );
use VCP::TestUtils qw( run );

my $lib_dir = rel2abs "lib";

## @ARGV processing
#my $exe_name = @ARGV ? shift : "vcp.exe";
#my @options = splice @ARGV;
my $exe_name = is_win32 ? "vcp.exe" : "vcp-bin";
my @options;
$exe_name = rel2abs $exe_name;

## Build and identify Prerequisites
run [ is_win32 ? "nmake" : "make", "pure_all" ];

my %skip_files = map { ( $_ => 1 ) } (
    ## Files to skip, such as tests that don't work.
    ## All tests < 10 are automatically skipped.
    't/10compile_dtd.t',
);
my @prereqs = grep !$skip_files{$_}, (
    glob( "t/[123456789]*.t" ),
    glob( "t/*,v" ),
    glob( "t/*.revml" )
    
);
my @failed_wildcards = grep /\*/, @prereqs;
die "Couldn't find prerequisites for ", join ", ", map "'$_'", @failed_wildcards
    if @failed_wildcards;

## Create and populate working directory
my $work_dir = "tmp/vcp_executable_test";
rmtree [ $work_dir ] if -e $work_dir;
mkpath [ $work_dir ];

for my $fn ( @prereqs ) {
    my $dest = rel2abs $fn, $work_dir;
    my $dest_d = dirname $dest;
    mkpath [ $dest_d] unless -d $dest_d;
    cp $fn, $dest or die "can't copy '$fn' to '$dest' ($!)\n";
}

## Run all test scripts
chdir $work_dir or die "$!: $work_dir";

delete $ENV{$_} for grep /p4|perl/i, keys %ENV;
$ENV{VCPTESTCOMMAND} = shell_quote $exe_name, @options;

$Test::Harness::switches .= " -I$lib_dir";
runtests sort @ARGV ? @ARGV : grep /\.t\z/, @prereqs;
