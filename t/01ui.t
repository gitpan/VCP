#!/usr/local/bin/perl -w

=head1 NAME

01ui.t - testing of VCP::UI

=cut

use strict ;

use Carp ;
use Test ;
use File::Temp qw( tmpnam );
use VCP::UI;
use VCP::TestUtils qw( vcp_cmd );

my @vcp = vcp_cmd ;

my $t = -d 't' ? 't/' : '' ;

# no timeout unless > 0.
my $timeout = 0; 
                


sub _ok {
   my ( $cli_params, $stdin, $exp_return_codes, $expected ) = @_;

   my ( $out, $err ) = ( "", "" );
   my $is_ok = eval {
      my @args = ( [ @vcp, @$cli_params ], \$stdin, \$out, \$err );
      push @args, $timeout if $timeout;
      push @args, { ok_result_codes => $exp_return_codes };
      VCP::TestUtils::run @args;
      1;
   };

   warn "$err" if $err && ! $is_ok;

   @_ = (
      $is_ok ? defined $expected ? "$out$err" : $is_ok : $@,
      defined $expected ? $expected : 1,
      join " ",
         "vcp",
         @$cli_params,
         $stdin ? qq{\\"$stdin"} : ()
   );
   goto &ok;
}

# Rough test of an interactive vcp session.
#
# Takes a list of alternating (output, input) pairs, where the output
# strings are generally user prompts.  The list may be odd-sized, with
# the final output item having no user input expected in response.
#
# Runs vcp in interactive mode, with the input supplied.  There is no
# attempt made to make sure the responses match up with the input,
# only that the responses are seen in the order expected.  The
# responses given are regexes.  They are concatenated together with
# '*', so they need not be complete.
# 
sub ok_interactive_vcp {
   my $options;
   $options = pop if ref $_[-1];
   croak "expected_return_codes option required, and must be array ref"
      unless ref $options->{expected_return_codes} eq "ARRAY";

   my (@output, @prompts);
   while( @_ ) {
      push @output, shift;
      push @prompts, shift
         if @_;
   }
   my $in = join( "\n", @prompts ) . "\n";
   #my $re = join( ".*", map "quotemeta $_", @output );
   my $re = join( ".*", @output );

   my @vcp = qw( vcp );
   @_ = ( [], $in, $options->{expected_return_codes}, /$re/i );
   goto &_ok;
}


my @tests = (
sub { 
   my $ui;
   $ui = VCP::UI->new;
   ok 1;
},

sub { 
   ok ! defined eval { VCP::UI->new( UIImplementation => "NOT::A::REAL::MODULE" )->run };
},

## sub {
##    $timeout = 10;
##    ok_interactive_vcp(
##       "This is vcp's interactive user interface.", "n",
##       { expected_return_codes => [0] }
##    );
## },
## 
## # empty revml->revml
## sub {
##    my $tmpfile = tmpnam();
##    `echo '<revml/>' > $tmpfile`;
##    ok_interactive_vcp(
##       "source scm type",            "revml",
##       "revml filespec",             "$tmpfile",
##       "destination scm type",       "revml",
##       "revml filespec",             "/dev/null",
##       "vcp: sorting revisions by change_id",
##       { expected_return_codes => [0] }
##    );
##    unlink $tmpfile if -e $tmpfile;
## },
## 
## # empty revml->p4
## sub {
##    my $tmpfile = tmpnam();
##    `echo '<revml/>' > $tmpfile`;
##    ok_interactive_vcp(
##       "source scm type",                              "revml",
##       "revml filespec",                               "$tmpfile",
##       "destination scm type",                         "p4",
##       "Launch a private p4d in a local directory",    "y",
##       "Directory to run p4d in",                      "${t}p4root_0",
##       "P4 user id",                                   "",
##       "Password",                                     "",
##       "Destination spec",                             "//depot/foo/...",
##       "vcp: ",
##       { expected_return_codes => [0] }
##    );
##    unlink $tmpfile if -e $tmpfile;
## },

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
