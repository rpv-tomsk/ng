package NG::Field::MP3File;
use strict;
use NG::Field;
use vars qw(@ISA);
@ISA = qw(NG::Field);

sub init {
    my $field = shift;
    $field->{OPTIONS}->{"ALLOWED_EXT"} = "mp3";
    $field->{TYPE} = "file";    
    $field->SUPER::init(@_) or return undef;
    return 1;
};

return 1;
