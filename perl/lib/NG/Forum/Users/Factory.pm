package NG::Forum::Users::Factory;
use strict;
use base qw(NG::Forum::Object);

sub get_user {
    my $self = shift;
    my $user_id = shift;
    my $forum = $self->forum();

    my $modulename = $self->get_modulename($user_id);
    my $obj = $forum->module($modulename, $user_id);
    return $obj;
};

sub get_modulename {
    my $self = shift;
    my $user_id = shift;
    
    return "NG::Forum::Users::Anonymous" unless $user_id;    
    return "NG::Forum::Users";
};

1;