package VCP::Source::revml ;

=head1 NAME

VCP::Source::revml - Reads a RevML file

=head1 SYNOPSIS

## revml input class:

   vcp foo.revml                     [dest_spec]
   vcp foo.revml --uncompress        [dest_spec]
   vcp foo.revml --dtd <revml.dtd>   [dest_spec]
   vcp foo.revml --version <version> [dest_spec]
   vcp revml:foo.revml:/foo/bar/...  [dest_spec]

Where <source> is a filename for input; or missing or '-' for STDIN.

=head1 DESCRIPTION

This source driver allows L<vcp|vcp> to read a RevML file.

For now, all revisions are fully reconstituted in the working
directory in order to make sure that all of the patches apply cleanly.
This can require a huge amount of disk space, but it works (optimizing
this is on the TODO).

=head1 OPTIONS

=over

=item --dtd

   --dtd=0.33
   --version=0.33

Use the indicated DTD version (must be compiled in to VCP) to parse
the RevML file.

=item --uncompress

Force uncompression of gzipped input.
If the input file ends in '.gz', the uncompress flag is implied.

=back

=cut

=for DEVELOPER_USE_ONLY
To use an alternate DTD:
   vcp revml[:<source>] --dtd <dtd>

=cut

use VCP::Logger qw( pr BUG );

$VERSION = 0.1 ;

@ISA = qw( VCP::Source VCP::Utils::revml );

use strict ;

use Carp ;
use Digest::MD5 ;
use Fcntl ;
use File::Path;
use File::Spec;
use MIME::Base64 ;
use RevML::Doctype ;
use Symbol ;
use UNIVERSAL qw( isa ) ;
use XML::Parser ;
use Time::Local qw( timegm ) ;
use VCP::Debug ':debug' ;
use VCP::Patch ;
use VCP::RefCountedFile;
use VCP::Rev ;
use VCP::Source;
use VCP::Utils qw( empty shell_quote start_dir_rel2abs );
use VCP::Utils::revml;
#use base qw( VCP::Source VCP::Utils::revml ) ;

#use fields (
#   'DTD_OPTION',        ## The --dtd or --version flag from the command line
#   'DOCTYPE',           ## revml doc type
#   'HEADER',            ## The $header is held here until the first <rev> is read
#   'IN_FH',             ## The handle of the input revml file
#   'WORK_NAME',         ## The name of the working file (diff or content)
#   'WORK_FH',           ## The filehandle of working file
#   'REV',               ## The VCP::Rev containing all of this rev's meta info
#   'STACK',             ## A stack of currently open elements
#   'UNDECODED_CONTENT', ## Base64 content waiting to be decoded.
#   'FILESPEC_RE',       ## A perl5 re compiled from $self->repo_filespec
#   'UNCOMPRESS',        ## un-compress gzipped input
#   'HEADER_ENDED',      ## Set when the first <rev> is encountered
#   'FILES',             ## A hash of files that were created as we read the
#                        ## RevML.  This is keyed on revision ID and contains
#                        ## VCP::RefCountedFile objects.  get_source_file()
#                        ## deletes these and returns the RefCountedFiles
#                        ## objects, so the disk space is reclaimed whenever
#                        ## the end point is finished with the file.
#) ;


#=item new
#
#Creates a new instance.  The only parameter is '-dtd', which overrides
#the default DTD found by searching for modules matching RevML::DTD:v*.pm.
#
#=cut

sub new {
   my $self = shift->SUPER::new;

   my ( $spec, $options ) = @_ ;

   $self->parse_revml_repo_spec( $spec )
      unless empty $spec;

   $self->parse_options( $options );

   return $self;
}


sub options_spec {
   my $self = shift;
   return (
      $self->SUPER::options_spec,
      'dtd|version=s' => \$self->{DTD_OPTION},
      'uncompress'    => \$self->{UNCOMPRESS},
   );
}


