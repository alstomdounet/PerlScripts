@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
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
use GraphicalCommon;
use ClearcaseMgt qw(getLabelListVOB setLabel renameElement checkoutElement getAttribute setAttribute isCheckedoutElement isPrivateElement uncheckoutElement checkinElement isLatest);
use Data::Dumper;
use File::Basename;
use File::Copy;
use Win32 qw(CSIDL_DESKTOPDIRECTORY);

use constant PROGRAM_VERSION => '1.0';

use constant {
	INVALID_DOCUMENT => 0,
	CHECKED_IN_DOCUMENT => 1,
	CHECKED_OUT_DOCUMENT => 2,
	MISSING_ATTR_DOCUMENT => 3,
};

use constant {
	IN_WORK => 0,
	PROOFREAD => 3,
	PROOFREAD_SIG => 4,
	APPROVAL => 7,
	APPROVAL_SIG => 8,
	STABLE => 10,
	CERTIFIED => 20,
	LAST_STEP => 99,
};

use constant {
	NO_SELECTION => 0,
	PROMOTE_DOC => 1,
	RESET_EVOL_DOC => 2,
	CHECKOUT_FOR_TAG_DOC => 3,
	CHECKOUT_FOR_EVOL_DOC => 4,
	UNCHECKOUT_DOC => 5,
	RENAME_DOC => 6,
	CHECKIN_DOC => 7,
	EVOL_DOC => 8,
	SET_VERSION_DOC => 9,
	EXPORT_DOC => 10,
};

my %levelsDescription;
$levelsDescription{+IN_WORK} = {"text" => "En rédaction", "nextLevel" => PROOFREAD};
#$levelsDescription{+TAGGING_NEEDED} = {"text" => "En taggage", "nextLevel" => PROOFREAD}; 
$levelsDescription{+PROOFREAD} = {"text" => "En vérification", "nextLevel" => PROOFREAD_SIG};
$levelsDescription{+PROOFREAD_SIG} = {"text" => "Modification pour\nSignature \"Vérifié\"", "nextLevel" => APPROVAL};
$levelsDescription{+APPROVAL} = {"text" => "En approbation", "nextLevel" => APPROVAL_SIG};
$levelsDescription{+APPROVAL_SIG} = {"text" => "Modification pour\nSignature \"Approuvé\"", "nextLevel" => STABLE};
$levelsDescription{+STABLE} = {"text" => "Approuvé", "nextLevel" => CERTIFIED};
$levelsDescription{+CERTIFIED} = {"text" => "Certifié", "nextLevel" => LAST_STEP};

INFO "Starting program (".PROGRAM_VERSION.")";
my %config = %{loadLocalConfig("config.xml", undef, ForceArray => qr/^labelName$/)}; # Loading / preprocessing of the configuration file
my $OFFLINE_MODE = $config{offlineMode}->{isActive};

my $currentDocument = $ARGV[0];
INFO "OFFLINE MODE IS ACTIVE" and $currentDocument = $config{offlineMode}->{fileToUse} if $OFFLINE_MODE;
LOGDIE "Program needs an argument." unless $currentDocument;
LOGDIE "Argument used has to be an existing and readable file. Argument is actually \"$currentDocument\"" unless -e $currentDocument and -f $currentDocument;

##########################################
# Building Canvas
##########################################
my ($canvas,$canvVersion, $text_ptr, $commentFrame, $description);
my $width = 160;
my $height  = 45;
my $offset_x = 50;
my $offset_y = 50;
my $squareSize = 50;
my $space_btw_versions = 50;
my $spaces_btw_steps = $height + ($height/3);
my $width_arc = ($height/3);
my %offset;
my %documentDescription;
my $displayFrame;
my $labelFrame;
my $editMode = 0;
my $programState = INVALID_DOCUMENT;
my $originalText = "Laquelle des actions suivantes voulez-vous effectuer?";
my $subtitleText = $originalText;
my $currentAction = NO_SELECTION;
my $selectedEvolution = 0;

my @properties = fileparse($currentDocument);
$documentDescription{completeName} = $currentDocument;
$documentDescription{suffix} = $properties[2];
$documentDescription{name} = $properties[0];
$documentDescription{newName} = $documentDescription{name};
$documentDescription{path} = $properties[1];
$documentDescription{labelToApply} = undef;

chdir($documentDescription{path});

