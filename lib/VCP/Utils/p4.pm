package VCP::Utils::p4 ;

=head1 NAME

VCP::Utils::p4 - utilities for dealing with the p4 command

=head1 SYNOPSIS

   use base qw( ... VCP::Utils::p4 ) ;

=head1 DESCRIPTION

A mix-in class providing methods shared by VCP::Source::p4 and VCP::Dest::p4,
mostly wrappers for calling the p4 command.

If the P4::Client module is detected, this will be used to connect to
the p4d instead of the command line client.  If this causes undesirable
results, set the environment variable VCPP4API to "0" (zero):

   C:\> set VCPP4API=0  ## On Win32

   $ export VCPP4API=0  ## Depends on your shell

=cut

@EXPORT_OK = qw( underscorify_name p4_get_settings );
@ISA = qw( Exporter );
use Exporter;

use strict ;
use Carp;

use VCP::Debug qw( :debug :profile ) ;
use VCP::Logger qw( lg pr );
use VCP::Utils qw( empty is_win32 shell_quote xchdir start_dir_rel2abs );

use constant use_p4_api_if_present => (
        empty( $ENV{VCPP4API} ) || $ENV{VCPP4API}
    )
        ? 1
        : 0;

use constant have_p4_api => use_p4_api_if_present
   && eval "require P4::Client; require P4::UI";


=head1 METHODS

=over

=item p4

   $self->p4( [ "edit", $fn ] );
   $self->p4( [ "change", "-i" ], \$info_for_p4_stdin );

Calls the p4 command with the appropriate user, client, port, and password.

=cut

## NOTE: hacking in p4 API stuff for now, will need to refactor and
## clean it all up a lot when it works.
my $client;
{
   package VCP::P4::UI;

   use VCP::Logger qw( lg lg_fh );
   my $lg_fh = lg_fh;

   @VCP::P4::UI::ISA = qw( P4::UI );

   sub InputData {
      my $self = shift;
print $lg_fh "$self>>>>>>>${$self->{stdin}}\n";
      return $self->{stdin} && ( $self->{stdin} != \undef ) ? "${$self->{stdin}}" : "";
   }

   sub OutputText {
      my $self = shift;
print $lg_fh "[[[$_[0]]]]";
      $self->{stdout} && ( $self->{stdout} != \undef )
          ? ${$self->{stdout}} .= shift
          : ();
   }

   sub OutputStat {
   }

   sub OutputInfo {
      my $self = shift;
      my $level = shift;
print $lg_fh "$self [[[$_[0]]]]\n";
      $self->{stdout} && ( $self->{stdout} != \undef )
          ? ${$self->{stdout}} .= "... " x $level . shift() . "\n"
          : print $lg_fh "... " x $level, shift, "\n";
   }

   sub OutputError {
      my $self = shift;
      $self->{stderr} && ( $self->{stderr} != \undef )
          ? ${$self->{stderr}} .= shift
          : ();
   }
}

{
   package VCP::P4::UIScriptMode;

   ##
   ## Simulates `p4 -s` (script mode)
   ##
   ## TODO: make the caller API-aware once we're happy with the API
   ## so that its even faster.
   ##

   use VCP::Logger qw( lg lg_fh );
   my $lg_fh = lg_fh;

   @VCP::P4::UIScriptMode::ISA = qw( VCP::P4::UI );

   sub OutputText {
      my $self = shift;
print $lg_fh "[[[$_[0]]]]";
      $self->{stdout} && ( $self->{stdout} != \undef )
          ? ${$self->{stdout}} .= "text: " . shift
          : ();
   }

   sub OutputInfo {
      my $self = shift;
      my $level = shift;
print $lg_fh "$self [[[$_[0]]]]\n";
      $self->{stdout} && ( $self->{stdout} != \undef )
          ? ${$self->{stdout}} .= "info: " . ( "... " x $level ) . shift() . "\n"
          : print $lg_fh "... " x $level, shift, "\n";
   }

   sub OutputError {
      my $self = shift;
      print $lg_fh $_[0];
      $self->{stdout} && ( $self->{stdout} != \undef )
          ? ${$self->{stdout}} .= "error: " . shift
          : ();
   }
}



