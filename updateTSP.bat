@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(lib);
use strict;
use warnings;
use Common;
use Data::Dumper;
use Digest::MD5 qw(md5);
use File::Copy;
use HTML::Template;
use Text::CSV;
use Cwd;

#Load XML reading class
my $xml = new XML::Simple();

# Read XML file
my %data = loadConfig("config.xml", KeyAttr=>[], ForceArray => 1);
my $data = \%data;

my $oldPath = $data->{OLDProject}[0]{path}[0];
my $newPath = $data->{NEWProject}[0]{path}[0];


{
	#Filtering of CSV files
	INFO "Filtering ".$data->{OLDProject}[0]{crossrefCSV}[0];
	my %hashtableOLD = filterLinesCSV($data->{OLDProject}[0]{crossrefCSV}[0],$data->{OLDProject}[0]{filterCrossRef}[0],$data->{CsvFilterOptions}[0]);
	INFO "Filtering ".$data->{NEWProject}[0]{crossrefCSV}[0];
	my %hashtableNEW = filterLinesCSV($data->{NEWProject}[0]{crossrefCSV}[0],$data->{NEWProject}[0]{filterCrossRef}[0],$data->{CsvFilterOptions}[0]);
	if(exists($data->{CsvFilterOptions}[0]{deleteIdenticalLines}))
	{
		INFO "Filtering identical lines in ".$data->{OLDProject}[0]{filterCrossRef}[0];
		deleteIdenticalLines($data->{OLDProject}[0]{filterCrossRef}[0],$data->{OLDProject}[0]{filterCrossRef}[0], %hashtableNEW);
		INFO "Filtering identical lines in ".$data->{NEWProject}[0]{filterCrossRef}[0];
		deleteIdenticalLines($data->{NEWProject}[0]{filterCrossRef}[0],$data->{NEWProject}[0]{filterCrossRef}[0], %hashtableOLD);
	}
}



{
	#Filtering of CSV files
	unlink("./analysisReport.txt");
	open (REP, ">./analysisReport.htm");
	
	#print "Checking XML file";
	
	INFO "Beginning Analysis of CSV files\n";
	my %OLDExtraction = loadCsvInMemory($data->{OLDProject}[0]{filterCrossRef}[0], 'Instance', 'Nom');	
	my %NEWExtraction = loadCsvInMemory($data->{NEWProject}[0]{filterCrossRef}[0], 'Instance', 'Nom');	

	my @lineKeys = (keys(%OLDExtraction), keys(%NEWExtraction));
	my %temp;
    foreach (@lineKeys) {
    	$temp{$_} = 1;
    }
    @lineKeys = sort keys %temp;
	
	#Extracting headers
	my @OLDHeader = loadHeaders($data->{OLDProject}[0]{filterCrossRef}[0]);
	my @NEWHeader = loadHeaders($data->{NEWProject}[0]{filterCrossRef}[0]);
	my @BOTHheader = @OLDHeader;
	%temp = ();
	foreach my $header (@OLDHeader)
	{
		$temp{$header} = 1;
	}
	foreach my $header (@NEWHeader)
	{
		push(@BOTHheader, $header) if not exists($temp{$header});
	}
	
	my @NEWOnly;
	my @OLDOnly;
	my @conflicts;
	foreach my $lineKey (@lineKeys)
	{
		my %tmp = (VARIABLE => $lineKey);
		push(@NEWOnly , \%tmp) if not exists $OLDExtraction{$lineKey};
		push(@OLDOnly , \%tmp) if not exists $NEWExtraction{$lineKey};
		if(exists($OLDExtraction{$lineKey}) and exists($NEWExtraction{$lineKey}))
		{
			my @diffHeaders;
			my %OLDlineContent = %{$OLDExtraction{$lineKey}};
			my %NEWlineContent = %{$NEWExtraction{$lineKey}};
			
			#Testing each fields
			foreach my $header (@BOTHheader)
			{
				my %tmp2 = (FIELD => $header,
							VALUE_OLD => "Not defined",
							VALUE_NEW => "Not defined");
				
				$tmp2{VALUE_OLD} = $OLDlineContent{$header} if exists($OLDlineContent{$header});
				$tmp2{VALUE_NEW} = $NEWlineContent{$header} if exists($NEWlineContent{$header});
				
				if(exists($OLDlineContent{$header}) ^ exists($NEWlineContent{$header}))
				{
					push(@diffHeaders, \%tmp2);
				}
				else
				{
					push(@diffHeaders, \%tmp2) if $OLDlineContent{$header} ne $NEWlineContent{$header};
				}
			}
			
			if(scalar(@diffHeaders > 0))
			{
				$tmp{FIELDS} = \@diffHeaders;
				push(@conflicts, \%tmp);
			}
		}
	}
	
	# Create a new HTML::Template object
	my $t = HTML::Template -> new( filename => "./ScriptData/AnalysisReport.tmpl" );

	$t->param(FILE_OLD => $data->{OLDProject}[0]{filterCrossRef}[0]);
  	$t->param(FILE_NEW => $data->{NEWProject}[0]{filterCrossRef}[0]);
  	$t->param(OLD_ONLY => \@OLDOnly);
  	$t->param(NEW_ONLY => \@NEWOnly);
  	$t->param(CONFLICTS => \@conflicts);
	
	print REP $t->output;
	
	close(REP);
}

