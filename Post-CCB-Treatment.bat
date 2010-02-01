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
use ClearquestMgt qw(changeFields makeQuery makeChanges connectCQ disconnectCQ getChangeRequestFields getEntity editEntity getEntityFields getChilds getAvailableActions getFieldsRequiredness cancelAction); 

use GraphicalCommon;

use constant {
	PROGRAM_VERSION => '0.3'
};

############################################################################################
# 
############################################################################################
INFO "Starting program (V ".PROGRAM_VERSION.")";
my %Config = loadConfig("Clearquest-config.xml"); # Loading / preprocessing of the configuration file
my $Clearquest_login = $Config{clearquest}->{login} or LOGDIE("Clearquest login is not defined properly. Check your configuration file");
my $crypted_string = $Clearquest_login;
$crypted_string =~ s/./*/g;
DEBUG "Using \$Clearquest_login = \"$crypted_string\"";

my $Clearquest_password;
if (ref($Config{clearquest}->{password})) {
	DEBUG "No credential given. Asking one for current session.";
	
	$| = 1;
	
	print "Insert hereafter password for user \'$Config{clearquest}->{login}\' : ";
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
	$Config{clearquest}->{password} = $Clearquest_password;
}
else {
	$Clearquest_password = $Config{clearquest}->{password};	
}

$crypted_string = $Clearquest_password;
$crypted_string =~ s/./*/g;
DEBUG "Using \$Clearquest_password = \"$crypted_string\"";

my $Clearquest_database = $Config{clearquest}->{database} or LOGDIE("Clearquest database is not defined properly. Check your configuration file");
DEBUG "Using \$Clearquest_database = \"$Clearquest_database\"";


my %CqFieldsDesc;
my $CqDatabase = 'ClearquestImage.db';
my $bugsDatabase = 'bugsDatabase.db';
if (-r $CqDatabase) {
	my $storedData = retrieve($CqDatabase);
	%CqFieldsDesc = %$storedData;
}
else { LOGDIE "Not valid database"; }
my $processedCR;
my $processedCRUI;
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

my %listOfCRToProcess = preload();
my @listOfCR = sort keys %listOfCRToProcess;
my %selection;

my $searchFrame = $mw->Frame() -> pack(-side => 'top', -fill => 'x');
my $CrToProcess;
my $CRSelection = addListBox($searchFrame, 'ID à traiter', \@listOfCR, \$CrToProcess);
$CRSelection->{listbox}->configure(-browsecmd => sub {changeCR($CrToProcess)});

sub changeCR {
	my $CrToProcess = shift;
	
	$listOfCRToProcess{$selection{id}} = \%selection if $selection{id};
	
	loadCR($CrToProcess);
	
	DEBUG "Saving modified CR in database";
	open FILE, ">output.txt";
	print FILE Dumper \%listOfCRToProcess;
	close FILE;
	#store(\%listOfCRToProcess, 'modifiedCRs.db');
	DEBUG "End of saving";
}

# Building buttons
my $bottomPanel = $mw->Frame()->pack(-side => 'bottom', -fill => 'x');
$bottomPanel->Button(-text => 'Cancel', ,-font => 'arial 9', -command => [ \&cancel, $mw], -height => 2, -width => 10) -> pack(-side => 'left');
my $buttonValidate = $bottomPanel->Button(-text => "Send modifications",-font => 'arial 9', -command => sub { validateChanges($processedCR); }, -height => 2, -width => 10, -state => 'disabled') -> pack(-side => 'right');

center($mw);
center($mw);
MainLoop();

############################################################################################
# 
############################################################################################
sub preload {
	INFO "Connecting to Clearquest";
	#connectCQ ($Clearquest_login, $Clearquest_password, $Clearquest_database);
	INFO "Retrieving needed informations";
	my @fields = qw(id description headline zone child_record ccb_comment sub_system component analyst submitter_cr_type impacted_items proposed_change scheduled_version State);
	my %filter = (State => 'Assigned', product => 'PRIMA EL II');
	#my @parentCR = makeQuery("ChangeRequest", \@fields, \%filter);
	
	%filter = (State => 'Analysed', substate => 'in progress', product => 'PRIMA EL II');
	#my @subCR = makeQuery("ChangeRequest", \@fields, \%filter);
	
	my $output = retrieve('bugList.db');
	my %output = %$output;
	#$output{parentCR} = \@parentCR;
	#output{subCR} = \@subCR;
	
	my @parentCR = filterAnswers($output{parentCR}, 'child_record','^.+$'); # Finds all parent CR
	
	my %results;
	foreach my $CR (@parentCR) {
		my $child = $CR->{child_record};
		unless ($results{$CR->{id}}) {
			$results{$CR->{id}}{fields} = $CR;
		}
		my @results = filterAnswers($output{subCR}, 'id', "^$child\$");
		next if scalar(@results == 0);
		$results{$CR->{id}}{childs}{$child}{fields} = shift @results;
	}
	
	INFO "Found ".scalar(keys %results)." parent CR";
	
	return %results;
}

