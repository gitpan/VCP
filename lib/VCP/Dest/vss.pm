package VCP::Dest::vss ;

=head1 NAME

VCP::Dest::vss - vss destination driver

=head1 SYNOPSIS

   vcp <source> vss:module
   vcp <source> vss:SSDIR:module
   vcp <source> vss:SSUSER@SSDIR:module
   vcp <source> vss:SSUSER:PASSWORD@SSDIR:module

where module is a module or directory that already exists within VSS.

SSDIR is the value to set the SSDIR environment variable to before
running SS.EXE and is a path to the sourcesafe directory.

This destination driver will check out the indicated destination in
a temporary directory and use it to add, delete, and alter files.

=head1 DESCRIPTION

B<Experimental>.  See L<NOTES|/NOTES> for details.

This driver allows L<vcp|vcp> to insert revisions in to a VSS
repository.  There are no options at this time.

=head1 OPTIONS

=over

=item --dont-recover-deleted-files

VSS, at least as of V6, does not allow you to repeatedly delete and 
recover a file.  So VCP::Dest::vss normally forces VSS to recover
a deleted file when a new revision shows up, which is close as it
can get to CVS or p4 semantics.

However, when coming from a VSS repository, it's ok to leave deleted files
lie.  Use this option in that case.

=item --mkss-ssdir

Make a new VSS database in directory named in the SSDIR portion of the
vss: specification.  The directory must be nonexistant or empty.
The database is created using the MKSS, DDCONV, and DDUPD commands.

NOTE: you need to use the SSUSER "Admin" to use this option (or tell
me how to add users from the command line).

=item --delete-ssdir

This option causes the --mkss option to delete the SSDIR if it exists
(including any contents).  THIS IS DANGEROUS AND SHOULD ONLY BE USED
IN TEST ENVIRONMENTS.

=back

=cut

$VERSION = 1 ;

@ISA = qw( VCP::Dest VCP::Utils::vss );

use strict ;
use Carp ;
use File::Basename ;
use File::Path ;
use File::Spec ;
use File::Spec::Unix ;
use VCP::Debug ':debug' ;
use VCP::Dest;
use VCP::Logger qw( pr pr_doing );
use VCP::Rev ;
use VCP::Utils qw( empty );
use VCP::Utils::vss;

#use base qw( VCP::Dest VCP::Utils::vss ) ;
#use fields (
#   'VSS_CURRENT_PROJECT', ## The last ss cp we issued.
#   'VSS_DELETE_SSDIR',    ## pass --delete-ssdir from new() to init()
#   'VSS_DONT_RECOVER',    ## Set if we should not recover deleted files.
#   'VSS_FILES',           ## HASH of all VSS files, managed by VCP::Utils::vss
#   'VSS_MKSS_SSDIR',      ## pass --mkss-ssdir from new() to init()
#) ;

## Optimization note: The slowest thing is the call to "vss commit" when
## something's been added or altered.  After all the changed files have
## been checked in by VSS, there's a huge pause (at least with a VSSROOT
## on the local filesystem).  So, we issue "vss add" whenever we need to,
## but we queue up the files until a non-add is seem.  Same for when
## a file is edited.  This preserves the order of the files, without causing
## lots of commits.  Note that we commit before each delete to make sure
## that the order of adds/edits and deletes is maintained.

#=item new
#
#Creates a new instance of a VCP::Dest::vss.  Contacts the vssd using the vss
#command and gets some initial information ('vss info' and 'vss labels').
#
#=cut

sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_vss_repo_spec( $spec )
      unless empty $spec;

   $self->parse_options( $options );

   return $self ;
}


sub options_spec {
   my $self = shift ;
   return (
      $self->SUPER::options_spec,
      "delete-ssdir"               => \$self->{VSS_DELETE_SSDIR},
      "dont-recover-deleted-files" => \$self->{VSS_DONT_RECOVER},
      "mkss-ssdir"                 => \$self->{VSS_MKSS_SSDIR},
   );
}


