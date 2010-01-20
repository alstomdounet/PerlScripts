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

use constant {
	VERSION => '0.1'
};

############################################################################################
# 
############################################################################################
INFO "Running program version V.".VERSION;
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


##########################################
# Building graphical interface
##########################################
# Generic configuration
Tk::CmdLine::SetResources(  # set multiple resources
	[ 	'*Button*relief: groove',
		'*Text*relief: groove',
		'*ROText*relief: groove',
		'*Entry*relief: groove',
		'*Button*background : grey'
	]
);

DEBUG "Building graphical interface";

my $mw = MainWindow->new(-title => "Interface to distribute bugs");
$mw->withdraw; # disable immediate display
$mw->minsize(640,480);

# SyFRSCC, Component, Type, ?headline?, CCB comment, Description / context, Proposed changes, Analysis cost+System+Hardware+Software+Validation+ Inmpacted items + Analyst + Work in progress
#addSearchableListBox($mw, 'Selected CR', 'parent_id', undef, undef,\@listOfBugs);
my $CrToProcess = 'atvcm00087110';
my $searchFrame = $mw->Frame() -> pack(-side => 'top', -fill => 'x');
$searchFrame->Label(-text => "ID à traiter", -width => 15 )->pack( -side => 'left' );
$searchFrame->Button(-text => "Ouvrir", -width => 15, -command => sub { loadCR($CrToProcess); } )->pack( -side => 'right' );
$searchFrame->Entry(-textvariable => \$CrToProcess, -width => 15 )->pack( -side => 'left', -fill => 'x', -expand => 1 );

# Building buttons
my $bottomPanel = $mw->Frame()->pack(-side => 'bottom', -fill => 'x');
$bottomPanel->Button(-text => 'Cancel', ,-font => 'arial 9', -command => [ \&cancel, $mw], -height => 2, -width => 10) -> pack(-side => 'left');
my $buttonValidate = $bottomPanel->Button(-text => "Validate",-font => 'arial 9', -command => sub { validateChanges($processedCR); }, -height => 2, -width => 10, -state => 'disabled') -> pack(-side => 'right');

center($mw);
center($mw);
MainLoop();

############################################################################################
# 
############################################################################################
sub loadCR {
	my $id = shift;
	$buttonValidate->configure(-state => 'disabled');
	DEBUG "Destroying content frame" and $contentFrame->destroy() if $contentFrame;
	my %fields = retrieveBug($id);
	$mw->messageBox(-title => "CR not found", -message => "$id was not found in Clearquest database. \nPlease check CR number, or eventually look into logfile.", -type => 'ok', -icon => 'error') and return unless %fields;
	$processedCR = \%fields;
	
	$contentFrame = $mw->Frame()->pack( -fill=>'both', -expand => 1);

	my $parentFrame = $contentFrame->Frame()->pack( -fill=>'x');
	my $titleFrame = $parentFrame->Frame() -> pack(-side => 'top', -fill => 'x');
	$titleFrame->Label(-text => "Titre", -width => 15 )->pack( -side => 'left' );
	$titleFrame->Label(-text => $processedCR->{fields}{headline}, -font => 'arial 9 bold')->pack( -side => 'left', -fill => 'x', -expand => 1 );
	
	addDescriptionField($parentFrame, 'Description', \$processedCR->{fields}{description}, -readonly => 1, -height => 3);
	addDescriptionField($parentFrame, 'CCB comment', \$processedCR->{fields}{CCB_comment}, -readonly => 1, -height => 1);
	
	my $notebook = $contentFrame->NoteBook()->pack( -fill=>'both', -expand=>1 );
	
	foreach my $subID (sort keys %{$processedCR->{childs}}) {
		DEBUG "Processing child $subID";
		buildTab($notebook,$subID,$processedCR->{childs}{$subID});
	}
	$mw->geometry("640x480");
	$buttonValidate->configure(-state => 'normal');
}

