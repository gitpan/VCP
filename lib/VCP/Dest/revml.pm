package VCP::Dest::revml ;

=head1 NAME

VCP::Dest::revml - Outputs versioned files to a revml file

=head1 SYNOPSIS

## revml output class:

   revml:[<output-file>]
   revml:[<output-file>] --dtd <revml.dtd>
   revml:[<output-file>] --version <version>
   revml:[<output-file>] --sort-by=name,rev

=head1 DESCRIPTION

The --dtd and --version options cause the output to be checked against
a particular version of revml.  This does I<not> cause output to be in 
that version, but makes sure that output is compliant with that version.

=head1 EXTERNAL METHODS

=over

=cut

use strict ;

use Carp ;
use Digest::MD5 ;
use Fcntl ;
use Getopt::Long ;
use MIME::Base64 ;
use RevML::Doctype ;
use RevML::Writer ;
use Symbol ;
use UNIVERSAL qw( isa ) ;
use VCP::Rev ;
use Text::Diff ;

use vars qw( $VERSION $debug ) ;

$VERSION = 0.1 ;

$debug = 0 ;

use base 'VCP::Dest' ;

use fields (
   'OUT_NAME',  ## The name of the output file, or '-' for stdout
   'OUT_FH',    ## The handle of the output file
   'WRITER',    ## The XML::AutoWriter instance write with
) ;


=item new

Creates a new instance.  The only parameter is '-dtd', which overrides
the default DTD found by searching for modules matching RevML::DTD:v*.pm.

Attempts to create the output file if one is specified.

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Dest::revml $self = $class->SUPER::new( @_ ) ;

   my @errors ;

   my ( $spec, $options ) = @_ ;

   my $parsed_spec = $self->parse_repo_spec( $spec ) ;

   my $file_name = $parsed_spec->{FILES} ;
   $self->{OUT_NAME} = defined $file_name && length $file_name
      ? $file_name
      : '-' ;
   if ( $self->{OUT_NAME} eq '-' ) {
      $self->{OUT_FH}   = \*STDOUT ;
      ## TODO: Check OUT_FH for writability when it's set to STDOUT
   }
   else {
      require Symbol ;
      $self->{OUT_FH} = Symbol::gensym ;
      ## TODO: Provide a '-f' force option
      open( $self->{OUT_FH}, ">$self->{OUT_NAME}" )
         or die "$!: $self->{OUT_NAME}" ;
   }

   my $doctype ;
   my @sort_spec ;
   {
      local *ARGV = $options ;
      GetOptions(
	 'dtd|version' => sub {
	    $doctype = RevML::Doctype->new( shift @$options ) ;
	 },
	 "k|sort-by=s" => \@sort_spec,
       ) or $self->usage_and_exit ;
   }

   $self->set_sort_spec( @sort_spec ) if @sort_spec ;

   $doctype = RevML::Doctype->new
      unless $doctype ;

   die join( '', @errors ) if @errors ;

   $self->writer(
      RevML::Writer->new(
	 DOCTYPE => $doctype,
	 OUTPUT  => $self->{OUT_FH},
      )
   );

   return $self ;
}


sub _ISO8601(;$) {
   my @f = reverse( ( @_ ? gmtime( shift ) : gmtime )[0..5] ) ;
   $f[0] += 1900 ;
   $f[1] ++ ; ## Month of year needs to be 1..12
   return sprintf( "%04d-%02d-%02d %02d:%02d:%02dZ", @f ) ;
}

sub _emit_characters {
   my ( $w, $buf ) = @_ ;

   $w->setDataMode( 0 ) ;

   ## Note that we don't let XML munge \r to be \n!!
   while ( $$buf =~ m{\G(?:
      (   [\x00-\x08\x0b-\x1f\x7f-\xff])
      | ([^\x00-\x08\x0b-\x1f\x7f-\xff]*)
      )}gx
   ) {
      if ( defined $1 ) {
	 $w->char( "", code => sprintf( "0x%02x", ord $1 ) ) ;
      }
      else {
	 $w->characters( $2 ) ;
      }
   }

}


