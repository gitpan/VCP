package VCP::UIMachines;

=begin hackers

DO NOT EDIT!!! GENERATED FROM ui_machines/vcp_ui.tt2 by /usr/bin/stml AT Thu Jan 29 22:06:02 2004

=end hackers

=head1 NAME

    VCP::UIMachines - State machines for user interface

=head1 SYNOPSIS

    Called by VCP::UI

=head1 DESCRIPTION

The user interface module L<VCP::UI|VCP::UI> is a framework that bolts
the implementation of the user interface to a state machine representing
the user interface.

Each state in this state machine is a method that runs the state and
returns a result (or dies to exit the program).

=cut

use strict;

use VCP::Debug qw( :debug );
use VCP::Utils qw( empty );

=head1 API

=over

=item new

Creates a new user interface object.

=cut

sub new {
    my $class = ref $_[0] ? ref shift : shift;
    my $self = bless { @_ }, $class;
}

=item run

Executes the user interface.

=cut

sub run {
    my $self = shift;
    my ( $ui ) = @_;

    $self->{STATE} = "init";
    while ( defined $self->{STATE} ) {
        debug "UI entering state $self->{STATE}" if debugging;
        no strict "refs";
        $self->{STATE} = $self->{STATE}->( $ui );
    }

    return;
}

=back

=head2 Interactive Methods

=over

=cut

use strict;

=item init

Initialize the machine

Next state: source_id_prompt

=cut

sub init {
    return 'source_id_prompt';
}

=item source_id_prompt: Source id

A symbolic name for the source repository.  This is used to
organize the VCP databases and to refer to the source
repository in other places.

Must consist of a leading letter then letters, numbers,
underscores and dashes only.

Valid answers:

     => source_type_prompt


=cut

sub source_id_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source id
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr{\A[a-z][a-z0-9-]*\z}i, 'source_type_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                ## Set the UI's source_repo_id.  This will write-through to
                ## the underlying source if it's been loaded already,
                ## otherwise the call to new_source() will do the write-through
                ## when it is loaded later.
                $ui->source_repo_id( $answer )
                    unless ! empty $ui->source_repo_id and empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


A symbolic name for the source repository.  This is used to
organize the VCP databases and to refer to the source
repository in other places.

Must consist of a leading letter then letters, numbers,
underscores and dashes only.
    
    
END_DESCRIPTION

    
    $default = $ui->source_repo_id && $ui->source_repo_id;
    $is_current_value = $ui->{EditMode} = 1 unless empty $default;

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_type_prompt: Source type

The kind of repository to copy data from.

Valid answers:

    p4 => source_p4_run_p4d_prompt
    vss => source_vss_vssroot_prompt
    cvs => source_cvs_cvsroot_prompt


=cut

