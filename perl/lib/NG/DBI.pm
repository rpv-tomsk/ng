package NG::DBI;
use strict;

use DBI 1.50;

$NG::DBI::VERSION = 0.4;
 
sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->config() or return undef;
    $self->init(@_) or return undef;
    return $self; 
}

sub config {
    my $self = shift;
    #$self->datasource('');
    #$self->username('');
    #$self->password('');
}

sub datasource {
    my $self = shift;
    return $self->{_ds} unless scalar(@_);
    $self->{_ds} = shift;
}

sub username {
    my $self = shift;
    return $self->{_username} unless scalar(@_);
    $self->{_username} = shift;
}

sub password {
    my $self = shift;
    return $self->{_passwd} unless scalar(@_);
    $self->{_passwd} = shift;
}

sub connect {
    my $self = shift;
    if (scalar(@_)) {
        foreach my $k (qw(_ds _username _passwd _attr)) {
            my $t = shift or next;
            $self->{$k} = $t;
        }
    }
    $self->{_dbh} = DBI->connect_cached($self->{_ds},$self->{_username},$self->{_passwd},$self->{_attr});#,{'pg_enable_utf8'=>1}
    if (!defined $self->{_dbh}) {
        $self->{_errstr} = $DBI::errstr;
        #$self->{_errstr} = "�� ���� ������������ � ��";
        return undef;
    } ;
    $self->After_open();
    return $self->{_dbh};
};

sub init {
    my $self = shift;
    $self->{_dbh} = undef;
    $self->{_errstr} = "";
    foreach my $k (qw(_ds _username _passwd _attr)) {
        my $t = shift or next;
        $self->{$k} = $t;
    };
    1;
}

sub dbh {
    my $self = shift;
    if (!defined $self->{_dbh}) {
        $self->{_dbh} =  $self->connect(@_);
    }
    return $self->{_dbh};
};

sub error {
    my $self = shift;
    my $err  = shift;
    $self->{_errstr} = $err;
    return 0;
}

sub errstr {
    my $self = shift;
    return $self->{_errstr};
}

sub _checkIndex {
    my $self = shift;
    my $index = shift;

    my $fname = "updatePageIndexes";
	return $self->error("NG::DBI::$fname(): �������� �������������� ������� �� �������� HASHREF") unless (ref($index) eq "HASH");
    return $self->error("����������� �������� ��������� �������.") unless defined $index->{CATEGORY};

    #return $self->error("� ������� ������������ ������������ ���������� ������: PAGEID + LANGID.") if (exists $index->{PAGEID} && exists $index->{LANGID});
    
    if (exists $index->{PAGEID}) {
        return $self->error("� ������� ����������� �������� SUBSITEID ��� ����� PAGEID.") unless exists $index->{SUBSITEID};
    }
    elsif (exists $index->{LINKID}) {
        return $self->error("� ������� ������������ ������������ ���������� ������ LINKID + SUBSITEID.") if exists $index->{SUBSITEID};
    }
    else {
        return $self->error("� ������� ����������� ���� PAGEID ��� LINKID.");
    };

    $index->{SUFFIX}||="";
    $index->{PAGEID} ||= 0;
    $index->{LINKID} ||= 0;
    $index->{LANGID} ||= 0;
    $index->{SUBSITEID} ||= 0;
    1;
}

sub updatePageIndexes {
	my $self = shift;
	my $indexes = shift;
	
	return $self->error("updatePageIndex(): �� ������� ����������� ������.") unless $indexes;
	return $self->error("updatePageIndex(): �������� ������� �� �������� ARRAYREF.") unless ref($indexes) eq "ARRAY";
	
    # ������ ���� �� ���� ��������, ���� ������ � ��, ���� �� �����-���������, ����� - ���������
    foreach my $index (@{$indexes}){
		$self->_checkIndex($index) || return 0;
        #���� �� ������� ������ $index->{PAGEID},$index->{LINKID},$index->{LANGID},$index->{SUFFIX}
        my $indexId = $self->getSearchIndexId($index);
		unless ($indexId) {
			my $e = $self->errstr();
			return $self->error("updatePageIndexes(): ������ ������ �������: $e") if $e;
		};

        if (scalar keys %{$index->{DATA}}) {
            if ($indexId) {
                return $self->updateFTSIndex($index);
            }
            else {
                return $self->insertFTSIndex($index);
            };
        }
        elsif ($indexId) {
            #������ ����, �� ������ � ��, �������
            return $self->deleteFTSIndex({ID => $indexId});
        };
    };
	return 1;
}

## Some methods 

sub After_open {
    
}

#NG::Application (raised from NG::SiteStruct) plugin events

sub beforeEnableNodeLink {
    my ($class,$link) = (shift,shift);
    
    if ($link->{LINKID} && $link->{LANGID}) {
        $class->cms->dbh()->do("UPDATE ng_ftsindex SET disabled = 0 WHERE link_id=? and lang_id = ?",undef,$link->{LINKID},$link->{LANGID}) or warn "beforeEnableNodeLink(): ".$DBI::errstr;
    }
    elsif ($link->{LINKID}) {
        $class->cms->dbh()->do("UPDATE ng_ftsindex SET disabled = 0 WHERE link_id=? and lang_id = 0",undef,$link->{LINKID}) or warn "beforeEnableNodeLink(): ".$DBI::errstr;
    }
    else {
        warn "beforeEnableNodeLink(): Missing LINKID value"
    };
    return 1;
};

sub afterDisableNodeLink {
    my ($class,$link) = (shift,shift);
    
    if ($link->{LINKID} && $link->{LANGID}) {
        $class->cms->dbh()->do("UPDATE ng_ftsindex SET disabled = 1 WHERE link_id=? and lang_id = ?",undef,$link->{LINKID},$link->{LANGID}) or warn "afterDisableNodeLink(): ".$DBI::errstr;
    }
    elsif ($link->{LINKID}) {
        $class->cms->dbh()->do("UPDATE ng_ftsindex SET disabled = 1 WHERE link_id=? and lang_id = 0",undef,$link->{LINKID}) or warn "afterDisableNodeLink(): ".$DBI::errstr;
    }
    else {
        warn "afterDisableNodeLink(): Missing LINKID value"
    };
    return 1;
};

sub beforeEnableNode {
    my ($class,$data) = (shift,shift);
    
    if ($data->{PAGEID}) {
        $class->cms->dbh()->do("UPDATE ng_ftsindex SET disabled = 0 WHERE page_id=?",undef,$data->{PAGEID}) or warn "beforeEnableNode(): ".$DBI::errstr;
    }
    else {
        warn "beforeEnableNode(): Missing PAGEID value"
    };
    return 1;
};

sub afterDisableNode {
    my ($class,$data) = (shift,shift);

    if ($data->{PAGEID}) {
        $class->cms->dbh()->do("UPDATE ng_ftsindex SET disabled = 1 WHERE page_id=?",undef,$data->{PAGEID}) or warn "afterDisableNode(): ".$DBI::errstr;
    }
    else {
        warn "afterDisableNode(): Missing PAGEID value"
    };
    return 1;
};

sub afterDeleteNodeLink {
    my ($class,$link) = (shift,shift);
    
    $class->cms()->db()->deleteFTSIndex($link);
};

sub afterDeleteNode {
    my ($class,$data) = (shift,shift);
    $class->cms()->db()->deleteFTSIndex({PAGEID=>$data->{PAGEID}});
};

return 1;
END{};
