#!/usr/local/bin/perl -w

=head1 NAME

02revmapdb.t - testing of VCP::HeadRevsDB

=cut

use strict;

use Carp;
use Test;
use File::Path;
use VCP::HeadRevsDB;

my $t = -d 't' ? 't/' : '' ;
my $db_loc = "${t}01db_filedb_sdbm";

rmtree [$db_loc] or die "$! unlinking $db_loc" if -e $db_loc;

my $db;

my @tests = (
sub {
   $db = VCP::HeadRevsDB->new( StoreLoc => $db_loc );
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
   $db->set( ["a", "b"] => qw( foo bar ) );
   ok join( ",", $db->get( ["a", "b"] ) ), "foo,bar";
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
   ok join( ",", $db->get( ["a", "b"] ) ), "foo,bar";
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
