package VCP::Dest::p4 ;

=head1 NAME

VCP::Dest::p4 - p4 destination driver

=head1 SYNOPSIS

   vcp <source> p4:user:password@p4port:[<dest>]
   vcp <source> p4:user(client):password@p4port:[<dest>]
   vcp <source> p4:[<dest>]

The <dest> spec is a perforce repository spec and must begin with // and a
depot name ("//depot"), not a local filesystem spec or a client spec. There
should be a trailing "/..." specified.

If no user name, password, or port are given, the underlying p4 command will
look at that standard environment variables. The password is passed using the
environment variable P4PASSWD so it won't be logged in debugging or error
messages, the other options are passed on the command line.

If no client name is given, a temporary client name like "vcp_tmp_1234" will be
created and used.  The P4CLIENT environment variable will not be used.  If an
existing client name is given, the named client spec will be saved off,
altered, used, and restored.  the client was created for this import, it will
be deleted when complete, regardless of whether the client was specified by the
user or was randomly generated.  WARNING: If perl coredumps or is killed with a
signal that prevents cleanup--like a SIGKILL (9)--the the client deletion or
restoral will not occur. The client view is not saved on disk, either, so back
it up manually if you care.

THE CLIENT SAVE/RESTORE FEATURE IS EXPERIMENTAL AND MAY CHANGE BASED ON USER
FEEDBACK.

VCP::Dest::p4 attempts change set aggregation by sorting incoming revisions.
See L<VCP::Dest/rev_cmp_sub> for the order in which revisions are sorted. Once
sorted, a change is submitted whenever the change number (if present) changes,
the comment (if present) changes, or a new rev of a file with the same name as
a revision that's pending. THIS IS EXPERIMENTAL, PLEASE DOUBLE CHECK
EVERYTHING!

=head1 DESCRIPTION

=head1 METHODS

=over

=cut

$VERSION = 1 ;

use strict ;
use vars qw( $debug ) ;

$debug = 0 ;

use Carp ;
use File::Basename ;
use File::Path ;
use Getopt::Long ;
use VCP::Debug ':debug' ;
use VCP::Dest ;
use VCP::Rev ;

use base qw( VCP::Dest VCP::Utils::p4 ) ;
use fields (
#   'P4_SPEC',               ## The root of the tree to update
   'P4_PENDING',            ## Revs pending the next submit
   'P4_DELETES_PENDING',    ## At least one 'delete' needs to be submitted.
   'P4_WORK_DIR',           ## Where to do the work.
   'P4_REPO_CLIENT',        ## See VCP::Utils::p4 for accessors and usage...

   ## members for change number divining:
   'P4_PREV_CHANGE_ID',    ## The change_id in the r sequence, if any
   'P4_PREV_COMMENT',      ## Used to detect change boundaries

) ;

=item new

Creates a new instance of a VCP::Dest::p4.  Contacts the p4d using the p4
command and gets some initial information ('p4 info' and 'p4 labels').

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Dest::p4 $self = $class->SUPER::new( @_ ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_p4_repo_spec( $spec ) ;

   my $files = $self->repo_filespec ;

   ## No need to deduce the rev_root, we let p4 do that by setting the
   ## client view to the destination path the user specified.

   GetOptions( "ArGhOpTioN" => \"" ) or $self->usage_and_exit ; # No options!

   $self->init_p4_view ;

   return $self ;
}


sub checkout_file {
   my VCP::Dest::p4 $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

confess unless defined $self && defined $self->header ;

   debug "vcp: retrieving '", $r->as_string, "' from p4 dest repo"
      if debugging $self ;

   ## The rev_root was put in the client view, p4 will "denormalize"
   ## the name for us.
   my $work_path = $self->work_path( $r->name ) ;
   debug "vcp: work_path '$work_path'" if debugging $self ;

   my VCP::Rev $saw = $self->seen( $r ) ;

   die "Can't backfill already seen file '", $r->name, "'" if $saw ;

   my ( undef, $work_dir ) = fileparse( $work_path ) ;
   $self->mkpdir( $work_path ) unless -d $work_dir ;

   my $tag = "r_" . $r->rev_id ;
   $tag =~ s/\W+/_/g ;

   ## The -f forces p4 to sync even if it thinks it doesn't have to.  It's
   ## not in there for any known reason, just being conservative.
   $self->p4( ['sync', '-f', $r->name . "\@$tag" ] ) ;
   die "'$work_path' not created in backfill" unless -e $work_path ;

   return $work_path ;
}


