package NG::Cron::Task;
use strict;

use NGService;
use NG::Cron::Logger;
use NG::Cron::Service;
use Fcntl qw(:flock :DEFAULT);

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
    
    NG::Exception->throw('NG.INTERNALERROR', "Incorrect usage. No MODULE or TASK specified.")  unless $params->{MODULE} && $params->{TASK};
    
    my $cms = $self->cms();
    my $mObj = $cms->getModuleByCode($params->{MODULE});
    NG::Exception->throw('NG.INTERNALERROR', $cms->getError()) unless $mObj;
    
    NG::Exception->throw('NG.INTERNALERROR', "Task $params->{MODULE}/$params->{TASK}: Class ".ref($mObj)." has no getInterface() method.") unless $mObj->can('getInterface');
    $self->{_interface} = $mObj->getInterface('CRON');
    NG::Exception->throw('NG.INTERNALERROR', "Task $params->{MODULE}/$params->{TASK}: Class ".ref($mObj)." has no CRON interface.") unless $self->{_interface};
    
    my $tasklist = NG::Cron::Service::getTasklist($self->{_interface},"Task $params->{MODULE}/$params->{TASK}");
    
    my ($config) = grep{$_->{TASK} eq $params->{TASK}}@$tasklist;
    NG::Exception->throw('NG.INTERNALERROR', "Task $params->{MODULE}/$params->{TASK} not found in module $params->{MODULE}.") unless $config;
    
    $self->{_config} = $config;
    $self->{_modulecode} = $params->{MODULE};
    #TODO: Путь брать из конфига
    my $lockDir = $cms->getSiteRoot()."/.cron-lock/";
    NG::Exception->throw('NG.INTERNALERROR', 'Lock directory '.$lockDir.' does not exists') unless -d $lockDir;
    
    $self->{_lockfile}   = $lockDir.$params->{MODULE}."_".$config->{TASK}.".pid";
    $self;
};

