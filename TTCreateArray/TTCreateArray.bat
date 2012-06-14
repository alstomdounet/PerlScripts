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


my $csv = Text::CSV->new ({sep_char => "\t", empty_is_undef => 0, auto_diag => 1, binary => 1});

#########################################################
# Allowed colors retrieval
#########################################################
my %STANDARD_COLORS;

my $fh;
unless (open $fh, "allowed_colors.csv") {
	ERROR "input file \"allowed_colors.csv\" cannot be processed. Program cannot continue.";
	die;
}
else {
	my @columns = @{$csv->getline($fh)};
	$csv->column_names (@columns);
	
	my @render_array;
	while (my $arrayref = $csv->getline_hr ($fh)) {
		ERROR "Color is not defined" and die $arrayref->{ALLOWED_COLORS} unless defined $arrayref->{ALLOWED_COLORS};
		
		$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{ALLOWED_COLORS} = $arrayref->{ALLOWED_COLORS};
		$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{RED} = $arrayref->{RED} if check_color_validity($arrayref->{ALLOWED_COLORS}, $arrayref->{RED});
		$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{GREEN} = $arrayref->{GREEN} if check_color_validity($arrayref->{ALLOWED_COLORS}, $arrayref->{GREEN});
		$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{BLUE} = $arrayref->{BLUE} if check_color_validity($arrayref->{ALLOWED_COLORS}, $arrayref->{BLUE});
		$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{COMPL_RED} = 255 - $STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{RED};
		$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{COMPL_GREEN} = 255 - $STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{GREEN};
		$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{COMPL_BLUE} = 255 - $STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}}{BLUE};
		
		push(@render_array,$STANDARD_COLORS{$arrayref->{ALLOWED_COLORS}});
	}
	
	open OUTFILE, ">:encoding(UTF-8)", "render_allowed_colors.html";
			
	my $template_file = './Templates/Color_Html/body.tmpl';
	my $mainTemplate = HTML::Template -> new( die_on_bad_params => 0, filename => $template_file, loop_context_vars => 1 );
			
	$mainTemplate->param(LIST_OF_COLORS => \@render_array);
			
	INFO "Generating render_allowed_colors.html";
	print OUTFILE $mainTemplate->output;
	close OUTFILE;
}

