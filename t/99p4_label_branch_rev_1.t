#!/usr/local/bin/perl -w

=head1 NAME

t/99p4_label_branch_rev_1.t

=cut

use strict ;

use Carp ;
use File::Basename;
use Test ;
use VCP::Dest::p4;
use VCP::Source::null;
use VCP::TestUtils;

my $progname = basename $0;

my $t = -d 't' ? 't/' : '' ;

my $p4root = tmpdir "p4root";

my $p4spec = "p4:$progname\@$p4root:";

my $p4d_pid;

my $dest = VCP::Dest::p4->new(
   "p4:$progname\@$p4root://depot/...",
   [qw( --init-p4d --delete-p4d-dir )]
);

my $source = VCP::Source::null->new;

my $change_id = 1;

sub p4_r {
   my ( $action, $name, $rev_id, $previous_id, $labels ) = @_;
   my $r = VCP::Rev->new(
      action               => $action,
      name                 => $name,
      source_name          => $name,
      rev_id               => $rev_id,
      source_rev_id        => $rev_id,
      type                 => "text",
      source_repo_id       => $progname,
      source               => $source,
      source_filebranch_id => "/depot/$name",
      branch_id            => "/depot",
      previous_id          => $previous_id,
      change_id            => $change_id,
   );

   $r->set_labels( @$labels ) if $labels;
   $r->set_source( $source );
   return $r;
}

my @tests = (
##
## Set up the test depot
##
sub {
   $dest->init;
   $dest->handle_header( {
      rep_type => "test",
      rev_root => "//depot",
   } );

   $dest->handle_rev( p4_r qw( edit   foo 1 ) );
   ++$change_id;
   $dest->handle_rev(
      p4_r qw( branch bar 1 ), "foo#1", [ qw( uh_oh_label ) ]
   );

   $dest->handle_footer();

   ok 1;
},

) ;

plan tests => scalar @tests ;

my $p4d_borken = p4d_borken ;

my $why_skip ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "$p4d_borken\n"           if $p4d_borken ;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
