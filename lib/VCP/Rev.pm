package VCP::Rev ;

=head1 NAME

VCP::Rev - VCP's concept of a revision

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over

=cut

$VERSION = 1 ;

use strict ;

use Carp ;
use VCP::Debug ':debug' ;
use vars qw( %FIELDS ) ;

use fields (
## RevML fields:
   'NAME',       ## The file name, relative to REV_ROOT
   'TYPE',       ## Type.  Binary/text.  Need to stdize the values here
   'REV_ID',     ## The source repositories unique ID for this revision
   'CHANGE_ID',  ## The unique ID for the change set, if any
   'P4_INFO',    ## p4-specific info.
   'CVS_INFO',   ## cvs-specific info.
   'STATE',      ## The state (CVS specific at the moment).
   'TIME',       ## The commit/submit time, if available, as a simple number
   'MOD_TIME',   ## The last modification time, if available
   'USER_ID',    ## The submitter/commiter of the revision
   'LABELS',     ## A HASH, keys are tags/labels assoc. with this rev.
   'COMMENT',    ## The comment/message for this rev.
   'ACTION',     ## What was done ('edit', 'move', 'delete', etc.)
   'BASE_REV_ID',
## Internal fields: used by VCP::* modules, but not present in RevML files.
   'WORK_PATH',  ## Where to find the revision on the local filesys
   'DEST_WORK_PATH', ## Where to find the rev on local fs if it was backfilled
   'SOURCE_NAME',  ## The non-normalized name of the file, meaningful only to
                   ## a specific VCP::Source
## TODO: delete this, I think it is no longer used.
   'SORT_KEY',   ## An ARRAY of ARRAYs of the fields and segments to sort by
) ;

BEGIN {
   ## Define accessors.
   for ( keys %FIELDS ) {
      next if $_ eq 'WORK_PATH' ;
      next if $_ eq 'DEST_WORK_PATH' ;
      my $f = lc( $_ ) ;
      if ( $f eq 'labels' ) {
	 eval qq{
	    sub $f {
	       my VCP::Rev \$self = shift ;
	       if ( \@_ ) {
	          \$self->{$_} = {} ;
		  \@{\$self->{$_}}{\@_} = (undef) x \@_ ;
	       }
	       return \$self->{$_} ? sort keys \%{\$self->{$_}} : () ;
	    }
	 } ;
      }
      else {
	 eval qq{
	    sub $f {
	       my VCP::Rev \$self = shift ;
	       confess "too many parameters passed" if \@_ > 1 ;
	       \$self->{$_} = shift if \@_ == 1 ;
	       return \$self->{$_} ;
	    }
	 } ;
      }
      die $@ if $@ ;
   }
}


## We never, ever want to delete a file that has revs referring to it.
## So, we put a cleanup object in %files_to_delete and manually manage a
## reference count on it.  The hash is keyed on filename and contains
## a count value.  When the count reaches 0, it is cleaned.  We add a warning
## about undeleted files, which is a great PITA.  The reason there's a
## warning is that we could be using gobs of disk space for temporary files
## if there's some bug preventing VCP::Rev objects from being DESTROYed
## soon enough.  It's a PITA because it means that the source and
## destination object really must be dereferenced ASAP, so their SEEN
## arrays get cleaned up, and every once in awhile I screw it up somehow.
my %files_to_delete ;

END {
   if ( debugging && ! $ENV{VCPNODELETE} ) {
      for ( sort keys %files_to_delete ) {
	 if ( -e $_ ) {
	    warn "$_ not deleted" ;
	 }
      }
   }
}


=item new

Creates an instance, see subclasses for options.

   my VCP::Rev $rev = VCP::Rev->new(
      name => 'foo',
      time => $commit_time,
      ...
   ) ;

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Rev $self ;

   {
      no strict 'refs' ;
      $self = bless [ \%{"$class\::FIELDS"} ], $class ;
   }

   while ( @_ ) {
      my $key = shift ;
      $self->{uc($key)} = shift ;
   }

   if ( $self->{LABELS} ) {
      $self->labels( @{$self->{LABELS}} ) if ref $self->{LABELS} eq "ARRAY" ;
   }
   else {
      $self->{LABELS} = {} unless $self->{LABELS} ;
   }

   return $self ;
}


