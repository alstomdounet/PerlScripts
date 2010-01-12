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

use constant {
	PROGRAM_VERSION => '0.1',
};

INFO "Starting program (V ".PROGRAM_VERSION.")";
my %Config = loadConfig("config.xml", ForceArray => qr/^table$/); # Loading / preprocessing of the configuration file

INFO "Connecting to Clearquest with user $Config{clearquest}->{login}";
connect($Config{clearquest}->{login}, $Config{clearquest}->{password}, $Config{clearquest}->{database});



foreach my $table (@{$Config{tables}->{table}}) {
	my $product  = shift;
	my $fieldsToRetrieve = shift;
	
	my @listFields = split(/,\s*/, $table->{fieldsToRetrieve});
	
	my @results = makeQuery($table->{ClearquestType}, \@listFields, $table->{filtering});
	
	#store(\@results, 'test.db');
}

LOGDIE 'end of program';

__END__
:endofperl
pause