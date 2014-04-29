package NG::Cron::Application;
use strict;

use NG::Application;
our @ISA = qw/NG::Application/;

use NG::Exception;
use NG::Cron::Task;
use NG::Cron::Service;

our $crontab = '/usr/bin/crontab';

our $begin_re = qr/NG CMS 6 CRONTAB BEGIN/;
our $end_re   = qr/NG CMS 6 CRONTAB END/;

our $begin_str = "### # # # NG CMS 6 CRONTAB BEGIN # # # ###\n";
our $end_str   = "### # # # NG CMS 6 CRONTAB END   # # # ###\n";

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
        $self->$method(@ARGV);
    };
    if (my $exc = $@) {
        if (NG::Exception->caught($exc)) {
            print STDERR $exc->message()."\n";
        }
        else {
            #warn "Operation '$operation' failed: $exc";
            #if ($exc =~ /^(.*)\ at\ /) {
            #    $exc = $1;
            #};
            print STDERR $exc;
        };
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
    NG::Cron::Task->new({MODULE=>$moduleCode, TASK=>$task})->run({startup=>'auto'});
};

sub doShowCrontab {
    my $self = shift;
    
    my @cronstr = NG::Cron::Service::_generateCrontab($self,"runtask");
    unshift @cronstr, $begin_str;
    push @cronstr,    $end_str;
    
    print @cronstr;
};

sub doUpdateCrontab {
    my ($self,$cmd,$username) = (shift,shift,shift);
    
    if (($< == 0) && !$username) {
        print "Incorrect usage. Run by root requires USERNAME.\n";
        exit 1;
    };
    
    if (($< != 0) && $username) {
        print "Incorrect usage. USERNAME requires run by root.\n";
        exit 1;
    };
    
    unless ($begin_str =~ $begin_re && $end_str =~ $end_re) {
        print 'Incorrect configuration. $begin_str must match $begin_re ; $end_str must match $end_re.\n';
        exit 1;
    };
    
    my $crontabParams = '';
    $crontabParams = "-u $username" if $username;
    
    #Получаем старый файл расписания
    my @oldcron = `$crontab $crontabParams -l`;
    #This breaks when no any crontab exists before run.
    #if($@ || $?){
    #    die "Error retrieving old crontab: ".$@.$?;
    #};
    
    #Формируем новый блок нашего расписания
    my @cronstr = NG::Cron::Service::_generateCrontab($self,"runtask");
    unshift @cronstr, $begin_str;
    push @cronstr,    $end_str;
    
    my $status = 0;  # 0 - init, 1 - found start, 2 - found end, updated.
    my $error  = "";
    my @newcrontab =();
    while (my $line = shift @oldcron){
        if ($line =~ $begin_re) {
            if ($status != 0) {
                $error = "Corrupted crontab: found duplicate BEGIN marker";
                last;
            };
            $status = 1;
            next;
        };
        if ($line =~ $end_re) {
            if ($status == 0) {
                $error = "Corrupted crontab: BEGIN marker not found before END marker";
                last;
            };
            if ($status != 1) {
                $error = "Corrupted crontab: found duplicate END marker";
                last;
            };
            push @newcrontab , @cronstr;
            $status = 2;
            next;
        };
        next if $status == 1;      #Skip our lines
        if ($line =~ /\ runtask\ /) {
            my $txt = $line;
            $txt =~ s/\r?\n//;
            print STDERR "Found line \"$txt\" which looks like ours.\n";
        }
        push @newcrontab, $line;   #Save existing lines
    };
    
    if ($error) {
        print $error."\n";
        return 1;
    }
    else { #No errors, update file
        push  @newcrontab, ("\n\n",@cronstr) unless $status == 2;
        eval{
            open(HANDLER ,"|$crontab $crontabParams -") || die "can't fork: $!";
            print HANDLER @newcrontab;
            close HANDLER;
        };
        if($@ || $?){
            die $@.$?;
        };
    };
};

1;
