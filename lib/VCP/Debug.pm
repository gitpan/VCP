package VCP::Debug ;

=head1 NAME

VCP::Debug - debugging support for VCP

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 EXPORTS

The following functions may be exported: L</debug>, L</enable_debug>,
L</debugging>
L</disable_debug>, along with the tags ':all' and ':debug'.  Use the latter
to head off future namespace pollution in case :all gets expanded in the
future..

A warning will be emitted on program exit for any specs that aren't used,
to help you make sure that you are using sensible specs.

=over

=cut

use strict ;
use vars qw( $VERSION @ISA @EXPORT_OK %EXPORT_TAGS ) ;
use Exporter ;

@ISA = qw( Exporter ) ;
@EXPORT_OK = qw(
   debug
   enable_debug
   disable_debug
   debugging
   explicitly_debugging
) ;
%EXPORT_TAGS = (
   'all'   => \@EXPORT_OK,
   'debug' => \@EXPORT_OK,
) ;

$VERSION = 0.1 ;

# TODO:
#=item use
#=item import
#
#In addition to all of the routines and tags that C<use> and C<import> normally
#take (see above), you may also pass in pairwise debugging definitions like
#so:
#
#   use VCP::debug (
#      ":all",
#      DEBUGGING_FOO => "foo,bar",
#   ) ;
#
#Any all caps export import requests are created as subroutines that may well be
#optimized away at compile time if "enable_debugging" has not been called. This
#requires a conspiracy between the author of a module and the author of the main
#program to call enable_debugging I<before> C<use>ing any modules that leverage
#this feature, otherwise compile-time optimizations won't occur.
#

=item debug

   debug $foo if debugging $self ;

Emits a line of debugging (a "\n" will be appended).  Use debug_some
to avoid the "\n".  Any undefined parameters will be displayed as
C<E<lt>undefE<gt>>.

=cut

my $dump_undebugged ;
my $reported_specs ;
my @debug_specs ;
my %used_specs ;
my %debugging ;

END {
   $used_specs{'##NEVER_MATCH##'} = 1 ;
   my @unused = grep ! $used_specs{$_}, @debug_specs ;

   warn "vcp: Unused debug specs: ", join( ', ', map "/$_/", @unused ), "\n"
      if @unused ;

   if ( @unused || $dump_undebugged ) {
      my @undebugged = grep {
	 my $name = $_ ;
	 ! grep $name =~ /$_/i, keys %used_specs
      } map lc $_, sort keys %debugging ;

      if ( @undebugged ) {
	 warn "vcp: Undebugged things: ", join( ', ', @undebugged ), "\n" ;
      }
      else {
	 warn "vcp: No undebugged things\n" ;
      }
   }
}

sub debug {
   return unless @debug_specs ;
   if ( @_ ) {
      my $t = join( '', map defined $_ ? $_ : "<undef>", @_ ) ;
      if ( length $t ) {
	 print STDERR $t, substr( $t, -1 ) eq "\n" ? () : "\n" ;
      }
   }
}


sub debug_some {
   return unless @debug_specs ;
   print STDERR map defined $_ ? $_ : "<undef>", @_ if @_ ;
}


=item debugging

   debug "blah" if debugging ;

Returns TRUE if the caller's module is being debugged

   debug "blah" if debugging $self ;
   debug "blah" if debugging $other, $self ; ## ORs the arguments together

Returns TRUE if any of the arguments are being debugged.  Plain
strings can be passed or blessed references.

=cut

sub _report_specs {
   my @report = grep ! /##NEVER_MATCH##/, @debug_specs ;
   print STDERR "Debugging ",join( ', ', map "/$_/", @report ),"\n"
      if @report ;
   $reported_specs = 1 ;
}