sub source_type_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source type
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'p4', 'p4', 'source_p4_run_p4d_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->new_source( $answer );
            },
        
        ],
        [ 'vss', 'vss', 'source_vss_vssroot_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->new_source( $answer );
            },
        
        ],
        [ 'cvs', 'cvs', 'source_cvs_cvsroot_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->new_source( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The kind of repository to copy data from.
    
    
END_DESCRIPTION

    
    $default = $ui->source && $ui->source->repo_scheme;
    $is_current_value = $ui->{EditMode} = 1 unless empty $default;

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_id_prompt: Destination id

A symbolic name for the destination repository.  This is used to
organize the VCP databases and to refer to the destination
repository in other places.

Must consist of a leading letter then letters, numbers,
underscores and dashes only.

Valid answers:

     => dest_type_prompt


=cut

sub dest_id_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination id
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr{\A[a-z][a-z0-9-]*\z}i, 'dest_type_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                ## Set the UI's dest_repo_id.  This will write-through to
                ## the underlying destination if it's been loaded already,
                ## otherwise the call to new_dest() will do the write-through
                ## when it is loaded later.
                $ui->dest_repo_id( $answer )
                    unless ! empty $ui->dest_repo_id and empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


A symbolic name for the destination repository.  This is used to
organize the VCP databases and to refer to the destination
repository in other places.

Must consist of a leading letter then letters, numbers,
underscores and dashes only.
    
    
END_DESCRIPTION

    
    $default = $ui->dest_repo_id && $ui->dest_repo_id;
    $is_current_value = $ui->{EditMode} = 1 unless empty $default;

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_type_prompt: Destination SCM type

The kind of repository to copy data to.

Valid answers:

    cvs => dest_cvs_cvsroot_prompt
    p4 => dest_p4_run_p4d_prompt
    vss => dest_vss_vssroot_prompt


=cut

sub dest_type_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination SCM type
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'cvs', 'cvs', 'dest_cvs_cvsroot_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->new_dest( $answer );
            },
        
        ],
        [ 'p4', 'p4', 'dest_p4_run_p4d_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->new_dest( $answer );
            },
        
        ],
        [ 'vss', 'vss', 'dest_vss_vssroot_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->new_dest( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The kind of repository to copy data to.
    
    
END_DESCRIPTION

    
    $default = $ui->dest && $ui->dest->repo_scheme;
    $is_current_value = $ui->{EditMode} = 1 unless empty $default;

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item wrapup: Next step

What to do with all of the entered options.

Valid answers:

    Save config file and run => save_config_file
    Run without saving config file => convert
    Save config file and exit => save_config_file


=cut

sub wrapup {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Next step
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'Save config file and run', 'Save config file and run', 'save_config_file',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->{Run} = 1;
            },
        
        ],
        [ 'Run without saving config file', 'Run without saving config file', 'convert',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->{Run} = 1;
            },
        
        ],
        [ 'Save config file and exit', 'Save config file and exit', 'save_config_file',
            undef,
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


What to do with all of the entered options.

    
END_DESCRIPTION

    
    $default = "Save config file and run";

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item save_config_file: Config file name

What filename to write the configuration file to.

Valid answers:

    Config filename => convert


=cut

sub save_config_file {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Config file name
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'Config filename', qr/./, 'convert',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->{SaveAsConfigFileName} = $answer;
                if ( -e $answer ) {
                    die "Warning: '$answer' exists but is a directory!\n"
                        if -d $answer;
                    die "Warning: '$answer' exists but is not a regular file!\n"
                        unless -f $answer;
                    die "Warning: '$answer' exists but is not writable!\n"
                        unless -w $answer;
                    die "Warning: '$answer' already exists!\n";
                }
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';

    
What filename to write the configuration file to.

    
END_DESCRIPTION

    
    if ( ! empty $ui->{Filename} ) {
      $default = $ui->{Filename};
    	$is_current_value = 1;
    }
    else {
    	$default = $ui->source->repo_id . "_to_" . $ui->dest->repo_id . ".vcp";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item convert

Run VCP with the options entered

=cut

sub convert {
    return undef;
}

=item dest_p4_run_p4d_prompt: Launch a p4d for the destination

If you would like to insert into an offline repository in a
local directory, vcp can launch a 'p4d' daemon for you in that
directory.  It will use a random high numbered TCP port.

Valid answers:

    yes => dest_p4_p4d_dir_prompt
    no => dest_p4_host_prompt


=cut

sub dest_p4_run_p4d_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Launch a p4d for the destination
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'yes', 'yes', 'dest_p4_p4d_dir_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                my $old = $ui->dest->{P4_RUN_P4D} ? 1 : 0;
                $answer = 1;
                $ui->dest->repo_server( undef )
                  if $ui->in_edit_mode and $old != $answer;
                
                $ui->dest->{P4_RUN_P4D} = $answer;
            },
        
        ],
        [ 'no', 'no', 'dest_p4_host_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                my $old = $ui->dest->{P4_RUN_P4D} ? 1 : 0;
                $answer = 0 ;
                $ui->dest->repo_server( undef )
                  if $ui->in_edit_mode and $old != $answer;
                  
                  $ui->dest->{P4_RUN_P4D} = $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';

    
If you would like to insert into an offline repository in a
local directory, vcp can launch a 'p4d' daemon for you in that
directory.  It will use a random high numbered TCP port.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->{P4_RUN_P4D} ? "yes" : "no" ;
      $is_current_value = 1;
    }
    else {
      $default = "no";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_p4_p4d_dir_prompt: Destination P4ROOT

The directory of the destination repository, p4d will be
launched here.

Valid answers:

     => dest_p4_user_prompt


=cut

sub dest_p4_p4d_dir_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination P4ROOT
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'dest_p4_user_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                # will set repo_server
                $ui->dest->ui_set_p4d_dir( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The directory of the destination repository, p4d will be
launched here.
    
    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_server ;
      $is_current_value = 1;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_p4_host_prompt: Destination P4PORT

The hostname/IP address and port of the p4d to write to,
separated by a colon.  Defaults to the default P4PORT variable
as reported by the 'p4 set' command (with a final default to
"perforce:1666" if the p4 set command does not return anything).

Valid answers:

    perforce:1666 => dest_p4_user_prompt


=cut

sub dest_p4_host_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination P4PORT
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'perforce:1666', qr/./, 'dest_p4_user_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_server( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The hostname/IP address and port of the p4d to write to,
separated by a colon.  Defaults to the default P4PORT variable
as reported by the 'p4 set' command (with a final default to
"perforce:1666" if the p4 set command does not return anything).

    
END_DESCRIPTION

    
    my $h = $ui->dest->p4_get_settings;
    if ($ui->in_edit_mode) {
      $default = $ui->dest->repo_server ;
      $is_current_value = 1;
    }
    else {
      $default = empty ( $h->{P4HOST} ) ?  "perforce:1666" : $h->{P4HOST} ;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_p4_user_prompt: Destination P4USER

The username to connect to the destination p4d with.  Defaults
to the user reported by the 'p4 set' command (with a final
default to the USER environment variable if the p4 set command
does not return anything).

Valid answers:

     => dest_p4_password_prompt


=cut

sub dest_p4_user_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination P4USER
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'dest_p4_password_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_user( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The username to connect to the destination p4d with.  Defaults
to the user reported by the 'p4 set' command (with a final
default to the USER environment variable if the p4 set command
does not return anything).

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_user;
      $is_current_value = 1;
    }
    else {
      my $h = $ui->dest->p4_get_settings;
      $default =  empty ( $h->{P4USER} ) 
               ? ( empty $ENV{USER} ? undef : $ENV{USER})
               : $h->{P4USER} ;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_p4_password_prompt: Destination P4PASSWD

The P4PASSWD needed to access the server.  Leave blank to use
the default reported by P4PASSWD.

WARNING: entering a password will cause it to be echoed in plain text to the terminal.

Valid answers:

     => dest_p4_filespec_prompt


=cut

sub dest_p4_password_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination P4PASSWD
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'dest_p4_filespec_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                if ( $ui->in_edit_mode ) {
                    $answer = $ui->dest->repo_password
                        if $answer eq "** current password **";
                }
                else {
                  my $h = $ui->dest->p4_get_settings ;
                  $answer = $h->{P4PASSWD}
                      if $answer eq "** current P4PASSWD **";
                }
                $ui->dest->repo_password( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The P4PASSWD needed to access the server.  Leave blank to use
the default reported by P4PASSWD.

WARNING: entering a password will cause it to be echoed in plain text to the terminal.

    
END_DESCRIPTION

    
    if ($ui->in_edit_mode ) {
      unless ( empty $ui->dest->repo_password ) {
        $default = "** current password **";
        $is_current_value = 1;
      }
    }
    else {
      my $h = $ui->dest->p4_get_settings;
      $default = "** current P4PASSWD **"
        unless empty $h->{P4PASSWD} ;
    }    

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_p4_filespec_prompt: Destination File Specification

Where to place the transferred revisions.  This is a perforce
repository spec and must begin with "//" and a depot name
("//depot"), not a local filesystem spec or a "//client" or
"//label" spec.

Valid answers:

    //depot/directory-path/... => wrapup


=cut

sub dest_p4_filespec_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination File Specification
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '//depot/directory-path/...', qr#\A//#, 'wrapup',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_filespec( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Where to place the transferred revisions.  This is a perforce
repository spec and must begin with "//" and a depot name
("//depot"), not a local filesystem spec or a "//client" or
"//label" spec.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_filespec;
      $is_current_value = 1;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_cvs_cvsroot_prompt: Destination CVSROOT

Specifies the destination CVS repository location and protocol.
Defaults to the CVSROOT environment variable.  If this is a
local directory, VCP can initialize it for you.

Valid answers:

     => dest_cvs_filespec_prompt


=cut

sub dest_cvs_cvsroot_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination CVSROOT
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'dest_cvs_filespec_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_server( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Specifies the destination CVS repository location and protocol.
Defaults to the CVSROOT environment variable.  If this is a
local directory, VCP can initialize it for you.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_server;
      $is_current_value = 1;
    }
    else {
      $default = empty ( $ENV{CVSROOT} ) ? undef : $ENV{CVSROOT};
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_cvs_filespec_prompt: Destination CVS filespec

Where to copy revisions to in the destination specified by
CVSROOT.  This must start with a CVS module name and may be in a
subdirectory of the result:

    module/...
    module/path/to/directory/...
    module/path/to/file 

For directories, this should contain a trailing "..." wildcard,
like "module/b/..." to indicate that the path is a directory.

Valid answers:

    module/filepath/... => dest_cvs_init_cvsroot_prompt


=cut

sub dest_cvs_filespec_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination CVS filespec
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'module/filepath/...', qr/./, 'dest_cvs_init_cvsroot_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_filespec( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Where to copy revisions to in the destination specified by
CVSROOT.  This must start with a CVS module name and may be in a
subdirectory of the result:

    module/...
    module/path/to/directory/...
    module/path/to/file 

For directories, this should contain a trailing "..." wildcard,
like "module/b/..." to indicate that the path is a directory.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_filespec;
      $is_current_value = 1;
    }
    

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_cvs_init_cvsroot_prompt: 'cvs init' the destination CVSROOT

If the destination CVSROOT is a local directory, should VCP
initialize a cvs repository in it?

Valid answers:

    yes => wrapup
    no => wrapup


=cut

sub dest_cvs_init_cvsroot_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
'cvs init' the destination CVSROOT
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'yes', 'yes', 'wrapup',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->{CVS_INIT_CVSROOT} = 1;
            },
        
        ],
        [ 'no', 'no', 'wrapup',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->{CVS_INIT_CVSROOT} = 0;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


If the destination CVSROOT is a local directory, should VCP
initialize a cvs repository in it?

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->{CVS_INIT_CVSROOT} ? "yes" : "no" ;
      $is_current_value = 1;
    }
    else {
      $default = "no";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_vss_vssroot_prompt: Destination SSDIR

The directory that will contain the srcsafe.ini file for the
destination repostiory.

Valid answers:

     => dest_vss_user_prompt


=cut

sub dest_vss_vssroot_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination SSDIR
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'dest_vss_user_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_server( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The directory that will contain the srcsafe.ini file for the
destination repostiory.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_server;
      $is_current_value = 1;
    }
      
      

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_vss_user_prompt: Destination SSUSER

Enter the SSUSER value needed to access the destination server.  Defaults to
the current environment's SSUSER or 'Admin'.

Valid answers:

     => dest_vss_password_prompt


=cut

sub dest_vss_user_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination SSUSER
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'dest_vss_password_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_user( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the SSUSER value needed to access the destination server.  Defaults to
the current environment's SSUSER or 'Admin'.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_user;
      $is_current_value = 1;
    }
    else {
      $default = empty( $ENV{SSUSER} ) ? "Admin" : $ENV{SSUSER} ;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_vss_password_prompt: Destination SSPWD

If a password (SSPWD) is needed to access the destination server, enter
it here.  Defaults to the current SSPWD if one is set.

WARNING: entering a password will cause it to be echoed in plain text 
to the terminal.

Valid answers:

     => dest_vss_filespec_prompt


=cut

sub dest_vss_password_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination SSPWD
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/^/, 'dest_vss_filespec_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                if ( $ui->in_edit_mode ) {
                    $answer = $ui->dest->repo_password
                        if $answer eq "** current password **";
                }
                else {
                    $answer = $ENV{SSPWD}
                        if $answer eq "** current SSPWD **";
                }
                $ui->dest->repo_password( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


If a password (SSPWD) is needed to access the destination server, enter
it here.  Defaults to the current SSPWD if one is set.

WARNING: entering a password will cause it to be echoed in plain text 
to the terminal.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      unless ( empty $ui->dest->repo_password ) {
        $default = "** current password **";
        $is_current_value = 1;
      }
    }
    else {
      $default = "** current SSPWD **"
        unless empty $ENV{SSPWD};
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_vss_filespec_prompt: Destination VSS filespec

Enter the vss filespec of the destination directory, with or
without a leading "$/" or "/" (all names are taken as
absolute).

Valid answers:

     => dest_vss_mkss_prompt


=cut

sub dest_vss_filespec_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Destination VSS filespec
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'dest_vss_mkss_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->repo_filespec( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the vss filespec of the destination directory, with or
without a leading "$/" or "/" (all names are taken as
absolute).

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->dest->repo_filespec ;
      $is_current_value = 1;
    }
    

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item dest_vss_mkss_prompt: 'mkss' the destination SSDIR

