package VCP::TestUtils ;

=head1 NAME

VCP::TestUtils - support routines for VCP testing

=cut

use Exporter ;

@EXPORT = qw( p4_options launch_p4d init_p4_client p4d_borken ) ;
@ISA = qw( Exporter ) ;

use strict ;

use Carp ;
use File::Spec ;
use POSIX ':sys_wait_h' ;


sub p4_options {
   my $prefix = shift || "" ;
   my $tmp = File::Spec->tmpdir ;
   return {
      repo    =>    File::Spec->catdir( $tmp, "${prefix}p4repo" ),
      work    =>    File::Spec->catdir( $tmp, "${prefix}p4work" ),
      user    =>    "${prefix}t_user",
#      client  =>    "${prefix}t_client",
      port    =>    19666,
   } ;
}


sub p4d_borken {
   my $p4dV = `p4d -V` || 0 ;
   return "p4d not found" unless $p4dV ;

   my ( $p4d_version ) = $p4dV =~ m{^Rev[^/]*/[^/]*/([^/]*)}m ;

   my $min_version = 99.2 ;
   return "p4d version too old, need at least $min_version"
       unless $p4d_version >= $min_version ;
   return "" ;
}

sub launch_p4d {
   my $options = pop ;
   croak "No options passed" unless $options && %$options ;
   {
      my $borken = p4d_borken ;
      croak $borken if $borken ;
   }
   ## Ok, this is wierd: we need to fork & run p4d in foreground mode so that
   ## we can capture it's PID and kill it later.  There doesn't seem to be
   ## the equivalent of a 'p4d.pid' file. If we let it daemonize, then I
   ## don't know how to get it's PID.
   my $p4d_pid = fork ;
   unless ( $p4d_pid ) {
      ## Ok, there's a tiny chance that this will fail due to a port
      ## collision.  Oh, well.
      exec 'p4d', '-f', '-r', $options->{repo}, '-p', $options->{port} ;
      die "$!: p4d" ;
   }
   sleep 1 ;
   ## Wait for p4d to start.  'twould be better to wait for P4PORT to
   ## be seen.
   select( undef, undef, undef, 0.250 ) ;
   END {
      return unless defined $p4d_pid ;
      kill 'INT',  $p4d_pid or die "$! $p4d_pid" ;
      my $t0 = time ;
      my $dead_child ;
      while ( $t0 + 15 > time ) {
         select undef, undef, undef, 0.250 ;
	 $dead_child = waitpid $p4d_pid, WNOHANG ;
	 warn "$!: $p4d_pid" if $dead_child == -1 ;
	 last if $dead_child ;
      }
      unless ( defined $dead_child && $dead_child > 0 ) {
	 print "terminating $p4d_pid\n" ;
	 kill 'TERM', $p4d_pid or die "$! $p4d_pid" ;
	 $t0 = time ;
	 while ( $t0 + 15 > time ) {
	    select undef, undef, undef, 0.250 ;
	    $dead_child = waitpid $p4d_pid, WNOHANG ;
	    warn "$!: $p4d_pid" if $dead_child == -1 ;
	    last if $dead_child ;
	 }
      }
      unless ( defined $dead_child && $dead_child > 0 ) {
	 print "killing $p4d_pid\n" ;
	 kill 'KILL', $p4d_pid or die "$! $p4d_pid" ;
      }
   }
}


#sub init_p4_client {
#   my $options = pop ;
#   croak "No options passed" unless $options && %$options ;
#   my $p4 = "p4 -c $options->{client} -u $options->{user} -p $options->{port}" ;
#   my $client_desc = `$p4 client -o` ;
#   die "$! running $p4 client -o\n" unless defined $client_desc ;
#   die "$p4 client -o returned ", $? >> 8, "\n" if $? ;
#   $client_desc =~ s(^Root.*)(Root:\t$options->{work})m ;
#   $client_desc =~ s(^View.*)(View:\n\t//depot/...\t//$options->{client}/...\n)ms ;
#   open( P4,
#      "| $p4 client -i"
#   ) or die "$! $p4 client -i" ;
#   print P4 $client_desc ;
#   unless ( close P4 ) {
#      die "$p4 client -i returned $?" if $! eq "0" ;
#      die qq{$! closing "| p4 client -i"} ;
#   }
#}

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
