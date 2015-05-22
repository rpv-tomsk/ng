package NG::Field;
use strict;
use NSecure;
use NGService;

use File::Copy;
use File::Path;
use NHtml;

my $converter = undef;
my $DEFAULT_IMAGES_RE  = qr@jpg|jpeg|gif|bmp|png@i;
my $DISABLED_FILES_RE = qr@pl|php|exe|cgi|bat|com|asp@i;

$NG::Field::VERSION = 0.1;


=head

   Специальные флаги, используемые в полях:
 
   field->{HIDE}=1         # Поле не выводится в форму, не принимаются значения из формы.    Ошибки из таких полей выносятся в глобальный контейнер ошибок.
   field->{IS_HIDDEN}=1    # Поле передается в форму как hidden поле (HIDE имеет приоритет). Ошибки из таких полей выносятся в глобальный контейнер ошибок.
   field->{IS_FAKEFIELD}=1 # Поле не является полем основной таблицы формы, флаг используется в операциях _load,_insert,_update для skip-а
   field->{NEED_LOAD_FOR_UPDATE} = 1 # Для произведения обновления значения поля или удаления записи требуется наличие его DBVALUE
=cut
 

sub new {
    my $class = shift;
    my $config = shift;
    my $parentobj = shift;

    $config || return $class->set_err("Отсутствует конфигурация создаваемого поля");
  	return $class->set_err("Конфигурация поля не является HASHREF (".(ref $config)) if ref $config ne "HASH";

    return $class->set_err("Не указан тип поля")  unless $config->{TYPE};
	return $class->set_err("Не указано имя поля") unless $config->{FIELD};

    my $classes = {
        fkselect		=> {CLASS=>"NG::Field::Select", },  #Устарело, используйте select
        select			=> {CLASS=>"NG::Field::Select", },
        radiobutton		=> {CLASS=>"NG::Field::Select", },
        multicheckbox	=> {CLASS=>"NG::Field::Multicheckbox"},
        multiselect		=> {CLASS=>"NG::Field::Multicheckbox"},
        multivalue		=> {CLASS=>"NG::Field::Multicheckbox"},
        mp3file			=> {CLASS=>"NG::Field::MP3File"},
        mp3properties   => {CLASS=>"NG::Field::MP3Properties"},
		turing			=> {CLASS=>"NG::Field::Turing"},
    };
    
    #Обратная совместимость. Следует использовать тип number, который был изначально, а не плодить типы втупую.
    $config->{TYPE} = "number" if $config->{TYPE} eq "float";
	
	if ($config->{TYPE} eq "fkparent") {
        if (!exists $config->{EDITABLE}) {
			my $options = {};
			$options = $config->{OPTIONS} if (exists $config->{OPTIONS});
			if (exists $options->{TABLE} || exists $options->{QUERY} || exists $config->{SELECT_OPTIONS}) {
				return $class->set_err("Указан источник данных, но отсутствует ключ EDITABLE");
			};
            $config->{TYPE}= "hidden";
        }
        elsif ($config->{EDITABLE}==1 || $config->{EDITABLE} eq "select") {
            $config->{TYPE}= "select";
        }
        elsif ($config->{EDITABLE} eq "radiobutton") {
            $config->{TYPE}= "radiobutton";
        }
        else {
            return $class->set_err("Параметр EDITABLE некорректен");
        };
    };
	
    my $type = $config->{TYPE};
    my $fieldclass = "NG::Field";
    
    if (exists $classes->{$type}) {
        $fieldclass = $classes->{$type}->{CLASS};
    };
    
    # если указан конкретный класс обработчик поля, то возмем его
    if (exists $config->{CLASS}) {
        $fieldclass = $config->{CLASS};
    }
    else {
        # если в конфиге есть информация о том что тип поля перекрыт\расширен, возмем этот класс
        my $extended_class = NG::Field->confParam('types', $type."_class");
        $fieldclass = $extended_class if $extended_class;
    };

	# Создаем поле другого класса
	if ($fieldclass && $fieldclass ne $class) {
		unless (UNIVERSAL::can($fieldclass,"can")) {
			eval "use $fieldclass";
			return $class->set_err($@) if ($@);
		};
		unless (UNIVERSAL::can($fieldclass,"new")) {
			return $class->set_err("Класс $fieldclass не содержит конструктора new().");
		};
		return $fieldclass->new($config,$parentobj);
	};
    	
    my $field = {};
	%{$field} = %{$config};
    
    bless $field, $class;
	$field->{_parentObj} = $parentobj;
	$field->{ERRORMSG} = "";
    $field->init(@_) or return undef;
	$field->setValue($config->{VALUE}) if (exists $config->{VALUE});
    return $field; 
};

sub init {
    my $field = shift;

    $field->{TEMPLATE} ||= $field->{_parentObj}->{_deffieldtemplate};    
    $field->{TEMPLATE} ||= "admin-side/common/fields.tmpl";
    
    $field->{_loaded} = 0;
	$field->{_changed} = 0;
    $field->{_new} = 0;
    
    $field->{OLDDBVALUE} = "";

    my $type = $field->{TYPE};
    
    my $hash = $field->{_errorTexts}->{""} = {};  # $hash->{$lang}->{$code}=$text;
    $hash->{NOT_UNIQUE}   = "Значение поля \"{n}\" не уникально";
    $hash->{INVALID_EMAIL}= "Адрес электронной почты некорректен";
    $hash->{INVALID_URL}  = "Некорректный URL";
    $hash->{INVALID_DATE} = "Неверный формат даты";
    $hash->{IS_EMPTY}     = "Не указано значение поля \"{n}\"";
    $hash->{MISSING_KEY}  = "Не указано значение ключевого поля {n}";
    $hash->{INVALID_INT}  = "Значение не является целым числом";
    $hash->{INVALID_NUMBER}="Значение не является числом";
    $hash->{INVALID_CIDR} = "Адрес или сеть указаны некорректно";
    $hash->{OUT_OF_RANGE} = "Значение находится вне допустимых пределов";
    $hash->{REGEXP_FORBIDDEN} = "Значение содержит недопустимые элементы";
    $hash->{VALUE_TOO_LONG}="Введенный текст слишком длинный ({size} символов при ограничении {limit})";
    
    $hash->{MISSING_FILE}            = "Не выбран файл";
    $hash->{EXTENSION_EXISTS}        = "Неверный формат файла *.{e}. Разрешаются только файлы без расширений.";
    $hash->{EXTENSION_NEEDED}        = "Неверный формат файла. Файлы без расширений запрещены.";
    $hash->{EXTENSION_FORBIDDEN}     = "Запрещенное расширение файла: *.{e}";
    $hash->{EXTENSIONLIST_FORBIDDEN} = "Запрещенное расширение файла: *.{e}. Расширения: {el} запрещены.";
    $hash->{EXTENSIONLIST_NEEDED}    = "Запрещенное расширение файла: *.{e}. Разрешается {el}.";

	if ($field->isFileField) {
		return $field->set_err("addfields(): UPLOADDIR value not specified for field ".$field->{FIELD}) unless exists $field->{UPLOADDIR};
        $field->{NEED_LOAD_FOR_UPDATE} = 1;
	};
    if ($type eq "id" || $type eq "hidden") {
        #TODO: Может быть имеет смысл отдельный тип IS_ID для визуальной отладки.
        $field->{IS_HIDDEN} = 1; 
    }
    elsif ($type eq "filter") {
        $field->{HIDE} = 1;
        #$field->{IS_HIDDEN} = 1;
    }
    elsif ($type eq "rtf") {
        $field->{IS_RTF} = 1;
    }
    elsif ($type eq "url") {
        $field->{IS_URL} = 1;
        $field->{LINK_PATTERN} = undef;
        $field->{LINK_URL} = "";
    }
    elsif ($type eq "rtffile") {
        return $field->set_err("Не указано значение опции FILEDIR для поля ".$field->{FIELD}) unless $field->options('FILEDIR');
        $field->{IS_RTF} = 1;
        $field->{NEED_LOAD_FOR_UPDATE} = 1;
    }
    elsif (($type eq "textfile")) {
        return $field->set_err("Не указано значение опции FILEDIR для поля ".$field->{FIELD}) unless $field->options('FILEDIR');
        $field->{IS_TEXTFILE} = 1;
        $field->{NEED_LOAD_FOR_UPDATE} = 1;
    }
    elsif ($type eq "checkbox") {
        if (!exists $field->{CB_VALUE}) { $field->{CB_VALUE} = 1; };
        $field->{IS_CHECKBOX} = 1;
    }
    elsif ($type eq "internal") {
         $field->{IS_INTERNAL} = 1; #внутренний тип. Не отображается в шаблоне
    }
    else {
        my $is_type = uc("IS_".$field->{TYPE});
        $field->{$is_type} = 1;  
    };
	return 1;
};

