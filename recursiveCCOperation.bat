@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
if ERRORLEVEL 1001 goto finishedCorrectly
goto waitDueToErrors
@rem ';

BEGIN {
	$0=~/^(.+[\\\/])[^\\\/]+[\\\/]*$/;
	my $physicalDir= $1 || "./";
	chdir($physicalDir);
}
use lib qw(lib);
use strict;
use warnings;
use Common;
use GraphicalCommon;
use ClearcaseMgt qw(getLabelListVOB setLabel renameElement checkoutElement getAttribute setAttribute isCheckedoutElement isPrivateElement uncheckoutElement checkinElement isLatest);
use Data::Dumper;
use File::Basename;
use File::Copy;
use Cwd;
use Win32 qw(CSIDL_DESKTOPDIRECTORY);

use constant PROGRAM_VERSION => '0.1';

use constant {
	OPERATION_RECURSIVE_CHECKIN => '-rec_ci',
	OPERATION_RECURSIVE_CHECKOUT => '-rec_co',
	OPERATION_RECURSIVE_ADD => '-rec_add',
};



INFO "Starting program (".PROGRAM_VERSION.")";
#my %config = %{loadLocalConfig("config.xml", undef, ForceArray => qr/^labelName$/)}; # Loading / preprocessing of the configuration file

my $currentOperation = $ARGV[0];
my $currentDirectory = $ARGV[1];
LOGDIE "Program needs two argument. first is operation among \"-rec_add\", \"-rec_ci\", \"-rec_co\" followed by a valid directory" unless $currentDirectory and $currentOperation;

LOGDIE "Argument has to be a valid operation among \"-rec_add\", \"-rec_ci\", \"-rec_co\", and you have entered \"$currentOperation\"" unless $currentOperation eq OPERATION_RECURSIVE_CHECKIN or $currentOperation eq OPERATION_RECURSIVE_CHECKOUT or $currentOperation eq OPERATION_RECURSIVE_ADD;


LOGDIE "Argument used has to be an existing and valid directory. Argument is actually \"$currentDirectory\"" unless -e $currentDirectory and -r $currentDirectory;

read_directory($currentDirectory);

sub read_directory {
	my ($directory) = @_;
	
	my $currentDirectory = cwd();
	DEBUG "Opening directory \"$currentDirectory\"";
	opendir(IMD, $directory) || LOGDIE("Cannot open directory \"$directory\"");
	LOGDIE "Root directory \"$currentDirectory\" is not in SCM" if isPrivateElement($directory);
	
	my @files = sort readdir(IMD);
	closedir(IMD);
	chdir($directory);
	foreach my $file (@files) {
		next if $file =~/^\.{1,2}$/;
		if(-d $file) {
			read_directory($file);
		}
		else {
			DEBUG "FILE ".$file;
		}
	} 
	chdir("..");
 }

 exit;


__END__
:waitDueToErrors
pause
:finishedCorrectly