package NG::Module::List;
use strict;

#TODO: внести в админку изменение, чтобы при отсутствии в списке привилегий, полученном вызовом modulePrivileges() модуля,  имени привилегии, вместо него подставлялся её код.

use Carp;
use NG::Form 0.4;
use NG::Field;
use NG::DBlist 0.4;
use NSecure;
use NGService;
use URI::Escape;
use NHtml;
use NG::Module::List::Event;
use NG::Module::List::Row;

$NG::Module::List::VERSION=0.3;

use NG::Block;

use vars qw(@ISA);
@ISA = qw(NG::Block);

#ACTION, NAME, METHOD/SUB, SKIPCONFIRM, CONFIRMTEXT
our $MULTIACTION_DELETE = {ACTION=>'delete', NAME=>'Удалить выбранные', METHOD=>'_maDeleteRecords', SKIPCONFIRM=>0};

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);
    $self->config();
    return $self->cms->error() if $self->cms->getError();
    $self->registerModuleActions();
    return $self; 
};

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    # Внутренние объекты и переменные класса
    $self->{_recordname} = "записи";
    
    # Переменные, определяющие основную конфигурацию класса
    $self->{_table} = "";        # Имя таблицы, из которой читаем, в которую пишем
    $self->{_idname} = "";       # Имя ключевого поля таблицы
    $self->{_fields} = [];       # Массив хешей всех обрабатываемых модулем полей таблицы
    $self->{_listfields} = [];   # Массив полей, которые выводить в список

    $self->{_searchfields} = [];   # массив полей, которые выводятся в форму в режиме редактирования
    $self->{_searchform}   = undef;# NG::Form for search
    $self->{_orders}       = [];   # Конфигурация вариантов сортировки списка
    $self->{_extra_links}  = []; # 
    $self->{_topbar_links} = []; #
    #Режим работы модуля
    $self->{_fieldsAnalysed} = 0;
    $self->{_pageBlockMode} = 0;
    $self->{_linkBlockMode} = 0;
    $self->{_templateBlockMode} = 0;
    $self->{_contentKey} = undef;
    $self->{_has_pageLangId} = 0;
    
    #переменные, для передачи данных между функциями построения списка
    $self->{_shlistActiveOrder} = undef;    # Активный order
    $self->{_shlistFKParam}="";
    $self->{_shlistPageParam}="";
    $self->{_shlistWhere}=[];
    $self->{_shlistSearch}=[];
    $self->{_shlistFields}=undef;
    
    $self->{_filters} = []; # Список фильтров списка
    $self->{_multiActions} = undef;  #Список возможных действий пользователя над группой записей.
    $self->{_versionKeys}  = undef;  #Список ключей кеша, которые надо обновить при действии с записью
    
    #Конфигурация поиска
    $self->{_searchconfig} = undef;
    
    $self->{_has_delete_link} = 1;
    $self->{_has_move_link} = 0;  ### Живет потому что есть метод disableMoveLink
    $self->{_hide_move_link} = 0;
    $self->{_posField} = undef;   ### Поле типа posorder
    $self->{_delete_link_name} = "Удалить";
    
    $self->{_listtemplate} = "admin-side/common/universallist.tmpl";
    
    $self->{_search_link_name} = "Поиск";
    $self->{_search_popup} = 1;
    $self->{_searchformtemplate} = "admin-side/common/searchform.tmpl";
    
    $self->{_disablepages} = 0;
    
    $self->{_onpage} = 10;
    $self->{_onlist} = 10;
    
    $self->{_rowClass} = "NG::Module::List::Row";
    
    $self->{_deletePriv} = undef; # Здесь будет хэшреф привилегии на удаление
    #---------------------------------------------------------------------------
    $self->{_options} = {
        INSERT_REDIRECTMODE => "ref",
        INSERT_REDIRECTURLMASK => undef
    };
    # INSERT_REDIRECTMODE (ref,added,url)
    # INSERT_REDIRECTURLMASK
    
    $self->{_aForms} = [];
};

sub config {
};

sub registerModuleActions {
    my $self = shift;

    $self->register_action('',"showList");
    
    $self->register_action('delete',"Delete")       if $self->{_has_delete_link};
    $self->register_action('deletefull',"Delete")   if $self->{_has_delete_link};
    
    $self->register_action('move',"Move");
    
    $self->register_action('showsearchform','showSearchForm') if (scalar @{$self->{_searchfields}});

    $self->register_action('insf',  'processForm');
    $self->register_action('updf',  'processForm');
    $self->register_action('formaction','processForm');
    $self->register_ajaxaction('checkboxclick', 'processCheckbox');
    $self->register_ajaxaction('multiaction', 'processMultiaction');
};

#
# Actions
#
sub showList {
    my $self = shift;
    
    $self->opentemplate($self->{_listtemplate}) || return $self->showError("showList(): не могу открыть шаблон");
    
    $self->beforeBuildList() or return $self->showError('showList(): Вызов beforeBuildList() не вернул текст ошибки');
    $self->buildList() or return $self->showError('showList(): Вызов buildList() не вернул текст ошибки');
    $self->afterBuildList() or return $self->showError('showList(): Вызов afterBuildList() не вернул текст ошибки');
    
    
    return $self->output($self->tmpl()->output());
};

sub buildList {
    my $self = shift;
    my $q = $self->q();
    
    my $is_search = $q->param("_search")||0; $is_search = 0 if ($is_search != 1);
    
    my $myurl = $self->getBaseURL().$self->getSubURL();
                                # Текущий URL, без учета AJAX/noAJAX,
    my $u = $q->url(-query=>1); # для возврата в исходную страницу
    $u =~ s/_ajax=1//;          # после действий со списком
    $u = uri_escape($u);

    # Заполняем описания полей списка описаниями из основного массива
    my $listfields = $self->_getIntersectFields($self->{_listfields}) or return $self->showError("buildList(): Ошибка вызова _getIntersectFields()");
    
    $self->processFKFields() or return $self->showError("buildList(): Ошибка вызова processFKFields()"); # Если в описании таблицы есть FK, учитываем их в ссылках и SQL
    $self->processFilters() or return $self->showError("buildList(): Ошибка вызова processFilters()");
    $self->processSorting($listfields) or return $self->showError("buildList(): Ошибка вызова processSorting()");
    $self->setPagesParam();
    $self->highlightSortedColumns($listfields) or return $self->showError("buildList(): Ошибка вызова highlightSortedColumns()");
    
    my @columns = $self->getListColumns($listfields);  # Также выставляет список полей для getListSQLFields
    my $headersCnt = scalar @columns;
    
    $headersCnt++ if $self->{_multiActions};
    
    my $refURL = getURLWithParams($self->getBaseURL().$self->getSubURL(),$self->getPagesParam(),$self->getFKParam(),$self->getFilterParam(),$self->getOrderParam());
    
    #Обрабатываем функцию поиска
    my $sform = undef;
    my $searchParam = "";
    if (scalar @{$self->{_searchfields}}) {
        my $sform = $self->createSearchForm() or return $self->showError("showSearchForm(): Ошибка вызова createSearchForm()");
        #$sform->{_ajax} = $is_ajax;
        
        if ($self->{_search_popup} || $is_search || $self->q()->param("showsearchform")) {
            my $tmpl = $self->gettemplate($self->{_searchformtemplate});
            #$tmpl->param(IS_AJAX=>$is_ajax);# if (!$self->{_search_popup} || $action eq "showsearchform");
            $tmpl->param(
                CANCEL_SEARCH_URL => getURLWithParams($self->getBaseURL().$self->getSubURL(),
                    $self->getFilterParam(),
                    $self->getFKParam(),
                    $self->getOrderParam()
                )
            );
            $sform->print($tmpl);
            $self->tmpl()->param(
                SEARCHFORMHTML => $tmpl->output(),
            );
        };
        if ($is_search) {
            $searchParam = $self->getSearchParam($sform);
            $self->buildSearchWhere($sform);
        };
        unless ($self->{_search_popup}) {
            push @{$self->{_topbar_links}}, {
                NAME    => $self->{_search_link_name},
                URL     => getURLWithParams($myurl,"showsearchform=1",$self->getFKParam(),$self->getFilterParam(),$self->getOrderParam(),$searchParam,$self->getPagesParam(),"ref=".$refURL),
                AJAX_URL=> getURLWithParams($myurl,"action=showsearchform","_ajax=1",$self->getFKParam(),$self->getFilterParam(),$self->getOrderParam(),$searchParam,$self->getPagesParam(),"ref=".$refURL),
            };
        };
        $refURL = getURLWithParams($refURL, $searchParam);
    };
    $refURL = uri_escape($refURL);

    #Добавляем ссылки на добавление и редактирование записи
    foreach my $fm (reverse @{$self->{_aForms}}) {
        if ($fm->{EDITLINKNAME} && $self->hasEditPriv($fm)) {
            my $link = {};
            $link->{NAME}=$fm->{EDITLINKNAME};
            $link->{URL}=$self->getBaseURL().$self->getSubURL()."?action=updf&".$self->{_idname}."={".$self->{_idname}."}".($fm->{EDITLINKPARAMS}?("&".$fm->{EDITLINKPARAMS}):"").($fm->{PREFIX}?"&_form=".$fm->{PREFIX}:"")."&rand=".int(rand(10000));
            $link->{AJAX}=$fm->{DISABLEAJAX}?0:1;
            $self->addRowLink($link) or return $self->showError("Ошибка добавления ссылки на редактирование записи");
        };
        if ($fm->{ADDLINKNAME} && $self->hasAddPriv($fm)) {
            my $link = {};
            $link->{NAME} = $fm->{ADDLINKNAME};
            #FK     - для уточнения внешнего ключа
            #Filter - для подстановки значения в LINKEDFIELD
            #Order  - учитывается при поиске страницы, на которую требуется перейти
            #Ref    - ссылка, куда возвращаться. TODO: проверять режим листа и не подставлять реф если он не будет нужен
            
            my @params = ();
            push @params, "action=insf";
            push @params, "_form=".$fm->{PREFIX} if $fm->{PREFIX};
            push @params, $self->getFKParam();
            push @params, $self->getFilterParam();
            push @params, $self->getOrderParam();
            push @params, "ref=".$refURL;
            push @params, "rand=".int(rand(10000));
            
            $link->{URL} = getURLWithParams($self->getBaseURL().$self->getSubURL(), @params);
            $link->{AJAX_URL} = getURLWithParams($self->getBaseURL().$self->getSubURL(),"_ajax=1",@params) unless $fm->{DISABLEAJAX};
            #$self->addTopbarLink($link);
            unshift @{$self->{_topbar_links}}, $link;
        };
    };
    
    $self->getListSQLTable() or return $self->error("Параметр table не задан");
    
    my $page = $q->param('page') || 0;
    $page = $page + 0;
    
    
    my $dblist = NG::DBlist->new(
        db     => $self->db(),
        table  => $self->getListSQLTable(),
        fields => $self->getListSQLFields(),
        where  => $self->getListSQLWhere(),
        order  => $self->getListSQLOrder(),
        pagename=>"page",
        page   => $page,
        onpage => $self->{_onpage},
        onlist => $self->{_onlist},
        url    => getURLWithParams($myurl,$self->getFKParam(),$self->getFilterParam(),$self->getOrderParam()),
    );

    my $index_counter = ($dblist->page()-1) * $self->{_onpage} + 1;
    my @arraydata = ();
    $dblist->rowfunction(
        sub {
            my $dblist = shift; ## Get object
            my $row = shift;    ## Get data
            
            $self->rowFunction($row);
            
            my $id = $row->{$self->{_idname}};
            
            my $rowObj = $self->{_rowClass}->new({
                ID      => $id,
                DATA    => $row,
                LISTOBJ => $self,
                INDEX   => $index_counter,
                REF     => $refURL,
            });
            
            $rowObj->{MOVE_URL} = getURLWithParams($myurl,"action=move","$self->{_idname}=$id",$self->getFKParam(),$self->getFilterParam(),$self->getOrderParam(),"ref=$u") if ($self->{_has_move_link}==1) && ($self->{_hide_move_link}==0);
            $rowObj->{MOVE_URL_HIDDEN} = 1 if ($self->{_has_move_link}==1) && ($self->{_hide_move_link}==1);
            $rowObj->{HEADERS_CNT} = $headersCnt;
            $rowObj->{MULTIACTIONS} = $self->{_multiActions};
            
            $self->doHighlight($rowObj);
            $index_counter++;
            push @arraydata, $rowObj;
        }
    );
    
    $dblist->disablePages() if ($self->{_disablepages} || $searchParam); #$searchParam - really has search, not empty
    $dblist->open($self->getListSQLValues()) or return $self->error($DBI::errstr);    ## На вход пойдут значения для where. Сразу же подсчитаем число записей, откроем sth
    my $data = $dblist->data();
    my $pages = $dblist->pages();  # Массив постраничной листалки
    my $cnt  = $dblist->size();    # Число записей
   
    my $ma = $self->{_multiActions};
    $ma = undef unless $cnt;
    
    my $template = $self->template() || return $self->error("NG::Module::List::buildList(): Template not opened");
    $template->param(
        HEADERS   => \@columns, #TODO: this can be $self->getListHeaders(),
        #HEADERS_CNT => $headersCnt,
        HEADERS_CNT_M1 => scalar(@columns)-1,  #Для чего это? (rpv,2014-11-27)
        PAGES     => $pages,
        DATA      => \@arraydata,
        FILTERS    => $self->getListFilters(),
        TOP_LINKS => $self->{_topbar_links},
        MYBASEURL => $myurl,
        THISURL   => getURLWithParams($myurl,"_ajax=1",$self->getFKParam(),$self->getFilterParam(),$self->getOrderParam(),$searchParam,$self->getPagesParam(),"ref=".$refURL),
        MULTIACTIONS => $ma,
    );

    return NG::Block::M_OK;
};

sub doHighlight {
    my $self = shift;
    my $rowObj = shift;
    
    my $hlId = $self->q()->param("hlid") || "";
    $rowObj->highlight() if $rowObj->{ID_VALUE} eq $hlId;
};

sub _getAF {
    my ($self,$fprefix) = (shift,shift);
    
    my $q = $self->q();
    
    $fprefix = $q->url_param('_form') unless defined $fprefix;
    
    return $self->error("processForm(): no forms configured") unless scalar @{$self->{_aForms}};
    
    return @{$self->{_aForms}}[0] unless ($fprefix);
    
    foreach my $aFt (@{$self->{_aForms}}) {
        #NB: Была идея, но не реализована, проверять дублирование префиксов форм.. (Может быть добавить в additionalForm() ?)
        #return $self->error("Duplicate form PREFIX detected") if ...;
        
        return $aFt if $aFt->{PREFIX} eq $fprefix;
    };
    return $self->error("processForm(): no form found for prefix $fprefix");
};