sub debugging {
   return undef unless @debug_specs ;

   my $result ;
   my @missed ;
   for my $where ( @_ ? map ref $_ || $_, @_ : scalar caller ) {
      if ( ! exists $debugging{$where} ) {
# print STDERR "missed $where\n" ;
	 ## If this is the first miss, then these may not have been reported.
	 _report_specs unless $reported_specs ;

	 ## We go ahead and evaluate all specs instead of returning when the
	 ## first is found so that we can set $used_specs for all specs that
	 ## match.
	 $debugging{$where} = 0 ;
	 for my $spec ( @debug_specs ) {
	    next if $spec eq '##NEVER_MATCH##' ;
# print STDERR "   /$spec/:\n" ;
	    if ( $where =~ /$spec/i ) {
	       $debugging{$where} = 1 ;
	       $used_specs{$spec} = 1 ;
	       $result = 1 ;
	       ## no last: we want to build up %used_specs.  There
	       ## aren't usually many specs anyway.
	    }
	    else {
# print STDERR "   ! /$spec/\n" ;
            }
	 }
      }
# print STDERR "$where ", $debugging{$where} ? 'yes' : 'no', "\n" ;
      return 1 if $debugging{$where} ;
   }

   return $result ;
}

=item explicitly_debugging

   debug "blah" if explicitly_debugging ;

Returns TRUE if the caller's module is being debugged by a literal match
instead of a pattern match.  This is used when debugging output would normally
be congested with too much crap from a particular subsystem when using a
wildcard debug spec (like ".*"), but you want the ability to turn on debugging
for that subsystem:

   debug "blah" if explicitly_debugging "VCP::Dest::sort" ;

requires an explicit C<VCP::Dest::sort> to be given in the debug specs.

   debug "blah" if explicitly_debugging $self ;
   debug "blah" if explicitly_debugging $other, $self ; ## ORs the args

Returns TRUE if any of the arguments are being debugged.  Plain
strings can be passed or blessed references.

=cut

my %explicitly_debugging ;

sub explicitly_debugging {
   return undef unless @debug_specs ;

   my $result ;
   my @missed ;
   for my $where ( @_ ? map ref $_ || $_, @_ : scalar caller ) {
      if ( ! exists $explicitly_debugging{$where} ) {
# print STDERR "missed $where\n" ;
	 ## If this is the first miss, then these may not have been reported.
	 _report_specs unless $reported_specs ;

	 ## We go ahead and evaluate all specs instead of returning when the
	 ## first is found so that we can set $used_specs for all specs that
	 ## match.
	 $explicitly_debugging{$where} = 0 ;
	 for my $spec ( @debug_specs ) {
	    next if $spec eq '##NEVER_MATCH##' ;
# print STDERR "   /$spec/:\n" ;
	    if ( lc $where eq lc $spec ) {
	       $explicitly_debugging{$where} = 1 ;
	       $used_specs{$spec} = 1 ;
	       $result = 1 ;
	       ## no last: we want to build up %used_specs.  There
	       ## aren't usually many specs anyway.
	    }
	    else {
# print STDERR "   ! /$spec/\n" ;
            }
	 }
      }
# print STDERR "$where ", $debugging{$where} ? 'yes' : 'no', "\n" ;
      return 1 if $explicitly_debugging{$where} ;
   }

   return $result ;
}

=item disable_debug

Disable all debugging.

=cut

sub disable_debug() {
   @debug_specs = () ;
   return ;
}

=item enable_debug

   enable_debug ;
   enable_debug( ...debug specs... ) ;

A debug spec is a regular expression that matches the name of a module.

=cut

sub enable_debug {
   my %specs = map { ( $_ => 1 ) } @debug_specs, @_ ;
   my @new_debug_specs = %specs 
      ? keys %specs 
      : qr/^/ ;
   _report_specs
      if $reported_specs && @debug_specs != @new_debug_specs ;
   @debug_specs = map(
      /^what$/i && ( $dump_undebugged = 1 ) ? '##NEVER_MATCH##' : $_,
      @new_debug_specs
   ) ;
   return ;
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
