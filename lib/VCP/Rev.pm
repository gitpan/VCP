package VCP::Rev;

=head1 NAME

VCP::Rev - VCP's concept of a revision

=head1 SYNOPSIS

   use VCP::Rev;

   use VCP::Rev qw( iso8601format );

   my $r = VCP::Rev->new;

=head1 DESCRIPTION

A data structure that represents a revision to a file (but, technically,
not a version of a file, though the two are often synonymous).

=head1 METHODS

=over

=cut

$VERSION = 1 ;

@EXPORT_OK = qw( iso8601format );
use Exporter ();
*import = \&Exporter::import;
*import = \&Exporter::import;

use strict ;

use Carp ;
use VCP::Logger qw( lg pr BUG );
use VCP::Debug ':debug' ;
use VCP::Utils 'empty' ;

my @fields;

BEGIN {
## VCP::Revs are blessed arrays that contain a series of unpacked fields
## (the references to shared strings above) and a packed string.  The
## accessors for the packed strings unpack as needed.  The packing is
## to save overhead for "payload" fields that are not used for sorting.
##
@fields = (
   ##
   ## RevML fields and their types.
   ##    s=string, the default
   ##    i=integer
   ##    _=build private accessors (prefixed with an "_") for a packed
   ##      field; allows public wrappers around packed fields.
   ##    @=it's an array (needed for serialization support)
   ##
   'ID:_',                 ## A unique identifier for the rev
   'NAME',               ## The file name, relative to REV_ROOT
   'SOURCE_NAME',          ## immutable field, initialized to NAME
   'SOURCE_FILEBRANCH_ID', ## immutable field, initialized to
                           ## NAME or NAME<branch_number> for cvs
   'SOURCE_REPO_ID',       ## immutable field, initialized to
                           ## <repo_type>:<repo_server>
   'TYPE',                 ## Type.  Binary/text.
   'BRANCH_ID',          ## What branch this revision is on
   'SOURCE_BRANCH_ID',     ## immutable field initialized to BRANCH_ID
   'REV_ID',             ## The source repositories unique ID for this revision
   'SOURCE_REV_ID',        ## immutable field initialized to REV_ID
   'CHANGE_ID',            ## The unique ID for the change set, if any
   'SOURCE_CHANGE_ID',     ## immutable field initialized to CHANGE_ID
   'P4_INFO',              ## p4-specific info.
   'CVS_INFO',             ## cvs-specific info.
   'TIME:i',               ## The commit/submit time, in seconds-since-the-epoch
   'MOD_TIME:i',           ## The last modification time, if available
   'USER_ID',            ## The submitter/commiter of the revision
   'LABELS:_@',            ## A bit vector of tags/labels assoc. with this rev.
   'COMMENT',            ## The comment/message for this rev.
   'ACTION',               ## What was done ('edit', 'move', 'delete', etc.)
   'PREVIOUS_ID',          ## The id of the preceding version
   'SOURCE:_',            ## A reference to the source so that the destination
                          ## can get the file it needs right from the source.
                          ## NOTE: it's up to callers to thunk this for
                          ## serialization, not VCP::Rev.  Some will want
                          ## to undef() it, others will want to save
                          ## and restore it.
);

##
## Compile the fields' accessors
##

my %call_count;
END {
   lg "$_: $call_count{$_}\n"
      for sort {
         $call_count{$a} <=> $call_count{$b}
      } keys %call_count;

}

my @code;

for ( @fields ) {
   my $key = $_;
   my ( $n, $t ) = split /:/;
   my $is_private = $t ? $t =~ s/_//  : undef;
   my $fname         = lc $n;
   my $name          = ( $is_private ? "_" : "" ) . lc $n;
   my $set_name      = ( $is_private ? "_" : "" ) . "set_" . lc $n;

   push @code, <<ACCESSOR;
#line 1 VCP::Rev::$name()
sub $name {
   goto &$set_name if \@_ > 1;
   my \$self = shift;
\$call_count{$name}++;
   return \$self->{$fname};
}


#line 1 VCP::Rev::$set_name()
sub $set_name {
   my \$self = shift;
\$call_count{$set_name}++;
   \$self->{$fname} = shift;
   Carp::cluck "$set_name called in non-void context" if defined wantarray;
}
ACCESSOR

}


debug @code if debugging;

eval join "", @code, 1 or do {
    my $line = 1;
    ( my $msg = join "", @code ) =~ s/^/sprintf "%3d|", $line++/mge;
    die "$@:\n$msg";
};

}