sub _getIntersectFields {
    my $self = shift;
    my $fieldList = shift;
    
    return $self->error("_getIntersectFields(): Перечень полей не массив.") if ref $fieldList ne "ARRAY";
    
    my @result = ();
    foreach my $field (@{$fieldList}) {
        my $fName = "";
        if (ref $field eq "HASH") {
            return $self->error("В хэше перечня полей формы не найден ключ FIELD.") if ( !exists $field->{FIELD} || !$field->{FIELD} );
            $fName = $field->{FIELD};
        }
        elsif (ref $field eq "") {
            $fName = $field;
            $field = {FIELD=>$fName};
        }
        else {
            return $self->error("Неверный тип значения элемента (".(ref $field).") в перечне полей формы.");
        };
        
        my $mainField = $self->getField($fName);
        return $self->error("Поле $fName не найдено в списке полей модуля.") unless $mainField;
        
        #return $self->error("Поля типа 'filter' и 'fkparent' добавляются в форму автоматически.")
        #    if ($mainField->{TYPE} eq "filter" || $mainField->{TYPE} eq "fkparent");
        
        foreach my $key (keys %{$mainField}) {
            $field->{$key} = $mainField->{$key} if !exists $field->{$key};
        };
        push @result, $field;
    };
    return \@result;
};

sub doFormAction {
    my $self = shift;
    my $form = shift;
    my $fa = shift;
    my $is_ajax = shift;
    
    return $form->doFormAction($fa, $is_ajax); 
};

