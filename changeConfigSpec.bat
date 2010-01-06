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

INFO "Starting program (V ".PROGRAM_VERSION.")";

my @list = createStructure("./config-specs");

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
my $mainPanel = $mw->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);
my $configSpecPanel = $mainPanel->Frame()->pack(-side => 'right', -fill => 'both', -expand => 1);
my $buttonsPanel = $mw->Frame(-height => '30') -> pack(-side => 'bottom', -fill => 'both');

$titlePanel->Label(-text => "Cette interface permet de modifier le fichier\nde configuration(config-spec) de Clearcase, afin de\nmodifier les élements affichés")->pack( -side => 'top', -fill => 'both', -expand => 1 );

my $cancelButton = $buttonsPanel->Button(-text => 'Quitter', -command => sub { exit(-1)}) -> pack(-side => 'left', -fill => 'both', -expand => 1);
$buttonsPanel->Button(-text => 'Valider' , -command => sub { confirm()}) -> pack(-side => 'right', -fill => 'both', -expand => 1);


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

sub  processSelectedFile {
	my $selection = shift;
	DEBUG "Here is selected item ($selection)";
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
}


sub cancel {
	my $mw = shift;
	
	my $answer = $mw->messageBox(-title => "Confirmation requested", -message => "Do you really want to quit this application?", -type => 'yesno', -icon => 'question');
	
	DEBUG "User has answered \"$answer\" to cancellation question";
	return unless $answer eq "Yes";
	INFO "User has requested a cancellation";
	exit(-1);
}

__END__
:endofperl
pause