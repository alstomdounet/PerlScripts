@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(lib);
use strict;
use warnings;
use Common;
use Storable qw(store retrieve);
use Data::Dumper;

my %Config = loadConfig("config.xml"); # Loading / preprocessing of the configuration file

# Preliminary checks
ERROR "ControlBuild project was not found inside '$Config{project_params}->{folders}->{cb_project_folder}'" and exit unless -d $Config{project_params}->{folders}->{cb_project_folder}."\\Applications";

###########################################
# MISSING : Building 
###########################################

my @lines = putFileInMemory($Config{script_params}->{properties_file});

my $fbsTreePath = $Config{project_params}->{tree_view}->{fbs_path};

cleanup("output");
LOGDIE "Directory was not purged successfully" if -d "output";
mkdir "output";
LOGDIE "Destination directory \"output\" was not created successfully" unless -d "output";

open MAINBACKUPFILE, ">output/allFunctions.backup.csv";
binmode MAINBACKUPFILE;
print MAINBACKUPFILE $lines[0];

foreach my $element (@{$Config{function_params}}) {
	my $finalDirectory = "output/".$element->{function_name};
	my $functionName = $element->{function_name};
	
	ERROR "Controlbuild application has to be created before executing this program\nFollow this rule:\n\t - Create A new application with ControlBuild called '$functionName'\n" unless -d "$Config{project_params}->{folders}->{cb_project_folder}\\Applications\\$functionName\\functional";
	
	mkdir "$finalDirectory";
	LOGDIE "Destination directory \"$finalDirectory\" was not created successfully" unless -d "output";
	
	INFO "Processing function $functionName";
	# Removing old structure if it exists

	mkdir $finalDirectory;
	LOGDIE "Destination directory \"$finalDirectory\" was not created successfully" unless -d $finalDirectory;
	
	my ($foundComponents,$suggested_path) = filterFile(\@lines, "$finalDirectory/$functionName.backup.csv", $fbsTreePath, $functionName);
	my @selectedComponents = selectComponents($foundComponents);
	createFilesStructure($functionName, \@selectedComponents, $finalDirectory);
	
}

close MAINBACKUPFILE;

exit;

sub filterFile {
	my $lines = shift;
	my $outputFile = shift;
	my $baseTreePath = shift;
	my $functionName = shift;
	
	my %foundComponents;
	my @lines = @$lines;
	
	 $| = 1;
	my $matches = 0;
	open BACKUP, ">$outputFile" or LOGDIE "Not possible to write in file \"$outputFile\" : $!"; 
	binmode BACKUP;
	print BACKUP shift(@lines);
	
	my $suggestedPath = undef;
	
	foreach my $line (@lines) {
		if ($line->{component_name} =~ /$functionName/) {
			$suggestedPath = $line->{path};
			$suggestedPath =~ s/^$baseTreePath//;
			DEBUG "Found automatic path \"$suggestedPath\"";
			last;
		}
	}
	
	my $matchingPath = "^".$baseTreePath.$suggestedPath;
	DEBUG "Selected path  : '$matchingPath'";	
	
	foreach my $line (@lines) {
		if($line->{path} =~ /$matchingPath/) 
		{
			print BACKUP $line->{all};
			print MAINBACKUPFILE $line->{all};
			my $componentName = $line->{component_name};
			$componentName =~ s/_$line->{variable}//;
			$foundComponents{$componentName}++;
			
			$matches++;
		}
	}
	
	close BACKUP;

	INFO "$matches lines were written for backup";
		
	my @foundComponents = keys(%foundComponents);
	INFO scalar(@foundComponents)." components found";
	return \@foundComponents, $suggestedPath;
}

sub selectComponents {
	my $foundComponents = shift;
	
	my @selectedComponents;
	foreach my $component (@$foundComponents)
	{
		my $componentPath = "$Config{project_params}->{folders}->{cb_project_folder}\\$Config{project_params}->{folders}->{fbs_folder}\\$component";
		push (@selectedComponents, $component) if -d $componentPath;
	}

	INFO scalar(@selectedComponents)." components selected";
	return @selectedComponents;
}

sub cleanup {
    my $dir = shift;
	local *DIR;

	return unless -d $dir;
	opendir DIR, $dir or LOGDIE "opendir failed for \"$dir\" : $!";
	for (readdir DIR) {
	        next if /^\.{1,2}$/;
	        my $path = "$dir/$_";
		unlink $path if -f $path;
		cleanup($path) if -d $path;
		LOGDIE "It was not possible to remove element \"$path\" : $!" if -e $path;
	}
	closedir DIR;
	rmdir $dir or LOGDIE "Deletion of \"$dir\" is not possible  : $!";
}

