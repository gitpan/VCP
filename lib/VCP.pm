package VCP ;

=head1 NAME

VCP - Versioned Copy, copying hierarchies of versioned files

=head1 SYNOPSIS

see the vcp command line.

=head1 DESCRIPTION

This module copies hierarchies of versioned files between repositories, and
between repositories and RevML (.revml) files.

Stay tuned for more documentation.

=head1 METHODS

=over

=for test_scripts t/10vcp.t t/50revml.t

=cut

$VERSION = 0.9 ;
$CHANGE_ID = ( q$Change: 4232 $ =~ /(\d+)/ )[0];
$DATE      = ( q$Date: 2004/03/18 $ =~ /(\d[\d[:punct:]]+\d)/ )[0];

use strict ;
use VCP::Logger qw( lg pr );

require VCP::Plugin;
require VCP::Source;
require VCP::Dest;

#use fields (
#   'PLUGINS',     # The VCP::Source to pull data from
#) ;


=item new

   $ex = VCP->new( $source, $dest ) ;

where

   $source  is an instance of VCP::Source
   $dest    is an instance of VCP::Dest

=cut

sub new {
   my $class = shift;
   my $self = bless {}, $class;

   my $w = length $#_;
   for ( my $i = 0; $i <= $#_; ++$i ) {
      lg sprintf "plugin %${w}d is %s", $i, ref $_[$i];
   }

   $self->{PLUGINS} = [ @_ ];

   ## Make sure that plugins are DESTROY-able and can clean up any mess
   ## they make even if the VCP object is still referred to somewhere,
   ## like a global variable or a plugin.
   $self->{PLUGIN_CLEANUP} = sub { @{$self->{PLUGINS}} = () };
   VCP::Plugin->queue_END_sub( $self->{PLUGIN_CLEANUP} );

   return $self ;
}


sub DESTROY {
   my $self = shift;
   VCP::Plugin->cancel_END_sub( $self->{PLUGIN_CLEANUP} );
}


=item insert_required_sort_filter

Called if a sorting filter must be inserted.

Does nothing if there's already a sort filter in place.

=cut

sub insert_required_sort_filter {
  my $self = shift ;

   my @sort_keys;

   for ( @{$self->{PLUGINS}}[ 1 .. $#{$self->{PLUGINS}} - 1 ] ) {
      @sort_keys = $_->sort_keys( @sort_keys );
   }

   my @sort_filters = $self->{PLUGINS}->[-1]->sort_filters( @sort_keys );

   if ( @sort_filters ) {
      pr "appending required ",
         join( ", ", map $_->filter_name, @sort_filters ),
         @sort_filters == 1 ? " filter" : " filters";
      splice @{$self->{PLUGINS}}, -1, 0, @sort_filters;
   }

}


=item copy_all

   $vcp->copy_all( $header, $footer ) ;

Calls $source->handle_header, $source->copy_revs, and $source->handle_footer.

=cut

sub copy_all {
  my $self = shift ;

   my ( $header, $footer ) = @_ ;

   lg "Plugins: ",
      join ", ",
      map $_->isa( "VCP::Filter" ) ? $_->filter_name : ref $_,
      @{$self->{PLUGINS}};

   {
      my $dest = $self->{PLUGINS}->[-1];
      for ( reverse @{$self->{PLUGINS}}[0..$#{$self->{PLUGINS}} -1] ) {
         $_->dest( $dest );
         $dest = $_;
      }
   }

   local $VCP::vcp = $self;  ## for debugging dumps

   my $s = $self->{PLUGINS}->[0];
   my $ok = eval {
      $s->handle_header( $header ) ;
      $s->copy_revs() ;
      $s->handle_footer( $footer ) ;
      1;
   };

   if ( ! $ok ) {
      my $x = $@;
      VCP::Logger::_interrupt_progress();
      die $x;
   }


   ## Removing this link allows the dest to be cleaned up earlier by perl,
   ## which keeps VCP::RefCountedFile from complaining about undeleted revs.
   $s->dest( undef ) ;

   return ;
}


=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
