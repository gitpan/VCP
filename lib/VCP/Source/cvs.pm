package VCP::Source::cvs ;

=head1 NAME

VCP::Source::cvs - A CVS repository source

=head1 SYNOPSIS

   vcp cvs:module/... -d ">=2000-11-18 5:26:30" <dest>
                                  # All file revs newer than a date/time

   vcp cvs:module/... -r foo      # all files in module and below labelled foo
   vcp cvs:module/... -r foo:     # All revs of files labelled foo and newer,
                                  # including files not tagged with foo.
   vcp cvs:module/... -r 1.1:1.10 # revs 1.1..1.10
   vcp cvs:module/... -r 1.1:     # revs 1.1 and up on main trunk

   ## NOTE: Unlike cvs, vcp requires spaces after option letters.

=head1 DESCRIPTION

Source driver enabling L<C<vcp>|vcp> to extract versions form a cvs
repository.

The source specification for CVS looks like:

    cvs:cvsroot:module/filespec [<options>]

or optionally, if the C<CVSROOT> environment variable is set:

    cvs:module/filespec [<options>]
    
The cvsroot is passed to C<cvs> with cvs' C<-d> option.

The filespec and E<lt>optionsE<gt> determine what revisions
to extract.

C<filespec> may contain trailing wildcards, like C</a/b/...> to extract
an entire directory tree.

If the cvsroot looks like a local filesystem (if it doesn't
start with ":" and if it points to an existing directory or file), this
module will read the RCS files directly from the hard drive unless
--use-cvs is passed.  This is more accurate (due to poor design of
the cvs log command) and much, much faster.

=head1 OPTIONS

=over

=item --cd

Used to set the CVS working directory.  VCP::Source::cvs will cd to this
directory before calling cvs, and won't initialize a CVS workspace of
it's own (normally, VCP::Source::cvs does a "cvs checkout" in a
temporary directory).

This is an advanced option that allows you to use a CVS workspace you
establish instead of letting vcp create one in a temporary directory
somewhere.  This is useful if you want to read from a CVS branch or if
you want to delete some files or subdirectories in the workspace.

If this option is a relative directory, then it is treated as relative
to the current directory.

=item -k

   -k sadf

Pass the CVS -k options through to the underlying CVS command.

=item -kb

Pass the -kb option to cvs, forces a binary checkout.  This is
useful when you want a text file to be checked out with Unix linends,
or if you know that some files in the repository are not flagged as
binary files and should be.

=item -r

   -r v_0_001:v_0_002
   -r v_0_002:

Passed to C<cvs log> as a C<-r> revision specification.  This corresponds
to the C<-r> option for the rlog command, not either of the C<-r>
options for the cvs command.  Yes, it's confusing, but "cvs log" calls
"rlog" and passes the options through.

=item --use-cvs

Do not try to read local repositories directly; use the cvs command
line interface.  This is much slower than reading the files directly
but is useful to see if there is a bug in the RCS file parser or
possibly when dealing with corrupt RCS files that cvs will read.

If you find that this option makes something work, then there is a
discrepancy between the code that reads the RCS files directly (in the
absence of this option) and cvs itself.  Please let me know
(barrie@slaysys.com).  Thanks.

=item -d

   -d "2000-11-18 5:26:30<="

Passed to 'cvs log' as a C<-d> date specification. 

WARNING: if this string doesn't contain a '>' or '<', you're probably doing
something wrong, since you're not specifying a range.  vcp may warn about this
in the future.

see "log" command in cvs(1) man page for syntax of the date specification.

=back

=head1 CVS Conversion issues

=head2 Files that aren't tagged

CVS has one peculiarity that this driver works around.

If a file does not contain the tag(s) used to select the source files,
C<cvs log> outputs the entire life history of that file.  We don't want
to capture the entire history of such files, so L<VCP::Source::cvs>
ignores any revisions before and after the oldest and newest tagged file.

=head2 Branches with multiple tags / "cloned" branches

CVS allows branches to be tagged with multiple tags using a command
like 

   cvs admin second_branch_tag:branch_tag

When VCP::Source::cvs notices this, it creates multiple branches with
identical revisions.  This is done by choosing the first branch tag for
the branches to be the primary branch and applying all actual changes to
it then "clone"ing each revision from that branch to all others.

For instance, if file foo is branched once in to a branch tagged with
"bar" and later a "goof" tag is aliased to the "bar" tag, then

    trunk     branch bar         branch goof
    =======   ================   ==================

    foo#1.1
      |    \
      |     \
      |      \
     ...      foo#1.1.1.1<bar>
                 |            \
                 |             \
                 |              \
                 |               foo#1.1.1.1<goof>
                 |
              foo#1.1.1.2<bar>                   
                 |            \
                 |             \
                 |              \
                 |               foo#1.1.1.2<goof>
                 |
                ...

This is EXPERIMENTAL and it's likely to give VCP::Dest::cvs fits.  It is
tested with CVS->p4 transfers.

If you only want the primary branch, you may use a Map: section in
the .vcp file to discard non-primary branches:

    Map:
        ...<goof>   <<delete>>

Currently, there is no way to ignore the primary branch other than
getting rid of that branch tag in the RCS files or hacking
VCP::Source::cvs's source code to ignore it.

=head1 FEATURES

(EXPERIMENTAL) It's possible somehow (I've never done it) to set the
state on edited revisions to "dead", which may result in a series of
revisions all marked "dead".  CVS, at least older versions, deleted a
file by marking the head rev as state "dead" instead of adding a new
revision.  So a dead revision is both an edit and a deletion.  I am not
sure whether the metadata on the rev refers to the time and user that
committed the edit, or the time and user that committed the delete.

VCP::Source::cvs detects consecutive "dead" revisions and "dead"
revisions that are also edits and issues a normal "edit" revision
followed by a concocted "delete" revision with a ".0" appended to the
rev_id.

=head1 LIMITATIONS

Stores all revisions for a file in RAM before sending so it can link all
the revisions properly.  Also stores all branch parents and the first
revision on every branch for all files scanned so it can insert
placeholders for branches with no revs.  Except for these branch point
revisions, all other revs for each file are sent before the next file is
scanned.

TODO: just send placeholders for all branches that match the filespec
and revspec?

Does not yet set the same time in all branch creation revisions.  This
may be necessary in order to help the changeset aggregator.  It will
probably take buffering all branch revs before sending them on.  Also,
it is not possible in the general case: not all files on a branch are
actually branched from parents that are checked in before the first file
on a branch is created.  It also makes no sense to do this for untagged
branches as there is no detectable semantic association between untagged
branches.

CVS does not try to protect itself from people checking in things that look
like snippets of CVS log file: they come out exactly like they went in,
confusing the log file parser.  So, if a repository contains messages in the
log file that look like the output from some other "cvs log" command, things
will likely go awry when using remote repositories (local repositories are
read directly and do not suffer this problem).  The direct RCS file
parser does not have this problem.

CVS stores the -k keyword expansion setting per file, not per revision,
so vcp will mark all revisions of a file with the current setting of
the -k flag for a file.

At least one cvs repository out there has multiple revisions of a single
file with the same rev number.  The second and later revisions with the
same rev number are ignored with a warning like "Can't add same revision
twice:...".

The xfree86 repository has several files 
xc/programs/Xserver/hw/xfree86//vga256/drivers/s3/s3Bt485.h:

   1.2     dead lines +1, -1
   1.1     Exp  lines
   1.2.2.2 Exp  lines +1, -1
   1.2.2.1 Exp  lines +1, -1

In this case, VCP::Source::cvs doesn't know how to retrieve rev 1.2 to
create the branch 1.2.2.x, so it uses 1.1.  If you know how to force it
to get rev 1.2, please let me know (in the future, the RCS parser will
allow this, but currently we always use cvs checkout to retrieve
versions).  I'd like to know how to use the cvs command to modify a
revision and then force it to the dead state without upping the revision
number, as that appears to have happened here.  I suspect something
other than the cvs command at play here, like the rcs command or RCS
file editing by hand or by script

