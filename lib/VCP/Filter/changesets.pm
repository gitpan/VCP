package VCP::Filter::changesets;

=head1 NAME

VCP::Filter::changesets - Group revs in to changesets

=head1 SYNOPSIS

  ## From the command line:
   vcp <source> changesets: ...options... -- <dest>

  ## In a .vcp file:

    ChangeSets:
       time                     <=60     ## seconds
       user_id                  equal    ## case-sensitive equality
       comment                  equal    ## case-sensitive equality
       source_filebranch_id     notequal ## case-sensitive inequality

=head1 DESCRIPTION

This filter is automatically loaded when there is no sort filter loaded
(both this and L<VCP::Filter::sort|VCP::Filter::sort> count as sort
filters).

=head2 Sorting by change_id, etc.

When all revs from the source have change numbers, this filter sorts by
change_id, branch_id, and name, regardless of the rules set.  The name
sort is case sensitive, though it should not be for Win32.  This sort by
change_id is necessary for sources that supply change_id because the
order of scanning the revisions is not usually (ever, so far :) in
change set order.

=head2 Aggregating changes

If one or more revisions arrives from the source with an empty
change_id, the rules for this filter establish the conditions that
determine what revisions may be grouped in to each change.

In this case, this filter rewrites all change_id fields so that the
(eventual) destination can use the change_id field to break the
revisions in to changes.  This is sometimes used by non-changeset
oriented destinations to aggregate "changes" as though a user were
performing them and to reduce the number of individual operations the
destination driver must perform (for instance: VCP::Dest::cvs prefers
to not call cvs commit all the time; cvs commit is slow).

Revisions are aggregated in to changes using a set of rules that
determine what revisions may be combined.  One rule is implicit in the
algorithm, the others are explicitly specified as a set of defaults that
may be altered by the user.

=head3 The Implicit Rule

The implicit rule is that no change may contain two revisions where one
is a descendant of another.  The algorithm starts with the set of
revisions that have no parents in this transfer, chooses a set of them
to be a change according to the explicit conditions, and emits it.  Only when
a revision is emitted does this filter consider it's offspring for
emission.  This cannot be changed.

(EXPERIMENTAL) The only time this implicit rule is not enough is in a
cloning situation.  In CVS and VSS, it is possible to "share" files
between branches.  VSS supports and promotes this model in its user
interface and documentation while CVS allows it more subtlely by
allowing the same branch to have multiple branch tags.  In either case,
there are multiple branches of a file that are changed simultaneously.
The CVS source recognizes this (and the VSS source may by the time you
read this) and chooses a master revision from which to "clone" other
revisions.  These cloned revisions appear on the child branch as
children of the master revision, not as children of the preceding
revision on the child branch.  This is confusing, but it works.  In
order to prevent this from confusing the destinations, however, it can
be important to make sure that two revisions to a given branch of a
given file do not occur in the same revision; this is the purpose of the
explicit rule "source_filebranch_id notequal", covered below.

=head3 The Explicit Rules

Rules may be specified for the ChangeSets filter.  If no rules are
specified, a set of default rules are used.  If any rules are specified,
none of the default rules are used.  The default rules are explained
after rule conditions are explained.

Each rule is a pair of words: a data field and a condition.

There are three conditions: "notequal", "equal" and "<=N" (where N is a
number; note that no spaces are allowed before the number unless the
spec is quoted somehow):

=over

=item equal

The "equal" condition is valid for all fields and states that all
revisions in the same change must have identical values for the
indicated field.  So:

    user_id                  equal

states that all revisions in a change must be submitted by the same
user.

All "equal" conditions are used before any other conditions, regardless
of the order they are specified in to categorize revisions in to
prototype changes.  Once all revisions have been categorized in to
prototyps changes, the "<=N" and "notequal" rules are applied in order
to split the change prototypes in to as many changes as are needed to
satisfy them.

=item notequal

The "notequal" condition is also valid for all fields and specifies that
no two revisions in a change may have equal values for a field.  It does
not make sense to apply this to time fields, and is usually only needed
to ensure that two revisions to the same file on the same branch do not
get bundled in to the same change.

