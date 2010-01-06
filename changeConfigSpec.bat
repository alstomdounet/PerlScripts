@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(lib);
use strict;
use warnings;
use Common;
use File::Find;
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
$mw->minsize(300,200);
$mw->maxsize(300,200);

my $titlePanel = $mw->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);
my $listBoxesPanel = $mw->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);
#my $buttonsPanel = $mw->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);

$titlePanel->Label(-text => "Cette interface permet de modifier le fichier\nde configuration(config-spec) de Clearcase, afin de\nmodifier les élements affichés")->pack( -side => 'top', -fill => 'both', -expand => 1 );

sub  processSelectedFile {
	my $selection = shift;
	DEBUG "Here is selected item";
}

#--------------------------------------------------------------------------
# Tk::Tree Widget
#--------------------------------------------------------------------------
  my $jobstree = $listBoxesPanel->Scrolled(
      'Tree',
      -background         => 'white',
      -selectbackground   => 'LightGoldenrodYellow',
      -selectforeground   => 'RoyalBlue3',
      -highlightthickness => 0,
      -font               => 'verdana 12',
      -relief             => 'flat',
      -scrollbars         => 'osoe',
      -borderwidth        => 1,
      -command          => \&processSelectedFile,
   )->pack(-side => 'left', -fill => 'both', -expand => 1, -anchor => 'w');

#--------------------------------------------------------------------------
# Tk::Tree Widget additional configurations
#--------------------------------------------------------------------------
   $jobstree->configure(
      -separator  => '/',
      -drawbranch => 'true',
      -indicator  => 'true',
      -selectborderwidth => '4',
      #-selectmode        => 'extended',
      -highlightcolor => 'red');
   $jobstree->focus();

foreach my $node (@list) {
   my $node_name = (split('/', $node))[-1];
  $node_name = $node if ($node_name eq '');
   $jobstree->add($node, -text, $node_name, -itemtype, 'text');
}
$jobstree->autosetmode();

   
INFO "displaying graphical interface";
$mw->Popup; # window appears screen-centered
MainLoop();

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