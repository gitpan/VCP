package VCP::Source::revml ;

=head1 NAME

VCP::Source::revml - Outputs versioned files to a revml file

=head1 SYNOPSIS

   vcp revml[:<source>]
   vcp revml[:<source>] --dtd <dtd>

Where <source> is a filename for input; or missing or '-' for STDIN.

To compile a DTD in to a perl module:

   revml: --dtd <dtd> --save-doctype

=head1 DESCRIPTION

This reads a revml file and reconstitutes every revision of every file
fond therein on the disk and then submits them to the destination.

This can require a huge amount of disk space, but it works.  Disk usage
can be optimised later by only reconstituting the files two revisions
at a time (the previous revision is needed to generate the current one)
as the revs are submitted to the destination after they are sorted
(by the dest).

When that happens, we need to bear in mind that
the revml file will be in the default sort order defined by L<VCP::Dest>
and this may be changed by other destinations, particularly the change
set oriented ones like p4.  As an example, imagine the following process:

   cvs -> vcp -> foo.revml -> vcp -> p4

There is some chance that L<VCP::Dest::p4> will want to reorder the
revisions in foo.revml in order to attemp change set aggregation.  This means
that it may ask for the revs in a different order than they are found in
the file.  Since the default sort order *should* put the foo.revml file
in (roughly) change set order.  This is a bad example, I guess, but hey,
just watch out when optimizing for disk space.

=head1 EXTERNAL METHODS

=over

=cut

use strict ;

use Carp ;
use Fcntl ;
use Getopt::Long ;
use Digest::MD5 ;
use RevML::Doctype ;
use Symbol ;
use UNIVERSAL qw( isa ) ;
use XML::Parser ;
use Time::Local qw( timegm ) ;
use VCP::Debug ':debug' ;
use VCP::Rev ;

use vars qw( $VERSION $debug ) ;

$VERSION = 0.1 ;

$debug = 0 ;

use base 'VCP::Source' ;

use fields (
   'COPY_MODE', ## TRUE to do a copy, FALSE if not (like when writing .pm DTD)
   'DOCTYPE',
   'HEADER',    ## The $header is held here until the first <rev> is read
   'IN_FH',     ## The handle of the input revml file
   'IN_NAME',   ## The name of the input revml file, or '-' for stdout
   'WORK_NAME', ## The name of the working file (diff or content)
   'WORK_FH',   ## The filehandle of working file
   'REV',       ## The VCP::Rev containing all of this rev's meta info
   'STACK',     ## A stack of currently open elements
) ;


=item new

Creates a new instance.  The only parameter is '-dtd', which overrides
the default DTD found by searching for modules matching RevML::DTD:v*.pm.

Attempts to open the input file if one is specified.

If the option '--save-doctype' is passed, then no copying of resources
is done (queue_all returns nothing to copy) and the doctype is saved
as a .pm file.  See L<RevML::Doctype> for details.

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Source::revml $self = $class->SUPER::new( @_ ) ;

   $self->{COPY_MODE} = 1 ;

   my ( $spec, $args ) = @_ ;

   my $parsed_spec = $self->parse_repo_spec( $spec ) ;

   my $save_doctype ;
   {
      local *ARGV = $args ;
      GetOptions(
	 'dtd|version' => sub {
	    $self->{DOCTYPE} = RevML::Doctype->new( shift @$args ) ;
	 },
	 'save-doctype' => \$save_doctype,
      ) or $self->usage_and_exit ;
   }

   $self->{DOCTYPE} = RevML::Doctype->new
      unless $self->{DOCTYPE} ;

   if ( $save_doctype ) {
      $self->{COPY_MODE} = 0 ;
      $self->{DOCTYPE}->save_as_pm ;
   }
   my @errors ;

   my $files = $parsed_spec->{FILES} ;

   $self->{IN_NAME} = defined $files && length $files
      ? $files
      : '-' ;

   if ( $self->{IN_NAME} eq '-' ) {
      $self->{IN_FH}   = \*STDIN ;
      ## TODO: Check IN_FH for writability when it's set to STDIN
   }
   else {
      require Symbol ;
      $self->{IN_FH} = Symbol::gensym ;
      open( $self->{IN_FH}, "<$self->{IN_NAME}" )
         or die "$!: $self->{IN_NAME}\n" ;
   }

   $self->{WORK_FH} = Symbol::gensym ;

   die join( '', @errors ) if @errors ;

   return $self ;
}


