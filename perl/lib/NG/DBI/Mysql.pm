package NG::DBI::Mysql;
use strict;
use NG::DBI 0.4;

$NG::DBI::Mysql::VERSION = 0.4;

use vars qw(@ISA);
@ISA = qw(NG::DBI);

sub get_id {
	my $self = shift;
	my $table = shift;
	my $field = shift;

        if (!defined $field && $table =~ /(.*)\.(.*)/) {
            $table = $1;
            $field = $2;
        };
                                    
        if ($field && $field ne "id") {
            $table.= ".".$field;
        };
	
	my $sth = $self->dbh->prepare("SELECT table_name,last_id FROM ng_sequence where table_name = ?") or return $self->error($DBI::errstr);
	$sth->execute($table) or return $self->error($DBI::errstr); 
	my $row = $sth->fetchrow_hashref();
	$sth->finish();
	if (defined $row->{last_id}) {
		$self->dbh->do("UPDATE ng_sequence SET last_id=last_id+1 where table_name = ?",undef,$table) or return $self->error($DBI::errstr);
		return $row->{last_id}+1;
	} else {
		$self->dbh->do("INSERT into ng_sequence (table_name,last_id) values (?,1)",undef,$table) or return $self->error($DBI::errstr);
		return 1;
	}
};

sub open_range() {
    my $self   = shift;
    my $sql    = shift;
    my $offset = shift;
    my $limit  = shift;
                
    croak("open_range: offset not specified") if (!defined $offset);
    croak("open_range: limit not specified") if (!defined $limit);
                        
    my $sth = $self->dbh->prepare("$sql limit ?,?") or return undef;
    $sth->execute(@_,$offset, $limit) or return undef;
    return $sth;
}

sub sqllimit {
    my $self = shift;
    my $sql = shift;
    my $offset = shift;
    my $limit = shift;

    croak("sqllimit: offset not specified") if (!defined $offset);
    croak("sqllimit: limit not specified") if (!defined $limit);

    return $sql .= " limit $offset,$limit";
};

sub date_to_db {
	my $self = shift;
	my $date = shift;
	if (!defined $date) { return undef; };
	if ($date =~/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/) {
		return $3."-".$2."-".$1;
	} else {
		return undef;
	}
}

sub date_from_db {
	my $self = shift;
	my $date = shift;
	if (!defined $date) { return undef; };
	if ($date =~/^(\d{4})-(\d{2})-(\d{2})/) {
		return undef if $1 eq "0000";
		return $3.".".$2.".".$1;
	} else {
		return undef;
	}
};

sub datetime_to_db {
	my $self = shift;
	my $date = shift;
	if (!defined $date) {return undef;};
	if ($date =~/^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2})\:(\d{1,2})\:(\d{1,2})/) {
		return $3."-".$2."-".$1." ".$4.":".$5.":".$6;
	} else {
		return undef;
	}
};

sub datetime_from_db {
	my $self = shift;
	my $date = shift;
	if (!defined $date) { return undef; };
	if ($date =~/^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2})\:(\d{1,2})\:(\d{1,2})/) {
		return $3.".".$2.".".$1." ".$4.":".$5.":".$6;
	} else {
		return undef;
	}
};


sub _fillIndexText {
    my $self = shift;
    my $index = shift;
    my $data = $index->{DATA};
    delete $data->{TEXT};
    my $text = "";
    foreach my $indexClass (keys %{$data}) {
        next if $indexClass eq "HEADER";
        next if $indexClass eq "DATE";
        $text .= " " if $text;
        $text .= $data->{$indexClass};
    };
    $data->{TEXT} = $text;
    return 1;
}

#Ищем по полному набору $index->{LINKID},$index->{LANGID},$index->{PAGEID},$index->{SUFFIX}
sub getSearchIndexId {
    my $self = shift;
    my $index = shift;
    
    my $sth = $self->dbh()->prepare_cached("select id from ng_ftsindex where link_id = ? and lang_id = ? and page_id = ? and suffix = ?");
    my $res = $sth->execute($index->{LINKID},$index->{LANGID},$index->{PAGEID},$index->{SUFFIX});
    unless ($res) {
        $self->{_errstr} = "NG::DBI::Mysql::getSearchIndexId(): Ошибка запроса: ".$DBI::errstr;
        return 0;
    };
    
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    return undef unless $row;
    $index->{ID} = $row->{id};
    return $row->{id};
}

