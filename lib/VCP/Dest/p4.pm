package VCP::Dest::p4 ;

=head1 NAME

VCP::Dest::p4 - p4 destination driver

=head1 SYNOPSIS

   vcp <source> p4[:<dest>]

where <dest> is a filespec to a directory in the perforce repository or on the
local client of the directory tree to use when importing files (this is known
as the "rev root", for lack of a better term).

The <dest> spec is run through the `p4 where` command to get an absolute path
on the local filesystem.  `p4 where` must generate exactly one line of output,
and the line is parsed to strip off the depot and client filespecs, including
file and directory names containing spaces (directory names containing trailing
spaces are not handled correctly!).

See `p4 help where` and the Perforce User's Guide for details on how to specify
the <dest>, but here's an overview (do check the Perforce User's Guide to see
if your version of `p4 where` behaves differently):

=over

=item *

any //depot/, //client/, or absolute or relative local filesystem spec can be
supplied for <dest> (local specs should not begin with "//" even if the local
OS would be Ok with it).

=item *

No need to type "/..." at the end of <dest>, VCP::Dest::p4
adds it if it's missing.

=item *

Relative specs (or a missing <dest>) are taken (by p4 where) to be relative to
the current working directory.

=item *

You cannot put directory names like "./" or "../" in the middle of any spec,
only at the beginning of a relative local filesystem spec.

=back

VCP::Dest::p4 does change number aggregation, see L<VCP::Dest/rev_cmp_sub>
for the order in which revisions are sorted. Once sorted, a change is submitted
whenever the change number (if present) changes, the comment (if present)
changes, or a new rev of a file with the same name as a revision that's
pending. THIS IS EXPERIMENTAL, PLEASE DOUBLE CHECK EVERYTHING!

=head1 DESCRIPTION

=head1 METHODS

=over

=cut

$VERSION = 1 ;

use strict ;
use vars qw( $debug ) ;

$debug = 0 ;

use Carp ;
use File::Basename ;
use File::Path ;
use Getopt::Long ;
use VCP::Debug ':debug' ;
use VCP::Dest ;
use VCP::Rev ;

use base 'VCP::Dest' ;
use fields (
#   'P4_SPEC',       ## The root of the tree to update
   'P4_PENDING',    ## Revs pending the next submit
   'P4_DELETES_PENDING',    ## At least one 'delete' needs to be submitted.
   'P4_WORK_DIR',   ## Where to do the work.

   ## members for change number divining:
   'P4_PREV_CHANGE_ID',  ## The change_id in the r sequence, if any
   'P4_PREV_COMMENT',    ## Used to detect change boundaries
) ;

=item new

Creates a new instance of a VCP::Dest::p4.  Contacts the p4d using the p4
command and gets some initial information ('p4 info' and 'p4 labels').

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Dest::p4 $self = $class->SUPER::new( @_ ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   my $parsed_spec = $self->parse_repo_spec( $spec ) ;

   my $files = $parsed_spec->{FILES} ;

   $self->{P4_PENDING} = [] ;

   GetOptions( "ArGhOpTioN" => \"" ) or $self->usage_and_exit ; # No options!

   $self->command( 'p4' ) ;

   my @where_spec ;
   if ( defined $files && length $files ) {
      @where_spec = ( $files ) ;
      $where_spec[0] =~ s{(/(\.\.\.)?)?$}{/...} ;
   }

   my $where_map ;
   $self->p4( [ where => @where_spec ], ">", \$where_map ) ;

   {
      my @where_map = split /\n/g, $where_map ;
      die "vcp: `p4 where` did not return a mapping for '$files'\n"
	 unless @where_map ;
      die(
          "vcp: `p4 where",
          map( " '$_'", @where_spec ),
          "` returned more than one line:\n$where_map"
      ) unless @where_map == 1 ;
   }

   my $work_root = $self->strip_p4_where( $where_map ) ;

   die "Couldn't parse `p4 where` output\np4 where: $where_map"
       unless defined $work_root and length $work_root ;

   $self->work_root( $work_root ) ;
   $self->command_chdir( $self->work_root ) ;
#   $self->mkdir( $self->work_path ) ;

   return $self ;
}


