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
use ClearcaseMgt qw(addToSource checkoutElement isCheckedoutElement isPrivateElement uncheckoutElement checkinElement);
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
my $comment = $ARGV[2];
LOGDIE "Program needs three argument. first is operation among \"-rec_add\", \"-rec_ci\", \"-rec_co\" followed by a valid directory and finally a good comment." unless $currentDirectory and $currentOperation and $comment;

LOGDIE "Argument #1 has to be a valid operation among \"-rec_add\", \"-rec_ci\", \"-rec_co\", and you have entered \"$currentOperation\"" unless $currentOperation eq OPERATION_RECURSIVE_CHECKIN or $currentOperation eq OPERATION_RECURSIVE_CHECKOUT or $currentOperation eq OPERATION_RECURSIVE_ADD;
LOGDIE "Argument #2 has to be an existing and valid directory. Argument is actually \"$currentDirectory\"" unless -e $currentDirectory and -r $currentDirectory;
LOGDIE "Argument #3 has to be a comment. Argument is actually \"$comment\"" unless $comment;

chdir($currentDirectory);
chdir("..");
DEBUG "Root directory needs to be checked out." and checkoutElement(".",$comment) unless isCheckedoutElement(".");
chdir($currentDirectory);
conditionalAddToSource($currentDirectory, $comment);

read_directory($currentDirectory);

sub read_directory {
	my ($directory) = @_;
	
	chdir($directory);
	my $currentDirectory = cwd();
	DEBUG "Opening directory \"$currentDirectory\"";
	opendir(IMD, ".") || LOGDIE("Cannot open current directory");
	LOGDIE "Root directory \"$currentDirectory\" is not in SCM" if isPrivateElement(".");
	DEBUG "Root directory needs to be checked out." and checkoutElement(".",$comment) unless isCheckedoutElement(".");
	
	my @files = sort readdir(IMD);
	closedir(IMD);

	foreach my $element (@files) {
		next if $element =~/^\.{1,2}$/;
		
		conditionalAddToSource($element, $comment);
		
		if(-d $element) {
			read_directory($element);
		}
	} 
	chdir("..");
 }
 
 sub conditionalAddToSource {
	my ($element, $comment) = @_;
 
	if (isPrivateElement($element)) {
		DEBUG "File \"$element\" needs to be added";
		if(addToSource($element, $comment)) {
			DEBUG "Element \"$element\" was added to source control";
		}
		else {
			ERROR "Element \"$element\" had a problem";
		}
	}
 }

 exit;


__END__
:waitDueToErrors
pause
:finishedCorrectly