if($OFFLINE_MODE) {
	$documentDescription{currentLevel} = $config{offlineMode}->{currentLevel};
	$programState = $config{offlineMode}->{programState};
	$documentDescription{currentVersion} = $config{offlineMode}->{currentVersion};
	$documentDescription{currentVersion} = undef if ref $config{offlineMode}->{currentVersion} eq "HASH";
} else {
	LOGDIE "This program doesn't currently handles private files." if isPrivateElement($currentDocument);
	$programState = CHECKED_IN_DOCUMENT;
	$documentDescription{currentLevel} = getDocumentLevel($currentDocument);
	$documentDescription{currentVersion} = getDocumentVersion($currentDocument);
	$programState = CHECKED_OUT_DOCUMENT if isCheckedoutElement($currentDocument);
}
$programState = MISSING_ATTR_DOCUMENT unless $documentDescription{currentVersion};
$documentDescription{currentVersion} = "" unless $documentDescription{currentVersion};
$documentDescription{targetVersion} = $documentDescription{currentVersion};
$documentDescription{targetLevel} = $documentDescription{currentLevel};

$documentDescription{docInCheckout} = 0;
$documentDescription{currentLevelText} = getLevelAsText($documentDescription{currentLevel});
$documentDescription{nextLevel} = getNextDocumentLevel($documentDescription{currentLevel});
$documentDescription{nextLevelText} = getLevelAsText($documentDescription{nextLevel});
$documentDescription{initLevel} = 0;
$documentDescription{initLevelText} = getLevelAsText($documentDescription{initLevel});

##########################################
# Building graphical interface
##########################################
# Generic configuration
use Tk;
use Tk::Balloon;

Tk::CmdLine::SetResources(  # set multiple resources
	[ 	'*Button*relief: groove',
		'*Text*relief: groove',
		'*Entry*relief: groove',
		'*RadioButton*relief: groove',
		'*Button*background: grey'
	]
);

DEBUG "Building graphical interface";

my $mw = MainWindow->new(-title => "Interface de gestion de la documentation");
$mw->withdraw; # disable immediate display
$mw->minsize(540,450);
$mw->maxsize(540,450); 

my $balloon = $mw->Balloon();
my @fillOptions = (-fill => 'both', -expand => 1);
my @centerProperties = (-side => 'top', -fill => 'both', -expand => 1);
my @displayedItems;

# Generic panels
my $topPanel = $mw->Frame()->pack(-pady => 10);
my $centerPanel = $mw->Frame()->pack(@centerProperties);

my $bottomPanel = $mw->Frame() ->pack(-ipady => 10, -side => 'bottom', -fill => 'x');

# Building Top panel
$topPanel->Label( -textvariable => \$subtitleText)->pack();

# Building center panel
my $leftPanel = $centerPanel->Frame()->pack(-side => 'left');
my $frm_choice = $centerPanel->Frame()->pack(-side => 'right');

# Building bottom panel

my $cancelButton = $bottomPanel->Button(-text => 'Quitter', -command => sub { confirm(-1, \%documentDescription)}) -> pack(-side => 'left', @fillOptions);
$bottomPanel->Button(-text => 'Valider' , -command => sub { confirm($currentAction, \%documentDescription)}) -> pack(-side => 'right', @fillOptions);

if($programState != MISSING_ATTR_DOCUMENT) {
	# Building left panel (filled with canvas)
	$canvas = createCanvas($leftPanel);

	@properties = ('-', -sticky => 'nsw', -ipady => 10, -ipadx => 20);
	$displayFrame = $mw->Frame();
	my $leftdisplayFrame = $displayFrame->Frame()->pack(-side => 'left');
	($canvVersion, $text_ptr) = createVersionBox($leftdisplayFrame, 50, 50, $documentDescription{currentVersion} , '??');
	my $rightdisplayFrame = $displayFrame->Frame()->pack(-side => 'right', -fill => 'x', -expand => 1);

	my $futureMajorVersion = incrementVersion($documentDescription{currentVersion}, 1, 0);
	my $futureMinorVersion = incrementVersion($documentDescription{currentVersion}, 0, 1);
	$rightdisplayFrame->Label(-text => "Vous voulez faire évoluer :", -font => 'arial 9 underline')->grid(@properties);
		$balloon->attach($rightdisplayFrame->Radiobutton(-text => "l'indice majeur", -variable => \$selectedEvolution, -value => $futureMajorVersion, -command => sub {changefinalText($canvVersion, $text_ptr, $selectedEvolution)})->grid(@properties),
		-msg => "On doit faire évoluer l'indice majeur si une livraison officielle a été faite");
	
		$balloon->attach($rightdisplayFrame->Radiobutton(-text => "l'indice mineur", -variable => \$selectedEvolution, -value => $futureMinorVersion, -command => sub {changefinalText($canvVersion, $text_ptr, $selectedEvolution)})->grid(@properties),
		-msg => "L'indice mineur évolue tant que le document n'est pas dans un état \"stable\"");
}

