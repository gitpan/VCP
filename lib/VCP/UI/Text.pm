package VCP::UI::Text ;

=head1 NAME

VCP::UI::Text - A textual user interface for VCP.

=head1 SYNOPSIS

    $ vcp        ## VCP::UI::Text is the current default

=head1 DESCRIPTION

This is a text-only user interface for VCP.  It prints out descriptions,
prompts the user, reads the responses, and validates input.

This class is designed to be refactored and/or inherited from for
alternative user interfaces, like GUIs.

=head1 METHODS

=over

=for test_script 00uitext.t

=cut

$VERSION = 0.1 ;

use strict ;
use VCP::UIMachines;
use VCP::Debug qw( :debug );
use VCP::Utils qw( empty );

#use fields (
#   'Source',     ## reference to the source plugin object
#   'Dest',       ## reference to the destination plugin object
#   'UIManager',  ## The instance of VCP::UI that is managing us
#   'Run',        ## Whether or not to run a conversion when complete
#   'SaveAsConfigFileName',  ## if non-empty, what filename to save as
#   'EditMode',   ## Whether the current question is an edit or a new one
#   'Filename',   ## If this is a config file re-edit or not
#) ;


sub new {
   my $class = shift;
   return bless {@_}, $class;
}

=item new_source

    $ui->new_source( "vss", @_ );

Creates a new source if the current source is not of the indicated class.

Emits a warning when the source is changed from one type to another and
clears in_edit_mode().

=cut

sub new_source {
   my $self = shift;
   my $scheme = shift;
   my $class = "VCP::Source::$scheme";
   ## using ref/eq instead of isa so subclasses don't
   ## masquerade as superclasses by default
   unless ( $self->{Source} && ref $self->{Source} eq $class ) {
      $self->emit_note( "Clearing all settings for source." )
         if $self->{Source};
      eval "require $class" or die "Couldn't load $class";
      my $new_source = $class->new;
      $new_source->repo_id( $self->source_repo_id )
          unless empty $self->source_repo_id;
      $new_source->repo_scheme( $scheme );

      $self->{Source} = $new_source;
          ## setting $self->{Source} changes the behavior of source_repo_id,
          ## so do it last.

      $self->{EditMode} = 0;
    }
}

=item source_repo_id

Sets/gets the source id.  This is needed because we prompt for the source
name before knowing what type of source to create in case we can read the
source settings from a file in the future.

=cut

sub source_repo_id {
    my $self = shift;
    if ( @_ ) {
        my $new_repo_id = shift;
        ## Save a copy in case the source is not yet loaded *or* it
        ## gets reloaded later.
        $self->{SourceRepoId} = $new_repo_id;
        if ( $self->source ) {
            $self->source->repo_id( $new_repo_id );
        }
    }

    $self->source ?  return $self->source->repo_id : $self->{SourceRepoId};
}

=item source

Gets (does not set) the source.

=cut

sub source { shift->{Source} }

=item dest

Gets (does not set) the dest.

=cut

sub dest { shift->{Dest} }

=item dest_repo_id

Sets/gets the dest repo_id.  This is needed because we prompt for the dest
name before knowing what type of dest to create in case we can read the
dest settings from a file in the future.

=cut

sub dest_repo_id {
    my $self = shift;
    if ( @_ ) {
        my $new_repo_id = shift;
        $self->{DestRepoId} = $new_repo_id;
            ## Save a copy in case the dest is not yet loaded *or* it
            ## gets reloaded later.
        if ( $self->dest ) {
            $self->dest->repo_id( $new_repo_id );
        }
    }

    $self->dest ?  return $self->dest->repo_id : $self->{DestRepoId};
}

=item new_dest

    $ui->new_dest( "vss", @_ );

Creates a new dest if the current dest is not of the indicated class.

Sets the repo_id to be dest_repo_id if necessary.

Emits a warning when the source is changed from one type to another and
clears in_edit_mode().

=cut

sub new_dest {
   my $self = shift;
   my $scheme = shift;
   my $class = "VCP::Dest::$scheme";
   ## using ref/eq instead of isa so subclasses don't
   ## masquerade as superclasses by default
   unless ( $self->{Dest} && ref $self->{Dest} eq $class ) {

      $self->emit_note( "Clearing all settings for destination." )
         if $self->{Dest};

      eval "require $class" or die "Couldn't load $class";

      my $new_dest = $class->new;
      $new_dest->repo_id( $self->dest_repo_id )
          unless empty $self->dest_repo_id;
      $new_dest->repo_scheme( $scheme );

      $self->{Dest} = $new_dest;
          ## setting $self->{Dest} changes the behavior of dest_repo_id, so
          ## do it last.

      $self->{EditMode} = 0;
    }
}

=item in_edit_mode