sub init {
   my $self = shift ;

   $self->SUPER::init;

   $self->{DOCTYPE} = RevML::Doctype->new(
       $self->{DTD_OPTION},
       main::bundled_files()
   );

   my $file = $self->decide_actual_input_filename;

   # always un-compress if filename ends in ".gz"
   my $gzip;
   if ( $^O =~ /Win32/ ) {
      $self->{UNCOMPRESS} = 1 if $file =~ /\.gz$/i ;
      $gzip = "gzip.exe";
   }
   else {
      $self->{UNCOMPRESS} = 1 if $file =~ /\.gz$/ ;
      $gzip = "gzip";
   }

   my $fs = $self->repo_filespec;
   $self->{FILESPEC_RE} = ( ! empty $fs )
      ? do {
         $fs =~ s{^/+}{};
         $self->compile_path_re( $fs )
      }
      : qr{^};

   if ( $file eq '-' ) {
      if( $self->{UNCOMPRESS} ) {
         open( $self->{IN_FH}, "gzip --decompress --stdout - |" )
            or die "$!: gzip --decompress --stdout - |";
      }
      else {
         $self->{IN_FH}   = \*STDIN ;
      }
      ## TODO: Check IN_FH for writability when it's set to STDIN
      ## don't you mean readability?
   }
   else {
      require Symbol ;
      $self->{IN_FH} = Symbol::gensym ;

      if( $self->{UNCOMPRESS} ) {
         my $in_name = shell_quote $file;

         open( $self->{IN_FH}, "gzip --decompress --stdout $in_name |" )
            or die "$!: gzip --decompress --stdout $in_name |";
      }
      else {
         open( $self->{IN_FH}, "<$file" ) or die "$!: $file\n";
      }
   }

   $self->{WORK_FH} = Symbol::gensym ;

   return $self ;
}


# ??? call this twice or only once if already set????
sub decide_actual_input_filename {
   my $self = shift;

   ## This supports a brain-dead compatability mode where you can
   ## "just" say revml:filename.revml or even just filename.revml
   ## on the command line.  The parse routines will stick that
   ## in repo_filespec and not set the server.  If, however, the
   ## server is set, then the filespec is a pattern we need to use
   ## to select files.
   my $file = $self->repo_server;
   if ( empty $file ) {
      $self->repo_server( $self->repo_filespec );
      $self->repo_filespec( undef );
      $file = $self->repo_server;
   }

   $file = "-"
      if empty $file;

   $file = $self->repo_server(
      start_dir_rel2abs $file
   ) unless $file eq "-";

   $file = "-" if empty $file;

   return $file;
}



=item ui_set_revml_repo_spec

set the repo_spec, but die if no good.
this should be called from a ui handler that
will handle exceptions.



=cut

sub ui_set_revml_repo_spec {
   my $self = shift ;

   $self->parse_revml_repo_spec( @_ );
   my $file = $self->decide_actual_input_filename;
   die "Error: '-' signifies standard input, not a file name.\n"
      if $file eq '-';
   die "Error: '$file' is a directory.\n"
      if -d $file;
   die "Warning: '$file' not found!\n"
      unless -e $file;
   die "Warning: '$file' not is not a plain file!\n"
      unless -f $file;
   die "Warning: '$file' not readable!\n"
      unless -r $file;
}



sub handle_header {
   my $self = shift ;

   ## Save this off until we get our first rev from the input
   ( $self->{HEADER} ) = @_;

   rmtree [ $self->_db_store_location( 'source_files') ];

   $self->parse_revml_file ;
      ## Unlike normal repositories, we have to scan all this here
      ## so that all files get extracted from the input so that
      ## VCP::Source::metadb can access them.

   $self->dest->handle_header( $self->{HEADER} )
      if defined $self->{HEADER};
}


sub get_source_file {
   my $self = shift ;
   my $r ;
   ( $r ) = @_ ;

   die "can't check out ", $r->as_string, "\n"
      unless defined $r->is_base_rev || $r->action eq "add" || $r->action eq "edit";

   return #VCP::RefCountedFile->new(
      $self->_db_store_location(
         'source_files',
         $r->source_name,
         $r->source_branch_id || "-",
         $r->source_rev_id
      )
#   )
   ;

      ## Pass ownership to the caller so it will be cleaned up when the
      ## caller is finished with it.
}


