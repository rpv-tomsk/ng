package NG::Cron::Task;
use strict;

sub new {
    my $class = shift;

    my $self = {};
    bless $self,$class;
    #$self->{_interface}
    #$self->{_config}
    #$self->{_modulecode}
    #$self->{_lockfile}
    #$self->{_lockfd}
    #$self->{_locked}
    $self->_load(@_);
    return $self;
};

sub _load {
    my ($self,$params) = (shift,shift);
    
    NG::Exception->throw('NG_INTERNALERROR', "Incorrect usage. No MODULE or TASK specified.")  unless $params->{MODULE} && $params->{TASK};
    
    my $cms = $self->cms();
    my $mObj = $cms->getModuleByCode($params->{MODULE});
    NG::Exception->throw('NG.INTERNALERROR', $cms->getError()) unless $mObj;
    
    $self->{_interface} = $mObj->getInterface('CRON');
    NG::Exception->throw('NG.INTERNALERROR', "Task $moduleCode/$task: Module $moduleCode has no CRON interface.") unless $interface;
    NG::Exception->throw('NG.INTERNALERROR', "Task $moduleCode/$task: Module $moduleCode interface CRON has no configCRON() method.") unless $interface->can('configCRON');
    
    my $tasklist = $interface->configCRON();
    NG::Exception->throw('NG.INTERNALERROR', "Task $moduleCode/$task: Module $moduleCode has invalid configCRON() configuration.") unless $tasklist && ref $tasklist eq "ARRAY";
    my ($config) = grep{$_->{TASK} eq $params->{TASK}}@$tasklist;
    
    NG::Exception->throw('NG.INTERNALERROR', "Task $moduleCode/$task not found in module $moduleCode.") unless $taskConfig;
    $self->_validateTaskConfig($config);
    $self->{_config} = $config;
    $self->{_modulecode} = $moduleCode;
    #TODO: Путь брать из конфига
    $self->{_lockfile}   = $cms->getSiteRoot()."/cron/lock/".$moduleCode."_".$config->{TASK}.".pid";
    $self;
};

sub run {
    my ($self,$params) = shift;
    
    NG::Exception->throw('NG.INTERNALERROR', "Invalid run type at task run()") unless $params && (($params->{startup} eq 'auto') || ($params->{startup} eq 'manual'));
    
    $self->_getStatusRecord();
    
    return 0 if ($params->{startup} eq 'auto') && ($self->{_statusRecord}->{startup} ne 'auto');
    NG::Exception->throw('NG.INTERNALERROR','Task is disabled') if ($self->{_statusRecord}->{startup} eq 'disabled');
    
    $self->_lock(); #Get exclusive lock 
    #TODO: unlock on DESTROY. Или не надо?
    
    NG::Exception->throw('NG.INTERNALERROR','Task is locked') unless $self->{_locked} || $params->{startup} eq 'auto';
    return 0 unless $self->{_locked};
    
    if ($params->{dofork}) {
        my $pid = fork();
        NG::Exception->throw('NG.INTERNALERROR',"Couldn't fork: $!") unless defined $pid;
        if ($pid == 0){
            #child process
            $self->_savepid();
            $self->_run();
            $self->_unlock();
            exit;
        }
        else {
            #parent process
            $self->_closelock(); #No unlock!
        };
    }
    else {
        $self->_savepid();
        $self->_run();
        $self->_unlock();
    };
};

=head
#sub stop {
#    my $self= shift;
#    my $task = shift;
#    my $pidfile = $self->_getPidFile($task);
#    return 1 if (!-e $pidfile);
#    my $oldpid = $self->_getPid($pidfile);
#    my $oldProcessExists = kill(0, $oldpid);
#    return 1 unless $oldProcessExists;
#    kill(0, $oldpid);
#    unlink $pidfile;
#    $self->dbh->do("update ng_cronstatus SET is_active = 0, status_text='Прервана пользоваетелем' where module_code=? and task_name=?", undef, $task->{MODULE_CODE},$task->{NAME});
#    return 1;
#}
=cut

sub _run {
    my $self = shift;
    $self->updateStatus({status=>'run',update_last_run_time=>1});
    
    my $method = $self->{_config}->{METHOD};
    $self->{_interface}->$method(NG::Cron::Logger->new($self));
    
    $self->updateStatus({status=>'stop'});
};