sub processForm {
    my ($self,$action,$is_ajax) = (shift,shift,shift);
    
    my $q = $self->q();
    my $dbh = $self->db()->dbh();
    
    my $fa = "";
    my $isInsert = 0;
    if ($action eq "formaction") {
        $fa = $q->param('formaction') || $q->url_param('formaction');
        $isInsert = $q->param('_new') || 0;
    };
    
    my $aF = $self->_getAF() or return $self->showError("processForm(): _getAF cant find form");
    return $self->error("У вас нет прав для выполнения данного действия.") if (
        (($fa eq "insert" || $action eq "insf" || $isInsert) && !$self->hasAddPriv($aF))
        || (($fa eq "update" || $action eq "updf") && !$self->hasEditPriv($aF))
    );

    #Компонуем ссылку, куда отправлять форму
    my $formurl = $self->q()->url()."?action=formaction";
    
    if ($action eq "insf" || $action eq "updf" || (!$is_ajax && $action eq "formaction")) {
        #Построение ссылки возврата после добавления записи
        $self->processFilters() or return $self->showError("processForm(): Ошибка вызова processFilters()");
        $self->processSorting([]) or return $self->showError("processForm(): Ошибка вызова processSorting()");

        $formurl = getURLWithParams($formurl,
            $self->getFilterParam(), # На текущий момент не используется в формирования ссылки перехода на добавленную запись
            $self->getOrderParam(),  # Добавленное значение используется при формировании ссылки перехода на добавленную запись
        );
        #TODO: дописать в NG::Form возможность переброса параметров из FORM_URL в HIDDEN-поля, если форма отправляется методом GET
    };
    
    $formurl = getURLWithParams($formurl,"_form=".$aF->{PREFIX}) if ($aF->{PREFIX});
    
    my $form = NG::Form->new(
        FORM_URL  => $formurl,
        KEY_FIELD => $self->{_idname},
        DB        => $self->db(),
        TABLE     => $self->{_table},
        DOCROOT   => $self->getDocRoot(),
        SITEROOT  => $self->getSiteRoot(),
        CGIObject => $q,
        REF       => $q->param('ref') || "",
        IS_AJAX   => $is_ajax,
        PREFIX    => $aF->{PREFIX},
        OWNER     => $self,
    );
    
    my $aFields = undef;
    if ($fa eq "insert" || $action eq "insf" || $isInsert) {
        #Тайтл
        my $title = "Добавление $self->{_recordname}:";
        if ($aF->{TITLE} ne "") {
            $title = $aF->{TITLE};
        };
        $form->setTitle($title);
        #Поля
        $aFields = $aF->{FIELDS};
        #Структура
        $form->setStructure($aF->{STRUCTURE}) if $aF->{STRUCTURE};
    }
    elsif ($fa eq "update" || $action eq "updf" || $action eq "formaction") {
        #Тайтл
        my $title = "Редактирование $self->{_recordname}:";
        if ($aF->{EDITTITLE} ne "") {
            $title = $aF->{EDITTITLE};
        }
        elsif ($aF->{TITLE} ne "") {
            $title = $aF->{TITLE};
        };
        $form->setTitle($title);
        #Поля
        return $self->error("Перечень полей EDITFIELDS формы не массив.") if $aF->{EDITFIELDS} && ref $aF->{EDITFIELDS} ne "ARRAY";
        $aFields = $aF->{EDITFIELDS} if $aF->{EDITFIELDS} && scalar @{$aF->{EDITFIELDS}};
        $aFields ||= $aF->{FIELDS};
        #Структура
        $form->setStructure($aF->{EDITSTRUCTURE} || $aF->{STRUCTURE}) if $aF->{EDITSTRUCTURE} || $aF->{STRUCTURE};
    }
    else {
        return $self->error("Передан некорректный параметр ACTION: ".$action);
    };
    
    return $self->error("Не знаю откуда наполнять форму полями.") unless $aFields;
    return $self->error("Перечень полей формы не массив.") unless ref $aFields eq "ARRAY";
    
    my $fs = $self->_getIntersectFields($aFields) or return $self->showError("_getIntersectFields(): неизвестная ошибка вызова.");
    
    foreach my $field (@{$fs}) {
        return $self->error("Please, don`t add 'filter' and 'fkparent' fields in formfields() and editfields() calls as they will be added automatically")
            if ($field->{TYPE} eq "filter" || ($field->{TYPE} eq "fkparent" && !$field->{EDITABLE}));
    };
    
    $form->addfields($fs) or return $self->error($form->getError());
    
    if ($action eq "insf") {
        #TODO: связываться с фильтрами, подставлять в форму выбранное в фильтре значение в соответствующее поле формы
        foreach my $filter (@{$self->{_filters}}) {
            my $v = $filter->fieldValue();
            return $self->showError("processForm(): Ошибка вызова filter->fieldValue().") unless $v;
            next unless scalar keys %$v;
            foreach my $f (keys %$v) {
                next unless $v->{$f};
                my $field=$form->_getfieldhash($f);
                $field->setValue($v->{$f}) if $field;
            };
        };
    };
    
    foreach my $field (@{$self->{_fields}}) {
        if ($field->{TYPE} eq "fkparent") {
            my $fkpF = undef;
            if ($field->{EDITABLE}) {
                $fkpF = $form->getField($field->{FIELD}) or return $self->showError("processForm(): Поле ".$field->{FIELD}." типа fkparent со свойством EDITABLE отсутствует в списке полей формы");
            }
            else {
                $fkpF = $form->addfields($field) or return $self->error($form->getError());
            };
            if ($action eq "insf") {
                $fkpF->setFormValue();
            };
        };
        #Тут в форму прокачиваются поля типа filter, в том числе и те, которые ранее имели типы pageId,blockId, etc...
        if ($field->{TYPE} eq "filter") {
            return $self->error("Value not specified for FK field \"".$field->{FIELD}."\"") if is_empty($field->{VALUE});
            $form->addfields($field) or return $self->error($form->getError());
        };
    };

=head
    #Форма создана.
    my @fkPrivFields = ();
    
    if ($action eq "insf" || $action eq "updf") {
        #Догружаем фкселекты. делаем проверку привилегий на их элементы.
        #Если идет insert или update, то fkselect-ы подгрузятся при выводе полной формы в случае ошибки
        foreach my $field (@{$form->fields()}) {
            next if $field->{TYPE} ne "fkselect";
            #Остальные фкселекты, у которых нет проверки привилегий, догрузятся формой в вызове print()
            next unless $field->options('PRIVILEGEMASK');
            
            push @fkPrivFields,$field; #Массив полей, в которых делаем проверку привилегий
            
            $field->fillFKSelectField() or return $self->error($field->error());
            
            my $so = $field->param('SELECT_OPTIONS');
           
            my @nso = (); 
            my $pmask = $field->options('PRIVILEGEMASK');
            foreach my $o (@{$so}) {
                my $privilege = $pmask;
                $privilege =~ s@\{id\}@$o->{ID}@;
                next unless $self->hasPriv($privilege);
                push @nso, $o;
            }
            $field->param('SELECT_OPTIONS',\@nso);
        };
    };
=cut
    my $template = "admin-side/common/universalform.tmpl";
    $template = $aF->{TEMPLATE} if $aF->{TEMPLATE};
    $self->opentemplate($template) || return $self->showError("processForm(): не могу открыть шаблон формы $template");
    
    my $oldsuffix = undef;
    
#showForm
    if ($action eq "insf") {
        $form->modeInsert();
        my $id = $self->db()->get_id($self->{_table},$self->{_idname});
        return $self->error($self->db()->errstr()) unless $id;
        $form->param($self->{_idname},$id);
        
        $self->afterFormLoadData($form,$action) or return $self->showError('processForm(): Вызов afterFormLoadData() не вернул текст ошибки');
        
        $form->print($self->tmpl()) or return $self->error("=".$form->getError());
        return $self->output($self->tmpl()->output());
    }
    elsif ($action eq "updf") {
        my $id = $q->param($self->{_idname});
        $form->param($self->{_idname},$id);
        $form->loadData() or return $self->error($form->getError());
=head
        foreach my $field (@fkPrivFields) {
            my $pmask = $field->options('PRIVILEGEMASK');
            my $privilege = $pmask;
            my $fvalue = $field->value();
            $privilege =~ s@\{id\}@$fvalue@;
            return $self->error("У Вас недостаточно прав для редактирования данной записи") unless $self->hasPriv($privilege);
        };
=cut
        
        $self->afterFormLoadData($form,$action) or return $self->showError('processForm(): Вызов afterFormLoadData() не вернул текст ошибки');
        
        $form->print($self->tmpl()) or return $self->error("=".$form->getError());
        return $self->output($self->tmpl()->output());
    }
#/showForm
#insertUpdate part
    elsif ($fa eq "insert") {
        $form->modeInsert(); #Наверное требуется для HIDE полей, которые тем не менее пишутся в БД.
    }
    elsif ($fa eq "update") {
        my $id = $q->param($self->{_idname});
        $form->param($self->{_idname},$id);
        $form->loadData() or return $self->error($form->getError());
        
        if (defined $self->{_searchconfig}) {
            $oldsuffix = $self->getIndexSuffixFromFormAndMask($form,$self->{_searchconfig}->{SUFFIXMASK});
            return $self->showError() if ($self->cms()->getError('') ne "");
        };
    }
    elsif ($action eq "formaction"){
        return $self->redirect($self->q()->url()) unless $fa;
        
        my $id = $q->param($self->{_idname}) || $q->url_param($self->{_idname});
        $form->param($self->{_idname},$id);
        $form->modeInsert() if $isInsert;
        
        #Обрабатываем экшны полей.
        my $ret = $self->doFormAction($form,$fa,$is_ajax);
        
        if ($is_ajax) {
            #NB: doFormAction может сам возвращать AJAX-ответ в случае ошибки.
            unless ($ret) {
                my $e = $form->getError();
                $e = "Во время обработки formaction $fa произошла ошибка: ".$e if $e;
                $e ||= "Обработчик doFormAction не вернул содержимого ответа";
                return $self->error($ret);
            };
            return $ret if ref($ret) && $ret->isa('NG::BlockContent');
            return $self->output($ret);
        }
        else {
            $ret || return $self->showError($form->getError());
        };
    }
    else {
        return $self->error("Incorrect form action: $action"); ## N.R. Если будет выполнение этого кода - значит наверху неверно изменили условия.
    };

    $form->setFormValues();
    
    $self->afterSetFormValues($form,$fa);
    
    if ($action eq "formaction" && $fa ne "insert" && $fa ne "update") {
        $form->print($self->tmpl()) or return $self->error($form->getError());
        $form->cleanUploadedFiles();
        return $self->output($self->tmpl()->output());
    };

=head
    @fkPrivFields = ();
    foreach my $field (@{$form->fields()}) {
        next if $field->type() ne "fkselect";
        next unless $field->options('PRIVILEGEMASK');
        
        push @fkPrivFields,$field;
        return $self->error("Отсутствует значение поля ".$field->{FIELD}) unless is_valid_id($field->value());
        
        my $privilege = $field->options('PRIVILEGEMASK');
        my $fvalue = $field->value();
        $privilege =~ s@\{id\}@$fvalue@;
        return $self->error("Значение поля ".$field->{FIELD}." недопустимо") unless $self->hasPriv($privilege);
        
        #TODO:
        #если не ругаемся - проверяем наличие записи в справочнике
        #
        #пропихиваем полученное значение из справочника в список данных формы.
        #
    };
=cut
    
    $form->StandartCheck();
    my $ret = $self->checkData($form,$fa);
    if ($ret != NG::Block::M_OK) {
        $form->cleanUploadedFiles();
        return $ret;
    };
    

    if (!$form->has_err_msgs()) {
        my $ret = $self->prepareData($form,$fa);
        if ($ret != NG::Block::M_OK) {
            $form->cleanUploadedFiles();
            return $ret;
        };
    };

    if ($form->has_err_msgs()) {
        $form->cleanUploadedFiles();
        if ($is_ajax) {
            return $self->output($form->ajax_showerrors());
        }
        else {
=head
            #Догружаем справочники полей фкселект
            foreach my $field (@fkPrivFields) {
                $field->fillFKSelectField() or return $self->error($field->error());
                
                my $so = $field->param('SELECT_OPTIONS');
               
                my @nso = (); 
                my $pmask = $field->options('PRIVILEGEMASK');
                foreach my $o (@{$so}) {
                    my $privilege = $pmask;
                    $privilege =~ s@\{id\}@$o->{ID}@;
                    next unless $self->hasPriv($privilege);
                    push @nso, $o;
                }
                $field->param('SELECT_OPTIONS',\@nso);
            };
=cut
            
            $form->print($self->tmpl()) or return $self->error($form->getError());
            return $self->output($self->tmpl()->output());
        };
    };

    $self->beforeInsertUpdate($form,$fa) or return $self->showError("InsertUpdate(): Ошибка вызова beforeInsertUpdate()");
    if ($fa eq "insert") {
        ## Insert
        my $posField = $self->getPosField();
        if ($posField && !defined $posField->{'VALUE'}) {
            my $posFieldName = $posField->{FIELD};
            $posField = $form->addfields($posField) or return $self->error($form->getError());
            my $insertTo = $posField->{INSERTTO} || "bottom";
            if ($insertTo eq "top") {
                $posField->setValue(1);
                if ($self->db()->isa("NG::DBI::Mysql")) {
                    $dbh->do("update ".$self->{_table}." set $posFieldName = $posFieldName+1 order by $posFieldName desc") or return $self->error($DBI::errstr);
                }
                else {
                    $dbh->do("UPDATE ".$self->{_table}." set $posFieldName = -$posFieldName-1") or return $self->error($DBI::errstr);
                    $dbh->do("UPDATE ".$self->{_table}." set $posFieldName = -$posFieldName") or return $self->error($DBI::errstr);
                };
            }
            elsif ($insertTo eq "bottom") {
                my $id = $form->getParam($self->{_idname});
                $posField->setValue($id);
            }
            else {
                return $self->error("Ошибка позиционирования записи: неверная конфигурация. Запись не добавлена.");
            };
            unless ($form->insertData()) {
                if ($insertTo eq "top") {
                    # Возвращаем смещенные позиции
                    if ($self->db()->isa("NG::DBI::Mysql")) { 
                        $dbh->do("update ".$self->{_table}." set $posFieldName = $posFieldName-1 order by $posFieldName") or return $self->error($DBI::errstr);
                    }
                    else {
                        $dbh->do("UPDATE ".$self->{_table}." set $posFieldName = -$posFieldName+1") or return $self->error($DBI::errstr);
                        $dbh->do("UPDATE ".$self->{_table}." set $posFieldName = -$posFieldName") or return $self->error($DBI::errstr);
                    };
                };
                return $self->error($form->getError());
            };
        }
        else {
            $form->insertData() or return $self->error($form->getError());
        };
        $self->_updateVersionKeys($form,$fa);
        $self->_makeLogEvent({operation=>"Вставка записи", operation_param=>"KEY ".join("_",$form->getKeyValues())});
    }
    else {
        ## Update
        $form->updateData() or return $self->error($form->getError());
        $self->_updateVersionKeys($form,$fa);
        $self->_makeLogEvent({operation=>"Обновление записи", operation_param=>"KEY ".join("_",$form->getKeyValues())});
    };
    
    if (defined $self->{_searchconfig}) {
        my $suffix = $self->getIndexSuffixFromFormAndMask($form,$self->{_searchconfig}->{SUFFIXMASK});
        return $self->showError() if ($self->cms()->getError('') ne "");
        if ($oldsuffix && $suffix ne $oldsuffix) {
            $self->_updateIndex($oldsuffix) or return $self->showError("InsertUpdate(): Ошибка обновления индекса");
        };
        $self->_updateIndex($suffix) or return $self->showError("InsertUpdate(): Ошибка обновления индекса");
    };
    $self->afterInsertUpdate($form,$fa) or return $self->showError("InsertUpdate(): Ошибка вызова afterInsertUpdate()");

    my $id = $form->getParam($self->{_idname});
    $self->_makeEvent($fa,{ID=>$id});

    my $ref = "";
    if ($self->{_options}->{INSERT_REDIRECTMODE} eq "added") {
        my $order = $self->getListSQLOrder();
        if ($order) {
            my @orders = ();
            if (!is_empty($order)) {
                my $ordertmp = $order;
                $ordertmp =~ s/order by//;
                my @pairs = split /,/,$ordertmp;
                foreach (@pairs) {
                    my $tmp = {};
                    $_ =~ s/^\s+//;
                    $_ =~ s/\s+$//;
                    ($tmp->{'field'},$tmp->{'sort'}) = split /\s+/,$_;
                    push @orders, $tmp;
                };
            };
            
            my @s = ();  ## conditions
            my @values = $self->getListSQLValues(); ## values
            
            for (my $i = 0; $i<=$#orders; $i++) {
                my $cond = "<";
                $cond = ">" if ($orders[$i]->{'sort'} eq "desc");
                $cond.= "=" if ($i == $#orders);
                
                my $w = $orders[$i]->{field}.$cond."?";
                
                push @values, $form->_getfieldhash($orders[$i]->{'field'})->{'DBVALUE'};
                for (my $j=0;$j<$i;$j++) {
                    $w .= " and ".$orders[$j]->{field}."=?";
                    push @values, $form->_getfieldhash($orders[$j]->{'field'})->{'DBVALUE'};
                };
                $w = "(".$w.")";
                
                push @s, $w; 
            };
            
            my $table = $self->getListSQLTable();
            my $where = $self->getListSQLWhere();
            
            $where .= " and " if $where;
            $where = $where ."(".join("or",@s).")";
            
            my ($currentcount) = $self->db()->dbh()->selectrow_array("select count(*) from $table where $where",undef,@values);
            
            $currentcount = 1 if ($currentcount  < 1);
            my $curpage = int(($currentcount - 1)/$self->{_onpage})+1;
            $self->setPagesParam($curpage);
            
            $ref = getURLWithParams($self->getBaseURL().$self->getSubURL(),
                $self->getPagesParam(),
                $self->getFKParam(),
                $self->getFilterParam(),
                $self->getOrderParam(),
                #$self->getSearchParam(), *Removed!
                "hlid=".$form->getParam($self->{_idname}),
            );
        }
        else {
            $ref = uri_unescape($q->param('ref'));
        };
    }
    elsif($self->{_options}->{INSERT_REDIRECTMODE} eq "url") {
        $ref = $self->{_options}->{INSERT_REDIRECTURLMASK};
        
        my $baseurl = $self->getBaseURL(); 
        my $data = $form->getFormData();
        
        $ref =~ s@{baseurl}@$baseurl@;
        $ref =~ s/\{(.+?)\}/$data->{$1}/gi;
    }
    else {
        $ref = uri_unescape($q->param('ref'));
    };
    
    if ($is_ajax) {
        #TODO: можно сделать загрузку ссылки REF в определенный контейнер, а не полную перезагрузку страницы
        #а может быть совместить оба метода, в зависимости от наличия знания о контейнере, который надо обновить.
        return $self->output("<script type='text/javascript'>parent.redirect('$ref');</script>");
    }
    else {
        return $self->redirect($ref);
    };
};

sub processCheckbox {
    my ($self,$action,$is_ajax) = (shift,shift,shift);
    
    my $q = $self->q();
    
    my $cbFieldName = $q->param('field')   || '';
    my $cbState     = $q->param('checked') || '';
    my $id          = $q->param('id');
    
    return $self->error("Отсутствует параметр имени поля checkbox") unless $cbFieldName;
    return $self->error("Неподдерживаемое значение состояния checkbox") unless $cbState eq 'true' || $cbState eq 'false';
    return $self->error("Отсутствует значение ключевого поля") unless $id;

    $self->changeRowValueByForm(
        {
            ID         => $id,
            FORMPREFIX => undef,   #TODO: 
        },
        sub {
            my ($form) = (shift);
            
            my $cbField = $form->getField($cbFieldName);
            return $self->error("Поле не найдено") unless $cbField;
            return $self->error("Поле не является полем checkbox") unless $cbField->{TYPE} eq "checkbox";    
            my $cbValue = 0;
            $cbValue = $cbField->{CB_VALUE} if $cbState eq 'true';
            $cbField->setValue($cbValue);
            return 1;
        }
    ) or return 0;
    
    return $self->outputJSON({status=>'ok',checked=>(($cbState eq 'true')?1:0)});
};

sub processMultiaction {
    my ($self,$action,$is_ajax) = (shift,shift,shift);
    
    my $q = $self->q();
    my $dbh = $self->db()->dbh();
    
    my $qId     = $q->param('id')          || '';
    my $qAction = $q->param('multiaction') || '';
    
    return $self->error("Multiaction: Действия не сконфигурированы") unless $self->{_multiActions} && ref $self->{_multiActions} eq "ARRAY";
    return $self->error("Multiaction: Не выбраны записи")   unless $qId;
    return $self->error("Multiaction: Не выбрано действие") unless $qAction;
    
    my $maction = undef;
    foreach my $ma (@{$self->{_multiActions}}) {
        if ($ma->{ACTION} eq $qAction) {
            $maction = $ma;
            last;  
        };
    };
    return $self->error("Multiaction: Выбранное действие не найдено") unless $maction;
    my $method = $maction->{METHOD};
    return $self->error("Multiaction: Выбранное действие сконфигурировано неверно: не указан METHOD") unless $method;
    return $self->error("Multiaction: Выбранное действие сконфигурировано неверно: метод '$method' не найден") unless $self->can($method);
    
    my @IDs = split /,/ , $qId;
    return $self->$method($qAction,\@IDs);
};

sub changeRowValueByForm {
    my ($self,$cfg,$sub) = (shift,shift,shift);
    
    my $q = $self->q();
    my $dbh = $self->db()->dbh();
    
    my $cbFormPrefix = $cfg->{FORMPREFIX};
    
    my $aF = $self->_getAF($cbFormPrefix) or return $self->showError("processCheckbox(): cant find form for checkbox");
    return $self->error("У вас нет прав для выполнения данного действия.") if !$self->hasEditPriv($aF);
    
    my $id = $cfg->{ID};
    return $self->error("changeRowValueByForm(): Отсутствует ID") unless $id;
    
    #Компонуем ссылку, куда отправлять форму
    my $formurl = $self->q()->url()."?action=formaction";
    
    my $form = NG::Form->new(
        FORM_URL  => $formurl,
        KEY_FIELD => $self->{_idname},
        DB        => $self->db(),
        TABLE     => $self->{_table},
        DOCROOT   => $self->getDocRoot(),
        SITEROOT  => $self->getSiteRoot(),
        CGIObject => $q,
        REF       => $q->param('ref') || "",
        IS_AJAX   => 1,
        PREFIX    => $aF->{PREFIX},
        OWNER     => $self,
    );
    #Поля
    my $aFields = undef;
    return $self->json_error("Перечень полей EDITFIELDS формы не массив.") if $aF->{EDITFIELDS} && ref $aF->{EDITFIELDS} ne "ARRAY";
    $aFields = $aF->{EDITFIELDS} if $aF->{EDITFIELDS} && scalar @{$aF->{EDITFIELDS}};
    $aFields ||= $aF->{FIELDS};
    
    return $self->error("Не знаю откуда наполнять форму полями.") unless $aFields;
    return $self->error("Перечень полей формы не массив.") unless ref $aFields eq "ARRAY";
    
    my $fs = $self->_getIntersectFields($aFields) or return $self->showError("_getIntersectFields(): неизвестная ошибка вызова.");
    
    foreach my $field (@{$fs}) {
        return $self->error("Please, don`t add 'filter' and 'fkparent' fields in formfields() and editfields() calls as they will be added automatically")
            if ($field->{TYPE} eq "filter" || ($field->{TYPE} eq "fkparent" && !$field->{EDITABLE}));
    };
    
    $form->addfields($fs) or return $self->error($form->getError());
    
    foreach my $field (@{$self->{_fields}}) {
        if ($field->{TYPE} eq "fkparent") {
            my $fkpF = undef;
            if ($field->{EDITABLE}) {
                $fkpF = $form->getField($field->{FIELD}) or return $self->showError("processCheckbox(): Поле ".$field->{FIELD}." типа fkparent со свойством EDITABLE отсутствует в списке полей формы");
            }
            else {
                $fkpF = $form->addfields($field) or return $self->error($form->getError());
            };
        };
        #Тут в форму прокачиваются поля типа filter, в том числе и те, которые ранее имели типы pageId,blockId, etc...
        if ($field->{TYPE} eq "filter") {
            return $self->error("Value not specified for FK field \"".$field->{FIELD}."\"") if is_empty($field->{VALUE});
            $form->addfields($field) or return $self->error($form->getError());
        };
    };
    
    $form->param($self->{_idname},$id);
    $form->loadData() or return $self->error($form->getError());
    
    my $oldsuffix = undef;
    if (defined $self->{_searchconfig}) {
        $oldsuffix = $self->getIndexSuffixFromFormAndMask($form,$self->{_searchconfig}->{SUFFIXMASK});
        return $self->showError() if ($self->cms()->getError('') ne "");
    };
    
    #$form->setFormValues();
    
    my $ret = $sub->($form);
    unless ($ret) {
        $form->cleanUploadedFiles();
        return $ret;  
    };
    
    my $fa = "update";
    $self->afterSetFormValues($form,$fa);
    
    $form->StandartCheck();
    $self->checkData($form,$fa);
    if (!$form->has_err_msgs()) {
        my $ret = $self->prepareData($form,$fa);
        if ($ret != NG::Block::M_OK) {
            $form->cleanUploadedFiles();
            return $ret;
        };
    };

    if ($form->has_err_msgs()) {
        $form->cleanUploadedFiles();
        #if ($is_ajax) {
        #    return $self->output($form->ajax_showerrors());
        #}
        #else {
        #    $form->print($self->tmpl()) or return $self->error($form->getError());
        #    return $self->output($self->tmpl()->output());
        #};
        return $self->error($form->getErrorString()||'При обработке формы возникли ошибки');
    };

    $self->beforeInsertUpdate($form,$fa) or return $self->showError("processCheckbox(): Ошибка вызова beforeInsertUpdate()");
    ## Update
    $form->updateData() or return $self->error($form->getError());
    $self->_updateVersionKeys($form,$fa);
    if (defined $self->{_searchconfig}) {
        my $suffix = $self->getIndexSuffixFromFormAndMask($form,$self->{_searchconfig}->{SUFFIXMASK});
        return $self->showError() if ($self->cms()->getError('') ne "");
        if ($oldsuffix && $suffix ne $oldsuffix) {
            $self->_updateIndex($oldsuffix) or return $self->showError("processCheckbox(): Ошибка обновления индекса");
        };
        $self->_updateIndex($suffix) or return $self->showError("processCheckbox(): Ошибка обновления индекса");
    };
    $self->afterInsertUpdate($form,$fa) or return $self->showError("processCheckbox(): Ошибка вызова afterInsertUpdate()");

    $id = $form->getParam($self->{_idname});
    $self->_makeEvent($fa,{ID=>$id});
    
    return 1;
};

sub Delete {
    my $self=shift;
    my $action=shift;
    my $is_ajax=shift;

    return $self->error("У вас нет прав для выполнения данного действия.") if (!$self->hasDeletePriv());

    my $q = $self->q();
    my $form = NG::Form->new(
        FORM_URL  => $self->q()->url()."?action=deletefull",
        KEY_FIELD => $self->{_idname},
        DB        => $self->db(),
        TABLE     => $self->{_table},
        DOCROOT   => $self->getDocRoot(),
        SITEROOT  => $self->getSiteRoot(),
        CGIObject => $q,
        REF       => $q->param('ref') || "",
        IS_AJAX   => $is_ajax,
        OWNER     => $self,
    );
    $form->addfields($self->{_fields}) or return $self->error($form->getError());
    $form->setFormValues(); # Чо за гон а кто будет параметры fkparent пихать в форму
    $self->{_idname} or return $self->showError("Delete(): Не найдено имя ключевого поля id");

    my $id = $q->param($self->{_idname});
    $form->param($self->{_idname},$id);

    $self->opentemplate("admin-side/common/deleteform.tmpl") || return $self->showError("Delete(): не могу открыть шаблон");
    $self->tmpl()->param(DELETE_MESSAGE=>"Вы действительно хотите удалить запись?");

    my $ret = $self->checkBeforeDelete($id);
    if ($ret == NG::Application::M_ERROR) {
        my $e = $self->cms->getError();
        $form->hideButtons();
        $form->addCloseButton({IMG => "/admin-side/img/buttons/close.gif"});
        $self->tmpl()->param(
            DELETE_MESSAGE => $e,
        );
        if ($action eq "deletefull" && $is_ajax) {
            #Форма уже отображена
            return $self->output("<script type='text/javascript'>parent.document.getElementById('error_".$form->getComposedKeyValue()."').innerHTML='".$e."';</script>");
        };
    }
    else {
        if($action eq "deletefull") {
            $self->beforeDelete($id) or return $self->showError("Delete(): Ошибка вызова beforeDelete()");
            $form->Delete() or return $self->error($form->getError());
            #TODO: Do $form->loadData() ?
            $self->_updateVersionKeys($form,'delete');
            if(defined $self->{_searchconfig}) {
                my $suffix = $self->getIndexSuffixFromFormAndMask($form,$self->{_searchconfig}->{SUFFIXMASK});
                return $self->showError() if ($self->cms()->getError('') ne "");
                $self->_updateIndex($suffix) or return $self->showError("Delete(): Ошибка обновления индекса");
            };
            $self->afterDelete($id,$form) or return $self->showError("Delete(): Ошибка вызова AfterDelete()");
            $self->_makeEvent('delete',{ID=>$id});
            $self->_makeLogEvent({operation=>"Удаление записи",operation_param=>"KEY ".$id});
            return $self->redirect(uri_unescape($q->param("ref")));
        };
        $form->hideButtons();
        $form->addButton({
             TITLE => "Удалить",
             IMG => "/admin-side/img/buttons/delete.gif",
             VALUE => "delete",
        });
        $form->addCloseButton();
    };
    
    #Формируем сокращенную форму из ключевых полей
    my @elements = ();   # Массив  
    foreach my $field (@{$form->keyfields()}) {
        $field->prepareOutput() or return $self->error($field->error());
        return $self->error("Не найдено значение ключевого поля ".$field->{FIELD}) if (is_empty($field->{VALUE}));
        push @elements, $field->param();
    };
    
    my $tmpl = $self->tmpl();
    $tmpl->param(
        FORM => {
            ELEMENTS   =>\@elements,
            BUTTONS    => $form->{_buttons},
            #ERRORMSG   => $globalError,
            URL         => $self->q()->url()."?action=deletefull",
            KEY_VALUE  =>$form->getComposedKeyValue(),
            KEY_PARAM  =>$form->_getKeyURLParam(),
            #CONTAINER  =>$form->{_container},
            REF        =>$form->{_ref},
            IS_AJAX    =>$form->{_ajax},
            #PREFIX     => $form->{_prefix},
            #HAS_ERRORS => $form->has_err_msgs()
        },
    );
    #$form->print($self->tmpl()) or return $self->error($form->getError());
    return $self->output($self->tmpl()->output());
};

sub _maDeleteRecords {
    my ($self,$maction,$ids) = (shift,shift,shift);
    
    return $self->error("У вас нет прав для выполнения данного действия.") if (!$self->hasDeletePriv());
    
    foreach my $id (@$ids) {
        my $ret = $self->checkBeforeDelete($id);
        if ($ret == NG::Application::M_ERROR) {
            my $e = $self->cms->getError();
            return $self->outputJSON({status=>'error', error=> 'Проверка перед удалением - ошибка:\n'.$e});
        };
    };
    
    $self->{_idname} or return $self->showError("Delete(): Не найдено имя ключевого поля id");

    my $q = $self->q();
    
    foreach my $id (@$ids) {
        my $form = NG::Form->new(
            FORM_URL  => '',
            KEY_FIELD => $self->{_idname},
            DB        => $self->db(),
            TABLE     => $self->{_table},
            DOCROOT   => $self->getDocRoot(),
            SITEROOT  => $self->getSiteRoot(),
            CGIObject => $q,
            REF       => '',
            IS_AJAX   => 1,
        );
        $form->addfields($self->{_fields}) or return $self->error($form->getError());
        $form->param($self->{_idname},$id);
        $self->beforeDelete($id) or return $self->showError("Delete(): Ошибка вызова beforeDelete()");
        $form->Delete() or return $self->error($form->getError());
        #TODO: Do $form->loadData() ?
        $self->_updateVersionKeys($form,'delete');
        if(defined $self->{_searchconfig}) {
            my $suffix = $self->getIndexSuffixFromFormAndMask($form,$self->{_searchconfig}->{SUFFIXMASK});
            return $self->showError() if ($self->cms()->getError('') ne "");
            $self->_updateIndex($suffix) or return $self->showError("Delete(): Ошибка обновления индекса");
        };   
        $self->afterDelete($id) or return $self->showError("Delete(): Ошибка вызова AfterDelete()");
        $self->_makeEvent('delete',{ID=>$id});
    };
    return $self->outputJSON({status=>'ok'});
};

 sub afterMove { my ($self, $id, $moveDir) = @_; }

sub Move {
    my $self = shift;
    my $is_ajax = shift;
    my $q = $self->q();
    my $db  = $self->db();
    my $dbh = $db->dbh();
    
    #TODO: hasEditPriv() требует параметр формы для проверки привилегий
    #TODO: проверить, ссылка позиционирования включается даже если нет привилегии на редактирование записи
    return $self->error("У вас нет прав для выполнения данного действия.") if (!$self->hasEditPriv($self->_getDF()));
    
    return $self->error('Действие недоступно.') if ($self->{_has_move_link} == 0) || ($self->{_hide_move_link} != 0);
  
    my $moveDir = $q->param('dir');
    my $id = $q->param($self->{_idname}) or return $self->error("Не найдено значение кода записи.");
    
    return $self->error("Некорректный запрос действия: неверно указано направление перемещения") unless ($moveDir eq "down") || ($moveDir eq "up");
    my $posField = $self->getPosField() or return $self->showError("Move(): поле позиционирования не найдено");   
    $self->processFKFields() or return $self->showError("Move(): Ошибка вызова processFKFields()"); # Если в описании таблицы есть FK, учитываем их в ссылках и SQL
    $self->processFilters()  or return $self->showError("Move(): Ошибка вызова processFilters()");
    #TODO: вызов processSorting с [] - это хак.
    $self->processSorting([])  or return $self->showError("Move(): Ошибка вызова processSorting()");
    
    die "Internal error:_shlistActiveOrder not defined." unless $self->{_shlistActiveOrder};
    my $found   = $self->{_shlistActiveOrder}->{ORDER};
    my $sortDir = $self->{_shlistActiveOrder}->{DIR};
    
    if ($sortDir eq "DESC") {
        if ($moveDir eq "up") {
            $moveDir = "down";
        }
        else {
            $moveDir = "up";
        };
    };

    my $posFieldName = $posField->{FIELD};
    my $idFieldName  = $self->{_idname};
    
    my @values = $self->getListSQLValues();
  
    my $table = $self->getListSQLTable();
    my $where = $self->getListSQLWhere();
    $where = "and $where" if $where;

    my $sth = $dbh->prepare("select $posFieldName from $table where $idFieldName=? $where") or return $self->error($DBI::errstr);
    unshift @values, $id;
    $sth->execute(@values) or return $self->error($DBI::errstr);
    my $currPos = $sth->fetchrow();
    return $self->error("Перемещаемая строка не найдена.") if !defined $currPos;
    $sth->finish();
    
    if ($moveDir eq "up") {
        shift @values;
        unshift @values,$currPos;
        $sth = $db->open_range("select $posFieldName from $table where $posFieldName < ? $where order by $posFieldName desc",0,1,@values) or return $self->error($DBI::errstr);
        my $prevPos = $sth->fetchrow();
        $sth->finish();
        
        return $self->redirect($q->param("ref")) unless $prevPos;
        
        $dbh->do("UPDATE $table set $posFieldName = -$posFieldName-1  where $posFieldName >= ? and $posFieldName < ?",undef,$prevPos,$currPos) or return $self->error($DBI::errstr);
        $dbh->do("UPDATE $table set $posFieldName = ? where $posFieldName = ?",undef,$prevPos,$currPos) or return $self->error($DBI::errstr);
        $dbh->do("UPDATE $table set $posFieldName = -$posFieldName where $posFieldName <= ? and $posFieldName > ?",undef,-$prevPos-1,-$currPos-1) or return $self->error($DBI::errstr);
    };
    
    if ($moveDir eq "down") {
        shift @values;
        unshift @values,$currPos;
        $sth = $db->open_range("select $posFieldName from $table where $posFieldName > ? $where order by $posFieldName ",0,1,@values) or return $self->error($DBI::errstr);
        my $nextPos = $sth->fetchrow();
        $sth->finish();
        
        return $self->redirect($q->param("ref")) unless $nextPos;
        
        $dbh->do("UPDATE $table set $posFieldName = -$posFieldName+1  where $posFieldName <= ? and $posFieldName > ?",undef,$nextPos,$currPos) or return $self->error($DBI::errstr);
        $dbh->do("UPDATE $table set $posFieldName = ? where $posFieldName = ?",undef,$nextPos,$currPos) or return $self->error($DBI::errstr);
        $dbh->do("UPDATE $table set $posFieldName = -$posFieldName where $posFieldName >= ? and $posFieldName < ?",undef,-$nextPos+1,-$currPos+1) or return $self->error($DBI::errstr);        
    };
    $self->_makeEvent('move',{ID=>$id, DIR=>$moveDir});
    #TODO: ugly solution....
    $self->_updateVersionKeys({$idFieldName => $id}, 'move');
    $self->afterMove($id, $moveDir);

    return $self->redirect($q->param("ref"));
};

#
# Подсистема привилегий
#
sub hasAddPriv {
    my $self = shift;
    my $aF = shift || return 0;
    return 0 unless $aF->{ADDLINKNAME};
    return $self->hasPriv($aF->{ADDPRIVILEGE}->{PRIVILEGE}) if ($aF->{ADDPRIVILEGE});
    return 1;
};

sub hasEditPriv {
    my $self = shift;
    my $aF = shift || return 0;
    return 0 unless ($aF->{EDITLINKNAME} || !$aF->{PREFIX});
    return $self->hasPriv($aF->{EDITPRIVILEGE}->{PRIVILEGE}) if ($aF->{EDITPRIVILEGE});
    return 1;
};

sub hasDeletePriv {
    my $self = shift;
    return $self->hasPriv($self->{_deletePriv}->{PRIVILEGE}) if ($self->{_deletePriv}->{PRIVILEGE});
    return 1;
};

#
# /Подсистема привилегий
#

#
#  Event-ы
#

sub _makeEvent {
    my $self = shift;
    my $ename = shift;
    my $eopts = shift;
    
    my $event = NG::Module::List::Event->new($self,$ename,$eopts);
    $self->cms()->processEvent($event);
};

##
##  Код, ответственный за индексирование блока
##

sub _updateIndex {
    my $self = shift;
    my $suffix = shift;
    
    my $mObj = $self->getModuleObj();
    return $self->error("moduleObj ".ref($mObj)." has no updateSearchIndex() method") unless $mObj->can("updateSearchIndex");
    return $mObj->updateSearchIndex($suffix);
};

sub getBlockIndex {
    my $self = shift;
    my $suffix = shift;

    return $self->showError("getBlockIndexes(): Ошибка вызова _analyseFieldTypes()") if ($self->_analyseFieldTypes() != NG::Block::M_OK);
    #return $self->error("Конфигурация модуля ".(ref $self)." не предусматривает работу в режиме блока страницы.") unless ($self->{_pageBlockMode}==1 || $self->{_linkBlockMode}==1);

    my $dbh = $self->db()->dbh();
    my $sc = $self->{_searchconfig} or return {};
    $sc->{SUFFIXMASK} ||= "";
    
    return {} unless $self->isMaskMatchSuffix($sc->{SUFFIXMASK},$suffix);
        
    return $self->error("Отсутвует значение категории индекса в конфигурации поиска") unless defined $sc->{CATEGORY};

    my $rFunc = undef;  #Метод, строящий индекс, если задан параметр RFUNC.

    if (exists $sc->{CLASSES}) {
        return $self->error('Cвойство CLASSES в конфигурации поиска не является HASHREF.') if (ref($sc->{CLASSES}) ne 'HASH');
        return $self->error('_getIndexes(): Отсуствует описание классов в свойстве CLASSES в конфигурации поиска.') unless scalar keys %{$sc->{CLASSES}};
        return $self->error('_getIndexes(): Одновременное использование CLASSES и RFUNC в конфигурации поиска недопустимо.') if exists $sc->{RFUNC};
        return $self->error('_getIndexes(): Без указания параметра RFUNC использование параметра RFUNCFIELDS невозможно.') if exists $sc->{RFUNCFIELDS};
    }
    elsif (exists $sc->{RFUNC}) {
        $sc->{CLASSES} = {};
        $rFunc = $sc->{RFUNC};
        return $self->error("_getIndexes(): Класс не содержит метода $rFunc, описанного в параметре RFUNC") unless $self->can($rFunc);
        return $self->error('_getIndexes(): В конфигурации поиска отсуствует параметр RFUNCFIELDS - описание списка полей для функции RFUNC.') unless $sc->{RFUNCFIELDS};
    }
    else {
        return $self->error('_getIndexes(): Без указания параметра RFUNC использование параметра RFUNCFIELDS невозможно.') if exists $sc->{RFUNCFIELDS};
        if (exists $sc->{DATAINDEXFIELDS}) { #Обратная совместимость с древним вариантом конфигурации поиска.
            return $self->error('Некорректное значение свойства DATAINDEXFIELDS в конфигурации поиска') if (ref($sc->{DATAINDEXFIELDS}) ne 'ARRAY');
            $sc->{CLASSES} = {};
            foreach my $t (@{$sc->{DATAINDEXFIELDS}}) {
                return $self->error('В списке полей свойства DATAINDEXFIELDS отсутствует имя поля') unless $t->{FIELD};
                return $self->error('В списке полей свойства DATAINDEXFIELDS отсутствует имя класса') unless $t->{CLASS};
                $sc->{CLASSES}->{$t->{CLASS}} ||= [];
                push @{$sc->{CLASSES}->{$t->{CLASS}}}, {FIELD=>$t->{FIELD}};
            }
            if ($sc->{PAGEINDEXFIELDS}) {
                return $self->error('Некорректное значение свойства PAGEINDEXFIELDS в конфигурации поиска') if (ref($sc->{PAGEINDEXFIELDS}) ne 'ARRAY');
                foreach my $t (@{$sc->{PAGEINDEXFIELDS}}) {
                    return $self->error('В списке полей свойства PAGEINDEXFIELDS отсутствует имя поля') unless $t->{FIELD};
                    return $self->error('В списке полей свойства PAGEINDEXFIELDS отсутствует имя класса') unless $t->{CLASS};
                    $sc->{CLASSES}->{$t->{CLASS}} ||= [];
                    push @{$sc->{CLASSES}->{$t->{CLASS}}}, {PFIELD=>$t->{FIELD}};
                }
            }
        }
        else {
            return $self->error('Не указаны свойства CLASSES или RFUNC в конфигурации поиска');
        };
    };

    #Формируем значения ключа индекса
    my $keys = undef;
    if (defined $sc->{KEYS}) {
        $keys = $sc->{KEYS};
    }
    else {
        if ($self->{_pageBlockMode}==1) {
            $keys||=[];
            push @{$keys}, "pageid";
        }
        elsif ($self->{_linkBlockMode}==1) {
            $keys||=[];
            push @{$keys}, "linkid";
            push @{$keys}, "langid" if ($self->{_has_pageLangId});
        }
        else {
            #Вверху будет проверка, и пустой массив не пройдет. Умирать тут не стоит.
        };
    };

    my $index = {};
    $index->{KEYS} = $keys;
    $index->{CATEGORY} = $sc->{CATEGORY};
    $index->{SUFFIX} = $suffix;
    
    #Получаем значения ключевых полей из суффикса
    my $keyValues = $self->getKeyValuesFromSuffixAndMask($suffix,$sc->{SUFFIXMASK});
    
    my $fieldObjs = {};
    #Заполняем ключевые поля данными
    foreach my $field (@{$self->{_fields}}) {
        next unless exists $keyValues->{$field->{FIELD}};
        my $v = $keyValues->{$field->{FIELD}};
        if ($field->{TYPE} eq "id") {
            $self->pushWhereCondition($field->{FIELD}."=?",$v);
        }
        elsif ($field->{TYPE} eq "fkparent") {
            # TODO: почему присваиваем в DEFAULT ??
            $field->{DEFAULT} = $v;
        }
        else {
            return $self->error("Поле ".$field->{FIELD}." не является fkparent или id. Значение ключа из суффикса не может быть игнорировано") unless exists $sc->{'SUFFIXFIELD'};
            if ($sc->{'SUFFIXFIELD'}->{$field->{FIELD}} eq "ignore") {
               #
            }
            elsif ($sc->{'SUFFIXFIELD'}->{$field->{FIELD}} eq "check") {
              $self->pushWhereCondition($field->{FIELD}."=?",$v);
            }
            else {
              return $self->error("Поле ".$field->{FIELD}." не является fkparent или id. Значение ключа из суффикса не может быть игнорировано.А еще SUFFIXFIELD какой-то не понятный :).");
            };
         };
        
        #Добавляем в список полей поля, описанные в суффиксе.
        #Их значения могут пригодиться в обработчиках, используются при обратном формировании суффикса.
        $fieldObjs->{$field->{FIELD}} = 1;
        delete $keyValues->{$field->{FIELD}};
    };
    return $self->showError("Ключи, выделенные из суффикса, не сопоставлены с полями таблицы данных:". join(' ',keys %{$keyValues})) if (scalar keys %{$keyValues});

    #Обрабатываем прочие ключевые поля, в т.ч filter, и выставленные ранее значения fkparent
    $self->processFKFields() or return $self->showError("_getIndexes(): Ошибка вызова processFKFields()"); # Если в описании таблицы есть FK, учитываем их в ссылках и SQL

    #Обрабатываем фильтры
    #Получаем список требуемых полей из фильтра
    my $filterRFunc=undef;
    my $filterFValues = {};
    if ($sc->{FILTER}) {
        my $filters;
        if (ref ($sc->{FILTER}) eq "ARRAY") {
            $filters = $sc->{FILTER};
        }
        elsif (ref ($sc->{FILTER}) eq "HASH") {
            $filters = [$sc->{FILTER}];
        }
        else {
            return $self->error('Некорректное значение свойства FILTER в конфигурации поиска');
        }
        foreach my $filter (@{$filters}) {
            if (exists $filter->{FUNC}) {
                my $fn = $filter->{FUNC};
                return $self->showError("_getIndexes(): Класс не содержит метода $fn, описанного в параметре FILTER.FUNC") unless $self->can($fn);
                #$self->setError("");
                my $v = undef;
                eval {
                    $v = $self->$fn($suffix);
                };
                return $self->error("_getIndexes(): Вызов метода $fn, описанного в параметре FILTER.FUNC, возвратил ошибку $@") if $@;
                unless ($v) {
                    my $e = $self->cms()->getError();
                    return $self->showError("_getIndexes(): Вызов метода $fn, описанного в параметре FILTER.FUNC, возвратил ошибку $e") if $e;
                    return $index;
                };
            }
            elsif (exists $filter->{RFUNC}) {
                return $self->showError("_getIndexes(): Возможно использование только одного параметра FILTER.RFUNC.") if $filterRFunc;
                $filterRFunc = $filter->{RFUNC};
                return $self->showError("_getIndexes(): Класс не содержит метода $filterRFunc, описанного в параметре FILTER.RFUNC") unless $self->can($filterRFunc);
            }
            elsif (exists $filter->{FIELD}) {
                my $fname = $filter->{FIELD} or return $self->showError("_getIndexes(): Не указано имя поля в параметре FILTER.FIELD конфигурации полнотекстового поиска.");
                if (exists $filter->{VALUE}) {
                    return $self->showError("_getIndexes(): Для фильтра по полю $fname значение параметра VALUE имеет некорректный тип ".(ref $filter->{VALUE})) if ref $filter->{VALUE};
                    $self->pushWhereCondition($fname."=?",$filter->{VALUE});
                }
                elsif (exists $filter->{VALUES}) {
                    #Включаем поле в список извлекаемых, для последующей проверки значений.
                    $fieldObjs->{$fname}= 1;
                    $filterFValues->{$fname}= $filter->{VALUES};
                }
                else {
                    return $self->showError("_getIndexes(): Не указаны проверяемые значения фильтра поля $fname в параметре FILTER.FIELD конфигурации полнотекстового поиска.")
                }
            }
            elsif (exists $filter->{WHERE}) {
                $self->pushWhereCondition($filter->{WHERE},$filter->{PARAMS});
            }
            else {
                return $self->showError("_getIndexes(): Неизвестный тип фильтра в параметре FIELD");
            };
        };
    };
    
    # Обрабатываем классы
    # Формируем список полей, на основе которых будем строить индекс
    # Вызываем нестрочные функции/методы
    my $clFuncValues = {};
    my $pFieldValues = {}; # Список значений требуемых полей из свойств страницы
    my $pFields      = {}; # Список полей свойств страницы, которые не найдены в основном хеше страницы
    my $pRow = $self->getPageRow();
    foreach my $class (keys %{$sc->{CLASSES}}) {
        my $ccfg = $sc->{CLASSES}->{$class};
        if (ref ($ccfg) eq "ARRAY") {
            #
        }
        elsif (ref ($ccfg) eq "HASH") {
            $ccfg = [$ccfg];
            $sc->{CLASSES}->{$class} = $ccfg;
        }
        else {
            return $self->error('Некорректное описание класса $class в свойстве CLASSES в конфигурации поиска');
        };
        
        foreach my $param (@{$ccfg}) {
            if (exists $param->{FIELD}) {
                my $fname = $param->{FIELD} or return $self->showError("_getIndexes(): Не указано имя поля в параметре CLASSES.$class.FIELD конфигурации полнотекстового поиска.");
                $fieldObjs->{$fname} = 1;
            }
            elsif (exists $param->{PFIELD}) {
                return $self->showError("_getIndexes(): Не указано имя поля страницы в параметре CLASSES.$class.PFIELD конфигурации полнотекстового поиска.") unless $param->{PFIELD};
                if (exists $pRow->{$param->{PFIELD}}) {
                    $pFieldValues->{$param->{PFIELD}} = $pRow->{$param->{PFIELD}};
                }
                else {
                    $pFields->{$param->{PFIELD}} = 1;
                };
            }
            elsif (exists $param->{TEXT}) {
                #
            }
            elsif (exists $param->{RFUNC}) {
                return $self->showError("_getIndexes(): Класс не содержит метода ".$param->{RFUNC}.", описанного в параметре CLASSES.$class.RFUNC") unless $self->can($param->{RFUNC});
            }
            elsif (exists $param->{FUNC}) {
                my $fn = $param->{FUNC};
                return $self->showError("_getIndexes(): Класс не содержит метода $fn, описанного в параметре CLASSES.$class.FUNC") unless $self->can($fn);
                #$self->setError("");
                my $v = undef;
                eval {
                    $v = $self->$fn($class,$suffix);
                };
                return $self->error("_getIndexes(): Вызов метода $fn, описанного в параметре CLASSES.$class.FUNC, возвратил ошибку $@") if $@;
                unless ($v) {
                    my $e = $self->cms()->getError();
                    return $self->showError("_getIndexes(): Вызов метода $fn, описанного в параметре CLASSES.$class.FUNC, возвратил ошибку $e") if $e;
                };
                $clFuncValues->{$class}->{$fn} = $v;
            }
            else {
                return $self->showError("_getIndexes(): Неизвестный тип правила формирования класса в параметре CLASS.$class");
            };
        };
    };
    
    
    #Догружаем требуемые поля из свойств страницы
    if (scalar keys %{$pFields}) {
        my $sqlfields = join(',',keys %{$pFields});
        $sqlfields =~ s/,$//;
        my $sql = "select $sqlfields from ng_sitestruct where id=?";
        my $row = $self->db()->dbh()->selectrow_hashref($sql,undef,$self->getPageId()) or return $self->showError("_getIndexes(): Ошибка получения свойств страницы: ".$DBI::errstr);
        foreach my $field (keys %{$pFields}) {
            $pFieldValues->{$field} = $row->{$field};
        };
    };
    
    #BEFORE/DATA/AFTER
    my $afterData = {}; # $afterData->{$class}
    my $beforeData = {}; # $beforeData->{$class}
    foreach my $class (keys %{$sc->{CLASSES}}) {
        my $ccfg = $sc->{CLASSES}->{$class};
        
        my $state = 0; # (0,1,2) == (before,data,after)
       
        my $classData = [];
        
        foreach my $param (@{$ccfg}) {
            my $loop = 0;
            if (exists $param->{FIELD} || exists $param->{RFUNC}) {
                $loop = 1;
            }
            elsif (exists $param->{PFIELD} || exists $param->{TEXT} || exists $param->{FUNC}) {
                $loop = 1 if exists $param->{LOOP} && $param->{LOOP} == 1;
            }
            else {
                return $self->showError("_getIndexes(): Неизвестный тип правила формирования класса в параметре CLASS.$class");
            };
            
            if ($state == 0 && $loop == 1) {
                $state = 1;
            }
            elsif ($state == 1 && $loop == 0) { # $state == 1 || $loop == 0
                $state = 2;
            };
            
            return $self->showError("_getIndexes(): Не могу сгруппировать правила класса $class") if ($state == 2 && $loop == 1);
            
            if ($state == 0 || $state == 2)  {
                my $v = "";
                if (exists $param->{PFIELD}) {
                    $v = $pFieldValues->{$param->{PFIELD}};
                }
                elsif (exists $param->{TEXT}) {
                    $v = $param->{TEXT};
                }
                elsif (exists $param->{FUNC}) {
                    $v = $clFuncValues->{$class}->{$param->{FUNC}};
                }
                else {
                    return $self->showError("_getIndexes(): state BEFORE or AFTER has invalid rule");
                };
                next unless $v;
                if ($state == 0) {
                    $beforeData->{$class} .= " " if ($beforeData->{$class});
                    $beforeData->{$class} .= $v;
                }
                else { # $state == 2
                    $afterData->{$class} .= " "  if ($afterData->{$class});
                    $afterData->{$class} .= $v;
                };
            }
            else { # $state == 1 
                push @{$classData},$param;
            };
        };
        $sc->{CLASSES}->{$class} = $classData;
    };

    if ($sc->{RFUNCFIELDS}) {
        #Часть полей может быть задана в фильтрах, совмещаем
        foreach my $field ( split /,/,$sc->{RFUNCFIELDS} ) {
            $fieldObjs->{$field} = 1;
        };
    };

    # Формируем строку запрашиваемых полей
    my $sqlfields = "";
    foreach my $field (keys %{$fieldObjs}) {
        $sqlfields .= $field.",";
        my $fh = $self->getField($field) or return $self->error("В списке полей модуля не найдено поле $field, описанное в конфигурации поиска");
        $fieldObjs->{$field} = NG::Field->new($fh, $self) or return $self->error("Ошибка создания объекта поля $field");
    };
    $sqlfields =~ s/,$//;
    
    my $table = $self->getListSQLTable();
    my $where = $self->getListSQLWhere();
    $where = ($where)?"where $where":"";
    my $order = $sc->{ORDER};
    $order = "order by $order" if $order;
    $order ||= "";
    
    my $sql = "select $sqlfields from $table $where $order";
    my $sth = $dbh->prepare($sql) or return $self->error($DBI::errstr);
    $sth->execute($self->getListSQLValues()) or return $self->error($DBI::errstr);
    #die "ooops!!!";
    while (my $row=$sth->fetchrow_hashref()) {
        # Вызываем фильтровую функцию
        if ($filterRFunc) {
            #$self->setError("");
            my $v = undef;
            eval {
               $v = $self->$filterRFunc($row,$suffix);
            };
            return $self->error("_getIndexes(): Вызов метода $filterRFunc, описанного в параметре FILTER.RFUNC, возвратил ошибку $@") if $@;
            unless ($v) {
                my $e = $self->cms()->getError();
                return $self->showError("_getIndexes(): Вызов метода $filterRFunc, описанного в параметре FILTER.RFUNC, возвратил ошибку $e") if $e;
                next;
            };
        };
        
        #Проверяем фильтры
        my $allowed = 1;
        foreach my $ffield (keys %{$filterFValues}) {
            my $found = 0;
            my $rv = $row->{$ffield};
            foreach my $v (@{$filterFValues->{$ffield}}) {
                if ($rv eq $v) {
                    $found = 1;
                    last;
                }
            };
            unless ($found) {
                $allowed = 0;
                last;
            };
        };
        next unless $allowed;
        
        #Строим строковый индекс
        if ($rFunc) {
            my $rowindex = undef;
            eval {
                $rowindex = $self->$rFunc($row);
            };
            return $self->error("_getIndexes(): Ошибка вызова метода $rFunc, описанного в параметре RFUNC: ".$@) if $@;
            return $self->showError("_getIndexes(): Ошибка вызова метода $rFunc, описанного в параметре RFUNC") unless $rowindex;
            next unless scalar keys %{$rowindex};

            return $self->showError("_getIndexes: Индекс, возвращенный getRowIndex() модуля ".ref($self)." возвратил неверный ключ DATA (не HASHREF).") if (ref $rowindex->{DATA} ne "HASH");
            if (exists $rowindex->{SUFFIX} && $rowindex->{SUFFIX} ne $suffix) {
                return $self->showError("_getIndexes: getRowIndex() возвратил неверный суффикс строки: '".$rowindex->{SUFFIX}."' не совпадает с ожидаемым ".$suffix.".");
            }
            next unless scalar keys %{$rowindex->{DATA}};

            foreach my $class (keys %{$rowindex->{DATA}}) {
                $index->{DATA}->{$class} .= " " if ($index->{DATA}->{$class});
                $index->{DATA}->{$class} .= $rowindex->{DATA}->{$class};
            };
        }
        else {
            my $rowFieldValues = {};
            foreach my $class (keys %{$sc->{CLASSES}}) {
                my $ccfg = $sc->{CLASSES}->{$class};
                my $cvalue = "";
                foreach my $param (@{$ccfg}) {
                    my $v = "";
                    if (exists $param->{FIELD}) {
                        my $fn = $param->{FIELD};
                        if (exists $rowFieldValues->{$fn}) {
                            $v = $rowFieldValues->{$fn};
                        }
                        else {
                            my $fieldObj = $fieldObjs->{$fn};
                            $fieldObj->setLoadedValue($row) or return $self->showError("_getIndexes(): Ошибка получения значения поля $fn для класса $class: ".$fieldObj->error());
                            $v = $fieldObj->searchIndexValue();
                            $rowFieldValues->{$fn} = $v;
                        };
                    }
                    elsif (exists $param->{PFIELD}) {
                        $v = $pFieldValues->{$param->{PFIELD}};
                    }
                    elsif (exists $param->{TEXT}) {
                        $v = $param->{TEXT};
                    }
                    elsif (exists $param->{RFUNC}) {
                        my $fn = $param->{RFUNC};
                        #$self->setError("");
                        eval {
                            $v = $self->$fn($row,$class,$suffix);
                        };
                        return $self->error("_getIndexes(): Вызов метода $fn, описанного в параметре CLASSES.$class.RFUNC, возвратил ошибку $@") if $@;
                        unless ($v) {
                            my $e = $self->cms()->getError();
                            return $self->showError("_getIndexes(): Вызов метода $fn, описанного в параметре CLASSES.$class.RFUNC, возвратил ошибку $e") if $e;
                        };
                    }
                    elsif (exists $param->{FUNC}) {
                        $v = $clFuncValues->{$class}->{$param->{FUNC}};
                    }
                    else {
                        return $self->showError("_getIndexes(): Неизвестный тип правила формирования класса в параметре CLASS.$class");
                    };
                    if ($v) {
                        $cvalue .= " " if $cvalue;
                        $cvalue .= $v;
                    };
                };
                $index->{DATA}->{$class} .= " " if ($index->{DATA}->{$class});
                $index->{DATA}->{$class} .= $cvalue;
            };
        };
    };
    $sth->finish();
    
    return $index unless scalar keys %{$index->{DATA}};

    foreach my $class (keys %{$beforeData}) {
        next unless $beforeData->{$class};
        $index->{DATA}->{$class} = " ".$index->{DATA}->{$class} if ($index->{DATA}->{$class});
        $index->{DATA}->{$class} = $beforeData->{$class}.$index->{DATA}->{$class};
    };
    
    foreach my $class (keys %{$afterData}) {
        next unless $afterData->{$class};
        $index->{DATA}->{$class} .= " " if ($index->{DATA}->{$class});
        $index->{DATA}->{$class} .= $afterData->{$class};
    };
    
    return $index;
};

##  /Код, ответственный за индексирование блока

sub getContentKey {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError("getContentKey(): Ошибка вызова _analyseFieldTypes()");
    return $self->{_contentKey};
}

sub _analyseFieldTypes {
    my $self = shift;
    
    return NG::Block::M_OK if ($self->{_fieldsAnalysed} == 1);
    $self->{_fieldsAnalysed} = 1;
    
    my ($has_pageId, $has_blockId, $has_tmplId) = (0,0,0);
    my ($has_pageLinkId,$has_subsiteId, $has_parentPageId,$has_parentLinkId) = (0,0,0,0);
    $self->{_contentKey} = "";
    foreach my $field (@{$self->{_fields}}) {
        unless ($field->{TYPE}){
            return $self->error("Ошибка конфигурации модуля ".ref($self).": Не указан тип поля ".$field->{FIELD});
        };
        if ($field->{TYPE} eq "id") {
            return $self->error("Ошибка в конфигурации: найдено два поля типа \"id\": ".$field->{FIELD}." и ".$self->{_idname}.".") if ($self->{_idname});
            $self->{_idname} = $field->{FIELD};
        };
        if ($field->{TYPE} eq "posorder"){
            return $self->error("Ошибка в конфигурации: найдено два поля типа \"posorder\": ".$field->{FIELD}." и ".$self->{_posField}->{FIELD}.".") if ($self->{_posField});
            $self->{_posField} = $field;
            $self->{_has_move_link} = 1;
            if ($field->{READONLY}) {
                $self->{_hide_move_link} = 1;
            };
        };
        if ($field->{TYPE} eq "pageLinkId") {
            $field->{VALUE} = $self->getPageLinkId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_pageLinkId  = 1;
        };
        if ($field->{TYPE} eq "pageLangId") {
            $field->{VALUE} = $self->getPageLangId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $self->{_has_pageLangId} = 1;
        };
        if ($field->{TYPE} eq "pageId") {
            $field->{VALUE} = $self->getPageId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_pageId  = 1;
        };
        if ($field->{TYPE} eq "subsiteId") {
            $field->{VALUE} = $self->getSubsiteId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_subsiteId = 1;
        };        
        if ($field->{TYPE} eq "blockId") {
            $field->{VALUE} = $self->getBlockId() or return $self->error("Значение для поля типа blockId не найдено, вероятно модуль вызван в режиме модуля страницы.");
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_blockId = 1;
        };
        if ($field->{TYPE} eq "parentPageId") {
            $field->{VALUE} = $self->getParentPageId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_parentPageId = 1;
        };
        if ($field->{TYPE} eq "parentLinkId") {
            $field->{VALUE} = $self->getParentLinkId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_parentLinkId = 1;
        };
        if ($field->{TYPE} eq "templateId") {
            #TODO: Мы не должны запрашивать код страницы для построения свойств поля типа rtf[file] если редактируем часть шаблона
            die ("Fields with type \"templateId\" is not supported yet by NG::Module::List.");
            #... ?
            $has_tmplId  = 1;
            next;
        };
    };
    # NB: видимо в будущем следует разделить два понятия - $has_pageLangId и $has_langId - для модуля и для блока/модуля страницы
    
    return $self->error("Ключевое поле в конфигурации модуля ".(ref $self)." не указано.") if (!defined $self->{_idname});
    
    #Эти поля берутся из свойств страницы, поэтому требуется отдельный флаг для проверки откуда нас вызвали
    $self->{_pageBlockMode} = 1 if ($has_pageId || $has_parentPageId  );
    $self->{_linkBlockMode} = 1 if ($has_pageLinkId || $self->{'_has_pageLangId'} || $has_subsiteId ||  $has_parentLinkId);
    $self->{_templateBlockMode} = 1 if ($has_tmplId);
    return $self->error("Ошибка в конфигурации модуля ".(ref $self)." - одновременная работа в режиме блока шаблона и блока страницы невозможна.")
        if (($self->{_pageBlockMode} || $self->{_linkBlockMode}) && $self->{_templateBlockMode});    # С учетом, что можно выставить флаг через конфиг.
    return $self->error("Ошибка в конфигурации модуля ".(ref $self)." - использование pageId или parentPageId исключает использование полей объединения страниц.")
        if ($self->{_pageBlockMode} && $self->{_linkBlockMode});
    # Одновременное использование subsiteId && pageLangId не запрещено, хотя и излишне.
    return $self->error("Ошибка в конфигурации модуля ".(ref $self)." - использование subsiteId исключает использование pageLinkId и parentLinkId.")	
        if ($has_subsiteId && ($has_pageLinkId || $has_parentLinkId));
        
    
    return NG::Block::M_OK;
}

sub getField {
    my $self = shift;
    my $fieldname = shift;
    
    return {NAME=>"№",TYPE=>"_counter_"} if ($fieldname eq "_counter_");
    
    foreach my $field (@{$self->{_fields}}) {
        return $field if $field->{FIELD} eq $fieldname;
    };
    return undef;
};

sub getPosField {
    my $self = shift;
    my $posField = $self->{_posField};
    return $posField if $posField;
    return undef; 
};

sub _pushCondition {
    my $self = shift;
    my $array = shift;
    my $sql = shift;
    my $fvalue = [];
    $fvalue = shift if (scalar @_);

    return unless $sql;
    my $pvalue = [];
    if (ref $fvalue eq 'ARRAY') {
        @{$pvalue} = (@{$fvalue});
    }
    else {
        foreach ($fvalue,@_) {
            push @{$pvalue}, $_;
        };
    };
    ## Можно хранить в двух массивах,
    #тогда удобнее выдавать массив параметров,
    #но теряется возможность удаления некоторого условия.    
    push @{$self->{$array}}, {
        SQL     => $sql,
        VALUES  => $pvalue,
    };
}; 
 
sub pushWhereCondition {
    my $self = shift;
    return $self->_pushCondition("_shlistWhere",@_);
};
    
sub pushSearchCondition {
    my $self = shift;
    return $self->_pushCondition("_shlistSearch",@_);
};


# Методы, влияющие на условия построения списка.
sub processFKFields {
    my $self = shift;
    
    #Из какого массива полей брать перечисление полей ?
    #Может ли ФК поле не участвовать в отображении списка ? - сейчас это значение обязательно. Если надо - перекрывайте метод.
    #Ранее был вариант что список полей брать из _listfields

    my $fkparam = "";
    foreach my $field (@{$self->{_fields}}) {
        if ($field->{TYPE} eq "fkparent") {
            my $param_value = $self->q()->param($field->{FIELD});
            if ($param_value !~ /^(?:0|[1-9][0-9]*)$/ && !defined ($param_value = $field->{DEFAULT})) {
                return $self->error("processFKFields(): Value not specified for fkparent field \"".$field->{FIELD}."\"");
            };
            $fkparam .= $field->{FIELD}."=".$param_value."&";
            $self->pushWhereCondition($field->{FIELD}."=?",$param_value);
        };
        if ($field->{TYPE} eq "filter") {
            my $param_value = $field->{VALUE};
            return $self->error("Value not specified for filter field \"".$field->{FIELD}."\"") if is_empty($param_value);
            $self->pushWhereCondition($field->{FIELD}."=?",$param_value);
        }
    };
    $fkparam =~ s/\&$//;
    $self->{_shlistFKParam} = $fkparam;
    return NG::Block::M_OK;
}

sub processFilters {
    my $self = shift;
    my $q = $self->q();
    foreach my $filter (@{$self->{_filters}}) {
        $filter->load() or return 0;
        $self->pushWhereCondition($filter->getWhereCondition(),$filter->getWhereParams());
    };
    return NG::Block::M_OK;
};

sub getListFilters {
    my $self = shift;
    
    return undef unless scalar @{$self->{_filters}};

    #Выбор значения в фильтре не должен менять FKParam или сортировку.
    my $fkp = $self->getFKParam();
    my $op  = $self->getOrderParam();
    
    my @filters = ();     #Массив фильтров, выводимый в полоске
    my $useForm = 0;      #Требуется ли обрамить вывод фильтров формой
    my $furlParams = "";  #Параметры, которые надо подставить в форму (фильтры, которые её не используют + $fkp + $op)
    foreach my $filter (@{$self->{_filters}}) {
        $filter->beforeOutput();
        my $fconfig = $filter->config();
#next unless $fconfig; #По идее, мы должны где-нибудь упасть, но явно тут не требуется тупой игнор. 
        
        my @params = ();
        foreach my $subf (@{$self->{_filters}}) {
            next if $subf eq $filter;
            push @params, $subf->getURLParams();
        };
        
        my $type = $filter->type();
        my $elements = $filter->elements();
        my $urlParams = $filter->getURLParams();
        if ($filter->useForm()) {
            $useForm = 1;
        }
        elsif ($urlParams) {
            $furlParams.="&" if $furlParams;
            $furlParams.= $urlParams;
        };
        push @filters, {
            NAME   => $fconfig->{NAME},
            ACTION => getURLWithParams($self->q()->url(),$self->getOrderParam(),$self->getFKParam(),@params),
            "TYPE_".uc($type)=>1,
            VALUES => $elements,
            FILTER_NAME => $fconfig->{FILTER_NAME},
        };
    };
    
    my @formparams = ();
    foreach my $pair ((split /&/,$furlParams),(split /&/,$op),(split /&/,$fkp)) {
        if ($pair =~ /(.+)=(.+)/) {
            push @formparams, {
                NAME  => $1,
                VALUE => $2,
            };
        };
    };

    return {
        ACTION => $self->q()->url(),
        PARAMS => \@formparams,
        LIST   => \@filters,
        USE_FORM => $useForm,
    };
};

sub processSorting {
    my $self = shift;
    my $listfields = shift or confess "processSorting(): incorrect usage";
    
    my $q = $self->q();

    my $posField = $self->getPosField();
    if ($posField) {
        push @{$listfields}, $posField;
        my $order = {};
        $order->{FIELD} = $posField->{FIELD};
        $order->{DEFAULTBY} = "DESC" if $posField->{REVERSE};
        unshift @{$self->{_orders}}, $order;
    };

    my $orderfield = "";
    my $dir;
    if ($q->url_param('asc')) {
        $orderfield = $q->url_param('asc');
        $dir = "ASC";
    }
    elsif ($q->url_param('desc')) {
        $orderfield = $q->url_param('desc');
        $dir = "DESC";
    };
    return NG::Block::M_OK unless scalar @{$self->{_orders}};
    my $default=undef;
    my $found = undef;
    foreach my $iorder (@{$self->{_orders}}) {
        if ($iorder->{FIELD} eq $orderfield){
            $found = $iorder;
        };
        
        return $self->error("Некорректная конфигурация модуля: найдено две записи сортировки по умолчанию.") if ($iorder->{DEFAULT} && $default);
        $default = $iorder if ($iorder->{DEFAULT});
    };
    return $self->error("Не найдено соответствующее запросу поле сортировки.") if ($dir && !defined $found);
    
    $default ||= @{$self->{_orders}}[0];
    
    unless ($dir) {
        $found = $default;
        $dir = $default->{DEFAULTBY} || "ASC";
    };
    $self->{_shlistActiveOrder} = {ORDER=>$found, DIR=>uc($dir)};

    # Запрещаем позиционирование, если сортировка не по полю позиции
    $self->{_hide_move_link} = 1 if ($posField && ($found->{FIELD} ne $posField->{FIELD}));

    return NG::Block::M_OK;
};

#Методы построения URL-адресов списка, возвращают куски вида param=value
sub getFKParam     { return shift->{_shlistFKParam};     };
sub getOrderParam  {
    my $self = shift;
    #return "" if (scalar @{$self->{_orders}} == 1);
    return "" unless $self->{_shlistActiveOrder};
    my $aOrder = $self->{_shlistActiveOrder};
    return lc($aOrder->{DIR})."=".$aOrder->{ORDER}->{FIELD};
};

sub getFilterParam {
    my $self = shift;
    my @urls = ();
    foreach my $filter (@{$self->{_filters}}) {
        push @urls , $filter->getURLParams();
    };
    return join("&",@urls);
};

#Методы построения списка
sub getListColumns {
    my $self = shift;
    my $listfields = shift or die "getListColumns(): incorrect usage";
    
    # Составляем строку-список запрашиваемых полей. При этом контролируем вхождение туда ключевого поля.
    my @columns=();
    my $fields = "";
    my $idfound = 0;
    foreach my $field (@{$listfields}) {
        $idfound = 1 if ($field->{TYPE} eq "id");
        push @columns,$field unless ($field->{TYPE} eq "hidden");  # Не включаем в список на отображение
        next if ($field->{FIELD} eq "_counter_");                  ## не включаем в список на выборку
        next if ($field->{'IS_FAKEFIELD'}); #не включаем в выборку вычисляемые поля
        $fields .= ",".$field->{FIELD};
        $field->{IS_POSORDER} = 1 if ($field->{TYPE} eq "posorder");
        $field->{ORDER} = getURLWithParams($field->{ORDER},$self->getFilterParam(),$self->getFKParam()) if ($field->{ORDER});
    };
    
    if ($idfound == 0) {
        $fields .= ",".$self->{_idname}; # Если ключевое поле не найдено
        push @{$listfields}, {
            TYPE=>"hidden",
            FIELD=>$self->{_idname},
            NAME=>$self->{_idname},
        };
    };
    $fields =~ s/^,//;
    $self->{_shlistFields} = $fields;
    return @columns;
};

sub highlightSortedColumns {
    my $self = shift;
    my $listfields = shift or confess "highlightSortedColumns(): incorrect usage";
    #Подсветка столбцов, по которым можно делать сортировку
    
    #Если есть несколько столбцов, значит есть дефолтный, значит есть активный
    return NG::Block::M_OK unless $self->{_shlistActiveOrder};
    my $found = $self->{_shlistActiveOrder}->{ORDER};
    my $dir   = $self->{_shlistActiveOrder}->{DIR};
    
    my $myurl = $self->q()->url();
    foreach my $iorder (@{$self->{_orders}}) {
        #Ищем соответствующее поле
        my $field = undef;
        foreach (@{$listfields}) {
            if ($_->{FIELD} eq $iorder->{FIELD})  {
                $field = $_;
                last;
            }
        }
        if (!defined $field) {
            last if (scalar @{$self->{_orders}} == 1);
            return $self->error("Некорректная конфигурация модуля: поле сортировки не найдено в списке столбцов");
        };
    
        if ($iorder->{FIELD} eq $found->{FIELD}) {
            #$field->{SELECTED_ORDER} = 1;
            $field->{"SELECTED_".$dir} = 1;
            if ($dir eq "ASC") {
                $field->{ORDER} = getURLWithParams($myurl,"desc=".$iorder->{FIELD},$self->getFKParam(),$self->getFilterParam());
            } elsif ($dir eq "DESC") {
                $field->{ORDER} = getURLWithParams($myurl,"asc=".$iorder->{FIELD},$self->getFKParam(),$self->getFilterParam());
            };
        }
        else {
            $iorder->{DEFAULTBY} ||= "ASC";
            $field->{ORDER} = getURLWithParams($myurl,lc($iorder->{DEFAULTBY})."=".$iorder->{FIELD},$self->getFKParam(),$self->getFilterParam());
        };
    };
    return NG::Block::M_OK;
};

#sub getListHeaders {  ## Prototype only
#    
#};

#Методы для компоновки SQL-запроса отображения списка
sub getListSQLFields {
    my $self = shift;
    die "Variable \"shlistFields\" is not initialised. Probally you need call getListColumns() method." if !defined $self->{_shlistFields};
    return $self->{_shlistFields};
};

sub getListSQLTable {
    my $self = shift;
    return $self->{_table};
};

sub getListSQLWhere {
    my $self = shift;
    my $where = "";
    foreach (@{$self->{_shlistWhere}}) {
        $where .= " and (".$_->{SQL}.")";
    };
    
    foreach (@{$self->{_shlistSearch}}) {
        $where .= " and (".$_->{SQL}.")";
    };
    
    $where =~ s/and\ //;
    return $where;
};

sub getListSQLValues {
    # Возвращает массив или указатель на массив 
    my $self = shift;
    my @param = ();
    foreach (@{$self->{_shlistWhere}}) {
        push @param, @{$_->{VALUES}} if scalar @{$_->{VALUES}};
    };

    foreach (@{$self->{_shlistSearch}}) {
        push @param, @{$_->{VALUES}} if scalar @{$_->{VALUES}};
    };

    return wantarray ? ():[] unless scalar @param;
    return wantarray ? @param:\@param; 
};

sub getListSQLOrder {
    my $self = shift;
    return "" unless $self->{_shlistActiveOrder};
    my $found = $self->{_shlistActiveOrder}->{ORDER};
    my $dir   = $self->{_shlistActiveOrder}->{DIR};

    return "order by ".$found->{"ORDER_$dir"} if ($found->{"ORDER_$dir"});
    return "order by ".$found->{FIELD}." ".$dir;
};

sub buildSearchWhere {
	my ($self,$sform) = (shift,shift);
	foreach my $field (@{$sform->{_fields}}) {
		next unless $field->{VALUE};
		my $type = $field->{TYPE};
		if ($type eq "datetime" && is_valid_date($field->{VALUE})) {
			$self->pushSearchCondition($field->{FIELD}." between ? and ?",[$self->db()->date_to_db($field->{VALUE})." 00:00:00",$self->db()->date_to_db($field->{VALUE})." 23:59:59"]);
		};
		if ($type eq "date" && is_valid_date($field->{VALUE})) {
			$self->pushSearchCondition($field->{FIELD}."=?",[$self->db()->date_to_db($field->{VALUE})]);
		};
		if ($type eq "text") {
			if ($self->db()->isa("NG::DBI::Postgres")) {
				$self->pushSearchCondition($field->{FIELD}." ilike ?",["%".$field->{VALUE}."%"]);
			} elsif ($self->db()->isa("NG::DBI::Mysql")) {
				$self->pushSearchCondition($field->{FIELD}." like ?",["%".$field->{VALUE}."%"]);
			};
		};
	};
};

sub getDeleteLink {
	my $self = shift;
	if ($self->hasDeletePriv() && $self->{_has_delete_link} == 1) {
		my $idn = $self->{_idname};
		return {
			NAME => $self->{_delete_link_name},
			#FKParam & FilterParam are used in delete link as they are key fields.
			URL  => getURLWithParams($self->getBaseURL().$self->getSubURL()."?action=delete&$idn={$idn}",$self->getFKParam(),$self->getFilterParam()),
			AJAX => 1,
		};
	};
	return undef;
};

sub getExtraLinks {
	my $self = shift;
	return $self->{_extra_links};
};

sub getPagesParam {
	my $self = shift;
	return $self->{_shlistPageParam};
}

sub setPagesParam {
	#TODO: review this method
	my $self = shift;
	my $page = shift || (is_valid_id($self->q()->url_param("page"))?$self->q()->url_param("page"):1);
	$self->{_shlistPageParam} = "page=".$page;
};

=comment

#
# Method obsoleted and removed from codebase.
# BW compat code (without getSearchParam() params) can be uncommented if strongly needed.

sub buildRefCurrentUrl {
	my $self = shift;
	
	my $refurl = getURLWithParams($self->getBaseURL().$self->getSubURL(),$self->getPagesParam(),$self->getFKParam(),$self->getFilterParam(),$self->getOrderParam());
	return uri_escape($refurl);
};
=cut

sub getSearchParam {
	my ($self,$sform) = (shift,shift);
	
	$sform or die "getSearchParam(): search form object parameter is missing!";
	
	my $url = "";
	foreach my $field (@{$sform->{_fields}}) {
		next unless $field->{VALUE};
		next if $field->{FIELD} eq "_search";
		$url .= $field->{FIELD}."=".uri_escape($field->{VALUE})."&";
	};
	return "" unless $url;
	#$url =~ s/\&$//;
	$url.="_search=1";
	return $url;
};

sub createSearchForm {
	my $self = shift;
	
	return $self->{_searchform} if defined $self->{_searchform};
	$self->{_searchform} = 0;
	return 0 unless scalar @{$self->{_searchfields}};
	
	my $action = getURLWithParams($self->getBaseURL().$self->getSubURL(),$self->getFKParam(),$self->getFilterParam());
	my $sform = NG::Form->new(
		FORM_URL  => $action,
		DOCROOT   => $self->getDocRoot(),
		CGIObject => $self->q(),
		DB        => $self->db(),
		OWNER     => $self,
	);
	
	my $fs = $self->_getIntersectFields($self->{_searchfields}) or return $self->showError("_getIntersectFields(): неизвестная ошибка вызова.");
	$sform->addfields($fs) or return $self->error($sform->getError());
	
	$sform->setFormValues();
	$sform->setTitle("Поиск");
	$sform->addfields({FIELD=>"_search",TYPE=>"hidden",VALUE=>"1"});
	
	$self->{_searchform} = $sform;
	return $self->{_searchform};
};

sub showSearchForm { #Action!
	my ($self,$action,$is_ajax) = (shift,shift,shift);
	
	return $self->showError('showSearchForm(): No search fields configured!') unless scalar @{$self->{_searchfields}};
	#return $self->showError('showSearchForm(): Non-AJAX load not supported') unless $is_ajax;
	
	#Если в описании таблицы есть FK, учитываем их в ссылках и SQL (createSearchForm() использует getFKParam() и getFilterParam())
	$self->processFKFields() or return $self->showError("showSearchForm(): Ошибка вызова processFKFields()");
	$self->processFilters() or return $self->showError("showSearchForm(): Ошибка вызова processFilters()");
	$self->processSorting([]) or return $self->showError("showSearchForm(): Ошибка вызова processSorting()");
	
	my $sform = $self->createSearchForm() or return $self->showError("showSearchForm(): Ошибка вызова createSearchForm()");

	$sform->{_ajax} = $is_ajax;
	my $tmpl = $self->gettemplate($self->{_searchformtemplate});
	$tmpl->param(CANCEL_SEARCH_URL => getURLWithParams($self->getBaseURL().$self->getSubURL(),$self->getFilterParam(),$self->getFKParam(),$self->getOrderParam()));
	$sform->print($tmpl);
	return $self->output($tmpl);
};

sub _updateVersionKeys {
    my ($self,$form,$fa) = (shift,shift,shift);
    
    return unless $self->{_versionKeys};
    
    my $cms  = $self->cms();
    my $mObj = $self->getModuleObj() or die "ASSERT: Unable to getModuleObj()!";

    my $params = {};
    #Ugly solution for $fa 'move'
    if (ref $form eq 'HASH') {
        $params = $form;
        $form = NG::Form->new(
            FORM_URL  => '',
            KEY_FIELD => $self->{_idname},
            DB        => $self->db(),
            TABLE     => $self->{_table},
            DOCROOT   => $self->getDocRoot(),
            SITEROOT  => $self->getSiteRoot(),
            CGIObject => $self->q(),
            REF       => '',
            IS_AJAX   => 1,
        );
        $form->addfields($self->{_fields}) or return $self->error($form->getError());
        $form->param($self->{_idname},$params->{$self->{_idname}});
        $form->loadData() or die $form->getError();
    };
    my @vk = map +{%$_}, @{$self->{_versionKeys}};
    foreach my $vk (@vk) {
        foreach my $key (keys %$vk) {
            if (ref $vk->{$key} eq 'CODE') {
                my $sub = $vk->{$key};
                $vk->{$key} = &$sub($form,$fa);
                next;
            };
            while ($vk->{$key} =~ /\{(.+?)\}/i) {
                my $value = undef;
                if (exists $params->{$1}) {
                    $value = $params->{$1};
                }
                else {
                    $value = $params->{$1} = $form->getParam($1);
                };
                $vk->{$key} =~ s/\{(.+?)\}/$value/i;
            };
        };
    };
    $cms->updateKeysVersion($mObj,\@vk);
};

#
# Интеграция в CMS
#

sub pageBlockAction {
    my ($self,$is_ajax) = (shift,shift);
    
    $self->_analyseFieldTypes() or return $self->showError("pageBlockAction(): Ошибка вызова _analyseFieldTypes()");
    return $self->error("Конфигурация модуля ".(ref $self)." не предусматривает редактирования блоков страницы.") unless ($self->{_pageBlockMode}==1 || $self->{_linkBlockMode}==1);
    
    return $self->run_actions($is_ajax);
}

sub blockAction {
    my ($self,$is_ajax) = (shift,shift);
    
    $self->_analyseFieldTypes() or return $self->showError("blockAction(): Ошибка вызова _analyseFieldTypes()");
    return $self->error("Конфигурация модуля ".(ref $self)." не предусматривает его работу в режиме CMS-модуля .") if ($self->{_pageBlockMode}==1 || $self->{_templateBlockMode}==1 || $self->{_linkBlockMode}==1);
    return $self->run_actions($is_ajax);
}

sub canEditPageBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError("canEditPageBlock(): Ошибка вызова _analyseFieldTypes()");
    return $self->{_pageBlockMode};
};

