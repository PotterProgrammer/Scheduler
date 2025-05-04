BEGIN {
    if(exists $ENV{PAR_TEMP}) {
		my $runningIn = $ENV{PWD};
		print "Running in $runningIn\n";
        my $dir = $ENV{PAR_TEMP};
		mkdir( "script");
        chdir "$runningIn/script";
##-->        my @substitutions = qw/Mojo Mojolicious email images lib public sms templates/;
##-->        my @substitutions = qw/images lib public templates/;
        my @substitutions = qw/images public templates email sms/;
        for(@substitutions){
            next if -l;
			unlink( "$runningIn/script/$_");
            system( qq(xcopy "$dir\\inc\\$_" "$runningIn\\script\\$_" /s/e/v/i/d/y) );
##-->                or die "Can't symlink $_ at $dir: $!";
        }
##-->        @substitutions = qw/email sms/; 
##-->        for(@substitutions){
##-->            next if -l;
##-->			unlink( "$_");
##-->##-->            symlink "$dir/inc/$_", "$_"
##-->            system( qq(xcopy  "$dir\\inc\\$_" "$_\\*" /s/e/v/i/d/y) );
##-->##-->                or die "Can't symlink $_ at $dir: $!";
##-->        }
        print "I'm at at $dir\n";
		system( "dir *");
         push @ARGV, qw(
            daemon -m production -l http://127.0.0.1:3000
        );
	}
}

1;
