#!/usr/local/bin/perl -w

=head1 NAME

01driver.t - testing of VCP::Driver services

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Utils qw( start_dir_rel2abs );
use VCP::Driver;

my $p ;

sub flatten_spec {
   my ( $obj ) = @_ ;

   return join(
      ' ',
      map(
         {
            local $_ = $obj->$_();
            defined $_ ? $_ : '-' ;
         }
         qw( repo_scheme repo_user repo_password repo_server repo_filespec )
      )
   ) ;
}

my @repo_vectors = (
[ 'scheme:user:password@server:files',
  'scheme user password server files' ],   

[ 'scheme:user:password@ser@:ver:files',
  'scheme user password ser@:ver files' ],   

[ 'scheme:files',
  'scheme - - - files' ],   

[ 'scheme:user@files',
  'scheme - - - user@files' ],   

[ 'scheme:user@:files',
  'scheme user - - files' ],   

) ;

my @tests = (
sub { $p = VCP::Driver->new() ; ok( ref $p, 'VCP::Driver' ) },

sub { ok "axx()" =~ $p->compile_path_re( "a**()" ) },
sub { ok "a/b"   !~ $p->compile_path_re( "a**b"  ) },
sub { ok "a/b"   =~ $p->compile_path_re( "a...b"  ) },
sub { ok "a\\b"  =~ $p->compile_path_re( "a...b"  ) },

##
## rev_root cleanup
##
sub { $p->rev_root( '\\//foo\\//bar\\//' )               ; ok( $p->rev_root, 'foo/bar' )},
sub { $p->deduce_rev_root( '\\foo/bar' )                 ; ok( $p->rev_root, 'foo'     )},
sub { $p->deduce_rev_root( '\\foo/bar/' )                ; ok( $p->rev_root, 'foo/bar' )},
sub { $p->deduce_rev_root( '\\foo/bar/blah*blop/baz' )   ; ok( $p->rev_root, 'foo/bar' )},
sub { $p->deduce_rev_root( '\\foo/bar/blah?blop/baz' )   ; ok( $p->rev_root, 'foo/bar' )},
sub { $p->deduce_rev_root( '\\foo/bar/blah...blop/baz' ) ; ok( $p->rev_root, 'foo/bar' )},

##
## Normalization & de-normalization
##
sub { ok( $p->normalize_name( '/foo/bar/baz' ), 'baz' ) },
#sub { eval {$p->normalize_name( '/foo/hmmm/baz' ) }, ok( $@ ) },
sub { ok( $p->denormalize_name( 'barf' ), 'foo/bar/barf' ) },

( map {
      my ( $spec, $flattened ) = @$_ ;
      my $s;
      sub {
         $p = VCP::Driver->new();  # make sure spec fields initialized
         $p->parse_repo_spec( $spec );
         ok( flatten_spec( $p ), $flattened );
      },
      sub {
         $s = $p->repo_spec_as_string;
         ok $s, $spec;
      },
      sub {
         $p = VCP::Driver->new();  # make sure spec fields initialized
         $p->parse_repo_spec( $s );
         ok( flatten_spec( $p ), $flattened );
      },

   } @repo_vectors
),

sub {
   $p = VCP::Driver->new();  # make sure spec fields initialized
   $p->parse_repo_spec( 'scheme:user:password@server:files' ) ;
   ok( $p->repo_user, 'user' ) ;
},

sub {
   ok( $p->repo_password, 'password' ) ;
},

sub {
   ok( $p->repo_server, 'server' ) ;
},

## Subprocesses that behave as expected
sub {
   $p->run_safely( [ $^X, qw( -e exit(0) ) ] );
   ok $p->command_result_code, 0;
},

sub {
   ok ! eval { $p->run_safely( [ $^X, qw( -e exit(1) ) ] ); 1 };
},

sub {
   ok $p->command_result_code, 1;
},

sub {
   $p->run_safely( [ $^X, qw( -e exit(1) ) ], { ok_result_codes => [ 1 ] } );
   ok $p->command_result_code, 1;
},

sub {
   $p->run_safely( [ $^X, qw( -e exit(1) ) ], { ok_result_codes => [ 0, 1 ] } );
   ok $p->command_result_code, 1;
},

sub {
   ok ! eval { $p->run_safely( [ $^X, qw( -e exit(2) ) ], { ok_result_codes => [ 0, 1 ] } ) };
},

sub {
   ok $p->command_result_code, 2;
},

sub {
   $p->run_safely( [ $^X, qw( -e warn("hi\n") ) ], { stderr_filter => qr/^hi\r?\n/ } );
   ok 1;
},

sub {
   ok join( " ", $p->options_spec ), qr/repo-id.*SCALAR/s;
},

sub {
   ok join( " ", $p->options_as_strings ), qr/#--repo-id/;
},

sub {
   $p->repo_id( "foo" );
   ok join( " ", map "'$_'", $p->options_as_strings ), qr/'--repo-id=foo'/;
},

sub {
   ok $p->revs;
},

sub {
   $p->repo_id( "" );
   ok join( " ", map "'$_'", $p->options_as_strings ), qr/'--repo-id='/;
},

sub {
   @VCP::Source::foo::ISA = qw( VCP::Driver );
   $INC{"VCP/Source/foo.pm"} = start_dir_rel2abs $0; ## To make the POD scanner happy.
   bless $p, "VCP::Source::foo";
   $p->parse_repo_spec( "floo:files" );
   $p->repo_id( "a repo" );
   ok $p->config_file_section_as_string,
      qr/Source:.*floo:files.*repo-id=a repo/s;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
