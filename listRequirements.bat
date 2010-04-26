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
use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use Time::localtime;
use POSIX qw(strftime);
use Text::CSV;
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.1',
	TEMPLATE_DIRECTORY => './Templates/',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";

my $config = loadLocalConfig(getScriptName().'.config.xml', 'config.xml', ForceArray => qr/^(document|table)$/);
my $CQConfig = loadSharedConfig('Clearquest-config.xml');

my $SCRIPT_DIRECTORY = getScriptDirectory();
my $DATA_DIRECTORY = $SCRIPT_DIRECTORY."Data\\";
DEBUG "Using $DATA_DIRECTORY as script directory";

my $CAC_LIST = loadCSV($DATA_DIRECTORY.'CaC_List.csv');
my $VBN_CaC_List = loadCSV($DATA_DIRECTORY.'VBN_CaC_List.csv');

open (FILE, ">".$SCRIPT_DIRECTORY.'Results.html');
		
my $t = HTML::Template -> new( filename => TEMPLATE_DIRECTORY."main.tmpl", die_on_bad_params => 0 );

$t->param(REQUIREMENTS => $CAC_LIST);
my $tm = strftime "%d-%m-%Y à %H:%M:%S", gmtime;
$t->param(DATE => $tm);

print FILE $t->output;
close(FILE);

sub loadCSV {
	my $file = shift;
	my @rows;
	my $csv = Text::CSV->new ( { binary => 1, sep_char => ';'} )  # should set binary attribute.
                 or die "Cannot use CSV: ".Text::CSV->error_diag ();
 
	open my $fh, $file or LOGDIE "$file was not opened correctly: $!";
	
	my $colref = $csv->getline($fh);
	$csv->column_names(@$colref); 

	
	while ( my $row = $csv->getline_hr( $fh ) ) {
		push(@rows, $row);
	}
	
	close $fh;
	return \@rows;
}


__END__
:endofperl
pause