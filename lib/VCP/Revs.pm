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

use strict ;

use Carp ;
use VCP::Debug ":debug" ;
use VCP::Rev ;

use fields (
   'REVS',        ## The revs, sorted or not
) ;


=item new

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my $self ;

   {
      no strict 'refs' ;
      $self = bless [ \%{"$class\::FIELDS"} ], $class ;
   }

   $self->{REVS} = [] ;

   return $self ;
}


=item add

   $revs->add( $rev ) ;
   $revs->add( $rev1, $rev2, ... ) ;

Adds a revision or revisions to the collection.

=cut

sub add {
   my VCP::Revs $self = shift ;

   if ( debugging $self || debugging scalar caller ) {
      debug( "vcp: queuing ", $_->as_string ) for @_ ;
   }

   push @{$self->{REVS}}, @_ ;
}


=item set

   $revs->set( $rev ) ;
   $revs->set( $rev1, $rev2, ... ) ;

Sets the list of revs.

=cut

sub set {
   my VCP::Revs $self = shift ;

   if ( debugging $self || debugging scalar caller ) {
      debug( "vcp: queuing ", $_->as_string ) for @_ ;
   }

   @{$self->{REVS}} = @_ ;
}


=item get

   @revs = $revs->get ;

Gets the list of revs.

=cut

sub get {
   my VCP::Revs $self = shift ;

   return @{$self->{REVS}} ;
}


=item sort

   # Using a custom sort function:
   $revs->sort( sub { my ( $rev_a, $rev_b ) = @_ ; ... } ) ;

Note: Don't use $a and $b in your sort function.  They're package globals
and that's not your package.  See L<VCP::Dest/rev_cmp_sub> for more details.

=cut

sub sort {
   my VCP::Revs $self = shift ;

   my ( $sort_func ) = @_ ;

   @{$self->{REVS}} = sort { $sort_func->( $a, $b ) } @{$self->{REVS}} ;
}


=item shift

   while ( $r = $revs->shift ) {
      ...
   }

Call L</sort> before calling this :-).

=cut

sub shift {
   my VCP::Revs $self = shift ;

   return shift @{$self->{REVS}} ;
}


=item as_array_ref

Returns an ARRAY ref of all revs.

=cut

sub as_array_ref {
   my VCP::Revs $self = shift ;

   return $self->{REVS} ;
}


=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This will be licensed under a suitable license at a future date.  Until
then, you may only use this for evaluation purposes.  Besides which, it's
in an early alpha state, so you shouldn't depend on it anyway.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
