#!/usr/local/bin/perl -w

=head1 NAME

cvs.t - testing of vcp cvs i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use File::Path ;
use File::Spec ;
use POSIX ':sys_wait_h' ;
use Test ;
use IPC::Run qw( run ) ;

my $cwd = cwd ;

## We always run vcp by doing a $^X vcp, to make sure that vcp runs under
## the same version of perl that we are running under.
my $vcp = 'vcp' ;
$vcp = "bin/$vcp"    if -x "bin/$vcp" ;
$vcp = "../bin/$vcp" if -x "../bin/$vcp" ;

$vcp = File::Spec->catfile( $cwd, $vcp ) ;

my $t = -d 't' ? 't/' : '' ;

my $p4repo = File::Spec->catdir( cwd, 'tmp', "cvsp4repo" ) ;
my $p4work = File::Spec->catdir( cwd, 'tmp', "cvsp4work" ) ;
my ( $p4user, $p4client, $p4port ) = qw( p4_t_user p4_t_client 19666 ) ;
my $p4spec = "p4:$p4user($p4client):\@$p4port:" ;

my $cvsroot = File::Spec->catdir( cwd, 'tmp', "cvsroot" ) ;
my $cvswork = File::Spec->catdir( cwd, 'tmp', "cvswork" ) ;
my $module = 'foo' ;  ## Must match the rev_root in the testrevml files

my $perl = $^X ;

sub slurp {
   my ( $fn ) = @_ ;
   open F, "<$fn" or die "$!: $fn" ;
   local $/ ;
   return <F> ;
}

my $max_change_id ;