sub backfill {
   my VCP::Dest::p4 $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

confess unless defined $self && defined $self->header ;

   $r->work_path( $self->checkout_file( $r ) ) ;

   return 1 ;
}


sub handle_header {
   my VCP::Dest::p4 $self = shift ;
   $self->{P4_PENDING}        = [] ;
   $self->{P4_PREV_COMMENT}   = undef ;
   $self->{P4_PREV_CHANGE_ID} = undef ;
   $self->SUPER::handle_header( @_ ) ;
}


sub handle_rev {
   my VCP::Dest::p4 $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;
debug "vcp: handle_rev got $r ", $r->name if debugging $self ;

   if ( 
      ( @{$self->{P4_PENDING}} || $self->{P4_DELETES_PENDING} )
      && (
	 (
	    defined $r->change_id && defined $self->{P4_PREV_CHANGE_ID}
	    &&      $r->change_id ne         $self->{P4_PREV_CHANGE_ID}
	    && ( debugging( $self ) ? debug "vcp: time to submit: change_id changed" : 1 )
	 )
	 || (
	    defined $r->comment && defined $self->{P4_PREV_COMMENT}
	    &&      $r->comment ne         $self->{P4_PREV_COMMENT}
	    && ( debugging( $self ) ? debug "vcp: time to submit: comment changed [", $r->comment, "] vs [", $self->{P4_PREV_COMMENT}, "]" : 1 )
	 )
	 || (
	    grep( $r->name eq $_->name, @{$self->{P4_PENDING}} )
	    && ( debugging( $self ) ? debug "vcp: time to submit: name repeated" : 1 )
	 )
      )
   ) {
      $self->submit ;
   }
   
   $self->compare_base_revs( $r )
      if $r->is_base_rev && defined $r->work_path ;

   my VCP::Rev $saw = $self->seen( $r ) ;

   return if $r->is_base_rev ;

   my $fn = $r->name ;
   debug "vcp: importing ", $r->as_string if debugging $self ;
   my $work_path = $self->work_path( $fn ) ;
   debug "vcp: work_path '$work_path'" if debugging $self ;

   if ( $r->action eq 'delete' ) {
      my $already_deleted;
      if ( ! $saw ) {
         $self->p4( [ 'files', $fn ], '>', \my $log );
         warn $log;
         $already_deleted = $log =~ /- delete change \d+/;
         $self->p4( [ 'sync', '-f', $fn ] )
            unless $already_deleted;
      }

      if ( -e $work_path ) {
         unlink $work_path || die "$! unlinking $work_path" ;
      }

      unless ( $already_deleted ) {
         $self->p4( ['delete', $fn] ) ;
         $self->{P4_DELETES_PENDING} = 1 ;
      }
      $self->delete_seen( $r ) ;
   }
   else {
   ## TODO: Don't assume same filesystem or working link().
      {
         my $filetype = defined $r->p4_info && $r->p4_info =~ /\((\S+)\)$/
	    ? $1
	    : $r->type ;

         my $add_it ;
	 if ( -e $work_path ) {
	    $self->p4( ["edit", "-t", $filetype, $fn] ) ;
	    unlink $work_path          or die "$! unlinking $work_path" ;
	 }
	 else {
	    $self->mkpdir( $work_path ) ;
	    $add_it = 1 ;
	 }
	 debug "vcp: linking ", $r->work_path, " to $work_path" if debugging $self ;
	 link $r->work_path, $work_path
	    or die "$! linking ", $r->work_path, " -> $work_path" ;

	 $r->dest_work_path( $work_path ) ;

	 if ( defined $r->mod_time ) {
	    utime $r->mod_time, $r->mod_time, $work_path
	       or die "$! changing times on $work_path" ;
	 }
	 if ( $add_it ) {
	    $self->p4( ["add", "-t", $filetype, $fn] ) ;
	 }
      }

      unless ( $saw ) {
	 ## New file.
      }

      ## TODO: Provide command line options for user-defined tag prefixes
      my $tag = "r_" . $r->rev_id ;
      $tag =~ s/\W+/_/g ;
      $r->add_label( $tag ) ;
      if ( defined $r->change_id ) {
	 my $tag = "ch_" . $r->change_id ;
	 $tag =~ s/\W+/_/g ;
	 $r->add_label( $tag ) ;
      }

debug "vcp: saving off $r ", $r->name, " in PENDING" if debugging $self ;
      push @{$self->{P4_PENDING}}, $r ;
   }

   $self->{P4_PREV_CHANGE_ID} = $r->change_id ;
   $self->{P4_PREV_COMMENT} = $r->comment ;
}


