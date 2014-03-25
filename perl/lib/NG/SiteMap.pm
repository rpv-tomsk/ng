package NG::SiteMap;

#TODO:
# Моменты неясные:
# Почему то при удалении страницы передавался ее id хотя во всех других случаях передается PageObj (Сделал чтоб передавался PageObj)
# Поидее страница всегда создается неактивной и это событие можем необрабатывать ??? +++
# Надо сделать ескейпинг  русских символов в урл при записи в файл
# Также вопрос при удалении страничек еще же удаляются связаные странички поидее для них тоже надо генерировать событие
# У нас же не поддерживается многосайтовость на основе суб доменов, иначе надо завязываться на под сайты
# Также считаю нужным ввести такое понятие как основной домен сайта, он же будет участвовать в в генерации url в xml предлагаю указывать его в конфиге
# Надо будет закинуть все существующие страницы и записи в базу +++
# Дата обновления урл и файлов

use strict;
use vars qw(@ISA);

sub AdminMode {
    use NG::Module;
    @ISA = qw(NG::Module);
};

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    
    $self->{_max_file_size} = 10000000;     
    $self->{_max_url_count} = 50000;
    
    $self->{_excluded_templates} = [];
    $self->{_excluded_pages} = [];
    
    $self->{_event_hash} = {};
    $self->{_site_domen} = "";
};

sub _addEventListener {
    my $self = shift;
    my $module = shift;
    my $event = shift;
    my $url_mask = shift;
    $self->{_event_hash}->{$module}->{$event} = $url_mask;
};

sub _excluded_templates {
    my $self = shift;
    my $array = shift;
    my @array = @{$array};
    $self->{_excluded_templates} = \@array;
};

sub _excluded_pages {
    my $self = shift;
    my $array = shift;
    my @array = @{$array};
    $self->{_excluded_pages} = \@array;
};

sub config {
    my $self = shift;

    $self->_addEventListener("NG::SiteStruct","updatenode","{url}");
    $self->_addEventListener("NG::SiteStruct","deletenode","{url}");
    $self->_addEventListener("NG::SiteStruct","enablenode","{url}");
    $self->_addEventListener("NG::SiteStruct","disablenode","{url}");
    $self->{_site_domen} = "nikolas.ru";
};


sub processEvent {
    my $self = shift;
    my $event = shift;
    
    my $action = $self->_getUrlAction($event) or return 1;
    my $url = $self->_getUrl($event) or return 1;

    if ($action eq "save") {
        $self->_saveUrl($url) or die "SiteMap::processEvent error in call _saveUrl() ".$self->getError();
    };
    
    if ($action eq "delete") {
        $self->_deleteUrl($url) or die "SiteMap::processEvent error in call _deleteUrl() ".$self->getError();
    };
    return 1;
};

