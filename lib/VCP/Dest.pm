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
use VCP::Revs ;
use VCP::Debug qw(:debug) ;

use vars qw( $VERSION $debug ) ;

$VERSION = 0.1 ;

$debug = 0 ;

use base 'VCP::Plugin' ;

use fields (
   'DEST_HEADER',      ## Holds header info until first rev is seen.
   'DEST_SORT_SPEC',   ## ARRAY of field names to sort by
   'DEST_SORT_KEYS',   ## HASH of sort keys, indexed by name and rev.
) ;

use VCP::Revs ;


=item new

Creates an instance, see subclasses for options.  The options passed are
usually native command-line options for the underlying repository's
client.  These are usually parsed and, perhaps, checked for validity
by calling the underlying command line.

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Dest $self = $class->SUPER::new( @_ ) ;

   $self->set_sort_spec( "change,time,comment" ) ;

   return $self ;
}


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

   $self->compare_base_revs( $rev ) ;

Checks out the indicated revision fromt the destination repository and
compares it (using digest()) to the file from the source repository
(as indicated by $rev->work_path). Dies with an error message if the
base revisions do not match.

Calls $self->checkout_file( $rev ), which the subclass must implement.

=cut

sub compare_base_revs {
   my VCP::Dest $self = shift ;
   my ( $rev ) = @_ ;

   ## This block should only be run when transferring an incremental rev.
   ## from a "real" repo.  If it's from a .revml file, the backfill will
   ## already be done for us.
   ## Grab it and see if it's the same...
   my $source_digest = $self->digest( $rev->work_path ) ;
   
   my $dest_digest   = $self->digest( $self->checkout_file( $rev ) ) ;
   die( "vcp: base revision\n",
       $rev->as_string, "\n",
       "differs from the last version in the destination p4 repository.\n",
       "    source digest: $source_digest\n",
       "    dest. digest:  $dest_digest\n"
   ) unless $source_digest eq $dest_digest ;
}


=item header

Gets/sets the $header passed to handle_header().

Generally not overridden: all error checking is done in new(), and
no output should be generated until output() is called.

=cut

sub header {
   my VCP::Dest $self = shift ;
   $self->{DEST_HEADER} = shift if @_ ;
   return $self->{DEST_HEADER} ;
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


=head3 Sorting

=over

=item set_sort_spec

   $dest->set_sort_spec( @key_names ) ;

@key_names specifies the list of fields to sort by.  Each element in the array
may be a comma separated list.  Such elements are treated as though each name
was passed in it's own element; so C<( "a", "b,c" )> is equivalent to C<("a",
"b", "c")>.  This eases command line parameter parsing.

Sets the sort specification, checking to make sure that the field_names
have corresponding parse_sort_field_... handlers in this object.

Legal field names include: name, change, change_id, rev, rev_id, comment,
time.

If a field is not present in a rev, it is treated as being less than "".

Default ordering is by

  - change_id    (compared numerically using <=>, for now)
  - time         (commit time: simple numeric, since this is a simple number)
  - comment      (alphabetically, case sensitive)

This ordering benefits change number oriented systems while preserving
commit order for non-change number oriented systems.

If change_id is undefined in either rev, it is not used.

If time is undefined in a rev, the value "-1" is used.  This causes
base revisions (ie digest-only) to precede real revisions.

That's not always good, though: one of commit time or change number should
be defined!  

Change ids are compared numerically, times by date order (ie numerically, since
time-since-the-epoch is used internally). Comments are compared alphabetically.

Each sort field is split in to one or more segments, see the appropriate
parse_sort_field_... documentation.

Here's the sorting rules:
  - Revisions are compared field by field.
  - The first non-equal field determines sort order.
  - Fields are compared segment by segment.
  - The first non-equal segment determines sort order.
  - A not-present segment compares as less-than any other segment, so
    fields that are leading substrings of longer fields come first, and
    not-present fields come before all present fields, including empty
    fields.

=cut

sub set_sort_spec {
   my VCP::Dest $self = shift ;

   my @spec = split ',', join ',', @_ ;

   for ( @spec ) {
      next if $self->can( "parse_sort_field_$_" ) ;
      croak "Sort specification $_ is not available in ",
         ref( $self ) =~ /.*:(.*)/ ;
   }

   debug "vcp: sort spec: ", join ",", @spec
      if explicitly_debugging "sort" || debugging $self ;
   $self->{DEST_SORT_SPEC} = \@spec ;
   return undef ;
}


=item parse_sort_field_name

    push @sort_key_segs, $self->parse_sort_field_name( $rev ) ;

Splits the C<name> of the revision in to segments suitable for sorting.

=cut

sub parse_sort_field_name {
   my VCP::Dest $self = shift ;
   my VCP::Rev $rev ;
   ( $rev ) = @_ ;

   for ( $rev->name ) {
      return ()   unless defined ;
      return ("") unless length  ;
      return split "/" ;
   }
}

=item parse_sort_field_rev
=item parse_sort_field_rev_id
=item parse_sort_field_revision
=item parse_sort_field_revision_id
=item parse_sort_field_change
=item parse_sort_field_change_id

    push @sort_key_segs, $self->parse_sort_field_name( $rev ) ;

These split the C<change_id> or C<rev_id> of the revision in to segments
suitable for sorting.  Several spellings of each method are provided for user
convenience; all spellings for each field work the same way.  This is because
users may think of different names for each field depending on how much RevML
they know (the _id variants come from RevML), or whether they like to spell
"revision" or "rev".