my $state = 'normal';
if($programState == CHECKED_IN_DOCUMENT) {
	my ($isLatest, $checkedOutByOther, @labelList);
	if($OFFLINE_MODE) {
		$isLatest = $config{offlineMode}->{isLatest};
		$checkedOutByOther = $config{offlineMode}->{checkedOutByOther};
		@labelList = @{$config{offlineMode}->{labelList}->{labelName}};
	} else {
		$isLatest = isLatest($documentDescription{completeName});
		@labelList = @{getLabelListVOB($currentDocument)} if($documentDescription{nextLevel} == STABLE);
		WARN "It is not currently possible to check if element is checked-out by another one." ; $checkedOutByOther = 0;
	}
	WARN "Any action altering document state are available, because it is not latest version" and $mw->messageBox(-title => "Avertissement", -message => "Il n'est pas possible de modifier les états de ce document.\n\nRaison:\n - le document visualisé n'est pas la dernière version.", -type => 'ok', -icon => 'warning') unless $isLatest;
	WARN "This element cannot be modified, because it was checked-out by another person / view" if $checkedOutByOther;
	
	if($documentDescription{nextLevel} == STABLE) {
		$labelFrame = $mw->Frame();
		
		if($config{labelFilter}) {
			@labelList = grep (/$config{labelFilter}/, @labelList);
		}
		@labelList = reverse sort @labelList;
		addListBox ($labelFrame, "Label:", \@labelList, \$documentDescription{labelToApply});
	}
	
	@properties = ('-', -sticky => 'nsw', -ipady => 8, -ipadx => 20);
	$frm_choice->Label(-text => "Je dois faire évoluer ce document:", -font => 'arial 9 underline')->grid(@properties);
	
	$state = 'disabled' if $documentDescription{nextLevel} == LAST_STEP or not $isLatest;
	my $text = 'Promouvoir ce document';
	$balloon->attach($frm_choice->Radiobutton(-text => $text, -variable => \$currentAction, -value => PROMOTE_DOC, -command => sub {selectionChanged($currentAction)}, -state => $state)->grid(@properties),
		-msg => "Cette action fait évoluer le document d'une étape dans le cycle de vie documentaire.\n\nA l'issue de cette action, il est interdit de modifier le document, sauf pour mettre à jour la table des matière documentaire.");
		
	$state = 'normal';
	$state = 'disabled' if $documentDescription{currentLevel} == IN_WORK or not $isLatest;
	$balloon->attach($frm_choice->Radiobutton(-text => 'Déclasser ce document', -variable => \$currentAction, -value => RESET_EVOL_DOC, -command => sub {selectionChanged($currentAction)}, -state => $state)->grid(@properties),
		-msg => "Cette action remet le document au début du cycle de vie documentaire.\nCeci arrive quand le document n'a pas réussi à passer la relecture / la certification.\n\nA l'issue de cette action, il n'est pas possible de modifier le document.");
	
	$frm_choice->Label(-text => "J'ai besoin d'effectuer une modification:", -font => 'arial 9 underline')->grid(@properties);
	$state = 'normal';
	$state = 'disabled' if not $isLatest;
	$balloon->attach($frm_choice->Radiobutton(-text => 'Tagger ce document', -variable => \$currentAction, -value => CHECKOUT_FOR_TAG_DOC, -command => sub {selectionChanged($currentAction)}, -state => $state)->grid(@properties),
		-msg => "Cette action n'est accessible que si le document doit être taggé.\n\nLe document devient modifiable, mais uniquement pour effectuer cette opération.");
	
	
	$balloon->attach($frm_choice->Radiobutton(-text => 'Réaliser une évolution', -variable => \$currentAction, -value => CHECKOUT_FOR_EVOL_DOC, -command => sub {selectionChanged($currentAction)}, -state => ($isLatest) ? 'normal' : 'disabled')->grid(@properties),
		-msg => "Cette action permet de modifier le document afin de réaliser une / des évolutions.\n\nLe document devient modifiable, mais reprends également le cycle de vie documentaire du début,\net requiert de faire évoluer l’indice du document.");
	
	$state = 'normal';
	$state = 'disabled' if $documentDescription{currentLevel} != IN_WORK or not $isLatest;
	$balloon->attach($frm_choice->Radiobutton(-text => 'Continuer à travailler sur la version en cours', -variable => \$currentAction, -value => EVOL_DOC, -command => sub {selectionChanged($currentAction)}, -state => $state)->grid(@properties),
		-msg => "Cette action permet de continuer à modifier le document afin de réaliser une / des évolutions.\n\nLe document devient modifiable.");
	
	$frm_choice->Label(-text => "Autres actions disponibles:", -font => 'arial 9 underline')->grid(@properties);
	
	$balloon->attach($frm_choice->Radiobutton(-text => 'Exporter ce document', -variable => \$currentAction, -value => EXPORT_DOC, -command => sub {selectionChanged($currentAction)})->grid(@properties),
		-msg => "Cette action permet d'exporter le document sous un nom contenant l'indice du document.\nCeci aura pour effet de créer une version localement, répertoire courant (pas de modifications en gestion de configuration).");
	
}
elsif ($programState == CHECKED_OUT_DOCUMENT) {
	@properties = ('-', -sticky => 'nsw', -ipady => 20, -ipadx => 20);
	$frm_choice->Label(-text => "Voici les actions disponibles:", -font => 'arial 9 underline')->grid(@properties);
	$balloon->attach($frm_choice->Radiobutton(-text => 'Annuler les modifications effectuées', -variable => \$currentAction, -value => UNCHECKOUT_DOC, -command => sub {selectionChanged($currentAction)})->grid(@properties),
		-msg => "Cette action annule toutes les modifications effectuées sur le document, depuis la dernière édition.");
	
	$balloon->attach($frm_choice->Radiobutton(-text => "Changer la version du fichier", -variable => \$currentAction, -value => RENAME_DOC, -command => sub {selectionChanged($currentAction)})->grid(@properties),
		-msg => "Cette action permet changer la version du document.\nCette action permet de continuer à modifier l'édition du document, mais reprends également le cycle de vie documentaire du début.");
	
	$balloon->attach($frm_choice->Radiobutton(-text => "Accepter les modifications", -variable => \$currentAction, -value => CHECKIN_DOC, -command => sub {selectionChanged($currentAction)})->grid(@properties),
		-msg => "Cette action permet d'enregistrer les modifications sur le serveur.");
	$currentAction = PROMOTE_DOC;
	
	$commentFrame = $mw->Frame(-padx => 10, -pady => 10);
	$commentFrame->Label(-text => "Entrez ci-dessous un commentaire pour la modification :", -font => 'arial 9 underline')->pack(-expand => 1, -fill => 'x');

	$description = $commentFrame->Scrolled("Text", -scrollbars => 'osoe', -padx => 5, -pady => 3) -> pack(-expand => 1, -fill => 'both');
		$balloon->attach($description, -msg => "La description exhaustive de la modification effectuée.");
}
elsif ($programState == MISSING_ATTR_DOCUMENT) {
	$mw->minsize(540,250);
	$mw->maxsize(540,250); 
	$subtitleText  = "Vous êtes actuellement en train d'éditer le document suivant:\n$documentDescription{name}\n\nCe document n'a pas de numéro de version valide, il est donc nécessaire d'en entrer un maintenant.";
	
	$displayFrame = $centerPanel->Frame()->pack();
	$displayFrame->Label(-text => "Entrez ci-dessous la version :", -font => 'arial 9 underline')->pack( -side => 'top', -fill => 'x', -ipady => 20);
	$balloon->attach($displayFrame->Entry(-textvariable => \$documentDescription{targetVersion}, -width => 4, -justify => 'center')->pack(-padx => 20, -ipady => 5, -side => 'top',-fill => 'x'), 
		-msg => "Version du fichier, sous la forme XY (ou X est une lettre majuscule et Y un chiffre)");
	$currentAction = SET_VERSION_DOC;
}
else {
	LOGDIE "File is in an insupported state";
}

