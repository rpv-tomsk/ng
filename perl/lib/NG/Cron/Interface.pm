package NG::Cron::Interface;
use strict;

use NG::Interface;
our @ISA = qw/NG::Interface/;

$Carp::Internal{'NG::Cron::Interface'}++;

sub validate_configCRON {
    my ($iface,$tasklist) = (shift,shift);
    #NG::Exception->throw('NG.INTERNALERROR', $contextDescription."Class ".ref($interface)." has invalid configCRON() configuration.") unless $tasklist && ref $tasklist eq "ARRAY";
    NG::Exception->throw('NG.INTERNALERROR', "Invalid configCRON() configuration in ".$iface->_package()) unless $tasklist && ref $tasklist eq "ARRAY";
    
    $iface->_validate($tasklist,'');
    $tasklist;
}

sub _validate {
    my ($iface,$tasklist,$contextDescription) = (shift,shift);
    
    my $tasks = {};
    foreach my $config (@$tasklist){
        NG::Exception->throw('NG.INTERNALERROR', "TASK: Missing TASK at configCRON() of ".$iface->_package())     unless $config->{TASK};
        NG::Exception->throw('NG.INTERNALERROR', "TASK: Invalid value: / is prohibited at configCRON() of ".$iface->_package()) if $config->{TASK} =~ /\//;
        NG::Exception->throw('NG.INTERNALERROR', "TASK: Missing METHOD at configCRON() of ".$iface->_package())   unless $config->{METHOD};
        NG::Exception->throw('NG.INTERNALERROR', "TASK: Missing FREQ_STR at configCRON() of ".$iface->_package()) unless $config->{FREQ_STR};
        
        if (ref $config->{FREQ_STR} eq "ARRAY") {
            foreach my $time (@{$config->{FREQ_STR}}){
                NG::Exception->throw('NG.INTERNALERROR', "TASK: Invalid FREQ_STR at configCRON() of ".$iface->_package().": '".$time."'") unless NG::Cron::Service::is_valid_cronfreq($time);
            };
        }
        else {
            NG::Exception->throw('NG.INTERNALERROR', "TASK: Invalid FREQ_STR at configCRON() of ".$iface->_package().": '".$config->{FREQ_STR}."'") unless NG::Cron::Service::is_valid_cronfreq($config->{FREQ_STR});
        };
        
        my $task = $config->{TASK};
        NG::Exception->throw('NG.INTERNALERROR',"Task '$task' specified twice at ".$iface->_package()) if exists $tasks->{$task};
        $tasks->{$task} = 1;
    };
    $tasklist;
};

sub getTaskConfig {
    my ($iface,$task) = (shift,shift);
    
    my $tasklist = $iface->safe('configCRON');
    my ($config) = grep {$_->{TASK} eq $task} @$tasklist;
    NG::Exception->throw('NG.INTERNALERROR', "Task '$task' not found in ".$iface->_package()) unless $config;
    $config;
};

1;
