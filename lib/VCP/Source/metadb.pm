package VCP::Source::metadb ;

=head1 NAME

VCP::Source::metadb - Read SCM metadata from a metadb file

=head1 SYNOPSIS

## Mostly used internally by the vcp filter and vcp transfer commands

=head1 DESCRIPTION

This source driver allows L<vcp|vcp> to read a set of revisions from
a metadata database written by VCP::Dest::metadb.

NOTE: passing a reference in the options array to new:

    $s = VCP::Source::metadb->new( $spec, [ $real_source ] );

sets the metadb's source to point to the real repository it should
get revisions from.  This should only be necessary for a transfer
operation, as filtering does not need to access the source repository.

=cut


@ISA = qw( VCP::Source VCP::Utils::metadb );

use strict ;

use VCP::Logger qw( pr BUG );
use VCP::Source;
use VCP::Utils qw( empty );
use VCP::Utils::metadb;

use vars qw( $VERSION $debug ) ;

$VERSION = 0.1 ;

#use base qw( VCP::Source VCP::Utils::metadb ) ;

#use fields (
#   'META_DB',        ## The bulk data file with the revisions
#   'REAL_SOURCE',    ## The *real* source to use if transferring revs
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

   $self->parse_repo_spec( $spec )
      unless empty $spec;

   ## grep out the REAL_SOURCE option
   @$options = grep
      !ref || ( ( $self->{REAL_SOURCE} = $_ ) && 0 ),
      @$options;

   $self->parse_options( $options );

   return $self;
}


sub init {
   my $self = shift ;

   $self->SUPER::init;

   $self->real_source->init
      if $self->real_source;

   die "VCP::Source::metadb::repo_server not set"
      if empty $self->repo_server;

   $self->repo_id( "metadb:" . $self->repo_server );

   $self->meta_db->open_db;

   return $self ;
}


sub dest {
   my $self = shift ;

   return $self->SUPER::dest( @_ );
}


sub handle_header {
   my $self = shift ;

   $self->dest->handle_header( $self->read_header )
      if $self->dest;
}


sub real_source {
   my $self = shift ;
    return $self->{REAL_SOURCE};
}


sub get_rev {
   my $self = shift ;
   BUG "metadb can't get a rev without a real source"
      unless $self->{REAL_SOURCE};

   return $self->{REAL_SOURCE}->get_rev( @_ );
}


sub copy_revs {
   my $self = shift ;

   $self->meta_db->foreach_record_do(
      sub {
         my $r = VCP::Rev->deserialize( @_ );
         $self->send_rev( $r );
      }
   );

}


=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1 ;