INFO "displaying graphical interface";
$mw->Popup; # window appears screen-centered
MainLoop();
exit(1001);

##############################################
# Graphical oriented functions
##############################################
sub selectionChanged {
	my $actionSelected = shift;
	
	destroyItems($canvas, @displayedItems);
	@displayedItems = drawChangeOfStep($canvas, $documentDescription{currentLevel}, $documentDescription{nextLevel}) if $actionSelected == 1;
	@displayedItems = drawChangeOfStep($canvas, $documentDescription{currentLevel}, $documentDescription{initLevel}) if $actionSelected == 2;
	
	if($actionSelected == CHECKOUT_FOR_EVOL_DOC or $actionSelected == RENAME_DOC) {
		$subtitleText = "Vous avez demandé à réaliser une évolution de document.\nPar conséquent, il est nécessaire d'en modifier l'indice."; 
		$mw->minsize(540,250);
		$mw->maxsize(540,250); 
		$selectedEvolution = '??';
		changefinalText($canvVersion, $text_ptr, $selectedEvolution);
		$editMode = 1;	
		$centerPanel->packForget;
		$displayFrame->pack(@centerProperties);
		$cancelButton->configure(-text => "Retour");
	}
	elsif($actionSelected == PROMOTE_DOC and $documentDescription{nextLevel} == STABLE) {
		$subtitleText  = "Afin d'identifier dans quelle version sera livrée ce document, il est nécessaire de renseigner\nle champ \"Label\" ci-dessous afin de spécifier pour quelle version logicielle ce document est applicable.";
		$mw->minsize(540,250);
		$mw->maxsize(540,250); 
		$centerPanel->packForget;
		$labelFrame->pack(@centerProperties);
		$editMode = 1;	
		$cancelButton->configure(-text => "Retour");
	}
	elsif($actionSelected == CHECKIN_DOC) {
		$editMode = 1;	
		$subtitleText = "Vous avez demandé à enreigstrer ce document.\nPar conséquent, il est nécessaire d'y ajouter un commentaire."; 
		$mw->minsize(540,250);
		$mw->maxsize(540,250); 
		$description->Contents("Taggage du document") if $documentDescription{currentLevel} == 2;
		$centerPanel->packForget;
		$commentFrame->pack(@centerProperties);
		$cancelButton->configure(-text => "Retour");
	}
	else {
		$editMode = 0;
		$subtitleText = $originalText;
		$documentDescription{labelToApply} = '';
		$mw->minsize(540,450);
		$mw->maxsize(540,450); 
		DEBUG "Init of target version (from \"$documentDescription{targetVersion}\" to \"$documentDescription{currentVersion}\")" and $documentDescription{targetVersion} = $documentDescription{currentVersion};
		$displayFrame->packForget if $displayFrame;
		$labelFrame->packForget if $labelFrame;
		$commentFrame->packForget if $commentFrame;
		$centerPanel->pack(@centerProperties);
		$description->Contents('') if $description;
		$cancelButton->configure(-text => "Quitter");
	}
}

