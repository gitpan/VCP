package VCP::Utils::metadb ;

=head1 NAME

VCP::Utils::metadb - utilities for dealing with metadbs 

=head1 SYNOPSIS

   use VCP::Utils::metadb;

=head1 DESCRIPTION

A mix-in class providing methods shared by VCP::Source::metadb and
VCP::Dest::metadb.

=cut

use strict ;

use VCP::Logger qw( pr );
use VCP::DB_File::big_records qw( escape_nl deescape_nl );

=head1 METHODS

=over

=item meta_db

Returns a reference to the Creates an empty one if need be.

=cut

sub meta_db {
   my $self = shift ;
   
   return $self->{META_DB} ||= do {
      $self->{META_DB} = VCP::DB_File::big_records->new( 
         StoreLoc => $self->_db_store_location,
         TableName => "revs",
      );
   };
}


## The meta_db itself is just a set of records with an ordering.  The
## record storage is provided by big_records.pm, but we need to store some
## additional stuff, and we can either store the header as a record or
## store it as a separate entity.  I've chosen to store it as a separate
## entity so that big_records.pm will store only revs, with an eye towards
## later optimization that could take advantage of that consistency.

sub header_file {
   my $self = shift;

   return File::Spec->catfile(
      $self->meta_db->store_loc,
      "header.txt"
   );
}


=item write_header

Writes a header to the meta_db.

=cut

sub write_header {
   my $self = shift;
   my ( $h ) = @_;

   my $fn = $self->header_file;

   open HEADER, "> $fn" or die "$!: '$fn'\n";
   for ( sort keys %$h ) {
      warn "not storing header field $_ => $h->{$_}"
         if ref $h->{$_};
      die "header keys may not contain '=': '$_'\n"
         if 0 <= index $_, "=";
      print HEADER escape_nl( $_ ), "=", escape_nl( $h->{$_} ), "\n"
         or die "$! while writing '$fn'\n";
   }
   close HEADER;
}


=item read_header

Reads a header from the meta_db.

=cut

sub read_header {
   my $self = shift;

   my $fn = $self->header_file;
   my %h;
   open HEADER, "< $fn" or die "$!: '$fn'\n";
   while ( <HEADER> ) {
      chomp;
      my ( $key, $value ) = map deescape_nl( $_ ), split /=/, $_, 2;
      $h{$key} = $value;
   }
   close HEADER;
   return \%h;
}


=back


=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1;
