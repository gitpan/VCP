#!/usr/local/bin/perl -w

=head1 NAME

01db_filedb_sdbm.t - testing of VCP::DB_File::sdbm

=cut

use strict;

use Carp;
use Test;
use File::Path;
use VCP::DB_File::sdbm;

my $t = -d 't' ? 't/' : '' ;
my $db_loc = "${t}01db_filedb_sdbm";

rmtree [$db_loc] or die "$! unlinking $db_loc" if -e $db_loc;

my $db;

my @tests = (
sub {
   $db = VCP::DB_File::sdbm->new( StoreLoc => $db_loc, TableName => "foo" );
   ok $db;
},

sub {
   ok ! -e $db->store_loc;
},

sub {
   $db->open_db;
   ok scalar glob $db->store_loc . "/*db*";
},

sub {
   $db->set( [ "a" ] => qw( foo bar ) );
   ok join( ",", $db->get( [ "a" ] ) ), "foo,bar";
},

sub {
   $db->close_db;
   ok scalar glob $db->store_loc . "/db*";
},

sub {
   $db->open_db;
   ok scalar glob $db->store_loc . "/db*";
},

sub {
   ok join( ",", $db->get( [ "a" ] ) ), "foo,bar";
},

sub {
   $db->delete_db;
   ok ! -e $db->store_loc;
},

sub {
   $db->open_db;
   ok scalar glob $db->store_loc . "/db*";
},

sub {
   $db->delete_db;
   ok ! -e $db->store_loc;
},

sub {
   rmtree [$db_loc] or warn "$! unlinking $db_loc" if -e $db_loc;
   ok 1;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
