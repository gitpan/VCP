package VCP::Dest ;

=head1 NAME

VCP::Dest - A base class for VCP destinations

=head1 SYNOPSIS

=head1 DESCRIPTION

=for test_scripts t/01sort.t

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Driver );

use strict ;

use Carp ;
use File::Spec ;
use File::Spec::Unix ;
use UNIVERSAL qw( isa ) ;
use VCP::Revs ;
use VCP::Debug qw(:debug) ;
use VCP::Driver;
use VCP::Logger qw( pr pr_doing pr_done );
use VCP::Utils qw( start_dir empty );

#use base 'VCP::Driver' ;

#use fields (
#   'DEST_HEADER',          ## Holds header info until first rev is seen.
#   'DEST_HEAD_REVS',       ## Map of head revision on each branch of each file
#   'DEST_REV_MAP',         ## Map of source rev id to destination file & rev
#   'DEST_MAIN_BRANCH_ID',  ## Container of main branch_id for each file
#   'DEST_FILES',           ## Map of files->state, for CVS' sake
#   'DEST_HAVE_REVS_TO_EMIT', ## Whether or not there will be/are/were
#                             ## revs emitted, used for UI output only.
#);

use VCP::Revs ;


###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=head2 SUBCLASS API

These methods are intended to support subclasses.

=over


=item digest

    $self->digest( "/tmp/readers" ) ;

Returns the Base64 MD5 digest of the named file.  Used to compare a base
rev (which is the revision *before* the first one we want to transfer) of
a file from the source repo to the existing head rev of a dest repo.

The Base64 version is returned because that's what RevML uses and we might
want to cross-check with a .revml file when debugging.

=cut

sub digest {
   shift ;  ## selfless little bugger, isn't it?
   my ( $path ) = @_ ;

   require Digest::MD5 ;
   my $d= Digest::MD5->new ;
   open DEST_P4_F, "<$path" or die "$!: $path" ;
   $d->addfile( \*DEST_P4_F ) ;

   my $digest = $d->b64digest ;
   close DEST_P4_F ;
   return $digest ;
}


=item compare_base_revs

   $self->compare_base_revs( $rev, $work_path ) ;

Checks out the indicated revision from the destination repository and
compares it (using digest()) to the file from the source repository
(as indicated by $work_path). Dies with an error message if the
base revisions do not match.

Calls $self->checkout_file( $rev ), which the subclass must implement.

=cut

sub compare_base_revs {
   my $self = shift ;
   my ( $rev, $source_path ) = @_ ;

   die "\$source_path not set at ", caller
      unless defined $source_path;

   ## This block should only be run when transferring an incremental rev.
   ## from a "real" repo.  If it's from a .revml file, the backfill will
   ## already be done for us.
   ## Grab it and see if it's the same...
   my $backfilled_path = $self->checkout_file( $rev );

   my $source_digest = $self->digest( $source_path ) ;
   my $dest_digest     = $self->digest( $backfilled_path );

   die( "vcp: base revision\n",
       $rev->as_string, "\n",
       "differs from the last version in the destination p4 repository.\n",
       "    source digest: $source_digest (in ", $source_path, ")\n",
       "    dest. digest:  $dest_digest (in ", $backfilled_path, ")\n"
   ) unless $source_digest eq $dest_digest ;
}


=item header

Gets/sets the $header data structure passed to handle_header().

=cut

sub header {
   my $self = shift ;
   $self->{DEST_HEADER} = shift if @_ ;
   return $self->{DEST_HEADER} ;
}



=item rev_map

Returns a reference to the RevMapDB for this backend and repository.
Creates an empty one if need be.

=cut

sub rev_map {
   my $self = shift ;
   
   return $self->{DEST_REV_MAP} ||= do {
      require VCP::RevMapDB;
      VCP::RevMapDB->new( 
         StoreLoc => $self->_db_store_location,
      );
   };
}

=item head_revs

Returns a reference to the HeadRevsDB for this backend and repository.
Creates an empty one if need be.

=cut

sub head_revs {
   my $self = shift ;
   
   return $self->{DEST_HEAD_REVS} ||= do {
      require VCP::HeadRevsDB;

      $self->{DEST_HEAD_REVS} = VCP::HeadRevsDB->new( 
         StoreLoc => $self->_db_store_location,
      );
   };
}

=item main_branch_id

Returns a reference to the MainBranchIdDB for this backend and repository.
Creates an empty one if need be.

=cut

sub main_branch_id {
   my $self = shift;
   
   return $self->{DEST_MAIN_BRANCH_ID} ||= do {
      require VCP::MainBranchIdDB;
      $self->{DEST_MAIN_BRANCH_ID} = VCP::MainBranchIdDB->new(
         StoreLoc => $self->_db_store_location,
      );
   };
}

