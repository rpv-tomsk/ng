package NG::Banners::BannersList;
use strict;

use NGService;
use NSecure;
use Data::Dumper;

use vars qw(@ISA);

sub AdminMode
{
 use NG::Module::List;
 @ISA = qw(NG::Module::List);
};

sub config
{
 my $self=shift;
 $self->tablename('banners');
 # Общая часть
 $self->fields(
               {FIELD=>'id',          TYPE=>'id',       NAME=>'Код',        IS_NOTNULL=>1},
               {FIELD=>'name',        TYPE=>'text',     NAME=>'Название',   IS_NOTNULL=>1, WIDTH=>'100%'},
               #{FIELD=>'size_x',      TYPE=>'text',     NAME=>'Ширина',     IS_NOTNULL=>1, WIDTH=>'10%'},
               #{FIELD=>'size_y',      TYPE=>'text',     NAME=>'Высота',     IS_NOTNULL=>1, WIDTH=>'10%'},
               #{FIELD=>'description', TYPE=>'textarea', NAME=>'Примечание', IS_NOTNULL=>0}
              );
 # Списковая
 $self->listfields([
                    {FIELD => 'name'},
                   # {FIELD => 'size_x'},
                   # {FIELD => 'size_y'}
                   ]);
 # Формовая часть
 $self->formfields(
                   {FIELD => 'id'},
                   {FIELD => 'name'},
                   #{FIELD => 'size_x'},
                   #{FIELD => 'size_y'},
                   #{FIELD => 'description'}
                   );
 #$self->{_onpage}=1;
 $self->order("name");
 #$self->setSubmodules(
 #                      [
 #                       {URL=>"places",MODULE=>"NG::Banners::Places"},
 #                      ]
 #                     );
 #выставляет табы и обеспечивает подсветку
 #$self->setTabs(
 #               {HEADER=>"Баннерные места",TABURL=>""}
 #              );                     
};

return 1;
END{};