sub parse_revml_file {
   my $self = shift ;

   my @stack ;
   $self->{STACK} = \@stack ;
   $self->{HEADER_ENDED} = 0;

   my $char_handler = sub {
      my $expat = shift ;
      my $pelt = $stack[-1] ; ## parent element
      my $tag = $pelt->{NAME} ;
      $pelt->{TEXT} .= $_[0] if exists $pelt->{TEXT} && defined $pelt->{TEXT};
      my $sub = "${tag}_characters" ;
      $self->$sub( @_ ) if $self->can( $sub ) ;
   } ;

   my $p = XML::Parser->new(
      Handlers => {
         Start => sub {
	    my $expat = shift ;
	    my $tag = shift ;

	    if ( $tag eq "char" ) {
	       while ( @_ ) {
	          my ( $attr, $value ) = ( shift, shift ) ;
#print STDERR $value, "=" ;
		  if ( $attr eq "code" ) {
		     if ( $value =~ s{^0x}{} ) {
			$value = chr( hex( $value ) ) ;
		     }
		     else {
			$value = chr( $value ) ;
		     }
#print STDERR ord $value, "\n" ;
		     $char_handler->( $expat, $value ) ;
		  }
	       }
	       return ;
	    }

            ## TODO: suss out "container" elements from the doctype.
	    push @stack, {
	       NAME => $tag,
	       @_,
	       ( $self->can( "${tag}_characters" )
                  || 0 <= index "revml,rev,branch,branches,", $tag . ","
               ) 
                  ? ()
                  : ( TEXT => "" ),
	    } ;

	    my $sub = "start_$tag" ;
	    $self->$sub( @_ ) if $self->can( $sub ) ;
	 },

	 End => sub {
	    my $expat = shift ;
	    my $tag = shift ;
	    return if $tag eq "char" ;

#print STDERR "</$tag>\n" ;
	    die "Unexpected </$tag>, expected </$stack[-1]>\n"
	       unless $tag eq $stack[-1]->{NAME} ;
	    my $sub = "end_$tag" ;
	    $self->$sub( @_ ) if $self->can( $sub ) ;
	    my $elt = pop @stack ;

	    if ( @stack ) {
               if (
                  exists $elt->{TEXT}
                  && defined $elt->{TEXT}
               ) {
                  ## Save all the meta fields for start_content() or start_diff()
                  if ( $tag eq 'label' ) {
                     push @{$stack[-1]->{labels}}, $elt->{TEXT} ;
                  }
                  elsif ( $stack[-1]->{NAME} eq "revml" ) {
                     die "Header field $tag after first rev\n"
                        if $self->{HEADER_ENDED};
                     ## ASSume none of these occur after first rev.
                     $self->{HEADER}->{$tag} = $elt->{TEXT} ;
                     if ( $tag eq "rev_root" ) {
                        $self->rev_root( $elt->{TEXT} );
                     }
                  }
                  else {
                     $stack[-1]->{$tag} = $elt->{TEXT} ;
                  }
               }
               else {
                  ## It's a node with child nodes.
                  delete $elt->{NAME};

                  if ( $stack[-1]->{NAME} eq "revml" && $tag ne "rev" ) {
                     die "Header field $tag after first rev\n"
                        if $self->{HEADER_ENDED};
                     ## ASSume none of these occur after first rev.
                     $self->{HEADER}->{$tag} = $elt;
                  }
                  else {
                     $stack[-1]->{$tag} = $elt;
                  }
               }
	    }
	 },

	 Char => $char_handler,
      },
   ) ;
   $p->parse( $self->{IN_FH} ) ;
}


sub start_rev {
   my $self = shift ;

   ## Make sure no older rev is lying around to confuse us.
   $self->{REV} = undef ;
   $self->{HEADER_ENDED} = 1;
}

## RevML is contstrained so that the diff and content tags are after all of
## the meta info for a revision.  And we really don't want to hold
## the entire content of a file in memory, in case it's large.  So we
## intercept start_content and start_diff and initialize the REV
## member as well as opening a place to catch all of the data that gets
## extracted from the file.
sub init_rev_meta {
   my $self = shift ;
   my ( $placeholder_type ) = @_;

   my $rev_elt = $self->{STACK}->[-2] ;
   my $r = VCP::Rev->new() ;
   ## All revml tag naes are lc, all internal data member names are uc
#require Data::Dumper ; print Data::Dumper::Dumper( $self->{STACK} ) ;

   for my $key ( grep /^[a-z_0-9]+$/, keys %$rev_elt ) {
      if ( $key eq 'labels' ) {
         $r->set_labels( $rev_elt->{labels} );
      }
      else {
         ## We know that all kids *in use today* of <rev> are pure PCDATA
	 ## Later, we'll need sub-attributes.
	 ## TODO: Flatten the element tree by preficing attribute names
	 ## with '@'?.
         $r->$key( $rev_elt->{$key} ) ;
      }
   }
#require Data::Dumper ; print Data::Dumper::Dumper( $r ) ;

   if ( defined $placeholder_type ) {
      $r->action( $placeholder_type );
   }
   else {
      my $work_path =
         $self->_db_store_location(
            'source_files',
            $r->name,
            $r->branch_id || "-",
            $r->rev_id
         );

      $self->{FILES}->{$r->id} = $work_path;

      $self->mkpdir( $work_path ) ;
   }

   $self->{REV} = $r ;
   return ;
}


