package NG::Cache::Memcached;
use strict;

use Data::Dumper;

use vars qw($MEMCACHED $VERSION_EXPIRATION);

$VERSION_EXPIRATION = 3600;  # 1 hour


sub getCacheContentMetadata {
#warn "getCacheContentMetadata()";
    my ($self,$keys) = (shift,shift);
    
    my @mkeys = ();
    foreach my $key (@$keys) {
        push @mkeys, "meta_".$key;
    };
    
    my $metadata = $MEMCACHED->get_multi(@mkeys);
    
    my $response = [];
    foreach my $key (@$keys) {
warn "getCacheContentMetadata(): meta_$key ".((exists $metadata->{"meta_".$key})?"":" not ")."found";
        push @$response,$metadata->{"meta_".$key};
    };
    return $response;
};

sub getCacheContent {
#warn "getCacheContent()";
    my ($self,$keys) = (shift,shift);
    
    my @mkeys = ();
    foreach my $key (@$keys) {
        push @mkeys, "data_".$key;
    };
    
    my $mcontent = $MEMCACHED->get_multi(@mkeys);
    
    my $content = [];
    foreach my $key (@$keys) {
        warn "getCacheContent(): data_$key ".((exists $mcontent->{"data_".$key})?"":" not ")."found"; #unless exists $mcontent->{"data_".$key};
        push @$content,$mcontent->{"data_".$key};
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
        warn "storeCacheContent(): Stored data/metadata key ".$row->[0]." exp ".$row->[3];
        $MEMCACHED->set("meta_".$row->[0], $row->[1], $row->[3]-2);
        $MEMCACHED->set("data_".$row->[0], $row->[2], $row->[3]);
    };
    return 1;
};


sub _createVersionKey {
    my ($self,$key) = (shift,shift);
    
    my $ret = $MEMCACHED->add("version_".$key,1,$VERSION_EXPIRATION);
    if (!defined $ret) {
        warn "Error MEMCACHED::add(version_$key)";
        return 0;
    };
    unless ($ret) {
        warn "ELEMENT ALREADY EXISTS while creating new element (version_$key)";
        return 1;
    };
    warn "Created new element (version_$key)";
    return 1;
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
    
    foreach my $key (@$keys) {
        my $ret = $MEMCACHED->incr("version_".$key);
        if (!defined $ret) {
            warn "Error MEMCACHED::incr(version_$key)";
            next;
        };
        if ($ret) {
            warn "Set new value on (version_$key): $ret";
            next;
        };
        $self->_createVersionKey($key);
    };
    return 1;
};

sub getKeysVersion {
#warn "getKeysVersion()";
    my ($self,$keys) = (shift,shift);
    
    my @mkeys = ();
    foreach my $key (@$keys) {
        push @mkeys, "version_".$key;
    };
    
    my $mversions = $MEMCACHED->get_multi(@mkeys);
    
    my $versions = [];
    foreach my $key (@$keys) {
        warn "getKeysVersion(): version_$key ".((exists $mversions->{"version_".$key})?"":" not ")."found: ".((exists $mversions->{"version_".$key})?$mversions->{"version_".$key}:""); #unless exists $mversions->{"version_".$key};
        unless (exists $mversions->{"version_".$key}) {
            $mversions->{"version_".$key} = $self->_createVersionKey($key);
        };
        push @$versions,$mversions->{"version_".$key};
    };
    return $versions;
};

sub initialize {
    my ($class,$params) = (shift,shift);
    
    die "NG::Cache::Memcached->initialize(): initialize() must be called only from BEGIN {} blocks" unless ${^GLOBAL_PHASE} eq "START" || exists $ENV{MOD_PERL};
    die "NG::Cache::Memcached->initialize(): No parameters passed" unless $params && ref $params eq "HASH";
    die "NG::Cache::Memcached->initialize(): Another cache is already set up." if $NG::Application::Cache and ref $NG::Application::Cache ne "NG::Cache::Stub";
    
    if ($params->{MEMCACHED}) {
        $NG::Application::Cache = {};
        bless $NG::Application::Cache,__PACKAGE__;

        $MEMCACHED = $params->{MEMCACHED};
        return;
    };
    
    die "NG::Cache::Memcached->initialize(): Namespace not specified" unless defined $params->{namespace};

    $NG::Application::Cache = {};
    bless $NG::Application::Cache,__PACKAGE__;

    eval "use Cache::Memcached::Fast;";
    die $@ if $@;
    
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
    $MEMCACHED = new Cache::Memcached::Fast($params);
};

return 1;
