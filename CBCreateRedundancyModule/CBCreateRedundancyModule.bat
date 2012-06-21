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
use DisplayMgt qw(displayBox);
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
	DEFAULT_TEMPLATE => 'Default',
	MAIN_TEMPLATE_NAME => 'main.tmpl',
};

INFO("Starting program (V ".PROGRAM_VERSION.")");

#########################################################
# loading of Configuration files
#########################################################
my $config = loadLocalConfig("CBCreateRedundancyModule.config.xml", 'config.xml', KeyAttr => {}, ForceArray => qr/^(component|rule)$/);

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
foreach my $component (@{$config->{component_list}->{component}}) {
	INFO "Processing Component \"$component->{name}\"";
	
	my $file = $SCRIPT_DIRECTORY.INPUT_DIR.'/'.$component->{refFile};
	
	
	unless (open IN_FILE, $file) {
		ERROR "input file \"$file\" cannot be processed. Component is skipped.";
		next;
	}
	
	my %variablesList;
	foreach my $line (<IN_FILE>) {
		if($line =~ /^\s*<variable name="([^"]*)">\s*$/) {
			$variablesList{$1} = undef;
		}
	}

	#########################################################
	# This part generates input / output files
	#########################################################
	my ($found, $others, $baseNames) = applyRewriteRules(\%variablesList, $config->{replacementRules}->{rule}, $component->{replacementRules}->{rule});
	
	seek(IN_FILE, 0, 0) or LOGDIE "Can't seek to beginning of file: $!";
	my $content = '';
	while(<IN_FILE>) { $content .= $_; }
	close IN_FILE;
	
	my $outDir = $SCRIPT_DIRECTORY.OUTPUT_DIR.'/'.$component->{name};
	mkdir($outDir);
	open OUTFILE, ">$outDir/inputs.xml";
	print OUTFILE $content;
	close OUTFILE;
	
	for my $key (keys(%$found)) {
		$content =~ s/$key/$found->{$key}/g;
	}
	
	open OUTFILE, ">$outDir/outputs.xml";
	print OUTFILE $content;
	close OUTFILE;
	
	#########################################################
	# This part generates list of variables
	#########################################################

	my @baseNames;
	for my $key (keys(%$baseNames)) {
		my %element;
		$element{BASENAME} = $key;
		push(@baseNames, \%element);
	}
	
	createFile('body.tmpl', $outDir.'/body.txt', \@baseNames);
	createFile('header.tmpl', $outDir.'/header.txt', \@baseNames);
}

sub createFile {
	my ($tmplFile, $outFile, $variables) = @_;
	
	DEBUG "Generating \"$outFile\"";
	open (MAINFILE, ">$outFile");

	my $template_file = $defaultTemplateDir.'/'.$tmplFile;
	my $mainTemplate = HTML::Template -> new( die_on_bad_params => 1, filename => $template_file );
			
	$mainTemplate->param(MODULES => $variables);
	
	print MAINFILE $mainTemplate->output;
	close(MAINFILE);
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

sub applyRewriteRules {
	my ($list, $rules, $additionnalRule) = @_;
	
	my %foundItems;
	my %baseNames;
	my %notFoundItems;
	
	push(@$rules, @$additionnalRule);
		
	for my $variable (keys %$list) {
		my $found = 0;
		my $baseNameDefined = undef;
		
		foreach my $rule (@$rules) {
			my ($new_variable, $basename) = applyRule($variable, $rule);
			
			
			if($new_variable ne $variable) {
				$foundItems{$variable} = $new_variable;
				$baseNameDefined = $basename if $basename;
				$found = 1;
				last;
			}
		}
		
		unless($found) {
			my ($new_variable, $basename) = applyRule($variable, $config->{replacementRules}->{default_rule});
						
			if($new_variable ne $variable) {
				WARN "Using default rule for \"$variable\"";
				$foundItems{$variable} = $new_variable;
				$baseNameDefined = $basename if $basename;
			}
			else {
				ERROR "No match rule for \"$variable\"";
				$notFoundItems{$variable} = undef;
			}
		}
		
		push(@{$baseNames{$baseNameDefined}}, $variable) if $baseNameDefined;
	}
	
	return (\%foundItems, \%notFoundItems, \%baseNames);
}

sub applyRule {
	my ($variable, $rule) = @_;
	my $match = $rule->{matchExpr};
	my $replace = '"'.$rule->{replaceExpr}.'"';
	
	my $repl_variable = $variable;
	$repl_variable =~ s/$match/eval $replace/e;
	
	if($rule->{baseNameExpr}) {
		my $replace = '"'.$rule->{baseNameExpr}.'"';
		my $basenamevar = $variable;
		$basenamevar =~ s/$match/eval $replace/e;
		return ($repl_variable, $basenamevar);
	}
	
	return ($repl_variable, undef);
}

sub genBaseNames {
	my ($list) = @_;
	
	my %foundItems;
	my %groups;
	my %unkItems;
	
	
	for my $variable (keys %$list) {
		if($variable and $variable =~ /^(.*)R(?:1|2)$/) {
			push(@{$foundItems{$1}},$variable);
		}
		elsif($variable and $variable =~ /^[A-Z0-9_]+$/) {
			$groups{$variable} = undef;
		}
		else {
			push(@{$unkItems{NOT_FOUND}}, $variable);
		}
	}
	
	return (\%foundItems, \%groups, \%unkItems);
}

__END__
:endofperl
pause