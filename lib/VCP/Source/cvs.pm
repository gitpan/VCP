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
   vcp cvs:module/... -r 1.1:     # revs 1.1 and up

   ## NOTE: Unlike cvs, vcp requires spaces after option letters.

=head1 DESCRIPTION

Source driver enabling L<C<vcp>|vcp> to extract versions form a cvs
repository.

This doesn't deal with branches yet (at least not intentionally).  That
will require a bit of Deep Thought.

The source specification for CVS looks like:

    cvs:cvsroot/filespec [<options>]

where the C<cvsroot> is passed to C<cvs> with the C<-d> option if
provided (C<cvsroot> is optional if the environment variable C<CVSROOT>
is set) and the filespec and E<lt>optionsE<gt> determine what revisions
to extract.

C<filespec> may contain trailing wildcards, like C</a/b/...> to extract
an entire directory tree.

=head1 OPTIONS

=over

=item -b, --bootstrap

   -b ...
   --bootstrap=...
   -b file1[,file2[, etc.]]
   --bootstrap=file1[,file2[, etc. ]]

(the C<...> there is three periods, a
L<Regexp::Shellish|Regexp::Shellish> wildcard borrowed from C<p4>
path syntax).

Forces bootstrap mode for an entire export (C<-b ...>) or for certain
files.  Filenames may contain wildcards, see L<Regexp::Shellish> for
details on what wildcards are accepted.

Controls how the first revision of a file is exported.  A bootstrap
export contains the entire contents of the first revision in the
revision range.  This should only be necessary when exporting for the
first time.

An incremental export contains a digest of the revision preceding the
first revision in the revision range, followed by a delta record between
that revision and the first revision in the range.  This allows the
destination import function to make sure that the incremental export
begins where the last export left off.

The default is decided on a per-file basis: if the first revision in the
range is revision #.1, the full contents are exported.  Otherwise an
incremental export is done for that file.

This option is necessary when exporting only more recent revisions from
a repository.

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

=item -kb, -k b

Pass the -kb option to cvs, forces a binary checkout.  This is
useful when you want a text file to be checked out with Unix linends,
or if you know that some files in the repository are not flagged as
binary files and should be.

=item --rev-root

B<Experimental>.

Falsifies the root of the source tree being extracted; files will
appear to have been extracted from some place else in the hierarchy.
This can be useful when exporting RevML, the RevML file can be made
to insert the files in to a different place in the eventual destination
repository than they existed in the source repository.

The default C<rev-root> is the file spec up to the first path segment
(directory name) containing a wildcard, so

   cvs:/a/b/c...

would have a rev-root of C</a/b>.

In direct repository-to-repository transfers, this option should not be
necessary, the destination filespec overrides it.

=item -r

   -r v_0_001:v_0_002
   -r v_0_002:

Passed to C<cvs log> as a C<-r> revision specification. This corresponds
to the C<-r> option for the rlog command, not either of the C<-r>
options for the cvs command. Yes, it's confusing, but 'cvs log' calls
'rlog' and passes the options through.

IMPORTANT: When using tags to specify CVS file revisions, it would ordinarily
be the case that a number of unwanted revisions would be selected.  This is
because the behavior of the cvs log command dumps the entire log history for
any files that do not contain the tag. VCP captures the histories of such files
and ignores all revisions that are older or newer than any files that match the
tags.

Be cautious using HEAD as the end of a revision range, this seems to cause the
delete actions for files deleted in the last revision to not be noticed. Not
sure why.

One of C<-r> or L<C<-d>|-d> must be specified.

=item C<-d>

   -d "2000-11-18 5:26:30<="

Passed to 'cvs log' as a C<-d> date specification. 

WARNING: if this string doesn't contain a '>' or '<', you're probably doing
something wrong, since you're not specifying a range.  vcp may warn about this
in the future.

One of L<C<-r>|-r> or C<-d> must be specified.

=back

=head2 Files that aren't tagged

CVS has one peculiarity that this driver works around.

If a file does not contain the tag(s) used to select the source files,
C<cvs log> outputs the entire life history of that file.  We don't want
to capture the entire history of such files, so L<VCP::Source::cvs> goes
ignores any revisions before and after the oldest and newest tagged file
in the range.

=head1 LIMITATIONS

   "What we have here is a failure to communicate!"
       - The warden in Cool Hand Luke

