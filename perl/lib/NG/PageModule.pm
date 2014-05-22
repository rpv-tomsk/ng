package NG::PageModule;

use strict;
use NG::Module 0.5;
use NG::Application;

$NG::PageModule::VERSION=0.5;

use vars qw(@ISA);
@ISA = qw(NG::Module);

sub init {
	my $self = shift;
	
    my $opts = shift || {};
    
	$self->SUPER::init($opts,@_);
    
=comment
	$self->{_editableBlocks} = undef;  # Вкладки.
	$self->{_editableBlocks} = undef;  # Редактируемые блоки страницы
=cut
	$self->{_selectedModule} = undef;  # Модуль страницы, который выбран активным по ссылке запроса
	$self->{_modules} = undef;          # Все модули страницы
	$self;
};

##
##   Отработка запросов к морде
##

sub run {
	my $pageObj = shift;
    
    $NG::Application::pageObj = $pageObj;
	
	my $cms = $pageObj->cms();
    my $q = $pageObj->q();

    my $ret = undef;
    if ($q->request_method() eq "POST") {
        return $cms->error("Модуль ".(ref $pageObj)." не содержит метода processPost") unless $pageObj->can("processPost");
        $ret = $pageObj->processPost();
        return $ret if $ret != NG::Application::M_OK;
    };

    return $cms->error("Модуль ".(ref $pageObj)." не содержит метода showPage") unless $pageObj->can("showPage");
    return $pageObj->showPage();
};

sub processPost {
    my $self = shift;
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $dbh = $cms->db()->dbh();
    
    my $ctrl = $q->param("_controller") || "";
    
    my $mObj = undef;
    if (!$ctrl) {
        return $cms->error("Отправленный запрос не содержит значения параметра _controller") if $self->_isBaseClass();
        $mObj = $self;
    }
    else {
        $ctrl = uc($ctrl);
        $mObj = $cms->getModuleByCode($ctrl) or return $cms->defError("processPost():","Запрошенный контроллер $ctrl не найден");
    };
    
    return $cms->error("Модуль ".(ref $mObj)." не содержит метода processModulePost") unless $mObj->can("processModulePost");
    #return $cms->error("Модуль ".$row->{module}." не содержит метода processModulePost") if $self->can("processModulePost") eq $mObj->can("processModulePost");
    return $mObj->processModulePost();
};

sub showPage {
	my $pageObj = shift;
	my $cms = $pageObj->cms();
	return $cms->buildPage($pageObj);
}

sub getLayout {
    my $pageObj = shift;
    my $aBlock  = shift; #Active Block. #TODO: значение должно быть хешем, возвращенным из $pageObj->getActiveBlock();

    my $cms = $pageObj->cms();

    #Параметры поиска LAYOUT для вывода контента
    my $layoutConf = "LAYOUT";
    $layoutConf = "PRINTLAYOUT" if $cms->isPrint();
    
    my $langId = $pageObj->getPageLangId();
    my $subsiteId = $pageObj->getSubsiteId();
	
    my $layout = undef;
    if ($aBlock) {
        #NB: CODE is MODULECODE_ACTION
        #1. Считываем параметр layout блока для языка "BLOCK_{CODE}.LAYOUT_{LANG}|BLOCK_{CODE}.PRINTLAYOUT_{LANG}"
        $layout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf."_L".$langId,undef) if $langId;
        return $layout if defined $layout;
        #1.1 Считываем параметр layout блока для подсайта "BLOCK_{CODE}.LAYOUT_S{ID}|BLOCK_{CODE}.PRINTLAYOUT_S{ID}" 
        $layout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf."_S".$subsiteId,undef) if $subsiteId;
        return $layout if defined $layout;
        #2. Считываем параметр "BLOCK_{CODE}.LAYOUT|BLOCK_{CODE}.PRINTLAYOUT"
        $layout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf,undef);
        return $layout if defined $layout;
        #3. Берем параметр layout из параметров блока
        $layout = $aBlock->{$layoutConf} if exists $aBlock->{$layoutConf};
        return $layout if defined $layout;
    };
    #4. Берем параметр $pageRow->{template|printtemplate}
    $layout = $pageObj->{_pageRow}->{template} if $pageObj->{_pageRow} && !$cms->isPrint();
    return $layout if defined $layout;
    $layout = $pageObj->{_pageRow}->{print_template} if $pageObj->{_pageRow} && $cms->isPrint();
    return $layout if defined $layout;
    #5. Считываем параметр ЦМС "CMS.LAYOUT_{LANG}|CMS.PRINTLAYOUT_{LANG}"
    $layout = $cms->confParam("CMS.".$layoutConf."_L".$langId,undef) if $langId;
    return $layout if defined $layout;
    #5. Считываем параметр ЦМС "CMS.LAYOUT_S{SUBSITEID}|CMS.PRINTLAYOUT_S{SUBSITEID}"
    $layout = $cms->confParam("CMS.".$layoutConf."_S".$subsiteId,undef) if $subsiteId;
    return $layout if defined $layout;
    #6. Считываем параметр ЦМС "CMS.LAYOUT|CMS.PRINTLAYOUT"
    $layout = $cms->confParam("CMS.".$layoutConf,undef);
    #return $layout if defined $layout;
    return $layout;
};