sub canEditLinkBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError("canEditLinkBlock(): Ошибка вызова _analyseFieldTypes()");
    return $self->{_linkBlockMode};
};

sub isLangLinked {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->{_has_pageLangId};
};

sub initialised {
    my $self=shift;
    return 1;
};

sub destroyPageBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError("destroyPageBlock(): Ошибка вызова _analyseFieldTypes()");
    return $self->error("Модуль ".(ref $self)." не поддерживает работу в режиме модуля страницы.") unless $self->{_pageBlockMode};
    return $self->_destroyBlock();
};

sub destroyLinkBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError("destroyLinkBlock(): Ошибка вызова _analyseFieldTypes()");
    return $self->error() unless $self->{_linkBlockMode};
    return $self->error("Модуль ".(ref $self)." не поддерживает работу в режиме модуля группы страниц.") unless $self->{_linkBlockMode};
    return $self->_destroyBlock();
};

sub _destroyBlock {
    my $self = shift;
    
    my $q = $self->q();
    my $dbh = $self->db()->dbh();
    
    #TODO: запрещаем удаление блока, если в описании полей присутствуют filter или fkparent поля
    $self->processFKFields() or return $self->showError("_destroyBlock(): Ошибка вызова processFKFields()");
   
    my $idFieldObj = $self->getField($self->{_idname}) or return $self->error("_destroyBlock(): Объект ключевого поля не найден");
    
    my $sth = $dbh->prepare("select ".$self->{_idname}." from ".$self->getListSQLTable()." where ".$self->getListSQLWhere()) or return $self->showError($DBI::errstr);
    $sth->execute($self->getListSQLValues()) or return $self->showError($DBI::errstr);
    while (my $v = $sth->fetchrow()) {
        $idFieldObj->{VALUE} = $v;
        
        my $form = NG::Form->new(
#            FORM_URL  => $formurl, #$q->url() + ?action=""
            KEY_FIELD => $self->{_idname},
            DB        => $self->db(),
            TABLE     => $self->{_table},
            DOCROOT   => $self->getDocRoot(),
            SITEROOT  => $self->getSiteRoot(),
            CGIObject => $q,
            REF       => $q->param('ref') || "",
#            IS_AJAX   => $is_ajax,
            OWNER     => $self,
        ) or return $self->showError("_destroyBlock(): Не могу создать форму");
        
        #NB: при конструировании формы создаваемые объекты полей развязаны с исходным конфигурационным хешем,
        #    т.е. единожды полученный массив хешей конфигов полей можно многократно применять в вызове $form->addfields()
        $form->addfields($self->{_fields}) or return $self->showError("_destroyBlock(): Ошибка вызова form->addfields()");
        
        $self->beforeDelete($v) or return $self->showError("_destroyBlock(): Ошибка вызова BeforeDelete()");
        $form->Delete() or return $self->error($form->getError());
        #TODO: Do $form->loadData() ?
        $self->_updateVersionKeys($form,'delete');
        $self->afterDelete($v,$form) or return $self->showError("_destroyBlock(): Ошибка вызова AfterDelete()");
    };
    $sth->finish();

    return NG::Block::M_OK;
};

