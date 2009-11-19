@rem = ' PERL for Windows NT - ccperl must be in search path
@echo off
ccperl %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';

use strict;
use warnings;
use XML::Simple;

my %Config = %{XMLin("config.xml")}; # Loading / preprocessing of the configuration file

print "ControlBuild project was not found inside '$Config{project_params}->{folders}->{cb_project_folder}'" and exit unless -d $Config{project_params}->{folders}->{cb_project_folder};
print "Controlbuild application has to be created before executing this program\nFollow this rule:\n\t - Create A new application with ControlBuild called '$Config{function_params}->{function_name}'\n" and exit unless -d "$Config{project_params}->{folders}->{cb_project_folder}\\Applications\\$Config{function_params}->{function_name}\\functional";

open FILE, $Config{script_params}->{properties_file} or die $!;
binmode FILE;
open BACKUP, ">backup_props_$Config{function_params}->{function_name}.csv" or die $!; 
binmode BACKUP;

my $header = <FILE>; # Skip first line
print BACKUP $header;

 $| = 1;
my $i = 0;
my $matches = 0;

my $matching_path = "^$Config{project_params}->{tree_view}->{fbs_path}$Config{function_params}->{tree_view}->{function_path}";

print "---- Selected tree path ------\n\t'$matching_path'\n\n---- Processing lines --------\n";

my %foundComponents;

my $suggested_path = undef;

while (my $line = <FILE>) {

	my @items = split (/;/, $line);
	my $path = $items[3];
	
	my $component_name = $items[11];
	
	if (not $suggested_path and $component_name =~ /$Config{function_params}->{function_name}/) {
		$suggested_path = $path;
		$suggested_path =~ s/^$Config{project_params}->{tree_view}->{fbs_path}//;
	}
	
	if($path =~ /$matching_path/) 
	{
		print BACKUP $line;
		$component_name =~ s/_$items[0]//;
		$foundComponents{$component_name}++;
		
		$matches++;
	}
	
	$i++;
	print "$i lines processed ($matches matches found)\r" if $i % 10000 == 0;
}

print "$i lines processed ($matches matches found)\r";

my @foundComponents = keys(%foundComponents);
my @selectedComponents;
foreach my $component (@foundComponents)
{
	push (@selectedComponents, $component) if -d "$Config{project_params}->{folders}->{cb_project_folder}\\$Config{project_params}->{folders}->{fbs_folder}\\$component";
}

my %Components;
@Components{@selectedComponents}=();

unless (exists $Components{$Config{function_params}->{function_name}})
{
	print "\n\nWARNING : No selected components have the name '$Config{function_params}->{function_name}'. \nIT IS HIGHLY POSSIBLE THAT YOU DID A MISTAKE with configuration file!!!\n";
	print "Maybe it should be better to replace field <function_params> / <tree_view> / <function_path> of configuration file with '$suggested_path'\n" if $suggested_path;
	<>;
}

print "\n\n---- Resume ------------------\nOn $i lines processed:\n - $matches lines were match for backup\n - ".scalar(@foundComponents)." components found\n - ".scalar(@selectedComponents)." components selected\n";
my $pause_btw_step = "ECHO No particular message should be displayed. If it is OK, then you can continue\nPAUSE\nCLS\n";
my $batch_template = <<EOF;
\@ECHO OFF
SET OLDDIR=$Config{project_params}->{folders}->{cb_project_folder}\\$Config{project_params}->{folders}->{fbs_folder}
SET NEWDIR=$Config{project_params}->{folders}->{cb_project_folder}\\Applications\\$Config{function_params}->{function_name}\\functional

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

ECHO Checking out 'fbs' and '$Config{function_params}->{function_name}' applications
ECHO --------------
cleartool co -c "Migration de la fonction '$Config{function_params}->{function_name}'" "%OLDDIR%"
cleartool co -c "Migration de la fonction '$Config{function_params}->{function_name}'" ".%NEWDIR%"
$pause_btw_step

ECHO <DISABLED FOR SECURITY>Deletion Of top-level MAC
ECHO --------------
rem cleartool rmname ".\\Applications\\%FUNCTION_NAME%\\functional\\%FUNCTION_NAME%"
$pause_btw_step

EOF

$i = 0;
my $total = scalar(@selectedComponents);
foreach my $component (@selectedComponents)
{
	$i++;
	
	$batch_template .= "ECHO [$i/$total]  Moving directory '$component'\nECHO --------------\ncleartool move \"%OLDDIR%\\$component\" \"%NEWDIR%\\$component\"\n$pause_btw_step\n";
}

$batch_template .= <<EOF;

ECHO Checking in 'fbs' and '$Config{function_params}->{function_name}' applications
ECHO --------------
cleartool ci -c "Migration de la fonction '$Config{function_params}->{function_name}'" "%OLDDIR%"
cleartool ci -c "Migration de la fonction '$Config{function_params}->{function_name}'" ".%NEWDIR%"
$pause_btw_step

echo ----------------------------------------------------------------
echo  Program is finished. You have now to follow hereafter operations:
echo ----------------------------------------------------------------

CALL postscript_instructions.bat
EOF

my $output_file = "move_$Config{function_params}->{function_name}.bat";
write_file($output_file, $batch_template);
print "\n---- Output file -------------\n\t'$output_file' has been written\n\n";

my $instructions .= <<EOF;
\@ECHO  1 / Save all components which were moved (they are located inside $Config{project_params}->{folders}->{cb_project_folder}\\Applications\\$Config{function_params}->{function_name}\\functional);
\@ECHO  2 / Open all MACS which has these components instanciated, and change model. BE VERY CAREFULL TO SELECT THE RIGHT MODEL BEFORE CHANGING.
\@ECHO  3 / Save all the modified MACS;
\@ECHO  4 / For safety, reimport backup advanced properties into top-level tree;
\@ECHO  5 / For safety, run a coherency test. No new error messages should have appeared.
\@PAUSE
EOF

write_file("postscript_instructions.bat", $instructions);

close FILE;
close BACKUP;

sub write_file
{
	my $file = shift;
	my $text = shift;
	
	open WRITE_FILE, ">$file" or die "Script was not able to write '$file' : $!";
	print WRITE_FILE $text;
	close WRITE_FILE;
}

__END__
:endofperl
pause