=comment isActive
sub isActive {
	my $self = shift;
	return $self->getPageRow()->{active};
}
=cut

sub _getBlockId {
	my $self = shift;
	my $q = $self->cms()->q();
	my $subUrl = $self->getAdminSubURL();
	my $blockId = $subUrl=~ /^block(\d+)\// ? $1 : $q->param('_blockid');
	$blockId ||= "";
	return $blockId;
}

sub _isBaseClass {
	my $self = shift;
	#return 0 if (ref $self ne __PACKAGE__);
    return 0 if $self->pageParam('module_id');
	return 1;
}

sub _getTemplateBlocks {
	#TODO: Использовать getTemplateBlocks
    my $self = shift;
    
    return $self->{_modules} if $self->{_modules};

    my $cms = $self->cms();
    my $dbh = $self->dbh();
    
	my $tmplFile = $self->pageParam('template');
	return $cms->error('Для дефолтного контроллера требуется указанный шаблон') unless $tmplFile;

	#Аналогичный запрос в NG::PluginsController::loadPlugins
    my $sql = "
select b.id as block_id, b.name, b.module_id, m.module, m.base as module_base, m.code as module_code,m.name as module_name, m.params as module_params,
b.action, b.params, b.active, b.fixed, b.editable, b.type, tb.disabled
from ng_blocks b, ng_tmpl_blocks tb, ng_modules m
where m.id = b.module_id and tb.block_id = b.id and tb.template = ?";
	
    my $sth = $dbh->prepare($sql) or return $cms->error(__PACKAGE__."::_getTemplateBlocks(): ".$DBI::errstr);
    $sth->execute($tmplFile) or return $cms->error(__PACKAGE__."::_getTemplateBlocks(): ".$DBI::errstr);
    my $hr = $sth->fetchall_arrayref({}) or return $cms->error(__PACKAGE__."::_getTemplateBlocks(): ".$DBI::errstr);
    $sth->finish();
    
    $self->{_modules} = $hr;
    return $self->{_modules};
};