sub confirm {
	my $action = shift;
	my $document = shift;
	
	DEBUG "requested action is $action";
	
	my $title = 'Demande de confirmation';
	my $message;
	my $iconStyle = 'question';
	
	if ($action == -1) {
		# Request to modify a filename
		if($editMode) {
			DEBUG "Request return from a Version change edition";
			$currentAction = 0;
			selectionChanged($currentAction);
			return;
		}
		else {
			$message = "Voulez-vous quitter cette interface?";
		}
	}
	elsif ($action == PROMOTE_DOC) {
		$document->{targetLevel} = $document->{nextLevel};
		if($document->{targetLevel} == STABLE and not $document->{labelToApply}) {
			$message = "Il est recommandé de définir un label sur ce document.\nVoulez-vous promouvoir le document à l'état \"$document->{nextLevelText}\"?";
			$iconStyle = 'warning';
		}
		else { $message = "Voulez-vous promouvoir le document à l'état \"$document->{nextLevelText}\"?"; }
	}
	elsif ($action == RESET_EVOL_DOC) {
		$document->{targetLevel} = $document->{initLevel};
		$message = "Voulez-vous rétrograder le document à l'état \"$document->{initLevelText}\"?";
	}
	elsif ($action == EVOL_DOC) {
		$message = "Les seules éditions autorisées  un document.\nEst-ce bien l'usage que vous voulez en faire?";
	}
	elsif ($action == CHECKOUT_FOR_EVOL_DOC) { 
		LOGDIE "This situation should never happen." unless($editMode);
		if($document->{currentVersion} eq $document->{targetVersion}) {
			$mw->messageBox(-title => "Erreur durant l'opération", -message => "L'opération n'a pas eu lieu, parce qu'il est nécessaire que le fichier change d'indice.", -type => 'ok', -icon => 'error');
			return;
		}
		$document->{targetLevel} = $document->{initLevel};

		$message = "Voulez-vous effectuer une modification / évolution nécessitant un changement d'indice?";
	}
	elsif ($action == UNCHECKOUT_DOC) { 
		$message = "TOUTES LES MODIFICATIONS EFFECTUEES DANS CE DOCUMENT SERONT PERDUES!\n\n\Êtes-vous sûr de vouloir annuler les modifications effectuées?";
	}
	elsif ($action == CHECKIN_DOC) { 
		if($description->Contents =~ /^\s*$/) {
			$mw->messageBox(-title => "Erreur durant l'opération", -message => "Il est nécessaire d'ajouter un commentaire.", -type => 'ok', -icon => 'error');
			return;
		}
	
		$message = "Le fichier et toutes ses modifications seront enregistrées sur le serveur. Êtes-vous sûr de vouloir les enregistrer?";
	}
	elsif ($action == EVOL_DOC) {
		$message = "Voulez-vous effectuer une modification / évolution sur ce document?";
	}
	elsif ($action == SET_VERSION_DOC or $action == RENAME_DOC) {
		if ($document->{targetVersion} =~ /^[A-Z]\d$/) {
			$message = "Voulez-vous attribuer la version \"$document->{targetVersion}\" à ce document?";
		}
		else {
			$mw->messageBox(-title => "Erreur durant l'opération", -message => "Le numéro de version n'a pas la forme requise.", -type => 'ok', -icon => 'error');
			$document->{targetVersion} = $document->{currentVersion};
			$document->{targetLevel} = $document->{initLevel};
			return;
		}
	}
	elsif($action == EXPORT_DOC) {
		$message = "Voulez-vous créer une copie locale de ce document?\n\nATTENTION: Ce fichier sera crée sur votre bureau.";
	}
	else { return; }
	
	my $answer = $mw->messageBox(-title => $title, -message => $message, -type => 'yesno', -icon => $iconStyle);
	
	DEBUG "User has answered \"$answer\" to confirmation question";
	return unless $answer eq "Yes";
	DEBUG "User has requested a confirmation of this action";
	
	my $result = 1;
	exit(1001) if($action == -1);
	
	DEBUG "Normally a change of version will be requested (from $document->{currentVersion} to $document->{targetVersion})" if ($document->{targetVersion} ne $document->{currentVersion});
	DEBUG "Normally a change of level will be requested (from $document->{currentLevel} to $document->{targetLevel})" if ($document->{targetLevel} ne $document->{currentLevel});
	
	# Preprocessing
	$result = checkoutElement($document->{completeName}, "Modification du document pour évolution.") if not $OFFLINE_MODE and ($action == CHECKOUT_FOR_EVOL_DOC or $action == EVOL_DOC);
	$result = checkoutElement($document->{completeName}, "Taggage du document.") if not $OFFLINE_MODE and $action == CHECKOUT_FOR_TAG_DOC;
	
	my $infoMessage =  "L'opération s'est déroulée correctement.";
	my $errorMessage =  "L'opération n'a pas eu lieu correctement.\nConsulter et conserver le fichier log pour analyser le problème rencontré.";
	if ($action == EXPORT_DOC) {
		INFO "Request to export document \"$document->{name}\"";
		
		if($document->{name} =~ m/^((?:BAD\d{10})|(?:B\d{9}))(.*)$/) {
			my $fileMaturity = "";
			$fileMaturity = ' - DRAFT' if $document->{currentLevel} == IN_WORK;
			#$fileMaturity = ' - TAGGING' if $document->{currentLevel} == TAGGING_NEEDED;
			$fileMaturity = ' - PROOFREAD' if $document->{currentLevel} == PROOFREAD;
			
			my $newName = $1.'_'.$document->{currentVersion}."$2".$fileMaturity.$document->{suffix};

			my $newFilename = Win32::GetFolderPath(CSIDL_DESKTOPDIRECTORY).'\\'.$newName;
			
			DEBUG "Exported name is \"$newFilename\"";
			if(-f $newFilename) {
				ERROR "File \"$newName\" already exists";
				$result = 0;
				$errorMessage = "Le fichier \"$newName\" existe déjà sur le bureau";
			}
			else {
				$result = copy($document->{completeName}, $newFilename);
				ERROR "An error occured while copying file : $!" unless $result;
				$infoMessage = "Le fichier \"$newName\" a été créé sur votre bureau." if $result;
			}
		}
		else {
			ERROR "Document is not compliant with FLO rules";
			$errorMessage = "Le document à exporter doit impérativement commencer par:\nBADxxxxxxxxxxxx ou Bxxxxxxxxx (un 'x' égale un chiffre)";
			$result = 0;
		}
	}
	elsif ($action == UNCHECKOUT_DOC) {
		INFO "Request to cancel all modifications";
		$result = uncheckoutElement($document->{completeName});
	}
	elsif ($action == CHECKIN_DOC) {
		INFO "Request to put file in checkin";
		$result = checkinElement($document->{completeName}, $description->Contents);
	}
	elsif ($action == PROMOTE_DOC or $action == RESET_EVOL_DOC or $action == CHECKOUT_FOR_TAG_DOC or $action == CHECKOUT_FOR_EVOL_DOC or $action == EVOL_DOC or $action == SET_VERSION_DOC or $action == RENAME_DOC) {
		if($action == PROMOTE_DOC and $document->{targetLevel} == STABLE) {
			if($document->{labelToApply}) {
				DEBUG "Trying to set label \"$document->{labelToApply}\"";
				$result = setLabel($document->{completeName}, $document->{labelToApply}, undef, 1) if $result;
			}
			else {
				WARN "Label has to be applied in order to maintain traceability.";
			}
		}
	
		DEBUG "Asking to migrate attributes (Level : \"$document->{targetLevel}\" and Version : \"$document->{targetVersion}\")";
		$result = setAndMigrateAttributes($document->{completeName}, $document->{targetLevel}, $document->{targetVersion}) if not $OFFLINE_MODE and $result;
		

	}
	else {
		LOGDIE "No operations asked";
	}
	
	INFO "Requested action was done correctly" and $mw->messageBox(-title => "Confirmation", -message => $infoMessage, -type => 'ok', -icon => 'info') and exit(1001) if($result);
	ERROR "Requested action was not performed correctly" and $mw->messageBox(-title => "Erreur durant l'opération", -message => $errorMessage, -type => 'ok', -icon => 'error');
}