sub init {
   my $self = shift ;

   ## Set default repo_id.
   $self->repo_id( "vss:" . $self->repo_server )
      if empty $self->repo_id && ! empty $self->repo_server ;

   $self->deduce_rev_root( $self->repo_filespec ) ;
   if ( $self->{VSS_MKSS_SSDIR} ) {
      if ( $self->{VSS_DELETE_SSDIR} ) {
         $self->rev_map->delete_db;
         $self->head_revs->delete_db;
         $self->files->delete_db;
      }
      $self->mkss_ssdir( $self->{VSS_DELETE_SSDIR} );
   }
   else {
      pr "ignoring --delete-ssdir, which is only useful with --mkss-ssdir\n"
         if $self->{VSS_DELETE_SSDIR};
   }


   $self->rev_map->open_db;
   $self->head_revs->open_db;
   $self->files->open_db;

   ## We need to know about the hierarchy under the target path.
   my $dest_path = $self->repo_filespec;
   $dest_path =~ s{([\\/]|[\\/](\.\.\.|\*\*))?\z}{/...};
   $self->get_vss_file_list( $dest_path );
}


sub sort_filters {
   shift->require_change_id_sort( @_ );
}


sub mkss_ssdir {
   my $self = shift;
   my ( $delete_ssdir ) = @_;

   my $ssdir = $self->ssdir;

   die "must set SSDIR to use --mkss option\n"
      if empty $ssdir;

   my $ssuser = $self->ssuser;
   die "must specify user 'Admin' to use --mkss option\n"
      if empty $ssuser;

   ## I wish I knew how to add users from the command line...
   die "must specify user 'Admin', not '$ssuser' with --mkss option\n"
      unless lc $ssuser eq "admin";

   my @files;
   @files =  glob "$ssdir/*" if -d $ssdir;

   if ( @files && $delete_ssdir ) {
      require File::Path;
      rmtree [ @files ];
      @files =  glob "$ssdir/*";
   }

   die "cannot --mkss on non-empty SSDIR $ssdir\n"
      if @files;

   my $data_dir = File::Spec->catdir( $ssdir, "data" );
   $self->mkdir( $data_dir ) unless -e $data_dir;

   ## TODO: see how the mkss.exe recipe changes in other versions of
   ## VSS.  This is the documented approach for VSS 6.0.
   $self->run_safely( [ "mkss.exe",   $data_dir ] );
   $self->run_safely( [ "ddconv.exe", $data_dir ] );

   ## ddupd.exe is not critical so we defensively continue on failure.
   eval { $self->run_safely( [ "ddupd.exe", $data_dir  ] ) };

   ##
   ## Write out VSS' config files.
   ##
   my $srcsafe_ini_fn  = File::Spec->catfile( $ssdir, "srcsafe.ini" );
   my $users_txt_fn    = File::Spec->catfile( $ssdir, "users.txt" );
#   my $ss_ini_fn       = File::Spec->catfile( $ssdir, "users", $ssuser, "ss.ini" );
   my $admin_ss_ini_fn = File::Spec->catfile( $ssdir, "users", "Admin", "ss.ini" );

   pr "creating $srcsafe_ini_fn";
   $self->mkpdir( $srcsafe_ini_fn ) unless -e $data_dir;

   open SRCSAFE_INI, ">$srcsafe_ini_fn"
      or die "$! creating $srcsafe_ini_fn\n";
   my $t = localtime;
   print SRCSAFE_INI <<SRCSAFE_INI_END or die "$! writing $srcsafe_ini_fn\n";
; $srcsafe_ini_fn created by $0 on $t
;
; Copied from the example given in VSS 6.0's help document.
;
; Three of these variables -- Data_Path, Users_Path, and Users_Txt -- must
; be in SRCSAFE.INI. Any other variable here can be overridden in SS.INI.
; Similarly, any SS.INI variable can be placed in SRCSAFE.INI to set a
; system "default," which individual users can still override in SS.INI.

; The two important paths used by SourceSafe.
Data_Path = data
Temp_Path = temp

; This tells admin where to put personal directories for new users.
Users_Path = users

; From this, find users.txt; from that, in turn, find SS.INI for a user.
Users_Txt = users.txt

; The following line contains common file groupings.
File_Types = Visual Basic (*.bas;*.cls;*.frm;*.frx;*.res;*.vbp;*.mak), Visual C++ (*.cpp;*.c;*.hpp;*.h;*.rc;*.mak), Visual FoxPro (*.h;*.pjt;*.pjx;*.prg;*.frx;*.frt;*.scx;*.sct;*.vcx;*.vct;*.lbx;*.lbt;*.qpr;*.mnx;*.mnt), Visual Test (*.mst;*.inc)
Img_File = HTMLFILE.GIF
Img_Folder = FOLDER.GIF
[\$/Features]
[\$/MyProject]
SRCSAFE_INI_END
   close SRCSAFE_INI;

   pr "creating $users_txt_fn";
   $self->mkpdir( $users_txt_fn );
   open USERS_TXT, ">$users_txt_fn" or die "$! creating $users_txt_fn\n";
   print USERS_TXT <<USERS_TXT_END or die "$! writing $users_txt_fn\n";
Admin=$admin_ss_ini_fn
;$ssuser=\$ss_ini_fn
USERS_TXT_END
   close USERS_TXT;

#   pr "creating $ss_ini_fn";
#   $self->mkpdir( $ss_ini_fn );
#   open SS_INI, ">$ss_ini_fn" or die "$! creating $ss_ini_fn\n";
#   print SS_INI <<SS_INI_END  or die "$! writing $ss_ini_fn\n";
#; $ss_ini_fn created by $0 on $t
#;
#; Copied from the example given in VSS 6.0's help document.
#;
#; This file contains all the variables that "customize" Visual SourceSafe
#; to your particular needs. The SS.INI variables are documented in
#; Online Help. Only a few of them are placed in this file by default.
#
#; C programmers should remove the semicolon from the following line, to
#; uncomment it. Other programmers REPLACE the line with different masks.
#; Relevant_Masks = *.c, *.h, *., *.asm
#
#; The following line prevents you from being asked for a check out
#; comment.
#Checkout_Comment = -
#
#Project = \$/Samples
#Sort_Order = Date
#[\$/Features]
#[\$/MyProject]
#SS_INI_END

   pr "creating $admin_ss_ini_fn";
   $self->mkpdir( $admin_ss_ini_fn );
   open SS_INI, ">$admin_ss_ini_fn" or die "$! creating $admin_ss_ini_fn\n";
   print SS_INI <<SS_INI_END  or die "$! writing $admin_ss_ini_fn\n";
; $admin_ss_ini_fn created by $0 on $t
;
; Copied from the example given in VSS 6.0's help document.
;
; This file contains all the variables that "customize" Visual SourceSafe
; to your particular needs. The SS.INI variables are documented in
; Online Help. Only a few of them are placed in this file by default.

; C programmers should remove the semicolon from the following line, to
; uncomment it. Other programmers REPLACE the line with different masks.
; Relevant_Masks = *.c, *.h, *., *.asm

; The following line prevents you from being asked for a check out
; comment.
Checkout_Comment = -

Project = \$/Samples
Sort_Order = Date
[\$/Features]
[\$/MyProject]
SS_INI_END
   close SS_INI;
}