sub _pushMPriv {
    my $self = shift;
    my $aPrivs = shift;
    my $hPrivs = shift;
    my $privHash = shift;

    return 0 unless (ref $privHash eq "HASH" && exists $privHash->{PRIVILEGE});
    unless (exists $hPrivs->{$privHash->{PRIVILEGE}}) {
        $hPrivs->{$privHash->{PRIVILEGE}} = $privHash;
        push @{$aPrivs}, $privHash;
    }
    else {
        $hPrivs->{$privHash->{PRIVILEGE}}->{NAME} ||= $privHash->{NAME};
    };
    return 1;
};

sub blockPrivileges {
    my $self = shift;
    my $aPrivs = [];
    my $hPrivs = {};
    foreach my $fm (@{$self->{_aForms}}) {
        if ($fm->{ADDPRIVILEGE}) {
            $self->_pushMPriv($aPrivs,$hPrivs, $fm->{ADDPRIVILEGE}) or return $self->error('modulePrivileges(): list form ('.$fm->{PREFIX}.') has incorrect ADD privilege hash');
        };
        if ($fm->{EDITPRIVILEGE}) {
            $self->_pushMPriv($aPrivs,$hPrivs, $fm->{ADDPRIVILEGE}) or return $self->error('modulePrivileges(): list form ('.$fm->{PREFIX}.') has incorrect EDIT privilege hash');
        };
    };
    if ($self->{_deletePriv}) {
        $self->_pushMPriv($aPrivs,$hPrivs,$self->{_deletePriv}) or return $self->error('modulePrivileges(): list has incorrect DELETE privilege hash');
    };
    return undef unless scalar @$aPrivs;
    return wantarray?@{$aPrivs}:$aPrivs;
};