sub dest_expected {
   my VCP::Source::revml $self = shift ;

   return $self->{COPY_MODE} ;
}


sub handle_header {
   my VCP::Source::revml $self = shift ;

   ## Save this off until we get our first rev from the input
   $self->{HEADER} = shift ;
   return ;
}


sub get_rev {
   my VCP::Source::revml $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;
}


sub copy_revs {
   my VCP::Source::revml $self = shift ;

   $self->revs( VCP::Revs->new ) ;
   $self->parse_revml_file ;

   $self->dest->sort_revs( $self->revs ) ;

   my VCP::Rev $r ;
   while ( $r = $self->revs->shift ) {
      $self->get_rev( $r ) ;
      $self->dest->handle_rev( $r ) ;
   }
}


sub parse_revml_file {
   my VCP::Source::revml $self = shift ;

   my @stack ;
   $self->{STACK} = \@stack ;

   my $p = XML::Parser->new(
      Handlers => {
         Start => sub {
	    my $expat = shift ;
	    my $tag = shift ;

#print STDERR "<$tag>\n" ;
	    push @stack, {
	       NAME => $tag,
	       ATTRS => [@_],
	       CONTENT => ! $self->can( "$tag\_characters" ) ? [] : undef,
	    } ;
	    my $sub = "start_$tag" ;
	    $self->$sub( @_ ) if $self->can( $sub ) ;
	 },

	 End => sub {
	    my $expat = shift ;
	    my $tag = shift ;
#print STDERR "</$tag>\n" ;
	    die "Unexpected </$tag>, expected </$stack[-1]>\n"
	       unless $tag eq $stack[-1]->{NAME} ;
	    my $sub = "end_$tag" ;
	    $self->$sub( @_ ) if $self->can( $sub ) ;
	    my $elt = pop @stack ;

	    if ( @stack
	       && $stack[-1]->{NAME} =~ /^rev(ml)?$/
	       && defined $elt->{CONTENT}
	       ) {
#print STDERR "</$tag>\n" ;
	       ## Save all the meta fields for start_content() or start_diff()
	       if ( $tag eq 'label' ) {
	          push @{$stack[-1]->{labels}}, $elt ;
	       }
	       else {
		  $stack[-1]->{$tag} = $elt ;
	       }
	    }
	 },

	 Char => sub {
	    my $expat = shift ;
	    my $pelt = $stack[-1] ; ## parent element
	    my $tag = $pelt->{NAME} ;
	    my $content = $pelt->{CONTENT} ;
	    if ( defined $content ) {
	       if ( @$content && $content->[-1]->{TYPE} eq 'PCDATA' ) {
	          $content->[-1]->{PCDATA} .= $_[0] ;
	       }
	       else {
	          push @$content, { TYPE => 'PCDATA', PCDATA => $_[0] } ;
	       }
	    }
	    my $sub = "$tag\_characters" ;
	    $self->$sub( @_ ) if $self->can( $sub ) ;
	 },
      },
   ) ;
   $p->parse( $self->{IN_FH} ) ;
}


sub start_rev {
   my VCP::Source::revml $self = shift ;

   ## We now have all of the header info parsed, save it off

   ## TODO: Demystify this hairy wart.  Better yet, simplify all the code
   ## in this module.  It needs to decode the fields as they come in and
   ## stick them in the header and the rev_meta 
   for ( map $self->{STACK}->[-2]->{$_}, grep /^[a-z_0-9]+$/, keys %{$self->{STACK}->[-2]} ) {
      $self->{HEADER}->{$_->{NAME}} = $_->{CONTENT}->[0]->{PCDATA} ;
   }

   ## Make sure no older rev is lying around to confuse us.
   $self->{REV} = undef ;
}

