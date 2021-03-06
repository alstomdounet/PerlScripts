@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
cqperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
if ERRORLEVEL 1001 goto finishedCorrectly
goto waitDueToErrors
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
use Crypt::Rijndael_PP qw(rijndael_encrypt rijndael_decrypt MODE_CBC);
use Storable qw(store retrieve thaw freeze);
use ClearquestMgt qw(connectCQ makeQuery);

use constant {
	PROGRAM_VERSION => '2.6 beta 4',
	DATABASE_VERSION => '2.5',
	OPTIONAL_FIELD_TEXT => 'Optional',
	MANDATORY_FIELD_TEXT => 'Mandatory',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";
DEBUG "Required database version is V ".DATABASE_VERSION."";
my $Config = loadSharedConfig("Clearquest-config.xml"); # Loading / preprocessing of the configuration file
my $localConfig = loadLocalConfig("Add-bug.config.xml", "config.xml"); # Loading / preprocessing of the configuration file

#################################
# Global variables
#################################

my $CqDatabase = getSharedDirectory().'ClearquestFieldsImage.db';
my $bugsDatabase = getScriptDirectory().'bugsDatabase.db';
my $failedBugsDatabase = getScriptDirectory().'FailedBugsDatabase.db';
my $encryptedDatabase = getScriptDirectory().'bugsDatabase.edb';
my $failedTextFile = getScriptDirectory().'FailedBugs.log.txt';
my $successTextFile = getScriptDirectory().'SuccessBugs.log.txt';

my %results;

if(-r $encryptedDatabase) {
	print "Insert hereafter keypass to decrypt database: ";
	chomp(my $password = <>);
	my $data = importEncryptedDb ($encryptedDatabase,$password);
	
	my $session = CQSession::Build(); 
	my $nbrOfBugsToInsert  = scalar(@{$data->{bugList}});
	INFO "You will insert $nbrOfBugsToInsert bugs into Clearquest database";
	while($nbrOfBugsToInsert > 0) {
		my $result = sendCrToCQ($session, $data);
		$nbrOfBugsToInsert--;
	}
	INFO "If not errors has occured, you can safely delete \"$encryptedDatabase\" (to avoid duplicate inserts)";
	exit(1001);
}

#################################
#
#################################
use threads;                    # Pour cr�er nos threads
use threads::shared;            # Pour partager nos donn�es entre threads

my $killThread : shared;          # Permet de tuer le thread proprement
my $FunctionName : shared;         # Contient le nom de la fonction � appeler
my $ThreadWorking : shared;       # Contient la valeur permettant au thread de lancer une proc�dure
my @ArgumentsThread : shared;     # Contient les arguements � passer � une �ventuelle proc�dure
my $ResultFunction : shared;    # Contient le r�sultat des fonctions lanc�es dans le thread
my $frozenCQFields : shared;
my $Clearquest_password : shared;

$ThreadWorking = 0;               # 0 : thread ne fait rien, 1 : il bosse
$killThread    = 0;               # 0 : thread en vie, 1 : thread se termine


my $Thread = threads->create( \&SubProcessesThread ); # Thread creation
#################################
# Main thread : this one is used to lauch auxiliary tasks
#################################
sub SubProcessesThread {
	my %FunctionsThreaded = ( "sendCrToCQ" => \&sendCrToCQ );
	DEBUG "Thread is started";

	while ($killThread != 1) { 	# Loop while we don't request to kill the thread
		if ( $ThreadWorking == 1 ) {     # Request thread to initiate its work
			DEBUG "Thread has began its task (function '$FunctionName')";
			$ResultFunction = $FunctionsThreaded{$FunctionName}->(@ArgumentsThread); # Launch function

			$ThreadWorking = 0; # Thread has finished its work
			DEBUG "Thread has finished its task";
		}
		sleep 1;
    }
	DEBUG "Thread is about to exit";
	$killThread = 0;
	return;
}



############################################################################################
# 
############################################################################################
use Tk;
use Tk::JComboBox;
use Tk::Balloon;
#use CQPerlExt; 

my $CONNECTION_TO_CQ_DISABLED;
if (not $localConfig->{scriptInfos}->{offlineMode} and $localConfig->{clearquest}->{userHasLogin}) {
	DEBUG "Utilisation of this program requires a login / password pair.";
	my $Clearquest_login = $Config->{clearquest_shared}->{login} or LOGDIE("Clearquest login is not defined properly. Check your configuration file");
	my $crypted_string = $Clearquest_login;
	$crypted_string =~ s/./*/g;
	DEBUG "Using \$Clearquest_login = \"$crypted_string\"";

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
} else {
	WARN "Script is used without login, or in OFFLINE MODE. It is not possible to connect directly to Clearquest.";
	$CONNECTION_TO_CQ_DISABLED = 1;
}

my $windowSizeX = 640;
my $windowSizeY = 480;

##########################################
# Retrieving stored data for Clearquest fields
##########################################
my %CqFieldsDesc;
my $syncNeeded = 0;
if (-r $CqDatabase) {
	my $storedData = retrieve($CqDatabase);
	%CqFieldsDesc = %$storedData;
	$syncNeeded = (time() - $CqFieldsDesc{lastUpdate} - $localConfig->{scriptInfos}->{refreshDatabase}) > 0;
	$syncNeeded = (DATABASE_VERSION ne $CqFieldsDesc{databaseVersion}) unless $syncNeeded;
	$syncNeeded = ($Config->{clearquest_shared}->{database} ne $CqFieldsDesc{CQDatabase}) unless $syncNeeded;
	$syncNeeded = ($Config->{clearquest_shared}->{product} ne $CqFieldsDesc{product}) unless $syncNeeded;
}
else { $syncNeeded = 1; }

if($syncNeeded and not $CONNECTION_TO_CQ_DISABLED) {
	syncFieldsWithClearQuest(\%CqFieldsDesc);
} else { DEBUG "Using all Clearquest data stored in database."; }
LOGDIE "You have a database at V $CqFieldsDesc{databaseVersion}. You have to upgrade it because program is now at V ".DATABASE_VERSION if (DATABASE_VERSION ne $CqFieldsDesc{databaseVersion});


$frozenCQFields = freeze(\%CqFieldsDesc);

##########################################
# Synchronizing with ClearQuest database
##########################################
sub syncFieldsWithClearQuest {
	my $data = shift;
	INFO "Synchronization of Clearquest fields is required.";
	
	INFO "Connecting to Clearquest database";
	my $session = connectCQ($Config->{clearquest_shared}->{login}, $Config->{clearquest_shared}->{password}, $Config->{clearquest_shared}->{database});
	
	if($session) {
		INFO "Connection established - Refreshing fields...";
	}
	else {
		WARN "Connection failed";
		return;
	}

	
	# Trying to get list of components dynamically from Clearquest database, with associated comments. 
	# It is get through makeQuery function (see hereafter) because we need to get comment (and it is not accessible otherwise)
	my @fieldList = ('sub_system', 'sub_system.component', 'sub_system.component.comment');
	
	my %filters = ('name' => $Config->{clearquest_shared}->{product});
	my $results = makeQuery('Product', \@fieldList , \%filters);
	
	# Trying to get list of components dynamically from Clearquest database, with associated comments. 
	my %results;
	foreach my $item (@$results) {
		$results{$item->{'sub_system'}}{$item->{'sub_system.component'}} = $item->{'sub_system.component.comment'};
	}
	
	# Trying to get list of sub-systems dynamically from Clearquest database, with associated comments. 
	# They have to be selected separately because they require selecting first other fields.
	my @listS;
	foreach my $sub_system (sort keys %results) {
		my %sub_system  = %{$results{$sub_system}};
		my ($sub_system, $simple_sub_system)  = extractComplexField($sub_system);
		DEBUG "Processing sub_system '$sub_system'";
		
		$data->{sub_system}{equivTable}{$simple_sub_system} = $sub_system; # selecting sub-system, so we can get associated components
		foreach my $component (sort keys %sub_system) {
			my ($component, $simple_component)  = extractComplexField($component);
			DEBUG "Processing component '$sub_system'";
			if ($simple_component =~ /^\s*$/) {
				DEBUG "Skipping empty component";
				next;
			}
			$data->{component}{equivTable}{$simple_sub_system}{$simple_component} = $component;
			$data->{component}{commentTable}{$simple_sub_system}{$simple_component} = $sub_system{$component};
		}
		push(@listS, $simple_sub_system);
	}
	$data->{sub_system}{shortDesc} = \@listS;
	

	# Trying to get all others fields. They can be selected easily without preselecting first other fields
	my @fields = qw(submitter_CR_origin submitter_CR_type submitter_priority submitter_severity frequency product_version site defect_detection_phase zone analyst CR_category write_arrival_state symptom);
	
	my $rec = $session->BuildEntity("ChangeRequest");

	$data->{product} = $Config->{clearquest_shared}->{product};
	$data->{CQDatabase} = $Config->{clearquest_shared}->{database};
	$rec->SetFieldValue('product', $data->{product});
	$rec->SetFieldValue('write_arrival_state', 'Submitted - new');
	
	foreach my $key (@fields) {
		DEBUG "Extracting field '$key'";
		my @shortDesc;
		
		# Added a default value
		push(@shortDesc, "No selection");
		$data->{$key}{equivTable}{"No selection"} = undef;
		
		foreach my $item (@{$rec->GetFieldChoiceList($key)}) {
			my ($text, $simpleText)  = extractComplexField($item);
			push(@shortDesc, $simpleText);
			$data->{$key}{equivTable}{$simpleText} = $text;
		}
		
		@shortDesc = sort (@shortDesc) if $key eq "analyst";
		
		$data->{$key}{shortDesc} = \@shortDesc;
	}

	$data->{lastUpdate} = time();
	$data->{scriptVersion} = PROGRAM_VERSION;
	$data->{databaseVersion} = DATABASE_VERSION;

	store ($data, $CqDatabase);
}

sub extractComplexField {
	my $text = shift;

	my $simpleText = $text;
	if($text =~ /^([^\xA0]*)\xA0/) { # This is a strange character inserted automatically by clearquest...
		$simpleText = $1;
		$simpleText =~ s/\s*$//g;
		#$text =~ s/\xA0/ /g;
	}
	
	return ($text, $simpleText);
}

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

my $alternateStatusWhenNobugsSelected = 'disabled';
$alternateStatusWhenNobugsSelected = 'normal' if $Config->{scriptInfos}->{allowNoBugsCheckins};

DEBUG "Building graphical interface";

my $mw = MainWindow->new(-title => "Interface to add new bugs into \"".$Config->{clearquest_shared}->{product}."\"");
$mw->withdraw; # disable immediate display
$mw->minsize($windowSizeX,$windowSizeY);

######################################################################
# Variables declaration
######################################################################
my @listSubSystems = @{$CqFieldsDesc{sub_system}{shortDesc}};
my %bugDescription;
my %backupDescription;
my $lastSelectedSubsystem = '';
my $balloon = $mw->Balloon();
my $textSendLater;
my $textSendNow;
my $textSendAllNow;
my $editMode = 1;
my $totalNumberOfBugs = 0;
my $currentBugIndex = 0;

# Building listboxes
my @mandatoryFields;

my $listZones = addListBox($mw, 'Zone', 'zone', OPTIONAL_FIELD_TEXT, 'Select hereafter if anomaly will be project specific or affects the whole product line', $CqFieldsDesc{zone}{shortDesc});
my $listSubsystems = addListBox($mw, 'Subsystem', 'sub_system', MANDATORY_FIELD_TEXT, 'Enter hereafter the subsystem',\@listSubSystems);
my $listComponents = addSearchableListBox($mw, 'Component', 'component', OPTIONAL_FIELD_TEXT, "Select the component affected.\nIf more components are affected, please make on CR per affected component.");
my $listVersions = addListBox($mw, 'Product version', 'product_version', MANDATORY_FIELD_TEXT, "Select the version affected bu the CR.",  $CqFieldsDesc{product_version}{shortDesc});
my $listCriticities = addListBox($mw, 'Severity', 'submitter_severity', MANDATORY_FIELD_TEXT, "Select Severity level, from \"bypassing\" (problems with no impact on functional)\nto \"blocking\" (issues which doesn't allow a step to complete).", $CqFieldsDesc{submitter_severity}{shortDesc});
my $listPriorities = addListBox($mw, 'Priority', 'submitter_priority', MANDATORY_FIELD_TEXT, "Select Priority level, from Low to High", $CqFieldsDesc{submitter_priority}{shortDesc});
my $listFrequencies = addListBox($mw, 'Frequency', 'frequency', MANDATORY_FIELD_TEXT, "Determine if the problem is systematic (Every time) or occurs only sometimes.", $CqFieldsDesc{frequency}{shortDesc});
my $listOrigins = addListBox($mw, 'Origin', 'submitter_CR_origin', MANDATORY_FIELD_TEXT, "Determine where is located the issue.", $CqFieldsDesc{submitter_CR_origin}{shortDesc});
my $listSites = addListBox($mw, 'Site', 'site', MANDATORY_FIELD_TEXT, "Determine who will process the issue.", $CqFieldsDesc{site}{shortDesc});
my $listDetPhasis = addListBox($mw, 'Detection phase', 'defect_detection_phase', MANDATORY_FIELD_TEXT, "Determine when was the problem detected.", $CqFieldsDesc{defect_detection_phase}{shortDesc});
my $listSymptoms = addSearchableListBox($mw, 'Symptom', 'symptom', OPTIONAL_FIELD_TEXT, "Problem which occurs because of this CR.", $CqFieldsDesc{symptom}{shortDesc});
my $listTypes = addListBox($mw, 'Type', 'submitter_CR_type', MANDATORY_FIELD_TEXT, "Type of modification:\n - defect for non-compliance of a requirement (specification, etc.)\n - enhancement is for various improvements (functionality, reliability, speed, etc.)", $CqFieldsDesc{submitter_CR_type}{shortDesc});
my $recordingMode = addListBox($mw, 'Recording mode', 'write_arrival_state', MANDATORY_FIELD_TEXT, "Mode in which this CR will be recorded", $CqFieldsDesc{write_arrival_state}{shortDesc});
my $listAnalyser = addSearchableListBox($mw, 'Analyst', 'analyst', OPTIONAL_FIELD_TEXT, "Determine who will analyse the issue.", $CqFieldsDesc{analyst}{shortDesc});
my $listCROrigin = addListBox($mw, 'Category', 'CR_category', MANDATORY_FIELD_TEXT, "TBD", $CqFieldsDesc{CR_category}{shortDesc});


# Building title / description
my $TitlePanel = $mw->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);
$TitlePanel->Label(-text => 'Title', -width => 15 )->pack( -side => 'left' );
my $title = $TitlePanel->Entry(-textvariable => \$bugDescription{headline})->pack(-fill => 'x', -side => 'top', -anchor => 'center');
$balloon->attach($title, -msg => "<Mandatory> Title of the issue. It shall be self-meaning, concise.");
push(@mandatoryFields, {Text => 'Title', CQ_Field => 'headline' });

my $DescriptionPanel = $mw->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);
$DescriptionPanel->Label(-text => "Description", -width => 15 )->pack( -side => 'left' );
my $description = $DescriptionPanel->Scrolled("Text", -scrollbars => 'osoe') -> pack( -side => 'top', -fill => 'both');
$balloon->attach($description, -msg => "<Mandatory> The complete description of the issue. It shall comply with following rules:\n - it describes one and ONLY one issue (if two problems are independant, then there are two issues);\n - It indicates as precisely as possible environment, conditions\n - It indicates paragraph/component affected when possible.");
push(@mandatoryFields, {Text => 'Description', CQ_Field => 'description' });

# Building buttons
my $bottomPanel = $mw->Frame() -> pack(-side => 'bottom', -fill => 'x');

$bottomPanel->Button(-text => 'Cancel', ,-font => 'arial 9', -command => [ \&cancel, $mw], -height => 2, -width => 10) -> pack(-side => 'left');
my $buttonSwitch = $bottomPanel->Button(-text => "Switch\nmode",-font => 'arial 9', -command => [ \&switchActions], -height => 2, -width => 10) -> pack(-side => 'left');

my $actionsPanel = $bottomPanel->Frame() -> pack(-side => 'right', -fill => 'x', -expand => 1);
my $containerActions = $actionsPanel->Frame();

my $buttonSendLater = $containerActions->Button(-text => 'Add CR in memory', -font => 'arial 9 bold', -command => [ \&AddAndSendCr, \%bugDescription, 0], -height => 2) -> pack(-side => 'left', -fill => 'x', -expand => 1);
my $buttonSendNow = $containerActions->Button(-text => 'Add and send CR now', -font => 'arial 9 bold', -command => [ \&AddAndSendCr, \%bugDescription, 1], -height => 2) -> pack(-side => 'left', -fill => 'x', -expand => 1);
my $buttonSendAllNow = $containerActions->Button(-text => 'Send all CRs now', -font => 'arial 9 bold', -command => [ \&AddAndSendCr, undef, -1], -height => 2) -> pack(-side => 'left', -fill => 'x', -expand => 1);
my $buttonExport = $containerActions->Button(-text => 'Export', -font => 'arial 9 bold', -command => [ \&ExportEncryptedDb], -height => 2) -> pack(-side => 'right', -fill => 'x', -expand => 1);

my $containerEdit = $actionsPanel->Frame();
my $navigationlabelText = "";
my $navigationlabel = $containerEdit->Label(-textvariable => \$navigationlabelText )->pack( -side => 'left', -fill => 'x', -expand => 1);
my $buttonDelete = $containerEdit->Button(-text => 'Delete', -font => 'arial 9 bold', -command => [ \&editDisplayedBug], -width => 10, -height => 2) -> pack(-side => 'right');
my $buttonModify = $containerEdit->Button(-text => 'Modify', -font => 'arial 9 bold', -command => [ \&editDisplayedBug, 1], -width => 10, -height => 2) -> pack(-side => 'right');
my $buttonNext = $containerEdit->Button(-text => '> >', -font => 'arial 9 bold', -command => [ \&manageNavigation, 1], -width => 5, -height => 2) -> pack(-side => 'right');
my $buttonPrevious = $containerEdit->Button(-text => '< <', -font => 'arial 9 bold', -command => [ \&manageNavigation, -1], -width => 5, -height => 2) -> pack(-side => 'right');

switchActions();

INFO "displaying graphical interface";
my $results = getNumberOfBugs(1);
$mw->messageBox(-title => "Information", -message => "You have currently $results issue(s) to be sent.\nClick \"Send all\" to synchronize with Clearquest database.", -type => 'ok', -icon => 'info') if $results;
$mw->Popup; # window appears screen-centered
MainLoop();

##########################################
# Managing saved bugs
##########################################
sub addBug {
	my $bug = shift;
	
	my %bug = %$bug;
	$bug{product} = $CqFieldsDesc{product};
	
	my %data;
	%data = %{retrieve($bugsDatabase)} if -r $bugsDatabase;
	
	push(@{$data{bugList}}, \%bug);
	
	store (\%data, $bugsDatabase) and $mw->messageBox(-title => "Information", -message => "Anomaly \"$bug{headline}\" has been registered inside offline database.", -type => 'ok', -icon => 'info');

	# Deleting fields which are quite usually different from one CR to another
	$bug->{submitter_priority} = '';
	$bug->{headline} = '';
	$bug->{submitter_severity} = '';
	$bug->{frequency} = '';
	$bug->{submitter_CR_type} = '';
	$bug->{symptom} = '';
	$bug->{description} = '';
	$description->Contents('');
}

sub editDisplayedBug {
	my $index = $currentBugIndex;
	my $editMode = shift;
	
	my %data = %{retrieve($bugsDatabase)};	
	
	if($editMode) {
		return unless validate();
		delete $data{bugList}[$index];
		foreach my $key (keys(%bugDescription)) {
			$data{bugList}[$index]{$key} = $bugDescription{$key}; 		
		}

		$mw->messageBox(-title => "Information", -message => "Issue has been modified", -type => 'ok', -icon => 'info');
	}
	else {
		my $response = $mw->messageBox(-title => "Removal confirmation requested", -message => "Do you confirm the removal of this issue?", -type => 'yesno', -icon => 'question');

		DEBUG "User has answered \"$response\" to removal of bug #$index";
		return unless $response eq "Yes";
		INFO "User has confirmed a removal of an issue";
		splice (@{$data{bugList}}, $index, 1);	
	}
	
	store (\%data, $bugsDatabase);
	
	manageNavigation();
}

sub sendCrToCQ {
	my $session = shift;
	my $externalParams = shift;
	
	my ($CQFields,$data,$cfg, $bug);
	if($externalParams) {
		DEBUG "Using parameters provided externally";
		$data = $externalParams;
		$CQFields = $externalParams->{CQFields};
		$cfg = $externalParams->{config};
	}
	else {
		DEBUG "Using parameters provided by some database files";
		$CQFields = thaw($frozenCQFields);

		return 0 unless -r $bugsDatabase;
		$data = retrieve($bugsDatabase);
		$cfg = $Config;
	}
	
	$bug = pop(@{$data->{bugList}});
	return 0 unless $bug;
	my %bug = %$bug;
	INFO "No bug to send to ClearQuest" and return 0 unless defined $bug->{headline};

	INFO "Trying to send \"$bug->{headline}\"";
	
	my %bug_trans;
	foreach my $field (keys(%bug)) {
		DEBUG "Processing field '$field'";
		DEBUG "Skipped equivalence" and $bug_trans{$field} = $bug{$field} and next if($field eq "headline" or $field eq "description" or $field eq "product");
		my $newText = $CQFields->{$field}{equivTable}{$bug{$field}};
		$newText = $CQFields->{component}{equivTable}{$bug{sub_system}}{$bug{component}} if $field eq "component";
		if($newText) {
			DEBUG "Value '$bug{$field}' has been associated with '$newText'";
		}
		else {
			DEBUG "Value '$bug{$field}' has been associated with NULL value";
		}
		$bug_trans{$field} = $newText;
	}
	####################################
	
	DEBUG "Building session";
	$session = CQSession::Build() unless $session; 
	DEBUG "Connecting to database '$cfg->{clearquest_shared}->{database}'";
	$session->UserLogon ($cfg->{clearquest_shared}->{login}, $Clearquest_password, $cfg->{clearquest_shared}->{database}, "");
	DEBUG "Building entity";	
	my $rec = $session->BuildEntity("ChangeRequest");
	DEBUG "Retrieving identifier.";	
	my $identifier = $rec->GetDisplayName();
	
	DEBUG "Setting \"product\" to \"$bug_trans{product}\"";
	$rec->SetFieldValue('product', $bug_trans{product});
	
	DEBUG "Setting \"sub_system\" to \"$bug_trans{sub_system}\"";
	$rec->SetFieldValue('sub_system', $bug_trans{sub_system});
	
	my $final_state = 'Submitted - new';
	$final_state = $bug_trans{write_arrival_state} if($bug_trans{write_arrival_state});
	
	DEBUG "Setting \"write_arrival_state\" to \"$final_state\"";
	$rec->SetFieldValue('write_arrival_state', $final_state);
	
	while(my($field, $value) = each(%bug_trans)) {
		next if ($field eq 'product' or $field eq 'sub_system' or $field eq 'write_arrival_state'); # We can skip those because it is already selected
		$value = '' unless ($value); # If field is not defined, then it is equal to an empty string to avoid errors by Clearquest.
		DEBUG "Setting \"$field\" to \"$value\"";
		$rec->SetFieldValue($field, $value);
	}
	
	DEBUG "Request to validate filled fields";
	my $result = makeCQValidation($rec);
	
	DEBUG "Request to commit changes";
	$result = makeCQCommit($rec) if($result);
		
	if($result > 0) {
		INFO "Issue was inserted with identifier : $identifier";
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$year += 1900;
		$mon++;
		insertTextIntoLogfile($successTextFile, "$year/$mon/$mday - $hour:$min:$sec\t$identifier\t$bug_trans{headline}\n");
		store ($data, $bugsDatabase) unless $externalParams;
	}
	else {
		ERROR("Insertion of bug has failed for reason: $result");
		
		my $failedData = retrieve($failedBugsDatabase) if -r $failedBugsDatabase;
		push(@{$failedData->{bugList}}, $bug);
		
		my $write_result = store ($failedData, $failedBugsDatabase);
		store ($data, $bugsDatabase) if $write_result and not $externalParams;
	
		insertTextIntoLogfile($failedTextFile, "---------------------------------\nResult of insert: $result\n");
		while(my($field, $value) = each(%bug)) {
			DEBUG "$field : $value";
			insertTextIntoLogfile($failedTextFile, "$field : $value\n");
		}
		close FILE;
	}
	return $result;
}

sub insertTextIntoLogfile {
	my ($file, $text) = @_;
	if(open FILE, ">>$file") {
		print FILE "$text";
		close FILE;
	}
	else {
		ERROR "Opening of file $file failed in append mode";
	}
}

sub makeCQValidation {
	my $rec = shift;
	my $RetVal;
	
	DEBUG "Trying to validate $rec";
	eval { $RetVal = $rec->Validate(); };
	# EXCEPTION information is in $@ 
	# RetVal is either an empty string or contains a failure message string 
	if ($@){ 
		ERROR "Exception while validating: �$@�"; 
	}
	if ($RetVal eq "") {
		DEBUG "Clearquest validation passed successfully";

		return 1;
	}
	else {
		ERROR "Validation of bug has failed on Clearquest side for following reason(s) : $RetVal";
	}
	return 0;
}

sub makeCQCommit {
	my $record = shift;
	my $RetVal;
	
	DEBUG "Trying to commit $record";
	eval {$RetVal = $record->Commit(); };
	# EXCEPTION information is in $@ 
	# RetVal is either an empty string or contains a failure message string 
	if ($@){ 
		ERROR "Exception while commiting: �$@�"; 
		$record->Revert();
	}
	if ($RetVal eq "") {
		return 1;
	}
	else {
		ERROR "Commit of bug has failed on Clearquest side for following reason(s) : $RetVal";
		$record->Revert();
	}
	return 0;
}

sub fillInterfaceWithBug {
	my $bugToRetrieve = shift;
	my %data = %{retrieve($bugsDatabase)} if -r $bugsDatabase;

	my %tmpBug = %{$data{bugList}[$bugToRetrieve]};
	
	foreach my $key (keys(%bugDescription)) {
		$bugDescription{$key} = undef;
	}
	
	foreach my $key (keys(%tmpBug)) {
		$bugDescription{$key} = $tmpBug{$key};
	}
	
	$description->Contents($bugDescription{description});
	
	return;
}

sub manageNavigation {
	my $newIndex = shift;
	$totalNumberOfBugs = getNumberOfBugs(1);
	
	if($totalNumberOfBugs == 0) {
		$currentBugIndex = 0;
		switchActions() if $editMode;		
	}
	else {
		$currentBugIndex += $newIndex if $newIndex;
		$currentBugIndex = 0 if $currentBugIndex < 0;
		$currentBugIndex = $totalNumberOfBugs - 1 if $currentBugIndex >= $totalNumberOfBugs;
		
		$navigationlabelText = "Viewing issue ".($currentBugIndex+1)."/$totalNumberOfBugs";
		fillInterfaceWithBug($currentBugIndex);
		
		if(($currentBugIndex -1) < 0) { $buttonPrevious->configure(-state => "disabled"); }
		else { $buttonPrevious->configure(-state => "normal"); }
		
		if(($currentBugIndex +1) < $totalNumberOfBugs) { $buttonNext->configure(-state => "normal"); }
		else { $buttonNext->configure(-state => "disabled"); }	
	}
}

sub getNumberOfBugs {
	my $alterButtons = shift;
	my $nbrOfIssues = 0;
	return 0 unless -r $bugsDatabase;
	my %data = %{retrieve($bugsDatabase)};
	$nbrOfIssues = scalar(@{$data{bugList}}) if $data{bugList};
	
	return $nbrOfIssues unless $alterButtons;
	
	if($nbrOfIssues > 0) {
		$buttonSendAllNow->configure(-state => "normal");
		$buttonExport->configure(-state => "normal");
		$buttonSwitch->configure(-state => "normal");
	}
	else {
		$buttonSendAllNow->configure(-state => "disabled");
		$buttonExport->configure(-state => "disabled");
		$buttonSwitch->configure(-state => "disabled");
		switchActions() if $editMode;
	}
	
	return $nbrOfIssues;
}

##############################################
# Graphical oriented functions
##############################################
sub cancel {
	my $mw = shift;
	
	my $response = $mw->messageBox(-title => "Confirmation requested", -message => "Do you really want to quit this application?", -type => 'yesno', -icon => 'question');
	
	DEBUG "User has answered \"$response\" to cancellation question";
	return unless $response eq "Yes";
	INFO "User has requested a cancellation";
	$killThread = 1; # Ask thread to kill itself
	$Thread->detach(); 
	while($killThread == 1) { sleep 1; } # Wait that thread finishes.
	exit(1001);
}

sub switchActions {
	$editMode = ($editMode + 1) % 2;
	
	if($editMode) {
		DEBUG "Edit mode is selected";
		$bugDescription{description} = '' unless $bugDescription{description};
		%backupDescription = %bugDescription;
		$containerActions->packForget();
		$containerEdit->pack(-fill => 'both', -expand => 1);
		manageNavigation();

	}
	else {
		DEBUG "Action mode is selected";
		foreach my $key (keys(%bugDescription)) {
			unless (exists $backupDescription{$key}) { $bugDescription{$key} = ''; next;  }
			$bugDescription{$key} = $backupDescription{$key};
		}
		$description->Contents($bugDescription{description});
		$containerEdit->packForget();
		$containerActions->pack(-fill => 'both', -expand => 1);
	}
	return;
}

sub AddAndSendCr {
	my $bugref = shift;
	my $numberOfBugsToSend = shift;
	

	$buttonSendLater->configure(-state => "disabled");
	$buttonSendNow->configure(-state => "disabled");
	$buttonSendAllNow->configure(-state => "disabled");
	$buttonExport->configure(-state => "disabled");
	
	$numberOfBugsToSend = 0 unless($numberOfBugsToSend);
	my $problemDiscovered = 0;
	
	if($bugref) {
		DEBUG "Request to add an anomaly on database";
		$problemDiscovered = 1 unless validate();
		addBug($bugref) unless $problemDiscovered; # Check if bug is filled properly
	}
	
	my $nbrOfIssues = getNumberOfBugs();
	
	if($numberOfBugsToSend != 0 and not $problemDiscovered and $nbrOfIssues > 0) {
		$mw->messageBox(-title => "Information", -message => "There was nothing to send", -type => 'ok', -icon => 'info') unless $nbrOfIssues;
		my $nbrOfIssuesToInsert = $nbrOfIssues;
		$nbrOfIssuesToInsert = $numberOfBugsToSend if $numberOfBugsToSend >= 0;
		my $totalToInsert = $nbrOfIssuesToInsert;
		
		$mw->messageBox(-title => "Information", -message => "You will insert $totalToInsert issue(s) inside Clearquest database\nThere is actually $nbrOfIssues issues stored in database.", -type => 'ok', -icon => 'info');

		my $nbrOfBugsInserted = 0;
		my $nbrOfBugsFailed = 0;
		my $nbrTotalOfBugs  = 0;
		my $session;
		while($nbrOfIssuesToInsert > 0) {
			$nbrOfIssuesToInsert--;
			DEBUG "Sending bug [".($totalToInsert-$nbrOfIssuesToInsert)."/$totalToInsert]";
			
			$FunctionName = 'sendCrToCQ';
			@ArgumentsThread = ($session);
			$ThreadWorking = 1;
			
			DEBUG "Waiting that thread finishes its task...";
			while ($ThreadWorking == 1) {
				sleep 1;
				$mw->update;
			}
			
			DEBUG "Bug insertion has returned $ResultFunction as result";

			$nbrOfBugsInserted += 1 if $ResultFunction > 0;
			$nbrOfBugsFailed += 1 if $ResultFunction < 0;
			$nbrTotalOfBugs += 1;
		}

		$mw->messageBox(-title => "Information", -message => "$nbrOfBugsInserted anomalies has been registered inside Clearquest database", -type => 'ok', -icon => 'info') if $nbrOfBugsInserted;
		$mw->messageBox(-title => "Insertion error", -message => "$nbrOfBugsFailed anomalies were not inserted inside Clearquest database. \nPlease check logfile for details, and / or insert it yourself using FailedBugs.txt", -type => 'ok', -icon => 'error') if $nbrOfBugsFailed;
	}
	
	getNumberOfBugs(1);
	$buttonSendLater->configure(-state => "normal");
	$buttonSendNow->configure(-state => "normal");
}

sub addListBox {
	my $parentElement = shift;
	my $labelName = shift;
	my $CQ_Field = shift;
	my $necessityText = shift;
	my $labelDescription = shift;
	my $listToInsert = shift;
	
	my $newElement = $parentElement->JComboBox(-label => $labelName, -labelWidth => 15, -labelPack=>[-side=>'left'], -textvariable => \$bugDescription{$CQ_Field}, -choices => $listToInsert, -browsecmd => [\&analyseListboxes])->pack(-fill => 'x', -side => 'top', -anchor => 'center'); # -> pack(-fill => 'both', -expand => 1)
	$newElement->setSelected($bugDescription{$CQ_Field}) if $bugDescription{$CQ_Field};
	$balloon->attach($newElement, -msg => "<$necessityText> $labelDescription");
	push(@mandatoryFields, {Text => $labelName, CQ_Field => $CQ_Field}) if "$necessityText" ne OPTIONAL_FIELD_TEXT;
	
	return $newElement;
}

sub analyseListboxes {	
	my $backup = $bugDescription{component};
	if($bugDescription{sub_system} and $bugDescription{sub_system} ne $lastSelectedSubsystem) {
		if($CqFieldsDesc{component}{commentTable}{$bugDescription{sub_system}}) {
			changeList($listComponents, $CqFieldsDesc{component}{commentTable}{$bugDescription{sub_system}}, $backup);
		}
		else {
			my %tmp;
			changeList($listComponents, \%tmp, $backup);
		}
		$lastSelectedSubsystem = $bugDescription{sub_system};
	}
}

sub validate {
	$bugDescription{description} = $description->Contents;
	
	my $resultText = '';
	foreach my $item (@mandatoryFields) {
		$resultText .= "\n - $item->{Text} is not selected / defined" unless (defined($bugDescription{$item->{CQ_Field}}) and $bugDescription{$item->{CQ_Field}} =~ /\S/);
	}
	
	if ($resultText) {
		$mw->messageBox(-title => "Missing information(s)", -message => "Following information(s) are missing : $resultText", -type => 'ok', -icon => 'error');
		return 0;
	}
	else {
		return 1;
	}
	
}

sub addSearchableListBox {
	my $parentElement = shift;
	my $labelName = shift;
	my $CQ_Field = shift;
	my $necessityText = shift;
	my $labelDescription = shift;
	my $completeList = shift;

	my %completeList;
	if (ref $completeList eq "ARRAY") {
		foreach my $item (@$completeList) {
			$completeList{$item} = $item;
		}
	}
	elsif(ref $completeList eq "HASH") { %completeList = %$completeList; }
	
	my %item;
	my @list;

	my $oldValue = $bugDescription{$CQ_Field};
	$item{searchActivated} = 0;
	$item{selectedList} = \@list;
	$item{selection} = \$bugDescription{$CQ_Field};
	$item{mainFrame} = $parentElement->Frame()->pack(-side => 'top', -fill => 'x');
	$item{mainFrame}->Label(-text => $labelName, -width => 15 )->pack(-side => 'left');
	$item{searchButton} = $item{mainFrame}->Button(-text => 'Search', -command => sub { manageSearchBox(\%item) }, -state => 'disabled')->pack( -side => 'right' );
	$item{listbox} = $item{mainFrame}->JComboBox(-choices => $item{selectedList}, -textvariable => $item{selection}, -state => 'disabled')->pack(-fill => 'x', -side => 'left', -expand => 1);
	$item{searchFrame} = $item{mainFrame}->Frame();
	$item{searchDescription} = $item{searchFrame}->Label(-textvariable => \$item{searchText})->pack(-side => 'left');
	$item{searchFrame}->Entry(-validate => 'all', -textvariable => \$item{search}, -width => 15, -validatecommand => sub { my $search = shift; search(\%item, $search); return 1; } )->pack(-side => 'right');

	changeList(\%item, \%completeList, $oldValue) if %completeList;
	$balloon->attach($item{listbox}, -msg => "<$necessityText> $labelDescription");
	push(@mandatoryFields, {Text => $labelName, CQ_Field => $CQ_Field}) if "$necessityText" ne OPTIONAL_FIELD_TEXT;

	return \%item;
}

sub changeList {
	my $item = shift;
	my $completeList = shift;
	my $selection = shift;
	
	$item->{completeList} = $completeList;

	my @list = sort keys %$completeList;
	@{$item->{selectedList}} = @list;
	$item->{searchButton}->configure(-state => (scalar(@list))?'normal':'disabled');
	$item->{listbox}->configure(-state => (scalar(@list))?'normal':'disabled');

	
	DEBUG "Trying to set default value \"$selection\"" and $item->{listbox}->setSelected($selection) if $selection;
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
	my $old_selection = ${$searchListbox->{selection}};
	foreach my $item (keys %completeList) {
		next unless (not $search or $search eq '' or $item =~ /$search/i or $completeList{$item} =~ /$search/i);
		push (@tmpList, $item);
		push (@resultsText, " => $item --- $completeList{$item}");
	}
	my $nbrOfResults = scalar(@tmpList);
	@{$searchListbox->{selectedList}} = sort @tmpList;
	${$searchListbox->{selection}} = $old_selection if $old_selection;
	${$searchListbox->{selection}} = $tmpList[0] if $nbrOfResults == 1;

	$balloon->attach($searchListbox->{searchDescription}, -msg => join("\n", @resultsText));
	$searchListbox->{listbox}->configure(-state => $nbrOfResults ? 'normal' : 'disabled');
	$searchListbox->{searchText} = ($nbrOfResults ? ($nbrOfResults == 1 ? "1 result" : $nbrOfResults.' results' ) : 'No results');
	return 1;
}

##########################################################
# Database related functions
##########################################################
sub ExportEncryptedDb {
	 # Functional style

	my %data;
	%data = %{retrieve($bugsDatabase)} if -r $bugsDatabase;
	$data{config} = $Config;
	$data{CQFields} = thaw($frozenCQFields);
	
	my $data = freeze(\%data);
	
	my $hexCode = '';
	my $securityCode = '';
	for(my $i = 0; $i < 8; $i++) {
		my $char = (0..9, 'A'..'Z', 'a'..'z')[rand 62];
		$securityCode .= $char;
		$hexCode .= sprintf("%02lx", ord($char));
	}
	
	my $key = $hexCode x 2; # 128bit hex number
	
	my $length = 256 - (length($data) % 128);
	my $data_padded = $data.createPaddedData($securityCode, $length); 
	$data = rijndael_encrypt($key, MODE_CBC, $data_padded,  128, 128);
	
	open FILE,">$encryptedDatabase - $securityCode";
	binmode FILE;
	print FILE sprintf("%03i", $length).$data;
	close FILE;
	
	INFO "Database has been exported with security code '$securityCode'";
	$mw->messageBox(-title => "Informations", -message => "Database has been exported as \"$encryptedDatabase\"\nSecurity code is \"$securityCode\" (case sensitive). You will have to provide it in order to use exported database.", -type => 'ok', -icon => 'info');
}

sub importEncryptedDb {
	my $file = shift;
	my $password = shift;
	open FILE, $file or die;
	binmode FILE;
	my $length;
	read FILE, $length, 3;
	local $/ = undef;
	my $data = <FILE>;
	close FILE;

	ERROR "Password has not required size (8 characters)" and exit if length($password) != 8;
	my $hexCode = '';
	foreach my $char (split'', $password) {
		$hexCode .= sprintf("%02lx", ord($char));
	}
	
	my $key = $hexCode x 2; # 256bit hex number
	
	$data = rijndael_decrypt($key, MODE_CBC, $data, 128, 128);
	my $uncryptedData = createPaddedData($data, $length);
	$data = substr $data, 0, -$length;
	my $refpaddedData = createPaddedData($password, $length);

	if($refpaddedData eq $uncryptedData) {
		DEBUG "Uncryption seems to be sucessfull";
		$data = thaw($data);
		return $data;
	}
	else {
		ERROR "password is not the same";
		exit;
	}
}

sub createPaddedData {
	my $pattern = shift;
	my $length = shift;
	

	my $paddedData = $pattern;
	$paddedData .= $pattern while (length($paddedData) <= $length);
	
	$paddedData = substr ($paddedData, -$length);
	DEBUG "Created padded data with length ".length($paddedData);
	return $paddedData;
}

__END__
:waitDueToErrors
pause
:finishedCorrectly