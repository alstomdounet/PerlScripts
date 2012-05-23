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
use File::Copy;
use Data::Dumper;

use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.2',
	TEMPLATE_ROOT_DIR => 'Templates',
	INPUT_DIR => 'inputs',
	OUTPUT_DIR => 'outputs',
	DEFAULT_TEMPLATE_DIR => '.',
	DEFAULT_TEMPLATE => 'Xml',
	MAIN_TEMPLATE_NAME => 'main.tmpl',
};

INFO("Starting program (V ".PROGRAM_VERSION.")");

#########################################################
# loading of Configuration files
#########################################################
my $config = loadLocalConfig("TTCreateArray.config.xml", 'config.xml', KeyAttr => {}, ForceArray => qr/^(component|rule)$/);

#########################################################
# Using template files
#########################################################
my $SCRIPT_DIRECTORY = getScriptDirectory();
my $rootTemplateDirectory = "./";

my $defaultTemplateDir = DEFAULT_TEMPLATE_DIR."/".TEMPLATE_ROOT_DIR.'/'.DEFAULT_TEMPLATE;
my $userTemplateDir = $SCRIPT_DIRECTORY.TEMPLATE_ROOT_DIR;

createDirInput($userTemplateDir, 'Templates files for current user has to be put in this directory');
createDirInput($SCRIPT_DIRECTORY.INPUT_DIR, 'Place all inputs XML documents in this folder');
createDirInput($SCRIPT_DIRECTORY.OUTPUT_DIR, 'All output files are put in this folder');

