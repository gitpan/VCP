package VCP::Source::p4 ;

=head1 NAME

VCP::Source::p4 - A Perforce p4 repository source

=head1 SYNOPSIS

   vcp p4://depot/...@10          # all files after change 10 applied
   vcp p4://depot/...@1,10        # changes 1..10
   vcp p4://depot/...@-2,10       # changes 8..10
   vcp p4://depot/...@1,#head     # changes 1..#head
   vcp p4://depot/...@-2,#head    # changes 8..10
   vcp p4:...@-2,#head            # changes 8..10, if only one depot

To specify a user name of 'user', P4PASSWD 'pass', and port 'port:1666',
use this syntax:

   vcp p4:user:client:pass@port:1666:files

Note: the password will be passed in the environment variable P4PASSWD
so it shouldn't show up in error messages.
User, client and the server string will
be passed as command line options to make them show up in error output.

You may use the P4... environment variables instead of any or all
of the fields in the p4: repository specification.  The repository
spec overrides the environment variables.

=head1 DESCRIPTION

Reads a p4d.

Note that not all metadata is exported: labels and users are not exported
as of yet.  This stuff will go in to the RevML at some point.

Also, the 'time' and 'mod_time' attributes will lose precision, since
p4 doesn't report them down to the minute.  Hmmm, seems like p4 never
sets a true mod_time.  It gets set to either the submit time or the
sync time.  From `C<p4 help client>`:

    modtime         Causes 'p4 sync' to force modification time 
		    to when the file was submitted.

    nomodtime *     Leaves modification time set to when the
		    file was fetched.

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

=item -r, --rev-root

Sets the root of the source tree to export.  All files to be exported
must be under this root directory.  The default rev-root is all of the
leading non-wildcard directory names.  This can be useful in the unusual
case of exporting a sub-tree of a larger project.  I think.

=back

=head1 METHODS

=over

=cut

use strict ;

use Carp ;
use Getopt::Long ;
use VCP::Debug ":debug" ;
use Regexp::Shellish qw( :all ) ;
use VCP::Rev ;
use VCP::Source ;

use base 'VCP::Source' ;
use fields (
   'P4_CUR',            ## The current change number being processed
   'P4_FILESPEC',       ## What revs of what files to get.  ARRAY ref.
   'P4_IS_INCREMENTAL', ## Hash of filenames, 0->bootstrap, 1->incremental
   'P4_INFO',           ## Results of the 'p4 info' command
   'P4_LABEL_CACHE',    ## ->{$name}->{$rev} is a list of labels for that rev
   'P4_LABELS',         ## Array of labels from 'p4 labels'
   'P4_MAX',            ## The last change number needed
   'P4_MIN',            ## The first change number needed
) ;

=item new