## RevML is contstrained so that the diff and content tags are after all of
## the meta info for a revision.  And we really don't want to hold
## the entire content of a file in memory, in case it's large.  So we
## intercept start_content and start_diff and initialize the REV
## member as well as opening a place to catch all of the data that gets
## extracted from the file.
sub init_rev_meta {
   my VCP::Source::revml $self = shift ;

   my $rev_elt = $self->{STACK}->[-2] ;
   my VCP::Rev $r = VCP::Rev->new() ;
   ## All revml tag naes are lc, all internal data member names are uc
#require Data::Dumper ; print Data::Dumper::Dumper( $self->{STACK} ) ;

   for ( grep /^[a-z_0-9]+$/, keys %$rev_elt ) {
      if ( $_ eq 'labels' ) {
         $r->labels(
	    map $_->{CONTENT}->[0]->{PCDATA}, @{$rev_elt->{labels}}
	 ) ;
      }
      else {
         ## We know that all kids *in use today* of <rev> are pure PCDATA
	 ## Later, we'll need sub-attributes.
	 ## TODO: Flatten the element tree by preficing attribute names
	 ## with, I dunno, say '_' or by adding '_attr' to them.
	 my $out_key = $_ ;
         $r->$out_key( $rev_elt->{$_}->{CONTENT}->[0]->{PCDATA} ) ;
      }
   }
#require Data::Dumper ; print Data::Dumper::Dumper( $r ) ;

   $r->work_path( $self->work_path( $r->name, $r->rev_id ) ) ;

   $self->mkpdir( $r->work_path ) ;

   $self->{REV} = $r ;
   return ;
}


sub start_delete {
   my VCP::Source::revml $self = shift ;

   $self->init_rev_meta ;
   $self->{REV}->action( 'delete' ) ;
   ## Clear the work_path so that VCP::Rev doesn't try to delete it.
   $self->{REV}->work_path( undef ) ;
}


sub start_move {
   my VCP::Source::revml $self = shift ;

   $self->init_rev_meta ;
   $self->{REV}->action( 'move' ) ;
   ## Clear the work_path so that VCP::Rev doesn't try to delete it.
   $self->{REV}->work_path( undef ) ;
   die "<move> unsupported" ;
}


sub start_content {
   my VCP::Source::revml $self = shift ;

   $self->init_rev_meta ;
#require Data::Dumper ; print Data::Dumper::Dumper( $self->{REV} ) ;
   $self->{REV}->action( 'edit' ) ;
   $self->{WORK_NAME} = $self->{REV}->work_path ;
   sysopen $self->{WORK_FH}, $self->{WORK_NAME}, O_WRONLY | O_CREAT | O_TRUNC
      or die "$!: $self->{WORK_NAME}" ;
}


sub content_characters {
   my VCP::Source::revml $self = shift ;
   syswrite $self->{WORK_FH}, $_[0] or die "$! writing $self->{WORK_NAME}" ;
   return ;
}

sub end_content {
   my VCP::Source::revml $self = shift ;
   
   close $self->{WORK_FH} or die "$! closing $self->{WORK_NAME}" ;

   if ( $self->none_seen ) {
#require Data::Dumper ; print Data::Dumper::Dumper( $self->{HEADER} ) ;
      $self->dest->handle_header( $self->{HEADER} ) ;
   }

   $self->seen( $self->{REV} ) ;
}

sub start_delta {
   my VCP::Source::revml $self = shift ;

   $self->init_rev_meta ;
   my $r = $self->{REV} ;
   $r->action( 'edit' ) ;
   $self->{WORK_NAME} = $self->work_path( $r->name, 'delta' ) ;
   sysopen $self->{WORK_FH}, $self->{WORK_NAME}, O_WRONLY | O_CREAT | O_TRUNC
      or die "$!: $self->{WORK_NAME}" ;
}


## TODO: Could keep deltas in memory if they're small.
*delta_characters = \&content_characters ;
## grumble...name used once warning...grumble
*delta_characters = \&content_characters ;

