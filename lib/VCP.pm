package VCP ;

=head1 NAME

VCP - Versioned Copy, copying hierarchies of versioned files

=head1 SYNOPSIS

=head1 DESCRIPTION

This module copies hierarchies of versioned files between repositories, and
between repositories and RevML (.revml) files.

Stay tuned for more documentation.

=head1 EXPORTS

The following functions may be exported: L</debug>, L</enable_debug>,
L</disable_debug>, along with the tags ':all' and ':debug'.  Use the latter
to head off future namespace pollution in case :all gets expanded in the
future..

=head1 METHODS

=over

=cut

use strict ;
use File::Spec ;
use File::Path ;
use VCP::Debug ;
use vars qw( $VERSION ) ;

$VERSION = 0.1 ;

require VCP::Source ;
require VCP::Dest ;

use fields (
   'SOURCE',     # The VCP::Source to pull data from
   'DEST',       # The RevML::Writer instance
) ;


=item new

   $ex = VCP->new( $source, $dest ) ;

where

   $source  is an instance of VCP::Source
   $dest    is an instance of VCP::Dest

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my ( $source, $dest ) = @_ ;

   my VCP $self ;
   {
      no strict 'refs' ;
      $self = bless [ \%{"$class\::FIELDS"} ], $class ;
   }

   $self->{SOURCE} = $source ;
   $self->{DEST}   = $dest ;

   return $self ;
}


=item dest

   $dest = $vcp->dest ;

Gets the dest object.  This object is set by passing it to
new(), so there's no need to set it.

=cut

sub dest {
   my VCP $self = shift ;
   return $self->{DEST} ;
}


=item copy_all

   $vcp->copy_all( $header, $footer ) ;

Calls $source->handle_header, $source->copy_revs, and $source->handle_footer.

=cut

sub copy_all {
   my VCP $self = shift ;

   my ( $header, $footer ) = @_ ;

   my VCP::Source $s = $self->source ;
   $s->dest( $self->dest ) ;

   $s->handle_header( $header ) ;
   $s->copy_revs() ;
   $s->handle_footer( $footer ) ;

   ## Removing this link allows the dest to be cleaned up earlier by perl,
   ## which keeps VCP::Rev from complaining about undeleted revs.
   $s->dest( undef ) ;
   return ;
}


=item source

   $source = $vcp->source ;

Gets the source object.  This object is set by passing it to
new(), so there's no need to set it.

=cut

sub source {
   my VCP $self = shift ;
   return $self->{SOURCE} ;
}


=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