=for test_script t/80rcs_parser.t t/91cvs2revml.t

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
#specified with -r.  The typical use is to get all files from a certain
#tag to now.
#
#It does this by exporting all revisions of files between the oldest and
#newest files that the -r specified.  Without C<-f>, these would
#be ignored.
#
#It is an error to specify C<-f> without C<-r>.
#
#exported.


=begin developerdocs

CVS branching needs some help to allow VCP::Dest::* drivers to branch
files appropriately because CVS branch creation (cvs rtag -b) does not
actually create a branched revision, it marks the parent revision for a
branch.

However, we need to include information about all the files that should
be branched when a branch is created.  CVS does not reliably record the
data of branch creation (though we might be able to find it in CVS
history, I have not found that to be a reliable approach; different CVS
versions seem to capture different things, at least by default).

There's a dilemma here: we need to create branched revisions for created
branches, but we don't know when to do it.  So the first time we see a
change on a branch, we create dummy revisions for all files that are
also on that branch.

These dummy revisions are VCP::Rev instances with a ".0" rev_id and with
no <digest>, <delta>, <content>, or <delete> elements.

See the docs for VCP::Rev::is_placeholder_rev().

Detection of branches that have been initiated this transfer has to
occur after unwanted revisions are thrown out (due to rev_id <
last_rev_in_filebranch or due to culling of unwanted revs) so we don't
think all branches have been created this transfer.

=end developerdocs

=cut

@ISA = qw( VCP::Source VCP::Utils::cvs );

use strict ;

use Carp ;
use VCP::Debug qw( :debug :profile ) ;
use VCP::Logger qw( lg pr pr_doing pr_done pr_done_failed BUG );
use VCP::Rev qw( iso8601format );
use VCP::Source ;
use VCP::Utils qw( empty is_win32 shell_quote start_dir_rel2abs xchdir );
use VCP::Utils::cvs ;

use constant debug_parser => 0;

#use base qw( VCP::Source VCP::Utils::cvs ) ;
#use fields (
#   'CVS_INFO',           ## Results of the 'cvs --version' command and CVSROOT
#   'CVS_REV_SPEC',       ## The revision spec to pass to `cvs log`
#   'CVS_DATE_SPEC',      ## The date spec to pass to `cvs log`
#   'CVS_WORK_DIR',       ## working directory set via --cd option
#   'CVS_USE_CVS',        ## holds the value of the --use-cvs option
#
#   'CVS_K_OPTION',       ## Which of the CVS/RCS "-k" options to use, if any
#
#   'CVS_PARSE_RCS_FILES', ## Read CVS files directly instead of through the
#                         ## cvs command.  Used if the CVSROOT looks local.
#
#   ## The following are for parsing RCS files directly
#   'CVS_RCS_FILE_PATH',  ## The file currently being scanned when reading
#                         ## RCS files directly.
#   'CVS_RCS_FILE_BUFFER', ## The file currently being scanned when reading
#   'CVS_RCS_FILE_LINES', ## How many lines have already been purged from
#                         ## CVS_RCS_FILE_BUFFER.
#   'CVS_RCS_FILE_EOF',   ## Set if we've read the end of file.
#   'CVS_MIN_REV',        ## The first desired rev_id or tag, if defined
#   'CVS_MAX_REV',        ## The first desired rev_id or tag, if defined
#
#   'CVS_READ_SIZE',      ## Used in test suite to torture the RCS parser by
#                         ## forcing a really tiny buffer size on it.
#   'CVS_ALIASED_BRANCH_TAGS', ## CVS allows filebranches to have more than
#                              ## one tag.  In this case, we clone all entries
#                              ## on the oldest tag in to entries on the
#                              ## newer tags, rev by rev, almost as though
#                              ## each was branched on to the new dest.
#   'CVS_CLONE_COUNT',         ## How many clones had to be made
#   'CVS_APPLIED_TAGS_COUNT',  ## Statistics gathering
#) ;


sub new {
   my $self = shift->SUPER::new;

   $self->{CVS_READ_SIZE} = 100_000;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_cvs_repo_spec( $spec )
      unless empty $spec;

   $self->parse_options( $options );


   return $self ;
}


sub parse_options {
   my $self = shift;
   $self->SUPER::parse_options( @_ );
}


sub options_spec {
   my $self = shift;
   return (
      $self->SUPER::options_spec,
      "cd=s"          => \$self->{CVS_WORK_DIR},
      "d=s"           => sub { shift; $self->date_spec( @_ ) },

      "k=s"           => sub {
         shift;
         $self->{CVS_K_OPTION} .= shift if @_;
         my $v = $self->{CVS_K_OPTION};
         $v =~ s/b//g if defined $v;
         defined $v && length $v ? $v : undef;
      },

      "kb"            => sub {
         shift;
         $self->{CVS_K_OPTION} .= "b" if @_;
         return defined $self->{CVS_K_OPTION} && $self->{CVS_K_OPTION} =~ "b";
      },

      "r=s"           => sub { shift; $self->rev_spec( @_ ) },
      "use-cvs"       => \$self->{CVS_USE_CVS},
   );
}


sub init {
   my $self= shift ;

   $self->SUPER::init;

   ## Set default repo_id.
   $self->repo_id( "cvs:" . $self->repo_server )
      if empty $self->repo_id && ! empty $self->repo_server ;

   $self->{CVS_PARSE_RCS_FILES} = ! $self->{CVS_USE_CVS} && do {
       # If the CVSROOT does not start with a colon, it must be
       # a direct read.  But check to see if it exists anyway,
       # because we'd prefer CVS give the error messages around here.
       my $root = $self->cvsroot;
       substr( $root, 0, 1 ) ne ":" && -d $root;
   };

   my $files = $self->repo_filespec ;
   $self->deduce_rev_root( $files ) 
      unless defined $self->rev_root;

   ## Don't normalize the filespec.
   $self->repo_filespec( $files ) ;

   ## Make sure the cvs command is available
   $self->command_stderr_filter(
      qr{^
         (?:cvs\s
             (?:
                (?:server|add|remove):\suse\s'cvs\scommit'\sto.*
                |tag.*(?:waiting for.*lock|obtained_lock).*
             )
        )\n
      }x
   ) ;

   if ( $self->{CVS_PARSE_RCS_FILES} ) {
      my $root = $self->cvsroot;
      $self->{CVS_INFO} = <<TOHERE;
CVSROOT=$root
TOHERE
      my $rev_spec = $self->rev_spec;
      if ( defined $rev_spec ) {
         for ( $rev_spec ) {
            if ( /^([^:]*):([^:]*)\z/ ) {
               @$self{qw( CVS_MIN_REV CVS_MAX_REV )} = ( $1, $2 );
            }
            else {
               die "can't parse revision specification '$rev_spec'";
            }
         }
      }
   }
   else {
      $self->cvs( ['--version' ], undef, \$self->{CVS_INFO} ) ;

      ## This does a checkout, so we'll blow up quickly if there's a problem.
      my $work_dir = $self->{CVS_WORK_DIR};
      unless ( defined $work_dir ) {
         $self->create_cvs_workspace ;
      }
      else {
         $self->work_root( start_dir_rel2abs $work_dir ) ; 
         $self->command_chdir( $self->work_path ) ;
      }
   }
}



sub ui_set_cvs_work_dir {
   my $self = shift ;
   my ($dir) = @_;

   $self->{CVS_WORK_DIR} = $dir;

   die "Warning: '$dir' not found!\n"
      unless -e $dir;
   die "Error: '$dir' exists, but is not a directory.\n"
      unless -d $dir;
}


sub rev_spec {
   my $self = shift ;
   $self->{CVS_REV_SPEC} = shift if @_ ;
   return $self->{CVS_REV_SPEC} ;
}


