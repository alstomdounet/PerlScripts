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
	PROGRAM_VERSION => '0.1 beta',
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
#connectCQ($CQConfig->{clearquest_shared}->{login}, $CQConfig->{clearquest_shared}->{password}, $CQConfig->{clearquest_shared}->{database});

foreach my $document (@{$config->{documents}->{document}}) {
	INFO "Processing document \"$document->{title}\"";
	$document->{title} = 'Titre manquant' unless $document->{title};
	my $BEFORE_REF_DOC = localizeVariable($BEFORE_REF, $document->{defaultParams}->{references}->{reference});
	my $AFTER_REF_DOC = localizeVariable($AFTER_REF, $document->{defaultParams}->{references}->{target});
	my $ANALYSED_DIRECTORY_DOC = localizeVariable($ANALYSED_DIRECTORY, $document->{defaultParams}->{analysedDirectory});
	
	my @tables;
	
	foreach my $table (@{$document->{tables}->{table}}) {
		INFO "Processing table \"$table->{title}\"";	
		$table->{title} = 'Titre manquant' unless $table->{title};
		
		my %tableElements = ('TABLE_NAME', $table->{title});
		
		if(not $table->{type}) {
			DEBUG "Requesting classic template";
			push(@tables, genClassicTable($table));
		}
		elsif($table->{type} =~ /^generic$/) {
			DEBUG "Requesting generic template";
			$tableElements{GENERICLIST} = 1;
		}
		elsif ($table->{type} =~ /^documentation$/) {
			DEBUG "Requesting documentation template";
			$table->{references}->{reference} = localizeVariable($BEFORE_REF_DOC, $table->{references}->{reference});
			$table->{references}->{target} = localizeVariable($AFTER_REF_DOC, $table->{references}->{target});
			$table->{analysedDirectory} = localizeVariable($ANALYSED_DIRECTORY_DOC, $table->{analysedDirectory});

			$tableElements{DOCLIST} = 1;
		}
		else {
			LOGDIE "Type $table->{type} is unknown";
		}
		
		# makeCQQuery($config->{CQ_Queries}->{listVersions}, 'versions.db');
		# my $listCR = makeCQQuery($config->{CQ_Queries}->{listCR}, 'AllCR.db');
		
		# my $docBiasis = getListOfBiases($listCR);

		# open FILE,">debug.txt";
		# print FILE Dumper $docBiasis;
		# close FILE;
		
		# my $BEFORE_LIST = getStructUsingReference($ANALYSED_DIRECTORY_TABLE, $BEFORE_REF_TABLE);
		# my $AFTER_LIST = getStructUsingReference($ANALYSED_DIRECTORY_TABLE, $AFTER_REF_TABLE);
		# my $results = compareLabels($ANALYSED_DIRECTORY_TABLE, $BEFORE_LIST, $AFTER_LIST);
		
		# #my $results = retrieve('test.db');
		# store($results, 'test.db');
		
		# buildTable($EQUIV_TABLE, $results, $docBiasis);
	}
	
	open (FILE, ">".$SCRIPT_DIRECTORY.$document->{filename});
		
	my $t = HTML::Template -> new( filename => TEMPLATE_DIRECTORY."main.tmpl" );

	$t->param(TABLES => \@tables);
	my $tm = strftime "%d-%m-%Y à %H:%M:%S", gmtime;
	$t->param(DATE => $tm);

	print FILE $t->output;
	close(FILE);
}

INFO "Processing results. It can take some time.";

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

sub makeCQQuery {
	my ($query, $file) = @_;
	
	return retrieve($file) if -r $file;
	
	my @fields = split(/\s*,\s*/, $query->{fieldsToRetrieve});
	my $results = makeQuery($query->{ClearquestType}, \@fields, $query->{filtering});
	store($results, $file) if $file;
	return $results;
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

	# unlink(OUT_FILENAME);
	# open (FILE, ">".OUT_FILENAME);
		
	# my $t = HTML::Template -> new( filename => "./listDocs.tmpl" );

	# $t->param(BEFORE_REF => $BEFORE_REF);
	# $t->param(AFTER_REF => $AFTER_REF);
	# $t->param(RESULTS => \@results);
	# my $tm = strftime "%d-%m-%Y à %H:%M:%S", gmtime;
	# $t->param(DATE => $tm);

	# print FILE $t->output;
	# close(FILE);
}

sub genClassicTable {
	my ($table) = @_;
	
	my (@fieldsSort, @listFields);
	LOGDIE "You have to lowercase those items first";
	@listFields = split(/,\s*/, $table->{fieldsToRetrieve}) if $table->{fieldsToRetrieve};
	DEBUG "Field dbid was missing (it is required)." and push(@listFields, 'dbid') unless grep(/^dbid$/, @listFields);
	DEBUG "Field id was missing (it is required)." and push(@listFields, 'id') unless grep(/^id$/, @listFields);

	@fieldsSort = split(/,\s*/, $table->{fieldsSorting}) if $table->{fieldsSorting};
	my $results = makeQuery($table->{ClearquestType}, \@listFields, $table->{filtering}, \@fieldsSort);

	my @headerToPrint;
	push(@headerToPrint, { FIELD => '#'});
	foreach my $field (@listFields) {
		next if $field eq 'dbid';
		push(@headerToPrint, { FIELD => $field});
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
	my ($refDirectory, $beforeList, $afterList) = @_;
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