my @tests = (

sub {
   my $type = 'cvs' ;
   my $infile  = $t . "test-$type-in-0.revml" ;
   my $outfile = $t . "test-$type-out-0.revml" ;
   my $infile_t = "test-$type-in-0-tweaked.revml" ;
   my $outfile_t = "test-$type-out-0-tweaked.revml" ;

   ##
   ## Idempotency test revml->cvs->revml
   ##
   my $diff = '' ;
   eval {
      my $out ;
      my $err ;
      ## $in and $out allow us to avoide execing diff most of the time.
      run( [ $perl, $vcp, "revml:$infile", "cvs:$cvsroot:$module" ], \undef )
	 or die "`$vcp revml:$infile cvs:$cvsroot:$module` returned $?" ;

      run(
         [ $perl, $vcp, "cvs:$cvsroot:$module", qw( -r 1.1: ) ], \undef, \$out , \$err,
         init => sub {
	    ## Gotta use a working directory with a checked-out version
	    chdir $cvswork or die $! . ": '$cvswork'" ;
	    run [qw( cvs -d ), $cvsroot, "checkout", $module],
	       \undef, \*STDERR, \*STDERR
	       or die $! ;
	 }
      ) or die "`$vcp cvs:$cvsroot:$module -r 1.1:` returned $?" ;

      print STDERR $err if defined $err ;

      my $in = slurp $infile ;

$in =~ s{^\s*<cvs_info>.*?</cvs_info>(\r\n|\n\r|\n)}{}smg ;

$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;

$in =~ s{^.*<mod_time>.*?</mod_time>.*(\r\n|\n\r|\n)}{}mg ;

$out =~ s{^.*<label>r_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$in =~ s{^.*<change_id>.*?</change_id>.*(\r\n|\n\r|\n)}{}mg ;
$out =~ s{^.*<label>ch_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$in =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg ;
$out =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg ;

#      ## The r_ and ch_ labels are not present in the source files.
#      $out =~ s{.*<label>(r|ch)_\w+</label>\r?\n\r?}{}g ;

      open F, ">$infile_t" ; print F $in ; close F ;
      open F, ">$outfile_t" ; print F $out ; close F ;
      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, '>', \$diff )
	 && $? != 256
      ) {
	 die "`diff -d -u $infile_t $outfile_t` returned $?" ;
      }

   } ;
   $diff = $@ if $@ ;
   chomp $diff ;
   ok( $diff, '' ) ;
   if ( $diff eq '' ) {
      if ( -e $infile_t  ) { unlink $infile_t  or warn "$!: $infile_t"  ; }
      if ( -e $outfile_t ) { unlink $outfile_t or warn "$!: $outfile_t" ; }
   }
},

sub {
   my $type = 'cvs' ;
   my $infile  = $t . "test-$type-in-0.revml" ;
   my $outfile = $t . "test-$type-out-0-p4.revml" ;
   my $infile_t = "test-$type-in-0-p4-tweaked.revml" ;
   my $outfile_t = "test-$type-out-0-p4-tweaked.revml" ;

   ##
   ## cvs->p4->revml
   ##
   my $diff = '' ;
   eval {
      my $out ;
      my $err ;

      ## Gotta use a working directory with a checked-out version
      chdir $cvswork or die $! . ": '$cvswork'" ;
      run [qw( cvs -d ), $cvsroot, "checkout", $module], \undef
	 or die $! ;

      run(
         [ $perl, $vcp, "cvs:$cvsroot:$module", qw( -r 1.1: ),
	    $p4spec, "-w", $p4work
	 ], \undef
      ) or die "`$vcp cvs:$cvsroot:$module -r 1.1:` returned $?" ;

      chdir $cwd or die $! ;

      run [ $perl, $vcp, "$p4spec//depot/..." ], \undef, \$out ;

      my $in = slurp $infile ;

$in =~ s{^\s*<cvs_info>.*?</cvs_info>(\r\n|\n\r|\n)}{}smg ;

$in =~ s{<rep_type>.*?</rep_type>}{<rep_type><!--deleted by cvs.t--></rep_type>}s ;
$out =~ s{<rep_type>.*?</rep_type>}{<rep_type><!--deleted by cvs.t--></rep_type>}s ;
$in =~ s{<rev_root>.*?</rev_root>}{<rev_root><!--deleted by cvs.t--></rev_root>}s ;
$out =~ s{<rev_root>.*?</rev_root>}{<rev_root><!--deleted by cvs.t--></rev_root>}s ;

$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;

$in =~ s{^.*<mod_time>.*?</mod_time>.*(\r\n|\n\r|\n)}{}mg ;

$out =~ s{^.*<label>r_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$in =~ s{^.*<change_id>.*?</change_id>.*(\r\n|\n\r|\n)}{}mg ;
$out =~ s{^.*<label>ch_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$out =~ s{^.*<change_id>(.*?)</change_id>.*(\r\n|\n\r|\n)}{
   $max_change_id = $1 if ! defined $max_change_id || $1 > $max_change_id ;
   ""
}gem ;

$out =~ s{<rev_id>}{<rev_id>1.}g ;
$out =~ s{<base_rev_id>}{<base_rev_id>1.}g ;

$in =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg ;
$out =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg;

$out =~ s{\s*<p4_info>.*?</p4_info>}{}sg ;

#      ## The r_ and ch_ labels are not present in the source files.
#      $out =~ s{.*<label>(r|ch)_\w+</label>\r?\n\r?}{}g ;

      open F, ">$infile_t" ; print F $in ; close F ;
      open F, ">$outfile_t" ; print F $out ; close F ;
      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, '>', \$diff )
	 && $? != 256
      ) {
	 die "`diff -d -u $infile_t $outfile_t` returned $?" ;
      }

   } ;
   $diff = $@ if $@ ;
   chomp $diff ;
   ok( $diff, '' ) ;
   if ( $diff eq '' ) {
      if ( -e $infile_t  ) { unlink $infile_t  or warn "$!: $infile_t"  ; }
      if ( -e $outfile_t ) { unlink $outfile_t or warn "$!: $outfile_t" ; }
   }
},

sub { skip( ! defined $max_change_id, $max_change_id, 3, "Max change_id in cvs->p4 transfer" ) },

sub {
   my $type = 'cvs' ;
   my $infile  = $t . "test-$type-in-1.revml" ;
   my $outfile = $t . "test-$type-out-1.revml" ;
   my $infile_t = "test-$type-in-1-tweaked.revml" ;
   my $outfile_t = "test-$type-out-1-tweaked.revml" ;

   ##
   ## Idempotency test for an incremental revml->cvs->revml update
   ##
   my $diff = '' ;
   eval {
      my $out ;
      ## $in and $out allow us to avoid execing diff most of the time.
      run( [ $perl, $vcp, "revml:$infile", "cvs:$cvsroot:$module" ], \undef )
	 or die "`$vcp revml:$infile cvs:$cvsroot:$module` returned $?" ;

      ## Gotta use a working directory with a checked-out version
      chdir $cvswork or die $! . ": '$cvswork'" ;
      run [qw( cvs -d ), $cvsroot, "checkout", $module],
         \undef, \*STDERR, \*STDERR
	 or die $! ;

      run(
         [ $perl, $vcp, "cvs:$cvsroot:$module", qw( -r ch_4: -f ) ],
	    \undef, \$out ,
      ) or die "`$vcp cvs:$cvsroot:$module -r ch_4:` returned $?" ;

      chdir $cwd or die $! ;

      my $in = slurp $infile ;

$in =~ s{^\s*<cvs_info>.*?</cvs_info>(\r\n|\n\r|\n)}{}smg ;

$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;

$in =~ s{^.*<mod_time>.*?</mod_time>.*(\r\n|\n\r|\n)}{}mg ;

$out =~ s{^.*<label>r_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$in =~ s{^.*<change_id>.*?</change_id>.*(\r\n|\n\r|\n)}{}mg ;
$out =~ s{^.*<label>ch_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$in =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg ;
$out =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg ;

#      ## The r_ and ch_ labels are not present in the source files.
#      $out =~ s{.*<label>(r|ch)_\w+</label>\r?\n\r?}{}g ;

      open F, ">$infile_t" ; print F $in ; close F ;
      open F, ">$outfile_t" ; print F $out ; close F ;
      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, '>', \$diff )
	 && $? != 256
      ) {
	 die "`diff -d -u $infile_t $outfile_t` returned $?" ;
      }

   } ;
   $diff = $@ if $@ ;
   chomp $diff ;
   ok( $diff, '' ) ;
   if ( $diff eq '' ) {
      if ( -e $infile_t  ) { unlink $infile_t  or warn "$!: $infile_t"  ; }
      if ( -e $outfile_t ) { unlink $outfile_t or warn "$!: $outfile_t" ; }
   }
},

sub {
   my $type = 'cvs' ;
   my $infile  = $t . "test-$type-in-1-bootstrap.revml" ;
   my $outfile = $t . "test-$type-out-1-bootstrap.revml" ;
   my $infile_t = "test-$type-in-1-bootstrap-tweaked.revml" ;
   my $outfile_t = "test-$type-out-1-bootstrap-tweaked.revml" ;

   ##
   ## Idempotency test
   ##
   my $diff = '' ;
   eval {
      my $out ;

      ## Gotta use a working directory with a checked-out version
      chdir $cvswork or die $! . ": '$cvswork'" ;
      run [qw( cvs -d ), $cvsroot, "checkout", $module],
         \undef, \*STDERR, \*STDERR
	 or die $! ;

      run(
         [ $perl, $vcp, "cvs:$cvsroot:$module", qw( -r ch_4: -f --bootstrap=** ) ],
	    \undef, \$out ,
      ) or die "`$vcp cvs:$cvsroot:$module -r ch_4:` returned $?" ;

      chdir $cwd ;

      my $in = slurp $infile ;

$in =~ s{^\s*<cvs_info>.*?</cvs_info>(\r\n|\n\r|\n)}{}smg ;

$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by cvs.t--></rep_desc>}s ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by cvs.t--></time>}sg ;

$in =~ s{^.*<mod_time>.*?</mod_time>.*(\r\n|\n\r|\n)}{}mg ;

$out =~ s{^.*<label>r_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$in =~ s{^.*<change_id>.*?</change_id>.*(\r\n|\n\r|\n)}{}mg ;
$out =~ s{^.*<label>ch_.*?</label>.*(\r\n|\n\r|\n)}{}mg ;

$in =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg ;
$out =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by cvs.t--></user_id>}sg ;

#      ## The r_ and ch_ labels are not present in the source files.
#      $out =~ s{.*<label>(r|ch)_\w+</label>\r?\n\r?}{}g ;

      open F, ">$infile_t" ; print F $in ; close F ;
      open F, ">$outfile_t" ; print F $out ; close F ;
      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, '>', \$diff )
	 && $? != 256
      ) {
	 die "`diff -d -u $infile_t $outfile_t` returned $?" ;
      }

   } ;
   $diff = $@ if $@ ;
   chomp $diff ;
   ok( $diff, '' ) ;
   if ( $diff eq '' ) {
      if ( -e $infile_t  ) { unlink $infile_t  or warn "$!: $infile_t"  ; }
      if ( -e $outfile_t ) { unlink $outfile_t or warn "$!: $outfile_t" ; }
   }
},

) ;