#########################################################
# For each graphical dashboard to generate
#########################################################
foreach my $graphicalDashboard (@{$config->{GraphicalDashboards}->{GraphicalDashboard}}) {
	INFO "Processing Component \"$graphicalDashboard->{properties}->{TITLE}\"";

	#my %modulesDescriptors;
	my @list_of_vars;
	my @list_of_elements;
	my %variablesInserted;
	my $DASHBOARD_WIDTH = 0;
	my $DASHBOARD_HEIGHT = 0;
	
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
		
		my @COMMON_ELEMENTS = qw(POS_X POS_Y SCALE ANGLE LOCKED);
		
		if($arrayref->{ELEMENT_TYPE} eq 'ImageControl') {
			DEBUG "Found Element of type \"$arrayref->{ELEMENT_TYPE}\"";
			%list = extract_keys($arrayref, @COMMON_ELEMENTS, qw(SIZE_X SIZE_Y IMAGE_PATH));
			$list{IMAGE_PATH} = $graphicalDashboard->{properties}->{PROJECT}."\\".$graphicalDashboard->{TrainTracerImagePath}.$list{IMAGE_PATH} if $list{IMAGE_PATH};	
			$list{IMAGE_PATH} =~ s#\\#\\\/#g if $list{IMAGE_PATH};
			$foundElement = 1;			
		}
		elsif($arrayref->{ELEMENT_TYPE} eq 'ImageViewVariable' or $arrayref->{ELEMENT_TYPE} eq 'SimpleView') {
			DEBUG "Found Element of type \"$arrayref->{ELEMENT_TYPE}\"";
			%list = extract_keys($arrayref, @COMMON_ELEMENTS, qw(SIZE_X SIZE_Y PATH));
			
			$foundElement = 1;	
		}
		elsif($arrayref->{ELEMENT_TYPE} eq 'Label') {
			DEBUG "Found Element of type \"$arrayref->{ELEMENT_TYPE}\"";
			%list = extract_keys($arrayref, @COMMON_ELEMENTS, qw(TEXT));
			
			$foundElement = 1;	
		}
		elsif($arrayref->{ELEMENT_TYPE}) {
			ERROR "Unknown Element type : \"$arrayref->{ELEMENT_TYPE}\"";
		}
		else {
			DEBUG "No Element type found.";
		}

		if ($foundElement) {
			my $tmp_width = 2; # to correct anomaly of TrainTracer with sizes...
			$tmp_width += $list{POS_X} if $list{POS_X};
			$tmp_width += $list{SIZE_X} if $list{SIZE_X};
			
			$DASHBOARD_WIDTH = $tmp_width if $tmp_width > $DASHBOARD_WIDTH;
			
			my $tmp_height = 2; # to correct anomaly of TrainTracer with sizes...
			$tmp_height = $list{POS_Y} if $list{POS_Y};
			$tmp_height += $list{SIZE_Y} if $list{SIZE_Y};
			
			$DASHBOARD_HEIGHT = $tmp_height if $tmp_height > $DASHBOARD_HEIGHT;
		
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
					
					my $defaultColor = 'WHITE';
					
					$range{COLOR} = translateColor($range{COLOR});

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
		
		open OUTFILE, ">:encoding(UTF-8)", "$outDir/$graphicalDashboard->{properties}->{TITLE}.xml";
			
		my $template_file = $defaultTemplateDir.'/body.tmpl';
		my $mainTemplate = HTML::Template -> new( die_on_bad_params => 0, filename => $template_file, loop_context_vars => 1 );
			
		foreach my $property (keys %{$graphicalDashboard->{properties}}) {
			$mainTemplate->param($property => $graphicalDashboard->{properties}->{$property});
		}
		
		$DASHBOARD_WIDTH = 10000 unless $DASHBOARD_WIDTH;
		$DASHBOARD_HEIGHT = 10000 unless $DASHBOARD_HEIGHT;
		
		$mainTemplate->param(DASHBOARD_WIDTH => $DASHBOARD_WIDTH) unless $graphicalDashboard->{properties}->{DASHBOARD_WIDTH} and ref $graphicalDashboard->{properties}->{DASHBOARD_WIDTH} eq "";;
		
		$mainTemplate->param(DASHBOARD_HEIGHT => $DASHBOARD_HEIGHT) unless $graphicalDashboard->{properties}->{DASHBOARD_HEIGHT} and ref $graphicalDashboard->{properties}->{DASHBOARD_HEIGHT} eq "";
			
		$mainTemplate->param(LIST_OF_VARS => \@list_of_vars);
		$mainTemplate->param(LIST_OF_ELEMENTS => \@list_of_elements);
			
		INFO "Generating \"$graphicalDashboard->{properties}->{TITLE}.xml\"";
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

sub check_color_validity {
	my $color_name = shift;
	my $color = shift;
	ERROR "Color $color_name is not a valid value (integer between 0 and 255). Read \"$color\"." and die unless defined $color and $color =~ /^\d{1,3}$/;
	ERROR "Color $color_name is not inside valid range (integer between 0 and 255). Read \"$color\"." and die unless $color >= 0 and $color <= 255;
	return 1;
}

sub translateColor {
	my $color_name = shift;
	
	$color_name = 'WHITE' unless $color_name;
	ERROR "Color \"$color_name\" is not recognized. Default color will be used." and $color_name = 'WHITE' unless defined $STANDARD_COLORS{$color_name};
	
	
	return "R=$STANDARD_COLORS{$color_name}{RED} G=$STANDARD_COLORS{$color_name}{GREEN} B=$STANDARD_COLORS{$color_name}{BLUE}";
}

__END__
:endofperl
pause