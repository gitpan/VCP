package VCP::Source ;

=head1 NAME

VCP::Source - A base class for repository sources

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 EXTERNAL METHODS

=over

=cut

use strict ;

use Carp ;
use Regexp::Shellish qw( compile_shellish ) ;
use Time::Local qw( timelocal ) ;
use UNIVERSAL qw( isa ) ;
use VCP::Debug qw( :debug ) ;

use vars qw( $VERSION $debug ) ;

$VERSION = 0.1 ;

$debug = 0 ;

use base 'VCP::Plugin' ;

use fields (
   'BOOTSTRAP_REGEXPS', ## Determines what files are in bootstrap mode.
   'DEST',
   'REVS',              ## A convenience for the child.
) ;


=item new

Creates an instance, see subclasses for options.  The options passed are
usually native command-line options for the underlying repository's
client.  These are usually parsed and, perhaps, checked for validity
by calling the underlying command line.

=cut

sub new {
   my $class = shift ;
   $class = ref $class || $class ;

   my VCP::Source $self = $class->SUPER::new( @_ ) ;

   $self->{BOOTSTRAP_REGEXPS} = [] ;
   $self->{REVS} = VCP::Revs->new ;

   return $self ;
}


###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.  See L<VCP::Plugin> for methods
often needed in subclasses.

=head2 Subclass utility API

=over

=item dest

Sets/Gets a reference to the VCP::Dest object.  The source uses this to
call handle_header(), handle_rev(), and handle_end() methods.

=cut

sub dest {
   my VCP::Source $self = shift ;

   $self->{DEST} = shift if @_ ;
   return $self->{DEST} ;
}

=back

=head1 SUBCLASS OVERLOADS

These methods should be overridded in any subclasses.

=over

=item dest_expected

Returns TRUE if a destination is expected given the parameters passed
to new().

Some sources can have configuration options that cause side effects.
The only one that does this so far is the revml source, which can
output the RevML doctype as a .pm file.

=cut

sub dest_expected {
   return 1 ;
}


=item copy

REQUIRED OVERLOAD.

   $source->copy_revs() ;

Called by L<VCP/copy> to do the entire export process.  This is passed a
partially filled-in header structure.

The subclass should call

   $self->dest->handle_rev( $rev_meta ) ;

The subclass needs to make sure the $rev_meta hash contains the metadata for
the file and a work_path that points to the work location of the
file:

   $rev_meta = VCP::Rev->new(
      work_path  => '/tmp/revex/4/depot/perl/perl.c',
      name       => 'depot/perl/perl.c',
      rev_id     => '4',
      change_id  => '22',
      labels     => [ 'v0_003', 'v0_004' ],
   ) ;

=cut

sub copy_revs {
   my VCP::Source $self = shift ;

   confess "ERROR: copy_revs not overloaded by class '",
      ref $self, "'.  Oops.\n" ;
}


=item handle_header

REQUIRED OVERLOAD.

Subclasses must add all repository-specific info to the $header, at least
including rep_type and rep_desc.

   $header->{rep_type} => 'p4',
   $self->p4( ['info'], \$header->{rep_desc} ) ;

The subclass must call the superclass method to pass the $header on to
the dest:

   $self->SUPER::handle_header( $header ) ;

=cut

sub handle_header {
   my VCP::Source $self = shift ;

   my ( $header ) = @_ ;

   confess "ERROR: copy not overloaded by class '", ref $self, "'.  Oops.\n"
      if $self->can( 'handle_header' ) eq \&handle_header ;

   $self->dest->handle_header( $header ) ;
}


=item handle_footer

Not a required overload, as the footer carries no useful information at
this time.  Overriding methods must call this method to pass the
$footer on:

   $self->SUPER::handle_footer( $footer ) ;

=cut

sub handle_footer {
   my VCP::Source $self = shift ;

   my ( $footer ) = @_ ;

   $self->dest->handle_footer( $footer ) ;
}


=item parse_time

   $time = $self->parse_time( $timestr ) ;

Parses "[cc]YY/MM/DD[ HH[:MM[:SS]]]".

Will add ability to use format strings in future.
HH, MM, and SS are assumed to be 0 if not present.

