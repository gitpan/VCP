package VCP::Plugin ;

=head1 NAME

VCP::Plugin - A base class for VCP::Source and VCP::Dest

=head1 SYNOPSIS

   use VCP::Plugin;
   @ISA = qw( VCP::Plugin );
   ...

=head1 DESCRIPTION

Some functionality is common to sources and destinations, such as cache
access, help text generation , command-line access shortcut member, etc.

=head1 EXTERNAL METHODS

=over

=cut

$VERSION = 0.1 ;

use strict ;

use File::Basename ;
use File::Path qw( mkpath rmtree );
use File::Spec;

use VCP::Logger qw( lg pr BUG );
use VCP::Revs;
use VCP::Utils qw(
   is_win32
   shell_quote
   xchdir
   start_dir
);

#use fields (
#   'REVS',          ## Any revisions we need to work with
#);

=item new

Creates an instance, see subclasses for options.  The options passed are
usually native command-line options for the underlying repository's
client.  These are usually parsed and, perhaps, checked for validity
by calling the underlying command line.

=cut

sub new {
   my $class = shift;
   return bless {}, $class;
}


=item plugin_documentation

   $text = $p->plugin_documentation;

Returns the text of the DESCRIPTION section of a module's .pm as contained in
VCP::Help.  The DESCRIPTION returned is determined by $self.

=cut

sub plugin_documentation {
   my $self = shift;

   require VCP::Help;
   return VCP::Help->get( ref( $self ) . " description" );
}


sub _reformat_docs_as_comments {
   ## This is used to convert help topics to inline comments for
   ## config files.
   my $self = shift;
   my $text = join "", @_;

   1 while chomp $text;
   $text =~ s/^/        ## /mg;
   return "$text\n";
}


=back

=cut


###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=head2 SUBCLASS API

These methods are intended to support subclasses.

=over


=item init

This is called after new() and before processing.  No attempt to connect
to or open a repository or database file should be made until init() is
called (ie not in new()).

=cut

sub init {
}


=item usage_and_exit

   GetOptions( ... ) or $self->usage_and_exit ;

Used by subclasses to die if unknown options are passed in.

=cut

sub usage_and_exit {
   my $self = shift ;

   lg "options error emitted to STDERR for ", ref $self;

   require VCP::Help;
   print "\n";
   VCP::Help->error( ref( $self ) . " usage" );
   exit 2;
}


=item tmp_dir

Returns the temporary directory this plugin should use, usually something
like "/tmp/vcp123/dest-p4".

=cut

my @END_subs;

=item queue_END_sub

In order to provide ordered destruction and cleanup at application shutdown,
plugins can queue up code to run before all directories are deleted.

=cut

sub queue_END_sub {
   my $self = shift;

   BUG "more than one sub passed to queue_END_sub" if @_ > 1;
   my ( $sub ) = @_;
   BUG "non-CODE ref passed to queue_END_sub" if ref $sub ne "CODE";

   push @END_subs, $sub;
}


sub cancel_END_sub {
   my $self = shift;

   BUG "more than one sub passed to cancel_END_sub" if @_ > 1;
   my ( $sub ) = @_;
   BUG "non-CODE ref passed to cancel_END_sub" if ref $sub ne "CODE";

   @END_subs = grep $_ ne $sub, @_;
}


my %tmp_dirs ;

END {
   return unless keys %tmp_dirs;
   xchdir "/" if is_win32; ## WinNT can't delete out from
                           ## under cwd.
   for ( @END_subs ) {
      eval { $_->(); 1 }
         or pr "cleanup error: $@";
   }

   rmtree [ reverse sort { length $a <=> length $b } keys %tmp_dirs ]
      if ! $ENV{VCPNODELETE} && %tmp_dirs ;
}

sub tmp_dir {
   my $self = shift ;
   my $plugin_dir = ref $self ;
   $plugin_dir =~ tr/A-Z/a-z/ ;
   $plugin_dir =~ s/^VCP:://i ;
   $plugin_dir =~ s/::/-/g ;
   my $tmp_dir_root = File::Spec->catdir( start_dir, "tmp", "vcp$$" ) ;

   ## Make sure no old tmpdir is there to mess us up in case
   ## a previous run crashed before cleanup or $ENV{VCPNODELETE} is set.
   if ( ! $tmp_dirs{$tmp_dir_root} && -e $tmp_dir_root ) {
      pr "removing previous working directory $tmp_dir_root";
      rmtree [$tmp_dir_root ], 0;
   }

   $tmp_dirs{$tmp_dir_root} = 1 ;
   return File::Spec->catdir( $tmp_dir_root, $plugin_dir, @_ ) ;
}


=item mkdir

   $self->mkdir( $filename ) ;
   $self->mkdir( $filename, $mode ) ;

Makes a directory and any necessary parent directories.

The default mode is 770.  Does some debug logging if any directories are
created.

Returns nothing.

=cut

sub mkdir {
   my $self = shift ;

   my ( $path, $mode ) = @_ ;

   BUG "undefined \$path" unless defined $path;
   BUG "empty \$path" unless length  $path;

   $path =~ s{/+$}{};  ## Let *BSD and other POSIXly correct system work

   unless ( -d $path ) {
      $mode = 0770 unless defined $mode ;
      lg "\$ ", shell_quote "mkdir", sprintf( "--mode=%04o", $mode ), $path;
      eval { mkpath [ $path ], 0, $mode }
         or die "failed to create $path with mode $mode: $@\n" ;
   }

   return ;
}


=item mkpdir

   $self->mkpdir( $filename ) ;
   $self->mkpdir( $filename, $mode ) ;

Makes the parent directory of a filename and all directories down to it.

The default mode is 770.  Does some debug logging if any directories are
created.

Returns the path of the parent directory.

=cut

sub mkpdir {
   my $self = shift ;

   my ( $path, $mode ) = @_ ;

   my ( undef, $dir ) = fileparse $path;

   $self->mkdir( $dir, $mode ) ;

   return $dir ;
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
