package VCP::Source ;

=head1 NAME

VCP::Source - A base class for repository sources

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

=over

=item  --bootstrap

  --bootstrap=pattern

Forces all files matching the given shell regular expression (may use
wildcards like "*", "?", and "...") to have their first revisions
transferred as complete copies instead of deltas.  This is useful when
you want to transfer a revision other than the first revision as the
first revision in the target repository.  It is also useful when you
want to skip some revisions in the target repository (although the L<Map
filter|VCP::Filter::map> has superceded this use).

=item --continue

Tells VCP to continue where it left off from last time.  This will not
detect new branches of already transferred revisions (this limitation
should be lifted, but results in an expensive rescan of metadata), but
will detect updates to already transferred revisions.

=back

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Driver );

use strict ;

use UNIVERSAL qw( isa ) ;
use VCP::Debug qw( :debug ) ;
use VCP::Driver;
use VCP::Logger qw( lg pr BUG );
use VCP::Utils qw( empty );

#use base 'VCP::Driver' ;

#use fields (
#   'BOOTSTRAP',         ## The raw option so we can regurgitate it
#   'BOOTSTRAP_REGEXPS', ## Determines what files are in bootstrap mode.
#   'DEST',
#   'CONTINUE',          ## Set if we're resuming from the prior
#                        ## copy operation, if there is one.  This causes
#                        ## us to determine a minimum rev by asking the
#                        ## destination what it's seen on a given filebranch
#   'QUEUED_REVS_COUNT',    ## Number of revs sent
#
#   ## Turns out that most real repositories (ie not RevML, at least)
#   ## are most easily scanned in reverse chronological order.  Keeping
#   ## the last revision or the last revision by filebranch is handy in
#   ## these cases.
#   'LAST_REV',               ## The rev that was last sent
#   'LAST_REV_BY_FILEBRANCH', ## The last sent
#   'PREVIOUS_IDS',           ## A HASH keyed on all the previous_ids seen.
#                             ## This is used to filter out base revisions
#                             ## with no children being sent.
#) ;


sub init {
   my $self = shift;
   $self->bootstrap( $self->{BOOTSTRAP} );
   $self->{QUEUED_REVS_COUNT} = 0;
   $self->{LAST_REV_BY_FILEBRANCH} = {};
}


###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.  See L<VCP::Plugin> for methods
often needed in subclasses.

=head2 Subclass utility API

=over

=item options_spec

Adds common VCP::Source options to whatever options VCP::Plugin parses:

=cut

sub options_spec {
   my $self = shift;
   return (
      $self->SUPER::options_spec,
      "bootstrap|b=s"    => \$self->{BOOTSTRAP},
      "continue"         => \$self->{CONTINUE},
      "rev-root=s"       => \$self->{REV_ROOT},
   );
}

=item dest

Sets/Gets a reference to the VCP::Dest object.  The source uses this to
call handle_header(), handle_rev(), and handle_end() methods.

=cut

sub dest {
   my $self = shift ;

   $self->{DEST} = shift if @_ ;
   return $self->{DEST} ;
}


=item continue

Sets/Gets the CONTINUE field (which the user sets via the --continue flag)

=cut

sub continue {
   my $self = shift ;

   $self->{CONTINUE} = shift if @_ ;
   return $self->{CONTINUE} ;
}


=item real_source

Returns the reference to be used when sending revisions to the destination.

Each revision has a pointer to the source that sends it so that filters
and destinations can call get_source_file().

Most sources return $self; Sources that spool data, such as
VCP::Source::metadb, need to specify a real source.  They do so by
overloading this method.  VCP::Source::revml does not do this, as it
supplies a get_source_file().

=cut

sub real_source {
    return shift;
}


sub send_rev {
   my $self = shift ;
   my ( $r ) = @_;

   debug $r->id
      if debugging;

   $r->set_source( $self->real_source );
   $self->dest->handle_rev( $r ) if $self->dest;
}

=item rev_mode

    my $mode = $self->rev_mode( $filebranch_id, $rev_id );

Returns FALSE, "base", or "normal" as a function of the filebranch and
rev_id.  Do not queue the revision if this returns FALSE (you may also
skip any preceding revisions).  Queue it only as a base revision if it
returns "base", and queue it as a full revision otherwise.

Not all base revs will be sent; base revs that have no child revs will
not be sent.

Always returns "normal" when not in continue mode.

=cut

