@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(lib);
use strict;
use warnings;
use Common;
use ClearcaseMgt qw(getConfigSpec setConfigSpec getViewNameByElement isSnapshotView);
use Data::Dumper;

my $Config = loadLocalConfig("config.xml"); # Loading / preprocessing of the configuration file

############################################################################################
# 
############################################################################################
use Tk;
use Tk::DirTree;
use Tk::Balloon;
use Tk::ItemStyle;
use Cwd;

use constant {
	PROGRAM_VERSION => '0.2',
	CFGSPEC_HEADER_NOT_PRESENT => 'Ce fichier ne contient pas d\'entêtes',
	CFGSPEC_SNP_PATH => './ConfigSpecs-snapshot',
	CFGSPEC_DYN_PATH => './ConfigSpecs-dynamic',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";

my %configSpec;
my ($description, $header, $title, $PATH_TO_ACTIVE_VIEW, $ACTIVE_VIEW, $ISSNAPSHOTVIEW, $PATH_TO_CFGSPEC, %pathToFiles);
my $OFFLINE_MODE = $Config->{offlineMode}->{isActive};
my $configSpec = "";
if($OFFLINE_MODE) {
	WARN "PROGRAM IS RUNNING IN OFFLINE MODE";
	$ISSNAPSHOTVIEW = $Config->{offlineMode}->{isSnapshotView};
}
else {
	$PATH_TO_ACTIVE_VIEW = $ARGV[0];
	LOGDIE "Program needs an argument." unless $PATH_TO_ACTIVE_VIEW;
	LOGDIE "Program takes one directory in argument. Argument is actually \"$ARGV[0]\"" unless -d $PATH_TO_ACTIVE_VIEW;
	$ACTIVE_VIEW = getViewNameByElement($PATH_TO_ACTIVE_VIEW);
	DEBUG "Found view \"$ACTIVE_VIEW\"" if $ACTIVE_VIEW;
	$ISSNAPSHOTVIEW = isSnapshotView($ACTIVE_VIEW) if $ACTIVE_VIEW;
	$configSpec = getConfigSpec($ACTIVE_VIEW) if $ACTIVE_VIEW;
}
my $activeConfigSpecFilename;
my $selectedConfigSpec;

if($ISSNAPSHOTVIEW) { $PATH_TO_CFGSPEC = CFGSPEC_SNP_PATH; }
else { $PATH_TO_CFGSPEC = CFGSPEC_DYN_PATH; }
my @list = createStructure($PATH_TO_CFGSPEC);

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

my $mw = MainWindow->new(-title => "Interface change config-spec");
my $balloon = $mw->Balloon();
$mw->minsize(640,480);
$mw->maxsize(640,480);
center($mw);
center($mw);

my $titlePanel = $mw->Frame() -> pack(-side => 'top', -fill => 'x');
$titlePanel->Label(-text => "Cette interface permet de modifier le fichier\nde configuration(config-spec) de Clearcase, afin de\nmodifier les élements affichés")->pack( -side => 'top', -fill => 'both', -expand => 1 );

my $buttonsPanel = $mw->Frame(-height => '30') -> pack(-side => 'bottom', -fill => 'both');
my $mainPanel = $mw->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);

#--------------------------------------------------------------------------
# Tk::Tree Widget
#--------------------------------------------------------------------------
  my $jobstree = $mainPanel->Scrolled(
      'Tree',
      -background         => 'white',
      -selectbackground   => 'LightGoldenrodYellow',
      -selectforeground   => 'RoyalBlue3',
      -highlightthickness => 0,
      -font               => 'verdana 10',
      -relief             => 'flat',
      -scrollbars         => 'osoe',
      -borderwidth        => 0,
      -command         => \&processSelectedFile,
   )->pack(-side => 'left', -fill => 'y',-anchor => 'w');

#--------------------------------------------------------------------------
# Tk::Tree Widget additional configurations
#--------------------------------------------------------------------------
   $jobstree->configure(
      -separator  => '/',
      -drawbranch => 'true',
      -indicator  => 'true',
      -selectborderwidth => '0',
      -highlightcolor => 'red');
   $jobstree->focus();