sub handle_rev {
   my VCP::Dest::revml $self = shift ;
   my VCP::Rev $r ;
   ( $r ) = @_ ;

   my $w = $self->writer ;

   if ( $self->none_seen ) {
      $w->setDataMode( 1 ) ;
      $w->xmlDecl ;
      my $h = $self->header ;
      ## VCP::Source::revml passes through the original date.  Other sources
      ## don't.
      $w->time(
         defined $h->{time}
	    ? _ISO8601 $h->{time}
	    : _ISO8601
      ) ;
      $w->rep_type( $h->{rep_type} ) ;
      $w->rep_desc( $h->{rep_desc} ) ;
      $w->rev_root( $h->{rev_root} ) ;
   }

   my VCP::Rev $saw = $self->seen( $r ) ;

   ## If there's no work path for the current file, keep the previous one.
   ## This is a cheat that allows us to diff against the last known version
   ## if a file is deleted and then re-added.  Without this line, we would
   ## have to include the new version of the file.
   $self->seen( $saw ) if $saw && ! defined $r->work_path ;

   my $fn = $r->name ;

   my $is_base_rev = $r->is_base_rev ;
   die(
      "Saw '", $saw->as_string,
      "', but found a later base rev '" . $r->as_string, "'"
   ) if $saw && $is_base_rev ;

   $w->start_rev ;
   $w->name(       $fn           ) ;
   $w->type(       $r->type      ) ;
   $w->p4_info(    $r->p4_info   ) if defined $r->p4_info ;
   $w->cvs_info(   $r->cvs_info  ) if defined $r->cvs_info ;
   $w->rev_id(     $r->rev_id    ) ;
   $w->change_id(  $r->change_id ) if defined $r->change_id ;
   $w->time(       _ISO8601 $r->time      )
      if ! $is_base_rev || defined $r->time ;
   $w->mod_time(   _ISO8601 $r->mod_time  ) if defined $r->mod_time ;
   $w->user_id(    $r->user_id   )
      if ! $is_base_rev || defined $r->time ;

   ## Sorted for readability & testability
   $w->label( $_ ) for sort $r->labels ;

   if ( defined $r->comment && length $r->comment ) {
      $w->start_comment ;
      my $c = $r->comment ;
      _emit_characters( $w, \$c ) ;
      $w->end_comment ;
      $w->setDataMode( 1 ) ;
   }

   my $digestion ;
   my $cp = $r->work_path ;
   if ( $is_base_rev ) {
      sysopen( F, $cp, O_RDONLY ) or die "$!: $cp\n" ;
      $digestion = 1 ;
   }
   elsif ( $r->action eq 'delete' ) {
      $w->delete() ;
      $self->delete_seen( $r ) ;
   }
   else {
      sysopen( F, $cp, O_RDONLY ) or die "$!: $cp\n" ;

      my $buf ;
      my $read ;
      my $has_nul ;
      my $total_char_count = 0 ;
      my $bin_char_count   = 0 ;
      while ( ! $has_nul ) {
	 $read = sysread( F, $buf, 100_000 ) ;
	 die "$! reading $cp\n" unless defined $read ;
	 last unless $read ;
	 $has_nul = $buf =~ tr/\x00// ;
	 $bin_char_count   += $buf =~ tr/\x00-\x08\x0b-\x1f\x7f-\xff// ;
	 $total_char_count += length $buf ;
      } ;

      sysseek( F, 0, 0 ) or die "$! seeking on $cp\n" ;
      
      $buf = '' unless $read ;
      ## base64 generate 77 chars (including the newline) for every 57 chars
      ## of input. A '<char code="0x01" />' element is 20 chars.
      my $encoding = $bin_char_count * 20 > $total_char_count * 77/57
	 ? "base64"
	 : "none" ;

      if (  ! $saw                    ## First rev, can't delta
         || ! defined $saw->work_path ## No file, can't delta
	 || $has_nul                  ## patch would barf, can't delta
	 || $encoding ne "none"       ## base64, can't delta
      ) {
         ## Full content, no delta.
	 $w->start_content( encoding => $encoding ) ;
	 while () {
	    ## Odd chunk size is because base64 is most concise with
	    ## chunk sizes a multiple of 57 bytes long.
	    $read = sysread( F, $buf, 57_000 ) ;
	    die "$! reading $cp\n" unless defined $read ;
	    last unless $read ;
	    if ( $encoding eq "none" ) {
	       _emit_characters( $w, \$buf ) ;
	    }
	    else {
	       $w->characters( encode_base64( $buf ) ) ;
	    }
	 }
	 $w->end_content ;
	 $w->setDataMode( 1 ) ;
      }
      else {
         ## Delta from previous version
	 $w->base_name(   $saw->name )
	    if $saw->name ne $r->name ;
	 $w->base_rev_id( $saw->rev_id ) ;

	 $w->start_delta( type => 'diff-u', encoding => 'none' ) ;

	 my $old_cp = $saw->work_path ;

	 die "vcp: no old work path for '", $saw->name, "'\n"
	    unless defined $old_cp && length $old_cp ;

	 die "vcp: old work path '$old_cp' not found for '", $saw->name, "'\n"
	    unless -f $old_cp ;

         ## TODO: Include entire contents if diff is larger than the contents.

#	 ## Accumulate a bunch of output so that characters can make a
#	 ## knowledgable CDATA vs &lt;&amp; escaping decision.
#	 ## We use '-a' since we don't wan't NULs and other control chars to
#	 ## make diff think it's binary.
#	 $self->run(
#	    [qw( diff -a -u ), $old_cp, $cp],
#	       '|', sub {
#		  $/ = "\n" ;
#		  <STDIN> ; <STDIN> ;     ## Throw away first two lines
#		  my @accum ;
#		  while (<STDIN>) {
#		     push @accum, $_ ;
#		     if ( @accum > 1000 ) {
#			print @accum ;
#			@accum = () ;
#		     }
#		  }
#		  print @accum ;
#		  close STDOUT ;
#		  kill 9, $$ ;  ## Avoid calling DESTROY()s
#	       },
#	       '>', sub {
#		  _emit_characters( $w, \$_[0] ) ;
#	       },
#	 ) ;
	 ## Accumulate a bunch of output so that characters can make a
	 ## knowledgable CDATA vs &lt;&amp; escaping decision.
	 my @output ;
	 my $outlen = 0 ;
	 ## TODO: Write a "minimal" diff output handler that doesn't
	 ## emit any lines from $old_cp, since they are redundant.
	 diff $old_cp, $cp,
	    {
	       ## Not passing file names, so no filename header.
               STYLE  => "VCP::DiffFormat",
	       OUTPUT => sub {
		  push @output, $_[0] ;
		  $outlen += length $_[0] ;
		  return unless $outlen > 100_000 ;
		  _emit_characters( $w, \join "", splice @output  ) ;
	       },
	    } ;
	 _emit_characters( $w, \join "", splice @output  ) if $outlen ;
	 $w->end_delta ;
	 $w->setDataMode( 1 ) ;
      } ;
      $digestion = 1 ;
   }

   if ( $digestion ) {
      ## TODO: See if this should be seek or sysseek.
      sysseek F, 0, 0 or die "$!: $cp" ;
      my $d= Digest::MD5->new ;
      $d->addfile( \*F ) ;
      $w->digest( $d->b64digest, type => 'MD5', encoding => 'base64' ) ;
      close F ;
   }

   $w->end_rev ;

#   $self->seen( $r ) ;
}


sub handle_footer {
   my VCP::Dest::revml $self = shift ;
   my ( $footer ) = @_ ;

   $self->writer->endAllTags() unless $self->none_seen ;

   return ;
}


sub writer {
   my VCP::Dest::revml $self = shift ;
   $self->{WRITER} = shift if @_ ;
   return $self->{WRITER} ;
}


=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