{
   package VCP::P4::UIForFileOutput;

   use VCP::Logger qw( lg lg_fh );
   my $lg_fh = lg_fh;

   @VCP::P4::UIForFileOutput::ISA = qw( VCP::P4::UI );

   sub OutputBinary {
      my $self = shift;
      my $fh = $self->{stdoutfh};
      print $fh $_[0];
   }

   sub OutputText {
      my $self = shift;
      my $fh = $self->{stdoutfh};
      print $fh $_[0];
   }

   sub OutputInfo {
      my $self = shift;
      my $level = shift;
      my $fh = $self->{stdoutfh};
      print $fh "... " x $level, shift, "\n";
   }
}


## We use Run() and force each command to be executed immediately
## instead of using RunTag() because RunTag() can't handle almost
## all of the functions we need.  Here's me proposing a way to use
## RunTag() and Christopher replying that we'd need to do this
## for almost all functions we need:
## 
## | Perhaps a place to start would be:
## |     - hardcoding a list of all such functions
## |     - calling the RunWait after each such function
## |
## | This could be done in the API's code or VCP's.
## 
## If you want to do this in the VCP for the time being, it would give us
## time to figure out how to fix it right (ugh).  Unfortunately, the list
## of functions includes a lot of the good ones: 
## 
##         diff
##         print
##         integrate
##         add/edit/delete
##         revert
##         reopen
##         resolve
##         submit
##         sync
## 
## I'm leaving the RunTag() code commented out because I haven't checked
## it in and I want to save it.  All those comments are prefixed with "RunTag():"
##
## RunTag(): my @uis;

sub _run_p4_api {
   my $self = shift;

   ## run_safely() calls this instead of run3( [ 'p4'... ] ... ), so we
   ## emulate run3()'s API.  This allows run_safely to do those things it
   ## does so well while we use the API behind the scenes.
   unless ( $client ) {
      pr "using p4 binary API";
      $client = P4::Client->new;

      $client->DebugLevel( debugging );
      $client->SetPort( $self->repo_server )
         if defined $self->repo_server;
      $client->Init() or die( "Failed to connect to Perforce Server" );
   }

   my @cmd = @{shift()};

   my %ios;
   @ios{qw( stdin stdout stderr )} = @_;
   $ios{stdin} = \${$ios{stdin}} if $ios{stdin};
   my $ui_class = "VCP::P4::UI";
   if ( $cmd[0] eq "-s" ) {
       shift @cmd;
       $ui_class = "VCP::P4::UIScriptMode";
   }
   my $slurp_tempfile;
   if ( defined $ios{stdout} ) {
      my $t = ref $ios{stdout};
      if ( ! $t ) {
         local *F;
         open F, ">$ios{stdout}" or die "$!: $ios{stdout}\n";
         binmode F;
         $ios{stdoutfh} = *F{IO};
         $ui_class = "VCP::P4::UIForFileOutput";
      }
      elsif ( $t eq "SCALAR" ) {
         ${$ios{stdout}} = undef;
      }
      elsif ( $t eq "CODE" ) {
         require File::Temp;
         $ios{stdoutfh} = File::Temp::tempfile();
         $slurp_tempfile = 1;
         $ui_class = "VCP::P4::UIForFileOutput";
      }
   }

   my $ui = $ui_class->new;

   %$ui = ( %$ui, %ios );

   profile_group ref( $self ) . " p4api " if profiling;
   profile_start ref( $self ) . " p4api " . $cmd[0] if profiling;

   $client->SetPassword( $self->repo_password ) if defined $self->repo_password;
   $client->SetClient  ( $self->repo_client   ) if defined $self->repo_client;
   $client->SetUser    ( $self->repo_user     ) if defined $self->repo_user;

   lg "\$ p4api ", join " ", shell_quote( @cmd );

   
   $client->Run( $ui, @cmd );
## RunTag():      $client->RunTag( $ui, @cmd );

## RunTag():     if (
## RunTag()          ( $ui->{stdout} && $ui->{stdout} != \undef )
## RunTag()          ||         diff
## RunTag()         print
## RunTag()         integrate
## RunTag()         add/edit/delete
## RunTag()         revert
## RunTag()         reopen
## RunTag()         resolve
## RunTag()         submit
## RunTag()         sync
## RunTag()  
## RunTag()       ) {
## RunTag()          lg "Waiting on $ui";
## RunTag()          $client->WaitTag;
## RunTag()          @uis = ();
## RunTag() lg "Done";
## RunTag()       }
## RunTag()       else {
## RunTag()          push @uis, $ui;
## RunTag()       }

   if ( $slurp_tempfile ) {
       seek $ui->{stdoutfh}, 0, 0 or die "$! rewinding temporary file";
       $ui->{stdout}->( $ui->{stdoutfh} );
   }

   close( $ui->{stdoutfh} ) if $ui->{stdoutfh};

   profile_end ref( $self ) . " p4api " . $cmd[0] if profiling;
}