sub rev_spec_cvs_option {
   my $self = shift ;
   return defined $self->rev_spec? "-r" . $self->rev_spec : (),
}


sub date_spec {
   my $self = shift ;
   $self->{CVS_DATE_SPEC} = shift if @_ ;
   return $self->{CVS_DATE_SPEC} ;
}


sub date_spec_cvs_option {
   my $self = shift ;
   return defined $self->date_spec ? "-d" . $self->date_spec : (),
}


sub denormalize_name {
   my $self = shift ;
   ( my $n = '/' . $self->SUPER::denormalize_name( @_ ) ) =~ s{/+}{/}g;
   return $n;
}


sub handle_header {
   my $self = shift;
   my ( $header ) = @_;

   $header->{rep_type} = 'cvs';
   $header->{rep_desc} = $self->{CVS_INFO};
   $header->{rev_root} = $self->rev_root;


   $self->dest->handle_header( $header );
}


sub get_source_file {
   my $self = shift ;

   my $r ;
   ( $r ) = @_ ;

   BUG "can't check out ", $r->as_string, "\n"
      unless $r->is_base_rev || $r->action eq "add" || $r->action eq "edit";

   my $wp = $self->work_path( "revs", $r->source_name, $r->source_rev_id ) ;
   $self->mkpdir( $wp ) ;

   my $cvs_name = $self->SUPER::denormalize_name( $r->source_name );
       ## Use SUPER:: to avoid getting the leading '/'

   $self->cvs( [
         "checkout",
         "-r" . $r->source_rev_id,
         "-p",
         !empty( $self->{CVS_K_OPTION} )
            ? "-k" . $self->{CVS_K_OPTION}
            : (),
         $cvs_name
      ],
      undef,
      $wp,
   ) ;

   return $wp;
}


sub _concoct_cloned_rev {
   my $self = shift;
   my ( $r, $branch_tag ) = @_;

   ( my $filebranch_id = $r->source_filebranch_id ) =~ s/<.*>\z/<$branch_tag>/;

   ## The comment field is for end users and to help the changeset
   ## aggregator group things properly when "comment equal" is
   ## specified.  Really, the changeset aggregator needs to detect
   ## both the cloned-from parent and the preceding version, but
   ## we set previous_id to the cloned-from parent, not the
   ## preceding version.

   my $pr = VCP::Rev->new(
      action               => "clone",
      id                   => $r->id . "<$branch_tag clone>",
      name                 => $r->source_name,
      source_name          => $r->source_name,
      source_filebranch_id => $filebranch_id,
      source_repo_id       => $r->source_repo_id,
      time                 => $r->time,
      branch_id            => $branch_tag,
      source_branch_id     => $branch_tag,
      rev_id               => $r->source_rev_id,
      source_rev_id        => $r->source_rev_id,
      user_id              => $r->user_id,
      previous_id          => $r->id,
      comment              => $r->is_branch_rev
         ? join( "",
            "[vcp] create branch '",
            $branch_tag,
            "' by cloning '",
            $r->source_branch_id,
            "'"
         )
         : $r->comment,
   );

   if ( debugging ) {
      debug "cloned: ", $pr->as_string;
      debug "  from: ", $r->as_string;
   }

   $self->queue_rev( $pr );

   return $pr;
}


