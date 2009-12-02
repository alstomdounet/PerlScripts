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

my %Config = loadConfig("config.xml", ForceArray => qr/_list$/); # Loading / preprocessing of the configuration file

# Preliminary checks
ERROR "ControlBuild project was not found inside '$Config{project_params}->{folders}->{cb_project_folder}'" and exit unless -d $Config{project_params}->{folders}->{cb_project_folder}."\\Applications";

my @lines = putFileInMemory($Config{script_params}->{properties_file});

my $fbsTreePath = $Config{project_params}->{tree_view}->{fbs_path};

cleanup("output");
LOGDIE "Directory was not purged successfully" if -d "output";
mkdir "output";
LOGDIE "Destination directory \"output\" was not created successfully" unless -d "output";

open MAINBACKUPFILE, ">output/allFunctions.backup.csv";
binmode MAINBACKUPFILE;
print MAINBACKUPFILE $lines[0];
my $MAINSCRIPTFILE;
open $MAINSCRIPTFILE, ">output/allFunctions.bat";
printScriptHeader($MAINSCRIPTFILE);
my $OLDDIR = "$Config{project_params}->{folders}->{cb_project_folder}\\$Config{project_params}->{folders}->{fbs_folder}";
my $message;

	$message = <<EOF;
INFO 'Putting FBS in checkout state';
doCommand('cleartool co -nc "$OLDDIR"');

EOF
	printProtected ($MAINSCRIPTFILE, $message);

my $selectedComponents = 0;
foreach my $element (@{$Config{function_list}}) {
	my $finalDirectory = "output/".$element->{function_name};
	my $functionName = $element->{function_name};
	my $NEWDIR = $Config{project_params}->{folders}->{cb_project_folder}."\\Applications\\".$functionName."\\functional";

	ERROR "Controlbuild application has to be created before executing this program\nFollow this rule:\n\t - Create A new application with ControlBuild called '$functionName'\n" unless -d "$Config{project_params}->{folders}->{cb_project_folder}\\Applications\\$functionName\\functional";
	
	mkdir "$finalDirectory";
	LOGDIE "Destination directory \"$finalDirectory\" was not created successfully" unless -d "output";
	
	INFO "Processing function \"$functionName\"";
	# Removing old structure if it exists

	mkdir $finalDirectory;
	LOGDIE "Destination directory \"$finalDirectory\" was not created successfully" unless -d $finalDirectory;
	
	my @foundComponents = filterFile(\@lines, "$finalDirectory/$functionName.backup.csv", $fbsTreePath, $functionName);
	my @selectedComponents = selectComponents(@foundComponents);
	
	WARN "Function is skipped (nothing to migrate)" and next unless scalar(@selectedComponents);
	
	$selectedComponents += scalar(@selectedComponents);
	INFO "$selectedComponents components ready to be migrated";
	my $components = join(" ", @selectedComponents);
	$message = <<EOF;
INFO 'Locking all components of \"$functionName\""';
doLockRecursive('$OLDDIR', qw($components));

INFO 'Putting function $functionName in checkout state';
doCommand('cleartool co -c "Migration de la fonction $functionName" "$NEWDIR"');

EOF
	printProtected ($MAINSCRIPTFILE, $message);
	
	createFilesStructure($functionName, \@selectedComponents, $finalDirectory, $MAINSCRIPTFILE, $NEWDIR);
	
	$message = <<EOF;
INFO 'Putting function $functionName in checkin state';
doCommand('cleartool ci -c "Migration de la fonction $functionName" "$NEWDIR"');

INFO 'Postprocessing of function \"$functionName\"(checkout, unlocking)';
doCheckoutRecursive('$NEWDIR', '..');
doUnlockRecursive('$NEWDIR', '');

EOF
	printProtected ($MAINSCRIPTFILE, $message);
	
}

$message = <<EOF;
INFO 'Putting FBS in checkin state';
doCommand('cleartool ci -nc "$OLDDIR"');

EOF
printProtected ($MAINSCRIPTFILE, $message);

printScriptFooter($MAINSCRIPTFILE);
close MAINBACKUPFILE;
close $MAINSCRIPTFILE;

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
		if ($line->{component_name} =~ /^$functionName$/) {
			$suggestedPath = $line->{path};
			$suggestedPath =~ s/^$baseTreePath//;
			DEBUG "Found automatic path \"$suggestedPath\"";
			last;
		}
	}
	
	unless ($suggestedPath) {
		LOGDIE "No matches were found for function \"$functionName\". It has to be an existing function." unless -d $OLDDIR."\\$functionName";
		WARN "Only one component has been found. It is probably an empty component.";
		return ($functionName);
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
	return @foundComponents;
}