=item <=N

The "<=N" specification is only available for the "time" field.  It
specifices that no gaps larger than N seconds may exist in a change.

=back

The default rules are:

    time                     <=60     ## seconds
    user_id                  equal    ## case-sensitive equality
    comment                  equal    ## case-sensitive equality
    source_filebranch_id     notequal ## case-sensitive inequality

These rules

The C<time <=60> condition sets a maximum allowable difference between two
revisions; revisions that are more than this number of seconds apart are
considered to be in different changes.

The C<user_id equal> and C<comment equal> conditions assert that two
revisions must be by the same user and have the same comment in order to
be in the same change.

=begin foo


The C<branched_rev_branch_id equal> condition is a special case to
handle repositories like CVS which don't record branch creation times.
This condition kicks in when a user creates several branches before
changing any files on any of them; in this case all of the branches get
created at the same time.  That leaves odd looking conversions.  This
condition also kicks in when multiple CVS branches exist with no changes
on them.  In this case, VCP::Source::cvs groups all of the branch
creations after the last "real" edit.  In both cases, the changeset
filter splits branch creations so that only one branch is created per
change.

The C<branched_rev_branch_id> condition only applies to revisions
branching from one branch in to another.

=end foo

The C<source_filebranch_id notequal> condition prevents cloned revs of a
file from appearing in the same change as eachother (see the discussion
above for more details).

=head1 ALGORITHM

=head2 handle_rev()

As revs are received by handle_rev(), they are store on disk.  Several
RAM-efficient (well, for Perl) data structures are built, however, that
describe each revision's children and its membership in a changeset.
Some or all of these structures may be moved to disk when we need to
handly truly large data sets.

=head3 The ALL_HAVE_CHANGE_IDS statistic

One statistic that handle_rev() gathers is whether or not all revisions
arrived with a non-empty change_id field.

=head3 The REV_COUNT statistic

How many revisions have been recieved.  This is used only for UI
feedback; primarily it is to forewarn the downstream filter(s) and
destination of how many revisions will constitute a 100% complete
transfer.

=head3 The CHANGES list

As each rev arrives, it is placed in a "protochange" determined solely
by the revision's fields in the rules list with an "equal" condition.
Protochanges are likely to have too many revisions in them, including
revisions that descend from one another and revisions that are too far
apart in time.

=head3 The CHANGES_BY_KEY index

The categorization of each revision in to changes is done by forming a
key string from all the fields in the rules list with the "equal"
condition.  This index maps unique keys to changes.

=head3 The CHILDREN index

This is an index of all revisions that are direct offspring of a
revision.


=head3 The REVS_BY_CHANGE_ID index

If all revs do indeed arrive with change_ids, they need to be sorted
and sent out in order.  This index is gathered until the first rev with
an empty change_id arrives.

=head3 The ROOT_IDS list

This is a list of the IDs of all revisions that have no parent revisions
in this transfer.  This is used as the starting point for
send_changes(), below.

=head3 The CHANGES_BY_REV index

As the large protochanges are split in to smaller ones, the resulting
CHANGES list is indexed by, among other things, which revs are in the
change.  This is so the algorithms can quickly find what change a
revision is in when it's time to consider sending that revision.

=head2 handle_footer()

All the real work occurs when handle_footer() is called.
handle_footer() glances at the change_id statistic gathered by
handle_rev() and determines whether it can sort by change_id or whether
it has to perform change aggregation.

If all revisions arrive with a change_id, sort_by_change_id_and_send()
If at least one revision didn't handle_footer() decides to perform
change aggregation by calling split_protochanges() and then
send_changes().

Any source or upstream filter may perform change aggregation by
assigning change_ids to all revisions.  VCP::Source::p4 does this.  At
the time of this writing no otherd do.

Likewise, a filter like VCP::Filter::StringEdit may be used to clear out
all the change_ids and force change aggregation.

=head2 sort_by_change_id_and_send()

If all revisions arrived with a change_id, then they will be sorted by
the values of ( change_id, time, branch_id, name ) and sent on.  There
is no provision in this filter for ignoring change_id other than if any
revisions arrive with an empty change_id, this sort is not done.

