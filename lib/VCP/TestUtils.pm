package VCP::TestUtils ;

=head1 NAME

VCP::TestUtils - support routines for VCP testing

=cut

use Exporter ;

@EXPORT = qw(
   assert_eq
   slurp
   mk_tmp_dir
   perl_cmd
   vcp_cmd
   get_vcp_output

   p4d_borken 
   launch_p4d

   cvs_borken
   init_cvs

   vss_borken

   s_content
   rm_elts
) ;

@ISA = qw( Exporter ) ;

use strict ;

use Carp ;
use Cwd ;
use File::Path ;
use File::Spec ;
use IPC::Run qw( run start kill_kill ) ;
use POSIX ':sys_wait_h' ;
use Text::Diff ;

=head1 General utility functions

=over

=item mk_tmp_dir

Creates one or more temporary directories, which will be removed upon exit
in an END block

=cut

{
   my @tmp_dirs ;
   END { rmtree \@tmp_dirs unless $ENV{VCPNODELETE} }

   sub mk_tmp_dir {
      confess "undef!!!" if grep !defined, @_ ;
      rmtree \@_ ;
      mkpath \@_, 0, 0770 ;
      push @tmp_dirs, @_ ;
   }
}

=item assert_eq

   assert_eq $test_name, $in, $out ;

dies with a useful diff in $@ is $in ne $out.  Returns nothing.

Requires a diff that knows about the -d and -U options.

=cut


sub assert_eq {
   my ( $name, $in, $out ) = @_ ;

   ## Doint this because Test::Differences isn't quite "real" yet...
   die diff \$in, \$out, { CONTEXT => 10 } if $in ne $out ;
}

=item slurp

   $guts = slurp $filename ;

=cut

sub slurp {
   my ( $fn ) = @_ ;
   open F, "<$fn" or die "$!: $fn" ;
   binmode F ;
   local $/ ;
   return <F> ;
}


=item perl_cmd

   @perl = perl_cmd

Returns a list containing the Perl executable and some options to reproduce
the current Perl options , like -I.

=cut

sub perl_cmd {
   my %seen ;
   return (
      $^X,
      (
	 map {
	    my $s = $_ ;
	    $s = File::Spec->rel2abs( $_ ) ;
	    "-I$s" ;
	 } grep ! $seen{$_}++, @INC
      )
   ) ;
}


=item vcp_cmd

   @vcp = vcp_cmd

Returns a list containing the Perl executable and some options to reproduce
the current Perl options , like -I.

vcp_cmd assumes it is called from within the main distro directory or one
subdir under it, since it looks for "bin/vcp" and "../bin/vcp".  This should be
adequate for almost all uses.

vcp_cmd caches it's results to allow it to be run from other directories after
the first time it's called. (this is not a significant performance improvement;
running the vcp process takes several orders of magnitude longer than the quick
checks vcp_cmd does).

=cut

my @vcp_cmd ;

sub vcp_cmd {
   unless ( @vcp_cmd ) {
      ## We always run vcp by doing a @perl, vcp, to make sure that vcp runs under
      ## the same version of perl that we are running under.
      my $vcp = 'vcp' ;
      $vcp = "bin/$vcp"    if -e "bin/$vcp" ;
      $vcp = "../bin/$vcp" if -e "../bin/$vcp" ;

      $vcp = File::Spec->rel2abs( $vcp ) ;

      @vcp_cmd = ( perl_cmd, $vcp ) ;
   }
   return @vcp_cmd ;
}


=item get_vcp_output

   @vcp = get_vcp_output "foo:", "-bar" ;

Does a:

   run [ vcp_cmd, @_, "revml:", ... ], \undef, \$out
      or croak "`vcp blahdy blah` returned $?";

and returns $out.  The "..." refers to whatever output options are needed
to make the test output agree with C<bin/gentrevml>'s test files
(t/test-*.revml).

=cut

sub get_vcp_output {
   my $out ;
   my @args = ( @_, "revml:", "--sort-by=name,rev_id" ) ;
   run [ vcp_cmd, @args ], \undef, \$out
      or croak "`vcp ", join( " ", @_ ), " returned $?\n" ;
   return $out ;
}

=cut

sub vcp_cmd {
   ## We always run vcp by doing a @perl, vcp, to make sure that vcp runs under
   ## the same version of perl that we are running under.
   my $vcp = 'vcp' ;
   $vcp = "bin/$vcp"    if -x "bin/$vcp" ;
   $vcp = "../bin/$vcp" if -x "../bin/$vcp" ;

   $vcp = File::Spec->rel2abs( $vcp ) ;

   return ( perl_cmd, $vcp ) ;
}


