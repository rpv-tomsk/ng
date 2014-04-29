package NG::Interface;
use strict;
use POSIX;

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

1;
