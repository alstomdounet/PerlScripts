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
	DEBUG_MODE => 0,
};

INFO "Starting program (V ".PROGRAM_VERSION.")";

my $config = loadLocalConfig(getScriptName().'.config.xml', 'config.xml', ForceArray => qr/^(document|table)$/);

my $SCRIPT_DIRECTORY = getScriptDirectory();
my $DATA_DIRECTORY = $SCRIPT_DIRECTORY."Data\\";
DEBUG "Using $DATA_DIRECTORY as script directory";

INFO "Extracting required informatiosn from files";
my %source;
my %fields;

INFO "generating list of requirements compliant for REI side";

# my %list_CDC1 = ( 'REQ-CDC-01' => 1, 'REQ-CDC-02' => 2, 'REQ-CDC-03' => 3, 'REQ-CDC-04' => 4);
# my %list_REI1 = ( 'REQ-REI-01' => 1, 'REQ-REI-02' => 2, 'REQ-REI-03' => 3, 'REQ-REI-04' => 4);
# my @list3;
# push(@list3, {'Exigence_REI' => 'REQ-REI-12', 'Exigence_CDC' => 'REQ-CDC-02', __LineNumber => 3});
# push(@list3, {'Exigence_REI' => 'REQ-REI-01', 'Exigence_CDC' => 'REQ-CDC-04', __LineNumber => 6});
# push(@list3, {'Exigence_REI' => 'REQ-REI-01', 'Exigence_CDC' => 'REQ-CDC-12', __LineNumber => 9});

# my %list_VBN_CDC1 = joinRequirements(\%list_CDC1, \%list_REI1, \@list3, 'Exigence_CDC', 'Exigence_REI');
# exit;

if (not DEBUG_MODE or not -r "Requirements_image.db") {
	%fields = ('Exigence_CDC' => 0, 'Texte' => 1);
	$source{CDC_LIST} = loadExcel($config->{documents}->{ClauseByClause}->{FileName}, $config->{documents}->{ClauseByClause}->{Sheet}, \%fields);

	%fields = ('Exigence_VBN' => 0, 'Texte' => 1);
	$source{VBN_LIST} = loadExcel($config->{documents}->{Requirements_VBN}->{FileName}, $config->{documents}->{Requirements_VBN}->{Sheet}, \%fields);

	%fields = ('Exigence_REI' => 0, 'Texte' => 1);
	$source{REI_LIST} = loadExcel($config->{documents}->{Requirements_REI}->{FileName}, $config->{documents}->{Requirements_REI}->{Sheet}, \%fields);

	%fields = ('Exigence_CDC' => 0, 'Exigence_VBN' => 1, 'Risk' => 4, 'History' => 5);
	$source{VBN_CDC_List} = loadExcel($config->{documents}->{Requirements_VBN_CBC}->{FileName}, $config->{documents}->{Requirements_VBN_CBC}->{Sheet}, \%fields);

	%fields = ('Exigence_CDC' => 0, 'Exigence_REI' => 1, 'Applicabilite' => 2, 'Risk' => 3, 'History' => 4);
	$source{REI_CDC_List} = loadExcel($config->{documents}->{Requirements_REI_CBC}->{FileName}, $config->{documents}->{Requirements_REI_CBC}->{Sheet}, \%fields);
	store(\%source, "Requirements_image.db");
}
else {
	%source = %{retrieve("Requirements_image.db")};
}

INFO "Preprocessing source files";
WARN "Missing analysis for source requirements";
my %list_CDC = map { $_->{Exigence_CDC} => $_ } @{$source{CDC_LIST}};
my %list_VBN = map { $_->{Exigence_VBN} => $_ } @{$source{VBN_LIST}};
my %list_REI = map { $_->{Exigence_REI} => $_ } @{$source{REI_LIST}};

INFO "generating list of requirements compliant for REI side";
my ($list_REI_CDC, $errors_REI_CDC, $history_REI_CDC) = joinRequirements(\%list_CDC, \%list_REI, $source{REI_CDC_List}, 'Exigence_CDC', 'Exigence_REI');

INFO "generating list of requirements compliant for VBN side";
my ($list_VBN_CDC, $errors_VBN_CDC, $history_VBN_CDC) = joinRequirements(\%list_CDC, \%list_VBN, $source{VBN_CDC_List}, 'Exigence_CDC', 'Exigence_VBN');

