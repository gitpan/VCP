package VCP::Filter::dumpdata ;

=head1 NAME

VCP::Filter::dumpdata - developement output filter

=head1 DESCRIPTION

Dump all data structures.  Requires the module BFD, which is not installed
automatically.  Dumps to the log file.

Not a supported module, API and behavior may change without warning.

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Filter );

use strict ;

#use base qw( VCP::Filter );

use VCP::Filter;
use VCP::Logger qw( lg );
use BFD qw();

sub handle_header {
   my $self = shift;
   lg BFD::d_to_string "for ", ref $self->dest, $_[0];
   $self->dest->handle_header( @_ );
}

sub handle_rev {
   my $self = shift;
   lg BFD::d_to_string "for ", ref $self->dest, $_[0]->as_hash;
   $self->dest->handle_rev( @_ );
}


sub handle_footer {
   my $self = shift;
   lg BFD::d_to_string "for ", ref $self->dest, $_[0];
   $self->dest->handle_footer( @_ );
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
