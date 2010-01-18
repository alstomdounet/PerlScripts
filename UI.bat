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
use Tk::NoteBook;
use Data::Dumper;
use GraphicalCommon;

############################################################################################
# 
############################################################################################
use Tk;
use Tk::JComboBox;
use Tk::Balloon;
use Tk::Pane;

############################################################################################
# 
############################################################################################
my %bugDescription;
my %CqFieldsDesc;
my $syncNeeded = 0;
my $CqDatabase = 'ClearquestImage.db';
my $bugsDatabase = 'bugsDatabase.db';
my (@listSubSystems, @mandatoryFields);


if (-r $CqDatabase) {
	my $storedData = retrieve($CqDatabase);
	%CqFieldsDesc = %$storedData;
}
else { $syncNeeded = 1; }

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

DEBUG "Building graphical interface";

my $mw = MainWindow->new(-title => "Interface to distribute bugs");
$mw->withdraw; # disable immediate display
$mw->minsize(640,480);

my $lastSelectedSubsystem = '';


# SyFRSCC, Component, Type, ?headline?, CCB comment, Description / context, Proposed changes, Analysis cost+System+Hardware+Software+Validation+ Inmpacted items + Analyst + Work in progress

my $parentFrame = $mw->Frame()->pack();

my $notebook = $mw->NoteBook()->pack( -fill=>'both', -expand=>1 );

my %tab;
$tab{ID} = "atvcm000122211";
buildTab($notebook,\%tab);

# Building buttons
my $bottomPanel = $mw->Frame()->pack(-side => 'bottom', -fill => 'x');
$bottomPanel->Button(-text => 'Cancel', ,-font => 'arial 9', -command => [ \&cancel, $mw], -height => 2, -width => 10) -> pack(-side => 'left');
my $buttonSwitch = $bottomPanel->Button(-text => "Validate",-font => 'arial 9', -command => [ \&switchActions], -height => 2, -width => 10) -> pack(-side => 'right');


$mw->Popup; # window appears screen-centered
MainLoop();

############################################################################################
# 
############################################################################################
sub buildTab {
	my $notebook = shift;
	my $content = shift;
	
	my $tab1 = $notebook->add($content->{ID}, -label => $content->{ID});

	$content{CRValues} = ;
	$content{tab} = $tab1;
	$content{listSubsystems} = addListBox($tab1, 'Subsystem', 'sub_system', 'Mandatory', 'Enter hereafter the subsystem',$CqFieldsDesc{sub_system}{shortDesc});
	$content{listComponents} = addSearchableListBox($tab1, 'Component', 'component', 'Mandatory', "Select the component affected.\nIf more components are affected, please make on CR per affected component.");
	$content{listAnalyser} = addSearchableListBox($tab1, 'Analyst', 'analyst', 'Mandatory', "Determine who will analyse the issue.", $CqFieldsDesc{analyst}{shortDesc});
	$content{listTypes} = addListBox($tab1, 'Type', 'submitter_CR_type', 'Mandatory', "Type of modification:\n - defect for non-compliance of a requirement (specification, etc.)\n - enhancement is for various improvements (functionality, reliability, speed, etc.)", $CqFieldsDesc{submitter_CR_type}{shortDesc});
	$content{TextProposedChanges} = addDescriptionField($tab1, 'Proposed changes', 'proposed_change','Mandatory');
}

exit;

__END__
:endofperl
pause