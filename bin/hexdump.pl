for (0..$#ARGV) {
    if ( $ARGV[$_] eq "-o" ) {
        my ( undef, $output_file ) = splice @ARGV, $_, 2;
        open STDOUT, ">$output_file" or die "$!: $output_file";
    }
}

for (@ARGV){
    open F, "<$_" or die "$!: $_";
    binmode F;
    $/ = undef;
    $_ = <F>;
    for ( split // ) {
        my $hex = sprintf "%02x", ord ;
        $_ =~ s/([^\040-\377])/ /;
        push @chars, $_;
        print $hex, " ";
        if ( ++$out_count > 16 ) {
            print " ", splice( @chars ), "\n";
            $out_count = 0;
        }
    }
}

print "   " x ( 17 - $out_count ), " ", @chars, "\n" if $out_count;

close STDOUT;

####