sub p4 {
   my $self = shift ;

   my $p4_command = "";
   if ( profiling ) {
      profile_group ref( $self ) . " p4 ";
      for( @{$_[0]} ) {
         unless ( /^-/ ) {
            $p4_command = $_;
            last;
         }
      }
   }
   local $VCP::Debug::profile_category = ref( $self ) . " p4 $p4_command"
      if profiling;

   unless ( have_p4_api ) {
       local $ENV{P4PASSWD} = $self->repo_password if defined $self->repo_password ;
       unshift @{$_[0]}, '-p', $self->repo_server  if defined $self->repo_server ;
       unshift @{$_[0]}, '-c', $self->repo_client  if defined $self->repo_client ;
       unshift @{$_[0]}, '-u', $self->repo_user    if defined $self->repo_user ;

       ## PWD must be cleared because, unlike all other Unix utilities I
       ## know of, p4 looks at it and bases it's path calculations on it.
       ## localizing this was giving me some grief.  Can't recall what.
       my $args = shift ;

       $self->run_safely( [ "p4", @$args ], @_ ) ;
   }
   else {
       my $options = @_ && ref $_[-1] eq "HASH" ? pop : {};
       $options->{sub} = sub { $self->_run_p4_api( @_ ) };
       $self->run_safely( @_, $options );
   }
}


=item p4_x

Run p4 -x, feeding args to STDIN.

=cut

sub p4_x {
   my $self = shift;
   my @cmd = @{shift()};
   unless ( have_p4_api ) {
      $self->p4( [ "-x", "-", @cmd ], @_ );
   }
   else {
      ## A hack to let the caller pretend to feed an array
      ## of lines to p4's STDIN.  This is only done where
      ## the caller wants to pass a possibly huge list of
      ## filenames.   So we redirect it to the "command line"
      ## passed to the P4 API.
      ## This will break if any caller ever starts passing
      ## something other than command line args on STDIN.
      if ( ref $_[0] eq "ARRAY" ) {
         my $in = $_[0];
         $_[0] = undef;
         push @cmd, map { my $s = $_; chomp $s; substr( $s, 0, 1 ) eq "/" ? $s : $self->command_chdir . "/" . $s } @{$in};
      }
else{
}

      $self->p4( \@cmd, @_ );
   }
}


=item parse_p4_form

   my %form = $self->parse_p4_form( $form );
   my %form = $self->parse_p4_form( \@command_to_emit_form );

Parses a p4 form and returns a list containing the form's data elements
in the order that they were accumulated.  This is suitable for initializing
a hash if order's not important, or an array if it is.

You can pass the form in verbatim, or a reference to a command to run
to get the form.  If the first parameter is an ARRAY reference, all
parameters will be passed to C<$self->p4> with stdout redirected to
a temporary variable.

Multiline fields will have trailing C<\n>s in the data, single-line fields
won't.  All fields have leading spaces on each line removed.

Comments are tagged with a field name of "#", blank (containing only spaces
if that) are tagged with a " ".  This is to allow accurate reproduction
of the file if reemitted.

