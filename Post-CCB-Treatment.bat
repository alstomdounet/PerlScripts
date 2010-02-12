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
use ClearquestMgt qw(changeFields makeQuery makeChanges connectCQ disconnectCQ getEntity editEntity getEntityFields getChilds getAvailableActions getFieldsRequiredness cancelAction); 

use GraphicalCommon;

use constant {
	PROGRAM_VERSION => '0.4'
};

use constant {
	UNDEFINED => 'UNDEFINED',
	UNREALISED => 'UNREALISED',
	REALISED => 'REALISED',
};

############################################################################################
# 
############################################################################################
INFO "Starting program (V ".PROGRAM_VERSION.")";
my $Config = loadSharedConfig("Clearquest-config.xml"); # Loading / preprocessing of the common configuration file
my $Clearquest_login = $Config->{clearquest_shared}->{login} or LOGDIE("Clearquest login is not defined properly. Check your configuration file");
my $crypted_string = $Clearquest_login;
my $scriptDir = getScriptDirectory();
$crypted_string =~ s/./*/g;
DEBUG "Using \$Clearquest_login = \"$crypted_string\"";

my $Clearquest_password;
if (ref($Config->{clearquest_shared}->{password})) {
	DEBUG "No credential given. Asking one for current session.";
	
	$| = 1;
	
	print "Insert hereafter password for user \'$Config->{clearquest_shared}->{login}\' : ";
	use Term::ReadKey;
	my $key;
	$Clearquest_password = '';
	#ReadMode 5; # Turn off controls keys
	ReadMode('noecho');
	$Clearquest_password = ReadLine(0);
	chomp $Clearquest_password;
	print "\n";
	ReadMode 'normal';

	INFO("Clearquest password was defined for current session.");
	$Config->{clearquest_shared}->{password} = $Clearquest_password;
}
else {
	$Clearquest_password = $Config->{clearquest_shared}->{password};	
}

$crypted_string = $Clearquest_password;
$crypted_string =~ s/./*/g;
DEBUG "Using \$Clearquest_password = \"$crypted_string\"";

my $Clearquest_database = $Config->{clearquest_shared}->{database} or LOGDIE("Clearquest database is not defined properly. Check your configuration file");
DEBUG "Using \$Clearquest_database = \"$Clearquest_database\"";

my $processedCR;
my $processedCRUI;
my $contentFrame;


############################################################################################
# 
############################################################################################
use Tk;
use Tk::JComboBox;
use Tk::Balloon;
use Tk::Checkbutton;
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

my $CqDatabase = getSharedDirectory().'ClearquestFieldsImage.db';
LOGDIE "No valid database found in \"$CqDatabase\"" unless -r $CqDatabase;
my %CqFieldsDesc = %{retrieve($CqDatabase)};

my $response = $mw->messageBox(-title => "Confirmation request", -message => "Do you want to complete automatically CR\nwhich are currently in progress (if possible)?", -type => 'yesno', -icon => 'question');

INFO "Connecting to Clearquest";
#connectCQ ($Clearquest_login, $Clearquest_password, $Clearquest_database);

