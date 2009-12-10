@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(lib);
use strict;
use warnings;
#use Common;
use Data::Dumper;

#my %Config = loadConfig("Clearquest-config.xml", ForceArray => qr/^filter$/); # Loading / preprocessing of the configuration file

my @list = readDirectory("./config-specs");
print Dumper @list;

sub readDirectory {
	my $dir = shift;
	
	opendir(DIR, $dir) || die "can't opendir $dir: $!";
	my @dots = grep { !/^(\.|\.\.)$/ } readdir(DIR);
    closedir DIR;
	return sort @dots;
}

sub changeConfigSpec {
	
}

__END__
:endofperl
pause