package VCP::Utils;

=head1 NAME

VCP::Utils - utilities used within VCP's modules.

=head1 SYNOPSIS

   use VCP::Utils qw( shell_quote );

=head1 DESCRIPTION

A mix-in class providing methods shared by VCP::Source::cvs and VCP::Dest::cvs,
mostly wrappers for calling the cvs command.

=cut

@EXPORT_OK = qw(
   empty
   escape_filename
   is_win32
   program_name
   start_dir_rel2abs
   shell_quote
   start_dir
   xchdir
);

@ISA = qw( Exporter );
use Exporter;

use Cwd;
use strict;
use File::Spec;
use File::Basename qw( basename );
use VCP::Logger qw( lg program_name BUG );
use constant is_win32 => $^O =~ /Win32/;

my $start_dir;
BEGIN { $start_dir = cwd }

=head1 FUNCTIONS

=over

=item shell_quote

   my $line = shell_quote \@command;
   my $line = shell_quote @command;
   print STDERR, $line, "\n";

Selectively quotes the command line to allow it to be printed in a non-vague
fashion and to be pastable in the local shell (sh/bash on Unix, COMMAND.COM,
etc. on Win32 and OS2).

NOTE: May not be perfect; errs on the side of safety and doesn't try to
escape things right on Win32 yet.  Patches welcome.

=cut

{
   my $q;
   BEGIN { $q = is_win32 ? '"' : "'" };

   sub shell_quote {
      my @parms = ref $_[0] eq "ARRAY" ? @{$_[0]} : @_;

      return join " ", map {
         defined $_
            ? m{[^\w:/\\.,=\@-]}
                ? do {
                   ( my $s = $_ ) =~ s/([\\$q])/\\$1/;
                   "$q$s$q";
                }
                : $_
            : "(((undef)))";
      } @parms;
   }
}


=item empty

Determines if a scalar value is empty, that is
not defined or zero length.

=cut

sub empty($) { 
   return ! ( defined $_[0] && length $_[0] );
}


=item escape_filename

Escape a string so that it may be used as a filename.  Converts
characters other than "-", "_", and alphanumerics to %NN% escape
sequences where NN is the ordinal value (usually the ASCII value or
UTF-8 codepoint) of the character.

=cut

sub escape_filename {
   my ($s) = @_;
   BUG "usage: escape_filename <filename-to-escape>"
      if empty $s;

   $s =~ s/([^0-9a-zA-Z\-_])/sprintf '%%%d%%', ord $1/eg ;
   return $s;
}

=item start_dir_rel2abs

   start_dir_rel2abs( $fn );

If $fn is a relative path (according to File::Spec), converts it to an
absolute path using start_dir() as the base directory.

=cut

sub start_dir_rel2abs {
   BUG "start_dir_rel2abs() takes one and only one argument"
      unless @_ == 1;

   my $p = File::Spec->rel2abs( @_, $start_dir );
   return $p unless is_win32;
   $p =~ s{\\+}{/}g;
   return $p;
}

=item start_dir

Returns the directory that was current when VCP::Utils was parsed.

=cut

sub start_dir { $start_dir }


=item xchdir

Changes to a directory (unless we're already in that directory) and logs
the change.  Throws an exception on error.  Sets $ENV{PWD}.

You should use minimal canonical paths where possible so that $ENV{PWD}
is a simple path.  Some child processes might not like paths with
thisdir ("/./") or updir segments ("/../").

Relative paths are an error.

=cut

{
   my %abs_cache;
   my $cwd = start_dir;

   sub xchdir($) {
      my $to_dir = shift;
      return if $cwd eq $to_dir;

      BUG
         "can't chdir() to relative path '$to_dir'"
         unless $abs_cache{$to_dir}
            ||= File::Spec->file_name_is_absolute( $to_dir );

      lg "\$ ", shell_quote "chdir", $to_dir;
      chdir $to_dir or die "vcp: $!: $to_dir";

      ## Set $ENV{PWD} to tell the p4 command line where we are.
      ## Otherwise, on Win32, it (I guess) uses the OS to get the cwd
      ## and this causes it to get the *long* pathname, which is not under
      ## the client root if the long pathname differs from the tmpdir
      ## returned by File::Spec->tmpdir, which is the short pathname.
      $ENV{PWD} = $cwd = $ENV{CWD} = $to_dir;
   }
}

=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
