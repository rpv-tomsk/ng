package NG::Authlib;
use strict;
use NG::Exception;

sub new {
    my $class = shift;
    my $lib = {};
    bless $lib, $class;
    $lib->init(@_);
    $lib;
};

sub init {
    my ($lib,$config,$ver) = (shift,shift,shift);
    
    my %p = (@_);
    
    $lib->{_table}  = $config->{table}  or NG::Exception->throw('NG.INTERNALERROR','\'table\' key is missing value');
    $lib->{_fields} = $config->{fields} or NG::Exception->throw('NG.INTERNALERROR','\'fields\' key is missing value');
    $lib->{_map} = {};
    $lib->{_map}->{id}    = $config->{id}    || 'id';
    $lib->{_map}->{hash}  = $config->{hash}  || 'hash';
    $lib->{_lengthLimit}  = $config->{lengthLimit} || 0;
    
    (ref $ver eq "HASH") or NG::Exception->throw('NG.INTERNALERROR','\'$ver\' parameter is not hashref');
    (keys %$ver) or NG::Exception->throw('NG.INTERNALERROR','\'$ver\' parameter has no versions');
    $lib->{_ver} = $ver;
    
    my $max = undef;
    foreach my $v (keys %$ver) {
        ($ver->{$v}->{plugin}) or NG::Exception->throw('NG.INTERNALERROR',"Version \'$v\' has no plugin value");
        $max = $v unless defined $max;
        $max = $v if $v > $max;
    };
    $lib->{_max} = $max;
    
    $lib;
};

sub authorize {
    my $lib = shift;
    my $p   = shift;
    
    NG::Exception->throw('NG.INTERNALERROR','authorize(): Only two keys are supported') if scalar keys %$p != 2;
    exists $p->{password} or die 'No password specified';
    
    my $password = delete $p->{password};
    my ($field)    = keys %$p;
    my $value    = $p->{$field};
    
    my $user = $lib->dbh->selectrow_hashref('SELECT '.$lib->{_fields}.' FROM '.$lib->{_table}.' WHERE '.$field.' = ?', undef, $value);
    NG::DBIException->throw('User record load error') if $DBI::errstr;

    return undef unless $user;
    return undef unless $lib->validate($user,$password);
    $user;
};

sub validate {
    my ($lib,$user,$password) = (shift,shift,shift);
    
    my $existingHash = $user->{$lib->{_map}->{hash}};
    NG::Exception->throw('NG.INTERNALERROR','Key \''.$lib->{_map}->{hash}.'\' at user hash is missing value') unless $existingHash;
    my $userId       = $user->{$lib->{_map}->{id}};
    NG::Exception->throw('NG.INTERNALERROR','Key \''.$lib->{_map}->{id}.'\' at user hash is missing value')   unless $userId;
    
    #Проверяем совпадение паролей
    my ($version,@rest) = split /:/,$existingHash;
    
    NG::Exception->throw('NG.AUTHLIB.EXPIRED',"Version $version does not configured") unless exists $lib->{_ver}->{$version};
    
    my $v = $lib->{_ver}->{$version};
    
    $existingHash =~ s/^$version\://;
    my $newHash = $lib->_buildHash($v,$user,$password,$existingHash);
    unless ($newHash && ($newHash eq $existingHash)) {
        return 0;
    };
    
    if ($version < $lib->{_max}) {
        my $updateHash = $lib->buildHash($user,$password);
        my $ret = $lib->dbh->do('UPDATE '.$lib->{_table}.' SET '.$lib->{_map}->{hash}.' = ? WHERE '.$lib->{_map}->{id}.' = ?', undef, $updateHash, $userId);
        NG::DBIException->throw('User record update error') if $DBI::errstr;
        NG::Exception->throw('NG.INTERNALERROR','User record update error') if $ret != 1;
    };
    
    return 1;
};

sub buildHash {
    my ($lib,$user,$password) = (shift,shift,shift);
    
    my $ret = $lib->{_max}.":".$lib->_buildHash($lib->{_ver}->{$lib->{_max}},$user,$password);
    NG::Exception->throw('NG.INTERNALERROR','buildHash(): Result hash is too long. Length: '.length($ret) . ' Limit: '  . $lib->{_lengthLimit}) if ($lib->{_lengthLimit} && length($ret) > $lib->{_lengthLimit});
    $ret;
};

sub _buildHash {
    my ($lib,$config,$user,$password,$existingHash) = (shift,shift,shift,shift,shift);
    
    NG::Exception->throw('NG.INTERNALERROR','_buildHash(): Missing password') unless $password ne "";
    my $plugin = $config->{plugin} or NG::Exception->throw('NG.INTERNALERROR','_buildHash(): Missing plugin value');
    
    unless ($plugin->can("can") && $plugin->can('buildHash')) {
        eval "use $plugin;";
        NG::Exception->throw('NG.INTERNALERROR',"_buildHash(): Unable to load module $plugin: ".$@)  if ($@);
    }; 
    
    $plugin->buildHash($user,$password,$config,$existingHash);
};

1;