=item new

Creates an instance, see subclasses for options.

   my $rev = VCP::Rev->new(
      name => 'foo',
      time => $commit_time,
      ...
   ) ;

=cut

sub new {
   my $class = ref $_[0] ? ref shift : shift;
   my $self = bless {@_}, $class;

   if ( $self->{labels} ) {
      $self->set_labels( @{delete $self->{labels}} );
   }
   else {
      $self->{labels} = [];
      $self->{seen_labels} = {};
   }

   return $self;
}

sub as_hash {
   my $self = shift;
   return { %$self };
}

=item fields

Returns a list of field names, with "@" prepended to any array fields.

=cut

sub fields {
   return map {
      my $name = lc $_;
      my $is_array = /\@/;
      $name =~ s/:.*//;
      $is_array ? "\@$name" : $name;
   } @fields;
}

=item serialize

Converts the revision metadata to a set of "name=value" strings
suitable for emitting to a flat file for later recovery.  Names are
included so that new revisions of VCP can rescuscitate revisions.

=cut

sub serialize {
   my $self = shift;

   return map {
      my $name = lc $_;
      my $is_array = /\@/;
      $name =~ s/:.*//;
      my $getter = $name eq "source" ? "_source" : $name;
      my @v = $self->$getter();
      @v && defined $v[0]
         ? $name . (
            $is_array
               ? "@" . join ",",
                  map {
                     my $v = $_;
                     $v =~ s/\\/\\\\/g;
                     $v =~ s/,/\\-/g;
                     $v;
                  } @v
               : "=" . $v[0]
            )
         : ();
   } sort @fields;
}


sub deserialize {
   my $class = shift;

   my $r = VCP::Rev->new;

   for ( @_ ) {
      my ( $name, $type, $value ) = /\A(\w+)([@=])(.*)\z/s
         or BUG "can't deserialize '$_'";
      my $setter = $name eq "source" ? "_set_source" : "set_$name";
      if ( $type eq "=" ) {
         BUG "unknown VCP::Rev field '$name'" unless $r->can( $setter );
         $r->$setter( $value );
      }
      else {
         my @values = map {
            s{\\\\}{\\}g;
            s{\\-}{,}g;
            $_;
         } split /,/, $value;
         $r->$setter( \@values );
      }
   }

   return $r;
}


sub split_name {
   shift;
   local $_ = $_[0];
   return ()     unless defined ;
   return ( "" ) unless length ;

   s{\A[\\/]+}{};
   s{[\\/]+\z}{};

   return split qr{[\\/]+};
}

sub cmp_name {
   my $self = shift;
   Carp::confess unless UNIVERSAL::isa( $self, __PACKAGE__ );

   my @a = ref $_[0] ? @{$_[0]} : $self->split_name( $_[0] );
   my @b = ref $_[1] ? @{$_[1]} : $self->split_name( $_[1] );

   my $r = 0;
   $r = shift( @a ) cmp shift( @b )
      while ! $r && @a && @b;

   $r || @a <=> @b;
}

=item split_id

   VCP::Rev->split_id( $id );

Splits an id in to chunks on punctuation and number/letter boundaries.

   Id           Result
   ==           ======
   1            ( 1 )
   1a           ( 1, "a" )
   1.2          ( 1, "", 2 )
   1a.2         ( 1, "a", 2 )

This oddness is to facilitate manually named revisions that use a
lettering scheme.  Note that the sort algorithms make an assumption that
"1.0a" is after "1.0".  This prevents kind of naming like "1.2pre1".

=cut

sub split_id {
   shift;
   for ( $_[0] ) {
      return ()     unless defined ;
      return ( "" ) unless length ;

      my @r = map /(\d*)(\D*)/, split /[^[:alnum:]]+/;
      pop @r while @r && ! length $r[-1];
      return @r;
   }
}

=item cmp_id

   VCP::Rev->cmp_id( $id1, $id2 );
   VCP::Rev->cmp_id( \@id1, \@id2 );  # for presplit ids

splits $id1 and $id2 if necessary and compares them using C<< <=> >> on
even numbered elements and C<cmp> on odd numbered elements.

=cut

