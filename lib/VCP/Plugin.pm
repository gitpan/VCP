package VCP::Plugin ;

=head1 NAME

VCP::Plugin - A base class for VCP::Source and VCP::Dest

=head1 SYNOPSIS

=head1 DESCRIPTION

Some functionality is common to sources and destinations, such as
cache access, Pod::Usage conversion, command-line access shortcut
member, etc.

=head1 EXTERNAL METHODS

=over

=cut

use strict ;

use Carp ;
use File::Basename ;
use File::Path ;
use File::Spec ;
use IPC::Run ;
use UNIVERSAL qw( isa ) ;
use VCP::Debug ':debug' ;
use VCP::Rev ;

use vars qw( $VERSION $debug ) ;

$VERSION = 0.1 ;

$debug = 0 ;

use fields (
   'WORK_ROOT',     ## The root of the export work area.
   'COMMAND',       ## The full path to the command-line.
   'COMMAND_CHDIR', ## Where to chdir to when running COMMAND
   'COMMAND_STDERR_FILTER', ## How to modify the stderr when running a command
   'COMMAND_OK_RESULT_CODES', ## HASH keyed on acceptable COMMAND return vals
   'REV_ROOT',
   'SEEN',          ## HASH of previosly seen filename/revisions.
   'REPO_USER',     ## The user name to log in to the repository with, if any
   'REPO_PASSWORD', ## The password to log in to the repository with, if any
   'REPO_SERVER',   ## The repository to connect to
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

   my $self ;

   {
      no strict 'refs' ;
      $self = bless [ \%{"$class\::FIELDS"} ], $class ;
   }

   my $plugin_dir = ref $self ;
   $plugin_dir =~ tr/A-Z/a-z/ ;
   $plugin_dir =~ s/^VCP:://i ;
   $plugin_dir =~ s/::/-/g ;
   $self->work_root( File::Spec->tmpdir, "vcp$$", $plugin_dir ) ;
   rmtree $self->work_root if -e $self->work_root ;
   $self->{SEEN} = {} ;

   $self->{COMMAND_OK_RESULT_CODES} = { 0 => undef } ;

   return $self ;
}


###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=head2 SUBCLASS API

These methods are intended to support subclasses.

=over

=item seen

   $old_rev = $self->seen( $new_rev ) ;
   $old_r = $self->seen( $name ) ;

