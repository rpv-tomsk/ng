package NG::Forum::Date;
use strict;
use Time::Local;
use base qw(Exporter);
our @EXPORT = qw(utc_current_date utc_current_datetime tz utc_to_tz);

sub utc_current_date {
    my @gmtime = gmtime();
    return sprintf("%02d.%02d.%02d", $gmtime[3], $gmtime[4]+1, $gmtime[5]+1900); 
};

sub utc_current_datetime {
    my @gmtime = gmtime();
    
    return sprintf("%02d.%02d.%02d %02d\:%02d\:%02d", $gmtime[3], $gmtime[4]+1, $gmtime[5]+1900, $gmtime[2], $gmtime[1], $gmtime[0]);
};

sub tz {
    my $tz = shift; #format [+-]hhmm[dst]
    my $tz_obj = undef;               
    
    if (my ($sign, $hour, $minute, $dst) = $tz =~ /([+-]?)(\d{2})(\d{2})((?:dst)?)/) {
        return {
            hour=>$hour,
            minute=>$minute,
            positive=>($sign eq '-' ? 0: 1),
            dst=>($dst ? 1: 0),
        };
    };
    
    return $tz_obj; 
};

sub utc_to_tz {
    my $datetime = shift || "";
    my $tz = shift || "";
    
    my $tz_obj = tz($tz) or return undef;
    
    if (my ($mday, $mon, $year, $hour, $min, $sec) = $datetime =~ /(\d+)\.(\d+)\.(\d+)\s+(\d+)\:(\d+)\:(\d+)/) {
        my $time = timegm($sec, $min, $hour, $mday, $mon-1, $year);
        my $tz_time = $tz_obj->{hour}*3600 + $tz_obj->{minute}*60;
        if ($tz_obj->{positive}) {
            $time = $time + $tz_time;
        }
        else {
            $time = $time - $tz_time;
        };
        
        my @gmtime = gmtime($time);
        
        return sprintf("%02d.%02d.%04d %02d:%02d:%02d", $gmtime[3], $gmtime[4]+1, $gmtime[5]+1900, $gmtime[2], $gmtime[1], $gmtime[0]);
    };
    return undef;
};

1;