sub getPageTabs {
	my $self = shift;
    
    my $cms = $self->cms();
	
	my $baseUrl = $self->getAdminBaseURL();
	if ($self->_isBaseClass()) {
        #Страница сделана на основе шаблона.
        my $blocks = $self->_getTemplateBlocks() or return $cms->error();
        
		my @tabs = ();
        my $blockId = $self->_getBlockId();
        my $foundEBlock = 0;
        
        $self->{_selectedModule} = undef;
        
        my $getObj = sub {
            my $block = shift;
            
            my $mRow = {};
            $mRow->{id}     = $block->{module_id};
            $mRow->{code}   = $block->{module_code};
            $mRow->{module} = $block->{module};
            $mRow->{base}   = $block->{module_base};
            $mRow->{params} = $block->{module_params};
            $mRow->{name}   = $block->{module_name};
            
            return $cms->getObject($block->{module}, {
                ADMINBASEURL => $baseUrl."block".$block->{block_id}."/",
                PAGEPARAMS   => $self->getPageRow(),
                MODULEROW    => $mRow,
            });
        };
        
		foreach my $eblock (@{$blocks}) {
            next unless $eblock->{editable};
            $foundEBlock = 1;
            
            next unless $cms->hasPageModulePrivilege(MODULE_ID=>$eblock->{module_id}, PRIVILEGE=>"ACCESS",PAGE_ID=>$self->pageParam('id'),SUBSITE_ID=>$self->pageParam('subsite_id'));
            
            #Локально созданный таб
			my $tab = {
				HEADER   => $eblock->{name},
                URL       => $baseUrl."block".$eblock->{block_id}."/",
                AJAX_URL  => $baseUrl."block".$eblock->{block_id}."/?_ajax=1",
				#SELECTED => $eblock->{SELECTED},
				#NOT_INITIALISED => $eblock->{NOT_INITIALISED},
			};
            #Проверяем активность таба, выбираем активный блок
            $blockId ||= $eblock->{block_id};
            if ($blockId eq $eblock->{block_id}) {
                $tab->{SELECTED} = 1;
                return $cms->error("NG::PageModule: Обнаружена ошибка - два активных модуля") if $self->{_selectedModule};
            };
            
            my $mObj = undef;
            #Формируем объект, если нужны его табы или это его таб
            if ($eblock->{editable} == 2 || $tab->{SELECTED}) {
                $mObj = &$getObj($eblock) or return $cms->error();
                $self->{_selectedModule} = $mObj if $tab->{SELECTED};
            };
            if ($eblock->{editable} == 2) {
                my $mTabs = $mObj->getModuleTabs();
                return $mTabs if $mTabs eq "0"; #cms error
                return $cms->error((ref $mObj)."::getModuleTabs(): не вернул списка вкладок") unless ($mTabs && ref $mTabs eq "ARRAY");
                foreach (@$mTabs) {
                    $_->{SELECTED} = 0 unless $tab->{SELECTED}; #гасим вложенные табы
                    push @tabs, $_;
                };
                $tab = undef; #Больше не нужен
            };
			push @tabs, $tab if $tab;
		};
        
        unless ($self->{_selectedModule}) {
            while(1) {
                my $code = $cms->confParam("CMS.SiteStructModule","") or last;
                last unless $cms->hasPageStructAccess($self->pageParam('id'),$self->pageParam('subsite_id'));
                
                $self->{_selectedModule} = $cms->getModuleByCode($code, {
                    ADMINBASEURL => $baseUrl,
                    PAGEPARAMS   => $self->getPageRow(),
                }) or return $cms->error();
                return [{HEADER=>"Структура",URL=>"/",SELECTED=>1}];
            };
            return $cms->error("Отсутствуют привилегии редактирования элементов страницы") if $foundEBlock;
            return $cms->error("Редактируемые блоки отсутствуют");
        };
		return \@tabs;
	}
	else {
        #Страница сделана на основе модуля. Забираем вкладки из него.
        return $self->getModuleTabs();
	}
};

# getPageModules() используется NG::PagePrivs при построении редактора привилегий
sub getPageModules {
	my $self = shift;
	
	my $cms = $self->cms();
	
	#Если мы не базовый класс
	if (!$self->_isBaseClass()) {
		return undef;
		#Проверяем наличие перекрытого метода modulePrivileges, по возвращенному им результату
		#my $mp = $self->modulePrivileges();
		#if (defined $mp && ref $mp eq "ARRAY") {
		#	return [{
		#		MODULE_ID=> $self->moduleParam('id'),
		#		NAME     => $self->moduleParam('name'),
		#	}];
		#};
		#if (defined $mp && $mp == $NG::Application::M_ERROR) {
		#	my $e = $cms->getError("NG::PageModule::getPageModules(): Неизвестная ошибка вызова modulePrivileges");
		#	return $cms->error($e);
		#};
	};
	#Если в небазовом классе нет modulePrivileges, или класс базовый - то возвращаем модуля из блоков страницы
    return undef unless $self->pageParam('template') || $self->pageParam('module_id');
	return $cms->error("Модуль ".(ref $self)." не содержит метода modulePrivileges(), страница не является шаблонной".$self->pageParam('id')) unless $self->pageParam('template');
	
    my $blocks = $self->_getTemplateBlocks() or return $cms->error();
	
	my @result = ();
	foreach my $block (@{$blocks}) {
		next unless $block->{editable};
		push @result,{
			#MODULE_ID => $block->{module_id},
			#NAME      => $block->{module_name},
			CODE => $block->{module_code},
		};
	};
	return \@result;
};

sub adminPage { 
	my $self = shift;
	my $is_ajax = shift;
	my $cms = $self->cms();
	
	my $mObj = undef;

	if ($self->_isBaseClass()) {
        return $cms->error("Предполагалось, что вызов adminPage будет после вызова getPageTabs") unless $self->{_selectedModule};
        return $cms->error("Модуль ".(ref $self->{_selectedModule})." не содержит метода adminPageModule") unless $self->{_selectedModule}->can("adminPageModule");
        return $self->{_selectedModule}->adminPageModule($is_ajax);
	};
    return $self->adminPageModule($is_ajax);
};

##
##  Индексатор блочных страниц
##