sub run {
    my ($self,$params) = (shift, shift);
    NG::Exception->throw('NG.INTERNALERROR', "Invalid run type at task run()") unless $params && (($params->{startup} eq 'auto') || ($params->{startup} eq 'manual')); 
    
    $self->_getStatusRecord();
    
    return 0 if ($params->{startup} eq 'auto') && ($self->{_statusRecord}->{startup} ne 'auto');
    NG::Exception->throw('NG.INTERNALERROR','Task is disabled') if ($self->{_statusRecord}->{startup} eq 'disabled');
    
    $self->_lock(); #Get exclusive lock 
    
    NG::Exception->throw('NG.INTERNALERROR','Task is locked') unless $self->{_locked} || $params->{startup} eq 'auto';
    return 0 unless $self->{_locked};
    
    if ($params->{dofork}) {
        my $pid = fork();
        #Чайлд унаследует блокировку
        NG::Exception->throw('NG.INTERNALERROR',"Couldn't fork: $!") unless defined $pid;
        if ($pid == 0){
            #child process
            $self->_savepid();
            $self->_run();
            $self->_clearpid();
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
        $self->_clearpid();
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
    $self->updateStatusRecord({status=>'run'});
    
    my $method = $self->{_config}->{METHOD};
    $self->{_interface}->$method(NG::Cron::Logger->new($self));
    $self->updateStatusRecord({status=>'stop'});
};

sub _lock {
    my $self = shift;
    
    unless ( sysopen( $self->{_lockfd}, $self->{_lockfile}, O_WRONLY | O_CREAT | O_TRUNC | O_BINARY ) ) {
        NG::Exception->throw('NG.INTERNALERROR',"Unable to open/create lock file ".$self->{_lockfile}." : $!");
    };
    $self->{_locked} = flock($self->{_lockfd}, LOCK_EX|LOCK_NB);
    
};

sub _unlock {
    my $self = shift;
    NG::Exception->throw('NG.INTERNALERROR',"Lockfile not opened ") unless $self->{_lockfd};
    #We are not using lock after _unlock, so just close it. Also note that no _closelock() is called after _unlock() calls.
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
    NG::Exception->throw('NG.INTERNALERROR',"Unable to write lock file ".$self->{_lockfile}." : $!") unless defined $ret;
};

sub _clearpid {
    my $self = shift;
    NG::Exception->throw('NG.INTERNALERROR',"Lockfile not opened ") unless $self->{_lockfd};
    my $ret = truncate($self->{_lockfd}, 0);
    NG::Exception->throw('NG.INTERNALERROR',"Unable to truncate lock file ".$self->{_lockfile}." : $!") unless defined $ret;
    $ret = seek($self->{_lockfd},0,0);
    NG::Exception->throw('NG.INTERNALERROR',"Unable to seek lock file ".$self->{_lockfile}." : $!") unless $ret;
    $ret = syswrite($self->{_lockfd}, '');
    NG::Exception->throw('NG.INTERNALERROR',"Unable to clear lock file ".$self->{_lockfile}." : $!") unless defined $ret;
};

#sub _getPid{
#    my $self = shift;
#    my $file = shift || return undef;
#    open (FH, "<", $file) || return undef;
#    my $pid = readline(FH);
#    close(FH);
#    return $pid;
#}

sub _getStatusRecord {
    my $self = shift;
    $self->{_statusRecord} = $self->dbh->selectrow_hashref('select id, module, task, status, startup from ng_cron_status where module=? and task=?', undef, $self->{_modulecode}, $self->{_config}->{TASK});
    unless ($self->{_statusRecord}){
        NG::Exception->throw('NG.INTERNALERROR', 'Error loading cron status record: '.$DBI::errstr) if $DBI::errstr;
        my $row = $self->{_statusRecord} = {};
        $row->{id}     = $self->db->get_id('ng_cron_status');
        $row->{module} = $self->{_modulecode};
        $row->{task}   = $self->{_config}->{TASK};
        $row->{status} = 'stop';  # run / stop
        $row->{startup}= 'auto';  # auto / manual / disabled
        my $ret = $self->dbh->do("INSERT INTO ng_cron_status (id, module, task, status, startup ) VALUES (?,?,?,?,?)",undef,
                      $row->{id}, $row->{module}, $row->{task}, $row->{status}, $row->{startup});
        unless (defined $ret && $ret == 1) {
            NG::Exception->throw('NG.INTERNALERROR', 'Error inserting cron status record: '.$DBI::errstr);
        };
    };
};

sub updateStatusRecord {
    my ($self, $newStatus) = (shift,shift);
    
    my $ph = "";
    my @values = ();
    
    foreach my $key (keys %$newStatus) {
        $ph .= ",$key = ?";
        push @values, $newStatus->{$key};
        $self->{_statusRecord}->{$key} = $newStatus->{$key};
    };
    NG::Exception->throw('NG.INTERNALERROR', 'updateStatusRecord(): No data to update') unless $ph;
    
    if (exists $newStatus->{status} && $newStatus->{status} eq 'run') {
        $ph .= ",time=?";
        push @values, $self->db->datetime_to_db(current_datetime());
    };
    
    my $where = "module=? and task=?";
    push @values, $self->{_modulecode};
    push @values, $self->{_config}->{TASK};
    $ph =~ s/^,//;
    
    my $ret = $self->dbh->do("UPDATE ng_cron_status SET $ph WHERE $where",undef, @values);
    unless (defined $ret && $ret == 1) {
        NG::Exception->throw('NG.INTERNALERROR', 'Error updating cron status record: '.$DBI::errstr);
    };
};
=head
CREATE TABLE ng_cron_status (
  id SERIAL, 
  module VARCHAR(25) NOT NULL, 
  task VARCHAR(50) NOT NULL, 
  status VARCHAR(50) NOT NULL, 
  startup VARCHAR(10), 
  "time" TIMESTAMP WITHOUT TIME ZONE, 
  status_text VARCHAR(25), 
  PRIMARY KEY(id)
) ;

COMMENT ON COLUMN ng_cron_status.module IS 'Код модуля';
COMMENT ON COLUMN ng_cron_status.task IS 'Название задания';
COMMENT ON COLUMN ng_cron_status.status IS 'Статус start/stop';
COMMENT ON COLUMN ng_cron_status.startup IS 'Тип запуска [auto|manual|disabled]';
COMMENT ON COLUMN ng_cron_status."time" IS 'Время последнего запуска задания';
COMMENT ON COLUMN ng_cron_status.status_text IS 'Текстовый статус';

CREATE UNIQUE INDEX ng_cron_status_idx ON ng_cron_status USING btree (module, task);

=cut

1;
