#!/usr/local/bin/perl -w

=head1 NAME

vcp.t - testing of vcp command

=cut

use strict ;

use Carp ;
use Test ;
use VCP::TestUtils qw( vcp_cmd );
use constant is_win32 => $^O =~ /Win32/;

my @vcp = vcp_cmd ;

my $options = <<'END_TRANSFER';
Options: --help
END_TRANSFER

# Note the spaces instead of tabs and the spaces after the null:
my $null_transfer = <<'END_TRANSFER';
Source:
        null:   

Destination:    null:  
END_TRANSFER

my $null_source = <<'END_TRANSFER';
Source: null:   
END_TRANSFER

my $null_destination = <<'END_TRANSFER';
Destination: null:   
END_TRANSFER

# Note the spaces instead of tabs and the spaces after the null:
my $identity_transfer = <<'END_TRANSFER';
Source:
        null:   

Destination:    null:  

Identity:
END_TRANSFER

sub _ok {
   my ( $cli_params, $stdin, $exp_return_codes, $expected ) = @_;

   my ( $out, $err ) = ( "", "" );
   my $ok = eval {
      VCP::TestUtils::run [ @vcp, @$cli_params ],
         \$stdin,
         \$out,
         \$err,
         { ok_result_codes => $exp_return_codes };
      1;
   };

   warn "$err" if $err && ! $ok;

   @_ = (
      $ok ? defined $expected ? "$out$err" : $ok : $@,
      defined $expected ? $expected : 1,
      join " ",
         "vcp",
         @$cli_params,
         $stdin ? qq{\\"$stdin"} : ()
   );
   goto &ok;
}


my @tests = (

#perldoc now complains when run as root, causing this test to fail
sub {
   return skip "perldoc may not be run as root", 1 unless $< || is_win32;
   _ok [ "help" ], undef, [0], qr/help topics/i;
},
sub {
   return skip "perldoc may not be run as root", 1 unless $< || is_win32;
   _ok [ "--help" ], undef, [0], qr/help topics/i
},

sub { _ok [ "vcp:-"  ], $options, [0], qr/help topics/i },

sub { _ok [ "scan",     "vcp:-"  ], $null_transfer,    [0]; },
sub { _ok [ "scan",     "vcp:-"  ], $null_source,      [0]; },
sub { _ok [ "filter",   "vcp:-"  ], $null_transfer,    [0]; },
sub { _ok [ "filter",   "vcp:-"  ], "",                [0]; },

sub { _ok [ "filter",   "vcp:-"  ], $null_source,      [0]; },
sub { _ok [ "filter",   "vcp:-"  ], $null_destination, [0]; },
sub { _ok [ "transfer", "vcp:-"  ], $null_transfer,    [0]; },

sub { _ok [ qw( null: null:                     ) ]                     },
sub { _ok [ qw( null: identity: null:           ) ]                     },
sub { _ok [ qw( null: identity: identity: null: ) ]                     },
sub { _ok [ "vcp:-"                               ], $null_transfer     },
sub { _ok [ "vcp:-"                               ], $identity_transfer },

sub { _ok [ 'foo:'           ], undef, [ 2 ],
    qr/unknown source scheme(.*:){3,}/s  },
sub { _ok [ 'revml:', 'foo:' ], undef, [ 2 ],
    qr/unknown dest\w* scheme(.*:){3,}/s },
sub { _ok [ '--foo'          ], undef, [ 1 ],
    qr/foo.*Usage/s             },

sub {
   local $ENV{VCPDEBUG} = "1";
   _ok [ "help" ], undef, undef, qr/debugging/i;
},

sub {
   _ok [
         "--output-config-file=-",
         "vcp:-"
      ],
      $null_transfer,
      [0],
      qr/Source:.*null:.*Dest:.*null:/s;
},

sub {
   _ok [
         "--output-config-file=-",
         "vcp:-"
      ],
      $identity_transfer,
      [0],
      qr/Source:.*null:.*Dest:.*null:.*Identity:/s;
},
sub {
   _ok [
         "--output-config-file=-",
         qw( null: identity: identity: null: )
      ],
      undef,
      [0],
      qr/Source:.*null:.*Dest:.*null:.*Identity:.*Identity:/s;
},
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
