#!/usr/local/bin/perl -w

=head1 NAME

00refcountedfile.t - testing of VCP::RefCountedFile services

=cut

use strict ;

use Carp;
use Test;
use VCP::RefCountedFile;

my $tmpdir = File::Spec->tmpdir;

my $f1 = File::Spec->catfile( $tmpdir, "f1" );
my $f10 = File::Spec->catfile( $tmpdir, "f10" );

my $why_skip;

if ( -e $f1 ) {
    unlink $f1 or $why_skip .= "$!: $f1";
}

if ( -e $f10 ) {
    unlink $f10 or $why_skip .= "$!: $f10";
}

sub touch($) {
    open F, "> $_[0]" or die "$!: $f1";
    close F;
}

my $r_a;

my @tests = (
sub {
    {
        my $r = VCP::RefCountedFile->new;
    }
    ok 1;
},

sub {
    my $r = VCP::RefCountedFile->new( $f1 );
    ok $r, $f1;
},

sub {
    my $r = VCP::RefCountedFile->new( $f1 );
    ok $r ne $f10;
},

sub {
    {
        my $r = VCP::RefCountedFile->new( $f1 );
    }
    ok 1;
},

sub {
    touch $f1;
    ok -e $f1;
},

sub {
    {
        my $r = VCP::RefCountedFile->new( $f1 );
    }
    ok !-e $f1;
},

## explicit undefing
sub {
    touch $f1;
    $r_a = VCP::RefCountedFile->new( $f1 );
    ok -e $f1;
},

sub {
    ok -e $f1;
},

sub {
    $r_a = undef;
    ok ! -e $f1;
},

## copying refs.
sub {
    touch $f1;
    my $r = VCP::RefCountedFile->new( $f1 );
    $r_a = $r;
    ok -e $f1;
},

sub {
    ok -e $f1;
},

sub {
    $r_a = undef;
    ok ! -e $f1;
},

## copying refs.
sub {
    touch $f1;
    my $r = VCP::RefCountedFile->new( $f1 );
    $r_a = $r;
    ok -e $f1;
},

sub {
    ok -e $f1;
},

sub {
    touch $f10;
    ok -e $f10;
},

sub {
    $r_a = $f10;  ## $r_a is now a normal string.
    ok ! -e $f1;
},

sub {
    ok -e $f10;
},

sub {
    $r_a = undef;
    ok -e $f10;
},

## mutations, mutations.

sub {
    touch $f1;
    touch $f10;
    $r_a = VCP::RefCountedFile->new( $f1 );
    ok -e $f1;
},

sub {
    $r_a .= "0";  ## $r_a is now a plain string.  We can fix that if need be.
    ok ! -e $f1;
},

sub {
    ok -e $f10;
},

sub {
    $r_a = undef;
    ok -e $f10;
},

);

plan tests => scalar( @tests ) ;

$why_skip ? skip 1, $why_skip : $_->() for @tests ;

if ( -e $f1 ) {
    unlink $f1 or $why_skip .= "$!: $f1";
}

if ( -e $f10 ) {
    unlink $f10 or $why_skip .= "$!: $f10";
}