print "Program is finished.";
my $output = <>;

sub printDup
{
	my $handle = shift;
	my $text = shift;
	print $text;
	print $handle $text;
}

sub filterLinesCSV
{
	my $inFile = shift;
	my $outFile = shift;
	my $filterList = shift;

	my $csv = Text::CSV->new ( { binary => 1, sep_char => ";" } );
	open( IN, "$inFile" ) || LOGDIE("Could not open file!: $!");
	binmode(IN);
	
	open( OUT, ">$outFile" ) || LOGDIE("Could not open file $outFile: $!");
	binmode(OUT);
	
	my %headerArray;

	
	my $header = <IN>;
	print OUT $header;
	$csv->parse( $header );
	my @headerLine = $csv->fields();
	
	my $columnNumber = 0;
	foreach my $element (@headerLine)
	{
		$element =~ s/\s+$//;
		$element =~ s/\s+$//;
		$headerArray{$element} = $columnNumber++;
	}
	
	my %deletedElements;
	my %hashTable;
	my $lineNumber = 2;
	foreach my $line (<IN>)
	{
		$csv->parse( $line );
		my @elements = $csv->fields();
		my $lineIsValid = 1;

		if((scalar(@elements)) != scalar(keys(%headerArray)))
		{
			ERROR " - There is ".(scalar(@elements))." columns in line $lineNumber, it should be ".(scalar(keys(%headerArray))).". Check if no extra \";\" are present in text columns.\n";
			$lineIsValid = 0;
		}
		
		if(exists($filterList->{'deleteNonProducers'}[0]))
		{
			my $filter = $filterList->{'deleteNonProducers'}[0];
			if(!exists($headerArray{$filter->{variable}}) or !exists($headerArray{$filter->{producer}}))
			{
				FATAL ("Correct syntax to defined property to delete non-producer variables is <deleteNonProducer variable=\"name_of_variable_column\" producer=\"name_of_producer_column\" />");
				<>;
				exit;
			}
			else
			{
				my $variable = $elements[$headerArray{$filter->{variable}}];
				my $producer = $elements[$headerArray{$filter->{producer}}];
				$lineIsValid = 0 if($producer ne "" and $variable ne $producer);
			}
		}
		
		#Section to delete elements
		foreach my $filter (@{$filterList->{'delete'}})
		{
			last if (!$lineIsValid);
			
			my $curElement = $elements[$headerArray{$filter->{column}}];

			if($curElement =~ m/$filter->{content}/m)
			{
				DEBUG " - Deleted \"".$filter->{column}."\" with value \"$curElement\"\n" if (!exists($deletedElements{$filter->{column}}{$curElement})); 
				$deletedElements{$filter->{column}}{$curElement} = 1;
				$lineIsValid = 0;
			}
		}
		
		$lineNumber++;
		
		#Instructions used only if data are "Valid".
		next if not $lineIsValid;
		

		# Replacing some datas
		foreach my $setValue (@{$filterList->{'setValue'}})
		{
			my $content = "";
			$content = $setValue->{content} if(defined($setValue->{content}));
			LOGDIE "Not present field : $setValue->{column}" if not defined $headerArray{$setValue->{column}};
			$elements[$headerArray{$setValue->{column}}] = $content;
		}
			
		#Generating compare table
		$csv->combine(@elements);
		my $rebuildedLine = $csv->string()."\r\n";
		if(exists($filterList->{'deleteIdenticalLines'}))
		{
			$hashTable{md5($rebuildedLine)} = 1;
		}

		print OUT $rebuildedLine;
	}
	
	close(IN);
	close(OUT);
	return %hashTable;
}

