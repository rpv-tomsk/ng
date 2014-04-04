package NG::Cron::Service;
use strict;

sub _generateCrontab {
    my $self = shift;
    my $iterator = $self->cms->getModulesIterator();
    my $cron = $self->getSiteRoot."/cron/".$0;
    my @items = ();
    while (my $module = &$iterator()){
        my $interface = $module->getInterface("CRONTAB");
        my $modleTasks = $interface->configCRON();
        next unless $modleTasks;
        push @items, @$modleTasks;
    }
    my @cron_str;
    foreach my $item(@items){
        if(ref $item->{FREQ_STR} eq "ARRAY"){
            push @cron_str, ("#".$item->{DESCRIPTION}."\n") if $item->{DESCRIPTION};
            foreach my $time (@{$item->{FREQ_STR}}){
                if (is_valid_cronfreq($time)){
                    push @cron_str, $time." ".$cron." ".$item->{TASKNAME}."\n";
                }
                
            }
        }else{
        push @cron_str, ("#".$item->{DESCRIPTION}."\n") if $item->{DESCRIPTION};
        push @cron_str, $item->{FREQ_STR}." ".$cron." ".$item->{TASKNAME}."\n" if is_valid_cronfreq($item->{FREQ_STR});
        }
    }
    return wantarray ? @cron_str :\@cron_str;
}

sub is_valid_cronfreq {
    my $self = shift if ref($_[0]) eq __PACKAGE__; #бедет работать в слечае &is_valid_cronfreq($str) и $self->is_valid_cronfreq($str);
    my $string = shift || die "is_valid_cronfreq(): no input data";
    my ($min,$hour,$day,$mon, $wday,@rest) = split(/\s+/,$string);
    return 0 if scalar @rest;
     $min =~ m#^((?:(?:\*)|(?:(?:[0-9]{1})|(?:[1-5][0-9])|(?:(?:(?:[0-9]{1})|(?:[1-5][0-9]))-(?:(?:[0-9]{1})|(?:[1-5][0-9])))|(?:(?:[0-9]{1}|(?:[1-5][0-9]))(?:,(?:[0-9]{1}|(?:[1-5][0-9])))*)))(?:/(?:(?:[0-9]{1})|(?:[1-5][0-9])))?)$#;
    return 0 unless $1;
     $hour =~ m#^((?:(?:\*)|(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3])|(?:(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3]))-(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3])))|(?:(?:[0-9]{1}|(?:[1][0-9])|(?:[2][0-3]))(?:,(?:[0-9]{1}|(?:[1][0-9])|(?:[2][0-3])))*)))(?:/(?:(?:[0-9]{1})|(?:[1][0-9])|(?:[2][0-3])))?)$#;
    return 0 unless $1;

    $day =~ m#^((?:(?:\*)|(?:\?)|(?:(?:(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1]))(?:[W,w]?|[L,l]?)?)|(?:(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1]))-(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1]))))|(?:(?:[1-9]|(?:[1-2][0-9])|(?:[3][0-1]))(?:,(?:[1-9]|(?:[1-2][0-9])|(?:[3][0-1])))*))(?:/(?:(?:[1-9])|(?:[1-2][0-9])|(?:[3][0-1])))?)$#;
    return 0 unless $1;

    $mon =~ m#^((?:(?:\*)|(?:(?:[1-9])|(?:[1][0-2])|(?:(?:(?:[1-9])|(?:[1][0-2]))-(?:(?:[1-9])|(?:[1][0-2])))|(?:(?:[1-9]|(?:[1][0-2]))(?:,(?:[1-9]|(?:[1][0-2])))*)|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|okt|nov|dec)|(?:(?:jan|feb|mar|apr|may|jun|jul|aug|sep|okt|nov|dec)(?:,(?:jan|feb|mar|apr|may|jun|jul|aug|sep|okt|nov|dec))*)))(?:/(?:(?:[1-9])|(?:[1][0-2])))?)$#;
    $wday =~ m#^((?:(?:(?:\*)|(?:\?)|(?:(?:(?:[0-6])[w]?)|(?:(?:[0-6])-(?:[0-6])))|(?:[0-6](?:,[0-6])*)|(?:sun|mon|tue|wed|thu|fri|sat)|(?:(?:sun|mon|tue|wed|thu|fri|sat)(?:,(?:sun|mon|tue|wed|thu|fri|sat))*)|(?:(?:(?:sun|mon|tue|wed|thu|fri|sat))-(?:(?:sun|mon|tue|wed|thu|fri|sat)))|[1-5]\#))?)$#;
    return 0 unless $1;

    return 1;
};

