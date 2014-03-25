package NG::Banners;
use strict;

use NG::Form 0.4;
use NG::DBlist 0.4;
#use NG::Module 0.4;
use NSecure;
use NGService;

#Модуль-диспетчер
$Banners::VERSION=0.0000005;
use vars qw(@ISA);
sub AdminMode
{
 use NG::Module;
 @ISA = qw(NG::Module);
};

sub config
{
 my $self=shift;
 $self->setSubmodules(
                       [
                        {url=>"clients",module=>"NG::Banners::Clients"},
                        {url=>"places",module=>"NG::Banners::Places"}
                       ]
                      );
};



sub moduleAction
{
 my $self=shift;
 return NG::Module::M_OK;
};

sub AUTOLOAD
{
 my $self=shift;

};

return 1;
END{};