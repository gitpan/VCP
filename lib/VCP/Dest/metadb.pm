package VCP::Dest::metadb ;

=head1 NAME

VCP::Dest::metadb - Store all metadata in to a serial store

=head1 SYNOPSIS

   metadb:[<output-file>]

=head1 DESCRIPTION

=head1 EXTERNAL METHODS

=over

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Dest VCP::Utils::metadb );

use strict ;

use VCP::Dest;
use VCP::Logger qw( pr_doing );
use VCP::Utils qw( empty );
use VCP::Utils::metadb;

#use base qw( VCP::Dest VCP::Utils::metadb );

#use fields (
#    'META_DB',   ## The bulk data file with the revisions
#) ;


=item new

Creates a new instance.  The only parameter is '-dtd', which overrides
the default DTD found by searching for modules matching RevML::DTD:v*.pm.

Attempts to create the output file if one is specified.

=cut

sub new {
   my $self = shift->SUPER::new( @_ ) ;

   my ( $spec, $options ) = @_ ;

   $self->parse_repo_spec( $spec )
      unless empty $spec;

   $self->parse_options( $options );

   return $self;
}


sub init {
   my $self = shift ;

   $self->SUPER::init;

   die "VCP::Dest::metadb::repo_server not set"
      if empty $self->repo_server;

   $self->repo_id( "metadb:" . $self->repo_server );

   $self->head_revs->delete_db;
   $self->meta_db  ->delete_db;
   $self->head_revs->open_db;
   $self->meta_db  ->open_db;

   return $self ;
}


sub handle_header {
   my $self = shift ;
   my ( $h ) = @_ ;

   $self->write_header( $h );
}


sub handle_rev {
   my $self = shift ;
   my $r ;
   ( $r ) = @_ ;

   $self->meta_db->set( [ $r->id ], $r->serialize );

   pr_doing;

   $self->head_revs->set( [ $r->source_repo_id, $r->source_filebranch_id ],
                          $r->source_rev_id );
}


sub handle_footer {
   my $self = shift ;
   my ( $footer ) = @_ ;

   $self->SUPER::handle_footer;

   return ;
}


=back

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