sub getProcessorClass {
    my $self = shift;
    
    # если указан конкретный класс, то возмем его
    return $self->{PROCESSOR} if exists $self->{PROCESSOR};
    
    # если в конфиге есть информация о том что тип поля перекрыт\расширен, возмем этот класс
    my $class = NG::Field->confParam('types', $self->{TYPE}."_processor");
    return $class if $class;
    
    return "NG::ImageProcessor" if ($self->{TYPE} eq "image");
    return "NG::FileProcessor" if ($self->isFileField());
    return "NG::TextProcessor";
};

sub afterLoad {
    return 1;
};

sub prepareOutput {
    #TODO: this
    return 1;
};

sub db {
    my $field = shift;
   
    unless ($field->{_db}) {
        my $parent = $field->parent() or return $field->showError("Отсутствует объект-родитель для получения db");
        return $field->set_err("Объект-родитель поля ".$field->{FIELD}. " не имеет метода db() ") unless $parent->can("db");    
        
        my $db = $parent->db();
        unless ($db->isa("NG::DBI")) {
            $field->set_err("Объект, возвращенный вызовом метода db() родителя в поле ".$field->{FIELD}. " не является NG::DBI")  ;
            $db = undef;
        };
        $field->{_db} = $db;
    };
    return $field->{_db};
};

sub dbh {
    my $field = shift;
    
    unless ($field->{_dbh}) {
        my $db = $field->db();
        $field->{_dbh} = $db->dbh() if $db;
    };
    return $field->{_dbh};
};

sub parent {
	my $field = shift;
    return $field->set_err("Для поля ".$field->{FIELD}. " не указан объект-родитель") if !$field->{_parentObj} || (ref $field->{_parentObj} eq "");
	return $field->{_parentObj};
};

sub setError {
	my $field = shift;
	my $errormsg = shift;
	my $mask     = shift;
    
    $errormsg =~ s/{n}/$field->{NAME}/;
    $errormsg =~ s/{f}/$field->{FIELD}/;
    
    if ($mask && ref $mask eq "HASH") {
        foreach my $key (keys %$mask) {
            my $v = $mask->{$key};
            $errormsg =~ s/{$key}/$v/;
        };
    };
    
    $errormsg ||= "";
warn "NG::Field($field->{FIELD})::setError(".ts($errormsg).")";
    $field->{ERRORMSG} = $errormsg;
	return 0;
};

sub set_err {
	my $self = shift;
	my $errstr = shift;
print STDERR "NG::Field(".(ref $self?$self->{FIELD}:"").")::set_err($errstr)\n";
	$NG::Field::errstr = $errstr;
	$self->{ERRORMSG} = $errstr if ref $self;
	return undef;
};

sub error { return shift->{ERRORMSG}; };
*ERROR = \&error;

sub hasError {
    my $field = shift;
    return 1 if $field->{ERRORMSG};
    return 0;
};

sub ajaxError {
	my ($s) = @_;
	{ name => $s->{FIELD}, type => $s->{TYPE}, err => $s->error };
}

sub showError {
    my $field = shift;
    my $defMsg = shift;
    
    $field->{ERRORMSG} ||= $defMsg;
    
    return 0;
};

sub _param {
	my $field = shift;
	my $href = shift;
	
	foreach my $key (keys %{$href}) {
		$field->{$key} = $href->{$key};
	}
	return 1;
}

sub param {
	my $field = shift;
	my $ref   = shift;
	
	if (!defined $ref) {
		#возвращаем все параметры в виде hashref
		my %tmp = %{$field};
		return \%tmp;
	};
	
	if (ref $ref eq "") {
		unshift(@_,$ref);
		if (scalar @_ == 1) {
			#запрос
			return $field->{$ref};
		}
		#elsif (scalar @_ % 2 == 0) {
		#}
		else {
			my %param = (@_);
			$field->_param(\%param) or return 0;
		};
	}
	elsif (ref $ref eq 'HASH') {
		$field->_param($ref) or return 0;
	}
	else {
		die "NG::Field::param(): incorrect method call";
	};
	return 1;
};

sub options {
    my $field = shift;
    my $param = shift;
    my $value = shift;
    $field->{OPTIONS} ||= {};
    return $field->{OPTIONS} unless $param;
    unless ($value) {
        return $field->{OPTIONS}->{$param} if exists $field->{OPTIONS}->{$param};
        return undef;
    };
    $field->{OPTIONS}->{$param} = $value;
};

sub isFileField {
	my $self = shift;
	my $type = $self->{TYPE};
	return 1 if ($type eq "file") || ($type eq "image");
	return 0;
}

sub type { return shift->{TYPE}; };

sub _setDBValue {
	my $self = shift;
	my $value = shift;
	
	$self->{DBVALUE} = $value;
	$self->{VALUE} = $value;
	
    if ($self->{TYPE} eq "date") {
        $self->{VALUE} = $self->db()->date_from_db($value);
    }
    elsif ($self->{TYPE} eq "checkbox") {
		$self->{CHECKED} = ($value eq $self->{CB_VALUE})?1:0;
    }
    elsif ($self->{TYPE} eq "datetime") {
        $self->{VALUE} = $self->db()->datetime_from_db($value);
    }
    elsif ($self->{TYPE} eq "inttimestamp") {
        use POSIX qw/strftime/;
        my $format = "%d.%m.%Y %T";
        $format = $self->{FORMAT} if exists $self->{FORMAT}; ## options->FORMAT ?
        $self->{VALUE} = strftime($format,localtime($value));
    }
    elsif ($self->{TYPE} eq "url") {
        my $link = parseBBlink($value);
        if (!defined $link) {
            $self->{LINK_URL} = $value;
        }
        else {
            $self->{LINK_URL} = $link->{HREF};
            $self->{LINK_PATTERN} = $link;
        };
    }
    elsif ($self->isFileField()) {
        $self->{VALUE} = $self->parent()->getDocRoot().$self->{UPLOADDIR}.$self->{VALUE} if ($self->{VALUE});
    }
	elsif ($self->{TYPE} eq "rtffile" || $self->{'TYPE'} eq "textfile") {
		return $self->setError("Can`t load data from file: OPTIONS.FILEDIR is not specified for \"".$self->{'TYPE'}."\" field \"$self->{FIELD}\".") if (is_empty($self->{OPTIONS}->{FILEDIR}));
		if ($value) {
			unless (-f $self->parent()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$value) {
				my ($v,$e) = saveValueToFile('',$self->parent()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$value);
				return $self->setError("Ошибка инициализации файла данных поля $self->{FIELD}: ".$e) unless defined $v;
				$self->{VALUE} = '';
				return 1;
			};
			my ($v,$e) = loadValueFromFile($self->parent()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$value);
            $self->{VALUE} = $v;
			return $self->setError("Ошибка чтения файла с данными поля $self->{FIELD}: ".$e) unless defined $v;
		}
	};
	return 1;
};

