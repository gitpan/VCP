package RevML::Writer ;

=head1 NAME

RevML::Writer - Write RevML files using the RevML DTD

=head1 SYNOPSIS

   use RevML::Doctype::v1_1 ;
   use RevML::Writer ;

=head1 DESCRIPTION

This class provides facilities to write out the tags and content of
RevML documents.  See XML::AutoWriter for all the details on this
writer's API.

=cut


use strict ;
use vars qw( $VERSION ) ;

use base qw( XML::AutoWriter ) ;

$VERSION = 0.1 ;

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

This module is Copyright 2000, Perforce Software, Inc.  All rights reserved.

This will be licensed under a suitable license at a future date.  Until
then, you may only use this for evaluation purposes.  Besides which, it's
in an early alpha state, so you shouldn't depend on it anyway.

=cut

1 ;