sub checkIndex {
    my $self = shift;
    my $index = shift;
    my $suffix = shift;
    
    my $cms = $self->cms();
    
    return $cms->error("Отсутствует значение категории индекса.") unless defined $index->{CATEGORY};
    
    # В пришедших индексах проверяем суффикс, если индекс был запрошен с суффиксом.
    # ## expired ## Если запрошен индекс без суффикса - не проверяем, можно вернуть любой, в т.ч и пустой.
    return $cms->error("возвращенный суффикс (".$index->{SUFFIX}.") не совпадает с запрошенным ($suffix).") if ($suffix && ($index->{SUFFIX} ne $suffix));
    return $cms->error("Отсутствует описание ключей индекса.") unless $index->{KEYS};
	return $cms->error("Описание ключей индекса (KEYS) не является ARRAYREF.") unless ref($index->{KEYS}) eq "ARRAY";
    my ($linkId,$langId,$pageId) = (0,0,0);
    foreach my $key (@{$index->{KEYS}}) {
        $linkId = $self->getPageLinkId() if lc($key) eq "linkid";
        $langId = $self->getPageLangId() if lc($key) eq "langid";
        $pageId = $self->getPageId() if lc($key) eq "pageid";
    };
    return $cms->error("В ключах присутствует недопустимая комбинация pageid + langid.") if ($pageId && $langId);
    return $cms->error("В ключах присутствует недопустимая комбинация pageid + linkid.") if ($pageId && $linkId);
        
    $index->{KEYTYPE} = 0;
    $index->{KEYTYPE} += 1 if ($linkId);
    $index->{KEYTYPE} += 2 if ($langId);
    $index->{KEYTYPE} += 4 if ($pageId);
    $index->{KEYTYPE} += 8 if ($index->{SUFFIX});
    
	## LANGID используется либо как денормализационное поле в случае pageId, либо как ключевое в случае linkId
	$index->{LANGID} = $self->getPageLangId(); 
	if ($linkId) {
		$index->{LINKID} = $linkId;
	}
	elsif ($pageId) {
		$index->{PAGEID} = $pageId;
		$index->{SUBSITEID} = $self->getSubsiteId();
	}
	else {
		return $cms->error("В ключах нет ни ключа pageid, ни ключа linkid.");
	};
    return 1;
};

sub updateSearchIndex {
	my $self = shift;
	my $suffix = shift;
    
    my $cms = $self->cms();
    
    my $submodules = $self->moduleBlocks();
    return $cms->error("Класс ".(ref $self)." не содержит метода moduleBlocks(), не могу получить список блоков страницы для индексации") unless defined $submodules;

    my $baseurl = $self->getAdminBaseURL();
    
    my $indexes = [];	
    foreach my $subm (@{$submodules}) {
        $subm->{BLOCK} or return $cms->error("Модуль ".(ref $self)." в описании блоков модуля отсутствует значение ключа BLOCK");
        my $opts = $subm->{OPTS} || {};
        return $cms->error("Параметр OPTS блока не является HASHREF") unless ref $opts eq "HASH";
        
        #Дубль кода в _adminModule() NG::Module
        $subm->{URL} = $self->getAdminSubURL() unless exists $subm->{URL};
        $subm->{URL} =~ s@^/@@;
        $opts->{ADMINBASEURL} = $baseurl. $subm->{URL};
        
        $opts->{MODULEOBJ} =  $self;
        
        my $classDef = {CLASS=>$subm->{BLOCK}};
        $classDef->{USE}= $subm->{USE} if exists $subm->{USE};
        my $bObj = $cms->getObject($classDef,$opts);
        
        return $cms->error("Block ".ref($bObj)." has no getBlockIndex() method") unless $bObj->can("getBlockIndex");
        
		my $blockIndex = $bObj->getBlockIndex($suffix) || return $cms->error();
		next if (scalar(keys %{$blockIndex}) == 0); # Функция возвращает {} если не надо обновлять/индексировать, нет индекса и тд
        
        $blockIndex->{KEYS} ||= ['pageid'];
        
		$self->checkIndex($blockIndex,$suffix) || return $cms->error("Ошибка в индексе, возвращенном модулем ".ref($bObj).": ".$cms->getError());
		
		my $foundIndex;
		foreach my $tmpindex (@{$indexes}){
			if ($tmpindex->{KEYTYPE} == $blockIndex->{KEYTYPE}) {
				$foundIndex = $tmpindex;
				last;
			};
		};
		if ($foundIndex) {
			# Индекс с такими ключами найден, сращиваем индексы
			foreach my $class (keys %{$blockIndex->{DATA}}) {
				$foundIndex->{DATA}->{$class} .= " " if ($foundIndex->{DATA}->{$class});
				$foundIndex->{DATA}->{$class} .= $blockIndex->{DATA}->{$class};
				#Считаем что допинфа недопустима.
			}
		}
		else {
			# Индекс с такими ключами не найден, просто добавляем
			$blockIndex->{OWNER} = $self->getModuleCode();
			push @{$indexes}, $blockIndex;
		}
	};

	my $db = $cms->db();
	my $st = $db->updatePageIndexes($indexes);
	return $cms->error($db->errstr()) unless $st;
	return 1;
}

