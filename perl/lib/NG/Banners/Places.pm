package NG::Banners::Places;
use strict;

use NGService;
use NSecure;
use NHtml;
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
 $self->tablename('banner_places');
 # Общая часть
 $self->fields(
               {FIELD=>'id',          TYPE=>'id',       NAME=>'Код',        IS_NOTNULL=>1},
               {FIELD=>'name',        TYPE=>'text',     NAME=>'Название',   IS_NOTNULL=>1, WIDTH=>'80%'},
               {FIELD=>'sizex',       TYPE=>'text',     NAME=>'Ширина',     IS_NOTNULL=>1, WIDTH=>'10%'},
               {FIELD=>'sizey',       TYPE=>'text',     NAME=>'Высота',     IS_NOTNULL=>1, WIDTH=>'10%'},
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
 $self->order("name");
 #дополнительная ссылка на код баннерного места 
 my $url=$self->getBaseURL();
 $url=$self-> getURLWithParams($url,"id={id}","action=showcode");
 $self->add_links("Код",$url,1);
 $self->register_action('showcode',"showCode");
};

sub getProcessUrl
{
 my $self=shift;
 #возвращает относительный url по которому находится обработчик баннерного места
 return "/getb/";
};

sub showCode
{
 my $self=shift;
 my $action=shift;
 my $is_ajax=shift;
 my $q=$self->q();
 my $id=(is_valid_id($q->param('id')))?$q->param('id'):0;
 my $ref=$q->param('ref');
 #делаю просто и без лишних затрат нервных клеток и нейронов
 my $sql="select id,sizex,sizey from banner_places where id=?";
 my $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
 $sth->execute($id) or return $self->setError($DBI::errstr);
 my $result=$sth->fetchrow_hashref();
 $sth->finish();
 my $placeCode="Извините, но данное рекламное место не найдено";
 #id пришел верный(по крайней мере такое баннерное место есть в базе)
 if(is_valid_id($result->{'id'}))
   {
    $self->opentemplate('admin-side/common/bannerplacecode.tmpl') or return $self->showError();
    $self->tmpl()->param(
                         ID      => $result->{'id'},
                         SIZEX   => $result->{'sizex'},
                         SIZEY   => $result->{'sizey'},
                         WEBPATH => $self->getProcessUrl()                        
                        );	
    $placeCode=nl2br(htmlspecialchars($self->tmpl()->output()));
   };
 $self->opentemplate("admin-side/common/information.tmpl") or return $self->showError();
 $self->tmpl()->param(
                      DATA     =>$placeCode,
                      KEY_VALUE=>$id,
                      AJAX     =>$is_ajax,
                      REF      =>$ref
                     );
 return $self->output($self->tmpl()->output());  
};

sub CheckData
{
 my $self=shift;
 my $form=shift;
 my $action=shift;
 #В форме уже есть ошибочные данные и поэтому дальнейшая проверка излишна
 if($form->has_err_msgs())
   {
   	return NG::Module::M_OK;
   };
 my $sizexField=$form->_getfieldhash("sizex");
 my $sizeyField=$form->_getfieldhash("sizey");
 if(!is_valid_id($sizexField->{'VALUE'}))
   {
   	$form->_setfielderror($sizexField,"Не корректно задан размер");
   };
 if(!is_valid_id($sizeyField->{'VALUE'}))
   {
   	$form -> _setfielderror($sizeyField,"Не корректно задан размер");
   };
 return NG::Module::M_OK;
};

return 1;
END{};