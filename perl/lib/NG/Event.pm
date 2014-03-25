package NG::Event;
use strict;

sub new {
    my $class = shift;
    

    my $sender = shift;
    die "There is no sender object" unless ref ($sender);
    my $name   = shift or die " There is parameter missing Event has no name";
    
    my $opts   = shift;
    
    my $self = {};
    bless $self, $class;
    
    $self->{_sender} = $sender;
    $self->{_name} = $name;
    $self->{_opts} = $opts;

    
    $self->init(@_) or return undef;
    

    return $self;
};

sub init {
    my $self = shift;
    return 1;
};

sub name {
    my $self = shift;
    return $self->{_name};
};

sub sender {
    my $self = shift;
    return $self->{_sender};
};

sub options {
    my $self = shift;
    return $self->{_opts};
};

return 1;
END{};
 