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
use ClearcaseMgt qw(getDirectoryStructure getAttribute);
use ClearquestMgt qw(connectCQ makeQuery);
use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use Time::localtime;
use POSIX qw(strftime);
use Text::CSV;
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.2',
	TEMPLATE_DIRECTORY => './Templates/',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";

my $config = loadLocalConfig(getScriptName().'.config.xml', 'config.xml', ForceArray => qr/^(document|table)$/);
my $CQConfig = loadSharedConfig('Clearquest-config.xml');

backCopy('config.xml', getScriptName().'.config.xml');

my $SCRIPT_DIRECTORY = getScriptDirectory();

my $BEFORE_REF = $config->{defaultParams}->{references}->{reference};
my $AFTER_REF = $config->{defaultParams}->{references}->{target};
my $ANALYSED_DIRECTORY =  $config->{defaultParams}->{analysedDirectory};
my $EQUIV_TABLE = loadCSV($config->{defaultParams}->{equivTable}) if $config->{defaultParams}->{equivTable};

INFO "Connecting to Clearquest with login $CQConfig->{clearquest_shared}->{login}";
connectCQ($CQConfig->{clearquest_shared}->{login}, $CQConfig->{clearquest_shared}->{password}, $CQConfig->{clearquest_shared}->{database});

foreach my $document (@{$config->{documents}->{document}}) {
	INFO "Processing document \"$document->{title}\"";
	$document->{title} = 'Titre manquant' unless $document->{title};
	$document->{defaultParams}->{references}->{reference} = localizeVariable($BEFORE_REF, $document->{defaultParams}->{references}->{reference});
	$document->{defaultParams}->{references}->{target} = localizeVariable($AFTER_REF, $document->{defaultParams}->{references}->{target});
	$document->{defaultParams}->{analysedDirectory} = localizeVariable($ANALYSED_DIRECTORY, $document->{defaultParams}->{analysedDirectory});
	
	my @tables;
	
	foreach my $table (@{$document->{tables}->{table}}) {
		INFO "Processing table \"$table->{title}\"";	
		$table->{title} = 'Titre manquant' unless $table->{title};
		
		my %tableElements;
		if(not $table->{type}) {
			DEBUG "Requesting classic template";
			%tableElements = %{genClassicTable($table)};
		}
		elsif($table->{type} =~ /^generic$/) {
			DEBUG "Requesting generic template";
			%tableElements = %{genGenericTable($table)};
			$tableElements{GENERICLIST} = 1;
		}
		elsif ($table->{type} =~ /^documentation$/) {
			DEBUG "Requesting documentation template";
			$table->{references}->{reference} = localizeVariable($document->{defaultParams}->{references}->{reference}, $table->{references}->{reference});
			$table->{references}->{target} = localizeVariable($document->{defaultParams}->{references}->{target}, $table->{references}->{target});
			$table->{analysedDirectory} = localizeVariable($document->{defaultParams}->{analysedDirectory}, $table->{analysedDirectory});

			%tableElements = %{genDocumentTable($table)};
			$tableElements{DOCLIST} = 1;
		}
		else {
			LOGDIE "Type $table->{type} is unknown";
		}
		
		$tableElements{TABLE_NAME} = $table->{title};
		push(@tables, \%tableElements);
	}
	
	open (FILE, ">".$SCRIPT_DIRECTORY.$document->{filename});
		
	my $t = HTML::Template -> new( filename => TEMPLATE_DIRECTORY."main.tmpl" );

	$t->param(TABLES => \@tables);
	my $tm = strftime "%d-%m-%Y � %H:%M:%S", gmtime;
	$t->param(DATE => $tm);

	print FILE $t->output;
	close(FILE);
}

INFO "Processing results. It can take some time.";

sub genDocumentTable {
	my ($table) = @_;
	LOGDIE "This table is not available at the moment";
	
	my @fields = split(/\s*,\s*/, $config->{CQ_Queries}->{listCR}->{fieldsToRetrieve});
	my $listCR = makeQuery("ChangeRequest", \@fields, $config->{CQ_Queries}->{listCR});
	
	my $docBiasis = getListOfBiases($listCR);
	my $results = compareLabels($table->{analysedDirectory}, $table->{references}->{reference}, $table->{references}->{target});
	return buildTable($EQUIV_TABLE, $results, $docBiasis);
}

sub isAssigned {
	my ($state, $substate) = @_;
	return 1 if $state eq 'Assigned' or $state eq 'Analysed';
	return 1 if $state eq 'Realised' and $substate ne 'complete';
	return 0;
}

