package VCP::Dest::p4 ;

=head1 NAME

VCP::Dest::p4 - p4 destination driver

=head1 SYNOPSIS

   vcp <source> p4[:<dest>]

where <dest> is an already created directory in the p4 repository.

This destination driver will check out the indicated destination in
a temporary directory and use it to add, edit, and delete files.

At this time, each file being changed is submitted and gets it's own
change number unless change numbers are assigned by the source.

Also for now, you must take care to cd to the working directory
that the current client's view point to.

=head1 DESCRIPTION

=head1 METHODS

=over

=cut

use strict ;
use vars qw( $debug ) ;

$debug = 0 ;

use Carp ;
use Cwd ;
use File::Basename ;
use File::Path ;
use Getopt::Long ;
use VCP::Debug ':debug' ;
use VCP::Dest ;
use VCP::Rev ;

use base 'VCP::Dest' ;
use fields (
   'P4_SPEC',       ## The root of the tree to update
   'P4_CHANGE_ID',  ## The current change_id in the r sequence, if any
   'P4_PENDING',    ## Revs pending the next submit
   'P4_WORK_DIR',   ## Where to do the work.
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

   $self->{P4_SPEC} = $files ;
   $self->{P4_PENDING} = [] ;

   die "No spec '$files' allowed for destination class p4:"
      if defined $files && length $files ;

   my $work_root ;
   local *ARGV = \@$options ;
   GetOptions(
      'w=s' => \$work_root
   ) or $self->usage_and_exit ;
   $work_root = cwd unless defined $work_root && length $work_root ;

   ## Make sure the p4 command is available
   $self->command( 'p4' ) ;
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

   return $self->SUPER::p4( @_ ) ;
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

   if ( defined $r->change_id
      && defined $self->{P4_CHANGE_ID}
      && $r->change_id ne $self->{P4_CHANGE_ID}
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
   }
   else {
   ## TODO: Don't assume same filesystem or working link().
      {
         my $add_it ;
	 if ( -e $work_path ) {
	    $self->p4( ['edit', $fn] ) ;
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
	 else {
#	    warn "vcp: no modification time available for $fn\n" ;
	 }
	 if ( $add_it ) {
	    $self->p4( ['add', $fn] ) ;
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

   ## TODO: Don't assume all revs either do or do not have a change id.
   $self->submit unless defined $r->change_id ;
   $self->{P4_CHANGE_ID} = $r->change_id ;
debug "vcp: done importing '$fn'" if debugging $self ;
debug "vcp: cleaning up $saw ", $saw->name, " in PENDING" if $saw && debugging $self ;
}


sub handle_footer {
   my VCP::Dest::p4 $self = shift ;

   $self->submit unless $self->none_seen ;
   $self->SUPER::handle_footer ;
}


sub submit {
   my VCP::Dest::p4 $self = shift ;

   my %pending_labels ;
   my %comments ;
   my $max_time ;
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

   my $change ;
   $self->p4( [ 'change', '-o' ], \$change ) ;
   my $description = join( "\n", keys %comments ) ;
   if ( length $description ) {
      $description =~ s/^/\t/gm ;
      $description .= "\n" if substr $description, -1 eq "\n" ;
   }

   $change =~ s/^Date:.*\r?\n\r/Date:\t$max_time\n/m
      or $change =~ s/(^Client:)/Date:\t$max_time\n\n$1/m
      or die "vcp: Couldn't modify change date\n$change" ;

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

This will be licensed under a suitable license at a future date.  Until
then, you may only use this for evaluation purposes.  Besides which, it's
in an early alpha state, so you shouldn't depend on it anyway.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
