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
) ;

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

   my $rev_root ;
   GetOptions( 'NoBloOdyOptTionsWanTErRoRMesSaGe' => \"" )
      or $self->usage_and_exit ;

   $self->command_stderr_filter(
      qr{^(?:cvs (?:server|add|remove): (re-adding|use 'cvs commit' to).*)\n}
   ) ;

   return $self ;
}


sub backfill {
   my VCP::Dest::cvs $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

   $self->create_cvs_workspace if $self->none_seen ;

   #my $fn = join( '', $self->rev_root, "/", $r->name ) ;
   my $fn = $r->name ;
   my $work_path = $self->work_path( $fn ) ;
   debug "vcp: backfilling '$fn', rev ", $r->rev_id if debugging $self ;
   debug "vcp: work_path '$work_path'" if debugging $self ;

   my VCP::Rev $saw = $self->seen( $r ) ;

   die "Can't backfill already seen file '", $r->name, "'" if $saw ;

   my ( undef, $work_dir ) = fileparse( $work_path ) ;
   unless ( -d $work_dir ) {
      $self->mkpdir( $work_path ) ;
      ( undef, $work_dir ) = fileparse( $fn ) ;
   }

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
   die "'$work_path' not created in backfill" unless -e $work_path ;

   $r->work_path( $work_path ) ;

   return 1 ;
}


sub handle_rev {
   my VCP::Dest::cvs $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;

   $self->rev_root( $self->header->{rev_root} )
      unless defined $self->rev_root ;

   $self->create_cvs_workspace if $self->none_seen ;
   
   my VCP::Rev $saw = $self->seen( $r ) ;

   my $fn = $r->name ;
   my $work_path = $self->work_path( $fn ) ;

   if ( $r->action eq 'delete' ) {
      unlink $work_path || die "$! unlinking $work_path" ;
      $self->cvs( ['remove', $fn] ) ;
      $self->cvs( ['commit', '-m', $r->comment, $fn] ) ;
      $self->delete_seen( $r ) ;
   }
   else {
      ## TODO: Don't assume same filesystem or working link().
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

      if ( ! $saw ) {
	 ## New file.
	 my @bin_opts = $r->type ne "text" ? "-kb" : () ;
	 $self->cvs( [ "add", @bin_opts, "-m", $r->comment, $fn ] ) ;
      }

      ## TODO: batch the commits when the comment changes or we see a
      ## new rev for a file with a pending commit..
      $self->cvs( ['commit', '-m', $r->comment, $fn] ) ;

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

      $self->tag( $_, $fn ) for @tags ;
      ## TODO: Provide command line options for user-defined tag prefixes
   }
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
