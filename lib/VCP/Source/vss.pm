package VCP::Source::vss ;

=head1 NAME

VCP::Source::vss - A VSS repository source

=head1 SYNOPSIS

   vcp vss:project/...

=head1 DESCRIPTION

Source driver enabling L<C<vcp>|vcp> to extract versions form a vss
repository.

The source specification for VSS looks like:

    vss:filespec [<options>]

C<filespec> may contain trailing wildcards, like C</a/b/...> to extract
an entire directory tree (this is the normal case).

NOTE: This does not support incremental exports, see LIMITATIONS.

=head1 OPTIONS

=over

#=item --cd
#
#Used to set the VSS working directory.  VCP::Source::vss will cd to this
#directory before calling vss, and won't initialize a VSS workspace of
#it's own (normally, VCP::Source::vss does a "vss checkout" in a
#temporary directory).
#
#This is an advanced option that allows you to use a VSS workspace you
#establish instead of letting vcp create one in a temporary directory
#somewhere.  This is useful if you want to read from a VSS branch or if
#you want to delete some files or subdirectories in the workspace.
#
#If this option is a relative directory, then it is treated as relative
#to the current directory.
##
#=cut

=item -V

   -V 5
   -V 5~3

Passed to C<ss History>.

=item undocheckout

If set, VCP will undo users' checkouts when it runs in to the "File ...
is checked out by ..." error.  This error occurs when scanning metadata
for a file which is checked out by somebody and there is also a deleted
file of the same name.  NOTE: The VSS account VCP uses may need
administrative prividges to perform UndoCheckout on files checked out
by some other user.

=back

=head2 Files that aren't tagged

VSS has one peculiarity that this driver works around.

If a file does not contain the tag(s) used to select the source files,
C<vss log> outputs the entire life history of that file.  We don't want
to capture the entire history of such files, so L<VCP::Source::vss> goes
ignores any revisions before and after the oldest and newest tagged file
in the range.

=head1 LIMITATIONS

Many and various.  VSS, aside from its "normal" level of database
corruption that many sites either deal with regularly or manage to
ignore, also has many reporting and, from what I can tell, data model
flaws that make it challenging to figure out what happened when.

=cut

$VERSION = 1.2 ;

# Removed docs for -f, since I now think it's overcomplicating things...
#Without a -f This will normally only replicate files which are tagged.  This
#means that files that have been added since, or which are missing the tag for
#some reason, are ignored.
#
#Use the L</-f> option to force files that don't contain the tag to be
#=item -f
#
#This option causes vcp to attempt to export files that don't contain a
#particular tag but which occur in the date range spanned by the revisions
#specified with -r. The typical use is to get all files from a certain
#tag to now.
#
#It does this by exporting all revisions of files between the oldest and
#newest files that the -r specified.  Without C<-f>, these would
#be ignored.
#
#It is an error to specify C<-f> without C<-r>.
#
#exported.

@ISA = qw( VCP::Source VCP::Utils::vss );

use strict ;

use Carp ;
use File::Basename;
use Regexp::Shellish qw( :all ) ;
use VCP::Rev ;
use VCP::Debug qw(:debug );
use VCP::Logger qw( lg pr BUG pr_doing pr_done );
use VCP::Source ;
use VCP::Utils qw( escape_filename empty start_dir_rel2abs );
use VCP::Utils::vss ;

#use base qw( VCP::Source VCP::Utils::vss ) ;
#use fields (
#   'VSS_CUR',            ## The current change number being processed
#   'VSS_IS_INCREMENTAL', ## Hash of filenames, 0->bootstrap, 1->incremental
#   'VSS_INFO',           ## Results of the 'vss --version' command and VSSROOT
#   'VSS_LABEL_CACHE',    ## ->{$name}->{$rev} is a list of labels for that rev
#   'VSS_LABELS',         ## Array of labels from 'p4 labels'
#   'VSS_MAX',            ## The last change number needed
#   'VSS_MIN',            ## The first change number needed
#   'VSS_UNDOCHECKOUT',   ## Whether or not to undocheckout when the
#                         ## "File ... is checked out" error occurs
#   'VSS_VER_SPECS',      ## An ARRAY of revision specs to pass to
#                         ## `ss History`.  undef if there are none.
#
#   'VSS_NAME_REP_NAME',  ## A mapping of names to repository names
#
#   'VSS_NEEDS_BASE_REV', ## What base revisions are needed.  Base revs are
#                         ## needed for incremental (ie non-bootstrap) updates,
#			 ## which is decided on a per-file basis by looking
#			 ## at VCP::Source::is_bootstrap_mode( $file ) and
#			 ## the file's rev number (ie does it end in .1).
#   'VSS_HIGHEST_VERSION_TO_SEND',  ## This is like VSS_HIGHEST_VERSION but
#                         ## does *not* include the ignored VSS revisions.
#                         ## So it will be smaller than VSS_HIGHEST_VERSION
#                         ## whenever labels are involved.
#
#   'VSS_CURRENT_PROJECT',  ## The last ss cp parameter we issued.
#
#   'VSS_FILES',            ## We need to scan VSS for a list of files so we
#                           ## can do wildcard processing.  This is done with
#                           ## a VCP::FilesDB object.
#
#   'VSS_BRANCHED_FROM',  ## Cache of what files are branched from what
#                         ## other files.  Each HASH key is an absolute
#                         ## VSS path to a file in lowercase.
#                         ## Each element is a
#                         ## RevML id (/path/to/file#5) of the parent
#                         ## version.
#
#   ## Log file parsing state.
#   'VSS_LOG_FILE_DATA',  ## The data that applies to the file for which
#                         ## the history log is being parsed.
#
#   'VSS_LOG_REV_DATA',   ## Multiple VSS revisions can get compressed
#                         ## in to a single VCP revision in order to
#                         ## associate labels with the last actually
#                         ## changed version.  To do this, the parser
#                         ## keeps accumulating data in this HASH
#                         ## until it finds a revision with an action
#                         ## other than "Labeled".  The parser works
#                         ## from most recent revision to oldest and,
#                         ## may need to go past a revision specification
#                         ## that was given on the command line.  This
#                         ## is a class data member so that repeated calls
#                         ## to the history command may be made to find
#                         ## a committable offense.
#   'VSS_LOG_OLDEST_VERSION',    ## The oldest rev parsed for this file.
#   'VSS_REV_ID_PREFIX',  ## What to prefix deleted file's source_rev_id
#                         ## with so that we can discern deleted from
#                         ## undeleted files in get_source_file().
#) ;


sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   unless ( empty $spec ) {
      ## Ignore leading / and $/
      $spec =~ s{^\$?/*}{};

      ## Make it look like a Unix path.
      $spec =~ s{\\}{/}g;

      $self->parse_vss_repo_spec( $spec );
   }

   $self->parse_options( $options );

   return $self ;
}


sub options_spec {
   my $self = shift;
   return (
      $self->SUPER::options_spec,
      "undocheckout"   => \$self->{VSS_UNDOCHECKOUT},
#      "cd=s"          => \$self->{VSS_WORK_DIR},
#      "V=s"           => sub {
#         shift;
#         push @{$self->{VSS_VER_SPECS}}, "-V" . shift if @_; 
#         return map substr( $_, 2 ), @{$self->{VSS_VER_SPECS}};
#      },
   );
}


sub init {
   my $self= shift ;

   $self->SUPER::init;

   ## Set default repo_id.
   $self->repo_id( "vss:" . $self->repo_server )
      if empty $self->repo_id && ! empty $self->repo_server ;

   if ( empty $self->repo_user && empty $ENV{SSUSER} ) {
      pr "Assuming user Admin for VSS source";
      $self->repo_user( "Admin" );
   }

   my $files = $self->repo_filespec ;
   $self->deduce_rev_root( $files )
      unless defined $self->rev_root;

   ## rev_root should be "$"-less.
   $self->rev_root( $1 )
      if $self->rev_root =~ m{\A\$(.*)};

#   my $work_dir = $self->{VSS_WORK_DIR};
#   unless ( defined $work_dir ) {
      $self->create_vss_workspace ;
#   }
#   else {
#      $self->work_root( start_dir_rel2abs $work_dir ) ; 
#      $self->command_chdir( $self->work_path ) ;
#   }

   {
      ## Dirty trick: send a known bad parm *just* to get ss.exe to
      ## print it's banner without popping open a help screen.
      ## we capture and ignore stderr because it's expected.
      $self->ss( [ "help", "/illegal arg" ],
         undef,
         \my $out,
         \my $ignored_err,
         {
            ok_result_codes => [0..255],
         },
      );
      $self->{VSS_INFO} = $out;
   }

   $self->files->delete_db;
   $self->files->open_db;

   if ( $self->{VSS_UNDOCHECKOUT} ) {
      $self->command_stderr_filter(
         sub {
            my ( $err_text_ref ) = @_;
            if ( $$err_text_ref =~ s{^File .* is checked out by .*\r?\n}{} ) {
               $self->throw_undocheckout_and_retry;
            }
         }
      );
   }
}

=item files

Returns a reference to the FilesDB for this backend and repository.
Creates an empty one if need be.

This is like VCP::Dest::files() but most other sources do not need
to do this, so these are 

=cut

sub files {
   my $self = shift ;
   
   return $self->{VSS_FILES} ||= do {
      require VCP::FilesDB;
      $self->{VSS_FILES} = VCP::FilesDB->new(
         TableName => "source_files",
         StoreLoc  => $self->_db_store_location,
      );
   }
}

sub is_incremental {
   my $self= shift ;
   my ( $file, $first_rev ) = @_ ;

   $first_rev =~ s/\.\d+//;  ## Trim down <delete /> rev_ids

   my $bootstrap_mode = $first_rev <= 1 || $self->is_bootstrap_mode( $file ) ;

   return ! $bootstrap_mode ;
}


sub denormalize_name {
   my $self = shift ;
   return $self->SUPER::denormalize_name( @_ ) ;
}


sub handle_header {
   my $self = shift ;
   my ( $header ) = @_ ;

   $header->{rep_type} = 'vss' ;
   $header->{rep_desc} = $self->{VSS_INFO} ;
   $header->{rev_root} = $self->rev_root ;

   $self->dest->handle_header( $header );
   return ;
}


sub ss_get {
   ## A specialized method for this so that we can snatch the file we get
   ## to it's new filename before it gets redeleted when the Get is being
   ## performed by _swap_in_deleted_file_and().  Otherwise SS.EXE helpfully
   ## deletes it, whether or not -S- is passed.

   my $self = shift ;
   my ( $r, $rev_id, $dir, $fn ) = @_;

   my $vss_name = "\$/" . $self->denormalize_name( $r->source_name );
   
   $self->ss(
      [ "Get",
         $vss_name,
         "-V$rev_id",
         "-GN",   ## Newlines only, please
         "-GL$dir",
      ],
   );

   my $temp_fn = "$dir/" . fileparse( $vss_name );

   die  ## Should be a BUG, but we don't want to abort the Recover.
      "$temp_fn ($vss_name) does not exist after Get"
      unless -e $temp_fn;

   rename "$temp_fn", "$dir/$fn" or die "$! renaming $temp_fn to $dir/$fn\n";

}


sub get_source_file {
   my $self = shift ;

   my $r ;
   ( $r ) = @_ ;

   debug "getting ", $r->as_string if debugging;

   die "can't check out ", $r->as_string, "\n"
      unless $r->is_base_rev || $r->action eq "add" || $r->action eq "edit";

   my $wp = $self->work_path( "revs", $r->source_name, $r->source_rev_id ) ;
   $self->mkpdir( $wp ) ;

   my ( $fn, $dir ) = fileparse( $wp );

confess "Shouldn't be get_rev()ing a rev with no rev_id" unless defined $r->rev_id;

   $dir =~ s{[\\/]\z}{};
      ## Trailing slashes confuse SS.EXE's dequoting by making it think
      ## the trailing slash is an escape character so it will take its
      ## trailing quote literally.

   my $do_normal_get = 1;

   my $vss_name = $self->denormalize_name( $r->source_name );

   $vss_name =~ s{\A(?!/)}{/};
   
   my $vcp_rev_id = $r->source_rev_id;
   my ( $generation, $vss_rev_id ) = $vcp_rev_id =~ /\A(\d+)\.(\d+)\z/
      or die "vcp: couldn't parse source_rev_id '$vcp_rev_id' from ",
         $r->as_string;

   $self->{VSS_REV_ID_PREFIX} = "$generation.";

   if ( ! $generation && $self->vss_file_is_deleted( $vss_name ) ) {
      $self->_swap_in_deleted_file_and(
         $vss_name,
         "ss_get", ( $r, $vss_rev_id, $dir, $fn )
      ) ;
      $do_normal_get = 0;
   }
   else {
      $self->ss_get( $r, $vss_rev_id, $dir, $fn )
   }

   return $wp;
}

## History report Parser states
## The code below does things like grep for "commit" and "skip to next"
## in these strings.  Plus, they make debug output easier to read.
use constant SKIP_TO_NEXT                    => "skip to next";
use constant SKIP_TO_NEXT_COMMIT_AT_END      => "skip to next and commit at end";
use constant ENTRY_START                     => "entry start";
use constant READ_ACTION                     => "read action";
use constant READ_COMMENT_AND_COMMIT         => "read comment and commit";
use constant READ_REST_OF_COMMENT_AND_COMMIT => "read rest of comment and commit";


sub _get_file_metadata {
   my $self = shift ;
   my ( $filename, $properties_handler ) = @_;

   my $ss_fn = "\$$filename";

   my $properties;

   $self->ss( [ "Properties", $ss_fn ], undef, \$properties );

   debug "[$properties]" if debugging;

   my ( $filetype ) = $properties =~ /^Type:\s+(\S+)$/m
      or BUG "Can't parse filetype from '$properties'";
   $filetype = lc $filetype;

   my $store_head_only = $properties =~ /^Store only latest version:\s+Y/mi;

   my $tmp_f;
   my $result = 1;

   if ( $properties_handler ) {
      my $need_history =
         $properties_handler->( $self, $filename, $properties );
      return unless $need_history;
   }

   ## Clear the parser state.
   $self->{VSS_LOG_OLDEST_VERSION}  = undef ;
   $self->{VSS_LOG_REV_DATA}        = undef;
   $self->{VSS_LOG_FILE_DATA}       = {
       Name     => $filename,
       Type     => $filetype,
       HeadOnly => $store_head_only,
   };

   ## The interplay between VSS_VER_SPECS and HeadOnly means that we
   ## we can't be sure that the most recent reported version
   ## is actually stored in the repository (it might be version 5 of 10,
   ## say).  So we can't pass -#1 to ss History, we have to tell the parser
   ## to bail after the first version it reads.

   $self->ss(
      [
         "History",
         "\$$filename",
         @{$self->{VSS_VER_SPECS} || []},
      ],
      undef,
      sub { $self->parse_history_output( @_, $store_head_only ) },
      $self->{VSS_VER_SPECS}
         ? (
            stderr_filter => sub {
               my ( $err_text_ref ) = @_ ;
               $$err_text_ref =~
                  s{^Version not found\r?\n\r?}[$result = 0; '' ;]mei ;
            },
         )
         : ()
   );

   ## If the history ended on a "Labeled" rev, it will not have
   ## been saved off as a real rev yet.
   ## I think this should only happen if the -V
   ## option was used.
   $self->_add_rev_from_log_parser if $self->{VSS_LOG_REV_DATA};

   ## If the oldest revision not found was not a branch founding
   ## revision, then VSS_LOG_OLDEST_VERSION will be set.
   my $oldest = $self->{VSS_LOG_OLDEST_VERSION};
   if ( defined $oldest
      && $self->is_incremental( $filename, $oldest )
      && ! $store_head_only
   ) {
      debug "scanning back to base rev" if debugging;

      ## Walk back and find the next real version (ie not a labelled
      ## version).  This should exist in the destination repository,
      ## even if it's not the head revision.
      while ( --$oldest && $oldest ) {
         $self->_parse_a_rev( $filename, $oldest );

         if ( !$self->{VSS_LOG_REV_DATA} ) {
            ## Must have found a real edit.
            debug
               "converting to base_rev",
               $self->last_rev->as_string
               if debugging;
            $self->last_rev->base_revify;
            last;
         }
      }
   }

   if ( keys %{$self->{VSS_LOG_REV_DATA}} ) {
      require Data::Dumper;
      local $Data::Dumper::Indent    = 1;
      local $Data::Dumper::Quotekeys = 0;
      local $Data::Dumper::Terse     = 1;
      BUG(
         "Data left over from log parse\n",
         Data::Dumper::Dumper(
            $self->{VSS_LOG_REV_DATA}
         )
      );
   }

   return $result;
}


{
## This routine is used once per operation so that the source file is
## deleted immediately after each operation so that the source repo
## is always put back in its proper state in case we exit between
## operations.  This is inefficient, but conservative.
## TODO: Allow a fast-but-dangerous option to make this maintain state
## for each file and only clean up the repository at the end.

my $pending_swap_out;
    ## pending_swap_out is set so that END{} can clean up...

END {
    $pending_swap_out->() if ! empty $pending_swap_out;
}

sub _swap_in_deleted_file_and {
   my $self = shift ;
   my ( $filename, $method, @args ) = @_;

   $filename =~ s{\A(?!/)}{/};
   my $ss_fn = "\$$filename";

   my $renamed_active;

   if ( $self->vss_file_is_active( $filename ) ) {
      my $i = "";
      while (1) {
         $renamed_active = "$ss_fn.vcp_bak$i";
	 ( my $key = $renamed_active ) =~ s/^\$?[\\\/]//g;
         last unless ($self->files->get( [ $key ] ))[0];
         $i ||= 0;
         ++$i;
      }
      $self->ss( [ "Rename", $ss_fn, $renamed_active ] );
   }

   my $result;

   $self->ss( [ "Recover", $ss_fn ], );

   $pending_swap_out = sub {
      $pending_swap_out = undef;
      my $ok = eval {
         $self->ss( [ "Delete", $ss_fn ] );
         1;
      };

      my $x = $ok ? "" : $@;

      if ( ! empty $renamed_active ) {
         if ( !
            eval { $self->ss( [ "Rename", $renamed_active, $ss_fn ] ); 1 }
         ) {
            $@ = "$x$@";
            return 0;
         };
      }

      return $ok;
   };

   my $ok = eval { $result = $self->$method( @args ); 1 };
   my $x = $ok ? "" : $@;

   $ok = $pending_swap_out->() && $ok;
   die $x.$@ unless $ok;

   return $result;
}

}


sub _concoct_deleted_rev {
   my $self = shift;
   my ( $vss_name, $properties ) = @_;

   my ( $highest_deleted_vss_rev_id ) = $properties =~ /^\s+Version:\s+(\d+)/mi
      or die "vcp: couldn't parse version from '$properties'\n";
   my $rev_id = $self->{VSS_REV_ID_PREFIX} . ( $highest_deleted_vss_rev_id + 1 );

   my $last_rev_id = $self->dest && $self->dest->last_rev_in_filebranch(
      $self->repo_id,
      $vss_name,
   );

   my $need_history = empty( $last_rev_id )
      || VCP::Rev->cmp_id( $last_rev_id, "0.$highest_deleted_vss_rev_id" ) < 0;

   my $need_deleted = $need_history
      || VCP::Rev->cmp_id( $last_rev_id, $rev_id ) < 0;

   $need_history ||= $need_deleted && $self->continue;
      ## Make sure we get the base revision if one is needed.  We get all
      ## the history, though, really, we only need one rev.
      ## TODO: only get enough history to get the base rev.

   return 0 unless $need_deleted;

   my $norm_name = $self->normalize_name( $vss_name );
   my $branch_id = (fileparse $vss_name )[1];

   my $dr = VCP::Rev->new(
      id                   => "$vss_name#$rev_id",
      name                 => $norm_name,
      source_name          => $norm_name,
      source_filebranch_id => $vss_name,
      branch_id            => $branch_id,
      source_branch_id     => $branch_id,
      source_repo_id       => $self->repo_id,
      action               => "delete",
      rev_id               => $rev_id,
      source_rev_id        => $rev_id,
   ) ;

   $self->set_last_rev_in_filebranch_previous_id( $dr );
   $self->queue_rev( $dr );

   return $need_history;
}


sub scan_metadata {
   my $self = shift ;

   ## Get a list of all files we need to worry about
   $self->get_vss_file_list( $self->repo_filespec );

   pr_doing "scanning VSS files: ", { Expect => 0+$self->vss_files };

   for my $filename ( $self->vss_files ) {
      pr_doing;

      my $is_active  = $self->vss_file_is_active(  $filename );
      my $is_deleted = $self->vss_file_is_deleted( $filename );

      $self->{VSS_REV_ID_PREFIX} = !$is_deleted ? "0." : "1.";
         ## If there is no deleted file, then the active file is
         ## the first file, so its revs get a "0.".  If there is a
         ## deleted file, the active file's revs are placed in the
         ## "1." series.

      my $found_active = $is_active
         ? $self->_get_file_metadata( $filename )
         : 0;

      my $found_deleted;

      if ( $is_deleted ) {

         $self->{VSS_REV_ID_PREFIX} = "0.";
            ## Deleted files are always the "0." file.

         my $tmp_ver_spec;
         if ( $found_active ) {
            ## If we were looking for a specific version and found it
            ## back in the deleted time, make sure we also get all
            ## the revs from the active file.
            ## THIS ASSUMES WE'RE NOT SEARCHING FOR A RANGE.
            ## Can't local()ize a p-hash.
            $tmp_ver_spec = $self->{VSS_VER_SPECS};
            $self->{VSS_VER_SPECS} = undef;
         }

         $found_deleted = $self->_swap_in_deleted_file_and(
            $filename,
            "_get_file_metadata", ( $filename, \&_concoct_deleted_rev )
         );

         $self->{VSS_VER_SPECS} = $tmp_ver_spec
            if $found_active;
      }

      $self->store_cached_revs;

      pr join " ",
         @{$self->{VSS_VER_SPECS}},
         "did not match any revisions of $filename"
         if $self->{VSS_VER_SPECS}
            && ! ( $found_deleted || $found_active );
   }

   pr_done;

   pr "found ", $self->sent_rev_count, " revisions";
}


# Here's a typical history
#
###############################################################################
##D:\src\vcp>ss history
#History of $/90vss.t ...
#
#*****************  Version 9   *****************
#User: Admin        Date:  3/05/02   Time:  9:32
#readd recovered
#
#*****  a_big_file  *****
#Version 3
#User: Admin        Date:  3/05/02   Time:  9:32
#Checked in $/90vss.t
#Comment: comment 3
#
#
#*****  binary  *****
#Version 3
#User: Admin        Date:  3/05/02   Time:  9:32
#Checked in $/90vss.t
#Comment: comment 3
#
#
#*****************  Version 8   *****************
#User: Admin        Date:  3/05/02   Time:  9:32
#readd deleted
#
#*****  binary  *****
#Version 2
#User: Admin        Date:  3/05/02   Time:  9:32
#Checked in $/90vss.t
#Comment: comment 2
#
#
#*****************  Version 7   *****************
#User: Admin        Date:  3/05/02   Time:  9:32
#readd added
#
#*****  a_big_file  *****
#Version 2
#User: Admin        Date:  3/05/02   Time:  9:32
#Checked in $/90vss.t
#Comment: comment 2
#
#
#*****************  Version 6   *****************
#User: Admin        Date:  3/05/02   Time:  9:32
#$del added
#
#*****************  Version 5   *****************
#User: Admin        Date:  3/05/02   Time:  9:32
#binary added
#
#*****************  Version 4   *****************
#User: Admin        Date:  3/05/02   Time:  9:31
#$add added
#
#*****************  Version 3   *****************
#User: Admin        Date:  3/05/02   Time:  9:31
#a_big_file added
#
#*****************  Version 2   *****************
#User: Admin        Date:  3/05/02   Time:  9:31
#$a added
#
#*****************  Version 1   *****************
#User: Admin        Date:  3/05/02   Time:  9:31
#Created
#
#
#D:\src\vcp>ss dir /r
#$/90vss.t:
#$a
#$add
#$del
#a_big_file
#binary
#readd
#
#$/90vss.t/a:
#$deeply
#
#$/90vss.t/a/deeply:
#$buried
#
#$/90vss.t/a/deeply/buried:
#file
#
#$/90vss.t/add:
#f1
#f2
#f3
#
#$/90vss.t/del:
#f4
#
#13 item(s)
#
#D:\src\vcp>
#
###############################################################################


sub _parse_a_rev {
   my ( $self, $fn, $rev_id ) = @_;

   $rev_id =~ s{\A0\.}{};

   $self->ss(
      [ "History", "\$/$fn", "-V$rev_id", "-#1" ],
      undef,
      sub { $self->parse_history_output( @_ ) }
   );

   ## If the history ended on a "Labeled" rev, it will not have
   ## been saved off as a real rev yet.
   ## I think this should only happen if the -V
   ## option was used.
   $self->_add_rev_from_log_parser if $self->{VSS_LOG_REV_DATA};
}


## Called each time a new revision is reached and there's no place to
## catch the information.
sub _init_log_rev_data {
   my $self = shift;

   debug "initializing new rev" if debugging;
   return $self->{VSS_LOG_REV_DATA} = {
      %{$self->{VSS_LOG_FILE_DATA}},
   };
}


sub _add_rev_from_log_parser {
   my ( $self ) = @_;

   debug "adding revision" if debugging;

   my $p = $self->{VSS_LOG_REV_DATA};
   BUG "trying to add a revision when none was parsed"
      unless $p;

   $self->{VSS_LOG_REV_DATA} = undef;

   $p->{Comment} = ''
      unless defined $p->{Comment};

   $p->{Comment} =~ s/\r\n|\n\r/\n/g ;
   chomp $p->{Comment};
   chomp $p->{Comment};

   my $added_it = $self->_add_rev( $p );

   my $name = $p->{Name};

   ## This is the version number without the additional label
   ## versions.
   my $v = $p->{Version};

   $self->{VSS_HIGHEST_VERSION_TO_SEND}->{$name} = $v
      if $added_it
         && ( ! defined $self->{VSS_HIGHEST_VERSION_TO_SEND}->{$name}
           || $v > $self->{VSS_HIGHEST_VERSION_TO_SEND}->{$name}
         );
      ## VSS_HIGHEST_VERSION_TO_SEND is used to generate the previous_id
      ## for revisions.  If we don't end up queuing a revision, $added_it
      ## will be false.  In this case, don't set VSS_HIGHEST_VERSION_TO_SEND
      ## because we don't want to refer to unsent revisions.

   $v += @{ $p->{Labels} || [] };
}


sub parse_history_output {
   my $self = shift;
   my ( $input, $exit_after_head_rev ) = @_ ;

   my $state = SKIP_TO_NEXT;

   my $p = $self->{VSS_LOG_REV_DATA};

   debug "\$exit_after_head_rev set" if debugging && $exit_after_head_rev;

   local $_ ;
   while ( <$input> ) {
      if ( debugging ) {
         my $foo = $_;
         chomp $foo;
         debug "[$foo]     $state\n";
      }

      if ( /^\*{5,}(?:\s+Version (\d+)\s+)?\*{5,}\s*\z/ ) {
         if ( $p && "commit" eq substr $state, -6 ) {
            $self->_add_rev_from_log_parser;
            return if $exit_after_head_rev;
         }
         $state = ENTRY_START;
         $p = $self->_init_log_rev_data unless $self->{VSS_LOG_REV_DATA};

         ## This will overwrite the newer/higher version number
         ## with the lower/older one until we reach the check-in
         ## we want
         $self->{VSS_LOG_OLDEST_VERSION} = $p->{Version} = $1;
         next;
      }

      next if 0 == index $state, SKIP_TO_NEXT;

      if ( $state eq ENTRY_START ) {
         if ( /^User:\s+(.*?)\s+Date:\s+(.*?)\s+Time:\s+(\S+)/ ) {
            ## Store these aside in case they're for the next VCP::Rev
            ## (which we can only tell when reading the action).
            $p->{User}= $1;
            $p->{Date}= $2;
            $p->{Time}= $3;
            $state = READ_ACTION;
            next;
         }

         if ( /^Label:\s*"([^"]+)"/ ) {
            ## Unshift because we're reading from newest to oldest yet
            ## we want oldest first so vss->vss is relatively consistent
            unshift @{$p->{Labels}}, $1;
            next;
         }
      }

      if ( $state eq READ_ACTION ) {
         if ( /Labeled/ ) {
            ## It's a label-add only, ignore the rest.
            ## for incremental exports, we'll need to commit at the
            ## end of the log if the last thing was a "Labeled"
            ## version.  We don't want to commit after each "Labeled"
            ## because we want to aggregate labels.
            $state = SKIP_TO_NEXT_COMMIT_AT_END;
            next;
         }

         if ( /Rolled back/ ) {
            ## This could be any number of things:
            ##    * Rollback
            ##    * Rollback-before-Branch
            ##    * Share -V
            ##    * Share -V followed by Branch
            ##    * Other things I don't understand
            ## We should figure out which one, but I'm not sure
            ## how to differentiate these.  For now, I'm assuming
            ## that it's a branch creation.
            my $previous_id = eval {
               $self->branched_from( $p->{Name} )
            };

            if ( $previous_id ) {
               ## Guess that it's a branch operation that VSS is hiding
               ## from us.  Hope the user didn't *really* issue a
               ## Rollback.
               pr
                  "assuming Rollback on branch is Branch point\n",
                  "    Parent: \$$previous_id\n",
                  "    Child:  \$$p->{Name}#$p->{Version}";
               $p->{PreviousId} = $previous_id;

               goto BranchFound;
            }
            $state = SKIP_TO_NEXT_COMMIT_AT_END;
            next;
         }

         if ( /Branched/ ) {
            $state = SKIP_TO_NEXT_COMMIT_AT_END;
            $p->{PreviousId} = $self->branched_from( $p->{Name} );

         BranchFound:
            $p->{Action} = "branch";

            ## copy_revs might convert this back from a placeholder to an
            ## edit if the source of the branch is not available.

            ## Prevent the caller from searching back for a base
            ## revision.
            ## TODO: Allow a project with branched files to be extracted
            ## with the branch point being bootstrapped.
            $self->{VSS_LOG_OLDEST_VERSION} = undef;

            ## Ignore all history before the branch, it's just
            ## bleedthrough from the parent.
            ## TODO: deal properly with shared history before a branch.
            ## This may require noting the branch point and scrolling
            ## back to the beginning creating placeholders over and
            ## over again as we do with dual-labelled CVS file branches.
            return;
         }

         if ( /^(Checked in .*|Created|.* recovered)\r?\n/ ) {
            $state = READ_COMMENT_AND_COMMIT;
            $p->{Action} = "edit";
            next;
         }
      }

      if ( $state eq READ_COMMENT_AND_COMMIT ) {
         if ( s/Comment: // ) {
            $p->{Comment} = $_;
            $state = READ_REST_OF_COMMENT_AND_COMMIT;
            next;
         }
         next unless /\S/;
      }

      if ( $state eq READ_REST_OF_COMMENT_AND_COMMIT ) {
          $p->{Comment} .= $_;
          next;
      }

      require Data::Dumper;
      local $Data::Dumper::Indent    = 1;
      local $Data::Dumper::Quotekeys = 0;
      local $Data::Dumper::Terse     = 1;

      BUG
         "unhandled VSS log line '$_' in state '$state' for:\n",
         Data::Dumper::Dumper( \%$p );
   }

   $self->_add_rev_from_log_parser
      if 0 <= index $state, "commit";
}


# Here's a (probably out-of-date by the time you read this) dump of the args
# for _add_rev:
#
###############################################################################
#$file = {
#  'WORKING' => 'src/Eesh/eg/synopsis',
#  'SELECTED' => '2',
#  'LOCKS' => 'strict',
#  'TOTAL' => '2',
#  'ACCESS' => '',
#  'RCS' => '/var/vss/vssroot/src/Eesh/eg/synopsis,v',
#  'KEYWORD' => 'kv',
#  'RTAGS' => {
#    '1.1' => [
#      'Eesh_003_000',
#      'Eesh_002_000'
#    ]
#  },
#  'HEAD' => '1.2',
#  'TAGS' => {
#    'Eesh_002_000' => '1.1',
#    'Eesh_003_000' => '1.1'
#  },
#  'BRANCH' => ''
#};
#$rev = {
#  'DATE' => '2000/04/21 17:32:16',
#  'MESSAGE' => 'Moved a bunch of code from eesh, then deleted most of it.
#',
#  'STATE' => 'Exp',
#  'AUTHOR' => 'barries',
#  'REV' => '1.1'
#};
###############################################################################


sub _add_rev {
   my $self = shift ;
   my ( $rev_data ) = @_ ;

   my $filename = $rev_data->{Name};
   my $vss_name = $filename;
   my $rev_id = $self->{VSS_REV_ID_PREFIX} .  $rev_data->{Version};
   my $action = $rev_data->{Action};

   my $mode = $self->rev_mode( $vss_name, $rev_id );
   return unless $mode;

   my $norm_name = $self->normalize_name( $filename );
   my $branch_id = (fileparse $vss_name )[1];

   $rev_data->{Type} ||= "text";

   my $r = VCP::Rev->new(
      id                   => "$vss_name#$rev_id",
      name                 => $norm_name,
      source_name          => $norm_name,
      source_filebranch_id => $vss_name,
      branch_id            => $branch_id,
      source_branch_id     => $branch_id,
      source_repo_id       => $self->repo_id,
      rev_id               => $rev_id,
      source_rev_id        => $rev_id,
      defined $rev_data->{PreviousId}
         ? ( previous_id          => $rev_data->{PreviousId} )
         : (),
      $action ne "branch"
         ? ( type                 => $rev_data->{Type} )
         : (),
      $mode ne "base"
	 ? (
	    action         => $action,
	    time           => $self->parse_time(
               $rev_data->{Date} . " " . $rev_data->{Time}
            ),
	    user_id        => $rev_data->{User},
	    comment        => $rev_data->{Comment},
	    state          => $rev_data->{STATE},
	    labels         => $rev_data->{Labels},
	 )
	 : (),
   );

   $self->{VSS_NAME_REP_NAME}->{$rev_data->{Name}} = $rev_data->{RCS} ;

   $self->set_last_rev_in_filebranch_previous_id( $r );
   $self->queue_rev( $r ) ;

   return 1;
}


sub branched_from {
   my $self = shift ;
   my ( $filename ) = @_;

   my $fn = "\$$filename";
   $fn = lc $fn unless $self->case_sensitive;

   $self->ss(
      [ "Paths", $fn ],
      undef,
      sub { $self->parse_paths_output( @_ ) },
   ) unless exists $self->{VSS_BRANCHED_FROM}->{$fn};

#   BUG "can't find parent for '$filename'"
   return undef
      unless exists $self->{VSS_BRANCHED_FROM}->{$fn};

   return $self->{VSS_BRANCHED_FROM}->{$fn};
}


## Output looks like:
##
##    Showing development paths for $/revml2vss/main-branch-1/branched...
##    
##      bar
##      $/revml2vss/main
##         bar   (Branched at version 4)
##         $/foo
##    
##         branched   (Branched at version 2)
##    >    $/revml2vss/main-branch-1
##
## We ignore the ">" position indicator.
##
##

sub parse_paths_output {
   my $self = shift ;
   my ( $input ) = @_ ;

   my $l = <$input>;
   BUG "expected 'Showing development...' from Paths, not '$l'"
      unless $l =~ /^Showing development/;

   $l = <$input>;
   BUG "expected Paths output line 2 to be blank, not '$l'"
      unless $l =~ /^\r?\n/;

   my $last_indent_length = 0;
   my $parent_full_fn;
   my $cur_fn;
   my $cur_branched_at;
   my $first_full_fn;

   local $_ ;
   while ( <$input> ) {
      if ( debugging ) {
         my $foo = $_;
         chomp $foo;
         debug "[$foo]\n";
      }

      next if /\A\s*\z/;

      my ( $indent, $content ) = /^(>?\s+)(\S.*?)\r?\n/
         or BUG "in Path output, can't parse line '$_'";

      my $cur_indent = length $indent;
      BUG
         "in Path output, unexpected outdent from $cur_indent to ",
         length $indent,
         " in '$_'"
         if $cur_indent < $last_indent_length;

      my $is_project = '$/' eq substr $content, 0, 2;

      if ( $cur_indent > $last_indent_length ) {
         $last_indent_length = $cur_indent;
         $parent_full_fn = $first_full_fn;
         $first_full_fn = undef;
         BUG "in Path output, expected filename, not project path '$content'"
            if $is_project;
      }

      if ( $is_project ) {
         ## Its a line showing a project the cur_fn is shared by.  Often
         ## (as in the above example) a file is in only one project
         ## but a file may be linked in to two projects.
         $content =~ s/\r?\n\z//;
         $content =~ s/\s*\([^()]+ is deleted in this project\)//;
         my $cur_full_fn = "$content/$cur_fn";
         $first_full_fn = $cur_full_fn unless defined $first_full_fn;
         ## The key is in VSS-ese, starts with '$'.  The value is
         ## in RevML-ese, starts with '/'.
         if ( defined $cur_branched_at ) {
            my $key = $cur_full_fn;
            $key = lc $key unless $self->case_sensitive;

            if ( empty $parent_full_fn ) {
               ## This *seems* to mean that the version wasn't truely
               ## branched, perhaps because a Rollback undid a branch
               ## or a delete or something else; I have no idea.
               next;
            }

            my $parent_rev_id = $self->{VSS_REV_ID_PREFIX} . $cur_branched_at;

            $self->{VSS_BRANCHED_FROM}->{$key} =
               substr "$parent_full_fn#$parent_rev_id", 1;
            debug $cur_full_fn, " branched from ",
               $self->{VSS_BRANCHED_FROM}->{$key}
               if debugging;
         }
      }
      else {
         ## Must be another file branched from the same parent.
         ( $cur_fn, $cur_branched_at ) =
            $content =~ /\A(.*?\S)(?:\s+\(Branched at version (\d+)\))?\r?\z/
            or BUG "in Path output, unable to parse chunk '$content'";

         ## The "Branched at version" value is the version number in
         ## the child file that the branch was created at.  The parent
         ## carries the preceding version number (we hope).
         $cur_branched_at-- if defined $cur_branched_at;
      }
   }
}

=head1 VSS NOTES

We lose comments attached to labels: labels are added to the last
"real" (ie non-label-only) revision and the comments are ignored.
This can be changed, contact me.

We assume a file has always been text or binary, don't think this is
stored per-version in VSS.

VSS does not track renames by version, so a previous name for a file is
lost.

VSS lets you add a new file after deleting an old one.  This module
renames the current file, restores the old one, issues its revisions,
then deletes the old on and renames the current file back.  In this
case, the C<rev_id>s from the current file start at the highest
C<rev_id> for the deleted file and continue up.  This can cause
problems if somebody has the file checked out, use the --undocheckout
option to force VCP to undo the checkout and carry on.

Looks for deleted files: recovers them if found just long enough to
cope with them, then deletes them again.  Repeatedly, if need be.

NOTE: when recovering a deleted file and using it, the current version
takes a "create the smallest window of opportunity to leave the source
repository in an uncertain state" approach: it renames the not-deleted
version (if any), restores the deleted one, does the History or Get, and
then deletes it and renames the not-deleted version back.

This is so that if something (the OS, the hardware, AC mains, or even
VCP code) crashes, the source repository is left as close to the
original state as is possible.  This does mean that this module can
issue many more commands than minimally necessary; perhaps there should
be a --speed-over-safety option or a transaction log & recovery system.

No incremental export is supported.  VSS' -V~Lfoo option, which says
"all versions since this label" does not actually cause the C<ss.exe
History> command to emit the indicated checkin.  We'll need to make the
history command much smarter to implement that.

Haven't tested many real-world scenarios yet.

If you specify a filespec that matches files branched from files
not included in the filespec, VCP pretends that the first revision of
the file at the new location is the first revision ever.

SS.EXE, which VCP uses for all SourceSafe operations, may ignore it's
-I- option, which should prevent it from seeking input, and seek input.
This can hang VCP, but it's usually when hitting ^C.  This can leave SS.EXE
running in a state consuming 100% CPU while waiting for a password.  Use
the Task Manager to clean up such processes.

=over

=item *

Share-ing a project

=back

=cut

=head1 SEE ALSO

L<VCP::Dest::vss>, L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