sub buildTab {
	my $notebook = shift;
	my $tabName = shift;
	my $content = shift;
	
	$content->{tabName} = $tabName;
	
	my $tab1 = $notebook->add($tabName, -label => $tabName);

	my (@mandatoryFields, @listSubSystems);
	$content->{tab} = $tab1;
	my @test;
	foreach my $item (@{$CqFieldsDesc{sub_system}{shortDesc}}) {
		push (@test, { -name => $item, -value => $CqFieldsDesc{sub_system}{equivTable}{$item} });
		#push (@test, { -name => $item, -value => $item.$item });
	}
	$content->{listSubsystems} = addListBox($tab1, 'Subsystem', \@test, \$content->{fields}{sub_system});
	my @list;
	$content->{dynamicComponentList} = \@list;

	my $backup = $content->{fields}{component};
	$content->{listComponents} = addListBox($tab1, 'Component', $content->{dynamicComponentList}, \$content->{fields}{component});

	if ($content->{fields}{sub_system}) {
		updateComponents($content->{fields}{sub_system}, $content->{listComponents}, $content->{dynamicComponentList});
		${$content->{listComponents}->{selection}} = $backup;
	}
	$content->{listAnalyser} = addListBox($tab1, 'Analyst', $CqFieldsDesc{analyst}{shortDesc}, \$content->{fields}{analyst}, -searchable => 0);
	$content->{listTypes} = addListBox($tab1, 'Type', $CqFieldsDesc{submitter_CR_type}{shortDesc}, \$content->{fields}{submitter_CR_type});
	$content->{TextImpactedItems} = addDescriptionField($tab1, 'Impacted items', \$content->{fields}{impacted_items}, -height => 1);
	$content->{TextProposedChanges} = addDescriptionField($tab1, 'Proposed changes', \$content->{fields}{proposed_change});
	
	$content->{listSubsystems}->{listbox}->configure(-browsecmd => sub {updateComponents($content->{fields}{sub_system}, $content->{listComponents}, $content->{dynamicComponentList});});
}

sub updateComponents {	
	DEBUG "Request to update listboxes";
	my ($value_subsystem, $listbox, $listRef) = @_;
	
	
	if($value_subsystem) {
		my %rhash = reverse %{$CqFieldsDesc{sub_system}{equivTable}};
		my $key = $rhash{$value_subsystem};

		if($CqFieldsDesc{component}{equivTable}{$key}) {
			my $oldValue = $listbox->{listbox}->getItemNameAt($listbox->{listbox}->getSelectedIndex());
			DEBUG "Equivalence table found with key eq \"$key\"";
			my @keys = sort keys %{$CqFieldsDesc{component}{equivTable}{$key}};
			my @list = genTableByEquivTable(\@keys, $CqFieldsDesc{component}{equivTable}{$key});
			@$listRef = @list;
			
			$listbox->{listbox}->setSelected($oldValue, -type => 'name');
			return;
		}
	}
	
	ERROR "No equivalence was found for subsystem \"$value_subsystem\"";
	@$listRef = ();
}

sub genTableByEquivTable {
	my ($quickList, $equivTable) = @_;
	my @list;
	foreach my $item (@$quickList) {
		push (@list, { -name => $item, -value => $equivTable->{$item} });
	}
	return @list;
}

sub retrieveBug {
	my $bugID = shift;
	my %bug;
	use ClearquestMgt qw(connectCQ disconnectCQ getChangeRequestFields getEntity editEntity getEntityFields getChilds getAvailableActions getFieldsRequiredness cancelAction); 

	my $idDatabase = $bugID.'.db';
	if (-r $idDatabase) {
		WARN "Using Database unstead of direct copy";
		my $bug = retrieve($idDatabase);
		return %$bug;
	}
	
	INFO "Connecting to Clearquest";
	connectCQ ('gmanciet', 'jsne1983aS!', 'atvcm');
	INFO "Retrieving needed informations";
	my $entity = getEntity('ChangeRequest',$bugID);
	my %fields = getEntityFields($entity);
	$bug{fields} = \%fields;
	foreach my $childID (getChilds($entity)) {
		DEBUG "Getting child properties ($childID)";
		my %child;
		my $childEntity = getEntity('ChangeRequest',$childID);
		my %childFields = getEntityFields($childEntity);
		$child{fields} = \%childFields;
		
		foreach my $action (getAvailableActions($entity)) {
			DEBUG "Skipped action $action" and next if $action eq 'Import' or $action eq 'Clone';
			DEBUG "Getting required fields for action \"$action\"";
			editEntity($entity, $action);
			my %fieldsRequired = getFieldsRequiredness($entity);
			$child{availableActions}{$action} = \%fieldsRequired;
			cancelAction($entity);
		}
		$bug{childs}{$childID} = \%child;
	}
	store(\%bug, $idDatabase) unless -r $idDatabase;
	return %bug;
}

sub validateChanges {
	my ($processedCR) = @_;
	
	my $response = $mw->messageBox(-title => "Confirmation requested", -message => "Do you really want perform all these modifications?", -type => 'yesno', -icon => 'question');
	
	DEBUG "User has answered \"$response\" to cancellation question";
	return unless $response eq "Yes";
	
	my @selectedFields = qw(sub_system component impacted_items analyst submitter_CR_type proposed_change);
	foreach my $id (sort keys %{$processedCR->{childs}}) {
		my $CR = $processedCR->{childs}->{$id}->{fields};
		
		my %selectedFields;
		foreach my $field (@selectedFields) {
			$selectedFields{$field} = $CR->{$field};
		}
		
		open FILE, ">$id-out.txt";
		print FILE Dumper \%selectedFields;
		close FILE;
	}

}

exit;

__END__
:endofperl
pause