package NG::Form;

use strict;
use Carp;
use NHtml;
use NSecure;
use NGService;
use NG::Field;

$NG::Form::VERSION = 0.4;

sub new {
	my $class = shift;
	my $self = {};

	bless $self, $class;
	$self->{_ajax} = 0;
	$self->{_fields} = [];
    $self->{_keyfields} = [];       # Массив ключевых полей формы
    $self->{_buttons} = undef;      # Массив кнопок формы
	$self->{_container}="";
	$self->{_new} = 0;
	$self->{_ref} = "";   			# URL куда возвращаться после обработки формы
	
	$self->{_table} = undef;
	$self->{_docroot} = undef;
    
    $self->{_prefix} = "";          # Идентификатор формы в случае многовариантности-многоформенности
	
	$self->{_error} = "";  ## Ошибки в ходе выполнения методов формы
    
    $self->{_lang} = "";            # Текущий язык формы
    $self->{_ferrors} = {};         # Переводы сообщений об ошибках для полей, с указанием поля ( $hash->{$lang}->{$field}->{$code} = $value )
    $self->{_aferrors} = {};        # Переводы сообщений об ошибках для всех полей              ( $hash->{$lang}->{$code} = $value )
    $self->{_flangparams} = {};     # Языковые варианты параметров полей                        ( $hash->{$lang}->{$field}->{$param} = $value )

	return $self->init(@_);
}

sub init {
	my $self=shift;
	my %ref = (@_);
    
    $self->{_title} = "";
	
	if ( exists $ref{FORM_URL} )    { $self->{_form_url}  = $ref{FORM_URL};      };
	if ( exists $ref{CONTAINER} )   { $self->{_container} = $ref{CONTAINER};     };
	if ( exists $ref{REF} )         { $self->{_ref}       = $ref{REF};           };
    if ( exists $ref{IS_AJAX} )     { $self->{_ajax}      = $ref{IS_AJAX};       };
    if ( exists $ref{PREFIX} )      { $self->{_prefix}    = $ref{PREFIX};        };
    if ( exists $ref{DEFFIELDTEMPLATE}) { $self->{_deffieldtemplate} = $ref{DEFFIELDTEMPLATE}; };
    if ( exists $ref{LANG})         { $self->{_lang}      = $ref{LANG};          };
    if ( exists $ref{NAME})         { $self->{_name}      = $ref{NAME};          };
	if (!exists $ref{DOCROOT} ) 	{ die "NG::Form::init(): DOCROOT parameter is missing"; };
	$self->{_docroot} = $ref{DOCROOT};

	$self->{_siteroot} = $ref{SITEROOT};
	

    $self->{_table} = $ref{TABLE};
    $self->{_owner} = $ref{OWNER};
    
    $self->{_structure} = undef;
    
	return $self;
}

sub prefix { return shift->{_prefix};};
sub title { return shift->{_title};  };
sub table { return shift->{_table};  };
sub owner { return shift->{_owner};  };

#sub setLang { shift->{_lang} = shift;};
sub getLang { return shift->{_lang}; };

sub setFieldsErrorText {
    my $form = shift;
    my $hash = shift;  #$hash->{$lang}->{$field}->{$code} = $value;
    
    return $form->error("setFieldsErrorText(): param is not HASHREF") unless ref($hash) eq "HASH";
    return $form->error("setFieldsErrorText(): default lang is not supported") if exists $hash->{""};
    return $form->error("setFieldsErrorText(): form constructor has no lang specified") unless $form->{_lang};
    
    $form->{_ferrors} = $hash;
    return 1;
};

sub setAllFieldsErrorText {
    my $form = shift;
    my $hash = shift;  #$hash->{$lang}->{$code} = $value;
    
    return $form->error("setAllFieldsErrorText(): param is not HASHREF") unless ref($hash) eq "HASH";
    return $form->error("setAllFieldsErrorText(): default lang is not supported") if exists $hash->{""};
    return $form->error("setAllFieldsErrorText(): form constructor has no lang specified") unless $form->{_lang};

    $form->{_aferrors} = $hash;
    return 1;
};

sub getFieldErrorText {
    my $form  = shift;
    my $field = shift || return "NG::Form->getFieldErrorText(): no field name";
    my $code  = shift || return "NG::Form->getFieldErrorText(): no error code";
    
    my $lang = $form->{_lang};
    return $form->{_ferrors}->{$lang}->{$field}->{$code} if exists $form->{_ferrors}->{$lang} && exists $form->{_ferrors}->{$lang}->{$field} && exists $form->{_ferrors}->{$lang}->{$field}->{$code};
    return $form->{_aferrors}->{$lang}->{$code} if exists $form->{_aferrors}->{$lang} && $form->{_aferrors}->{$lang}->{$code};
    
    return "";
};