sub loadHeaders
{
	my $inFile = shift;
	
	open( IN, "$inFile" ) || die("Could not open file!: $!");
	binmode(IN);
	
	my $header = <IN>;
	close IN;
	
	my @headerArray;
	my $idElement = 0;
	DEBUG("Processing header for file $inFile");
	foreach my $element (split(";", $header))
	{
		$element =~ s/\s+$//;
		$element =~ s/\s+$//;
		push(@headerArray, $element);
	}
	DEBUG "Here are header elements found:\r\n".Dumper(@headerArray);
	return @headerArray;
}

sub loadCsvInMemory
{
	my $inFile = shift;
	my @keys = @_;
	my $keys = @keys;
	
	open( IN, "$inFile" ) || die("Could not open file!: $!");
	binmode(IN);
	
	my $header = <IN>;
	my %hashTable;
	my @keysID;
	
	my @headerArray;
	my %headerArray;
	my $columnNumber = 0;
	foreach my $element (split(";", $header))
	{
		$element =~ s/\s+$//;
		$element =~ s/\s+$//;
		push(@headerArray, $element);
		$headerArray{$element} = $columnNumber++;
	}

	if($keys > 0)
	{	
		foreach my $key (@keys)
		{
			@keysID = (@keysID, $headerArray{$key});
		} 
	}
	
	my $columnID = 0;
	foreach my $line (<IN>)
	{
		my @elements = split(";", $line);
		my %elements;
		my $columnNumber = 0;
		foreach my $element (@elements)
		{
			$elements{$headerArray[$columnNumber++]} = $element;
		}
		
		if(scalar(@keysID) > 0)
		{
			my $key = "";
			foreach my $id (@keysID)
			{
				$key .= $elements[$id];
			}
			$hashTable{$key} = \%elements;
		}
		else
		{
			$hashTable{$columnID++} = \%elements;
		}
	}
	close(IN);
	
	return %hashTable;

}

sub deleteIdenticalLines
{
	my $inFile = shift;
	my $outFile = shift;
	my %hashTable = @_;
	
	open( IN, "$inFile" ) || die("Could not open file!: $!");
	binmode(IN);
	my $header = <IN>;
	my @lines = <IN>;
	close(IN);
	
	open( OUT, ">$outFile" ) || die("Could not open file!: $!");
	binmode(OUT);
	print OUT $header;	
	
	foreach my $line (@lines)
	{
		my $localHash = md5($line);
		print OUT $line if not exists($hashTable{$localHash});
	}
	close(OUT);
}

sub uncompressTSP
{
	print "Opening TSP directory. Please extract TSP Controlbuild to $data->{TSP}->{path}, then close explorer to continue.\n";
	system("explorer.exe", $data->{TSP}->{ftp}->{downloadPath});
}

sub copyDirectories
{
	my $oldPath = shift;
	my $newPath = shift;
	
	-d $oldPath or die "$oldPath is not a directory!";
	mkdir $newPath if not -d $newPath;
	-d $newPath or die "$newPath is not a directory!";
	system("winmerge.exe", "/r /x /e /wl \"$oldPath\" \"$newPath\"");
}

1;

__END__
:endofperl
@pause
