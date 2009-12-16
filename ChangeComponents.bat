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

my $PROGRAM_VERSION = "0.1";

INFO "Starting program (V $PROGRAM_VERSION)";
my %Config = loadConfig("Clearquest-config.xml"); # Loading / preprocessing of the configuration file

use CQPerlExt; 

my $Clearquest_database = $Config{clearquest}->{database} or LOGDIE("Clearquest database is not defined properly. Check your configuration file");
DEBUG "Using \$Clearquest_database = \"$Clearquest_database\"";

my $Clearquest_fields = $Config{clearquest}->{fieldsToRetrieve} or LOGDIE("Clearquest fields are not defined properly. Check your configuration file");
DEBUG "Using \$Clearquest_fields = \"$Clearquest_fields\"";

my $windowSizeX = 600;
$windowSizeX = $Config{scriptInfos}->{windowSizeX} if($Config{scriptInfos}->{windowSizeX} and $Config{scriptInfos}->{windowSizeX} =~ /^\d+$/ and $Config{scriptInfos}->{windowSizeX} > $windowSizeX);

my $windowSizeY = 400;
$windowSizeY = $Config{scriptInfos}->{windowSizeY} if($Config{scriptInfos}->{windowSizeY} and $Config{scriptInfos}->{windowSizeY}  =~ /^\d+$/ and $Config{scriptInfos}->{windowSizeY} > $windowSizeY);

my @list = readCSVFile("list.csv");

exit;

##########################################
# Synchronizing with ClearQuest database
##########################################

sub readCSVFile {
	my $file  = shift;
	use Text::CSV;
	
	my $hr;
	my $csv = Text::CSV->new ( { binary => 1, sep_char => ";" } );
	open( $hr, "$file" ) || LOGDIE("Could not open file!: $!");
	
	$csv->column_names ($csv->getline ($hr));
	
	my $session = CQSession::Build(); 
	
	eval( '$session->UserLogon ($Config{clearquest}->{login}, $Config{clearquest}->{password}, "atvcm", "")' );
	if($@) {
		my $error_msg = $@;
		DEBUG "Error message is : $error_msg";
		ERROR "Clearquest database is not reachable actually. Check network settings. It can be considered as normal if you are not currently connected to the Alstom intranet" and return if($error_msg =~ /Unable to logon to the ORACLE database "cqueste"/);
		LOGDIE "An unknown error has happened during Clearquest connection. Please report this issue.";
	}
	
	while(!$csv->eof()) {
		my $ref = $csv->getline_hr($hr);
		
		last unless $ref->{dbid};
		
		INFO "Processing \"".$ref->{'sub_system.name'}." -> $ref->{name}\" (# $ref->{dbid})";
		
		my $rec = $session->GetEntityByDbId('component', $ref->{dbid});
		#my $rec = $session->GetEntity("component", $ref->{dbid});
		
		$rec->EditEntity('modify');
		
		my $extracted_name = 'EXPL-TEST';
		$extracted_name = $rec->GetFieldValue('name');

		
		ERROR "Component has not expected property 'name', with value '$extracted_name'" and next if($extracted_name ne $ref->{name});
		
		DEBUG "Setting following comment : \"$ref->{comment}\"";
		$rec->SetFieldValue('comment', $ref->{comment});
		
		DEBUG "Sending modification to server";
		$rec->Validate();
		$rec->Commit();
	}
	
	CQSession::Unbuild($session);
	close $hr;
}

__END__
:endofperl
pause