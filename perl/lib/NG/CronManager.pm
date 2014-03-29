package NG::CronManager;
use strict;

use NG::Application;
our @ISA = qw/NG::Application/;

sub run {
    my $cms = shift;
    
    my $dbh = $cms->dbh();
    $cms->openConfig() || return $cms->showError();
    
    my $iterator = $cms->getModulesIterator();
    while (my $mObj = &$iterator()) {
print $mObj->getModuleCode()."\n";
        my $interface = $mObj->getInterface('CRON') or next;
    };
};

1;