##
##  Управление созданием страниц
##


# Для создания страницы
sub canAddPage {
	my $self = shift;
	
	my $pageRow = $self->getPageRow();
	return 1 if ($pageRow->{subptmplgid});
	return 0;
};

sub canActivate {
	my $self = shift;
	return 1;
};

sub canDeactivate {
	my $self = shift;
	return 1;
};

sub getPageAddVariants {
	my $self = shift;
	my $cms = $self->cms();
	my $dbh = $cms->db()->dbh();
	my $pageRow = $self->getPageRow();
	
    return $cms->error("Данная страница не поддерживает добавление подстраниц") unless $pageRow->{subptmplgid};
	
    my @variants = ();
    #Запрашиваем список шаблонов группы, делаем left join ng_tmpllink для целей
    #проверки корректности данных (корректности денормализации)
    #Один шаблон должен иметь соответствие только с одним link_id в ng_tmpllink,
    #и значение link_id должно совпадать с ng_templates.link_id
    my $sth = $dbh->prepare("select t.id,t.name,t.modulecode, t.link_id as t_link_id, l.link_id from ng_templates t left join ng_tmpllink l on t.id = l.template_id where t.group_id=?") or return $cms->error("NG::PageModule::getPageAddVariants: select templates: ".$DBI::errstr);
    $sth->execute($pageRow->{subptmplgid}) or return $cms->error("NG::PageModule::getPageAddVariants: select templates: ".$DBI::errstr);
	
    my $ttl = {}; # $ttl->{$template_id} = $link_id  -- Хеш для проверки
    
    while (my $row = $sth->fetchrow_hashref()) {
        if ($row->{link_id} && $row->{t_link_id} != $row->{link_id}) {
            return $cms->error("ng_templates.link_id != nt_tmpllink.link_id for template ".$row->{id});
        };
        if (exists $ttl->{$row->{id}}){
            return $cms->error("Found different link_id for template ".$row->{id}) if $ttl->{$row->{id}} && $row->{link_id} && $ttl->{$row->{id}} != $row->{link_id};
        };
        $ttl->{$row->{id}} = $row->{link_id};
        
        push @variants, {
            ID=>$row->{id},
            NAME=>$row->{name},
            TEMPLATE_ID=>$row->{id},
        };
    };
    return \@variants;
};

