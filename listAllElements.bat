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
use ClearcaseMgt qw(getDirectoryStructure getAttribute);
use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use Time::localtime;
use POSIX qw(strftime);
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.1 beta',
};

my $results = retrieve('test.db');
#my $latest = getDirectoryStructure('D:\\clearcase_storage\\gmanciet_view\\PRIMA2\\ProjectSpecificDocs\\02_Requirements\\SyFRSCC');
#my $labelled = getDirectoryStructure('D:\\clearcase_storage\\gmanciet_view\\PRIMA2\\ProjectSpecificDocs\\02_Requirements\\SyFRSCC', -label => 'Liv_STR3.3.0_Maroc_12012010');
#my $results = compareLabels($labelled, $latest);

#store($results, 'test.db');
#open FILE, ">result.txt";
#print FILE Dumper ;
#close FILE;

sub compareLabels {
	my ($beforeList, $afterList) = @_;
	
	my %elements;
	foreach my $element (keys %$beforeList, keys %$afterList) { $elements{$element}++ }

	my %results;
	foreach my $element (keys %elements) {
		my (%beforeVersion, %afterVersion);
		next if -d $element;
		
		if($beforeList->{$element}) {
			$beforeVersion{State} = getAttribute($element, "State", $beforeList->{$element});
			$beforeVersion{Version} = getAttribute($element, "Version", $beforeList->{$element});
			$beforeVersion{revision} = $beforeList->{$element};
		}
		
		if($afterList->{$element}) {
			$afterVersion{State} = getAttribute($element, "State", $afterList->{$element});
			$afterVersion{Version} = getAttribute($element, "Version", $afterList->{$element});
			$afterVersion{revision} = $afterList->{$element};
		}
		my @list = ($element, \%beforeVersion, \%afterVersion);
		$results{$element} = \@list;
	}
	
	return \%results;
}

__END__
:endofperl
pause