my $activeConfigSpecStyle  = $jobstree->ItemStyle('text', -font => 'verdana 10 bold', -background => 'white');
foreach my $node (@list) {
   my $node_name = (split('/', $node))[-1];
  $node_name = $node if ($node_name eq '');
  
  my @otherOptions;
  my $file = $PATH_TO_CFGSPEC."/$node";
	$file =~ s/\//\\/g;
   if (-f $file) {
	my $content = readFile($file);
	my $found = $configSpec eq $content;
	$activeConfigSpecFilename = $node if $found;
	DEBUG "Found filename of current config-spec (\"$activeConfigSpecFilename\")" if $found;
	@otherOptions = (-style => $activeConfigSpecStyle) if $found;
   	$pathToFiles{$node} = $file;
   }

   $jobstree->add($node, -text, $node_name, -itemtype, 'text', @otherOptions);
}
$jobstree->autosetmode();

my $configSpecPanel = $mainPanel->Frame(-padx => 10, -pady => 10)->pack(-side => 'right', -fill => 'both', -expand => 1);

my $configSpecTitlePanel = $configSpecPanel->Frame( -borderwidth => 1, -relief => 'solid', -padx => 20)->pack();
$configSpecTitlePanel->Label(-text => 'Config-spec sélectionné : ', -pady => 3, -font => 'verdana 9')->pack( -side => 'left' );
$title = $configSpecTitlePanel->Label(-text => '<<aucun>>', -pady => 3,  -font => 'verdana 9 bold')->pack( -side => 'right');

$header = $configSpecPanel->Label(-text => '<=== Il est nécessaire de sélectionner l\'un des config-specs recherchés.', -pady => 5)->pack( -side => 'top', -fill => 'both', -expand => 1 );
$description = $configSpecPanel->Scrolled("Text", -scrollbars => 'osoe', -state => 'disabled') -> pack( -side => 'top', -fill => 'both', -expand => 1);

my $cancelButton = $buttonsPanel->Button(-text => 'Quitter', -command => [\&cancel, $mw], -pady => 5) -> pack(-side => 'left', -fill => 'both', -expand => 1);
my $validateButton = $buttonsPanel->Button(-text => "Sélectionner un config-spec\npour activer ce bouton..." , -command => sub { validate($selectedConfigSpec, $configSpec)}, -state => 'disabled', -pady => 5) -> pack(-side => 'right', -fill => 'both', -expand => 1);

sub  processSelectedFile {
	my $selection = shift;
	DEBUG "Selected item is \"$selection\"";
	return if -d $PATH_TO_CFGSPEC."/$selection";
	$selectedConfigSpec = parseFile($selection);
	fillConfigSpecInterface($selectedConfigSpec);
}   

sub parseFile {
	my $file = shift;
	
	my %configSpec;
	
	$configSpec{filename} = $file;
	$configSpec{wholeFilename} = $pathToFiles{$file};

	DEBUG "Parsing \"$configSpec{wholeFilename}\"";
	$configSpec{content} = readFile($configSpec{wholeFilename});
	
	if($configSpec{content} =~ m/^(.*?)#{15,}(.*)$/s) {
		$configSpec{header} = $1;
		$configSpec{body} = $2;
		$configSpec{header} =~ s/^\s*#+\s*(.*?)\s*$/$1/mg;
	}
	else {
		$configSpec{header} = CFGSPEC_HEADER_NOT_PRESENT;
		$configSpec{body} = $configSpec{content};	
	}

	return \%configSpec;
}

sub readFile {
	my $file = shift;
	ERROR "File \"$file\" is not readable" unless -r $file;
	
	open FILE, $file or LOGDIE "It was not possible to open \"$file\"";
	local $/; # enable localized slurp mode
    my $content = <FILE>;
	close FILE;
	return $content;
}

sub fillConfigSpecInterface {
	my $configSpec = shift;
	
	$title->configure(-text => $configSpec->{filename}) if $title;
	$header->configure(-text => $configSpec->{header});
	$description->configure(-state => 'normal');
	$description->Contents($configSpec->{body});
	$description->configure(-state => 'disabled');
	if($activeConfigSpecFilename ne $configSpec->{filename}) {
		$validateButton->configure(-text => "Appliquer le config-spec suivant:\n$configSpec->{filename}",-state => 'normal');
	}
	else {
		$validateButton->configure(-text => "Le config-spec sélectionné est déjà appliqué.\nSélectionnez-en un autre.",-state => 'disabled');
	}
}

