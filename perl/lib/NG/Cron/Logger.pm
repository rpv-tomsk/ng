package NG::Cron::Logger;
use strict;
use NG::Exception;
sub new{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->{_task} = shift || NG::Exception->throw('NG.INTERNALERROR', 'No TASK passed to new() while creating NG::Cron::Logger');
    return $self;
};

sub logMessage($$){
    my $self = shift;
    my $message = shift || NG::Exception->throw('NG.INTERNALERROR', 'logMessage(): No message passed');
    my $ret = $self->dbh->do("insert into ng_cron_logs (module,task,message) VALUES (?,?,?)", undef, $self->{_task}->{_modulecode},$self->{_task}->{_config}->{TASK},$message);
    NG::Exception->throw('NG.INTERNALERROR', 'logMessage(): error saving record') unless $ret == 1;
}

sub setStatus(){
    my $self = shift;
    my $message = shift || return;
    $self->{_task}->updateStatusRecord({status_text=>$message});
};

=head
CREATE TABLE ng_cron_logs (
  id SERIAL, 
  module VARCHAR(25) NOT NULL,
  task VARCHAR(50) NOT NULL,
  message VARCHAR(50) NOT NULL,
  ctime TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL,
  PRIMARY KEY(id)
);

CREATE INDEX ng_cron_logs_idx ON ng_cron_logs USING btree (module,task,ctime);
=cut

1;