Returns a time suitable for feeding to localtime or gmtime.

Assumes local system time, so no good for parsing times in revml, but that's
not a common thing to need to do, so it's in VCP::Source::revml.pm.

=cut

sub parse_time {
   my VCP::Source $self = shift ;
   my ( $timestr ) = @_ ;

   ## TODO: Get parser context here & give file, line, and column. filename
   ## and rev, while we're scheduling more work for the future.
   confess "Malformed time value $timestr\n"
      unless $timestr =~ /^(\d\d)?\d\d(\D\d\d){2,5}/ ;
   my @f = split( /\D/, $timestr ) ;
   --$f[1] ; # Month of year needs to be 0..11
   push @f, ( 0 ) x ( 6 - @f ) ;
   return timelocal( reverse @f ) ;
}


=item revs

   $self->revs( VCP::Revs->new ) ;
   $self->revs->add( $r ) ; # Many times
   $self->dest->sort_revs( $self->revs ) ;
   my VCP::Rev $r ;
   while ( $r = $self->revs->pop ) {
      ## ...checkout the source reve & set $r->work_path() to refer to it's loc.
      $self->dest->handle_rev( $r ) ;
   }

Sets/gets the revisions member.  This is used by most sources to accumulate
the set of revisions to be copied.

This member should be set by the child in copy_revs().  It should then be
passed to the destination

=cut

sub revs {
   my VCP::Source $self = shift ;

   $self->{REVS} = $_[0] if @_ ;
   return $self->{REVS} ;
}


=item bootstrap

Usually called from within call to GetOptions in subclass' new():

   GetOptions(
      'b|bootstrap:s'   => sub {
	 my ( $name, $val ) = @_ ;
	 $self->bootstrap( $val ) ;
      },
      'r|rev-root'      => \$rev_root,
      ) or $self->usage_and_exit ;

Can be called plain:

   $self->bootstrap( $bootstrap_spec ) ;

See the command line documentation for the format of $bootstrap_spec.

Returns nothing useful, but L</bootstrap_regexps> does.

=cut

sub bootstrap {
   my VCP::Source $self = shift ;
   my ( $val ) = @_ ;
   $self->{BOOTSTRAP_REGEXPS} = $val eq ''
      ? [ compile_shellish( '**' ) ]
      : [ map compile_shellish( $_ ), split /,+/, $val ] ;

   return ;
}


#=item bootstrap_regexps
#
#   $self->bootstrap_regexps( $re1, $re1, ... ) ;
#   $self->bootstrap_regexps( undef ) ; ## clears the list
#   @res = $self->bootstrap_regexps ;
#
#Sets/gets the list of regular expressions defining what files are in bootstrap
#mode.  This is usually set by L</bootstrap>, though.
#
#=cut
#
#sub bootstrap_regexps {
#   my VCP::Source $self = shift ;
#   $self->{BOOTSTRAP_REGEXPS} = [ @_ == 1 && ! defined $_[0] ? () : @_ ]
#      if @_ ;
#   return @{$self->{BOOTSTRAP_REGEXPS}} ;
#}
#
=item is_bootstrap_mode

   ... if $self->is_bootstrap_mode( $file ) ;

Compares the filename passed in against the list of bootstrap regular
expressions set by L</bootstrap>.

The file should be in a format similar to the command line spec for
whatever repository is passed in, and not relative to rev_root, so
"//depot/foo/bar" for p4, or "module/foo/bar" for cvs.

This is typically called in the subbase class only after looking at the
revision number to see if it's a first revision (in which case the
subclass should automatically put it in bootstrap mode).

=cut

sub is_bootstrap_mode {
   my VCP::Source $self = shift ;
   my ( $file ) = @_ ;

   my $result = grep $file =~ $_, @{$self->{BOOTSTRAP_REGEXPS}} ;

   debug (
      "vcp: $file ",
      ( $result ? "=~ " : "!~ " ),
      "[ ", join( ', ', map "qr/$_/", @{$self->{BOOTSTRAP_REGEXPS}} ), " ] (",
      ( $result ? "not in " : "in " ),
      "bootstrap mode)"
   ) if debugging $self ;

   return $result ;
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
