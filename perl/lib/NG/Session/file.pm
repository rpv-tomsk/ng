package NG::Session::file;
use strict;

use NG::Session;
use vars qw(@ISA);
@ISA = qw(NG::Session);

=head

Пример конфига (Имя сессии - Face):

[SessionFace]
Module = "NG::Session::file"

#Имя таблицы с сессиями, по умолчанию /tmp
Directory = '/tmp'

#Необязательные параметры, по умолчанию:
UMask = 0660

=cut

sub getDSN {
    my $self=shift;

    my $params = {};
    if (my $p = $self->getConfParam("Directory","")) {
        $params->{Directory} = $p;
    };
    if (my $p = $self->getConfParam("UMask","")) {
        $params->{UMask} = $p;
    };

    return ("driver:file",$params);
};

return 1;
END{};