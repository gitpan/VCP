package VCP::Dest::null;

=head1 NAME

VCP::Dest::null - null destination driver

=head1 SYNOPSIS

   vcp <source> null:
   vcp <source> null:

=head1 DESCRIPTION

Behaves like a normal destination but generates no output.

=cut

$VERSION = 1 ;

@ISA = qw( VCP::Dest );

use strict ;

use Carp ;
use File::Basename ;
use File::Path ;
use VCP::Debug ':debug' ;
use VCP::Dest;
use VCP::Logger qw( lg pr_doing );
use VCP::Rev ;

#use base qw( VCP::Dest );
#use fields (
#   'NULL_GET_REVS',  ## 0 => don't actually fetch the revs, otherwise do.
#);

sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   die "vcp: the null source takes no spec ('$1')\n"
      if defined $spec && $spec =~ m{\Anull:(.+)}i;

   $self->repo_id( "null" );
   $self->parse_repo_spec( $spec ) if defined $spec;
   $self->parse_options( $options );

   return $self;
}


sub options_spec {
   my $self = shift;
   return (
      $self->SUPER::options_spec,
      "dont-get-revs"   => sub { $self->{NULL_GET_REVS} = 0 },
   );
}


sub handle_rev {
   my $self = shift;
   my ( $r ) = @_;

   debug "got ", $r->as_string if debugging;

   $r->get_source_file
      if (
         ! defined $self->{NULL_GET_REVS}
         || $self->{NULL_GET_REVS}
      ) && (
            $r->is_base_rev
            || (
               ! $r->is_placeholder_rev
               && $r->action ne "delete"
            )
         );

   pr_doing;
}


=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