sub getListOfBiases {
	my ($listCR) = @_;
	DEBUG "Building parent child tree";
	my %parentList;
	my %CRList;
	foreach my $CR (@$listCR) {
		$CRList{$CR->{id}} = $CR;
		push @{$parentList{$CR->{id}}}, $CR->{child_record} if $CR->{child_record};
	}
	
	my %docBiasis;
	DEBUG "Finding potential documentation biasis";
	foreach my $CR (@$listCR) {
		next unless $CR->{'sub_system.name'} eq 'SyFRSCC';
		next unless isAssigned ($CR->{state}, $CR->{substate});
		
		my $biasFound = 0;
		if($CR->{parent_record}) {
			my $parentCR = $CRList{$CR->{parent_record}};
			$biasFound++ if isADocumentBias($parentCR->{'sub_system.name'}, $CR->{'component.name'}, $parentCR->{'component.name'}, $parentCR->{state}, $parentCR->{substate});
			foreach my $childID (@{$parentList{$CR->{parent_record}}}) {
				my $childCR = $CRList{$childID};
				$biasFound++ if isADocumentBias($childCR->{'sub_system.name'}, $CR->{'component.name'}, $childCR->{'component.name'}, $childCR->{state}, $childCR->{substate});
			}
		}
		
		if($CR->{child_record}) {
			my $childCR = $CRList{$CR->{child_record}};
			$biasFound++ if isADocumentBias($childCR->{'sub_system.name'}, $CR->{'component.name'}, $childCR->{'component.name'}, $childCR->{state}, $childCR->{substate});
		}
		
		$biasFound++ if (not $CR->{parent_record} and not $CR->{child_record});
		
		DEBUG $CR->{id}." is a bias" and push @{$docBiasis{$CR->{'component.name'}}{$CR->{'scheduled_version.name'}}{$CR->{id}}}, $CR if $biasFound;
	}
	
	return \%docBiasis;
}

sub isADocumentBias {
	my ($sub_system, $refComponent, $component, $state, $substate) = @_;
	return 0 if $sub_system ne 'SyFDD' or $component ne $refComponent;
	return 0 if $state eq 'Assigned' or $state eq 'Analysed';
	return 0 if $state eq 'Realised' and $substate ne 'complete';
	return 1;
}

sub buildTable {
	my ($equivTable, $results, $biasList) = @_;
	my @results;
	foreach my $key (keys %$results) {
		my %document;
		$document{DOCUMENT} = $key;

		foreach my $testedItem (keys %$equivTable) {
			if($key =~ /$testedItem/) {
				$document{CODE_DOC} = $equivTable->{$testedItem}->[0];
				$document{DOCUMENT} = $equivTable->{$testedItem}->[1];
				delete $equivTable->{$testedItem};
				last;
			}
		}
		
		if ($document{CODE_DOC} and $biasList->{$document{CODE_DOC}}) {
			my $list = $biasList->{$document{CODE_DOC}};
			my @list;
			foreach my $key (sort keys %$list) {
				my $version = $list->{$key};
				my @CRList;
				foreach my $key (sort keys %$version) {
					push(@CRList, { ID => $key } );
				}
				push(@list, { SCHEDULED_VERSION => $key , CRLIST => \@CRList } );
			}
			
			$document{BIASLIST} = \@list;
		}
		
		my @fields = @{$results->{$key}};
		my $status = selectStatus($fields[0], $fields[1]);
		$document{STATUS} = $status if $status;
		$document{BEFORE_TEXT} = formatVersion($fields[0]);
		$document{AFTER_TEXT} = formatVersion($fields[1]);

		
		push @results, \%document;
	}

	@results = sort {
			return -1 if ($a->{CODE_DOC} and not $b->{CODE_DOC});
			return 1 if (not $a->{CODE_DOC} and $b->{CODE_DOC});
			return ($a->{DOCUMENT} cmp $b->{DOCUMENT}) unless ($a->{CODE_DOC});
			return $a->{CODE_DOC} cmp $b->{CODE_DOC} or $a->{DOCUMENT} cmp $b->{DOCUMENT};
		 } @results;

	my %results = (BEFORE_REF => $BEFORE_REF, AFTER_REF => $AFTER_REF, RESULTS => \@results);
	return \%results;
}

sub genClassicTable {
	my ($table) = @_;
	
	my (@fieldsSort, @listFields);
	$table->{fieldsToRetrieve} = lc($table->{fieldsToRetrieve});
	@fieldsSort = split(/,\s*/, $table->{fieldsSorting}) if $table->{fieldsSorting};
	@listFields = split(/,\s*/, $table->{fieldsToRetrieve}) if $table->{fieldsToRetrieve};
	DEBUG "Field id was missing (it is required)." and unshift(@listFields, 'id') unless grep(/^id$/, @listFields);
	DEBUG "Field dbid was missing (it is required)." and unshift(@listFields, 'dbid') unless grep(/^dbid$/, @listFields);

	my $results = makeQuery("ChangeRequest", \@listFields, $table->{filtering}, \@fieldsSort);

	my @headerToPrint;
	foreach my $field (@listFields) {
		next if $field eq 'dbid' or $field eq 'id';
		push(@headerToPrint, { FIELD => ucfirst($field)});
	}
	
	my @resultsToPrint;
	my $number = 0;
	foreach my $result (@$results) {
		my @resultToPrint;
		foreach my $field (@listFields) {
			next if ($field eq 'dbid' or $field eq 'id');
			my $field = $result->{$field};
			$field =~ s/\n/<br \/>\n/g;
			push(@resultToPrint, { CONTENT => $field});
		}
		push(@resultsToPrint, { NUMBER => ++$number, DBID => $result->{'dbid'}, ID => $result->{'id'}, RESULT => \@resultToPrint });
	}
	
	my %tableProperties = (HEADER => \@headerToPrint, RESULTS => \@resultsToPrint);
	return \%tableProperties;
}

