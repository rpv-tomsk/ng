package NG::Cache::Memcached;
use strict;

use Data::Dumper;

use Storable qw(freeze thaw);
$Storable::canonical = 1;

use Digest::MD5 qw(md5_hex);

use vars qw($MEMCACHED);

#use Digest::SHA1 qw( sha1_hex );

sub getCacheContentKeys {
    my $self = shift;
#warn "getCacheContentKeys()";
    my $blocks = shift;

    my @keys = ();
    foreach my $block (@$blocks) {
        my $code = $block->{CODE};
        my $req  = $block->{REQUEST};

        my $r = freeze({CODE=>$code,REQUEST=>$req});
        my $key = md5_hex($r);
#print STDERR Dumper($block,$r, $key);
        push @keys,"meta_".$key;
#warn "get $code meta for $key";
        $block->{___MEMCKEY} = "meta_".$key;
    };
    my $keys = $MEMCACHED->get_multi(@keys);

    my $ret = {};
    foreach my $block (@$blocks) {
        my $key = delete $block->{___MEMCKEY};
        unless (exists $keys->{$key}) {
#warn "getCacheContentKeys: $block->{CODE} data $key ".((exists $keys->{$key})?"":" not ")."found";
            next;
        };
#if (exists $keys->{$key}) {
#warn "getCacheContentKeys: empty META for ".Dumper($block,$keys->{$key}) unless scalar(keys %{$keys->{$key}});
#}
        $ret->{$block->{CODE}} = $keys->{$key};
    };
    return $ret;
};

sub getCacheContent {
    my $self = shift;
    my $blocks = shift;
#warn "getCacheContent()";

    my @keys = ();
    foreach my $block (@$blocks) {
        my $code = $block->{CODE};
        my $req  = $block->{REQUEST};

        my $r = freeze({CODE=>$code,REQUEST=>$req});
        my $key = md5_hex($r);
        push @keys,"data_".$key;
        
#print STDERR "GET:".Dumper({CODE=>$code, REQUEST=>$req},$r, $key, thaw($r)) if $code =~ /NEWS/;
#warn "store all $code data for $key"  if $code =~ /NEWS/;;
        
        $block->{___MEMCKEY} = "data_".$key;
    };
    my $keys = $MEMCACHED->get_multi(@keys);

    my $ret = {};
    foreach my $block (@$blocks) {
        my $key = delete $block->{___MEMCKEY};
#warn "getCacheContent: $block->{CODE} data $key ".((exists $keys->{$key})?"":" not ")."found" unless exists $keys->{$key};
        $ret->{$block->{CODE}} = $keys->{$key};
    };
    return $ret;
};

sub storeCacheContent {
#warn "storeCacheContent()";

    my $self = shift;
    my $blocks = shift;

    foreach my $block (@$blocks) {
        my $code = $block->{CODE};
        my $req  = $block->{REQUEST};       #meta data
        # $block->{KEYS}->{HEADERS} ???      #meta data
        # $block->{DATA}                     #real data


        my $r = freeze({CODE=>$code, REQUEST=>$req});
        my $key = md5_hex($r);
#print STDERR Dumper($block,$r, $key, thaw($r));
#print STDERR "STORE:".Dumper({CODE=>$code, REQUEST=>$req},$r, $key, thaw($r)) if $code =~ /NEWS_NEWS(LIST|FULL)/;
#warn "store all $code data for $key"  if $code =~ /NEWS_NEWS(LIST|FULL)/;;

        my $k2 = md5_hex(freeze(thaw($r)));
print STDERR "MISMATCH $key != $k2".Dumper($block,$r, $key, thaw($r)) if $key ne $k2;

        my $expire = $block->{MAXAGE}; ### DIRTY HACK!!!
        $MEMCACHED->set("meta_".$key, $block->{KEYS}, $expire-2);
        $MEMCACHED->set("data_".$key, $block->{DATA}, $expire);
    };

    return 1;
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
