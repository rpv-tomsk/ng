package NG::Forum::Users::Anonymous;
use strict;
use base qw(NG::Forum::Users);

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    $self->{_user_data} = {
        id=>0,
        login=>"Incognito"
    };
};

sub is_root {
    return 0;
};

sub is_moderate {
    return 0;
};

sub can_access {
    my $self = shift;
    my $forum = $self->forum();
    return 0 if($forum->is_disabled_anonymous_users());
    return $self->SUPER::can_access(@_);
};

sub can_write {
    my $self = shift;
    my $forum = $self->forum();
    return 0 if($forum->is_disabled_anonymous_users());
    return $self->SUPER::can_write(@_);
};

sub can_moderate {
    my $self = shift;
    my $forum = $self->forum();
    return 0 if($forum->is_disabled_anonymous_users());
    return $self->SUPER::can_moderate(@_);
};

1;