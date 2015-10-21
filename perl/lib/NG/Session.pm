package NG::Session;
use strict;

use CGI::Session;

=head
TODO: кто должен поддерживать возможность указания ключей DSN
id:(static|sha|md5|sha512|sha256|incr)
serialize:(default:storable:freezethaw:yaml)

подклассы выставляют в DSN значение ключа driver, вроде как id и serialize могли бы
выставляться основным классом, считываясь из параметра DSN_ID и DSN_SERIALIZE.
Думаю что конфликта с параметрами DSN быть не должно.

С другой стороны базовый класс должен быть легким, да и метод называется getDSN() ?
=cut


=head
Пример конфига (Имя сессии - Face) для тупого использования CGI::Session:
Считываются параметры Module, DSN и остаток секции считается параметрами DSN

[SessionFace]
Module = "NG::Session"
DSN = "driver:bitbucket"
Log = 1
=cut

sub new {
    my $class = shift;
    return $class->_session("new",@_);
};

sub load {
    my $class = shift;
    return $class->_session("load",@_);
};
    
sub _session {
    my $class = shift;
    my $cmeth = shift;
    
    my $conf = shift;
    
    my $app  = $conf->{'App'} or return $class->set_err('No App param specified');
    my $cname= $conf->{'ConfName'} or return $class->set_err('No ConfName param specified');
    
    my $moduleName = $app->confParam("Session".$cname.".Module") or return $class->set_err("Can`t get parameter Module for session $cname.");
    
    if ($moduleName ne $class) {
        eval "use $moduleName";
        if ($@) {
            return $class->set_err($@);
        };
        unless (UNIVERSAL::can($moduleName,$cmeth)) {
            return $class->set_err("Класс $moduleName не содержит конструктора $cmeth().");
        };
        return $moduleName->$cmeth($conf,@_);
    };
    
    my $self = {};
    bless $self, $class;
    $self->init($conf,@_);
    
    my $sid = shift;
    my $sparams = shift;

    my ($dsn, $dsnargs) = $self->getDSN();
    $dsn or return undef;
    my $session = CGI::Session->$cmeth($dsn, $sid, $dsnargs, $sparams);
    unless ($session) {
        $NG::Session::errstr = CGI::Session->errstr();
        return undef;
    };
    $session->cleanExpiredSessions() if ( rand(1000) > 990 );
    return $session;
};

sub init {
    my $self = shift;
    my $conf = shift;
    
    $self->{_app} = $conf->{App};
    $self->{_name} = $conf->{ConfName};
};

sub app {
    my $self = shift;
    return $self->{_app};
};

sub set_err {
    my $self = shift;
    my $e = shift;
    $NG::Session::errstr = $e;
    return undef;
};

sub errstr {
    return $NG::Session::errstr;
};

sub getConfParam {
    my $self = shift;
    my $param = shift;
    return $self->{_app}->confParam("Session".$self->{_name}.".".$param, shift);
};

sub getDSN {
    my $self = shift;
    
    return $self->set_err("NG::Session descendant has no getDSN() method") if (ref $self ne "NG::Session");
    my $co = $self->app()->{_confObj} or return $self->set_err("NG::Session::getDSN(): cant get confObj from app");
    
    my $hash = $co->param(-block=>"Session".$self->{_name});
    
    my $dsn = "";
    my $params = {};
    #TODO: что насчет нескольких параметров через запятую, как они возвращаются из конфига в случае $cfg->param(-block=>'x'), как ARRAY ?
    foreach my $key (keys %{$hash}) {
        next if $key eq "Module";
        if ($key eq "DSN") {
            $dsn = $hash->{$key};
            next;
        };
        $params->{$key} = $hash->{$key};
    };
    return $self->set_err("NG::Session::getDSN(): can`t get DSN from config") unless $dsn;
    
    return ($dsn,$params);
};

return 1;
END{};