sub handle_header {
   my $self = shift ;

   $self->rev_root( $self->header->{rev_root} )
      unless defined $self->rev_root ;

   $self->create_vss_workspace ;

   $self->SUPER::handle_header( @_ ) ;
}


sub checkout_file {
   my $self = shift ;
   my $r ;
   ( $r ) = @_ ;

   debug "checking out ", $r->as_string, " from vss dest repo"
      if debugging ;

   my $denorm_name = $self->denormalize_name( $r->name ) ;
   my $work_path = $self->work_path( "co", $denorm_name ) ;
   debug "work_path '$work_path'" if debugging ;

   my ( $file, $work_dir ) = fileparse( $work_path ) ;
   $self->mkpdir( $work_path ) unless -d $work_dir ;
   $work_dir =~ s{[\\/]+$}{}g;

   my ( undef, $dirs ) = fileparse( $denorm_name );

   ## Set current project.
   ## TODO: only change projects when necessary by remembering
   ## the last cp we did.
   $self->ss_cp( $dirs );

   my $version = ($self->rev_map->get( [ $r->source_repo_id, $r->id ] ))[1];
   my @v = empty $version ? () : ( "-V$version" );

   ## This -GN is a hack; it's here because the test suite uses
   ## Unix lineends and the checksums require it.  This should be
   ## a command-line option that the test suite enables.
   $self->ss( [ "Get", $file, @v, "-GL$work_dir", "-GN" ] );
   die "'$work_path' not created by vss checkout" unless -e $work_path ;

   return $work_path ;
}


