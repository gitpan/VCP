package VCP::Filter ;

=head1 NAME

VCP::Filter - A base class for filters

=head1 SYNOPSIS

   use VCP::Filter;
   @ISA = qw( VCP::Filter );
   ...

=head1 DESCRIPTION

A VPC::Filter is a VCP::Plugin that is placed between the source
and the destination and allows the stream of revisions to be altered.

For instance, the Map: option in vcp files is implemented by
VCP::Filter::Map

By default a filter is a pass-through.

=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Plugin );

use strict;
use Carp ();
use VCP::ConfigFileUtils qw( config_file_quote );
use VCP::Debug qw( :debug );
use VCP::Logger qw( lg BUG );
use VCP::Plugin;
use VCP::Utils qw( empty );

#use base "VCP::Plugin";
#use fields (
#    'PRETTY_PRINTED_RULES_LIST_LINES',
#                          ## The list of rules that was parsed so that it
#                          ## may be regurgitated in to a config file
#    'DEST',   ## Points to the next filter.
#);

sub dest {
   my $self = shift;

   $self->{DEST} = shift if @_;
   return $self->{DEST};
}

###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=over

=item parse_rules_list

Used in VCP::Filter::*map and VCP::Filter::*edit to parse lists of rules
where every rule is a set of N "words".  The value of N is computed from
the number of labels passed in and the labels are used when printing an
error message:

    @rules = $self->parse_rules( $options, "Pattern", "Replacement" );

=cut

sub parse_rules_list {
   my $self = shift;
   my $options = shift;
   my $default = @_ && ref $_[-1] ? pop : [];

   my @labels  = @_;
   my $expression_count = @labels;
   BUG "No expression labels passed" unless $expression_count;
   BUG "No options " unless $options;

   my @rule;
   my $rules;
   while ( @$options ) {
      my $v = shift @$options;
      last if $v eq "--";
      
      push @rule, $v;
      push @$rules, [splice @rule] if @rule == $expression_count;
   }
   push @$rules, \@rule if @rule;

   $rules = $default unless $rules || @rule;

   ## Format pretty rules for the log, error messages, or later output
   ## to config file.
   my @out = map [
      map config_file_quote( $_ ), @$_
   ], @$rules;

   my @w;
   for ( \@labels, @out ) {
      for my $i (0..$#$_) {
         $w[$i] = length $_->[$i]
            if ! defined $w[$i] || length $_->[$i] > $w[$i];
      }
   }

   ( my $filter_type = ref $self ) =~ s/.*://;
   my $format = join " ", map "%-${_}s", @w;
   my @msg = (
      sprintf( "##  $format\n", @labels ),
      sprintf( "##  $format\n", map "=" x $_, @w ),
      map(
         sprintf( "    $format\n", map defined $_ ? $_ : "", @$_ ),
         @out
      )
   );

   die "incomplete rule in $filter_type:\n\n", @msg, "\n" if @rule;

   lg "$filter_type rules:\n", @msg;

   ## Take a copy in case the caller decides to alter the rules.
   $self->{PRETTY_PRINTED_RULES_LIST_LINES} = \@msg;

   return $rules;
}

=item filter_name

Returns the StudlyCaps version of the filter name.  By default, assumes
a single work name and uses ucfirst on it.  Filters like StringEdit should
overload this to be more creative and typgraphically appealing (heh).

=cut

sub filter_name {
   my $self = shift;

   my ( $filtername ) = ( ref( $self ) =~ /\AVCP::Filter::(\w+)\z/ )
      or BUG "Can't parse filter name from ", ref $self;

   return ucfirst $filtername;
}

=item sort_keys

   my @output_sort_order = $filter->sort_keys( @input_sort_order );

Accepts a list of sort keys from the upstream filter and returns a list
of sort keys representing the order that records will be emitted in.

This is a pass-through by default, but VCP::Filter::sort and VCP::Filter::changesets return appropriate values.

=cut

sub sort_keys {
   my $self = shift;
   return @_;
}

=item config_file_section_as_string

=cut

sub config_file_section_as_string {
   my $self = shift;

   require VCP::Help;

   my $section_name = $self->filter_name;
   my $plugin_docs  = $self->plugin_documentation;
 
   return join "",
      "$section_name:\n",
      $self->{PRETTY_PRINTED_RULES_LIST_LINES}
         ? map "        $_", @{$self->{PRETTY_PRINTED_RULES_LIST_LINES}}
         : (),
      !empty( $plugin_docs )
         ? $self->_reformat_docs_as_comments( $plugin_docs )
         : (),
      "\n";
}


=item last_rev_in_filebranch

(passthru; see L<VCP::Dest|VCP::Dest>)

=cut

sub last_rev_in_filebranch {
   shift->dest->last_rev_in_filebranch( @_ );
}

=item backfill

(passthru; see L<VCP::Dest|VCP::Dest>)

=cut

sub backfill {
   shift->dest->backfill( @_ );
}

=item handle_header

(passthru)

=cut

sub handle_header {
   shift->dest->handle_header( @_ );
}

=item rev_count

passthru, see VCP::Dest.

=cut

sub rev_count {
   shift->dest->rev_count( @_ );
}

=item handle_rev

passthru, see VCP::Dest.

=cut

sub handle_rev {
   shift->dest->handle_rev( @_ );
}

=item skip_rev

passthru, see VCP::Dest

=cut

sub skip_rev {
    shift->dest->skip_rev( @_ );
}

=item handle_footer

passthru, see VCP::Dest

=cut

sub handle_footer {
   shift->dest->handle_footer( @_ );
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
