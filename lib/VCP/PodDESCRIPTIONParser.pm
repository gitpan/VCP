package VCP::PodDESCRIPTIONParser;

=head1 NAME

VCP::PodDESCRIPTIONParser - Parse DESCRIPTION sections from a set of source files.

=head1 SYNOPSIS

   use VCP::PodDESCRIPTIONParser;
   my $p = VCP::PodDESCRIPTIONParser->new;
   my $options_hash = $p->parse( @packages_or_filenames );

=head1 DESCRIPTION

Returns a hash of all C<=item>s found in all DESCRIPTION sections in the
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
   push @{$self->{Paragraphs}}, $paragraph;
}

sub textblock {
   my $self = shift;
   my ( $paragraph ) = @_;

   $paragraph =~ s/\s+/ /g;
   $paragraph =~ s/\A\s+//g;
   $paragraph =~ s/\s+\z//g;
   push @{$self->{Paragraphs}}, $paragraph;
}

sub command {
   my $self = shift;
   my ( $command, $paragraph ) = @_;

   return if $command eq "head1";  ## The reader already
                                   ## knows it's a DESCRIPTION

   $paragraph =~ s/\s+/ /g;
   $paragraph =~ s/\A\s+//g;
   $paragraph =~ s/\s+\z//g;

   $paragraph .= "\n" . "=" x length $paragraph;
   push @{$self->{Paragraphs}}, $paragraph;
}


sub parse {
   my $self = shift;
   $self = $self->new unless ref $self;
   my ( $fn ) = @_;

   $self->select( "DESCRIPTION" );

   $self->{Paragraphs} = [];


   $self->parse_from_file( $fn );

   return $self->{Paragraphs};
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
