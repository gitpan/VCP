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
use VCP::Dest ;
use VCP::Rev ;

use base 'VCP::Dest' ;
use fields (
   'CVS_CVSROOT',    ## What to pass using -d.
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

   my $parsed_spec = $self->parse_repo_spec( $spec ) ;
   my $files = $parsed_spec->{FILES} ;

   $self->cvsroot( $parsed_spec->{SERVER} ) ;

   my $rev_root ;
   GetOptions(
      'r|rev-root' => \$rev_root,
   ) or $self->usage_and_exit ;

   if ( defined $rev_root ) {
      $self->rev_root( $rev_root ) ;
   }
   elsif ( defined $files && length $files ) {
      $self->deduce_rev_root( $files ) ;
   }

   ## Make sure the cvs command is available
   $self->command( 'cvs', '-Q', '-z9' ) ;
   $self->mkdir( $self->work_path ) ;
   $self->command_stderr_filter(
      qr{^(?:cvs (?:server|add|remove): use 'cvs commit' to.*)\n}
   ) ;

   return $self ;
}


sub create_workspace {
   my VCP::Dest::cvs $self = shift ;

   confess "Can't create_workspace twice" unless $self->none_seen ;

   ## establish_workspace
   $self->rev_root( $self->header->{rev_root} )
      unless defined $self->rev_root ;
   $self->command_chdir( $self->work_path ) ;
   $self->cvs( [ 'checkout', $self->rev_root ] ) ;
   $self->work_root( $self->work_path( $self->rev_root ) ) ;
   $self->command_chdir( $self->work_path ) ;
}


sub backfill {
   my VCP::Dest::cvs $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

   $self->create_workspace if $self->none_seen ;

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


sub cvs {
   my VCP::Dest::cvs $self = shift ;

   unshift @{$_[0]}, $self->cvsroot_cvs_option ;

   return $self->SUPER::cvs( @_ ) ;
}


sub cvsroot {
   my VCP::Dest::cvs $self = shift ;
   $self->{CVS_CVSROOT} = shift if @_ ;
   return $self->{CVS_CVSROOT} ;
}


sub cvsroot_cvs_option {
   my VCP::Dest::cvs $self = shift ;
   return defined $self->cvsroot ? "-d" . $self->cvsroot : (),
}



sub handle_rev {
   my VCP::Dest::cvs $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;

   $self->create_workspace if $self->none_seen ;
   
   my VCP::Rev $saw = $self->seen( $r ) ;

   my $fn = $r->name ;
   my $work_path = $self->work_path( $fn ) ;

   if ( $r->action eq 'delete' ) {
      unlink $work_path || die "$! unlinking $work_path" ;
      $self->cvs( ['remove', $fn] ) ;
      $self->cvs( ['commit', '-m', $r->comment, $fn] ) ;
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
	       ## Warn: MacOS danger here: "" is like Unix's "..".  Shouldn;t
	       ## ever be a problem, though.
	       if ( length $base_dir && ! -d $base_dir ) {
	          mkdir $base_dir, 0770 or die "vcp: $! making '$base_dir'" ;
		  debug "vcp: mkdired '$base_dir' 0770" if debugging $self ;
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
      $self->tag( "r_" . $r->rev_id, $fn ) ;
      $self->tag( "ch_" . $r->change_id, $fn )
	 if defined $r->change_id ;

      $self->tag( $_, $fn ) for $r->labels ;
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

This will be licensed under a suitable license at a future date.  Until
then, you may only use this for evaluation purposes.  Besides which, it's
in an early alpha state, so you shouldn't depend on it anyway.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
