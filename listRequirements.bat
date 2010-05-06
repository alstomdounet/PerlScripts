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
use Spreadsheet::ParseExcel;
use XML::Simple;
use open ':encoding(utf8)';

use constant {
	PROGRAM_VERSION => '0.2',
	TEMPLATE_DIRECTORY => './Templates/',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";

my $config = loadLocalConfig(getScriptName().'.config.xml', 'config.xml', ForceArray => qr/^(document|table)$/);

my $SCRIPT_DIRECTORY = getScriptDirectory();
my $DATA_DIRECTORY = $SCRIPT_DIRECTORY."Data\\";
DEBUG "Using $DATA_DIRECTORY as script directory";

INFO "Reading source files";
my %source;
my %fields;

%fields = ('Exigence_CDC' => 0, 'Texte' => 1);
$source{CDC_LIST} = loadExcel($config->{documents}->{ClauseByClause}->{FileName}, $config->{documents}->{ClauseByClause}->{Sheet}, \%fields);

%fields = ('Exigence_VBN' => 0, 'Texte' => 1);
$source{VBN_LIST} = loadExcel($config->{documents}->{Requirements_VBN}->{FileName}, $config->{documents}->{Requirements_VBN}->{Sheet}, \%fields);

%fields = ('Exigence_REI' => 0, 'Texte' => 1);
$source{REI_LIST} = loadExcel($config->{documents}->{Requirements_REI}->{FileName}, $config->{documents}->{Requirements_REI}->{Sheet}, \%fields);

%fields = ('Exigence_CDC' => 0, 'Exigence_VBN' => 1, 'state' => 2, 'req_level' => 3, 'Risk' => 4);
$source{VBN_CDC_List} = loadExcel($config->{documents}->{Requirements_VBN_CBC}->{FileName}, $config->{documents}->{Requirements_VBN_CBC}->{Sheet}, \%fields);

%fields = ('Exigence_CDC' => 0, 'Exigence_REI' => 1, 'Applicabilite' => 2, 'Risk' => 3, 'Comment' => 4);
$source{REI_CDC_List} = loadExcel($config->{documents}->{Requirements_REI_CBC}->{FileName}, $config->{documents}->{Requirements_REI_CBC}->{Sheet}, \%fields);

INFO "Preprocessing source files";
my %list_CDC = map { $_->{Exigence_CDC} => $_ } @{$source{CDC_LIST}};
my %list_VBN = map { $_->{Exigence_VBN} => $_ } @{$source{VBN_LIST}};
my %list_REI = map { $_->{Exigence_REI} => $_ } @{$source{REI_LIST}};



INFO "generating list of requirements compliant for VBN side";
my %list_VBN_CDC;
my $i = 1;
foreach (sort @{$source{VBN_CDC_List}}) {
	$i++;
	#ERROR "Line $i: No equivalent found for VBN key called \"$_->{Exigence_VBN}\"" and next unless $list_VBN{$_->{Exigence_VBN}};
	#ERROR "Line $i: No equivalent found for CDC key called \"$_->{Exigence_CDC}\"" and next unless $list_CDC{$_->{Exigence_CDC}};
	my %item;
	my $orig_item = $list_VBN{$_->{Exigence_VBN}};
	$item{Texte} = $orig_item->{Texte};
	if(defined $_->{Risk} and "$_->{Risk}" ne "") {
		$item{Risk} = "R".$_->{Risk};
	}
	
	$item{Req_ID} = $_->{Exigence_VBN};
	push(@{$list_VBN_CDC{$_->{Exigence_CDC}}}, \%item);
}

INFO "generating list of requirements compliant for REI side";
my %list_REI_CDC;
my %errors_reported;
$i = 1;
foreach (sort @{$source{REI_CDC_List}}) {
	$i++;

	unless ($list_REI{$_->{Exigence_REI}}) {
		next if $errors_reported{$_->{Exigence_REI}};
		
		ERROR "Line $_->{__LineNumber}: No equivalent found for REI key called \"$_->{Exigence_REI}\"";
		$errors_reported{$_->{Exigence_REI}}++;
		next;
	}
	
	unless ($list_CDC{$_->{Exigence_CDC}}) {
		next if $errors_reported{$_->{Exigence_CDC}};
		ERROR "Line $_->{__LineNumber}: No equivalent found for CDC key called \"$_->{Exigence_CDC}\"";
		$errors_reported{$_->{Exigence_CDC}}++;
		next;
	}
	
	my %item;
	if( defined $_->{Risk} and "$_->{Risk}" ne "") {
		$item{Risk} = "R".$_->{Risk};
	}
	
	my $orig_item = $list_REI{$_->{Exigence_REI}};
	$item{Texte} = $orig_item->{Texte};
	$item{Req_ID} = $_->{Exigence_REI};
	push(@{$list_REI_CDC{$_->{Exigence_CDC}}}, \%item);
}

INFO "Generating final mapping";
my @final_report;
foreach (sort @{$source{CDC_LIST}}) {
	my $reference = $_->{Exigence_CDC};
	my %requirement;
	$requirement{Texte} = $_->{Texte};
	$requirement{Req_ID} = $reference;
	$requirement{REQUIREMENTS_VBN} = $list_VBN_CDC{$reference} if $list_VBN_CDC{$reference};
	$requirement{REQUIREMENTS_REI} = $list_REI_CDC{$reference} if $list_REI_CDC{$reference};

	push(@final_report, \%requirement);
}

INFO "Generating HTML report";
open (FILE, ">".$SCRIPT_DIRECTORY.'Results.html');
		
my $t = HTML::Template -> new( filename => TEMPLATE_DIRECTORY."main.tmpl", die_on_bad_params => 1 );

$t->param(REQUIREMENTS_CDC => \@final_report);
my $tm = strftime "%d-%m-%Y � %H:%M:%S", gmtime;
$t->param(DATE => $tm);

print FILE $t->output;
close(FILE);

sub loadExcel {
	my ($filename, $sheet, $header) = @_;

	my $oExcel = new Spreadsheet::ParseExcel;

    my $oBook = $oExcel->Parse($filename);
    my($iR, $iC, $oWkC);
    DEBUG "Excel file \"$oBook->{File}\" with $oBook->{SheetCount} sheets, made by $oBook->{Author}";
	
	my @elements;
	
    my $oWkS = $oBook->worksheet($sheet) or LOGDIE "No sheet called $sheet is found";
    DEBUG "Properties of sheet \"$oWkS->{Name}\" : Rows[$oWkS->{MinRow},$oWkS->{MaxRow}], Columns[$oWkS->{MinCol},$oWkS->{MaxCol}]";
	
	my $dimScalar = 0;
	my %header;
	foreach my $key (keys(%$header)) {
		if ($header->{$key} >= $oWkS->{MinCol} and $header->{$key} <= $oWkS->{MaxCol}) {	
			DEBUG "Column #$header->{$key} called \"$key\" is being processed";
		}
		else {
			LOGDIE "Column {$key => $header->{$key}} was defined out of column range";
		}
	}
	
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
		my %line;
		
		foreach my $key (keys(%$header)) {
			my $iC = $header->{$key};
			my $oWkC = "";
			if(not defined $oWkS->{Cells}[$iR][$iC]) {
				$oWkC = "";
			}
			else {
				$oWkC = "".$oWkS->{Cells}[$iR][$iC]->Value."";
			}
			
			$line{$key} = $oWkC;
        }
		
		$line{__LineNumber} = $iR;
		push(@elements, \%line);
    }
	return \@elements;
	
}

__END__
:endofperl
pause