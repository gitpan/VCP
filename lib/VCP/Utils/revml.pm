package VCP::Utils::revml ;

=head1 NAME

VCP::Utils::revml - utilities for dealing with the revml command

=head1 SYNOPSIS

   use VCP::Utils::revml ;

=head1 DESCRIPTION

A mix-in class providing methods shared by VCP::Source::revml and VCP::Dest::revml.

=cut

use strict ;

use Carp ;
use VCP::Debug qw( :debug ) ;
use VCP::Utils qw( empty ) ;

=head1 METHODS


=item parse_revml_repo_spec

parse repo_spec by calling parse_repo_spec, then
set the repo_id.

=cut

sub parse_revml_repo_spec {
   my $self = shift ;
   my ( $spec ) = @_ ;

   $self->parse_repo_spec( $spec ) ;

   $self->repo_id(
      join ":",
         "revml",
         defined $self->repo_server   ? $self->repo_server   : "",
         defined $self->repo_filespec ? $self->repo_filespec : "",
   );
};




=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1;
