package NG::Cache::Memcached;
use strict;

use Data::Dumper;

use vars qw($MEMCACHED $VERSION_EXPIRATION $DATA_EXPIRATION);

$VERSION_EXPIRATION = 3600;  # 1 hour
$DATA_EXPIRATION    = 3600;  # 1 hour


sub getCacheContentMetadata {
#warn "getCacheContentMetadata()";
    my ($self,$keys) = (shift,shift);
    
    my @mkeys = ();
#my $mnames = {};
    foreach my $id (@$keys) {
        my $key = $self->cms->getCacheId('content',$id);
        push @mkeys, "meta_".$key;
#$mnames->{"meta_".$key} = $id->{CODE};
    };
    
    my $metadata = $MEMCACHED->get_multi(@mkeys);
    
    my $response = [];
    foreach my $key (@mkeys) {
#warn "getCacheContentMetadata(): ".$mnames->{$key}." $key ".((exists $metadata->{$key})?"":"not ")."found";
        push @$response,$metadata->{$key};
    };
    return $response;
};

sub getCacheContent {
#warn "getCacheContent()";
    my ($self,$keys) = (shift,shift);
    
    my @mkeys = ();
#my $mnames = {};
    foreach my $id (@$keys) {
        my $key = $self->cms->getCacheId('content',$id);
        push @mkeys, "content_".$key;
#$mnames->{"content_".$key} = $id->{CODE};
    };
    
    my $mcontent = $MEMCACHED->get_multi(@mkeys);
    
    my $content = [];
    foreach my $key (@mkeys) {
        #warn "getCacheContent(): ".$mnames->{$key}." $key ".((exists $mcontent->{$key})?"":" not ")."found"; #unless exists $mcontent->{$key};
        push @$content,$mcontent->{$key};
    };
    return $content;
};

=head
    $CACHE->storeCacheContent([
        [$ID,$METADATA,$DATA,$EXPIRE],
        [$ID,$METADATA,$DATA,$EXPIRE],
        ...
    ]);
    
    ID       - Хеш идентификатор контента (ключи CODE + REQUEST)
    METADATA - Метаданные кешируемого контента
    DATA     - Содержимое кешируемого контента
    EXPIRE   - Максимальное время жизни элемента кеша, секунды
=cut

sub storeCacheContent {
    my ($self,$data) = (shift,shift);
    
    foreach my $row (@$data) {
        my $key = $self->cms->getCacheId('content',$row->[0]);
        #warn "storeCacheContent(): ".$row->[0]->{CODE}." Stored content/metadata ".$key." exp ".$row->[3];
        $MEMCACHED->set("meta_".$key, $row->[1], $row->[3]-2);
        $MEMCACHED->set("content_".$key, $row->[2], $row->[3]);
    };
    return 1;
};

sub expireCacheContent {
    my ($self,$keys) = (shift,shift);
    
    foreach my $id (@$keys) {
        my $key = $self->cms->getCacheId('content',$id);
        
        #warn "expireCacheContent(): ".$id->{CODE}." Removed content/metadata ".$key;
        $MEMCACHED->delete("meta_".$key);
        $MEMCACHED->delete("content_".$key);
    };
    return 1;
};

sub _createVersionKey($$) {
    my ($self,$key) = (shift,shift);
    
    my $value = time();
    my $ret = $MEMCACHED->add($key,$value,$VERSION_EXPIRATION);
    if (!defined $ret) {
        warn "Error MEMCACHED::add($key) while _createVersionKey()";
        return undef;
    };
    unless ($ret) {
        warn "ELEMENT ALREADY EXISTS while creating new element ($key)";
        return 0;
    };
    #warn "Created new element ($key)";
    return $value;
};

=head
    $CACHE->updateKeysVersion($moduleObj,
        [
            {key1=>value1, key2=>value2},
            {MODULECODE => $moduleCode, key1=>value1, key2=>value2},
        ];                    - массив хешей, определяющих модуль и ключи, по которым необходимо проверять устаревание кешированного контента
    );
    
    
    Метод предназначен для использования в коде модулей, поэтому имеет первым параметром $moduleObj
=cut

sub updateKeysVersion {
    my ($self,$keys) = (shift,shift);
    
    my $ret = undef;
    foreach my $id (@$keys) {
        my $key = $self->cms->getCacheId('version',$id);
        my $try = 0;
        while (1) {
            $ret = $MEMCACHED->incr("version_".$key);
            if (!defined $ret) {
                warn "Error MEMCACHED::incr(version_$key). Try $try.";
                last;
            };
            if ($ret) {
                warn "Set new value on (version_$key): $ret Try $try" if $try;
                #Touch()
                my $cas = $MEMCACHED->gets("version_".$key);
                unless (defined $cas) {
                    warn "Touch for version_$key failed. Unable to get CAS";
                    last;
                };
                unless ($MEMCACHED->cas('version_'.$key, @$cas,$VERSION_EXPIRATION)) {
                    warn "Touch for version_$key failed. Failed cas() call";
                    last;
                };
                #
                last;
            };
            $ret = $self->_createVersionKey("version_".$key);
            last unless defined $ret;
            last if $ret;
            last if $try >= 1;
            $try++;
        };
        warn "updateKeysVersion() failed on (version_$key)" unless $ret;
    };
    return $ret;
};

