package NG::Profiler;
use strict;

my @timeStamps;
our @IPList = ();
our $TimeLimit = 0;
our $sub = undef;
our $singleLine = 0;
our $fmtt = "%.4f";  #Format for time
our $fmtp = "%.1f";  #Format for percents
our $useGroups = 1;
our $tabSymbol = "\t";

sub noopSaveTimestamp {}; #Do nothing
*saveTimestamp = \&noopSaveTimestamp;

sub realSaveTimestamp {
    my $name = shift;
    my $group = shift || "d"; #default
    
    $group = "" unless $useGroups;
    $group = "" if $singleLine;

    my $t = gettimeofday();
    push @timeStamps,{
        name => $name,
        time => $t,
        group => $group,
    };
};

sub resetSaving {
    no warnings 'redefine';
    *saveTimestamp = \&noopSaveTimestamp;
    @timeStamps = ();
}

sub startSaving {
    unless (UNIVERSAL::can('NG::Profiler','gettimeofday')) {
        eval "use Time::HiRes qw(gettimeofday);";
    };
    no warnings 'redefine';
    *saveTimestamp = \&realSaveTimestamp;
    @timeStamps = ();
};


sub outputTimestamps {
    my $s = "";
    my $target = shift;

    my $firstTS = shift @timeStamps or return;
    my $all = $timeStamps[-1]->{time} - $firstTS->{time};
    return unless $all > $TimeLimit;
    
    my @groupsStack = ();
    my $size = 0;

    push @groupsStack, {
        group => $firstTS->{group},
        time  => $firstTS->{time},
        ptime => $firstTS->{time},
    };

    foreach my $TS (@timeStamps) {
        my $t = $size;
        while ($t>=0) {
            last if ($TS->{group} eq $groupsStack[$t]->{group});
            $t--;
        };

        if ($t>=0) {
            #Show totals for group
            while ($size>=0) {
                last if ($TS->{group} eq $groupsStack[-1]->{group});

                $size--;
                my $TTS = pop @groupsStack;

                last if ($TTS->{cnt} < 2); #Dont show totals for single row
                $s .= "$tabSymbol"x($size+1) unless $singleLine;
                my $l = $TTS->{time} - $TTS->{ptime};
                $s .= "TOTAL $TTS->{group}: +".sprintf($fmtt, $l)."(".sprintf($fmtp,($l*100/$all))."%)";
                $s .= $singleLine?" ":"\n";
            };
        };

        my $l = $TS->{time} - $groupsStack[-1]->{time};
        unless ($singleLine) {
            $s .= "$tabSymbol"x$size;
            $s .= "$tabSymbol" if ($t<0);
        }

        $s .= $TS->{group}.":" if $TS->{group};
        $s .= "$TS->{name}: +".sprintf($fmtt, $l)."(".sprintf($fmtp,($l*100/$all))."%)";
        $s .= $singleLine?" ":"\n";

        if ($t<0) {
            #Not found in stack, adding
            push @groupsStack, {group=>$TS->{group}, ptime=>$groupsStack[-1]->{time},cnt=>0};
            $size++;
        }
        $groupsStack[-1]->{time} = $TS->{time}; #update time
        $groupsStack[-1]->{cnt}++;
    };

    #This is ok code, for results checking.
    while ($size>=1) {
        $size--;
        my $TTS = pop @groupsStack;

        $s .= "$tabSymbol"x($size+1) unless $singleLine;

        my $l = $TTS->{time} - $TTS->{ptime};
        $s .= "TOTAL $TTS->{group}: +".sprintf($fmtt, $l)."(".sprintf($fmtp,($l*100/$all))."%)";
        $s .= "\n" unless $singleLine;
    };

    $s = "Start: 0.0" . ($singleLine?" ":"\n") . $s. "TOTAL: ".sprintf($fmtt,$all)."\n" if $s;
    $s = $sub->() . ($singleLine?" ":"\n") . $s if defined $sub;

    if (defined $target && $target eq 'warn') {
        warn $s;
    }
    elsif (defined $target) {
        use Fcntl qw( :DEFAULT );
        my $Store_Flags = O_WRONLY | O_CREAT | O_BINARY;

        my $write_fh;
        unless ( sysopen( $write_fh, $target, $Store_Flags ) ) {
            print STDERR "Unable to open $target while saving Profiler data : $!\n";
            return;
        };
        seek($write_fh,0,2);
        my $size_left = length($s);
        my $offset    = 0;
        do {
            my $write_cnt = syswrite( $write_fh, $s, $size_left, $offset );
            unless ( defined $write_cnt ) {
                print STDERR "Unable to write Profiler data to $target : $!\n";
                return;
            };
            $size_left -= $write_cnt;
            $offset += $write_cnt;
        } while ( $size_left > 0 );
        close ($write_fh);
    }
    else {
        print STDERR $s."\n";
    };
};

1;

=head
Usage:

#!/usr/bin/perl
use strict;
use lib('/web/kinomax/sites/ng5/perl/lib','/web/kinomax/sites/kinomax.tomsk.ru/perl/lib');
use NG::Bootstrap;
use NG::Profiler;

#NG::Profiler::resetSaving();
#if ($ENV{REMOTE_ADDR} eq "95.170.101.80") {
#  NG::Profiler::startSaving();
#};

#$NG::Profiler::TimeLimit = 0.1; #1 second
#$NG::Profiler::sub = sub {
#  $NG::Application::cms->q->url(-absolute=>1);
#};
#$NG::Profiler::singleLine=0;
#NG::Profiler::saveTimestamp("start");



NG::Bootstrap::importX(undef, App => 'Kinomax::Face',DB=>'Kinomax::DB',  SiteRoot=>'/web/kinomax/sites/kinomax.tomsk.ru');

#NG::Profiler::saveTimestamp("end");
#NG::Profiler::outputTimestamps();

=cut