sub start_delete {
   my $self = shift ;

   $self->init_rev_meta ;
   $self->{REV}->set_action( "delete" ) ;
   1;  ## prevent void context warning
}


sub start_move {
   my $self = shift ;

   $self->init_rev_meta ;
   $self->{REV}->set_action( "move" ) ;
   die "<move> unsupported" ;
}


sub start_content {
   my $self = shift ;

   $self->init_rev_meta ;
#require Data::Dumper ; print Data::Dumper::Dumper( $self->{REV} ) ;
   $self->{REV}->action( "edit" ) ;
   $self->{WORK_NAME} = $self->{FILES}->{$self->{REV}->id};
   $self->{UNDECODED_CONTENT} = "" ;

   debug "writing $self->{WORK_NAME}" if debugging;
   sysopen $self->{WORK_FH}, $self->{WORK_NAME}, O_WRONLY | O_CREAT | O_TRUNC
      or die "$!: $self->{WORK_NAME}" ;
   ## The binmode here is to make sure we don't convert \n to \r\n and
   ## to allow ^Z out the door (^Z is EOF on windows, and they take those
   ## things rather more seriously there than on Unix).
   binmode $self->{WORK_FH};
}


sub content_characters {
   my $self = shift ;
   if ( $self->{STACK}->[-1]->{encoding} eq "base64" ) {
      $self->{UNDECODED_CONTENT} .= shift ;
      if ( $self->{UNDECODED_CONTENT} =~ s{(.*\n)}{} ) {
	 syswrite( $self->{WORK_FH}, decode_base64( $1 ) )
	    or die "$! writing $self->{WORK_NAME}" ;
      }
   }
   elsif ( $self->{STACK}->[-1]->{encoding} eq "none" ) {
# print STDERR map( sprintf( " %02x=$_", ord ), $_[0] =~ m/(.)/gs ), "\n" ;
      syswrite $self->{WORK_FH}, $_[0]
         or die "$! writing $self->{WORK_NAME}" ;
   }
   else {
      die "unknown encoding '$self->{STACK}->[-1]->{encoding}'\n";
   }
   return ;
}

sub end_content {
   my $self = shift ;
   
   if ( length $self->{UNDECODED_CONTENT} ) {
      syswrite( $self->{WORK_FH}, decode_base64( $self->{UNDECODED_CONTENT} ) )
	 or die "$! writing $self->{WORK_NAME}" ;
   }
   close $self->{WORK_FH} or die "$! closing $self->{WORK_NAME}" ;
}

sub start_delta {
   my $self = shift ;

   $self->init_rev_meta ;
   my $r = $self->{REV} ;
   $r->action( 'edit' ) ;
   $self->{WORK_NAME} = $self->_db_store_location(
      'source_files',
      $r->name,
      $r->branch_id || "-",
      'delta'
   ) ;
   sysopen $self->{WORK_FH}, $self->{WORK_NAME}, O_WRONLY | O_CREAT | O_TRUNC
      or die "$!: $self->{WORK_NAME}" ;
   ## See comment in start_content :)
   binmode $self->{WORK_FH};
}


## TODO: Could keep deltas in memory if they're small.
*delta_characters = \&content_characters ;
## grumble...name used once warning...grumble
*delta_characters = \&content_characters ;

sub end_delta {
   my $self = shift ;

   close $self->{WORK_FH} or die "$! closing $self->{WORK_NAME}" ;

#print STDERR `hexdump -cx $self->{WORK_NAME}` ;

   my $r = $self->{REV} ;
   my $abs_name = $self->rev_root . "/" . $r->name;
   return if $abs_name !~ $self->{FILESPEC_RE};

   my $bv_r = $self->queued_rev( $r->previous_id ) ;
   $bv_r = $self->queued_rev( $bv_r->previous_id )
       while $bv_r && ! exists $self->{FILES}->{$bv_r->id};

   die "No original content to patch for ", $r->as_string
      unless defined $bv_r;

   my $source_fn = $self->{FILES}->{$bv_r->id};
   my $dest_fn   = $self->{FILES}->{$r->id};

   if ( -s $self->{WORK_NAME} ) {
      vcp_patch( $source_fn, $dest_fn, $self->{WORK_NAME} );
      unless ( $ENV{VCPNODELETE} ) {
         unlink $self->{WORK_NAME}
            or pr "$! unlinking $self->{WORK_NAME}\n" ;
      }
   }
   else {
      ## TODO: Don't assume working link()
      debug "linking '$source_fn', '$dest_fn'"
         if debugging ;

      link $source_fn, $dest_fn
         or die "$!: linking '$source_fn', '$dest_fn'";
   }
}


