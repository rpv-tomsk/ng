package NG::Interface;
use strict;
use Carp;
$Carp::Internal{'NG::Interface'}++;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_) or return undef;
    #$self->config();
    return $self; 
};

sub init {
    my $self = shift;
    my $opts = shift || {};
    $self->{_mObj} =  delete $opts->{MODULEOBJ};
    $self->{_opts}   = $opts;
    die "Missing MODULEOBJ obj in constructor ".ref($self) unless $self->{_mObj};
    return $self;
};

sub getModuleObj { #для обращения в интерфейсе к родителю, то есть к модулю вызвавшему его
    my $self = shift;
    return $self->{_mObj};
};

sub run {
    my ($self,$method) = (shift,shift);
    return $self->$method(@_);
};

sub safe {
    my ($self,$method) = (shift,shift);
    
    my $ret = $self->$method(@_);
    
    my $validateMethod = "validate_$method";
    $self->$validateMethod($ret) if UNIVERSAL::can($self,$validateMethod);
    $ret;
};

sub try { #Really this is 'trysafe'
    my ($self,$method) = (shift,shift);
    
    my $ret = undef;
    $ret = $self->$method(@_) if $self->can($method);
    
    my $validateMethod = "validate_$method";
    $self->$validateMethod($ret) if UNIVERSAL::can($self,$validateMethod);
    $ret;
};

sub _package {
    my $self = shift;
    my $obj = $self->{_mObj};
    return 'interface "'.(ref $self).'"'.(($self ne $obj)?(' of module "'.(ref $obj).'"'):'');
}

sub can {
    my ($self,$method) = (shift,shift);
    return 1 if UNIVERSAL::can($self,$method);
    return 0 unless $self->{_mObj};
    return UNIVERSAL::can($self->{_mObj},$method);
};

our $AUTOLOAD;
sub AUTOLOAD {
    my $self=shift;
    my $pkg = ref $self;
    $AUTOLOAD =~ s/$pkg\:\://;
    
    return $self->{_mObj}->$AUTOLOAD(@_) if $self->{_mObj} && $self->{_mObj}->can($AUTOLOAD);
    
    croak('Can\'t locate object method "'.$AUTOLOAD.'" via '.$self->_package());
};

sub DESTROY {};

1;