If the destination SSDIR is a local directory, should VCP 
use mkss to initialize a vss repository in it?

Valid answers:

    yes => wrapup
    no => wrapup


=cut

sub dest_vss_mkss_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
'mkss' the destination SSDIR
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'yes', 'yes', 'wrapup',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->{VSS_MKSS_SSDIR} = 1 ;
            },
        
        ],
        [ 'no', 'no', 'wrapup',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->dest->{VSS_MKSS_SSDIR} = 0 ;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


If the destination SSDIR is a local directory, should VCP 
use mkss to initialize a vss repository in it?

    
END_DESCRIPTION

    
    if ($ui->in_edit_mode ) {
      $default = $ui->dest->{VSS_MKSS_SSDIR} ? "yes" : "no" ;
      $is_current_value = 1;
    }
    else {
      $default = "no";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_p4_run_p4d_prompt: Launch a p4d for the source

If you would like to extract from an offline repository in a
local directory, vcp can launch a 'p4d' daemon for you in that
directory.  It will use a random high numbered TCP port.

Valid answers:

    no => source_p4_host_prompt
    yes => source_p4_p4d_dir_prompt


=cut

sub source_p4_run_p4d_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Launch a p4d for the source
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'no', 'no', 'source_p4_host_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                my $old = $ui->source->{P4_RUN_P4D} ? 1 : 0;
                $answer = 0;
                $ui->source->repo_server( undef )
                  if $ui->in_edit_mode and $old != $answer;
                
                $ui->source->{P4_RUN_P4D} = $answer;
            },
        
        ],
        [ 'yes', 'yes', 'source_p4_p4d_dir_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                my $old = $ui->source->{P4_RUN_P4D} ? 1 : 0;
                $answer = 1;
                $ui->source->repo_server( undef )
                  if $ui->in_edit_mode and $old != $answer;
                
                $ui->source->{P4_RUN_P4D} = $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';

    
If you would like to extract from an offline repository in a
local directory, vcp can launch a 'p4d' daemon for you in that
directory.  It will use a random high numbered TCP port.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->{P4_RUN_P4D} ? "yes" : "no" ;
      $is_current_value = 1;
    }
    else {
      $default = "no";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_p4_p4d_dir_prompt: Source P4ROOT

The directory of the source repository.  The source p4d will be
launched here.

Valid answers:

     => source_p4_user_prompt


=cut

sub source_p4_p4d_dir_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source P4ROOT
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'source_p4_user_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                # will set repo_server
                $ui->source->ui_set_p4d_dir( $answer ) ;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The directory of the source repository.  The source p4d will be
launched here.
    
    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode )  {
      $default = $ui->source->repo_server ;
      $is_current_value = 1;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_p4_host_prompt: Source P4PORT

Enter the name and port of the p4d to read from, separated by a colon.
Defaults to what is in config file, then the P4HOST environment variable if
set or "perforce:1666" if not.

Valid answers:

    perforce:1666 => source_p4_user_prompt


=cut

sub source_p4_host_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source P4PORT
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'perforce:1666', qr/./, 'source_p4_user_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_server( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the name and port of the p4d to read from, separated by a colon.
Defaults to what is in config file, then the P4HOST environment variable if
set or "perforce:1666" if not.

    
END_DESCRIPTION

    
    my $h = $ui->source->p4_get_settings;
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_server ;
      $is_current_value = 1;
    }
    else {
      $default = empty  $h->{P4HOST} ? "perforce:1666"  : $h->{P4HOST} ;
    }  

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_p4_user_prompt: Source P4USER

