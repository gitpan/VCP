package VCP::Source::null ;

=head1 NAME

VCP::Source::null - A null source, for testing purposes

=head1 SYNOPSIS

   vcp null:

=head1 DESCRIPTION

Takes no options, delivers no data.

=cut

$VERSION = 1.0 ;

@ISA = qw( VCP::Source );

use strict ;

use Carp ;
use VCP::Debug ":debug" ;
use File::Spec;
use VCP::Source;

#use base qw( VCP::Source );

sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   die "vcp: the null source takes no spec ('$1')\n"
      if defined $spec && $spec =~ m{\Anull:(.+)}i;

   $self->repo_id( "null" );

   $self->parse_repo_spec( $spec ) if defined $spec;
   $self->parse_options( $options );

   return $self ;
}


sub options_spec {
   return ();
}


sub handle_header {
   my $self = shift ;
   my ( $header ) = @_ ;

   $self->dest->handle_header( $header );
   return ;
}


sub get_source_file {
   my $self = shift;
   require File::Spec;
   my ( $r ) = @_;

   return File::Spec->devnull;
}


=head1 SEE ALSO

L<VCP::Dest::null>, L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
