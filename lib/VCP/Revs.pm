package VCP::Revs ;

=head1 NAME

VCP::Revs - A collection of VCP::Rev objects.

=head1 SYNOPSIS

=head1 DESCRIPTION

Right now, all revs are kept in memory, but we will enable storing them to
disk and recovering them at some point so that we don't gobble huge
tracts of RAM.

=head1 METHODS

=over

=cut

$VERSION = 1 ;

use strict ;

use VCP::Logger qw( BUG );
use VCP::Debug ":debug" ;
use VCP::DB_File::big_records;
use VCP::Rev ;
use VCP::Utils qw( empty );

=item new

=cut

sub new {
   my $class = shift;
   my $self = bless { @_ }, $class;

   BUG "STORE_LOC not set" if empty $self->{STORE_LOC};

   return $self ;
}


sub revs_db {
   my $self = shift;

   my $plugin_name = $self->{PLUGIN_NAME};
   $plugin_name = "" unless defined $plugin_name;
   $plugin_name =~ s/::/-/g;
   return $self->{REVS_DB} ||= do {
      my $db = VCP::DB_File::big_records->new(
         StoreLoc  => $self->{STORE_LOC},
         TableName => "$plugin_name-revs",
      );
      $db->delete_db;
      $db->open_db;
      $db;
   };
}


sub DESTROY {
   my $self = shift;
   if ( $self->{REVS_DB} ) {
      $self->{REVS_DB}->close_db;
      $self->{REVS_DB}->delete_db;
   }
}


=item add

   $revs->add( $rev ) ;
   $revs->add( $rev1, $rev2, ... ) ;

Adds a revision or revisions to the collection.

The ( name, rev_id, branch_id ) tuple must be unique, if a second rev
is C<add()>ed with the same values, an exception is thrown.

=cut

sub added_rev {
   my $self = CORE::shift ;
   my ( $id ) = @_;
   return $self->revs_db->exists( [ $id ] );
}


sub add {
   my $self = CORE::shift ;

   Carp::confess "undef passed" if grep ! defined, @_;

   if ( debugging ) {
      debug "queuing ", $_->as_string for @_ ;
   }

   for my $r ( @_ ) {
      my $id = $r->id;

      BUG "can't add same revision twice: '" . $r->as_string
         if $self->added_rev( $id );

      $self->revs_db->set( [ $id ], $r->serialize );
   }
}


=item exists 

   if ( $revs->exists( $id ) ) { ... }

=cut

sub exists {
   my $self = CORE::shift ;
   return $self->revs_db->exists( [ @_ ] );
}


=item get

   $rev = $revs->get( $id ) ;  ## return the rev with a given ID (or die())

=cut

sub get {
   my $self = CORE::shift ;

   BUG "can't retrieve all revs at once any more" unless @_;

   my @fields = $self->revs_db->get( [ @_ ] );

   return undef unless @fields;

   return VCP::Rev->deserialize( @fields );
}


=item foreach

   $revs->foreach( sub { ... } );

Apply a subroutine to each revision.

=cut

sub foreach {
   my $self = shift;

   my ( $sub ) = @_;

   $self->revs_db->foreach_record_do(
      sub {
         my $r = VCP::Rev->deserialize( @_ );
         $sub->( $r );
      }
   );
}


=back

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