#
# /Интеграция в CMS
#

#
# Конфигурационные методы
#

sub _getDF {
    # Метод возвращает хэш конфига дефолтной формы
    #
    my $self = shift;
    if (!scalar @{$self->{_aForms}} || @{$self->{_aForms}}[0]->{PREFIX} ) {
        my $aF = {
            PREFIX => "",
            FIELDS => [],
            EDITFIELDS => [],
            TITLE => "",
            EDITTITLE =>"",
            STRUCTURE => undef,
            EDITSTRUCTURE => undef,
            ADDLINKNAME => "Добавить",
            ADDPRIVILEGE => undef,
            EDITLINKNAME => "Редактировать",
            EDITPRIVILEGE => undef,
            TEMPLATE => "",
            DISABLEAJAX => 0,
            EDITLINKPARAMS => "",
        };
        unshift @{$self->{_aForms}}, $aF;
    };
    return @{$self->{_aForms}}[0];
};

sub disableAddlink {
    my $self = shift;
    $self->_getDF()->{ADDLINKNAME} = undef;
};

sub disableEditlink {
    my $self = shift;
    $self->_getDF()->{EDITLINKNAME} = undef;
};

sub disableDeletelink {
    my $self = shift;
    $self->{_has_delete_link} = 0;
};

sub disableMovelink {
    my $self = shift;
    $self->{_has_move_link} = 0;
};

