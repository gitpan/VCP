package VCP::Logger;

=head1 NAME

VCP::Logger - Update message, bug, and Log file management

=head1 SYNOPSIS

   use VCP::Logger qw( shell_quote );

=head1 DESCRIPTION

Does not throw exceptions or use the debug module, so this is safe to
use with both.  Load this as the very first module in your program.

The log file name defaults to "vcp.log", set the environment
variable VCPLOGFILE to change it.  Here's how to do this in your
program:

   BEGIN {
      $ENV{VCPLOGFILE} = "foo.bar"
         unless defined $ENV{VCPLOGFILE} || length $ENV{VCPLOGFILE};
   }

=cut

@EXPORT_OK = qw(
   BUG
   lg
   lg_fh
   log_file_name
   pr
   pr_active
   pr_did
   pr_doing
   pr_done
   pr_done_failed
   program_name
   start_time
);

@ISA = qw( Exporter );
use Exporter;

use strict ;
use Carp;
use File::Basename qw( basename );

use constant program_name => basename $0;
use constant log_file_name => 
   defined $ENV{VCPLOGFILE} && length $ENV{VCPLOGFILE}
      ? $ENV{VCPLOGFILE}
      : "vcp.log";

my $quiet_mode = 0;

=head1 FUNCTIONS

=over

=item lg

Prints a timestamped message to the log.  Adds a trailing newline if
need be.  The first word of the message should not be capitalized
unless it's a name or acronym; this makes grepping a bit easier
(same for all error messages).

"lg" is "log" abbreviated so as not to conflict with Perl's builtin
log().

The timestamps are in integer seconds since this module was compiled
unless you have Time::HiRes install in which case they are in floating
point seconds.

Should not throw an exception or alter $@ in the normal course of events
(does not call any routines that should do so).

=cut

my $start_time;

## We "gracefully" degrade to 1 second resolution if no Time::HiRes.
BEGIN { eval "use Time::HiRes qw( time )" }

BEGIN {
   $start_time = time;
}

{
   my $s1;  BEGIN { $s1 = program_name . ": " }

   sub _msg {
      my $msg = join "", map defined $_ ? $_ : "(((UNDEF)))", @_;
      1 while chomp $msg;
      $msg =~ s/^$s1//o; ## TODO: go 'round and get rid of all the vcp: prefixes
      join $msg, $s1, "\n";
   }

   my $log_failure_warned;

   sub _lg {
      print LOG (
         sprintf( "%f ", time - $start_time ),
         @_
      ) or $log_failure_warned++
         or warn "$! writing ", program_name, " log file ", log_file_name, "\n";
   }

}


sub lg {
  _lg &_msg;
}

=item lg_fh

Returns a reference to the log filehandle (*LOG{IO}) so you can emit
to the log directly.  The log is flushed after every write, so this should
be quite safe.

=cut

sub lg_fh { *LOG{IO} }

=item pr

Print a status notification to STDERR (unless in quiet mode) and log it.

=cut

my $doing;
my %did;
my @did_keys;
my $last_progress;
my $need_progress_prompt;
my $expect;
my $count;
my $spinner_pos;
my $last_char_count;
my $fmt;

my $bar_width = 10;
my @spinner = qw( - \ | / - \ | / );

sub _reset_progress {
   $expect = 0;
   $count = 0;
   $last_char_count = 0;
   $spinner_pos = 0;
   $last_progress = "";
   $need_progress_prompt = 0;
   @did_keys = ();
   %did = ();
}


sub _start_progress {
   $need_progress_prompt = 1;
   if ( ! $expect || $expect < 0 ) {
      $expect = 0;
   }
   else {
      my $l = length $expect;
      $fmt = "[%-${bar_width}s] %${l}d/$expect";
   }
}


sub _char_count {
   my ( $count ) = @_;
   return $bar_width if $count >= $expect;

   return int( $bar_width * $count / $expect );
       ## Do not ever return a full bar in mid-process
}


sub _interrupt_progress {
   return unless defined $doing && ! $need_progress_prompt;
   print STDERR "\n";
   $last_progress = "";
   $need_progress_prompt = 1;
}

