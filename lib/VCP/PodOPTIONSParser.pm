package VCP::PodOPTIONSParser;

=head1 NAME

VCP::PodOPTIONSParser - Parse OPTIONS sections from a set of source files.

=head1 SYNOPSIS

   use VCP::PodOPTIONSParser;
   my $p = VCP::PodOPTIONSParser->new;
   my $options_hash = $p->parse( @packages_or_filenames );

=head1 DESCRIPTION

Returns a hash of all C<=item>s found in all OPTIONS sections in the
given filenames.  Warns if duplicate options are found.

ASSUMES ALL PACKAGES REFERRED TO ARE ALREADY LOADED.  %INC is used to
locate their source code.

Converts packages (any string matching /\w[:\w]+/) to filenames.

=cut

$VERSION = 0.1 ;

use Pod::Select;
@ISA = qw( Pod::Select );

use strict;

use VCP::Logger qw( BUG );

sub verbatim {
   my $self = shift;
   my ( $paragraph ) = @_;

   1 while chomp $paragraph;
   push @{$self->{Options}->{$self->{CurOption}}}, $paragraph
      if defined $self->{CurOption};
}

sub textblock {
   my $self = shift;
   my ( $paragraph ) = @_;

   1 while chomp $paragraph;
   push @{$self->{Options}->{$self->{CurOption}}}, $paragraph
      if defined $self->{CurOption};
}

sub command {
   my $self = shift;
   my ( $command, $paragraph ) = @_;

   if ( $command eq "item" ) {
       1 while chomp $paragraph;
       $self->{CurOption} = $paragraph;
   }
   else {
       $self->{CurOption} = undef;
   }

}

sub parse {
   my $self = shift;
   $self = $self->new unless ref $self;

   $self->select( "OPTIONS" );

   $self->{Options} = {};

   for my $fn ( @_ ) {
      if ( $fn =~ /\A\w[:\w]+\z/ ) {
         ( my $key = $fn ) =~ s/::/\//g;
         $key .= ".pm";
         BUG "can't find source for $fn in \%INC"
            unless defined $INC{$key};
         $fn = $INC{$key};
      }
      $self->parse_from_file( $fn );
   }

   return $self->{Options};
}

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
