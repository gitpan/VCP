package VCP::Dest::summary ;

=head1 NAME

VCP::Dest::summary - developement output

=head1 DESCRIPTION

Dump each revision as a string.

Not a supported module, API and behavior may change without warning.

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Dest );

use strict ;

use VCP::Dest;
use VCP::Logger qw( pr );
#use base qw( VCP::Dest );

sub _dump {
    my ( $h ) = @_;

    my @keys = sort keys %$h;
    my $w;
    for ( @keys ) {
       $w = length if !defined $w || $w < length;
    }

    map {
       my $v = $h->{$_};
       $v =~ s/([\\'])/\\$1/g;
       $v =~ s/\r/\\r/g;
       $v =~ s/\n/\\n/g;
       $v =~ s/\t/\\t/g;
       sprintf "    %-${w}s: '%s'\n", $_, $v;
    } @keys;
}

sub handle_header { pr "Header:\n", _dump $_[1] }
sub handle_rev    { pr $_[1]->as_string, "\n"   }
sub handle_footer { pr "Footer:\n", _dump $_[1] }


=back

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
