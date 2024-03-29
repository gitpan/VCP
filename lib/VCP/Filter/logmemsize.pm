package VCP::Filter::logmemsize ;

=head1 NAME

VCP::Filter::logmemsize - developement logging filter

=head1 DESCRIPTION

Watches memory size.  Only works on linux for now.

Not a supported module, API and behavior may change without warning.

=cut

$VERSION = 0.1 ;

use strict ;

my $start_size;


sub get_size {
    open F, "/proc/$$/statm" or return 0;
    my ( $s ) = <F> =~ /^(\d+)/;
    close F;

    return $s * 4;
}

sub get_sizes {
    my $s = get_size;

    return ( $s - $start_size, "KB (", $s, "KB)" );
}

BEGIN {
    $start_size = get_size;
}

use base qw( VCP::Filter );
use fields qw( LogString );

use VCP::Utils  qw( empty );
use VCP::Logger qw( pr lg );

END {
   lg "memsize: ", get_sizes;
}

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my ( $spec, $options ) = @_;

   my $self = $class->SUPER::new( @_ );
   $self->{LogString} = shift @$options if $options;
   $self->{LogString} = "" unless defined $self->{LogString};
   $self->{LogString} .= " " unless empty $self->{LogString};

   lg $self->{LogString}, "starting memsize: (${start_size}KB)";
   lg $self->{LogString}, "memsize: ", get_sizes;

   return $self;
}


sub handle_header {
   my VCP::Filter::logmemsize $self = shift ;

   lg $self->{LogString}, "memsize: ", get_sizes;

   $self->SUPER::handle_header( @_ );
}

sub handle_rev {
   my VCP::Filter::logmemsize $self = shift ;

   lg $self->{LogString}, "memsize: ", get_sizes;
   $self->SUPER::handle_rev( @_ );
}


sub handle_footer {
   my VCP::Filter::logmemsize $self = shift ;

   lg $self->{LogString}, "memsize: ", get_sizes;
   $self->SUPER::handle_footer ( @_ );
   lg $self->{LogString}, "memsize: ", get_sizes;
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
