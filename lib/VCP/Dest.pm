package VCP::Dest ;

=head1 NAME

VCP::Dest - A base class for VCP destinations

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 EXTERNAL METHODS

=over

=cut

use strict ;

use Carp ;
use UNIVERSAL qw( isa ) ;

use vars qw( $VERSION $debug ) ;

$VERSION = 0.1 ;

$debug = 0 ;

use base 'VCP::Plugin' ;

use fields (
   'HEADER',   ## Holds header info until first rev is seen.
) ;

use VCP::Revs ;


=item new

Creates an instance, see subclasses for options.  The options passed are
usually native command-line options for the underlying repository's
client.  These are usually parsed and, perhaps, checked for validity
by calling the underlying command line.

=cut

#sub new {
#   my $class = shift ;
#   $class = ref $class || $class ;
#
#   my VCP::Dest $self = $class->SUPER::new( @_ ) ;
#
#   return $self ;
#}


###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=head2 SUBCLASS API

These methods are intended to support subclasses.

=over

=item header

Gets/sets the $header passed to handle_header().

Generally not overridden: all error checking is done in new(), and
no output should be generated until output() is called.

=cut

sub header {
   my VCP::Dest $self = shift ;
   $self->{HEADER} = shift if @_ ;
   return $self->{HEADER} ;
}

=back

=head2 SUBCLASS OVERLOADS

These methods are overloaded by subclasses.

=over

=item backfill

   $dest->backfill( $rev ) ;

Checks the file indicated by VCP::Rev $rev out of the target repository if
this destination supports backfilling.  Currently, only the revml destination
does not support backfilling.

The $rev->{workpath} must be set to the filename the backfill was put
in.

This is used when doing an incremental update, where the first revision of
a file in the update is encoded as a delta from the prior version.  A digest
of the prior version is sent along before the first version delta to
verify it's presence in the database.

So, the source calls backfill(), which returns TRUE on success, FALSE if the
destination doesn't support backfilling, and dies if there's an error in
procuring the right revision.

If FALSE is returned, then the revisions will be sent through with no
working path, but will have a delta record.

MUST BE OVERRIDDEN.

=cut

sub backfill {
   my VCP::Dest $self = shift ;
   die ref( $self ) . "::backfill() not found, Oops.\n" ;
}


=item handle_footer

   $dest->handle_footer( $footer ) ;

Does any cleanup necessary.  Not required.  Don't call this from the override.

=cut

sub handle_footer {
   my VCP::Dest $self = shift ;
   return ;
}

=item handle_header

   $dest->handle_header( $header ) ;

Stows $header in $self->header.  This should only rarely be overridden,
since the first call to handle_rev() should output any header info.

=cut

sub handle_header {
   my VCP::Dest $self = shift ;

   my ( $header ) = @_ ;

   $self->header( $header ) ;

   return ;
}

=item rev_cmp_sub

Returns a subroutine reference to a sorting function.  See L</sort>.

Returns -1, 0, or 1 depending on the relative order between $rev_a and $rev_b.
This may be overridded.

Default ordering is by

  - change_id    (compared numerically using <=>, for now)
  - time         (commit time: simple numeric, since this is a simple number)
  - comment      (alphabetically, case sensitive)
  - name         (path-component-wise alphabetically case sensitive)

This ordering benefits change number oriented systems while preserving
commit order for non-change number oriented systems.

If change_id is undefined in either rev, it is not used.

If time is undefined in a rev, the value "-1" is used.  This causes
base revisions (ie digest-only) to precede real revisions.

That's not always good, though: one of commit time or change number should
be defined!  

Change ids are compared numerically, times by date order
(ie by alphabetic, since ISO8601 dates are used internally).  Comment
is compared alphabetically, and name is compared piecewise alphabetically
after splitting both names on '/' ('//', '///', etc, are treated like '/').

This will confess a problem if none of the above are defined, since I
can't think of any other rational sorting basis in the general case.

=cut

sub rev_cmp_sub {
   return sub {
      my VCP::Rev $rev_a ;
      my VCP::Rev $rev_b ;
      ( $rev_a, $rev_b ) = @_ ;

      my $result =
         (    defined $rev_a->{CHANGE_ID} && defined $rev_b->{CHANGE_ID} 
              &&      $rev_a->{CHANGE_ID} <=>        $rev_b->{CHANGE_ID}
	 )
         || ( ( $rev_a->{TIME} || -1 ) <=> ( $rev_b->{TIME} || -1 ) )
	 || ( defined $rev_a->{COMMENT}   && defined $rev_b->{COMMENT}
            &&        $rev_a->{COMMENT}   cmp       $rev_b->{COMMENT}
	 ) ;

      return $result if $result ;

      my @a_name = split qr{/+}, $rev_a->{NAME} ;
      my @b_name = split qr{/+}, $rev_b->{NAME} ;

      while ( @a_name && @b_name ) {
         $result = shift( @a_name ) cmp shift( @b_name ) ;
	 return $result if $result ;
      }

      return @a_name <=> @b_name ;
   } ;
}


=item sort_revs

   $source->dest->sort_revs( $source->revs ) ;

This sorts the revisions that the source has identified in to whatever order
is needed by the destination.  The default ordering is set by L</rev_cmp_sub>.

=cut

sub sort_revs {
   my VCP::Dest $self = shift ;

   my VCP::Revs $revs ;
   ( $revs ) = @_ ;

   $revs->sort( $self->rev_cmp_sub ) ;
}


=item handle_rev

   $dest->handle_rev( $rev ) ;

Outputs the item referred to by VCP::Rev $rev.  If this is the first call,
then $self->none_seen will be TRUE and any preamble should be emitted.

MUST BE OVERRIDDEN.  Don't call this from the override.

=cut

sub handle_rev {
   my VCP::Dest $self = shift ;
   die ref( $self ) . "::handle_rev() not found, Oops.\n" ;
}



=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This will be licensed under a suitable license at a future date.  Until
then, you may only use this for evaluation purposes.  Besides which, it's
in an early alpha state, so you shouldn't depend on it anyway.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
