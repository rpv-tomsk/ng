package NG::Banners::Clients::CShows;
use strict;

use NGService;
use NSecure;
use Data::Dumper;

use vars qw(@ISA);

sub AdminMode {
    use NG::Module::List;
    @ISA = qw(NG::Module::List);
};

sub getParamFromUrl
{
 my $self=shift;
 my $url=$self->q()->url(-absolute=>1);
 $url=~/(\d+)/;
 return $1;
};

sub config 
{
 my $self = shift;
 $self->tablename('banners_shows');
 # Общая часть
 my $cid=is_valid_id($self->q()->param('cid'))?$self->q()->param('cid'):(is_valid_id($self->getParamFromUrl())?$self->getParamFromUrl():0);
 $self->fields(
               {FIELD=>'id',       TYPE =>'id',       NAME =>'Код',                IS_NOTNULL=>1},
               {FIELD=>'cid',      TYPE =>'fkparent', NAME =>'Код клиента',        IS_NOTNULL=>1},
               {FIELD=>'sdate',    TYPE =>'date',     NAME =>'Начало'},
               {FIELD=>'edate',    TYPE =>'date',     NAME =>'Конец'},
               {FIELD=>'bid',      TYPE =>'fkselect', 
               	                   NAME =>'Баннер',     
               	                   OPTIONS=>{ 
               	                             TABLE      =>"banners",
               	                             ID_FIELD   =>"id",
               	                             NAME_FIELD =>"name",
               	                             PARAMS     =>[
               	                                           $cid,
               	                                          ],
               	                             WHERE      =>"cid=? and moderated=1",
               	                             ORDER      =>"name",
               	                            },
               	                   IS_NOTNULL=>1},
               
               {FIELD=>'pid',      TYPE   =>'fkselect', 
               	                   NAME   =>'Место',     
               	                   OPTIONS=>{ 
               	                             TABLE      =>"clients_places",
               	                             ID_FIELD   =>"id",
               	                             NAME_FIELD =>"name",
               	                             #{WHERE     =>"cid=$cid"},
               	                             #{ORDER     =>"name"},
               	                             QUERY      =>"select bp.id as id,bp.name as name from clients_places cp,banner_places bp where cp.cid = $cid and cp.pid=bp.id order by name",
               	                            },
               	                   IS_NOTNULL=>1},	
               {FIELD=>'def', TYPE =>'checkbox', NAME =>'Баннер по умолчанию',  IS_NOTNULL=>0},	                                               
               {FIELD=>'is_show', TYPE =>'checkbox', NAME =>'Отображать',           DEFAULT=>1,   IS_NOTNULL=>0}
               #{FIELD=>'name',     TYPE =>'text',     NAME =>'Название',           IS_NOTNULL=>1},
               #{FIELD=>'alt',      TYPE =>'text',     NAME =>'Алтернативный текст',IS_NOTNULL=>0},
               #{FIELD=>'sizex',    TYPE =>'text',     NAME =>'По горизонтали',     IS_NOTNULL=>0},
               #{FIELD=>'sizey',    TYPE =>'text',     NAME =>'По вертикали',       IS_NOTNULL=>0},
               #{FIELD=>'file',     TYPE =>'file',     NAME =>'Файл баннера',       IS_NOTNULL=>0, UPLOADDIR=>"upload/banners/"},
               #{FIELD=>'text',     TYPE =>'textarea', NAME =>'Текстовый баннер',   IS_NOTNULL=>0},
               #{FIELD=>'is_flash', TYPE =>'checkbox', NAME =>'Флэш',               IS_NOTNULL=>0},
               #{FIELD=>'is_text',  TYPE =>'checkbox', NAME =>'Текст',              IS_NOTNULL=>0}
              );
    
    # Списковая
    $self->listfields([
                       {FIELD => 'bid'},
                       {FIELD => 'pid'},
                       {FIELD => 'sdate'},
                       {FIELD => 'edate'},
                       #{FIELD => 'sizey'},
                      ]);
    # Формовая часть
    $self->formfields(
                      {FIELD => 'id'},
                      {FIELD => 'bid'},
                      {FIELD => 'pid'},
                      {FIELD => 'sdate'},
                      {FIELD => 'edate'},
                      {FIELD => 'def'},
                      {FIELD => 'is_show'},
                      #{FIELD => 'alt'},
                      #{FIELD => 'text'},
                      #{FIELD => 'file'}
                     );
};
#вставим немного костылей(патчей то есть) для расширения функционала модуля
sub getListColumns {
    my $self = shift;
    # Составляем строку-список запрашиваемых полей. При этом контролируем вхождение туда ключевого поля.
    my @columns=();
    my $fields = "";
    my $idfound = 0;
    foreach my $field (@{$self->{_listfields}}) {
        $idfound = 1 if ($field->{TYPE} eq "id");
        push @columns,$field unless ($field->{TYPE} eq "hidden");  # Не включаем в список на отображение
        next if ($field->{FIELD} eq "_counter_");                  ## не включаем в список на выборку
    	my $prefix="bs.";
    	if($field->{'FIELD'} eq "bid") #"патч" номер раз
    	  {
    	   $prefix="b.name as ";
    	  }
    	elsif($field->{'FIELD'} eq "pid") #"патч" номер два
    	  {
    	   $prefix="bp.name as ";
    	  };  
    	$fields .= ",".$prefix.$field->{FIELD};
    	$field->{IS_POSORDER} = 1 if ($field->{TYPE} eq "posorder");
        $field->{ORDER} = getURLWithParams($field->{ORDER},$self->getFilterParam()) if ($field->{ORDER});
    };
    if ($idfound == 0)
      {
       $fields .= ","."bs.".$self->{_idname}; # Если ключевое поле не найдено
      };
    $fields =~ s/^,//;
    $self->{_shlistFields} = $fields;
    return @columns;
};

sub processFKFields {
    my $self = shift;

    #Из какого массива полей брать перечисление полей ?
    #Может ли ФК поле не участвовать в отображении списка ? - сейчас это значение обязательно. Если надо - перекрывайте метод.
    #Ранее был вариант что список полей брать из _listfields
    my $fkparam = "";
    foreach my $field (@{$self->{_fields}}) {
        if ($field->{TYPE} eq "fkparent") {
            $self->setFKParentValue($field) || return $self->showError();
            my $param_value = $field->{VALUE};
            $fkparam .= $field->{FIELD}."=".$param_value."&";
            $self->pushWhereCondition("bs.".$field->{FIELD}."=?",$param_value);
        };
        if ($field->{TYPE} eq "filter") {
            my $param_value = $field->{VALUE};
            return $self->error("Value not specified for FK field \"".$field->{FIELD}."\"") unless $param_value;
            $self->pushWhereCondition($field->{FIELD}."=?",$param_value);
        }
    };
    $fkparam =~ s/\&$//;
    $self->{_shlistFKParam} = $fkparam;
    return NG::Module::M_OK;
};

sub getListSQLTable {
    my $self = shift;
    return $self->{_table}." bs,banner_places bp,banners b";
};

sub getListSQLWhere {
    my $self = shift;
    my $where = "";
    foreach (@{$self->{_shlistWhere}}) {
        $where .= " and (".$_->{SQL}.")";
    };
    $where =~ s/and\ //;
    $where.="and bs.pid=bp.id and b.id=bs.bid";
    return $where;
};
return 1;
END{};