package NG::DBlist;
use strict;

$NG::DBlist::VERSION = 0.4;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);
#    $self->config();
    return $self; 
}

sub init {
    my $self = shift;
    my %param = @_;
    $self->{_db}       = $param{db}     || die "NG::DBlist::init(): 'db' parameter missing";
    $self->{_table}    = $param{table}  || die "NG::DBlist::init(): 'table' parameter missing";
	$self->{_fields}   = $param{fields} || die "NG::DBlist::init(): 'fields' parameter missing";
	$self->{_where}    = $param{where}  || "";
	$self->{_order}    = $param{order}  || "";
	$self->{_page}     = $param{page}   || 1;
	$self->{_onpage}   = $param{onpage} || 10;
	$self->{_onlist}   = $param{onlist} || 10;
	$self->{_pagename} = $param{pagename} || "page";
	$self->{_url}      = $param{url}    || "";
    $self->{_urlmask}  = $param{urlmask}|| "";
	#
	$self->{_size}   = undef;
	$self->{_opened} = 0;
	$self->{_sth}    = undef;
	$self->{_rfunc}  = undef;
	$self->{_data}   = [];
	$self->{_glob}   = {};
	$self->{_disable_pages} = 0;
}

sub page   { return shift->{_page};   };
sub opened { return shift->{_opened}; };
sub db() {return shift->{_db};}

sub open {
    my $self = shift;

    my $dbh    = $self->{_db}->dbh();
    my $table  = $self->{_table};
    my $fields = $self->{_fields};
    my $where  = $self->{_where};
    my $order  = $self->{_order};
    my $ref    = $_[0];
  
    my @params;
    if (!defined $ref) {
        undef @params;  
    }
    elsif (ref $ref eq "ARRAY") {
        @params = @{$ref};
    }
    else {
        @params = @_;
    };

    $where = ($where)?"WHERE $where":"";
    
    my $ret = 0;
    while (1) {
        my $sth = $dbh->prepare("SELECT count(*) FROM $table $where") or last;
        $sth->execute(@params) or last;
        $self->{_size} = $sth->fetchrow();
        $sth->finish();
        $ret = 1;
        last;
    };
    unless ($ret) {
        warn "DBlist: open() failed. Query: 'select count(*) from $table $where'";
        return $ret;
    };
    
    my $sql = "SELECT $fields FROM $table $where $order";
    #warn $sql;
    $ret = 0;
    while (1) {
        if ($self->{_disable_pages}) {
            $self->{_sth} = $dbh->prepare($sql) or last;
            $self->{_sth}->execute(@params) or last;
        }
        else {
            $self->{_sth} = $self->{_db}->open_range($sql,$self->{_onpage}*($self->{_page}-1),$self->{_onpage},@params) or last;
        }
        $ret = 1;
        last;
    };
    unless ($ret) {
        warn "DBlist: open() failed. Query: '$sql'";
        return $ret;
    };
    $self->{_opened} = 1;
    return 1;
}

sub size {
    my $self = shift;
    if (!$self->opened()) { die "NG::DBlist object not opened yet."; };
    return $self->{_size};
}

sub sth {
    my $self = shift;
    if (!$self->opened()) { die "NG::DBlist object not opened yet."; };
    return $self->{_sth};
}

sub data {
	my $self = shift;
	my $sth = $self->sth;
	my $rfunc = $self->{_rfunc};

	while (my $row = $sth->fetchrow_hashref()) {
		if ($rfunc) {
			&$rfunc($self,$row);
		};
		push @{$self->{_data}}, $row;
	};
	return wantarray ? @{$self->{_data}}:$self->{_data}; 
}

sub rowfunction {
	my $self = shift;
	$self->{_rfunc} = shift;
}

