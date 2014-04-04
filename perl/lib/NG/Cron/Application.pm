package NG::Cron::Application;
use strict;

use NG::Application;
our @ISA = qw/NG::Application/;

use NG::Cron::Task;

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
    my $self = shift;
    
    my $dbh = $self->dbh();
    $self->openConfig() || return $self->showError();
    
    my $cmd = $ARGV[0];
    my $op = undef;
    $op = $OPS->{$cmd} if $cmd;
    
    if (! $cmd || ! $op) {
        $op = $OPS->{help};
    };
    
    my $method = $op->{sub};
    my $ret = eval{
        $cms->$method(@ARGV);
    };
    if (my $exc = $@) {
        if (NG::Exception->caught($exc)) {
            print STDERR $exc->message();
        };
        #warn "Operation '$operation' failed: $exc";
        #if ($exc =~ /^(.*)\ at\ /) {
        #    $exc = $1;
        #};
        die $exc;
    };
    exit(0);
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
    NG::Exception->throw('NG.INTERNALERROR', "Incorrect usage. Run by root is forbidden.") if ($< == 0); #запретим запуск от рута
    NG::Exception->throw('NG.INTERNALERROR', "Incorrect usage. No task to run specified.") unless $task;
    my $moduleCode = undef;
    if ($task =~ /(\S+?)\/(\S+)/){
        $moduleCode = $1;
        $task = $2;
    };
    my $task = NG::Cron::Task->new({MODULE=>$moduleCode, TASK=>$task});
    $task->run({startup=>'auto'});
};


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
    
    #my $crontab = $self->_generateCrontab();
    ### # # # # # NG CMS 6 CRONTAB BEGIN # # # # #
    ### This block can be updated by cron.pl updatecrontab
    ### # # # # #  NG CMS 6 CRONTAB END  # # # # #
    
    #1) Add delimiters at top and bottom of $crontab. Add comment.
    #2) Get existing crontab content
    #3) Find existing block by delimiters and remove it
    #4) Place new block instead
    #5) Update crontab
    
    die "Not implemented yet";
    
    $username = $ENV{USER} if ($< != 0 && !$username);
    my $cronfile = $self->getSiteRoot()."/tmp/cron.tmp";
    my @newcrontab =();
    my $started = 0; #флаг того что найдена строка ограничитель
    my $modifed = 0;
    my @cronstr = $self->_generateCrontab();
    my @oldcron = `crontab -l`; #тут хранится строка крона
    my $user = uc( $self->confParam("CRONTAB.User") || $username );
    my $begin_str = "### # # # NG CMS 6 CRONTAB BEGIN $user # # # ###\n";
    $begin_str .= "MAILTO=".($self->confParam("CRONTAB.DebugTo") || 'rpv@nikolas.ru')."\n";
    my $end_str = "### # # # NG CMS 6 CRONTAB END $user  # # # ###\n";
    unshift @cronstr, $begin_str ;
    push @cronstr, $end_str;
    $begin_str = qr/NG CMS 6 CRONTAB BEGIN $user/;
    $end_str = qr/NG CMS 6 CRONTAB END $user/;

    while (my $line = shift @oldcron){
        if($started){
            next unless ($line =~ $end_str);
            $started = 0;
        }else{
            if($line =~ $begin_str){
                $started = 1;
                $modifed = 1;
                push @newcrontab , @cronstr;
                
            }else{
                push  @newcrontab, $line;
            }
        }
    }
    push  @newcrontab, ("\n",@cronstr) unless $modifed;
    open FH, '>', $cronfile || die $!;
    print FH @newcrontab;
    close(FH);
    my $ret = system("crontab -u $username $cronfile");
    sleep(1);
    unlink $cronfile;
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
