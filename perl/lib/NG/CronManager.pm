package NG::CronManager;
use strict;

use NG::Application;
our @ISA = qw/NG::Application/;

my $OPS = {
    'runtask'       => {sub => 'doRunTask'},        #Run task specified
    'showcrontab'   => {sub => 'doShowCrontab'},    #Generates crontab to output
    'updatecrontab' => {sub => 'doUpdateCrontab'},  #Generates crontab and installs it
    'help'          => {sub => 'doShowUsage'},      #Default function
};
#HELP
$OPS->{'runtask'}->{cmdline}= "{op} MODULECODE/TASK";
$OPS->{'showcrontab'}->{cmdline}= "{op}";
$OPS->{'updatecrontab'}->{cmdline}= "{op} [USERNAME]";
$OPS->{'help'}->{cmdline}= "{op}";

my @helpOrder = qw/
    runtask
    showcrontab
    updatecrontab
    help
/;

sub run {
    my $cms = shift;
    
    my $dbh = $cms->dbh();
    $cms->openConfig() || return $cms->showError();
    
    my $cmd = $ARGV[0];
    my $op = undef;
    $op = $OPS->{$cmd} if $cmd;

    if (! $cmd || ! $op) {
        $op = $OPS->{help};
        #push @opParams,$cmd;
    };

    my $method = $op->{sub};
    $cms->$method(@ARGV);
};

sub doShowUsage {
    my $cms = shift;
    my $cmd = shift || "";

    print (($cmd)?"Incorrect command specified.\n":"No command specified.\n") if $cmd ne "help";

    my %ops = map {$_,1} @helpOrder;
    foreach my $key (sort keys %$OPS) {
        push @helpOrder, $key unless exists $ops{$key};
    };

    print "Possible commands are:\n";
    foreach my $key (@helpOrder) {
        my $h = (exists $OPS->{$key}->{cmdline})?$OPS->{$key}->{cmdline}:$key;
        $h=~ s/\{op\}/$key/;
        print "$0 $h\n";
    };
    exit 0;
};

sub doRunTask {
    my ($self,$cmd,$task) = (shift,shift,shift);
    
    sub _error { print $_[0]."\n"; exit 1; };
    
    _error "Incorrect usage. Run by root is forbidden." if ($< == 0);
    _error "Incorrect usage. No task to run specified." unless $task;
    my $moduleCode = undef;
    if ($task =~ /(\S+?)\/(\S+)/){
        $moduleCode = $1;
        $task = $2;
    };
    _error "Incorrect usage. No MODULECODE or TASK specified." unless $task && $moduleCode;
    my $mObj = $self->getModuleByCode($moduleCode);
    _error $self->getError() unless $mObj;
    my $interface = $mObj->getInterface('CRON');
    _error "Task $moduleCode/$task: Module $moduleCode has no CRON interface." unless $interface;
    
    
    
    print "Running task $task\n";
}

sub doShowCrontab {
    my $self = shift;
    
    print $self->_generateCrontab();
}

sub doUpdateCrontab {
    my ($self,$cmd,$username) = (shift,shift,shift);
    
    if (($< == 0) && !$username) {
        print "Incorrect usage. Run by root requires USERNAME.\n";
        exit 1;
    };
    
    my $crontab = $self->_generateCrontab();
    ### # # # # # NG CMS 6 CRONTAB BEGIN # # # # #
    ### This block can be updated by cron.pl updatecrontab
    ### # # # # #  NG CMS 6 CRONTAB END  # # # # #
    
    #1) Add delimiters at top and bottom of $crontab. Add comment.
    #2) Get existing crontab content
    #3) Find existing block by delimiters and remove it
    #4) Place new block instead
    #5) Update crontab
    
    die "Not implemented yet";
}

sub _generateCrontab {
    my $self = shift;
    
    my $iterator = $self->getModulesIterator();
    while (my $mObj = &$iterator()) {
print $mObj->getModuleCode()."\n";
        my $interface = $mObj->getInterface('CRON') or next;
    };
    
    return "* * * * * /sbin/reboot\n";
};

1;
