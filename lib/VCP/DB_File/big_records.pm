package VCP::DB_File::big_records;

=head1 NAME

VCP::DB_File::big_records - VCP::DB_File::sdbml subclass for large records

=head1 SYNOPSIS

    use VCP::DB_File;
    VCP::DB_File->new;

=head1 DESCRIPTION

sdbm files are limited to 1008 bytes per record, including key.  That's
just not enough for storing revisions in (although it suffices for most
other VCP needs).

This subclass assumes your disk is large enough and that you won't be
altering records in place, but allows for unlimited record sizes.  No
attempt is made to reclaim free space; so far our application doesn't
need that.

Records are retrievable in the order they were added in (so this "file"
may be a queue) or in random order (like a DB file).

=head1 INTERNALS

There are three related data sets:

    - an sdbm database "db", which is an index to the location and size
      of each record for the key of the record
    - a file "records.mdb", which is a set of ( key, record size, record data)
      entries for each record
    - a file "order.txt", which is a flat file with one key per record
      in the order that they were added to the file

Generally, you should use this module only to read or write a dataset as an
error in reading could cause corruption if you write (the orders.txt is not
flushed or seek() properly on a read error).  This is sufficient for our
purposes, because these files are only used by but could be a problem if read/write mode is needed.

=over

=for test_script t/01db_file_big_records.t

=cut

$VERSION = 1 ;

@EXPORT_OK = qw( escape_nl deescape_nl );

@ISA = qw( VCP::DB_File::sdbm Exporter );

use strict ;

use VCP::Debug qw( :debug );
use Fcntl;
use File::Spec;
use VCP::Debug qw( :debug );
use VCP::Logger qw( lg pr BUG );
use VCP::Utils qw( empty );
use VCP::DB_File::sdbm;

#use base qw( VCP::DB_File::sdbm Exporter );

#use fields (
#   'RecordsFileName',  ## Where we store the data
#   'RecordsFH',        ## Our handle to it when its open
#   'OrderFileName',    ## The order the records were added in
#   'OrderFH',
#);


sub db_file {
   my $self = shift;
   return File::Spec->catfile(
      $self->store_loc,
      "db"
   );
}


sub records_file {
   my $self = shift;
   return File::Spec->catfile(
       $self->store_loc,
       "records.mdb"
    );
}


sub order_file {
   my $self = shift;
   return File::Spec->catfile(
       $self->store_loc,
       "order.txt"
    );
}


sub close_db {
   my $self = shift;

   close $self->{RecordsFH} if $self->{RecordsFH};
   close $self->{OrderFH}   if $self->{OrderFH};
   $self->{RecordsFH} = undef;
   $self->{OrderFH} = undef;

   $self->SUPER::close_db;
}


sub _open {
   my ( $fn, $mode ) = @_;

   local *DATAFILE;
   sysopen DATAFILE, $fn, $mode or die "$! opening '$fn'";
   binmode DATAFILE;
   return *DATAFILE{IO};
}


sub open_db {
   my $self = shift;

   $self->SUPER::open_db;
   $self->{RecordsFH} = _open $self->records_file, O_RDWR | O_CREAT;
   $self->{OrderFH}   = _open $self->order_file,   O_RDWR | O_CREAT;
}


sub open_existing_db {
   my $self = shift;

   $self->SUPER::open_db;

   my $fn = $self->records_file;

   $self->{RecordsFH} = _open $self->records_file, O_RDWR;
   $self->{OrderFH}   = _open $self->order_file,   O_RDWR;
}


sub escape_nl {
   my $k = shift;
   $k =~ s/\\/\\\\/g;
   $k =~ s/\n/\\n/g;
   return $k;
}


sub deescape_nl {
   my $k = shift;
   1 while chomp $k;
   $k =~ s{\\n}{\n}g;
   $k =~ s{\\\\}{\\}g;
   return $k;
}


sub set {
   my $self = shift;
   my $key_parts = shift;

   my $key = $self->pack_values( @$key_parts );

   my $pointer = $self->SUPER::raw_get( $key );
   my ( $location, $old_encoded_size ) =
      defined $pointer
         ? $self->unpack_values( $pointer )
         : ( undef, 0 );

   if ( !defined $location ) {
      my $fh = $self->{OrderFH};
      print $fh escape_nl( $key ), "\n";
   }

   BUG "corrupt pointer '$pointer' for '$key'\n"
      if defined $pointer and empty $location or empty $old_encoded_size;

   ## The dual \n is for easy reading in an editor
   my $packed = escape_nl( $self->pack_values( @_ ) ) . "\n====\n";
   my $data_size = length( $packed ) - 6;  ## the \n====\n is not data.

   my $header = "$key;$data_size\n";  # not packed, but safe-ish
       ## We include the key in case we ever need to rebuild the sdbm
       ## file.

   my $encoded_size = $data_size + length $header;

   if ( $encoded_size > $old_encoded_size && defined $location ) {
      sysseek  $self->{RecordsFH}, $location, 0;
      syswrite $self->{RecordsFH}, ( "x" x ( $old_encoded_size - 1 ) ) . "\n";
      $location = undef;
   }

   if ( empty $location ) {
      lg "growing $key from $old_encoded_size to $encoded_size"
         if $old_encoded_size;
      $location = sysseek( $self->{RecordsFH}, 0, 2 );
      $self->raw_set( $key, $self->pack_values( $location, $encoded_size ) );
   }

   sysseek  $self->{RecordsFH}, $location, 0;
   syswrite $self->{RecordsFH}, $header;
   syswrite $self->{RecordsFH}, $packed;
}


sub get_data {
   my $self = shift;
   my ( $location, $encoded_size ) = @_;

   return if empty $location;

   sysseek $self->{RecordsFH}, $location, 0;
   sysread $self->{RecordsFH}, my( $v ), $encoded_size;
   my ( $header, $value ) = split /\n/, $v, 2;
   my ( $key, $length ) = split /;/, $header;

   BUG "corrupt header '$header'"
      if empty $key || empty $length;
   substr( $value, $length ) = "";  ## Knock off extra data
   BUG "length trim failed: $length != ", length $value
      if length $value != $length;

   return $self->unpack_values( deescape_nl $value );
}


sub get {
   my $self = shift;
   return $self->get_data( $self->SUPER::get( @_ ) )
}


=item foreach_record_do

    $db->foreach_record_do( sub { ... } );

Iterate over the contents in as-stored order, executing sub { ... }
for each one found.

=cut

sub foreach_record_do {
   my $self = shift;
   my ( $sub ) = @_;

   my $fh = $self->{OrderFH};

   seek $fh, 0, 0;
   while ( <$fh> ) {
      $sub->(
         $self->get_data(
            $self->unpack_values(
               $self->raw_get( deescape_nl $_ )
            )
         )
      );
   }
}


=item dump

BROKEN FOR NOW.  Reports the pointers, not the pointed-to data

TODO: fix.

=cut

=back

=head1 LIMITATIONS

There is no way (yet) of telling the mapper to continue processing the
rules list.  We could implement labels like C< <<I<label>>> > to be
allowed before pattern expressions (but not between pattern and result),
and we could then impelement C< <<goto I<label>>> >.  And a C< <<next>>
> could be used to fall through to the next label.  All of which is
wonderful, but I want to gain some real world experience with the
current system and find a use case for gotos and fallthroughs before I
implement them.  This comment is here to solicit feedback :).

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