sub p4 {
   my VCP::Dest::p4 $self = shift ;

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


=item strip_p4_where

Takes a line of output from a `p4 where` command and strips off all but the
last filespec. This is a bit tricky in the face of directory names with spaces
and is very hard or impossible if a directory name ends in a space.

It's a separate function so the test suite can have at it.

=cut

sub strip_p4_where {
   shift ;
   my ( $where_stdout ) = @_ ;

   1 while chomp $where_stdout ;
   # Trim off up to the last "//" and all non-space chars after it.
   # Also keep trimming until the first " /" to try to work around
   # spaces in file names.
   my $path_start_re = $^O =~ /Win|DOS/i
       ? "(?:[A-Za-z]:)?[\\\\/]"
       : "/(?!/)" ;

   $where_stdout =~ s{^.* (?=$path_start_re)}{}
       or return undef ;

   $where_stdout =~ s{[\\/]\.\.\.$}{} ;
   return $where_stdout ;
}


sub denormalize_name {
   my VCP::Dest::p4 $self = shift ;
   return '//' . $self->SUPER::denormalize_name( @_ ) ;
}


sub backfill {
   my VCP::Dest::p4 $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

confess unless defined $self && defined $self->header ;

   if ( $self->none_seen ) {
      $self->rev_root( $self->header->{rev_root} )
         unless defined $self->rev_root ;
   }

   my $fn = $self->denormalize_name( $r->name ) ;
   ## The depot name was handled by the client view.
   $fn =~ s{^//[^/]+/}{} ;
   debug "vcp: backfilling '$fn', rev ", $r->rev_id if debugging $self ;

   my $work_path = $self->work_path( $fn ) ;
   debug "vcp: work_path '$work_path'" if debugging $self ;

   my VCP::Rev $saw = $self->seen( $r ) ;

   die "Can't backfill already seen file '", $r->name, "'" if $saw ;

   my ( undef, $work_dir ) = fileparse( $work_path ) ;
   unless ( -d $work_dir ) {
      $self->mkpdir( $work_path ) ;
      ( undef, $work_dir ) = fileparse( $fn ) ;
   }

   my $tag = "r_" . $r->rev_id ;
   $tag =~ s/\W+/_/g ;

   ## The -f forces p4 to sync even if it thinks it doesn't have to.  It's
   ## not in there for any known reason, just being conservative.
   $self->p4( ['sync', '-f', "$fn\@$tag" ] ) ;
   die "'$work_path' not created in backfill" unless -e $work_path ;

   $r->work_path( $work_path ) ;

   return 1 ;
}


sub handle_rev {
   my VCP::Dest::p4 $self = shift ;

   my VCP::Rev $r ;
   ( $r ) = @_ ;
debug "vcp: handle_rev got $r ", $r->name if debugging $self ;

   ## TODO: Build a view as needed that maps P4_SPEC on to the
   ## /tmp/... workspace.  could even modify an existing view, I
   ## suppose, but I don't want to risk damaging an existing view.
   if ( $self->none_seen ) {
      $self->rev_root( $self->header->{rev_root} )
         unless defined $self->rev_root ;
   }

   if ( 
      ( @{$self->{P4_PENDING}} || $self->{P4_DELETES_PENDING} )
      && (
	 (
	    defined $r->change_id && defined $self->{P4_PREV_CHANGE_ID}
	    &&      $r->change_id ne         $self->{P4_PREV_CHANGE_ID}
	    && ( debugging( $self ) ? debug "vcp: change_id changed" : 1 )
	 )
	 || (
	    defined $r->comment && defined $self->{P4_PREV_COMMENT}
	    &&      $r->comment ne         $self->{P4_PREV_COMMENT}
	    && ( debugging( $self ) ? debug "vcp: comment changed" : 1 )
	 )
	 || (
	    grep( $r->name eq $_->name, @{$self->{P4_PENDING}} )
	    && ( debugging( $self ) ? debug "vcp: name repeated" : 1 )
	 )
      )
   ) {
      $self->submit ;
   }


   
   my VCP::Rev $saw = $self->seen( $r ) ;

   my $fn = $self->denormalize_name( $r->name ) ;
   ## The depot name was handled by the client view.
   $fn =~ s{^//[^/]+/}{} ;
   debug "vcp: importing '$fn'" if debugging $self ;
   my $work_path = $self->work_path( $fn ) ;
   debug "vcp: work_path '$work_path'" if debugging $self ;

   if ( $r->action eq 'delete' ) {
      unlink $work_path || die "$! unlinking $work_path" ;
      $self->p4( ['delete', $fn] ) ;
      $self->{P4_DELETES_PENDING} = 1 ;
      $self->delete_seen( $r ) ;
   }
   else {
   ## TODO: Don't assume same filesystem or working link().
      {
         my $filetype = defined $r->p4_info && $r->p4_info =~ /\((\S+)\)$/
	    ? $1
	    : $r->type ;

         my $add_it ;
	 if ( -e $work_path ) {
	    $self->p4( ["edit", "-t", $filetype, $fn] ) ;
	    unlink $work_path          or die "$! unlinking $work_path" ;
	 }
	 else {
	    $self->mkpdir( $work_path ) ;
	    $add_it = 1 ;
	 }
	 debug "vcp: linking ", $r->work_path, " to $work_path" if debugging $self ;
	 link $r->work_path, $work_path
	    or die "$! linking ", $r->work_path, " -> $work_path" ;

	 $r->dest_work_path( $work_path ) ;

	 if ( defined $r->mod_time ) {
	    utime $r->mod_time, $r->mod_time, $work_path
	       or die "$! changing times on $work_path" ;
	 }
	 if ( $add_it ) {
	    $self->p4( ["add", "-t", $filetype, $fn] ) ;
	 }
      }

      unless ( $saw ) {
	 ## New file.
      }

      my $tag = "r_" . $r->rev_id ;
      $tag =~ s/\W+/_/g ;
      $r->add_label( $tag ) ;
      if ( defined $r->change_id ) {
	 my $tag = "ch_" . $r->change_id ;
	 $tag =~ s/\W+/_/g ;
	 $r->add_label( $tag ) ;
      }

      ## TODO: Provide command line options for user-defined tag prefixes
debug "vcp: saving off $r ", $r->name, " in PENDING" if debugging $self ;
      push @{$self->{P4_PENDING}}, $r ;
   }

   $self->{P4_PREV_CHANGE_ID} = $r->change_id ;
debug "vcp: done importing '$fn'" if debugging $self ;
debug "vcp: cleaning up $saw ", $saw->name, " in PENDING" if $saw && debugging $self ;

   $self->{P4_PREV_COMMENT} = $r->comment ;
}


sub handle_footer {
   my VCP::Dest::p4 $self = shift ;

   $self->submit if @{$self->{P4_PENDING}} || $self->{P4_DELETES_PENDING} ;
   $self->SUPER::handle_footer ;
}


sub submit {
   my VCP::Dest::p4 $self = shift ;

   my %pending_labels ;
   my %comments ;
   my $max_time ;

   if ( @{$self->{P4_PENDING}} ) {
      for my $r ( @{$self->{P4_PENDING}} ) {
	 $comments{$r->comment} = $r->name if defined $r->comment ;
	 $max_time = $r->time if ! defined $max_time || $r->time > $max_time ;
	 for my $l ( $r->labels ) {
	    push @{$pending_labels{$l}}, $r->name ;
	 }
      }

      my @f = reverse( (localtime $max_time)[0..5] ) ;
      $f[0] += 1900 ;
      ++$f[1] ; ## Day of month needs to be 1..12
      $max_time = sprintf "%04d/%02d/%02d %02d:%02d:%02d", @f ;
   }

   my $description = join( "\n", keys %comments ) ;
   if ( length $description ) {
      $description =~ s/^/\t/gm ;
      $description .= "\n" if substr $description, -1 eq "\n" ;
   }

   my $change ;
   $self->p4( [ 'change', '-o' ], \$change ) ;

   if ( defined $max_time ) {
      $change =~ s/^Date:.*\r?\n\r/Date:\t$max_time\n/m
	 or $change =~ s/(^Client:)/Date:\t$max_time\n\n$1/m
	 or die "vcp: Couldn't modify change date\n$change" ;
   }

   $change =~ s/^Description:.*\r?\n\r?.*/Description:\n$description/m
      or die "vcp: Couldn't modify change description\n$change" ;
   $self->p4([ 'submit', '-i'], '<', \$change ) ;

   ## Create or add a label spec for each of the labels.  The 'sort' is to
   ## make debugging output more legible.
   ## TODO: Modify RevML to allow label metadata (owner, desc, options)
   ## to be passed through.  Same for user, client, jobs metadata etc.
   ## The assumption is made that most labels will apply to a single change
   ## number, so we do the labelling once per submit.  I don't think that
   ## this will break if it doesn't, but TODO: add more labelling tests.
   for my $l ( sort keys %pending_labels ) {
      my $label_desc ;
      $self->p4( [qw( label -o ), $l], '>', \$label_desc ) ;
      $self->p4( [qw( label -i ) ],    '<', \$label_desc ) ;
      $self->p4( [qw( labelsync -a -l ), $l, @{$pending_labels{$l}}] ) ;
   }
   @{$self->{P4_PENDING}} = () ;
   $self->{P4_DELETES_PENDING} = undef ;
}

sub tag {
   my VCP::Dest::p4 $self = shift ;

   my $tag = shift  ;
   $tag =~ s/\W+/_/g ;
   $self->p4( ['tag', $tag, @_] ) ;
}


## Prevent VCP::Plugin from rmtree-ing the workspace we're borrowing
sub DESTROY {
   my VCP::Dest::p4 $self = shift ;

   $self->work_root( undef ) ;
   $self->SUPER::DESTROY ;
}


=back

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