sub setFieldLangParams {
    my $form = shift;
    my $hash  = shift;
    
    return $form->error("NG::Form->setFieldLangParams(): no params hash") unless ref($hash) eq "HASH";
    return $form->error("NG::Form->setFieldLangParams(): default lang is not supported") if exists $hash->{""};
    return $form->error("NG::Form->setFieldLangParams(): form constructor has no lang specified") unless $form->{_lang};
    
    warn ("NG::Form->setFieldLangParams(): form already has fields added. LANGPARAMS value can be ignored") if scalar @{$form->{_fields}};
    
    $form->{_flangparams} = $hash;
    return 1;
};


sub _addfield { #internal method
	my $self = shift;
	my $field = shift;
    
    return $self->error("_addfields(): Отсутствует обязательный параметр") unless $field;
    
    my $fObj = undef;
    if (!ref $field) {
        die "Field is not hash or object";
    }
    if (ref $field eq "HASH") {
        return $self->error("Ошибка добавления поля в форму: Не указано имя поля") unless $field->{FIELD};
        if (exists $field->{LANGPARAMS}) {
            my $lp  = $field->{LANGPARAMS};
            my $ref = ref $lp;
            my $lang = $self->{_lang};
            my $ff = $field->{FIELD};
            if ($ref eq "ARRAY") {
                foreach my $param (@$lp) {
                    unless (exists $self->{_flangparams}->{$lang}->{$ff}->{$param}) {
                        warn "addfields(): setFieldLangParams() has no param \"$param\" value for field \"$ff\" lang \"$lang\"";
                        next;
                    };
                    warn "addfields(): field \"$ff\" parameter \"$param\" overriden by LANGPARAMS value" if exists $field->{$param};
                    $field->{$param} = $self->{_flangparams}->{$lang}->{$ff}->{$param};
                };
            }
            elsif ($ref eq "HASH" && $lang) {
                return $self->error("addfields(): LANGPARAMS has no key for lang $lang") unless exists $lp->{$lang};
                $lp = $lp->{$lang};
                foreach my $param (keys %$lp) {
                    warn "addfields(): field \"$ff\" parameter \"$param\" overriden by LANGPARAMS value" if exists $field->{$param};
                    $field->{$param} = $lp->{$param};
                };
            }
            elsif ($ref eq "HASH") {
                warn "NG::Form->addfields(): field \"$ff\" has LANGPARAMS but form constructor has no lang specified";
            }
            else {
                return $self->error("Field \"$ff\" has incorrect LANGPARAMS value");
            };
            delete $field->{LANGPARAMS};
        };
        $fObj = NG::Field->new($field, $self);
        return $self->error("Ошибка добавления поля " . $field->{FIELD} . " в форму: ". $NG::Field::errstr) unless $fObj;
    }
    elsif ($field->isa("NG::Field") ) {
        $fObj = $field;
    }
    else {
        return $self->error("Добавляемое поле не является HASHREF или объектом NG::Field");
    }

    my $type = $fObj->type();
    if ($type eq "id" || $type eq "filter") {
        return $self->error("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
        push @{$self->{_keyfields}},$fObj ;
    }
    elsif (($type eq "rtf") || ($type eq "rtffile")) {
        $fObj->{FILE_HANDLER} ||= $self->q()->url(-absolute=>1);
    }
	push @{$self->{_fields}}, $fObj;
    return $fObj;
}

sub addfields {
	my $self = shift;
	my $ref = shift;
	
	if (!defined $ref) { die "Field not defined in \$form->addfields()..."; };
	
	if (ref $ref eq "") {
		unshift(@_,$ref);
		my %field = (@_);
		return $self->_addfield(\%field);
	}
    elsif (ref $ref eq 'HASH') {
		return $self->_addfield($ref);
	}
    elsif (ref $ref eq 'ARRAY') {
        my $fObjs = [];
		foreach my $tmp (@{$ref}) {
			my $fObj = $self->_addfield($tmp) or return 0;
            push @{$fObjs}, $fObj;
		};
        return $fObjs;
	}
    elsif (UNIVERSAL::isa($ref, "NG::Field")) {
		return $self->_addfield($ref);
	};
    return 0;
};

sub deletefield {
    my $self = shift;
    my $fieldname = shift;
    my @fields = @{$self->{_fields}};
    $self->{_fields} = [];
    my $found = 0;
    foreach my $field (@fields) {
        if ($field->{FIELD} ne $fieldname) {
            push @{$self->{_fields}}, $field;
        }
        else {
            $found = 1;
        }
    };
    if ($found) {
        my @keyfields = @{$self->{_keyfields}};
        $self->{_keyfields} = [];
        foreach my $field (@keyfields) {
            if ($field->{FIELD} ne $fieldname) {
                push @{$self->{_keyfields}}, $field;
            }
        };    
    };
    die "NG::Form::deletefield(): field $fieldname not found" unless $found;
};

sub fields {
	my $self = shift;
	return $self->{_fields};
}

sub keyfields {
	my $self = shift;
	return $self->{_keyfields};
}

sub param {
	my $self = shift;
	
	my $first = shift;
	my $type  = ref $first;

	if (!scalar(@_)){
		croak ("Single reference arg must be hash-ref") unless $type eq 'HASH' or (ref($first) and UNIVERSAL::isa($first,'HASH'));
		push (@_,%$first);
	} else {
		unshift(@_,$first);
	}

	for (my $x=0; $x<=$#_; $x+=2)	{
		my $p = $_[$x];
		my $value = $_[$x+1];
		
		my $field = $self->_getfieldhash($p) or next;
		$field->setValue($value);
	};
}

sub _getfieldhash {
	my $self = shift;
	my $fieldname = shift;
	foreach my $field (@{$self->{_fields}}) {
		if ($field->{FIELD} eq $fieldname)  {
			return $field;
			last;
		}
	}
	return undef;
}

sub setfieldparam {
	my $self = shift;
    warn("Method NG::Form::setfieldparam() is expired now. Use NG::Field::setparam() instead.");
	my $fieldname = shift or croak("Fieldname not specified in \$form->setfieldparam()");
	my $param = shift or croak("Param name not specified in \$form->setfieldparam()"); 
	my $value = shift;

	my $field=$self->_getfieldhash($fieldname) or croak "Field \"$fieldname\" not found in \$form->setfieldparam()"; 
	$field->{$param} = $value;
};

sub modeInsert {
	my $self=shift;
	$self->{'_new'}=1;
	# Set default values for fields
	foreach my $field (@{$self->{_fields}}) {
        $field->setDefaultValue() unless ($field->{VALUE});
        $field->{_new} = 1;
	};
};

sub setcontainer {
	my $self=shift;
	my $container=shift;
	$self->{'_container'}=$container;
};

sub pusherror {
	my $self = shift;
	my $fieldname = shift;
	my $errormsg = shift;
	my $field=$self->_getfieldhash($fieldname) or die "Field \"$fieldname\" not found in \$form->pusherror()";
    $field->setError($errormsg);
};

sub pusherrorcode {
	my $self = shift;
	my $fieldname = shift;
	my $code = shift;
	my $field=$self->getField($fieldname) or die "Field \"$fieldname\" not found in \$form->pusherror()";
    $field->setErrorByCode($code);
};

sub deleteerror {
	my $self = shift;
	my $fieldname = shift;
	my $field=$self->_getfieldhash($fieldname) or die "Field \"$fieldname\" not found in \$form->deleteerror()";
	$field->setError("");
};

sub ajaxErrorReport {
	my ($self) = @_;
	my ($report, $index) = ({ status => 'error', fields => [] },0);
	
	foreach my $field (@{$self->{_fields}})	{
		next if $field->{HIDE};
		push @{$report->{fields}}, $field->ajaxError() if length($field->error()) > 0;
	};
	create_json($report);
};

sub ajax_showerrors {
	my $self = shift;
    my $key_value = $self->getComposedKeyValue();
    
    my $globalError = "";
	my $error = "<script type='text/javascript'>";
	foreach my $field (@{$self->{_fields}}) {
        my ($e,$ge) = $field->getJSShowError();
        $error .= $e if $e;
        $globalError .= $ge if $ge;
	};
    $error .= "parent.document.getElementById('error_$key_value').innerHTML='$globalError';";
	$error .= "</script>\n";
    return $error.$self->ajax_updatevalue;
};

sub ajax_updatevalue {
	my $self = shift;
	my $update = "<script type='text/javascript'>";

	foreach my $field (@{$self->{_fields}}) {
	    next if ($field->{HIDE});
        $update .= $field->getJSSetValue();
	};
	$update .= "</script>\n";
    return $update;
};

sub has_err_msgs {
	my $self = shift;
    
    foreach my $field (@{$self->{_fields}}) {
        return 1 if $field->hasError();
	};
    return 0;
};
*hasErrors = \&has_err_msgs;



sub error {
	my $self = shift;
	my $error = shift;
    my $defErr = shift;
	$self->{_error} = $error;
    $self->{_error} ||= $defErr;
    warn $self->{_error};
	return 0;
}

sub getError {
    my $self = shift;
    return $self->{_error};
};

sub getErrorString {
    my $self = shift;
    my $error = "";
    foreach my $field (@{$self->{_fields}}) {
        my $fe = $field->error();
        $error .= $fe."\n" if (!is_empty($fe));
    };
    return $error;
};

sub setTitle {
    my $self = shift;
    $self->{_title} = shift;
}

sub print {
	my $self = shift;
	my $template = shift;

    use URI::Escape;
    my $u = $self->q()->url(-query=>1); # Текущий URL, без учета AJAX/noAJAX, для возврата в исходную страницу после действий
    $u =~ s/_ajax=1//;

    my @elements = ();   # Массив  
    my $fHash = {};      # Hash of not hidden and not showed fields
    my $fAll  = {};
    my $globalError = "";
    foreach my $field (@{$self->fields()}) {
        $field->prepareOutput() or return $self->error($field->error());
        $field->{VALUE} = "" unless exists $field->{VALUE};
        
        $fAll->{$field->{FIELD}} = $field;
        
        if ($field->{HIDDEN_FIELD} || $field->{HIDE}) { #Перенаправляем ошибки из неотображаемых полей в глобальный контейнер
            my $em = $field->error() || "";
            $globalError .= $em;
            
            next if $field->{HIDE};
            
            my $f = $field->param();   # Возвращает копию поля в виде хэшреф
            push @elements, $f;        # Добавляет поле на отображение как скрытое.
            next;
        };
        $fHash->{$field->{FIELD}} = $field; # Добавляем маркер что поле нужно отобразить в форме
    };
    
    if ($self->{_structure}) {
        return $self->error("_structure is not ARRAYREF") unless ref $self->{_structure} eq "ARRAY";
        foreach my $e (@{$self->{_structure}}) {
            return $self->error("incorrect TYPE (".$e->{TYPE}.") in structure record") unless $e->{TYPE} eq "row";
            return $self->error("FIELDS недопустимо для типа row in structure record") if exists $e->{FIELDS};
            if (exists $e->{FIELD}) {
                return $self->error("недопустимое сочетание: FIELD и COLUMNS in structure record") if exists $e->{COLUMNS};
                return $self->error("отсутствует значение FIELD in structure record") unless $e->{FIELD};
                return $self->error("Поле ".$e->{FIELD}." из structure record не найдено в полях формы") unless exists $fHash->{$e->{FIELD}};
                
                my $field = $fHash->{$e->{FIELD}};
                delete $fHash->{$e->{FIELD}};
                
                my $f = $field->param();
                push @elements, {ROW_START=>1,ROW=>$e};
                push @elements, $f;
                push @elements, {ROW_END=>1,ROW=>$e};
            }
            elsif (exists $e->{COLUMNS}) {
                return $self->error("structure record: COLUMNS is not ARRAYREF") unless ref $e->{COLUMNS} eq "ARRAY";
                return $self->error("structure record: COLUMNS array is empty") unless scalar @{$e->{COLUMNS}};
                
                push @elements, {ROW_START=>1,ROW=>$e};
                push @elements, {COLUMNS_START=>1};
                foreach my $c (@{$e->{COLUMNS}}) {
                    return $self->error("incorrect TYPE (".$c->{TYPE}.") in COLUMNS description") unless $c->{TYPE} eq "column";
                    my $fields = [];
                    if (exists $c->{FIELD}) {
                        return $self->error("недопустимое сочетание: FIELD и FIELDS in COLUMNS description") if exists $c->{FIELDS};
                        push @{$fields}, $c->{FIELD};
                    }
                    elsif (exists $c->{FIELDS}) {
                        return $self->error("structure record: FIELDS in COLUMNS description is not ARRAYREF") unless ref $c->{FIELDS} eq "ARRAY";
                        $fields = $c->{FIELDS};
                    }
                    else {
                        #Something strange
                        return $self->error("В описании COLUMNS в элементе не найдено ни FIELD ни FIELDS");
                    };
                    push @elements, {COLUMN_START=>1,COLUMN=>$c};
                    foreach my $fn (@{$fields}) {
                        return $self->error("Поле ".$fn." из structure record не найдено в полях формы") unless exists $fHash->{$fn};
                        
                        my $field = $fHash->{$fn};
                        delete $fHash->{$fn};
                        
                        my $f = $field->param();
                        push @elements, $f;
                    };
                    push @elements, {COLUMN_END=>1,COLUMN=>$c};
                };
                push @elements, {COLUMNS_END=>1};
                push @elements, {ROW_END=>1,ROW=>$e};
            }
            else {
                #Something strange
                return $self->error("В описании структуры ряда не найдено FIELD или COLUMNS");
            };
        };
    };

	foreach my $field (@{$self->fields()}) {
        next unless exists $fHash->{$field->{FIELD}};
        delete $fHash->{$field->{FIELD}};

        my $f = $field->param();
        push @elements, {ROW_START=>1} unless $f->{IS_HIDDEN};
        push @elements, $f;
        push @elements, {ROW_END=>1} unless $f->{IS_HIDDEN};
	};
    my $urlfa = $self->{_form_url};
    $urlfa.= "?" if ($urlfa !~ /\?/);
    $urlfa.= "&" if ($urlfa !~ /[&?]$/);

    unless ($self->{_buttons}) {
        $self->addButton({
            TITLE => "Сохранить",
            IMG => "/admin-side/img/buttons/save.gif",
            VALUE => ($self->{_new}?"insert":"update"),
        });
        $self->addCloseButton();
    };
    
    my $title = $self->{_title};
    while ($title =~ /\{(.+?)\}/i) {
        my $f = $self->getField($1) or next;
        my $value = $f->value();
        $title =~ s/\{(.+?)\}/$value/i;
    };

	$template->param(
        FORM => {
			NAME => $self->{_name},
            TITLE => $title,
            ELEMENTS   =>\@elements,
            FIELDS     => $fAll,
            URL   =>$self->{_form_url},
            URLFA      => $urlfa,
            SELF_URL   =>$u,
            KEY_VALUE  =>$self->getComposedKeyValue(),
            KEY_PARAM  =>$self->_getKeyURLParam(),
            CONTAINER  =>$self->{_container},
            NEW        =>$self->{_new},
            REF        =>$self->{_ref},
            IS_AJAX    =>$self->{_ajax},
            HIDE_BUTTONS=>$self->{_hidebuttons},
            ERRORMSG   => $globalError,
            PREFIX     => $self->{_prefix},
            BUTTONS    => $self->{_buttons},
            HAS_ERRORS => $self->has_err_msgs()
        },
	);
	return 1;
};

sub setStructure {
    my $self = shift;
    $self->{_structure} = shift;
};

sub hideButtons {
    my $self = shift;
    $self->{_buttons} = [];
};

sub removeButtons {
    my $self = shift;
    $self->{_buttons} = [];
};

sub addButton {
    my $self = shift;
    my $button = shift || {};
    $self->{_buttons} ||= [];
    
    my $t = {};
    if (exists $button->{TEMPLATE}) {
        $t->{TEMPLATE} = $button->{TEMPLATE};
    }
    else {
        exists $button->{IMG} or croak("addButton(): IMG not specified");
        exists $button->{VALUE} or croak("addButton(): VALUE not specified");
    };
    $t->{BUTTON} = $button;
    push @{$self->{_buttons}},$t;
};

sub addCloseButton {
    my $self = shift;
    my $button = shift || {};
    $self->{_buttons} ||= [];

    my $t = {};
    $button->{IMG} ||= "/admin-side/img/buttons/cancel.gif";
    $t->{TEMPLATE} = $button->{TEMPLATE} if exists $button->{TEMPLATE};
    $t->{CLOSE_BTN} = $button;
    push @{$self->{_buttons}}, $t;
};


sub cleanUploadedFiles {
	my $self = shift;

	foreach my $field (@{$self->fields()}) {
		## Отдельная очистка залитых файлов нужна, поскольку форма может быть отклонена по различным причинам
		## TODO: сделать отдельную заливку файлов, с прикреплением, чтобы не было необходимости переотправлять файл если отклонено из-за другого параметра.
		## Через кэш таблица+поле+айди ключа, дата-время заливки + устаревание и очистка.

        if ($field->isFileField() && !is_empty($field->{TMP_FILE})) {
			unlink $field->{TMP_FILE};
			$field->{TMP_FILE} = "";
		};
	};
};

sub StandartCheck {
	my $self = shift;

    foreach my $field (@{$self->fields()}) {
        next if $field->{HIDE};
        $field->check();
    };
};


sub _saveData {
    my $self = shift;
    my $action = shift;

    my $fields = $self->fields();
   
    foreach my $field (@{$fields}) {
        next unless $field->changed();
        $field->processChilds() or return $self->error("Ошибка вызова processChilds() поля ".$field->{FIELD}." :".$field->error());
    };

    foreach my $field (@{$fields}) {
        next unless $field->changed();
        $field->process() or return $self->error("Ошибка вызова process() поля ".$field->{FIELD}.": ".$field->error());
    };
  
    foreach my $field (@{$fields}) {
		$field->beforeSave($action) or return $self->error("Ошибка вызова beforeSave() поля ".$field->{FIELD}.": ".$field->error());
    };
	my $ret = "";
	if ($action eq "insert") {
		$ret = $self->_insert();
	}
	else {
		$ret = $self->_update($self->fields());
	};
    if ($ret) {
        foreach my $field (@{$fields}) {
    		$field->afterSave() or return $self->error("Ошибка вызова afterSave() поля ".$field->{FIELD}.": ".$field->error());
        };
    }
    $self->cleanUploadedFiles();
    return $ret;
};

sub insertData {
    my $self = shift;
    return $self->_saveData("insert");
}    

sub updateData {
    my $self = shift;
    return $self->_saveData("update");
}
    
sub _insert {
    my $self = shift;
    my $dbh = $self->dbh();
	my $table = $self->{_table} or return $self->error("Parameter \"TABLE\" not initialised");
    
    my $fieldsH = {};  #
    my @fields  = ();
	my @data = ();
    
    my $ph = "";
	foreach my $field (@{$self->fields()}) {
        my @fieldDbFields = $field->dbFields('insert');
        foreach my $dbField (@fieldDbFields) {
            return $self->error("Table field $dbField specified twice for 'insert' operation: at " . $fieldsH->{$dbField}." and ".$field->{FIELD}) if $fieldsH->{$dbField};
            $fieldsH->{$dbField} = $field->{FIELD};
            
            push @data,$field->dbValue($dbField);
            push @fields, $dbField;
            $ph .= "?,";
        };
	};
	$ph =~ s/\,+$//;
    $dbh->do("INSERT INTO ".$self->{_table}."(".join(',',@fields).") VALUES ($ph)",undef,@data) or return $self->error($DBI::errstr);
    return 1;
};

sub _update {
    my $self = shift;
    my $afields = shift;
    
    my $dbh = $self->dbh();
    my $table = $self->{_table} or return $self->error("Parameter \"TABLE\" not initialised");
    
    my @keyfields = ();
    my @keyvalues = ();
    my $fieldsH   = {};  
    my @fields    = ();
    my @data      = ();
    
    foreach my $field (@{$self->fields()}) {
        my @fieldDbFields = $field->dbFields('update');
        foreach my $dbField (@fieldDbFields) {
            return $self->error("Table field $dbField specified twice for 'update' operation: at " . $fieldsH->{$dbField}." and ".$field->{FIELD}) if $fieldsH->{$dbField};
            $fieldsH->{$dbField} = $field->{FIELD};
            
            if (($field->{TYPE} eq "id") || ($field->{TYPE} eq "filter")) {
                #Ключевое поле
                push @keyfields, $dbField."=?";
                push @keyvalues, $field->dbValue($dbField);
            }
            else {
                next unless $field->changed($dbField);
                push @fields, $dbField."=?";
                push @data, $field->dbValue($dbField);
            };
        };
    };
    return $self->error("Can`t find key fields") unless scalar @keyfields;
    return 1 unless scalar @fields;    #Нечего обновлять

    $dbh->do("UPDATE $self->{_table} SET ".join(',',@fields)." WHERE ".join(' AND ',@keyfields),undef,@data,@keyvalues) or return $self->error($DBI::errstr);

    return 1;
};

sub loadData {
	my $self = shift;
    return $self->_load($self->fields());
};

sub _load {
    my $self = shift;
    my $afields = shift;
    
	my $dbh = $self->dbh();
	my $table = $self->{_table} or return $self->error("Parameter \"TABLE\" not initialised");
	
	#Компонуем запрос
    my $fields = "";
    foreach my $field (@{$afields}) {
        next if ($field->{IS_FAKEFIELD});
        $fields .= ",".$field->{FIELD};
    };

    #Компонуем ключи и условие запроса
    my @keys = ();
    my $where  = "";
    foreach my $field (@{$self->{_keyfields}}) {
        $where .= " $field->{FIELD}=? and";
        return $self->error("Can`t find value for key field \"$field->{FIELD}\" in form::_load") if(is_empty($field->{VALUE}));
        push @keys, $field->{VALUE};
    };

    return $self->error("Can`t find key fields") unless $where;
    $where  =~ s/and$//;    
    $fields =~ s/^,//;
	
	my $sth = $dbh->prepare("select $fields from $table where $where") or return $self->error("NG::Form->_load(): Ошибка в запросe: $DBI::errstr");
	$sth->execute(@keys) or return $self->error("NG::Form->_load(): Ошибка исполнения запроса: $DBI::errstr");
	my $tmp = $sth->fetchrow_hashref();
    return $self->error("Запрошенные данные не найдены") unless $tmp;
	$sth->finish();

    #Выставляем полученные значения
	foreach my $field (@{$afields}) {
        unless ($field->{IS_FAKEFIELD}) {
            $field->setLoadedValue($tmp->{$field->{'FIELD'}}) or return $self->error("Ошибка вызова setLoadedValue() поля ".$field->{FIELD}." :".$field->error());
        };
	};
    #Дополнительные действия
    foreach my $field (@{$afields}) {
        $field->afterLoad() or return $self->error("Ошибка вызова afterLoad() поля $field->{FIELD}: ".$field->error());
    };
    return 1;
};

sub setFormValues {
    my $self = shift;
    my $q = $self->q();
    
    foreach my $field (@{$self->fields()}) {
        next if ($field->{HIDE});
        $field->setFormValue();
    };
    $self->{_new} = $q->param('_new') || 0; 
    return 1; #TODO:  NG:Module::M_OK
};

sub getFormData {
	my $self = shift;
	my $data = {};
	foreach my $field (@{$self->{_fields}}) {
		$data->{$field->{FIELD}} = $field->{VALUE};
	};
	return $data;
};

sub getField {
    my ($self,$f) = (shift,shift);
    my $field = $self->_getfieldhash($f); # or die "NG::Form::getField(): field \"$f\" is not found";
	return $field;
};

sub getParam {
    my ($self,$f) = (shift,shift);
    my $field = $self->_getfieldhash($f) or die "NG::Form::getParam(): field \"$f\" is not found";
	return $field->value();
};
*getValue = \&getParam;

sub setParam
{
 my ($self, $fn, $p) = @_;
 
 my $field = $self->_getfieldhash($fn) or die "NG::Form::setParam(): field \"$fn\" is not found";
 $field->setValue($p);
};

sub cleanField {
    my $self = shift;
    my $field = shift;

    return $self->error("Операция запрещена: У очищаемого поля стоит признак \"Не пустое\"") if ($field->{IS_NOTNULL});
	
    my @fields = ();
    my @loadfields = ();
   
    push @fields,$field;
    push @loadfields, $field if ($field->isFileField() || $field->type() eq "rtffile");

    if (exists $field->{CHILDS}) {
        my $childs = $field->getChilds();
        return $self->showError() unless $childs;
        
        return $self->error("Параметр CHILDS не является ссылкой на массив") unless (ref $field->{CHILDS} eq "ARRAY");
        foreach my $ch (@{$childs}) {
            my $child = $self->_getfieldhash($ch->{FIELD}) or return $self->error("Подчиненное поле ".$ch->{FIELD}." не найдено");
			
			#next if $child->{IS_NOTNULL};
			return $self->error("Вложенная подчиненность полей недопустима") if exists $child->{CHILDS};

            if ( $child->isFileField() || $child->type() eq "rtffile" ) {
				push @loadfields, $child;
			}
			else {
				$child->setLoadedValue("") or return $self->error("Ошибка вызова setLoadedValue() поля ".$child->{FIELD}." :".$child->error());
			};
            push @fields,$child;
        };
    };
    $self->_load(\@loadfields) or return 0;

    foreach my $f (@fields) {
        $f->clean() unless $f->changed();
        $f->processChilds() or return $self->error("Ошибка вызова processChilds() поля ".$field->{FIELD}." :".$field->error());
    };
 
    $self->_update(\@fields) or return 0;
    return 1;
}

sub getDocRoot {
	my $self = shift;
	return $self->{_docroot};
};

sub getSiteRoot {
	my $self = shift;
	return $self->{_siteroot};
};

sub getComposedKeyValue() {
    my $self = shift;
    my $keyValue = "";
    foreach my $field (@{$self->{_keyfields}}) {
        return $self->error("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
        die "Can`t find value for key field \"$field->{FIELD}\" in NG::Form::getComposedKeyValue()" if(is_empty($field->{VALUE}));
        $keyValue .= "_".$field->{VALUE};
    };
    $keyValue =~ s/^_//;
    return $keyValue;
};

sub _getKeyURLParam {
    my $self = shift;
    my $param = "";
    foreach my $field (@{$self->{_keyfields}}) {
        next if $field->{TYPE} eq "filter";
        die "Can`t find value for key field \"$field->{FIELD}\" in Form::_getKeyURLParam()" if (is_empty($field->{VALUE}));
        $param .= $field->{FIELD}."=".$field->{VALUE}."&";
    };
    $param =~ s/\&$//;
    return $param;
}

sub getKeyWhere {
    my $self = shift;
    my $where = "";
    foreach my $field (@{$self->{_keyfields}}) {
        return $self->error("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
        $where .= " ".$field->{FIELD}."=? and";
    };
    $where  =~ s/and$//;
    return $where;
}

sub getKeyValues {
    my $self = shift;
    my @keyValues = ();
    foreach my $field (@{$self->{_keyfields}}) {
        return $self->error("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
        die "Can`t find value for key field \"$field->{FIELD}\" in Form::getKeyValues()" if(is_empty($field->{VALUE}));
        push @keyValues, $field->{VALUE};
    }
    return wantarray?@keyValues:\@keyValues;
}

sub _faError {
    my $form = shift;
    my $error = shift;
    my $is_ajax = shift;
    return "<script type='text/javascript'>alert('".(escape_js $error)."');</script>" if $is_ajax;
    $form->error($error);
    return 0;
}; 
 
sub doFormAction {
    my $form = shift;
    my $fa = shift;
    my $is_ajax = shift;
   
    my $field = undef;
    my $action = undef;
   
    foreach my $f (@{$form->fields()}) {
        next if ($f->{HIDE});
        my $actions = $f->getFieldActions();
        
        unless ($actions && ref $actions eq "ARRAY") {
            my $e = $f->error();
            $e = "returns error: ".$e if $e;
            $e ||= "does not returns correct value";
            return $form->_faError("NG::Form::doFormAction(): field ".$f->{FIELD}."->getFieldActions() ".$e,$is_ajax);
        }; 
        
        foreach my $a (@{$actions}) {
            if ($f->{FIELD}."_".$a->{ACTION} eq $fa) {
                $field = $f;
                $action = $a;
                last;
            }; 
        }; 
        last if $field;
    }; 
    return $form->_faError("NG::Form::doFormAction(): не найдено поле и метод для обработки action $fa",$is_ajax) unless ($field && $action && $action->{METHOD});
    my $method = $action->{METHOD};
    return $form->_faError("NG::Form::doFormAction(): Поле $field->{FIELD} не содержит метода $method для обработки $fa",$is_ajax) unless $field->can($method);
     
    my $ret = $field->$method($is_ajax);
   
#print STDERR $ret;
    unless ($ret) {
        return $form->_faError($field->error(),$is_ajax);
    }; 
    return $ret;
}; 
 
sub Delete {
    my $self = shift;
    
    #Формирование ключей и условия запроса, обработка файловых типов данных
    my @fields = ();
    my @params = ();
    my @loadfields = ();

    foreach my $field (@{$self->{_fields}}) {
        my $type = $field->{TYPE};
        if ($type eq "id" || $type eq "filter") {
            return $self->error("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
            return $self->error("Не найдено значение ключевого поля ".$field->{FIELD}) if (is_empty($field->{VALUE}));
            push @params, $field->{VALUE};
            push @fields, $field->{FIELD};
            next;
        }
        next if ($field->{IS_FAKEFIELD});
        if ($field->{NEED_LOAD_FOR_UPDATE}) {
            push @loadfields, $field;
        };
    };
    if (scalar @loadfields) {
        $self->_load(\@loadfields) or return 0;
    };
    
    foreach my $field (@{$self->{_fields}}) {
        $field->beforeDelete() or return $self->error("При выполнении beforeDelete() поля ".$field->{FIELD}." произошла ошибка: ". $field->error());
    };
    $self->db()->dbh()->do("delete from ".$self->{_table}." where ".join("=? and ",@fields)."=?",undef,@params) or return $self->error($DBI::errstr);
    return 1;
};

return 1;
END{};


=head
    
    Описание конфигурирования структурного отображения полей формы:
    Ключ NAME в настоящее время никак не используется. Хэши передаются в шаблон, можно использовать доп ключи элементов структуры.

    $form->structure([
        {TYPE=>"row", NAME=>"row_for_field1", HEADER=>"Заголовок строки, перед полем", FIELD=>"field1"},
        {TYPE=>"row", NAME=>"row_for_3_columns", HEADER=>"Заголовок строки, над всеми столбцами",
            COLUMNS => [
                {TYPE=>"column", NAME=>"row2_column1", HEADER=>"Заголовок столбца1, над полем2",       FIELD=>"field2",           WIDTH=>"20%", },
                {TYPE=>"column", NAME=>"row2_column2", HEADER=>"Заголовок столбца2, над всеми полями", FIELDS=>["field3","field4"],             },
                {TYPE=>"column", NAME=>"row2_column3", HEADER=>"Заголовок столбца3, над полем5",       FIELD=>"field5",                         },
            ],
        },
    ]);


=cut
