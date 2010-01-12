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
use ClearquestMgt qw(connect makeQuery);
use Storable qw(store retrieve thaw freeze);
use HTML::Template;

use constant {
	PROGRAM_VERSION => '0.1',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";
my %Config = loadConfig("config.xml", ForceArray => qr/^table$/); # Loading / preprocessing of the configuration file

INFO "Connecting to Clearquest with user $Config{clearquest}->{login}";
#connect($Config{clearquest}->{login}, $Config{clearquest}->{password}, $Config{clearquest}->{database});



foreach my $table (@{$Config{tables}->{table}}) {
	my @listFields = split(/,\s*/, $table->{fieldsToRetrieve});
	#my @results = makeQuery($table->{ClearquestType}, \@listFields, $table->{filtering});
	#store(\@results, 'test.db');
	my @results = @{retrieve('test.db')};
	
	my $filename = $table->{filename};
	unlink($filename);
	open (FILE, ">$filename");
	
	my $t = HTML::Template -> new( filename => "./Report.tmpl" );

	my @headerToPrint;
	push(@headerToPrint, { FIELD => '#'});
	foreach my $field (@listFields) {
		push(@headerToPrint, { FIELD => $field});
	}
	
	my @resultsToPrint;
	my $number = 0;
	foreach my $result (@results) {
		my @resultToPrint;
		push(@resultToPrint, { CONTENT => ++$number});
		foreach my $field (@listFields) {
			my $field = $result->{$field};
			$field =~ s/\n/<br \/>\n/g;
			push(@resultToPrint, { CONTENT => $field});
		}
		push(@resultsToPrint, { RESULT => \@resultToPrint });
	}
	
	$t->param(HEADER => \@headerToPrint);
  	$t->param(RESULTS => \@resultsToPrint);
	$t->param(TABLE_NAME => $table->{title});
	
	print FILE $t->output;
	
	close(FILE);
}

__END__
:endofperl
pause