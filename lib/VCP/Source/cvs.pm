package VCP::Source::cvs ;

=head1 NAME

VCP::Source::cvs - A CVS repository source

=head1 SYNOPSIS

   vcp cvs:path/... -r foo        # all files in path and below labelled foo
   vcp cvs:path/... -r foo:       # All revs of files labelled foo and newer
   vcp cvs:path/... -r foo: -f    # All revs of files labelled foo and newer,
                                  # including files not tagged with foo.
   vcp cvs:path/... -r 1.1:1.10   # revs 1.1..1.10
   vcp cvs:path/... -r 1.1:       # revs 1.1 and up

   vcp cvs:path/... -D ">=2000-11-18 5:26:30"
                                  # All file revs newer than a date/time

   ## NOTE: Unlike cvs, vcp requires spaces after option letters.

=head1 DESCRIPTION

Reads a CVS repository.  You must check out the files of interest in to
a local working directory and run the cvs command from within that
directory.  This is because the "cvs log" and "cvs checkout" commands
need to have a working directory to play in.

This module in alpha.

This doesn't deal with branches yet (at least not intentionally).  That will
require a bit of Deep Thought.

This only deals with filespecs spelled like "/a/b/c" or "a/b/..." for now.

Later, we can handle other filespecs by reading the entire log output.

=head1 OPTIONS

=over

=item -b, --bootstrap

   -b '**'
   --bootstrap='**'
   -b file1[,file2[,...]]
   --bootstrap=file1[,file2[,...]]

Forces bootstrap mode for an entire export (-b '**') or for
certain files.  Filenames may contain wildcards, see L<Regexp::Shellish>
for details on what wildcards are accepted.  For now, one thing to
remember is to use '**' instead of p4's '...' wildcard.

Controls how the first revision of a file is exported.  A bootstrap
export contains the entire contents of the first revision in the revision
range.  This should only be used when exporting for the first time.

An incremental export contains a digest of the revision preceding the first
revision in the revision range, followed by a delta record between that
revision and the first revision in the range.  This allows the destination
import function to make sure that the incremental export begins where the
last export left off.

The default is decided on a per-file basis: if the first revision in the
range is revision #1, the full contents are exported.  Otherwise an
incremental export is done for that file.

This option is necessary when exporting only more recent revisions from
a repository.

=item --cd

Used to set the CVS root directory, overriding the value of the CVSROOT
environment variable.  Using this and --cd it is possible to export from
one CVS repository and import to another.

=item --rev-root

*experimental*

Sets the root of the source tree to export.  All files to be exported
must be under this root directory.  The default rev-root is all of the
leading non-wildcard directory names.  This can be useful in the unusual
case of exporting a sub-tree of a larger project.  I think.

=item -r

   -r v_0_001:v_0_002 -f
   -r v_0_002:-f

Passed to 'cvs log' as a '-r' revision specification.

WARNING: if this
string doesn't contain a ':', you're probably doing something wrong,
since you're not specifying a revision range.  vcp may warn about this
in the future.

This will normally only replicate files which are tagged.  This means
that files that have been added since, or which are missing the tag
for some reason, are ignored.

Use the L</-f> option to force files that don't contain the tag to be
exported.  This is probably what is expected.

One of -r or L</-D> must be specified.

=item -d

   -d "2000-11-18 5:26:30<="

Passed to 'cvs log' as a '-d' date specification. 

WARNING: if this
string doesn't contain a '>' or '<', you're probably doing something wrong,
since you're not specifying a range.  vcp may warn about this
in the future.

One of L</-r> or -D must be specified.

=item -f

Not implemented yet.

This option causes vcp to attempt to export files that don't contain a
particular tag.

It is an error to specify C<-f> without C<-r>.

It does this by exporting all revisions of files between the oldest and
newest files that the -r specified.  Without C<-f>, these would
be ignored.

=back

