package NG::Module::MainAdm;
use strict;

use NGService;
use NSecure;
use NG::Nodes;
use NG::Form;

use vars qw(@ISA);
use NG::Module;
@ISA = qw(NG::Module);

sub getModuleTabs {
	return [];
}

sub adminModule {
    my $self = shift;
    return $self->cms->output("");
};

return 1;
END{};
