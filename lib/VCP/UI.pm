package VCP::UI ;

=head1 NAME

VCP::UI - User interface framework for interactive mode VCP.

=head1 SYNOPSIS

    $ vcp

=head1 DESCRIPTION

When VCP is run with no source or destination specifications, it loads
and launches an interactive user interface.

The current default is a text user interface, but this may change
to be a graphical UI on some platforms in the future.

UI.pm is a UI manager for UI::Machines and front-end implementations
like UI::Text.  These do not derive from UI, they are managed by UI.

TODO: Rename UI.pm to UIManager.pm, then factor stuff out of UI::Text
into a new UI.pm.

=head1 METHODS

=over

=cut

$VERSION = 0.1 ;

use strict ;

=item new

   my $ui = VCP::UI->new;

=cut

sub new {
   my $class = shift;
   return bless { @_ }, $class;
}

=item run

Runs the UI.  Selects the appropriate user interface (unless one has
been passed in) and runs it.

=cut

sub run {
    my $self = shift;

    $self->{UIImplementation} = "VCP::UI::Text"
        unless defined $self->{UIImplementation};

    unless ( ref $self->{UIImplementation} ) {
        eval "require $self->{UIImplementation}" or die "$@ loading $self->{UIImplementation}";
    }

    $self->{UIImplementation}->new( UIManager => $self, @_ )->run;
}


=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP::UI package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
