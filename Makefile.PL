use ExtUtils::MakeMaker;

use strict ;
use File::Find;

require 5.00503 ;

my @programs = qw( vcp ) ;

my $ui_machines;
my @prereqs;
my $have_stateml = eval "require StateML";

##
## Search ui_machines/ for StatML machines so we can build the rule
## for "make ui".  The directory "ui_machines" does not ship with
## the distribution, so this rule will not apply to the distribution
## and users need not have StateML installed.
##
if ( $have_stateml && -e "ui_machines" ) {
    my @ui_machines;
    find(
       sub {
           push @ui_machines, $File::Find::name if /\.stml\z/i;
       },
       "ui_machines"
    );

    @ui_machines = grep !/revml\.stml/, @ui_machines;
    warn "Ignoring revml UI machines to keep the UI simple and avoid XML and StateML build prerequisites (XML is required for testing, however).\n";

    @prereqs = ( StateML => 0 );

    ## Sort by length to get the master machine first, then the others
    ## Sort by name just to get things in a repeatable order.
    $ui_machines = join " ",
        sort {
            length $a <=> length $b || $a cmp $b
        } @ui_machines;
}


## Identify help files so VCP::Help can be built
if ( -e "lib/VCP/Help.pm" ) {
   ## This is mainly so that nmake lib/VCP/Help.pm will remake it.
   unlink "lib/VCP/Help.pm" or warn "$!:lib/VCP/Help.pm";
}

my @help_files = qw( bin/vcp );
find(
    sub {
        next unless $File::Find::name =~ /source|dest|filter/i;
        next unless $File::Find::name =~ /\.(pm|pod)\z/i;
        next unless -f;
        push @help_files, $File::Find::name;
    },
    "lib/VCP",
);

## Sort and Give .pod files precedence
{
    my %seen;
    @help_files = reverse
        grep
            !$seen{ lc( (m{(.*)\.})[0] ) }++,  ## Select first .pm or .pod seen
            reverse @help_files;  ## .pod sorts after .pm, so reverse the sort
}

my $help_files = join " ", @help_files;

# Build a hash of the makefile rules we'll need to build t/test-*.revml
my @io_schemes = qw( revml cvs p4 vss ) ;
#warn "ONLY BUILDING VSS!!!";
#@io_schemes = qw( vss ) ;
my %io_scheme_revmls = (

   (  # batch 0
      map {
	 my $fn = "t/test-$_-in-0.revml" ;
         ## Note the literal tabs here...
	 ( $fn => <<TOHERE ) ;
	\$(PERL)  "-I\$(INST_ARCHLIB)" "-I\$(INST_LIB)" "-I\$(PERL_ARCHLIB)" "-I\$(PERL_LIB)" \\
	bin/gentrevml --$_ --batch 0 > $fn
TOHERE
      } @io_schemes,
   ),

   ( # batch 1 (incremental)
      map {
	 my $fn = "t/test-$_-in-1.revml" ;
         ## Note the literal tabs here...
	 ( $fn => <<TOHERE ) ;
	\$(PERL)  "-I\$(INST_ARCHLIB)" "-I\$(INST_LIB)" "-I\$(PERL_ARCHLIB)" "-I\$(PERL_LIB)" \\
	bin/gentrevml --$_ --batch 1 > $fn
TOHERE
      } @io_schemes
   ),

   ( # batch 1, --bootstrap
      map {
	 my $fn = "t/test-$_-in-1-bootstrap.revml" ;
         ## Note the literal tabs here...
	 ( $fn => <<TOHERE ) ;
	\$(PERL)  "-I\$(INST_ARCHLIB)" "-I\$(INST_LIB)" "-I\$(PERL_ARCHLIB)" "-I\$(PERL_LIB)" \\
	bin/gentrevml --$_ --batch 1 --bootstrap > $fn
TOHERE
      } @io_schemes
   ),

   ( # batch 0, --no-big-files so some tests can run faster / be less verbose on failure
      map {
	 my $fn = "t/test-$_-in-0-no-big-files.revml" ;
         ## Note the literal tabs here...
	 ( $fn => <<TOHERE ) ;
	\$(PERL)  "-I\$(INST_ARCHLIB)" "-I\$(INST_LIB)" "-I\$(PERL_ARCHLIB)" "-I\$(PERL_LIB)" \\
	bin/gentrevml --$_ --batch 0 --no-big-files > $fn
TOHERE
      } @io_schemes
   ),
) ;

