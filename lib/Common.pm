use Log::Log4perl qw(:easy);
use XML::Simple;

my $localConfigPath = "./localconfig/";

my $config_text = <<TEXT;
log4perl.rootLogger = DEBUG, LOGFILE, Screen

log4perl.appender.LOGFILE = Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename = logFile.csv
log4perl.appender.LOGFILE.mode = write
log4perl.appender.LOGFILE.layout = PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern = %p;%d;(%F:%L);%m%n

log4perl.appender.Screen=Log::Log4perl::Appender::Screen
log4perl.appender.Screen.stderr=0
log4perl.appender.Screen.Threshold=INFO
log4perl.appender.Screen.layout=Log::Log4perl::Layout::SimpleLayout

TEXT

Log::Log4perl->init_once( $localConfigPath."logging-config.conf" ) and DEBUG "Found customization of logging file" if -r $localConfigPath."logging-config.conf";
Log::Log4perl->init_once( \$config_text ) and DEBUG "Taking default logging parameters" unless -r $localConfigPath."logging-config.conf";

my $logger = Log::Log4perl->get_logger();

sub loadConfig {
	my $file = shift;
	my $configFile = $localConfigPath.$file;
	LOGDIE "Unable to load main configuration file ($configFile)" unless (-r $configFile);
	DEBUG "Loading configuration file $configFile.";
	
	return %{XMLin($configFile, @_)};
}