sub setDBValue {
=head
    Метод для настоящих джедаев. Джедай должен сам знать, 
    что будет происходить, если для загруженной данными формы вызывать setDBValue().
    
    Предназначение: Выставлять значение, которое должно быть записано в БД без изменений. 
                    В результате выполнения вызова производится обновление VALUE.
                    Выставленное DBVALUE может быть обработано методом process() поля
=cut
    my $self = shift;
    my $value = shift;
    
    my $ret = $self->_setDBValue($value,@_);
    if ($ret) {
        $self->{_changed}=1;
    };
    return $ret;
};

#
# Заполняет внутренние структуры данными, полученными из БД.
# Доступны все поля таблицы, полученные из БД.
# Перечень полей таблицы определяется возвратом вызовов dbFields() по всем полям формы.
#
sub setLoadedValue {
    my $self = shift;
    my $row  = shift;
    
    unless (exists $row->{$self->{FIELD}}) {
        return 1 if $self->{IS_FAKEFIELD};
        return $self->setError("setLoadedValue(): Отсутствуют данные для поля");
    };
    my $value = $row->{$self->{FIELD}};
    
    my $ret = $self->_setDBValue($value,@_);
    if ($ret) {
        $self->{OLDDBVALUE} = $value;
        $self->{_loaded}=1;
        $self->{_changed}=0;
    };
    return $ret;
};

sub _setValue {
	my $field = shift;
	my $value = shift;
	
	if ($field->{TYPE} eq "checkbox") {
		$field->{CHECKED}="";
		$value = 0 unless defined $value;
		if ($value ne $field->{CB_VALUE}) {
			$value = 0;
		}
		else {
			$field->{CHECKED}="checked";
		};
		$field->{VALUE} = $value;
	}
	elsif ($field->{TYPE} eq "date") {
		$field->{VALUE} = $value;
	}
	elsif ($field->{TYPE} eq "datetime") {
		$field->{VALUE} = $value;
	}
	elsif ($field->isFileField()) {
		if (!is_empty($value) && -e $value) {
			if (!$field->{TMP_FILENAME}) {
				($field->{TMP_FILENAME}) = $value =~ /([^\\\/]*)$/; 
			};
			$field->{VALUE} = $value;
		}
		else {
            $field->{VALUE} = "";
		};
	}
	elsif (($field->{TYPE} eq "number") || ($field->{TYPE} eq "int")) {
		$field->{VALUE} = $value;
        $field->{VALUE} = undef if defined $value && $value eq "";
	}
	else {
		$field->{VALUE} = $value;
	};
    return 1;
};

sub setValue {
    my $field = shift;
    $field->_setValue(@_) or return 0;
	$field->{_changed} = 1;
    return 1;
};

sub setDefaultValue {
	my $field = shift;
	$field->setValue($field->{DEFAULT}) if (exists $field->{DEFAULT});
};

sub _convert {
    $converter ||= $NG::Application::cms->getObject("Text::Iconv","utf-8","cp1251") or die "NG::Field::_convert(): can`t use Text::Iconv module";
    $converter->convert($_[0]);
};

sub setFormValue {
    my $field = shift;
    
    my $q = $field->parent()->q();
    
	my ($contentType, $is_utf8) = ($q->content_type()||"",0);

    $is_utf8++ if $contentType =~ /utf\-?8/i; # application/x-www-form-urlencoded; charset=UTF-8
    $is_utf8++ if $q->http('X-Requested-With') && $q->http('X-Requested-With') eq "XMLHttpRequest";
    
    my $value = ($is_utf8) ? _convert($q->param($field->{FIELD})) : $q->param($field->{FIELD});

    if ($field->{ESCAPE} && $field->{ESCAPE} eq "HTML") {
        $value = htmlspecialchars($value);
    };
    
    if ($field->isFileField()) {
        return 1 if is_empty($value);
        return 1 unless -e $value;
        $field->setTmpFile($q->tmpFileName($value),$value);
        return 1;
    };
#print STDERR $field->{FIELD}." - ".$value;
    $field->_setValue($value);
    $field->{_changed} = 1 unless $field->{READONLY};
};

sub setTmpFile {
    my $field = shift;
    my $tmpfile  = shift;
    my $filename = shift;  # Не обязательный. Если не указан, то имя сформируется из параметра вызова setValue($tmpfile)
    
    close($filename) if $filename && ref $filename;
    $filename =~ s/.*?([^\\\/]+)$/$1/ if $filename;
    
    $field->{TMP_FILENAME} = $filename; # Исходное имя файла.
    $field->{TMP_FILE} = $tmpfile;      # Эта переменная содержит только пути к временным файлам.
                                        # Если файл не временный, путь к нему содержится только в VALUE
    $field->setValue($tmpfile);
    $field->genNewFileName();
};

sub value {
	my $field = shift;
	return $field->{VALUE};
};
*VALUE = \&value;

sub REQUIRED {return shift->{IS_NOTNULL}; };
sub NAME {return shift->{NAME}; };

sub genNewFileName {
    my $field = shift;
    
    my $fname = $field->options("FILENAME_MASK");
    my $ext = "html";
    
    if ($field->isFileField()) {
        return undef if is_empty($field->{TMP_FILENAME});
        $ext = get_file_extension($field->{TMP_FILENAME}) || "";
        $field->{TMP_FILENAME} =~ /([^\\\/]+?)\.?$ext$/;
        my $ts = ts($1);
        $ts =~ s/[^a-zA-Z0-9]/_/gi;
        $fname ||= "{t}_{f}_{k}_{r}{e}";
        
        $fname =~ s@\{t\}@$ts@;
    }
    else {
        $fname ||= "{f}_{k}{e}";
    };
    
    my $p = $field->parent();
    
    my $fieldName = $field->{FIELD};
    $fname =~ s@\{f\}@$fieldName@;
    my $key = $p->getComposedKeyValue();
    $fname =~ s@\{k\}@$key@;
    my $rand = int(rand(9999));
    $fname =~ s@\{r\}@$rand@;
    $ext = ".".$ext if $ext;
    $fname =~ s@\{e\}@$ext@;
      
    while ($fname =~ /\{(.+?)\}/) {
        my $f = $p->getField($1) or die("Field $1 not found for FILENAME_MASK");
        my $value = $f->value();
        warn "NG::Field::dbValue(): no value for field $1 in FILENAME_MASK of field $fieldName" unless $value;
        $value = ts($value);
        $value =~ s/[^a-zA-Z0-9]/_/gi;
        $fname =~ s/\{.+?\}/$value/;
    };
    $field->{DBVALUE} = $fname;
};