sub get_revs_from_log_file {
   my $self = shift;

   # The log command must be run in the directory above the work root,
   # since we pass in the name of the workroot dir as the first dir in
   # the filespec.
   my $tmpdir = $self->tmp_dir( "co" ) ;

   my $spec = $self->repo_filespec;
   $spec =~ s{/+(\.\.\.)?\z}{}; ## hack, since cvs always recurses.
   my @log_parms = (
      "log",
      $self->rev_spec_cvs_option,
      $self->date_spec_cvs_option,
      length $spec ? $spec : (),
   );
   pr "running ", shell_quote "cvs", @log_parms;
   $self->cvs(
      \@log_parms,
      undef,
      sub { $self->parse_cvs_log_output( @_ ) },
      {
         in_dir => $tmpdir,
         stderr_filter => sub {
            my ( $err_text_ref ) = @_ ;
            $$err_text_ref =~ s{
               ## This regexp needs to gobble newlines.
               ^cvs(?:\.exe)?\slog:\swarning:\sno\srevision\s.*?\sin\s[`"'](.*)[`"']\r?\n\r?  
               }{}gxmi ;
         },
      },
   ) ;
}


sub queue_parsed_revs {
   my $self = shift;
   my ( $file_data ) = @_;

   my @revs = values %{$file_data->{revs}};
   my $rtags = $file_data->{RTAGS};

   ## TODO: concoct_dead_edit_revs!!!
   ## TODO: add a file with multiple dead revisions to the test suite.
   ## TODO: set similar times on branch placeholders, as much as
   ## possible.  Ideal is time of oldest instantiated rev - 1 second.
   ## If no instantiated revs, do time of latest parent + 1 second.
   ## Where necessary, break in to multiple branch timings.

   for my $rev ( @revs ) {
      ## Link all revs to their preceding revs.

      ## Note that these are not yet converted to VCP::Revs, they're still
      ## HASHes keyed using RCS file format field names.

      ## TODO: Factor this code up in to the RCS scanner to save memory,
      ## processor cycles and disk space in continue mode.  This will
      ## take a bit of trickery because there's a check for existing
      ## revs up there and looking ahead to set previous on revs we
      ## haven't seen yet will mess that up.

      my $rev_id = $rev->{rev_id};
      my $next   = $rev->{next};
      unless ( empty $next ) {  ## "empty next syndrome", har har
         if ( $rev->{is_on_trunk} ) {
            ## RCS's "next" indicator on the truck points to the
            ## previous revision.
            my $prev_rev_id = $next;
            $rev->{previous_rev_id} = $prev_rev_id;
            $rev->{no_change} ||=
               $file_data->{revs}->{$prev_rev_id}->{empty_text};
         }
         else {
            ## On branches, RCS' "next" indicator points to the next
            ## revision.
            my $next_rev_id = $next;
            $file_data->{revs}->{$next_rev_id}->{previous_rev_id} = $rev_id;
            $rev->{no_change} = $rev->{empty_text};
         }
      }

   }

   for my $rev ( @revs ) {
      my $rev_id = $rev->{rev_id};

      if ( $rev->{branches} ) {
         for my $branch_rev_id ( @{$rev->{branches}} ) {
            $file_data->{revs}->{$branch_rev_id}->{previous_rev_id} = $rev_id;
            $file_data->{revs}->{$branch_rev_id}->{founds_branch} = 1;
         }
      }

      my $prev_rev_id = $rev->{previous_rev_id};
      $file_data->{revs}->{$prev_rev_id}->{next_rev_id} = $rev_id
         unless empty $prev_rev_id
   }

   my @delete_revs;
   for my $rev ( @revs ) {
      ## Split "dead" revs in to Exp + dead revs.
      if ( $rev->{state} eq "dead"
         && ( ! $rev->{no_change} ## dead rev that alters the file
            || (
               empty( $rev->{previous_rev_id} )  ## dead rev is root rev
               || $file_data->{revs}->{$rev->{previous_rev_id}}->{state}
                  eq "dead"
                  ## two consecutive dead revs require intervening edit
            )
         )
      ) {
         $rev->{state} = "Exp";
         my $delete_rev_id = "$rev->{rev_id}.0";
         my $delete_rev = $file_data->{revs}->{$delete_rev_id} = {
            %$rev,
            rev_id          => $delete_rev_id,
            previous_rev_id => $rev->{rev_id},
            author          => undef,
            date            => undef,
            state           => "dead",
            branches        => [],
            founds_branch   => 0,
            comment         => "[vcp] delete of edited revision with dead state\n",
         };
         push @delete_revs, $delete_rev;
         if ( ! empty $rev->{next_rev_id} ) {
            my $next_rev = $file_data->{revs}->{$rev->{next_rev_id}};
            $next_rev->{previous_rev_id} = $delete_rev->{rev_id};
         }
      }
   }

   for my $rev ( splice( @revs ), @delete_revs ) {
      my $rev_id = $rev->{rev_id};
      $self->compute_branch_metadata( $file_data, $rev );

      my $mode = $self->rev_mode( $rev->{filebranch_id}, $rev_id );
      next unless $mode;
      $rev->{mode} = $mode;
      push @revs, $rev;
   }

   ## Convert the hashes in to VCP::Revs and insert placeholders for
   ## all branch points.
   for my $rev ( @revs ) {
      my $rev_id = $rev->{rev_id};

      ( $rev->{previous_rev_id} = $rev_id ) =~ s{\.\d+\z}{.0}
          if $rev->{founds_branch};
          ## Point branch founding revs at branch placeholders instead
          ## of their actual parents.  Placeholders are created just
          ## below.

      my $r = $self->_create_rev( $file_data, $rev );
      next unless $r;

      $file_data->{revs}->{$rev_id} = $r;  ## TODO: try deleting this.
      for my $branch_rev_id ( @{$rev->{branches}} ) {
         ## Create branch revs (placeholders) with appropriate
         ## branch_ids from RTAGS.
         my $placeholder_rev = {
            %$rev,
            state           => "branch",
            rev_id          => $branch_rev_id,
            author          => undef,
            date            => undef,
            comment         => undef,
            previous_rev_id => $rev_id,
         };
         $placeholder_rev->{rev_id} =~ s{\.\d+\z}{.0};

         $self->compute_branch_metadata( $file_data, $placeholder_rev );

         my $mode = $self->rev_mode( $rev->{filebranch_id}, $rev_id );
         next unless $mode;
         $rev->{mode} = $mode;

         $placeholder_rev->{comment} =
            "[vcp] create branch '$placeholder_rev->{branch_id}'";
         $self->_create_rev( $file_data, $placeholder_rev );
      }
   }

   $self->store_cached_revs;
}


sub parse_rcs_files {
   my $self = shift;

   require File::Find;
   require Cwd;

   my $root = $self->cvsroot;
   my $spec = $self->repo_filespec;

#   my $cwd = Cwd::cwd;
   xchdir $root;

   ## Be compatible with cvs and recurse by default.
   $spec =~ s{/*\z}{/...} if $spec !~ m{(^|\/)\.\.\.\z} && -d $spec;
   $spec =~ s{^/+}{};

   local $| = 1;

   $File::Find::prune = 0;  ## Suppress used only once warning.

   my %seen;

   # Jump as far down the directory hierarchy as we can.
   # Figure out if this is a specific file by adding ,v
   # and checking for it (here and in the Attic), but that's
   # not worth the hassle right now.  It would save us some
   # work when pulling a file out of the top of a big dir tree,
   # though.
   ( my $start = $spec ) =~ s{(^|/+)[^/]*(\*|\?|\.\.\.).*}{};

   {
       my $where = "$root/";
       $where .= "$start/" if length $start;
       $where .= "...";

       pr_doing "scanning '$where': ";
   }

   debug "start: ", $start if debugging;
   debug "spec:  ", $spec  if debugging;

   my $files_count = 0;

   if ( -f "$start,v" ) {
      ++$files_count;
      $self->parse_rcs_file( $start );
      goto SKIP_FILE_FIND;
   }

   ( my $attic_start = $start ) =~ s{((?:[\\/]|\A))([^\\/]+)\z}{${1}Attic/$2};
   if ( -f "$attic_start,v" ) {
      ++$files_count;
      $self->parse_rcs_file( $attic_start );
      goto SKIP_FILE_FIND;
   }

   while ( length $start && ! -d $start ) {
      last unless $start =~ s{/+[^/]*\z}{};
   }

#   $spec = substr( $spec, length $start ); ## TODO: fix this for /foo/bar.../baz
   $spec =~ s{^[\\/]+}{}g;

   my $pat = $self->compile_path_re( $spec );
   debug "pattern: ", $pat if debugging;

   $start = "." unless length $start && -d $start;

   my $ok = eval {
      File::Find::find(
         {
            no_chdir => 1,
            wanted => sub {

               if ( /CVSROOT\z/ ) {
                   $File::Find::prune = 1;
                   return;
               }

               return if -d;

               s/^\.\///;
               return unless s/,v\z//;

               ( my $undeleted_path = $_ ) =~ s/(\/)Attic\//$1/;

               if ( -f _ && $undeleted_path =~ $pat ) {

                  if ( $seen{$undeleted_path}++ ) {
                      pr "already scanned '$undeleted_path,v',",
                         " ignoring '$_,v'";
                      return;
                  }

                  eval {
                     lg "parsing '", $_, "'";
                     $self->parse_rcs_file( $_ );
                     1;
                  } or do {
                     pr_done_failed;
                     die "$@ for $_\n";
                  };

                  ++$files_count;
               }

               pr_doing;
            },
         },
         $start
      );
      1;
   };
   my $x = $@;

   die $x unless $ok;

SKIP_FILE_FIND:

   pr_done "found $files_count files";
}

## Used to detect symbols for branch tags and vendor branch tags.
sub _is_branch_or_vendor_tag($) {
   return $_[0] =~ /\.0\.\d+\z/
      || ! ( $_[0] =~ tr/.// % 2 );
}


sub analyze_file_data {
   ## Compute file-level information once the file metadata has been
   ## parsed and before any revisions have been parsed.
   my $self = shift;
   my ( $file_data ) = @_;

   debug "analyzing file data" if debugging && debug_parser;

   my $norm_name = $self->normalize_name( $file_data->{working} );

   $file_data->{norm_name}   = $norm_name;
   $file_data->{denorm_name} = $self->denormalize_name( $norm_name );
   $file_data->{revs}        = {};
   my $rtags = $file_data->{RTAGS};
   for my $rev_id ( keys %$rtags ) {
      next unless _is_branch_or_vendor_tag $rev_id;

      my @tags = @{$rtags->{$rev_id}};
      my $master_tag = pop @tags;
      next unless @tags;

      $self->{CVS_ALIASED_BRANCH_TAGS}->{$master_tag} = \@tags;
   }
}

sub analyze_branches {
   ## Takes @{$rev_data->{branches}}, a ARRAY of rev_ids of branched
   ## rev_ids and adds branches that do not yet have revs on them
   ## by looking at the keys of $file_data->{RTAGS} for magic branch
   ## numbers.  Does not need the final number in the branches in
   ## $rev_data->{branches} to be accurate.
   my $self = shift;
   my ( $file_data, $rev_data ) = @_;

   my @branches = @{$rev_data->{branches} || []};
      ## This misses branches with no revs on them, must scan RTAGS

   my %populated_branches = map {
      ( my $magic_branch_number = $_ ) =~ s{(\.\d+)\.\d+\z}{.0$1};
      ( $magic_branch_number => undef );
   } @branches;

   my $magic_branch_id_prefix = $rev_data->{rev_id} . ".0.";
   ## Add in labelled but empty branches from the tags (symbols)
   ## list
   push @branches, 
      map {
         ( my $placeholder_rev_id = $_ ) =~ s{\.0(\.\d+)\z}{$1};
         "$placeholder_rev_id.0"
      }
      grep(
         ( ( 0 == index $_, $magic_branch_id_prefix )
            && ! exists $populated_branches{$_}
         ),
         keys %{$file_data->{RTAGS}}
      );

   $rev_data->{branches} = \@branches;
}

{
   my $special = "\$,.:;\@";
   my $idchar = "[^\\s$special\\d\\.]";  # Differs from man rcsfile(1)
   my $num_re = "[0-9.]+";
   my $id_re = "(?:(?:$num_re)?$idchar(?:$idchar|$num_re)*)";

   my %id_map = (
       # RCS file => "cvs log" (& its parser) field name changes
       "log"    => "comment",
       "expand" => "keyword",
   );

   sub _xdie {
      my $self = shift;
      my $buffer = $self->{CVS_RCS_FILE_BUFFER};

      my $pos = pos( $$buffer ) || 0;

      my $line = $self->{CVS_RCS_FILE_LINES}
         + ( substr( $$buffer, 0, $pos ) =~ tr/\n// );

      my $near = substr( $$buffer, $pos, 100 );
      $near .= "..." if $pos + 100 > length $$buffer;

      $near =~ s/\n/\\n/g;
      $near =~ s/\r/\\r/g;
      die @_, " in RCS file $self->{CVS_RCS_FILE_PATH}, near line $line: '$near'\n";
   }

   sub _read_rcs_goodness {
      my $self = shift;
      my ( $fh ) = @_;

      $self->_xdie( "read beyond end of file" )
         if $self->{CVS_RCS_FILE_EOF};

      my $buffer = $self->{CVS_RCS_FILE_BUFFER};

      my $pos = pos( $$buffer ) || 0; ## || 0 in case no matches yet.
      $self->{CVS_RCS_FILE_LINES} += substr( $$buffer, 0, $pos ) =~ tr/\n//;
      substr( $$buffer, 0, $pos ) = "";

      my $c = 0;
      {
         my $little_buffer;
         $c = read $fh, $little_buffer, $self->{CVS_READ_SIZE};

         ## Hmmm, sometimes $c comes bak undefined at end of file,
         ## with $! not TRUE.  most odd.  Tested with 5.6.1 and 5.8.0
         $self->_xdie( "$! reading rcs file" )
            if ! defined $c && $!;

         $$buffer .= $little_buffer if $c;
      };

      pos( $$buffer ) = 0;  ## Prevent undefs from tripping up code later
      $self->{CVS_RCS_FILE_EOF} ||= ! $c;
      1;
   }

   sub compute_branch_metadata {
      ## Given a rev data structure on a branch, fill in the various
      ## branch-related values needed to create a VCP::Rev
      my $self = shift;
      my ( $file_data, $rev ) = @_;

      ( my $branch_number = $rev->{rev_id} ) =~
         s{\A(\d+(?:\.\d+\.\d+)*)\.\d+(\.\d+)?\z}{$1};
         ## Deal with an odd number of dots by making the branch number
         ## have an even number.  Odd numbers of dots on rev_ids are
         ## used when VCP::Source::cvs needs to impute two revs from
         ## one, for instance when an edit rev (ie one with changed
         ## content) is marked dead.

      if ( $branch_number =~ tr/.// ) {
         $rev->{branch_number} = $branch_number;
         my @n = split /\D+/, $rev->{branch_number};
         $rev->{on_vendor_branch} = $n[-1] % 2;
         my $tagged_branch_id=
            $rev->{on_vendor_branch}
               ? $rev->{branch_number}
               : join ".", @n[0..$#n-1], 0, $n[-1];

         my $rtags = $file_data->{RTAGS};
         if ( exists $rtags->{$tagged_branch_id} ) {
            my @branch_tags = @{$rtags->{$tagged_branch_id}};
            $rev->{branch_id} =
               $rev->{master_branch_tag} = $branch_tags[-1]
               ## The last one in the list is the oldest, or "master" branch tag
         }
         else {
            $rev->{branch_id} = "_branch_$rev->{branch_number}";
               ## TODO: allow the user to specify a format string for this
         }
         $rev->{filebranch_id} = "$file_data->{denorm_name}<$branch_number>";
      }
      else {
         $rev->{filebranch_id} = "$file_data->{denorm_name}<>";
      }
   }

   sub parse_rcs_file {
      my $self = shift;

      profile_start ref( $self ) . " parse_rcs_file()" if profiling;

      my ( $file ) = @_;

      require File::Spec::Unix;
      my $path = $self->{CVS_RCS_FILE_PATH} = File::Spec::Unix->canonpath(
         join "", $self->cvsroot, "/", $file, ",v"
      );

      debug "going to read $path" if debugging;

      open F, "<$path" or die "$!: $path\n";
      binmode F;

      my $rev_id;

      $file =~ s{\A(.*?)[\\/]+Attic}{$1};
      $file =~ s{([\\/])[\\/]+}{$1}g;
      my $norm_name = $self->normalize_name( $file );

      my $file_data = {
         rcs         => $path,
         working     => $file,
      };

      $self->{CVS_RCS_FILE_EOF} = 0;
      $self->{CVS_RCS_FILE_LINES} = 0;
      $self->{CVS_RCS_FILE_BUFFER} = \(my $b = "");
      local $_;
      *_ = $self->{CVS_RCS_FILE_BUFFER};
      pos = 0;

      my $h;  # which hash to stick the data in.  As the parsing progresses,
              # this is pointed at the per-file metadata
              # hash or a per-revision hash so that the low level
              # key/value parsing just parses things and stuffs them 
              # in $h and it'll be stuffing them in the right place.

      my $id; # the name of the element to assign the next value to

   START:
      $self->_read_rcs_goodness( \*F );
      if ( /\A($id_re)\s+(?=\S)/gc ) {
         $h = $file_data;
         $id = $1;
         $id = $id_map{$id} if exists $id_map{$id};

         # had a buggy RE once...
         $self->_xdie( "$id should not have been parsed as an identifier" )
            if $id =~ /\A$num_re\z/o;

         debug "parsing field ", $id
            if debug_parser && debugging;

         goto VALUE;
      }
      else {
         ## ASSume first identifier < 100 chars
         if ( ! $self->{CVS_RCS_FILE_EOF} && length() < 100 ) {
            debug "reading more for START parsing"
               if debug_parser && debugging;

            $self->_read_rcs_goodness( \*F );
            goto START;
         }

         $self->_xdie( "RCS file should begin with an identifier" );
      }

   PARAGRAPH_START:
      if ( /\G($num_re)\r?\n/gc ) {
         $rev_id = $1;

         if ( $h == $file_data && ! $file_data->{revs} ) {
            $self->analyze_file_data( $file_data );
         }

         if ( debug_parser && debugging ) {
            my $is_new = ! exists $file_data->{revs}->{$rev_id};
            debug
               "parsing", $is_new ? () : " MORE", " ", $rev_id, " fields";
         }

         ## Throw away unwanted revs ASAP to save space and so the part of
         ## the culling algorithm that estimates limits can find the
         ## oldest / newest wanted revs easily.
         my $keep = 1;
         $keep
            &&= VCP::Rev->cmp_id( $rev_id, $file_data->{min_rev_id} ) >= 0
            if defined $file_data->{min_rev_id};
         $keep
            &&= VCP::Rev->cmp_id( $rev_id, $file_data->{max_rev_id} ) <= 0
            if defined $file_data->{max_rev_id};

         if ( $keep ) {
            ## Reuse the existing hash if this is a second pass
            $h = $file_data->{revs}->{$rev_id} ||= {};
         }
         else {
            ## create a throw-away hash to keep the logic simpler
            ## in the parser (this way it doesn't have to test
            ## $h for definedness each time before writing it).
            $h = {};
         }
         $h->{rev_id} = $rev_id;
         $h->{is_on_trunk} = ( $rev_id =~ tr/.// ) == 1;
         $id = undef;

         goto ID;
      }
      elsif ( /\Gdesc\s+(?=\@)/gc ) {
         ## We're at the end of the first set of per-rev sections of the
         ## RCS file, switch back to the per-file metadata hash to capture
         ## the "desc" field.
         $h = $file_data;
         $id = "desc";
         $id = $id_map{$id} if exists $id_map{$id};
         debug "parsing field ", $id
            if debug_parser && debugging;

         goto VALUE;
      }
      else {
         ## ASSume no identifier or rev number is > approx 1000 chars long
         if ( ! $self->{CVS_RCS_FILE_EOF} && length() - pos() < 1000 ) {
            debug "reading more for PARAGRAPH_START parsing"
               if debug_parser && debugging;

            $self->_read_rcs_goodness( \*F );
            goto PARAGRAPH_START;
         }

         $self->_xdie( "expected an identifier or version string" );
      }

   ID:
      if ( /\G($id_re)(?:\s+(?=\S)|\s*(?=;))/gc ) { # No ^, unlike PARAGRAPH_START's first RE
         $id = exists $id_map{$1} ? $id_map{$1} : $1;

         # had a buggy RE once...
         $self->_xdie( "$id should not have been parsed as an identifier" )
            if debug_parser && $id =~ /\A$num_re\z/o;

         debug "parsing field ", $id
            if debug_parser && debugging;

#         goto VALUE;
      }
      else {
         ## ASSume no identifier > approx 1000 chars long
         if ( ! $self->{CVS_RCS_FILE_EOF} && length() - pos() < 1000 ) {
            debug "reading more for ID parsing"
               if debug_parser && debugging;

            $self->_read_rcs_goodness( \*F );
            goto ID;
         }

         $self->_xdie( "expected an identifier or version string" );
      }

   VALUE:
      $self->_xdie( "already assigned to '$h->{$id}'" )
         if debug_parser && exists $h->{$id};

   VALUE_DATA:
      if ( substr( $_, pos, 1 ) eq ";" ) { #/\G(?=;)/gc ) {
         $h->{$id} = "";
      }
      elsif ( /\G\@/gcs ) {
         # It's an RCS string (@...@)

         if ( $id eq "text" ) {
            $h->{$id} = "TEXT NOT EXTRACTED FROM RCS FILE";
            $h->{empty_text} = 1;
         }
         else {
            $h->{$id} = "";
         }

      STRING:
         ## The 1000 limits perl's internal regex recursion limit to
         ## well below the 32766 limit.  That's ok here because we keep
         ## looping back for more (originally the {0,1000} was a *).
         while ( /\G((?:[^\@]+|(?:\@\@)+){0,1000})/gc ) {
            if ( $id eq "text" ) {
               $h->{empty_text} &&= !length $1;
            }
            else {
               $h->{$id} .= $1;
            }
         }

         unless ( /\G\@(?=[^\@])/gc ) {
            # NOTE: RCS files must end in a newline, so it's safe
            # to assume a non-@ after the @.
            debug "reading more for STRING parsing"
               if debug_parser && debugging;

            $self->_read_rcs_goodness( \*F );
            goto STRING;
         }

         $self->_xdie( "odd number of '\@'s in RCS string for field '$id'" )
             if ( $h->{$id} =~ tr/\@// ) % 2;

         $h->{$id} =~ s/\@\@/\@/g;

#         goto VALUE_END;
      }
      elsif ( /\G(?!\@)/gc ) {
         # Not a string, so it's a semicolon delimited value

      NOT_STRING:
         if ( /\G([^;]+)/gc ) {
            $h->{$id} .= $1;
            unless ( /\G(?=;)/gc ) {
               debug "reading more for NOT_STRING parsing"
                  if debug_parser && debugging;

               $self->_read_rcs_goodness( \*F );
               goto NOT_STRING;
            }
         }

         if ( $id eq "date" ) {
            ## The below seems to monkey with $_, so protect pos().
            my $p = pos;
            $h->{time} = $self->parse_time( $h->{date} );
            pos = $p;
         }

#         goto VALUE_END;
      }
      else {
         # We only need one char.
         if ( ! $self->{CVS_RCS_FILE_EOF} && length() - pos() < 1 ) {
            debug "reading more for VALUE_DATA parsing"
               if debug_parser && debugging;

            $self->_read_rcs_goodness( \*F );
            goto VALUE_DATA;
         }
         $self->_xdie( "unable to parse value for $id" );
      }

   VALUE_END:
      debug "$id='",
         substr( $h->{$id}, 0, 100 ),
         length $h->{$id} > 100 ? "..." : (),
         "'"
         if debug_parser && debugging;

      if ( $id eq "symbols" ) {
         my %tags;

         for ( split /\s+/, $h->{symbols} ) {
            my ( $tag, $rev_id ) = split /:/, $_, 2;
            $tags{$tag} = $rev_id;
            push @{$h->{RTAGS}->{$rev_id}}, $tag;
         }
         delete $h->{symbols};

         ## Convert the passed-in min and max revs from symbolic tags
         ## to dotted rev numbers.  The "symbols" $id only occurs
         ## once in a file, so this gets executed once and is setting
         ## fields in the file metadata (not in a rev's metadata).
         if ( ! empty $self->{CVS_MIN_REV} ) {
            my $min_rev_id = $self->{CVS_MIN_REV};

            if ( $min_rev_id =~ /[^\d.]/ ) {
               $min_rev_id = exists $tags{$min_rev_id}
                  ? $tags{$min_rev_id}
                  : undef;

               if ( empty $min_rev_id ) {
                  # $min_rev_id was a tag that is not found.  Emulate
                  # cvs -r and skip this file entirely.
                  lg "-r tag $self->{CVS_MIN_REV} not found in $h->{rcs}";
                  return;
               }
            }

            $h->{min_rev_id} = [ VCP::Rev->split_id( $min_rev_id ) ];
         }

         if ( ! empty $self->{CVS_MAX_REV} ) {
            my $max_rev_id = $self->{CVS_MAX_REV};

            if ( $max_rev_id =~ /[^\d.]/ ) {
               $max_rev_id = exists $tags{$max_rev_id}
                  ? $tags{$max_rev_id}
                  : undef;

               if ( empty $max_rev_id ) {
                  # $max_rev_id was a tag that is not found.  Emulate
                  # cvs -r and skip this file entirely.
                  lg "-r tag $self->{CVS_MAX_REV} not found in $h->{rcs}";
                  return;
               }
            }

            $h->{max_rev_id} = [ VCP::Rev->split_id( $max_rev_id ) ];
         }
      }
      elsif ( $id eq "branches" ) {
         $h->{branches} = [
            grep length, split /[^0-9.]+/, $h->{branches}
         ];
         $self->analyze_branches( $file_data, $h );
      }

      $id = undef;

   VALUE_END_DELIMETER:
      if ( /\G[ \t]*(?:\r?\n|;[ \t]*(?:\r?\n|(?=[^ \t;]))|(?=[^ \t;]))/gc ) {
      VALUE_END_WS:
         if ( /\G(?=\S)/gc ) {
            goto ID;
         }

         if ( /\G[ \t\r\n]*(\r?\n)+(?=\S)/gc ) {
            goto PARAGRAPH_START;
         }

         ## ASSume no runs of \v or \r\n of mroe than 1000 chars.
         if ( ! $self->{CVS_RCS_FILE_EOF} && length() - pos() < 1000 ) {
            debug "reading more for VALUE_END_WS parsing"
               if debug_parser && debugging;

            $self->_read_rcs_goodness( \*F );
            goto VALUE_END_WS;
         }

         goto FINISHED unless length;

         if ( ! /\G(\r?\n)/gc ) {
            $self->_xdie( "expected newline" );
         }
      }

      # ASSume semi + whitespace + 1 more char is less than 1000 bytes
      if ( length() - pos() < 1000 ) {
         debug "reading more for VALUE_END_DELIMETER parsing"
            if debug_parser && debugging;

         eval {
            $self->_read_rcs_goodness( \*F );
            goto FINISHED if /\G(\r?\n)*\z/gc;
            goto VALUE_END_DELIMETER;
         };
         if ( 0 == index $@, "read beyond end of file" ) {
            goto FINISHED if /\G(\r?\n)*\z/gc;
         }
         else {
            die $@;
         }

      }
      $self->_xdie( "expected optional semicolon and tabs or spaces" );

   FINISHED:

      close F;
      $self->{CVS_RCS_FILE_BUFFER} = undef;

      $self->queue_parsed_revs( $file_data );

      profile_end ref( $self ) . " parse_rcs_file()" if profiling;
   }
}  ## this ends a scope, not a sub {}


sub scan_metadata {
   my $self = shift ;

   $self->{CVS_ALIASED_BRANCH_TAGS} = undef;
   $self->{CVS_CLONE_COUNT} = undef;

   if ( $self->{CVS_PARSE_RCS_FILES} ) {
      $self->parse_rcs_files;
   }
   else {
      $self->get_revs_from_log_file;
   }

   ## conserve memory
   $self->{CVS_ALIASED_BRANCH_TAGS} = undef;

   pr "found ",
      $self->sent_rev_count, " rev(s)",
      $self->{CVS_CLONE_COUNT}
         ? " ($self->{CVS_CLONE_COUNT} cloned)"
         : (),
      defined $self->{CVS_APPLIED_TAGS_COUNT}
         ? " with $self->{CVS_APPLIED_TAGS_COUNT} tag applications"
         : (),
      "\n";
}


# Here's a typical file log entry.
#
###############################################################################
#
#RCS file: /var/cvs/cvsroot/src/Eesh/Changes,v
#Working file: src/Eesh/Changes
#head: 1.3
#branch:
#locks: strict
#access list:
#symbolic names:
#        Eesh_003_000: 1.3
#        Eesh_002_000: 1.2
#        Eesh_000_002: 1.1
#keyword substitution: kv
#total revisions: 3;     selected revisions: 3
#description:
#----------------------------
#revision 1.3
#date: 2000/04/22 05:35:27;  author: barries;  state: Exp;  lines: +5 -0
#*** empty log message ***
#----------------------------
#revision 1.2
#date: 2000/04/21 17:32:14;  author: barries;  state: Exp;  lines: +22 -0
#Moved a bunch of code from eesh, then deleted most of it.
#----------------------------
#revision 1.1
#date: 2000/03/24 14:54:10;  author: barries;  state: Exp;
#*** empty log message ***
#=============================================================================
#############################################################################

sub clean_log_output {
   my $self = shift;
   my ( $file_data, $rev_data ) = @_;

   $self->analyze_branches( $file_data, $rev_data );

   $rev_data->{comment} = ''
      if $rev_data->{comment} eq '*** empty log message ***' ;

   $rev_data->{comment} =~ s/\r\n|\n\r/\n/g ;

   if ( $file_data->{last_rev} ) {
      ( my $last_branch_num = $file_data->{last_rev}->{rev_id} )
         =~ s/\.(\d+)\z//;
      my $last_branch_rev_id_not_rev_one = $1 ne 1;
      $last_branch_num = "" unless 0 <= index $last_branch_num, ".";

      my $rev_id = $rev_data->{rev_id};
      ( my $branch_num = $rev_id ) =~ s/\.\d+\z//;
      $branch_num = "" unless 0 <= index $branch_num, ".";

      if ( $last_branch_num eq $branch_num ) {
         ## Revs are logged newest to oldest, so...
         $file_data->{last_rev}->{previous_rev_id} = $rev_id;
      }
      elsif ( length $last_branch_num ) {
         if ( $last_branch_rev_id_not_rev_one ) {
            ## The last rev was the oldest rev on its branch.  Note it
            ## so that the oddball .0000 rev_ids faked up in other
            ## revs' @{$rev_data->{branches}} can be cleaned up.
            $file_data->{branch_founding_rev_ids}->{$last_branch_num} =
               $file_data->{last_rev}->{rev_id};
         }
      }
   }

   $file_data->{last_rev} = $rev_data;
}


sub clean_up_guessed_branch_rev_ids {
   ## The cvs rlog does not tell us the rev_ids of revisions that
   ## found branches, so the parser puts funny looking revision
   ## ids in @{$rev_data->{branches}}.  We now know the first one
   ## we saw on each branch, so go back and fix things up where
   ## possible.
   my $self = shift;
   my ( $file_data ) = @_;

   my $h = delete $file_data->{branch_founding_rev_ids};

   for my $rev_data ( values %{$file_data->{revs}} ) {
      next unless $rev_data->{branches};
      for ( @{$rev_data->{branches}} ) {
         next unless substr( $_, -5 ) eq ".0000";
         my $branch_num = substr( $_, 0, -5 );
         $_ = exists $h->{$branch_num}
            ? $h->{$branch_num}
            : "$branch_num.1";
      }
   }
}


sub parse_cvs_log_output {
   ## Takes a filehandle and extracts all files and revs from it.
   ## This is different from parse_rcs_file because that's called
   ## once per file and this is called once for all files.

   my ( $self, $fh ) = @_ ;

   profile_start ref( $self ) . " parse_cvs_log_output()" if profiling;

   local $_ ;

   my $file_data = {};
   my $h = $file_data;   ## which hash to stick the data in.
   my $saw_equals;
   my $state = "file_data";

   ## DOS, Unix, Mac lineends spoken here.
   while ( <$fh> ) {
      s/\r//g if is_win32;
      ## [1] See bottom of file for a footnote explaining this delaying of 
      ## clearing $file_data and $state until we see
      ## a ========= line followed by something other than a -----------
      ## line.
      ## TODO: Move to a state machine design, hoping that all versions
      ## of CVS emit similar enough output to not trip it up.

      ## TODO: BUG: Turns out that some CVS-philes like to put text
      ## snippets in their revision messages that mimic the equals lines
      ## and dash lines that CVS uses for delimiters!!

   PLEASE_TRY_AGAIN:
      if ( debugging && debug_parser ) {
         ( my $foo = $_ ) =~ s/[\r\n]*//g;
         debug "$state [$foo]";
      }

      if ( /^={50,}$/ ) {
         debug "=======" if debugging && debug_parser;
         if ( $h ) {
            $h == $file_data
               ? $self->analyze_file_data( $file_data )
               : $self->clean_log_output( $file_data, $h );
         }
         $saw_equals = 1;
         $h = undef;
      }
      elsif ( /^-{25,}$/ ) {
         debug "-----" if debugging && debug_parser;
         ## There's at least one CVS repository out there with
         ## munged revs that results in a "====" line followed by
         ## a "-----" line and followed by more revision data.
         ## In this case, $h will be empty (it was cleared when the
         ## "=====" was seen).
         if ( $h ) {
            $h == $file_data
               ? $self->analyze_file_data( $file_data )
               : $self->clean_log_output( $file_data, $h );
         }
         $saw_equals = 0 ;
         $h = undef;
         $state = "rev_wait" ;
      }
      else {
         if ( $saw_equals ) {
            ## If we get here, then the ==== line we saw really is the start
            ## of a new file.  Sweep up after the last one and begin anew.
            if ( keys %$file_data && $file_data->{revs} ) {
               $self->clean_up_guessed_branch_rev_ids( $file_data );
               $self->queue_parsed_revs( $file_data );
            }

            $h = $file_data = {};
            $state = "file_data";
            $saw_equals = 0 ;
         }

         if ( $state eq "file_data" ) {
            if (
               /^(RCS file|Working file|head|branch|locks|access list|keyword substitution):\s*(.*)/i
            ) {
               $file_data->{lc( (split /\s+/, $1 )[0] )} = $2 ;
            }
            elsif ( /^total revisions:\s*([^;]*)/i ) { }
            elsif ( /^symbolic names:/i )            { $state = "tags" }
            elsif ( /^description:/i )               { $state = 'desc' }
            else {
               carp "Unhandled CVS log line '$_'" if /\S/ ;
            }
         }
         elsif ( $state eq 'tags' ) {

            if ( /^\S/ ) {
               $state = "file_data";
               goto PLEASE_TRY_AGAIN ;
            }

            my ( $tag, $rev_id ) = m{(\S+):\s+(\S+)} ;
            unless ( defined $tag ) {
               carp "Can't parse tag from CVS log line '$_'" ;
               $state = "file_data";
            }
            else {
               push( @{$file_data->{RTAGS}->{$rev_id}}, $tag ) ; 
            }
         }
         elsif ( $state eq "rev_wait" ) {
            my ( $rev_id ) = m/([\d.]+)/;
            $h = $file_data->{revs}->{$rev_id} = {
               rev_id => $rev_id,
            };
            $state = "rev_data" ;
         }
         elsif ( $state eq "rev_data" ) {
            for ( split /;\s*/ ) {
               my ( $key, $value ) = m/(\S+):\s+(.*?)\s*$/ ;
               $h->{lc($key)} = $value ;
            }
            $h->{no_change} =
                defined $h->{lines} && $h->{lines} eq "+0 -0";
            $state = 'rev_branches_or_message' ;
         }
         elsif ( $state eq 'rev_branches_or_message' ) {
            if ( /\Abranches:\s+(.*);$/ ) {
               my @branch_numbers = grep length, split /[^\d.]+/, $1;
               $h->{branches} = [
                  map "$_.0000", @branch_numbers
                     ## We don't know the actual rev_id of the first
                     ## rev on a branch, so put an odd looking number
                     ## there as a flag for touch up.  This
                     ## is adequate for analyze_branches and for
                     ## placeholder creation.  It is not adequate for
                     ## setting the previous_ids of the *real* first
                     ## rev on each branch because that rev's rev_id
                     ## *may* not be a .1 rev.
               ];
            }
            else {
               $h->{comment} .= $_;
            }
         }
         elsif ( $state eq "desc" ) {
            ## NOOP, ignore the description field for now.
            ## Perhaps use it as a comment on the first rev??
         }
         else {
            BUG "unknown parser state '$state'";
         }
      }
   }

   ## Never, ever forget the last rev.  "Wait for me! Wait for me!"
   ## Most of the time, this should not be a problem: cvs log puts a
   ## line of "=" at the end.  But just in case I don't know of a
   ## funcky condition where that might not happen...
   if ( $h ) {
      $h == $file_data
         ? () ## No need to analyze file_data if no revs found...
         : $self->clean_log_output( $file_data, $h );
   }

   if ( keys %$file_data && $file_data->{revs} ) {
      $self->clean_up_guessed_branch_rev_ids( $file_data );
      $self->queue_parsed_revs( $file_data );
   }

   profile_end ref( $self ) . " parse_cvs_log_output()" if profiling;
}


