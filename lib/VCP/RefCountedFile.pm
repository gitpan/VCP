package VCP::RefCountedFile;

=head1 NAME

VCP::RefCountedFile - An object that deletes a named file when nothing refers to it any more.

=head1 SYNOPSIS

   use VCP::RefCountedFile;

   {
      my $fn = VCP::RefCountedFile->new( "/path/to/name" );
      print $fn;
   }  ## "name" is deleted here.

=head1 DESCRIPTION

An object that mimics a string, but which refers to a file and deletes the
file when the last reference to the file via such objects disappears.

=cut

$VERSION = 1;

use strict ;

use Carp ;
use overload (
   '""' => \&as_string,
   'cmp' => sub {
      "$_[0]" cmp "$_[1]"
   },
);

use VCP::Debug ':debug' ;
use VCP::Logger qw( pr );
use VCP::Utils 'empty' ;

sub new {
   my $class = ref $_[0] ? ref shift : shift;
   my $self = bless \my( $value ), $class;
   $self->set( @_ ) if @_;
   return $self;
}


sub as_string {
   my $self = shift;
   return $$self;
}


my %ref_counts;
    ## Each file gets a ref count.  This hash maintains that ref_count.


sub set {
   my $self = shift;

   my ( $value ) = @_;

   if ( !empty( $$self )
      && $ref_counts{$$self}
      && --$ref_counts{$$self} < 1
      && -e $$self
   ) {
      if ( debugging ) {
         my @details ;
	 my $i = 2 ;
	 do { @details = caller($i++) } until $details[0] ne __PACKAGE__ ;
	 debug "$self unlinking '$$self' in "
	    . join( '|', @details[0,1,2,3]) ;
      }
      unlink $$self or pr "$! unlinking $$self\n"
         unless $ENV{VCPNODELETE};
   }

   $$self = $value;

   ++$ref_counts{$$self} unless empty $$self;
}

END {
   if ( debugging && ! $ENV{VCPNODELETE} ) {
      for ( sort keys %ref_counts ) {
	 if ( -e $_ ) {
	    pr "$_ not deleted" ;
	 }
      }
   }
}


sub DESTROY {
   return if $ENV{VCPNODELETE};
   my $self = shift ;
   $self->set( undef );
}


=back

=head1 SUBCLASSING

This class is a bless scalar.

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