sub setAndMigrateAttributes {
	my $document = shift;
	my $requestedLevel = shift;
	my $requestedVersion = shift;
	
	LOGDIE "Level you want to select (\"$requestedLevel\") is invalid" unless isValidLevel($requestedLevel);
	LOGDIE "Version you want to select (\"$requestedVersion\") is invalid" unless $requestedVersion =~ /^[A-Z]\d$/;
	my $result1 = 1;
	my $result2 = 1;
	my $state = getAttribute($document, 'State');
	$state = "" if not $state;
	if ($state ne "$requestedLevel") {
		$result1 = setAttribute($document, 'State', $requestedLevel);
		DEBUG "Document Level has been changed correctly to \"$requestedLevel\"" if $result1;
	}
	my $version = getAttribute($document, 'Version');
	$version = "" if not $version;
	if ($version ne "$requestedVersion") {
		$result2 = setAttribute($document, 'Version', $requestedVersion);
		DEBUG "Document Version has been changed correctly to \"$requestedVersion\"" if $result2;
	}
	
	INFO "Attributes Level and Version has been applied" and return 1 if $result1 and $result2;
	return 0;
}

sub setDocumentLevel {
	my $document = shift;
	my $level = shift;
	
	# Checking that level we want to set exists
	LOGDIE "Obsolete function";
}