=back

=head1 XML "cleanup" functions

These are used to get rid of content or elements that are known to differ
when comparing the revml fed in to a repository with the revml that
comes out.

=over

=item s_content

   s_content
      $elt_type1, $elt_type2, ..., \$string1, \$string2, ..., $new_content ;

Changes the contents of the elements, since some things, like suer id or
mod_time can't be the same after going through a repository.

If $new_val is not supplied, a constant string is used.

=cut

sub s_content {
   my $new_val = pop if @_ && ! ref $_[-1] ;
   $new_val = "<!-- deleted by test suite -->" unless defined $new_val ;

   my $elt_type_re = do {
      my @a ;
      push @a, quotemeta shift while @_ && ! ref $_[0] ;
      join "|", @a ;
   } ;

   $$_ =~ s{(<($elt_type_re)[^>]*?>).*?(</\2\s*>)}
	   {$1$new_val$3}sg
      for @_ ;

   $$_ =~ s{(<($elt_type_re)[^>]*?>).*?(</\2\s*>)}{$1$new_val$3}sg
      for @_ ;
}


=item rm_elts

   rm_elts $elt_type1, $elt_type2, ..., \$string1, \$string2
   rm_elts $elt_type1, $elt_type2, ..., qr/$content_re/, \$string1, \$string2

Removes the specified elements from the strings, including leading whitespace
and trailing line separators.  If the optional $content_re regular expression
is provided, then only elements containing that pattern will be removed.

=cut

sub rm_elts {
   my $elt_type_re = do {
      my @a ;
      push @a, quotemeta shift while @_ && ! ref $_[0] ;
      join "|", @a ;
   } ;

   my $content_re = @_ && ref $_[0] eq "Regexp" ? shift : qr/.*?/s ;
   my $re = qr{^\s*<($elt_type_re)\b[^>]*?>$content_re</\1\s*>\r?\n}sm ;

   $$_ =~ s{$re}{}g for @_ ;
}


=head1 p4 repository mgmt functions

=over

=item p4_borken

Returns true if the p4 is missing or too old (< 99.2).

=cut

sub p4d_borken {
   my $p4dV = `p4d -V` || 0 ;
   return "p4d not found" unless $p4dV ;

   my ( $p4d_version ) = $p4dV =~ m{^Rev[^/]*/[^/]*/([^/]*)}m ;

   my $min_version = 99.2 ;
   return "p4d version too old, need at least $min_version"
       unless $p4d_version >= $min_version ;
   return "" ;
}

=item launch_p4d

   launch_p4d "prefix_" ;

Creates an empty repository and launches a p4d for it.  The p4d will be killed
and it's repository deleted on exit.  Returns the options needed to access
the repository.

=cut