#Возвращает список полей таблицы, необходимых для выполнения операции формой
#Операции:
# - load   - Загрузка значений
# - insert - Вставка новой записи в таблицу
# - update - Обновление записи в таблице
sub dbFields {
    my ($field,$action) = (shift,shift);
    return () if $field->{IS_FAKEFIELD};
    return ($field->{FIELD});
};

#Возвращает значение для сохранения в таблице / для использования в условиях запроса
#
# $dbField заполнен, если идет сохранение (insert/update) формы, в остальных случаях (а их достаточно) - undef
sub dbValue {
	my ($field,$dbField) = (shift,shift);
    die "Not implemented" if $dbField && $dbField ne $field->{FIELD};
    
	my $type = $field->type();

	if ($type eq "rtffile" || $type eq "textfile") {
		return $field->{DBVALUE} if exists($field->{DBVALUE});
		$field->genNewFileName();
	}
	elsif ($field->isFileField()){
		return $field->{DBVALUE};
	}
	elsif ($type eq "date") {
		$field->{DBVALUE} = $field->db()->date_to_db($field->{VALUE});
	}
	elsif ($type eq "datetime") {
		$field->{DBVALUE} = $field->db()->datetime_to_db($field->{VALUE});
	}
    elsif ($type eq "id") {
        die("Can`t find value for key field \"$field->{FIELD}\"") if !defined $field->{VALUE};
        $field->{DBVALUE} = $field->{VALUE};
    }
	else {
		$field->{DBVALUE} = $field->{VALUE};
	};
	return $field->{DBVALUE};
};

sub oldDBValue {
    my $field=shift;
    return $field->{'OLDDBVALUE'};
};

sub checkFileType {
    my $field = shift;
	
	my $size = 0;
	
	if ($field->{VALUE}) { $size = -s $field->{VALUE}; };
	
	if ($size == 0) {
		if (($field->{_new}==1) && ($field->{IS_NOTNULL}) && is_empty($field->{VALUE})) {
            return $field->setErrorByCode("MISSING_FILE");
		};
		return 1;
	};
    #TODO: нужно ли проверять ранее загруженные значения? для этого надо использовать _loaded
    return 1 if $field->{_loaded} && !$field->changed();
    
    my $filename = $field->{TMP_FILENAME};
    $filename ||= $1 if ($field->{VALUE} =~ /([^\\\/]*)$/); 

    my $ext = get_file_extension($filename);
    
    my $allowed_re = $field->options("ALLOWED_EXT");
    
    if (defined $allowed_re && !$allowed_re && $ext) {
        return $field->setErrorByCode("EXTENSION_EXISTS",{e=>$ext});
    };
    
    if ($field->type() eq "image") {
        $allowed_re ||= $DEFAULT_IMAGES_RE;
    };
    
    my $exts = "";
    if (ref $allowed_re eq "Regexp") {
        #
    }
    elsif (ref $allowed_re) {
        return $field->setError("Некорректное значение опции ALLOWED_EXT");
    }
    elsif ($allowed_re) {
        my @aext = split /\|/, $allowed_re;
        foreach (@aext) {
            $exts .= " *.$_" if $_ =~ /[a-zA-Z0-9_-]+/;
        };
        $allowed_re = qr@$allowed_re@i;
    };
    
    if ($allowed_re && $ext !~ $allowed_re) {
        if (!$ext) {
            #+Требуется расширение по списку if $exts
            #Требуется расширение
            if ($exts) {
                return $field->setErrorByCode("EXTENSIONLIST_NEEDED",{el=>$exts,e=>""});
            }
            else {
                return $field->setErrorByCode("EXTENSION_NEEDED");
            };
        }
        else {
            if ($exts) {
                return $field->setErrorByCode("EXTENSIONLIST_NEEDED",{el=>$exts,e=>$ext});
            }
            else {
                return $field->setErrorByCode("EXTENSION_FORBIDDEN",{e=>$ext});
            }
        };
    };
    
    my $disabled_re  = $field->options("DISABLED_EXT");
    
    if (defined $disabled_re && !$disabled_re && !$ext) {
        return $field->setErrorByCode("EXTENSION_NEEDED");
    };

    if (ref $disabled_re eq "Regexp") {
        #
    }
    elsif (ref $disabled_re) {
        return $field->setError("Некорректное значение опции DISABLED_EXT");
    }
    elsif ($disabled_re) {
        my @aext = split /\|/, $disabled_re;
        foreach (@aext) {
            $exts .= " *.$_" if $_ =~ /[a-zA-Z0-9_-]+/;
        };
        $disabled_re = qr@$disabled_re@i;
    };
    
    if ($disabled_re && $ext =~ $disabled_re) {
        if (!$ext) {
            return $field->setErrorByCode("EXTENSION_NEEDED");
        }
        elsif ($exts) {
            return $field->setErrorByCode("EXTENSIONLIST_FORBIDDEN",{el=>$exts,e=>$ext});
        }
        else {
            return $field->setErrorByCode("EXTENSION_FORBIDDEN",{e=>$ext});
        };
    };
    
    if ($ext =~ $DISABLED_FILES_RE) {
        return $field->setErrorByCode("EXTENSION_FORBIDDEN",{e=>$ext});
    };
    return 1;
};

=head TODO ?
sub getMessageByCode {
    my $field = shift;
    my $code  = shift;
    
    return "";
};
=cut

sub getErrorByCode {
    my $field = shift;
    my $code  = shift;
    
=comment
{f} - $field->{FIELD}
{n} - $field->{NAME}
    
--- файловая проверка
{e}  - extension
{el} - extension list

=cut
    my $form = $field->parent(); # Это может быть и Row
    my $lang = $form->getLang();
    
    my $text = $form->getFieldErrorText($field->{FIELD},$code);
    return $text if $text;
    
    my $hash = $field->{_errorTexts};
    return $hash->{$lang}->{$code} if exists $hash->{$lang} && exists $hash->{$lang}->{$code};
    return $hash->{""}->{$code} if exists $hash->{""} && exists $hash->{""}->{$code};

    $text = $field->getErrorByCode('UNKNOWN_ERROR_CODE') unless $code eq "UNKNOWN_ERROR_CODE";
    return $text if $code eq "UNKNOWN_ERROR_CODE";
    $text ||= "Unknown error code {code}";
    $text =~ s/{code}/$code/;
    return $text;
};

sub setErrorByCode {
    my $field = shift;
    my $code  = shift;
    my $mask  = shift;

    my $e = $field->getErrorByCode($code);
    return $field->setError($e,$mask);
};

sub pushErrorTexts {
    my $field = shift;
    my $hash = shift; #$hash->{$lang}->{$code} = $text or $hash->{$code} = $text
    
    return $field->setError("pushErrorTexts(): Hash parameter is not HASHREF") unless ref $hash eq "HASH";
    
    my $e = $field->{_errorTexts};
    
    my $m = 0;  # 1->with lang 2->w/o lang
    foreach my $key (keys %$hash) {
        my $s = $hash->{$key};
        if (ref $s eq "HASH") {
            #$key is $lang
            return $field->setError("pushErrorTexts(): Hash parameter contains mixed language definition style") if $m == 2;
            $m = 1;
            foreach my $code (keys %$s) {
                warn "pushErrorTexts(): error code $code is overriden in class ".(ref $field) if exists $e->{$key} && exists $e->{$key}->{$code};
                $e->{$key}->{$code} = $s->{$code};
            };
        }
        else {
            #$key is $code
            return $field->setError("pushErrorTexts(): Hash parameter contains mixed language definition style") if $m == 1;
            $m = 2;
            warn "pushErrorTexts(): error code $key is overriden in class ".(ref $field) if exists $e->{""} && exists $e->{""}->{$key};
            $field->{_errorTexts}->{""}->{$key} = $s;
        };
    };
    return 1;
};

