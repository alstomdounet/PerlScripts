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
use DisplayMgt qw(displayBox);
use File::Copy;
use Data::Dumper;
use ClearcaseMgt qw(getDirectoryStructure getAttribute);
use ClearquestMgt qw(connectCQ makeQuery);
use ClearquestCommon qw(checkPasswordAndAskIfIncorrect getAnswer);

use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use Time::localtime;
use POSIX qw(strftime);
use Text::CSV;
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.2',
	TEMPLATE_ROOT_DIR => 'Templates',
	DEFAULT_TEMPLATE_DIR => '.',
	DEFAULT_TEMPLATE => 'Default',
	MAIN_TEMPLATE_NAME => 'main.tmpl',
	DEBUG_DATABASE => 'DebugDatabase.db',
};

INFO("Starting program (V ".PROGRAM_VERSION.")");

#########################################################
# loading of Configuration files
#########################################################
my $config = loadLocalConfig("genBULTEC.config.xml", 'config.xml', ForceArray => qr/^(document|table)$/);
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

my $debugMode = $config->{debugMode};
my $databaseGenNeeded = !($debugMode and -r DEBUG_DATABASE);
WARN "DEBUG mode is activated" if $debugMode;
WARN "results won't be updated (DEBUG mode and a DEBUG database)" unless $databaseGenNeeded;

my $Clearquest_password = checkPasswordAndAskIfIncorrect($CQConfig->{clearquest_shared}->{password}) if $databaseGenNeeded;

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
connectCQ($CQConfig->{clearquest_shared}->{login}, $Clearquest_password, $CQConfig->{clearquest_shared}->{database}) if $databaseGenNeeded;

foreach my $document (@{$config->{documents}->{document}}) {
	INFO "Processing document \"$document->{title}\"";
	$document->{title} = 'Titre manquant' unless $document->{title};
	while(my($key, $value) = each(%GENERIC_FIELDS)) {
		$document->{title} =~ s/\*\*$key\*\*/$value/; 
	}
	$document->{defaultParams}->{references}->{reference} = localizeVariable($BEFORE_REF, $document->{defaultParams}->{references}->{reference});
	$document->{defaultParams}->{references}->{target} = localizeVariable($AFTER_REF, $document->{defaultParams}->{references}->{target});
	$document->{defaultParams}->{analysedDirectory} = localizeVariable($ANALYSED_DIRECTORY, $document->{defaultParams}->{analysedDirectory});
	
	my $currentTemplate = DEFAULT_TEMPLATE;
	
	if($document->{template}) {
		$currentTemplate = $document->{template};
		INFO "Document \"$document->{title}\" requests template called \"$currentTemplate\"";
	}
	
	my $currentTemplateDir = DEFAULT_TEMPLATE_DIR;
	if(-d $userTemplateDir.'\\'.TEMPLATE_ROOT_DIR.'\\'.$currentTemplate) {
		$currentTemplateDir = $userTemplateDir;
		INFO "Using user-defined template scheme unstead of one used by default";
	}
	
	my $currentTemplateWithEntryPoint = $currentTemplateDir.'\\'.TEMPLATE_ROOT_DIR.'\\'.$currentTemplate.'\\'.MAIN_TEMPLATE_NAME;
	DEBUG "template entry point used is \"$currentTemplateWithEntryPoint\"";
	LOGDIE "Request template scheme \"$currentTemplate\" in directory \"$currentTemplateDir\" is not defined" unless -d $currentTemplateDir.'\\'.TEMPLATE_ROOT_DIR.'\\'.$currentTemplate;
	LOGDIE "Request template scheme \"$currentTemplate\" in directory \"$currentTemplateDir\" is not defined correctly" unless -r $currentTemplateWithEntryPoint;
	
	my @tables;
	if($databaseGenNeeded) {
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
		store(\@tables, DEBUG_DATABASE);
	}
	else {
		my $results = retrieve(DEBUG_DATABASE);
		@tables = @$results;
	}
	
	open (FILE, ">".$SCRIPT_DIRECTORY.$document->{filename});
		
	my $t = HTML::Template -> new( filename => $currentTemplateWithEntryPoint );

	$t->param(TABLES => \@tables);
	my $tm = strftime "%d-%m-%Y à %H:%M:%S", gmtime;
	$t->param(DATE => $tm);
	$t->param(TITLE => $document->{title});

	print FILE $t->output;
	close(FILE);
}

INFO "Processing results. It can take some time.";

sub genDocumentTable {
	my ($table) = @_;
	LOGDIE "This table is not available at the moment";
	
	my @fields = split(/\s*,\s*/, $config->{CQ_Queries}->{listCR}->{fieldsToRetrieve});
	my $listCR = makeQuery("ChangeRequest", \@fields, $config->{CQ_Queries}->{listCR}, -GENERIC_VALUES => \%GENERIC_FIELDS);
	
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

	
	my $results = makeQuery("ChangeRequest", \@$listFields, $table->{filtering}, -SORT_BY => \@fieldsSort, -GENERIC_VALUES => \%GENERIC_FIELDS);

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
	my ($listFields, $listAliases) = genFieldNames($table->{fieldsToRetrieve});

	my $results = makeQuery($table->{clearquestType}, \@$listFields, $table->{filtering}, -SORT_BY => \@fieldsSort, -GENERIC_VALUES => \%GENERIC_FIELDS);	
	
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