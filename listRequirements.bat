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
	PROGRAM_VERSION => '0.3',
	TEMPLATE_DIRECTORY => './Templates/',
	RISKS => '1_Risks',
	COVERAGE => '2_Coverage',
	MISSING_REQS => '2_mreq',
	NOT_REFERENCED => 'Not referenced',
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
	
	%fields = ('Exigence_CDC' => 0, 'Texte' => 2, 'Lot' => 6, 'Statut' => 7, 'Livrable' => 8);
	$source{TGC_List} = loadExcel($config->{documents}->{Assigned_REQ_TGC}->{FileName}, $config->{documents}->{Assigned_REQ_TGC}->{Sheet}, \%fields, 2);
	
	store(\%source, "Requirements_image.db");
}
else {
	WARN "Using DEBUG MODE. You have to delete \"Requirements_image.db\" to force refresh.";
	%source = %{retrieve("Requirements_image.db")};
}

INFO "Preprocessing source files";
WARN "Missing analysis for source requirements";
my ($list_CDC) = genList($source{CDC_LIST}, 'Exigence_CDC');
my ($list_VBN) = genList($source{VBN_LIST}, 'Exigence_VBN');
my ($list_REI, $stats) = genList($source{REI_LIST}, 'Exigence_REI');
DEBUG Dumper $stats;
my ($unfiltered_list_TGC) = genList($source{TGC_List}, 'Exigence_CDC');

my $list_TGC;
while (my ($key, $value) = each %$unfiltered_list_TGC) {
	$list_TGC->{$key} = $value if applicable_TGC_Requirement($value);
}

INFO "Generating exhaustive list for contractual requirements";
my %Contractual_List;
my %uniqueKeys = map { $_ => 1 } (keys %$list_CDC, keys %$list_TGC);

foreach my $sortable_key (keys %uniqueKeys) {
	if($list_CDC->{$sortable_key}) {
		$Contractual_List{$sortable_key} = $list_CDC->{$sortable_key};
	}
	else {
		$Contractual_List{$sortable_key} = $list_TGC->{$sortable_key};
	}
}

DEBUG "Contractual requirements have ".scalar(keys %Contractual_List)." occurences";

INFO "generating list of requirements compliant for REI side";
my ($list_REI_CDC, $errors_REI_CDC, $history_REI_CDC, $stats_REI_CDC) = joinRequirements(\%Contractual_List, $list_REI, $source{REI_CDC_List}, 'Exigence_CDC', 'Exigence_REI');

INFO "generating list of requirements compliant for VBN side";
my ($list_VBN_CDC, $errors_VBN_CDC, $history_VBN_CDC, $stats_VBN_CDC) = joinRequirements(\%Contractual_List, $list_VBN, $source{VBN_CDC_List}, 'Exigence_CDC', 'Exigence_VBN');

my %completeList = (REI => $list_REI_CDC, VBN => $list_VBN_CDC);

my @sortedList = sort { $Contractual_List{$a}{__SORT_KEY} cmp $Contractual_List{$b}{__SORT_KEY} } keys %Contractual_List;
INFO "Building prospective table";
my ($prosp_table) = buildProspectiveTable(\%Contractual_List);

INFO "Generating final mapping";
my @final_report;