sub _show_progress {
   my $progress;
   if ( $expect ) {
      my $char_count = _char_count $count;

      my $chars = join "", 
         "#" x $char_count,
         $char_count < $bar_width
            ? $spinner[ $spinner_pos++ & 0x07 ]
            : ();

      $progress = sprintf $fmt, $chars, $count;

      $last_char_count      = $char_count;
   }
   else {
      $progress = $spinner[ $spinner_pos++ & 0x07 ] . " " . $count;
   }

   $progress .= join "", map " $_ $did{$_}", @did_keys;

   $progress .= " ";  ## So there's a space before any truely unexpected
                      ## errors perl might emit.
   
   print STDERR
      $need_progress_prompt
         ? $doing
         : defined $last_progress
            ? "\010" x length $last_progress
            : (),
      $progress;
   $last_progress = $progress;
   $need_progress_prompt = 0;
}


sub pr {
   _interrupt_progress;

   my $msg = &_msg;
   print STDERR $msg unless $quiet_mode;
   _lg $msg;
}


=item pr_doing

   pr_doing "Fooo";
   pr_doing "Fooo", { ...options... };
   pr_doing;  ## to show progress

Print a status notification and show progress.  Call repeatedly to
show continuing progress.  Works with pr() to manage lineends.

Call with no parameters to show progress on the current task.  Call
pr_done or pr_done_failed to finish up.

Options:

    Expect   => $c, # There should be this number of calls, total, not
                    # including the call with the options set..

=cut

sub pr_doing {
   if ( @_ ) {
      my $options = ref $_[-1] eq "HASH" ? pop : undef;
      my $msg = &_msg;
      1 while chomp $msg;
      if ( $options || ! defined $doing || $doing ne $msg ) {
         _reset_progress;

         if ( $options ) {
            $expect = $options->{Expect};
         }

         print STDERR " completed (perhaps; pr_done() not called)\n"
            if defined $doing;

         $doing = $msg;
         _lg $doing, "\n";
      }

      _start_progress;
      return;
   }

   ++$count;

   _show_progress;
}

=item pr_did

    pr_did $what, $status;

Adds a message to the progress bar, does not affect progress otherwise.

Useful to display additional progress metrics.

Call before pr_doing.

=cut

sub pr_did {
    my ( $what, $status ) = @_;
    lg "did ", $what, " ", $status;
    push @did_keys, $what unless exists $did{$what};
    $did{$what} = $status;
}

=item pr_active

Show that we're active.

=cut

sub pr_active {
   _show_progress if defined $doing;
}


=item p4_done

Called to end a "pr_doing" sucessfully.  Logs the completion bug does not
emit to STDERR.  Prints and logs any message passed.

=cut

sub pr_done {
   return unless defined $doing;
   _lg $doing, " completed\n";
   print STDERR "\n";
   _reset_progress;
   $doing = undef;
   goto &pr if @_;
}

=item p4_done_failed

Called to end a "pr_doing" in dismal failure.  Logs the (in)completion and
and emits a message to the log and STDERR if one is passed.

=cut

sub pr_done_failed {
   print STDERR "\n";
   _lg $doing, " FAILED\n";
   $doing = undef;
   $need_progress_prompt = 0;
   goto &pr if @_;
}

BEGIN {
   open LOG, ">>" . log_file_name or die "$!: " . log_file_name . "\n";

   ## Flush the LOG every print() so that we never miss data and
   ## so that we can pass the log to child processes to emit STDOUT
   ## and STDERR to.
   select LOG;
   $| = 1;
   select STDOUT;

   ## Print a header line guaranteed to start at the beginning of a
   ## line.
   print LOG "\n", "#" x 79, "\n";
   lg "started ",
      scalar localtime $start_time,
      " (",
      scalar gmtime $start_time,
      " GMT)";
}

END {
   lg "ended";
}

=item BUG

Reports a bug using Carp::confess and logging the information.

=cut

sub BUG {
   _interrupt_progress;

   print STDERR "\n";
   print STDERR "***BUG REPORT***\n", @_, "\n";
   print STDERR "Please see ", log_file_name, "\n";
   print LOG "***BUG REPORT***\n", @_, "\n";

   open STDOUT, ">&LOG" or warn "$! redirecting STDOUT to LOG\n";
   open STDERR, ">&LOG" or warn "$! redirecting STDOUT to LOG\n";
   print LOG "\n\%INC:\n";
   print LOG "    $_ => '$INC{$_}'\n" for sort keys %INC;
   print LOG "\n";
   require Carp;
   eval { Carp::confess "stack trace" };
   warn $@;
   system $^X, "-V" and warn "$! getting perl -V\n";

   exit 1;
}

=item start_time

Returns the time the application started.  This is a floating point
number if Time::HiRes was found.

=cut

sub start_time() { $start_time }

=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
