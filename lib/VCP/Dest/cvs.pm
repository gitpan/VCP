package VCP::Dest::cvs ;

=head1 NAME

VCP::Dest::cvs - cvs destination driver

=head1 SYNOPSIS

   vcp <source> cvs:module
   vcp <source> cvs:CVSROOT:module

where module is a module or directory that already exists within CVS.

This destination driver will check out the indicated destination in
a temporary directory and use it to add, delete, and alter files.

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
use VCP::Rev ;

use base qw( VCP::Dest VCP::Utils::cvs ) ;
use fields (
   'CVS_CHANGE_ID',  ## The current change_id in the rev_meta sequence, if any
   'CVS_LAST_MOD_TIME',  ## A HASH keyed on working files of the mod_times of
                     ## the previous revisions of those files.  This is used
		     ## to make sure that new revision get a different mod_time
		     ## so that CVS never thinks that a new revision hasn't
		     ## changed just because the VCP::Source happened to create
		     ## two files with the same mod_time.
   'CVS_PENDING_COMMAND', ## "add" or "edit"
   'CVS_PENDING',    ## Revs to be committed
## These next fields are used to detect changes between revs that cause a
## commit. Commits are batched for efficiency's sake.
   'CVS_PREV_CHANGE_ID', ## Change ID of previous rev
   'CVS_PREV_COMMENT',   ## Revs to be committed
) ;

## Optimization note: The slowest thing is the call to "cvs commit" when
## something's been added or altered.  After all the changed files have
## been checked in by CVS, there's a huge pause (at least with a CVSROOT
## on the local filesystem).  So, we issue "cvs add" whenever we need to,
## but we queue up the files until a non-add is seem.  Same for when
## a file is edited.  This preserves the order of the files, without causing
## lots of commits.  Note that we commit before each delete to make sure
## that the order of adds/edits and deletes is maintained.

=item new

Creates a new instance of a VCP::Dest::cvs.  Contacts the cvsd using the cvs
command and gets some initial information ('cvs info' and 'cvs labels').

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Dest::cvs $self = $class->SUPER::new( @_ ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_repo_spec( $spec ) ;
   $self->deduce_rev_root( $self->repo_filespec ) ;

   {
      local *ARGV = $options ;
      GetOptions(
         "NoFreakinOptionsAllowed" => \undef,
      )
	 or $self->usage_and_exit ;
   }

   $self->command_stderr_filter(
      qr{^(?:cvs (?:server|add|remove): (re-adding|use 'cvs commit' to).*)\n}
   ) ;

   return $self ;
}


sub handle_header {
   my VCP::Dest::cvs $self = shift ;

   debug "vcp: first rev" if debugging $self ;
   $self->rev_root( $self->header->{rev_root} )
      unless defined $self->rev_root ;

   $self->create_cvs_workspace ;

   $self->{CVS_PENDING_COMMAND} = "" ;
   $self->{CVS_PENDING}         = [] ;
   $self->{CVS_PREV_COMMENT}    = undef ;
   $self->{CVS_PREV_CHANGE_ID}  = undef ;

   $self->SUPER::handle_header( @_ ) ;
}


sub checkout_file {
   my VCP::Dest::cvs $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

   debug "vcp: $r checking out ", $r->as_string, " from cvs dest repo"
      if debugging $self ;

   my $fn = $r->name ;
   my $work_path = $self->work_path( $fn ) ;
   debug "vcp: work_path '$work_path'" if debugging $self ;

   my $saw = $self->seen( $r ) ;

   die "Can't backfill already seen file '", $r->name, "'" if $saw ;

   my ( undef, $work_dir ) = fileparse( $work_path ) ;
   $self->mkpdir( $work_path ) unless -d $work_dir ;

   my $tag = "r_" . $r->rev_id ;
   $tag =~ s/\W+/_/g ;

   ## Ok, the tricky part: we need to use a tag, but we don't want it
   ## to be sticky, or we get an error the next time we commit this
   ## file, since the tag is not likely to be a branch revision.
   ## Apparently the way to do this is to print it to stdout on update
   ## (or checkout, but we used update so it works with a $fn relative
   ## to the cwd, ie a $fn with no module name first).
   $self->cvs(
      [ qw( update -d -p ), -r => $tag, $fn ],
      '>', $work_path
   ) ;
   die "'$work_path' not created by cvs checkout" unless -e $work_path ;

   return $work_path ;
}