=item is_base_rev

Returns TRUE if this is a base revision.  This is the case if no
action is defined.  A base revision is a revision that is being
transferred merely to check it's contents against the destination
repository's contents.  It's usually a digest and the actual bosy
of the revision is 'backfilled' from the destination repository and
checked against the digest.  This cuts down on transfer size, since
the full body of the file never need be sent with incremental updates.

See L<VCP::Dest/backfill> as well.

=cut

sub is_base_rev {
   my VCP::Rev $self = shift ;

   return ! defined $self->{ACTION} ;
}


=item base_revify

Converts a "normal" rev in to a base rev.

=cut

sub base_revify {
   my VCP::Rev $self = shift ;

   $self->{$_} = undef for qw(
      P4_INFO
      CVS_INFO
      STATE
      TIME
      MOD_TIME
      USER_ID
      LABELS
      COMMENT
      ACTION
   );
}


=item work_path, dest_work_path

These set/get the name of the working file for sources and destinations,
respectively.  These files are automatically cleaned up when all VCP::Rev
instances that refer to them are DESTROYED or have their work_path or
dest_work_path set to other files or undef.

=cut

sub _set_work_path {
   my VCP::Rev $self = shift ;

   my ( $field, $fn ) = @_ ;
   my $doomed = $self->{$field} ;
   if ( defined $doomed
      && $files_to_delete{$doomed}
      && --$files_to_delete{$doomed} < 1
      && -e $doomed
   ) {
      if ( debugging $self ) {
         my @details ;
	 my $i = 2 ;
	 do { @details = caller(2) } until $details[0] ne __PACKAGE__ ;
	 debug "vcp: $self unlinking '$doomed' in "
	    . join( '|', @details[0,1,2,3]) ;
      }
      unlink $doomed or warn "$! unlinking $doomed\n"
         unless $ENV{VCPNODELETE};
   }

   $self->{$field} = $fn ;
   ++$files_to_delete{$self->{$field}} if defined $self->{$field} ;
}


sub work_path {
   my VCP::Rev $self = shift ;
   confess "too many parameters passed" if @_ > 1 ;
   $self->_set_work_path( 'WORK_PATH', @_ ) if @_ ;
   return $self->{WORK_PATH} ;
}


sub dest_work_path {
   my VCP::Rev $self = shift ;
   confess "too many parameters passed" if @_ > 1 ;
   $self->_set_work_path( 'DEST_WORK_PATH', @_ ) if @_ ;
   return $self->{DEST_WORK_PATH} ;
}


=item labels

   $r->labels( @labels ) ;
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
   my VCP::Rev $self = shift ;
   @{$self->{LABELS}}{@_} = (undef) x @_ ;
   return ;
}


sub as_string {
   my VCP::Rev $self = shift ;

   my @v = map(
      defined $_ ? $_ : "<undef>",
      $self->is_base_rev
	 ? map $self->$_(), qw( name rev_id change_id type )
	 : map(
	    $_ eq 'time' && defined $self->$_()
                ? scalar localtime $self->$_()
	    : $_ eq 'comment' && defined $self->$_()
                ? do {
                   my $c = $self->$_();
                   $c =~ s/\n/\\n/g;
                   $c =~ s/\r/\\r/g;
                   $c =~ s/\t/\\t/g;
                   $c =~ s/\l/\\l/g;
                   $c = substr( $c, 0, 32 )
                      if length( $c ) > 32;
                   $c;
                }
                : $self->$_(),
	    qw(name rev_id change_id type action time user_id comment )
	 )
   ) ;

   return $self->is_base_rev
      ? sprintf( qq{%s#%s @%s (%s) -- base rev --}, @v )
      : sprintf( qq{%s#%s @%s (%s) %s %s %s "%s"}, @v ) ;
}

sub DESTROY {
   return if $ENV{VCPNODELETE};
   my VCP::Rev $self = shift ;
   $self->work_path( undef ) ;
   $self->dest_work_path( undef ) ;
   my $doomed = $self->work_path ;
   if ( defined $doomed && -e $doomed ) {
      debug "vcp: $self unlinking '$doomed'" if debugging $self ;
      unlink $doomed or warn "$! unlinking $doomed\n";
   }
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
