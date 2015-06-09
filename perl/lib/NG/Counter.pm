package NG::Counter;

use strict;
use DBI;
use vars qw(@ISA);

sub AdminMode {
    use NG::Module;
    @ISA = qw(NG::Module);
};
        
sub FaceMode {
    use NG::Face;
    @ISA = qw(NG::Face);
};


sub get_dbh_cached {
    my $self=shift;
    my $db = $self->db();
    my $dbhc = DBI->connect_cached($db->datasource(),$db->username(),$db->password());	
    return $dbhc;
}

sub countPage {
    my $self=shift;
    my $q=$self->q();
    my $dbh = $self->get_dbh_cached();
    
    my $COMMITPERIOD  = 60;  # Секунды, Как часто делать коммит при большом потоке
    my $MINREQPERIOD  = 10;  # Секунды, если запросы реже чем один в период, значит поток "не большой"

    $dbh->{AutoCommit} = 0;

    my $sth = $dbh->prepare("insert into counter_raw (ip, referer, url, useragent, xforwarded,title)	VALUES (?, ?, ?, ?, ?,?)") or return $self->error($DBI::errstr);

    my $title = $self->getPageParams()->{full_name};
    $sth->execute( $q->remote_addr(), $q->referer(), $q->url(-full=>1,-query=>1), $q->user_agent(), $ENV{'HTTP_X_FORWARDED_FOR'},$title ) or return $self->error($DBI::errstr);

    my $time = time();
    $NG::Counter::last_commit ||= $time;
    my $lastQ = $NG::Counter::last_query;
    $lastQ ||= $time - $MINREQPERIOD - 1;
    my $last_commit = $NG::Counter::last_commit;

    if ($NG::Bootstrap::is_cgi || ($time - $lastQ > $MINREQPERIOD)){
        $dbh->commit();
    }
    elsif ($NG::Bootstrap::is_modperl) {
        if ($time - $last_commit > $COMMITPERIOD){
            $dbh->commit();
            $NG::Face::last_commit = $time;
        }
    }
    $NG::Counter::last_query = $time;
    return 1;  
};

1;
END{};
 