sub check {
    my $field = shift;
    
    my $type  = $field->{TYPE};
    my $value = $field->{VALUE};

    if ($field->isFileField()) {
        return $field->checkFileType();
    };
        
    #TODO: а вдруг мы захотим проверять уникальность числа пробелов в строке ?
    if (($field->{UNIQUE}) && !is_empty($field->dbValue())) {
        my $dbh = $field->dbh() or return $field->showError("check(): Отсутствует значение dbh");
        my $parent = $field->parent() or return $field->showError("check(): Отсутствует значение parent()");
        my $table = $parent->{_table} or return $field->setError("Отсутствует имя таблицы для проверки уникальности");
        
        return $field->showError("check(): У объекта-родителя отсутствует метод fields()") unless $parent->can("fields");
        my $fields = $parent->fields();
        return $field->showError("check(): Метод fields() родителя вернул не ARRAYREF") unless ref $fields eq "ARRAY";

        my $keyWhere = "";
        my @keyValues = ();
        foreach my $tmpfield (@{$fields}) {
            next unless $tmpfield->type() eq "id";
            
            return $field->setError("При проверке уникальности {f} не найдено значение ключевого поля ".$tmpfield->{FIELD}) if (is_empty($tmpfield->{VALUE}));
            
            $keyWhere .=  $tmpfield->{FIELD}."<>? and";
            push @keyValues, $tmpfield->dbValue();
        };
        unless ($keyWhere) {
            return $field->setError("При проверке уникальности значения поля \"{n}\" не найдены ключевые поля");
        };
        $keyWhere =~ s/and$//;

        my $sameWhere  = "";
        my @sameValues  = ();
        my $parentFieldsList = (ref $field->{UNIQUE} eq "ARRAY")?$field->{UNIQUE}:[];
        foreach my $pfName (@{$parentFieldsList}) {
            my $tmpfield = $parent->getField($pfName) or return $field->setError("Поле $pfName, описанное в опции UNIQUE, не найдено");
            return $field->setError("Недопустимо использовать ключевые поля в опции UNIQUE") if ($tmpfield->type() eq "id");
            #TODO: is_empty() проверяет value() а в запросе участвует dbValue()
            return $field->setError("При проверке уникальности не найдено значение поля \"$tmpfield->{FIELD}\"") if(is_empty($tmpfield->value()));
            $sameWhere .=  $tmpfield->{FIELD}."=? and ";
            push @sameValues, $tmpfield->dbValue();
        };
        $sameWhere .= $field->{FIELD}."=?";
        push @sameValues, $field->dbValue();
        
        my $sth = $dbh->prepare("select ".$field->{FIELD}." from $table where ($keyWhere) and ($sameWhere)") or return $field->setError($DBI::errstr);
        $sth->execute(@keyValues,@sameValues) or return $field->setError($DBI::errstr);
        my $row = $sth->fetchrow_hashref();
        $sth->finish();
        return $field->setErrorByCode("NOT_UNIQUE") if ($row);
    };

    #Потому что фильтр невидим. Фильтр - программное поле.
    die "Не указано значение поля \"".$field->{FIELD}."\" типа filter" if (($type eq "filter") && is_empty($value));
    
    if (($type eq "id") && !is_valid_id($value)) {
        return $field->setErrorByCode("MISSING_KEY");
    };
       
    if (($type eq "email") && ($value) && (!is_valid_email($value)))  {
        return $field->setErrorByCode("INVALID_EMAIL");
    };
        
    if ($field->{IS_NOTNULL} && is_empty($value)) {
        return $field->setErrorByCode("IS_EMPTY");
    };
		
    if ($type eq "url" && !is_empty($value)){
        if (is_valid_link($value)){
            return 1;
        }
        elsif (my $ret = parseBBlink($value)) { #"
            return $field->setErrorByCode("INVALID_URL") if (!is_valid_link($ret->{HREF}));
        }
        else {
            return $field->setErrorByCode("INVALID_URL");
        };
    };
    
    if ($type eq "date" && !is_empty($value) && !is_valid_date($value)) {
        return $field->setErrorByCode("INVALID_DATE");
    };
    
    if ($type eq "datetime" && !is_empty($value) && !is_valid_datetime($value)) {
        return $field->setErrorByCode("INVALID_DATE");
    };
    
    if ($type eq "int" && $value && !is_int($value)) {
        return $field->setErrorByCode("INVALID_INT");
    };
    if ($type eq "number" && $value && !is_float($value)) {
        return $field->setErrorByCode("INVALID_NUMBER");
    };
    if (($type eq "number" || $type eq "int") && defined $value && ((exists $field->{MIN} && $value < $field->{MIN}) || (exists $field->{MAX} && $value > $field->{MAX}))) {
        return $field->setErrorByCode("OUT_OF_RANGE");
    }; 
    if ($type eq "cidr" && $value && !is_valid_cidr($value)) {
        return $field->setErrorByCode("INVALID_CIDR");
    };
    if ($value && $field->{OPTIONS}->{REGEXP}) {
        my $re = $field->{OPTIONS}->{REGEXP};
        return $field->setError("Некорректное значение опции REGEXP") unless ref $re eq "Regexp";
        if ($value !~ $re ) {
            return $field->setError($field->{OPTIONS}->{REGEXP_MESSAGE});
            return $field->setErrorByCode("REGEXP_FORBIDDEN");
        };
    };
    if ($value && exists $field->{LENGTH} && $type =~ /^((?:rtf|text)(?:file)?|textarea)?$/ && length($value) > $field->{LENGTH}) {
        return $field->setErrorByCode("VALUE_TOO_LONG", {size=>length($value),limit=>$field->{LENGTH}});
    }
    return 1;
};

sub getChilds {
    my $self = shift;
    
    return [] unless exists $self->{CHILDS};
    NG::Exception->throw('NG.INTERNALERROR','Параметр CHILDS не является ссылкой на массив') unless ref $self->{CHILDS} eq "ARRAY";
    
    my $childs = [];
    foreach my $ch (@{$self->{CHILDS}}) {
        if (ref $ch eq "HASH") {
            NG::Exception->throw('NG.INTERNALERROR','Отсутствует параметр FIELD в описании подчиненного поля') unless exists $ch->{FIELD};
            push @{$childs}, $ch;
        }
        else {
            push @{$childs},{FIELD=>$ch};
        };
    };
    return $childs;
};

