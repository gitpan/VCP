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

To specify a user name of 'user', P4PASSWD 'pass', and port 'host:1666',
use this syntax:

   vcp p4:user(client)password@host:1666:files

Note: the password will be passed in the environment variable P4PASSWD so it
shouldn't show up in error messages. This means that a password specified in a
P4CONFIG file will override the password you set on the command line. This is a
bug.  User, client and the server string will be passed as command line options
to make them show up in error output.

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

$VERSION = 1.0 ;

use strict ;

use Carp ;
use Getopt::Long ;
use Fcntl qw( O_WRONLY O_CREAT ) ;
use VCP::Debug ":debug" ;
use Regexp::Shellish qw( :all ) ;
use VCP::Rev ;
use VCP::Source ;
use IPC::Run qw( run io timeout new_chunker ) ;

use base 'VCP::Source' ;
use fields (
   'P4_FILESPEC',       ## What revs of what files to get.  ARRAY ref.
   'P4_INFO',           ## Results of the 'p4 info' command
   'P4_LABEL_CACHE',    ## ->{$name}->{$rev} is a list of labels for that rev
#   'P4_LABELS',         ## Array of labels from 'p4 labels'
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

   my $tmp = $ENV{PWD} ;
   delete $ENV{PWD} ;

   $self->SUPER::p4( @_ ) ;
   $ENV{PWD} = $tmp if defined $tmp ;
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
   .*\r?\n
}mx ;

# And this one grabs the comment
my $filelog_comment_re = qr{
   \G
   ^\r?\n
   ((?:^[^\S\r\n].*\r?\n)*)
   ^\r?\n
}mx ;


