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
use Text::CSV;

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
	MAIN_TEMPLATE_NAME => 'body.tmpl',
};

INFO("Starting program (V ".PROGRAM_VERSION.")");

#########################################################
# loading of Configuration files
#########################################################
my $config = loadLocalConfig("TTCreateArray.config.xml", 'config.xml', KeyAttr => {}, ForceArray => qr/^(GraphicalDashboard|rule)$/);

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
my $csv = Text::CSV->new ({sep_char => "\t"});

foreach my $graphicalDashboard (@{$config->{GraphicalDashboards}->{GraphicalDashboard}}) {
	INFO "Processing Component \"$graphicalDashboard->{properties}->{TITLE}\"";

	#my %modulesDescriptors;
	my @list_of_vars;
	my @list_of_elements;

	my $file = $SCRIPT_DIRECTORY.INPUT_DIR.'/'.$graphicalDashboard->{refFile};
	
	#########################################################
	# Reading connections variables
	#########################################################
	my $fh;
	unless (open $fh, $file) {
		ERROR "input file \"$file\" cannot be processed. Component is skipped.";
		next;
	}
	
	$csv->column_names ($csv->getline($fh));
	
	
	while (my $arrayref = $csv->getline_hr ($fh)) {
		push(@list_of_vars, {PATH => $arrayref ->{PATH}});
		
		my %list;
		foreach my $key (qw(SIZE_X SIZE_Y POS_X POS_Y LOCKED PATH)) {
			$list{$key} = $arrayref->{$key};
		}
		
		$list{$arrayref->{ELEMENT_TYPE}} = 1;
		
		$list{PATH} =~ s#\/#\\\/#g;
		
		push(@list_of_elements, \%list);
	}
	
	print Dumper @list_of_elements;
		
	my $outDir = $SCRIPT_DIRECTORY.OUTPUT_DIR.'/';
	
	open OUTFILE, ">$outDir/$graphicalDashboard->{properties}->{FILE_ID}.xml";
		
	my $template_file = $defaultTemplateDir.'/body.tmpl';
	my $mainTemplate = HTML::Template -> new( die_on_bad_params => 0, filename => $template_file, loop_context_vars => 1 );
		
	foreach my $property (keys %{$graphicalDashboard->{properties}}) {
		$mainTemplate->param($property => $graphicalDashboard->{properties}->{$property});
	}
		
	$mainTemplate->param(LIST_OF_VARS => \@list_of_vars);
	$mainTemplate->param(LIST_OF_ELEMENTS => \@list_of_elements);
		
	INFO "Generating $graphicalDashboard->{properties}->{FILE_ID}.xml";
	print OUTFILE $mainTemplate->output;
	close OUTFILE;
}

sub loadModule {
	my ($module_name) = @_;

	my $file = $SCRIPT_DIRECTORY.INPUT_DIR.'/model_'.$module_name.'.descr.xml';
	unless (-r $file) {
		ERROR("FileName of module \"$module_name\" has not been found on path \"$file\"");
		return;
	}
	my $graphicalDashboard = XMLin($file, KeyAttr => {}, ForceArray => qr/^(pin)$/);
	
	return $graphicalDashboard;
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