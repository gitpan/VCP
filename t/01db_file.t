#!/usr/local/bin/perl -w

=head1 NAME

01db_filedb.t - testing of VCP::DB_File

=cut

use strict;

use Carp;
use Test;
use File::Path;
use VCP::DB_File;

my $t = -d 't' ? 't/' : '' ;
my $db_loc = "${t}01db_filedb";

rmtree [$db_loc] or die "$! unlinking $db_loc" if -e $db_loc;

my $db;
my $v;

my @tests = (
sub {
   $db = VCP::DB_File->new( StoreLoc => $db_loc, TableName => "foo" );
   ok $db;
},

sub {
   ok ! -e $db->store_loc;
},

sub {
   $db->mkdir_store_loc;
   ok -d $db->store_loc;
},

sub {
   $db->rmdir_store_loc;
   ok ! -e $db->store_loc;
},

sub {
   $v = $db->pack_values( "a", "b" );
   ok $v, "a;b";
},

sub {
   ok join( "|", $db->unpack_values( $v ) ), "a|b";
},

sub {
   $v = $db->pack_values( "" );
   ok $v, "";
},

sub {
   ok join( "|", map "[$_]", $db->unpack_values( $v ) ), "[]";
},

sub {
   $v = $db->pack_values( "", "" );
   ok $v, ";";
},

sub {
   ok join( "|", $db->unpack_values( $v ) ), "|";
},

sub {
   $v = $db->pack_values( "a;b", "b" );
   ok $v, "a%,b;b";
},

sub {
   ok join( "|", $db->unpack_values( $v ) ), "a;b|b";
},

sub {
   $v = $db->pack_values( "a;%", "b" );
   ok $v, "a%,%%;b";
},

sub {
   ok join( "|", $db->unpack_values( $v ) ), "a;%|b";
},

sub {
   $v = $db->pack_values( "a%;", "b" );
   ok $v, "a%%%,;b";
},

sub {
   ok join( "|", $db->unpack_values( $v ) ), "a%;|b";
},

sub {
   $db->close_db;
   rmtree [$db_loc] or warn "$! unlinking $db_loc" if -e $db_loc;
   ok 1;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