sub getDocumentLevel {
	my $document = shift;
	my $version = shift;

	LOGDIE "File \"$document\" has not been found" unless -e $document;
	
	my $result = getAttribute($document, 'State', $version);
	$result = 0 if not $result or $result eq "";

	LOGDIE "Retrieved level is not valid (value is \"$result\")" unless isValidLevel($result);
	DEBUG "Level of document is: $result (".getLevelAsText($result).")";
	return $result;
}

sub isValidLevel {
	my $level = shift;
	
	return 1 if exists $levelsDescription{$level};
	return 0;
}

sub getDocumentVersion {
	my $document = shift;
	my $version = shift;

	my $result = getAttribute($document, 'Version', $version);
	
	$result = "" if not $result;
	DEBUG "Document version is \"$result\".";
	return $result;
}

sub setDocumentVersion {
	my $document = shift;
	my $version = shift;
	
	LOGDIE "Obsolete function";
}

sub getLevelAsText {
	my $level = shift;
	return undef if $level == LAST_STEP;
	LOGDIE "Attribute \"$level\" was not found." unless $levelsDescription{$level};
	return  $levelsDescription{$level}{text};
}

sub getNextDocumentLevel {
	my $level = shift;
	LOGDIE "Attribute \"$level\" was not found." unless $levelsDescription{$level};
	return  $levelsDescription{$level}{nextLevel};
}

################################################################

sub createCanvas {
	my $frame = shift;
	
	my $canvas = $frame->Canvas(-width => $width + $width_arc+ $offset_x*2, -height => (scalar(keys(%levelsDescription)) - 1)*$spaces_btw_steps + $height + $offset_y*2 - 30, -background=>'white')->pack();
	my $documentName = $documentDescription{name};
	$documentName = substr($documentName, 0, 37).'...' if length($documentName) > 38;
	$canvas->createText(12 , 12 , -text => "Nom : $documentName", -anchor => 'w');
	$canvas->createText(12 , 28 , -text => "Indice actuel : $documentDescription{currentVersion}", -anchor => 'w');
	
	my $currentPosition = 0;
	foreach my $currentLevel (sort {$a <=> $b} keys(%levelsDescription)) {
		$offset{$currentLevel} = $currentPosition;
	
		my $text  = getLevelAsText($currentLevel);
	
		my $color = 'orange';
		$color = 'green' if $documentDescription{currentLevel} >= STABLE;
		$color = 'grey' if $documentDescription{currentLevel} != $currentLevel;
	
		createStep($canvas, 'Oval', $offset_x, ($currentPosition*$spaces_btw_steps) + $offset_y, $width, $height, $text, $color);
	
		last if(getNextDocumentLevel($currentLevel) == LAST_STEP);
	
		$canvas->createLine(
			$offset_x + $width/2, 
			($currentPosition*$spaces_btw_steps) + $offset_y + $height,
			$offset_x + $width/2, 
			($currentPosition*$spaces_btw_steps) + $offset_y + $spaces_btw_steps,
			-arrow => 'last', -fill => 'grey');
	
		$currentPosition++;
	}
	return $canvas;
}

