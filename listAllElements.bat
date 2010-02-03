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
	OUT_FILENAME => 'testOutput.html',
	REF_DIRECTORY => 'D:\\clearcase_storage\\gmanciet_view\\PRIMA2\\ProjectSpecificDocs\\02_Requirements\\SyFRSCC',
};

my $BEFORE_REF = 'Liv_STR3.3.0_Maroc_12012010';
my $AFTER_REF = 'LATEST';

my $results = retrieve('test.db');
#my $latest = getDirectoryStructure(REF_DIRECTORY);
#my $labelled = getDirectoryStructure(REF_DIRECTORY, -label => 'Liv_STR3.3.0_Maroc_12012010');

INFO "Processing results. It can take some time.";
#my $results = compareLabels(REF_DIRECTORY, $labelled, $latest);
#store($results, 'test.db');

my @results;
foreach my $key (sort keys %$results) {
	DEBUG "Processing $key";
	my %document;
	$document{DOCUMENT} = $key;

	my @fields = @{$results->{$key}};
	$document{BEFORE_TEXT} = formatVersion($fields[0]);
	$document{AFTER_TEXT} = formatVersion($fields[1]);
	
	push @results, \%document;
}

unlink(OUT_FILENAME);
open (FILE, ">".OUT_FILENAME);
	
my $t = HTML::Template -> new( filename => "./listDocs.tmpl" );

$t->param(BEFORE_REF => $BEFORE_REF);
$t->param(AFTER_REF => $AFTER_REF);
$t->param(RESULTS => \@results);
my $tm = strftime "%d-%m-%Y à %H:%M:%S", gmtime;
$t->param(DATE => $tm);

print FILE $t->output;
close(FILE);

sub formatVersion {
	my ($element) = @_;
	
	return 'N/A' unless($element->{revision});
	return $element->{revision}."<br />(pas de gestion documentaire)" unless($element->{Version} or $element->{State});
	return $element->{Version} if ($element->{State} == 10);
	return "$element->{Version}<br />(State $element->{State})";
}

sub compareLabels {
	my ($refDirectory, $beforeList, $afterList) = @_;
	$refDirectory = quotemeta($refDirectory);
	
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
		
		$element =~ s/^$refDirectory\\(.*)/$1/;
		my @list = (\%beforeVersion, \%afterVersion);
		$results{$element} = \@list;
	}
	
	return \%results;
}

__END__
:endofperl
pause