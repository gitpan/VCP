package VCP::ConfigFileUtils;

=head1 NAME

VCP::ConfigFileUtils - utilities used to parse or create vcp config files

=head1 SYNOPSIS

   use VCP::ConfigFileUtils qw( parse_config_file write_config_file );

=head1 DESCRIPTION

=cut

@EXPORT_OK = qw(
   config_file_quote
   parse_config_file
   write_config_file
);

@ISA = qw( Exporter );
use Exporter;

use strict;

use VCP::Debug qw( :debug );
use VCP::Logger qw( pr );
use VCP::Utils qw( start_dir_rel2abs );

=head1 FUNCTIONS

=over

=item config_file_quote

Adds quotation marks if a config file entry needs to be quoted.

LIMITATION: does not escape quotes in a string, can't figure out how to
do that for p4.

=cut

sub config_file_quote {
   my @parms = ref $_[0] eq "ARRAY" ? @{$_[0]} : @_;

   return join " ", map {
      defined $_
         ? m{\s}
             ? qq{"$_"}
             : $_
         : "(((undef)))";
   } @parms;
}

=item parse_config_file

   parse_config_file( $fn );
   parse_config_file( $fn, $may_not_be_a_config_file );

Reads a configuration file and returns a list of
(section name, \@section_tokens).

=cut

sub parse_config_file {
   ## NOTE: This should *not* be used to sniff files from STDIN because
   ## they can be huge and we don't have a mechanism that allows us to
   ## read a chunk, make a decision, then relace the chunk for the XML
   ## parser if it looks like revml.  Thus, if it comes on STDIN, the
   ## config file must be specced with a "vcp:-" CLI param.
   my ( $fn, $may_not_be_a_config_file ) = @_;

   my $source_desc = $fn eq "-" ? "stdin" : $fn;

   $fn = start_dir_rel2abs $fn unless $fn eq "-";

   $may_not_be_a_config_file = 0 if $fn =~ /\.vcp\z/i;

   pr "vcp: reading config from $source_desc\n"
       unless $may_not_be_a_config_file;

   if ( $fn eq "-" ) {
      ## Note: this can only occur if vcp:- was specified, not
      ## if "-" was specified (see the $arg ne "-" above).
      *VCPSPECFILE = \*STDIN;
   }
   else {
      open VCPSPECFILE, "<$fn" or die "$!: $fn\n";
   }

   my $vcp = "";
   my $c;
   do {
      $c = read VCPSPECFILE, $vcp, 1_000_000, length $vcp;
      die "$! while reading $fn\n"
         unless defined $c;
   } while ( $c );

   close VCPSPECFILE;

   die "IS REVML FILE\n"
      if $may_not_be_a_config_file && $vcp =~ m{<revml[^>]*>.*</revml>}m;

   pr "vcp: reading config from $source_desc\n"
       if $may_not_be_a_config_file;

   require VCP::Utils::p4;
   my @vcp_spec = VCP::Utils::p4->parse_p4_form( $vcp );
   undef $vcp;

   require Text::ParseWords;
   my @out;

   ## The Options and Dest/Destination tags are special: Options must come
   ## first and Dest must come last.
   my $options_value;
   my $dest_value;
   while ( @vcp_spec ) {
      my ( $tag, $value ) = ( lc shift @vcp_spec, shift @vcp_spec );
      for ( $value ) {
         s/\A\s+//;
         s/\s+\z//;
      }

      ## use quotewords and tell it to keep the backslashes
      ## because backslashes are important on Win32.
      $value = [ map {
             s{^(['"]?)(.*)\1}{$2};
             $_;
         } Text::ParseWords::quotewords( '\s+', 1, $value )
      ];

      if ( $tag eq "options" ) {
         die "vcp: two Options entries found in config file\n"
            if $options_value;
         $options_value = $value;
      }
      elsif ( $tag eq "dest" || $tag eq "destination" ) {
         die "vcp: two Destination entries found in config file\n"
            if $dest_value;
         $dest_value = $value;
      }
      elsif ( $tag eq "source" && @out ) {
         die "vcp: Source must come before filter sections in config file\n";
      }
      else {
         push @out, $tag, $value;
      }
   }
   unshift @out, "options", $options_value if $options_value;
   push    @out, "dest", $dest_value       if $dest_value;

   if ( debugging ) {
      require Data::Dumper;
      debug( Data::Dumper->Dump( [ \@out ], [ $source_desc ] ) );
   }

   return \@out;
}

=item write_config_file

   write_config_file( $filename, @plugins );

=cut

sub write_config_file {
   my ( $fn, @plugins ) = @_;

   $fn = start_dir_rel2abs $fn unless $fn eq "-";

   pr "vcp: writing config file to $fn\n";

   open CONFIG_FILE, ">$fn" or die "$!: $fn\n";
   ## Put dest after source.
   if ( @plugins > 2 && $plugins[-1]->isa( "VCP::Dest" ) ) {
      my $dest = pop @plugins;
      splice @plugins, 1, 0, $dest;
   }
   for ( @plugins ) {
      print CONFIG_FILE $_->config_file_section_as_string
         or die "$!: $fn\n";
   }
   close CONFIG_FILE or die "$!: $fn\n";
}

=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