plan tests => scalar( @tests ) ;

##
## Build a repository and they will come...
##

my $why_skip ;

$why_skip .= "# '$vcp' not found\n"    unless -x $vcp ;
$why_skip .= "cvs command not found\n" unless `cvs -v` =~ /Concurrent Versions System/ ;
unless ( $why_skip ) {
   ## Give vcp ... cvs:... a repository to work with.  Note that it does not
   ## use $cvswork, just this test script does.
   rmtree [ $p4repo, $p4work ] ;
   mkpath [ $p4repo, $p4work ], 0, 0700 ;
#   END { rmtree [$p4repo,$p4work] }


   $ENV{CVSROOT} = $cvsroot ;
   rmtree [ $cvsroot, $cvswork ] ;
   mkpath [ $cvsroot, $cvswork ], 0, 0700 ;
#   END { rmtree [$cvsroot,$cvswork] }

   system qw( cvs init )                     and die "cvs init failed" ;

   chdir $cvswork                            or  die "$!: $cvswork" ;
   mkdir $module, 0770                       or  die "$!: $module" ;
   chdir $module                             or  die "$!: $module" ;
   system qw( cvs import -m ), "${module} import", $module, "${module}_vendor", "${module}_release"
                                             and die "cvs import failed" ;
   chdir $cwd                                or  die "$!: $cwd" ;
   $ENV{CVSROOT} = "foobar" ;

   $ENV{P4USER}= $p4user ;
   $ENV{P4CLIENT}= $p4client ;
   $ENV{P4PORT} = $p4port ;

   launch_p4d() ;
   init_client() ;

   $ENV{P4USER}   = "foobar_user" ;
   $ENV{P4PORT}   = "foobar_port" ;
   $ENV{P4CLIENT} = "foobar_client" ;
   $ENV{P4PASSWD} = "foobar_passwd" ;
}