sub rev_mode {
   my $self = shift;
   return "normal" unless $self->continue && $self->dest;

   my ( $filebranch_id, $rev_id ) = @_;

   BUG "\$filebranch_id == undef" unless defined $filebranch_id;
   BUG "\$filebranch_id == ''"    unless length  $filebranch_id;
   BUG "\$rev_id == undef" unless defined $rev_id;
   BUG "\$rev_id == ''"    unless length  $rev_id;

   my $last_rev_in_dest_id = $self->dest->last_rev_in_filebranch(
      $self->repo_id,
      $filebranch_id
   );

   return "normal" if empty $last_rev_in_dest_id;
   my $cmp = VCP::Rev->cmp_id( $rev_id, $last_rev_in_dest_id );

   return "normal" if $cmp > 0;
   return "base"   if $cmp == 0;
   return undef;
}

=item queue_rev

Some revs can't be sent immediately.  They get queued.  Once queued, the
revision may not be altered.  All revisions must be queued before being
sent.  All revs from the source repository should be queued, --continue
processing is automatic.  Placeholders should be inserted for all branches,
even empty ones.

This updates last_rev and last_rev_for_filebranch.

Returns FALSE if the rev cannot be queued, for instance if it's already
been queued once.

rev_mode() should be called before creating a rev, or at least before
queue_rev()ing it in order to see if and in what form the rev should be
sent.

=cut


sub _store_rev {
   ## Shove a rev out to disk, noting its previous_id.
   my $self = shift ;
   my ( $r ) = @_;

   my $p_id = $r->previous_id;
   $self->{PREVIOUS_IDS}->{$p_id} = undef
      unless empty( $p_id )
         || $self->is_bootstrap_mode( $r->source_name );
         ## Files that are being bootstrapped do not need base revs, so 
         ## don't note their previous_ids so that base revs will not be
         ## sent for them.  The base rev in question might have some other
         ## rev referring to it, but is not needed for this one.

   $self->revs->add( $r );
}

sub queue_rev {
   my $self = shift ;
   my ( $r ) = @_;

   debug $r->id
      if debugging;

   my $filebranch_id = $r->source_filebranch_id;
   my $l = $self->{LAST_REV_BY_FILEBRANCH};
   ## We keep the last revision in each filebranch in memory so that
   ## sources that have to parse from most recent to oldest can queue
   ## each rev, then later set its revision.
   $self->_store_rev( $l->{$filebranch_id} )
      if $l->{$filebranch_id};

   if ( $self->revs->added_rev( $r->id ) ) {
      pr "can't extract same revision twice (corrupt source repository?): '",
         $r->as_string;
      return undef;
   }

   ++$self->{QUEUED_REVS_COUNT};
   $self->{LAST_REV} = $r;

   $l->{$filebranch_id} = $r;
#if ( $self->{QUEUED_REVS_COUNT} >= 100 ) {
#    my @p;
#    for my $p ( @{$VCP::vcp->{PLUGINS}} ) {
#        no strict 'refs';
#        my $h = {};
#        my $t = ref $p;
#        push @p, $t, $h;
#        for ( sort keys %{"${t}::FIELDS"} ) {
#            next if $_ eq "DEST";
#            next if UNIVERSAL::isa( $p->{$_}, "VCP::DB" );
#            $h->{$_} = $p->{$_};
#        }
#    }
#    use BFD;d\@p;
#    die;
#}

}


=item queued_rev

    $self->queued_rev( $id );

Returns a queued rev by id.

Sources where revs can arrive willy-nilly, like VCP::Source::revml, queue
up all revs and need to randomly access them.

=cut

sub queued_rev {
   my $self = shift ;
   my ( $id ) = @_;

   for my $r ( values %{$self->{LAST_REV_BY_FILEBRANCH}} ) {
      return $r
         if $r->id eq $id;
   }
   return $self->revs->get( $id );
}

=item last_rev

Returns the last revision queued.

=cut

sub last_rev {
   my $self = shift ;
   my ( $r ) = @_;

   return $self->{LAST_REV};
}


=item last_rev_for_filebranch

    $self->last_rev_for_filebranch( $filebranch_id );

Returns the last revision queued on the indicated filebranch.

=cut

sub last_rev_for_filebranch {
   my $self = shift ;
   my ( $filebranch_id ) = @_;

   return $self->{LAST_REV_BY_FILEBRANCH}->{$filebranch_id};
}


=item set_last_rev_in_filebranch_previous_id

    $self->set_last_rev_in_filebranch_previous_id( $r );

If there is a last_rev_for_filebranch for $r->filebranch_id, sets its
previous_id to point to $r.  This is useful for sources which scan
in most-recent-first order.

=cut


