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
use ClearcaseMgt qw(addToSource checkoutElement isCheckedoutElement isPrivateElement uncheckoutElement checkinElement);
use Data::Dumper;
use File::Basename;
use File::Copy;
use Cwd;
use Switch;
use Win32 qw(CSIDL_DESKTOPDIRECTORY);

use constant PROGRAM_VERSION => '0.6';

use constant {
	OPERATION_RECURSIVE_CHECKIN => '-rec_ci',
	OPERATION_RECURSIVE_CHECKOUT => '-rec_co',
	OPERATION_RECURSIVE_UNCHECKOUT => '-rec_uco',
	OPERATION_RECURSIVE_ADD => '-rec_add',
};

INFO "Starting program (".PROGRAM_VERSION.")";
#my %config = %{loadLocalConfig("config.xml", undef, ForceArray => qr/^labelName$/)}; # Loading / preprocessing of the configuration file

my $currentOperation = $ARGV[0];
my $currentDirectory = $ARGV[1];
my $comment;
LOGDIE "Program needs three argument. first is operation among \"-rec_add\", \"-rec_ci\", \"-rec_co\", \"-rec_uco\" followed by a valid directory and finally a good comment." unless $currentDirectory and $currentOperation;

LOGDIE "Argument #1 has to be a valid operation among \"-rec_add\", \"-rec_ci\", \"-rec_co\", \"-rec_uco\" and you have entered \"$currentOperation\"" unless $currentOperation eq OPERATION_RECURSIVE_CHECKIN or $currentOperation eq OPERATION_RECURSIVE_CHECKOUT or $currentOperation eq OPERATION_RECURSIVE_ADD or $currentOperation eq OPERATION_RECURSIVE_UNCHECKOUT;
LOGDIE "Argument #2 has to be an existing and valid directory. Argument is actually \"$currentDirectory\"" unless -e $currentDirectory and -r $currentDirectory;

####################################################################
# Building graphical display
####################################################################
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
my @fillOptions = (-fill => 'both', -expand => 1);
my $window_width = 540;
my $window_height = 250;

my ($commentFrame, $description);

my $mw = MainWindow->new(-title => "Interface de gestion de la documentation (".PROGRAM_VERSION.")");
my $balloon = $mw->Balloon();
$mw->withdraw; # disable immediate display
$mw->minsize($window_width,$window_height);
$mw->maxsize($window_width,$window_height); 



my $bottomPanel = $mw->Frame()->pack(-ipady => 10, -side => 'bottom', -fill => 'x');
my $cancelButton = $bottomPanel->Button(-text => 'Quitter', -command => sub { confirm(-1) } ) -> pack(-side => 'left', @fillOptions);
$bottomPanel->Button(-text => 'Valider' , -command => sub { confirm(1, $description->Contents())}) -> pack(-side => 'right', @fillOptions);

$commentFrame = $mw->Frame()->pack(-padx => 10, -pady => 10);
$commentFrame->Label(-text => "Entrez ci-dessous un commentaire pour la modification :", -font => 'arial 9 underline')->pack(-expand => 1, -fill => 'x');

$description = $commentFrame->Scrolled("Text", -scrollbars => 'osoe', -padx => 5, -pady => 3) -> pack(@fillOptions);
$balloon->attach($description, -msg => "La description exhaustive de la modification effectuée.");




WARN "Comment is statically defined";
my $comment = 'test';

INFO "displaying graphical interface";
$mw->Popup; # window appears screen-centered
MainLoop();

$comment =~ s/\s+$//;

LOGDIE "Argument #3 has to be a comment. Argument is actually \"$comment\"" if $comment =~ /^\s*$/;
INFO "Defined comment is \"$comment\"";
		
switch ($currentOperation) {
case OPERATION_RECURSIVE_CHECKIN {
	LOGDIE "Not implemented";
	exit;
}
case OPERATION_RECURSIVE_CHECKOUT {
	LOGDIE "Not implemented";
	exit;
}
case OPERATION_RECURSIVE_UNCHECKOUT {
	LOGDIE "Not implemented";
	exit;
} 
case OPERATION_RECURSIVE_ADD {
	chdir($currentDirectory);
	if (isPrivateElement(".")) {
		chdir("..");
		DEBUG "Root directory needs to be checked out." and checkoutElement(".",$comment) unless isCheckedoutElement(".");
	}
	chdir($currentDirectory);
	conditionalAddToSource($currentDirectory, $comment);

	RecurAddToSource($currentDirectory);
}
else {	LOGDIE "Unknown operation";	}
}

sub confirm {
	my $action = shift;
	my $localComment = shift;
	
	DEBUG "requested action is $action";
	
	my $title = 'Demande de confirmation';
	my $message;
	my $iconStyle = 'question';
	
	if ($action == -1) {
		# Request to modify a filename
			$message = "Voulez-vous quitter cette interface?";
	}
	elsif ($action == 1) {
		$message = "Voulez-vous faire l'action désirée avec le commentaire défini auparavant?";

	}
	else {
		LOGDIE "No operations asked";
	}
	
	my $answer = $mw->messageBox(-title => $title, -message => $message, -type => 'yesno', -icon => $iconStyle);
	
	DEBUG "User has answered \"$answer\" to confirmation question";
	return unless $answer eq "Yes";
	DEBUG "User has requested a confirmation of this action";
	
	if ($action == -1) {
		# Request to exit
		exit(1001);
	}
	elsif ($action == 1) {
		$comment = $localComment;
		$mw->destroy();
	}
}

sub RecurAddToSource {
	my ($directory) = @_;
	
	chdir($directory);
	my $currentDirectory = cwd();
	DEBUG "Opening directory \"$currentDirectory\"";
	opendir(IMD, ".") || LOGDIE("Cannot open current directory");
	LOGDIE "Root directory \"$currentDirectory\" is not in SCM" if isPrivateElement(".");
	DEBUG "Root directory needs to be checked out." and checkoutElement(".",$comment) unless isCheckedoutElement(".");
	
	my @files = sort readdir(IMD);
	closedir(IMD);

	foreach my $element (@files) {
		next if $element =~/^\.{1,2}$/;
		
		conditionalAddToSource($element, $comment);
		
		if(-d $element) {
			RecurAddToSource($element);
		}
	} 
	chdir("..");
 }
 
 sub conditionalAddToSource {
	my ($element, $comment) = @_;
 
	if (isPrivateElement($element)) {
		DEBUG "File \"$element\" needs to be added";
		if(addToSource($element, $comment)) {
			DEBUG "Element \"$element\" was added to source control";
		}
		else {
			ERROR "Element \"$element\" had a problem";
		}
	}
 }

 exit;


__END__
:waitDueToErrors
pause
:finishedCorrectly