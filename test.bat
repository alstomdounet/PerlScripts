@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
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

############################################################################################
# 
############################################################################################
use Tk;
use Tk::JComboBox;
use Tk::Balloon;



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


my $mw = MainWindow->new(-title => "Interface to add new bugs");
$mw->withdraw; # disable immediate display
$mw->minsize(640,480);
my $balloon = $mw->Balloon();

my @completeList = (
      { -name => 'Black',  -value => '#00az00', -data => 'test' },
      { -name => 'Blue',   -value => '#0000ff' },
      { -name => 'Green',  -value => '#008000' },
      { -name => 'Purple', -value => '#8000ff' },
      { -name => 'Red',    -value => '#ff0000' },
      { -name => 'Yellow', -value => '#ffff00' }
   );
my @selectedList;
my $selection;

my $TitlePanel = $mw->Frame() -> pack(-side => 'top', -fill => 'x');
$TitlePanel->Button(-text => 'Search', -width => 15 )->pack( -side => 'left' );
my $title = $TitlePanel->Entry(-validate => 'all', -validatecommand => [\&search])->pack(-fill => 'x', -side => 'top', -anchor => 'center');

my $itemBox = $mw->Frame() -> pack(-side => 'top', -fill => 'x');
$itemBox->Label(-text => 'Ma liste', -width => 15 )->pack(-side => 'left');
$itemBox->Button(-text => 'Search')->pack( -side => 'right' );
my $listbox = $itemBox->JComboBox(-choices => \@selectedList, -textvariable => \$selection)->pack(-fill => 'x', -side => 'left', -expand => 1);
@selectedList = @completeList;

my $description = $mw->Scrolled("Text", -scrollbars => 'osoe') -> pack( -side => 'top', -fill => 'both');

INFO "displaying graphical interface";
$mw->Popup; # window appears screen-centered
MainLoop();

##############################################
# Graphical oriented functions
##############################################

sub manageSearchBox {
	my $searchListbox = shift;
}

sub search {	
	$description->Contents(Dumper \@_);
	my $search = shift;
	INFO "Call Search function with search : \"$search\"";
	my @tmpList = ();
	my $old_selection = $selection;
	
	foreach my $item (@completeList) {
		next unless ($item->{-name} =~ /$search/i or $item->{-value} =~ /$search/i);
		push (@tmpList, $item);
	}
	#@selectedList = @tmpList;
	DEBUG "Selection is \"$old_selection\"";
	$selection = $old_selection if $old_selection;
	$description->Contents(scalar(@selectedList)." Results\n\n".Dumper \@selectedList);
	return 1;
}

__END__
:endofperl
pause