my $io_test_files = join( ' ', sort keys %io_scheme_revmls ) ;

## Create this so that libscan() will find it.
open F, ">lib/VCP/Help.pm" or warn "$!:lib/VCP/Help.pm";
close F;

WriteMakefile(
    'NAME'          => 'VCP',
    'VERSION_FROM'  => "lib/VCP.pm",
    'EXE_FILES'     => [ map "bin/$_", @programs ],
    'PREREQ_PM'     => {
	'Digest::MD5'      => 0,
	'File::Temp'       => 0,
	'MIME::Base64'     => 0,
	'Regexp::Shellish' => 0.93,
	'Text::Diff'       => 0,
        'XML::ValidWriter' => 0.38,
	'XML::Parser'      => 0,
        ## Below this line are for development only.  Above are for VCP features.
        'IPC::Run3'        => 0,
        'Pod::Links'       => 0,  # In PodToHtml-xxx.tar.gz
        'Pod::Text'        => 0,
        'Pod::HTML_Elements'  => 0,
        'Pod::Select'         => 0,
        'Pod::Usage'          => 0,
        'HTML::Element'       => 0,
        @prereqs,
    },
    'LIBS'          => [''],   # e.g., '-lm' 
    'DEFINE'        => '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'           => '',     # e.g., '-I/usr/include/other' 
    clean => { FILES => $io_test_files },
);

if ( -e "lib/VCP/Help.pm" ) {
   ## This so that nmake lib/VCP/Help.pm will remake it.
   unlink "lib/VCP/Help.pm" or warn "$!:lib/VCP/Help.pm";
}

sub MY::libscan {
   package MY ;
   my $self = shift ;
   my ( $path ) = @_ ;
   return '' if /.*\.log$/ ;
   return '' if /\.(bak|sw[a-z])$/ ;
   return '' if /~/ ;
   return $self->SUPER::libscan( $path ) ;
}


sub MY::postamble {
   package MY ;
   my $self = shift ;
   return join(
      "",
      "\npure_all :: $io_test_files\n",
      map(
         "\n$_ : bin/gentrevml\n$io_scheme_revmls{$_}",
	 sort keys %io_scheme_revmls
      ),
      "\n\n",
      "clean_tmp :\n\trm -rf /tmp/vcp*\n\n",
      "test_all_p4_versions :\n\t./test_all_p4_versions.sh\n\n",
      defined $ui_machines
         ? (
            "lib/VCP/UIMachines.pm : ui_machines/vcp_ui.tt2 $ui_machines\n",
               "\tstml --define package=VCP::UIMachines --template=ui_machines/vcp_ui.tt2 $ui_machines lib/VCP/UIMachines.pm\n",
               "\t\$(PERL) -Ilib -cw lib/VCP/UIMachines.pm\n",
               "\n",
            "ui-with-handlers.png : $ui_machines\n",
               "\tstml --show-handlers $ui_machines ui.png\n",
               "\n",
            "ui-with-handlers.ps : $ui_machines\n",
               "\tstml --show-handlers $ui_machines ui.ps\n",
               "\n",
            "ui.png : $ui_machines\n",
               "\tstml $ui_machines ui.png\n",
               "\n",
            "ui.ps : $ui_machines\n",
               "\tstml $ui_machines ui.ps\n",
               "\n",
            "ui : lib/VCP/UIMachines.pm\n\n",
            "ui_all : ui ui.png ui.ps\n\n",
            "pure_all :: ui\n\n",
         )
         : (),
      "lib/VCP/Help.pm: bin/genhelp $help_files\n",
      "\t\$(PERL) bin/genhelp $help_files\n\n",
      "vcp_html/index.html: bin/genhtml $help_files\n",
      "\t\$(PERL) bin/genhtml $help_files\n\n",
      "\npure_all :: lib/VCP/Help.pm\n",
   ) ;
}
