package NG::Field::Multicheckbox;
use strict;

#TODO: удаление связанных значений
#TODO: readonly
#TODO: сделать кнопку выбрать все / отменить выбор
#TODO: добавить параметры связанные с дефолтными значениями
#TODO: сообщение на пустой справочник



use NG::Field;
use NGService;
use NSecure;

use Carp;

use vars qw(@ISA);
@ISA = qw(NG::Field);

sub init {
    my $field = shift;
    #$field->{TEMPLATE} ||= "admin-side/common/fields/multicheckbox.tmpl";
    
    if ($field->{TYPE} eq 'multivalue') {
        $field->{TEMPLATE} ||= "admin-side/common/fields/multivalue.tmpl";
    };
    
    $field->SUPER::init(@_) or return undef;
    
    $field->db() or return undef;
    
    $field->{_DATAH} = undef; #Выбранные элементы, хеш (ключ = значение = id выбранного элемента)
    $field->{_DATAA} = undef; #Выбранные элементы, массив id
    $field->{_NEWH}  = {};    #Сохраняемые  элементы (выбранные на форме)
    $field->{_DICTH} = {};    #Данные словаря (ключ=значение = id элемента), хэш, для проверок значений _DATAH и _NEWH
    $field->{SELECT_OPTIONS} = [];
    
    $field->{_dict_loaded} = 0;
    $field->{_data_loaded} = 0;
    
    my $options = $field->{OPTIONS} || return $field->set_err("Для поля $field->{FIELD} типа multicheckbox не указаны дополнительные параметры");
    return $field->set_err("Параметр OPTIONS не является HASHREF") if ref $options ne "HASH";
    
    if ($options->{DICT}) {
        return $field->set_err("Значение атрибута DICT конфигурации поля $field->{FIELD} типа multicheckbox не является ссылкой на хэш") if ref $options->{DICT} ne "HASH";
        #TODO: проверить на наличие VALUES
        my $dict = $options->{DICT};
        $dict->{ID_FIELD}  ||= "id";
        $dict->{NAME_FIELD}||= "name";
        
        if (exists $dict->{PARAMS}) {
            return $field->set_err("Значение атрибута PARAMS списка значений поля $field->{FIELD} не является ссылкой на массив") if ref $dict->{PARAMS} ne "ARRAY";
            return $field->set_err("Атрибут PARAMS неприменим без атрибутов WHERE или QUERY") unless ($dict->{WHERE} || $dict->{QUERY});
        };
        if ($dict->{QUERY}) {
            return $field->set_err("Режим multivalue и опция DICT.QUERY не совместимы") if $field->{TYPE} eq 'multivalue';
            return $field->set_err("Опции DICT.ADDITION и DICT.QUERY не совместимы") if $dict->{ADDITION};
            return $field->set_err("Атрибут QUERY несовместим с атрибутами TABLE, WHERE и ORDER") if ($dict->{TABLE} || $dict->{WHERE} || $dict->{ORDER});
            $dict->{_SQL} = $dict->{QUERY};
        }
        else {
            $dict->{TABLE} || return $field->set_err("Для поля $field->{FIELD} типа multicheckbox не указано имя таблицы со значениями");
            my $sql="select ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." from ".$dict->{TABLE};
            if ($dict->{WHERE}) {
                return $field->set_err("Опции DICT.ADDITION и DICT.WHERE не совместимы") if $dict->{ADDITION};
                $sql .= " where ".$dict->{WHERE};
            };
            if ($dict->{ORDER}) { $sql .= " order by ".$dict->{ORDER}; };
            $dict->{_SQL} = $sql;
        };
    }
    elsif ($options->{VALUES}) {
        return $field->set_err("Значение атрибута VALUES конфигурации поля $field->{FIELD} типа multicheckbox не является ссылкой на массив") if ref $options->{VALUES} ne "ARRAY";
        return $field->set_err("Режим multivalue и опция VALUES не совместимы") if $field->{TYPE} eq 'multivalue';
        
        foreach my $p (@{$options->{VALUES}}) {
            return $field->set_err("Значение массива VALUES поля $field->{FIELD} не является хэшем.") if ref $p ne "HASH";
            my $id = $p->{ID};
            return $field->set_err("В списке значений VALUES поля $field->{FIELD} отсутствует значение ключа ID ") if (!$id && $id != 0);
            $p->{NAME} || return $field->set_err("В списке значений VALUES поля $field->{FIELD} отсутствует значение ключа NAME");
            $field->{_DICTH}->{$id} = $id;
            $field->{SELECT_OPTIONS} = $options->{VALUES};
        };
        $field->{_dict_loaded} = 1;
    }
    else {
        return $field->set_err("Отсутствует опция списка значений DICT или VALUES.");
    };
    
    unless ($field->{NOLOADDICT}) {
        return $field->set_err("Значение атрибута STORAGE конфигурации поля $field->{FIELD} типа multicheckbox не является ссылкой на хэш") if ref $options->{STORAGE} ne "HASH";
        my $storage = $options->{STORAGE};
        
        return $field->set_err("Не указано имя таблицы (TABLE) в атрибуте STORAGE поля $field->{FIELD}") unless $storage->{TABLE};
        return $field->set_err("Не указано имя поля данных (FIELD) в атрибуте STORAGE поля $field->{FIELD}") unless $storage->{FIELD};
        return $field->set_err("Не указан хэш связи полей основной таблицы и хранилища выбранных вариантов (FIELDS_MAP) в атрибуте STORAGE поля $field->{FIELD}") unless $storage->{FIELDS_MAP};
        return $field->set_err("Параметр FIELDS_MAP в атрибуте STORAGE поля $field->{FIELD} не является хэшем") unless ref $storage->{FIELDS_MAP} eq "HASH";
        return $field->set_err("Отсутствуют связи в параметре FIELDS_MAP атрибута STORAGE поля $field->{FIELD}") unless scalar keys %{$storage->{FIELDS_MAP}};
    };        
   
    $field->pushErrorTexts({
        NOTHING_CHOOSEN       => "Не выбраны значения.",
    });
    
    $field->{IS_FAKEFIELD}=1;
    return 1;
};

