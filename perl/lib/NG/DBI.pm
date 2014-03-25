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
        foreach my $k qw(_ds _username _passwd _attr) {
            my $t = shift or next;
            $self->{$k} = $t;
        }
    }
    $self->{_dbh} = DBI->connect_cached($self->{_ds},$self->{_username},$self->{_passwd},$self->{_attr});#,{'pg_enable_utf8'=>1}
    if (!defined $self->{_dbh}) {
        $self->{_errstr} = $DBI::errstr;
        #$self->{_errstr} = "Не могу подключиться к БД";
        return undef;
    } ;
    $self->After_open();
    return $self->{_dbh};
};

sub init {
    my $self = shift;
    $self->{_dbh} = undef;
    $self->{_errstr} = "";
    foreach my $k qw(_ds _username _passwd _attr) {
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
	return $self->error("NG::DBI::$fname(): Параметр запрашиваемого индекса не является HASHREF") unless (ref($index) eq "HASH");
    return $self->error("Отсутствует значение категории индекса.") unless defined $index->{CATEGORY};

    #return $self->error("В индексе присутствует недопустимая комбинация ключей: PAGEID + LANGID.") if (exists $index->{PAGEID} && exists $index->{LANGID});
    
    if (exists $index->{PAGEID}) {
        return $self->error("В индексе отсутствует значение SUBSITEID для ключа PAGEID.") unless exists $index->{SUBSITEID};
    }
    elsif (exists $index->{LINKID}) {
        return $self->error("В индексе присутствует недопустимая комбинация ключей LINKID + SUBSITEID.") if exists $index->{SUBSITEID};
    }
    else {
        return $self->error("В индексе отсутствует ключ PAGEID или LINKID.");
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
	
	return $self->error("updatePageIndex(): Не передан обновляемый индекс.") unless $indexes;
	return $self->error("updatePageIndex(): Параметр индекса не является ARRAYREF.") unless ref($indexes) eq "ARRAY";
	
    # Крутим цикл по всем индексам, ищем индекс в БД, если не нашли-вставляем, нашли - обновляем
    foreach my $index (@{$indexes}){
		$self->_checkIndex($index) || return 0;
        #Ищем по полному набору $index->{PAGEID},$index->{LINKID},$index->{LANGID},$index->{SUFFIX}
        my $indexId = $self->getSearchIndexId($index);
		unless ($indexId) {
			my $e = $self->errstr();
			return $self->error("updatePageIndexes(): Ошибка поиска индекса: $e") if $e;
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
            #Индекс пуст, но найден в БД, удаляем
            return $self->deleteFTSIndex({ID => $indexId});
        };
    };
	return 1;
}

## Some methods 

sub After_open {
    
}

return 1;
END{};