sub processNewSubpages {
	my $self = shift;
	my $newSubpages = shift;
	my $variant = shift;
	
    my $cms = $self->cms();
    
	## Cool-ьные мысли.
	## getPageAddVariants() должен выставлять флаг, что он использовал значение pageRow->{subptmplgid} для построения списка вариантов.
	## processNewSubpages(), в случае если добавляемая страница не связана с другими страницами (keys $newSubpages == 1), то
	##                        разрешаем указывать в варианте добавления страницы аттрибуты print_template_id, subptmplgid, module

	return $cms->error("processNewSubpages(): newSubpages is not HASHREF") unless ref $newSubpages eq "HASH";
	return $cms->error("processNewSubpages(): variant is not HASHREF") unless ref $variant eq "HASH";
	
    
    unless ($variant->{TEMPLATE_ID}) {
        #Страница сделана не на основе шаблона, модуль содержит свой getPageAddVariants()
        return $cms->error("processNewSubpages(): variant has no TEMPLATE_ID parameter") if $self->_isBaseClass() && !$variant->{MODULECODE}; #ASSERT
        
        my $module_id = $self->pageParam('module_id');
        if ($variant->{MODULECODE}) {
            #Модуль запросил создание страницы на основе другого модуля
            my $mRow = $cms->getModuleRow("code=?",$variant->{MODULECODE}) or return $cms->defError("processNewSubpages():","Запрошенный модуль ".$variant->{MODULECODE}." не найден");
            $module_id = $mRow->{id};
        };
        
		#TODO: прототип.
		foreach my $subsiteId (keys %{$newSubpages}) {
			my $page = $newSubpages->{$subsiteId};
			$page->{PAGEROW}->{template} = $variant->{template} if $variant->{template};
			$page->{PAGEROW}->{print_template} = $variant->{print_template} if $variant->{print_template};
			$page->{PAGEROW}->{module_id} = $module_id;
			$page->{PAGEROW}->{subptmplgid} = $variant->{subptmplgid} if $variant->{subptmplgid};
			$page->{ACTIVE} = 1;
		};
		return 1;
	};
	
	my $dbh = $cms->db()->dbh();

	my $singleTemplate = undef;
	my $linkedTemplates = undef;
	
	if ($cms->confParam("CMS.hasSubsites")) {
		# Загружаем список подсайтов, для которых можем создавать аналогичные страницы, по признаку связанности шаблона
		my $sql = "select	
				ng_tmpllink.subsite_id as subsite_id,
				ng_tmpllink.template_id as template_id,
				ng_templates.name as template_name,
				ng_templates.subptmplgid,
				ng_templates.print_template,
				ng_templates.modulecode
			from
				ng_tmpllink,ng_templates
			where
				ng_templates.id = ng_tmpllink.template_id 
				and ng_tmpllink.link_id = (select link_id from ng_templates where id = ?)";

		my $sth=$dbh->prepare($sql) or return $cms->error($DBI::errstr);
		$sth->execute($variant->{TEMPLATE_ID}) or return $cms->error($DBI::errstr);
		$linkedTemplates = $sth->fetchall_hashref(['subsite_id']);
		$sth->finish();
	};

	unless (scalar keys %{$linkedTemplates}) {
		$linkedTemplates = undef;
		my $lsth = $dbh->prepare("select id as template_id,name as template_name,subptmplgid,template,print_template from ng_templates where id = ?") or return $cms->error($DBI::errstr); 
		$lsth->execute($variant->{TEMPLATE_ID}) or return $cms->error($DBI::errstr);
		$singleTemplate = $lsth->fetchrow_hashref();
		$lsth->finish();
	};
	
	foreach my $subsiteId (keys %{$newSubpages}) {
        my $page = $newSubpages->{$subsiteId};
	
		$page->{ACTIVE} = 1;
		my $template = undef;
		if (exists $linkedTemplates->{$subsiteId}) {
			$template = $linkedTemplates->{$subsiteId};
		}
		elsif ($singleTemplate) {
			$template = $singleTemplate;
		}
		else {
			$page->{ACTIVE} = 0;
			$page->{MESSAGE} ||= "Отсутствует шаблон для добавляемой страницы";
		};
		$page->{ATTRIB}->{VARIANT_NAME} = $template->{template_name};
		$page->{PAGEROW}->{template} = $template->{template};
		$page->{PAGEROW}->{print_template} = $template->{print_template};
		$page->{PAGEROW}->{subptmplgid} = $template->{subptmplgid};
		
		if ($template->{modulecode}) {
		    my $mRow = $cms->getModuleRow("code=?",$template->{modulecode}) or return $cms->defError("processNewSubpages():","Запрошенный модуль ".$template->{modulecode}." не найден");
		    $page->{PAGEROW}->{module_id} = $mRow->{id};
		};
	};
	return 1; #TODO: change this ?
};



sub initialisePage {
	my $self = shift;
=head	
	$self->initPageStructure({
		BUILD_EDITABLEBLOCKS=>1,
		SKIP_BLOCKPRIVS =>1,
	}) or return $self->showError("initPageStructure(): hmmm...");
	
	my @initialisedBlocks = ();
	my $has_errors = 0;
	my $errText = "";

	foreach my $eblock (@{$self->{_editableBlocks}}) {
		next unless $eblock->{NOT_INITIALISED};
		my $moduleObj = $eblock->{MODULEOBJ};
		
		my $res = $moduleObj->initPageBlock();
		if($res == NG::Module::M_OK) {
			push @initialisedBlocks, $eblock;
			next;
		};
		if ($res == NG::Module::M_REDIRECT) {
			#$firstNIblockId ||= $block->{id};
			next;
		};
		if ($res == NG::Module::M_ERROR) {
			$errText = $moduleObj->getError();
			$has_errors = 1;
			last;
		};
		$errText = "Некорректный код возврата ($res) из initPageBlock()";
		$has_errors = 1;
		last;
	};
	if ($has_errors) {
		foreach my $eblock (@initialisedBlocks) {
			next unless $eblock->{MODULEOBJ}->can("destroyPageBlock");
			$eblock->{MODULEOBJ}->destroyPageBlock();
		};
		return $self->setError($errText);
	};
=cut
	return 1;
};