INFO "displaying graphical interface";
MainLoop();

sub center {
  my $win = shift;

  $win->withdraw;   # Hide the window while we move it about
  $win->update;     # Make sure width and height are current

  # Center window
  my $xpos = int(($win->screenwidth  - $win->width ) / 2);
  my $ypos = int(($win->screenheight - $win->height) / 2);
  $win->geometry("+$xpos+$ypos");

  $win->deiconify;  # Show the window again
}

sub createStructure {
	my $directory  = shift;
	use File::Find;
	
	my @list = ();
	find(
		sub { 
			$File::Find::prune = 1 if $_ eq '.svn';
			return if $_ eq '.svn';
			my $name =  $File::Find::name;
			return if $directory eq $name;
			$name = substr($name, (length ($directory)+1));
			push(@list, $name);
		},
		$directory);
	return sort @list;
}

sub validate {
	my $configSpec = shift;
	my $currentConfigSpec = shift;
	
	DEBUG "Trying to validate command";
	
	my $answer = $mw->messageBox(-title => "Demande de confirmation", -message => "Voulez-vous appliquer le config-spec appelé \"$configSpec->{filename}\" ?", -type => 'yesno', -icon => 'question');
	
	DEBUG "User has answered \"$answer\" to question";
	return unless $answer eq "Yes";
	INFO "User has requested to continue";
	
	my $result = changeConfigSpec($configSpec, $currentConfigSpec);
	my $newConfigSpec = getConfigSpec($ACTIVE_VIEW);
	$result = $newConfigSpec eq $configSpec->{content};
	
	INFO "Requested action was done correctly" and $mw->messageBox(-title => "Confirmation", -message => "L'opération s'est déroulée correctement.", -type => 'ok', -icon => 'info') and exit(1001) if($result);
	ERROR "Requested action was not performed correctly" and $mw->messageBox(-title => "Erreur durant l'opération", -message => "L'opération n'a pas eu lieu correctement.\nConsulter et conserver le fichier log pour analyser le problème rencontré.", -type => 'ok', -icon => 'error');
	exit(-1);
}

sub changeConfigSpec {
	my $configSpec = shift;
	my $currentConfigSpec = shift;
	
	DEBUG "Applying config-spec \"$configSpec->{wholeFilename}\"";
	my $BACKUP;
	my $BACKUP_FILE = getScriptDirectory()."config-spec.backup";
	open $BACKUP, ">$BACKUP_FILE" or ERROR "Unable to do a backup of current config-spec ($BACKUP_FILE): $!";
	print $BACKUP $currentConfigSpec and close $BACKUP if $BACKUP;

	$mw->messageBox(-title => "Avertissement", -message => "La mise à jour d'une vue snapshop requiert une mise à jour de tous les fichiers.\nIl s'agit d'une opération longue (plus de 10 minutes), qui fige l'interface durant ce temps.", -type => 'ok', -icon => 'warning') if $ISSNAPSHOTVIEW;

	if ($ISSNAPSHOTVIEW) { INFO "Applying config-spec for a snapshot view. It can take some time, it is necessary to wait."; }
	else { INFO "Applying config-spec for a dynamic view. It can take some time, it is necessary to wait."; }
	my $result = setConfigSpec($configSpec->{wholeFilename}, $PATH_TO_ACTIVE_VIEW);
	DEBUG "Operation has finished with return code \"$result\"";
	return $result;
}

sub cancel {
	my $mw = shift;
	
	my $answer = $mw->messageBox(-title => "Demande de confirmation", -message => "Voulez-vous quitter cette application?", -type => 'yesno', -icon => 'question');
	
	DEBUG "User has answered \"$answer\" to cancellation question";
	return unless $answer eq "Yes";
	INFO "User has requested a cancellation";
	exit(-1);
}

__END__
:endofperl
pause