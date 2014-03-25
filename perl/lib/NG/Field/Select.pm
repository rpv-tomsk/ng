package NG::Field::Select;
use strict;

#TODO: добавить опцию текста если нет значений.
#TODO: реализовать check
#TODO: обработка привилегий.
#TODO: selectedName(), setValue() value() должны быть стабильны по значению.
#TODO: условие проверять, попадает ли выбранное значение под действие флага DISABLED
#TODO: default_null

use NG::Field;
use NHtml;

use vars qw(@ISA);
@ISA = qw(NG::Field);

sub init {
    #TODO: фильтровать привилегии на селект. Доделать выставление первой записи при выводе на морду. дописать систему привилегий на считывание привилегии из поля и доп ключа 
    my $field = shift;
    #$field->{TEMPLATE} ||= "admin-side/common/fields/multicheckbox.tmpl";

    $field->{TYPE}= "select" if $field->{TYPE} eq "fkselect"; #NB: Код для обеспечения обратной совместимости    
    
    $field->SUPER::init(@_) or return undef;
    
    $field->parent() or return 0; ## Вызовы методов могут выставить ошибки
    $field->db() or return 0; 
    
    $field->{_dict_loaded} = 0;         #Словарь подгружен
    $field->{_prepared} = 0;            #Произведена коррекция списка опций, возможно добавлены значения "не выбрано"/"выберите значение"
    $field->{_prepare_adds_option} = 0; #Коррекция списка опций добавила нулевой дополнительный элемент
    $field->{_defoption} = undef;       #опция, которая стала дефолтной из ключа option.DEFAULT
    $field->{_selected_option} = undef; #текущая выбранная в списке опция

    my $options = undef;
    if (exists $field->{OPTIONS}) {
        $options = $field->{OPTIONS};
        return $field->set_err("Параметр OPTIONS не является HASHREF") if ref $options ne "HASH";
    };

    if (exists $field->{SELECT_OPTIONS}) {
        return $field->set_err("Значение атрибута SELECT_OPTIONS поля $field->{FIELD} не является ссылкой на массив") if ref $field->{SELECT_OPTIONS} ne "ARRAY";
        if ($options) {
            return $field->set_err("Атрибут SELECT_OPTIONS несовместим с наличием OPTIONS.QUERY и OPTIONS.TABLE") if exists $options->{QUERY} || exists $options->{TABLE};
        };
        $field->setSelectOptions($field->{SELECT_OPTIONS}) or return undef;
    }
    else {
        $options || return $field->set_err("Для поля $field->{FIELD} не указан параметр источника данных списка значений");
        $options->{ID_FIELD}  ||= "id";
        $options->{NAME_FIELD}||= "name";
        if (exists $options->{PARAMS}) {
            return $field->set_err("Значение атрибута PARAMS конфигурации поля $field->{FIELD} типа fkselect не является ссылкой на массив") if ref $options->{PARAMS} ne "ARRAY";
            return $field->set_err("Атрибут PARAMS неприменим без атрибутов WHERE или QUERY") unless ($options->{WHERE} || $options->{QUERY});
        };
        if ($options->{QUERY}) {
            return $field->set_err("Атрибут QUERY несовместим с атрибутами TABLE, WHERE и ORDER") if ($options->{TABLE} || $options->{WHERE} || $options->{ORDER});
            $options->{_SQL} = $options->{QUERY};
        }
        else {
            $options->{TABLE} || return $field->set_err("Для поля $field->{FIELD} типа fkselect не указано имя таблицы со значениями");
            my $sql="select ".$options->{ID_FIELD}.",".(exists($options->{NAME_FIELD_QUERY}) ? $options->{NAME_FIELD_QUERY} : $options->{NAME_FIELD});
            
            $sql.=",".$options->{DISABLE_FIELD} if $options->{DISABLE_FIELD};
            $sql.=",".$options->{DEFAULT_FIELD} if $options->{DEFAULT_FIELD};
            $sql.=",".$options->{PRIVILEGE_FIELD} if $options->{PRIVILEGE_FIELD};
            
            $sql.=" from ".$options->{TABLE};
            if ($options->{WHERE}) { $sql .= " where ".$options->{WHERE};    };
            if ($options->{ORDER}) { $sql .= " order by ".$options->{ORDER}; };
            $options->{_SQL} = $sql;
        };
        $field->{SELECT_OPTIONS} = [];
    };
    
    $field->{NULL_VALUE} = 0 unless exists $field->{NULL_VALUE};
    $field->pushErrorTexts({
        NONEXISTENT_VALUE => "Выбрано несуществующее значение справочника в поле \"{n}\"",
        NOT_CHOOSEN       => "Значение поля \"{n}\" не выбрано",
    });
    return 1;
};

