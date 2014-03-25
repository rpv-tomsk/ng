package NG::Banners::Places::BPlaces;
use strict;

use NGService;
use NSecure;
use Data::Dumper;

use vars qw(@ISA);


sub AdminMode {
    use NG::Module::List;
    @ISA = qw(NG::Module::List);
};

sub config {
	my $self = shift;
	$self->tablename('banner_places');
   
    # Общая часть
    $self->fields(
                  {FIELD=>'id',          TYPE=>'id',       NAME=>'Код',        IS_NOTNULL=>1},
                  {FIELD=>'name',        TYPE=>'text',     NAME=>'Название',   IS_NOTNULL=>1, WIDTH=>'80%'},
                  {FIELD=>'sizex',      TYPE=>'text',     NAME=>'Ширина',     IS_NOTNULL=>1, WIDTH=>'10%'},
                  {FIELD=>'sizey',      TYPE=>'text',     NAME=>'Высота',     IS_NOTNULL=>1, WIDTH=>'10%'},
                  {FIELD=>'description', TYPE=>'textarea', NAME=>'Примечание', IS_NOTNULL=>0}
                 );
    # Списковая
    $self->listfields([
                       {FIELD => 'name'},
                       {FIELD => 'sizex'},
                       {FIELD => 'sizey'}
                      ]);
    # Формовая часть
    $self->formfields(
                      {FIELD => 'id'},
                      {FIELD => 'name'},
                      {FIELD => 'sizex'},
                      {FIELD => 'sizey'},
                      {FIELD => 'description'}
                     );
    
    
    #$self->{_onpage}=1;
    $self->order("name");
    #$self->order(
    #    {FIELD=>"name",DEFAULT=>0,ORDER_ASC=>"name",ORDER_DESC=>"name desc",DEFAULTBY=>'DESC', NAME=>"По наименованию"},
    #    {FIELD=>"id",  DEFAULT=>1,ORDER_ASC=>"id",  ORDER_DESC=>"id desc",  DEFAULTBY=>'DESC', NAME=>"По коду"},
    #);
    
    #$self->{_onpage} = 20;
	#$self->set_privilege("CAN_ADMINS"); 
};

return 1;
END{};
