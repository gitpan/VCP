#!/usr/local/bin/perl -w

=head1 NAME

cvs.t - testing of vcp cvs i/o

=cut

use strict ;

use Carp ;
use Cwd ;
use File::Path ;
use File::Spec ;
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


my @tests = (

sub {
   my $type = 'cvs' ;
   my $infile  = $t . "test-$type-in-0.revml" ;
   my $outfile = $t . "test-$type-out-0.revml" ;
   my $infile_t = "test-$type-in-0-tweaked.revml" ;
   my $outfile_t = "test-$type-out-0-tweaked.revml" ;

   ##
   ## Idempotency test
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
   my $infile  = $t . "test-$type-in-1.revml" ;
   my $outfile = $t . "test-$type-out-1.revml" ;
   my $infile_t = "test-$type-in-1-tweaked.revml" ;
   my $outfile_t = "test-$type-out-1-tweaked.revml" ;

   ##
   ## Idempotency test
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
   
   chdir $cwd                                or  die "$!: $cwd" ;
   $ENV{CVSROOT} = "foobar" ;
}


print STDERR $why_skip if $why_skip ;


$why_skip ? skip( 1, '' ) : $_->() for @tests ;

#chdir "$cvswork/cvs_t" or die $! ;;
#print `pwd` ;
#run( ['cvs', 'log', glob( '*/*' )] ) ;