=item files

Returns a reference to the FilesDB for this backend and repository.
Creates an empty one if need be.

=cut

sub files {
   my $self = shift ;
   
   return $self->{DEST_FILES} ||= do {
      require VCP::FilesDB;
      $self->{DEST_FILES} = VCP::FilesDB->new(
         StoreLoc => $self->_db_store_location,
      );
   }
}

=back

=head2 SUBCLASS OVERLOADS

These methods are overloaded by subclasses.

=over

=item backfill

   $dest->backfill( $rev ) ;

Checks the file indicated by VCP::Rev $rev out of the target repository
if this destination supports backfilling.  Currently, only the revml and
the reporting & debugging destinations do not support backfilling.

The $rev->workpath must be set to the filename the backfill was put
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
   my $self = shift ;
   my ( $r, $work_path ) = @_;

   die ref( $self ) . "::checkout_file() not found for ", $r->as_string, "\n"
      unless $self->can( "checkout_file" );

   my $dest_work_path = $self->checkout_file( $r );

   link $dest_work_path, $work_path
      or die "$! linking $dest_work_path to $r->work_path";
   unlink $dest_work_path or die "$! unlinking $dest_work_path";
}

=item sort_filter

    sub sort_filter {
       my $self = shift;
       my @sort_keys = @_;
       return () if @sort_keys && $sort_keys[0] eq "change_id";
       require VCP::Filter::changesets;
       return ( VCP::Filter::changesets->new(), );
    }

This is passed a sort specification string and returns any filters
needed to presort data for this destination.  It may return the
empty list (the default), or one or more instantiated filters.

=cut

sub sort_filters {
   return ();
}


=item require_change_id_sort

Destinations that care about the sort order usually want to use the
changesets filter, so they can overload the sort filter like so:

   sub sort_filters { shift->require_change_id_sort( @_ ) }

=cut

sub require_change_id_sort {
   my $self = shift ;
   my @sort_keys = @_;
   return () if @sort_keys && $sort_keys[0] eq "change_id";
   require VCP::Filter::changesets;
   return (
      VCP::Filter::changesets->new(),
   );
}


=item handle_footer

   $dest->handle_footer( $footer ) ;

Does any cleanup necessary.  Not required.  Don't call this from the override.

=cut

sub handle_footer {
   my $self = shift ;
   pr_done if $self->{DEST_HAVE_REVS_TO_EMIT};
   return ;
}

=item handle_header

   $dest->handle_header( $header ) ;

Stows $header in $self->header.  This should only rarely be overridden,
since the first call to handle_rev() should output any header info.

=cut

sub handle_header {
   my $self = shift ;

   my ( $header ) = @_ ;

   $self->{DEST_HAVE_REVS_TO_EMIT} = undef;

   $self->header( $header ) ;

   return ;
}

=item rev_count

   $dest->rev_count( $number_of_revs_forthcoming );

Sent by the last aggregating plugin in the filter chain just before
the first revision is sent to inform us of the number of revs to expect.

=cut

sub rev_count {
   my $self = shift ;

   my ( $number_of_revs_forthcoming ) = @_;
   $self->{DEST_HAVE_REVS_TO_EMIT} = $number_of_revs_forthcoming;

   if ( $self->{DEST_HAVE_REVS_TO_EMIT} ) {
      pr_doing "writing revisions: ", {
         Expect => $number_of_revs_forthcoming,
      };
   }
   else {
      pr "no revisions to write";
   }
}

=item skip_rev

Sent by filters that discard revisions in line.

=cut

sub skip_rev {
   my $self = shift;

   pr_doing
      if $self->{DEST_HAVE_REVS_TO_EMIT};
}


=item handle_rev

   $dest->handle_rev( $rev ) ;

Outputs the item referred to by VCP::Rev $rev.  If this is the first call,
then $self->none_seen will be TRUE and any preamble should be emitted.

MUST BE OVERRIDDEN.  Don't call this from the override.

=cut

=item last_rev_in_filebranch

   my $rev_id = $dest->last_rev_in_filebranch(
      $source_repo_id,
      $source_filebranch_id
   );

Returns the last revision for the file and branch indicated by
$source_filebranch_id.  This is used to support --continue.

Returns undef if not found.

=cut

sub last_rev_in_filebranch {
   my $self = shift;
   return 0 unless defined $self->{DEST_HEAD_REVS};
   return ($self->head_revs->get( \@_ ))[0];
}

=back


=head1 NOTES

Several fields are jury rigged for "base revisions": these are fake
revisions used to start off incremental, non-bootstrap transfers with
the MD5 digest of the version that must be the last version in the
target repository.  Since these are "faked", they don't contain
comments or timestamps, so the comment and timestamp fields are treated as
"" and 0 by the sort routines.

=cut

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