sub filterAnswers {
	my ($arrayRef, $key, $value) = @_;
	
	return grep { $_->{$key} =~ /$value/ } @$arrayRef;
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
	
	addDescriptionField($parentFrame, 'Description', \$processedCR->{fields}{description}, -readonly => 1, -height => 3);
	addDescriptionField($parentFrame, 'CCB comment', \$processedCR->{fields}{ccb_comment}, -readonly => 1, -height => 1);
	
	my $notebook = $contentFrame->NoteBook()->pack( -fill=>'both', -expand=>1 );
	
	foreach my $subID (sort keys %{$processedCR->{childs}}) {
		DEBUG "Processing child $subID";
		buildTab($notebook,$subID,$processedCR->{childs}{$subID}, $processedCRUI->{childs}{$subID});
	}
	$mw->geometry("640x480");
	$buttonValidate->configure(-state => 'normal');
}

sub buildTab {
	my $notebook = shift;
	my $tabName = shift;
	my $content = shift;
	my $receiver = shift;
	
	$receiver->{tabName} = $tabName;
	
	my $tab1 = $notebook->add($tabName, -label => $tabName);

	my (@mandatoryFields, @listSubSystems);
	$receiver->{tab} = $tab1;
	my @test;
	foreach my $item (@{$CqFieldsDesc{sub_system}{shortDesc}}) {
		push (@test, { -name => $item, -value => $CqFieldsDesc{sub_system}{equivTable}{$item} });
		#push (@test, { -name => $item, -value => $item.$item });
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
	$receiver->{listAnalyser} = addListBox($tab1, 'Analyst', $CqFieldsDesc{analyst}{shortDesc}, \$content->{fields}{analyst}, -searchable => 0);
	$receiver->{listTypes} = addListBox($tab1, 'Type', $CqFieldsDesc{submitter_CR_type}{shortDesc}, \$content->{fields}{submitter_cr_type});
	$receiver->{TextImpactedItems} = addDescriptionField($tab1, 'Impacted items', \$content->{fields}{impacted_items}, -height => 1);
	$receiver->{TextProposedChanges} = addDescriptionField($tab1, 'Proposed changes', \$content->{fields}{proposed_change});
	
	$receiver->{listSubsystems}->{listbox}->configure(-browsecmd => sub {updateComponents($content->{fields}{sub_system}, $receiver->{listComponents}, $receiver->{dynamicComponentList});});
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
	
	INFO "Connecting to Clearquest";
	connectCQ ($Clearquest_login, $Clearquest_password, $Clearquest_database);
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
	my ($processedCR) = @_;
	
	my $response = $mw->messageBox(-title => "Confirmation requested", -message => "Do you really want perform all these modifications?", -type => 'yesno', -icon => 'question');
	
	DEBUG "User has answered \"$response\" to cancellation question";
	return unless $response eq "Yes";
	
	my @selectedFields = qw(sub_system component analyst impacted_items submitter_cr_type proposed_change);
	
	INFO "Connecting to clearquest database \"$Clearquest_database\" with user \"$Clearquest_login\"";
	connectCQ ($Clearquest_login, $Clearquest_password, $Clearquest_database);
	my @CR_ok = ("");
	foreach my $bugID (sort keys %{$processedCR->{childs}}) {
		INFO "Processing CR named \"$bugID\"";
		my $CR = $processedCR->{childs}->{$bugID}->{fields};
		
		my @changedFields;
		foreach my $field (@selectedFields) {
			push(@changedFields, { FieldName => $field, FieldValue => $CR->{$field}});
		}

		my $entity = getEntity('ChangeRequest',$bugID);
		editEntity($entity, 'Rectify');
		my $result = changeFields($entity, -OrderedFields => \@changedFields);
		my $message = "";
		if($result) {
			$result = makeChanges($entity);
			$message = "Validation / commit has failed on \"$bugID\".\nPlease refer to logfile for details." unless $result;
		}
		else {
			$message = "Modifications of fields of \"$bugID\" has not been performed correctly.\nPlease refer to logfile for details.";
			cancelAction($entity);
		}
		$mw->messageBox(-title => "Problem with CR \"$bugID\"", -message => $message, -type => 'ok', -icon => 'error') and next unless $result;
		push(@CR_ok, $bugID);
	}
	
	if(scalar(@CR_ok) > 1) {
		my $message = "Modifications were performed successfully on following CRs:".join("\n - ", @CR_ok);
		INFO $message;
		#$mw->messageBox(-title => "Operation successful", -message => $message, -type => 'ok', -icon => 'info');
	}
}

exit;

__END__
:endofperl
pause