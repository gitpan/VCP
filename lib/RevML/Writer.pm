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

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