Enter the P4USER value needed to access the server.  Defaults to
the P4USER value reported by p4 set (with a final default to the
USER environment variable if p4 set does not return anything).

Valid answers:

     => source_p4_password_prompt


=cut

sub source_p4_user_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source P4USER
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'source_p4_password_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_user( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the P4USER value needed to access the server.  Defaults to
the P4USER value reported by p4 set (with a final default to the
USER environment variable if p4 set does not return anything).

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_user;
      $is_current_value = 1;
    }
    else {
      my $h = $ui->source->p4_get_settings;
      $default = empty $h->{P4USER}
               ? ( empty $ENV{USER} ? undef : $ENV{USER} )
               : $h->{P4USER} ;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_p4_password_prompt: Source P4PASSWD

If a password (P4PASSWD) is needed to access the server, enter
it here. Defaults to the current P4PASSWD if one is set.

WARNING: entering a password will cause it to be echoed in plain text to the terminal.

Valid answers:

     => source_p4_filespec_prompt


=cut

sub source_p4_password_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source P4PASSWD
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'source_p4_filespec_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                if ( $ui->in_edit_mode ) {
                    $answer = $ui->source->repo_password 
                        if $answer eq "** current password **";
                }
                else {
                    my $h = $ui->source->p4_get_settings;
                    $answer = $h->{P4PASSWD}
                        if $answer eq "** current P4PASSWD **";
                }
                $ui->source->repo_password( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


If a password (P4PASSWD) is needed to access the server, enter
it here. Defaults to the current P4PASSWD if one is set.

WARNING: entering a password will cause it to be echoed in plain text to the terminal.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      unless ( empty $ui->source->repo_password ) {
        $default = "** current password **";
        $is_current_value = 1;
      }
    }
    else {
      my $h = $ui->source->p4_get_settings;
      $default = "** current P4PASSWD **"
        unless empty $h->{P4PASSWD} ;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_p4_filespec_prompt: Source File specification

If you want to copy a portion of the source repository, enter a p4
filespec starting with the depot name.  Do not enter any revision or
change number information.

Valid answers:

    //depot/directory-path/... => dest_id_prompt


=cut

sub source_p4_filespec_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source File specification
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '//depot/directory-path/...', qr{\A//.+}, 'dest_id_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_filespec( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


If you want to copy a portion of the source repository, enter a p4
filespec starting with the depot name.  Do not enter any revision or
change number information.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_filespec;
      $is_current_value = 1;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_cvs_cvsroot_prompt: Source CVSROOT

The CVSROOT to read revisions from.  Defaults to the CVSROOT
environment variable.

Valid answers:

    cvsroot spec => source_cvs_filespec_prompt


=cut

sub source_cvs_cvsroot_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source CVSROOT
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'cvsroot spec', qr/./, 'source_cvs_filespec_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_server( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The CVSROOT to read revisions from.  Defaults to the CVSROOT
environment variable.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_server;
      $is_current_value = 1;
    }
    else {
      $default = empty( $ENV{CVSROOT} ) ? undef : $ENV{CVSROOT};
    }  

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_cvs_filespec_prompt: Source CVS filespec

Enter the cvs filespec of the file(s) to copy.  This must start
with a CVS module name and end in a filename, directory
name, or "..." wildcard:

    module/...
    module/file
    module/path/to/subdir/...
    module/path/to/subdir/file

Valid answers:

    module/filepath/... => source_cvs_working_directory_prompt


=cut

sub source_cvs_filespec_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source CVS filespec
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'module/filepath/...', qr/./, 'source_cvs_working_directory_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_filespec( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the cvs filespec of the file(s) to copy.  This must start
with a CVS module name and end in a filename, directory
name, or "..." wildcard:

    module/...
    module/file
    module/path/to/subdir/...
    module/path/to/subdir/file

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_filespec;
      $is_current_value = 1;
    }
       

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_cvs_working_directory_prompt: Source CVS working directory

