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
	RISKS => '1_Risks',
	COVERAGE => '2_Coverage',
	MISSING_REQS => '2_mreq',
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

if (not $config->{DebugMode} or not -r "Requirements_image.db") {
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
	
	%fields = ('Exigence_TGC' => 0, 'Lot' => 6, 'Statut' => 7, 'Livrable' => 8);
	$source{TGC_List} = loadExcel($config->{documents}->{Assigned_REQ_TGC}->{FileName}, $config->{documents}->{Assigned_REQ_TGC}->{Sheet}, \%fields);
	
	store(\%source, "Requirements_image.db");
}
else {
	WARN "Using DEBUG MODE. You have to delete \"Requirements_image.db\" to force refresh.";
	%source = %{retrieve("Requirements_image.db")};
}

INFO "Preprocessing source files";
WARN "Missing analysis for source requirements";
my %list_CDC = map { $_->{Exigence_CDC} => $_ } @{$source{CDC_LIST}};
my %list_VBN = map { $_->{Exigence_VBN} => $_ } @{$source{VBN_LIST}};
my %list_REI = map { $_->{Exigence_REI} => $_ } @{$source{REI_LIST}};
my %list_TGC = map { $_->{Exigence_TGC} => $_ } @{$source{TGC_List}};

INFO "generating list of requirements compliant for REI side";
my ($list_REI_CDC, $errors_REI_CDC, $history_REI_CDC, $stats_REI_CDC) = joinRequirements(\%list_CDC, \%list_REI, $source{REI_CDC_List}, 'Exigence_CDC', 'Exigence_REI');

INFO "generating list of requirements compliant for VBN side";
my ($list_VBN_CDC, $errors_VBN_CDC, $history_VBN_CDC, $stats_VBN_CDC) = joinRequirements(\%list_CDC, \%list_VBN, $source{VBN_CDC_List}, 'Exigence_CDC', 'Exigence_VBN');

INFO "Generating final mapping";
my @final_report;
foreach (sort @{$source{CDC_LIST}}) {
	my $reference = $_->{Exigence_CDC};
	my %requirement;
	$requirement{Texte} = $_->{Texte};
	$requirement{Req_ID} = $reference;
	$requirement{REQUIREMENTS_VBN} = $list_VBN_CDC->{$reference} if $list_VBN_CDC->{$reference};
	$requirement{REQUIREMENTS_REI} = $list_REI_CDC->{$reference} if $list_REI_CDC->{$reference};
	
	$requirement{APPLICABILITE} = 'NA';
	$list_TGC{$reference}{Lot} = 'Inconnu' unless $list_TGC{$reference}{Lot};
	$list_TGC{$reference}{Livrable} = 'Inconnu' unless $list_TGC{$reference}{Livrable};
	$requirement{REF_DOC} = $list_TGC{$reference}{Lot}." / ". $list_TGC{$reference}{Livrable};
	$requirement{APPLICABILITE} = 'YES' if ($list_TGC{$reference}{Livrable} =~ /DID0000170295/) or ($list_TGC{$reference}{Lot} =~ /TCM3/);

	push(@final_report, \%requirement);
}

# Building history lists
my @history;
push(@history, { TITLE => 'History for REI requirements coverage', HISTORY_LIST => $history_REI_CDC });
push(@history, { TITLE => 'History for VBN requirements coverage', HISTORY_LIST => $history_VBN_CDC });

my @statistics;
push(@statistics, { TITLE => 'History for REI requirements coverage', CATEGORY => $stats_REI_CDC });
push(@statistics, { TITLE => 'History for VBN requirements coverage', CATEGORY => $stats_VBN_CDC});


INFO "Generating HTML report";
open (FILE, ">".$SCRIPT_DIRECTORY.'Results.html');
		
my $t = HTML::Template -> new( filename => TEMPLATE_DIRECTORY."main.tmpl", die_on_bad_params => 1, loop_context_vars => 1 );

