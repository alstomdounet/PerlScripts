@rem = ' PERL for Windows NT - ratlperl must be in search path
@echo off
ratlperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
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
use Switch;
use File::Copy;
use Data::Dumper;
use ClearcaseMgt qw(getDirectoryStructure getAttribute);
use ClearquestMgt qw(connectCQ makeQuery);
use ClearquestCommon qw(checkPasswordAndAskIfIncorrect getAnswer);

use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use POSIX qw(strftime);
use Text::CSV;
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.5',
	TEMPLATE_ROOT_DIR => 'Templates',
	DEFAULT_TEMPLATE_DIR => '.',
	DEFAULT_TEMPLATE => 'Default',
	MAIN_TEMPLATE_NAME => 'main.tmpl',
	DEBUG_DATABASE_PREFIX => 'DebugDatabase',
};

INFO("Starting program (V ".PROGRAM_VERSION.")");

#########################################################
# loading of Configuration files
#########################################################
my $config = loadLocalConfig("ClearquestExtractor.config.xml", 'config.xml', ForceArray => qr/^(document|table)$/);
my $CQConfig = loadSharedConfig('Clearquest-config.xml');

#########################################################
# Using template files
#########################################################
my $SCRIPT_DIRECTORY = getScriptDirectory();
my $rootTemplateDirectory = "./";

my $defaultTemplateDir = DEFAULT_TEMPLATE_DIR.DEFAULT_TEMPLATE;
my $userTemplateDir = $SCRIPT_DIRECTORY.TEMPLATE_ROOT_DIR;

if (not -d $userTemplateDir) {
	mkdir($userTemplateDir);
	INFO("Creating user template directory ".TEMPLATE_ROOT_DIR);
	open FILE,">".$userTemplateDir."/readme.txt";
	printf FILE 'Templates files for current user has to be put in this directory';
	close FILE;
}

my $DEBUG_MODE = $config->{debugMode};
my $DATABASE_GEN_NEEDED = $config->{databaseGenNeeded};
WARN "!!!DEBUG mode is activated!!!" if $DEBUG_MODE;
WARN "!!!DATABASEGEN mode is activated!!!" if $DATABASE_GEN_NEEDED;

my $connectionRequired = $DATABASE_GEN_NEEDED or not $DEBUG_MODE;

my $Clearquest_password = checkPasswordAndAskIfIncorrect($CQConfig->{clearquest_shared}->{password}) if $connectionRequired;

#########################################################
# Generic fields customisation / replacing
#########################################################
my %GENERIC_FIELDS;
while (my ($key, $value) = each(%{$config->{genericFields}})) {
	LOGDIE("Key \"$key\" is not defined properly. Check your .xml file.") unless (ref($value) eq '' and $value ne '');
	
	if($value =~ /^\*\*ASK: (.*)\*\*$/) {
		DEBUG "Found dynamic field for \"$key\"";
		$GENERIC_FIELDS{$key} = getAnswer($1);
	}
	else {
		DEBUG "Found static field for \"$key\" > '$value'";
		$GENERIC_FIELDS{$key} = $value;
	}
}

my $BEFORE_REF = $config->{defaultParams}->{references}->{reference};
my $AFTER_REF = $config->{defaultParams}->{references}->{target};
my $ANALYSED_DIRECTORY =  $config->{defaultParams}->{analysedDirectory};
my $EQUIV_TABLE = loadCSV($config->{defaultParams}->{equivTable}) if $config->{defaultParams}->{equivTable};

INFO "Connecting to Clearquest with login $CQConfig->{clearquest_shared}->{login}";
connectCQ($CQConfig->{clearquest_shared}->{login}, $Clearquest_password, $CQConfig->{clearquest_shared}->{database}) if $connectionRequired;
my $debug_index = 0;