NOTE: This does not implement 100% compatible p4 forms parsing; it should
be upwards compatible and one day we should implement full forms parsing.

=cut

## this simulates the real C++ tokenizer built in to p4.  That tokenizes
## p4 forms with a state machine that knows about quoting, text blocks,
## etc.  Some layer above the parser informs the parser about whether or
## not the current field is a text block.  This parser tries to emulate that
## tokenizer's behavior without implementing a low level state machine.

sub parse_p4_form {
   my $self = shift;

   my $form;
   
   if ( ref $_[0] eq "ARRAY" ) {
      $self->p4( $_[0], undef, \$form, @_[1..$#_] )
   }
   else {
      $form = shift;
   }

   my @lines = split /\r?\n/, $form;

   my @entries;
   my $cat;  ## Set when catenating lines together in a comment or value
   my $blanks = 0;

   for ( @lines ) {
      ++$blanks, next if /^$/;
      next if /^#/;

#      if ( s/^\s*#\s*(.*)/$1/ ) {
#         $blanks = 0;
#         unless ( @entries && $entries[-2] eq "#" ) {
#            chomp $entries[-1] if $cat;
#            push @entries, ( "#", "" );
#            $cat = 1;
#         }
#      }
#      elsif ( /^([A-Za-z]+):[ \t]*(?:(\S.*))?\z/ ) {
      if ( /^([A-Za-z_]+):[ \t]*(?:(\S.*))?\z/ ) {
         chomp $entries[-1] if $cat;
         $cat = undef;
         $blanks = 0;

         push @entries, $1;
         if ( defined $2 ) {
            local $_ = $2;
            s/(^|[ \t]+)#.*//;
            push @entries, length $_ ? "$_\n" : "";
         }
         else {
            push @entries, "";
         }
         $cat = 1;
         next;
      }

      if ( $cat ) {
         s/^\s//;  ## This may be too general.  May need to trim the same
                    ## number of characters from each line.
         $entries[-1] .= "\n" x $blanks;
         $blanks = 0;
         s/(^|[ \t]+)#.*//;
         $entries[-1] .= $_ . "\n";
      }
      elsif ( ! length ) {
         next;
      }
      else {
         ## We warn instead of dieing in case p4 can output things we don't
         ## expect.  TODO: This could be bad, change to die() with a
         ## syntax error.
         pr "ignoring '$_' from p4 output\n";
      }
   }
   chomp $entries[-1] if $cat;
   return @entries;
}


=item build_p4_form

   my $form = $self->build_p4_form( @form_fields );
   my $form = $self->build_p4_form( %form_fields );
   $self->build_p4_form( ..., \@command_to_emit_form );

Builds a p4 form and either returns it or submits it to the indicated command.

=cut

sub build_p4_form {
   my $self = shift;

   my @form;
   
   while ( @_ ) {
      last if ref $_[0] eq "ARRAY";  ## rest is a command.
      my ( $name, $value ) = ( shift, shift );

      if ( $name eq "#" ) {
         $value =~ s/^/# /mg;
         chomp $value;
         push @form, $value, "\n\n";
         next;
      }

      push @form, ( $name, ":" );

      if ( $value =~ tr/\n// ) {
         push @form, "\n";
         $value =~ s/^(?!$)/\t/gm;
         chomp $value;
         push @form, $value, "\n\n";
      }
      else {
         push @form, ( " ", $value, "\n\n" );
      }
   }

   my $form = join "", @form;
   @form = ();

   $self->p4( $_[0], undef, \$form, @_[1..$#_] ) if @_;

   return $form;
}


=item parse_p4_repo_spec

Calls $self->parse_repo_spec, then post-processes the repo_user in to a user
name and a client view. If the user specified no client name, then a client
name of "vcp_tmp_$$" is used by default.

This also initializes the client to have a mapping to a working directory
under /tmp, and arranges for the current client definition to be restored
or deleted on exit.

=cut

sub parse_p4_repo_spec {
   my $self = shift ;
   my ( $spec ) = @_ ;

   $self->parse_repo_spec( $spec ) ;
};


sub set_up_p4_user_and_client {
   my $self = shift ;

   my ( $user, $client ) ;
   ( $user, $client ) = $self->repo_user =~ m/([^()]*)(?:\((.*)\))?/
      if defined $self->repo_user ;
   $client = "vcp_tmp_$$" if empty $client ;

   $self->repo_user( $user ) ;
   $self->repo_client( $client ) ;

   if ( $self->can( "min" ) ) {
      my $filespec = $self->repo_filespec ;

      ## If a change range was specified, we need to list the files in
      ## each change.  p4 doesn't allow an @ range in the filelog command,
      ## for wataver reason, so we must parse it ourselves and call lots
      ## of filelog commands.  Even if it did, we need to chunk the list
      ## so that we don't consume too much memory or need a temporary file
      ## to contain one line per revision per file for an entire large
      ## repo.
      my ( $name, $min, $comma, $max ) ;
      ( $name, $min, $comma, $max ) =
	 $filespec =~ m/^([^@]*)(?:@(-?\d+)(?:(\D|\.\.)((?:\d+|#head)))?)?$/i
	 or die "Unable to parse p4 filespec '$filespec'\n";

      lg "parsed '$filespec' as :",
         join " ", map defined $_ ? "'$_'" : "<<undef>>", $name, $min, $comma, $max
         if debugging;

      die "'$comma' should be ',' in change_id range in '$filespec'\n"
	 if defined $comma && $comma ne ',' ;

      if ( ! defined $min ) {
	 $min = 1 ;
	 $max = '#head' ;
      }

      if ( ! defined $max ) {
	 $max = $min ;
      }
      elsif ( lc( $max ) eq '#head' ) {
	 $self->p4( [qw( counter change )], undef, \$max ) ;
	 $max =~ tr/\r\n//d;
      }

      if ( $max == 0 ) {
         ## TODO: make this a "normal exit"
         die "Current change number is 0, no work to do\n";
      }

      if ( $min < 0 ) {
	 $min = $max + $min ;
      }

      $self->repo_filespec( $name ) ;
      $self->min( $min ) ;
      $self->max( $max ) ;
   }

   $self->init_p4_view;
}


=item init_p4_view

   $self->init_p4_view

Borrows or creates a client with the right view.  Only called from
VCP::Dest::p4, since VCP::Source::p4 uses non-view oriented commands.

=cut

sub init_p4_view {
   my $self = shift ;

   my $client = $self->repo_client ;

   ## Temporarily unset the client so that $self->p4(...) doesn't
   ## pass it on the command line when we do `p4 clients`
   $self->repo_client( undef ) ;
   my $client_exists = grep $_ eq $client, $self->p4_clients ;
   debug "client '$client' exists" if debugging && $client_exists;
   $self->repo_client( $client ) ;

   my $client_spec = $self->p4_get_client_spec ;
## work around a wierd intermittant failure on Win32.  The
## Options: line *should* end in nomodtime normdir
## instead it looks like:
##
## Options:	noallwrite noclobber nocompress unlocked nomÔ+
##
## but only occasionally!
$client_spec = $self->p4_get_client_spec
    if $^O =~ /Win32/ && $client_spec =~ /[\x80-\xFF]/;

   my $original_client_spec = $client_exists ? $client_spec : undef;

   my $p4_spec = $self->repo_filespec ;
   $p4_spec = "//..." if empty $p4_spec;

   die "p4 file specification must not end in a '/' or '\\': '$p4_spec'\n"
       if $p4_spec =~ m{[\\/]\z};

   my $client_path = "//$client";

   if ( $p4_spec =~ m{\/\.\.\.\z} ) {
      $client_path .= "/...";
   }
   else {
      $p4_spec =~ m{/([^/]*)\z}
         or die "p4 file specification must begin with a '/': '$p4_spec'\n";
      $client_path .= "/$1";
   }

   ## For VCP::Source::p4, we need to sync in to the "co" directory
   ## and then link() over to a forest of revisions (/path/to/file/13
   ## where 13 is a rev_id).  So we place the p4 command's working
   ## directory and the client's Root in to the "co" dir.
   $self->command_chdir( $self->work_path( "co" ) );
   my $work_dir = $self->command_chdir;

   $client_spec =~ s{^Root[^\r\n]*}{Root:\t$work_dir}m ;
   $client_spec =~ s{^View.*}{View:\n\t"$p4_spec"\t"$client_path"\n}ms ;
   $client_spec =~ s{^(Options:[^\r\n]*)}{$1 nocrlf}m 
      if $^O =~ /Win32/ ;
   $client_spec =~ s{^LineEnd[^\r\n]*}{LineEnd:\tunix}mi ;

   debug "using client spec:\n", $client_spec if debugging ;

   $self->p4_set_client_spec( $client_spec ) ;

   $self->queue_p4_restore_client_spec( $original_client_spec );
}

=item p4_clients

Returns a list of known clients.

=cut

sub p4_clients {
   my $self = shift ;

   my $clients ;
   pr "running p4 clients";
   $self->p4( [ "clients", ], undef, \$clients ) ;
   return map { /^Client (\S*)/ ; $1 } split /\n/m, $clients ;
}

=item p4_get_client_spec

Returns the current client spec for the named client. The client may or may not
exist first, grep the results from L</p4_clients> to see if it already exists.

=cut

sub p4_get_client_spec {
   my $self = shift ;
   my $client_spec ;
   $self->p4( [ "client", "-o" ], undef, \$client_spec ) ;
   return $client_spec ;
}


=item p4_get_settings

gets all p4 variables/config info available from the 'p4 set' command,
and puts them into a hash and returns a reference to it.  These are
the settings which were set via a p4 config file or environment variables (*nix),
or the registry (windows).

=cut

sub p4_get_settings {
   open F, "p4 set|" or die "couldn't run p4 command";
   my %h;
   while(<F>) {
      die "unexpected output from 'p4 set'"
         unless /^(P4[A-Z]+)=(.*)$/ ;
      my ($var, $val) = ($1, $2);

      # there might be lines like P4USER=bob (config)
      # indicating that a value was read from the config file.
      # strip these parenthesized things out, along with any
      # extra whitespace.
      $val =~ s/\s*\(.*\)\s*$// ;
      
      $h{$var} = $val;
   }
   close F;

   return \%h;
}




=item queue_p4_restore_client_spec

   $self->queue_p4_restore_client_spec( $client_spec ) ;

Saves a copy of the named p4 client and arranges for it's restoral on exit
(assuming END blocks run). Used when altering a user-specified client that
already exists.

If $client_spec is undefined, then the named client will be deleted on
exit.

Note that END blocks may be skipped in certain cases, like coredumps,
kill -9, or a call to POSIX::exit().  None of these should happen except
in debugging, but...

=cut

my @client_backups ;
my @p4ds_to_kill;

END {
   my $child_exit;
   {
      local $?;  ## Protect this; we're about to run a child process and
                 ## we want to exit with the appropriate value.
      for ( @client_backups ) {
         my ( $object, $name, $spec ) = @$_ ;
         my $tmp_name = $object->repo_client ;
         $object->repo_client( $name ) ;
         if ( defined $spec ) {
            $object->p4_set_client_spec( $spec ) ;
         }
         else {
            my $out ;
            my $ok = eval {
               $object->p4(
                  [ "client", "-df", $object->repo_client ], undef, \$out
               );
               1;
            };
            if ( $ok ) {
               pr "unexpected stdout from p4:\np4: ", $out
                  unless $out =~ /^Client\s.*\sdeleted./ ;
            }
            else {
               my $msg = $@;
               $msg =~ s/^/    /mg;
               $out =~ s/^/    /mg;
               pr "WARNING: p4 client ",
                   $object->repo_client,
                   " may not have been deleted:\n",
                   $out, $msg;
            }
            $child_exit = $?;
         }
         $object->repo_client( $tmp_name ) ;
         $_ = undef ;
      }
      @client_backups = () ;
   }
   $? = $child_exit if $child_exit && ! $?;
   __PACKAGE__->kill_all_vcp_p4ds;
}


sub queue_p4_restore_client_spec {
   my $self = shift ;
   my ( $client_spec ) = @_ ;
   push @client_backups, [ $self, $self->repo_client, $client_spec ] ;
}

=item p4_set_client_spec

   $self->p4_set_client_spec( $client_spec ) ;

Writes a client spec to the repository.

=cut


sub p4_set_client_spec {
   my $self = shift ;
   my ( $client_spec ) = @_ ;

   ## Capture stdout so it doesn't show through to user.
   $self->p4( [ "client", "-i" ], \$client_spec, \my $out ) ;

   die "unexpected stdout from p4:\np4: ", $out
      unless $out =~ /^Client\s.*\ssaved\./ ;
}

=item split_repo_server

Splits the repo_server field in to $host and $port sections, where
$host may be a directory name (when --run-p4d or --init-p4d in effect).

This is a separate method in order to encapsulate splitting of
paths with a volumn name on Win32 (can extend to other OSs as needed).

=cut

sub split_repo_server {
   my $self = shift;
   is_win32
       ? do {
          my $s = $self->repo_server;
          ## Expect possible drive letter.
          $s =~ m{\A((?:[A-Za-z]:)?[^:]*)(?::([^:]*))?\z};
          ( $1, $2 );
       }
       : ( split ":", $self->repo_server, 2 );

}

=item run_p4d

Runs a p4d instance in the directory indicated by repo_server (use a directory
path in place of a host name).  If repo_server contains a port, that port
will be used, otherwise a random port will be used (and placed back in to
repo_server so the p4 client can find it).

Dies unless the directory exists and contains files matching db.* (to
help prevent unexpected initting of empty directories).

=cut
   

sub run_p4d {
   my $self = shift;

   my ( $dir, $port ) = $self->split_repo_server;

   die "Can't run p4d in non-existant directory '$dir'\n"
      unless -e $dir;
   die "Can't run p4d in non-directory '$dir'\n"
      unless -d $dir;

   my @files;

   @files =  glob "$dir/db.*" if -d $dir;

   die "cannot --run-p4d on dir '$dir' with no 'db.*' files\n"
      unless @files;

   $port = $self->launch_p4d( $dir, $port );
   $self->repo_server( "localhost:$port" );
}



=item launch_p4d

VCP can use its own p4d, this sub is used to launch it and queue its
demise when the program exits.

The $p4root argument is required.  The $p4port is optional; if
undefined, a random p4 port is chosen (if the random port is already in
use, successive random ports will be chosen up to 10 times until an
unused port is found)

The return value is the p4 port.

TODO: Make VCP.pm kill things when the transfer is over and only use
END{} subs if that fails.

=cut

sub try_p4d {
   my ( @cmd_line ) = @_;

   pr '$ ', shell_quote @cmd_line;

   require File::Temp;
   local *P4DOUT = File::Temp::tempfile();
   binmode P4DOUT or die "$!: P4DOUT\n";

   ## This suppresses used only once warnings and ensures that the
   ## saved files are closed on exit.
   local *SAVE_STDOUT;
   local *SAVE_STDERR;

   my $p4dpid;
   {
      open SAVE_STDOUT, ">&STDOUT" or die "vcp: $! saving STDOUT for P4DOUT\n";
      open SAVE_STDERR, ">&STDERR" or die "vcp: $! saving STDERR for P4DOUT\n";

      open STDOUT, ">& P4DOUT" or die "vcp: $! STDOUT >& P4DOUT\n";
      open STDERR, ">& P4DOUT" or die "vcp: $! STDERR >& P4DOUT\n";

      if ( is_win32 ) {
         $p4dpid = system 1, @cmd_line;
      }
      else {
         $p4dpid = fork();
         unless ( $p4dpid ) {
             exec @cmd_line
                or die "$! error: ", shell_quote( @cmd_line ), "\n";
                ## the word "error" triggered the $p4dout =~ /error/
                ## regex below.
         }
      }

      open STDERR, ">&SAVE_STDERR"
         or die "vcp: $! restoring STDERR for P4DOUT\n";
      open STDOUT, ">&SAVE_STDOUT"
         or die "vcp: $! restoring STDOUT for P4DOUT\n";

      die "$! running p4d" unless defined $p4dpid;
   }

   my $time = 0.01;
   my $total_time = 0;
   my $p4dout;
   my $error_looped_once;

   while ( $total_time < 10 ) {
       $total_time += $time;
       select undef, undef, undef, $time;
       $time *= 10;
       $time = 1 if $time > 1;

       sysseek P4DOUT, 0, 0 or die "vcp: $! seeking on p4d output temp file\n";

       sysread P4DOUT, $p4dout, 10000;

       return ( $p4dpid, $p4dout ) if $p4dout =~ /Perforce Server starting/i;
       if (
          $p4dpid <= 0
             ## The system() command may fail and issue an error message
             ## to STDERR.  In which case, it returns a -1 into $p4dpid
             ## and we need to recover the STDOUT emmissions.
          || $p4dout =~ /error/i
       ) {

          last if $error_looped_once;

          ## Give it time to finish emitting output.
          $time = 0.1;
          $total_time = 0;
          $error_looped_once = 1;
       }
   }

   close P4DOUT;

   kill TERM => $p4dpid if defined $p4dpid && $p4dpid >= 0;

   return ( undef, $p4dout );
}

sub launch_p4d {
   { my $self = shift; }
   my ( $p4root, $p4port ) = @_;

   $p4root = start_dir_rel2abs( $p4root );

   require VCP::Utils;

   my $h ;
   my $pick_a_port = ! defined $p4port;
   my $launch_attempts = 0;

   while (1) {
      ++$launch_attempts;

      # use a random port if the caller hasn't provided one
      while ( ! defined $p4port ) {
         ## 30_000 is because I vaguely recall some TCP stack that had
         ## problems with listening on really high ports.
         ## 2048 is because I vaguely recall
         ## that some OS required root privs up to 2047 instead of 1023.
         $p4port = ( rand( 65536 ) % 30_000 ) + 2048 ;
         $p4port = undef if $p4port == 1666;
      }

      my @p4d = ( "p4d", "-f", "-r", $p4root, "-p", $p4port ) ;

      my ( $pid, $p4dout ) = try_p4d @p4d;

      if ( defined $pid ) {
         push @p4ds_to_kill, $pid;
         last;
      }

      unless (
             $pick_a_port
             && $p4dout =~ /listen.*failed/
             && $launch_attempts < 10
      ) {
         $p4dout =~ s/^/    /mg;
         die 
            "p4d failed to start (made $launch_attempts attempts):\n",
            "    \$ ", VCP::Utils::shell_quote( @p4d ), "\n",
            $p4dout;
      }
      lg $p4dout;
      undef $p4port;
   }

   return $p4port;
}


=item kill_all_vcp_p4ds

Kills all p4ds that have been started by this VCP process.

=cut

sub kill_all_vcp_p4ds {
   local $?;
   while ( @p4ds_to_kill ) {
      my $pid = shift @p4ds_to_kill;
      pr "shutting down p4d\n";
      kill TERM => $pid or pr "$! killing p4d\n";
      select undef, undef, undef, 0.1; ## Give p4d a chance to exit so
                                       ## File::Temp can delete P4DOUT
   }
}


=item underscorify_name

Converts special characters ('#', '@', whitespace and non-printing character
codes) in branch, label, and client names in to other symbols.

   "a " => "a_20_"

NOTE: I have not been able to find a description of the set of legal p4
names (namelength, character set, etc).  This is purely a first attempt,
if you have details on this, please let me know.

=cut

sub underscorify_name {
   my @out = @_;
   for ( @out ) {
      s/([#\@[:^graph:]])/sprintf( "_%02x_", ord $1 )/ge;
   }

   wantarray ? @out : @out > 1 ? confess "Returning multiple tags in scalar context" : $out[0];
}


=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