sub _createSitemapFile {
    my $self = shift;
    my $file_row = shift;
    my $dbh = $self->db()->dbh();
    my $filepath = $self->getDocRoot().$file_row->{filename};
    
    my $FH = undef;
    open ($FH,">".$filepath) or return $self->error("Can't open $filepath for write sitemap: ".$!);
    
    print $FH qq(<?xml version="1.0" encoding="UTF-8"?>\n);
    print $FH qq(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n);
    
    my $sth = $self->db()->dbh()->prepare("select * from ng_sitemap_urls where sitemap=?") or return $self->error($DBI::errstr);
    $sth->execute($file_row->{id}) or return $self->error($DBI::errstr);
    while (my $row = $sth->fetchrow_hashref()) {
        $row->{url} = _escape_url($row->{url});
        $row->{updatedate} = $self->db()->date_to_db($self->db()->date_from_db($row->{updatedate}));                                
        print $FH qq(<url>\n);
        print $FH qq(<loc>http://$self->{_site_domen}$row->{url}</loc>\n);
        print $FH qq(<lastmod>$row->{updatedate}</lastmod>\n);
        print $FH qq(</url>\n);
    };     
    $sth->finish();
    
    print $FH qq(</urlset>\n);
    close ($FH);
    $file_row->{file_size} = -s $filepath;
    $dbh->do("update ng_sitemap_files set url_count=?,file_size=? where id=?",undef,$file_row->{url_count},$file_row->{file_size},$file_row->{id}) or return $self->error($DBI::errstr);
    return 1;
};

sub _createSitemapIndexFile {
    my $self = shift;
    my $dbh = $self->db()->dbh();
    my $filepath = $self->getDocRoot()."sitemap_index.xml";
    
    my $FH = undef;
    open ($FH,">".$filepath) or return $self->error("Can't open $filepath for write sitemap index: ".$@);
    
    print $FH qq(<?xml version="1.0" encoding="UTF-8"?>\n);
    print $FH qq(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n);
    
    my $sth = $self->db()->dbh()->prepare("select * from ng_sitemap_files order by id desc") or return $self->error($DBI::errstr);
    $sth->execute() or return $self->error($DBI::errstr);
    while (my $row = $sth->fetchrow_hashref()) {
        print $FH qq(<sitemap>\n);
        print $FH qq(<loc>http://$self->{_site_domen}/$row->{filename}</loc>\n);
        print $FH qq(</sitemap>\n);
    };     
    $sth->finish();
    
    print $FH qq(</sitemapindex>\n);
    close ($FH);
    return 1;
};


sub _saveUrl {
    my $self = shift;
    my $url = shift;
    
    my $dbh = $self->db()->dbh();
    
    my $sth = $dbh->prepare("select * from ng_sitemap_urls where url=?") or return $self->error($DBI::errstr);
    $sth->execute($url) or return $self->error($DBI::errstr);
    my $url_row = $sth->fetchrow_hashref();
    $sth->finish();
    
    my $file_row = {};
    
    unless ($url) {
        $sth = $dbh->prepare("select * from ng_sitemap_files where id=?") or return $self->error($DBI::errstr);
        $sth->execute($url_row->{sitemap}) or return $self->error($DBI::errstr);
        $file_row = $sth->fetchrow_hashref();
        $sth->finish();
    }
    else {
        $sth = $dbh->prepare("select * from ng_sitemap_files order by id desc limit 1") or return $self->error($DBI::errstr);
        $sth->execute() or return $self->error($DBI::errstr);
        $file_row = $sth->fetchrow_hashref();
        $sth->finish();        
    };

    if (!$file_row || (!$url_row && ($file_row->{url_count}>=$self->{_max_url_count} || $file_row->{file_size}>=$self->{_max_file_size}))) {
        my $id = $self->db()->get_id("ng_sitemap_file_number");
        $file_row = {
            id => $id,
            filename => "sitemap".$id.".xml",
            url_count => 0,
            file_size => 0 
        };
        $dbh->do("insert into ng_sitemap_files (id,filename,url_count,file_size) values(?,?,?,?)",undef,$file_row->{id},$file_row->{filename},$file_row->{url_count},$file_row->{file_size}) or return $self->error($DBI::errstr);
    };

    if ($url_row) {
        $dbh->do("update ng_sitemap_urls set updatedate = now() where id=?",undef,$url_row->{id}) or return $self->error($DBI::errstr);
    }
    else {
        $url_row = {
            id => $self->db()->get_id("ng_sitemap_urls"),
            url => $url,
            sitemap => $file_row->{id}
        };
        $file_row->{url_count}++;
        $dbh->do("insert into ng_sitemap_urls(id,url,sitemap,updatedate) values(?,?,?,now())",undef,$url_row->{id},$url_row->{url},$url_row->{sitemap}) or return $self->error($DBI::errstr);
    };

    $self->_createSitemapFile($file_row) or return $self->showError();
    $self->_createSitemapIndexFile() or return $self->showError();
    return 1;
};

sub _deleteUrl {
    my $self = shift;
    my $url = shift;
    
    my $dbh = $self->db()->dbh();
    
    my $sth = $dbh->prepare("select * from ng_sitemap_urls where url=?") or return $self->error($DBI::errstr);
    $sth->execute($url) or return $self->error($DBI::errstr);
    my $url_row = $sth->fetchrow_hashref();
    $sth->finish();

    return 1 unless $url_row;
    
    $dbh->do("delete from ng_sitemap_urls where id=?",undef,$url_row->{id}) or return $self->error($DBI::errstr);
    
    $sth = $dbh->prepare("select * from ng_sitemap_files order by id desc limit 1") or return $self->error($DBI::errstr);
    $sth->execute() or return $self->error($DBI::errstr);
    my $file_row = $sth->fetchrow_hashref();
    $sth->finish();
    
    return 1 unless $file_row;
    
    $file_row->{url_count}--;    
    $self->_createSitemapFile($file_row) or return $self->showError();
    $self->_createSitemapIndexFile() or return $self->showError();
    return 1;     
};

sub _getUrlMasks {
    my $self = shift;
    my $modulename = shift;
    my $eventname = shift;
    
    return undef if (!exists $self->{_event_hash}->{$modulename});
    return undef if (!exists $self->{_event_hash}->{$modulename}->{$eventname} && !exists $self->{_event_hash}->{$modulename}->{""});

    return  $self->{_event_hash}->{$modulename}->{$eventname} || $self->{_event_hash}->{$modulename}->{""};
};

sub _getUrl {
    my $self = shift;
    my $event = shift;
    
    my $sender = $event->sender();
    my $modulename = ref $sender;
    my $data = $event->options();
    
    my $url = $self->_getUrlMasks($modulename,$event->name()) or return undef;
    
    if ($modulename eq "NG::SiteStruct") {
        return _processMask($url,$data->{PAGEOBJ}->getPageRow());
    }
    elsif ($sender->isa("NG::Module::List")) {
        return _processMask($url,{id=>$data->{ID}});
    };
    
    return $url;
};

sub _escape_url {
    my $url = shift;
    return "" unless $url;
    $url =~ s/\&/\&amp\;/g;
    $url =~ s/\'/\&apos\;/g; #'
    $url =~ s/\"/\&quot\;/g; #"
    $url =~ s/\</\&lt\;/g;
    $url =~ s/\>/\&gt\;/g;
    return $url;
};

sub _processMask {
    my $mask = shift;
    my $param = shift;
    $mask =~ s/\{([^\}]+)\}/$$param{$1}/gi;
    return $mask;
};

sub _getUrlAction {
    my $self = shift;
    my $event = shift;

    my $sender = $event->sender();
    my $modulename = ref $sender;
    my $eventname = $event->name();
    my $data = $event->options();

    if ($modulename eq "NG::SiteStruct") {
    
        my $po = $data->{PAGEOBJ};
        my $pr = $po->getPageRow();
        
        foreach (@{$self->{_excluded_pages}}) {
            return undef if ($_ == $pr->{id});
        };

        foreach (@{$self->{_excluded_templates}}) {
            return undef if ($_ == $pr->{template_id});
        };
    
        return "save" if ($eventname eq "enablenode"); 
        return "delete" if ($eventname eq "disablenode");
        
        
        return "save" if (($eventname eq "addnode" || $eventname eq "updatenode") && $po->isActive());
        return "delete" if ($eventname eq "deletenode" && $po->isActive());                              
    }
    elsif ($sender->isa("NG::Module::List")) {
        return "save" if ($eventname eq "insert" || $eventname eq "update");
        return "delete" if ($eventname eq "delete");
    };
    return undef;
    # Can return "delete" or "save"
};

return 1;
END {};