foreach my $document (@{$config->{documents}->{document}}) {
	INFO "Processing document \"$document->{title}\"";
	$document->{title} = 'Titre manquant' unless $document->{title};
	while(my($key, $value) = each(%GENERIC_FIELDS)) {
		$document->{title} =~ s/\*\*$key\*\*/$value/; 
	}
	$document->{defaultParams}->{references}->{reference} = localizeVariable($BEFORE_REF, $document->{defaultParams}->{references}->{reference});
	$document->{defaultParams}->{references}->{target} = localizeVariable($AFTER_REF, $document->{defaultParams}->{references}->{target});
	$document->{defaultParams}->{analysedDirectory} = localizeVariable($ANALYSED_DIRECTORY, $document->{defaultParams}->{analysedDirectory});
	
	my @tables;
	foreach my $table (@{$document->{tables}->{table}}) {
		INFO "Processing table \"$table->{title}\"";	
		$table->{title} = 'Titre manquant' unless $table->{title};
		while(my($key, $value) = each(%GENERIC_FIELDS)) {
			$table->{title} =~ s/\*\*$key\*\*/$value/; 
		}
		
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
		elsif($table->{type} =~ /^formattedByTemplate$/) {
			DEBUG "Requesting Formatted template";
			%tableElements = %{genFormattedByTemplateTable($table)};
			$tableElements{FORMATTED_BY_TEMPLATE} = 1;
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
	
	####################################################################
	# This section  manage templates
	####################################################################
	my $currentTemplate = DEFAULT_TEMPLATE;
	
	if($document->{templateDir}) {
		$currentTemplate = $document->{templateDir};
		INFO "Document \"$document->{title}\" requests template called \"$currentTemplate\"";
	}
	
	my $currentTemplateDir = DEFAULT_TEMPLATE_DIR;
	if(-d $userTemplateDir.'\\'.TEMPLATE_ROOT_DIR.'\\'.$currentTemplate) {
		$currentTemplateDir = $userTemplateDir;
		INFO "Using user-defined template scheme unstead of one used by default";
	}
	
	$currentTemplateDir = $currentTemplateDir.'\\'.TEMPLATE_ROOT_DIR.'\\'.$currentTemplate.'\\';
	my $currentTemplateWithEntryPoint = $currentTemplateDir.MAIN_TEMPLATE_NAME;
	
	DEBUG "template entry point used is \"$currentTemplateWithEntryPoint\"";
	LOGDIE "Template dir not found: \"$currentTemplateDir\" is not defined" unless -d $currentTemplateDir;
	LOGDIE "Template entry point not found: \"$currentTemplateWithEntryPoint\"" unless -r $currentTemplateWithEntryPoint;
	
	####################################################################
	# This section  manage templates
	####################################################################
	

	
	####################################################################
	# This section  manage complex documents
	####################################################################
	open (MAINFILE, ">".$SCRIPT_DIRECTORY.$document->{filename});
	my $mainTemplate = HTML::Template -> new( die_on_bad_params => 0, filename => $currentTemplateWithEntryPoint );
	
	my @finalTables;
	if($document->{indexedDocument}) {	
		DEBUG "This is a complex document";
		my $outputSubDir = $SCRIPT_DIRECTORY.$document->{indexedDocument}->{subDirectory}."\\";
		my $relativeSubDir = "./".$document->{indexedDocument}->{subDirectory}."/";
		mkdir $outputSubDir unless -d $outputSubDir;
		my $indexDocument = 1;
		
		foreach (@tables) {
			my $table = $_;
			$table->{LINK} = $relativeSubDir."table$indexDocument.html";
			
			DEBUG "Generating ".$relativeSubDir."table$indexDocument.html";
			open (SUBFILE, ">".$outputSubDir."table$indexDocument.html");
			
			my $subTemplate = HTML::Template -> new( die_on_bad_params => 0, filename => $currentTemplateDir.$document->{indexedDocument}->{template} );
			
			my @tmpTable;
			push(@tmpTable, $table);
			
			$subTemplate->param(TABLE => \@tmpTable);
			my $tm = strftime "%d-%m-%Y � %H:%M:%S", localtime;
			$subTemplate->param(DATE => $tm);
			$subTemplate->param(TITLE => $document->{title});
			
			print SUBFILE $subTemplate->output;
			close SUBFILE;
			$indexDocument++;
			push(@finalTables, $table);
		} 
	}
	else {
		@finalTables = @tables;
	}

	$mainTemplate->param(TABLES => \@finalTables);
	my $tm = strftime "%d-%m-%Y � %H:%M:%S", localtime;
	$mainTemplate->param(DATE => $tm);
	$mainTemplate->param(TITLE => $document->{title});
	
	print MAINFILE $mainTemplate->output;
	close(MAINFILE);
}

INFO "Processing results. It can take some time.";

sub genDocumentTable {
	my ($table) = @_;
	LOGDIE "This table is not available at the moment";
	
	my @fields = split(/\s*,\s*/, $config->{CQ_Queries}->{listCR}->{fieldsToRetrieve});
	my $listCR = usedebugQuery ("ChangeRequest", \@fields, $config->{CQ_Queries}->{listCR}, -GENERIC_VALUES => \%GENERIC_FIELDS);
	
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
	my $number = 0;
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
		$document{IS_ODD} = $number % 2;
		$number++;
		
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

sub usedebugQuery {
	if($DEBUG) {
		return makeQuery(@_, -USE_DEBUG_FILE => DEBUG_DATABASE_PREFIX."_".$debug_index++.'.db');
	}
	else {
		return makeQuery(@_);
	}

}

sub genFormattedByTemplateTable {
	my ($table, $debugStore) = @_;
	
	my @fieldsSort = genFilterFields($table->{fieldsSorting});
	my ($listFields, $listAliases) = genFieldNames($table->{fieldsToRetrieve});
	
	my $results = usedebugQuery("ChangeRequest", \@$listFields, $table->{filtering}, -SORT_BY => \@fieldsSort, -GENERIC_VALUES => \%GENERIC_FIELDS);
	
	my @resultsToPrint;
	my $number = 0;
	foreach my $result (@$results) {
		my @resultToPrint;
		my %transformedResult;
		
		$transformedResult{NUMBER} = ++$number;
		$transformedResult{IS_ODD} = $number % 2;

		for(my $index=0; $index < scalar(@$listAliases); $index++) {
		
			my $Field_Value = $result->{$listFields->[$index]};
			$Field_Value =~ s/\n/<br \/>\n/g;
			if ( $listAliases->[$index] =~ m/^\@(.*)\@$/)
			{
				my $Field_Name = $1;
				DEBUG "Field : $Field_Name";
				my $UC_Field_Content = uc($Field_Name . "_" . $Field_Value);
				$transformedResult{$UC_Field_Content}   = 1;
				DEBUG "Field : $UC_Field_Content";
				$transformedResult{$Field_Name} = $Field_Value;

			}
			else
			{
				$transformedResult{$listAliases->[$index]} = $Field_Value;
			}
		}
		push(@resultsToPrint, \%transformedResult);
	}
	
	my %tableProperties = (RESULTS => \@resultsToPrint);
	$tableProperties{COUNT_ROW} = $#resultsToPrint + 1;
	return \%tableProperties;
}

sub genClassicTable {
	my ($table, $debugStore) = @_;
	
	my @fieldsSort = genFilterFields($table->{fieldsSorting});
	my ($listFields, $listAliases) = genFieldNames($table->{fieldsToRetrieve});
	DEBUG "Field id was missing (it is required)." and unshift(@$listFields, 'id') unless grep(/^id$/, @$listFields);
	DEBUG "Field dbid was missing (it is required)." and unshift(@$listFields, 'dbid') unless grep(/^dbid$/, @$listFields);

	my @headerToPrint;
	foreach my $field (@$listAliases) {
		next if $field eq 'dbid' or $field eq 'id';
		push(@headerToPrint, { FIELD => ucfirst($field)});
	}

	
	my $results = usedebugQuery("ChangeRequest", \@$listFields, $table->{filtering}, -SORT_BY => \@fieldsSort, -GENERIC_VALUES => \%GENERIC_FIELDS);
	
	
	my @resultsToPrint;
	my $number = 0;
	foreach my $result (@$results) {
		my @resultToPrint;
		foreach my $field (@$listFields) {
			next if ($field eq 'dbid' or $field eq 'id');
			my $field = $result->{$field};
			$field =~ s/\n/<br \/>\n/g;
			push(@resultToPrint, { CONTENT => $field});
		}
		push(@resultsToPrint, { NUMBER => ++$number, DBID => $result->{'dbid'}, ID => $result->{'id'}, RESULT => \@resultToPrint, IS_ODD => $number % 2 });
	}
	
	my %tableProperties = (HEADER => \@headerToPrint, RESULTS => \@resultsToPrint);
	return \%tableProperties;
}

sub genGenericTable {
	my ($table) = @_;
	
	my @fieldsSort = genFilterFields($table->{fieldsSorting});
	my @fieldsGroup = genFilterFields($table->{fieldsGrouping});
	my ($listFields, $listAliases) = genFieldNames($table->{fieldsToRetrieve});

	my $results = usedebugQuery ($table->{clearquestType}, \@$listFields, $table->{filtering}, -SORT_BY => \@fieldsSort, -GENERIC_VALUES => \%GENERIC_FIELDS, -GROUP_BY=> \@fieldsGroup);
	
	
	my @headerToPrint;
	foreach my $field (@$listAliases) {
		push(@headerToPrint, { FIELD => $field});
	}
	
	my @resultsToPrint;
	my $number = 0;
	foreach my $result (@$results) {
		my @resultToPrint;
		foreach my $field (@$listFields) {
			my $field = $result->{$field};
			$field =~ s/\n/<br \/>\n/g;
			push(@resultToPrint, { CONTENT => $field});
		}
		push(@resultsToPrint, { NUMBER => ++$number, RESULT => \@resultToPrint, IS_ODD => $number % 2  });
	}
	
	my %tableProperties = (HEADER => \@headerToPrint, RESULTS => \@resultsToPrint);
	return \%tableProperties;
}

sub genFieldNames {
	my ($inputString) = @_;

	
	my @listFields;
	my @listAliases;
	
	my @tmplistFields = split(/\s*,\s*/, $inputString) if $inputString;
	
	foreach my $field (@tmplistFields) {
		my $alias = $field;
		if($field =~ /(\S+)\s+AS\s+'([^']+)'/i) {
			
			$field = $1;
			$alias = $2;
		}
		elsif($field =~ /(\S+)\s+AS\s+(\S+)/i) {
			$field = $1;
			$alias = $2;
		}
		elsif(!($field =~ /\s/)) {
			$alias = $field;
		}
		else {
			ERROR "Field \"$field\" is not syntaxically correct.";
			next;
		}
		
		DEBUG "Found equivalence for column names : \"$field\" => \"$alias\"" if "$field" ne "$alias";
		push(@listFields, lc($field));
		push(@listAliases, $alias);
	}
	
	return (\@listFields, \@listAliases);
	
}

sub genFilterFields {
	my ($inputString) = @_;
	$inputString = lc($inputString);
	my @list = split(/,\s*/, $inputString) if $inputString;
	return @list;
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