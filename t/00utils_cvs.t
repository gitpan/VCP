#!/usr/local/bin/perl -w

=head1 NAME

00utils_cvs.t - testing of VCP::Utils::cvs

=cut

use strict ;

use Carp ;
use Test ;
use VCP::Utils::cvs;

my @tests = (
sub { ok eval { VCP::Utils::cvs::RCS_check_tag( "a"  ), 1 } || $@, 1 },
sub { ok eval { VCP::Utils::cvs::RCS_check_tag( "ab" ), 1 } || $@, 1 },
sub { ok eval { VCP::Utils::cvs::RCS_check_tag( "a1" ), 1 } || $@, 1 },
sub { ok eval { VCP::Utils::cvs::RCS_check_tag( "a(" ), 1 } || $@, 1 },
sub { ok eval { VCP::Utils::cvs::RCS_check_tag( "0"  ), 1 } ||  0, 0 },
sub { ok eval { VCP::Utils::cvs::RCS_check_tag( "("  ), 1 } ||  0, 0 },
sub { ok eval { VCP::Utils::cvs::RCS_check_tag( "a b"  ), 1 } ||  0, 0 },

sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "a"  ), "a"   },
sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "ab" ), "ab"  },
sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "a1" ), "a1"  },
sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "a(" ), "a("  },
sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "a/" ), "a/"  },

sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "0"  ), "tag_0"    },
sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "("  ), "tag_("    },
sub { ok VCP::Utils::cvs::RCS_underscorify_tag( "a b"), "a_20_b"   },
sub { ok VCP::Utils::cvs::RCS_underscorify_tag( " a" ), "tag__20_a" },
) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