sub cmp_id {
   my $self = shift;
   Carp::confess unless UNIVERSAL::isa( $self, __PACKAGE__ );

   my @a = ref $_[0] ? @{$_[0]} : $self->split_id( $_[0] );
   my @b = ref $_[1] ? @{$_[1]} : $self->split_id( $_[1] );

   my ( $A, $B, $r );
   while ( 1 ) {
      last unless @a && @b;
      ( $A, $B ) = ( shift @a, shift @b );
      confess "\$A='$A' not numeric" unless $A =~ /\A\d+\z/;
      confess "\$B='$B' not numeric" unless $B =~ /\A\d+\z/;
      $r = $A <=> $B;
      return $r if $r;

      last unless @a && @b;
      ( $A, $B ) = ( shift @a, shift @b );
      $r = $A cmp $B;
      return $r if $r;
   }

   return @a <=> @b;
}


=item is_base_rev

Returns TRUE if this is a base revision.  This is the case if no action
is defined.  A base revision is a revision that is being transferred
merely to check it's contents against the destination repository's
contents. Base revisions contain no action and contain a <digest> but no
<delta> or <content>.

When a VCP::Dest::* receives a base revision, the actual body of the
revision is 'backfilled' from the destination repository and checked
against the digest.  This cuts down on transfer size, since the full
body of the file never need be sent with incremental updates.

See L<VCP::Dest/backfill> as well.

=cut

sub is_base_rev {
   my $self = shift ;

   return ! defined $self->{action};
}


=item is_placeholder_rev

Returns TRUE if this is a placeholder revision.  Placeholder revisions
are used to record branch points for files that have not been altered on
their branches.

This occurs when reading CVS repositories and finding files that have
branch tags but no revisions on the branch.

A placeholder revision has an action of "placeholder".

Note that placeholders may have rev_id and change_id fields, but they
may be malformed; they are present for sorting purposes only and should
be ignored by the destination repository.

Placeholders may not be present for branches which have files on them.

=cut

sub is_placeholder_rev {
   my $self = shift ;

   my $a = $self->{action};

   return defined $a
      && (
         $a eq "placeholder"
         || $a eq "branch"
         || $a eq "clone"
      );
}


=item is_branch_rev

Returns TRUE if this is a branch founding placeholder revision.
These revisions are used to record branch points for files without
modifying the files.

A branch revision has an action of "branch".

Note that branch placeholders may have rev_id and change_id fields, but
they may be malformed; they are present for sorting purposes only and
should be ignored by the destination repository.

Branch revisions may not be present for branches which have files on
them but should be in order to cause the destination to create the
branch before altering any files on it.

=cut

sub is_branch_rev {
   my $self = shift ;

   my $a = $self->{action};

   return defined $a && $a eq "branch";
}


=item is_clone_rev

Returns TRUE if this is a cloning placeholder revision.  These revisions
are used to mirror files from one branch to another when a physical
filebranch maps to more than one logical branch.  This is not possible
in p4, but is possible in both CVS and VSS.  CVS generates these as of
this writing, VSS may by the time you read this.

=cut

sub is_clone_rev {
   my $self = shift ;

   my $a = $self->{action};

   return defined $a && $a eq "clone";
}


=item base_revify

Converts a "normal" rev in to a base rev.

=cut

sub base_revify {
   my $self = shift ;

   $self->set_labels;
   $self->{$_} =undef for qw(
      p4_info
      cvs_info
      time
      mod_time
      user_id
      comment
      action
      previous_id
   );
}

=item id

Sets/gets the id.  Returns "$name#$rev_id" by default, which should work
for most systems.

=cut

sub id {
   goto &_set_id if @_ > 1;
   my $self = shift;

   my $id = $self->_id;

   return $id if defined $id;
   my $n = $self->{source_name};
   my $r = $self->{source_rev_id};
   BUG "undefined name: ", $self->as_string unless defined $n;
   BUG "empty name: ", $self->as_string unless length $n;
   BUG "undefined source_rev_id: ", $self->as_string unless defined $r;
   BUG "empty source_rev_id: ", $self->as_string unless length $r;
   return "$n#$r";
}


sub set_id {
   goto &_set_id;
}

## We maintain a reference to the sources and pack the index.  This allows
## for recoverable serialization (as changesets.pm uses), but may hamper
## storage between instantiations (as VCP::Dest::metadb does).
my %sources;
sub source {
   my $self = shift;

   goto \&set_source if @_;

   return $sources{$self->{source} || ""}; ## $sources{""} == undef
}