sub processChilds {
    my $self = shift;
   
    my $defConvMethod = "_setValueFromField";
   	my $convMethods = {
#	   "image_image" => "_setFileValueFromField",
#	   "file_image" => "_setFileValueFromField",
#	   "image_file" => "_setFileValueFromField",
#	   "file_file" => "_setFileValueFromField",
    };

    return 1 unless exists $self->{CHILDS};
    
    my $childs = $self->getChilds();
    return $self->showError() unless $childs;
    
    foreach my $ch (@{$childs}) {
        my $convMethod;
        $convMethod = $ch->{METHOD} if exists $ch->{METHOD};
        my $chName = $ch->{FIELD};
        
        my $child = $self->parent()->getField($chName) or NG::Exception->throw('NG.INTERNALERROR', "Подчиненное поле $chName не найдено");
        
        #Ищем подходящий метод конвертации поля в поле
        $convMethod ||= $convMethods->{$self->type()."_".$child->type()} if exists $convMethods->{$self->type()."_".$child->type()};
        $convMethod ||= $defConvMethod;
        
        NG::Exception->throw('NG.INTERNALERROR', "Класс ".ref($child)." поля ".$child->{FIELD}." не содержит метода ".$convMethod." для копирования данных из поля ".$self."(".ref($self).")") unless $child->can($convMethod);
        
        $child->$convMethod($self,$ch) or NG::Exception->throw('NG.INTERNALERROR',"Ошибка выставления значения из ".$self->{FIELD}." подчиненному полю ".$child->{FIELD}." :".$child->error());
    };
    return 1;
};

=head
    #Example 1.  Простейшая конфигурация, две картинки из одной
    
    {FIELD=>'smallimage', TYPE=>'image',    NAME=>'Изображение',UPLOADDIR=>"/some/dir", IS_NOTNULL=>1,
        OPTIONS=>{WIDTH=>120,METHOD=>"towidth"},
        CHILDS=> [{FIELD=>"bigimage"}],
    },
    {FIELD=>'bigimage',   TYPE=>'image',    NAME=>'Изображение',UPLOADDIR=>"/some/dir", HIDE=>1,
        OPTIONS=>{WIDTH=>400,METHOD=>"towidth"}
    },
    
    1. Форма выставит значение только в smallimage, поскольку bigimage имеет параметр HIDE=>1
    2. Произойдет копирование пути временного файла в поле bigimage (временные файлы удаляются после окончания процессов сохранения)
       отработает стандартный копировщик полей друг в друга в методе processChilds (метод вызывается у объекта поля чайлд, с параметром "родитель")
    3. Вызовутся методы полей beforeSave. Для полей типа image это приведет к процедуре пережатия с параметром OPTIONS.METHOD, произойдет пережатие
       временного файла в целевые файлы нужного размера
    4. произойдет сохранение данных формы в БД
    
    #Example 2. Сохраняем размер исходной картинки
    {FIELD=>'image',   TYPE=>'image',  NAME=>'Изображение',UPLOADDIR=>"/some/dir",
        CHILDS=> [
            {FIELD=>"imgsize", METHOD=>"imgSize"},
            {FIELD=>"filesize", METHOD=>"fileSize"},
        ],
        OPTIONS=>{WIDTH=>400,METHOD=>"towidth"}
    },
    {FIELD=>'imgsize',  TYPE=>'text',  NAME=>'Исходный размер', HIDE=>1, CLASS=>"NG::CoolField"
    },
    
    Производится сохранение оригинальных размеров картинки и размера оригинального файла,
    поскольку методы beforeSave выполняются после методов PROCESS
    
    1. Форма выставит значение только в image, поскольку imgsize имеет параметр HIDE=>1
    2. У поля imgsize произойдет вызов метода imgSize с параметром поля-родителя. Класс NG::CoolField должен обладать достаточным интеллектом, чтобы
       суметь скопировать размер изображения из поля-родителя. В перспективе возможна организация совместного использования объекта Image::Magick
       родительского поля для получения требуемых данных в объектах - потомках.
    3. Вызовутся методы полей beforeSave. Для полей типа image это приведет к процедуре пережатия с параметром OPTIONS.METHOD, произойдет пережатие
       временного файла в целевые файлы нужного размера.
    4. произойдет сохранение данных формы в БД 

    #Example 3. Сохраняем размеры оригинальной
    {FIELD=>'image',   TYPE=>'image',  NAME=>'Изображение',UPLOADDIR=>"/some/dir", EARLY_PROCESS=>1,
        CHILDS=> [
            {FIELD=>"imgsize", METHOD=>"imgSize"},
            {FIELD=>"filesize", METHOD=>"fileSize"},
        ],
        OPTIONS=>{WIDTH=>400,METHOD=>"towidth"}
    },
    {FIELD=>'proxy',  TYPE=>'image'}
    {FIELD=>'imgsize',  TYPE=>'text',  NAME=>'Исходный размер', HIDE=>1, CLASS=>"NG::CoolField"
    },
   
    # ЭТО НЕ РЕАЛИЗОВАНО.  

=cut

sub _setValueFromField {
    my $self = shift;
    my $parent = shift;
    
    if ($self->isFileField()) {
        return $self->setError("Поле-родитель ".$parent->{FIELD}." не является файловым полем") unless ($parent->isFileField());
        $self->{TMP_FILENAME} = $parent->{TMP_FILENAME};
        $self->genNewFileName();
        my $v = $parent->value();
        unless ($v) {
            $self->clean();
        }
        else {
            $self->setValue($v);
        };
        return 1;
    };
    
    $self->setValue($parent->value());
    return 1;
};

## Обработка перед сохранением
sub process {
    my $self = shift;
    
    my $options = $self->{OPTIONS};
    return 1 unless $options && ($options->{STEPS} || $options->{METHOD});

	my $oldDbV = $self->{OLDDBVALUE};
	my $newDbV = $self->dbValue();

    return 1 if ($oldDbV && $oldDbV eq $newDbV); 
    
    my $procClass = $self->getProcessorClass() or return $self->showError("Ошибка вызова метода getProcessorClass(). Метод не возвратил текст ошибки.");
    
    my $cms = $self->cms();
    my $pCtrl = $cms->getObject("NG::Controller",{
        PCLASS  => $procClass,
        STEPS   => $options->{STEPS} || [{METHOD=>$options->{METHOD},PARAMS=>$options->{PARAMS}}],
        FIELD   => $self,
        FORM    => $self->parent(),
    });
    
    if ($self->isFileField()) {
        my $source = $self->value();
        my $newDBV = $self->dbValue();
        my $dest = $self->parent()->getDocRoot().$self->{UPLOADDIR}.$newDBV;
        eval { mkpath($self->parent()->getDocRoot().$self->{UPLOADDIR}); };
        if ($@) {
            $@ =~ /(.*)at/s;
            return $self->setError("Ошибка при создании директории: $1");
        };
        
        $pCtrl->process($source);
        $pCtrl->saveResult($dest);
        $self->setDBValue($newDBV);
    }
    else {
        my $value = $self->value();
        $pCtrl->process($value);
        $self->setValue($pCtrl->getResult());
    };
    return 1;
};

#Возвращает признак, было ли изменено значение поля таблицы
#Вызывается без $dbField для определения необходимости вызова методов processChilds(), process(), clean()
sub changed {
    my ($field,$dbField) = (shift,shift);
    die "Not implemented" if $dbField && $dbField ne $field->{FIELD};

    return 1 if $field->{_changed};
    return 0;
};