sub drawChangeOfStep {
	my $c = shift;
	my $currentLevel = shift;
	my $finalLevel = shift;
	
	my @elements;
	
	my $p1_x = $width + $offset_x;
	my $p1_y = $offset_y + $height/2 + ($offset{$currentLevel}*$spaces_btw_steps);
	my $p2_x = $width + $offset_x + $width_arc;
	my $p2_y = $offset_y + $height/2 + ($offset{$finalLevel}*$spaces_btw_steps);
	
	push @elements, $c->createLine(
		$p1_x,
		$p1_y, 
		$p2_x, 
		$p1_y,
		$p2_x,
		$p2_y,
		$p1_x,
		$p2_y, 
		-width => 2, -arrow => 'last'
		);
	
	push @elements, createStep($c, 'final', $offset_x, ($offset{$finalLevel}*$spaces_btw_steps) + $offset_y, $width, $height, getLevelAsText($finalLevel), 'grey');
		
	return @elements;
}

sub createStep {
	my $c = shift;
	my $type = shift;
	my $pos_x = shift;
	my $pos_y = shift;
	my $width = shift;
	my $height = shift;
	my $text = shift;
	my $color = shift;
	
	my @arguments = ($pos_x, $pos_y, $pos_x + $width, $pos_y + $height,	-fill => $color);
	my $step;
	unless($type eq 'final') {
		$step = $c->createOval(@arguments);
	}
	else {
		$step = $c->createOval(@arguments, -width => 2);
	}
	$text = $c->createText($pos_x + $width/2 , $pos_y + $height/2 , -text => $text , -anchor=>'center', -justify =>'center');
	return ($step, $text);
}

sub destroyItems {
	my $c = shift;
	$c->delete(@_);
}

sub createVersionBox {
	my $frame = shift;
	my $offset_x = shift;
	my $offset_y = shift;
	my $initVersion = shift;
	my $finalVersion = shift;
	
	my $canvas = $frame->Canvas(-width => $squareSize*2 + $space_btw_versions + $offset_x*2, -height => $squareSize + $offset_y*2, -background=>'white')->pack();

	$canvas->createLine(
		$offset_x + $squareSize, 
		$offset_y + $squareSize/2,
		$offset_x + $squareSize+ $space_btw_versions, 
		$offset_y + $squareSize/2,
		-arrow => 'last', -fill => 'black');
		
	_createVersionBox($canvas, $offset_x, $offset_y, $squareSize, $initVersion, 'orange');

	my $text_ptr = _createVersionBox($canvas, $offset_x + $squareSize + $space_btw_versions, $offset_y, $squareSize, '??', 'orange');
	return ($canvas, $text_ptr);
}

sub _createVersionBox {
	my $c = shift;
	my $pos_x = shift;
	my $pos_y = shift;
	my $squareSize = shift;
	my $text = shift;
	my $color = shift;
	
	my @arguments = ($pos_x, $pos_y, $pos_x + $squareSize, $pos_y + $squareSize, -fill => $color);
	my $step = $c->createRectangle(@arguments);
	return $c->createText($pos_x + $squareSize/2 , $pos_y + $squareSize/2 , -text => $text, -font => 'arial 18', -anchor=>'center', -justify =>'center');
}

sub changefinalText {
	my $c = shift;
	my $id = shift;
	my $text = shift;
	
	$documentDescription{targetVersion} = $text;
	$c->itemconfigure($id, -text => $text);
}

sub incrementVersion {
	my $version = shift;
	my $incrementMajor = shift;
	my $incrementMinor = shift;
	
	my $finalVersion;
	if($version =~ /^([A-Z])(\d)$/) {
		my $majorVersion = $1;
		my $minorVersion = $2;
		
		DEBUG "Incremented major version" and $majorVersion++ and return "${majorVersion}0" if $incrementMajor;
		DEBUG "Incremented minor version" and $minorVersion++ if $incrementMinor;
		return "$majorVersion$minorVersion";
	}
	else {
		LOGDIE("Version \"$version\" doesn't match a valid version");
	}
}

__END__
:waitDueToErrors
pause
:finishedCorrectly