#!/usr/local/bin/perl -w

=head1 NAME

p4.t - testing of vcp p4 i/o

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

## TODO: Test bootstrap mode

## We always run vcp by doing a $perl vcp, to make sure that vcp runs under
## the same version of perl that we are running under.
my $vcp = 'bin/vcp' ;
$vcp = "../bin/$vcp" if -x "../bin/$vcp" ;
$vcp = File::Spec->catfile( $cwd, $vcp ) ;

my $t = -d 't' ? 't/' : '' ;

my $p4repo = File::Spec->catdir( cwd, 'tmp', "p4repo" ) ;
my $p4work = File::Spec->catdir( cwd, 'tmp', "p4work" ) ;
my ( $p4user, $p4client, $p4port ) = qw( p4_t_user p4_t_client 19666 ) ;
my $p4spec = "p4:$p4user($p4client):\@$p4port:" ;

my $cvsroot = File::Spec->catdir( cwd, 'tmp', "p4cvsroot" ) ;
my $cvswork = File::Spec->catdir( cwd, 'tmp', "p4cvswork" ) ;
$ENV{CVSROOT} = $cvsroot;
my $cvs_module = 'depot' ;

my $depot = "//depot" ;

my $incr_change ; # what change number to start incremental export at

my $perl = $^X ;

sub slurp {
   my ( $fn ) = @_ ;
   open F, "<$fn" or die "$!: $fn" ;
   local $/ ;
   return <F> ;
}


my @tests = (

sub {
   ## revml -> p4 -> revml, bootstrap export
   my $type = 'p4' ;
   my $infile  = $t . "test-$type-in-0.revml" ;
   my $outfile = $t . "test-$type-out-0.revml" ;
   my $infile_t = "test-$type-in-0-tweaked.revml" ;
   my $outfile_t = "test-$type-out-0-tweaked.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-0.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   my $diff = '' ;
   eval {
      my $out ;
      ## $in and $out allow us to avoide execing diff most of the time.
      run [ $perl, $vcp, "revml:$infile", $p4spec, '-w', $p4work ], \undef
	 or die "`$vcp revml:$infile $p4spec` returned $?" ;

      run [ $perl, $vcp, "$p4spec..." ], \undef, \$out 
	 or die "`$vcp $p4spec...` returned $?" ;

      my $in = slurp $infile ;

#$out =~ s{<name>depot/}{<name>}g ;
$in =~ s{^\s*<p4_info>.*?</p4_info>\n}{}smg ;
$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;

      ## The r_ and ch_ labels are not present in the source files.
      $out =~ s{.*<label>(r|ch)_\w+</label>\r?\n\r?}{}g ;

      open F, ">$infile_t" ; print F $in ; close F ;
      open F, ">$outfile_t" ; print F $out ; close F ;
      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, \$diff )
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
#   chdir $cwd or die "$!: $cwd" ;
},

sub {
   ## Test a single file extraction from a p4 repo.  This file exists in
   ## change 1.
   my $out ;
   run( [$perl, $vcp, "$p4spec//depot/add/f1"], \undef, \$out ) ;
   ok(
      $out,
      qr{<rev_root>depot/add</.+<name>f1<.+<rev_id>1<.+<rev_id>2<.+</revml>}s
   ) ;
},

sub {
   ## Test a single file extraction from a p4 repo.  This file does not exist
   ## in change 1.
   my $out ;
   run( [$perl, $vcp, "$p4spec//depot/add/f2"], \undef, \$out ) ;
   ok(
      $out,
      qr{<rev_root>depot/add</.+<name>f2<.+<change_id>2<.+<change_id>3<.+</revml>}s
   ) ;

},

sub {
   ## p4 -> cvs bootstrap (to -> revml when we get VCP::Source::cvs to check
   ## cvs results)
   my $type = 'p4' ;
   my $infile  = $t . "test-$type-in-0.revml" ;
   my $outfile  = $t . "test-$type-out-cvs-0.revml" ;
   my $infile_t = "test-$type-in-0-cvs-tweaked.revml" ;
   my $outfile_t = "test-$type-out-0-cvs-tweaked.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   my $diff = '' ;
   eval {
      my $out ;
      run( [ $perl, $vcp, "$p4spec//depot/...", "cvs" ], \undef )
	 or die "`$vcp $p4spec//depot/... cvs` returned $?" ;

      ## Gotta use a working directory with a checked-out version
      chdir $cvswork or die $! . ": '$cvswork'" ;
      run [qw( cvs checkout ), $cvs_module], \undef, \*STDERR, \*STDERR
	 or die $! ;

      run( [ $vcp, "cvs:$cvs_module", qw( -r 1.1: ) ], \undef, \$out )
	 or die "`$vcp cvs:$cvs_module -r 1.1: ` returned $?" ;

      chdir $cwd or die $! ;

      my $in = slurp $infile ;

#$out =~ s{<name>depot/}{<name>}g ;
$in =~ s{^\s*<p4_info>.*?</p4_info>\n}{}smg ;
$in =~ s{<rep_type>.*?</rep_type>}{<rep_type><!--deleted by p4.t--></rep_type>}s ;
$out =~ s{<rep_type>.*?</rep_type>}{<rep_type><!--deleted by p4.t--></rep_type>}s ;
$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;
$in =~ s{^\s*<change_id>.*?</change_id>\n}{}smg ;

$out =~ s{^\s*<label>r_.*?</label>\n}{}smg ;
$out =~ s{^\s*<label>ch_.*?</label>\n}{}smg ;

$out =~ s{<rev_id>1.}{<rev_id>}g ;
$out =~ s{<base_rev_id>1.}{<base_rev_id>}g ;

$in =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by p4.t--></user_id>}sg ;
$out =~ s{<user_id>.*?</user_id>}{<user_id><!--deleted by p4.t--></user_id>}sg ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;

open F, ">$infile_t" ; print F $in ; close F ;
open F, ">$outfile_t" ; print F $out ; close F ;

      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, \$diff )
	 && $? != 256
      ) {
	 die "`diff -d -u $infile_t $outfile_t returned $?" ;
      }
   } ;
   $diff = $@ if $@ ;
   chomp $diff ;
   ok( $diff, '' ) ;
   if ( $diff eq '' ) {
      if ( -e $infile_t ) { unlink $infile_t or warn "$!: $infile_t" ; }
      if ( -e $outfile_t ) { unlink $outfile_t or warn "$!: $outfile_t" ; }
   }
},