# Here's a (probably out-of-date by the time you read this) dump of the args
# for _create_rev:
#
###############################################################################
#$file = {
#  'WORKING' => 'src/Eesh/eg/synopsis',
##  'SELECTED' => '2',
#  'LOCKS' => 'strict',
##  'TOTAL' => '2',
#  'ACCESS' => '',
#  'RCS' => '/var/cvs/cvsroot/src/Eesh/eg/synopsis,v',
#  'KEYWORD' => 'kv',
#  'RTAGS' => {
#    '1.1' => [
#      'Eesh_003_000',
#      'Eesh_002_000'
#    ]
#  },
#  'HEAD' => '1.2',
###  'TAGS' => {   <== not used, so commented out.
###    'Eesh_002_000' => '1.1',
###    'Eesh_003_000' => '1.1'
###  },
#  'BRANCH' => ''
#};
#$rev = {
#  'DATE' => '2000/04/21 17:32:16',
#  'comment' => 'Moved a bunch of code from eesh, then deleted most of it.
#',
#  'STATE' => 'Exp',
#  'AUTHOR' => 'barries',
#  'REV' => '1.1'
#};
###############################################################################

sub _create_rev {
   my $self = shift ;
   my ( $file_data, $rev_data ) = @_ ;

   BUG "No state" if empty $rev_data->{state};
   BUG "no denorm_name" if empty $file_data->{denorm_name};

   my $norm_name = $file_data->{norm_name};

   my $is_branch = $rev_data->{state} eq "branch";

   my $action = $rev_data->{state} eq "dead"
      ? "delete"
      : $is_branch
         ? "branch"
         : "edit";

   my $type =
      defined $file_data->{keyword}
      && $file_data->{keyword} =~ /[o|b]/
          ? "binary"
          : "text"
      if ! $is_branch;

   my $rev_id = $rev_data->{rev_id};

   my $branch_id = $rev_data->{branch_id};

   my $denorm_name = $file_data->{denorm_name};
   my $id = "$denorm_name#$rev_id";
   my $previous_id;
   $previous_id = "$denorm_name#$rev_data->{previous_rev_id}"
      unless empty $rev_data->{previous_rev_id};

   my $labels = $file_data->{RTAGS}->{$rev_id};
   $self->{CVS_APPLIED_TAGS_COUNT} += @$labels
      if $labels;

   my $r = VCP::Rev->new(
      id                   => $id,
      name                 => $norm_name,
      source_name          => $norm_name,
      rev_id               => $rev_id,
      source_rev_id        => $rev_id,
      type                 => $type,
      action               => $action,
      time                 => defined $rev_data->{date}
         ? $self->parse_time( $rev_data->{date} )
         : undef,
      user_id              => $rev_data->{author},
      labels               => $labels,
      branch_id            => $branch_id,
      source_branch_id     => $branch_id,
      source_filebranch_id => $rev_data->{filebranch_id},
      source_repo_id       => $self->repo_id,
      previous_id          => $previous_id,
      comment              => $rev_data->{comment},
   );

   $r->base_revify if $rev_data->{mode} eq "base";

   return unless $self->queue_rev( $r );

   my $mbt = $rev_data->{master_branch_tag};

   if (
      defined $mbt
      && exists $self->{CVS_ALIASED_BRANCH_TAGS}->{$mbt}
   ) {

      for my $cloned_tag (
         @{$self->{CVS_ALIASED_BRANCH_TAGS}->{$mbt}}
      ) {
         $self->_concoct_cloned_rev( $r, $cloned_tag );
      }

   }
   return $r;
}

