package VCP::Driver;

=head1 NAME

VCP::Driver - A base class for sources and destinations

=head1 SYNOPSIS

   use VCP::Driver;
   @ISA = qw( VCP::Driver );
   ...

=head1 DESCRIPTION

A VPC::Driver is a VCP::Plugin and is the base class for VCP::Source
and VCP::Dest.

=head1 OPTIONS

Options global to all sources and destinations (unless otherwise
documented:


=over

=item --case-sensitive

Whether or not to compare filenames in a case sensitive manner.  This
defaults to true on Win32 and false elsewhere.  It also may not affect
all operations because VCP shells out to subcommands that have their
own opinions about such matters.

=item --db-dir

The directory to store VCP's state information in.

VCP store state information for each transfer that describes what
revisions were read from the source repository and how they were written
to the destination repository. Typically this is kept in a subdirectory
of the C<vcp_state> directory, where the subdirectory is based on the
C<repo_id> value (which may be set by the C<--repo-id> option).  This
allows you to set the directory name.

=item --repo-id

The globally unique identifier for a repository.  This is normally set
to the repo_server field value from the repository specification but may
need to be specified manually if the repository has been moved or is
accessed using different server specifications.

This is only used when a source or destination needs to create a
transfer state database, and is ignored by those that don't.  It is
allowed globally (unless otherwise documented) so that users may be
consistent in setting it so that if a source or dests suddenly grows a
need to use it, it will be there (if the user has been consistent).

=back


=cut

$VERSION = 0.1 ;

@ISA = qw( VCP::Plugin );

use strict;
use Cwd ;
use File::Basename ;
use File::Path qw( rmtree );
use File::Spec ;
use File::Temp qw( tempfile );
use Getopt::Long;
use POSIX qw( dup dup2 );

use UNIVERSAL qw( isa );
use Regexp::Shellish qw( compile_shellish );
use VCP::ConfigFileUtils qw( config_file_quote );
use VCP::Debug qw( :debug :profile );
use VCP::Logger qw( lg lg_fh pr pr_active BUG );
use VCP::Plugin;
use VCP::Rev ;
use VCP::Utils qw(
   empty
   escape_filename
   is_win32
   shell_quote
   start_dir
   start_dir_rel2abs
   xchdir
);


#use base "VCP::Plugin";
#use fields (
#   'WORK_ROOT',     ## The root of the export work area.
#   'COMMAND_CHDIR', ## Where to chdir to when running COMMAND
#   'COMMAND_STDERR_FILTER', ## How to modify the stderr when running a command
#   'COMMAND_OK_RESULT_CODES', ## HASH keyed on acceptable COMMAND return vals
#   'COMMAND_RESULT_CODE',     ## What the last run_safely command returned.
#   'REV_ROOT',
#   'REPO_ID',       ## uniquely identifies repository
#   'REPO_SCHEME',   ## The scheme (this is usually superfluous, since new() has
#                    ## already been called on the correct class).
#   'REPO_USER',     ## The user name to log in to the repository with, if any
#   'REPO_PASSWORD', ## The password to log in to the repository with, if any
#   'REPO_SERVER',   ## The repository to connect to
#   'REPO_FILESPEC', ## The filespec to get/store
#
#   'DB_DIR',        ## Directory name in which to store the transfer
#                    ## state databases
#   'CASE_SENSITIVE', ## Whether or not to match in a case sensitive manner
#);

sub new {
   my $self = shift->SUPER::new( @_ );

   $self->work_root( $self->tmp_dir ) ;
   rmtree $self->work_root if ! $ENV{VCPNODELETE} && -e $self->work_root ;

   $self->{COMMAND_OK_RESULT_CODES} = [ 0 ];

   $self->command_chdir( $self->work_path ) ;

   return $self;
}


###############################################################################

=head1 SUBCLASSING

This class uses the fields pragma, so you'll need to use base and 
possibly fields in any subclasses.

=over

=item revs

Sets/gets the revs container.  This is used by most sources to accumulate
the set of revisions to be copied.

This member should be set by the child in copy_revs().  It should then be
passed to the destination

=cut

sub revs {
   my $self = shift ;

   BUG "can't set the revs database any more" if @_;
   return $self->{REVS} ||= VCP::Revs->new(
       STORE_LOC => $self->_db_store_location,
       PLUGIN_NAME => int $self,
   );
}




=item parse_options

   $self->parse_options( \@options, @spec );

Parses out all options according to @spec.  The --repo-id option is
always parsed and VCP::Source.pm and VCP::Dest.pm offer common
options as well.

=cut

sub parse_options {
   my $self = shift;
   my $options = shift;
   return unless defined $options;

   BUG "options specs passed to parse_options, that is no longer allowed!"
      if @_;

   local *ARGV = $options;
   my @options_spec = $self->options_spec;
   @options_spec = ( "TAKESNOOPTIONS" => \undef )
      unless @options_spec;

   GetOptions( @options_spec) or $self->usage_and_exit ;

   if( ! empty $self->db_dir && empty $self->repo_id ) {
      pr "--repo-id required if --db-dir present";
      $self->usage_and_exit ;
   }
}


=item options_spec

Returns a list of Getopt::Long::GetOptions() options specifications with
the limitation that CODE refs (sub { ... }) are not allowed.  This is
called by parse_options() and dot_vcp_file_options_string().

Specified option global to all sources and destinations.  See above.

Note that only a few of the myriad syntaxes that Getopt::Long allows are
provided for here so that we can reliably reguritate the values when
writing .vcp files.  To wit, these are the "!", ":" and "=" flag
characters (the type after the flag character is ignored).

Storage locations must be a SCALAR or CODE reference for now, and the
code references must be written like:

    '...' => sub { shift; $self->accessor( @_ ) },

so that they may be used as an getter by the options printing code.

Overloading methods should be of the form:

    sub options_spec {
       my $self = shift;
       return (
          $self->SUPER::options_spec,
          "my-option1-long-name|short-name1..." => \$self->{FOO},
          "my-option2-long-name|short-name2..." => sub {
             shift;
             $self->setter_getter( @_ );
          },
          ...
       );
    }

=cut

sub options_spec {
    my $self = shift;
    return (
       "db-dir=s"       => \$self->{DB_DIR},
       "repo-id=s"      => \$self->{REPO_ID},
       "case-sensitive" => \$self->{CASE_SENSITIVE},
   );
}

=item options_as_strings

Returns a list of options as strings.  Each string will be a single
option and, if it has a value, it's value suitable for passing on
the command line or emitting to a .vcp file.

Options that are not set (are undefined) are returned with a leading "#"
character.  These should be grepped out if the options are not going to
be on a single line each in a .vcp file.

String options that are "" internally are not returned with a leading ""
character.

=cut

sub options_as_strings {
   my $self = shift;
   my @options = $self->options_spec;
   my %options;
   while ( @options ) {
      my ( $spec, $ref ) = ( shift @options, shift @options );

      my $ref_type = ref $ref;
      BUG "must store $spec option in a SCALAR ref, not in a ", $ref_type
         unless $ref_type eq "SCALAR" || $ref_type eq "CODE";

      my ( $name, $c, $type ) =
          $spec =~ /^(\w[-\w]*)[|\w-]*(([!~+=:])?([insfe])?([@%])?)?$/
             or BUG "can't parse option spec '$spec'";

      $c = "~" if empty $c;
      $c = "=" if $c eq ":";

      $options{$name} = {
         Type  => $c,
         Value => $ref,
      }
   }

   map {
      my $name = $_;
      my $d = $options{$name};
      my $v_ref = $d->{Value};

      my @v = ref $v_ref eq "CODE"
         ? $v_ref->()
         : $$v_ref;
      @v = ( undef ) unless @v;
      map {
         my $v = $_;
           $d->{Type} eq "~" ?   $v ? "--$name" : "#--$name"
         : $d->{Type} eq "!" ?   $v ? "--$name" : "--no$name"
         :        defined $v ? config_file_quote "--$name=$v" : "#--$name=???";
      } @v;
   } sort keys %options;
}

=item repo_spec_as_string

Returns a string that represents a Source: or Dest: specification
equivalent to the one that was parsed (usually by new() calling
parse_repo_spec()).

=cut

sub repo_spec_as_string {
   my $self = shift;

   my $scheme   = $self->repo_scheme;
   BUG "repo_scheme not set" if empty $scheme;

   my $user     = $self->repo_user;
   my $password = $self->repo_password;
   my $server   = $self->repo_server;
   my $filespec = $self->repo_filespec;

   my @out = ( $scheme, ":" );
   push @out, $user          unless empty $user;
   push @out, ":", $password unless empty $password;
   push @out, "@"            unless empty( $user ) && empty( $password );
   push @out, $server        unless empty $server;
   unless ( empty $filespec ) {
      push @out, ":" if @out > 2;  ## if more than just a scheme
      push @out, $filespec;
   }

   return config_file_quote join "", @out;
}

=item config_file_section_as_string

Returns a string that may be emitted to dump a filter's settings to a .vcp
file.

=cut

sub config_file_section_as_string {
   my $self = shift;

   require VCP::Help;

   my ( $section ) = ( ref( $self ) =~ /\AVCP::(Source|Dest)::/ )
      or BUG "Can't parse 'Source' or 'Dest' from ", ref $self;

   my $spec = $self->repo_spec_as_string;

   my $plugin_docs  = $self->plugin_documentation;

   return join( "",
      "$section: $spec\n",
      ! empty( $plugin_docs )
         ? $self->_reformat_docs_as_comments( $plugin_docs )
         : (),
      ( map
         {
            my $name = $_;
            $name =~ s/^#*\s*--?//;
            $name =~ s/[^\w-].*//;
            my $text = VCP::Help->get( ref( $self ) . " option $name" );
            (
               "\n    $_\n",
               ! empty( $text )
                  ? $self->_reformat_docs_as_comments( $text )
                  : (),
            );
         } $self->options_as_strings
      ),
      "\n",
   );
}

=item compile_path_re

Compiles a filespec in to a regular expression, treating '*', '?', '...',
and '{}' (brace pairs) as wildcards.  "()" and "**" are not treated
as capture and "...", respectively.

=cut

sub compile_path_re {
   my $self = shift;
   compile_shellish(
      shift,
      {
         case_sensitive => $self->case_sensitive,
         star_star      => 0,
         parens         => 0,
      }
   );
}



=item parse_repo_spec

   my $spec = $self->split_repo_spec( $spec ) ;

This splits a repository spec in one of the following formats:

   scheme:user:passwd@server:filespec
   scheme:user@server:filespec
   scheme::passwd@server:filespec
   scheme:server:filespec
   scheme:filespec

into the indicated fields, which are stored in $self and may be
accessed and altered using L</repo_scheme>, L</repo_user>, L</repo_password>,
L</repo_server>, and L</repo_filespec>. Some sources and destinations may
add additional fields. The p4 drivers create an L<VCP::Utils::p4/repo_client>,
for instance, and parse the repo_user field to fill it in.  See
L<VCP::Utils::p4/parse_p4_repo_spec> for details.

The spec is parsed from the ends towards the middle in this order:

   1. SCHEME (up to first ':')
   2. FILESPEC  (after last ':')
   3. USER, PASSWORD (before first '@')
   4. SERVER (everything left).

This approach allows the FILESPEC string to contain '@', and the SERVER
string to contain ':' and '@'.  USER can contain ':'.  Funky, but this
works well, at least for cvs and p4.

If a section of the repo spec is not present, the corresponding entry
in $hash will not exist.

The attributes repo_user, repo_password and repo_server are set
automatically by this method.  It does not store the SCHEME anyware
since the SCHEME is ignored by the plugin (the plugin is selected using
the scheme, so it knows the scheme implicitly), and the FILES setting
often needs extra manipulation, so there's no point in storing it.

=cut

sub parse_repo_spec {
   my $self = shift ;

   my ( $spec ) = @_ ;
   BUG "parse_repo_spec called with missing argument"
      if empty $spec;

   $self->repo_scheme( undef );
   $self->repo_filespec( undef );
   $self->repo_user( undef );
   $self->repo_password( undef );
   $self->repo_server( undef );

   for ( $spec ) {
      return unless s/^([^:]*)(?::|$)// ;
      $self->repo_scheme( $1 ) ;

      return unless s/(?:^|:)([^:]*)$// ;
      $self->repo_filespec( $1 ) ;

      if ( s/^([^\@]*?)(?::([^\@:]*))?@// ) {
         $self->repo_user( $1 ) if defined $1 ;
         $self->repo_password( $2 ) if defined $2 ;
      }

      return unless length $spec ;
      $self->repo_server( $spec ) ;
   }
}

=item work_path

   $full_path = $self->work_path( $filename, $rev ) ;

Returns the full path to the working copy of the local filename.

Each VCP::Plugin gets their own hierarchy to use, usually rooted at
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
   my $self = shift ;

   my $path = File::Spec->canonpath(
      File::Spec->catfile( $self->work_root, @_ )
   ) ;

   return $path ;
}