sub handle_footer {
   my VCP::Dest::p4 $self = shift ;

   $self->submit
       if ( $self->{P4_PENDING} && @{$self->{P4_PENDING}} )
          || $self->{P4_DELETES_PENDING} ;
   $self->SUPER::handle_footer ;
}


sub submit {
   my VCP::Dest::p4 $self = shift ;

   my %pending_labels ;
   my %comments ;
   my $max_time ;

   if ( @{$self->{P4_PENDING}} ) {
      for my $r ( @{$self->{P4_PENDING}} ) {
	 $comments{$r->comment} = $r->name if defined $r->comment ;
	 $max_time = $r->time if ! defined $max_time || $r->time > $max_time ;
	 for my $l ( $r->labels ) {
	    push @{$pending_labels{$l}}, $r->dest_work_path ;
	 }
      }

      if ( defined $max_time ) {
	 my @f = reverse( (localtime $max_time)[0..5] ) ;
	 $f[0] += 1900 ;
	 ++$f[1] ; ## Day of month needs to be 1..12
	 $max_time = sprintf "%04d/%02d/%02d %02d:%02d:%02d", @f ;
      }
      elsif ( debugging $self ) {
         debug "No max_time found" ;
      }
   }

   my $description = join( "\n", keys %comments ) ;
   if ( length $description ) {
      $description =~ s/^/\t/gm ;
      $description .= "\n" if substr $description, -1 eq "\n" ;
   }

   my $change ;
   $self->p4( [ 'change', '-o' ], \$change ) ;

   if ( defined $max_time ) {
      $change =~ s/^Date:.*\r?\n\r/Date:\t$max_time\n/m
	 or $change =~ s/(^Client:)/Date:\t$max_time\n\n$1/m
	 or die "vcp: Couldn't modify change date\n$change" ;
   }

   $change =~ s/^Description:.*\r?\n\r?.*/Description:\n$description/m
      or die "vcp: Couldn't modify change description\n$change" ;
   $self->p4([ 'submit', '-i'], '<', \$change ) ;

   ## Create or add a label spec for each of the labels.  The 'sort' is to
   ## make debugging output more legible.
   ## TODO: Modify RevML to allow label metadata (owner, desc, options)
   ## to be passed through.  Same for user, client, jobs metadata etc.
   ## The assumption is made that most labels will apply to a single change
   ## number, so we do the labelling once per submit.  I don't think that
   ## this will break if it doesn't, but TODO: add more labelling tests.
   for my $l ( sort keys %pending_labels ) {
      my $label_desc ;
      $self->p4( [qw( label -o ), $l], '>', \$label_desc ) ;
      $self->p4( [qw( label -i ) ],    '<', \$label_desc ) ;

      my $pending_labels = join( "\n", @{$pending_labels{$l}} ) . "\n" ;
      $self->p4( [qw( -x - labelsync -a -l ), $l ], "<", \$pending_labels ) ;
   }
   @{$self->{P4_PENDING}} = () ;
   $self->{P4_DELETES_PENDING} = undef ;
}

sub tag {
   my VCP::Dest::p4 $self = shift ;

   my $tag = shift  ;
   $tag =~ s/\W+/_/g ;
   $self->p4( ['tag', $tag, @_] ) ;
}


## Prevent VCP::Plugin from rmtree-ing the workspace we're borrowing
sub DESTROY {
   my VCP::Dest::p4 $self = shift ;

   $self->work_root( undef ) ;
   $self->SUPER::DESTROY ;
}


=back

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
