@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(lib);
use strict;
use warnings;
use Common;
use Data::Dumper;


#my %Config = loadConfig("config.xml", ForceArray => qr/^filter$/); # Loading / preprocessing of the configuration file

############################################################################################
# 
############################################################################################
use Tk;
use Tk::DirTree;
use Tk::Balloon;

use constant PROGRAM_VERSION => '0.1';
use constant PARSED_PATH => './config-specs';

INFO "Starting program (V ".PROGRAM_VERSION.")";

my @list = createStructure(PARSED_PATH);
my %configSpec;
my ($description, $header, $title);

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
$mw->withdraw; # disable immediate display
$mw->minsize(640,480);
$mw->maxsize(640,480);

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



foreach my $node (@list) {
   my $node_name = (split('/', $node))[-1];
  $node_name = $node if ($node_name eq '');
   $jobstree->add($node, -text, $node_name, -itemtype, 'text');
}
$jobstree->autosetmode();

my $configSpecPanel = $mainPanel->Frame(-padx => 10, -pady => 10)->pack(-side => 'right', -fill => 'both', -expand => 1);
$header = $configSpecPanel->Label(-text => '<=== Il est nécessaire de sélectionner l\'un des config-specs recherchés.')->pack( -side => 'top', -fill => 'both', -expand => 1 );
$description = $configSpecPanel->Scrolled("Text", -scrollbars => 'osoe', -state => 'disabled') -> pack( -side => 'top', -fill => 'both', -expand => 1);

my $cancelButton = $buttonsPanel->Button(-text => 'Quitter', -command => [\&cancel, $mw]) -> pack(-side => 'left', -fill => 'both', -expand => 1);
my $validateButton = $buttonsPanel->Button(-text => 'Valider' , -command => sub { confirm()}, -state => 'disabled') -> pack(-side => 'right', -fill => 'both', -expand => 1);

sub  processSelectedFile {
	my $selection = shift;
	DEBUG "Selected item is \"$selection\"";
	return if -d PARSED_PATH."/$selection";
	my $configSpec = parseFile($selection);
	fillConfigSpecInterface($configSpec);
}   

sub parseFile {
	my $file = shift;
	
	my %configSpec;
	
	$configSpec{fileName} = $file;
	$file = PARSED_PATH."/$file";
	DEBUG "Parsing $file";
	ERROR "Config spec \"$file\" is not readable" unless -r $file;
	
	open FILE, $file or LOGDIE "It was not possible to open \"$file\"";
	local $/; # enable localized slurp mode
    $configSpec{content} = <FILE>;

	close FILE;
	
	# dfsfdfdsfsd
	
	if($configSpec{content} =~ m/^(.*?)#{15,}(.*)$/s) {
		$configSpec{header} = $1;
		$configSpec{header} =~ s/^\s*#+\s*(.*?)\s*$/$1/mg;
		$configSpec{body} = $2;
	}
	else {
		$configSpec{header} = "Ce fichier ne contient pas d'entêtes";
		$configSpec{body} = $configSpec{content};	
	}

	return \%configSpec;
}

sub fillConfigSpecInterface {
	my $configSpec = shift;
	
	$title->configure(-text => $configSpec->{title}) if $title;
	$header->configure(-text => $configSpec->{header});
	$description->configure(-state => 'normal');
	$description->Contents($configSpec->{body});
	$description->configure(-state => 'disabled');
}

INFO "displaying graphical interface";
center($mw);
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
			$File::Find::prune = 1 if $_ eq ".svn";
			return if $_ eq ".svn";
			my $name =  $File::Find::name;
			return if $directory eq $name;
			$name = substr($name, (length ($directory)+1));
			push(@list, $name);
		},
		$directory);
	return sort @list;
}

sub changeConfigSpec {
	my $text = shift;
	ERROR "This function is not currently implemented";
	return 1;
}	

sub isActiveConfigSpec {
	ERROR "This function is not currently implemented";
	return 0;
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