sub set_last_rev_in_filebranch_previous_id {
   my $self = shift ;
   my ( $r ) = @_;

   BUG "\$r undef" unless defined $r;
   BUG "\$r = '$r'" unless ref $r;

   my $child_rev = $self->last_rev_for_filebranch( $r->source_filebranch_id );
   if ( $child_rev ) {
      return if $child_rev->is_base_rev;
      debug "setting ", $child_rev->id, "->previous_id to ", $r->id
         if debugging;

      $child_rev->previous_id( $r->id );
   }
}


=item already_queued

    $self->already_queued( $id );

Returns true if the indicated id was queued.

=cut

sub already_queued {
   my $self = shift;
   return $self->revs->exists( @_ );
}




=item queued_rev_count

Returns (does not set) the number of revs queued so far.

Replaces the deprecated function sent_rev_count().

=cut

sub queued_rev_count {
    my $self = shift;
    return $self->{QUEUED_REVS_COUNT};
}

sub sent_rev_count {  ## DEPRECATED
    my $self = shift;
    return $self->{QUEUED_REVS_COUNT};
}


=item store_cached_revs

    $self->store_cached_revs;

For parsers which read history one file at a time and branch in rev_id
space, like VCP::Source::cvs, it's possible to flush all revs to disk
after each file is parsed.  This method takes the last VCP::Rev in
each filebranch and stores it to disk, freeing memory.

=cut

sub store_cached_revs {
   my $self = shift ;

   $self->_store_rev( $_ )
      for values %{$self->{LAST_REV_BY_FILEBRANCH}};
   %{$self->{LAST_REV_BY_FILEBRANCH}} = ();
      ## NB: Don't delete $self->{LAST_REV_BY_FILEBRANCH}, it causes a
      ## massive memory leak, probably because $self is a phash.
}


=item send_revs

    $self->send_revs;

Removes and sends all revs accumulated so far.  Called automatically
after scan_metadata().

=cut

sub send_revs {
   my $self = shift ;

   debug "sending queued revs" if debugging;

   $self->dest->rev_count( $self->{QUEUED_REVS_COUNT} )
      if $self->dest;

   $self->store_cached_revs;
   $self->revs->foreach(
      sub {
         my ( $r ) = @_;

         return if $r->is_base_rev && ! exists $self->{PREVIOUS_IDS}->{$r->id};
            ## Ignore base revisions with no children.

         $self->send_rev( @_ );
      }
   );
}

=back

=head1 SUBCLASS OVERLOADS

These methods should be overridded in any subclasses.

=over

=cut

=item scan_metadata

This is called to scan the metadata for the source repository.  It
should call rev_mode() for each revision found (including any that need
to be concocted to make up for collapsed metadata in the source, like
VSS or CVS deletes or CVS branch creation) and if that returns TRUE,
then queue_rev() should be called.

If rev_mode() returns "base", then the transfer is in --continue mode
and this rev should be built as or converted to a base revision.  The
easiest way to do this is to build it normally and then call
$r->base_revify().

If the metadata source returns metadata from most recent to oldest, as
do most file history reports, the previous_id() need not be set until
the next revision in a filebranch is scanned.  The most recent rev
passed to queue_rev() is available by calling last_rev(), if the
metadata is one branch at a time, and the last rev in each filebranch is
available by calling last_rev_for_filebranch().

If the metadata is scanned one file or filebranch at a time and
branched are all created by the time the end of a file's metadata
arrives, calling store_cached_revs() will flush all queued revs from the
last_rev() and last_rev_for_filebranch() in-memory caches to the disk
cache (all other revs are flushed as their successors arrive).

There is no easy way to handle randomly ordered metadata at this time,
typically a source will accumulate as little as it can in memory and
queue the rest.  See VCP::Source::cvs for an example of this.

Once scan_metadata() is complete, send_revs() will be called
automatically.

=cut

sub scan_metadata {
   my VCP::Source $self = shift;
   return;
}

sub copy_revs {  ## TODO: delete this (DEPRECATED)
   my $self = shift ;
   my ( $revs ) = @_;
   $self->scan_metadata();
   $self->send_revs;
}


=item get_source_file

All sources must provide a way for the destination to fetch a revision.

=cut

sub get_source_file {
    my $self = shift;
    die $self, " does not overload get_source_file()\n";
}


=item handle_header

REQUIRED OVERLOAD.

Subclasses must add all repository-specific info to the $header, at least
including rep_type and rep_desc.

   $header->{rep_type} => 'p4',
   $self->p4( ['info'], \$header->{rep_desc} ) ;

The subclass must pass the $header on to the dest:

   $self->dest->handle_header( $header )
      if $self->dest;

This may be called when dest is null to allow the source to initialize
itself when it won't be scanning the real source.  So the if $self->dest
is important.

That's not the case for copy_revs().

=cut

