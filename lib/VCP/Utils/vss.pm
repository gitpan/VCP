package VCP::Utils::vss ;

=head1 NAME

VCP::Utils::vss - utilities for dealing with the vss command

=head1 SYNOPSIS

   use VCP::Utils::vss ;

=head1 DESCRIPTION

A mix-in class providing methods shared by VCP::Source::vss and VCP::Dest::vss,
mostly wrappers for calling the vss command.

=cut

use strict ;

use Carp ;
use File::Spec ;
use File::Temp qw( mktemp ) ;
use VCP::Debug qw( :debug ) ;
use VCP::Logger qw( lg pr_doing pr_done pr_done_failed );
use VCP::Utils qw( empty start_dir ) ;

=head1 METHODS

=item ssdir

The location of the VSS database, if set in either the SSDIR environment
variable or in the source or destination specification.

=cut

sub ssdir {
   my $self = shift;

   defined $self->repo_server
      ? File::Spec->rel2abs(
          $self->repo_server,
          start_dir
      )
      : $ENV{SSDIR};
}

=item ssuser

The location of the VSS database, if set in either the SSUSER environment
variable or in the source or destination specification.

=cut

sub ssuser {
   my $self = shift;

   defined $self->repo_user
      ? $self->repo_user
      : $ENV{SSUSER};
}

=item ss

Calls the vss command with the appropriate vssroot option.

TODO: See if we can use two different users to do vss->vss.  Not sure if VSS
sets the cp and workfold per machine or per user.

=cut

sub ss {
   my $self = shift ;

   my $args = shift ;

   my $cmd = shift @$args;

   my $user = $self->repo_user;
   my @Y_arg;
   push @Y_arg, "-Y$user" unless empty $user;

   local $ENV{SSPWD} = $self->repo_password if defined $self->repo_password;
   local $ENV{SSDIR} = $self->ssdir         if defined $self->repo_server;
   lg "SSDIR=$ENV{SSDIR}";
   my @I_arg;

   push @I_arg, "-I-" unless grep /^-I/, @$args;

   my @O_arg;

   ## Forcing VSS to emit to a file with its -O@foo.txt syntax
   ## prevents it from wrapping at 80 cols.  Sigh.
   my ( $out_ref, $out_fn );
   ## ss ignored -O@ on help command
   if ( $#_ >= 1 && $_[1] && ref $_[1]
      && lc $cmd ne "help"
    ) {
      $out_fn = mktemp(
         File::Spec->catfile( File::Spec->tmpdir, "vcp_vss_XXXX" )
      );
      $out_ref = $_[1];
      $_[1] = undef;
      @O_arg = ( "-O\@$out_fn" );
   }

   my $retrying;

RETRY:

   my $ok = eval {
      $self->run_safely(
         [ "ss", $cmd, @$args, @Y_arg, @I_arg, @O_arg ], @_
      ) ;
      1;
   };

   if ( !$ok ) {
      if ( ! $retrying && $@ eq "UNDOCHECKOUT\n" ) {
         $self->run_safely(
            [
               "ss", "UndoCheckout", $args->[0], @Y_arg, "-I-Y", "-G-"
            ],
            {
               stderr_filter => qr{
                  ^(?:
                     \$/.*
                     |File.*not\sfound.*
                     |Continue.*
                     |.*has\schanged.*
                  )\r?\n
               }xm,
            }
         );
         $retrying = 1;
         goto RETRY;
      }
      else {
         die $@;
      }
   }

   if ( $out_ref ) {
      local *F;
      open F, "<$out_fn" or die "$!: $out_fn for SS.EXE stdout\n";
      if ( ref $out_ref eq "SCALAR" ) {
         $$out_ref = join "", <F>;
      }
      else {
         $out_ref->( \*F );
      }
      close F;
      unlink $out_fn or warn "$! deletign '$out_fn'\n";
   }

   return;
}

=item throw_undocheckout_and_retry

This is called from the stderr_filter for SS.EXE commands that 
emit a "File ... is checked out by ..." message so that VCP can
issue an undocheckout command and retry, like the Recover command.

=cut

sub throw_undocheckout_and_retry {
   my $self = shift;
   die "UNDOCHECKOUT\n";
}

=item ss_cp

    $self->ss_cp( $project );

Changes to a new current project, does not change projects if this is
the current project.

=cut

sub ss_cp {
   my $self = shift;
   my ( $new_project ) = @_;

   return
      if defined $self->{VSS_CURRENT_PROJECT}
         && $new_project eq $self->{VSS_CURRENT_PROJECT};
   $self->ss( [ "cp", "\$/$new_project" ] );
   $self->{VSS_CURRENT_PROJECT} = $new_project;
}


=item parse_vss_repo_spec

parse repo_spec by calling parse_repo_spec, then
set the repo_id.

=cut

sub parse_vss_repo_spec {
   my $self = shift ;
   my ( $spec ) = @_ ;

   $self->parse_repo_spec( $spec ) ;

   $self->repo_id( "vss:" . $self->repo_server );
};



=item create_vss_workspace

Creates a temporary directory.

=cut

sub create_vss_workspace {
   my $self = shift ;

   ## establish_workspace in a directory named "co" for "checkout". This is
   ## so that VCP::Source::vss can use a different directory to contain
   ## the revs, since all the revs need to be kept around until the VCP::Dest
   ## is through with them.
   my $workspace = $self->tmp_dir;

   $self->mkdir( $workspace );
}