if($response eq "Yes") {
	my %filter = (state => 'Realised', product => 'PRIMA EL II', child_record => {operator => 'IS_NOT_NULL'} );
	my @fields = qw(id child_record state substate);
	#my $parentCRList = makeQuery("ChangeRequest", \@fields, \%filter);
	#store ($parentCRList, 'parentDB.db');
	my $parentCRList = retrieve('parentDB.db');
	
	INFO "Retrieving all childs";
	%filter = (product => 'PRIMA EL II', parent_record => {operator => 'IS_NOT_NULL'});
	my @countFields = qw(realised_cost_analysis realised_cost_hardware realised_cost_software realised_cost_system realised_cost_validation);
	@fields = ('parent_record', 'id', 'state', 'substate', 'realised_version', @countFields);
	#my $subCR = makeQuery("ChangeRequest", \@fields, \%filter);
	#store ($subCR, 'child.db');
	my $subCR = retrieve('child.db');
	
	INFO "Analysing results";
	my %parentList;
	DEBUG "Preprocessing parent";
	foreach my $parent (@$parentCRList) {
		my $parentID = $parent->{id};
		unless (exists $parentList{$parentID}) {
			$parentList{$parentID}{fields} = $parent;
		}
		$parentList{$parentID}{childs}{$parent->{child_record}} = 1;
	}
	
	foreach my $child (@$subCR) {
		next unless exists $parentList{$child->{parent_record}};
		next unless exists $parentList{$child->{parent_record}}{childs}{$child->{id}};
		$parentList{$child->{parent_record}}{childs}{$child->{id}} = $child;
	}
	
	foreach my $parentID (sort keys %parentList) {
		my $parent = $parentList{$parentID};
		my $result = REALISED;
		
		my $list = '';
		foreach my $childID (sort keys %{$parent->{childs}}) {
			my $child = $parent->{childs}->{$childID};
			my $substate = ($child->{substate}) ? $child->{substate} : 'No substate';
			$list .= "   - $child->{id} : $child->{state} / $substate\n";
			
			unless(isRealised($child)) { $result = UNREALISED; }
			if(isUndefined($child)) { $result = UNDEFINED; }
			
			foreach my $addedField (@countFields) {
				$parent->{fields}->{$addedField} += $child->{$addedField} if $child->{$addedField};
			}
		}
		
		my $complete = 0;
		my $correct = 0;
		my $editInProgress = $parent->{fields}->{substate} eq 'in progress';
		if($result eq UNDEFINED) {
			($editInProgress) ? ($complete = 1) : ($correct = 1);
		}
		else {
			$complete = 1 if $result eq REALISED and $editInProgress;
			$correct = 1 if $result eq UNREALISED and not $editInProgress;
		}
		
		next unless $correct or $complete;
		my $icon = 'info';
		my $message = "$parentID is $parent->{fields}->{substate}, and has been determined as $result, with following childs:\n$list\nDo you want to complete it?";
		if ($correct) {
			$icon = 'error';
			$message = "$parentID is $parent->{fields}->{substate}, but has been determined as $result, with following childs:\n$list\nIt should have been defined as a CR in progress. Do you want to CORRECT it?";
		}
		
		my $response = '';
		$response = $mw->messageBox(-title => "Modification of CR in state $result", -message => $message, -type => 'yesno', -icon => $icon) if $complete or $correct;
		if($response eq "Yes") {
			if($correct) {
				my %fields = ('work_in_progress' => 'Yes');
				my $result = _performModifications($parentID, 'modify', undef, \%fields);
				ERROR "$parentID was not corrected due to an error" and next unless $result;
			}
			
			if($complete) {
				my %fields;
				foreach my $addedField (@countFields) {
					$fields{$addedField} = $parent->{$addedField};
				}
				print Dumper \%fields;
				#my $result = _performModifications($parentID, 'complete', undef, \%fields);
				#ERROR "$parentID was not corrected due to an error" and next unless $result;
			}
		}
	}
}
exit;

sub isUndefined {
	my ($item) = @_;
	my $state = $item->{state};
	return 1 if $state eq 'Rejected' or $state eq 'Duplicated' or $state eq 'Updated' or $state eq 'Validation_failed' or $state eq 'Postponed';
	return 0;
}

sub isRealised {
	my ($item) = @_;
	my $state = $item->{state};
	my $substate = $item->{substate};

	return 1 if $state eq 'Closed';
	return 1 if $state eq 'Validated' and not $substate eq 'in progress';
	return 1 if $state eq 'Realised' and $substate eq 'complete';

	return 0;
}

my %listOfCRToProcess = preload();
my @listOfCR = sort keys %listOfCRToProcess;
#my %selection;

my $searchFrame = $mw->Frame() -> pack(-side => 'top', -fill => 'x');
my $CrToProcess;
my $CRSelection = addListBox($searchFrame, 'ID à traiter', \@listOfCR, \$CrToProcess);
$CRSelection->{listbox}->configure(-browsecmd => sub {changeCR($CrToProcess)});

# Building buttons
my $bottomPanel = $mw->Frame()->pack(-side => 'bottom', -fill => 'x');
$bottomPanel->Button(-text => 'Cancel', ,-font => 'arial 9', -command => [ \&cancel, $mw], -height => 2, -width => '15') -> pack(-side => 'left', -fill => 'both');
my $buttonValidate = $bottomPanel->Button(-text => "Send modifications",-font => 'arial 9', -command => sub { validateChanges($processedCR); }, -height => 2, -state => 'disabled') -> pack(-side => 'right', -fill => 'both', -expand => 1);