sub genGenericTable {
	my ($table) = @_;
	
	my (@fieldsSort, @listFields);
	$table->{fieldsToRetrieve} = lc($table->{fieldsToRetrieve});
	@fieldsSort = split(/,\s*/, $table->{fieldsSorting}) if $table->{fieldsSorting};
	@listFields = split(/,\s*/, $table->{fieldsToRetrieve}) if $table->{fieldsToRetrieve};

	my $results = makeQuery($table->{clearquestType}, \@listFields, $table->{filtering}, \@fieldsSort);	
	
	my @headerToPrint;
	foreach my $field (@listFields) {
		push(@headerToPrint, { FIELD => ucfirst($field)});
	}
	
	my @resultsToPrint;
	my $number = 0;
	foreach my $result (@$results) {
		my @resultToPrint;
		foreach my $field (@listFields) {
			my $field = $result->{$field};
			$field =~ s/\n/<br \/>\n/g;
			push(@resultToPrint, { CONTENT => $field});
		}
		push(@resultsToPrint, { NUMBER => ++$number, RESULT => \@resultToPrint });
	}
	
	my %tableProperties = (HEADER => \@headerToPrint, RESULTS => \@resultsToPrint);
	return \%tableProperties;
}

sub localizeVariable {
	my ($generalValue, $localizedValue) = @_;
	return $localizedValue if $localizedValue;
	return $generalValue; 
}

sub formatVersion {
	my ($element) = @_;
	
	return 'N/A' unless($element->{revision});
	return $element->{revision}."<br />(pas de gestion documentaire)" unless($element->{Version} or $element->{State});
	return $element->{Version} if ($element->{State} == 10);
	return "$element->{Version}<br />(State $element->{State})";
}

sub compareLabels {
	my ($refDirectory, $BEFORE_REF_TABLE, $AFTER_REF_TABLE) = @_;
	
	my $beforeList = getStructUsingReference($refDirectory, $BEFORE_REF_TABLE);
	my $afterList = getStructUsingReference($refDirectory, $AFTER_REF_TABLE);

	$refDirectory = quotemeta($refDirectory);
	
	my %elements;
	foreach my $element (keys %$beforeList, keys %$afterList) { $elements{$element}++ }

	my %results;
	foreach my $element (keys %elements) {
		my (%beforeVersion, %afterVersion);
		next if -d $element;

		if($beforeList->{$element}) {
			$beforeVersion{State} = getAttribute($element, "State", $beforeList->{$element});
			$beforeVersion{Version} = getAttribute($element, "Version", $beforeList->{$element});
			$beforeVersion{revision} = $beforeList->{$element};
		}
		
		if($afterList->{$element}) {
			$afterVersion{State} = getAttribute($element, "State", $afterList->{$element});
			$afterVersion{Version} = getAttribute($element, "Version", $afterList->{$element});
			$afterVersion{revision} = $afterList->{$element};
		}
		
		$element =~ s/^$refDirectory\\(.*)/$1/;
		my @list = (\%beforeVersion, \%afterVersion);
		$results{$element} = \@list;
	}
	
	return \%results;
}

sub selectStatus {
	my ($beforeItem, $afterItem) = @_;
	return 'new' unless $beforeItem->{revision};
	return 'deleted' unless $afterItem->{revision};
	
	my $status = ($beforeItem->{Version} cmp $afterItem->{Version});
	$status = ($beforeItem->{State} <=> $afterItem->{State}) unless $status;
	return 'upgraded' if $status < 0;
	return 'downgraded' if $status > 0;
	
	return '';
}

sub getStructUsingReference {
	my ($directory, $reference) = @_; 
	return getDirectoryStructure($directory) if ($reference =~ /^[\\\/]main[\\\/]latest/i);
	return getDirectoryStructure($directory, -label => $reference) if ($reference =~ /^[^\/\\\{\}\(\)]+$/);
	LOGDIE "Script is not able to handle references like \"$reference\"";
}

sub loadCSV {
	my $file = shift;
	my %rows;
	my $csv = Text::CSV->new ( { binary => 1, sep_char => ';'} )  # should set binary attribute.
                 or die "Cannot use CSV: ".Text::CSV->error_diag ();
 
	open my $fh, $file or die "$file: $!";
	while ( my $row = $csv->getline( $fh ) ) {
		next unless $row->[0];
		my $key = shift @$row;
		$rows{$key} = $row;
	}
	close $fh;
	return \%rows;
}

__END__
:endofperl
pause