sub getKeysVersion {
#warn "getKeysVersion()";
    my ($self,$keys,$_direct) = (shift,shift,shift);
    
    my @mkeys = ();
    my @directKeys = ();
    unless ($_direct) {
        foreach my $id (@$keys) {
            my $key = (ref $id)?$self->cms->getCacheId('version',$id):$id;
            push @directKeys, $key;
            push @mkeys, "version_".$key;
        };
    }
    else {
        foreach my $key (@$keys) {
            push @directKeys, $key;
            push @mkeys, "version_".$key;
        };
    };
    
    my $mversions = $MEMCACHED->get_multi(@mkeys);
    
    my $versions = [];
    foreach my $key (@mkeys) {
        #warn "getKeysVersion(): $key ".((exists $mversions->{$key})?"":"not ")."found: ".((exists $mversions->{$key})?$mversions->{$key}:""); #unless exists $mversions->{$key};
        unless (exists $mversions->{$key}) {
            $mversions->{$key} = $self->_createVersionKey($key);
            if (defined $mversions->{$key} && ($mversions->{$key} == 0)) {
                 $mversions->{$key} = $MEMCACHED->get($key);
            };
        };
        warn "getKeysVersion() failed for key $key" unless $mversions->{$key};
        push @$versions,$mversions->{$key};
    };
    #Массив значений версий + массив внутренних ключей.
    #Функция должна возвращать требуемые значения, если ей передан массив внутренних ключей в качестве $keys и выставлен флаг $_direct
    #Флаг $_direct может быть выставлен только в BlocksController, коду сайтов флаг недоступен.
    return [$versions,\@directKeys];
};

sub setCacheData {
    my ($self,$id,$data,$expire) = (shift,shift,shift,shift);
    
    $expire ||= $DATA_EXPIRATION;
    
    my $key = $self->cms->getCacheId('data',$id);
    #warn "setCacheData():  Stored data_".$key." exp ".$expire;
    $MEMCACHED->set("data_".$key, $data, $expire);
};

sub getCacheData {
    my ($self,$id) = (shift,shift);
    
    my $key = $self->cms->getCacheId('data',$id);
    my $ret = $MEMCACHED->get("data_".$key);
    #warn "getCacheData(): data_$key ".((defined $ret)?"":" not ")."found"; #unless exists $mcontent->{$key};
    $ret;
};

sub deleteCacheData {
    my ($self,$id) = (shift,shift);
    
    my $key = $self->cms->getCacheId('data',$id);
    my $ret = $MEMCACHED->delete("data_".$key);
    $ret;
};


sub _initMemcached {
    my ($class,$params) = (shift,shift);
    
    my $default = {
        servers => ['localhost:11211'],
        namespace => 'prod_cache_:',
        connect_timeout => 0.2,
        io_timeout => 0.5,
        close_on_error => 1,
        max_failures => 3,
        failure_timeout => 2,
        nowait => 1,
        hash_namespace => 1,
    };
    foreach my $key (keys %$default) {
        next if exists $params->{$key};
        $params->{$key} = $default->{$key};
    };
    new Cache::Memcached::Fast($params);
};

sub initialize {
    my ($class,$params) = (shift,shift);
    
    die "NG::Cache::Memcached->initialize(): initialize() must be called only from BEGIN {} blocks" unless $^V lt v5.14.0 || ${^GLOBAL_PHASE} eq "START" || exists $ENV{MOD_PERL};
    die "NG::Cache::Memcached->initialize(): No parameters passed" unless $params && ref $params eq "HASH";
    die "NG::Cache::Memcached->initialize(): Another cache is already set up." if $NG::Application::Cache and ref $NG::Application::Cache ne "NG::Cache::Stub";
    
    if ($params->{MEMCACHED}) {
        $NG::Application::Cache = {};
        bless $NG::Application::Cache,__PACKAGE__;

        $MEMCACHED = $params->{MEMCACHED};
        return;
    };
    
    die "NG::Cache::Memcached->initialize(): Namespace not specified" unless defined $params->{namespace};
    
    eval "use Cache::Memcached::Fast;";
    die $@ if $@;

    $NG::Application::Cache = {};
    bless $NG::Application::Cache,__PACKAGE__;
    
    $MEMCACHED = $class->_initMemcached($params);
};

return 1;
