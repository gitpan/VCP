use ExtUtils::MakeMaker;

use strict ;
use vars qw( $VERSION ) ;

require 5.00503 ;

$VERSION = 0.091 ;

my @programs = qw( vcp ) ;

my @io_schemes = qw( revml cvs p4 ) ;
my %io_scheme_revmls = (
   (
      map {
	 my $fn = "t/test-$_-in-0.revml" ;
   ## Note the literal tabs here...
	 ( $fn => <<TOHERE ) ;
	\$(PERL)  "-I\$(INST_ARCHLIB)" "-I\$(INST_LIB)" "-I\$(PERL_ARCHLIB)" "-I\$(PERL_LIB)" \\
	bin/gentrevml --$_ --batch 0 > $fn
TOHERE
      } @io_schemes,
   ),
   (
      map {
	 my $fn = "t/test-$_-in-1.revml" ;
   ## Note the literal tabs here...
	 ( $fn => <<TOHERE ) ;
	\$(PERL)  "-I\$(INST_ARCHLIB)" "-I\$(INST_LIB)" "-I\$(PERL_ARCHLIB)" "-I\$(PERL_LIB)" \\
	bin/gentrevml --$_ --batch 1 > $fn
TOHERE
      } @io_schemes
   ),
   (
      map {
	 my $fn = "t/test-$_-in-1-bootstrap.revml" ;
   ## Note the literal tabs here...
	 ( $fn => <<TOHERE ) ;
	\$(PERL)  "-I\$(INST_ARCHLIB)" "-I\$(INST_LIB)" "-I\$(PERL_ARCHLIB)" "-I\$(PERL_LIB)" \\
	bin/gentrevml --$_ --batch 1 --bootstrap > $fn
TOHERE
      } @io_schemes
   ),
) ;

my $io_test_files = join( ' ', sort keys %io_scheme_revmls ) ;

WriteMakefile(
    'NAME'          => 'VCP',
    'VERSION'       => $VERSION,
    'EXE_FILES'     => [ map "bin/$_", @programs ],
    'PREREQ_PM'     => {
        'IPC::Run'         => 0,
	'MIME::Base64'     => 0,
	'Regexp::Shellish' => 0,
        'XML::ValidWriter'  => 0.36,
	'XML::Parser'      => 0,
	'Digest::MD5'      => 0,
    },
    'LIBS'          => [''],   # e.g., '-lm' 
    'DEFINE'        => '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'           => '',     # e.g., '-I/usr/include/other' 
#    'PM'	=> {'Spec.pm'	=> '$(INST_LIBDIR)/File/Spec.pm',
#    			'OS2.pm'	=> '$(INST_LIBDIR)/File/Spec/OS2.pm',
#    			'Win32.pm'	=> '$(INST_LIBDIR)/File/Spec/Win32.pm',
#    			'VMS.pm'	=> '$(INST_LIBDIR)/File/Spec/VMS.pm',
#   			'Unix.pm'	=> '$(INST_LIBDIR)/File/Spec/Unix.pm',
#    			}
    clean => { FILES => $io_test_files },
);

sub MY::libscan {
   package MY ;
   my $self = shift ;
   my ( $path ) = @_ ;
   return '' if /\.sw[a-z]$/ ;
   return '' unless length $self->SUPER::libscan( $path ) ;
   return $path ;
}


sub MY::postamble {
   package MY ;
   my $self = shift ;
   return join(
      '',
      "\npure_all :: $io_test_files\n",
      map(
         "\n$_ : bin/gentrevml\n$io_scheme_revmls{$_}",
	 sort keys %io_scheme_revmls
      )
   ) ;
}