sub _loadFKSelect {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $sql = $options->{_SQL} or return $field->set_err("NG::Field::Select::prepareOutput(): отсутствует значение запроса. Ошибка инициализации поля.");
    my @params = ();
    @params = @{$options->{PARAMS}} if (exists $options->{PARAMS});
    
    my $dbh = $field->dbh() or return $field->showError("_loadFKSelect(): отсутствует dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->showError("Ошибка загрузки значений fkselect: ".$DBI::errstr);
    $sth->execute(@params) or return $field->showError($DBI::errstr);
    my @result = ();
    while (my $row = $sth->fetchrow_hashref()) {
        my $o = {};
        $o->{ID} = $row->{$options->{ID_FIELD}};
        $o->{NAME} = $row->{$options->{NAME_FIELD}};
        $o->{DEFAULT} = $row->{$options->{DEFAULT_FIELD}} if $options->{DEFAULT_FIELD};
        $o->{DISABLED} = $row->{$options->{DISABLE_FIELD}} if $options->{DISABLE_FIELD};
        $o->{PRIVILEGE} = $row->{$options->{PRIVILEGE_FIELD}} if $options->{PRIVILEGE_FIELD};
        push @result, $o;
    };
    $sth->finish();
    return $field->setSelectOptions(\@result);
};

sub setSelectOptions {
    my $field = shift;
    my $so    = shift;
    
    return $field->set_err("setSelectOptions(): некорректный параметр списка значений.") unless ($so && ref $so eq 'ARRAY');
    
    $field->{_prepared} = 0;
    $field->{_prepare_adds_option} = 0;
    $field->{_selected_option} = undef; #текущая выбранная в списке опция
    $field->{_defoption} = undef;       #опция, которая стала дефолтной из ключа option.DEFAULT
    my $seloption = undef;              #опция, которая стала выбранной из ключа option.SELECTED

    my @o = ();
    foreach my $t (@{$so}) {
        return $field->set_err("Значение массива SELECT_OPTIONS поля $field->{FIELD} не является хэшем.") if ref $t ne "HASH";
        return $field->set_err("В элементе списка значений SELECT_OPTIONS поля $field->{FIELD} отсутствует значение ключа ID ") unless exists $t->{ID} && defined $t->{ID};
        return $field->set_err("В элементе списка значений SELECT_OPTIONS поля $field->{FIELD} отсутствует значение ключа NAME") unless exists $t->{NAME} && defined $t->{NAME};
        
        my $p = {};
        $p->{ID} = $t->{ID};
        $p->{NAME} = $t->{NAME};
        $p->{SELECTED} = $t->{SELECTED} if exists $t->{SELECTED};
        $p->{DEFAULT} = $t->{DEFAULT} if exists $t->{DEFAULT};
        $p->{DISABLED} = $t->{DISABLED} if exists $t->{DISABLED};
        $p->{PRIVILEGE} = $t->{PRIVILEGE} if exists $t->{PRIVILEGE};
        
        $field->{_defoption} = $p if exists $p->{DEFAULT} && $p->{DEFAULT};
        $field->{_selected_option} = $p if (exists $field->{VALUE} && $field->{VALUE} eq $p->{ID});
        if (exists $p->{SELECTED} && $p->{SELECTED}) {
            delete $seloption->{SELECTED} if $seloption; # Чистим, если в списке несколько опций с флагом SELECTED
            $seloption = $p;
        };
        push @o, $p;
    };
    if ($seloption) {
        $field->{_selected_option} = $seloption;
        $field->{VALUE} = $seloption->{ID};
        $field->{DBVALUE} = $seloption->{ID};
        $field->{_changed} = 1;
    };
    
    $field->{_selected_option}->{SELECTED}=1 if $field->{_selected_option};
    $field->{SELECT_OPTIONS} = \@o;
    $field->{_dict_loaded} = 1;
    
    return 1;
};

sub setDefaultValue {
    my $field = shift;
    
    #option.DEFAULT имеет приоритет над значением, указанным в field->{DEFAULT}.
    #Если нет ни того ни другого - применяется опция DEFAULT_FIRST
    
    my $options = $field->{OPTIONS} || {};
    if ($field->{_defoption}) {
        delete $field->{_selected_option}->{SELECTED} if $field->{_selected_option};
        $field->{_selected_option} = $field->{_defoption};
        $field->{_selected_option}->{SELECTED} = 1;
        $field->{VALUE} = $field->{_selected_option}->{ID};
        $field->{DBVALUE} = $field->{_selected_option}->{ID};
        $field->{_changed} = 1;
    }
    elsif (exists $field->{DEFAULT}) {
        $field->setValue($field->{DEFAULT});
    }
    elsif (exists $options->{DEFAULT_FIRST} && $options->{DEFAULT_FIRST} && scalar @{$field->{SELECT_OPTIONS}} > 0) {
        delete $field->{_selected_option}->{SELECTED} if $field->{_selected_option};
        $field->{_selected_option} = @{$field->{SELECT_OPTIONS}}[0];
        $field->{_selected_option}->{SELECTED} = 1;
        $field->{VALUE} = $field->{_selected_option}->{ID};
        $field->{DBVALUE} = $field->{_selected_option}->{ID};
        $field->{_changed} = 1;
    };
};

sub _prepare {
    my $field = shift;
    
    unless ($field->{_dict_loaded}) {
        $field->_loadFKSelect() or return 0;
    };
    return 1 if $field->{_prepared} == 1;
    
    #Если новая строка:
    #  - если поле обязательное: IS_NOTNULL=>1
    #    + если выбирать не из чего, т.е. строк всего одна - она автоматически станет выбранной.
    #    + или оставляем список как есть, с выбранным первым вариантом: options.DEFAULT_FIRST=1
    #    + или добавляем в список строку options.TEXT_IS_NEW || "Выберите значение" (ID=0)
    #  - если поле не обязательное: IS_NOTNULL=>0
    #    + выбираем первый элемент выбраным, если есть options.DEFAULT_FIRST=1
    #    + добавляем первой строкой options.TEXT_IS_NULL || "Не указано" (ID=0)
    my $options = $field->{OPTIONS} || {};
    
    my $defaultFirst = 0;
    $defaultFirst = 1 if exists $options->{DEFAULT_FIRST} && $options->{DEFAULT_FIRST};

    if (!$field->{_selected_option} && $defaultFirst && scalar @{$field->{SELECT_OPTIONS}}) {
        #NB: не выставляет значение выбранной опции как значение поля, только для отображения.
        @{$field->{SELECT_OPTIONS}}[0]->{SELECTED} = 1;
    };
    
    #Еще есть условие: $field->{_new}==1
    $field->{_prepare_adds_option} = 0;
    if ($field->{IS_NOTNULL}) {
        my $text = "";
        $text = $options->{TEXT_IS_NEW} if exists $options->{TEXT_IS_NEW} && $options->{TEXT_IS_NEW};
        $text ||= "Выберите значение";
        unless ($field->{_selected_option} || $defaultFirst || (scalar @{$field->{SELECT_OPTIONS}} == 1) || $field->{TYPE} eq "radiobutton") {
            $field->{_prepare_adds_option} = 1;
            unshift @{$field->{SELECT_OPTIONS}},{
                ID   => $field->{NULL_VALUE},
                NAME => $text,
            };
        };
    }
    else {
        my $text = "";
        $text = $options->{TEXT_IS_NULL} if exists $options->{TEXT_IS_NULL} && $options->{TEXT_IS_NULL};
        $text ||= "Не указано";
        $field->{_prepare_adds_option} = 1;
        unshift @{$field->{SELECT_OPTIONS}},{
            ID   => $field->{NULL_VALUE},
            NAME => $text,
        };
    };
    $field->{_prepared} = 1;
    return 1;
};

sub prepareOutput {
    my $field = shift;
    $field->_prepare() or return 0;
    return 1;
};

sub _setDBValue {
    my $field = shift;
	my $value = shift;
	
	$field->{DBVALUE} = $value;
	$field->{VALUE} = $value;
    $field->{_selected_option}=undef;
    foreach my $opt (@{$field->{SELECT_OPTIONS}}) {
        delete $opt->{SELECTED};
        if (defined $value && $opt->{ID} eq $value) {
            $opt->{'SELECTED'}=1;
            #$field->{VALUE} = $opt->{NAME};
            $field->{_selected_option} = $opt;
        };
    };
    return 1;
};

sub _setValue {
	my $field = shift;
	my $value = shift;
	
    $field->{VALUE} = $value;
    $field->{DBVALUE} = $value;

    $field->{_selected_option}=undef;
    foreach my $f (@{$field->{SELECT_OPTIONS}}) {
        delete $f->{SELECTED};
        if (defined $value && $f->{ID} eq $value) {
            $f->{SELECTED} = 1;
            $field->{_selected_option} = $f;
        };
    };
    
    $field->{_changed} = 1;
    return 1;
};

sub value {
    #TODO: полностью идентично NG::Field::value()
	my $field = shift;
	return $field->{VALUE};
};

sub dbValue {
    my $field = shift;
    return $field->{DBVALUE};
};

sub _getSOFromDB {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $sql = $options->{_SQL} or return $field->set_err("NG::Field::Select::selectedName(): отсутствует значение запроса. Ошибка инициализации поля.");
    
    my @params = ();
    @params = @{$options->{PARAMS}} if (exists $options->{PARAMS});
    
    $sql = "select s.* from ($sql) s where s.".$options->{ID_FIELD}."=?";
    push @params, $field->{VALUE};

    my $dbh = $field->dbh() or return $field->showError("_loadFKSelect(): отсутствует dbh");        
    my $sth = $dbh->prepare($sql) or return $field->showError("Ошибка загрузки значений fkselect: ".$DBI::errstr);
    $sth->execute(@params) or return $field->showError($DBI::errstr);
    my $row = $sth->fetchrow_hashref() or return undef;
    $sth->finish();
    
    my $so = {};
    $so->{ID} = $row->{$options->{ID_FIELD}};
    $so->{NAME} = $row->{$options->{NAME_FIELD}};
    $so->{DEFAULT} = $row->{$options->{DEFAULT_FIELD}} if $options->{DEFAULT_FIELD};
    $so->{DISABLED} = $row->{$options->{DISABLE_FIELD}} if $options->{DISABLE_FIELD};
    $so->{PRIVILEGE} = $row->{$options->{PRIVILEGE_FIELD}} if $options->{PRIVILEGE_FIELD};
    return $so;
};

sub selectedName {
    my $field = shift;
    
    if ($field->{_selected_option}) {
        return $field->{_selected_option}->{NAME};
    };
    
    if ($field->{_dict_loaded}) {
        #die "NG::Field::Select::selectedName(): Dictionary loaded but no selected option exists";
        return "[no dict]";
    };
    
    return "" unless $field->{VALUE};
    my $so = $field->_getSOFromDB();
    $field->{_selected_option} = $so if $so;
    return "" unless $field->{_selected_option};
    return $field->{_selected_option}->{NAME};
};
*SELECTEDNAME = \&selectedName;

sub selectOptions {
	my $field = shift;

    if ($field->{_dict_loaded}==0) {
        $field->_loadFKSelect() or return undef;
    };
    if ($field->{_prepare_adds_option} == 1) {
        $field->{_prepared} = 0;
        $field->{_prepare_adds_option} = 0;
        shift @{$field->{SELECT_OPTIONS}};
    };
    return $field->{SELECT_OPTIONS};
};

sub getJSSetValue {
    my $field = shift;
    
    my $fd = $field->{FIELD};
    my $value = escape_js $field->{VALUE};
    my $key_value = $field->parent()->getComposedKeyValue();
    
    $field->_prepare() or return "alert('".$field->error()."');";
    
    if ($field->{TYPE} eq "radiobutton") {
        my $update = "parent.document.getElementById('$fd$key_value').innerHTML='';\n";
        foreach my $option (@{$field->{SELECT_OPTIONS}}) {
            $update .= "e = document.createElement('input'); e.type='radio';";
            $update .= "e.name='".$field->{FIELD}."';";
            $update .= "e.value='".(escape_js $option->{ID})."';";
            $update .= "e.checked=true;\n" if $option->{SELECTED};
            $update .= "e.disabled=true;\n" if $option->{DISABLED};
            
            $update .= "parent.document.getElementById('$fd$key_value').appendChild(e);";
            $update .= "t = document.createTextNode('".(escape_js $option->{NAME})."');";
            $update .= "parent.document.getElementById('$fd$key_value').appendChild(t);";
            $update .= "e = document.createElement('br');";
            $update .= "parent.document.getElementById('$fd$key_value').appendChild(e);";
        };
        return $update;
    }
    elsif ($field->{TYPE} eq "select") {
        my $i = 0;
        my $update = "parent.document.getElementById('$fd$key_value').options.length=0;\n";
        foreach my $option (@{$field->{SELECT_OPTIONS}}) {
            $update .= "o = new Option('".(escape_js $option->{NAME})."','".(escape_js $option->{ID})."',false,".($option->{SELECTED}?"true":"false").");\n";
            $update .= "o.disabled=true;\n" if $option->{DISABLED};
            $update .= "parent.document.getElementById('$fd$key_value').options[$i]= o;\n";
            $i++;
        };
        $update .= "parent.document.getElementById('$fd$key_value').value='$value';\n";
        return $update;
    }
    else {
        return "alert('Unknown field type ".$field->{TYPE}." in NG::Field::Select::getAjaxSetValue()')";
    };
    
};


sub check {
    my $field = shift;
    
    unless ($field->{_selected_option}) {
        if ($field->{VALUE} && !$field->{_dict_loaded}) {
            #Dict not loaded, try to load SO
            my $so = $field->_getSOFromDB();
            $field->{_selected_option} = $so if $so;
        };
    };
    
    unless ($field->{_selected_option}) {
        my $nullValue = $field->{NULL_VALUE};
        if ($field->{VALUE} && $field->{VALUE} ne $nullValue) {
            return $field->setErrorByCode("NONEXISTENT_VALUE");
        };
        if ($field->{IS_NOTNULL} && $field->{VALUE} eq $nullValue) {
            return $field->setErrorByCode("NOT_CHOOSEN");
        };
    };
    return $field->SUPER::check(@_);
};


1;


=head

Описание конфигурирования
{
    FIELD => "some_name",      # Используется в составе уникальных идентификаторов формы
    TYPE  => "select",         # select | radiobutton
    NAME  => "Категория",
    IS_NOTNULL => [0|1],       # Обязательность выбора хоть одного варианта
    DEFAULT => 12,             # Опция из списка опций с ключом DEFAULT или
                               # из поля DEFAULT_FIELD справочника имеет приоритет.
	
    #Пришедшее из списка SELECTED будет перевыставлять значение VALUE, которое имеется на момент вызова setSelectOptions
    SELECT_OPTIONS => [        # список элементов выбора для select
        {NAME=>"Выберите день недели",ID=>"0"},
        {NAME=>"Понедельник",ID=>"1"},
        {NAME=>"Вторник",ID=>"2"},
        {NAME=>"Среда",ID=>"3"},
        {NAME=>"Четверг",ID=>"4"},
        {NAME=>"Пятница",ID=>"5"},
        {NAME=>"Суббота",ID=>"6"},
        {NAME=>"Воскресенье",ID=>"7",PRIVILEGE=>"SUNDAY_PRIVILEGE",DEFAULT=>1,DISABLED=1,SELECTED=>1},
    ],
    
    #Часть хэша OPTIONS, ответственная за новые значения ()
    #Если новая строка:
    #  - если поле обязательное: IS_NOTNULL=>1
    #    + если выбирать не из чего, т.е. строк всего одна - она автоматически станет выбранной.
    #    + или оставляем список как есть, с выбранным первым вариантом: options.DEFAULT_FIRST=1
    #    + или добавляем в список строку options.TEXT_IS_NEW || "Выберите значение" (ID=0)
    #  - если поле не обязательное: IS_NOTNULL=>0
    #    + выбираем первый элемент выбраным, если есть options.DEFAULT_FIRST=1
    #    + добавляем первой строкой options.TEXT_IS_NULL || "Не указано" (ID=0)
    OPTIONS => {
        TEXT_IS_NEW => "Выберите день недели",
        TEXT_IS_NULL => "День недели не выбран",
        DEFAULT_FIRST => 1, # В отличие от параметра DEFAULT, не надо знать код позиции.
    },                      # влияет только на отображение.
    
    #Часть хэша OPTIONS, ответственная за проверку привилегий на элементы списка выбора
    OPTIONS => {
        PRIVILEGE_FIELD => "privilege",      #Выгружаем привилегию на элемент из таблицы элементов
        PRIVILEGEMASK   => "CATEGORY_{id}",  #Или воспользуемся маской
        FULL_PRIVILEGE  => "ALL_CATEGORY",   #Пользователь может иметь спец привилегию полного доступа
    },
    
    #Часть хэша OPTIONS, ответственная за источник данных для элементов выбора значения
    OPTIONS => {
        #Имена полей, из которых извлекать значения.
        ID_FIELD=>"id",     # по умолчанию id
        NAME_FIELD=>"name", # по умолчанию name
        DEFAULT_FIELD=>"is_def",
        DISABLE_FIELD=>"is_disa",
        
        
        #Источник данных - запрос 
        QUERY => "",        # SQL-запрос
        
        #Источник данных - таблица
        TABLE => "category",    # ... или таблица
        WHERE => "id>2",        # без where
        ORDER => "name",        # без order by
        
        PARAMS=> [],        # Параметры для QUERY или TABLE
    },
}
=cut