center($mw);
center($mw);
MainLoop();

############################################################################################
# 
############################################################################################
sub preload {
	my %output;
	my $parentCR;
	my $subCR;
	
	if(-r $scriptDir.'modifiedCR.db') {
		INFO "Found database for unfinished operation";
		my $response = $mw->messageBox(-title => "Warning : using backup copy", -message => "Program has detected a previous, unfinished operation.\nDo you want to recover this session (if not, all changes in this session will be lost)?", -type => 'yesno', -icon => 'warning');
		if($response eq "Yes") {
			my $output = retrieve($scriptDir.'modifiedCR.db');
			return %$output;
		}
		unlink $scriptDir.'modifiedCR.db';
	}
	
	INFO "Connecting to Clearquest";
	connectCQ ($Clearquest_login, $Clearquest_password, $Clearquest_database);
	INFO "Retrieving all parents";
	my @fields = qw(id description headline zone child_record ccb_comment sub_system component analyst submitter_cr_type impacted_items proposed_change scheduled_version);
	my %filter = (State => 'Assigned', product => 'PRIMA EL II', child_record => {operator => 'IS_NOT_NULL'});
	$parentCR = makeQuery("ChangeRequest", \@fields, \%filter);
	$output{parentCR} = $parentCR;
	
	INFO "Retrieving all childs";
	%filter = (State => 'Analysed', substate => 'in progress', product => 'PRIMA EL II', parent_record => {operator => 'IS_NOT_NULL'});
	$subCR = makeQuery("ChangeRequest", \@fields, \%filter);
	$output{subCR} = $subCR;

	INFO "Analysing results";
	my %results;
	foreach my $CR (@$parentCR) {
		my $child = $CR->{child_record};
		
		my $results = filterAnswers($output{subCR}, 'id', "^$child\$");
		next if scalar(@$results) == 0;
		unless ($results{$CR->{id}}) {
			$results{$CR->{id}}{fields} = $CR;
		}
		$results{$CR->{id}}{childs}{$child}{fields} = shift @$results;
	}
	
	INFO "Found ".scalar(keys %results)." parent CR";
	
	return %results;
}

sub changeCR {
	my $CrToProcess = shift;
	
	if($processedCR and not $processedCR->{isModified}) {
	
		my $response = $mw->messageBox(-title => "Confirmation requested", -message => "Do you want that modifications done on this CR to be registered on server?", -type => 'yesno', -icon => 'question');
		
		if($response eq "Yes") {
			DEBUG "User has requested to register $processedCR->{fields}->{id}";
			$processedCR->{isModified} = 1;
		}
	}
	
	#$listOfCRToProcess{$processedCR->{fields}->{id}} = $processedCR if $processedCR->{fields}->{id};
	loadCR($CrToProcess) if $CrToProcess;
}

sub filterAnswers {
	my ($arrayRef, $key, $value) = @_;
	
	my @array = grep { $_->{$key} =~ /$value/ } @$arrayRef;
	return \@array;
}

sub loadCR {
	my $id = shift;
	$buttonValidate->configure(-state => 'disabled');
	DEBUG "Destroying content frame" and $contentFrame->destroy() if $contentFrame;
	$processedCR = $listOfCRToProcess{$id};

	$mw->messageBox(-title => "CR not found", -message => "$id was not found in Clearquest database. \nPlease check CR number, or eventually look into logfile.", -type => 'ok', -icon => 'error') and return unless $processedCR;
	
	$contentFrame = $mw->Frame()->pack( -fill=>'both', -expand => 1);

	my $parentFrame = $contentFrame->Frame()->pack( -fill=>'x');
	my $titleFrame = $parentFrame->Frame() -> pack(-side => 'top', -fill => 'x');
	$titleFrame->Label(-text => "Titre", -width => 15 )->pack( -side => 'left' );
	$titleFrame->Label(-text => $processedCR->{fields}{headline}, -font => 'arial 9 bold')->pack( -side => 'left', -fill => 'x', -expand => 1 );
	
	$processedCR->{fields}{changeState} = 1 unless exists $processedCR->{fields}{changeState};
	addDescriptionField($parentFrame, 'Description', \$processedCR->{fields}{description}, -readonly => 1, -height => 3);
	addDescriptionField($parentFrame, 'CCB comment', \$processedCR->{fields}{ccb_comment}, -readonly => 1, -height => 1);
	addCheckButton($parentFrame, 'Change this parent into its Realised / in progress state', \$processedCR->{fields}{changeState});
	$titleFrame->Label(-text => "Titre", -width => 15 )->pack( -side => 'left' );
	
	my $notebook = $contentFrame->NoteBook()->pack( -fill=>'both', -expand=>1 );
	
	foreach my $subID (sort keys %{$processedCR->{childs}}) {
		DEBUG "Processing child $subID";
		buildTab($notebook,$subID,$processedCR->{childs}{$subID}, $processedCRUI->{childs}{$subID}, $id);
	}
	$mw->geometry("640x480");
	$buttonValidate->configure(-state => 'normal');
}