sub handle_rev {
   my $self = shift ;

   my $r ;
   ( $r ) = @_ ;

   debug "got ", $r->as_string if debugging;

   ## We're not too concerned with foo->vss conversion performance
   ## and the DOS command line is a funky thing to try passing
   ## lots of parameters on, so we do each rev as it is received
   ## instead of batching them by change number.

   if ( $r->is_base_rev ) {
      my $work_path = $r->get_source_file;
      $self->compare_base_revs( $r, $work_path );
      pr_doing;
      return;
   }

   my $denorm_name = $self->denormalize_name( $r->name );
   my $work_path = $self->work_path( "co", $denorm_name ) ;

   ## Throw away the filename in the split, then cat the volumen
   ## back on.
   my ( $vol, $work_dir, undef ) = File::Spec->splitpath( $work_path ) ;
   $work_dir = File::Spec->catpath( $vol, $work_dir, "" );
   $self->mkdir( $work_dir );
   $work_dir =~ s{[\\/]+$}{}; ## vss is picky about trailing slashes in -GLpath

   if ( -e $work_path ) {
      unlink $work_path or die "$! unlinking $work_path" ;
   }

   ##
   ## Add this file's ancestor directories to VSS as projects if they
   ## were not found in the vss_files scan.
   ##
   my ( $file, $dirs ) = fileparse( $denorm_name );
   $dirs =~ s{\\}{/}g;  ## Make debugging output pretty, ss is cool with /
   {
      my @dirs = File::Spec::Unix->splitdir( $dirs );
      shift @dirs while @dirs && ! length $dirs[0];
      pop   @dirs while @dirs && ! length $dirs[-1];

      my $cur_project = "";
      for ( @dirs ) {
         $cur_project .= "/" if length $cur_project;
         $cur_project .= $_;

         unless ( $self->files->exists( [ $cur_project ] ) ) {
            $self->ss( [ "Create", "\$/$cur_project", "-C-" ] );
            $self->files->set( [ $cur_project ], "project" );
         }
      }
   }

   $self->ss_cp( $dirs );

   my $pr_id = $r->previous_id;

   my $state = "handled";  ## Should never show through, but be defensive

   if ( $r->action eq "delete" ) {
      $self->ss(
         [ "Delete", $file, "-I-y" ],
         {
            stderr_filter => qr{^You have.*checked out.*Y[\r\n]*$}s,
         }
      );
      $state = "deleted";
      $self->files->set( [ $denorm_name ], $state );
      $self->rev_map->set(
         [ $r->source_repo_id, $r->id ],
         $denorm_name,
         "",  ## VSS does not give version numbers to deleted files
         $state,
         defined $r->branch_id ? $r->branch_id : ""
      );

      ## TODO: Restore the file instead of adding it if it comes back?
   }
   else {
      if ( ! empty $pr_id ) {
         my ( $pfull_name, $pversion, $state, $pbranch_id ) =
            $self->rev_map->get( [ $r->source_repo_id, $pr_id ] );

         if ( ( $r->branch_id || "" ) ne $pbranch_id ) {
            ## Create a branch.

            $pfull_name =~ s{^\$?/+}{};

            if ( $pfull_name eq $file ) {
               die "branched revision has same name as parent ('$pfull_name'):\n",
                   "    parent:   ", $pr_id, "\n",
                   "    branched: ", $r->as_string, "\n",
                   "Perhaps a Map: filter is missing/broken\n";              
            }

            ## NOTE: In VSS, this command creates a "Rollback" log message,
            ## which is unfortunate.  I'd much prefer "Branched".  Ah well,
            ## if VSS didn't do this sort of thing, people would not switch.
            $self->ss(
               [ "Share",
                  "\$/$pfull_name",
                  "-V$pversion",
                  "-E",                # branch after sharing
                  "-P$file",
               ],
            );

            $self->ss( [ "Checkout", $file, "-G-" ] );
            $state = "branched to";
            $self->files->set( [ $denorm_name ], $state );
         }
      }

      unless ( $r->is_placeholder_rev ) {
         my $source_path = $r->get_source_file;

         debug "linking '$source_path' to '$work_path'"
            if debugging ;

         link $source_path, $work_path
            or die "$! linking '$source_path' -> $work_path" ;

         if ( defined $r->mod_time ) {
            utime $r->mod_time, $r->mod_time, $work_path
               or die "$! changing times on $work_path" ;
         }

         my $comment_flag = "-C-";
         if ( defined $r->comment ) {
            my $cfn = $self->work_path( "comment.txt" ) ;
            open COMMENT, ">$cfn"       or die "$!: $cfn";
            print COMMENT $r->comment   or die "$!: $cfn";
            close COMMENT               or die "$!: $cfn";
            $comment_flag = "-C\@$cfn";
         }

         my $check_it_in = 1;

         my @state = $self->files->get( [ $denorm_name ] );

         $state = "edited";
         if ( ! @state || $self->vss_file_is_deleted( $denorm_name ) ) {
            my $bin_flag = $r->type ne "text" ? "-B" : "-B-";

            if ( ! $self->vss_file_is_active( $denorm_name ) ) {
               ## If the file has been deleted before, -I-y causes ss to
               ## recover it instead of adding it anew.
               $check_it_in = 0;
               my $I = $self->{VSS_DONT_RECOVER} ? "n" : "y";
               $self->ss(
                  [ "Add", $work_path, "-K", $bin_flag, $comment_flag, "-I-$I" ],
                  {
                     stderr_filter => sub {
                        if ( ${$_[0]} =~
                        s/A deleted file of the same name already exists.*//s
                        ) {
                           return if $self->{VSS_DONT_RECOVER};
                           $check_it_in = 1;
                           $self->ss( [ "Checkout", $file, "-G-" ] );
                           $state = "undeleted";
                        }
                     },
                  }
               );
               $state = "added";
            }
         }

         if ( $check_it_in ) {
            $self->ss(
               [ "Checkin", $file, "-GL$work_dir", "-K", "-I-y", $comment_flag
               ],
               {
                  stderr_filter => 
                     qr{^.*was checked out from.*not from the current folder\.\r?\nContinue.*\r?\n},
               }
            );
         }
      }

      my $history;

      $self->ss_cp( $dirs );
      $self->ss( [ "History", $file, "-#1" ], undef, \$history );

      my ( $version ) =
         $history =~ /^\*+\s+Version\s+(\d+)\s+\*/ms;

      die "unable to parse a version string from:\n$history"
         if empty $version;

      $self->rev_map->set(
         [ $r->source_repo_id, $r->id ],
         $denorm_name,
         $version,
         $state,
         defined $r->branch_id ? $r->branch_id : ""
      );

      my @labels = map {
         s/^([^a-zA-Z])/tag_$1/ ;
	 s/\W/_/g ;
	 $_ ;
      } $r->labels;

      for ( @labels ) {
         $self->ss( [
            "Label",
            $file,
            "-L$_",
            "-C-",
            "-I-y",   ## Yes, please reuse the label
         ]);
      }
   }

   $self->files->set( [ $denorm_name ], $state );
   $self->head_revs->set(
      [ $r->source_repo_id, $r->source_filebranch_id ],
      $r->source_rev_id
   );

   pr_doing;
}

=head1 TODO

This module is here purely to support the VCP test suite, which must
import a bunch of files in to VSS before it can test the export.  It works,
but is not field tested.

While I'm sure there exist pressing reasons for importing files in to
VSS from other repositories, I have never had such a request and do not
wish to invest a lot of effort in advance of such a request.

Therefore, this module does not batch checkins, cope with branches,
optimize comment settings, etc.

Patches or contracts welcome.

=head1 NOTES

VSS does not flag individual revisions as binary vs. text; the change is
made on a per-file basis.  This module does not alter the filetype on
C<Checkin>, however it does set binary (-B) vs. text (-B-) on C<Add>.

VSS allows one label per file, and adding a label (by default) causes a
new versions of the file.  This module adds the first label it receives
for a file (which is first may or may not be predictable depending on
the source repository) to the existing version unless the existing
version already has a label, then it just adds new versions as needed.

This leads to the backfilling issue: when backfilling, there are no labels
to request, so backfilling always assumes that the most recent rev is the
base rev for incremental imports.

The C<ss Delete> and C<ss Share $file> commands do not allow a comment.

Files are recalled from deleted status when added again if they were
deleted.

=head1 LIMITATIONS

Built and tested against VSS v6.0 only.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
