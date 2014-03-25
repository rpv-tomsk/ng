package NG::TextProcessor;

use strict;

$NG::TextProcessor::VERSION=0.1;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);    
    $self; 
};

sub init {
    my $self = shift;
    $self->{_ctrl} = shift;
    $self->{_value} = undef;
    $self;
};

sub getCtrl {
    my $self = shift;
    return $self->{_ctrl};
};

sub setValue {
    my $self = shift;
    my $value = shift;
    
    $self->{_value} = $value;
    1;
};

=head
sub setUpdateDate {
    my $self=shift;
    my $parent=shift;
    $self->setValue(current_date());
    return 1;
};

sub removeDoubleSpaces {
    my $self = shift;
    
    $self->{_value} =~ s///g;
};
=cut

sub getResult {
    my $self = shift;
    return $self->{_value};
};

1;