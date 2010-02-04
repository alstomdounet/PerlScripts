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
use ClearquestMgt qw(connectCQ makeQuery);
use Storable qw(store retrieve thaw freeze);
use HTML::Template;
use Time::localtime;
use POSIX qw(strftime);
use XML::Simple;

use constant {
	PROGRAM_VERSION => '0.2 beta',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";

my $ConfigTables = loadScriptConfig("config.xml", ForceArray => qr/^(table|node)$/); # Loading / preprocessing of the configuration file

INFO "Connecting to Clearquest with user $Config{clearquest}->{login}";
connectCQ($Config{clearquest}->{login}, $Config{clearquest}->{password}, $Config{clearquest}->{database});



foreach my $table (@{$Config->{tables}->{table}}) {
	INFO "Processing \"$table->{title}\"";
	my @listFields = split(/,\s*/, $table->{fieldsToRetrieve});
	my @fieldsSort = split(/,\s*/, $table->{fieldsSorting});
	my @results = makeQuery($table->{ClearquestType}, \@listFields, $table->{filtering});

	#store(\@results, 'test.db');
	#my @results = @{retrieve('test.db')};
	
	@results = sort { 
		foreach my $field (@fieldsSort) 
		{ my $result = $a->{$field} cmp $b->{$field};
			return $result if $result != 0;
		} 
	} @results;
	
	my $filename = $table->{filename};
	unlink($filename);
	open (FILE, ">$filename");
	
	my $t = HTML::Template -> new( filename => "./Report.tmpl" );

	my @headerToPrint;
	push(@headerToPrint, { FIELD => '#'});
	foreach my $field (@listFields) {
		next if $field eq 'dbid';
		push(@headerToPrint, { FIELD => $field});
	}
	
	my @resultsToPrint;
	my $number = 0;
	foreach my $result (@results) {
		my @resultToPrint;
		foreach my $field (@listFields) {
			next if ($field eq 'dbid' or $field eq 'id');
			my $field = $result->{$field};
			$field =~ s/\n/<br \/>\n/g;
			push(@resultToPrint, { CONTENT => $field});
		}
		push(@resultsToPrint, { NUMBER => ++$number, DBID => $result->{'dbid'}, ID => $result->{'id'}, RESULT => \@resultToPrint });
	}
	
	$t->param(HEADER => \@headerToPrint);
  	$t->param(RESULTS => \@resultsToPrint);
	$t->param(TABLE_NAME => $table->{title});
	my $tm = strftime "%d-%m-%Y à %H:%M:%S", gmtime;
	$t->param(DATE => $tm);
	
	print FILE $t->output;
	
	close(FILE);
}

__END__
:endofperl
pause