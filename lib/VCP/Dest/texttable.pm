package VCP::Dest::texttable ;

=head1 NAME

VCP::Dest::texttable - developement output

=head1 DESCRIPTION

Dump each revision's metadata in a text table format. 

Requires Text::Table to be installed.

Does not dump header/footer.

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Dest );

use strict ;

use VCP::Dest;
use VCP::Logger qw( pr );
use Text::Table;
use VCP::Utils qw( empty start_dir_rel2abs );

#use base qw( VCP::Dest );
#use fields (
#   'FIELDS',   ## Which fields to print
#   'FILE',     ## Where to write output, if not STDOUT
#   'FH',       ## The filehandle for output
#   'TABLE',    ## The Text::Table object
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

   my %sep = (
      is_sep => 1,
      title  => "|",
      body   => "|",
   );

   $self->{TABLE} = Text::Table->new(
      \%sep,
      map { ( "$_\n&", \%sep ) } @{$self->{FIELDS}}
   );

   if ( empty $self->{FILE} ) {
      $self->{FH} = \*STDOUT;
   }
   else {
      local *F;
      my $fn = start_dir_rel2abs( $self->{FILE} );
      open F, "> $fn" or die "$! opening $fn\n";
      $self->{FH} = *F{IO};
   }

}


sub handle_footer {
   my $self = shift;

   my $fh = $self->{FH};
   my $table = $self->{TABLE};

   print $fh
      $table->rule( "-", "+" ),
      $table->title,
      $table->rule( "-", "+" ),
      $table->body,
      $table->rule( "-", "+" );
}

sub handle_rev    {
   my $self = shift ;
   my ( $r ) = @_;

   $self->{TABLE}->add(

      map {
	 my $name = $_;
	 my $is_list = $name =~ s/\@//;
	 my $value = $name eq "time"
	    ? VCP::Rev::iso8601format( $r->$name )
	    : $is_list
	       ? join ", ", map "'$_'", $r->$name
	       : $r->$name;

         $value =~ s/\r/\\r/g;
         $value =~ s/\n/\\n/g;
         $value;
         
      } @{$self->{FIELDS}}
   );

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