Returns true if the machine is editing an existing set of settings.

=cut

sub in_edit_mode {
   my $self = shift;
   return $self->{EditMode};
}

=item ask

    $text_ui->ask(
        $is_error,
        $description,
        $always_verbose,
        $name,
        $prompt,
        $default,
        $answer_key
    );

Prompts the user, giving them the possibly lengthy description,
a blank line and a prompt.  Reads a single line of input and
returns it and a reference to the matching answer key.

The answer key looks like:
   
   [
      [ $suggested_answer_1, $validator_1, ... ],
      [ $suggested_answer_2, $validator_2, ... ],
      [ $suggested_answer_3, $validator_3, ... ],
      ...
   ]

The suggested answers are like "yes", "No", etc.  Leave this
as undef or "" to run a validator without an answer.

The validators are one of:

    undef             Entry is compared to the suggested answer, if defined
    'foo'             Answer must equal 'foo' (case sensitive)
    qr//              Answer must match the indicated regexp
    sub {...}, \&foo  The subroutine will validate.

If all validators are strings that are equal to the suggested answer,
a multiple choice prompt/response is generated instead of free text
entry.

Validation subroutines must return TRUE for valid input, FALSE for invalid
input but without a message, or die "...\n" with an error message for the
user if the input is not valid.  If no validators pass, an error message
will be printed and the user will be reprompted.  If multiple code
reference validators fail with different error messages, then these
will all be printed.

The answer to be validated is placed in $_ when calling a code ref.

=cut

sub _trim {
   ( @_ ? $_[0] : $_ ) =~ s/\A[\r\n\s]*(.*?)[\r\n\s]*\z/$1/s
       or warn "Couldn't trim '$_'";
}


{
   my $try_count = 0;
   my $prev_name= "";
   
   sub ask {
      my $self = shift;
      my (
          $is_error,
          $description,
          $always_verbose,
          $name,
          $prompt,
          $default,
	  $is_current_value,
          $answer_key
      ) = @_;
      die "A name is required" unless defined $name;

      ## reset $try_count if this is a new question.
      if ( $name ne $prev_name ) {
         $try_count = 0;
         $prev_name = $name;
      }

      ## take a copy so _trim doesn't modify the original and also
      ## skip over answer_key records with no suggested answers.
      my @suggested_answers = grep defined, map $_->[0], @$answer_key;

      _trim
         for grep defined, $description, $name, @suggested_answers;

      ## We require that multiple choice is pure multiple choice,
      ## meaning that if any answer_key records have undef suggested
      ## answers, its still text input.  If need be, we could make
      ## those multiple choice but offer an "other" choice leading
      ## to text entry, but that's not yet needed.
      my $is_multiple_choice =
         !grep
            !defined $_->[0] || $_->[0] ne $_->[1],
            @$answer_key;

      my $choices;

      $prompt = $name if empty $prompt;

      if ( $is_multiple_choice ) {
         $choices = [ sort @suggested_answers ];
         $prompt = $self->build_prompt( $prompt );
      }
      else {
         my $d = empty( $default )
            ? undef
            : $is_current_value
               ? "Current value: $default"
               : "Default: $default";
         $prompt = $self->build_prompt( $prompt, $d, \@suggested_answers );
      }

      if ( ! $is_error ) {
         $self->emit_blank_line;
         $self->emit_blank_line;
      }

      while (1) {

         $self->output(
            $name,
            $is_error,
            $try_count++ % 10
               ? 2
               : ( ! $always_verbose
                  && $self->{UIManager}->{TersePrompts}
               ) ? 1 : 0,
	    $description,
            $choices,
            $default,
	    $is_current_value,
            $prompt
         );

         my $answer = $self->input;

         exit(0)
	    unless defined $answer;  # only when piping stdin (test scripts)

         _trim $answer;

         if ( $is_multiple_choice
            && (
               $answer =~ /\A\d+\z/
               || ( ! length $answer && empty $default )
            )
         ) {
            if (
               $answer !~ /\A\d+\z/
               || $answer < 1
               || $answer > $#suggested_answers + 1
            ) {
               $self->emit_error(
                  "Please enter a number between 1 and ",
                  $#suggested_answers + 1,
                  " or the full text of an option."
               );
               next;
            }

            $answer = $choices->[ $answer - 1 ];
         }

         $answer = $default
            if defined $default && ! length $answer;

         my @results = eval { $self->validate(
            $answer, $answer_key, $is_multiple_choice
         ) };
         return @results if @results > 1;
         $self->emit_error(
            @results
               ? !length $answer
                   ? "Please enter a value."
                   : "Invalid input."
               : $@
         );
      }
   }
}

=item input

    my $line = $text_ui->input;

Gets the user's input with or without surrounding whitespace and newline.