foreach my $sorted_key (@sortedList) {
	my ($requirement) = fillCdCRequirement($Contractual_List{$sorted_key}, $prosp_table);

	push(@final_report, $requirement) if $requirement;
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

sub buildProspectiveTable {
	my($list_reference) = @_;

	my %equiv_list;
	
	DEBUG "Building intermediate prospective table";
	foreach my $reference (keys %{$list_reference}) {
		my $req = $list_reference->{$reference};
		if ($list_VBN_CDC->{$reference} and $list_REI_CDC->{$reference}) {
			foreach my $VBN_item (@{$list_VBN_CDC->{$reference}}) {
				foreach my $REI_item (@{$list_REI_CDC->{$reference}}) {
					next unless($VBN_item->{Req_ID} ne NOT_REFERENCED and $REI_item->{Req_ID} ne NOT_REFERENCED);
					$equiv_list{VBN_SIDE}{$VBN_item->{Req_ID}}{$REI_item->{Req_ID}}{List} = $VBN_item;
					push(@{$equiv_list{VBN_SIDE}{$VBN_item->{Req_ID}}{$REI_item->{Req_ID}}{References}}, $reference);
					
					$equiv_list{REI_SIDE}{$REI_item->{Req_ID}}{$VBN_item->{Req_ID}}{List} = $REI_item;
					push(@{$equiv_list{REI_SIDE}{$REI_item->{Req_ID}}{$VBN_item->{Req_ID}}{References}}, $reference);
				}
			}
		}
	}
	
	DEBUG "Building final prospective table";
	my %final_list;
	foreach my $side_key (keys %equiv_list) {
		my %side = %{$equiv_list{$side_key}};
		foreach my $main_level_key (keys %side) {
			my %main_level = %{$side{$main_level_key}};
			foreach my $sub_level_key (keys %main_level) {
				my %sub_level = %{$main_level{$sub_level_key}};
				my %final_item;
				$final_item{TEXTE} = $sub_level{List}{Texte};
				$final_item{REQ_ID} = $sub_level{List}{Req_ID};
				$final_item{REFERENCES} = join(', ', @{$sub_level{References}});
				$final_list{$side_key}{$sub_level_key}{$main_level_key} = \%final_item;
			}
		}
	}
	return \%final_list;
}

sub genList {
	my ($list, $key, $otherList) = @_;
	my @list = @$list;
	my %tmp;
	my %stats;
	my %finalList;
	%finalList = %$otherList if $otherList;
	
	foreach my $req (@list) {
		my $req_id = $req->{$key};
		my $sort_key = $req_id;
		if($req_id =~ /^REQ-(\d{6})-PY-(\w{13})$/) {
			$sort_key = "A-$2-PY-$1";
			$tmp{TYPE_1}{"$1"}++;
		}
		elsif($req_id =~ /^REQ-(\w{13})-(\d{4})$/) {
			$sort_key = "B-$1-$2";
			$tmp{TYPE_2}{"$2"}++;
		}
		elsif($req_id =~ /^REQ-RTS_(\d+)-(\d{4})$/) {
			$sort_key = "C-$1-$2";
			$tmp{TYPE_3}{"$1"}++;
		}
		elsif($req_id =~ /^REQ-VBN-(\d{4})$/) {
			$sort_key = "Z-$1";
			$tmp{TYPE_4}{"$1"}++;
		}
		elsif($req_id =~ /^TLMAIN_SyRB_PP_(\d{4})$/) {
			$sort_key = "A-$1";
			$tmp{TYPE_5}{"$1"}++;
		}
		elsif($req_id =~ /^RSAD(?:MR|)_TGC_(\d{3})$/) {
			$sort_key = "A-$1";
			$tmp{TYPE_6}{"$1"}++;
		}
		else {
			ERROR "\"$req_id\" is not sortable. It will be ignored";
			print Dumper $req;
			<>;
			next;
		}
		
		if ($finalList{$req_id}) {
			$stats{errors}{$req_id}++;
			ERROR "This requirement has been defined several times : \"$req_id\"";
			print Dumper $req;
			<>;
		}
		else {
			$req->{__SORT_KEY} = $sort_key;
			$finalList{$req_id} = $req;
		}
	}
	

	foreach my $type (keys %tmp) {
		my @rev_sorted_list = reverse sort keys %{$tmp{$type}};
		my $last_value = shift @rev_sorted_list;
		$stats{$type}{highest} = "$last_value";
		while (my $value = shift @rev_sorted_list) {
			if($last_value - $value > 1) {
				$stats{$type}{gaps} = "GAP between \"$value\" and \"$last_value\"";
			}
			$last_value = $value;
		}
	}
	return (\%finalList, \%stats);
}

sub fillCdCRequirement {
	my ($req, $prospect_table) = @_;
	my %requirement;
	my $reference = $req->{Exigence_CDC};
	$requirement{Texte} = $req->{Texte};
	$requirement{Req_ID} = $reference;
	
	my @list = ({ THIS_SIDE => 'REI', OTHER_SIDE => 'VBN'}, { THIS_SIDE => 'VBN', OTHER_SIDE => 'REI'});
	
	foreach my $item (@list) {
		if($completeList{$item->{THIS_SIDE}}{$reference}) {
			$requirement{'REQUIREMENTS_'.$item->{THIS_SIDE}} = $completeList{$item->{THIS_SIDE}}{$reference};
			
			my @list_reqs;
			foreach my $REI_REQ (@{$completeList{$item->{THIS_SIDE}}{$reference}}) {
				push(@list_reqs, $REI_REQ->{Req_ID});
			}
			
			my @list_missing_reqs;
			foreach my $VBN_REQ (@{$completeList{$item->{OTHER_SIDE}}{$reference}}) {
				my $VBN_REQ_ID = $VBN_REQ->{Req_ID};
				next if $VBN_REQ_ID eq NOT_REFERENCED;

				if(exists $prospect_table->{$item->{THIS_SIDE}.'_SIDE'}{$VBN_REQ_ID}) {
					foreach my $REI_REQ_ID (keys %{$prospect_table->{$item->{THIS_SIDE}.'_SIDE'}{$VBN_REQ_ID}}) {
						unless(grep(/^$REI_REQ_ID$/, @list_reqs)) {
							push(@list_missing_reqs, $prospect_table->{$item->{THIS_SIDE}.'_SIDE'}{$VBN_REQ_ID}{$REI_REQ_ID});
						}
					}
				}
			}

			$requirement{'PROSPECTIVES_'.$item->{THIS_SIDE}} = \@list_missing_reqs;
		}
	}

	$list_TGC->{$reference}{Lot} = $unfiltered_list_TGC->{$reference}{Lot} if $unfiltered_list_TGC->{$reference}{Lot};
	$list_TGC->{$reference}{Livrable} = $unfiltered_list_TGC->{$reference}{Livrable} unless $unfiltered_list_TGC->{$reference}{Livrable};
	$list_TGC->{$reference}{Lot} = 'Inconnu' unless $list_TGC->{$reference}{Lot};
	$list_TGC->{$reference}{Livrable} = 'Inconnu' unless $list_TGC->{$reference}{Livrable};
	$requirement{REF_DOC} = $list_TGC->{$reference}{Lot}." / ". $list_TGC->{$reference}{Livrable};
	$requirement{ORIGIN} = (applicable_TGC_Requirement($list_TGC->{$reference}))? 'REI' : 'VBN';
	return \%requirement;
}

sub applicable_TGC_Requirement {
	my ($item) = @_;
	return 1 if ($item->{Livrable} =~ /DID0000170295/) or ($item->{Lot} =~ /TCM3/);
	return 0;
}

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
		
		if($_->{$key_link} eq "" and ($_->{Applicabilite} =~ /Non/ or $_->{Applicabilite} =~ /Suiveur/)) {
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
		my $applicability = 'YES';
		$applicability = 'NO' if $_->{Applicabilite} and $_->{Applicabilite} =~ /Non/;
		$applicability = 'FOLLOWER' if $_->{Applicabilite} and $_->{Applicabilite} =~ /Suiveur/;
		
		if($valid_ref_required) {
			my $orig_item = $list_to_link->{$_->{$key_link}};
			$item{Texte} = $orig_item->{Texte};
		}
		else {
			$item{Texte} = $_->{History};
			$item{Texte} = 'Justification is not yet written...' unless $item{Texte};
		}
		
		$item{Applicabilite} = $applicability;
		$item{Req_ID} = (defined ($_->{$key_link}) and "$_->{$key_link}" ne '') ? $_->{$key_link} : NOT_REFERENCED;
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
	my ($filename, $sheet, $header, $beginLine) = @_;

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
	
	$beginLine = 1 unless $beginLine;
    for(my $iR = $beginLine ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
		my %line;
		my $emptyRow = 1;
		
		foreach my $key (keys(%$header)) {
			my $iC = $header->{$key};
			my $oWkC = "";
			if(not defined $oWkS->{Cells}[$iR][$iC]) {
				$oWkC = "";
			}
			else {
				$oWkC = "".$oWkS->{Cells}[$iR][$iC]->Value."";
				$emptyRow = 0 if $oWkC;
			}
			
			$line{$key} = $oWkC ;
        }
		
		$line{__LineNumber} = $iR;
		push(@elements, \%line) unless $emptyRow;
    }
	
	return \@elements;
	
}

__END__
:endofperl
pause