sub destroyPage {
	my $self = shift;
	my $linkedPages = shift;
=head
	my $errTexts = "";

	## Формируем хэш с идентификаторами данных линкованных блоков линкованных страниц
	my $keyHash = {};
	my $blockModulesHash = {};
	foreach my $lpObj (@{$linkedPages}) {
		next unless $lpObj->can("editableBlocks");
		my $eBlocks = $lpObj->editableBlocks();

		
		unless ($eBlocks) {
			$errTexts.=" " if $errTexts;
			my $e = $lpObj->getError();
			$e = " вернул ошибку $e" if ($e);
			$e ||= " не вернул данных и сообщения об ошибке";
			$errTexts.= "Вызов editableBlocks() для страницы ".$lpObj->getPageId().$e;
			next;
		};
		
		foreach my $eblock (@{$eBlocks}) {
			my $moduleObj = $eblock->{MODULEOBJ};
			my $eblockId  = $eblock->{BLOCK_ID};
			if (!$eblockId || !$moduleObj) {
				$errTexts.= " " if $errTexts;
				$errTexts.= "Вызов editableBlocks() для страницы ".$lpObj->getPageId()." вернул блок с отсутствующим параметром BLOCK_ID или MODULEOBJ";
				next;
			};
			if (exists $blockModulesHash->{$eblockId} && ($blockModulesHash->{$eblockId} ne ref($moduleObj))) {
				$errTexts.= " " if $errTexts;
				$errTexts.= "Вызов editableBlocks() для страницы ".$lpObj->getPageId()." вернул блок $eblockId несовпадающего класса:".$blockModulesHash->{$eblockId} ." и ". ref($moduleObj);
				next;
			};
			if ($moduleObj->canEditLinkBlock()) {
				#Do work.
			}
			elsif ($moduleObj->canEditPageBlock()) {
				next;
			}
			else {
				my $e = $moduleObj->getError();
				$e = " вернул ошибку $e" if ($e);
				$e ||= " вернул некорректный статус без сообщения об ошибке";
				$errTexts.= " " if $errTexts;
				$errTexts.= "Вызов canEditLinkBlock() для модуля ".ref($moduleObj)." (блок $eblockId) страницы ".$lpObj->getPageId().$e;
				next;
			};
			
			$blockModulesHash->{$eblockId} ||= ref($moduleObj);
			next if $eblock->{NOT_INITIALISED};
			
			my $key = $moduleObj->getContentKey();
			unless ($key) {
				my $e = $moduleObj->getError();
				$e = " вернул ошибку $e" if ($e);
				$e ||= " не вернул данных и сообщения об ошибке";
				$errTexts.=" " if $errTexts;
				$errTexts.= "Вызов getContentKey() для модуля ".ref($moduleObj)." (блок $eblockId) страницы ".$lpObj->getPageId().$e;
				next;
			};
			#По сравнению с предыдущей реализацией сравниваем ключи, идентифицируюшие контент только для совпадающих BLOCKID
			$key = "b".$eblockId.$key;
			
			$keyHash->{$key}||=0;
			$keyHash->{$key}++;
		};
	};
	return $self->error($errTexts) if $errTexts;

	
	#Формируем блоки удаляемой (этой) страницы
	my $eBlocks = $self->editableBlocks();
	
	unless ($eBlocks) {
		my $e = $self->getError();
		$e = " вернул ошибку $e" if ($e);
		$e ||= " не вернул данных и сообщения об ошибке";
		return $self->error("Вызов editableBlocks() для страницы ".$self->getPageId().$e);
	};
	
	my @destroyLBObjs = ();
	my @destroyPBObjs = ();
	
	foreach my $eblock (@{$eBlocks}) {
		my $moduleObj = $eblock->{MODULEOBJ};
		my $eblockId  = $eblock->{BLOCK_ID};
		if (!$eblockId || !$moduleObj) {
			return $self->error("Вызов editableBlocks() для страницы ".$self->getPageId()." вернул блок с отсутствующим параметром BLOCK_ID или MODULEOBJ");
		};
		if (exists $blockModulesHash->{$eblockId} && ($blockModulesHash->{$eblockId} ne ref($moduleObj))) {
			return $self->error("Вызов editableBlocks() для страницы ".$self->getPageId()." вернул блок $eblockId несовпадающего класса:".$blockModulesHash->{$eblockId} ." и ". ref($moduleObj));
		};
		$blockModulesHash->{$eblockId} ||= ref($moduleObj);
		next if $eblock->{NOT_INITIALISED};
		
		if ($moduleObj->canEditLinkBlock()) {
			#Do work.
			my $key = $moduleObj->getContentKey();
			unless ($key) {
				my $e = $moduleObj->getError();
				$e = " вернул ошибку $e" if ($e);
				$e ||= " не вернул данных и сообщения об ошибке";
				return $self->error("Вызов getContentKey() для модуля ".ref($moduleObj)." (блок $eblockId) страницы ".$self->getPageId().$e);
			};
			$key = "b".$eblockId.$key;
			
			unless (exists $keyHash->{$key}) {
				push @destroyLBObjs, $moduleObj;
			};
			next;
		}
		elsif ($moduleObj->canEditPageBlock()) {
			push @destroyPBObjs, $moduleObj;
			next;
		}
		else {
			my $e = $moduleObj->getError();
			$e = " вернул ошибку $e" if ($e);
			$e ||= " вернул некорректный статус без сообщения об ошибке";
			return $self->error("Вызов canEditLinkBlock() для модуля ".ref($moduleObj)." страницы ".$self->getPageId().$e);
			next;
		};
	};
	
	foreach my $moduleObj (@destroyPBObjs) {
	    my $res = $moduleObj->destroyPageBlock();
		if ($res != NG::Block::M_OK) {
			my $e = $moduleObj->getError();
			$e = " вернул ошибку $e" if ($e);
			$e ||= " вернул некорректный статус без сообщения об ошибке";
			return $self->error("Вызов destroyPageBlock() для модуля ".ref($moduleObj)." страницы ".$self->getPageId().$e);
		};
	};
	foreach my $moduleObj (@destroyLBObjs) {
	    my $res = $moduleObj->destroyLinkBlock();
		if ($res != NG::Module::M_OK) {
			my $e = $moduleObj->getError();
			$e = " вернул ошибку $e" if ($e);
			$e ||= " вернул некорректный статус без сообщения об ошибке";
			return $self->error("Вызов destroyLinkBlock() для модуля ".ref($moduleObj)." страницы ".$self->getPageId().$e);
		};
	};
=cut
	return 1;
};

