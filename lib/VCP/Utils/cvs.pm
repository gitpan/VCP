package VCP::Utils::cvs ;

=head1 NAME

VCP::Utils::cvs - utilities for dealing with the cvs command

=head1 SYNOPSIS

   use VCP::Utils::cvs ;

=head1 DESCRIPTION

A mix-in class providing methods shared by VCP::Source::cvs and VCP::Dest::cvs,
mostly wrappers for calling the cvs command.

=cut

use strict ;

use Carp ;
use VCP::Debug qw( debug debugging ) ;
use File::Spec ;
use File::Temp qw( mktemp ) ;
use POSIX ':sys_wait_h' ;

=head1 METHODS

=item cvs

Calls the cvs command with the appropriate cvsroot option.

=cut

sub cvs {
   my $self = shift ;

   my $args = shift ;

   unshift @$args, "-d" . $self->repo_server
      if defined $self->repo_server;

   return $self->run_safely( [ qw( cvs -Q -z9 ), @$args ], @_ ) ;
}


sub create_cvs_workspace {
   my $self = shift ;

   confess "Can't create_workspace twice" unless $self->none_seen ;

   ## establish_workspace in a directory named "co" for "checkout". This is
   ## so that VCP::Source::cvs can use a different directory to contain
   ## the revs, since all the revs need to be kept around until the VCP::Dest
   ## is through with them.
   $self->command_chdir( $self->tmp_dir( "co" ) ) ;
   $self->cvs( [ 'checkout', $self->rev_root ] ) ;
   $self->work_root( $self->tmp_dir( "co", $self->rev_root ) ) ;
   $self->command_chdir( $self->work_path ) ;
}


=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