print STDERR $why_skip if $why_skip ;


$why_skip ? skip( 1, '' ) : $_->() for @tests ;

#chdir "$cvswork/cvs_t" or die $! ;;
#print `pwd` ;
#run( ['cvs', 'log', glob( '*/*' )] ) ;

###############################################################################

sub launch_p4d {
   ## Ok, this is wierd: we need to fork & run p4d in foreground mode so that
   ## we can capture it's PID and kill it later.  There doesn't seem to be
   ## the equivalent of a 'p4d.pid' file.
   my $p4d_pid = fork ;
   unless ( $p4d_pid ) {
      ## Ok, there's a tiny chance that this will fail due to a port
      ## collision.  Oh, well.
      exec 'p4d', '-f', '-r', $p4repo ;
      die "$!: p4d" ;
   }
   ## Wait for p4d to start.  'twould be better to wait for P4PORT to
   ## be seen.
   select( undef, undef, undef, 0.250 ) ;
   END {
      kill 'INT',  $p4d_pid or die "$! $p4d_pid" ;
      my $t0 = time ;
      my $dead_child ;
      while ( $t0 + 15 > time ) {
         select undef, undef, undef, 0.250 ;
	 $dead_child = waitpid $p4d_pid, WNOHANG ;
	 warn "$!: $p4d_pid" if $dead_child == -1 ;
	 last if $dead_child ;
      }
      unless ( defined $dead_child && $dead_child > 0 ) {
	 print "terminating $p4d_pid\n" ;
	 kill 'TERM', $p4d_pid or die "$! $p4d_pid" ;
	 $t0 = time ;
	 while ( $t0 + 15 > time ) {
	    select undef, undef, undef, 0.250 ;
	    $dead_child = waitpid $p4d_pid, WNOHANG ;
	    warn "$!: $p4d_pid" if $dead_child == -1 ;
	    last if $dead_child ;
	 }
      }
      unless ( defined $dead_child && $dead_child > 0 ) {
	 print "killing $p4d_pid\n" ;
	 kill 'KILL', $p4d_pid or die "$! $p4d_pid" ;
      }
   }
}


sub init_client {
   my $client_desc = `p4 client -o` ;
   $client_desc =~ s(^Root.*)(Root:\t$p4work)m ;
   $client_desc =~ s(^View.*)(View:\n\t//depot/...\t//$ENV{P4CLIENT}/...\n)ms ;
   open( P4, "| p4 client -i" ) or die "$! p4 client -i" ;
   print P4 $client_desc ;
   close P4 ;
}
