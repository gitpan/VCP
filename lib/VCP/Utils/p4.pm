package VCP::Utils::p4 ;

=head1 NAME

VCP::Utils::p4 - utilities for dealing with the p4 command

=head1 SYNOPSIS

   use VCP::Utils::p4 qw( :all ) ;

=head1 DESCRIPTION

A mix-in class providing methods shared by VCP::Source::p4 and VCP::Dest::p4,
mostly wrappers for calling the p4 command.

=cut

use strict ;

use Carp ;
use VCP::Debug qw( debug debugging ) ;
use File::Spec ;
use File::Temp qw( mktemp ) ;
use POSIX ':sys_wait_h' ;

=head1 METHODS

=item repo_client

The p4 client name. This is an accessor for a data member in each class.
The data member should be part of VCP::Utils::p4, but the fields pragma
does not support multiple inheritance, so the accessor is here but all
derived classes supporting this accessor must provide for a key named
"P4_REPO_CLIENT".

=cut

sub repo_client {
   my $self = shift ;

   $self->{P4_REPO_CLIENT} = shift if @_ ;
   return $self->{P4_REPO_CLIENT} ;
}


=item p4

Calls the p4 command with the appropriate user, client, port, and password.

=cut

sub p4 {
   my $self = shift ;

   local $ENV{P4PASSWD} = $self->repo_password if defined $self->repo_password ;
   unshift @{$_[0]}, '-p', $self->repo_server  if defined $self->repo_server ;
   unshift @{$_[0]}, '-c', $self->repo_client  if defined $self->repo_client ;
   unshift @{$_[0]}, '-u', $self->repo_user    if defined $self->repo_user ;

   ## TODO: Specify an empty 

   ## localizing this was giving me some grief.  Can't recall what.
   ## PWD must be cleared because, unlike all other Unix utilities I
   ## know of, p4 looks at it and bases it's path calculations on it.
   my $tmp = $ENV{PWD} ;
   delete $ENV{PWD} ;

   my $args = shift ;

   $self->run_safely( [ "p4", @$args ], @_ ) ;
   $ENV{PWD} = $tmp if defined $tmp ;
}


=item parse_p4_repo_spec

Calls $self->parse_repo_spec, the post-processes the repo_user in to a user
name and a client view. If the user specified no client name, then a client
name of "vcp_tmp_$$" is used by default.

This also initializes the client to have a mapping to a working directory
under /tmp, and arranges for the current client definition to be restored
or deleted on exit.

=cut

sub parse_p4_repo_spec {
   my $self = shift ;
   my ( $spec ) = @_ ;

   my $parsed_spec = $self->parse_repo_spec( $spec ) ;

   my ( $user, $client ) ;
   ( $user, $client ) = $self->repo_user =~ m/([^()]*)(?:\((.*)\))?/
      if defined $self->repo_user ;
   $client = "vcp_tmp_$$" unless defined $client && length $client ;

   $self->repo_user( $user ) ;
   $self->repo_client( $client ) ;

   my $client_exists = grep $_ eq $client, $self->p4_clients ;
   debug "p4: client '$client' exists" if $client_exists && debugging $self ;

   my $client_spec = $self->p4_get_client_spec ;

   $self->queue_p4_restore_client_spec( $client_exists ? $client_spec : undef );

   my $p4_spec = $parsed_spec->{FILES} ;
   $p4_spec =~ s{(/(\.\.\.)?)?$}{/...} ;
   my $work_dir = $self->work_root ;

   $client_spec =~ s(^Root.*)(Root:\t$work_dir)m ;
   $client_spec =~ s(^View.*)(View:\n\t$p4_spec\t//$client/...\n)ms ;

   $self->p4_set_client_spec( $client_spec ) ;

   debug "p4: using client spec", $client_spec if debugging $self ;

   return $parsed_spec ;
}

=item p4_clients

Returns a list of known clients.

=cut

sub p4_clients {
   my $self = shift ;

   my $clients ;
   $self->p4( [ "clients", ], ">", \$clients ) ;
   return map { /^Client (\S*)/ ; $1 } split /\n/m, $clients ;
}

=item p4_get_client_spec

Returns the current client spec for the named client. The client may or may not
exist first, grep the results from L</p4_clients> to see if it already exists.

=cut

sub p4_get_client_spec {
   my $self = shift ;
   my $client_spec ;
   $self->p4( [ "client", "-o" ], ">", \$client_spec ) ;
   return $client_spec ;
}


=item queue_p4_restore_client_spec

   $self->queue_p4_restore_client_spec( $client_spec ) ;

Saves a copy of the named p4 client and arranges for it's restoral on exit
(assuming END blocks run). Used when altering a user-specified client that
already exists.

If $client_spec is undefined, then the named client will be deleted on
exit.

Note that END blocks may be skipped in certain cases, like coredumps,
kill -9, or a call to POSIX::exit().  None of these should happen except
in debugging, but...

=cut

my @client_backups ;

END {
   for ( @client_backups ) {
      my ( $object, $name, $spec ) = @$_ ;
      my $tmp_name = $object->repo_client ;
      $object->repo_client( $name ) ;
      if ( defined $spec ) {
	 $object->p4_set_client_spec( $spec ) ;
      }
      else {
         $object->p4( [ "client", "-d", $object->repo_client ] ) ;
      }
      $object->repo_client( $tmp_name ) ;
      $_ = undef ;
   }
   @client_backups = () ;
}


sub queue_p4_restore_client_spec {
   my $self = shift ;
   my ( $client_spec ) = @_ ;
   push @client_backups, [ $self, $self->repo_client, $client_spec ] ;
}

=item p4_set_client_spec

   $self->p4_set_client_spec( $client_spec ) ;

Writes a client spec to the repository.

=cut


sub p4_set_client_spec {
   my $self = shift ;
   my ( $client_spec ) = @_ ;
   $self->p4( [ "client", "-i" ], "<", \$client_spec ) ;
}


=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