sub beforeSave {
    my $self = shift;
    my $action = shift;
    
    if ($self->isFileField()) {
        return $self->setError("Предыдущее значение поля не загружено, замещаемый файл не будет удален") unless $self->{_loaded} || ($action eq "insert");
        return $self->setError("Не указано значение опции UPLOADDIR для поля ".$self->{FIELD}) unless $self->{UPLOADDIR};

        my $uplDir = $self->parent()->getDocRoot().$self->{UPLOADDIR};
        my $oldDbV = $self->{OLDDBVALUE};
        my $newDbV = $self->dbValue();
        my $target = $uplDir.$newDbV;

        my $file = $self->value();
        if ($file && $file ne $target) {
            my $targetDir = $target;
            $targetDir=~s@[^\/]+$@@; #вырезаем текст после последнего слеша

            eval { mkpath($targetDir); };
            if ($@) {
                $@ =~ /(.*)at/s;
                return $self->setError("Ошибка при создании директории: $1");
            };

            move($file,$target) or return $self->setError("Ошибка копирования файла: ".$!);
            $self->setDBValue($newDbV);
            $self->{TMP_FILE} = "";

            my $mask = umask();
            $mask = 0777 &~ $mask;
            chmod $mask, $target;
        };

        $self->_unlink($oldDbV) if ($oldDbV && $oldDbV ne $newDbV);
    }
    elsif ($self->{TYPE} eq "rtffile" || $self->{'TYPE'} eq "textfile") {
        my $dbv = $self->dbValue();
        return $self->setError("Отсутствует имя файла для сохранения данных поля ".$self->{FIELD}." типа ".$self->{'TYPE'}) unless $dbv;
        my ($v,$e) = saveValueToFile($self->{VALUE},$self->parent()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$dbv);
        return $self->setError("Ошибка сохранения данных поля $self->{FIELD}: ".$e) unless defined $v;
    };
    return 1;
};

sub afterSave {
    my $self = shift;
    return 1;
};

sub beforeDelete {
    my $field = shift;
    
    my $type = $field->{TYPE};
    if ($field->isFileField()) {
        return $field->setError("Не указано значение опции UPLOADDIR для поля ".$field->{FIELD}) unless $field->{UPLOADDIR};
        return $field->setError("Значение файлового поля не загружено") unless $field->{_loaded};
        my $dbv = $field->dbValue();
        $field->_unlink($dbv) if $dbv;
    };
    if ($type eq "rtffile" || $type eq "textfile") {
        my $filedir = $field->options('FILEDIR') or return $field->setError("Не указана опции FILEDIR");
        return $field->setError("Значение файлового поля не загружено") unless $field->{_loaded};
        my $dbv = $field->dbValue();           
        unlink $field->parent()->getSiteRoot().$filedir.$dbv if $dbv;
    };
    if ($type eq "rtf" || $type eq "rtffile") {
        #Удаление прикрепленных картинок
        my $options = $field->{OPTIONS};
        next unless $options->{IMG_TABLE}; #Если IMG_TABLE не указано, считаем что заливки картинок с сохранением инфы не производилось
        return $field->setError("Не указано значение опции IMG_UPLOADDIR") unless $options->{IMG_UPLOADDIR};
        
        my @params = ();
        my @fields = ();
        my $form = $field->parent();
        my $fieldsMap = $options->{IMG_TABLE_FIELDS_MAP} || {};

        #TODO: переделать обращение к ключевым полям формы
        foreach my $tmpfield (@{$form->{_keyfields}}) {
            my $name = $tmpfield->{FIELD};
            $name = $fieldsMap->{$name} if exists $fieldsMap->{$name};
            next unless $name;
            push @params, $tmpfield->{VALUE};
            push @fields, $name;
        };
    
        foreach my $key (keys %{$options->{IMG_TABLE_EXTRAKEY}}) {
            push @params, $options->{IMG_TABLE_EXTRAKEY}->{$key};
            push @fields, $key;
        };
    
        return $field->setError("Не найдены ключевые поля привязки картинок к удаляемой записи") unless scalar @fields;
        $options->{IMG_TABLE_FILENAME_FIELD} ||= "filename"; #TODO: вынести подобные блоки в одно место 
        my $sql = "select ".$options->{IMG_TABLE_FILENAME_FIELD}." from ".$options->{IMG_TABLE}." where ".join("=? and ",@fields)."=?";
    
        my $sth = $field->dbh()->prepare($sql) or return $field->setError($DBI::errstr);
        $sth->execute(@params) or return $field->setError($DBI::errstr);
        while (my ($filename) = $sth->fetchrow()) {
            unlink $form->getDocRoot().$options->{IMG_UPLOADDIR}.$filename;
        };
        $sth->finish();
        $field->dbh()->do("delete from ".$options->{IMG_TABLE}." where ".join("=? and ",@fields)."=?",undef,@params) or return $field->setError($DBI::errstr);
    };
    return 1;
};

sub getJSSetValue {
    my $field = shift;

    if (($field->{TYPE} eq "id") || ($field->{TYPE} eq "filter") || ($field->{TYPE} eq "file") ||($field->{TYPE} eq "image") ||($field->{TYPE} eq "checkbox")) {
        return ""; #TODO: реализовать корректное выставление значений
    };
    
    my $fd = $field->{FIELD};
    my $value = escape_js $field->{VALUE};
    my $key_value = $field->parent()->getComposedKeyValue();
    $value = "" unless defined $value;
    return "parent.document.getElementById('$fd$key_value').value='$value';\n";
};

sub getJSShowError {
    my $field = shift;
    my $key_value = $field->parent()->getComposedKeyValue();
    my $fd = $field->{FIELD};
    my $em = escape_js $field->error();
    
    if (($field->{TYPE} eq "id") || $field->{TYPE} eq "hidden" || ($field->{TYPE} eq "filter") || ($field->{HIDE})) {
        return (undef,$em);
    };
    
    my $error = "";
    if ($em) {
        $error .= "parent.document.getElementById('error_$fd$key_value').innerHTML='$em';";
        $error .= "parent.document.getElementById('error_$fd$key_value').style.display='block';\n";
    }
    else {
        $error .= "parent.document.getElementById('error_$fd$key_value').innerHTML='';";
        $error .= "parent.document.getElementById('error_$fd$key_value').style.display='none';\n";
    };
    return $error;
};

sub _unlink {
    my ($field,$dbValue) = (shift,shift);
    
    die "Missing UPLOADDIR" unless $field->{UPLOADDIR};
    die "Missing DBValue" unless $dbValue;
    
    if ($field->{TYPE} eq 'image' && $field->{OPTIONS}->{IMGRESIZER}) {
        my $resizer = $field->{OPTIONS}->{IMGRESIZER};
        
        if ($resizer =~ /^([^\/]+)(\/\S+\/\S+)?$/) {
            my $module = $field->cms()->getModuleInstance($1);
            $module->deleteFromCache($field->{UPLOADDIR},$dbValue);
        }
        else {
            die "Wrong IMGRESIZER option";
        };
    };
    
    unlink $field->parent()->getDocRoot().$field->{UPLOADDIR}.$dbValue;
};

sub clean {
    my $self = shift;
    
    my $oldDbV = $self->{OLDDBVALUE};
	my $newDbV = $self->dbValue();

	if ($self->isFileField()) {
        die "TODO: fix this UPLOADDIR" unless exists $self->{UPLOADDIR};
        $self->_unlink($oldDbV) if $oldDbV;
        delete $self->{DBVALUE};
    };
    $self->setValue("");
};


sub ASHASH {
  my $self = shift;
  my %h = %{$self};
  return \%h;
}