=cut

sub input {
   my $self = shift;
   return scalar <STDIN>;
}

=item output

    $text_ui->output(
        $terseness,
        $description,
	$choices,
	$default,
	$is_current_value,
	$prompt,
     );

Outputs the parameters to the user; defaults to print()ing it with
stdout buffering off.

$description will be undef after the first call until ask() decides that
the user needs to see it again.

=cut

sub output {
   my $self = shift;
   my (
      $name,
      $is_error,
      $terse,
      $description,
      $choices,
      $default,
      $is_current_value,
      $prompt
   ) = @_;

   local $| = 1;

   print "\n";

   if ( ! $terse && !empty $description ) {
      if ( ! $is_error ) {
         print "$name\n";
         print "-" x length $name, "\n";
      }
      my $indent = $is_error ? "*** " : "    ";
      $description =~ s/^/$indent/mg;
      print "\n$description\n\n";
   }

   if ( $terse < 2 && $choices && @$choices ) {
      my $format = do {
         my $iw = length( $#$choices + 1 );
         my $ow = 0;
         for ( @$choices ) {
            $ow = length if ! $ow || length > $ow;
         }
	 "    %${iw}d) %-${ow}s%s\n";
      };
      my $counter = 0;
      print map(
         sprintf(
            $format,
            ++$counter,
            $_,
            defined $default && $_ eq $default
	       ? $is_current_value
                  ? " <-- current value (default)"
                  : " <-- default"
               : "",
         ),
         @$choices
      ), "\n";
   }

   print $prompt, " ";
}


=item emit_hrule

Prints a separator line.  Used between prompts and at exit.

=cut

sub emit_hrule {
   print "-" x 40, "\n"
}


=item emit_blank_line

Prints a blank line.  Used at exit.

=cut

sub emit_blank_line {
   print "\n"
}


=item emit_error

Prints a message.  Defaults to warn()ing.

=cut

sub emit_error {
   shift;
   my $msg = join "", @_;
   1 while chomp $msg;
   $msg =~ s/^/*** /mg;
   warn "\n", $msg, "\n";
}


=item emit_note

Prints a message.  Defaults to warn()ing.

=cut

sub emit_note {
   shift;
   my $msg = join "", @_;
   1 while chomp $msg;
   $msg =~ s/^/NOTE: /mg;
   warn "\n", $msg, "\n";
}


=item build_prompt

    $text_ui->build_prompt( $prompt, \@suggested_answers );

Assembed $prompt and possibly the strings in \@suggested_answers in to
a single string fit for a user.

=cut

sub build_prompt {
   my $self = shift;
   my ( $prompt, $default, $suggested_answers ) = @_;

   my @s = grep length, @$suggested_answers;

   return join "",
      $prompt,
      @s
          ? ( " (", join( ", ", sort @s ), ")" )
          : (),
      defined $default ? " [$default]" : "",
      "?";
}

=item validate

    $text_ui->validate( $answer, $answer_key, $is_multiple_choice );

Returns a two element list ( $answer, $matching_answer_key_entry ) or
dies with an error message.  If $is_multiple_choice, then the answer
will be matched case-insensitively for literal string validators.

=cut

sub validate {
   my $self = shift;
   my ( $answer, $answer_key, $is_multiple_choice ) = @_;

   my @msgs;

   for my $entry ( @$answer_key ) {
      debug "checking '$answer' against $entry->[1]" if debugging;
      return ( $answer, $entry )
         if ( ! defined $entry->[1]
               && ( ! defined $entry->[0]
                  || $answer eq $entry->[0]
               )
            )
            || ( ref $entry->[1] eq ""
               && $is_multiple_choice
                  ? (
                     lc $answer eq lc $entry->[1]
                     || ( lc $answer eq "y" && $entry->[1] eq "yes" )
                     || ( lc $answer eq "n" && $entry->[1] eq "no" )
                  )
                  :    $answer eq    $entry->[1]
            )
            || ( ref $entry->[1] eq "Regexp" && $answer =~ $entry->[1] )
            || ( ref $entry->[1] eq "CODE"  
                  && do {
                     local $_ = $answer;
                     my $ok = eval { $entry->[1]->() || 0 };
                     push @msgs, $@ unless defined $ok;
                     $ok;
                  }
               );
   }

   die join "", @msgs if @msgs;

   return 0;
}


sub run {
    my $self = shift;

    $self->{EditMode} = $self->{Source} || $self->{Dest};

    my $m = VCP::UIMachines->new;

    $m->run( $self );

    $self->emit_hrule;
    $self->emit_blank_line;

    return (
        $self->{Source},
        $self->{Dest},
        $self->{SaveAsConfigFileName},
        $self->{Run},
    );
}







=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP::UI::Text package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
