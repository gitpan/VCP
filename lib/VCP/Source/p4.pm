package VCP::Source::p4;

=head1 NAME

VCP::Source::p4 - A Perforce p4 repository source

=head1 SYNOPSIS

   vcp p4://depot/...@10          # all files after change 10 applied
   vcp p4://depot/...@1,10        # changes 1..10
   vcp p4://depot/...@-2,10       # changes 8..10
   vcp p4://depot/...@1,#head     # changes 1..#head
   vcp p4://depot/...@-2,#head    # changes 8..10
   vcp p4:...@-2,#head            # changes 8..10, if only one depot

To specify a user name of 'user', P4PASSWD 'pass', port 'host:1666',
and p4 client 'client' use this syntax:

   vcp p4:user(client):pass@host:1666:files

Or, to run against a private p4d in a local directory, use this syntax
and the --run-p4d option:

   vcp p4:user(client):pass@/dir:files
   vcp p4:user(client):pass@/dir:1666:files

Note: VCP will set the environment variable P4PASSWD rather than
sending the password to p4 via the command line, so it shouldn't show
up in error messages.  This means that a password specified in a
P4CONFIG file will override the one set on the VCP command line.  This
is a bug.  User, client and the server string will be passed as
command line options to make them show up in error output.

You may use the P4... environment variables instead of any or all of the
fields in the p4: repository specification.  The repository spec
overrides the environment variables.

If the L<P4::Client> Perl module is installed, this will be used instead
of the p4 command line utility.  If this causes undesirable results, set
the environment variable VCPP4API equal to "0" (zero).

=head1 DESCRIPTION

Driver to allow L<vcp|vcp> to extract files from a
L<Perforce|http://perforce.com/> repository.

Note that not all metadata is extracted: users, clients and job tracking
information is not exported, and only label names are exported.

Also, the 'time' and 'mod_time' attributes will lose precision, since
p4 doesn't report them down to the minute.  Hmmm, seems like p4 never
sets a true mod_time.  It gets set to either the submit time or the
sync time.  From C<p4 help client>:

    modtime         Causes 'p4 sync' to force modification time 
                    to when the file was submitted.

    nomodtime *     Leaves modification time set to when the
                    file was fetched.

=head1 OPTIONS

See also the OPTIONS sections in L<VCP::Source|VCP::Source/OPTIONS>
and L<VCP::Driver/OPTIONS>.

=over

=item --run-p4d

Runs a p4d instance in the directory indicated by repo_server (use a
directory path rather than a host name).  If repo_server contains a
port, that port will be used, otherwise a random port will be used.

Dies unless the directory exists and contains files matching db.* (to
help prevent unexpected initializing of empty directories).

VCP will kill this p4d when it's done.

=item --follow-branch-into

Causes VCP to notice "branch into" messages in the output of p4's
filelog command and.  If the file that's the target of the p4
integrate (branch) command is revision number #1, adds the target to
the list of exported files.  This usually needs a --rev-root option to
set the rev root to be high enough in the directory tree to include
all branches (it's an error to export a file that is not under the rev
root).

=item --rev-root

Sets the "revisions" root of the source tree being extracted; without this
option, VCP assumes that you are extracting the directory tree ending in the
last path segment in the filespec without a wildcard.  This allows you to
specify a shorter root directory, which can be useful especially with
--follow-branch-into, since branches may often lead off from the current
directory to peer directories or even in to entirely different trees.

The default C<rev-root> is the file spec up to the first path segment
(directory name) containing a wildcard, so

   p4:/a/b/c...

would have a rev root of C</a/b>.

In direct repository-to-repository transfers, this option should not be
necessary, the destination filespec overrides it.

=back

=head1 BRANCHES

VCP uses the "directory" name of each file as the file's branch_id.
VCP ignores p4 branch specs for several reasons:

=over

=item 1

Branch specs are not version controlled, which means that you can't tell
what a branch spec looked like when a branch was created.

=item 2

Multiple branch specs can point to the same directory or even the same file.

=item 3

branch specs are not necessary in managing a p4 repository.

=back

TODO: build a filter or VCP::Source::p4 option that allows p4 branch
specifications to determine branch_ids.

As the L<VCP Branches|VCP::Branches> chapter mentions, you can use a Map
section in the transfer specification to extract meaningful C<branch_id>s if
you need to.

=for test_script t/9*p4.t

=cut

