package VCP::DefaultFilters;


=head1 NAME

VCP::DefaultFilters - Class for determining default filters
to install for a given source and dest.

=head1 SYNOPSIS

   require VCP::DefaultFilters;
   my $df = VCP::DefaultFilters->new;
   my @filter_args = $df->create_default_filters( $source, $dest );

=head1 DESCRIPTION

   Given references to a vcp source and destination, determines the
   default filters which would be appropriate, builds and returns a
   list of arguments that should look like the portion of @ARGV (command
   line arguments) that specify filters.

=head1 

   There should be a default filter wizard sub of the form
   <source-scheme>2<dest-scheme>_default_filters for each source -> dest
   combination that requires default filters to be loaded.  If no
   default filters are required for a source -> dest combination, no
   wizard sub need be defined by that name.

   The @args array definition in the following subs looks like .vcp
   config file format, but it's not parsed by that.  we're just using
   qw() to put the args into an array.


=cut

$VERSION = 0.1 ;

use strict;
use Carp;
use VCP::Debug qw( :debug );
use VCP::Logger qw( lg BUG );


sub new {
   my $class = shift;
   $class = ref $class || $class;

   my $self = {};
   return bless $self;
}


sub create_default_filters {
   my $self = shift;

   croak "usage create_default_filters <source>, <dest>"
      unless @_ == 2;
   my ($source, $dest) = ( $_[0]->repo_scheme, $_[1]->repo_scheme );
   my $wizard = "${source}2${dest}_default_filters";

   my @filters;
   eval {
      lg "calling $wizard to set default filters";
      @filters = $self->$wizard;
   };
   if( $@ =~ /Can't locate object method "$wizard" via/i ) {
      lg "no default filters defined for $source to $dest conversion";
   }
   else {
      BUG "create_default_filters: $@\n" if $@;
   }

   return @filters;
}

##-------------------------------------------------------------------------##
## default filter wizards below


sub cvs2p4_default_filters {
   my @args = qw( 
      Map:
         (...)<>      main/$1
         (...)<(*)>   $2/$1
   );
   return @args;
}


sub p42cvs_default_filters {
   ## ASSumes directories under //depot/foo/ are the main and branch
   ## dirs.
   my @args = qw( 
      Map:
        */(...)<(...)>  $1<$2>
   );
   return @args;
}


=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut


1;

