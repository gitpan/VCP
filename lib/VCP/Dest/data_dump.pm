package VCP::Dest::data_dump ;

=head1 NAME

VCP::Dest::data_dump - developement output

=head1 DESCRIPTION

Dump all data structures.  Requires the module BFD, which is not installed
automatically.

Not a supported module, API and behavior may change without warning.

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Dest );

use strict ;

use VCP::Dest;
#use base qw( VCP::Dest );

use BFD;

sub handle_header {
   warn "\n";
   d $_[1];
}

sub handle_rev {
   warn "\n";
   d $_[1]->as_hash;
}


sub handle_footer {
   warn "\n";
   d $_[1];
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
