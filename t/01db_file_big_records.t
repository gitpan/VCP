#!/usr/local/bin/perl -w

=head1 NAME

01db_filedb_big_records.t - testing of VCP::DB_File::big_records

=cut

use strict;

use Carp;
use Test;
use File::Path;
use VCP::DB_File::big_records;

my $t = -d 't' ? 't/' : '' ;
my $db_loc = "${t}01db_file_big_records";

rmtree [$db_loc] or die "$! unlinking $db_loc" if -e $db_loc;

my $db;

my @tests = (
sub {
   $db = VCP::DB_File::big_records->new(
       StoreLoc => $db_loc,
       TableName => "foo"
   );
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
   $db->set( [ "b" ] => ( "foo\n;bar\n;", "biz\000baz\n;bot" ) );
   ok join( ",", $db->get( [ "b" ] ) ), "foo\n;bar\n;,biz\000baz\n;bot";
},

sub {
   $db->set( [ "c" ] => ( "x" x 2000 ) );
   ok join( ",", $db->get( [ "c" ] ) ), "x" x 2000;
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
   ok join( ",", $db->get( [ "b" ] ) ), "foo\n;bar\n;,biz\000baz\n;bot";
},

sub {
   ok join( ",", $db->get( [ "c" ] ) ), "x" x 2000;
},

sub {
   my @out;
   $db->foreach_record_do( sub { push @out, @_ } );
   @out
      ? ok(
         join( "|", @out ),
         join( "|", map $db->get( [ $_ ] ), qw( a b c ) )
      )
      : ok( "", "some data, at least" )
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
   rmtree [$db_loc] or warn "$! unlinking $db_loc"
      if -e $db_loc && ! $ENV{VCPNODELETE};
   ok 1;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