sub selectComponents {
	my @selectedComponents = ();
	foreach my $component (@_) {
		LOGDIE "Empty component found" if $component eq "";
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
			
			my $offsetDuToCommas = 0;
			while(!($items[8+$offsetDuToCommas] =~ /^\d+$/)) { $offsetDuToCommas++; }
			WARN "Line $linesProcessed -> Offset inserted : $offsetDuToCommas (stopped at ".$items[8+$offsetDuToCommas].")" if $offsetDuToCommas > 0;
			
			my $component_name = $items[11+$offsetDuToCommas];
			$line{path} = $items[3];
			$line{component_name} = substr($component_name, 0, -(length($items[0]) + 1));
			
			LOGDIE "Empty component name. parameters are '$component_name' and '$items[0]' and '".(-(length($items[0]) + 1))."'" unless $line{component_name};
			
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

sub printProtected {
	my $handler  = shift;
	my $message = shift;
	
	$message =~ s/\\/\\\\/g;
	print $handler $message;
	
}

sub printScriptHeader {
	my $handler = shift;
	
	print $handler <<'EOF';
@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use lib qw(../lib);
use strict;
use warnings;
use Common;
use Time::HiRes qw(gettimeofday tv_interval);
use File::Find;
use Term::ReadKey;

print <<EOM;
WARNING : PLEASE CHECK FOLLOWING POINTS:
----------------------------------------
  - CHECK IF THIS BATCH FILE IS CORRECT BEFORE EXECUTING IT :
  - HAVE YOU EXECUTED THIS SCRIPT WITH AN UPDATED CSV FILE
  - CHECK COMPONENTS WHICH WILL BE MOVED
  - FUNCTION WHICH WILL BE MOVED IS IN A STABLE STATE
----------------------------------------
IF YOU HAVE UNDERSTOOD THIS MESSAGE, YOU CAN PROCEED...
----------------------------------------
EOM
<>;

EOF
}

sub printScriptFooter {
	my $handler = shift;
	
	print $handler <<'EOF';
print <<EOM;
----------------------------------------
Here are all remaining operations:
  1 / Save all components which were moved;
  2 / Open all MACS which has these components instanciated, and change model. BE VERY CAREFULL TO SELECT THE RIGHT MODEL BEFORE CHANGING.
  3 / Save all the modified MACS;
  4 / For safety, reimport backup advanced properties into top-level tree;
  5 / For safety, run a coherency test. No new error messages should have appeared.
----------------------------------------
EOM
<>;

sub doMove {
	my $oldDir = shift;
	my $newDir = shift;
	doCommand("cleartool move \"$oldDir\" \"$newDir\"");
}

sub doCheckoutRecursive {
	my $baseDir = shift;
	my @directories = ();
	foreach my $dir (@_) {
		push(@directories, File::Spec->canonpath($baseDir."\\".$dir));
	}
	my $t1 = [gettimeofday];
	find(\&checkoutFile, @directories);
	DEBUG "Checkout has taken ".tv_interval ( $t1, [gettimeofday] )." seconds";
}

sub doLockRecursive {
	my $baseDir = shift;
	my @directories = ();
	foreach my $dir (@_) {
		push(@directories, File::Spec->canonpath($baseDir."\\".$dir));
	}
	my $t1 = [gettimeofday];
	find(\&lockFile, @directories);
	INFO "Locking has taken ".tv_interval ( $t1, [gettimeofday] )." seconds";
}

sub doUnlockRecursive {
	my $baseDir = shift;
	my @directories = ();
	foreach my $dir (@_) {
		push(@directories, File::Spec->canonpath($baseDir."\\".$dir));
	}
	my $t1 = [gettimeofday];
	find(\&lockFile, @directories);
	INFO "Locking has taken ".tv_interval ( $t1, [gettimeofday] )." seconds";
}

sub unlockFile {
	my $file = $File::Find::name;
	$file =~ s/\//\\/g;
	doCommand("cleartool unlock -c \"Migration des fonctions. Demander a gmanciet en cas de problemes.\" \"$file\"", 0, 1);
}

sub lockFile {
	my $file = $File::Find::name;
	$file =~ s/\//\\/g;
	doCommand("cleartool lock -c \"Migration des fonctions. Demander a gmanciet en cas de problemes.\" -nuser gmanciet \"$file\"", 0, 1);
}

sub checkoutFile {
	my $file = $File::Find::name;
	$file =~ s/\//\\/g;
	doCommand("cleartool co -nc \"$file\"", 0, 1);
}

sub doCommand {
	my $command = shift;
	my $skipCheckpoint = shift;
	my $skipRecording = shift;
	
RETRY:
	my $t0 = [gettimeofday];
	DEBUG "Command entered : >>>$command<<<" unless $skipRecording;
	my $result = `$command 2>&1 1>NUL`;
	DEBUG "Command has taken ".tv_interval ( $t0, [gettimeofday] )." seconds" unless $skipRecording;
	
	my $returnString = 'UNKNOWN';
	my $message = '';
	if ($result eq '') {
		$returnString = "OK";
	} elsif ($result =~ /^cleartool: Error:\s*(.*)/) {
		$message = $1;
		$returnString = "ERROR";
	} elsif ($result =~ /^cleartool: Warning:\s*(.*)/) {
		$message = $1;
		$returnString = "WARNING";
	} 
	
	if($returnString ne 'OK') {
		WARN "Command entered was : >>>$command<<<";
		if($returnString eq 'WARNING') {
			WARN "Warning returned by command: $message";
		} elsif ($returnString eq 'WARNING') {
			ERROR "Error returned by command: $message";
		} else {
			ERROR "Unknown event : >>>$result<<<";
		}
		
		print "Something strange happened. Do you want to ignore (i) or retry (r)? ";
		ReadMode('cbreak');
		my $key = ReadKey(0);
		ReadMode('normal');
		#print "\n".ord($key)."\n";
		print "\rRetrying                                                           \r" and goto RETRY unless $key eq 'i' or $key eq 'I';
		print "\r                                                                    \r";
		return $returnString;
	}
	return $returnString;
}


__END__
:endofperl
pause
EOF
}

sub createFilesStructure {
	my $functionName = shift;
	my $selectedComponents = shift;
	my $directory = shift;
	my $MAINSCRIPTFILE = shift;
	my $NEWDIR = shift;
	
	my $i = 0;
	my $total = scalar(@$selectedComponents);
	foreach my $component (@$selectedComponents) {
		$i++;
		
		$message = <<EOF;
		INFO 'Processing "$component"';
		doMove('$OLDDIR\\$component', '$NEWDIR\\$component');
		
EOF
		printProtected ($MAINSCRIPTFILE, $message);
	}

	close FILE;
	close BACKUP;
}


__END__
:endofperl
pause