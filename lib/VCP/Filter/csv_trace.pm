package VCP::Filter::csv_trace ;

=head1 NAME

VCP::Filter::csv_trace - developement logging filter

=head1 DESCRIPTION

Dumps fields of revisions in CSV format.

Not a supported module, API and behavior may change without warning.

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Filter );

use strict ;

#use base qw( VCP::Filter );

use VCP::Filter;
use VCP::Logger qw( pr lg );
use VCP::Utils qw( empty start_dir_rel2abs );
use Getopt::Long;

#use fields (
#   'FIELDS',   ## Which fields to print
#   'FILE',     ## Where to write output
#   'FH',       ## The filehandle of the output file
#);


sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   ## Cheesy.  TODO: factor parse_options up to plugin?

   if ( $options && @$options ) {
      local *ARGV = $options;

      GetOptions(
         "fields=s" => \$self->{FIELDS},
         "file=s"   => \$self->{FILE},
      ) or $self->usage_and_exit ;
   }

   die "vcp: output filename required for csv_trace filter\n"
      if empty $self->{FILE};
   return $self ;
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

   local *F;
   my $fn = start_dir_rel2abs( $self->{FILE} );
   open F, "> $fn" or die "$! opening $fn\n";
   $self->{FH} = *F{IO};

   my $fh = $self->{FH};

   print $fh join( ",", map {
      my $name = $_;
      $name =~ s/\@//;
      csv_escape( $name );
   } @{$self->{FIELDS}} ),
   "\n";

   $self->SUPER::handle_header( @_ );
}

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
   $self->SUPER::handle_rev( $r );
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