=head2 split_and_send_changes()

Once all revisions have been placed in to protochanges, a change is
selected and sent like so:

=over

=item 1

Get an oldest change with no revs that can't yet be sent.  If none is
found, then select one oldest change and remove any revs that can't be
sent yet.

=item 2

Select as many revs as can legally be sent in a change by sorting them
in to time order and then using the <=N and notequal rules to determine
if each rev can be sent given the revs that have already passed the
rules.  Delay all other revs for a later change.

=back

=cut

$VERSION = 1 ;

@ISA = qw( VCP::Filter );

use strict ;
use VCP::Logger qw( lg pr BUG );
use VCP::Debug qw( :debug );
use VCP::Utils qw( empty );
use VCP::Filter;
use VCP::Rev;
use VCP::DB_File; ## TODO: move pack_values and unpack_values in to Utils
use VCP::DB_File::big_records;
#use base qw( VCP::Filter );

## A change handle is a number from 0..N.

## A change key is the catenation of all fields that are configured to
## be "equal".  This is useful until all revs have been received, then
## is discarded as the changes to that point are re-split based on the "<=N"
## rules.

## TODO: move the various HASH and ARRAY data structures to disk when
## we get more than, oh say 10,000 revs.

#use fields (
#   'CHILDREN',        ## A HASH keyed on a rev's id of ARRAYs of the
#                      ## rev's children's ids.
#   'REV_COUNT',       ## How many revs we received
#   'ALL_HAVE_CHANGE_IDS', ## Set if all incoming revs have change_ids
#   'REVS_BY_CHANGE_ID',   ## HASH of change_id => \@rev_ids
#
#   'CHANGES_BY_KEY',  ## A HASH of change keys to change handles
#   'CHANGE_KEY_SUB',  ## Returns the change key for a rev
#   'CHANGE_SPLIT_TEST_SUB',
#                      ## Returns TRUE if a change needs to be split
#                      ## between two revisions
#   'CHANGES',         ## An ARRAY of changes: each change is a list of
#                      ## packed strings, one per rev.  The first field in
#                      ## the pack is the rev_id, the second is it's time.
#   'CHANGES_BY_REV',  ## Which change each revision is a member of.  This
#                      ## is used when several changes have the same timestamp
#                      ## and we want to avoid sending a change for which we
#                      ## don't have all the revisions ready to go.  It
#                      ## is not valid until the initial changes are split
#                      ## by time.
#   'ROOT_IDS',        ## Ids of parentless revs.  This is built by handle_rev()
#                      ## and send_changes() uses it to seed
#                      ## the wavefront clustering algorithm.
#   'REVS_DB',         ## A temporary data store of revisions
#   'INDEX_COUNT',     ## How many indexes have been assigned to revs
#   'INDEXES_BY_ID',   ## What index each rev has
#);


sub _compile_change_key_sub {
   my $self = shift;
   my ( $rules ) = @_;

   my @code;

   for ( @$rules ) {
      my ( $field, $cond ) = map lc, @$_;

      if ( $cond eq "equal" ) {
         push @code,
            $field ne "branched_rev_branch_id" ? <<CODE : <<CODE;
      \$r->$field,
CODE
      \$r->is_placeholder_rev,
      \$r->is_placeholder_rev ? \$r->branch_id : "\\000",
CODE
      }
   }

   @code = ( <<'PREAMBLE', @code, <<'POSTAMBLE' );
#line 1 VCP::Filter::changesets::initial_change_key()
sub {
   my ( $r ) = @_;

   my $key = VCP::DB_File->pack_values( 
      map defined $_ ? $_ : "",
PREAMBLE
   );
   debug $r->as_string, " key '$key'" if debugging;
   return $key;
}
POSTAMBLE

   debug "\n", @code if debugging;

   unless ( $self->{CHANGE_KEY_SUB} = eval join "", @code ) {
      my $x =$@;
      chomp $x;
      lg "$x:\n", @code;
      die $x, "\n";
   }
}