#sub launch_p4d {
#   my $prefix = shift || "" ;
#
#   {
#      my $borken = p4d_borken ;
#      croak $borken if $borken ;
#   }
#
#   my $tmp  = File::Spec->tmpdir ;
#   my $repo = File::Spec->catdir( $tmp, "vcp${$}_${prefix}p4repo" ) ;
#   mk_tmp_dir $repo ;
#
#   ## Ok, this is wierd: we need to fork & run p4d in foreground mode so that
#   ## we can capture it's PID and kill it later.  There doesn't seem to be
#   ## the equivalent of a 'p4d.pid' file. If we let it daemonize, then I
#   ## don't know how to get it's PID.
#
#   my $port ;
#   my $p4d_pid ;
#   my $tries ;
#   while () {
#      ## 30_000 is because I vaguely recall some TCP stack that had problems
#      ## with listening on really high ports.  2048 is because I vaguely recall
#      ## that some OS required root privs up to 2047 instead of 1023.
#      $port = ( rand( 65536 ) % 30_000 ) + 2048 ;
#      my @p4d = ( 'p4d', '-f', '-r', $repo, '-p', $port ) ;
#      print "# Running ", join( " ", @p4d ), "\n" ;
#      $p4d_pid = fork ;
#      unless ( $p4d_pid ) {
#	 ## Ok, there's a tiny chance that this will fail due to a port
#	 ## collision.  Oh, well.
#	 exec @p4d ;
#	 die "$!: p4d" ;
#      }
#      sleep 1 ;
#      ## Wait for p4d to start.  'twould be better to wait for P4PORT to
#      ## be seen.
#      select( undef, undef, undef, 0.250 ) ;
#
#      last if kill 0, $p4d_pid ;
#      die "p4d failed to start after $tries tries, aborting\n"
#         if ++$tries >= 3 ;
#      warn "p4d failed to start, retrying\n" ;
#   }
#
#   END {
#      return unless defined $p4d_pid ;
#      kill 'INT',  $p4d_pid or die "$! $p4d_pid" ;
#      my $t0 = time ;
#      my $dead_child ;
#      while ( $t0 + 15 > time ) {
#         select undef, undef, undef, 0.250 ;
#	 $dead_child = waitpid $p4d_pid, WNOHANG ;
#	 warn "$!: $p4d_pid" if $dead_child == -1 ;
#	 last if $dead_child ;
#      }
#      unless ( defined $dead_child && $dead_child > 0 ) {
#	 print "terminating $p4d_pid\n" ;
#	 kill 'TERM', $p4d_pid or die "$! $p4d_pid" ;
#	 $t0 = time ;
#	 while ( $t0 + 15 > time ) {
#	    select undef, undef, undef, 0.250 ;
#	    $dead_child = waitpid $p4d_pid, WNOHANG ;
#	    warn "$!: $p4d_pid" if $dead_child == -1 ;
#	    last if $dead_child ;
#	 }
#      }
#      unless ( defined $dead_child && $dead_child > 0 ) {
#	 print "killing $p4d_pid\n" ;
#	 kill 'KILL', $p4d_pid or die "$! $p4d_pid" ;
#      }
#   }
#
#   return {
#      user =>    "${prefix}t_user",
#      port =>    $port,
#   } ;
#}
sub launch_p4d {
   my $prefix = shift || "" ;

   {
      my $borken = p4d_borken ;
      croak $borken if $borken ;
   }

   my $tmp  = File::Spec->tmpdir ;
   my $repo = File::Spec->catdir( $tmp, "vcp${$}_${prefix}p4repo" ) ;
   mk_tmp_dir $repo ;

   ## Ok, this is wierd: we need to fork & run p4d in foreground mode so that
   ## we can capture it's PID and kill it later.  There doesn't seem to be
   ## the equivalent of a 'p4d.pid' file. If we let it daemonize, then I
   ## don't know how to get it's PID.

   my $port ;
   my $tries ;
   my $h ;
   while () {
      ## 30_000 is because I vaguely recall some TCP stack that had problems
      ## with listening on really high ports.  2048 is because I vaguely recall
      ## that some OS required root privs up to 2047 instead of 1023.
      $port = ( rand( 65536 ) % 30_000 ) + 2048 ;
      my @p4d = ( "p4d", "-f", "-r", $repo, "-p", $port ) ;
      print "# Running ", join( " ", @p4d ), "\n" ;
      $h = start \@p4d ;
      ## Wait for p4d to start.  'twould be better to wait for P4PORT to
      ## be seen.
      sleep 1 ;

      ## The child process will have died if the port is taken or due
      ## to other errors.
      last if $h->pumpable;
      finish $h;
      die "p4d failed to start after $tries tries, aborting\n"
         if ++$tries >= 3 ;
      warn "p4d failed to start, retrying\n" ;
   }

   END {
      return unless $h;
      $h->kill_kill;
      $? = 0;  ## p4d exits with a "15", which becomes our exit code
               ## if we don't clear this.
   }

   return {
      user =>    "${prefix}t_user",
      port =>    $port,
   } ;
}

=back

=head1 CVS mgmt functions

=over

=item cvs_borken

Returns true if cvs -v works and outputs "Concurrent Versions System".

=cut

sub cvs_borken {
   my $cvsV = `cvs -v` || 0 ;
   return "cvs command not found" unless $cvsV ;
   return "cvs command does not appear to be for CVS: '$cvsV'"
       unless $cvsV =~ /Concurrent Versions System/;

   return "" ;
}

=item init_cvs

   my $cvs_options = init_cvs $prefix, $module_name ;

Creates a CVS repository containing an empty module. Also sets
$ENV{LOGNAME} if it notices that we're running as root, so CVS won't give
a "cannot commit files as 'root'" error. Tries "nobody", then "guest".

Returns the options needed to access the cvs repository.

=cut