=head1 LIMITATIONS

   "What we have here is a failure to communicate!"
       - The warden in Cool Hand Luke

CVS does not try to protect itself from people checking in things that look
like snippets of CVS log file: they go in Ok, and they come out Ok, screwing up
the parser.

So, if you come accross a repository that contains messages that look like "cvs
log" output, this is likely to go awry.

At least one cvs repository out there has multiple revisions of a single file
with the same rev number.  The second and later revisions with the same rev
number are ignored with a warning like "Can't add same revision twice:...".

=cut

$VERSION = 1.1 ;

use strict ;

use Carp ;
use Getopt::Long ;
use VCP::Debug ':debug' ;
use Regexp::Shellish qw( :all ) ;
use VCP::Rev ;
use VCP::Source ;

use base 'VCP::Source' ;
use fields (
   'CVS_CUR',            ## The current change number being processed
   'CVS_FILESPEC',       ## What revs of what files to get.  ARRAY ref.
   'CVS_BOOTSTRAP',      ## Forces bootstrap mode
   'CVS_IS_INCREMENTAL', ## Hash of filenames, 0->bootstrap, 1->incremental
   'CVS_INFO',           ## Results of the 'cvs --version' command and CVSROOT
   'CVS_LABEL_CACHE',    ## ->{$name}->{$rev} is a list of labels for that rev
   'CVS_LABELS',         ## Array of labels from 'p4 labels'
   'CVS_MAX',            ## The last change number needed
   'CVS_MIN',            ## The first change number needed
   'CVS_REV_SPEC',       ## The revision spec to pass to `cvs log`
   'CVS_DATE_SPEC',      ## The date spec to pass to `cvs log`
   'CVS_FORCE_MISSING',  ## Set if -f was specified.
   'CVS_CVSROOT',        ## What to pass with -d, if anything

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

   my $parsed_spec = $self->parse_repo_spec( $spec ) ;

   my $files = $parsed_spec->{FILES} ;

   my $work_dir ;
   my $rev_root ;
   my $rev_spec ;
   my $date_spec ;
   my $force_missing ;

##TODO: Add option to Regexp::Shellish to allow '...' instead of or in
## addition to '**'.
   GetOptions(
      "b|bootstrap:s"   => sub {
	 my ( $name, $val ) = @_ ;
	 $self->{CVS_BOOTSTRAP} = $val eq ""
	    ? [ compile_shellish( "**" ) ]
	    : [ map compile_shellish( $_ ), split /,+/, $val ] ;
      },
      "cd=s"          => \$work_dir,
      "rev-root=s"    => \$rev_root,
      "r=s"           => \$rev_spec,
      "d=s"           => \$date_spec,
      "f+"            => \$force_missing,
   ) or $self->usage_and_exit ;

   unless ( defined $rev_spec || defined $date_spec ) {
      print STDERR "Revision (-r) or date (-D) specification missing\n" ;
      $self->usage_and_exit ;
   }

   if ( $force_missing && ! defined $rev_spec ) {
      print STDERR
         "Force missing (-f) may not be used without a revision spec (-r)\n" ;
      $self->usage_and_exit ;
   }

   unless ( defined $rev_root ) {
      $self->deduce_rev_root( $files ) ;
   }
   else {
      $files = "$rev_root/$files" ;
   }

## TODO: Figure out whether we should make rev_root merely set the rev_root
## in the header.  I think we probably should do it that way, as it's more
## flexible and less confusing.

   my $recurse = $files =~ s{/\.\.\.$}{} ;

   ## Don't normalize the filespec.
   $self->filespec( $files ) ;

   $self->cvsroot( $parsed_spec->{SERVER} ) ;
   $self->rev_spec( $rev_spec ) ;
   $self->date_spec( $date_spec ) ;
   $self->force_missing( $force_missing ) ;

   ## Make sure the cvs command is available
   $self->command( 'cvs', '-Q', '-z9' ) ;
   $self->command_stderr_filter(
      qr{^(?:cvs (?:server|add|remove): use 'cvs commit' to.*)\n}
   ) ;

   ## Doing a CVS command or two here also forces cvs to be found in new(),
   ## or an exception will be thrown.
   $self->command_dir( $work_dir ) if defined $work_dir ;
   $self->cvs( ['--version' ], \$self->{CVS_INFO} ) ;

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


sub filespec {
   my VCP::Source::cvs $self = shift ;
   $self->{CVS_FILESPEC} = shift if @_ ;
   return $self->{CVS_FILESPEC} ;
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


sub cvsroot {
   my VCP::Source::cvs $self = shift ;
   $self->{CVS_CVSROOT} = shift if @_ ;
   return $self->{CVS_CVSROOT} ;
}


sub cvsroot_cvs_option {
   my VCP::Source::cvs $self = shift ;
   return defined $self->cvsroot ? "-d" . $self->cvsroot : (),
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

sub cvs {
   my VCP::Source::cvs $self = shift ;

   unshift @{$_[0]}, $self->cvsroot_cvs_option ;
   return $self->SUPER::cvs( @_ ) ;
}


sub get_rev {
   my VCP::Source::cvs $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;

   my $wp = $self->work_path( $r->name, $r->rev_id ) ;
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
   ## and figure out which files should not be reported, because cvs log will
   ## emit the entire log for these files.
   my $tmp_f = $self->command_stderr_filter ;
   my %ignore_files ;
   my $ignore_file = sub {
      exists $ignore_files{$self->{CVS_NAME_REP_NAME}->{$_[0]}} ;
   } ;
   $self->command_stderr_filter( sub {
      my ( $err_text_ref ) = @_ ;
      $$err_text_ref =~ s@
         ^cvs\slog:\swarning:\sno\srevision\s.*?\sin\s[`"'](.*)[`"']\n
      @
         $ignore_files{$1} = undef ;
	 '' ;
      @gxme ;
   } ) ;

   $self->{CVS_LOG_FILE_DATA} = {} ;
   $self->{CVS_LOG_REV} = {} ;
   $self->{CVS_SAW_EQUALS} = 0 ;
   $self->cvs( [
         "log",
	 $self->rev_spec_cvs_option,
	 $self->date_spec_cvs_option,
	 length $self->filespec ? $self->filespec : (),
      ],
      '>', sub { $self->parse_log_file( @_ ) },
   ) ;

   $self->command_stderr_filter( $tmp_f ) ;

   my $revs = $self->revs ;

   ## Figure out the time stamp range for -f (FORCE_MISSING) calcs.
   my ( $min_rev_spec_time, $max_rev_spec_time ) ;
   if ( $self->{CVS_FORCE_MISSING} ) {
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
      $max_rev_spec_time = $max_time if substr( $self->rev_spec, -1 ) eq ':' ;

      debug(
	 "cvs: -f including files in ['" . localtime( $min_rev_spec_time ),
	 "'..'" . localtime( $max_rev_spec_time ),
	 "']"
      ) if debugging $self ;
   }

   ## Remove extra revs from queue.
   ## TODO: Debug simultaneous use of -r and -D, since we probably are
   ## blowing away revs that -D included that -r didn't.  I haven't
   ## checked to see if we do or don't blow said revs away.
   my %oldest_revs ;
   $self->revs( VCP::Revs->new ) ;
   for my $r ( @{$revs->as_array_ref} ) {
      if ( $ignore_file->( $r->source_name ) ) {
	 if ( defined $min_rev_spec_time 
	    && $r->time >= $min_rev_spec_time
	    && $r->time <= $max_rev_spec_time
	 ) {
	    debug(
	       "cvs: -f including file '", $r->source_name, "'"
	    ) if debugging $self ;
	 }
	 else {
	    debug(
	       "cvs: ignoring file '", $r->source_name,
	       "': no revisions match -r"
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

1
