@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(lib);
use strict;
use warnings;
use Common;
use Storable qw(store retrieve);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use ClearcaseMgt qw(checkoutElement isLatest setAttribute isPrivateElement checkinElement);

my %Config = loadConfig("config.xml", ForceArray => qr/_list$/); # Loading / preprocessing of the configuration file


my $srcDir = "./docs";

my $ONLINE_MODE = 0;

my $result;
my $finalDir = $Config{REP_FINAL};
my $destFile = $Config{SPEC_FINAL};
my $initialVersion = $Config{VERSION_INITIALE};
my $initialState = $Config{ETAT_INITIAL};

find(sub { 
INFO "Found match" and $result = $_ if /^$destFile.*\.doc$/; 
 }, $finalDir);
$destFile = $result if $result;

LOGDIE "Path ".$finalDir." doesn't exists" unless -d $finalDir;
my $locDstFile = $finalDir."\\".$destFile;
LOGDIE "Destination file $destFile doesn't exists" unless -f $locDstFile;
#LOGDIE "File is not configuration management" if isPrivateElement($locDstFile);
#LOGDIE "File is not latest revision." unless isLatest($locDstFile);

my @list = extract_list($srcDir);

setCCAttributes($locDstFile, $initialVersion, $initialState);

foreach my $version (@list) {
	my $file = $version;
	$version =~ s/^(.*)\.doc$/$1/i;
	INFO "Processing Version $version";
	my $srcFile = $srcDir.'\\'.$file;
	
	DEBUG "Checkout \"$locDstFile\"" and checkoutElement($locDstFile) or LOGDIE 'Checkout was not performed correctly';
	DEBUG "Delete \"$locDstFile\"" and unlink($locDstFile) or LOGDIE 'Removal was not performed correctly';
	DEBUG "Copy \"$srcFile\" in \"$locDstFile\"" and copy($srcFile, $locDstFile) or LOGDIE 'Copy was not performed correctly';
	DEBUG "Checkin \"$locDstFile\"" and checkinElement($locDstFile, "Mise en gestion de conf de la version $version.") or LOGDIE 'Checkin was not performed correctly';
	DEBUG "Checkout \"$locDstFile\" with attributes $version and 10" and setCCAttributes($locDstFile, $version, '10') or LOGDIE 'Attributes were not set correctly';
} 

# Extract list
sub extract_list {
    my $dir = shift;
	local *DIR;

	return unless -d $dir;
	opendir DIR, $dir or LOGDIE "opendir failed for \"$dir\" : $!";
	my @results ;
	for (readdir DIR) {
	        next if /^\.{1,2}$/;
			WARN "$_ has not correct syntax. It will be ignored" and next unless(/^[A-Z]\d\.doc$/);
	        push (@results , $_);
	}
	closedir DIR;
	return sort @results;
}

sub setCCAttributes {
	my $document = shift;
	my $version = shift;
	my $state = shift;
	
	my $result = setAttribute($document, 'Version',  "$version");
	my $result2 = setAttribute($document, 'State', "$state");
	return $result and $result2;
}


__END__
:endofperl
pause