sub end_delta {
   my VCP::Source::revml $self = shift ;

   close $self->{WORK_FH} or die "$! closing $self->{WORK_NAME}" ;

   my VCP::Rev $r = $self->{REV} ;

   ## Delay sending handle_header to dest until patch succeeds.
   my $is_first = $self->none_seen ;

   my VCP::Rev $saw = $self->seen( $r ) ;

   die "No original content to patch for ", $r->name, ",",
      " revision ", $r->rev_id
      unless defined $saw ;

   if ( -s $self->{WORK_NAME} ) {
      my $patchout ;

      $self->run(
	 [ 'patch',
	    '-o', $r->work_path,
	    '-u',
	    $saw->work_path,
	    $self->{WORK_NAME}
	 ],
	 \undef,     # Close child's STDIN.  *sigh*
	 \$patchout,
      )
	 or die "$! patching ", $saw->work_path, " up to rev ",
	    $r->rev_id, ",\n$patchout" ;
      $patchout =~ s/^missing header for.*$//m ;
      $patchout =~ s/^patching file.*$//m ;

      debug "vcp: patch output:\n$patchout" if debugging $self ;

      unlink $self->{WORK_NAME} or warn "$! unlinking $self->{WORK_NAME}\n" ;
   }
   else {
      ## TODO: Don't assume working link()
      debug "vcp: linking ", $saw->work_path, ", ", $r->work_path
         if debugging $self ;

      link $saw->work_path, $r->work_path
         or die "vcp: $! linking ", $saw->work_path, ", ", $r->work_path
   }

   if ( $is_first ) {
#require Data::Dumper ; print Data::Dumper::Dumper( $self->{HEADER} ) ;
      $self->dest->handle_header( $self->{HEADER} ) ;
   }

}


## Convert ISO8601 UTC time to local time since the epoch
sub end_time {
   my VCP::Source::revml $self = shift ;

   my $timestr = $self->{STACK}->[-1]->{CONTENT}->[0]->{PCDATA} ;
   ## TODO: Get parser context here & give file, line, and column. filename
   ## and rev, while we're scheduling more work for the future.
   confess "Malformed time value $timestr\n"
      unless $timestr =~ /^\d\d\d\d(\D\d\d){5}/ ;
   confess "Non-UTC time value $timestr\n" unless substr $timestr, -1 eq 'Z' ;
   my @f = split( /\D/, $timestr ) ;
   --$f[1] ; # Month of year needs to be 0..11
   $self->{STACK}->[-1]->{CONTENT}->[0]->{PCDATA} = timegm( reverse @f ) ;
}

# double assign => avoid used once warning
*end_mod_time = *end_mod_time = \&end_time ;


## TODO: Verify that we should be using a Base64 encoded MD5 digest,
## according to <delta>'s attributes.  Oh, and same goes for <content>'s
## encoding.

## TODO: workaround backfilling if the destination is revml, since
## it can't put the original content in place.  We'll need to flag
## some kind of special pass-through mode for that.
##

sub end_digest {
   my VCP::Source::revml $self = shift ;

   $self->init_rev_meta unless defined $self->{REV} ;
   my $r = $self->{REV} ;

   my $original_digest = $self->{STACK}->[-1]->{CONTENT}->[0]->{PCDATA} ;
   my $d = Digest::MD5->new() ;

   if ( $r->is_base_rev ) {
      $self->dest->handle_header( $self->{HEADER} ) if $self->none_seen ;

      ## Don't bother checking the digest if the destination returns
      ## FALSE, meaning that a backfill is not possible with that destination.
      ## VCP::Dest::revml does this.
      return unless $self->dest->backfill( $r ) ;
      my VCP::Rev $saw = $self->seen( $r ) ;
      warn "I've seen ", $r->name, " before" if $saw ;
   }
   my $work_path = $r->work_path ;

   sysopen F, $work_path, O_RDONLY
      or die "$! opening '$work_path' for digestion\n" ;
   $d->addfile( \*F ) ;
   close F ;
   my $reconstituted_digest = $d->b64digest ;

   ## TODO: provide an option to turn this in to a warning
   ## TODO: make this abort writing anything to the dest, but continue
   ## processing, so as to deliver as many error messages as possible.
   die "Digest check failed for ", $r->name, ",",
      " revision ", $r->rev_id
      unless $original_digest eq $reconstituted_digest ;
}


## Having this and no sub rev_characters causes the parser to accumulate
## content.
sub end_rev {
   my VCP::Source::revml $self = shift ;

   $self->revs->add( $self->{REV} )  unless $self->{REV}->is_base_rev ;

   ## Release this rev.
   $self->{REV} = undef ;
}




=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This will be licensed under a suitable license at a future date.  Until
then, you may only use this for evaluation purposes.  Besides which, it's
in an early alpha state, so you shouldn't depend on it anyway.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
