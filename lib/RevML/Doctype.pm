package RevML::Doctype ;

=head1 NAME

RevML::Doctype - A subclass of XML::Doctype

=head1 SYNOPSIS

   use RevML::Doctype ;

   ## To use the highest RevML::Doctype module (e.g. RevML::Doctype::v0_22)
   $rmldt = RevML::Doctype->new ;

   ## To parse a .dtd file:
   $rmldt = RevML::Doctype->new( 'revml.dtd' );
   $rmldt = RevML::Doctype->new( DTD_FILE => 'revml.dtd' );

   ## To load a preparsed .pm file
   $rmldt = RevML::Doctype->new( 1.1 ) ;
   $rmldt = RevML::Doctype->new( VERSION => 1.1 ) ;


=head1 DESCRIPTION

=head1 METHODS

=over

=cut

use strict ;

use Carp ;

use XML::Doctype ;

use base 'XML::Doctype' ;

use vars qw( $VERSION ) ;

$VERSION = 0.1 ;


=item new

Creates an instance.

=cut

my $highest_doctype_pm_version;

sub _highest_doctype_pm_version {
   return $highest_doctype_pm_version if defined $highest_doctype_pm_version;

   $highest_doctype_pm_version = 0 ;

   unless ( grep defined, @_ ) {
      @_ = map glob( "$_/v*.pm" ),
         grep -d,
         map "$_/RevML/Doctype",
         grep !ref,
         @INC;
   }

   for ( @_ ) {
      next unless s{.*RevML/Doctype/v([\d_]+)\.pm$}{$1}i ;
      tr/_/./ ;
      $highest_doctype_pm_version = $_
         if $_ > $highest_doctype_pm_version;
   }
   return $highest_doctype_pm_version;
}


sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my ( $dtd_spec, @doctype_modules ) = @_ ;

   $dtd_spec = _highest_doctype_pm_version @doctype_modules
      if ! defined $dtd_spec || $dtd_spec eq 'DEFAULT' ;

   die "No RevML::Doctype found, use -dtd option or install a RevML::DocType::vXXX module\n"
      unless $dtd_spec ;

   ## Try to load $self from a file, or bless one ourself and parse a DTD.
   my $self ;

   if ( $dtd_spec =~ /^\d+(?:\.\d+)*$/ ) {
      ## TODO: Make the save format provide a new(), or be data-only.
      my $doctype_pm = $dtd_spec ;
      $doctype_pm =~ tr/./_/ ;
      require "RevML/Doctype/v$doctype_pm.pm" ;
      no strict 'refs' ;
      $self = ${"RevML::Doctype::v$doctype_pm\::doctype"} ;
      die $@ if $@ ;
   }
   else {
      ## Read in the DTD from a file.
      $self = fields::new( $class );

      ## Read in the file instead of referring to an external entitity to
      ## get more meaningful error messages.  It's short.
      ## TODO: This is probably the result of a minor tail-chasing incident
      ## and we might be able to go back and read the file directly
      open( DTD, "<$dtd_spec" ) or die "$!: $dtd_spec" ;
      my $dtd = join( '', <DTD> ) ;
      close DTD ;
      $self = $class->SUPER::new( 'revml', DTD_TEXT => $dtd ) ;
   }

   die "Unable to load DTD", defined $dtd_spec ? " '$dtd_spec'" : '', "\n"
      unless $self ;

   die "No <revml> version attribute found"
      unless defined $self->version ;

   return $self ;
}


=item save_as_pm

   $doctype->save_as_pm ;
   $doctype->save_as_pm( $out_spec ) ;

Outspec is a module name.  'RevML::Doctype::vNNN' is assumed if
no outspec is provided.  Use '-' to emit to STDOUT.

Saves the Doctype object in a perl module.  Tries to save in
lib/RevML/Doctype/ if that directory exists, then in ./ if not.

=cut

sub save_as_pm {
   my $self = shift ;

   my ( $out_spec ) = @_ ;
   ## TODO: Try to prevent accidental overwrites by looking for
   ## the destination and diffing, then promping if a diff is
   ## found.
   $out_spec = "RevML::Doctype::v" . $self->version
      unless defined $out_spec ;

   $out_spec =~ s/\./_/g ;

   if ( $out_spec ne '-' ) {
      my $out_file = $out_spec ;
      $out_file =~ s{::}{/}g ;
      $out_file =~ s{^/+}{}g ;
      $out_file .= '.pm' ;

      require File::Basename ;
      my $out_dir = File::Basename::dirname( $out_file ) ;

      if ( -d File::Spec->catdir( 'lib', $out_dir ) ) {
	 $out_file = File::Spec->catfile( 'lib', $out_file ) ;
      }
      elsif ( ! -d $out_dir ) {
	 $out_file = File::Basename::fileparse( $out_file ) ;
      }

      print "writing RevML v" . $self->version . " to '$out_file' as '$out_spec'.\n" ;
      open( F, ">$out_file" ) || die "$! $out_file" ;
      print F $self->as_pm( $out_spec ) ;
      close F ;

      ## Test for compilability if we saved it.
      exec( 'perl', '-w', $out_file ) if defined $out_file ;
   }
   else {
      print $self->as_pm( $out_spec ) ;
   }

   return ;
}


sub version {
   my $self = shift ;
   return $self->element_decl( 'revml' )->attdef( 'version' )->default ;
}


=item import

=item use

   ## To extablish a default RevML::Doctype for the current package:
   use RevML::Doctype 'DEFAULT' ;
   use RevML::Doctype DTD_FILE => 'revml.dtd' ;

=cut

## This inherits XML::Doctype::import, which passes through the args
## to our constructor.


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
