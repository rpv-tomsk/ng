package NG::Field::Multicheckbox;
use strict;

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
    $field->{_NEWH}  = undef; #Сохраняемые элементы (выбранные на форме)
    $field->{_NEWA}  = undef; #Сохраняемые элементы (выбранные на форме), массив id
    $field->{_DICTA} = undef; #Данные словаря, полный словарь (для вывода multicheckbox)
    $field->{_DICTH} = undef; #Данные словаря (ключ=значение), хэш, для проверок значений _DATAH и _NEWH
    
    $field->{_value_id}    = undef;   #Выбранные элементы через запятую
    $field->{_value_names} = undef;   #Выбранные элементы через разделитель
    $field->{_changed}     = 0;       #Признак изменения списка выбранных значений. Может быть undef в процессе работы.
    
    $field->{_dict_loaded} = 0;
    $field->{_data_loaded} = 0;
    
    my $options = $field->{OPTIONS} || return $field->set_err("Для поля $field->{FIELD} не указаны дополнительные параметры");
    return $field->set_err("Параметр OPTIONS не является HASHREF") if ref $options ne "HASH";
    
    if ($options->{DICT}) {
        return $field->set_err("Значение атрибута DICT конфигурации поля $field->{FIELD} не является ссылкой на хэш") if ref $options->{DICT} ne "HASH";
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
        
        $field->{_DICTA} = [];
        foreach my $p (@{$options->{VALUES}}) {
            return $field->set_err("Значение массива VALUES поля $field->{FIELD} не является хэшем.") if ref $p ne "HASH";
            my $id = $p->{ID};
            return $field->set_err("В списке значений VALUES поля $field->{FIELD} отсутствует значение ключа ID ") if (!$id && $id != 0);
            $p->{NAME} || return $field->set_err("В списке значений VALUES поля $field->{FIELD} отсутствует значение ключа NAME");
            $field->{_DICTH}->{$id} = $p->{NAME};
            push @{$field->{_DICTA}}, {
                ID      => $id,
                NAME    => $p->{NAME},
                DEFAULT => $p->{DEFAULT},
            };
        };
        $field->{_dict_loaded} = 1;
    }
    else {
        return $field->set_err("Отсутствует опция списка значений DICT или VALUES.");
    };

    my $storage = $options->{STORAGE};
    if ($storage) {
        return $field->set_err("Отсутствует атрибут STORAGE поля $field->{FIELD}") unless $storage;
        return $field->set_err("Значение атрибута STORAGE конфигурации поля $field->{FIELD} не является ссылкой на хэш") if ref $storage ne "HASH";
        return $field->set_err("Не указано имя таблицы (TABLE) в атрибуте STORAGE поля $field->{FIELD}") unless $storage->{TABLE};
        return $field->set_err("Не указано имя поля данных (FIELD) в атрибуте STORAGE поля $field->{FIELD}") unless $storage->{FIELD};
        return $field->set_err("Не указан хэш связи полей основной таблицы и хранилища выбранных вариантов (FIELDS_MAP) в атрибуте STORAGE поля $field->{FIELD}") unless $storage->{FIELDS_MAP};
        return $field->set_err("Параметр FIELDS_MAP в атрибуте STORAGE поля $field->{FIELD} не является хэшем") unless ref $storage->{FIELDS_MAP} eq "HASH";
        return $field->set_err("Отсутствуют связи в параметре FIELDS_MAP атрибута STORAGE поля $field->{FIELD}") unless scalar keys %{$storage->{FIELDS_MAP}};
    }
    else {
        $options->{STORE_FIELD} ||= $field->{FIELD};
    };
    
    $field->pushErrorTexts({
        NOTHING_CHOOSEN       => "{n}: Не выбрано ни одного значения.",
    });
    
    $field->{HAS_ORDERING} = 0;
    if ($options->{STORE_FIELD} || ($storage && $storage->{ORDER})) {
        $field->{HAS_ORDERING} = (exists $options->{ORDERING})?$options->{ORDERING}:1;
    };
    return 1;
};

