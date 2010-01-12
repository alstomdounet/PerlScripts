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
my $path = 'D:\\clearcase_storage\\gmanciet_view\\PRIMA2\\ProjectSpecificDocs\\02_Requirements\\SyFRSCC\\TFE\\TRF';
my $destFile = 'BAD0002243278 SyFRScc';
my $initialVersion = 'A0';
my $initialState = '10';
my $ONLINE_MODE = 0;

my $result;
find(sub { 
INFO "Found match" and $result = $_ if /^$destFile.*\.doc$/; 
 }, $path);
$destFile = $result if $result;

LOGDIE "Path $path doesn't exists" unless -d $path;
LOGDIE "Destination file $destFile doesn't exists" unless -f $path."\\".$destFile;
#LOGDIE "File is not configuration management" if isPrivateElement($path."\\".$destFile);
#LOGDIE "File is not latest revision." unless isLatest($path."\\".$destFile);

my @list = extract_list($srcDir);

setCCAttributes($path."\\".$destFile, $initialVersion, $initialState) if $ONLINE_MODE;

foreach my $version (@list) {
	my $file = $version;
	$version =~ s/^(.*)\.doc$/$1/i;
	INFO "Processing Version $version";
	checkout($path."\\".$destFile) or LOGDIE 'Checkout was not performed correctly';
	unlink($path."\\".$destFile) or LOGDIE 'Removal was not performed correctly';
	copy($srcDir.''.$file, $path."\\".$destFile) or LOGDIE 'Copy was not performed correctly';
	checkin($path."\\".$destFile) or LOGDIE 'Checkin was not performed correctly';
	setCCAttributes($path."\\".$destFile, $version, 10) or LOGDIE 'Attributes were not set correctly';
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
	
	my $result = setAttribute($document, 'Version',  $version);
	return $result and setAttribute($document, 'State', $state);
}


__END__
:endofperl
pause