sub backfill {
   my VCP::Dest::cvs $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

   $r->work_path( $self->checkout_file( $r ) ) ;

   return 1 ;
}

my $old_r ;
sub handle_rev {
   my VCP::Dest::cvs $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;

   if ( 
      ( @{$self->{CVS_PENDING}} )#|| $self->{CVS_DELETES_PENDING} )
      && (
         @{$self->{CVS_PENDING}} > 25  ## Limit command line length
	 || (
	    defined $r->change_id && defined $self->{CVS_PREV_CHANGE_ID}
	    &&      $r->change_id ne         $self->{CVS_PREV_CHANGE_ID}
	    && ( debugging( $self ) ? debug "vcp: change_id changed" : 1 )
	 )
	 || (
	    defined $r->comment && defined $self->{CVS_PREV_COMMENT}
	    &&      $r->comment ne         $self->{CVS_PREV_COMMENT}
	    && ( debugging( $self ) ? debug "vcp: comment changed" : 1 )
	 )
	 || (
	    grep( $r->name eq $_->name, @{$self->{CVS_PENDING}} )
	    && ( debugging( $self ) ? debug "vcp: name repeated" : 1 )
	 )
      )
   ) {
      debug "vcp: committing on general principles" if debugging $self ;
      $self->commit ;
   }

   $self->compare_base_revs( $r )
      if $r->is_base_rev && defined $r->work_path ;

   ## Don't save the reference.  This forces the DESTROY to happen here,
   ## if possible.  TODO: Keep VCP::Rev from deleting files prematurely.
   my $saw = !!$self->seen( $r ) ;

   return if $r->is_base_rev ;

   my $fn = $r->name ;
   my $work_path = $self->work_path( $fn ) ;

   if ( $r->action eq 'delete' ) {
      $self->commit ;
      unlink $work_path || die "$! unlinking $work_path" ;
      $self->cvs( ['remove', $fn] ) ;
      ## Do this commit by hand since there are no CVS_PENDING revs, which
      ## means $self->commit will not work. It's relatively fast, too.
      $self->cvs( ['commit', '-m', $r->comment || '', $fn] ) ;
      $self->delete_seen( $r ) ;
   }
   else {
      ## TODO: Move this in to commit().
      {
	 my ( $vol, $work_dir, undef ) = File::Spec->splitpath( $work_path ) ;
	 unless ( -d $work_dir ) {
	    my @dirs = File::Spec->splitdir( $work_dir ) ;
	    my $this_dir = shift @dirs  ;
	    my $base_dir = File::Spec->catpath( $vol, $this_dir, "" ) ;
	    do {
	       ## Warn: MacOS danger here: "" is like Unix's "..".  Shouldn't
	       ## ever be a problem, we hope.
	       if ( length $base_dir && ! -d $base_dir ) {
	          $self->mkdir( $base_dir ) ;
		  ## We dont' queue these to a PENDING because these
		  ## should be pretty rare after the first checkin.  Could
		  ## have a modal CVS_PENDING with modes like "add", "remove",
		  ## etc. and commit whenever the mode's about to change,
		  ## I guess.
		  $self->cvs( ["add", $base_dir] ) ;
	       }
	       $this_dir = shift @dirs  ;
	       $base_dir = File::Spec->catdir( $base_dir, $this_dir ) ;
	    } while @dirs ;
	 }
      }
      if ( -e $work_path ) {
	 unlink $work_path or die "$! unlinking $work_path" ;
      }

      debug "vcp: linking ", $r->work_path, " to $work_path"
         if debugging $self ;

      ## TODO: Don't assume same filesystem or working link().
      link $r->work_path, $work_path
	 or die "$! linking '", $r->work_path, "' -> $work_path" ;

      if ( defined $r->mod_time ) {
	 utime $r->mod_time, $r->mod_time, $work_path
	    or die "$! changing times on $work_path" ;
      }

      my ( $acc_time, $mod_time ) = (stat( $work_path ))[8,9] ;
      if ( ( $self->{CVS_LAST_MOD_TIME}->{$work_path} || 0 ) == $mod_time ) {
         ++$mod_time ;
	 debug "vcp: tweaking mod_time on '$work_path'" if debugging $self ;
	 utime $acc_time, $mod_time, $work_path
	    or die "$! changing times on $work_path" ;
      }
      $self->{CVS_LAST_MOD_TIME}->{$work_path} = $mod_time ;

      $r->dest_work_path( $fn ) ;

      if ( ! $saw ) {
	 ## New file.
	 my @bin_opts = $r->type ne "text" ? "-kb" : () ;
	 $self->commit if $self->{CVS_PENDING_COMMAND} ne "add" ;
	 $self->cvs( [ "add", @bin_opts, "-m", $r->comment || '', $fn ] ) ;
	 $self->{CVS_PENDING_COMMAND} = "add" ;
      }
      else {
	 $self->commit if $self->{CVS_PENDING_COMMAND} ne "edit" ;
	 $self->{CVS_PENDING_COMMAND} = "edit" ;
      }

#      ## TODO: batch the commits when the comment changes or we see a
#      ## new rev for a file with a pending commit..
#      $self->cvs( ['commit', '-m', $r->comment || '', $fn] ) ;
#
debug "$r pushing ", $r->dest_work_path if debugging $self ;
      push @{$self->{CVS_PENDING}}, $r ;
  }

   $self->{CVS_PREV_CHANGE_ID} = $r->change_id ;
   $self->{CVS_PREV_COMMENT} = $r->comment ;
}