sub init_cvs {
   my ( $prefix , $module ) = @_ ;

   my $tmp = File::Spec->tmpdir ;
   my $options = {
      repo    =>    File::Spec->catdir( $tmp, "vcp${$}_${prefix}cvsroot" ),
      work    =>    File::Spec->catdir( $tmp, "vcp${$}_${prefix}cvswork" ),
   } ;

   my $cwd = cwd ;
   ## Give vcp ... cvs:... a repository to work with.  Note that it does not
   ## use $cvswork, just this test script does.

   $ENV{CVSROOT} = $options->{repo} ;

   ## CVS does not like root to commit files.  So, try to fool it.
   ## CVS calls geteuid() to determine rootness (so does perl's $>).
   ## If root, CVS calls getlogin() first, then checks the LOGNAME and USER
   ## environment vars.
   ##
   ## What this means is: if the user is actually logged in on a physical
   ## terminal as 'root', getlogin() will return "root" to cvs and we can't
   ## fool CVS.
   ##
   ## However, if they've used "su", a very common occurence, then getlogin()
   ## will return failure (NULL in C, undef in Perl) and we can spoof CVS
   ## using $ENV{LOGNAME}.
   if ( ! $>  && $^O !~ /Win32/ ) {
      my $login = getlogin ;
      if ( ( ! defined $login || ! getpwnam $login )
         && ( ! exists $ENV{LOGNAME} || ! getpwnam $ENV{LOGNAME} )
      ) {
	 for ( qw( nobody guest ) ) {
	    my $uid = getpwnam $_ ;
	    next unless defined $uid ;
	    ( $ENV{LOGNAME}, $> ) = ( $_, $uid ) ;
	    last ;
	 }
	 ## Must set uid, too, to keep perl (and thus vcp) from bombing
	 ## out when running setuid and given a -I option. This happens
	 ## a lot in the test suite, since the tests often call vcp
	 ## using "perl", "-Iblib/lib", "bin/vcp", ... to recreate the
	 ## appropriate operating environment for Perl.  If this becomes
	 ## a problem, perhaps we can hack in a "run as user" option to
	 ## VCP::Utils::cvs so that only the cvs subcommands are run
	 ## setuid, or perhaps we can avoid passing "-I" to the perls.
	 $< = $> ;
	 
	 warn
	    "# Setting real & eff. uids=",
	    $>,
	    "(",
	    $ENV{LOGNAME},
	    qq{) to quell "cvs: cannot commit files as 'root'"\n} ;
      }
   }

   mk_tmp_dir $options->{repo} ;

   run [ qw( cvs init ) ]                    or die "cvs init failed" ;

   mk_tmp_dir $options->{work} ;
   chdir $options->{work}                    or die "$!: $options->{work}" ;

   mkdir $module, 0770                       or die "$!: $module" ;
   chdir $module                             or die "$!: $module" ;
   run [ qw( cvs import -m ), "$module import", $module, "${module}_vendor", "${module}_release" ]
                                             or die "cvs import failed" ;
   chdir $cwd                                or die "$!: $cwd" ;

   delete $ENV{CVSROOT} ;
#   chdir ".."                                or die "$! .." ;
#
#   system qw( cvs checkout CVSROOT/modules ) and die "cvs checkout failed" ;
#
#   open MODULES, ">>CVSROOT/modules"         or  die "$!: CVSROOT/modules" ;
#   print MODULES "\n$module $module/\n"      or  die "$!: CVSROOT/modules" ;
#   close MODULES                             or  die "$!: CVSROOT/modules" ;
#
#   system qw( cvs commit -m foo CVSROOT/modules )
#                                             and die "cvs commit failed" ;
   return $options ;
}

=back

=head1 VSS mgmt functions

=over

=item vss_borken

fails unless $ENV{SSUSER} is defined and the command C<ss whoami> runs and
returns what looks like a username.

May lock up if the ss.exe command prompts for a password.

This is because I can't figure out a reliable way to detect if the "ss" command
runs well without risking a lock up, since it has a habit of prompting for
a password that I can't break it of without initalizing a custom Source Safe
repository.

=cut

sub vss_borken {
   return "SSUSER not in the environment" unless defined $ENV{SSUSER};

   my $user = `ss Whoami` ;
   return "ss command not found" unless defined $user && length $user;
   return "ss command did not return just a username"
       unless $user =~ /\A\S+$/m;

   return "" ;
}

=back

=head1 COPYRIGHT

Copyright 2000, Perforce Software, Inc.  All Rights Reserved.

This module and the VCP package are licensed according to the terms given in
the file LICENSE accompanying this distribution, a copy of which is included in
L<vcp>.

=cut

1 ;