CVS does not try to protect itself from people checking in things that
look like snippets of CVS log file: they come out exactly like they
went in, confusing the log file parser.

So, if a repository contains messages in the log file that look like the 
output from some other "cvs log" command, things will likely go awry.

At least one cvs repository out there has multiple revisions of a single file
with the same rev number.  The second and later revisions with the same rev
number are ignored with a warning like "Can't add same revision twice:...".

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

use strict ;

use Carp ;
use Getopt::Long ;
use Regexp::Shellish qw( :all ) ;
use VCP::Rev ;
use VCP::Debug ':debug' ;
use VCP::Source ;
use VCP::Utils::cvs ;

use base qw( VCP::Source VCP::Utils::cvs ) ;
use fields (
   'CVS_CUR',            ## The current change number being processed
   'CVS_BOOTSTRAP',      ## Forces bootstrap mode
   'CVS_IS_INCREMENTAL', ## Hash of filenames, 0->bootstrap, 1->incremental
   'CVS_INFO',           ## Results of the 'cvs --version' command and CVSROOT
   'CVS_LABEL_CACHE',    ## ->{$name}->{$rev} is a list of labels for that rev
   'CVS_LABELS',         ## Array of labels from 'p4 labels'
   'CVS_MAX',            ## The last change number needed
   'CVS_MIN',            ## The first change number needed
   'CVS_REV_SPEC',       ## The revision spec to pass to `cvs log`
   'CVS_DATE_SPEC',      ## The date spec to pass to `cvs log`
   'CVS_FORCE_MISSING',  ## Set if -r was specified.

   'CVS_K_OPTION',       ## Which of the CVS/RCS "-k" options to use, if any

   'CVS_LOG_CARRYOVER',  ## The unparsed bit of the log file
   'CVS_LOG_FILE_DATA',  ## Data about all revs of a file from the log file
   'CVS_LOG_STATE',      ## Parser state machine state
   'CVS_LOG_REV',        ## The revision being parsed (a hash)

   'CVS_NAME_REP_NAME',  ## A mapping of repository names to names, used to
                         ## figure out what files to ignore when a cvs log
			 ## goes ahead and logs a file which doesn't match
			 ## the revisions we asked for.

   'CVS_NEEDS_BASE_REV', ## What base revisions are needed.  Base revs are
                         ## needed for incremental (ie non-bootstrap) updates,
			 ## which is decided on a per-file basis by looking
			 ## at VCP::Source::is_bootstrap_mode( $file ) and
			 ## the file's rev number (ie does it end in .1).
   'CVS_SAW_EQUALS',     ## Set when we see the ==== lines in log file [1]
) ;


sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Source::cvs $self = $class->SUPER::new( @_ ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_repo_spec( $spec ) ;

   my $work_dir ;
   my $rev_root ;
   my $rev_spec ;
   my $date_spec ;
   #   my $force_missing ;

   GetOptions(
      "b|bootstrap:s"   => sub {
	 my ( $name, $val ) = @_ ;
	 $self->{CVS_BOOTSTRAP} = $val eq ""
	    ? [ compile_shellish( "..." ) ]
	    : [ map compile_shellish( $_ ), split /,+/, $val ] ;
      },
      "cd=s"          => \$work_dir,
      "rev-root=s"    => \$rev_root,
      "r=s"           => \$rev_spec,
      "d=s"           => \$date_spec,
      "k=s"           => sub { warn $self->{CVS_K_OPTION} = $_[1] } ,
      "kb"            => sub { warn $self->{CVS_K_OPTION} = "b" } ,
#      "f+"            => \$force_missing,
   ) or $self->usage_and_exit ;

   unless ( defined $rev_spec || defined $date_spec ) {
      print STDERR "Revision (-r) or date (-d) specification missing\n" ;
      $self->usage_and_exit ;
   }

#   if ( $force_missing && ! defined $rev_spec ) {
#      print STDERR
#         "Force missing (-f) may not be used without a revision spec (-r)\n" ;
#      $self->usage_and_exit ;
#   }
#
   my $files = $self->repo_filespec ;
   unless ( defined $rev_root ) {
      $self->deduce_rev_root( $files ) ;
   }
#   else {
#      $files = "$rev_root/$files" ;
#   }
#
### TODO: Figure out whether we should make rev_root merely set the rev_root
### in the header.  I think we probably should do it that way, as it's more
### flexible and less confusing.

   my $recurse = $files =~ s{/\.\.\.$}{} ;

   ## Don't normalize the filespec.
   $self->repo_filespec( $files ) ;

   $self->rev_spec( $rev_spec ) ;
   $self->date_spec( $date_spec ) ;
   $self->force_missing( defined $rev_spec ) ;
#   $self->force_missing( $force_missing ) ;

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

   ## Doing a CVS command or two here also forces cvs to be found in new(),
   ## or an exception will be thrown.
   $self->cvs( ['--version' ], \$self->{CVS_INFO} ) ;

   ## This does a checkout, so we'll blow up quickly if there's a problem.
   unless ( defined $work_dir ) {
      $self->create_cvs_workspace ;
   }
   else {
      $self->work_root( File::Spec->rel2abs( $work_dir ) ) ; 
      $self->command_chdir( $self->work_path ) ;
   }

   return $self ;
}