sub handle_footer {
   my VCP::Dest::cvs $self = shift ;

   $self->commit
       if $self->{CVS_PENDING} && @{$self->{CVS_PENDING}} ;#|| $self->{CVS_DELETES_PENDING} ;
   $self->SUPER::handle_footer ;
}


sub commit {
   my VCP::Dest::cvs $self = shift ;

   return unless @{$self->{CVS_PENDING}} ;

   ## All comments should be the same, since we alway commit when the 
   ## comment changes.
   my $comment = $self->{CVS_PENDING}->[0]->comment || '' ;

   ## @names was originally to try to convince cvs to commit things in the
   ## preferred order.  No go: cvs chooses some order I can't fathom without
   ## reading it's source code.  I'm leaving this in for now to keep cvs
   ## from having to scan the working dirs for changes, which may or may
   ## not be happening now (need to check at some point).
   my @names = map $_->dest_work_path, @{$self->{CVS_PENDING}} ;

   $self->cvs( ['commit', '-m', $comment, @names ] ) ;

   for my $r ( @{$self->{CVS_PENDING}} ) {
      ## TODO: Don't rtag it with r_ if it gets the same rev number from the
      ## commit.
      ## TODO: Batch files in to the rtag command, esp. for change number tags,
      ## for performance's sake.
      ## TODO: batch tags, too.
      my @tags = map {
         s/^([^a-zA-Z])/tag_$1/ ;
	 s/\W/_/g ;
	 $_ ;
      }(
	 defined $r->rev_id    ? "r_" . $r->rev_id     : (),
         defined $r->change_id ? "ch_" . $r->change_id : (),
	 $r->labels,
      ) ;

      $self->tag( $_, $r->dest_work_path ) for @tags ;
      ## TODO: Provide command line options for user-defined tag prefixes
    }

   @{$self->{CVS_PENDING}} = () ;
   $self->{CVS_PENDING_COMMAND} = "" ;
}


sub tag {
   my VCP::Dest::cvs $self = shift ;

   my $tag = shift  ;
   $tag =~ s/\W+/_/g ;
   $self->cvs( ['tag', $tag, @_] ) ;
}


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