INFO "Generating final mapping";
my @final_report;
foreach (sort @{$source{CDC_LIST}}) {
	my $reference = $_->{Exigence_CDC};
	my %requirement;
	$requirement{Texte} = $_->{Texte};
	$requirement{Req_ID} = $reference;
	$requirement{REQUIREMENTS_VBN} = $list_VBN_CDC->{$reference} if $list_VBN_CDC->{$reference};
	$requirement{REQUIREMENTS_REI} = $list_REI_CDC->{$reference} if $list_REI_CDC->{$reference};

	push(@final_report, \%requirement);
}

# Building history lists
my @history;
push(@history, { TITLE => 'History for REI requirements coverage', HISTORY_LIST => $history_REI_CDC });
push(@history, { TITLE => 'History for VBN requirements coverage', HISTORY_LIST => $history_VBN_CDC });


INFO "Generating HTML report";
open (FILE, ">".$SCRIPT_DIRECTORY.'Results.html');
		
my $t = HTML::Template -> new( filename => TEMPLATE_DIRECTORY."main.tmpl", die_on_bad_params => 1 );

$t->param(REQUIREMENTS_CDC => \@final_report);
$t->param(HISTORY => \@history);
my $tm = strftime "%d-%m-%Y à %H:%M:%S", gmtime;
$t->param(DATE => $tm);

print FILE $t->output;
close(FILE);

sub joinRequirements {
	my($list_reference, $list_to_link, $list_links, $key_ref, $key_link) = @_;

	DEBUG "Processing list of requirements";
	
	my %list;
	my @history;
	
	my %errors;
	my %analysis_table;
	
	foreach (sort @{$list_links}) {
		# Identifying referenced 
		$analysis_table{LIST_REF}->{$_->{$key_ref}}++;
		$analysis_table{LIST_TO_LINK}->{$_->{$key_link}}++;

		unless ($list_to_link->{$_->{$key_link}}) {
			next if $errors{TO_LINK_UNMATCHED}->{$_->{$key_link}};
			
			DEBUG "Line $_->{__LineNumber}: No equivalent found for LINKS key called \"$_->{$key_link}\"";
			$errors{TO_LINK_UNMATCHED}->{$_->{$key_link}} = $_->{__LineNumber};
			next;
		}
		
		unless ($list_reference->{$_->{$key_ref}}) {
			next if $errors{REF_UNMATCHED}->{$_->{$key_ref}};
			
			DEBUG "Line $_->{__LineNumber}: No equivalent found for REFERENCES key called \"$_->{$key_ref}\"";
			$errors{REF_UNMATCHED}->{$_->{$key_ref}} = $_->{__LineNumber};
			next;
		}
		
		my %item;
		my %hist_item;
		
		my $orig_item = $list_to_link->{$_->{$key_link}};
		$item{Texte} = $orig_item->{Texte};
		my $risk = $_->{Risk};
		if(defined $risk and "$risk" ne "") {
			$risk = "R".$risk;
			unless ($risk eq "R0" or $risk eq "R1" or $risk eq "R2" or $risk eq "R3" or $risk eq "R9") {
				LOGDIE "Line $_->{__LineNumber}: Risk \"$risk\" is not a valid value";
			}
			
			$item{Risk} = "R".$_->{Risk};
		}
		else {
			$item{Risk} = 'R9';
		}
		
		$item{Link_Key} = sprintf($key_link."_%04d", $_->{__LineNumber});
		$hist_item{Link_Key} = $item{Link_Key};
		$hist_item{History} = $_->{History};
		
		$item{Req_ID} = $_->{$key_link};
		push(@history, \%hist_item);
		push(@{$list{$_->{$key_ref}}}, \%item);
	}
	
	foreach my $ref (keys %$list_reference) {
		$errors{REF_UNUSED}{$ref}++ unless $analysis_table{LIST_REF}{$ref};
	}
	
	foreach my $ref (keys %$list_to_link) {
		$errors{TO_LINK_UNUSED}{$ref}++ unless $analysis_table{LIST_TO_LINK}->{$ref};
	}
	
	return (\%list, \%errors, \@history);
	
}

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