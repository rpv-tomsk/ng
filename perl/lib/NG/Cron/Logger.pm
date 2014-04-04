package NG::Cron::Logger;
use strict;

sub new{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->{_task} = shift || NG::Exception->throw('NG.INTERNALERROR', 'No TASK passed to new() while creating NG::Cron::Logger');
    return $self;
};

sub logMessage($$){
    my $self = shift;
    my $message = shift;
    #$message = join("\n", @$message) if (ref $message eq "ARRAY");
    #return unless $message;
    #$self->{_cms}->dbh->do("insert into ng_cron_logs (logtext,taskname) VALUES (?,?)", undef,$message, $self->{_task}->{TASKNAME});
}

sub setStatus(){
    my $self = shift;
    my $message = shift || return;
    $self->{_task}->updateStatus({status_text=>$message});
};

1;
