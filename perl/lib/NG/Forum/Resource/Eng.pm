package NG::Forum::Resource::Eng;
use strict;
use base qw(NG::Forum::Resource::Rus);

sub init_resource {
    my $self = shift;
    my $resources = $sellf->SUPER::init_resource();
    
    return $resources;    
};

1;