sub handle_header {
   my $self = shift ;

#   my ( $header ) = @_ ;

   BUG "ERROR: handle_header not overloaded by class '", ref $self, "'.  Oops.\n";
#      if $self->can( 'handle_header' ) eq \&handle_header ;

#   $self->dest->handle_header( $header ) ;
}


=item handle_footer

Not a required overload, as the footer carries no useful information at
this time.  Overriding methods must call this method to pass the
$footer on:

   $self->SUPER::handle_footer( $footer ) ;

=cut

sub handle_footer {
   my $self = shift ;

   my ( $footer ) = @_ ;

   ## Release memory.
   $self->{LAST_REV_BY_FILEBRANCH} = undef;
   $self->{LAST_REV} = undef;
   $self->{PREVIOUS_IDS} = undef;

   $self->dest->handle_footer( $footer ) ;
}


=item parse_time

   $time = $self->parse_time( $timestr ) ;

Parses "[cc]YY/MM/DD[ HH[:MM[:SS]]]".

Will add ability to use format strings in future.
HH, MM, and SS are assumed to be 0 if not present.

Returns a time suitable for feeding to localtime or gmtime.

Assumes local system time, so no good for parsing times in revml, but that's
not a common thing to need to do, so it's in VCP::Source::revml.pm.

=cut

{
    ## This routine is slow and gets called a *lot* with duplicate
    ## inputs, at least by VCP::Source::cvs, so we memoize it.
    my %cache;

    sub parse_time {
       my $self = shift ;
       my ( $timestr ) = @_ ;

       return $cache{$timestr} ||= do {
           ## TODO: Get parser context here & give file, line, and column.
           ## filename and rev too, while we're scheduling more work for
           ## the future.
           BUG "Malformed datetime value '$timestr'\n"
              unless $timestr =~ /^(\d\d)?\d?\d(\D\d?\d){2,5}/ ;
           
           my $is_am;
           my $is_pm;
           if ( $timestr =~ s/\s*([ap])m?\s*\z//i ) {
               $is_am = 1 if lc $1 eq "a";
               $is_pm = 1 if lc $1 eq "p";
           }

           my @f = split /[[:punct:]\s]/, $timestr;

           if (
              length $f[0] <= 2
              && $f[0] <= 12
              && ( length $f[2] == 4
                 || $f[2] > 12
                 || "0" eq substr( $f[2], 0, 1 )
              )
           ) {
              ## Must be MM/DD/YY, or MM/DD/YYYY.  timelocal() needs
              ## YY(YY)?/MM/DD
              splice @f, 0, 3, ( $f[2], $f[0], $f[1] );
           }

           $f[3] = 0   if $is_am && $f[3] == 12;
           $f[3] += 12 if $is_pm && $f[3] <= 11;

           --$f[1] ; # Month of year needs to be 0..11
           push @f, ( 0 ) x ( 6 - @f ) ;
           require Time::Local;
           my $t = eval { Time::Local::timelocal( reverse @f ) };
           BUG $@ unless defined $t;
           return $t;
        }
    }
}


=item bootstrap

Sets (and parses) or gets the bootstrap spec.

Can be called plain:

   $self->bootstrap( $bootstrap_spec ) ;

See the command line documentation for the format of $bootstrap_spec.

=cut

sub bootstrap {
   my $self = shift ;
   if ( @_ ) {
      my ( $val ) = @_ ;
      $self->{BOOTSTRAP} = $val;
      $self->{BOOTSTRAP_REGEXPS} = [
         defined $val
            ? map $self->compile_path_re( $_ ), split /,+/, $val
            : ()
       ];
    }

   return $self->{BOOTSTRAP};
}


=item is_bootstrap_mode

   ... if $self->is_bootstrap_mode( $file ) ;

Compares the filename passed in against the list of bootstrap regular
expressions set by L</bootstrap>.

The file should be in a format similar to the command line spec for
whatever repository is passed in, and not relative to rev_root, so
"//depot/foo/bar" for p4, or "module/foo/bar" for cvs.

This is typically called in the subbase class only after looking at the
revision number to see if it is a first revision (in which case the
subclass should automatically put it in bootstrap mode).

=cut

sub is_bootstrap_mode {
   my $self = shift ;
   my ( $file ) = @_ ;

   my $result = grep $file =~ $_, @{$self->{BOOTSTRAP_REGEXPS}} ;

   lg(
      "$file ",
      ( $result ? "=~ " : "!~ " ),
      "[ ", join( ', ', map "qr/$_/", @{$self->{BOOTSTRAP_REGEXPS}} ), " ] (",
      ( $result ? "not in " : "in " ),
      "bootstrap mode)"
   ) if debugging;

   return $result ;
}

=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