## Convert ISO8601 UTC time to local time since the epoch
sub end_time {
   my $self = shift ;

   my $timestr = $self->{STACK}->[-1]->{TEXT};
   ## TODO: Get parser context here & give file, line, and column. filename
   ## and rev, while we're scheduling more work for the future.
   confess "Malformed time value $timestr\n"
      unless $timestr =~ /^\d\d\d\d(\D\d\d){5}/ ;
   confess "Non-UTC time value $timestr\n" unless substr $timestr, -1 eq 'Z' ;
   my @f = split( /\D/, $timestr ) ;
   --$f[1] ; # Month of year needs to be 0..11
   $self->{STACK}->[-1]->{TEXT} = timegm( reverse @f ) ;
}

# double assign => avoid used once warning
*end_mod_time = *end_mod_time = \&end_time ;


## TODO: Verify that we should be using a Base64 encoded MD5 digest,
## according to <delta>'s attributes.  Oh, and same goes for <content>'s
## encoding.

## TODO: workaround backfilling if the destination is revml, since
## it can't put the original content in place.  We'll need to flag
## some kind of special pass-through mode for that.

sub end_digest {
   my $self = shift ;

   $self->init_rev_meta unless defined $self->{REV} ;

   my $r = $self->{REV} ;
   my $abs_name = $self->rev_root . "/" . $r->name;
   return if $abs_name !~ $self->{FILESPEC_RE};

   my $original_digest = $self->{STACK}->[-1]->{TEXT};

   my $work_path = $self->{FILES}->{$r->id};

   if ( $r->is_base_rev ) {
      ## Don't bother checking the digest if the destination returns
      ## FALSE, meaning that a backfill is not possible with that destination.
      ## VCP::Dest::revml does this.
      if ( $self->{HEADER} ) {
         $self->dest->handle_header( $self->{HEADER} );
         $self->{HEADER} = undef;
      }

      return unless $self->dest->backfill( $r, $work_path );
   }

   my $d = Digest::MD5->new() ;
   sysopen F, $work_path, O_RDONLY
      or die "$! opening '$work_path' for digestion\n" ;
   ## See comment for binmode in start_content :)
   binmode F;
   $d->addfile( \*F ) ;
   close F ;
   my $reconstituted_digest = $d->b64digest ;

   ## TODO: provide an option to turn this in to a warning
   ## TODO: make this abort writing anything to the dest, but continue
   ## processing, so as to deliver as many error messages as possible.
   unless ( $original_digest eq $reconstituted_digest ) {
      my $reject_file_name = $r->name ;
      $reject_file_name =~ s{[^A-Za-z0-9 -.]+}{-}g ;
      $reject_file_name =~ s{^-+}{}g ;
      my $reject_file_path = File::Spec->catfile(
         File::Spec->tmpdir,
	 $reject_file_name
      ) ;

      link $work_path, $reject_file_path 
         or die "digest check failed for ", $r->as_string, "\n",
	 "   failed to leave copy in '$reject_file_path': $!\n" ;

      die "digest check failed for ", $r->as_string, "\n",
	 "   copy left in '$reject_file_path'\n",
         "   got      digest: $reconstituted_digest\n",
         "   expected digest: $original_digest\n";
   }
}


sub end_placeholder {
   my $self = shift ;
   $self->init_rev_meta( "placeholder" );
}


## Having this and no sub rev_characters causes the parser to accumulate
## content.
sub end_rev {
   my $self = shift ;

   BUG "rev_root not set" unless defined $self->rev_root;
   my $abs_name = $self->rev_root . "/" . $self->{REV}->name;
   return if $abs_name !~ $self->{FILESPEC_RE};

   $self->queue_rev( $self->{REV} );
   $self->{REV} = undef ;
}


=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1 ;
