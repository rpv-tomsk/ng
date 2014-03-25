package NG::Forum::Object;
use strict;

sub new {
    my $class = shift;
    my $forum_obj = shift;
    my $obj = {};
    bless $obj, $class;
    $obj->_init($forum_obj);
    $obj->init(@_);
    return $obj;
};

sub _init {
    my $self = shift;
    my $forum_obj = shift;
    $self->{_forum} = $forum_obj;
};

sub forum {
    my $self = shift;
    return $self->{_forum};
};

sub init {};


1;