@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
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
use Data::Dumper;
use ClearquestMgt qw(connectCQ cancelAction editEntity makeQuery disconnectCQ getChangeRequestFields getEntity getDuplicatesAsString getAvailableActions getEntityFields getChilds getFieldsRequiredness changeFields makeChanges);
use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use Time::localtime;
use POSIX qw(strftime);
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.2 beta',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";

my %Config = loadLocalConfig("Scheduledconfig.xml", ForceArray => qr/^(?:table)|(?:node)$/); # Loading / preprocessing of the configuration file

INFO "Connecting to Clearquest";
connectCQ('gmanciet', '', 'atvcm');

my $entity = getEntity('ChangeRequest', 'atvcm00087861');
my $scheduled_version = getEntityFields($entity, -Field => 'scheduled_version');

my @fields = ('id', 'sub_system.name', 'State', 'scheduled_version', 'realised_version', 'substate');
my @results = makeQuery('ChangeRequest', \@fields, $Config{filtering});

open FILE, ">results.txt";
INFO "Found ".scalar(@results)." results";
foreach my $bugID (@results) {
	print FILE "$bugID->{id};".$bugID->{'sub_system.name'}.";$bugID->{state};$bugID->{substate};$bugID->{scheduled_version};$bugID->{realised_version}\n";
}
close FILE;

foreach my $bug (@results) {
	my $bugID = $bug->{id};
	INFO "Processing CR \"$bugID\"";

	my $entity = getEntity('ChangeRequest',$bugID);
	editEntity($entity, 'Rectify');
	
	my %fields;
	$fields{'scheduled_version'} = $scheduled_version;
	my $result = changeFields($entity, -Fields => \%fields);
	if($result) {
		$result = makeChanges($entity);
		ERROR "Validation / commit has failed on child \"$bugID\"."  and next unless $result;
		INFO "Modifications of child CR \"$bugID\" done correctly.";
	}
	else {
		ERROR "Modifications of fields of child \"$bugID\" has not been performed correctly.";
		cancelAction($entity);
	}
}

__END__
:endofperl
pause