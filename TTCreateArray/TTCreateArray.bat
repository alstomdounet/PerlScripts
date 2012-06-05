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
use File::Copy;
use Data::Dumper;
use Text::CSV;
use Log::Log4perl qw(:easy);

use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.1',
	TEMPLATE_ROOT_DIR => 'Templates',
	INPUT_DIR => 'inputs',
	OUTPUT_DIR => 'outputs',
	DEFAULT_TEMPLATE_DIR => '.',
	DEFAULT_TEMPLATE => 'Xml',
	MAIN_TEMPLATE_NAME => 'body.tmpl',
};

Log::Log4perl->init_once("./config/log-config.conf" );

my $logger = Log::Log4perl->get_logger();

INFO("Starting program (V ".PROGRAM_VERSION.")");

#########################################################
# loading of Configuration files
#########################################################

my $config = XMLin( './config/config.xml', KeyAttr => {}, ForceArray => qr/^(GraphicalDashboard|rule)$/);




#########################################################
# Using template files
#########################################################
my $SCRIPT_DIRECTORY = "./";
my $rootTemplateDirectory = "./";

my $defaultTemplateDir = DEFAULT_TEMPLATE_DIR."/".TEMPLATE_ROOT_DIR.'/'.DEFAULT_TEMPLATE;
my $userTemplateDir = $SCRIPT_DIRECTORY.TEMPLATE_ROOT_DIR;

createDirInput($userTemplateDir, 'Templates files for current user has to be put in this directory');
createDirInput($SCRIPT_DIRECTORY.INPUT_DIR, 'Place all inputs XML documents in this folder');
createDirInput($SCRIPT_DIRECTORY.OUTPUT_DIR, 'All output files are put in this folder');

#########################################################
# Foreach component to generate
#########################################################
my $csv = Text::CSV->new ({sep_char => "\t", empty_is_undef => 0, auto_diag => 1, binary => 1});