sub is_incremental {
   my VCP::Source::cvs $self= shift ;
   my ( $file, $first_rev ) = @_ ;

   my $bootstrap_mode = substr( $first_rev, -2 ) eq ".1"
      || ( $self->{CVS_BOOTSTRAP}
         && grep $file =~ $_, @{$self->{CVS_BOOTSTRAP}}
      ) ;

   return $bootstrap_mode ? 0 : "incremental" ;
}


sub rev_spec {
   my VCP::Source::cvs $self = shift ;
   $self->{CVS_REV_SPEC} = shift if @_ ;
   return $self->{CVS_REV_SPEC} ;
}


sub rev_spec_cvs_option {
   my VCP::Source::cvs $self = shift ;
   return defined $self->rev_spec? "-r" . $self->rev_spec : (),
}


sub date_spec {
   my VCP::Source::cvs $self = shift ;
   $self->{CVS_DATE_SPEC} = shift if @_ ;
   return $self->{CVS_DATE_SPEC} ;
}


sub date_spec_cvs_option {
   my VCP::Source::cvs $self = shift ;
   return defined $self->date_spec ? "-d" . $self->date_spec : (),
}


sub force_missing {
   my VCP::Source::cvs $self = shift ;
   $self->{CVS_FORCE_MISSING} = shift if @_ ;
   return $self->{CVS_FORCE_MISSING} ;
}


sub denormalize_name {
   my VCP::Source::cvs $self = shift ;
   return '/' . $self->SUPER::denormalize_name( @_ ) ;
}


sub handle_header {
   my VCP::Source::cvs $self = shift ;
   my ( $header ) = @_ ;

   $header->{rep_type} = 'cvs' ;
   $header->{rep_desc} = $self->{CVS_INFO} ;
   $header->{rev_root} = $self->rev_root ;

   $self->dest->handle_header( $header ) ;
   return ;
}


sub get_rev {
   my VCP::Source::cvs $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;

   my $wp = $self->work_path( "revs", $r->name, $r->rev_id ) ;
   $r->work_path( $wp ) ;
   $self->mkpdir( $wp ) ;

   $self->cvs( [
	 "checkout",
	 "-r" . $r->rev_id,
	 "-p",
	 $r->source_name,
      ],
      '>', $wp,
   ) ;
}