=item rm_work_path

   $self->rm_work_path( $filename, $rev ) ;
   $self->rm_work_path( $dirname ) ;

Removes a directory or file from the work directory tree.  Also
removes any and all directories that become empty as a result up to
the work root (/tmp on Unix).

=cut

sub rm_work_path {
   my $self = shift ;

   my $path = $self->work_path( @_ ) ;

   if ( defined $path && -e $path ) {
      xchdir "/" if is_win32; ## WinNT can't delete out from
                              ## under cwd.
      lg "\$ ", shell_quote "rm", "-rf", $path;
      if ( ! $ENV{VCPNODELETE} ) {
         rmtree $path or pr "$!: $path"
      }
      else {
         pr "not removing working directory $path due to VCPNODELETE\n";
      }
   }

   my $root = $self->work_root ;

   if ( substr( $path, 0, length $root ) eq $root ) {
      while ( length $path > length $root ) {
	 ( undef, $path ) = fileparse $path;
	 ## TODO: More discriminating error handling.  But the error emitted
	 ## when a directory is not empty may differ from platform
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
   my $self = shift ;

   if ( @_ ) {
      if ( defined $_[0] ) {
	 $self->{WORK_ROOT} = File::Spec->catdir( @_ ) ;
	 lg ref $self, " work_root set to '",$self->work_root,"'";
	 unless ( File::Spec->file_name_is_absolute( $self->{WORK_ROOT} ) ) {
	    require Cwd ;
	    $self->{WORK_ROOT} = File::Spec->catdir( start_dir, @_ ) ;
	 }
      }
      else {
         $self->{WORK_ROOT} = undef ;
      }
   }

   return $self->{WORK_ROOT} ;
}


=item command_chdir

Sets/gets the directory to chdir into before running the default command.

DEPRECATED: use in_dir => "dirname" instead:

   $self->cvs(
      [..],
      \$in,
      \$out,
      in_dir => $dirname,
   );

=cut

sub command_chdir {
   my $self = shift ;
   if ( @_ ) {
      $self->{COMMAND_CHDIR} = shift ;
      lg ref $self, " command_chdir set to '", $self->command_chdir, "'";
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

DEPRECATED: use stderr_filter => qr/regexp/ instead:

    $self->ss( [ 'Delete', $file, "-I-y" ],
        stderr_filter => qr{^You have.*checked out.*Y[\r\n]*$}s,
        );

=cut

sub command_stderr_filter {
   my $self = shift ;
   $self->{COMMAND_STDERR_FILTER} = $_[0] if @_ ;
   return $self->{COMMAND_STDERR_FILTER} ;
}


=item command_ok_result_codes

   $self->command_ok_result_codes( 0, 1 ) ;

Occasionally, a non-zero result is Ok.  this method lets you set a list
of acceptable result codes.

DEPRECATED: use ok_result_codes => [ 0, 1, ... ] instead:

   $self->p4(
      [..],
      \$in,
      \$out,
      ok_result_codes => [ 0, 1 ]
   );

=cut

sub command_ok_result_codes {
   my $self = shift ;

   @{$self->{COMMAND_OK_RESULT_CODES}} = @_ if @_;

   return @{$self->{COMMAND_OK_RESULT_CODES}} ;
}


=item repo_id

   $self->repo_id( $repo_id ) ;
   $repo_id = $self->repo_id ;

Sets/gets the repo_id, a unique identifier for the repository.

=cut

sub repo_id {
   my $self = shift ;
   $self->{REPO_ID} = $_[0] if @_ ;
   return $self->{REPO_ID} ;
}



=item repo_scheme

   $self->repo_scheme( $scheme_name ) ;
   $scheme_name = $self->repo_scheme ;

Sets/gets the scheme specified ("cvs", "p4", "revml", etc). This is normally
superfluous, since the scheme name is peeked at in order to load the
correct VCP::{Source,Dest}::* class, which then calls this.

This is usually set automatically by L</parse_repo_spec>.

=cut

sub repo_scheme {
   my $self = shift ;
   $self->{REPO_SCHEME} = $_[0] if @_ ;
   return $self->{REPO_SCHEME} ;
}


=item repo_user

   $self->repo_user( $user_name ) ;
   $user_name = $self->repo_user ;

Sets/gets the user name to log in to the repository with.  Some plugins
ignore this, like revml, while others, like p4, use it.

This is usually set automatically by L</parse_repo_spec>.

=cut

sub repo_user {
   my $self = shift ;
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
   my $self = shift ;
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
   my $self = shift ;
   $self->{REPO_SERVER} = $_[0] if @_ ;
   return $self->{REPO_SERVER} ;
}


=item repo_filespec

   $self->repo_filespec( $filespec ) ;
   $filespec = $self->repo_filespec ;

Sets/gets the filespec.

This is usually set automatically by L</parse_repo_spec>.

=cut

sub repo_filespec {
   my $self = shift ;
   $self->{REPO_FILESPEC} = $_[0] if @_ ;
   return $self->{REPO_FILESPEC} ;
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
      BUG "undef arg" unless defined $spec ;
      s{[\\/]+}{/}g ;
      s{^/}{}g ;
      s{/\Z}{}g ;
      return $_ ;
   }
}

sub rev_root {
   my $self = shift ;

   if ( @_ ) {
      $self->{REV_ROOT} = &_slash_hack ;
      lg ref $self, " rev_root set to '$self->{REV_ROOT}'";
   }

   return $self->{REV_ROOT} ;
}


=item deduce_rev_root

   $self->deduce_rev_root ;
   print $self->rev_root ;

This is used in most plugins to deduce the rev_root from the filespec portion
of the source or destination spec if the user did not specify a rev_root as
an option.

This function sets the rev_root to be the portion of the filespec up to (but
not including) the first file/directory name with a wildcard.

'/' and '\' are recognized as directory separators, and '*', '?', and '...'
as wildcard sequences.  Runs of '/' and '\' characters are treated as
single '/' characters (this may damage UNC paths).

NOTE: if no wildcards are found and the last character is a '/' or '\\', then
the entire string will be considered to be the rev_root.  Otherwise the
spec is expected to refer to a file, in which case the rev_root does
not include the final name.  This means that

   cvs:/foo

and

   cvs:/foo/

are different.

=cut

sub deduce_rev_root {
   my $self = shift ;

   my ( $spec ) = @_;

   $spec =~ s{^[\\/]*}{}g;
   my @dirs ;
   for ( split( /[\\\/]+/, $spec, -1 ) ) {
      if ( /[*?]|\.\.\./ ) {
         push @dirs, "";  ## Pretend "/foo/bar/..." was "/foo/bar/"
         last ;
      }
      push @dirs, $_ ;
   }

   pop @dirs;  ## Throw away trailiing filename or ""

   $self->rev_root( join( '/', @dirs ) ) ;
}


=item normalize_name

   $fn = $self->normalize_name( $fn ) ;

Normalizes the filename by converting runs of '\' and '/' to '/', removing
leading '/' characters, and removing a leading rev_root.  Dies if the name
does not begin with rev_root.

=cut

sub normalize_name {
   my $self = shift ;

   ## my $revr = $self->{REV_ROOT};

   my ( $spec ) = &_slash_hack ;

   my $rr = $self->rev_root ;
   my $rrl = length $rr ;

   return $spec unless $rrl ;
   BUG "'$spec' does not begin with rev_root '$rr'"
      unless $self->case_sensitive
         ?    substr( $spec, 0, $rrl ) eq    $rr
         : lc substr( $spec, 0, $rrl ) eq lc $rr;

   die "no files under the rev root '$rr' in spec '$spec'\n"
      if $rrl + 1 > length $spec;

   my $s = substr( $spec, $rrl + 1 ) ;
   return $s;
}


=item case_sensitive

Returns TRUE or FALSE: whether or not to be case sensitive.  If not
set as an option, returns !is_win32.

=cut

sub case_sensitive {
   my $self = shift ;
   return defined $self->{CASE_SENSITIVE}
      ? $self->{CASE_SENSITIVE}
      : !is_win32;
}


=item denormalize_name

   $fn = $self->denormalize_name( $fn ) ;

Denormalizes the filename by prepending the rev_root.  May do more in
subclass overloads.  For instance, does not prepend a '//' by default for
instance, but p4 overloads do that.

=cut

sub denormalize_name {
   my $self = shift ;

   return join( '/', $self->rev_root, shift ) ;
}

=item db_dir

Set or return the directory name where the transfer state databases
are stored.

This is the directory to store the state information for this transfer
in.  This includes the mapping of source repository versions
(name+rev_id, usually) to destination repository versions and the
status of the last transfer, so that incremental transfers may restart
where they left off.

=cut

sub db_dir {
   my $self = shift ;
   
   $self->{DB_DIR} = shift if @_;
   return $self->{DB_DIR};
}

=item _db_store_location

Determine the location to store the transfer state databases.

Uses the path provided by the --db-dir option if present,
else use directory 'vcp_state' in the directory the program was
started in.  The file name is an escaped repo_id.

This is passed in to the appropriate DBFile or used directly by the
destinations as need be.

=cut

sub _db_store_location {
   my $self = shift ;

   my $loc = $self->db_dir;
   $loc = "vcp_state" if empty $loc;
   $loc = start_dir_rel2abs $loc;

   return File::Spec->catdir( $loc, escape_filename( $self->repo_id ), @_ );
}


=item run_safely

Runs a command "safely", first chdiring in to the proper directory and
then running it while examining STDERR through an optional filter and
looking at the result codes to see if the command exited acceptably.

Most often called from VCP::Utils::foo methods.

=cut

my $log_fh = lg_fh;
{

my $cached_in_fh  = tempfile( "vcp_XXXX" );
my $cached_in_fd  = fileno $cached_in_fh;
my $cached_out_fh = tempfile( "vcp_XXXX" );
my $cached_out_fd = fileno $cached_out_fh;
my $cached_err_fh = tempfile( "vcp_XXXX" );
my $cached_err_fd = fileno $cached_err_fh;

my $null_fn = File::Spec->devnull;;
my $null_in_fh = do {
   local *NULL;
   open NULL, "<$null_fn" or die "$!: $null_fn";
   *NULL{IO};
};
my $null_in_fd = fileno $null_in_fh;

my $null_out_fh = do {
   local *NULL;
   open NULL, ">$null_fn" or die "$!: $null_fn";
   *NULL{IO};
};

my $log_fd = fileno $log_fh;

## We ASSume that STDIN and STDOUT are not redirected in the course of running
## VCP, so we only have to save these off now.
my $saved_fd0;
my $saved_fd1;
my $saved_fd2;

if ( is_win32 ) {
   $saved_fd0 = dup 0;
   $saved_fd1 = dup 1;
   $saved_fd2 = dup 2;
}

sub _run3 {
   profile_start "run3()" if profiling;
   my ( $cmd, $stdin, $stdout, $stderr ) = @_;

   pr_active;

   lg '$ ', shell_quote( @$cmd ),
      !ref $stdout && defined $stdout
        ? ( " > ", shell_quote( $stdout ) )
        : ();

   BUG "undef passed for stdin" unless defined $stdin;

   my $in_fh;
   my $in_fd;
   if ( $stdin != \undef ) {
      $in_fh = $cached_in_fh;
      truncate $in_fh, 0;
      seek $in_fh, 0, 0;
      $in_fd = $cached_in_fd;
      print $in_fh ref $stdin eq "ARRAY" ? @$stdin : $$stdin
         or die "$! writing to temp file\n";
      seek $in_fh, 0, 0;
   }
   else {
      $in_fh = $null_in_fh;
      $in_fd = $null_in_fd;
   }

   my $out_fh;
   my $out_fd;
   if ( defined $stdout ) {
      if ( ref $stdout ) {
        $out_fh = $cached_out_fh;
        $out_fd = $cached_out_fd;
        seek $out_fh, 0, 0;
        truncate $out_fh, 0;
      }
      else {
        local *OUT_FH;
        open OUT_FH, ">$stdout" or die "$!: $stdout";
        $out_fh = *OUT_FH{IO};
        $out_fd = fileno $out_fh;
      }
   }
   else {
      $out_fh = $log_fh;
      $out_fd = $log_fd;
   }

   ## The cvs login uses stderr to prompt the user.  Let the caller
   ## pass in an IO::Handle or GLOB
   my $capture_stderr = 
      defined $stderr
      && ! (
         UNIVERSAL::isa( $stderr, "IO::Handle" )
         || ref $stderr eq "GLOB"
      );

   my $redirect_stderr = $capture_stderr || ! defined $stderr;

   my $err_fh;
   my $err_fd;
   if ( $capture_stderr ) {
      $err_fh = $cached_err_fh;
      $err_fd = $cached_err_fd;
      seek $err_fh, 0, 0;
      truncate $err_fh, 0;
   }
   elsif ( $redirect_stderr ) {
      $err_fh = $log_fh;
      $err_fd = $log_fd;
   }

   if ( is_win32 ) {
      ## TODO: see if CreateProcess, etc, is faster.
      require IO::Handle;  ## need flush()

      ## Perl tries hard to flush these in system() but we're messing
      ## it up by sneaking the dup2()s in when it's not looking, so
      ## we need to flush these.
      flush STDOUT;
      if ( $redirect_stderr ) {
         flush STDERR;
      }

      dup2 $in_fd,  0 or die "$! redirecting STDIN";
      dup2 $out_fd, 1 or die "$! redirecting STDOUT";
      if ( $redirect_stderr ) {
         dup2 $err_fd, 2 or die "$! redirecting STDERR";
      }

      profile_start if profiling;
      my $r = system
         {$cmd->[0]}
         map {
            ## Probably need to offer a win32 escaping
            ## option to handle commands with
            ## different ideas of quoting.
            ( my $s = $_ ) =~ s/"/"""/g;
            $s;
         } @$cmd;
      my $x = $!;
      profile_end if profiling;

      dup2 $saved_fd0, 0 or die "$! restoring STDIN";
      dup2 $saved_fd1, 1 or die "$! restoring STDOUT";
      dup2 $saved_fd2, 2 or die "$! restoring STDERR";
      die $x unless defined $r;
   }
   else {
      ## ASSume Unix-like fork()/exec()
      profile_start if profiling;
      my $pid = fork;
      unless ( $pid ) {
         ## In child or with error.
         die "$! forking ", shell_quote( @$cmd ) unless defined $pid;

         ## In child, phew!
         dup2 $in_fd,  0 or die "$! redirecting STDIN";
         dup2 $out_fd, 1 or die "$! redirecting STDOUT";
         dup2 $err_fd, 2 or die "$! redirecting STDERR";
         exec @$cmd
            or die "$! execing ", shell_quote( @$cmd );
      }
      waitpid $pid, 0;
      profile_end if profiling;
   }


   if ( ! defined $stdout ) {
   }
   elsif ( ref $stdout eq "SCALAR" ) {
      seek $out_fh, 0, 0 or die "$! seeking on temp file for child output";

      my $count = read $out_fh, $$stdout, 10_000;
      $count = read $out_fh, $$stdout, 10_000, length $$stdout
         while $count == 10_000;

      die "$! reading child output from temp file"
         unless defined $count;
   }
   elsif ( ref $stdout eq "CODE" ) {
      seek $out_fh, 0, 0 or die "$! seeking on temp file for child output";
      $stdout->( $out_fh );
   }

   if ( $capture_stderr ) {
      ## Can only capture stderr to a scalar
      seek $err_fh, 0, 0 or die "$! seeking on temp file for child errput";

      my $count = read $err_fh, $$stderr, 10_000;
      $count = read $err_fh, $$stderr, 10_000, length $$stderr
         while $count == 10_000;

      die "$! reading child stderr from temp file"
         unless defined $count;
   }

   profile_end "run3()" if profiling;
}

}

sub run_safely {
   profile_start "run_safely()" if profiling;

   my $self = shift ;

   BUG "pass options in a trailing HASH instead of inline, please"
      if grep defined && /ok_result_codes|in_dir|stderr_filter/, @_;

   my $options = @_ && ref $_[-1] eq "HASH" ? pop : {};
   my ( $cmd, $stdin, $stdout, $stderr ) = @_;
   $options ||= {};

   ## NEVER pass on our own STDIN to the child.
   $stdin = \undef unless defined $stdin;

   my $cmd_path = $cmd->[0] ;
   my $cmd_name = basename( $cmd_path ) ;

   my $in_dir = defined $options->{in_dir} 
      ? File::Spec->rel2abs(
         $options->{in_dir},
         $self->command_chdir
      )
     : $self->command_chdir;

   my $childs_stderr = '' ;
   my $stderr_filter =
       defined $options->{stderr_filter}
          ? $options->{stderr_filter}
          : $self->command_stderr_filter;

   $stderr = \$childs_stderr if ! defined $stderr;

   my $ok_result_codes =
       defined $options->{ok_result_codes}
           ? $options->{ok_result_codes}
           : $self->{COMMAND_OK_RESULT_CODES};

   $self->{COMMAND_RESULT_CODE} = undef;

   if ( defined $in_dir ) {
      $self->mkdir( $in_dir )
	 unless -e $in_dir;

      xchdir $in_dir;
   }

#   require IPC::Run3;
   
   $options->{sub}
      ? $options->{sub}->( $cmd, $stdin, $stdout, $stderr )
      : _run3( $cmd, $stdin, $stdout, $stderr );
#   IPC::Run3::run3( $cmd, $stdin, $stdout, $stderr, $options );
   $self->{COMMAND_RESULT_CODE} = $? >> 8;

#   if ( defined $cwd ) {
#      chdir $cwd or die "$!: $cwd" ;
##      debug "now in ", cwd if debugging ;
#   }

   my @errors ;

   if ( length $childs_stderr ) {
      print $log_fh $childs_stderr;
      my $err = $childs_stderr;

      if ( ref $stderr_filter eq 'Regexp' ) {
         $err =~ s/$stderr_filter//mg ;
      }
      elsif ( ref $stderr_filter eq 'CODE' ) {
         $stderr_filter->( \$err ) ;
      }

      if ( length $err ) {
	 $err =~ s/^/$cmd_name: /gm ;
	 $err .= "\n" unless substr( $err, -1 ) eq "\n" ;
	 push (
	    @errors,
	    "unexpected stderr from '$cmd_name':\n",
	    $err,
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
      shell_quote( @$cmd ),
      " returned ",
      $self->{COMMAND_RESULT_CODE},
      " not ",
      join( ', ', @$ok_result_codes ),
      "\n",
      empty( $childs_stderr ) ? () : do {
         1 while chomp $childs_stderr;
         $childs_stderr =~ s/^/    /mg;
         ( "stderr:\n", $childs_stderr, "\n" );
      },
   )
      unless grep $_ eq $self->{COMMAND_RESULT_CODE}, @$ok_result_codes;

   die join( '', @errors ) if @errors ;

   BUG "Result of `", join( ' ', @$cmd ), "` checked"
      if defined wantarray ;

   profile_end "run_safely()" if profiling;
}

=item command_result_code

Returns the result code from the last C<run_safely()> command.  This is
a separate method because (a) most invocations set the ok result codes
list so that funny looking but ok results are ignored, and (2) because
returning the command execution code from the run() command leads to
funny looking inverted logic because most shell commands return 0 for
sucess.  Now, if Perl has an "N but false" special case to go with its
"0 but true".

This is read-only.

=cut

sub command_result_code {
   my $self = shift ;

   return $self->{COMMAND_RESULT_CODE};
}


sub DESTROY {
   my $self = shift ;

   $self->{REVS} = undef;
      ## Give VCP::Revs a chance to clean up

   if ( defined $self->work_root ) {
      local $@ ;
      eval { $self->rm_work_path() ; } ;

      pr "unable to remove work directory '", $self->work_root, "'\n"
	 if ! $ENV{VCPNODELETE} && -d $self->work_root ;
   }
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