Called to register the fact that $new_rev has been seen, and
to return the last request for the same resource, which refers to the
previous version of the resource.  If a plain scalar is passed, simply
returns the last rev structure that was seen for that filename (but
does not mark that filename as having been seen if it hasn't).

This is one of the few accessor methods in VCP's implementation that returns
the previous value.

=cut

sub seen {
   my VCP::Plugin $self = shift ;
   my ( $arg ) = @_ ;

   confess "SEEN not initted: need to call SUPER::new?"
      unless defined $self->{SEEN} ;

   if ( ref $arg ) {
      my VCP::Rev $r = $arg ;
      my $old_r = $self->{SEEN}->{$r->name} ;
      $self->{SEEN}->{$r->name} = $arg ;
      return $old_r ;
   }
   else {
      return exists $self->{SEEN}->{$arg} && $self->{SEEN}->{$arg} ;
   }
}


=item delete_seen

Deletes the last seen revision for a file.  Returns nothing.

=cut

sub delete_seen {
   my VCP::Plugin $self = shift ;
   my ( $arg ) = @_ ;

   confess "SEEN not initted: need to call SUPER::new?"
      unless defined $self->{SEEN} ;

   delete $self->{SEEN}->{$arg->name} ;
   return ;
}

=item none_seen

Returns TRUE if $dest->seen( $r ) has not yet been called.

=cut

sub none_seen {
   my VCP::Plugin $self = shift ;

   ## This can happen if a subclass forgets to init it's base class(es).
   confess "Oops" unless defined $self->{SEEN} ;

   return ! %{$self->{SEEN}} ;
}


=item parse_repo_spec

   my $spec = $self->split_repo_spec( $spec ) ;

This splits a repository spec in one of the following formats:

   scheme:user:passwd@server:file_spec
   scheme:user@server:file_spec
   scheme::passwd@server:file_spec
   scheme:server:file_spec
   scheme:file_spec

in to a HASH reference like

   $hash = {
      SCHEME    => 'scheme',
      USER      => 'user',
      PASSWORD  => 'password',
      SERVER    => 'server',
      FILES     => 'file_spec',
   } ;

.  The spec is parsed from the edges in in this order:

   1. SCHEME (up to first ':')
   2. FILES  (after last ':')
   3. USER, PASSWORD (before first '@')
   4. SERVER (everything left.

This approach allows the FILES string to contain '@', and the SERVER
string to contain ':' and '@'.  USER can contain ':'.  Funky, but this
works well, at least for cvs and p4.

If a section of the repo spec is not present, the corresponding entry
in $hash will not exist.

The attributes repo_user, repo_password and repo_server are set
automatically by this method.  It does not store the SCHEME anyware
since the SCHEME is usually ignored by the plugin (the plugin is
selected using the scheme, so it knows the scheme implicitly), and
the FILES setting often needs extra manipulation, so there's no point
in storing it.

=cut

sub parse_repo_spec {
   my VCP::Plugin $self = shift ;

   my ( $spec ) = @_ ;

   my $result ;

   for ( $spec ) {
      return $result unless s/^([^:]*)(?::|$)// ;
      $result->{SCHEME} = $1 ;

      return $result unless s/(?:^|:)([^:]*)$// ;
      $result->{FILES} = $1 ;

      if ( s/^([^\@]*?)(?::([^\@:]*))?@// ) {
         if ( defined $1 ) {
	    $result->{USER}     = $1 ;
	    $self->repo_user( $1 ) ;
	 }

         if ( defined $2 ) {
	    $result->{PASSWORD} = $2 ;
	    $self->repo_password( $2 ) ;
	 }
      }

      return $result unless length $spec ;
      $result->{SERVER} = $spec ;
      $self->repo_server( $spec ) ;
   }

   return $result
}



=item usage_and_exit

   GetOptions( ... ) or $self->usage_and_exit ;

Used by subclasses to die if unknown options are passed in.

Requires Pod::Usage when called.

=cut

## TODO: Move to VCP::Plugin
sub usage_and_exit {
   my VCP::Plugin $self = shift ;

   require Pod::Usage ;
   my $f = ref $self ;
   $f =~ s{::}{/}g ;
   $f .= '.pm' ;

   for ( @INC ) {
      my $af = File::Spec->catfile( $_, $f ) ;
      if ( -f $af ) {
	 Pod::Usage::pod2usage(
	    -input   => $af,
	    -verbose => 0,
	    -exitval => 2,
	 ) ;
	 confess ;
      }
   }

   die "can't locate '$f' to print usage.\n" ;
}


=item work_path

   $full_path = $self->work_path( $filename, $rev ) ;

Returns the full path to the working copy of the local filename.

Each VCP::Plugin gets thier own hierarchy to use, usually rooted at
a directory named /tmp/vcp$$/plugin-source-foo/ for a module
VCP::Plugin::Source::foo.  $$ is vcp's process ID.

This is typically $work_root/$filename/$rev, but this may change.
$rev is put last instead of first in order to minimize the overhead of
creating lots of directories.

It *must* be under $work_root in order for rm_work_path() to fully
clean.

All directories will be created as needed, so you should be able
to create the file easily after calling this.  This is only
called by subclasses, and is optional: a subclass could create it's
own caching system.

Directories are created mode 0775 (rwxrwxr-x), subject to modification
by umask or your local operating system.  This will be modifiable in
the future.

=cut

sub work_path {
   my VCP::Plugin $self = shift ;

   my $path = File::Spec->canonpath(
      File::Spec->catfile( $self->work_root, @_ )
   ) ;

   return $path ;
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
   my VCP::Plugin $self = shift ;

   my ( $path, $mode ) = @_ ;
   $mode = 0770 unless defined $mode ;

   unless ( -d $path ) {
      debug "vcp: mkdir $path, ", sprintf "%04o", $mode if debugging $self ;
      mkpath( $path, 0, $mode ) ;
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
   my VCP::Plugin $self = shift ;

   my ( $path, $mode ) = @_ ;

   my ( undef, $dir ) = fileparse( $path ) ;

   $self->mkdir( $dir, $mode ) ;

   return $dir ;
}


=item rm_work_path

   $self->rm_work_path( $filename, $rev ) ;
   $self->rm_work_path( $dirname ) ;

Removes a directory or file from the work.  Also removes any and
all directories that become empty as a result up to the
work root (/tmp on Unix).

=cut

sub rm_work_path {
   my VCP::Plugin $self = shift ;

   my $path = $self->work_path( @_ ) ;

   if ( defined $path && -e $path ) {
      debug "vcp: rmtree $path" if debugging $self ;
      rmtree $path or die "$!: $path" ;
   }

   my $root = $self->work_root ;

   if ( substr( $path, 0, length $root ) eq $root ) {
      while ( length $path > length $root ) {
	 ( undef, $path ) = fileparse( $path ) ;
	 ## TODO: More discriminating error handling.  But the error emitted
	 ## when a directory is not empty may ## differ from platform
	 ## to platform, not sure.
	 last unless rmdir $path ;
      }
   }
}


=item work_root

   $root = $self->work_root ;
   $self->work_root( $new_root ) ;
   $self->work_root( $new_root, $dir1, $dir2, .... ) ;

Gets/sets the work root.  This defaults to

   File::Spec->tmpdir . "/vcp$$/" . $plugin_name

but may be altered.  If set to a relative path, the current working
directory is prepended.  The returned value is always absolute, and will
not change if you chdir().  Depending on the operating system, however,
it might not be located on to the current volume.  If not, it's a bug,
please patch away.

=cut

sub work_root {
   my VCP::Plugin $self = shift ;

   if ( @_ ) {
      if ( defined $_[0] ) {
	 $self->{WORK_ROOT} = File::Spec->catdir( @_ ) ;
	 debug "vcp: work_root set to '",$self->work_root,"'"
	    if debugging $self ;
	 unless ( File::Spec->file_name_is_absolute( $self->{WORK_ROOT} ) ) {
	    require Cwd ;
	    $self->{WORK_ROOT} = File::Spec->catdir( Cwd::cwd, @_ ) ;
	 }
      }
      else {
         $self->{WORK_ROOT} = undef ;
      }
   }

   return $self->{WORK_ROOT} ;
}


=item command

   $self->command( 'p4' ) ;
   $self->command( 'cvs' ) ;

   $path_to_command = $self->command ;

This sets the name of the primary command name that is to be
used.  A search of the PATH environment variable is then done if 
the path is relative to see if the command can be found.

This method croaks if the command can not be found.

This is usually called by new().

Once this is set, the command may be executed by doing something like

   $self->p4( [qw( counters )], \$out )
      or die "Process failed".

, which runs a 'p4 counters' and pipes the output in to the \$out
variable.

See L<IPC::Run> for details on the additional parameters after
the command.

=cut

sub _cmd_not_found {
   my ( $cmd, $msg, @path ) = @_ ;
   
   croak "'$cmd' $msg",
      @path
         ? ", searched in " . join( ", ", map "'$_'", @path )
	 : () ;
}

sub command {
   my VCP::Plugin $self = shift ;

   if ( @_ ) {
      my ( $cmd, @args ) = @_ ;
      my @path ;
      unless ( File::Spec->file_name_is_absolute( $cmd ) ) {
         ## TODO: Port this to other OSs
	 for ( $^O ) {
	    if ( /Win/ ) {
	       @path = split( /;/, $ENV{PATH} ) ;
	    }
	    else {
	       @path = split( /:/, $ENV{PATH} ) ;
	    }
	 }

	 for ( @path ) {
	    my $candidate = File::Spec->catfile( $_, $cmd ) ;
	    if ( -f $candidate && -x $_ ) {
	       $cmd = $candidate ;
	       last ;
	    }
	 }
      }

      _cmd_not_found( $cmd, 'not found',      @path )   unless -e $cmd ;
      _cmd_not_found( $cmd, 'is a directory', @path )   if     -d _ ;
      _cmd_not_found( $cmd, 'not a file',     @path )   unless -f _ ;
      _cmd_not_found( $cmd, 'not executable', @path )   unless -x _ ;

      @{$self->{COMMAND}} = ( $cmd, @args ) ;
   }

   return @{$self->{COMMAND}} ;
}


=item command_chdir

Sets/gets the directory to chdir into before running the default command.

=cut

sub command_chdir {
   my VCP::Plugin $self = shift ;
   if ( @_ ) {
      $self->{COMMAND_CHDIR} = shift ;
      debug "vcp: command_chdir set to '", $self->command_chdir, "'"
         if debugging $self ;
   }
   return $self->{COMMAND_CHDIR} ;
}


=item command_stderr_filter

   $self->command_stderr_filter( qr/^cvs add: use 'cvs commit'.*\n/m ) ;
   $self->command_stderr_filter( sub { my $t = shift ; $$t =~ ... } ) ;

Some commands--cough*cvs*cough--just don't seem to be able to shut up
on stderr.  Other times we need to watch stderr for some meaningful output.

This allows you to filter out expected whinging on stderr so that the command
appears to run cleanly and doesn't cause $self->cmd(...) to barf when it sees
expected output on stderr.

This can also be used to filter out intermittent expected errors that
aren't errors in all contexts when they aren't actually errors.

=cut

sub command_stderr_filter {
   my VCP::Plugin $self = shift ;
   $self->{COMMAND_STDERR_FILTER} = $_[0] if @_ ;
   return $self->{COMMAND_STDERR_FILTER} ;
}


=item command_ok_result_codes

   $self->command_ok_result_codes( 0, 1 ) ;

Occasionally, a non-zero result is Ok.  this method lets you set a list
of acceptable result codes.

=cut

sub command_ok_result_codes {
   my VCP::Plugin $self = shift ;

   if ( @_ ) {
      %{$self->{COMMAND_OK_RESULT_CODES}} = () ;
      @{$self->{COMMAND_OK_RESULT_CODES}}{@_} = () ;
   }

   return unless defined wantarray ;
   return keys %{$self->{COMMAND_STDERR_FILTER}} ;
}


=item repo_user

   $self->repo_user( $user_name ) ;
   $user_name = $self->repo_user ;

Sets/gets the user name to log in to the repository with.  Some plugins
ignore this, like revml, while others, like p4, use it.

This is usually set automatically by L</parse_repo_spec>.

=cut

sub repo_user {
   my VCP::Plugin $self = shift ;
   $self->{REPO_USER} = $_[0] if @_ ;
   return $self->{REPO_USER} ;
}


=item repo_password

   $self->repo_password( $password ) ;
   $password = $self->repo_password ;

Sets/gets the password to log in to the repository with.  Some plugins
ignore this, like revml, while others, like p4, use it.

This is usually set automatically by L</parse_repo_spec>.

=cut

sub repo_password {
   my VCP::Plugin $self = shift ;
   $self->{REPO_PASSWORD} = $_[0] if @_ ;
   return $self->{REPO_PASSWORD} ;
}


=item repo_server

   $self->repo_server( $server ) ;
   $server = $self->repo_server ;

Sets/gets the repository to log in to.  Some plugins
ignore this, like revml, while others, like p4, use it.

This is usually set automatically by L</parse_repo_spec>.

=cut

sub repo_server {
   my VCP::Plugin $self = shift ;
   $self->{REPO_SERVER} = $_[0] if @_ ;
   return $self->{REPO_SERVER} ;
}


=item rev_root

   $self->rev_root( 'depot' ) ;
   $rr = $self->rev_root ;

The rev_root is the root of the tree being sourced. See L</deduce_rev_root>
for automated extraction.

Root values should have neither a leading or trailing directory separator.

'/' and '\' are recognized as directory separators and runs of these
are converted to single '/' characters.  Leading and trailing '/'
characters are then removed.

=cut

sub _slash_hack {
   for ( my $spec = shift ) {
      s{[/\\]+}{/}g ;
      s{^/}{}g ;
      s{/\Z}{}g ;
      return $_ ;
   }
}

sub rev_root {
   my VCP::Plugin $self = shift ;

   if ( @_ ) {
      $self->{REV_ROOT} = &_slash_hack ;
      debug "vcp: rev_root set to '$self->{REV_ROOT}'" if debugging $self ;
   }
   return $self->{REV_ROOT} ;
}


=item deduce_rev_root

   $self->deduce_rev_root ;
   print $self->rev_root ;

If the user did not specify a rev_root, passing the filespec to this
will do it.

'/' and '\' are recognized as directory separators, and '*', '?', and '...'
as wildcard sequences.  Runs of '/' and '\' characters are reduced to
single '/' characters.

If no wildcards are used in the filespec, then the dirname is used.

If there is only a single name component, it is assumed to be a directory
name.

=cut

sub deduce_rev_root {
   my VCP::Plugin $self = shift ;

   my ( $spec ) = &_slash_hack ;
   my @dirs ;
   my $wildcard_found ;
   for ( split( /\//, $spec ) ) {
      if ( /[*?]|\.\.\./ ) {
	 $wildcard_found = 1 ;
         last ;
      }
      push @dirs, $_ ;
   }

   my $dirs = $wildcard_found || @dirs < 2 ? $#dirs : $#dirs - 1 ;
   $self->rev_root( join( '/', @dirs[0..$dirs] ) ) ;
}


=item normalize_name

   $fn = $self->normalize_name( $fn ) ;

Normalizes the filename by converting runs of '\' and '/' to '/', removing
leading '/' characters, and removing a leading rev_root.  Dies if the name
does not begin with rev_root.

=cut

sub normalize_name {
   my VCP::Plugin $self = shift ;

   my ( $spec ) = &_slash_hack ;

   my $rr = $self->rev_root ;

   return $spec unless length $rr ;
   confess "'$spec' does not begin with rev_root '$rr'"
      unless substr( $spec, 0, length $rr ) eq $rr ;
 
   return substr( $spec, length( $rr ) + 1 ) ;
}


=item denormalize_name

   $fn = $self->denormalize_name( $fn ) ;

Denormalizes the filename by prepending the rev_root.  May do more in
subclass overloads.  For instance, does not prepend a '//' by default for
instance, but p4 overloads do that.

=cut

sub denormalize_name {
   my VCP::Plugin $self = shift ;

   return join( '/', $self->rev_root, shift ) ;
}


=item run

   $self->run( [@cmd_and_args], \$stdout, \$stderr ) ;

A wrapper around L<IPC::Run/run>, which integrates debuggins support and
disables stdin by default.

=cut

sub run {
   my VCP::Plugin $self = shift ;
   my $cmd_line = shift ;

   debug "vcp: running ", join( ' ', map "'$_'", @$cmd_line )
      if debugging $self ;
   
   return IPC::Run::run( $cmd_line, \undef, @_ ) ;
}


use vars qw( $AUTOLOAD ) ;

## AUTOLOADed methods are a touch slower than normal perl methods, but you're
## about to fork, so it doesn't matter.

sub AUTOLOAD {
   my ( $package, $fun ) = $AUTOLOAD =~ m/(.*)::(.*)/g ;

   my VCP::Plugin $self = shift ;

   confess "Can only autoload $package member functions"
      unless isa( $self, __PACKAGE__ ) ;

   my $args = shift ;
   confess "Can't AUTOLOAD '$AUTOLOAD' until a command is defined"
      unless defined $self->command ;

   my $cmd = basename( $self->command ) ;

   confess "Can only AUTOLOAD '$cmd', not '$fun'"
      unless $fun eq $cmd ;

   ## Prefix succinct mode args with '>', etc.
   my $childs_stderr = '' ;
   my @redirs ;
   my $fd = 1 ;
   while ( @_ ) {
      last unless ref $_[0] ;
      push @redirs, "$fd>", shift ;
      ++$fd ;
   }
   push @redirs, @_ ;

   ## Put it on the beginning so that later redirects specified by the client
   ## can override our redirect.  This is necessary in case the client does
   ## a '2>&1' or some other subtle thing.
   unshift @redirs, '2>', \$childs_stderr
      unless grep $_ eq '2>', @redirs ;

   unshift @redirs, '<', \undef
      unless grep $_ eq '<', @redirs ;

   debug "vcp: running ", join( ' ', map "'$_'", $self->command, @$args ),
      " in ", defined $self->{COMMAND_CHDIR}
         ?  $self->{COMMAND_CHDIR}
	 : "undef"
      if debugging $self, join( '::', ref $self, $cmd ) ;
   
   my $h = IPC::Run::harness(
      [ $self->command, @$args ],
      @redirs,
      defined $self->{COMMAND_CHDIR}
         ? ( init => sub {
	    chdir $self->{COMMAND_CHDIR}
	       or die "$! chdiring to $self->{COMMAND_CHDIR}"
	    } )
	 : (),
   ) ;
   $h->run ;

   my @errors ;

   if ( length $childs_stderr ) {
      if ( debugging $self ) {
         my $t = $childs_stderr ;
	 my $cmdname = basename( $self->command ) ;
	 $t =~ s/^/$cmdname: /gm ;
	 debug $t ;
      }
      my $f = $self->command_stderr_filter ;
      if ( ref $f eq 'Regexp' ) {
         $childs_stderr =~ s/$f//mg ;
      }
      elsif ( ref $f eq 'CODE' ) {
         $f->( \$childs_stderr ) ;
      }

      if ( length $childs_stderr ) {
	 my $cmdname = basename( $self->command ) ;
	 $childs_stderr =~ s/^/$cmdname: /gm ;
	 $childs_stderr .= "\n" unless substr( $childs_stderr, -1 ) eq "\n" ;
	 push (
	    @errors,
	    "vcp: unexpected stderr from '$cmdname':\n",
	    $childs_stderr,
	 ) ;
      }
   }

   ## In checking the result code, we assume the first one is the important
   ## one.  This is done because a few callers pipe the first child's output
   ## in to a perl sub that then does a kill 9,$$ to effectively exit without
   ## calling DESTROY.
   ## TODO: Look at all of the result codes if we can get rid of kill 9, $$.
   push(
      @errors,
      "vcp: ",
      join( ' ', $self->command, @$args ),
      " returned ",
      $h->full_result( 0 ),
      " not ",
      join( ', ', keys %{$self->{COMMAND_OK_RESULT_CODES}} ),
      "\n"
   )
      unless exists $self->{COMMAND_OK_RESULT_CODES}->{$h->full_result( 0 )} ;

   die join( '', @errors ) if @errors ;

   Carp::cluck "Result of `", join( ' ', $self->command, @$args ), "` checked"
      if defined wantarray ;

   return ;
}


## Don't try to AUTOLOAD DESTROY.  Oh wait, I need to do some cleanup
## here anyway.  Cool.
sub DESTROY {
   my VCP::Plugin $self = shift ;

   if ( defined $self->work_root ) {
      local $@ ;
      eval { $self->rm_work_path() ; } ;

      warn "Unable to remove work directory '", $self->work_root, "'\n"
	 if -d $self->work_root ;
   }
}

=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This will be licensed under a suitable license at a future date.  Until
then, you may only use this for evaluation purposes.  Besides which, it's
in an early alpha state, so you shouldn't depend on it anyway.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=cut

1