sub {
   ## revml -> p4 -> revml, incremental export
   my $type = 'p4' ;
   my $infile  = $t . "test-$type-in-1.revml" ;
   my $outfile = $t . "test-$type-out-1.revml" ;
   my $infile_t = "test-$type-in-1-tweaked.revml" ;
   my $outfile_t = "test-$type-out-1-tweaked.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-0.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   my $diff = '' ;
   eval {
      run
         [ qw( p4 -u ), $p4user, "-c", $p4client, "-p", $p4port, qw( counter change ) ],
	 \undef, \$incr_change ;
      chomp $incr_change ;
      die "Invalid change counger value: '$incr_change'"
         unless $incr_change =~ /^\d+$/ ;

      ++$incr_change ;

      my $out ;

      ## $in and $out allow us to avoide execing diff most of the time.
      run [ $perl, $vcp, "revml:$infile", "$p4spec", '-w', $p4work ], \undef
	 or die "`$vcp revml:$infile $p4spec` returned $?" ;

      run [ $perl, $vcp, "$p4spec...\@$incr_change,#head" ], \undef, \$out
	 or die "`$vcp $p4spec...\@$incr_change,#head` returned $?" ;

      my $in = slurp $infile ;

$out =~ s{<name>depot/}{<name>}g ;
$in =~ s{^\s*<p4_info>.*?</p4_info>\n}{}smg ;
$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;

      ## The r_ and ch_ labels are not present in the source files.
      $out =~ s{.*<label>(r|ch)_\w+</label>\r?\n\r?}{}g ;

      open F, ">$infile_t" ; print F $in ; close F ;
      open F, ">$outfile_t" ; print F $out ; close F ;

      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, \$diff )
	 && $? != 256
      ) {
	 die "`diff -d -u $infile_t $outfile_t returned $?" ;
      }
   } ;
   $diff = $@ if $@ ;
   chomp $diff ;
   ok( $diff, '' ) ;
   if ( $diff eq '' ) {
      if ( -e $infile_t ) { unlink $infile_t or warn "$!: $infile_t" ; }
      if ( -e $outfile_t ) { unlink $outfile_t or warn "$!: $outfile_t" ; }
   }
#   chdir $cwd or die "$!: $cwd" ;
},