sub _compile_change_split_test_sub {
   my $self = shift;
   my ( $rules ) = @_;

   my @checks;
   my @accum;

   for ( @$rules ) {
      my ( $field, $cond ) = map lc, @$_;

      if ( $cond eq "equal" ) {
         ## This is not used to split changes here, it's used when
         ## splitting them originally, see the initial_change_key sub.
      }
      elsif ( $field eq "time" && $cond =~ /\A<=\s*(\d+)\z/ ) {
         push @checks, <<CODE;
      ( defined \$h->{max_$field} and ( \$r->$field - \$h->{max_$field} ) > $1
         and join "",
               "$field > $1: '", \$h->{max_$field},
               "' vs. '", \$r->$field
      )
CODE
         push @accum, <<CODE;
      \$h->{max_$field} = \$r->$field;
CODE
      }
      elsif ( $cond =~ /\Anot\s*equal\z/ ) {
         push @checks, <<CODE;
      ( exists \$h->{${field}s_seen}->{\$r->$field || ""}
         and "already saw $field '" . \$r->$field . "'"
      )
CODE
         push @accum, <<CODE;
      \$h->{${field}s_seen}->{\$r->$field || ""} = 1;
      debug "now have seen $field '", \$r->$field || "", "'"
         if debugging;
CODE
      }
      else {
         die "vcp: invalid ", $self->filter_name, " rule: \"$field\" \"$cond\"";
      }
   }

   my @code = ( <<'PRE', join( "      ||", @checks ), <<'MID', @accum, <<'POST' );
#line 1 VCP::Filter::changesets::change_split_test()
sub {
   my ( $h, $change, $r ) = @_;
   ## Returns TRUE if $change should be split starting with $r

   debug "split testing ", $r->as_string
     if debugging;

   my $should_split = (
PRE
   );
MID
   return $should_split;
}
POST

   debug "\n", @code if debugging;

   unless ( $self->{CHANGE_SPLIT_TEST_SUB} = eval join "", @code ) {
      my $x =$@;
      chomp $x;
      lg "$x:\n", @code;
      die $x, "\n";
   }
}


sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $options ||= [];

   my @rules = $self->parse_rules_list(
      $options, "Field", "Condition",
      [ ## default rules
         [qw( time                   <=60     )],
         [qw( user_id                equal    )],
         [qw( comment                equal    )],
         [qw( source_filebranch_id   notequal )],
      ]
   );

   $self->_compile_change_key_sub(        @rules );
   $self->_compile_change_split_test_sub( @rules );

   return $self ;
}

sub filter_name { return "ChangeSets" }


sub sort_keys {
   my $self = shift;
   return qw(
      change_id
   );
}


sub revs_db {
   my $self = shift;
   $self->{REVS_DB};
}


sub r_index {
   my $self = shift;
   my ( $id ) = @_;

   return exists $self->{INDEXES_BY_ID}->{$id}
      ? $self->{INDEXES_BY_ID}->{$id}
      : ( $self->{INDEXES_BY_ID}->{$id} = $self->{INDEX_COUNT}++ );
}


sub store_rev {
   my $self = shift;
   my ( $r ) = @_;

   my $id = $r->id;
   my $r_index = $self->r_index( $id );

   $self->revs_db->set( [ $r_index ], $r->serialize );

   return $r_index;
}


sub destore_rev {
   my $self = shift;
   my ( $r_index ) = @_;

   my $r = VCP::Rev->deserialize(
      $self->revs_db->get( [ $r_index ] )
   );
   BUG "vcp: $_ not found" unless $r;

   return $r;
}


sub handle_header {
   my $self = shift;
   $self->{REV_COUNT} = 0;
   $self->{ALL_HAVE_CHANGE_IDS} = 1;
   $self->{REVS_BY_CHANGE_ID} = {};
   $self->{CHANGES_BY_KEY} = {};
   $self->{CHANGES} = [];
   $self->{INDEX_COUNT} = 0;
   $self->{INDEXES_BY_ID} = {};

   my $store_loc = $self->tmp_dir;

   $self->{REVS_DB} = VCP::DB_File::big_records->new(
      StoreLoc  => $store_loc,
      TableName => "revs",
   );

   $self->revs_db->delete_db;
   $self->revs_db->open_db;

   $self->SUPER::handle_header( @_ );
}