## FOOTNOTES:
# [1] :pserver:guest@cvs.tigris.org:/cvs hass some goofiness like:
#----------------------------
#revision 1.12
#date: 2000/09/05 22:37:42;  author: thom;  state: Exp;  lines: +8 -4
#
#merge revision history for cvspatches/root/log_accum.in
#----------------------------
#revision 1.11
#date: 2000/08/30 01:29:38;  author: kfogel;  state: Exp;  lines: +8 -4
#(derive_subject_from_changes_file): use \t to represent tab
#characters, not the incorrect \i.
#=============================================================================
#----------------------------
#revision 1.11
#date: 2000/09/05 22:37:32;  author: thom;  state: Exp;  lines: +3 -3
#
#merge revision history for cvspatches/root/log_accum.in
#----------------------------
#revision 1.10
#date: 2000/07/29 01:44:06;  author: kfogel;  state: Exp;  lines: +3 -3
#Change all "Tigris" ==> "Helm" and "tigris" ==> helm", as per Daniel
#Rall's email about how the tigris path is probably obsolete.
#=============================================================================
#----------------------------
#revision 1.10
#date: 2000/09/05 22:37:23;  author: thom;  state: Exp;  lines: +22 -19
#
#merge revision history for cvspatches/root/log_accum.in
#----------------------------
#revision 1.9
#date: 2000/07/29 01:12:26;  author: kfogel;  state: Exp;  lines: +22 -19
#tweak derive_subject_from_changes_file()
#=============================================================================
#----------------------------
#revision 1.9
#date: 2000/09/05 22:37:13;  author: thom;  state: Exp;  lines: +33 -3
#
#merge revision history for cvspatches/root/log_accum.in
#

=head1 SEE ALSO

L<VCP::Dest::cvs>, L<vcp>, L<VCP::Process>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