Enter the CVS working directory (Optional). VCP::Source::cvs will cd
to this directory before calling cvs and won't initialize a CVS
workspace of its own.  Leave blank to allow VCP to use a
temporary directory.

Valid answers:

     => source_cvs_binary_checkout_prompt


=cut

sub source_cvs_working_directory_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source CVS working directory
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/^/, 'source_cvs_binary_checkout_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->ui_set_cvs_work_dir( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the CVS working directory (Optional). VCP::Source::cvs will cd
to this directory before calling cvs and won't initialize a CVS
workspace of its own.  Leave blank to allow VCP to use a
temporary directory.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
       $default = $ui->source->{CVS_WORK_DIR} ;
       $is_current_value = 1;
    }
       

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_cvs_binary_checkout_prompt: Force binary checkout

Pass the -kb option to cvs, to force a binary checkout. This is useful
when you want a text file to be checked out with Unix linends, or if
you know that some files in the repository are not flagged as binary
files and should be.

Valid answers:

    no => source_cvs_use_cvs_prompt
    yes => source_cvs_use_cvs_prompt


=cut

sub source_cvs_binary_checkout_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Force binary checkout
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'no', 'no', 'source_cvs_use_cvs_prompt',
            undef,
        
        ],
        [ 'yes', 'yes', 'source_cvs_use_cvs_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->{CVS_K_OPTION} = "b";            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Pass the -kb option to cvs, to force a binary checkout. This is useful
when you want a text file to be checked out with Unix linends, or if
you know that some files in the repository are not flagged as binary
files and should be.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->{CVS_K_OPTION} =~ /b/ ? "yes" : "no" ;
      $is_current_value = 1;
    }
    else {
      $default = "no";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_cvs_use_cvs_prompt: Use cvs executable

This forces VCP to use the cvs executable rather than read local
CVSROOT directories directly.  This is slower, but may be used
to work around any limitations that might crop up in VCP's RCS
file parser.

Valid answers:

    yes => dest_id_prompt
    no => dest_id_prompt


=cut

sub source_cvs_use_cvs_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Use cvs executable
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'yes', 'yes', 'dest_id_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->{CVS_USE_CVS} = 1;            },
        
        ],
        [ 'no', 'no', 'dest_id_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->{CVS_USE_CVS} = 0;            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


This forces VCP to use the cvs executable rather than read local
CVSROOT directories directly.  This is slower, but may be used
to work around any limitations that might crop up in VCP's RCS
file parser.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->{CVS_USE_CVS} ? "yes" : "no" ;
      $is_current_value = 1;
    }
    else { 
      $default = "no";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_vss_vssroot_prompt: Source SSDIR

The directory containing the srcsafe.ini file for the source
repository.

Valid answers:

     => source_vss_user_prompt


=cut

sub source_vss_vssroot_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source SSDIR
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'source_vss_user_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_server( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


The directory containing the srcsafe.ini file for the source
repository.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_server;
      $is_current_value = 1;
    }
    else {
      $default = empty( $ENV{SSDIR} ) ? undef : $ENV{SSDIR};
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_vss_user_prompt: Source SSUSER

Enter the SSUSER value needed to access the server.  Defaults to
the current environment's SSUSER or 'Admin'.

Valid answers:

     => source_vss_password_prompt


=cut

sub source_vss_user_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source SSUSER
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'source_vss_password_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_user( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the SSUSER value needed to access the server.  Defaults to
the current environment's SSUSER or 'Admin'.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_user;
      $is_current_value = 1;
    }
    else {
      $default = empty( $ENV{SSUSER} ) ? "Admin" : $ENV{SSUSER} ;
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_vss_password_prompt: Source SSPWD

If a password (SSPWD) is needed to access the server, enter
it here.  Defaults to the current SSPWD if one is set.

WARNING: entering a password will cause it to be echoed in plain text
to the terminal.

Valid answers:

     => source_vss_filespec_prompt


=cut

sub source_vss_password_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source SSPWD
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/^/, 'source_vss_filespec_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                if ( $ui->in_edit_mode ) {
                    $answer = $ui->source->repo_password
                        if $answer eq "** current password **";
                }
                else {
                    $answer = $ENV{SSPWD}
                        if $answer eq "** current SSPWD **";
                }
                $ui->source->repo_password( $answer )
                    unless empty $answer;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