$VERSION = 1.0 ;

@ISA = qw( VCP::Source VCP::Utils::p4 );

use strict ;

use Carp ;
use Fcntl qw( O_WRONLY O_CREAT ) ;
use File::Basename;
use VCP::Debug ":debug" ;
use VCP::Logger qw( lg BUG pr pr_doing pr_done );
use VCP::Rev;
use VCP::Source;
use VCP::Utils qw( empty is_win32 );
use VCP::Utils::p4;

#use base qw( VCP::Source VCP::Utils::p4 ) ;
#use fields (
#   'P4_REPO_CLIENT',       ## Set by p4_parse_repo_spec in VCP::Utils::p4
#   'P4_INFO',              ## Results of the 'p4 info' command
#   'P4_RUN_P4D',           ## whether --run-p4d specified
#   'P4_LABEL_CACHE',       ## ->{$name}->{$rev} is a list of labels for that rev
#   'P4_MAX',               ## The last change number needed
#   'P4_MIN',               ## The first change number needed
#   'P4_FOLLOW_BRANCH_INTO',  ## Whether or not to follow "branch-into" events
#
#   'P4_SPECS_TO_SCAN',  ## Filespecs for sets of files to scan.
#                             ## Starts with the user provided spec, then
#                             ## grows as branches are found if
#                             ## P4_FOLLOW_BRANCH_INTO is set.
#
#   'P4_BRANCH_SPECS',      ## A HASH of branch specs by branch_id.  Used to
#                           ## pass on the appropriate branch specs to the
#                           ## destination.
#) ;


sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_p4_repo_spec( $spec )
      unless empty $spec;

   $self->parse_options( $options );

   return $self ;
}


sub DESTROY {
   my $self = shift;
   if ( $self->rev_labels_db ) {
      $self->rev_labels_db->close_db;
      $self->rev_labels_db->delete_db;
   }
}


sub options_spec {
   my $self = shift;
   return (
      $self->SUPER::options_spec,
      'follow-branch-into' => \$self->{P4_FOLLOW_BRANCH_INTO},
      'run-p4d'            => \$self->{P4_RUN_P4D},
   );
}


