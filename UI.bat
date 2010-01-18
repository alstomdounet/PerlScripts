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
WARN "Missing dynamic retrieval of bugs";
my @listOfBugs = qw(atvcm000125654 atvcm000125644 atvcm000125694);
my %CqFieldsDesc;
my $CqDatabase = 'ClearquestImage.db';
my $bugsDatabase = 'bugsDatabase.db';
if (-r $CqDatabase) {
	my $storedData = retrieve($CqDatabase);
	%CqFieldsDesc = %$storedData;
}
else { LOGDIE "Not valid database"; }
my $processedCR;
my $contentFrame;


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
#my %bugDescription;


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

# SyFRSCC, Component, Type, ?headline?, CCB comment, Description / context, Proposed changes, Analysis cost+System+Hardware+Software+Validation+ Inmpacted items + Analyst + Work in progress
addSearchableListBox($mw, 'Selected CR', 'parent_id', undef, undef,\@listOfBugs);

# Building buttons
my $bottomPanel = $mw->Frame()->pack(-side => 'bottom', -fill => 'x');
$bottomPanel->Button(-text => 'Cancel', ,-font => 'arial 9', -command => [ \&cancel, $mw], -height => 2, -width => 10) -> pack(-side => 'left');
my $buttonSwitch = $bottomPanel->Button(-text => "Validate",-font => 'arial 9', -command => [ \&switchActions], -height => 2, -width => 10) -> pack(-side => 'right');

loadCR('testID');

$mw->Popup; # window appears screen-centered
MainLoop();

############################################################################################
# 
############################################################################################
sub loadCR {
	my $id = shift;
	use Tk::ROText;
	
	$processedCR = undef;
	
	use Fields;
	
	DEBUG "Destroying content frame" and $contentFrame->destroy() if $contentFrame;
	
	$contentFrame = $mw->Frame()->pack( -fill=>'both', -expand => 1);

	my $parentFrame = $contentFrame->Frame()->pack( -fill=>'x');
	my $titleFrame = $parentFrame->Frame() -> pack(-side => 'top', -fill => 'x');
	$titleFrame->Label(-text => "Titre", -width => 15 )->pack( -side => 'left' );
	$titleFrame->Label(-text => "Ceci est mon titre", -width => 15 )->pack( -side => 'left' );
	
	my $description = $parentFrame->Frame() -> pack(-side => 'top', -fill => 'x', -expand => 1);
	$description->Label(-text => "Description", -width => 15 )->pack( -side => 'left' );
	my $text = $description->Scrolled("ROText", -scrollbars => 'osoe', -height => 5 ) -> pack( -side => 'top', -fill => 'x');
	$text->Contents("Ceci est la description\n\n\ndsdsds\nn\nddsdsds\n\ndssdsdqsdzaemcmllcds");
	
	my $notebook = $contentFrame->NoteBook()->pack( -fill=>'both', -expand=>1 );
	
	WARN "Loading sub-CR";
	my @subCR = qw(atvcm00087450 atvcm00087451 atvcm00087452);
	
	foreach my $subID (@subCR) {
		$processedCR->{subCR}->{$subID};
		buildTab($notebook,$subID,$processedCR->{subCR}->{$subID});
	}
}

sub buildTab {
	my $notebook = shift;
	my $tabName = shift;
	my $content = shift;
	
	$content->{tabName} = $tabName;
	
	my $tab1 = $notebook->add($tabName, -label => $tabName);

	my (@mandatoryFields, @listSubSystems);
	$content->{tab} = $tab1;
	$content->{CRFields} = undef;
	$content->{listSubsystems} = addListBox($tab1, 'Subsystem', $content->{CRFields}->{'sub_system'}, 'Mandatory', 'Enter hereafter the subsystem',$CqFieldsDesc{sub_system}{shortDesc});
	$content->{listComponents} = addSearchableListBox($tab1, 'Component', $content->{CRFields}->{'component'}, 'Mandatory', "Select the component affected.\nIf more components are affected, please make on CR per affected component.");
	$content->{listAnalyser} = addSearchableListBox($tab1, 'Analyst', $content->{CRFields}->{'analyst'}, 'Mandatory', "Determine who will analyse the issue.", $CqFieldsDesc{analyst}{shortDesc});
	$content->{listTypes} = addListBox($tab1, 'Type', $content->{CRFields}->{'submitter_CR_type'}, 'Mandatory', "Type of modification:\n - defect for non-compliance of a requirement (specification, etc.)\n - enhancement is for various improvements (functionality, reliability, speed, etc.)", $CqFieldsDesc{submitter_CR_type}{shortDesc});
	$content->{TextProposedChanges} = addDescriptionField($tab1, 'Proposed changes', $content->{CRFields}->{'proposed_change'},'Mandatory');
}

exit;

__END__
:endofperl
pause