If a password (SSPWD) is needed to access the server, enter
it here.  Defaults to the current SSPWD if one is set.

WARNING: entering a password will cause it to be echoed in plain text
to the terminal.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      unless ( empty $ui->source->repo_password ) {
        $default = "** current password **";
        $is_current_value = 1;
      }
    }
    else {
      $default = "** current SSPWD **"
        unless empty $ENV{SSPWD};
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_vss_filespec_prompt: Source VSS filespec

Enter the vss filespec of the file(s) to copy, with or
without a leading "$/" or "/" (all names are taken as
absolute).  To copy more than one file, use a "..." or "*"
wildcard:

    ...                      Copy entire repository
    project1/...             Copy entire project
    project1/file            Copy one file
    project1/dir/...         Copy a subdirectory
    project1/dir/file*.bas   Copy a set of files

Valid answers:

     => source_vss_undocheckout_prompt


=cut

sub source_vss_filespec_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Source VSS filespec
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ '', qr/./, 'source_vss_undocheckout_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->repo_filespec( $answer );
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


Enter the vss filespec of the file(s) to copy, with or
without a leading "$/" or "/" (all names are taken as
absolute).  To copy more than one file, use a "..." or "*"
wildcard:

    ...                      Copy entire repository
    project1/...             Copy entire project
    project1/file            Copy one file
    project1/dir/...         Copy a subdirectory
    project1/dir/file*.bas   Copy a set of files

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->repo_filespec;
      $is_current_value = 1;
    }
    else {
      $default = "...";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=item source_vss_undocheckout_prompt: Issue "ss undocheckout" as needed

If set, VCP will undo users' checkouts when it runs in to
the "File ... is checked out by ..." error.  This occurs, at
least, when scanning metadata for a checked-out file when
there is also a deleted version of the same file.

Valid answers:

    yes => dest_id_prompt
    no => dest_id_prompt


=cut

sub source_vss_undocheckout_prompt {
    my ( $ui ) = @_;

    my $default = undef;
    my $is_current_value = undef;

    ## Use single-quotish HERE docs as the most robust form of quoting
    ## so we don't have to mess with escaping.
    my $prompt = <<'END_PROMPT';
Issue "ss undocheckout" as needed
END_PROMPT

    chomp $prompt;

    my @valid_answers = (
        [ 'yes', 'yes', 'dest_id_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->{VSS_UNDOCHECKOUT} = 1;
            },
        
        ],
        [ 'no', 'no', 'dest_id_prompt',
            sub {
                my ( $ui, $answer, $answer_record ) = @_;
                $ui->source->{VSS_UNDOCHECKOUT} = 0;
            },
        
        ],
    );

    my $description = <<'END_DESCRIPTION';


If set, VCP will undo users' checkouts when it runs in to
the "File ... is checked out by ..." error.  This occurs, at
least, when scanning metadata for a checked-out file when
there is also a deleted version of the same file.

    
END_DESCRIPTION

    
    if ( $ui->in_edit_mode ) {
      $default = $ui->source->{VSS_UNDOCHECKOUT} ? "yes" : "no";
      $is_current_value = 1;
    }
    else {
      $default = "no";
    }

    
    while (1) {
        my ( $answer, $answer_record ) =
            $ui->ask(
                0,
                $description,
                0,
                $prompt,
                $prompt,
                $default,
                $is_current_value,
                \@valid_answers
            );

        ## Run handlers for this arc, redo question if exceptions generated
        my $ok = eval {
            $answer_record->[-1]->( $ui, $answer, $answer_record )
                if defined $answer_record->[-1];
            1;
        };

        unless ( $ok ) {
            my $eval_error = $@;

            if ( $eval_error =~ /^warning:/i ) {
                ## recoverable error, ask if user wants to accept value anyway?
                my ( undef, $r ) = $ui->ask(
                    'error',
                    $eval_error,
                    1,
                    "Warning",
                    "Accept this value anyway",
                    "no",
                    0,
                    [
                        [ "yes", "yes", undef ],
                        [ "no",  "no",  undef ],
                    ]
                );
                next unless $r->[0] eq "yes";
            }
            else {
                ## completely un-acceptable exception, re-ask question.
                chomp $eval_error;
                warn "\n\n  $eval_error\n\n";
                next; 
            }
        }

        ## The next state
        return $answer_record->[-2];
    }
}

=back

=head1 WARNING: AUTOGENERATED

This module is autogenerated in the pre-distribution build process, so
to change it, you need the master repository files in ui_machines/...,
not a CPAN/PPM/tarball/.zip/etc. distribution.

=head1 COPYRIGHT

Copyright 2003, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1;