sub scan_filelog {
   my VCP::Source::p4 $self = shift ;

   my ( $first_change_id, $last_change_id ) = @_ ;

   my $log = '' ;

   my $delta = $last_change_id - $first_change_id + 1 ;

   my $spec =  join( '', $self->filespec . '@' . $last_change_id ) ;
   my $temp_f = $self->command_stderr_filter ;
   $self->command_stderr_filter(
       qr{//\S* - no file\(s\) at that changelist number\.\s*\n}
   ) ;

   my %oldest_revs ;
   {
      my $log_state = "need_file" ;

      my VCP::Rev $r ;
      my $name ;
      my $comment ;

      my $p4_filelog_parser = sub {
	 local $_ = shift ;

      REDO_LINE:
	 if ( $log_state eq "need_file" ) {
	    die "\$r defined" if defined $r ;
	    die "vcp: p4 filelog parser: file name expected, got '$_'"
	       unless m{^//(.*?)\r?\n\r?} ;

	    $name = $1 ;
	    $log_state = "revs" ;
	 }
	 elsif ( $log_state eq "revs" ) {
	    return if m{^\.\.\.\s+\.\.\..*\r?\n\r?} ;
	    unless ( m{$filelog_rev_info_re} ) {
	       $log_state = "need_file" ;
	       goto REDO_LINE ;
	    }

	    my $change_id = $2 ;
	    if ( $change_id < $self->min ) {
	       undef $r ;
	       $log_state = "need_comment" ;
	       return ;
	    }

	    my $type = $6 ;

	    my $norm_name = $self->normalize_name( $name ) ;
	    die "\$r defined" if defined $r ;
	    $r = VCP::Rev->new(
	       name      => $norm_name,
	       rev_id    => $1,
	       change_id => $change_id,
	       action    => $3,
	       time      => $self->parse_time( $4 ),
	       user_id   => $5,
	       p4_info   => $_,
	       comment   => '',
	    ) ;

	    my $is_binary = $type =~ /^(?:u?x?binary|x?tempobj|resource)/ ;
	    $r->type( $is_binary ? "binary" : "text" ) ;

	    $r->labels( $self->get_p4_file_labels( $name, $r->rev_id ) );

	    ## Filelogs are in newest...oldest order, so this should catch
	    ## the oldest revision of each file.
	    $oldest_revs{$name} = $r ;

	    debug "vcp: ", $r->as_string if debugging $self ;

	    $log_state = "need_comment" ;
	 }
	 elsif ( $log_state eq "need_comment" ) {
	    unless ( /^$/ ) {
	       die
   "vcp: p4 filelog parser: expected a blank line before a comment, got '$_'" ;
	    }
	    $log_state = "comment_accum" ;
	 }
	 elsif ( $log_state eq "comment_accum" ) {
	    if ( /^$/ ) {
	       if ( defined $r ) {
		  $r->comment( $comment ) ;
		  $self->revs->add( $r ) ;
		  $r = undef ;
	       }
	       $comment = undef ;
	       $log_state = "revs" ;
	       return ;
	    }
	    unless ( s/^\s// ) {
	       die "vcp: p4 filelog parser: expected a comment line, got '$_'" ;
	    }
	    $comment .= $_ ;
	 }
	 else {
	    die "unknown log_state '$log_state'" ;
	 }
      } ;

      $self->p4(
	 [qw( filelog -m ), $delta, "-l", $spec ],
	 '>', new_chunker, $p4_filelog_parser
      ) ;
      $self->command_stderr_filter( $temp_f ) ;

      die "\$r defined" if defined $r ;
   }

   my @base_rev_specs ;
   for my $name ( sort keys %oldest_revs ) {
      my $r = $oldest_revs{$name} ;
      my $rev_id = $r->rev_id ;
      if ( $self->is_incremental( "//$name", $r->rev_id ) ) {
	 $rev_id -= 1 ;
	 push @base_rev_specs, "//$name#$rev_id" ;
      }
      else {
	 debug "vcp: bootstrapping '", $r->name, "#", $r->rev_id, "'"
	    if debugging $self ;
      }
      $oldest_revs{$name} = undef ;
   }

   if ( @base_rev_specs ) {
      undef $log ;
      $self->command_stderr_filter(
	  qr{//\S* - no file\(s\) at that changelist number\.\s*\n}
      ) ;
      $self->p4( [qw( filelog -m 1 -l ), @base_rev_specs ], \$log ) ;
      $self->command_stderr_filter( $temp_f ) ;

      while ( $log =~ m{\G(.*?)^//(.*?)\r?\n\r?}gmsc ) {
	 warn "vcp: Ignoring '$1' in p4 filelog output\n" if length $1 ;
	 my $name = $2 ;

	 my $norm_name = $self->normalize_name( $name ) ;
	 while () {
	    next if     $log =~ m{\G^\.\.\.\s+\.\.\..*\r?\n\r?}gmc ;

	    last unless $log =~ m{$filelog_rev_info_re}gc ;

	    my VCP::Rev $br = VCP::Rev->new(
	       name      => $norm_name,
	       rev_id    => $1,
	       change_id => $2,
   # Don't send these on a base rev for incremental changes:
   #	     action    => $3,
   #	     time      => $self->parse_time( $4 ),
   #	     user_id   => $5,
		type      => $6,
   #	     comment   => '',
	    ) ;

	    $self->revs->add( $br ) ;

	    $log =~ m{$filelog_comment_re}gc ;
	 }
      }
   }
}


sub filespec {
   my VCP::Source::p4 $self = shift ;
   $self->{P4_FILESPEC} = shift if @_ ;
   return $self->{P4_FILESPEC} ;
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

   my @labels = map(
      /^Label\s*(\S*)/ ? $1 : (),
      split( /^/m, $labels )
   ) ;

   $self->command_ok_result_codes( 0, 1 ) ;

   while ( @labels ) {
      my $bundle_size = @labels > 25 ? @labels : 25 ;
      my @bundle_o_labels = splice @labels, 0, $bundle_size ;

      my $marker = "//.../NtLkly" ;
      my @p4_files_args = map {
         ( $marker, "//...\@$_" ) ;
      } @bundle_o_labels ;
      my $files ;
      $self->p4( [ "-s", "files", @p4_files_args ], \$files ) ;

      my $label ;
      for my $spec ( split /\n/m, $files ) {
         last if $spec =~ /^exit:/ ;
         if ( $spec =~ /^error: $marker/o ) {
	    $label = shift @bundle_o_labels ;
	    next ;
	 }
	 next if $spec =~ m{^error: //\.\.\.\@.+ file(\(s\))? not in label.$} ;
         $spec =~ /^.*?: *\/\/(.*)#(\d+)/
	    or die "Couldn't parse name & rev from '$spec' in '$files'" ;

         debug "vcp: p4 label '$label' => '$1#$2'" if debugging $self ;
	 push @{$self->{P4_LABEL_CACHE}->{$1}->{$2}}, $label ;
      }
   }
   $self->command_ok_result_codes( 0 ) ;

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

   return (
      (  exists $self->{P4_LABEL_CACHE}->{$name}
      && exists $self->{P4_LABEL_CACHE}->{$name}->{$rev}
      )
	 ? @{$self->{P4_LABEL_CACHE}->{$name}->{$rev}}
	 : ()
   ) ;
}


my $filter_prog = <<'EOPERL' ;
   use strict ;
   my ( $name, $working_path ) = ( shift, shift ) ;
   }
EOPERL


sub get_revs {
   my VCP::Source::p4 $self = shift ;

   my ( @revs ) = @_ ;

   return unless @revs ;

   for ( @revs ) {
      my VCP::Rev $r = $_ ;  ## 5.00503 doesn't have for my Foo $foo (...)
      next if defined $r->action && $r->action eq "delete" ;
      my $fn  = $r->name ;
      my $rev = $r->rev_id ;
      $r->work_path( $self->work_path( $fn, $rev ) ) ;
      my $wp  = $r->work_path ;
      $self->mkpdir( $wp ) ;

      my $denormalized_name = $self->denormalize_name( $fn ) ;
      my $rev_spec = "$denormalized_name#$rev" ;

      sysopen( WP, $wp, O_CREAT | O_WRONLY )
	 or die "$!: $wp" ;

      my $re = quotemeta( $rev_spec ) . " - .* change \\d+ \\((.+)\\)";

      ## TODO: look for "+x" in the (...) and pass an executable bit
      ## through the rev structure.

      $self->p4( 
	 [ "print", $rev_spec ],
	 ">", sub {
	    $_ = shift ;
            s/\A$re\r?\n//m if $re ;
	    print WP or die "$! writing to $wp" ;
	    $re = undef ;
	 },
      ) ;

      close WP or die "$! closing wp" ;
   }

#   ## TODO: Don't filter non-text files.
#   ## TODO: Consider using a 'p4 sync' command to restore the modification
#   ## time so we can capture it.
#   my $dispatch_prog = <<'EOPERL' ;
#      use strict ;
#      my ( $name, $working_path ) = ( shift, shift ) ;
#      my $re = "info: " . quotemeta( $name ) . " - .* change \\d+ \\((.+)\\)\$";
#      my $found_header ;
#      my $found_this_header ;
#      my $header_like = '' ;
#      while (<STDIN>) {
#	 if ( defined $re && /$re/m ) {
#	    $found_header = 1 ;
#	    $found_this_header = 1 ;
#	    open( STDOUT, ">$working_path" )
#	       or die ">$working_path" ;
#	    if ( @ARGV ) {
#	       ( $name, $working_path ) = ( shift, shift ) ;
#	       $re = "info: " . quotemeta( $name ) . " - .* change \\d+ \\((.+)\\)\$";
#	       $found_this_header = 0 ;
#	       $header_like = "" ;
#	    }
#	    else {
#	       undef $re ;
#	    }
#	    next ;
#	 }
#	 die "No header found for '$name' in '$_' using qr{$re}"
#	    unless $found_header ;
#	 $header_like = $_ if ! length $header_like && m{\/\/.*#\d+ - } ;
#	 s/^text: // ;
#	 next if /^exit: \d+/ ;
#	 print ;
#      }
#
#      unshift @ARGV, ( $name, $working_path ) unless $found_this_header ;
#
#      die(
#         "Did not find ",
#         @ARGV / 2,
#         " files in p4 print output\n",
#	 ( length $header_like ? "suspect qr{$header_like} didn't match\n":()),
#         join( '', map "'$_'\n", @ARGV )
#      ) if @ARGV ;
#EOPERL
#   $self->p4(
#      [ "-s", "print", @rev_specs ],
#      "|", [ $^X, "-we", $dispatch_prog, @dispatcher_args ]
#   ) ;

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

   $self->scan_filelog( $self->min, $self->max ) ;
   $self->dest->sort_revs( $self->revs ) ;

   my VCP::Rev $r ;
   my @bundle_o_revs ;
   my %bundled_rev_names ;
   while ( $r = $self->revs->shift ) {
      if ( @bundle_o_revs >= 50 ) {#|| exists $bundled_rev_names{$r->name} ) {
         $self->get_revs( @bundle_o_revs ) ;
	 $self->dest->handle_rev( $_ ) for @bundle_o_revs ;
	 @bundle_o_revs = () ;
	 %bundled_rev_names = () ;
      }
      push @bundle_o_revs, $r ;
      $bundled_rev_names{$r->name} = undef ;
   }

   $self->get_revs( @bundle_o_revs ) ;
   for ( @bundle_o_revs ) {
      debug "vcp: sending ", $_->as_string, " to dest" if debugging $self ;
      $self->dest->handle_rev( $_ ) 
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

1