Creates a new instance of a VCP::Source::p4.  Contacts the p4d using the p4
command and gets some initial information ('p4 info' and 'p4 labels').

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Source::p4 $self = $class->SUPER::new( @_ ) ;

   ## Make sure the p4 command is available
   $self->command( 'p4' ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   my $parsed_spec = $self->parse_repo_spec( $spec ) ;
   my $files = $parsed_spec->{FILES} ;

   my $rev_root ;

##TODO: Add option to Regexp::Shellish to allow '...' instead of or in
## addition to '**'.

   GetOptions(
      'b|bootstrap:s'   => sub {
	 my ( $name, $val ) = @_ ;
	 $self->bootstrap( $val ) ;
      },
      'r|rev-root'      => \$rev_root,
      ) or $self->usage_and_exit ;

   ## If a change range was specified, we need to list the files in
   ## each change.  p4 doesn't allow an @ range in the filelog command,
   ## for wataver reason, so we must parse it ourselves and call lots
   ## of filelog commands.  Even if it did, we need to chunk the list
   ## so that we don't consume too much memory or need a temporary file
   ## to contain one line per revision per file for an entire large
   ## repo.
   my ( $name, $min, $comma, $max ) ;
   ( $name, $min, $comma, $max ) =
      $files =~ m/^([^@]*)(?:@(-?\d+)(?:(\D|\.\.)((?:\d+|#head)))?)?$/i
      or die "Unable to parse p4 filespec '$files'\n";

   die "'$comma' should be ',' in revision range in '$files'\n"
      if defined $comma && $comma ne ',' ;

   if ( ! defined $min ) {
      $min = 1 ;
      $max = '#head' ;
   }

   if ( ! defined $max ) {
      $max = $min ;
   }
   elsif ( lc( $max ) eq '#head' ) {
      $self->p4( [qw( counter change )], \$max ) ;
      chomp $max ;
   }

   if ( $min < 0 ) {
      $min = $max + $min ;
   }

   unless ( defined $rev_root ) {
      if ( length $name >= 2 && substr( $name, 0, 2 ) ne '//' ) {
         ## No depot on the command line, default it to the only depot
	 ## or error if more than one.
	 my $depots ;
	 $self->p4( ['depots'], \$depots ) ;
	 $depots = 'depot' unless length $depots ;
	 my @depots = split( /^/m, $depots ) ;
	 die "vcp: p4 has more than one depot, specify one as source\n"
	    if @depots > 1 ;
	 debug "vcp: defaulting depot to '$depots[0]'" if debugging $self ;
	 $name = join( '/', '/', $depots[0], $name ) ;
      }
      $self->deduce_rev_root( $name ) ;
   }
   else {
      $self->rev_root( $rev_root ) ;
      $name = join( '/', $rev_root, $name ) ;
   }

   die "no depot name specified for p4 source '$name'\n"
      unless $name =~ m{^//[^/]+/} ;

   ## Don't normalize the filespec.
   $self->filespec( $name ) ;

   $self->min( $min ) ;
   $self->max( $max ) ;
   $self->cur( undef ) ;

   $self->load_p4_info ;
   $self->load_p4_labels ;

   return $self ;
}


sub p4 {
   my VCP::Source::p4 $self = shift ;

   local $ENV{P4PASSWD} = $self->repo_password
      if defined $self->repo_password ;

   unshift @{$_[0]}, '-p', $self->repo_server
      if defined $self->repo_server ;

   if ( defined $self->repo_user ) {
      my ( $user, $client ) = $self->repo_user =~ m/([^()]*)(?:\((.*)\))?/ ;
      unshift @{$_[0]}, '-c', $client if defined $client ;
      unshift @{$_[0]}, '-u', $user ;
   }

   return $self->SUPER::p4( @_ ) ;
}


sub load_p4_info {
   my VCP::Source::p4 $self = shift ;

   my $errors = '' ;
   $self->p4( ['info'], \$self->{P4_INFO} ) ;
}


sub is_incremental {
   my VCP::Source::p4 $self= shift ;

   my ( $file, $first_rev ) = @_ ;

   my $bootstrap_mode = $first_rev == 1 || $self->is_bootstrap_mode( $file ) ;

   return ! $bootstrap_mode ;
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
   .*\r?\n\r?
}mx ;

# This re matches "... ...", if the previous re doesn't match.
#
my $filelog_etc_re = qr{
   \G                  # Use with /gc!!
   ^\.\.\.\s+\.\.\.
   .*\r?\n\r?
}mx ;

# And this one grabs the comment
my $filelog_comment_re = qr{
   \G
   ^\r?\n\r?
   ((?:^(?:\s|$).*\r?\n\r?)*)
   \n\r?
}mx ;


sub lookup_revs_in_change {
   my VCP::Source::p4 $self = shift ;

   my ( $change_id ) = @_ ;

   my $log = '' ;

   my $spec =  join( '', $self->filespec . '@' . $change_id ) ;
   my $temp_f = $self->command_stderr_filter ;
   $self->command_stderr_filter(
       qr{//\S* - no file\(s\) at that changelist number\.\s*\n}
   ) ;
   $self->p4( [qw( filelog -m 1 -l ), $spec ], \$log ) ;
   $self->command_stderr_filter( $temp_f ) ;

   $self->{P4_IS_INCREMENTAL} = {} ;

   while ( $log =~ m{\G(.*?)^//(.*?)\r?\n\r?}gmsc ) {
      warn "vcp: Ignoring '$1' in p4 filelog output\n" if length $1 ;
      my $name = $2 ;
      my $norm_name = $self->normalize_name( $name ) ;
      while () {
         next if $log =~ m{$filelog_etc_re}gc ;
         last unless $log =~ m{$filelog_rev_info_re}gc ;

	 my VCP::Rev $r = VCP::Rev->new(
	    name      => $norm_name,
	    rev_id    => $1,
	    change_id => $2,
	    action    => $3,
	    time      => $self->parse_time( $4 ),
	    user_id   => $5,
	    type      => $6,
	    comment   => '',
	 ) ;

	 if ( $r->change_id != $change_id ) {
	    debug(
	       "ignoring change '",
	       $r->change_id,
	       "' '",
	       $r->action,
	       "' for '$spec'" 
	    ) if debugging $self ;
	    $log =~ m{$filelog_comment_re}gc ;
	    next ;
	 }

	 my VCP::Rev $old_r = $self->seen( $r ) ;

         unless ( $old_r ) {
	    unless ( exists $self->{P4_IS_INCREMENTAL}->{$norm_name} ) {
	       my $ii = $self->is_incremental( "//$name", $r->rev_id ) ;
	       $self->{P4_IS_INCREMENTAL}->{$norm_name} = $ii ;
	       if ( $ii ) {
		  my $rev = $r->rev_id - 1 ;
		  my $blog ;
		  $self->p4( [qw( filelog -m 1 -l ), "//$name#$rev" ], \$blog );
		  debug (
		     "vcp: '", $r->name, "#", $r->rev_id,
		     "' incremental from #$rev"
		  ) if debugging $self ;

		  ## Skip the filename header line
		  $blog =~ m/\r?\n\r?/g
		     or die "Couldn't parse '$blog'" ;

		  $blog =~ m/$filelog_rev_info_re/gc
		     or die "Couldn't parse '$blog'" ;

		  my VCP::Rev $br = VCP::Rev->new(
		     name      => $norm_name,
		     rev_id    => $1,
		     change_id => $2,
      # Don't send these on a base rev for incremental changes:
      #		     action    => $3,
      #		     time      => $self->parse_time( $4 ),
      #		     user_id   => $5,
		     type      => $6,
      #		     comment   => '',
		  ) ;
		  $old_r = $br ;

		  ## Don't bother getting the comment or labels
		  debug(
		     sprintf(
			"vcp: queueing base rev %s#%s @%s (%s)",
			map $br->$_, qw( name rev_id change_id type )
		     )
		  ) if debugging $self ;
		  $self->revs->add( $br ) ;
	       }
	       else {
		  debug "vcp: bootstrapping '$norm_name#", $r->rev_id
		     if debugging $self ;
	       }
	    }
	 }
	       
	 ## Eat a blank line, then all comment lines, including a terminating
	 ## blank line after the comment.  The comment begins with a tab that
	 ## we trim, as well.
	 if ( $log =~ m{$filelog_comment_re}gc ) {
	    if ( defined $1 ) {
	       my $comment = $1 ;
	       $comment =~ s/^\s//gm ;
	       $comment =~ s/\r\n|\n\r/\n/g ;
	       $r->comment( $comment ) ;
	    }
	 }
	 else {
	    warn
	    "vcp: No comment parsed for $name#", $r->rev_id,
	    ' @', $r->change_id ;
	 }
	 $r->labels( $self->get_p4_file_labels( $r->name, $r->rev_id ) );
         if ( $r->change_id eq $change_id
	    && ( ! $old_r || $old_r->rev_id ne $r->rev_id )
	 ) {
	    debug(
	       sprintf(
		  "vcp: queueing %s#%s @%s %s %s %s (%s)\n%s",
		  map(
		     $r->$_,
		     qw(name rev_id change_id action time user_id type comment)
		  )
	       )
	    ) if debugging $self ;
	    $self->revs->add( $r ) ;
	 }
	 else {
	    die $r->as_string, " ??? ", $old_r->as_string ;
	 }
      }
   }
}


sub filespec {
   my VCP::Source::p4 $self = shift ;
   $self->{P4_FILESPEC} = shift if @_ ;
   return $self->{P4_FILESPEC} ;
}


sub cur {
   my VCP::Source::p4 $self = shift ;
   $self->{P4_CUR} = shift if @_ ;
   return $self->{P4_CUR} ;
}


sub min {
   my VCP::Source::p4 $self = shift ;
   $self->{P4_MIN} = shift if @_ ;
   return $self->{P4_MIN} ;
}


sub max {
   my VCP::Source::p4 $self = shift ;
   $self->{P4_MAX} = shift if @_ ;
   return $self->{P4_MAX} ;
}


sub load_p4_labels {
   my VCP::Source::p4 $self = shift ;

   my $labels = '' ;
   my $errors = '' ;
   $self->p4( ['labels'], \$labels ) ;

   @{$self->{P4_LABELS}} = map(
      /^Label\s*(\S*)/ ? $1 : (),
      split( /^/m, $labels )
   ) ;
   return ;
}


sub denormalize_name {
   my VCP::Source::p4 $self = shift ;
   return '//' . $self->SUPER::denormalize_name( @_ ) ;
}


sub get_p4_file_labels {
   my VCP::Source::p4 $self = shift ;

   my $name ;
   my VCP::Rev $rev ;
   ( $name, $rev ) = @_ ;

   my $labels = $self->{P4_LABELS} ;

   if ( ! exists $self->{P4_LABEL_CACHE}->{$name} && @$labels ) {
      my $files = '' ;
      my $errors = '' ;
      $self->p4(
         ['files', map $self->denormalize_name( $name ) . "\@$_", @$labels ],
	    '>', \$files,
	    '2>', \$errors,
      );

      ## Build a list of labels that don't match, so we can skip them
      ## when scanning stdout.
      my %no_match = map { ( $_ => 1 ) } $errors =~ /\@(\S+)/g ;

      my @labels = grep ! exists $no_match{$_}, @$labels ;

      for ( split( /^/m, $files ) ) {
	 if ( /^\S+?#(\d+)/ ) {
	    die "Ran out of labels before running out of files"
	       unless @labels ;
	    push @{$self->{P4_LABEL_CACHE}->{$name}->{$1}}, shift @labels ;
	 }
	 else {
	    die "Indecipherable output from 'p4 files': $_" ;
	 }
      } ;
      die "Ran out of files before running out of labels"
	 if @labels ;
   }

   return (
      (  exists $self->{P4_LABEL_CACHE}->{$name}
      && exists $self->{P4_LABEL_CACHE}->{$name}->{$rev}
      )
	 ?  @{$self->{P4_LABEL_CACHE}->{$name}->{$rev}}
	 : ()
   ) ;
}


sub get_rev {
   my VCP::Source::p4 $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;

   my $fn  = $r->name ;
   my $rev = $r->rev_id ;
   $r->work_path( $self->work_path( $fn, $rev ) ) ;
   my $wp  = $r->work_path ;
   $self->mkpdir( $wp ) ;

   ## TODO: Don't filter non-text files.
   ## TODO: Consider using a 'p4 sync' command to restore the modification
   ## time so we can capture it.
   $self->p4(
      [ 'print', $self->denormalize_name( $fn ) . "#$rev" ],
      '|', sub {
         @ARGV = () ;   ## Make this a STDIN filter.
         <> ;           ## Throw away the first line, a p4 file header line
	 while (<>) {
	    print ;
	 }
	 close STDOUT ;
	 ## TODO: Rework this to get rid of dependancy on Unix signals
	 kill 9, $$ ;   ## Exit without running DESTRUCTs.
      },
      '>', $wp,
   ) ;

   return ;
}


sub handle_header {
   my VCP::Source::p4 $self = shift ;
   my ( $header ) = @_ ;

   $header->{rep_type} = 'p4' ;
   $header->{rep_desc} = $self->{P4_INFO} ;
   $header->{rev_root} = $self->rev_root ;

   $self->dest->handle_header( $header ) ;
   return ;
}


sub copy_revs {
   my VCP::Source::p4 $self = shift ;

   $self->revs( VCP::Revs->new ) ;

   for (
      $self->cur( $self->min ) ;
      $self->cur <= $self->max ;
      $self->cur( $self->cur + 1 )
   ) {
      $self->lookup_revs_in_change( $self->cur ) ;
   }

   $self->dest->sort_revs( $self->revs ) ;

   my VCP::Rev $r ;
   while ( $r = $self->revs->shift ) {
      $self->get_rev( $r ) ;
      $self->dest->handle_rev( $r ) ;
   }
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