sub pages {
	my $self = shift;
	
	if (!$self->opened()) { die "NG::DBlist object not opened yet."; };
	if ($self->{_disable_pages} == 1) {
		return wantarray ? ():[]; 
	};
 
    my $size=$self->{_size};  if ($size==0){$size=1;}  # Число записей
    my $page=$self->{_page};			    # Текущая страница
    my $el_on_page=$self->{_onpage};		    # Число записей на странице
    my $page_display=$self->{_onlist};	    # Отображать число ссылок
   
    my $url = $self->{_url} || "?";
    if ($url =~ /\/$/) {
		$url=$url."?";
    } else {
		if (($url !~ /\&$/) && ($url !~ /\?$/)) { $url=$url."&"; };
    } 
    my $page_name = $self->{_pagename};
    
    $self->{_urlmask} ||= $url.$page_name."={page}";
    
    my $page_count=int(($size-1)/$el_on_page)+1;
 #   my $npd=int(($page-1)/$page_display);
 #   my $fp=$npd*$page_display+1;
 #   my $ep=($npd+1)*$page_display;
 #   if ($ep>$page_count){$ep=$page_count;}

    my $half_page_display=int($page_display/2);

    my $fp = $page-$half_page_display;
    my $ep = $page+$half_page_display;

    if ($fp<1) {
        $fp=1;
        if ($fp+$page_display<=$page_count) {
			$ep=$fp+$page_display;
		}
		else {
			$ep = $page_count;
		};
    };
    if ($ep>$page_count) {
        $ep=$page_count;
        if ($ep-$page_display>=1) { $fp = $ep-$page_display; } else { $fp = 1; };
    };    

    my @pages;
    if ($fp>1){
		my $tmp;
		$tmp->{PAGE}=$fp-1;
		$tmp->{PREV_LIST}=1;
		$tmp->{PAGE_NAME}=$page_name;
		$tmp->{URL}=$url;
		$tmp->{PAGEURL} = $self->{_urlmask};
		$tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
		CORE::push @pages, $tmp;
	}
    if ($page>1) {
		my $tmp;
		$tmp->{PAGE}=$page-1;
		$tmp->{IS_PREV}=1;
		$tmp->{PAGE_NAME}=$page_name;		
		$tmp->{URL}=$url;
		$tmp->{PAGEURL} = $self->{_urlmask};
		$tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
		CORE::push @pages, $tmp;
    };
    for (my $i=$fp;$i<=$ep;$i++) {
		my $tmp;
		$tmp->{PAGE}=$i;
		if (defined $page && $page==$i) {
			$tmp->{CURRENT}=1;
	    }
		else {
			$tmp->{NORMAL}=1;
	    };
    	$tmp->{PAGE_NAME}=$page_name;
        $tmp->{URL}=$url;
		$tmp->{PAGEURL} = $self->{_urlmask};
		$tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
        CORE::push @pages, $tmp;
    };
    if ($page<$page_count) {
		my $tmp;
		$tmp->{PAGE}=$page+1;
		$tmp->{IS_NEXT}=1;
		$tmp->{PAGE_NAME}=$page_name;		
		$tmp->{URL}=$url;
		$tmp->{PAGEURL} = $self->{_urlmask};
		$tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
		CORE::push @pages, $tmp;
    };
	if ($ep<$page_count){
		my $tmp;
		$tmp->{PAGE}=$ep+1;
		$tmp->{NEXT_LIST}=1;
		$tmp->{PAGE_NAME}=$page_name;
		$tmp->{URL}=$url;
		$tmp->{PAGEURL} = $self->{_urlmask};
		$tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
		CORE::push @pages, $tmp;
	}
    if (scalar (@pages)==1){
		@pages = ();
	}
    foreach (@pages) {
	$_->{IS_NEXT} = 0 unless ($_->{IS_NEXT});
	$_->{IS_PREV} = 0 unless ($_->{IS_PREV});
	$_->{NORMAL} = 0 unless ($_->{NORMAL});
	$_->{CURRENT} = 0 unless ($_->{CURRENT});
    };
    return wantarray ? @pages:\@pages; 
}

sub disablePages {
	my $self = shift;
	if ($self->opened()) { die "disablePages(): dataset already opened."; };
	$self->{_disable_pages} = 1;
};

sub glob {
	return $_[0]->{_glob};
}

sub skipped {
    my $self = shift;
    return $self->{_onpage}*($self->{_page}-1);
}

sub pageExists {
    my $self = shift;
    die "NG::DBlist object not opened yet." if !$self->opened();
    return 1 if $self->{_page} == 1;
    return 0 if $self->{_page} < 0 || $self->{_disable_pages} || $self->{_size}==0 || !$self->{_sth}->rows();
    return 1;
}

return 1;
END{};