=item get_vss_file_list

Retrieves a list of all files and directories under a particular
path.  We need this so we can tell what dirs and files need to be added.

=cut

sub _scan_for_files {
   my $self = shift;
   my ( $path, $type, $filelist ) = @_;

   $path = $self->repo_filespec
      unless defined $path;
   $path =~ s{^\$?[\\/]*}{/};

   my $path_re = $self->compile_path_re( $path );

   debug "file scan re: $path_re" if debugging ;
   my $cur_project;
   for ( @$filelist ) {
      pr_doing;
      if ( /^(|No items found.*|\d+ item.*s.*)$/i ) {
         undef $cur_project;
         next;
      }

      if ( m{^\$(\/.*):} ) {
         $cur_project = $1;
         ## Catch all project entries, because we may be importing
         ## to a non-existant project inside a project that exists.
         if ( length $cur_project ) {
            ## Add a slash so a preexisting dest project is found.
#            if ( "$cur_project/" =~ $path_re ) {
               my $p = $cur_project;
#               ## Catch all parent projects.  This prevents us from
#               ## creating more than need be.
#               do {
               my @state = $self->files->get( [ $p ] );
               $self->files->set( [ $p ], @state, "project" )
                  if ! grep $_ eq "project", @state;
                   
#                  $self->{VSS_FILES}->{$p} = "project";
#               } while $p =~ s{/[^/]*}{} && length $p;
#            }
            $cur_project .= "/";
         }
         next;
      }

      if ( m{^\$(.*)} ) {
         confess "undefined \$cur_project" unless defined $cur_project;
         ## A subproject.  note here for completeness' sake; it should also
         ## occur later in a $/foo: section of it's own.
         my $p = "$cur_project$1";
         if ( $p =~ $path_re ) {
            my @state = $self->files->get( [ $p ] );
            $self->files->set( [ $p ], @state, "project" )
               if ! grep $_ eq "project", @state;
         }
         next;
      }

      if ( "$cur_project$_" =~ $path_re ) {
         my $p = "$cur_project$_";
         my @state = $self->files->get( [ $p ] );
         ## In VSS, a file may be both deleted and not deleted.  So
         ## we always append the type to a list of types for files.
         $self->files->set( [ $p ], @state, $type )
            if ! grep $_ eq $type, @state;
         next;
      }
   }

}

sub get_vss_file_list {
   my $self = shift;
   my ( $path ) = @_;

   ## Sigh.  I tried passing in $path to the Dir -D command and
   ## ss.exe whines because $path is rarely a deleted path RATHER
   ## THAN JUST GIVING ME ALL DELETED FILES UNDER $path!!!
   ## So, we get all the output and filter it for $path/... ourselves.
   ## This does have the advantage that we can use full wildcards in
   ## $path.

   $self->ss_cp( "" );

   pr_doing "scanning VSS for files '$path': ";

   $self->_scan_for_files( $path, "file",
      [ do {
         my $filelist;
         $self->ss( [qw( Dir -R )], undef, \$filelist );
         map { s/[\r\n]//g; $_ } split /^/m, $filelist;
      } ]
   );

   $self->_scan_for_files( $path, "deleted",
      [ do {
         my $filelist;
         $self->ss( [qw( Dir -R -D)], undef, \$filelist );
         map { s/[\r\n]//g; $_ } split /^/m, $filelist;
      } ]
   );

   pr_done "found " . $self->vss_files, " files";
}

=item vss_files

    @files = $self->vss_files;

returns a list of all files (not projects) that get_vss_file_list()
loaded.

=cut

sub vss_files {
   my $self = shift;

   ## TODO: allow a pattern.  This would let us handle filespecs like
   ## /a*/b*
   map $_->[0],
      grep 
         grep( $_ ne "project", $self->files->get( $_ ) ),
         $self->files->keys;
}

## TODO: DEPRECATED.  delete this sub once it's not needed by VCP::Source::vss.
sub vss_file {
   my $self = shift;
   my ( $path, $value ) = @_;

warn caller;

   confess unless defined $path;

   for ( $path ) {
      s{\\}{/}g;
      s{\/+$}{};
      s{\$+}{}g;
      s{^/+}{};
   }

   if ( @_ > 1 ) {
      $self->{VSS_FILES}->{$path} = $value;
      if ( $value ) {
         my $p = $path;
         while () {
            $p =~ s{(^|/)+[^/]+$}{};
            last unless length $p || $self->{VSS_FILES}->{$p};
            $self->{VSS_FILES}->{$p} = "project";
         }
      }
   }

   return exists $self->{VSS_FILES}->{$path} && $self->{VSS_FILES}->{$path};
}

=item vss_file_is_deleted

Returns 1 if the file is a deleted file.

NOTE: in VSS a file may be deleted and not deleted at the same time!
Thanks to Dave Foglesong for pointing this out.

=cut

sub vss_file_is_deleted {
   my $self = shift;
   return grep $_ eq "deleted", $self->files->get( [ @_ ] );
}

=item vss_file_is_active

Returns 1 if the file is an active (undeleted) file.

NOTE: in VSS a file may be deleted and active at the same time!
Thanks to Dave Foglesong for pointing this out.

=cut

sub vss_file_is_active {
   my $self = shift;
   return grep $_ ne "deleted", $self->files->get( [ @_ ] );
}

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;

1;