sub DESTROY {
   my $self = shift;
   if ( $self->{REVS_DB} ) {
       $self->revs_db->close_db;
       $self->revs_db->delete_db;
   }
}


sub handle_rev {
   my $self = shift;
   my ( $r ) = @_;

   my $r_index = $self->store_rev( $r );

   my $r_index_in_binary = pack( "w", $r_index );

   if ( $self->{ALL_HAVE_CHANGE_IDS} ) {
      if ( empty $r->change_id ) {
         if ( $self->{REV_COUNT} ) {
            pr "only first ", $self->{REV_COUNT}, " revisions had change_ids";
         }
         $self->{ALL_HAVE_CHANGE_IDS} = 0;
         $self->{REVS_BY_CHANGE_ID} = undef;
      }
      else {
         $self->{REVS_BY_CHANGE_ID}->{$r->change_id} .= $r_index_in_binary;
      }
   }

   my $change_key = $self->{CHANGE_KEY_SUB}->( $r );

   my $change_index = exists $self->{CHANGES_BY_KEY}->{$change_key}
      ? $self->{CHANGES_BY_KEY}->{$change_key}
      : do {
         push @{$self->{CHANGES}}, "";
         $self->{CHANGES_BY_KEY}->{$change_key} = $#{$self->{CHANGES}};
      };


   $self->{CHANGES}->[$change_index] .= $r_index_in_binary;

   $self->{CHANGES_BY_REV}->[$r_index] = $change_index;

   if ( empty $r->previous_id ) {
      $self->{ROOT_IDS} .= $r_index_in_binary;
   }
   else {
      ## It's a descendant node, note its parentage and stow it for later
        $self->{CHILDREN}->[
           $self->r_index( $r->previous_id )
        ] .= $r_index_in_binary;
   }

   ++$self->{REV_COUNT};
}