sub copy_revs {
   my VCP::Source::cvs $self = shift ;

   $self->{CVS_LOG_STATE} = '' ;
   $self->{CVS_LOG_CARRYOVER} = '' ;
   $self->revs( VCP::Revs->new ) ;

   ## We need to watch STDERR for messages like
   ## cvs log: warning: no revision `ch_3' in `/home/barries/src/revengine/tmp/cvsroot/foo/add/f4,v'
   ## Files that cause this warning need to have some revisions ignored because
   ## cvs log will emit the entire log for these files in addition to 
   ## the warning, including revisions checked in before the first tag and
   ## after the last tag.
   my $tmp_f = $self->command_stderr_filter ;
   my %ignore_files ;
   my $ignore_file = sub {
      exists $ignore_files{$self->{CVS_NAME_REP_NAME}->{$_[0]}} ;
   } ;

   ## This regexp needs to gobble newlines.
   $self->command_stderr_filter( sub {
      my ( $err_text_ref ) = @_ ;
      $$err_text_ref =~ s@
         ^cvs(?:\.exe)?\slog:\swarning:\sno\srevision\s.*?\sin\s[`"'](.*)[`"']\r?\n\r?
      @
         $ignore_files{$1} = undef ;
	 '' ;
      @gxmei ;
   } ) ; ## `

   $self->{CVS_LOG_FILE_DATA} = {} ;
   $self->{CVS_LOG_REV} = {} ;
   $self->{CVS_SAW_EQUALS} = 0 ;
   # The log command must be run in the directory above the work root,
   # since we pass in the name of the workroot dir as the first dir in
   # the filespec.
   my $tmp_command_chdir = $self->command_chdir ;
   $self->command_chdir( $self->tmp_dir( "co" ) ) ;
   $self->cvs( [
         "log",
	 $self->rev_spec_cvs_option,
	 $self->date_spec_cvs_option,
	 length $self->repo_filespec ? $self->repo_filespec : (),
      ],
      '>', sub { $self->parse_log_file( @_ ) },
   ) ;

   $self->command_chdir( $tmp_command_chdir ) ;
   $self->command_stderr_filter( $tmp_f ) ;

   my $revs = $self->revs ;

   ## Figure out the time stamp range for force_missing calcs.
   my ( $min_rev_spec_time, $max_rev_spec_time ) ;
   if ( $self->force_missing ) {
      ## If the rev_spec is /:$/ || /^:/, we tweak the range ends.
      my $max_time = 0 ;
      $max_rev_spec_time = 0 ;
      $min_rev_spec_time = 0 if substr( $self->rev_spec, 0, 1 ) eq ':' ;
      for my $r ( @{$revs->as_array_ref} ) {
         next if $r->is_base_rev ;
         my $t = $r->time ;
         $max_time = $t if $t >= $max_rev_spec_time ;
	 next if $ignore_file->( $r->source_name ) ;
         $min_rev_spec_time = $t if $t <= ( $min_rev_spec_time || $t ) ;
         $max_rev_spec_time = $t if $t >= $max_rev_spec_time ;
      }
#      $max_rev_spec_time = $max_time if substr( $self->rev_spec, -1 ) eq ':' ;
      $max_rev_spec_time = undef if substr( $self->rev_spec, -1 ) eq ':' ;

      debug(
	 "vcp: including files in ['",
	 localtime( $min_rev_spec_time ),
	 "'..'",
	 defined $max_rev_spec_time
	    ? localtime( $max_rev_spec_time )
	    : "<end_of_time>",
	 "']"
      ) if debugging $self ;
   }

   ## Remove extra revs from queue by copying from $revs to $self->revs().
   ## TODO: Debug simultaneous use of -r and -d, since we probably are
   ## blowing away revs that -d included that -r didn't.  I haven't
   ## checked to see if we do or don't blow said revs away.
   my %oldest_revs ;
   $self->revs( VCP::Revs->new ) ;
   for my $r ( @{$revs->as_array_ref} ) {
      if ( $ignore_file->( $r->source_name ) ) {
	 if (
	       (!defined $min_rev_spec_time || $r->time >= $min_rev_spec_time)
	    && (!defined $max_rev_spec_time || $r->time <= $max_rev_spec_time)
	 ) {
	    debug(
	       "vcp: including file ", $r->as_string
	    ) if debugging $self ;
	 }
	 else {
	    debug(
	       "vcp: ignoring file ", $r->as_string,
	       ": no revisions match -r"
	    ) if debugging $self ;
	    next ;
	 }
      }
      ## Because of the order of the log file, the last rev set is always
      ## the first rev in the range.
      $oldest_revs{$r->source_name} = $r ;
      $self->revs->add( $r ) ;
   }
   $revs = $self->revs ;

   ## Add in base revs
   for my $fn ( keys %oldest_revs ) {
      my $r = $oldest_revs{$fn} ;
      my $rev_id = $r->rev_id ;
      if ( $self->is_incremental( $fn, $rev_id ) ) {
	 $rev_id =~ s{(\d+)$}{$1-1}e ;
         $revs->add(
	    VCP::Rev->new(
	       source_name => $r->source_name,
	       name        => $r->name,
	       rev_id      => $rev_id,
	       type        => $r->type,
	    )
	 )
      }
   }

   $self->dest->sort_revs( $self->revs ) ;

   my VCP::Rev $r ;
   while ( $r = $self->revs->shift ) {
      $self->get_rev( $r ) ;
      $self->dest->handle_rev( $r ) ;
   }
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
###############################################################################

sub parse_log_file {
   my ( $self, $input ) = @_ ;

   if ( defined $input ) {
      $self->{CVS_LOG_CARRYOVER} .= $input ;
   }
   else {
      ## There can only be leftovers if they don't end in a "\n".  I've never
      ## seen that happen, but given large comments, I could be surprised...
      $self->{CVS_LOG_CARRYOVER} .= "\n" if length $self->{CVS_LOG_CARRYOVER} ;
   }

   my $store_rev = sub {
#      my ( $is_oldest ) = @_ ;
      return unless keys %{$self->{CVS_LOG_REV}} ;

      $self->{CVS_LOG_REV}->{MESSAGE} = ''
         if $self->{CVS_LOG_REV}->{MESSAGE} eq '*** empty log message ***' ;

      $self->{CVS_LOG_REV}->{MESSAGE} =~ s/\r\n|\n\r/\n/g ;

#debug map "$_ => $self->{CVS_LOG_FILE_DATA}->{$_},", sort keys %{$self->{CVS_LOG_FILE_DATA}} ;
      $self->_add_rev( $self->{CVS_LOG_FILE_DATA}, $self->{CVS_LOG_REV} ) ;

#      if ( $is_oldest ) {
#         if ( 
#	    $self->is_incremental(
#	       $self->{CVS_LOG_FILE_DATA}->{WORKING},
#	       $self->{CVS_LOG_REV}->{REV}
#	    )
#	 ) {
#	    $self->{CVS_LOG_REV}->{REV} =~ s{(\d+)$}{$1-1}e ;
#
#	    $self->_add_rev(
#	       $self->{CVS_LOG_FILE_DATA},
#	       $self->{CVS_LOG_REV},
#	       "is base rev"
#	    );
#	 }
#      }
      $self->{CVS_LOG_REV} = {} ;
   } ;

   local $_ ;

   ## DOS, Unix, Mac lineends spoken here.
   while ( $self->{CVS_LOG_CARRYOVER} =~ s/^(.*(?:\r\n|\n\r|\n))// ) {
      $_ = $1 ;

      ## [1] See bottom of file for a footnote explaining this delaying of 
      ## clearing CVS_LOG_FILE_DATA and CVS_LOG_STATE until we see
      ## a ========= line followed by something other than a -----------
      ## line.
      ## TODO: Move to a state machine design, hoping that all versions
      ## of CVS emit similar enough output to not trip it up.

      ## TODO: BUG: Turns out that some CVS-philes like to put text
      ## snippets in their revision messages that mimic the equals lines
      ## and dash lines that CVS uses for delimiters!!

   PLEASE_TRY_AGAIN:
      if ( /^===========================================================*$/ ) {
         $store_rev->() ;# "is oldest" ) ;
	 $self->{CVS_SAW_EQUALS} = 1 ;
	 next ;
      }

      if ( /^----------------------------*$/ ) {
         $store_rev->() unless $self->{CVS_SAW_EQUALS} ;
	 $self->{CVS_SAW_EQUALS} = 0 ;
	 $self->{CVS_LOG_STATE} = 'rev' ;
	 next ;
      }

      if ( $self->{CVS_SAW_EQUALS} ) {
	 $self->{CVS_LOG_FILE_DATA} = {} ;
	 $self->{CVS_LOG_STATE} = '' ;
	 $self->{CVS_SAW_EQUALS} = 0 ;
      }

      unless ( $self->{CVS_LOG_STATE} ) {
	 if (
	    /^(RCS file|Working file|head|branch|locks|access list|keyword substitution):\s*(.*)/i
	 ) {
#warn uc( (split /\s+/, $1 )[0] ), "/", $1, ": ", $2, "\n" ;
	    $self->{CVS_LOG_FILE_DATA}->{uc( (split /\s+/, $1 )[0] )} = $2 ;
#$DB::single = 1 if /keyword/ && $self->{CVS_LOG_FILE_DATA}->{WORKING} =~ /Makefile/ ;
	 }
	 elsif ( /^total revisions:\s*([^;]*)/i ) {
	    $self->{CVS_LOG_FILE_DATA}->{TOTAL} = $1 ;
	    if ( /selected revisions:\s*(.*)/i ) {
	       $self->{CVS_LOG_FILE_DATA}->{SELECTED} = $1 ;
	    }
	 }
	 elsif ( /^symbolic names:/i ) {
	    $self->{CVS_LOG_STATE} = 'tags' ;
	    next ;
	 }
	 elsif ( /^description:/i ) {
	    $self->{CVS_LOG_STATE} = 'desc' ;
	    next ;
	 }
	 else {
	    carp "Unhandled CVS log line '$_'" if /\S/ ;
	 }
      }
      elsif ( $self->{CVS_LOG_STATE} eq 'tags' ) {
	 if ( /^\S/ ) {
	    $self->{CVS_LOG_STATE} = '' ;
	    goto PLEASE_TRY_AGAIN ;
	 }
	 my ( $tag, $rev ) = m{(\S+):\s+(\S+)} ;
	 unless ( defined $tag ) {
	    carp "Can't parse tag from CVS log line '$_'" ;
	    $self->{CVS_LOG_STATE} = '' ;
	    next ;
	 }
	 $self->{CVS_LOG_FILE_DATA}->{TAGS}->{$tag} = $rev ; 
	 push( @{$self->{CVS_LOG_FILE_DATA}->{RTAGS}->{$rev}}, $tag ) ; 
      }
      elsif ( $self->{CVS_LOG_STATE} eq 'rev' ) {
	 ( $self->{CVS_LOG_REV}->{REV} ) = m/([\d.]+)/ ;
	 $self->{CVS_LOG_STATE} = 'rev_meta' ;
	 next ;
      }
      elsif ( $self->{CVS_LOG_STATE} eq 'rev_meta' ) {
	 for ( split /;\s*/ ) {
	    my ( $key, $value ) = m/(\S+):\s+(.*?)\s*$/ ;
	    $self->{CVS_LOG_REV}->{uc($key)} = $value ;
	 }
	 $self->{CVS_LOG_STATE} = 'rev_message' ;
	 next ;
      }
      elsif ( $self->{CVS_LOG_STATE} eq 'rev_message' ) {
	 $self->{CVS_LOG_REV}->{MESSAGE} .= $_ ;
      }
   }

   ## Never, ever forget the last rev.  "Wait for me! Wait for me!"
   ## Most of the time, this should not be a problem: cvs log puts a
   ## line of "=" at the end.  But just in case I don't know of a
   ## funcky condition where that might not happen...
   unless ( defined $input ) {
      $store_rev->() ; # "is oldest" ) ;
      $self->{CVS_LOG_REV} = undef ;
      $self->{CVS_LOG_FILE_DATA} = undef ;
   }
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
#  'RCS' => '/var/cvs/cvsroot/src/Eesh/eg/synopsis,v',
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
   my VCP::Source::cvs $self = shift ;
   my ( $file_data, $rev_data, $is_base_rev ) = @_ ;

   my $norm_name = $self->normalize_name( $file_data->{WORKING} ) ;

   my $action = $rev_data->{STATE} eq "dead" ? "delete" : "edit" ;

   my $type = $file_data->{KEYWORD} =~ /[o|b]/ ? "binary" : "text" ;

#debug map "$_ => $rev_data->{$_}, ", sort keys %{$rev_data} ;

   my VCP::Rev $r = VCP::Rev->new(
      source_name => $file_data->{WORKING},
      name        => $norm_name,
      rev_id      => $rev_data->{REV},
      type        => $type,
#      ! $is_base_rev
#	 ? (
	    action      => $action,
	    time        => $self->parse_time( $rev_data->{DATE} ),
	    user_id     => $rev_data->{AUTHOR},
	    comment     => $rev_data->{MESSAGE},
	    state       => $rev_data->{STATE},
	    labels      => $file_data->{RTAGS}->{$rev_data->{REV}},
#	 )
#	 : (),
   ) ;

   $self->{CVS_NAME_REP_NAME}->{$file_data->{WORKING}} = $file_data->{RCS} ;
   eval {
      $self->revs->add( $r ) ;
   } ;
   if ( $@ ) {
      if ( $@ =~ /Can't add same revision twice/ ) {
         warn $@ ;
      }
      else {
         die $@ ;
      }
   }
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