sub insertFTSIndex {
    my $self = shift;
    my $index = shift;
    
    my $id = $self->get_id('ng_ftsindex');
    my $data = $index->{DATA};
    $self->_fillIndexText($index) unless exists $data->{TEXT};
    $data->{A} ||= "";
    $data->{B} ||= "";
    $data->{C} ||= "";
    $data->{D} ||= "";
    
    my $sth = $self->dbh()->prepare_cached("insert into ng_ftsindex (id,text,header,date,category,link_id,lang_id,page_id,subsite_id,suffix,module) values (?,?,?,?,?,?,?,?,?,?,?)");
    my $res = $sth->execute($id,$data->{TEXT},$data->{HEADER},$self->date_to_db($data->{DATE}),$index->{CATEGORY},$index->{LINKID},$index->{LANGID},$index->{PAGEID},$index->{SUBSITEID},$index->{SUFFIX},$index->{OWNER});
    unless ($res) {
        $self->{_errstr} = "NG::Mysql::Mysql::insertFTSIndex(): Ошибка запроса: ".$DBI::errstr;
        return 0;
    };
    $sth->finish();
    return $id;
}

sub updateFTSIndex {
    my $self = shift;
    my $index = shift;
    
    unless ($index->{ID}) {
        $self->{_errstr} = "NG::DBI::Mysql::updateFTSIndex(): Отсутствует код обновляемого индекса";
        return 0;
    }
    
    my $data = $index->{DATA};
    $self->_fillIndexText($index) unless exists $data->{TEXT};
    
    $data->{A} ||= "";
    $data->{B} ||= "";
    $data->{C} ||= "";
    $data->{D} ||= "";
    undef $data->{DATE} unless $data->{DATE};
    
    my $sql = "update ng_ftsindex set text=?,header=?,date=?,category=?,link_id=?,lang_id=?,page_id=?,subsite_id=?,suffix=?,module=? where id = ?";
    my $sth = $self->dbh()->prepare_cached($sql);
    my $res = $sth->execute($data->{TEXT},$data->{HEADER},$self->date_to_db($data->{DATE}),$index->{CATEGORY},$index->{LINKID},$index->{LANGID},$index->{PAGEID},$index->{SUBSITEID},$index->{SUFFIX},$index->{OWNER},$index->{ID});
    unless ($res) {
        $self->{_errstr} = "NG::DBI::Mysql::updateFTSIndex(): Ошибка запроса: ".$DBI::errstr;
        $sth->finish();
        return 0;
    }
    $sth->finish();
    return 1;
}

sub deleteFTSIndex {
    my $self = shift;
    my $index = shift;
    
    #return 1 unless ($self->{_search_config});  #Если незапрошено явное удаление. используется чтобы не создавать ng_ftsindex для функций работы со структурой сайта
    
    if ($index->{ID}) {
        $self->dbh()->do("delete from ng_ftsindex where id=?",undef,$index->{ID});
    }
    elsif ($index->{PAGEID}) {
        $self->dbh()->do("delete from ng_ftsindex where page_id=?",undef,$index->{PAGEID});
    }
    elsif ($index->{LANGID}) {
        unless ($index->{LINKID}) {
            $self->{_errstr} = "NG::DBI::Mysql::deleteFTSIndex(): Отсутствует идентификатор группы страниц для удаляемых индексов с указанным LANGID";
            return 0;
        };
        $self->dbh()->do("delete from ng_ftsindex where link_id=? and lang_id=?",undef,$index->{LINKID},$index->{LANGID});
    }
    elsif ($index->{LINKID}) {
        $self->dbh()->do("delete from ng_ftsindex where link_id=?",undef,$index->{LINKID});
    }
    else {
        $self->{_errstr} = "NG::DBI::Mysql::deleteFTSIndex(): Отсутствует идентификатор удаляемых индексов";
        return 0;
    };
    return 1;
};
return 1;
END{};