sub putFileInMemory {
	my $inputFile = shift;
	
	my @lines;
	if(-r "db.tmp") {
		DEBUG "Beginning reading of database";
		my $lines = retrieve("db.tmp");
		@lines = @$lines;
		DEBUG "Finished reading of database";
	}
	else {
		open FILE, $inputFile or die $!;
		binmode FILE;
		my $header = <FILE>;
		push(@lines, $header);
		my $linesProcessed = 0;
		while (my $line = <FILE>) {
			my %line;
			my @items = split (/;/, $line);
			my $path = $items[3];
			
			my $component_name = $items[11];
			$line{path} = $items[3];
			$line{component_name} = $items[11];
			$line{all} = $line;
			$line{variable} = $items[0];
			push(@lines, \%line);
			$linesProcessed++;
			DEBUG "$linesProcessed lines processed" if $linesProcessed % 10000 == 0;
		}
		close FILE;
	
		store(\@lines, "db.tmp");
	}
	
	INFO "Script has read ".scalar(@lines)." lines of properties";
	return @lines;
}

sub write_file {
	my $file = shift;
	my $text = shift;
	
	open WRITE_FILE, ">$file" or die "Script was not able to write '$file' : $!";
	print WRITE_FILE $text;
	close WRITE_FILE;
}

sub createFilesStructure {
	my $functionName = shift;
	my $selectedComponents = shift;
	my $directory = shift;
	
	my $pause_btw_step = "ECHO No particular message should be displayed. If it is OK, then you can continue\nPAUSE\nCLS\n";
	my $batch_template = <<EOF;
\@ECHO OFF
SET OLDDIR=$Config{project_params}->{folders}->{cb_project_folder}\\$Config{project_params}->{folders}->{fbs_folder}
SET NEWDIR=$Config{project_params}->{folders}->{cb_project_folder}\\Applications\\$functionName\\functional
ECHO WARNING : PLEASE CHECK FOLLOWING POINTS:
ECHO ----------------------------------------
ECHO  - CHECK IF THIS BATCH FILE IS CORRECT BEFORE EXECUTING IT :
ECHO  - HAVE YOU EXECUTED THIS SCRIPT WITH AN UPDATED CSV FILE
ECHO  - CHECK COMPONENTS WHICH WILL BE MOVED
ECHO  - FUNCTION WHICH WILL BE MOVED IS IN A STABLE STATE
ECHO -------
ECHO IF YOU HAVE UNDERSTOOD THIS MESSAGE, YOU CAN PROCEED...
PAUSE
CLS
ECHO Checking out 'fbs' and '$functionName' applications
ECHO --------------
cleartool co -c "Migration de la fonction '$functionName'" "\%OLDDIR\%"
cleartool co -c "Migration de la fonction '$functionName'" ".\%NEWDIR\%"
$pause_btw_step

ECHO <DISABLED FOR SECURITY>Deletion Of top-level MAC
ECHO --------------
rem cleartool rmname ".\\Applications\\\%FUNCTION_NAME\%\\functional\\\%FUNCTION_NAME\%"
$pause_btw_step
EOF

	my $i = 0;
	my $total = scalar(@$selectedComponents);
	foreach my $component (@$selectedComponents) {
		$i++;
		
		$batch_template .= "ECHO [$i/$total]  Moving directory '$component'\nECHO --------------\ncleartool move \"%OLDDIR%\\$component\" \"%NEWDIR%\\$component\"\n\n";
	}

	$batch_template .= <<EOF;
ECHO Checking in 'fbs' and '$functionName' applications
ECHO --------------
rem cleartool ci -c "Migration de la fonction '$functionName'" "%OLDDIR%"
cleartool ci -c "Migration de la fonction '$functionName'" ".%NEWDIR%"
$pause_btw_step

echo ----------------------------------------------------------------
echo  Program is finished. You have now to follow hereafter operations:
echo ----------------------------------------------------------------

CALL postscript_instructions.bat
EOF

	my $output_file = "$directory/move_$functionName.bat";
	write_file($output_file, $batch_template);
	DEBUG "'$output_file' has been written";

	my $instructions .= <<EOF;
\@ECHO  1 / Save all components which were moved (they are located inside $Config{project_params}->{folders}->{cb_project_folder}\\Applications\\$functionName\\functional);
\@ECHO  2 / Open all MACS which has these components instanciated, and change model. BE VERY CAREFULL TO SELECT THE RIGHT MODEL BEFORE CHANGING.
\@ECHO  3 / Save all the modified MACS;
\@ECHO  4 / For safety, reimport backup advanced properties into top-level tree;
\@ECHO  5 / For safety, run a coherency test. No new error messages should have appeared.
\@PAUSE
EOF

	write_file("$directory/postscript_instructions.bat", $instructions);

	close FILE;
	close BACKUP;
}


__END__
:endofperl
pause