##
##
##

=head getPageBlocksPrivileges
sub getPageBlocksPrivileges {
	my $self = shift;
	
	if ($self->_isBaseClass()) {
		$self->initPageStructure({
			BUILD_EDITABLEBLOCKS=>1,
			SKIP_BLOCKPRIVS => 1,
			USE_CACHE       => 1,
		}) or return $self->showError("initPageStructure(): hmmm...");

		my $blocks = $self->editableBlocks(); 
		unless ($blocks) {
			my $e = $self->getError();
			$e = " вернул ошибку $e" if ($e);
			$e ||= " не вернул данных и сообщения об ошибке";
			return $self->showError("Вызов editableBlocks() для страницы ".$self->getPageId().$e);
		};

		my @pageBlocks = ();
		foreach my $block (@{$blocks}) {
			my $moduleObj = $block->{MODULEOBJ};
			
			my $mp = $moduleObj->modulePrivileges();
			unless ($mp) {
				return $self->error("Ошибка получения списка привилегий модуля ".ref($self).":".$moduleObj->getError());
			};
			if (ref $mp ne "ARRAY") {
				return $self->error("Возвращенное значение списка привилегий модуля ".ref($self)." не является массивом");
			};
				
			my $type = "";
			my $has_lang_linked = 0;
			if ($moduleObj->canEditLinkBlock()) {
				$type = "link";
				$has_lang_linked = 1 if ($moduleObj->hasLangLindked());
			}
			elsif ($moduleObj->canEditPageBlock())  {
				$type = "page";
			}
			else {
				return $self->showError("Блок не является блоком типа LinkBlock или PageBlock, вызовы функций canEditLinkBlock() и canEditPageBlock() модуля ".ref($moduleObj)." не вернули ошибок (код страницы: ".$self->getPageId().")");
			};
			push @pageBlocks, {
				NAME       => $block->{HEADER},
				PRIVILEGES => $mp,
				TYPE	   => $type,
				BLOCKID    => $block->{BLOCK_ID},
				HAS_LANG_LINKED => $has_lang_linked
			};
		};
		return \@pageBlocks;
	}
	else {
		#Страница - модуль
		my $mp = $self->modulePrivileges();
		unless ($mp) {
			return $self->error("Ошибка получения списка привилегий модуля ".ref($self).":".$self->getError());
		};
		if (ref $mp ne "ARRAY") {
			return $self->error("Возвращенное значение списка привилегий модуля ".ref($self)." не является массивом привилегий");
		};
		
		return [] unless scalar @{$mp};
		
		my $type = "";
		if ($self->canEditLinkBlock()) {
			$type = "link";
		}
		elsif ($self->canEditPageBlock())  {
			$type = "page";
		}
		else {
			return $self->showError("Блок не является блоком типа LinkBlock или PageBlock, вызовы функций canEditLinkBlock() и canEditPageBlock() модуля ".(ref($self))." не вернули ошибок");
		};
		
		return [{
			NAME       => "Модуль",
			PRIVILEGES => $mp,
			TYPE	   => $type,
			BLOCKID    => 1,
		}];
	};
};
=cut

return 1;
END {};