#Возвращает HTML, выводимый в лист
sub getListCellHTML {
    my $field = shift;
    
    my ($type,$fName) = ($field->{TYPE},$field->{FIELD});
    
    if ($type eq 'image') {
        my $link = "";
        if ($field->{DBVALUE}) {
            my $resizer = $field->{OPTIONS}->{IMGRESIZER};
            if ($resizer && $resizer =~ /^(\S+)\/(\S+)\/(\S+)$/) {
                my ($code,$group,$size) = ($1,$2,$3);
                
                my $module = $field->cms()->getModuleInstance($code);
                $link = $module->getBaseURL() or return "[ERROR]";
                $link .= "$group/$size/".$field->{DBVALUE};
            }
            else {
                $link = $field->{UPLOADDIR}.$field->{DBVALUE};
            };
        }
        
        return "<div><img src='$link'></div>" if $link;
        return '';
    }
    elsif ($type eq 'checkbox') {
        my ($clickable,$checked) = ('','');
        $clickable = 'clickable' if $field->{CLICKABLE};
        $checked   = 'checked'   if $field->{VALUE};
        
        my $parent = $field->parent();
        my $id     = $parent->{ID_VALUE};
        
        return "<center>"
        ."<div class='list-checkbox $clickable $checked' data-field='$fName' data-id='$id'></div>"
        ."</center>";
    }
    elsif ($field->isFileField) {
        my $link = "";
        $link = $field->{UPLOADDIR}.$field->{DBVALUE} if $field->{DBVALUE};
        
        return "<a href='$link'>Загружен</a>" if $link;
        return 'Отсутствует';
    }
    else {
        my ($url,$title) = ($field->{URLMASK},$field->{TITLE});
        
        if ($url) {
            my $parent  = $field->parent();
            my $baseurl = $parent->list()->getBaseURL();
            my $row     = $parent->{ROW};
            $url =~ s@{baseurl}@$baseurl@;
			$url =~ s/\{(.+?)\}/$row->{$1}/gi;
        };
        
        my $ret = '';
        $ret .= $url?"<a href='$url' title='$title'>":'<p>';
        $ret .= $field->{VALUE};
        $ret .= $url?"</a>":'</p>';
        return $ret;
    }
};

sub getFieldActions {
    my $self = shift;
    
=head
   Возвращаемое значение: массив хэшей, каждый хэш содержит параметры:
   ACTION - имя экшна, которое использовано в шаблоне поля в виде FIELD_ACTION
   METHOD - имя метода класса поля, который требуется вызвать
   NEED_LOAD_FOR_UPDATE - необязательное поле, переопределяющее
                          флаг NEED_LOAD_FOR_UPDATE поля в случае
                          обработки данного экшна (НЕ РЕАЛИЗОВАНО, ЗАГРУЗКА ДАННЫХ ПЕРЕД ВЫПОЛНЕНИЕМ ЭКШНА НЕ ПРОИЗВОДИТСЯ)
=cut
    
    if ($self->{TYPE} eq "rtf" || $self->{TYPE} eq "rtffile") {
        return [
            {ACTION=>"uploadimage", METHOD=>"uploadRtfImage",NEED_LOAD_FOR_UPDATE=>0},
        ];
    }
    elsif ($self->isFileField()) {
        return [
            {ACTION=>"deletefile", METHOD=>"deleteFile"},
        ];
    }
    else {
        return [];
    };
};

sub uploadRtfImage {
    my $field = shift;
    my $is_ajax = shift;

    return $field->setError("Требуемое поле не является полем типа rtf или rtffile.") unless ($field->{TYPE} eq "rtf" || $field->{TYPE} eq "rtffile");
    return $field->setError("uploadRtfImage() может вызываться только как ajax-метод.") unless $is_ajax;

    eval "use NG::RtfImage 0.4;";
    my $options = $field->{OPTIONS} or return NG::RtfImage->getErrorJS("Не найден параметр OPTIONS");
    my $uploaddir = $options->{IMG_UPLOADDIR} or return NG::RtfImage->getErrorJS("Не указана опция IMG_UPLOADDIR");
    
    ## производим подстановку параметров {} в IMG_UPLOADDIR
    
    #TODO: Добавить проверку наличия записи с указанными ключевыми полями
    #хмм. такой записи может не быть, поскольку заливается картинка к еще не вставленной записи.
    #Вариант: Запретить заливку картинок к еще не созданным записям. 
    
    my $keyMap = {};
    my $form = $field->parent();
    #TODO: переделать обращение к ключевым полям формы
    foreach my $field (@{$form->{_keyfields}}) {
        return $field->setError("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
        return NG::RtfImage->getErrorJS("Не найдено значение ключевого поля $field->{FIELD}") if (is_empty($field->{VALUE}));
        $keyMap->{$field->{FIELD}} = $field->{VALUE};
    };
    $uploaddir =~ s/\{(.+?)\}/$keyMap->{$1}/gi;

    my $RI = NG::RtfImage->new(
        CGIObject=>$form->q(),
        DOCROOT=>$form->{_docroot},
        SUBDIR=>$uploaddir,                           ## Не обязательный, но часто используемый, параметр.
        FIELDNAME=>'userfile',                        ## Не обязательный параметр.
    );

    if ($RI->moveUploadedFile()) {                    ## Метод перемещения залитого файла, внутри проверяет тип файла
        if (!is_empty $options->{IMG_TABLE}) {
            my $idField       = $options->{IMG_TABLE_ID_FIELD}       || "id";
            my $filenameField = $options->{IMG_TABLE_FILENAME_FIELD} || "filename";
            my $file_name = $RI->filename();
	    
			my $id = $field->db()->get_id($options->{IMG_TABLE});
			return $RI->getErrorJS("Ошибка внесения записи в БД: ".$field->db()->errstr()) unless $id;
            my @params = ();
            my $sql = "insert into ".$options->{IMG_TABLE}." ($idField,$filenameField";
            my $fieldsMap = $options->{IMG_TABLE_FIELDS_MAP} || {};
            #TODO: Реализовать проверку, чтобы все ключи из fieldsMap были использованы
            foreach my $name ( keys %{$keyMap} ) {
                my $name1 = $name;
                $name1 = $fieldsMap->{$name} if exists $fieldsMap->{$name};
                next unless $name1;
                $sql .= ",".$name1;
                push @params, $keyMap->{$name};
            };
            
            foreach my $key (keys %{$options->{IMG_TABLE_EXTRAKEY}}) {
                $sql .= ",".$key;
                push @params, $options->{IMG_TABLE_EXTRAKEY}->{$key};
            };
            return $RI->getErrorJS("Не найдены ключевые поля привязки загружаемой картинки к записи") unless scalar @params;
            
            $sql .= ") values (?,?";
            $sql .= ",?" x scalar(@params);
            $sql .= ")";
            
            unshift @params, $file_name;
            unshift @params, $id;
            
            $field->dbh()->do($sql,undef,@params) or return $RI->getErrorJS("Ошибка внесения записи в БД: ($sql) ".$DBI::errstr);
        };
        return $RI->getFileNameJS();
    }
    else {
        $RI->cleanUploadedFile();           ## Очищаем временный файл
        return $RI->getErrorJS();           ## Сообщаем об ошибке.
    };
};

sub deleteFile {
    my $field = shift;
    my $is_ajax = shift;
    
    my $ret = eval {
        my $ret = $field->parent()->cleanField($field);
    };
    if (my $exc = $@) {
        my $excMsg  = "";
        if (NG::Exception->caught($exc)) {
            my $excCode = $exc->code();
            $excMsg  = $exc->message()." (".$excCode.")";
        }
        elsif (ref $exc){
            $excMsg = "Неизвестное исключение класса ".(ref $exc);
        }
        else {
            $excMsg = $exc;
        };
        return $field->error($excMsg);
    };
    
    if ($ret && $is_ajax) {
        return "<!-- -->"; #STUB
    };
    return $ret;
};

return 1;
END{};