sub set_source {
   my $self = shift;
   my ( $new_source ) = @_;

BUG "source must be an object" if defined $new_source && !ref $new_source;

   if ( defined $new_source ) {
      my $key = int $new_source;
      $sources{$key} ||= do {
          ## Make sure circrefs to filters are removed at END.  This
          ## makes using VCP::Rev->source() unstable in END{} blocks, but
          ## really, juggling a live grenade in the final seconds of
          ## your life is ok.
          require VCP::Plugin;
          VCP::Plugin->queue_END_sub( sub { delete $sources{$key} } );

          $new_source;
      };

      $self->{source} = $key;
   }
   else {
      $self->{source} = $new_source;
   }
}


=item get_source_file

Fetches the file from the source repository and returns a path to that file.

=cut

sub get_source_file {
    my $self = shift;
    die "source() not set for ", $self->as_string, "\n"
       unless $self->source;
    $self->source->get_source_file( $self );
}


=item labels

   $r->set_labels( \@labels ) ;  ## pass an array ref for speed
   @labels = $r->labels ;

Sets/gets labels associated with a revision.  If a label is applied multiple
times, it will only be returned once.  This feature means that the automatic
label generation code for r_... revision and ch_... change labels won't add
additional copies of labels that were already applied to this revision in the
source repository.

Returns labels in an unpredictible order, which happens to be sorted for
now.  This sorting is purely for logging purposes and may disappear at
any moment.

=item add_label

  $r->add_label( $label ) ;
  $r->add_label( @labels ) ;

Marks one or more labels as being associated with this revision of a file.

=cut

sub add_label {
   my $self = shift ;
   for ( @_ ) {
      push @{$self->{labels}}, $_
         unless $self->{seen_labels}->{$_}++;
   }
   return ;
}


sub labels {
   goto &set_labels if @_ > 1;
   my $self = shift;
   @{$self->{labels}};
}


sub set_labels {
   my $self = shift;
   @{$self->{labels}} = ();
   %{$self->{seen_labels}} = ();
   $self->add_label( map ref() ? @$_ : $_, @_ );
}


sub _branch_id {
    my $self = shift;

    for ( $self->branch_id) {
        return "" if empty $_;
        return "<$_>";
    }
}


sub _name_branch_id {
    my $self = shift;

    $self->name . $self->_branch_id;
}

=item iso8601format

   VCP::Rev::iso8601format( $time );

Takes a seconds-since-the-epoch time value and converts it to
an ISO8601 formatted date.  Exportable:

   use VCP::Rev qw( iso8601format );

=cut

sub iso8601format {
   die "time parameter missing" unless @_;
   my @f = reverse( (gmtime shift)[0..5] ) ;
   $f[0] += 1900 ;
   $f[1] ++ ; ## Month of year needs to be 1..12
   return sprintf( "%04d-%02d-%02d %02d:%02d:%02dZ", @f ) ;
}


=item as_string

Prints out a string representation of the name, rev_id, change_id, type,
time, and a bit of the comment.  base revisions are flagged as such (and
don't have fields like time and comment).

=cut

sub as_string {
   my $self = shift ;

   my @v = map(
      defined $_ ? $_ : "<undef>",
      map(
         $_ eq 'time' && defined $self->$_()
             ? iso8601format $self->$_()
         : $_ eq 'comment' && defined $self->$_()
             ? do {
                my $c = $self->$_();
                $c =~ s/\\/\\\\/g;
                $c =~ s/\n/\\n/g;
                $c =~ s/\r/\\r/g;
                $c =~ s/\t/\\t/g;
                $c =~ s/\f/\\f/g;
                $c =~ s/([^\020-\177])/sprintf "\\%03o", ord $1/eg;
                $c = substr( $c, 0, 32 )
                   if length( $c ) > 32;
                $c;
             }
         : $_ eq 'action' && defined $self->$_()
             ? sprintf "%-6s", $self->$_() # 6 == length "delete"
             : $self->$_(),
         (
            qw( name rev_id change_id branch_id type ),
            $self->is_base_rev
               ? ()
               : qw( action time user_id comment ),
         )
      )
   ) ;

   return $self->is_base_rev
      ? sprintf( qq{%s#%s @%s <%s> (%s) BASE REV}, @v )
      : sprintf( qq{%s#%s @%s <%s> (%s) %s %s %s "%s"}, @v );
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