sub _loadDict {
    my $field = shift;
    
    my $options = $field->{OPTIONS};
    return $field->set_err("Отсутствует атрибут DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    return $field->set_err('DATA not loaded') unless defined $field->{_DATAH} || $field->{_new};
    
    my $sql = $dict->{_SQL} or return $field->set_err("NG::Field::Multicheckbox::_loadDict(): отсутствует значение запроса. Ошибка инициализации поля.");
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
        };
        $field->{_DICTH}->{$id} = $name;
    };
    $sth->finish();
    
    my $cnt = scalar @result;
    $field->{SIZE} ||= $cnt if $field->{TYPE} eq "multiselect";
    
    $result[int($cnt/2)]->{HALF} = 1 if $cnt > 1;
    
    $field->{_DICTA} = \@result;
    $field->{_dict_loaded} = 1;
    return 1;
};

sub prepareOutput {
    my $field = shift;
    
    if ($field->{TYPE} eq 'multivalue') { #Делаем частичную загрузку, только выбранные значения
        warn "Multicheckbox(multivalue): _dict_loaded = 1 warning!" if $field->{_dict_loaded}; #Справочник уже загружен.
        
        my $options = $field->{OPTIONS};
        return $field->set_err("Отсутствует атрибут DICT") unless $options->{DICT};
        my $dict = $options->{DICT};
        
        #Справочник полностью не загружаем, поэтому нужно запросить нужные значения
        my @params = ();
        @params = @{$dict->{PARAMS}} if exists $dict->{PARAMS};
        
        $field->{SELECTED_OPTIONS} = [];
        $field->{SELECTED_ID} = "";
        return 1 if $field->{_new};
        return $field->set_err('DATA(A) not loaded') unless defined $field->{_DATAA};
        return 1 unless scalar @{$field->{_DATAA}};
        
        my $placeholders = "";
        my ($dataIdxs,$i) = ({},0);
        foreach my $id (@{$field->{_DATAA}}) {
            $placeholders.="?,";
            push @params, $id;
            $dataIdxs->{$id} = $i++;
        };
        $placeholders =~s /,$//;
        
        my $sql="SELECT ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." FROM ".$dict->{TABLE}." WHERE ";
        $sql .= $dict->{WHERE}. " AND "  if $dict->{WHERE};
        $sql .= $dict->{ID_FIELD}." IN (".$placeholders.")";
        $sql .= " ORDER BY ".$dict->{ORDER} if $dict->{ORDER};
        
        
        my $dbh = $field->dbh() or return $field->set_err("prepareOutput(): отсутствует dbh");
        
        my $sth = $dbh->prepare($sql) or return $field->set_err("Ошибка загрузки значений multicheckbox: ".$DBI::errstr);
        $sth->execute(@params) or return $field->set_err($DBI::errstr);
        
        #Порядок сортировки списка выбранных значений может быть:
        #- соответствующий выборке из справочника (сортированного/не сортированного)
        #- соответствующий выборке из таблицы связи (сортированной/не сортированной)
        
        my $orderByDict = 1;
        $orderByDict = 0 if $options->{STORAGE} && $options->{STORAGE}->{ORDER};
        
        my @result = ();
        my @ids = ();
        my $dictIdx = 0;
        while (my ($id,$name) = $sth->fetchrow()) {
            my $dataIdx = delete $dataIdxs->{$id};
            $result[($orderByDict?$dictIdx:$dataIdx)] = {ID=>$id,NAME=>$name};
            $dictIdx++;
        };
        $sth->finish();
        
        return $field->set_err("Ошибка загрузки multicheckbox: значения ".join(',', keys %$dataIdxs)." не найдены в справочнике.") if scalar keys %$dataIdxs;
        
        my $value = "";
        $value .= $_->{ID}."," foreach @result;
        $value =~s /,$//;
        
        $field->{SELECTED_OPTIONS} = \@result;
        $field->{SELECTED_ID} = $value;
        
        return 1;
    };
    
    unless ($field->{_dict_loaded}) {
        #Делаем полную загрузку справочника значений
        $field->_loadDict() or return undef;
    };
    return $field->set_err('DATA(H) not loaded') unless defined $field->{_DATAH} || $field->{_new};
    foreach my $elm (@{$field->{_DICTA}}) {
        $elm->{SELECTED} = ((defined $field->{_DATAH} && exists $field->{_DATAH}->{$elm->{ID}})||($field->{_new} && $elm->{DEFAULT}))?1:0,
    };
    $field->{SELECT_OPTIONS} = $field->{_DICTA};
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
    my $storage = $options->{STORAGE};
    
    unless ($storage) {
        defined $field->{_value_id} or 'afterLoad(): Missing _value_id';
        
        $field->{_DATAH} = {};
        $field->{_DATAA} = [split(/,/,$field->{_value_id})];
        foreach my $id (@{$field->{_DATAA}}) {
            $field->{_DATAH}->{$id} = $id;
        };
        $field->{_data_loaded} = 1;
        return 1;
    };
    
    my $h = $field->_getKey($storage) or return 0;
    my $sql="SELECT ".$storage->{FIELD}." FROM ".$storage->{TABLE}.$h->{WHERE};
    $sql.= " ORDER BY ".$storage->{ORDER} if $storage->{ORDER};
    my $dbh = $field->dbh() or return $field->showError("afterLoad(): отсутствует dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("Ошибка загрузки значений multicheckbox: ".$DBI::errstr);
    $sth->execute(@{$h->{PARAMS}}) or return $field->set_err($DBI::errstr);
    
    $field->{_DATAH} = {};
    $field->{_DATAA} = [];
    while (my ($id) = $sth->fetchrow()) {
        $field->{_DATAH}->{$id} = $id; #Данные (выбранные элементы), хэш
        push @{$field->{_DATAA}}, $id; 
        #return $field->showError("Некорректное состояние БД: обнаружено значение ($id), отсутствующее в справочнике значений") unless exists $field->{_DICTH}->{$id};
    };
    $sth->finish();
    $field->{_data_loaded} = 1;
    return 1;
};

sub setFormValue {
    my $field = shift;
    
    my $q = $field->parent()->q();
    $field->{_NEWH} = {};
    $field->{_NEWA} = [];
    
    $field->{_value_id}    = undef;
    $field->{_value_names} = undef;
    $field->{_changed}     = undef;   #Необходимо определить наличие изменений/проверить выбранные на форме значения.
    
    if ($field->{TYPE} eq 'multivalue') {
        my $v = $q->param($field->{FIELD})||'';
        foreach my $id (split /,/,$v) {
            $field->{_NEWH}->{$id} = $id;
            push @{$field->{_NEWA}},$id;
        }
        return 1;
    };
    
    foreach my $id ($q->param($field->{FIELD})) {
        $field->{_NEWH}->{$id} = $id;
        push @{$field->{_NEWA}},$id;
    };
    return 1;
};

sub afterSave {
    my ($self,$action) = (shift,shift);
    
    return 1 unless $self->changed();
    
    my $options = $self->{OPTIONS};
    my $storage = $options->{STORAGE} or return 1;

    #Данные в форму загружены, т.к. LIST делает $form->loadData перед сохранением $form->update()
    unless ($self->{_dict_loaded}) {
        $self->_loadDict() or return undef;
    };
    
    return $self->set_err('DATA(H) not loaded') unless defined $self->{_DATAH}||$self->{_new};
    return $self->set_err('DATA(A) not loaded') unless defined $self->{_DATAA}||$self->{_new};
    return $self->set_err('NEW(A) not set') unless defined $self->{_NEWA};
    

    my $h = $self->_getKey($storage) or return 0;
    
    my $dbh = $self->dbh() or return $self->showError("afterSave(): отсутствует dbh");
    
    if ($storage->{ORDER}) {
        unless ($self->{_new}) {
            return 1 if join(',',@{$self->{_DATAA}}) eq join(',',@{$self->{_NEWA}});
            #Удаляем всё
            $dbh->do("DELETE FROM ".$storage->{TABLE}.$h->{WHERE},undef,@{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
        #Сохраняем в нужном порядке
        my $ins_sth = $dbh->prepare("insert into ".$storage->{TABLE}." (".$storage->{FIELD}.",".$storage->{ORDER}.",".$h->{FIELDS}.") values (?,?,".$h->{PLHLDRS}.")");
        my $idx = 1;
        foreach my $id (@{$self->{_NEWA}}) {
            return $self->showError("Некорректное состояние: выбрано значение ($id), отсутствующее в справочнике значений") unless exists $self->{_DICTH}->{$id};
            $ins_sth->execute($id, $idx++, @{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
        return 1;
    };
    
    my $ins_sth = $dbh->prepare("insert into ".$storage->{TABLE}." (".$storage->{FIELD}.",".$h->{FIELDS}.") values (?,".$h->{PLHLDRS}.")");
    my $del_sth = $dbh->prepare("delete from ".$storage->{TABLE}.$h->{WHERE}." and ".$storage->{FIELD}."=?");
    #TODO: выводить ошибки по кодам ?
    foreach my $id (@{$self->{_DATAA}}) {
        return $self->showError("Некорректное состояние: в БД обнаружено значение ($id), отсутствующее в справочнике значений") unless exists $self->{_DICTH}->{$id};
        unless (exists $self->{_NEWH}->{$id} && $self->{_NEWH}->{$id} == $id) {
            $del_sth->execute(@{$h->{PARAMS}},$id) or return $self->showError($DBI::errstr);
        };
    };
    foreach my $id (@{$self->{_NEWA}}) {
        return $self->showError("Некорректное состояние: выбрано значение ($id), отсутствующее в справочнике значений") unless exists $self->{_DICTH}->{$id};
        unless (exists $self->{_DATAH}->{$id}) {
            $ins_sth->execute($id, @{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
    };
    return 1;
};

#sub HAS_ORDERING {
#    my $field = shift;
#    
#    my $options = $field->{OPTIONS} || {};
#    my $storage = $options->{STORAGE} || {};
#    
#    return 0 unless ($options->{STORE_FIELD} || $storage->{ORDER});
#    return $options->{ORDERING} if exists $options->{ORDERING};
#    return 1;
#};

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

sub dbFields {
    my ($field,$action) = (shift,shift);
    
    my $options = $field->{OPTIONS};
    
    my @fields = ();
    push @fields, $options->{STORE_FIELD} if $options->{STORE_FIELD};
    push @fields, $options->{STORE_NAME}  if $options->{STORE_NAME};
    return @fields;
};

sub dbValue {
    my ($self,$dbField) = (shift,shift);
    
    my $options = $self->{OPTIONS};
    return $self->{_value_id}    if defined $self->{_value_id}    && $options->{STORE_FIELD} && $options->{STORE_FIELD} eq $dbField;
    return $self->{_value_names} if defined $self->{_value_names} && $options->{STORE_NAME}  && $options->{STORE_NAME}  eq $dbField;
    
    die "mchbx: dbValue(): - do not know how to get dbValue for $dbField";
};

sub check {
    my $self = shift;
    if ($self->{IS_NOTNULL}) {
        if ($self->{_NEWA}) {
            #Был вызов setFormValue() но выбрано ничего не было.
            return $self->setErrorByCode("NOTHING_CHOOSEN") unless scalar @{$self->{_NEWA}};
            
            #Проверим, что все выбранные значения существуют в справочнике
            return $self->_process();
        }
        elsif ($self->{_data_loaded}) {
            #Вызова setFormValue() не было, но была загрузка данных из хранилища. Проверим.
            return $self->setErrorByCode("NOTHING_CHOOSEN") unless scalar @{$self->{_DATAA}};
        };
        #Не было ни загрузки данных из хранилища, ни выставления значений из формы. Проверять нечего.
    };
    return $self->process();
};

sub process {
    my $self = shift;
    return 1 if defined $self->{_changed};
    return $self->_process();
};

sub _process {
    my $self = shift;
    
    unless (@{$self->{_NEWA}}) {
        $self->{_value_id}    = '';
        $self->{_value_names} = '';
        $self->{_changed}     = 1;
        $self->{_changed}     = 0 if $self->{_new};
        return 1;
    };
    
    unless ($self->{_dict_loaded}) {
        $self->_loadDict() or return undef;
    };
    
    my @names;
    foreach my $id (@{$self->{_NEWA}}) {
        return $self->showError("Некорректное состояние: выбрано значение ($id), отсутствующее в справочнике значений") unless exists $self->{_DICTH}->{$id};
        push @names, $self->{_DICTH}->{$id};
    };
    
    my $options = $self->{OPTIONS};
    my $ns = $options->{STORE_NAME_SEPARATOR};
    $ns = ',' unless defined $ns;
    
    $self->{_value_id}    = join(',',@{$self->{_NEWA}});
    $self->{_value_names} = join($ns,@names);
    
    $self->{_changed} = 0;
    $self->{_changed} = 1 if $self->{_new} or join(',',@{$self->{_DATAA}}) ne join(',',@{$self->{_NEWA}});

    return 1;
};

sub selectedValuesCnt {
    my $self = shift;
    die '' unless $self->{_NEWA};
    return scalar @{$self->{_NEWA}};
};

sub changed {
    my $self = shift;
    die '_changed value is undefined' unless defined $self->{_changed};
    $self->{_changed};
};

sub clean {
    #TODO: implement ?
};

sub setLoadedValue {
    my ($self,$row) = (shift,shift);
    
    my $options = $self->{OPTIONS};
    $self->{_value_id} = $row->{$options->{STORE_FIELD}} || '' if $options->{STORE_FIELD};
    
    return 1; #Значения для связи берутся из $form.
}; 

sub beforeSave { return 1; };

sub beforeDelete {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $storage = $options->{STORAGE} or return 1;
    my $h = $field->_getKey($storage) or return 0;
    my $dbh = $field->dbh() or return $field->showError("beforeDelete(): отсутствует dbh");
    my $sth = $dbh->do("DELETE FROM ".$storage->{TABLE}.$h->{WHERE},undef,@{$h->{PARAMS}}) or return $field->set_err("beforeDelete(): Ошибка удаления значений: ".$DBI::errstr);
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
    
    my $dbh = $field->dbh() or return $field->set_err("doAutocomplete(): отсутствует dbh");
    
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
    $text =~s/\s+$//;
    $text =~s/^\s+//;
    $text =~ s/ +/ /g;
    
    return create_json({error=>'Добавляемое значение не указано'}) unless $text && !is_empty($text);
    
    my $sql= "select ".$dict->{ID_FIELD}." as id,".$dict->{NAME_FIELD}." as label FROM ".$dict->{TABLE}." WHERE ".$dict->{NAME_FIELD}." ILIKE ?";
    my $sth=$dbh->prepare($sql) or return create_json({error=>"Ошибка БД: ".$DBI::errstr});
    $sth->execute('%'.$text.'%')  or return create_json({error=>"Ошибка БД: ".$DBI::errstr});
    my $row1=$sth->fetchrow_hashref();
    if ($row1) {
        my $row2=$sth->fetchrow_hashref();
        return create_json({error=>'В справочнике найдено несколько записей, содержащих "'.$text.'"'}) if $row2;
    };
    return create_json({id=>$row1->{id},label=>$row1->{label}}) if $row1;
    
    my $id = $db->get_id($dict->{TABLE},$dict->{ID_FIELD});
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
    FIELD => "some_name",      # Используется в составе уникальных идентификаторов формы. Из основной таблицы поле с этим именем не запрашивается.
    TYPE  => "multicheckbox",  # multicheckbox | multiselect |multivalue
                
                multivalue - специальный режим. Отдельный шаблон, передача значений - через запятую в одном поле HTTP запроса
                
    NAME  => "Варианты цвета",
    IS_NOTNULL => [0|1],       # Обязательность выбора хоть одного варианта
    
    SIZE => 12,                # высота списка multiselect
    
    OPTIONS => {
        #### ОПИСАНИЕ СЛОВАРЯ
        # I - Словарь в виде таблицы БД, загружается SQL-запросом
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
        # II - Словарь, жестко заданный в конфигурации
        VALUES => [
            {ID=>1,NAME=>"Name_Id1"},
            {ID=>2,NAME=>"Name_Id2",DEFAULT=>1},  #TODO: default
            {ID=>3,NAME=>"Name_Id3"},
        ],
        #### ОПИСАНИЕ СОХРАНЕНИЯ ЗНАЧЕНИЙ
        #Сохранение выбранных значений в таблицу отношения многие-ко-многим
        STORAGE => {
            TABLE => "table",             #Имя таблицы связи
            FIELD => "dict_id",           #Имя поля для сохранения ID выбранных значений
            FIELDS_MAP => {               #Карта сопоставления полей основной таблицы и таблицы связи
                storage_field1=>'record_field1',   #Поле связи => Поле основной таблицы
                storage_field2=>'record_field2',
            },
            ORDER => 'order_field',       #Имя поля для сохранения порядка выбранных значений в multivalue
        },
        #Сохранение выбранных значений в поле основной таблицы, в виде строки кодов, разделенных запятой
        STORE_FIELD => "movie_actor_id",   #Имя поля в основной таблице. Если STORAGE отсутствует, то STORE_FIELD по-умолчанию равно FIELD
        
        #Сохранение выбранных значений в поле основной таблицы, в виде строки значений с разделителем
        STORE_NAME  => "movie_actor_text", #Имя поля в основной таблице
        STORE_NAME_SEPARATOR => ", "       #Разделитель сохраняемых значений
        ORDERING => (0|1),                 #Разрешает/запрещает ручную сортировку при использовании STORE_FIELD или STORAGE.ORDER. Default=1
        
        ## + Нужно добавить параметр позиции чекбоксов - слева или справа от наименования
        ## + параметр числа минимального и максимального количества выбранных значений
    },
}
=cut