$t->param(REQUIREMENTS_CDC => \@final_report);
$t->param(HISTORY => \@history);
$t->param(STATISTICS => \@statistics);
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
	my %statistics;
	
	$statistics{+RISKS}{Name} = 'Risks analysis';
	
	foreach (sort @{$list_links}) {
		# Identifying referenced 
		$analysis_table{LIST_REF}->{$_->{$key_ref}}++;
		$analysis_table{LIST_TO_LINK}->{$_->{$key_link}}++;

		my $valid_ref_required = 1;
		
		if($_->{$key_link} eq "" and $_->{Applicabilite} =~ /Non/) {
			$valid_ref_required = 0;
		}
		
		if (not $list_to_link->{$_->{$key_link}} and $valid_ref_required) {
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
		
		if($valid_ref_required) {
			my $orig_item = $list_to_link->{$_->{$key_link}};
			$item{Texte} = $orig_item->{Texte};
			$item{Req_ID} = $_->{$key_link};
			$item{Applicabilite} = 'YES';
		}
		else {
			$item{Texte} = $_->{History};
			$item{Texte} = 'Justification is not yet written...' unless $item{Texte};
			$item{Req_ID} = 'No reference';
			$item{Applicabilite} = 'NO';
		}
		
		my $risk = $_->{Risk};
		$item{Risk} = '9' unless (defined $risk and "$risk" ne "");
		
		$risk = "R".$risk;
		LOGDIE "Line $_->{__LineNumber}: Risk \"$risk\" is not a valid value" unless ($risk eq "R0" or $risk eq "R1" or $risk eq "R2" or $risk eq "R3" or $risk eq "R9");
		$statistics{+RISKS}{Sum}++;
		$statistics{+RISKS}{List}{$risk}++;
		$item{Risk} = $risk;
		
		$item{Link_Key} = sprintf($key_link."_%04d", $_->{__LineNumber});
		$hist_item{Link_Key} = $item{Link_Key};
		$hist_item{History} = $_->{History};
		

		push(@history, \%hist_item);
		push(@{$list{$_->{$key_ref}}}, \%item);
	}
	

	foreach my $ref (keys %$list_reference) {
		$errors{REF_USED}{$ref}++;
		$errors{REF_UNUSED}{$ref}++ unless $analysis_table{LIST_REF}{$ref};
	}
	
	$statistics{+COVERAGE}{Name} = 'Contractual covering';
	$statistics{+COVERAGE}{Sum} = scalar keys %{$errors{REF_USED}};
	$statistics{+COVERAGE}{List}{'Uncovered contractual requirements'} = scalar keys %{$errors{REF_UNUSED}};
	$statistics{+COVERAGE}{List}{'Contractual requirements covered'} =  $statistics{+COVERAGE}{Sum} - scalar keys %{$errors{REF_UNUSED}};
	
	foreach my $ref (keys %$list_to_link) {
		$statistics{+MISSING_REQS}{Sum}++;
		$errors{TO_LINK_USED}{$ref}++;
		$errors{TO_LINK_UNUSED}{$ref}++ unless $analysis_table{LIST_TO_LINK}->{$ref};
	}
	
	$statistics{+MISSING_REQS}{Name} = 'Requirements not referenced by contractual side';
	$statistics{+MISSING_REQS}{Sum} = scalar keys %{$errors{TO_LINK_USED}};
	$statistics{+MISSING_REQS}{List}{'Covered requirements'} = $statistics{+MISSING_REQS}{Sum} - scalar keys %{$errors{TO_LINK_UNUSED}};
	$statistics{+MISSING_REQS}{List}{'Uncovered requirements'} = scalar keys %{$errors{TO_LINK_UNUSED}};
	

	my @statistics = buildStatistics(%statistics);
	
	return (\%list, \%errors, \@history, \@statistics);
}

sub buildStatEntry {
	my ($name, $value, $total) = @_;
	my %item;
	$item{NAME} = $name;
	$item{VALUE} = $value;
	$item{PERCENTAGE} = sprintf(("%.1f", $value*100/$total));
	return \%item;
}

sub buildStatistics {
	my %statistics = @_;
	my @statistics;

	################################################################################
	
	foreach my $category (sort keys %statistics) {
		my %item = %{$statistics{$category}};
		my %category;
		$category{NAME} = $item{Name};
		$category{COUNT_LIST} = scalar(keys %{$item{List}}) + 1;
		$category{VALUE_TOTAL} = $item{Sum};
		
		my @list;
		foreach my $key (sort keys %{$item{List}}) {
			push(@list, buildStatEntry($key,$item{List}{$key},$category{VALUE_TOTAL}));
		}
		
		$category{LIST} = \@list;
		DEBUG "Nothing was set for category \"$category\"" and next unless scalar(@list);
		push(@statistics, \%category);
	}
	
	################################################################################
	
	return @statistics;
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