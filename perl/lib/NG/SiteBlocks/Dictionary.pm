package NG::SiteBlocks::Dictionary;
use strict;
use NG::Module::List;

our @ISA = qw(NG::Module::List);

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    my $opts = shift;
    $self->{'_table'} = $opts->{'TABLE'} if ($opts->{'TABLE'});
};                             

sub config {
    my $self = shift;
    $self->fields(
        {'FIELD'=>'id', 'TYPE'=>'id'},
        {'FIELD'=>'name', 'TYPE'=>'text', 'IS_NOTNULL'=>1, 'NAME'=>'Название'},
        {'FIELD'=>'position', 'TYPE'=>'posorder', 'NAME'=>'Позиция'}
    );
    
    $self->formfields(
        {'FIELD'=>'id'},
        {'FIELD'=>'name'}
    );
    
    $self->listfields(
        {'FIELD'=>'name'}
    );    
};

1;