sub split_and_send_changes {
   ## handle_rev() built us a set of protochanges.  Send the oldest
   ## protochange first, splitting off as many revs as need be (in time
   ## order) in order to get *something* to send.  Also split in time
   ## order when we run in to multiple changes to the same filebranch.

   ## TODO: Could optimize a few ways:
   ##    - Keep an in-time order array of values %cur_changes
   ##    - Keep @{$change->{Revs}} in time order
   ##    - Don't delete $cur_change if there is anything left in
   ##      its FutureIndexes

   my $self = shift;

   pr "aggregating changes";

   $self->{REVS_BY_CHANGE_ID} = undef;
      ## Conserve memory

   
   ## Some shortcuts
   my $changes        = $self->{CHANGES};
   my $changes_by_rev = $self->{CHANGES_BY_REV};
   my $children       = $self->{CHILDREN};

   my @cur_indexes = unpack "w*", $self->{ROOT_IDS};
      ## ids for revisions that we can send.  Initially this is the
      ## set of revisions with no parents; children of those revs are
      ## added as those revs are emitted.  @cur_indexes get grouped in
      ## to changes in %cur_changes.

   $self->{ROOT_IDS} = undef;
      ## Conserve memory

   my %cur_changes;
      ## The set of changes that we are currently growing.  As revs are
      ## consumed from @cur_indexes, they are added to changes.  This is
      ## a HASH rather than an array because it's a very sparse space,
      ## we hope.
      ## Each change here has an ARRAY of Revs that may be sent and a
      ## string containing the ids of Revs that may not yet be sent.
      ## It also has a MinTime, the lowest time value of any of the
      ## Revs that may be sent.

   my $change_number = 1;  ## Humans start counting at 1.

   while ( @cur_indexes || keys %cur_changes ) {

      debug "revs that may now be sent:\n", map "   " .
         $self->destore_rev( $_ )->as_string . "\n", @cur_indexes
         if debugging;

      for my $r_index ( splice @cur_indexes ) {
         my $r = $self->destore_rev( $r_index );
         my $change_index = $changes_by_rev->[$r_index];
            ## The 0 based offset of the current change in the changes
            ## array.

         my $change = $cur_changes{$change_index};
         if ( !$change ) {
            my @future_indexes =
               grep $_ != $r_index,
               unpack "w*", $changes->[$change_index]
               if $changes->[$change_index];

            undef $changes->[$change_index];

            $cur_changes{$change_index} = $change = {
               Index          => $change_index,
               MinTime        => $r->time || 0,
               Revs           => [ $r ],
               FutureIndexes  => \@future_indexes,
            };

         }
         else {
            $change->{MinTime} = $r->time || 0
               if ( $r->time || 0 ) < $change->{MinTime};

            push @{$change->{Revs}}, $self->destore_rev( $r_index );
            @{$change->{FutureIndexes}}
               = grep $_ != $r_index, @{$change->{FutureIndexes}};
         }

      }

      debug "protochanges:\n", map {
            ( "   ",
               VCP::Rev::iso8601format( $_->{MinTime} || 0 ), "\n",
               map( "      " . $_->as_string . "\n", @{$_->{Revs}} ),
               map( "    f:" . $self->destore_rev( $_ )->as_string . "\n",
                  @{$_->{FutureIndexes}} )
            );
         } sort {
            $a->{MinTime} <=> $b->{MinTime} || $a->{Index} <=> $b->{Index};
         } values %cur_changes
         if debugging;

      my $cur_change;
      {
         ## Get the oldest change (based on MinTime).  If there's more
         ## than one, use the one with the smallest number of future
         ## revisions, and of those, use the one with the smallest
         ## Index, just for repeatability.
         ## TODO: Id
         my $min_time;
         my @oldest_changes;

         ## NOTE: a time (and thus a MinTime) of 0 or "" or undef means
         ## that there is no known time.
         ## TODO: identify choose a change that optimizes the number of
         ## changes.  This probably means splitting protochanges first
         ## then choosing the one that causes the minimum number of split
         ## changes in the future.

         for ( values %cur_changes ) {

            if ( ! defined $min_time || $_->{MinTime} < $min_time ) {
               $min_time = $_->{MinTime};
               @oldest_changes = ( $_ );
            }
            elsif ( $_->{MinTime} == $min_time ) {
               push @oldest_changes, $_;
            }
         }
         BUG "\@oldest_changes empty" unless @oldest_changes;

         debug scalar @oldest_changes, " changes at ", $min_time
            if debugging;

         if ( @oldest_changes > 1 ) {
            ## Sort is for repeatability only
            @oldest_changes = sort {
               @{$a->{FutureIndexes}} <=> @{$b->{FutureIndexes}}
                                      ||
                          $a->{Index} <=> $b->{Index}
            } @oldest_changes;
         }

         ## For now, just grab the first one.
         ## TODO: look through the changes and find the one with the
         ## largest gap after one of the @{$_->{Revs}}.  This will require
         ## loading the first rev in @{$_->{FutureIndexes}} and getting its
         ## time,
         ## but that's ok.  We could also choose a change that will free
         ## up some other complete change, but that's more subtle.

         $cur_change = shift @oldest_changes;
      }

      ## Set the change_id for each rev to be sent.
      ## Move children of the change we're sending in to @cur_indexes.
      ## We're sending all their parents, so we'll never have a
      ## chicken-and-egg problem in %cur_changes.
      my $should_split_why;
      my @revs_to_send;
      my @revs_to_keep;
      my %h;

      for my $r (
         sort { ( $a->time || 0 ) <=> ( $b->time || 0 ) }
         @{delete $cur_change->{Revs}}
      ) {
         $should_split_why ||=
            $self->{CHANGE_SPLIT_TEST_SUB}->( \%h, $cur_change, $r );

         if ( $should_split_why ) {
            push @revs_to_keep, $r;
            next;
         }

         $r->change_id( $change_number );
         push @revs_to_send, $r;

         my $r_index = delete $self->{INDEXES_BY_ID}->{$r->id};

         if ( $children->[$r_index] ) {
            push @cur_indexes, unpack "w*", $children->[$r_index];
         }
         undef $children->[$r_index];  ## undef $foo releases extra memory
         undef $self->{CHANGES_BY_REV}->[$r_index];
      }

      lg "split protochange to build \@$change_number:", $should_split_why
         if $should_split_why;

      lg "change \@$change_number: " . @revs_to_send . " revs:\n",
         map "    " . $_->as_string . "\n", @revs_to_send;

      if ( @revs_to_keep ) {
         lg "leftover revs " . @revs_to_keep . " from change \@$change_number",
            debugging ? (
               ":\n",
               map "    " . $_->as_string . "\n", @revs_to_keep
            )
            : ();

         $cur_change->{Revs} = \@revs_to_keep;
         $cur_change->{MinTime} = $revs_to_keep[0]->time || 0;
            ## @revs_to_keep is in time order
      }
      else {
         ## Replace the future revs in the spot in $self->{CHANGES} that
         ## held this protochange.  This is to reduce the number of HASHes in
         ## memory: if a protochange has no revs eligible to be sent, might
         ## as well pack it back down.
         $changes->[$cur_change->{Index}] =
            pack "w*", splice @{$cur_change->{FutureIndexes}}
            if @{$cur_change->{FutureIndexes}};
            ## Leave all unprocess changes from this change behind.
         delete $cur_changes{$cur_change->{Index}};
      }

      ## Do this last just to not send a partial change.  If an error or
      ## segfault arises in an earlier loop, doing this should make the
      ## resulting state cleaner.
      $self->dest->handle_rev( $_ ) for @revs_to_send;

      ++$change_number;
   }

   ## Conserve memory
   $self->{CHILDREN}              = undef;
   $self->{CHANGE_SPLIT_TEST_SUB} = undef;
   $self->{CHANGES}               = undef;
   $self->{CHANGES_BY_REV}        = undef;
   $self->{INDEXES_BY_ID}         = undef;
}