sub addCheckButton {
	my ($parentFrame, $text, $variableRef) = @_;
	my $titleFrame = $parentFrame->Frame() -> pack(-side => 'top', -fill => 'x');
	$titleFrame->Label(-text => "", -width => 15 )->pack( -side => 'left' );
	return $titleFrame->Checkbutton(-text => $text, -variable => $variableRef)->pack( -side => 'left' );
}

sub buildTab {
	my ($notebook, $tabName, $content, $receiver, $parentID) = @_;
	
	$receiver->{tabName} = $tabName;
	
	my $tab1 = $notebook->add($tabName, -label => $tabName);

	my (@mandatoryFields, @listSubSystems);
	$receiver->{tab} = $tab1;
	my @test;
	foreach my $item (@{$CqFieldsDesc{sub_system}{shortDesc}}) {
		push (@test, { -name => $item, -value => $CqFieldsDesc{sub_system}{equivTable}{$item} });
	}
	
	$receiver->{listSubsystems} = addListBox($tab1, 'Subsystem', \@test, \$content->{fields}{sub_system});
	my @list;
	$receiver->{dynamicComponentList} = \@list;

	my $backup = $content->{fields}{component};
	$receiver->{listComponents} = addListBox($tab1, 'Component', $receiver->{dynamicComponentList}, \$content->{fields}{component});

	if ($content->{fields}{sub_system}) {
		updateComponents($content->{fields}{sub_system}, $receiver->{listComponents}, $receiver->{dynamicComponentList});
		${$receiver->{listComponents}->{selection}} = $backup;
	}
	
	unless($content->{fields}{proposed_change} =~ m/^=== Analyse de \w+ \(CR parent atvcm\d{8}\) ===/) {
		$content->{fields}{proposed_change} = "=== Analyse de $content->{fields}{analyst} (CR parent $parentID) ===\n".$content->{fields}{proposed_change}."\n=== Complément d'analyse ===" if $content->{fields}{proposed_change};
	}
	
	$receiver->{listAnalyser} = addListBox($tab1, 'Analyst', $CqFieldsDesc{analyst}{shortDesc}, \$content->{fields}{analyst}, -searchable => 0);
	$receiver->{listTypes} = addListBox($tab1, 'Type', $CqFieldsDesc{submitter_CR_type}{shortDesc}, \$content->{fields}{submitter_cr_type});
	$receiver->{TextImpactedItems} = addDescriptionField($tab1, 'Impacted items', \$content->{fields}{impacted_items}, -height => 1);
	$receiver->{TextProposedChanges} = addDescriptionField($tab1, 'Proposed changes', \$content->{fields}{proposed_change});
	
	$receiver->{listSubsystems}->{listbox}->configure(-browsecmd => sub {updateComponents($content->{fields}{sub_system}, $receiver->{listComponents}, $receiver->{dynamicComponentList});});
	$receiver->{checkBox} = addCheckButton($tab1, 'Pass this CR directly in Assigned state', \$content->{fields}{changeState});
	$receiver->{checkBox}->configure(-command => sub { $receiver->{listAnalyser}->{label}->configure(-text => ($content->{fields}{changeState}) ? ('Implementer') : ('Analyst')); } );
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

	my $idDatabase = $bugID.'.db';
	if (-r $idDatabase) {
		WARN "Using Database unstead of direct copy";
		my $bug = retrieve($idDatabase);
		return %$bug;
	}
	
	INFO "Retrieving needed informations";
	my $entity = getEntity('ChangeRequest',$bugID);
	my %fields = getEntityFields($entity);
	$bug{fields} = \%fields;
	foreach my $childID (getChilds($entity)) {
		INFO "Retrieving needed informations for child \"$childID\"";
		my %child;
		my $childEntity = getEntity('ChangeRequest',$childID);
		my %childFields = getEntityFields($childEntity);
		$child{fields} = \%childFields;
		$bug{childs}{$childID} = \%child;
	}
	store(\%bug, $idDatabase) unless -r $idDatabase;
	return %bug;
}

