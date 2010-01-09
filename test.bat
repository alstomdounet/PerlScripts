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

my %completeList2 = (
      'Black' => { comment => '#00az00', data => 'test' },
      'Blue' => { comment => '#0000ff' },
      'Green' => { comment => '#008000' },
      'Purple' => { comment => '#8000ff' },
      'Red' => { comment => '#ff0000' },
      'Yellow' => { comment => '#ffff00' }
   );
my %bugDescription;
my @mandatoryFields;
   
my $listComponents = addListBox($mw, 'Component', 'component', 'Optional', "Select the component affected.\nIf more components are affected, please make on CR per affected component.", \%completeList2);
my $listAnalyser = addListBox($mw, 'Analyst', 'analyst', 'Mandatory', "Determine who will analyse the issue.", \%completeList2);


INFO "displaying graphical interface";
$mw->Popup; # window appears screen-centered
MainLoop();

##############################################
# Graphical oriented functions
##############################################

sub addListBox {
	my $parentElement = shift;
	my $labelName = shift;
	my $CQ_Field = shift;
	my $necessityText = shift;
	my $labelDescription = shift;
	my $completeList = shift;

	my @list = sort keys %$completeList;
	my %item;

	$item{searchActivated} = 0;
	$item{selectedList} = \@list;
	$item{completeList} = $completeList;
	$item{mainFrame} = $mw->Frame()->pack(-side => 'top', -fill => 'x');
	$item{mainFrame}->Label(-text => $labelName, -width => 15 )->pack(-side => 'left');
	$item{searchButton} = $item{mainFrame}->Button(-text => 'Search', -command => sub { manageSearchBox(\%item) })->pack( -side => 'right' );
	$item{listbox} = $item{mainFrame}->JComboBox(-choices => $item{selectedList}, -textvariable => \$item{selection})->pack(-fill => 'x', -side => 'left', -expand => 1);
	$item{searchFrame} = $item{mainFrame}->Frame();
	$item{searchFrame}->Label(-textvariable => \$item{searchText})->pack(-side => 'left');
	$item{searchFrame}->Entry(-validate => 'all', -textvariable => \$item{search}, -width => 15, -validatecommand => sub { my $search = shift; search(\%item, $search); return 1; } )->pack(-side => 'right');

	#$item{listbox}->setSelected($CQ_Field) if $CQ_Field;
	$balloon->attach($item{listbox}, -msg => "<$necessityText> $labelDescription");
	push(@mandatoryFields, {Text => $labelName, CQ_Field => $CQ_Field});

	return %item;
}

sub manageSearchBox {
	my $searchListbox = shift;
	
	$searchListbox->{searchActivated} = ($searchListbox->{searchActivated}+1)%2;
	if($searchListbox->{searchActivated}) {
		DEBUG "Search activated";
		$searchListbox->{searchButton}->configure(-text => 'X');
		$searchListbox->{searchFrame}->pack(-fill => 'x', -side => 'right', -anchor => 'center');
		$balloon->attach($searchListbox->{searchButton}, -msg => 'Cancel search');
	}
	else {
		DEBUG "Search deactivated";
		$searchListbox->{search} = '';
		$searchListbox->{searchButton}->configure(-text => 'Search');
		$searchListbox->{searchFrame}->packForget();
		$balloon->attach($searchListbox->{searchButton}, -msg => 'Perform a search on left list');
	}
}

sub search {	
	my $searchListbox = shift;
	my $search = shift;
	
	DEBUG "Search request is : \"$search\"";
	my @tmpList;
	my %completeList = %{$searchListbox->{completeList}};
	my @resultsText = ("Hereafter are results remainings:");
	my $old_selection = $searchListbox->{selection};
	foreach my $item (keys %completeList) {
		next unless ($item =~ /$search/i or $completeList{$item}{comment} =~ /$search/i);
		push (@tmpList, $item);
		push (@resultsText, " => $item --- $completeList{$item}{comment}");
	}
	my $nbrOfResults = scalar(@tmpList);
	@{$searchListbox->{selectedList}} = sort @tmpList;
	$searchListbox->{selection} = $old_selection if $old_selection;
	$searchListbox->{selection} = $tmpList[0] if $nbrOfResults == 1;

	$balloon->attach($searchListbox->{searchFrame}, -msg => join("\n", @resultsText));
	$searchListbox->{listbox}->configure(-state => $nbrOfResults ? 'normal' : 'disabled');
	$searchListbox->{searchText} = ($nbrOfResults ? ($nbrOfResults == 1 ? "1 result" : $nbrOfResults.' results' ) : 'No results');
	return 1;
}

__END__
:endofperl
pause