package NG::Cron::Service;
use strict;
use Cwd 'abs_path';

sub _generateCrontab {
    my $cms = shift;
    my $cmd = shift;
    
    my $iterator = $cms->getModulesIterator();
    my $cron = abs_path($0);
    my @items = ();
    while (my $module = &$iterator()){
        next unless $module->can('getInterface');
        my $interface = $module->getInterface('NG::Cron::Interface');
        next unless $interface;
        my $moduleTasks = $interface->safe('configCRON');
        
        map {$_->{MODULE}=$module->{_moduleRow}->{code}} @$moduleTasks;
        push @items, @$moduleTasks;
    };
    my @cron_str;
    foreach my $item(@items){
        if(ref $item->{FREQ_STR} eq "ARRAY"){
            push @cron_str, "## ".($item->{DESCRIPTION}||($item->{MODULE}."/".$item->{TASK}))."\n";
            
            foreach my $time (@{$item->{FREQ_STR}}){
                push @cron_str, $time." ".$cron." $cmd ".$item->{MODULE}."/".$item->{TASK}."\n";
            };
        }
        else{
            push @cron_str, ("## ".$item->{DESCRIPTION}."\n") if $item->{DESCRIPTION};
            push @cron_str, $item->{FREQ_STR}." ".$cron." $cmd ".$item->{MODULE}."/".$item->{TASK}."\n";
        };
    };
    return wantarray ? @cron_str :\@cron_str;
}

sub is_valid_cronfreq {
    my $string = shift || die "is_valid_cronfreq(): no input data";
    my ($min,$hour,$day,$mon, $wday,@rest) = split(/\s+/,$string);
    return 0 if scalar @rest;
    $min =~ m#^((?:(?:\*)|(?:(?:[0-9]{1})|(?:[1-5][0-9])|(?:(?:(?:[0-9]{1})|(?:[1-5][0-9]))-(?:(?:[0-9]{1})|(?:[1-5][0-9])))|(?:(?:[0-9]{1}|(?:[1-5][0-9]))(?:,(?:[0-9]{1}|(?:[1-5][0-9])))*)))(?:/(?:(?:[0-9]{1})|(?:[1-5][0-9])))?)$#;
    return 0 unless defined $1;
    $hour =~ m#^((?:(?:\*)|(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3])|(?:(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3]))-(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3])))|(?:(?:[0-9]{1}|(?:[1][0-9])|(?:[2][0-3]))(?:,(?:[0-9]{1}|(?:[1][0-9])|(?:[2][0-3])))*)))(?:/(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3])))?)$#;
    return 0 unless defined $1;

    $day =~ m#^((?:(?:\*)|(?:\?)|(?:(?:(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1]))(?:[W,w]?|[L,l]?)?)|(?:(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1]))-(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1]))))|(?:(?:[1-9]|(?:[1-2][0-9])|(?:[3][0-1]))(?:,(?:[1-9]|(?:[1-2][0-9])|(?:[3][0-1])))*))(?:/(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1])))?)$#;
    return 0 unless defined $1;

    $mon =~ m#^((?:(?:\*)|(?:(?:[1-9])|(?:[1][0-2])|(?:(?:(?:[1-9])|(?:[1][0-2]))-(?:(?:[1-9])|(?:[1][0-2])))|(?:(?:[1-9]|(?:[1][0-2]))(?:,(?:[1-9]|(?:[1][0-2])))*)|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|okt|nov|dec)|(?:(?:jan|feb|mar|apr|may|jun|jul|aug|sep|okt|nov|dec)(?:,(?:jan|feb|mar|apr|may|jun|jul|aug|sep|okt|nov|dec))*)))(?:/(?:(?:[1-9])|(?:[1][0-2])))?)$#;
    $wday =~ m#^((?:(?:(?:\*)|(?:\?)|(?:(?:(?:[0-6])[w]?)|(?:(?:[0-6])-(?:[0-6])))|(?:[0-6](?:,[0-6])*)|(?:sun|mon|tue|wed|thu|fri|sat)|(?:(?:sun|mon|tue|wed|thu|fri|sat)(?:,(?:sun|mon|tue|wed|thu|fri|sat))*)|(?:(?:(?:sun|mon|tue|wed|thu|fri|sat))-(?:(?:sun|mon|tue|wed|thu|fri|sat)))|[1-5]\#))?)$#;
    return 0 unless defined $1;

    return 1;
};

1;
