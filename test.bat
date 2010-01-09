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

############################################################################################
# 
############################################################################################
use Tk;
use Tk::JComboBox;
use Tk::Balloon;



##########################################
# Building graphical interface
##########################################
# Generic configuration
Tk::CmdLine::SetResources(  # set multiple resources
	[ 	'*Button*relief: groove',
		'*Text*relief: groove',
		'*Entry*relief: groove',
		'*Button*background : grey'
	]
);


my $mw = MainWindow->new(-title => "Interface to add new bugs");
$mw->withdraw; # disable immediate display
$mw->minsize(640,480);
my $balloon = $mw->Balloon();

my %completeList = (
      'Black' => { comment => '#00az00', data => 'test' },
      'Blue' => { comment => '#0000ff' },
      'Green' => { comment => '#008000' },
      'Purple' => { comment => '#8000ff' },
      'Red' => { comment => '#ff0000' },
      'Yellow' => { comment => '#ffff00' }
   );

   

my @selectedList;
my $searchActivated = 0;

my %item;

my $itemBox = $mw->Frame()->pack(-side => 'top', -fill => 'x');
$itemBox->Label(-text => 'Ma liste', -width => 15 )->pack(-side => 'left');
my $searchButton = $itemBox->Button(-text => 'Search', -command => [\&manageSearchBox])->pack( -side => 'right' );
my $listbox = $itemBox->JComboBox(-choices => \@selectedList, -textvariable => \$item{selection})->pack(-fill => 'x', -side => 'left', -expand => 1);
my $searchFrame = $itemBox->Frame();
$searchFrame->Label(-textvariable => \$item{searchText})->pack(-side => 'left');
$searchFrame->Entry(-validate => 'all', -textvariable => \$item{search}, -width => 15, -validatecommand => [\&search])->pack(-side => 'right');
@selectedList = sort keys %completeList;

INFO "displaying graphical interface";
$mw->Popup; # window appears screen-centered
MainLoop();

##############################################
# Graphical oriented functions
##############################################

sub manageSearchBox {
	my $searchListbox = shift;
	$searchActivated = ($searchActivated+1)%2;
	if($searchActivated) {
		DEBUG "Search activated";
		$searchButton->configure(-text => 'X');
		$searchFrame->pack(-fill => 'x', -side => 'right', -anchor => 'center');
		$balloon->attach($searchButton, -msg => 'Cancel search');
	}
	else {
		DEBUG "Search deactivated";
		$item{search} = '';
		$searchButton->configure(-text => 'Search');
		$searchFrame->packForget();
		$balloon->attach($searchButton, -msg => 'Perform a search on left list');
	}
}

sub search {	
	my $search = shift;
	DEBUG "Search request is : \"$search\"";
	my @tmpList = ();
	my @resultsText = ("Hereafter are results remainings:");
	my $old_selection = $item{selection};
	foreach my $item (keys %completeList) {
		next unless ($item =~ /$search/i or $completeList{$item}{comment} =~ /$search/i);
		push (@tmpList, $item);
		push (@resultsText, " => $item --- $completeList{$item}{comment}");
	}
	
	@selectedList = sort @tmpList;
	$item{selection} = $old_selection if $old_selection;
	$item{selection} = $selectedList[0] if scalar(@selectedList) == 1;

	$balloon->attach($searchFrame, -msg => join("\n", @resultsText));
	$listbox->configure(-state => scalar(@selectedList) ? 'normal' : 'disabled');
	$item{searchText} = (scalar(@selectedList) ? (scalar(@selectedList) == 1 ? "1 result" : scalar(@selectedList).' results' ) : 'No results');
	return 1;
}

__END__
:endofperl
pause