sub _d($) { defined $_[0] ? $_[0] : "" }


sub sort_by_change_id_and_send {
   my $self = shift;

   ## NOTE: this sub is not needed much now that the ChangeSets filter
   ## is only added when necessary.  It perhaps should not be here at
   ## all.

   pr "sorting by change_id";

   ## Free memory
   $self->{CHILDREN}              = undef;
   $self->{CHANGE_SPLIT_TEST_SUB} = undef;
   $self->{CHANGES}               = undef;
   $self->{CHANGES_BY_REV}        = undef;
   $self->{ROOT_IDS}              = undef;
   $self->{INDEXES_BY_ID}         = undef;

   for my $change_id (
      sort {
         VCP::Rev->cmp_id( $a, $b )
      } keys %{$self->{REVS_BY_CHANGE_ID}}
   ) {
      my @rev_indexes =
         unpack "w*", delete $self->{REVS_BY_CHANGE_ID}->{$change_id};
      lg "change $change_id: " . @rev_indexes . " revs";
      debug "change $change_id:\n", map "    $_\n", @rev_indexes
         if debugging;
      my @revs;
      for ( @rev_indexes ) {
         push @revs, $self->destore_rev( $_ );
      }

      for my $r ( sort {
            ( _d $a->time || 0 ) <=> ( $b->time || 0 )
                                 ||
                _d $a->branch_id cmp _d $b->branch_id
                                 ||
                        $a->name cmp $b->name
                                 ||
              VCP::Rev->cmp_id( $a->rev_id, $b->rev_id )
         } @revs
      ) {
         $self->dest->handle_rev( $r );
      }
   }
}


sub rev_count {
   ## Ignore this, we send our own after emitting a log message
}


sub handle_footer {
   my $self = shift;

   $self->SUPER::rev_count( $self->{REV_COUNT} );

   ## Conserve memory
   $self->{CHANGES_BY_KEY}        = undef;
   $self->{CHANGE_KEY_SUB}        = undef;

   $self->{ALL_HAVE_CHANGE_IDS}
      ? $self->sort_by_change_id_and_send
      : $self->split_and_send_changes;

   $self->SUPER::handle_footer( @_ );
}

=head1 LIMITATIONS

This filter does not take the source_repo_id in to account: if somehow
you are merging multiple repositories in to one and want to interleave
the commits/submits "properly", ask for advice.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