sub _lock {
    my $self = shift;
    
    unless ( sysopen( $self->{_lockfd}, $self->{_lockfile}, O_WRONLY | O_CREAT | O_TRUNC | O_BINARY ) ) {
        NG::Exception->throw('NG.INTERNALERROR',"Unable to open/create lock file ".$self->{_lockfile}." : $!");
    };
    $self->{_locked} = flock($write_fh, LOCK_EX|LOCK_NB);
    
    #my $task = shift;
    #my $pid =  $$;
    #my $fh;
    #my $pidfile  = $self->_getPidFile($task);
    #if (-e $pidfile){
    #    my $oldpid = $self->_getPid($pidfile);
    #    my $oldProcessExists = kill(0, $oldpid);
    #    unlink $pidfile unless $oldProcessExists;
    #    print "This task is already running earlier.\n"if $oldProcessExists;
    #    exit(1) if $oldProcessExists;  #что делать если процесс существует? выходим или нужно проверить умер ли 
    #}
    #open($fh, '>', $pidfile) || die $!."$pidfile";
    #print $fh $pid;
    #close $fh;
};

sub _unlock {
    my $self = shift;
    NG::Exception->throw('NG.INTERNALERROR',"Lockfile not opened ") unless $self->{_lockfd};
    #We are not using lock after _unlock, so just close it. Also note that not _closelock() is called after _unlock() calls.
    close $self->{_lockfd};
    undef $self->{_lockfd};
};

sub _closelock {
    my $self = shift;
    NG::Exception->throw('NG.INTERNALERROR',"Lockfile not opened ") unless $self->{_lockfd};
    close $self->{_lockfd};
    undef $self->{_lockfd};
};

sub _savepid {
    my $self = shift;
    NG::Exception->throw('NG.INTERNALERROR',"Lockfile not opened ") unless $self->{_lockfd};
    my $ret = syswrite($self->{_lockfd}, $$);
    NG::Exception->throw('NG.INTERNALERROR',"Unable to write lock file ".$self->{_lockfile}." : $!"); unless defined $ret;
};


#sub _getPid{
#    my $self = shift;
#    my $file = shift || return undef;
#    open (FH, "<", $file) || return undef;
#    my $pid = readline(FH);
#    close(FH);
#    return $pid;
#}

sub _validateTaskConfig {
    my $self = shift;
    my $config = shift;
    
    die "No TASK" unless $config->{TASK};
    die "TASK: Invalid value. \/ is prohibited." if $config->{TASK} =~ /\//;
    die "No METHOD" unless $config->{METHOD};
    NG::Exception->throw('NG.INTERNALERROR', "Class ".(ref $self->{_interface})." has no method " . $config->{METHOD} )unless $self->{_interface}->can($config->{METHOD});
};

sub _getStatusRecord {
    my ($self, $moduleCode, $task) = (shift, shift,shift);
    $self->{_statusRecord} = $self->dbh->selectrow_hashref('select id, module, task, status, startup from ng_cron_status where module=? and task=?', undef, $self->{_modulecode}, $self->{_config}->{TASK});
    unless ($self->{_statusRecord}){
        NG::Exception->throw('NG.INTERNALERROR', 'Error loading cron status record: '.$DBI::errstr) if $DBI::errstr;
        my $row = $self->{_statusRecord} = {};
        $row->{id}     = $self->db->get_id('ng_cron_status');
        $row->{module} = $self->{_modulecode};
        $row->{task}   = $self->{_config}->{TASK};
        $row->{status} = 'stop';  # run / stop
        $row->{startup}= 'auto';  # auto / manual / disabled
        my $ret = $dbh->do("INSERT INTO ng_cron_status (id, module, task, status, startup ) VALUES (?,?,?,?,?)",undef,
                      $row->{id}, $row->{module}, $row->{task}, $row->{status}, $row->{startup});
        unless (defined $ret && $ret == 1) {
            NG::Exception->throw('NG.INTERNALERROR', 'Error inserting cron status record: '.$DBI::errstr);
        };
    };
};

sub updateStatus {
    my ($self, $newStatus) = (shift,shift);
    
    my $ph = "";
    my @values = ();
    if (delete $newStatus->{update_last_run_time}) {
        $ph .= "time=?";
        push @values, "now ;-)";
    };
    
    foreach my $key (keys %$newStatus) {
        $ph .= ",$key = ?";
        push @values, $newStatus->{$key};
        $self->{_statusRecord}->{$key} = $newStatus->{$key};
    };
    
    my $where = "module=? and task=?";
    push @values, $self->{_modulecode};
    push @values, $self->{_config}->{TASK};
    $ph =~ s/^,//;
    
    my $ret = $dbh->do("UPDATE ng_cron_status SET $ph WHERE $where",undef, @values);
    unless (defined $ret && $ret == 1) {
        NG::Exception->throw('NG.INTERNALERROR', 'Error updating cron status record: '.$DBI::errstr);
    };
};


1;
