package VCP::Dest::csv ;

=head1 NAME

VCP::Dest::csv - developement output

=head1 DESCRIPTION

Dump each revision's metadata in CSV format.  Does not dump header/footer.

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Dest );

use strict ;

use VCP::Dest;
use VCP::Logger qw( pr );
use VCP::Utils qw( empty start_dir_rel2abs );

#use base qw( VCP::Dest );
#use fields (
#   'FIELDS',   ## Which fields to print
#   'FILE',     ## Where to write output, if not STDOUT
#   'FH',       ## The filehandle for output
#);


sub new {
   my $self = shift->SUPER::new( @_ ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_repo_spec( $spec );
   $self->parse_options( $options );

   return $self ;
}


sub options_spec {
   my $self = shift ;

   return (
      $self->SUPER::options_spec,
      "fields=s" => \$self->{FIELDS},
      "file=s"   => \$self->{FILE},
   );
}

sub csv_escape {
   local $_ = @_ ? shift : $_;
   return "" unless defined;
   return '""' unless length;
   ## crude but effective.
   s/\r/\\r/g;
   s/\n/\\n/g;
   s/"/""/g;
   $_ = qq{"$_"} if /[",]/;
   $_;
}

sub init {
   my $self = shift ;
   $self->SUPER::init;

   $self->{FIELDS} = [
      !empty( $self->{FIELDS} )
         ? do {
            my @names = split /,/, $self->{FIELDS};
            my %fields = map {
               my $name = $_;
               $name =~ s/\@//;
               ( $name => $_ );
            } VCP::Rev->fields;

            for ( @names ) {
               if ( ! exists $fields{$_} && !VCP::Rev->can($_) ) {
                  pr "vcp: '$_' not a name, skipping";
                  next;
               }
               $_ = $fields{$_} if exists $fields{$_};
            }

            @names;
         }
         : VCP::Rev->fields
   ];
}

sub handle_header {
   my $self = shift ;

   $self->{FILE} = $self->repo_filespec
      if empty $self->{FILE};

   if ( empty $self->{FILE} ) {
      $self->{FH} = \*STDOUT;
   }
   else {
      local *F;
      my $fn = start_dir_rel2abs( $self->{FILE} );
      open F, "> $fn" or die "$! opening $fn\n";
      $self->{FH} = *F{IO};
   }

   my $fh = $self->{FH};

   print $fh join( ",", map {
      my $name = $_;
      $name =~ s/\@//;
      csv_escape( $name );
   } @{$self->{FIELDS}} ),
   "\n";
}
sub handle_footer {}

sub handle_rev    {
   my $self = shift ;
   my ( $r ) = @_;

   my $fh = $self->{FH};

   print $fh join( ",", map {
      my $name = $_;
      my $is_list = $name =~ s/\@//;
      csv_escape(
         $name eq "time"
            ? VCP::Rev::iso8601format( $r->$name )
            : $is_list
               ? join ";", $r->$name
               : $r->$name
      );
   } @{$self->{FIELDS}}
   ),
    "\n";
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