#########################################################
# Foreach component to generate
#########################################################
foreach my $component (@{$config->{components}->{component}}) {
	INFO "Processing Component \"$component->{name}\"";

	my %modulesDescriptors;
	my $extracted_interfaces = "";

	my $_start_offset_X = 408;
	my $_start_offset_Y = 144;
	my $start_position_input_X = -24;
	my $start_position_input_Y = 48;

	my $start_position_output_X = 24; # Has to be added to component width
	my $start_position_output_Y = $start_position_input_Y;

	my $space_between_comps = 40;
	my $space_between_vars = 24;

	my $current_base_offset_X = 0;
	my $current_base_offset_Y = 0;
	my $current_local_id = 0;

	
	my $file = $SCRIPT_DIRECTORY.INPUT_DIR.'/'.$component->{refFile};
	
	#########################################################
	# Reading connections variables
	#########################################################
	unless (open IN_FILE, $file) {
		ERROR "input file \"$file\" cannot be processed. Component is skipped.";
		next;
	}
	
	my %variablesList;
	my @tab;
	my $lineNumber = 0;
	foreach my $line (<IN_FILE>) {
		chomp($line);
		my @line = split(/\t/, $line);
		
		my $module = $line[0];
		$lineNumber++;
		
		#########################################################
		# Loading model description if it is not already done
		#########################################################
		unless($modulesDescriptors{$module}) {
			DEBUG "Adding informations for module $module";
			if(my $comp = loadModule($module)) {

				$modulesDescriptors{$module} = $comp;
				push(@tab, \@line);
			}
			else {
				ERROR "Line $lineNumber will be ignored";
			}
		}
		else {
			push(@tab, \@line);
		}
	}
	
	#########################################################
	# This part generates modules positions
	#########################################################
	my @list_modules;
	my @list_connections_in;
	my @list_connections_out;
	
	foreach my $line (@tab) {

		my %currModuleChars;
		DEBUG "Using module \"$line->[0]\"";		
		my $moduleCharacteristics = $modulesDescriptors{$line->[0]};

		#########################################################
		# This part generates modules positions
		#########################################################
		$currModuleChars{LOCAL_ID} = $current_local_id;
		
		
		$currModuleChars{MODULE_WIDTH} = $moduleCharacteristics->{size}->{width};
		$currModuleChars{MODULE_HEIGHT} = $moduleCharacteristics->{size}->{height};
		$currModuleChars{MODULE_GENERIC_NAME} = $moduleCharacteristics->{CBname};
		$currModuleChars{MODULE_INST_NAME} = $line->[1];
		$currModuleChars{MODULE_POS_X} = $_start_offset_X;
		$currModuleChars{MODULE_POS_Y} = $_start_offset_Y + $current_base_offset_Y;
		
		$current_base_offset_Y += $currModuleChars{MODULE_HEIGHT} + $space_between_comps;
		$current_local_id++;
		
		my @module_inputs;
		my @module_outputs;
		
		my $offset = 0;
		my $var_position_y = 0;
		foreach my $input (@{$moduleCharacteristics->{interface}->{inputs}->{pin}}) {
			if($line->[$offset+2]) {
				my %inputVariable;
				$inputVariable{LOCAL_ID} = $current_local_id++;
				$inputVariable{EXPRESSION} = $line->[$offset+2];
				$inputVariable{VAR_POS_X} = $currModuleChars{MODULE_POS_X} + $start_position_input_X;
				$inputVariable{VAR_POS_Y} = $currModuleChars{MODULE_POS_Y} + $start_position_input_Y + ($space_between_vars * $var_position_y);
				push(@list_connections_in, \%inputVariable);
				
				my %moduleInputVar;
				$moduleInputVar{LOCAL_ID} = $inputVariable{LOCAL_ID};
				$moduleInputVar{FORMAL_NAME} = $input->{content};
				push(@module_inputs, \%moduleInputVar);
			}
			$offset++;
			$var_position_y++;
		}
		
		$var_position_y = 0;
		foreach my $output (@{$moduleCharacteristics->{interface}->{outputs}->{pin}}) {
			if($line->[$offset+2]) {
				my %outputVariable;
				$outputVariable{LOCAL_ID} = $current_local_id++;
				$outputVariable{EXPRESSION} = $line->[$offset+2];
				$outputVariable{MODULE_LOCAL_ID} = $currModuleChars{LOCAL_ID};
				$outputVariable{FORMAL_NAME} = $output->{content};
				
				$outputVariable{VAR_POS_X} = $currModuleChars{MODULE_POS_X} + $currModuleChars{MODULE_WIDTH} + $start_position_output_X;
				$outputVariable{VAR_POS_Y} = $currModuleChars{MODULE_POS_Y} + $start_position_output_Y + ($space_between_vars * $var_position_y);
				push(@list_connections_out, \%outputVariable);
				
			}
			$offset++;
			$var_position_y++;
		}
		
		$currModuleChars{MODULE_VARS_IN} = \@module_inputs;
		$currModuleChars{MODULE_VARS_OUT} = \@module_outputs;
		
		push(@list_modules, \%currModuleChars);
	}
	
	#########################################################
	# This part generates input / output files
	#########################################################
	if(-d $component->{inject_path}) {
		INFO "injecting results in $component->{inject_path}\\$component->{name}\\$component->{name}.xml";
		
		my $template_file = DEFAULT_TEMPLATE_DIR."/".TEMPLATE_ROOT_DIR.'/InjectXml/body.tmpl';
		my $mainTemplate = HTML::Template -> new( die_on_bad_params => 0, filename => $template_file );
		$mainTemplate->param(CONNECT_VARS_IN => \@list_connections_in);
		$mainTemplate->param(CONNECT_VARS_OUT => \@list_connections_out);
		$mainTemplate->param(MODULES => \@list_modules);
		
		INFO "Generating $component->{name}.xml";
		my $results = $mainTemplate->output;
		
		open OUTFILE, "$component->{inject_path}/$component->{name}/$component->{name}.xml";
		
		my $insideBody = 0;
		my $insideFBD = 0;
		
		my $newFile = "";
		foreach my $line (<OUTFILE>) {
			if($line =~ /^\s*<body>\s*$/) {
				INFO "Found <body> tag";
				
				$insideBody = 1;
			}
			
			if($line =~ /^\s*<\/body>\s*$/) {
				INFO "Found </body> tag";
				
				$insideBody = 0;
			}
			
			if($line =~ /^\s*<FBD>\s*$/ && $insideBody) {
				INFO "Found <FBD> tag";
				
				$insideFBD = 1;
				$newFile = $newFile . $results;
			}
			
			if(($insideBody && ! $insideFBD)|| !$insideBody) {
				$newFile = $newFile . $line;
			}
			
			if($line =~ /^\s*<\/FBD>\s*$/ && $insideBody) {
				INFO "Found </FBD> tag";
				$insideFBD = 0;
			}
		}
		
		close OUTFILE;
		open OUTFILE, ">$component->{inject_path}/$component->{name}/$component->{name}.xml";
		print OUTFILE $newFile;
		close OUTFILE;
	}
	else {
		my $outDir = $SCRIPT_DIRECTORY.OUTPUT_DIR.'/';
	
		open OUTFILE, ">$outDir/$component->{name}.xml";
		
		my $template_file = $defaultTemplateDir.'/body.tmpl';
		my $mainTemplate = HTML::Template -> new( die_on_bad_params => 0, filename => $template_file );
				
		$mainTemplate->param(MODULE_NAME => $component->{name});
		
		$mainTemplate->param(INTERFACES => $extracted_interfaces);
		$mainTemplate->param(CONNECT_VARS_IN => \@list_connections_in);
		$mainTemplate->param(CONNECT_VARS_OUT => \@list_connections_out);
		$mainTemplate->param(MODULES => \@list_modules);
		
		INFO "Generating $component->{name}.xml";
		print OUTFILE $mainTemplate->output;
		close OUTFILE;
	}
}

sub loadModule {
	my ($module_name) = @_;

	my $file = $SCRIPT_DIRECTORY.INPUT_DIR.'/model_'.$module_name.'.descr.xml';
	unless (-r $file) {
		ERROR("FileName of module \"$module_name\" has not been found on path \"$file\"");
		return;
	}
	my $component = XMLin($file, KeyAttr => {}, ForceArray => qr/^(pin)$/);
	
	return $component;
}

sub createDirInput {
	my ($folder, $readme_message) = @_;
	if (not -d $folder) {
		mkdir($folder);
		INFO("Creating commented directory ".$folder);
		open FILE,">".$folder."/readme.txt";
		printf FILE $readme_message;
		close FILE;
	}
}

__END__
:endofperl
pause