sub {
   ## p4 -> revml, incremental export in bootstrap mode
   my $type = 'p4' ;
   my $infile  = $t . "test-$type-in-1-bootstrap.revml" ;
   my $outfile = $t . "test-$type-out-1-bootstrap.revml" ;
   my $infile_t = "test-$type-in-1-bootstrap-tweaked.revml" ;
   my $outfile_t = "test-$type-out-1-bootstrap-tweaked.revml" ;
   ##
   ## Idempotency test
   ##
   ## These depend on the "test-foo-in-0.revml" files built in the makefile.
   ## See MakeMaker.PL for how those are generated.
   ##
   my $diff = '' ;
   eval {
      my $out ;

      run( [ $perl, $vcp, "$p4spec...\@$incr_change,#head", "--bootstrap=**" ],
         \undef, \$out
      ) or die(
	 "`$vcp $p4spec...\@$incr_change,#head --bootstrap=**` returned $?"
      ) ;

      my $in = slurp $infile ;

$out =~ s{<name>depot/}{<name>}g ;
$in =~ s{^\s*<p4_info>.*?</p4_info>\n}{}smg ;
$in =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;
$out =~ s{<rep_desc>.*?</rep_desc>}{<rep_desc><!--deleted by p4.t--></rep_desc>}s ;

$in =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;
$out =~ s{<time>.*?</time>}{<time><!--deleted by p4.t--></time>}sg ;

      ## The r_ and ch_ labels are not present in the source files.
      $out =~ s{.*<label>(r|ch)_\w+</label>\r?\n\r?}{}g ;

      open F, ">$infile_t" ; print F $in ; close F ;
      open F, ">$outfile_t" ; print F $out ; close F ;

      if (
	 $in ne $out
	 && run( [ 'diff', '-U', '10', $infile_t, $outfile_t ], \undef, \$diff )
	 && $? != 256
      ) {
	 die "`diff -d -u $infile_t $outfile_t` returned $?" ;
      }
   } ;
   $diff = $@ if $@ ;
   chomp $diff ;
   ok( $diff, '' ) ;
   if ( $diff eq '' ) {
      if ( -e $infile_t ) { unlink $infile_t or warn "$!: $infile" ; }
      if ( -e $outfile_t ) { unlink $outfile_t or warn "$!: $outfile" ; }
   }
#   chdir $cwd or die "$!: $cwd" ;
},

) ;
plan tests => scalar( @tests ), todo => [4] ;

##
## Build a repository and they will come...
##

my $why_skip ;

$why_skip .= "# '$vcp' not found\n"    unless -x $vcp ;
$why_skip .= "p4 command not found\n"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "p4d command not found\n" unless ( `p4d -V` || 0 ) =~ /^Perforce/ ;

my $p4d_pid ;

unless ( $why_skip ) {
   ## Give vcp ... p4:... a repository to work with.  Note that it does not
   ## use $p4work, just this test script does.
   rmtree [ $p4repo, $p4work ] ;
   mkpath [ $p4repo, $p4work ], 0, 0700 ;
#   END { rmtree [$p4repo,$p4work] }

   rmtree [ $cvsroot, $cvswork ] ;
   mkpath [ $cvsroot, $cvswork ], 0, 0700 ;
#   END { rmtree [$cvsroot,$cvswork] }

   $ENV{P4USER}= $p4user ;
   $ENV{P4CLIENT}= $p4client ;
   $ENV{P4PORT} = $p4port ;

   launch_p4d() ;
   init_client() ;
   init_cvs() ;
   $ENV{P4USER}   = "foobar_user" ;
   $ENV{P4PORT}   = "foobar_port" ;
   $ENV{P4CLIENT} = "foobar_client" ;
   $ENV{P4PASSWD} = "foobar_passwd" ;
}

print STDERR $why_skip if $why_skip ;

$why_skip ? skip( 1, '' ) : $_->() for @tests ;

###############################################################################

sub launch_p4d {
   ## Ok, this is wierd: we need to fork & run p4d in foreground mode so that
   ## we can capture it's PID and kill it later.  There doesn't seem to be
   ## the equivalent of a 'p4d.pid' file.
   $p4d_pid = fork ;
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


sub init_cvs {
   ## Give vcp ... cvs:... a repository to work with.  Note that it does not
   ## use $cvswork, just this test script does.

   system qw( cvs init )                     and die "cvs init failed" ;

   chdir $cvswork                            or  die "$!: $cvswork" ;

   mkdir $cvs_module, 0770                   or  die "$!: $cvs_module" ;
   chdir $cvs_module                         or  die "$!: $cvs_module" ;
   system qw( cvs import -m foo ), $cvs_module, $cvs_module, qw( foo )
                                             and die "cvs import failed" ;
   chdir $cwd                                or  die "$!: $cwd" ;
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
   
}