sub validateChanges {
	changeCR();
	
	my $response = $mw->messageBox(-title => "Confirmation requested", -message => "Do you really want perform all these modifications?", -type => 'yesno', -icon => 'question');
	
	DEBUG "User has answered \"$response\" to cancellation question";
	return unless $response eq "Yes";
	
	INFO "Saving modifications in case of crash";
	my $saved_output = _copyElement(\%listOfCRToProcess);
	store $saved_output, $scriptDir.'modifiedCR.db';
	
	my @selectedFields = qw(sub_system component analyst impacted_items submitter_cr_type proposed_change);
	my @copiedFieldsFromParent = qw(zone scheduled_version);

	INFO "Connecting to clearquest database \"$Clearquest_database\" with user \"$Clearquest_login\"";
	connectCQ ($Clearquest_login, $Clearquest_password, $Clearquest_database);
	
	my @success_CR;
	my @failed_CR;
	foreach my $processedCR (values %listOfCRToProcess) {
		next unless $processedCR->{isModified};
		INFO "Processing parent CR \"$processedCR->{fields}->{id}\"";

		my $errors_occured = 0;
		my $childProcessed = 0;
		foreach my $bugID (sort keys %{$processedCR->{childs}}) {
			DEBUG "Processing child CR \"$bugID\"";
			my $CR = $processedCR->{childs}->{$bugID}->{fields};
			$childProcessed++;
			
			my @changedFields;
			
			foreach my $field (@selectedFields) {
				push(@changedFields, { FieldName => $field, FieldValue => $CR->{$field}});
			}
			
			foreach my $field (@copiedFieldsFromParent) {
				push(@changedFields, { FieldName => $field, FieldValue => $processedCR->{fields}->{$field}});
			}

			my $result = _performModifications ($bugID, 'Rectify', \@changedFields);
			ERROR "$bugID was not rectified correctly" and $errors_occured++ unless $result;
		}
		
		if($errors_occured) {
			push (@failed_CR, $processedCR->{fields}->{id});
		}
		else {
			my $bugID = $processedCR->{fields}->{id};
			my %fields = ('work_in_progress' => 'Yes', 'realised_item' => "$childProcessed CR crées et affectées.");
			_performModifications ($bugID, 'Realise', undef, \%fields) or ERROR "$bugID has not changed its state in Realised / complete";
			push (@success_CR, $processedCR->{fields}->{id});
		}
	}

	open FILE, ">${scriptDir}Report.txt";
	
	print FILE "Hereafter are correctly modified parent CR:\n - ".join("\n - ", @success_CR)  if scalar (@success_CR) > 0;
	print FILE "\n\nHereafter are failed parent CR:\n - ".join("\n - ", @failed_CR) if scalar (@failed_CR) > 0;
	
	close FILE;
	
	INFO "All modifications done correctly. Removing backup database" and unlink $scriptDir.'modifiedCR.db';
}

sub _performModifications {
	my ($bugID, $action, $orderedFields, $fields) = @_;
	my $entity = getEntity('ChangeRequest',$bugID);
	editEntity($entity, $action);
	my $result = changeFields($entity, -OrderedFields => $orderedFields, -Fields => $fields);
	if($result) {
		$result = makeChanges($entity);
		return 0 unless $result;
		return 1;
	}
	else {
		cancelAction($entity);
		return 0;
	}
}

sub _copyElement {
	my $element = shift;
	if(ref($element) eq 'HASH') {
		my %hash;
		foreach my $key (keys %$element) {
			$hash{$key} = _copyElement($element->{$key});
		}
		return \%hash;
	}
	else {
		my $result = $element;
		return $result;
	}
	
}

exit;

__END__
:endofperl
pause