sub init {
   my $self = shift ;

   $self->SUPER::init;

   my $repo_server = $self->repo_server;
   $repo_server = $ENV{P4PORT} unless defined $repo_server;
   die 'P4PORT not set\n' if empty $repo_server;

   $self->repo_id( "p4:$repo_server" )
      if empty $self->repo_id;


   $self->run_p4d if $self->{P4_RUN_P4D};

   $self->set_up_p4_user_and_client;

   my $name = $self->repo_filespec ;
   if ( length $name >= 2 && substr( $name, 0, 2 ) ne '//' ) {
      ## No depot on the command line, default it to the only depot
      ## or error if more than one.
      my $depots ;
      $self->p4( ['depots'], undef, \$depots ) ;
      $depots = 'depot' unless length $depots ;
      my @depots = split( /^/m, $depots ) ;
      die "p4 has more than one depot, can't assume //depot/...\n"
         if @depots > 1 ;
      lg "defaulting depot to '$depots[0]'";
      $name = join( '/', '/', $depots[0], $name ) ;
   }

   $self->deduce_rev_root( $name )
      if empty $self->rev_root;

   die "no depot name specified for p4 source '$name'\n"
      unless $name =~ m{^//[^/]+/} ;
   $self->repo_filespec( $name ) ;

   $self->load_p4_info ;
   $self->load_p4_branches ;
}


sub ui_set_p4d_dir {
   my $self = shift;
   my ($dir) = @_;
   $self->repo_server( $dir );

   die "Warning: '$dir' not found!\n"
      unless -e $dir;
   die "Error: '$dir' exists, but is not a directory.\n"
      unless -d $dir;
}


sub load_p4_info {
   my $self = shift ;

   my $errors = '' ;
   $self->p4( ['info'], undef, \$self->{P4_INFO} ) ;
}


# A typical entry in the filelog looks like
#-------8<-------8<------
#//revengine/revml.dtd
#... #6 change 11 edit on 2000/08/28 by barries@barries (text)
#
#        Rev 0.008: Added some modules and tests and fixed lots of bugs.
#
#... #5 change 10 edit on 2000/08/09 by barries@barries (text)
#
#        Got Dest/cvs working, lots of small changes elsewhere
#
#-------8<-------8<------
# And, from a more tangled source tree, perl itself:
#-------8<-------8<------
#... ... branch into //depot/ansiperl/x2p/a2p.h#1
#... ... ignored //depot/maint-5.004/perl/x2p/a2p.h#1
#... ... copy into //depot/oneperl/x2p/a2p.h#3
#... ... copy into //depot/win32/perl/x2p/a2p.h#2
#... #2 change 18 integrate on 1997/05/25 by mbeattie@localhost (text)
#
#        First stab at 5.003 -> 5.004 integration.
#
#... ... branch into //depot/lexwarn/perl/x2p/a2p.h#1
#... ... branch into //depot/oneperl/x2p/a2p.h#1
#... ... copy from //depot/relperl/x2p/a2p.h#2
#... ... branch into //depot/win32/perl/x2p/a2p.h#1
#... #1 change 1 add on 1997/03/28 by mbeattie@localhost (text)
#
#        Perl 5.003 check-in
#
#... ... branch into //depot/mainline/perl/x2p/a2p.h#1
#... ... branch into //depot/relperl/x2p/a2p.h#1
#... ... branch into //depot/thrperl/x2p/a2p.h#1
#-------8<-------8<------
#
# This next regexp is used to parse the lines beginning "... #"

my $filelog_rev_info_re = qr{
   \G                  # Use with /gc!!
   ^\.\.\.\s+
   \#(\d+)\s+          # Revision
   change\s+(\d+)\s+   # Change nubmer
   (\S+)\s+            # Action
   \S+\s+              ### 'on '
   (\S+)\s+            # date
   \S+\s+              ### 'by '
   (\S(?:.*?\S))\s+    # user id.  Undelimited, so hope for best
   \((\S+?)\)          # type
   .*\r?\n
}mx ;

# And this one grabs the comment
my $filelog_comment_re = qr{
   \G
   ^\r?\n
   ((?:^[^\S\r\n].*\r?\n)*)
   ^\r?\n
}mx ;


sub add_rev {
   my $self = shift ;
   my ( $r ) = @_;

   my $mode = $self->rev_mode( $r->source_filebranch_id, $r->rev_id );

   return unless $mode;

   $r->base_revify if $mode eq "base";

   $self->queue_rev( $r );
}


sub parse_p4_changes_output {
   my $self = shift;
   my ( $fh ) = @_;

   my $r ;
   my $name ;
   my $comment ;

   local $_;

   my $log_state = "need_change" ;
   while ( <$fh> ) {
   if ( debugging ) {
      my $l = $_;
      1 while chomp $l;
      debug "$log_state: [$l]";
   }
   REDO_LINE:
      if ( $log_state eq "need_file" ) {
         die "\$r defined" if defined $r ;
         die "p4 filelog parser: file name expected, got '$_'"
            unless m{^//(.*?)\r?\n\r?} ;

         $name = $1 ;
         $log_state = "revs" ;
      }
      elsif ( $log_state eq "revs" ) {
         if ( $r && m{^\.\.\. #} ) {
            $self->add_rev( $r );
            $r = undef;
         }
         elsif ( m{^\.\.\.\s+\.\.\.\s*(.*?)\s*\r?\n\r?} ) {
            my $chunk = $1;
            if ( $chunk =~ /^branch from (.*)/ ) {
               ## Only pay attention to branch foundings
               next if ! $r || $r->rev_id ne "1";

               my $base_spec = $1;
               my ( $base_name, $base_rev, $source_rev ) =
                  $base_spec =~ m{\A([^#]+)#(\d+)(?:,#(\d+))?\z}
                     or die "Could not parse branch from '$base_spec' for ",
                     $r->as_string;
               ## TODO: $base_rev is usually #1 when a new branch
               ## is created, since the last "add" of the source
               ## file is usually #1.  However, it might not be and I'm
               ## not sure what, if anything, should be done with it.
               $source_rev = $base_rev unless defined $source_rev;
               $r->previous_id( "$base_name#$source_rev" );
            }
            elsif ( $self->{P4_FOLLOW_BRANCH_INTO}
               && $chunk =~ /^branch into (.*)/
            ) {
               my $target_spec = $1;
               my ( $target_name, $target_rev ) =
                  $target_spec =~ m{\A(.*)#(\d+)\z}
                     or die"Could not parse branch into '$target_spec' for ",
                        $r->as_string;
               push @{$self->{P4_SPECS_TO_SCAN}}, $target_name;
            }
            ## We ignore unrecognized secondary log lines.
            next;
         }

         unless ( m{$filelog_rev_info_re} ) {
            $log_state = "need_file" ;
            $self->add_rev( $r ) if defined $r;
            $r = undef;
            goto REDO_LINE ;
         }

         my $rev_id    = $1;
         my $change_id = $2;
         my $action    = $3;
         my $time      = $4;
         my $user_id   = $5;
         my $type      = $6 ;

         if ( $change_id < $self->min ) {
            undef $r ;
            $log_state = "need_comment" ;
            next;
         }

         $user_id =~ s/\@(.*)//;
         my $client = $1;

         my $norm_name = $self->normalize_name( $name ) ;
         die "\$r defined" if defined $r ;

         my $p4_name = "//$name";
         my $id = "$p4_name#$rev_id";

         my $branch_id = (fileparse $p4_name )[1];

         $type = $type =~ /^(?:u?x?binary|x?tempobj|resource)/
            ? "binary"
            : "text";

         $r = VCP::Rev->new(
            id                   => $id,
            action               => $action,
            name                 => $norm_name,
            source_name          => $norm_name,
            source_filebranch_id => $p4_name,
            branch_id            => $branch_id,
            source_branch_id     => $branch_id,
            source_repo_id       => $self->repo_id,
            rev_id               => $rev_id,
            source_rev_id        => $rev_id,
            change_id            => $change_id,
            source_change_id     => $change_id,
            time                 => $self->parse_time( $time ),
            user_id              => $user_id,
            $action ne "branch"
               ? (
                  p4_info              => $_,
                  type                 => $type,
               )
               : (),
            comment              => '',
         );

         $self->set_last_rev_in_filebranch_previous_id( $r );

         $r->set_labels( $self->get_rev_labels( $id ) );

         $log_state = "need_comment" ;
      }
      elsif ( $log_state eq "need_comment" ) {
         unless ( /^\r?\n/ ) {
            die
"p4 filelog parser: expected a blank line before a comment, got '$_'" ;
         }
         $log_state = "comment_accum" ;
      }
      elsif ( $log_state eq "comment_accum" ) {
         if ( /^\r?\n/ ) {
            if ( defined $r ) {
               $r->comment( $comment ) ;
            }
            $comment = undef ;
            $log_state = "revs" ;
            next;
         }
         unless ( s/^\s// ) {
            die "p4 filelog parser: expected a comment line, got '$_'" ;
         }
         s/\r\n$/\n/ if is_win32;
         $comment .= $_ ;
      }
      else {
         die "unknown log_state '$log_state'" ;
      }
   }

   if ( $r ) {
      $self->add_rev( $r );
      $r = undef;
   }
}





sub p4_filelog_parser {
   my $self = shift;
   my ( $fh ) = @_;

   my $r ;
   my $name ;
   my $comment ;

   local $_;

   my $log_state = "need_file" ;
   while ( <$fh> ) {
   if ( debugging ) {
      my $l = $_;
      1 while chomp $l;
      debug "$log_state: [$l]";
   }
   REDO_LINE:
      if ( $log_state eq "need_file" ) {
         die "\$r defined" if defined $r ;
         die "p4 filelog parser: file name expected, got '$_'"
            unless m{^//(.*?)\r?\n\r?} ;

         $name = $1 ;
         $log_state = "revs" ;
      }
      elsif ( $log_state eq "revs" ) {
         if ( $r && m{^\.\.\. #} ) {
            $self->add_rev( $r );
            $r = undef;
         }
         elsif ( m{^\.\.\.\s+\.\.\.\s*(.*?)\s*\r?\n\r?} ) {
            my $chunk = $1;
            if ( $chunk =~ /^branch from (.*)/ ) {
               ## Only pay attention to branch foundings
               next if ! $r || $r->rev_id ne "1";

               my $base_spec = $1;
               my ( $base_name, $base_rev, $source_rev ) =
                  $base_spec =~ m{\A([^#]+)#(\d+)(?:,#(\d+))?\z}
                     or die "Could not parse branch from '$base_spec' for ",
                     $r->as_string;
               ## TODO: $base_rev is usually #1 when a new branch
               ## is created, since the last "add" of the source
               ## file is usually #1.  However, it might not be and I'm
               ## not sure what, if anything, should be done with it.
               $source_rev = $base_rev unless defined $source_rev;
               $r->previous_id( "$base_name#$source_rev" );
            }
            elsif ( $self->{P4_FOLLOW_BRANCH_INTO}
               && $chunk =~ /^branch into (.*)/
            ) {
               my $target_spec = $1;
               my ( $target_name, $target_rev ) =
                  $target_spec =~ m{\A(.*)#(\d+)\z}
                     or die"Could not parse branch into '$target_spec' for ",
                        $r->as_string;
               push @{$self->{P4_SPECS_TO_SCAN}}, $target_name;
            }
            ## We ignore unrecognized secondary log lines.
            next;
         }

         unless ( m{$filelog_rev_info_re} ) {
            $log_state = "need_file" ;
            $self->add_rev( $r ) if defined $r;
            $r = undef;
            goto REDO_LINE ;
         }

         my $rev_id    = $1;
         my $change_id = $2;
         my $action    = $3;
         my $time      = $4;
         my $user_id   = $5;
         my $type      = $6 ;

         if ( $change_id < $self->min ) {
            undef $r ;
            $log_state = "need_comment" ;
            next;
         }

         $user_id =~ s/\@(.*)//;
         my $client = $1;

         my $norm_name = $self->normalize_name( $name ) ;
         die "\$r defined" if defined $r ;

         my $p4_name = "//$name";
         my $id = "$p4_name#$rev_id";

         my $branch_id = (fileparse $p4_name )[1];

         $type = $type =~ /^(?:u?x?binary|x?tempobj|resource)/
            ? "binary"
            : "text";

         $r = VCP::Rev->new(
            id                   => $id,
            action               => $action,
            name                 => $norm_name,
            source_name          => $norm_name,
            source_filebranch_id => $p4_name,
            branch_id            => $branch_id,
            source_branch_id     => $branch_id,
            source_repo_id       => $self->repo_id,
            rev_id               => $rev_id,
            source_rev_id        => $rev_id,
            change_id            => $change_id,
            source_change_id     => $change_id,
            time                 => $self->parse_time( $time ),
            user_id              => $user_id,
            $action ne "branch"
               ? (
                  p4_info              => $_,
                  type                 => $type,
               )
               : (),
            comment              => '',
         );

         $self->set_last_rev_in_filebranch_previous_id( $r );

         $r->set_labels( $self->get_rev_labels( $id ) );

         $log_state = "need_comment" ;
      }
      elsif ( $log_state eq "need_comment" ) {
         unless ( /^\r?\n/ ) {
            die
"p4 filelog parser: expected a blank line before a comment, got '$_'" ;
         }
         $log_state = "comment_accum" ;
      }
      elsif ( $log_state eq "comment_accum" ) {
         if ( /^\r?\n/ ) {
            if ( defined $r ) {
               $r->comment( $comment ) ;
            }
            $comment = undef ;
            $log_state = "revs" ;
            next;
         }
         unless ( s/^\s// ) {
            die "p4 filelog parser: expected a comment line, got '$_'" ;
         }
         s/\r\n$/\n/ if is_win32;
         $comment .= $_ ;
      }
      else {
         die "unknown log_state '$log_state'" ;
      }
   }

   if ( $r ) {
      $self->add_rev( $r );
      $r = undef;
   }
}


sub scan_metadata {
   my $self = shift ;

   my ( $first_change_id, $last_change_id ) = ( $self->min, $self->max ) ;

   my $delta = $last_change_id - $first_change_id + 1 ;

   my $spec =  join( '', $self->repo_filespec, '@', $last_change_id ) ;

   $self->{P4_SPECS_TO_SCAN} = [ $spec ];

   while ( @{$self->{P4_SPECS_TO_SCAN}} ) {
      my $s = shift @{$self->{P4_SPECS_TO_SCAN}};

      $self->p4(
         [ "filelog", "-m", $delta, "-l", $s ],
         undef,
         sub { $self->p4_filelog_parser( @_ ) },
         {
            stderr_filter => 
               sub { qr{//\S* - no file\(s\) at that changelist number\.\s*\r?\n} } 
         }
      ) ;

   }

   pr "found " . $self->sent_rev_count, " revisions";
}


sub min {
   my $self = shift ;
   $self->{P4_MIN} = shift if @_ ;
   return $self->{P4_MIN} ;
}


sub max {
   my $self = shift ;
   $self->{P4_MAX} = shift if @_ ;
   return $self->{P4_MAX} ;
}

# $ p4 labels   
# Label P98.2 1999/06/14 'Perforce98.2-compatible scripts & source files. '
# Label P99.1 1999/06/14 'Perforce99.1-compatible scripts & source files. '
# Label PerForte-1-0 2002/02/27 'Initial version from Axel Wienberg.  Created by david_rees. '
# Label PerForte-1-1 2002/02/28 'Created by david_rees. '
# Label jam2-2-0 1998/09/24 'Jam/MR 2.2 '
# Label jam2-2-4 1998/09/24 'Jam/MR 2.2.4 '
# Label vcp_00_02 2000/12/11 'VCP release 0.02. '
# Label vcp_00_03 2000/12/11 'VCP Release 0.03 '
# Label vcp_00_04 2000/12/19 'VCP release 0.4 '
# Label vcp_00_05 2000/12/19 'VCP release 0.05 '
# Label vcp_00_06 2000/12/20 'VCP Release 0.06 '
# Label vcp_00_068 2001/05/21 'VCP version v0.068 '
# Label vcp_00_07 2002/07/17 'VCP release v0.07 '
# Label vcp_00_08 2001/05/23 'VCP release 0.08 '
# Label vcp_00_09 2001/05/30 'Created by barrie_slaymaker. '
# Label vcp_00_091 2001/06/07 'vcp release 0.091 '
# Label vcp_00_1 2001/07/03 'VCP release 0.1 '
# Label vcp_00_2 2001/07/18 'VCP release 0.2. '
# Label vcp_00_21 2001/07/20 'VCP release 0.21 '
# Label vcp_00_22 2001/12/18 'VCP release 0.22 '
# Label vcp_00_221 2001/07/30 'VCP Release 0.221 '
# Label vcp_00_26 2001/12/18 'VCP release 0.26 '
# Label vcp_00_28 2002/04/30 'VCP release 0.28 '
# Label vcp_00_30 2002/05/24 'VCP release 0.3 '

sub load_p4_labels {
   my $self = shift ;

   my $labels = '' ;
   my $errors = '' ;
   pr "running p4 labels";
   $self->p4( ['labels'], undef, \$labels ) ;

   my @labels = map(
      /^Label\s*(\S*)/ ? $1 : (),
      split( /^/m, $labels )
   ) ;

   if ( @labels ) {
      my $marker = "//.../NtLkly" ;

      pr_doing "running p4 files to find labelled files: ";
      $self->p4_x(
         [ "-s", "files" ],
         [
            map {
               ( "$marker\n", "//...\@$_\n" ) ;
            } @labels,
         ],
         \my $files,
         { ok_result_codes => [ 0, 1 ] },
      );

      my $label ;
      for my $spec ( split /\r?\n/m, $files ) {
         pr_doing;
         last if $spec =~ /^exit:/ ;
         if ( $spec =~ /^error: $marker/o ) {
            $label = shift @labels ;
            next ;
         }
         next if $spec =~ m{^error: //\.\.\.\@.+ file(\(s\))?( not in label.)?$} ;
         $spec =~ /^.*?: *(\/\/.*#\d+)/
            or die "Couldn't parse name & rev from '$spec' in p4 output:\n$files\n" ;
         my $id = $1;

         debug "p4 label '$label' => '$id'" if debugging ;
         $self->rev_labels_db->set(
            [ $id ],
            $self->rev_labels_db->get( [ $1 ] ), $label
         );
      }
      pr_done;
   }

   return ;
}


# $ p4 branches
# Branch BoostJam 2001/11/12 'Created by david_abrahams. '
# Branch P4DB_2.1 2002/07/07 'P4DB Version 2.1 '
# Branch gjam 2000/03/22 'Created by grant_glouser to branch the jam sources. '
# Branch jab_triggers 1999/03/18 'Created by jeff_bowles. '
# Branch java_reviewer 2002/08/12 'Created by david_markley. '
# Branch lw2pub 1999/06/18 'Created by laura_wingerd. '
# Branch mwm2pub 1999/06/18 'Created by laura_wingerd. '
# Branch p4hltest 2002/04/24 'Branch for testing FileLogCache stuff out. '
# Branch p4jsp 2002/07/30 'p4jsp to public depot '
# Branch p4package 2001/11/05 'Created by david_markley. '
# Branch scouten-jam 2000/08/18 'ES version of jam. '
# Branch scouten-webkeeper 2000/03/01 'ES version of webkeeper. '
# Branch srv_webkeep_guest_to_main 2001/09/04 'Created by stephen_vance. '
# Branch steve_howell_util 1998/12/31 'Created by steve_howell. '
# Branch tq_cvs2p4 2000/09/09 'Created by thomas_quinot. '
# Branch vsstop4_rc2ps 2002/03/06 'for pulling Roberts branch into mine '

sub load_p4_branches {
#   my $self = shift ;
#
#   pr "running p4 branches";
#   $self->p4( ['branches'], undef, \my $branches ) ;
#
#   my @branches = map
#      /^Branch\s*(\S*)/ ? $1 : (),
#      split /^/m, $branches;
#
#   for ( @branches ) {
#      $self->p4( ['branch', '-o', $_ ], undef, \my $branch_spec );
#      $self->{P4_BRANCH_SPECS}->{$_} = $branch_spec;
#   }
#
#   return ;
}


sub denormalize_name {
   my $self = shift ;
   my $fn = $self->SUPER::denormalize_name( @_ );
   $fn =~ s{^/*}{//};
   return $fn;
}


sub rev_labels_db {
   return shift->{REV_LABELS_DB};
}


sub get_rev_labels {
   my $self = shift ;

   my ( $id ) = @_ ;
   return $self->rev_labels_db->get( [ $id ] );
}


my $filter_prog = <<'EOPERL' ;
   use strict ;
   my ( $name, $working_path ) = ( shift, shift ) ;
   }
EOPERL


sub get_source_file {
   my $self = shift ;

   my $r ;

   ( $r ) = @_ ;
   BUG "can't check out ", $r->as_string, "\n"
      unless $r->is_base_rev || $r->action eq "add" || $r->action eq "edit";

   my $fn  = $r->source_name ;
   my $rev = $r->source_rev_id ;
   
   my $wp  = $self->work_path( $fn, $rev );
   $self->mkpdir( $wp ) ;
   die "$wp already exists\n"
       if -f $wp;

   my $p4_work_path = $self->work_path( "co", $fn );
   my $rev_spec = "$p4_work_path#$rev" ;

   ## TODO: look for "+x" in the (...) and pass an executable bit
   ## through the rev structure.
   $self->p4( [ "sync", "-f", $rev_spec ] ) ;

   die "$p4_work_path not created by sync -v $rev_spec\n"
       unless -f $p4_work_path;

   link $p4_work_path, $wp or die "$! linking $p4_work_path to $wp\n";

#   close WP or die "$! closing wp" ;
   return $wp;
}


sub handle_header {
   my $self = shift ;
   my ( $header ) = @_ ;

   $header->{rep_type} = 'p4' ;
   $header->{rep_desc} = $self->{P4_INFO} ;
   $header->{rev_root} = $self->rev_root ;

   my $tmp_db_loc = $self->tmp_dir;

   $self->{REV_LABELS_DB} = VCP::DB_File::big_records->new(
      StoreLoc  => $tmp_db_loc,
      TableName => "rev_labels",
   );

   $self->rev_labels_db->delete_db;
   $self->rev_labels_db->open_db;
   $self->load_p4_labels ;

   $self->dest->handle_header( $header );
   return ;
}



=over

=item repo_client

The p4 client name. This is an accessor for a data member in each class.
The data member should be part of VCP::Utils::p4, but the fields pragma
does not support multiple inheritance, so the accessor is here but all
derived classes supporting this accessor must provide for a key named
"P4_REPO_CLIENT".

=cut

sub repo_client {
   my $self = shift ;

   $self->{P4_REPO_CLIENT} = shift if @_ ;
   return $self->{P4_REPO_CLIENT} ;
}

=back

=cut

=head1 LIMITATIONS

Treats each branched file as a separate branch with a unique branch_id,
although files that are branched together should end up being submitted
together in the destination repository due to change number aggregation.

Ignores branch specs for now.  There may be an option to enable
automatic use of branch specs because most are probably well behaved.
However, in the event of a branch spec being altered after the original
branch, this could lead to odd results.  Not sure how useful branch
specs are vs. how likely a problem this is to be.  We may also want to
support "external" branch specs to allow deleted branch specs to be
used.

=head1 SEE ALSO

L<VCP::Dest::p4>, L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
