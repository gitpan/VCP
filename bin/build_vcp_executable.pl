#!/usr/local/bin/perl -w

=head1 NAME

build_vcp_executable.pl

=head1 SYNOPSIS

    cd VCP
    bin\build_vcp_executable.pl

=head1 DESCRIPTION

Builds vcp binaries using PAR's pp command.  Make sure you have all the
VCP prereqs installed because pp silently won't include any not found.

=cut

###############################################################################

sub scan_pm_files_in {
   my ( $prefix ) = @_ ;

   my $dirname = $prefix . '::' ;
   $dirname =~ s{(::)+}{/}g ;

   my %seen ;
   require File::Spec;
   for ( @INC ) {
      my $dir = File::Spec->catdir( $_, $dirname ) ;
      opendir( D, $dir ) or next ;
      my @files = grep $_ !~ /^\.\.?$/ && s/\.pm$//i, readdir D ;
      closedir D ;
      $seen{$_} = 1 for @files ;
   }

   return map "${prefix}::$_", keys %seen;
}


sub scan_pod_files_in {
   my ( $prefix ) = @_ ;

   my $dirname = $prefix . '::' ;
   $dirname =~ s{(::)+}{/}g ;

   my %seen ;
   require File::Spec;
   for ( @INC ) {
      my $dir = File::Spec->catdir( $_, $dirname ) ;
      opendir( D, $dir ) or next ;
      my @files = grep $_ !~ /^\.\.?$/ && s/\.pod$//i, readdir D ;
      closedir D ;
      $seen{$_} = 1 for @files ;
   }

   return map "${prefix}::$_", keys %seen;
}



###############################################################################

use strict;
use lib "lib";
use constant is_win32 => $^O =~ /Win32/i;

use VCP::TestUtils qw( run );

## VCP uses lazy loading extensively...
my %skip_modules = (
    "VCP::TestUtils"            => 1,
    "VCP::PodDESCRIPTIONParser" => 1,
    "VCP::PodOPTIONSParser"     => 1,
);

my @modules = 
    grep !$skip_modules{$_},
    sort( (
        scan_pm_files_in( "RevML"          ),
        scan_pm_files_in( "RevML::Doctype" ),
        scan_pm_files_in( "VCP"            ),
        scan_pm_files_in( "VCP::Source"    ),
        scan_pm_files_in( "VCP::Filter"    ),
        scan_pm_files_in( "VCP::Dest"      ),
        scan_pm_files_in( "VCP::Utils"     ),
        scan_pm_files_in( "VCP::UI"        ),
    ) );

#my @pod_files = map { s{::}{/}g; "$_.pod" } sort( (
#    scan_pod_files_in( "VCP"         ),
#    scan_pod_files_in( "VCP::Source" ),
#    scan_pod_files_in( "VCP::Filter" ),
#    scan_pod_files_in( "VCP::Dest"   ),
#    scan_pod_files_in( "VCP::Utils"  ),
#    scan_pod_files_in( "VCP::UI"     ),
#) );

## PAR <= v0.79 doesn't let vcp scan @INC, so we hardcode in a list of
## modules.
mkdir "tmp" unless -e "tmp";
{
    my @files = sort
#        @pod_files,
        map {
            local $_ = $_;
            s{::}{/}g;
            "$_.pm";
        } @modules;

    open VCP,     "<bin/vcp"     or die "$!: bin/vcp\n";
    open VCP_OUT, ">tmp/vcp_par" or die "$!: tmp/vcp_par\n";
    while (<VCP>) {
        if ( s{^(\s*)#.*INSERT.*BUNDLE.*HERE.*\r?\n}{} ) {
            my $indent = $1;
            print VCP_OUT map "$indent'$_',\n", @files;
        }
        print VCP_OUT $_ or die "$!: bin/vcp_par\n";
    }
    close VCP;
    close VCP_OUT;
}

my $exe_name = is_win32 ? "vcp.exe" : "vcp-bin";

if ( 1 ) {
    if ( -e $exe_name ) {
        unlink $exe_name or die $!;
    }

    my @cmd = (
        "pp",
        "-o", $exe_name,
#        "-p", "-B",  "-o", "vcp.pl",
        "-lib=lib",
        sort(
            map "--add=$_", @modules#, map "lib/$_", @pod_files
        ),
        "tmp/vcp_par"
    );

    warn join( " ", @cmd ), "\n";

    system @cmd and die $!;
}

warn "Testing generated executable\n";

delete $ENV{$_} for grep /p4|perl/i, keys %ENV;

my $ok = 1;

{
    my $zip_list = "<NO WZUNZIP.EXE OUTPUT>\n";
    eval {
        run [ is_win32 ? ( "wzunzip", "-v" ) : ( "unzip", "-l" ), $exe_name ],
            \undef, \$zip_list;
        warn "DB_File.pm not in $exe_name, patch the pp perl script\n"
            unless $zip_list =~ /DB_File\.pm/;
        1;
    } or do {
        $ok = 0;
        warn $@, $zip_list;
    }
}

unless ( -e "tmp" ) {
    mkdir "tmp" or die "$!: tmp/";
}

use File::Spec;
my $abs_exe_name = File::Spec->rel2abs( $exe_name );

chdir "tmp" or die "$!: tmp/";

{
    my $vcp_output = "<NO VCP.EXE OUTPUT>\n";
    eval {
        run [ $abs_exe_name, "help" ], \undef, \$vcp_output;
        1;
    } or do {
        $ok = 0;
        warn $@, $vcp_output;
    }
}

die "$exe_name fails test(s).\n" unless $ok;

print "$exe_name seems ok, please test in a real application.\n";
