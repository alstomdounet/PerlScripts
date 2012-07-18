use Log::Log4perl qw(:easy);
use XML::Simple;
use File::Path qw (mkpath);
use File::Copy;
use Win32 qw(CSIDL_DESKTOPDIRECTORY CSIDL_APPDATA CSIDL_PERSONAL);

my $scriptName = $0;
$scriptName =~ s/.*\\([^\\]+)\.[^\.]+$/$1/;

my $ROOT_DIR = Win32::GetFolderPath(CSIDL_DESKTOPDIRECTORY).'\\PerlScripts';
$ROOT_DIR = Win32::GetFolderPath(CSIDL_PERSONAL).'\\PerlScripts' unless -d $ROOT_DIR;
$ROOT_DIR = Win32::GetFolderPath(CSIDL_APPDATA).'\\PerlScripts' unless -d $ROOT_DIR;

my $SCRIPT_OUTPUT_DIR = $ROOT_DIR.'\\'.$scriptName.'\\';
my $SCRIPT_PARAMETERS_DIR = $SCRIPT_OUTPUT_DIR.'Config\\';
my $SCRIPT_LOG_DIR = $SCRIPT_OUTPUT_DIR."Log\\";
my $SHARED_OUTPUT_DIR = $ROOT_DIR.'\\Shared\\';
my $SHARED_PARAMETERS_DIR = $SHARED_OUTPUT_DIR.'Config\\';


mkpath($SHARED_PARAMETERS_DIR) and print "Shared script parameters directory created in \"$SHARED_PARAMETERS_DIR\"\n" unless -d $SHARED_PARAMETERS_DIR;
mkpath($SHARED_OUTPUT_DIR) and print "Shared script parameters directory created in \"$SHARED_OUTPUT_DIR\"\n" unless -d $SHARED_OUTPUT_DIR;
mkpath($SCRIPT_PARAMETERS_DIR) and print "Perl script parameters directory created in \"$SCRIPT_PARAMETERS_DIR\"\n" unless -d $SCRIPT_PARAMETERS_DIR;
mkpath($SCRIPT_OUTPUT_DIR) and print "Perl script output directory created in \"$SCRIPT_OUTPUT_DIR\"\n" unless -d $SCRIPT_OUTPUT_DIR;
mkpath($SCRIPT_LOG_DIR) and print "Perl script directory for logfiles created in \"$SCRIPT_LOG_DIR\"\n" unless -d $SCRIPT_LOG_DIR;

my $config_text = <<TEXT;
log4perl.rootLogger = DEBUG, LOGFILE, PERMLOGFILE, Screen

log4perl.appender.LOGFILE = Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename = sub { logFile('lastExec'); };
log4perl.appender.LOGFILE.utf8 = 1
log4perl.appender.LOGFILE.mode = write
log4perl.appender.LOGFILE.layout = PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern = %p;%r;(%F{2}:%L);%m%n

log4perl.appender.PERMLOGFILE = Log::Log4perl::Appender::File
log4perl.appender.PERMLOGFILE.filename = sub { logFile('history'); };
log4perl.appender.PERMLOGFILE.utf8 = 1
log4perl.appender.PERMLOGFILE.mode = append
log4perl.appender.PERMLOGFILE.layout = PatternLayout
log4perl.appender.PERMLOGFILE.Threshold=INFO
log4perl.appender.PERMLOGFILE.layout.ConversionPattern = %p;%d;(%F{2}:%L);%m%n

log4perl.appender.Screen=Log::Log4perl::Appender::Screen
log4perl.appender.Screen.stderr=0
log4perl.appender.Screen.Threshold=INFO
log4perl.appender.Screen.layout=Log::Log4perl::Layout::SimpleLayout

TEXT

my $foundLogFile = 0;
Log::Log4perl->init_once( $SCRIPT_PARAMETERS_DIR."log-config.conf" ) and DEBUG "Found customization of logging file in script directory" and $foundLogFile++ if -r $SCRIPT_PARAMETERS_DIR."log-config.conf";
Log::Log4perl->init_once( $SHARED_PARAMETERS_DIR."log-config.conf" ) and DEBUG "Found customization of logging file in shared directory" and $foundLogFile++ if not $foundLogFile and -r $SHARED_PARAMETERS_DIR."log-config.conf";
Log::Log4perl->init_once( \$config_text ) and DEBUG "Taking default logging parameters" if not $foundLogFile;

my $logger = Log::Log4perl->get_logger();

sub getSharedDirectory { return $SHARED_OUTPUT_DIR; }
sub getScriptDirectory { return $SCRIPT_OUTPUT_DIR; }
sub getScriptName {	return $scriptName; }
sub loadSharedConfig { return _loadConfig($SHARED_PARAMETERS_DIR, @_); }
sub loadLocalConfig { return _loadConfig($SCRIPT_PARAMETERS_DIR, @_); }

sub backCopy { 
	my ($newName, $file) = @_; 
	WARN "This function has to be used only during development";
	LOGDIE "Missing New name" unless $newName; 
	copy($SCRIPT_PARAMETERS_DIR.$newName, '.\\initConfig\\'.$file); 
}

sub _loadConfig {
	my ($directory, $file, $newName, @XMLArgs) = @_;

	$newName = $file unless $newName;
	my $configFile = $directory.$file;
	my $realConfigFile = $directory.$newName;
	if(-f $realConfigFile) {
		DEBUG "Loading configuration file \"$newName\" on \"$directory\".";
		return XMLin($realConfigFile, @XMLArgs);
	}
	else {
		$default_template = '.\\initConfig\\'.$file;
		LOGDIE "Undefined default template \"$default_template\"" unless -f $default_template;
		copy($default_template, $realConfigFile) and INFO "Created file \"$realConfigFile\" used to parametrize script";
		LOGDIE "You have first to customize \"$realConfigFile\"";
	}	
}

sub logFile {
	my $type = shift;
	my $file = $SCRIPT_LOG_DIR.$type.'.csv';
	return $file;
}