The splits occur at the following points:

   1. Before and after each substring of consecutive digits
   2. Before and after each substring of consecutive letters
   3. Before and after each non-alpha-numeric character

The substrings are greedy: each is as long as possible and non-alphanumeric
characters are discarded.  So "11..22aa33" is split in to 5 segments:
( 11, "", 22, "aa", 33 ).

If a segment is numeric, it is left padded with 50 NUL characters.

This algorithm makes 1.52 be treated like revision 1, minor revision 52, not
like a floating point C<1.52>.  So the following sort order is maintained:

   1.0
   1.0b1
   1.0b2
   1.0b10
   1.0c
   1.1
   1.2
   1.10
   1.11
   1.12

The substring "pre" might be treated specially at some point.

(At least) the following cases are not handled by this algorithm:

   1. floating point rev_ids: 1.0, 1.1, 1.11, 1.12, 1.2
   2. letters as "prereleases": 1.0a, 1.0b, 1.0, 1.1a, 1.1

Never returns (), since C<rev_id> is a required field.

=cut

## This function's broken out to be shared.
sub _pad_number {
   for ( $_[0] ) {
      return () unless defined ;
      return ( "\x00" x ( 50 - length ) ) . $_[0] ;
   }
}

sub _pad_rev_id {
   map /^\d+\z/ ? _pad_number $_ : $_ , @_ ;
}


## This function's broken out to be shared.
sub _clean_text_field {
   for ( $_[0] ) {
      return () unless defined ;
      return ($_) ;
   }
}

## This function (not method) is broken out for testing purposes.  Perhaps
## later, it can be made in to a method to allow subclassing.
sub _split_rev_id {
   for ( $_[0] ) {
      return ()     unless defined ;
      return ( "" ) unless length ;

      return split /(?:
	  (?<=[[:alpha:]])(?=[^[:alpha:]])
	 |(?<=[[:digit:]])(?=[^[:digit:]])
	 |[^[:alnum:]]+
      )/x ;
   }
}

*parse_sort_field_rev_id = \&parse_sort_field_rev ;
*parse_sort_field_revision = \&parse_sort_field_rev ;
*parse_sort_field_revision_id = \&parse_sort_field_rev ;
sub parse_sort_field_rev {
   my VCP::Dest $self = shift ;
   my ( $rev ) = @_ ;
   return _pad_rev_id _split_rev_id $rev->rev_id ;
}


*parse_sort_field_change_id = \&parse_sort_field_change ;
sub parse_sort_field_change {
   my VCP::Dest $self = shift ;
   my ( $rev ) = @_ ;
   return _pad_rev_id _split_rev_id $rev->change_id ;
}

=item parse_sort_field_time

Pads and returns the seconds-since-epoch value that is the time.

=cut

sub parse_sort_field_time {
   my VCP::Dest $self = shift ;
   my ( $rev ) = @_ ;
   return _pad_number $rev->time ;
}

=item parse_sort_field_comment

Just returns the comment.

=cut

sub parse_sort_field_comment {
    my VCP::Dest $self = shift ;
    my ( $rev ) = @_ ;
    return _clean_text_field $rev->comment ;
}


sub _calc_sort_key {
    my VCP::Dest $self = shift ;
    my ( $rev ) = @_ ;
    my @fields ;
    for my $spec ( @{$self->{DEST_SORT_SPEC}} ) {
        my $sub = $self->can( "parse_sort_field_$spec" ) ;
	die "Can't sort by $spec, no parse_sort_field_$spec found"
	   unless $sub ;
	my @segments = $sub->( $self, $rev ) ;
	confess $rev->as_string, " contains an <undef> sort key"
	   if grep !defined, @segments ;
        push @fields, \@segments ;
    }
    return \@fields ;
}

## The sort routine
sub _rev_cmp {
   confess "\$a is a '$a', not a VCP::Rev" unless isa( $a, "VCP::Rev" ) ;
   confess "\$b is a '$b', not a VCP::Rev" unless isa( $b, "VCP::Rev" ) ;
   my @a_fields = @{$a->sort_key} ;
   my @b_fields = @{$b->sort_key} ;

   debug "vcp cmp: ", $a->as_string, "\n        :", $b->as_string
      if explicitly_debugging "sort" ;

   while ( @a_fields && @b_fields ) {
      my $result ;
      my @a_segments = @{shift @a_fields} ;
      my @b_segments = @{shift @b_fields} ;
      while ( @a_segments && @b_segments ) {
	 debug "vcp cmp: $a_segments[0] cmp $b_segments[0]"
	    if explicitly_debugging "sort" ;
	 $result = shift( @a_segments ) cmp shift( @b_segments ) ;
	 debug "vcp cmp: $result" if $result && explicitly_debugging "sort" ;
	 return $result if $result ;
      }
      debug "vcp cmp: " . @a_segments . " <=> " . @b_segments
	 if explicitly_debugging "sort" ;
      $result = @a_segments <=> @b_segments ;
      debug "vcp cmp: $result" if $result && explicitly_debugging "sort" ;
      return $result if $result ;
   }

   confess "revs have different numbers of sort key fields:",
      $a->as_string, "\n",
      $b->as_string 
      if @a_fields || @b_fields ;

   debug "vcp cmp: 0" if debugging "sort" ;
   return 0 ;
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

   for ( $revs->get ) {
       $_->sort_key( $self->_calc_sort_key( $_ ) ) ;
   }

   debug "sorting revisions" if debugging ;
   $revs->set( sort _rev_cmp $revs->get ) ;
}

=back


=back

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