sub additionalForm {
    my $self = shift;
    my $aF = shift;
    
    die "additionalForm(): AForm description is not specified" unless $aF;
    die "additionalForm(): AForm description is not HASHREF" unless ref $aF eq "HASH";
    
    die "additionalForm(): No PREFIX specified" unless $aF->{PREFIX};
    die "additionalForm(): No FIELDS specified" unless $aF->{FIELDS};
    
    $aF->{FIELDS} ||= [];
    $aF->{EDITFIELDS} ||= [];
    $aF->{TITLE} = "" if !defined $aF->{TITLE};
    $aF->{EDITTITLE} = "" if !defined $aF->{EDITTITLE};
    $aF->{ADDLINKNAME} = "" if !defined $aF->{ADDLINKNAME};
    $aF->{EDITLINKNAME} = "" if !defined $aF->{EDITLINKNAME};
    $aF->{DISABLEAJAX} ||= 0;
    
    die "additionalForm(): ADDPRIVILEGE is not HASH or scalar" if ref $aF->{ADDPRIVILEGE} && ref $aF->{ADDPRIVILEGE} ne "HASH";
    die "additionalForm(): EDITPRIVILEGE is not HASH or scalar" if ref $aF->{EDITPRIVILEGE} && ref $aF->{EDITPRIVILEGE} ne "HASH";
    $aF->{ADDPRIVILEGE} = { PRIVILEGE=> $aF->{ADDPRIVILEGE}} if $aF->{ADDPRIVILEGE} && ref $aF->{ADDPRIVILEGE} eq "";
    $aF->{EDITPRIVILEGE} = { PRIVILEGE=> $aF->{EDITPRIVILEGE}} if $aF->{EDITPRIVILEGE} && ref $aF->{EDITPRIVILEGE} eq "";
    
    #die "additionalForm(): No ADDLINKNAME or EDITLINKNAME" unless ($aF->{ADDLINKNAME} || $af->{EDITLINKNAME});
    
    push @{$self->{_aForms}}, $aF;
    return $aF; # Может быть использована в дальнейшем для изменения конфигурации формы
};

