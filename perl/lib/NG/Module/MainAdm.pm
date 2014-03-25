package NG::Module::MainAdm;
use strict;

use NGService;
use NSecure;
use NG::Nodes;
use NG::Form;

use vars qw(@ISA);

sub AdminMode {
    use NG::Module;
    @ISA = qw(NG::Module);
};

sub getModuleTabs {
	return [];
}

sub moduleAction {
	return NG::Module::M_OK;
}

return 1;
END{};