sub _loadDict {
    my $field = shift;
    
    my $options = $field->{OPTIONS};
    return $field->set_err("Отсутствует атрибут DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    return $field->set_err('DATA not loaded') unless defined $field->{_DATAH};
    
    my $sql = $dict->{_SQL} or return $field->set_err("NG::Field::Multicheckbox::prepareOutput(): отсутствует значение запроса. Ошибка инициализации поля.");
    my @params = ();
    @params = @{$dict->{PARAMS}} if (exists $dict->{PARAMS});
    
    my $dbh = $field->dbh() or return $field->set_err("_loadDict(): отсутствует dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("Ошибка загрузки значений multicheckbox: ".$DBI::errstr);
    $sth->execute(@params) or return $field->set_err($DBI::errstr);
    my @result = ();
    while (my ($id,$name) = $sth->fetchrow()) {
        push @result, {
            ID=>$id,
            NAME=>$name,
            SELECTED=>((exists $field->{_DATAH}->{$id}) && ($id eq $field->{_DATAH}->{$id}))?1:0,
        };
        $field->{_DICTH}->{$id} = $id;
    };
    $sth->finish();
    
    my $cnt = scalar @result;
    $field->{SIZE} ||= $cnt if $field->{TYPE} eq "multiselect";
    
    $result[int($cnt/2)]->{HALF} = 1 if $cnt > 1;
    
    $field->param('SELECT_OPTIONS',\@result);
    $field->{_dict_loaded} = 1;
    return 1;
};

sub prepareOutput {
    my $field = shift;
    
    my $options = $field->{OPTIONS};
    return $field->set_err("Отсутствует атрибут DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    if ($field->{TYPE} eq 'multivalue') {
        #Справочник полностью не загружаем, поэтому нужно запросить нужные значения
        my @params = ();
        @params = @{$dict->{PARAMS}} if exists $dict->{PARAMS};
        
        return $field->set_err('DATA(A) not loaded') unless defined $field->{_DATAA};
        
        my $placeholders = "";
        foreach my $id (@{$field->{_DATAA}}) {
            $placeholders.="?,";
            push @params, $id;
        };
        $placeholders =~s /,$//;
        
        my $sql="SELECT ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." FROM ".$dict->{TABLE}." WHERE ";
        $sql .= $dict->{WHERE}. " AND "  if $dict->{WHERE};
        $sql .= $dict->{ID_FIELD}." IN (".$placeholders.")";
        $sql .= " ORDER BY ".$dict->{ORDER} if $dict->{ORDER};
        
        
        my $dbh = $field->dbh() or return $field->set_err("_loadDict(): отсутствует dbh");
        
        my $sth = $dbh->prepare($sql) or return $field->set_err("Ошибка загрузки значений multicheckbox: ".$DBI::errstr);
        $sth->execute(@params) or return $field->set_err($DBI::errstr);
        my @result = ();
        my $value  = "";
        while (my ($id,$name) = $sth->fetchrow()) {
            push @result, {
                ID=>$id,
                NAME=>$name,
            };
            $value .= $id.',';
        };
        $sth->finish();
        $value =~s /,$//;
        
        $field->{SELECTED_OPTIONS} = \@result;
        $field->{SELECTED_ID} = $value;
        
        return 1;
    };
    
    unless ($field->{_dict_loaded}) {
        $field->_loadDict() or return undef;
    };
    return 1;
};

sub _getKey {
    my $field = shift;
    my $storage = shift;
    
    my $parent = $field->parent() or return $field->showError("Отсутствует объект-родитель");
    
    my $fields = "";
    my $ph = "";
    my $where = "";
    my @params = ();
    foreach my $key (keys %{$storage->{FIELDS_MAP}}) {
        $where .= "and ".$key ."=?";
        my $f = $storage->{FIELDS_MAP}->{$key} or return $field->showError("Отсутсвует значение имени связанного поля для поля $key.");
        my $fObj = $parent->getField($f) or return $field->showError("Поле $f, указанное как связанное с $key, не найдено.");
        my $v = $fObj->value($f) or return $field->showError("В связанном c полем $key поле $f отсутcтвует значение.");
        $fields .= ",".$key;
        $ph .= ",?";
        push @params, $v;
    };
    return $field->showError("Отсутствуют связанные поля") unless $where;
    $where  =~ s/^and//;
    $where = " where ".$where;
    $fields =~ s/^,//;
    $ph =~s /^,//;
    return {WHERE=>$where,PARAMS=>\@params,FIELDS=>$fields,PLHLDRS=>$ph};
};

sub afterLoad {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $storage = $options->{STORAGE} or return $field->showError("afterLoad(): отсутствует опция STORAGE");
    
    my $h = $field->_getKey($storage) or return 0;
    my $sql="select ".$storage->{FIELD}." from ".$storage->{TABLE}.$h->{WHERE};
    my $dbh = $field->dbh() or return $field->showError("afterLoad(): отсутствует dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("Ошибка загрузки значений multicheckbox: ".$DBI::errstr);
    $sth->execute(@{$h->{PARAMS}}) or return $field->set_err($DBI::errstr);
    
    $field->{_DATAH} = {};
    $field->{_DATAA} = [];
    while (my ($id) = $sth->fetchrow()) {
        $field->{_DATAH}->{$id} = $id; #Данные (выбранные элементы), хэш
        push @{$field->{_DATAA}}, $id; 
        #return $field->showError("Некорректное состояние БД: обнаружено значение ($id), отсутствующее в справочнике значений") unless exists $field->{_DICTH}->{$id} && $id == $field->{_DICTH}->{$id};
    };
    $sth->finish();
    $field->{_data_loaded} = 1;
    return 1;
};

sub setFormValue {
    my $field = shift;
    
    my $q = $field->parent()->q();
    
    if ($field->{TYPE} eq 'multivalue') {
        $field->{_NEWH} = {};
        foreach my $id (split /,/,$q->param($field->{FIELD})){
            $field->{_NEWH}->{$id} = $id;
        }
        return 1;
    };
    
    $field->{_NEWH} = {};
    foreach my $id ($q->param($field->{FIELD})) {
        $field->{_NEWH}->{$id} = $id;
    };
    return 1;
};

sub afterSave {
    my $self = shift;

    unless ($self->{_dict_loaded}) {
        $self->_loadDict() or return undef;
    };
    
    return $self->set_err('DATA(H) not loaded') unless defined $self->{_DATAH};
    return $self->set_err('DATA(A) not loaded') unless defined $self->{_DATAA};
    
    my $options = $self->{OPTIONS};
    my $storage = $options->{STORAGE} or return $self->showError("afterSave(): отсутствует опция STORAGE");
    my $h = $self->_getKey($storage) or return 0;
    
    my $dbh = $self->dbh() or return $self->showError("afterSave(): отсутствует dbh");
    
    my $ins_sth = $dbh->prepare("insert into ".$storage->{TABLE}." (".$storage->{FIELD}.",".$h->{FIELDS}.") values (?,".$h->{PLHLDRS}.")");
    my $del_sth = $dbh->prepare("delete from ".$storage->{TABLE}.$h->{WHERE}." and ".$storage->{FIELD}."=?");
    #TODO: выводить ошибки по кодам ?
    foreach my $id (@{$self->{_DATAA}}) {
        return $self->showError("Некорректное состояние: в БД обнаружено значение ($id), отсутствующее в справочнике значений") unless exists $self->{_DICTH}->{$id} && $id == $self->{_DICTH}->{$id};
        unless (exists $self->{_NEWH}->{$id} && $self->{_NEWH}->{$id} == $id) {
            $del_sth->execute(@{$h->{PARAMS}},$id) or return $self->showError($DBI::errstr);
        };
    };
    foreach my $id (keys %{$self->{_NEWH}}) {
        return $self->showError("Некорректное состояние: выбрано значение ($id), отсутствующее в справочнике значений") unless exists $self->{_DICTH}->{$id} && $id == $self->{_DICTH}->{$id};
        unless (exists $self->{_DATAH}->{$id} && $self->{_DATAH}->{$id} == $id) {
            $ins_sth->execute($id, @{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
    };
    return 1;
};

sub getJSSetValue {
    #TODO: implement this method
    return "";
};

sub setValue {
    my $field = shift;
    my $value = shift; # Array of values
    
    die "mchbx: setValue();"
    
    #TODO: implement
};

sub value {
	my $field = shift;
    #TODO: implement
    
    die "mchbx: value()";
    
	return [];          # Array of values
};

sub dbValue {
    croak "mchbx: dbValue();"
};

sub check {
    my $self = shift;
    
    return 1 unless $self->{IS_NOTNULL};
    return 1 if scalar keys %{$self->{_NEWH}};
    return $self->setErrorByCode("NOTHING_CHOOSEN");
};

sub clean {
    #TODO: implement ?
};

sub beforeSave {
	my $self = shift;
    return 1;
};

sub getFieldActions {
    my $self = shift;
    return [
        {ACTION=>"autocomplete", METHOD=>"doAutocomplete"},
        {ACTION=>"addrecord",    METHOD=>"addRecord"},
    ];
};

sub doAutocomplete {
    my $field = shift;
    my $is_ajax = shift;
    
    my $form = $field->parent();
    my $cms  = $field->cms();
    
    #Подстрока поиска
    use Encode;
    my $term = $field->q()->param("term") || "";
    Encode::from_to($term, "utf-8", "windows-1251");
    
    $term =~s/\s$//;
    $term =~s/^\s//;
    $term =~ s/ +/ /;
    
    return $cms->outputJSON([]) unless length($term) >= 3;
    
    #Уже выбранные элементы
    my $values = $field->q()->param("values") || "";
    my @vals = split(/,/,$values);
    my $n = scalar(@vals);

    my $options = $field->{OPTIONS};
    return $field->set_err("Отсутствует атрибут DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    my @params = ();
    @params = @{$dict->{PARAMS}} if exists $dict->{PARAMS};
    
    my $sql="SELECT ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." FROM ".$dict->{TABLE}." WHERE ";
    $sql .= $dict->{ID_FIELD}." NOT IN (".join(",", ("?") x $n).") AND " if $n;
    $sql .= $dict->{NAME_FIELD}." ILIKE ?";
    $sql .= " AND (".$dict->{WHERE}. ")"  if $dict->{WHERE};
    $sql .= " ORDER BY ".$dict->{ORDER} if $dict->{ORDER};
    #$sql .= " LIMIT $options->{LIMIT}" if($options->{LIMIT}); #TODO:
    
    push @vals,'%'.$term.'%';
    
    my $dbh = $field->dbh() or return $field->set_err("_loadDict(): отсутствует dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("Ошибка загрузки значений multicheckbox: ".$DBI::errstr);
    $sth->execute(@vals,@params) or return $field->set_err($DBI::errstr);
    my @result = ();
    while (my ($id,$name) = $sth->fetchrow()) {
        push @result, {
            id   => $id,
            label=> $name,
        };
    };
    $sth->finish();
    return create_json(\@result);
};

sub addRecord{
    my $field = shift;
    
    my $cms = $field->cms();
    my $q   = $field->q();
    my $db  = $field->db();
    my $dbh = $field->dbh();
    
    my $options = $field->{OPTIONS};
    my $dict = $options->{DICT};
    return create_json({error=>"Отсутствует атрибут DICT"}) unless $dict;
    return create_json({error=>"Пополнение справочника запрещено"}) unless $dict->{ADDITION};
    return create_json({error=>'Добавление значений в словари с условием WHERE не поддерживается'}) if $dict->{WHERE};
    
    my $text = $q->param("value") || "";
    $text = Encode::decode("utf-8", $text);
    $text = Encode::encode("windows-1251", $text);
    $text =~s/\s$//;
    $text =~s/^\s//;
    $text =~ s/ +/ /;
    
    return create_json({error=>'Добавляемое значение не указано'}) unless $text && !is_empty($text);
    
    my $sql= "select ".$dict->{ID_FIELD}." as id,".$dict->{NAME_FIELD}." as label FROM ".$dict->{TABLE}." WHERE ".$dict->{NAME_FIELD}." ILIKE ?";
    my $sth=$dbh->prepare($sql) or return create_json({error=>"Ошибка БД: ".$DBI::errstr});
    $sth->execute('%'.$text.'%')  or return create_json({error=>"Ошибка БД: ".$DBI::errstr});
    my $row1=$sth->fetchrow_hashref();
    my $row2=$sth->fetchrow_hashref();
    
    return create_json({error=>'В справочнике найдено несколько записей, содержащих "'.$text.'"'}) if $row2;
    return create_json({id=>$row1->{id},label=>$row1->{label}}) if $row1;
    
    my $id = $db->get_id($dict->{TABLE},$dict->{TABLE}."_id");
    return create_json({error=>"Ошибка БД при получении кода новой записи: ".$DBI::errstr}) unless $id;
    $dbh->do("INSERT INTO ".$dict->{TABLE}." (".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}.") VALUES (?,?)",undef,$id,$text) or return create_json({error=>"Ошибка БД при вставке записи: ".$DBI::errstr});
    return create_json({id=>$id,label=>$text});
};

1;


=head
    Описание конфигурирования
    
    #TODO: добавить "поле" которое будет показывать допустимость выбора параметра, по данным в БД.
    # Т.е. допустим некую ткань нельзя выбирать в вариантах исполнения товара, потому что для ткани не забиты её цвета (условие активности - colorscount>0)
{
    FIELD => "some_name",      # Используется в составе уникальных идентификаторов формы
    TYPE  => "multicheckbox",  # multicheckbox | multiselect |multivalue
                
                multivalue - специальный режим. Отдельный шаблон, передача значений - через запятую в одном поле HTTP запроса
                
    NAME  => "Варианты цвета",
    IS_NOTNULL => [0|1],       # Обязательность выбора хоть одного варианта
    
    SIZE => 12,                # высота списка multiselect
    
    OPTIONS => {
        # I - SQL part
        DICT=>{
            ID_FIELD=>"id",     # по умолчанию id
            NAME_FIELD=>"name", # по умолчанию name
            
            DEFAULT_FIELD=>"defa", # TODO: default
            
            QUERY => "",        # SQL-запрос
            
            TABLE => "",        # ... или таблица
            WHERE => "",        # без where
            ORDER => "",        # без order by
            
            PARAMS=> [],        # Параметры для QUERY или TABLE
            
            ADDITION  => 1,         #Разрешает пополнять справочник (реализовано в режиме multivalue)
            
            #TODO: дописать условие отображения элемента
        },
        # II - configured part
        VALUES => [
            {ID=>1,NAME=>"Name_Id1"},
            {ID=>2,NAME=>"Name_Id2",DEFAULT=>1},  #TODO: default
            {ID=>3,NAME=>"Name_Id3"},
        ],
        
        STORAGE => {
            TABLE => "table",
            FIELD => "dict_id",
            FIELDS_MAP => {storage_field1=>'record_field1',storage_field2=>'record_field2',},
        },
        ## + Нужно добавить параметр позиции чекбоксов - слева или справа от наименования
        ## + параметр числа минимального и максимального количества выбранных значений
    },
}
=cut
