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

Note: the password will be passed in the environment variable P4PASSWD
so it shouldn't show up in error messages. This means that a password
specified in a P4CONFIG file will override the password you set on the
command line. This is a bug.  User, client and the server string will be
passed as command line options to make them show up in error output.

You may use the P4... environment variables instead of any or all of the
fields in the p4: repository specification.  The repository spec
overrides the environment variables.

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

=over

=item -b, --bootstrap

   -b '...'
   --bootstrap='...'
   -b file1[,file2[,...]]
   --bootstrap=file1[,file2[,...]]

(the C<...> there is three periods, a
L<Regexp::Shellish|Regexp::Shellish> wildcard borrowed from C<p4>
path syntax).

Forces bootstrap mode for an entire export (-b '...') or for certain
files.  Filenames may contain wildcards, see L<Regexp::Shellish> for
details on what wildcards are accepted.

Controls how the first revision of a file is exported.  A bootstrap
export contains the entire contents of the first revision in the revision
range.  This should only be necessary when exporting for the first time.

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

B<Experimental>.

Falsifies the root of the source tree being extracted; files will
appear to have been extracted from some place else in the hierarchy.
This can be useful when exporting RevML, the RevML file can be made
to insert the files in to a different place in the eventual destination
repository than they existed in the source repository.

The default C<rev-root> is the file spec up to the first path segment
(directory name) containing a wildcard, so

   p4:/a/b/c...

would have a rev-root of C</a/b>.

In direct repository-to-repository transfers, this option should not be
necessary, the destination filespec overrides it.

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
use IPC::Run qw( run io timeout new_chunker ) ;

use base qw( VCP::Source VCP::Utils::p4 ) ;
use fields (
   'P4_REPO_CLIENT',    ## Set by p4_parse_repo_spec in VCP::Utils::p4
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

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_p4_repo_spec( $spec ) ;

   my $rev_root ;

   GetOptions(
      'b|bootstrap:s'   => sub {
	 my ( $name, $val ) = @_ ;
	 $self->bootstrap( $val ) ;
      },
      'r|rev-root=s'    => \$rev_root,
      ) or $self->usage_and_exit ;


   my $name = $self->repo_filespec ;
   unless ( defined $rev_root ) {
      if ( length $name >= 2 && substr( $name, 0, 2 ) ne '//' ) {
         ## No depot on the command line, default it to the only depot
	 ## or error if more than one.
	 my $depots ;
	 $self->p4( ['depots'], \$depots ) ;
	 $depots = 'depot' unless length $depots ;
	 my @depots = split( /^/m, $depots ) ;
	 die "vcp: p4 has more than one depot, can't assume //depot/...\n"
	    if @depots > 1 ;
	 debug "vcp: defaulting depot to '$depots[0]'" if debugging $self ;
	 $name = join( '/', '/', $depots[0], $name ) ;
      }
      $self->deduce_rev_root( $name ) ;
   }
   else {
      $self->rev_root( $rev_root ) ;
   }

   die "no depot name specified for p4 source '$name'\n"
      unless $name =~ m{^//[^/]+/} ;
   $self->repo_filespec( $name ) ;

   $self->load_p4_info ;
   $self->load_p4_labels ;

   return $self ;
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

   my $spec =  join( '', $self->repo_filespec . '@' . $last_change_id ) ;
   my $temp_f = $self->command_stderr_filter ;
   $self->command_stderr_filter(
       qr{//\S* - no file\(s\) at that changelist number\.\s*\r?\n}
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
	  qr{//\S* - no file\(s\) at that changelist number\.\s*\r?\n}
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

   my $marker = "//.../NtLkly" ;
   my $p4_files_args =
      join(
         "",
	 ( map {
	    ( "$marker\n", "//...\@$_\n" ) ;
	 } @labels ),
      ) ;
   my $files ;
   $self->p4( [ qw( -x - -s files) ], "<", \$p4_files_args, ">", \$files ) ;

   my $label ;
   for my $spec ( split /\n/m, $files ) {
      last if $spec =~ /^exit:/ ;
      if ( $spec =~ /^error: $marker/o ) {
	 $label = shift @labels ;
	 next ;
      }
      next if $spec =~ m{^error: //\.\.\.\@.+ file(\(s\))? not in label.$} ;
      $spec =~ /^.*?: *\/\/(.*)#(\d+)/
	 or die "Couldn't parse name & rev from '$spec' in '$files'" ;

      debug "vcp: p4 label '$label' => '$1#$2'" if debugging $self ;
      push @{$self->{P4_LABEL_CACHE}->{$1}->{$2}}, $label ;
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


sub get_rev {
   my VCP::Source::p4 $self = shift ;

   my VCP::Rev $r ;

   ( $r ) = @_ ;

   return if defined $r->action && $r->action eq "delete" ;
   my $fn  = $r->name ;
   my $rev = $r->rev_id ;
   $r->work_path( $self->work_path( $fn, $rev ) ) ;
   my $wp  = $r->work_path ;
   $self->mkpdir( $wp ) ;

   my $denormalized_name = $self->denormalize_name( $fn ) ;
   my $rev_spec = "$denormalized_name#$rev" ;

   sysopen( WP, $wp, O_CREAT | O_WRONLY )
      or die "$!: $wp" ;

   binmode WP ;

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

   ## Discard the revs so they'll be DESTROYed and thus
   ## clean up after themselves.
   while ( my VCP::Rev $r = $self->revs->shift ) {
      $self->get_rev( $r ) ;
      $self->dest->handle_rev( $r ) ;
   }
}

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