foreach my $graphicalDashboard (@{$config->{GraphicalDashboards}->{GraphicalDashboard}}) {
	INFO "Processing Component \"$graphicalDashboard->{properties}->{TITLE}\"";

	#my %modulesDescriptors;
	my @list_of_vars;
	my @list_of_elements;
	my %variablesInserted;

	my $file = $SCRIPT_DIRECTORY.INPUT_DIR.'/'.$graphicalDashboard->{refFile};
	
	#########################################################
	# Reading input file
	#########################################################
	my $fh;
	unless (open $fh, $file) {
		ERROR "input file \"$file\" cannot be processed. Component is skipped.";
		next;
	}
	
	my @columns = @{$csv->getline($fh)};
	$csv->column_names (@columns);
	
	# Building ranges arrays
	my %ranges;
	if(my @results = sort grep(/^RNGE\[\d+-\d+\]_/, @columns)) {
		foreach my $result (@results) {
			if($result =~ /^(RNGE\[(\d+)-(\d+)\])_(.*)$/) {
				$ranges{$1}{RANGE_MIN} = $2;
				$ranges{$1}{RANGE_MAX} = $3;
				push(@{$ranges{$1}{KEYS}}, $4);
			}
		}
	}
	# End of process
	
	while (my $arrayref = $csv->getline_hr ($fh)) {
		my %list;
		my $foundElement = 0;
		if($arrayref->{ELEMENT_TYPE} eq 'ImageControl') {
			DEBUG "Found Element of type \"$arrayref->{ELEMENT_TYPE}\"";
			%list = extract_keys($arrayref, qw(SIZE_X SIZE_Y POS_X POS_Y LOCKED IMAGE_PATH));
			$list{IMAGE_PATH} = $graphicalDashboard->{properties}->{PROJECT}."\\".$graphicalDashboard->{TrainTracerImagePath}.$list{IMAGE_PATH} if $list{IMAGE_PATH};	
			$list{IMAGE_PATH} =~ s#\\#\\\/#g if $list{IMAGE_PATH};
			$foundElement = 1;			
		}
		elsif($arrayref->{ELEMENT_TYPE} eq 'ImageViewVariable' or $arrayref->{ELEMENT_TYPE} eq 'SimpleView') {
			DEBUG "Found Element of type \"$arrayref->{ELEMENT_TYPE}\"";
			%list = extract_keys($arrayref, qw(SIZE_X SIZE_Y POS_X POS_Y LOCKED PATH));
			
			$foundElement = 1;	
		}
		else {
			WARN "Unknown Element type : \"$arrayref->{ELEMENT_TYPE}\"";
			%list = extract_keys($arrayref, qw(POS_X POS_Y LOCKED PATH));
		}

		if ($foundElement) {
			$list{$arrayref->{ELEMENT_TYPE}} = 1;
			$list{PATH} = $graphicalDashboard->{TrainTracerVariablesPath}.$list{PATH}  if $list{PATH};	
			$list{PATH} =~ s#\/#\\\/#g if $list{PATH};
			$list{SIZE_X} = 'NaN' unless $list{SIZE_X};
			$list{SIZE_Y} = 'NaN' unless $list{SIZE_Y};
			$list{POS_X} = '0' unless $list{POS_X};
			$list{POS_Y} = '0' unless $list{POS_Y};
			$list{LOCKED} = 'true' unless $list{LOCKED};
			push(@list_of_elements, \%list);
		}
		
		###################################################
		# managing variables
		###################################################
		if($arrayref->{PATH}) {
		
			my $path = $arrayref->{PATH};
			my @lists_ranges;
			
			# Checking ranges
			foreach my $key_range (keys %ranges) {

				my %range;
				foreach my $key (@{$ranges{$key_range}{KEYS}}) {
					$range{$key} = $arrayref->{"${key_range}_$key"} if($arrayref->{"${key_range}_$key"});
				}
				
				if(%range) {
					$range{RANGE_MIN} = $ranges{$key_range}{RANGE_MIN};
					$range{RANGE_MAX} = $ranges{$key_range}{RANGE_MAX};
					$range{SMALL_IMAGE} = $graphicalDashboard->{TrainTracerImagePath}.$range{SMALL_IMAGE} if $range{SMALL_IMAGE};
					$range{IMAGE} = $graphicalDashboard->{TrainTracerImagePath}.$range{IMAGE} if $range{IMAGE};
					
					my $defaultColor = 'R=255 G=255 B=255';
					$defaultColor = 'R=0 G=255 B=0' if $range{RANGE_MIN} == 0 and $range{RANGE_MAX} == 0;
					$defaultColor = 'R=255 G=0 B=0' if $range{RANGE_MIN} == 1 and $range{RANGE_MAX} == 1;

					$range{COLOR} = $defaultColor unless $range{COLOR};
					push(@lists_ranges, \%range);
				}
			}
			
			if ($variablesInserted{$path}) {
				WARN "Variable $path already inserted. It will be skipped" if $variablesInserted{$path}; 
			}
			else {
				DEBUG "Adding variable \"$path\"";
				$variablesInserted{$path} = 1;
				$path = $graphicalDashboard->{TrainTracerVariablesPath}.$path;	
				push(@list_of_vars, {PATH => $path, RANGES => \@lists_ranges });	
			}
		}
	}
	
	if(%variablesInserted) {
		my $outDir = $SCRIPT_DIRECTORY.OUTPUT_DIR.'/';
		
		open OUTFILE, ">:encoding(UTF-8)", "$outDir/$graphicalDashboard->{properties}->{FILE_ID}.xml";
			
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
	else {
		ERROR "Dashboard cannot be generated, because no variables are defined.";
	}
}

sub extract_keys {
	my $ref_array = shift;
	my @elements = @_;

	my %list;
	foreach my $key (@elements) {
		$list{$key} = $ref_array->{$key} if ($ref_array->{$key});
	}
	
	return %list;
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

sub logFile {
	my $type = shift;
	my $file = OUTPUT_DIR.'/logfile.csv';
	return $file;
}

__END__
:endofperl
pause