sub _setPriv {
    my $self = shift;
    my $target = shift;
    my $priv = shift;
    
    if (ref $priv eq "") {
        $priv = {PRIVILEGE=>$priv};
    }
    elsif (ref $priv ne "HASH"){
        die "_setPriv(): parameter is not valid reference";
    };
    die "_setPriv(): PRIVILEGE not defined" unless exists $priv->{PRIVILEGE};
    
    $$target ||= {};
    $$target->{PRIVILEGE} = $priv->{PRIVILEGE};
    $$target->{NAME} = $priv->{NAME} || "";
    return 1;
};
#TODO: проверить методы setAddPriv setEditPriv setDeletePriv
sub setAddPriv    { my $self = shift; return $self->_setPriv(\$self->_getDF()->{ADDPRIVILEGE},shift);  };
sub setEditPriv   { my $self = shift; return $self->_setPriv(\$self->_getDF()->{EDITPRIVILEGE},shift); };
sub setDeletePriv { my $self = shift; return $self->_setPriv(\$self->{_deletePriv},shift);             };

sub setFormStructure { my $self = shift; $self->_getDF()->{STRUCTURE} = shift; };
sub setFormTemplate  { my $self = shift; $self->_getDF()->{TEMPLATE} = shift;  };

sub disablePages {
    my $self = shift;
    $self->{_disablepages} = 1;
};

sub tablename {
    my $self = shift;
    $self->{_table} = shift;
};

sub _pushFields {
    my $self = shift;
    my $aRef = shift;
    
    my $ref = $_[0];
    if (ref $aRef ne "ARRAY") { die "aRef is not array ref in \$NG::Module::List->_pushFields()."; }; #TODO: fix msg
    if (!defined $ref) { die "Parameter not specified in \$NG::Module::List->_pushFields()."; }; #TODO: fix msg
    
    if (ref $ref eq 'HASH') {
        foreach my $tmp (@_) {
            push @{$aRef}, $tmp;
        };
    }
    elsif (ref $ref eq 'ARRAY') {
        foreach my $tmp (@{$ref}) {
            if (ref $tmp ne "HASH") { die "Invalid type" }; #TODO: fix msg
            push @{$aRef}, $tmp;
        };
    }
    else {
        die "NG::Module::List->fields(): invalid parameter type."; #TODO: fix msg
    };
};

sub fields     { my $self = shift; $self->_pushFields($self->{_fields},@_);     };
sub listfields { my $self = shift; $self->_pushFields($self->{_listfields},@_); };

sub formfields { my $self = shift; $self->_pushFields($self->_getDF()->{FIELDS},@_);  };
sub editfields { my $self = shift; $self->_pushFields($self->_getDF()->{EDITFIELDS},@_);  };

sub searchfields { my $self = shift; $self->_pushFields($self->{_searchfields},@_); };

sub filter {
    my $self = shift;
	my $filterObj = $self->cms()->getObject("NG::Module::List::Filters",$self,@_);
    push @{$self->{_filters}},$filterObj;
    return;
};

sub order {
    my $self = shift;
    die "Incorect parameters in order() call." if (scalar @_ == 0);
    
    if (ref $_[0] eq 'HASH') {      # Нам пришел список hashref
        @{$self->{_orders}} = (@_);
    }
    elsif (ref $_[0] eq 'ARRAY') {  # Надеемся что в массиве hashref-ы
        $self->{_orders} = $_[0];
    }
    else { # Пришла строка
        my $field = shift;
        my $order = shift || 'ASC';
        push @{$self->{_orders}}, {FIELD=>$field, 'DEFAULTBY'=>$order};
    };
};

sub searchConfig { my $self = shift; $self->{_searchconfig} = shift; };

sub multiactions {
    my $self = shift;
    $self->{_multiActions}||=[];
    $self->_pushFields($self->{_multiActions},@_);
};

sub updateKeysVersion {
    my $self = shift;
    $self->{_versionKeys}||=[];
    $self->_pushFields($self->{_versionKeys},@_);
};

sub add_url_field {
    my $self = shift;
    my $fieldname = shift;
    my $urlmask = shift;
    my $title = shift;
    foreach my $field (@{$self->{_fields}}) {
        if ($field->{FIELD} eq $fieldname) {
            $field->{URLMASK} = $urlmask;
            $field->{TITLE} = $title;
        };
    };
};

sub add_links {
    my $self = shift;
    my $name = shift;
    my $urlmask = shift;
    my $ajax = shift;
    push @{$self->{_extra_links}}, {NAME=>$name,URL=>$urlmask,AJAX=>$ajax};
    carp "WARNING: NG::Module::List::add_links() - method expired, please use addRowLink";
};

sub addRowLink {
    my $self = shift;
    my $link = shift;
    return $self->error("addRowLink: параметр не является HASHREF") if ref $link ne "HASH";
    return $self->error("addRowLink: отсутствует параметр NAME") unless $link->{NAME};
    return $self->error("addRowLink: отсутствует параметр URL") unless $link->{URL};
    push @{$self->{_extra_links}}, $link;
};

sub addTopbarLink {
    my $self = shift;
    my $link = shift;
    push @{$self->{_topbar_links}}, $link;
};

#
# /Конфигурационные методы
#

## Virtual methods

sub beforeBuildList    { return NG::Block::M_OK; };
sub afterBuildList     { return NG::Block::M_OK; };

sub afterInsertUpdate  { return NG::Block::M_OK; };
sub beforeInsertUpdate { return NG::Block::M_OK; };

sub checkData          { return NG::Block::M_OK; };
sub prepareData        { return NG::Block::M_OK; };

sub checkBeforeDelete  { return NG::Block::M_OK; };
sub beforeDelete { return NG::Block::M_OK; };
sub afterDelete  { return NG::Block::M_OK; };

sub afterFormLoadData  { return NG::Block::M_OK; };

sub afterSetFormValues { return NG::Block::M_OK; };

sub rowFunction {
	# $self = shift;
	# $row = shift;
	# $row->{field} = $row->{field} . " - proccess";
};

return 1;
END{};
