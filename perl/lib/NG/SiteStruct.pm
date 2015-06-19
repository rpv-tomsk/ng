package NG::SiteStruct;
use strict;

use NG::Module;

use vars qw(@ISA);
@ISA = qw(NG::Module);

sub moduleTabs {
	return [
	    {HEADER=>"Структура сайта",URL=>"/"},
	];
};

sub moduleBlocks {
	return [
		{URL=>"/",BLOCK=>"NG::SiteStruct::Block"},
	]
};

sub modulePrivileges {
    return [];
    #return undef;
};

sub pageModulePrivileges {
    my $self = shift;
    my $arr = [];
    #push @$arr, {PRIVILEGE => "ACCESS",  NAME => "Доступ к странице"};
    push @$arr, {PRIVILEGE => "PROPERTIES",  NAME => "Редактирование свойств"};
    push @$arr, {PRIVILEGE => "NEWPAGE", NAME => "Создание страниц"};
    push @$arr, {PRIVILEGE => "DELPAGE", NAME => "Удаление страниц"};
    return $arr;
};

package NG::SiteStruct::Block;

use strict;
use vars qw(@ISA);

use NG::Form;
use NG::Nodes;
use NSecure;
use NHtml;
use NG::SiteStruct::Event;

use NGPlugins;
use NG::Block;
@ISA = qw(NG::Block);

sub getBlockIndex {{}};

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    $self->{_pstructtemplate} = "admin-side/common/pagestructure.tmpl";
    
    $self->register_ajaxaction("","action_structPage");
    $self->register_ajaxaction("movenodedown","action_moveNodeDown");
    $self->register_ajaxaction("movenodeup","action_moveNodeUp");
    $self->register_ajaxaction("addsubnodeform","action_showAddForm");
    $self->register_ajaxaction("editnodeform","action_updateNode");
    $self->register_ajaxaction("updatenode","action_updateNode");
    $self->register_ajaxaction("deletenode","action_deleteNode");
    $self->register_ajaxaction("enablepage","action_enablePage");
    $self->register_ajaxaction("disablepage","action_disablePage");
    $self->register_ajaxaction("switchsubsite","action_switchSubsite");
    
    $self->{_pageId} = undef;
    $self->{_showAll} = 0;
    
    $self;
};

sub getStructModuleObj {
    my $self = shift;
    
    my $cms = $self->cms();
    my $mObj = $self->SUPER::getModuleObj();
    
    my $code1 = $mObj->getModuleCode() or return $cms->error();
    my $code2 = $cms->confParam("CMS.SiteStructModule","") or return $cms->error("Config parameter CMS.SiteStructModule is not configured");
    
    return $mObj if $code1 eq $code2;
    return $cms->getModuleByCode($code2);
};

sub blockAction {
    my $self = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
    my $q   = $cms->q();
    
    my $showAll = $q->param('all') || 0;
    $self->{_showAll} = 0;
    $self->{_showAll} = 1 if ($showAll == 1);
    $self->{_pageURL} = $self->getBaseURL();
    $self->{_pageMode} = 0;

    my $subUrl = $self->getSubURL();
    #if (!$self->{_showAll} && $subUrl) {
    if ($subUrl) {
        return $cms->error("Некорректный код страницы") if $subUrl !~ /^(\d+)\//;
        $self->{_pageId} = $1;
        $self->{_pageURL} = $self->getBaseURL().$self->{_pageId}."/";
    };

    return $self->run_actions($is_ajax);
};

sub pageBlockAction {
    my $self = shift;
    my $is_ajax = shift;

    my $cms = $self->cms();
    my $q   = $cms->q();
    
    my $showAll = $q->param('all') || 0;
    $self->{_showAll} = 0;
    $self->{_showAll} = 1 if ($showAll == 1);
    $self->{_pageId} = $self->getPageId() or return $cms->error("NG::SiteStruct::pageBlockAction: getPageId() failed");
    $self->{_pageURL} = $self->getBaseURL();
    $self->{_pageMode} = 1;
    #$self->{_parentBaseURL} = $self->SUPER::getModuleObj()->getAdminBaseURL();
#return $cms->error($self->SUPER::getModuleObj()->getAdminBaseURL());
    return $self->run_actions($is_ajax);
};

sub _canAddSubpage {
	my $self = shift;
	my $pageObj = shift;
	
	my $page = $pageObj->getPageRow();
=head
    TODO: проверять привилегии
	my $canAddSubnode = $self->app()->hasPageBlockPrivilege(
		PAGE_ID   => $page->{id},
		BLOCK_ID  => 0,
		PRIVILEGE => "NEWPAGE",
		SUBSITE_ID => $page->{subsite_id},
	);
=cut
    my $canAddSubnode = 1;
	#TODO: проверять наличие ошибок после вызова hasPageBlockPrivilege, в т ч и в других местах
	
    return 0 unless $pageObj->can("canAddPage");
    
	if ($canAddSubnode)  {
		$canAddSubnode = $pageObj->canAddPage();
		#TODO: проверять наличие ошибок после вызова canAddPage
	};
	return $canAddSubnode;
};

sub _getLinkedPages {
	my ($self,$req) = (shift,shift);
	
	my $cms = $self->cms();
	my $dbh = $cms->dbh();
    
    my $pRow;
    if (ref $req) { #$pageObj
        $pRow = $req->getPageRow();
    }
    else {
        $pRow = $cms->getPageRowById($req);
        return $self->error("Страница не найдена") unless $pRow;
    };
	
	if ($cms->confParam("CMS.hasSubsites")) {
        my $pageLinkId = $pRow->{link_id};
		
		return $self->error("Обнаружено недопустимое значение link_id страницы") unless $pageLinkId;
		
		## Загружаем список подсайтов, на которых есть связанные страницы
		my $sql = "select
				ng_subsites.id as subsite_id,
				ng_subsites.name as subsite_name,
				ng_lang.id as lang_id,
				ng_lang.name as lang_name,
				ng_lang.img as lang_img,
				ng_sitestruct.id as node_id,
				ng_sitestruct.link_id as link_id,
				ng_sitestruct.name as node_name,
				ng_sitestruct.disabled as node_disabled,
				ng_sitestruct.url as node_url
			from
				ng_subsites,
				ng_lang,
				ng_sitestruct
			where
				ng_sitestruct.subsite_id = ng_subsites.id
				and ng_sitestruct.lang_id = ng_subsites.lang_id
				and ng_lang.id = ng_sitestruct.lang_id
				and ng_sitestruct.link_id = ?";
		my $sth=$dbh->prepare($sql) or return $self->error($DBI::errstr);    
		$sth->execute($pageLinkId) or return $self->error($DBI::errstr);
		my $linkedPages = $sth->fetchall_hashref(['subsite_id']) or return $self->error($DBI::errstr);
		$sth->finish();
		return $self->error("_getLinkedPages(): Нарушение структуры данных в БД (несовпадают link_id,lang_id), страница - родитель не найдена") unless scalar keys %{$linkedPages};
		return $linkedPages;
	}
	else {
        my $lp = {};
        
        $lp->{subsite_id} = $pRow->{subsite_id};
        $lp->{link_id} = $pRow->{link_id};
        $lp->{lang_id} = $pRow->{lang_id};
        $lp->{node_id} = $pRow->{id};
        $lp->{node_disabled} = $pRow->{disabled};
        $lp->{node_url} = $pRow->{url};
        $lp->{node_name} = $pRow->{name};
        return {$pRow->{subsite_id} => $lp};
	};
};

sub getBaseFields {
    my $self = shift;
    return [
   		{NAME=>"Внутреннее название",FIELD=>"name",TYPE=>"text",IS_NOTNULL=>1,},
		{NAME=>"URL suffix",FIELD=>"url",TYPE=>"text",IS_NOTNULL=>1,},
		{NAME=>"Название страницы",FIELD=>"full_name",TYPE=>"text",IS_NOTNULL=>1,},
		{NAME=>"Заголовок страницы",FIELD=>"title",TYPE=>"text",IS_NOTNULL=>1,},
	];
};

sub getDescrFields {
    my $self = shift;
    return [    
        {NAME=>"Ключевые слова",FIELD=>"keywords",TYPE=>"textarea",IS_NOTNULL=>0,HEIGHT=>40},
        {NAME=>"Описание",FIELD=>"description",TYPE=>"textarea",IS_NOTNULL=>0,HEIGHT=>40},
	];
};

sub processNodeInfo($$$)    {}; #$self,$pageObj,$nodeInfo - Обработка выводимой информации о странице
sub afterSetFormValues($$$) {}; #$self,$pageObj,$form     - Предобработка введенных параметров новой страницы перед её созданием

sub action_showAddForm {
	my ($self,$action,$is_ajax) = (shift,shift,shift);
	
    my $cms = $self->cms();

    my $subUrl = $self->getSubURL();
    my $pageId = $self->{_pageId} or return $cms->error("Некорректный код страницы");
    
    my $pageObj = $cms->getPageObjById($pageId) or return $cms->error();

	my $q = $cms->q();
	my $dbh = $cms->db()->dbh();
	my $adminId = $cms->getAdminId();
	#my $page = $pageObj->getPageRow();

	#(1)Разрешено ли добавление страниц
	my $canAddSubnode = $self->_canAddSubpage($pageObj);
	unless ($canAddSubnode) {
		return $self->showError("Добавление подстраницы невозможно: отсутствуют права либо страница не поддерживает добавление подстраниц");
	};

	my $variantId = $q->param('variantId');
	my $prevVariantId = $q->param('prevVariantId');
	
	#Флаг того, что происходит перевыбор варианта.
	my $selVariantAction = 0;
	$selVariantAction = 1 if (defined $q->param('selectemplate.x') && $q->param('selectemplate.x') ne "0");
	
	#Флаг того, что происходит добавление/создание страниц
	my $doitAction = 0;
	$doitAction = 1 if ($selVariantAction == 0) and ($q->request_method eq "POST");
	
	#Флаг того, что требуется отображать две части формы одновременно
	my $showTwoPartsForm = 0;
	my $paramHasLinkedPages = $q->param('haslinkedpages') || "0";
	$showTwoPartsForm = 1 if ($paramHasLinkedPages eq "0");
	
	my $baseUrl = $self->getBaseURL();
	my $form = NG::Form->new(
		KEY_FIELD => "id",
		FORM_URL  => $baseUrl.$subUrl."?action=addsubnodeform",
		DOCROOT   => "z", #TODO: kostyl` ? Конечно костыль
		DB        => $self->db(),
		CGIObject => $q,
		TABLE     => "ng_sitestruct",
		REF       => $baseUrl.$subUrl,
        IS_AJAX   => $is_ajax,
	);
	$form->setTitle('Создание новой страницы:');
	$form->setcontainer('new_subpage');
	$form->addfields({NAME=>"id",FIELD=>"id",TYPE=>"id"}); ## Fake keyfield
	$form->param("id",1);
	
	my $variants = $pageObj->getPageAddVariants();
	my $variant = undef;
	if (!$variants) {
		# TODO: getPageAddVariants errors output
		return $cms->defError("showAddForm():","getPageAddVariants(): unknown error");
	}
	elsif (ref($variants) eq "ARRAY") {
		return $self->error("Метод ".ref($pageObj)."::getPageAddVariants(): возвратил пустой список вариантов добавления страницы") if (scalar @{$variants} == 0);
		#Корректный список вариантов.
        my $i = 1; 
		my $variantIds = {};
		foreach my $v (@{$variants}) {
            $v->{ID}||=$i++;
            #return $self->error("В списке вариантов добавления страницы отсутствует ID варианта") unless $v->{ID};
            #return $self->error("В списке вариантов добавления страницы присутствует недопустимый ключ ID") if exists $v->{ID};
			return $self->error("В списке вариантов добавления страницы обнаружены дублирующиеся значения ID варианта (".$v->{ID}.")") if (exists $variantIds->{$v->{ID}});
			$variantIds->{$v->{ID}} = 1;
			$variant = $v if ($v->{ID} eq $variantId);
		};
		$variant ||= @{$variants}[0];
	}
	else {
		return $self->error("Метод ".ref($pageObj)."::getPageAddVariants(): возвратил некорректное значение списка вариантов добавления страницы");
	};
	$variant->{SELECTED} = 1;
	
	$form->addfields([
		{
			NAME=>"Варианты новой страницы",
			FIELD=>"variantId",
			TYPE=>"select",
			IS_NOTNULL=>1,
			NEW_SELECTTEXT=>"Выберите вариант страницы",
			SELECT_OPTIONS => $variants,
			TEMPLATE=>$cms->{_template_dir}."admin-side/common/sitestruct/selecttemplateform.tmpl",
			HIDE_BUTTON => ($showTwoPartsForm==1)?1:0,
		},
		{
			NAME => "Код варианта предыдущего этапа",
			FIELD => "prevVariantId",
			TYPE => "hidden",
			VALUE => 0,
		},
	]);
    delete $variant->{ID}; # Добавление поля типа select завершено.
    
	$form->addfields({
		NAME => "Флажок",
		FIELD => "haslinkedpages",
		TYPE => "hidden",
		VALUE => 0,
	}) if ($showTwoPartsForm);
	$form->modeInsert();	
	if ($q->request_method eq "POST") {
		$form->setFormValues();
		$form->StandartCheck();
	};
	if (!defined $prevVariantId && !defined $variantId && ($showTwoPartsForm == 0)) {
		# Показываем первую часть формы
		if ($form->has_err_msgs()){
			if($is_ajax) {
				return $self->output($form->ajax_showerrors());
			};
		};
		$form->hideButtons();
		my $tmpl = $cms->gettemplate("admin-side/common/universalform.tmpl")  || return $cms->error();
		$form->print($tmpl) or return $self->error($form->getError());
		return $cms->output($tmpl);
	};
	
    NGPlugins->invokeWhileTrue('NG::SiteStruct','afterVariant',$self,$pageObj,$form) or return $cms->error();
    
	# Показываем вторую часть формы
	my $variantSelectField = $form->_getfieldhash('variantId');
	$variantSelectField->{HIDE_CLOSE_BTN} = 1;
	
	my $baseFields = $self->getBaseFields();
    $form->addfields($baseFields) or return $self->error($form->getError());

    $self->_injectPageFormFields($pageObj,$form) or return $self->showError("_injectPageFormFields(): Some error happens.");
	
	$form->addfields([
		{
			NAME=>"Связанные разделы",
			FIELD=>"linkedParts",
			TYPE=>"custom",
			IS_NOTNULL=>0,
			TEMPLATE=>$cms->{_template_dir}."admin-side/common/sitestruct/linkedsections.tmpl",
		},
	]) or return $self->error($form->getError());
	my $linkedPartsField = $form->_getfieldhash('linkedParts');
	$form->modeInsert();
	$form->setFormValues() if ($q->request_method eq "POST" && defined $prevVariantId);
	
	$self->afterSetFormValues($pageObj,$form);
	
	## Сохраняем значение кода выбранного шаблона, как флаг что показываем вторую часть формы
	## и для проверки, что пользователь не сменил шаблон без нажатия кнопки выбрать
	$form->param('prevVariantId',$variantId) if $variantId; 
	my $url = "";
	if ($doitAction == 1) {
		$form->StandartCheck();
		$url = $form->getParam('url');
		$url =~ s/^\///;
		$url =~ s/\/$//;
		if($url =~ /[^a-zA-Z0-9\_\-]/) {
			$url = "";
			$form->pusherror("url","Значение должно содержать только латинские символы и цифры");
		} elsif (is_empty($url)) {
			$url = "";
			$form->pusherror("url","Значение не указано");
		} else {
			$url .= "/";
		};
	};
	
	my $newSubpages = {};  # Хэш страниц, которые мы собираемся создать: $h->{$subsiteId}
	
	#Вычисляем наличие связанных страниц
	my $linkedParentPages = $self->_getLinkedPages($pageObj) or return $self->showError("_getLinkedPages(): method returns unknown error");
	
	#my $allSubsitesPrivileges = $dbh->selectall_hashref("select subsite_id,privilege from ng_subsite_privs where admin_id = ? and (privilege='ACCESS' or privilege='NEWPAGE')",["subsite_id","privilege"],undef,$adminId);
	
	foreach my $subsiteId (keys %{$linkedParentPages}) {
		my $ppage = $linkedParentPages->{$subsiteId};
		my $langId = $ppage->{lang_id};
	   
		my $canAddLinkedSubnode = 0;
		#if (!exists $allSubsitesPrivileges->{$subsiteId}->{ACCESS}) {
		#	$canAddLinkedSubnode = 0;
		#}
		#elsif (exists $allSubsitesPrivileges->{$subsiteId}->{NEWPAGE}) {
		#	$canAddLinkedSubnode = 1;
		#}
		#elsif ($cms->hasPageBlockPrivilege(PAGE_ID => $ppage->{node_id}, BLOCK_ID => 0, PRIVILEGE => "NEWPAGE")) {
		#	$canAddLinkedSubnode = 1;
		#};
$canAddLinkedSubnode = 1;
		
		my $subpage = {};
		$subpage->{PAGEROW} = {
			subsite_id => $ppage->{subsite_id},
			lang_id    => $ppage->{lang_id},
			parent_id  => $ppage->{node_id},
			disabled   => $ppage->{node_disabled},
		};
		$subpage->{PARENTROW} = {
			url        => $ppage->{node_url},
		};
		$subpage->{ATTRIB} = {
			SUBSITE_ID   => $ppage->{subsite_id},
			SUBSITE_NAME => $ppage->{subsite_name},
			LANG_ID   => $ppage->{lang_id},
			LANG_NAME => $ppage->{lang_name},
			LANG_IMG  => $ppage->{lang_img},
			NODE_NAME => $ppage->{node_name},
			NODE_URL  => $ppage->{node_url},
		};
		#$subpage->{MESSAGE} = "$canAddLinkedSubnode $doitAction $pageId $ppage->{node_id} ($pageLinkId)";
		unless ($canAddLinkedSubnode) {
			$subpage->{READONLY} = 1;
			$subpage->{MESSAGE} = "Отсутствует доступ к созданию страницы";
		}
		else {
			#Делаем активной ноду текущего подсайта
			$subpage->{CHECKED} = 1 if ($ppage->{node_id} == $pageId) and ($doitAction == 0);
		}
		$newSubpages->{$subsiteId} = $subpage;
	};
	
	#Сохраняем ключевые параметры добавляемой страницы, которые могут быть испорчены вызовом processNewSubpages
	my $subpagesControl = {};
    my $variantControl = {};
	foreach my $subsiteId (keys %{$newSubpages}) {
		my $page = $newSubpages->{$subsiteId};
		
		my $cpage = {};
		$cpage->{READONLY} = $page->{READONLY};
		$cpage->{PAGEROW}->{subsite_id} = $page->{PAGEROW}->{subsite_id};
		$cpage->{PAGEROW}->{lang_id}    = $page->{PAGEROW}->{lang_id};
		$cpage->{PAGEROW}->{parent_id}  = $page->{PAGEROW}->{parent_id};
		$cpage->{PAGEROW}->{disabled}   = $page->{PAGEROW}->{disabled};
		$cpage->{PARENTROW}->{url}      = $page->{PARENTROW}->{url};
		$subpagesControl->{$subsiteId} = $cpage;
        
        $variantControl->{MODULECODE} = $variant->{MODULECODE};
	};
	
	my $res = $pageObj->processNewSubpages($newSubpages,$variant) or return $cms->error();
    
	#Проверка параметров создаваемых страниц
	foreach my $subsiteId (keys %{$newSubpages}) {
		my $page = $newSubpages->{$subsiteId};
		#проверяем сохраненные "ключевые параметры"
		my $cpage = $subpagesControl->{$subsiteId} || return $self->error("processNewSubpages(): method inserts some new subsite page");
		if (   $page->{PAGEROW}->{subsite_id} ne $subsiteId
			|| $page->{PAGEROW}->{subsite_id} ne $cpage->{PAGEROW}->{subsite_id}
			|| $page->{PAGEROW}->{lang_id}   ne $cpage->{PAGEROW}->{lang_id}
			|| $page->{PAGEROW}->{parent_id} ne $cpage->{PAGEROW}->{parent_id}
			|| $page->{PAGEROW}->{disabled}  ne $cpage->{PAGEROW}->{disabled}
			|| $page->{PARENTROW}->{url}     ne $cpage->{PARENTROW}->{url}
			|| $page->{READONLY} ne $cpage->{READONLY}
            || $variantControl->{MODULECODE} ne $variant->{MODULECODE}
		   ) {
			return $cms->error("processNewSubpages(): method corrupts page parameters");
		};
        
		#Проверяем наличие обязательных свойств страниц.
		return $cms->error("Отсутствует код шаблона или название модуля для новой страницы варианта '".$variant->{NAME}."' (subsite_id=$subsiteId)") unless ($page->{PAGEROW}->{template} || $page->{PAGEROW}->{module_id});
	};
    
    #$variant->{ID} = $app->getVariantId(MODULE=>(ref $npageObj), CODE=> $variant->{CODE});
    
    my $hasSelectedPPage = 0;
    my $hasPPageErrors = 0;
    my @lp = ();
    foreach my $subsiteId (keys %{$newSubpages}) {
        my $page = $newSubpages->{$subsiteId};
        push @lp,$page;
        
        $page->{CHECKED} = 0;
        
        my $enabled = $q->param("doit_".$subsiteId) || 0;
        $enabled = 0 if ($enabled != 1);
        $enabled = 0 if $page->{READONLY};
        $enabled = 0 unless $page->{ACTIVE};
        if ($page->{ERRORMSG}) {
            $hasPPageErrors = 1;
            $enabled = 0;
        };
        next unless $enabled;
        $hasSelectedPPage = 1;
        $page->{CHECKED} = 1;
    };
    
    if (scalar keys %{$newSubpages} > 1) {
		$linkedPartsField->{LINKED_PAGES} = \@lp;
		#Проверяем, не сменил ли хитрый пользователь шаблон, забыв нажать волшебную кнопку ?
		if (($prevVariantId ne $variantId) && ($selVariantAction != 1)) {
			$variantSelectField->setError('После смены шаблона нажмите "Выбрать"!');
		}
		$linkedPartsField->setError("Не выбран ни один раздел для добавления.") unless ($hasSelectedPPage || $doitAction == 0);
		$variantSelectField->{HIDE_BUTTON} = 0;
	};
    
    ## Если ошибок нет - добавляем страницы и делаем редирект
    if (!$hasPPageErrors && !$form->has_err_msgs() && $doitAction && $hasSelectedPPage) {
        my @newPages = ();
        my @np = ();
        foreach my $page (@lp) {
            next unless $page->{CHECKED};
            
            foreach my $f (@{$form->fields()}) {
                next if ($f->{FIELD} eq "id");
                next if ($f->{FIELD} eq "url");
                $page->{PAGEROW}->{$f->{FIELD}} = $form->getParam($f->{FIELD});
            };
            
            $page->{PAGEROW}->{url} = $url;
            
            push @newPages, $page->{PAGEROW};
            push @np, $page;
        };
        
        my $ret = eval {
            $self->addLinkedPages(\@newPages);
        };
        if (my $exc = $@) {
            if (NG::SiteStruct::Exception->caught($exc)) {
                my $idx = $exc->params()->{PAGEIDX};
                $np[$idx]->{ERRORMSG} = $exc->message();
                $hasPPageErrors = 1;
            }
            else {
                return $cms->error($exc) unless ref $exc;
                return $cms->error($exc->code.": ".$exc->message);
            };
        }
        else {
            #afterNodeAdded вызывается от NG::Application. Вызов от NG::SiteStruct может отличаться наличием FORM, VARIANT и т д
            #foreach my $pObj (@{$ret->{PAGES}}) {
            #    NGPlugins->invoke('NG::SiteStruct','afterNodeAdded',{PAGEOBJ=>$pObj->{PAGEOBJ}, VARIANT=>$variant, PREV_SIBLING_ID=>$pObj->{PREV_SIBLING_ID}});
            #};
            
            NGPlugins->invoke('NG::SiteStruct','afterAllNodesAdded',{VARIANT=>$variant, NODES=>$ret->{PAGES}, FORM=>$form});
            
            #TODO: делать перенаправление на страницу "текущего" подсайта
            #my $newPage = $newSubpages->{$self->getSubsiteId()};
            #if ($newPage->{CHECKED}) {
            #	return $self->fullredirect("/admin-side/pages/".$newPage->{PAGEROW}->{id}."/");
            #};
            return $self->fullredirect("/admin-side/pages/".$ret->{PAGES}[0]->{PAGEOBJ}->getPageId()."/",$is_ajax);
        };
    };
    
    if (scalar keys %{$newSubpages} == 1) {
        my ($subsiteId) = keys %{$newSubpages};
        my $page = $newSubpages->{$subsiteId};
        $linkedPartsField->{SUBSITE_ID} = $subsiteId;
        $form->pusherror("url",$page->{ERRORMSG}) if !is_empty($page->{ERRORMSG});
    };

    #Если $selTmplAction - выводим вторую часть формы
    #Если $doitAction -
    #  ---- если есть ошибки - выводим ошибки ( Аякс - аяксом, не аякс - формой)
    #  ---- если нет ошибок - добавляем страницы

	## Если есть ошибки и Аякс - выводим 
	if ($is_ajax && ($selVariantAction != 1) && ($form->has_err_msgs() || $hasPPageErrors)) {
		my $error = "";
		if (scalar keys %{$newSubpages} > 1) {
		    $error .= "<script type='text/javascript'>";
    		foreach my $subsiteId (keys %{$newSubpages}) {
    			my $page = $newSubpages->{$subsiteId};
    			my $em = escape_js($page->{ERRORMSG});
    			if ($em) {
    				$error .= "parent.document.getElementById('error_$subsiteId').innerHTML='$em';\n";
    				$error .= "parent.document.getElementById('errortr_$subsiteId').style.display='';\n";
    			}
    			else {
    				$error .= "parent.document.getElementById('error_$subsiteId').innerHTML='';\n";
    				$error .= "parent.document.getElementById('errortr_$subsiteId').style.display='none';\n";
    			};
    		};
    		$error .= "</script>";
        };
		$error .= $form->ajax_showerrors();
		return $self->output($error);
	}
	
	# Выводим форму, если еще не делалось добавление страниц или возврат ошибок делается не аяксом.
	my $tmpl = $cms->gettemplate("admin-side/common/universalform.tmpl")  || return $cms->error();

	$form->print($tmpl) or return $self->error($form->getError());

	if($is_ajax) {
		my $tmp=$tmpl->output();
		return $self->output("<script>parent.document.getElementById('new_subpage').innerHTML='".escape_js($tmp)."';</script>") if ($q->request_method eq "POST");
		return $self->output("$tmp");
	}
	else {
		return $self->output($tmpl->output());
	};
};

sub addLinkedPages {
    my ($self, $newPages) = (shift,shift);
    
    #Supported additional keys (options) at $newPages:
    # -to_top         -
    # -after_page_id  -
    # -disabled       -
    
    my $cms = $self->cms();
    my $dbh = $self->dbh();
    
    my $idx = 0;
    my $subSites = {};
    my @newPagesInt;
    #Делаем проверки
    foreach my $newPage (@$newPages) {
        my $subsiteId = $newPage->{subsite_id};
        
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Duplicated subsite') if exists $subSites->{subsiteId};
        $subSites->{subsiteId} = $subsiteId;
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Forbidden field found (id/tree_order/level)') if exists $newPage->{id} || exists $newPage->{tree_order} || exists $newPage->{level};
        
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Missing parent_id') unless $newPage->{parent_id};
        
        #Загружаем ноду-родителя
        my $tree = $self->_create_tree_object();
        $tree->loadNode($newPage->{parent_id}) or NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'No parent node found');
        my $parentRow = $tree->getNodeValue();
        my $parentURL = $parentRow->{url} || '';
        
        $newPage->{url} ||= '';
        unless ($newPage->{url} eq '/') {
            #URL может быть задан в абсолютном пути, приведем к относительному
            
            $newPage->{url} =~ s/^$parentURL// if $parentURL && $newPage->{url} =~ /^\//;
            
            $newPage->{url} =~ s/^\///;
            $newPage->{url} =~ s/\/$//;
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Missing url') unless $newPage->{url};
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Wrong \'url\' value') if $newPage->{url} =~ /\//;
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Wrong (non-latin) \'url\' value') if $newPage->{url} =~ /[^a-zA-Z0-9\_\-]/;
            $newPage->{url} .= '/';
        };
        
        my $int = {
            PAGEROW => $newPage,
            TREE    => $tree,
            #PARENTROW => $parentRow, #Not used.
            #PREV_SIBLING_ID => ...   #Assigned on later steps.
            #PAGEOBJ         => ...   #Assigned on later steps.
            #TO_TOP          => ...   #Assigned on later steps.
        };
        push @newPagesInt, $int;
        
        $newPage->{url} = $parentURL.$newPage->{url} unless $newPage->{url} eq '/';
        
        #проверка конфликтов URL в пределах одного подсайта.
        my $checkSth = $dbh->prepare("select id,name from ng_sitestruct where url = ? and subsite_id = ?") or return $self->error($DBI::errstr);
        $checkSth->execute($newPage->{url},$subsiteId) or return $self->error($DBI::errstr);
        my $foundPage = $checkSth->fetchrow_hashref();
        $checkSth->finish();
        
        if ($foundPage) {
            $newPage->{url} =~ m/([^\/]+)\/$/;
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx}, "Укажите другое значение URL suffix. Указанный suffix ($1) уже есть в этом разделе - страница '".$foundPage->{name}."'.")
        };
        $idx++;
    };
    
    my $linkId = $self->db()->get_id('ng_sitestruct.link_id');
    return $self->error($self->db()->errstr()) unless $linkId;
    
    my @initialisedPObj = ();
    my @linkedPages = ();
    my $ret = eval {
        #Создаем записи в структуре сайта
        $idx = 0;
        foreach my $int (@newPagesInt) {
            my $newPage = $int->{PAGEROW};
            my $tree    = $int->{TREE};
            
            $newPage->{link_id} = $linkId;
            $newPage->{subptmplgid} ||= "0";
            $newPage->{catch}       ||= "0";
            
            #Ищем ноду, после которой будет добавлена наша новая страница. Посылаем её параметры в event для синхронизации деревьев
            my $lastChild = undef;
            my $opts = {};
            
            if ($newPage->{-to_top}) {
                NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Ошибка создания страницы - конфликт опций -after_page_id и -to_top') if $newPage->{-after_page_id};
                delete $newPage->{-to_top};
                $opts->{TO_TOP} = 1;
                $int->{TO_TOP}  = 1;
            }
            elsif ($newPage->{-after_page_id}) {
                my $aPageId = delete $newPage->{-after_page_id};
                $lastChild = $self->_create_tree_object();
                $lastChild = $lastChild->loadNode(id => $aPageId);
                
                NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Ошибка создания страницы - страница -after_page_id не найдена') unless $lastChild;
                NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Ошибка создания страницы - страница -after_page_id находится в другой ветке') unless $lastChild->{_parent_id} == $newPage->{parent_id};
                $opts->{AFTER} = $lastChild;
            }
            else {
                my $lastChildOrd = $tree->getLastChildOrder();
                if ($lastChildOrd) {
                    $lastChild = $self->_create_tree_object();
                    $lastChild = $lastChild->loadNode(tree_order => $lastChildOrd);
                };
            };
                
            if ($lastChild) {
                $int->{PREV_SIBLING_ID} = $lastChild->{_id};
            };
            
            $newPage->{id} = $self->db()->get_id('ng_sitestruct');
            
            if ($newPage->{-disabled}) {
                $newPage->{disabled} = $newPage->{id} unless $newPage->{disabled};
                delete $newPage->{-disabled};
            };
        
            #NG::Nodes не умеет возвращать ошибки, делает die().
            $newPage->{id} = $tree->DBaddChild($newPage,$opts);
            $idx++;
        };
        #Создаем объекты новых страниц
        my @newPObj = ();
        $idx = 0;
        
        #foreach my $newPage (@$newPages) {
        foreach my $int (@newPagesInt) {
            my $nPObj = $cms->getPageObjById($int->{PAGEROW}->{id}); #Загружаем значение из БД заново, актуальное значение (дефолтные значения полей и прочее).
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Ошибка создания объекта страницы: '.$cms->getError()) unless $nPObj;
            $int->{PAGEOBJ} = $nPObj;
            $idx++;
        };

        #Инициализируем их.
        $idx = 0;
        foreach my $int (@newPagesInt) {
            my $res = $int->{PAGEOBJ}->initialisePage();
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Ошибка инициализации страницы: '.$cms->getError()) unless $res;
            push @initialisedPObj, $int->{PAGEOBJ};
            $idx++;
        };
        
        #Повызываем плагины (бывшие Events)
        $idx = 0;
        foreach my $int (@newPagesInt) {
            next unless $int->{PAGEOBJ};
            NGPlugins->invoke('NG::Application','afterNodeAdded',{PAGEOBJ=>$int->{PAGEOBJ},PREV_SIBLING_ID=>$int->{PREV_SIBLING_ID},TO_TOP=>$int->{TO_TOP}});
            push @linkedPages, {
                PAGEOBJ         => $int->{PAGEOBJ},
                PREV_SIBLING_ID => $int->{PREV_SIBLING_ID},
                TO_TOP          => $int->{TO_TOP},
            };
            $idx++;
        };
        NGPlugins->invokeWhileTrue('NG::Application','afterLinkedNodesAdded',{PAGES=>\@linkedPages}) or NG::Exception->throw('NG.INTERNALERROR','Ошибка выполнения обработчиков afterLinkedPagesAdded(): '.$cms->getError());
        return {PAGES=>\@linkedPages};
    };
    if (my $exc = $@) {
        #Произошла ошибка. Возвращаем всё взад.
        
        #Деинициализируем инициализированные объекты
        eval {
            foreach my $nPObj (@initialisedPObj) {
                $nPObj->destroyPage(\@initialisedPObj);
            };
        };
        
        #Делаем откат вставленных в структуру записей.
        foreach my $newPage (@$newPages) {
            last unless $newPage->{id};
            $dbh->do("delete from ng_sitestruct where id = ?",undef,$newPage->{id}) or warn $DBI::errstr;
        };
        
        #Повызываем плагины еще раз. В обратную сторону.
        if (scalar @linkedPages) {
            eval {
                foreach my $elem (@linkedPages) {
                    NGPlugins->invoke('NG::Application','afterDeleteNode',{PAGEID=>$elem->{PAGEOBJ}->getPageId(),PAGEOBJ=>$elem->{PAGEOBJ}});
                };
            };
        };
        
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},$exc) unless ref $exc;
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Exception: '.$exc->message.' Code: '.$exc->code) unless NG::SiteStruct::Exception->caught($exc);
        die $exc; #Raise up.
    };
    $self->_updateKeysVersion();
    return $ret;
};

sub deleteLinkedPages {
    my ($self, $deletePages) = (shift,shift);
    
    my $cms = $self->cms();
    my $dbh = $self->dbh();
    
    NG::Exception->throw('NG.INTERNALERROR','deleteLinkedPages(): Неверный параметр') unless ref $deletePages eq "ARRAY" && scalar @$deletePages;
    
    my $idx = 0;
    my $indexes = {};
    foreach my $pageId (@$deletePages) {
        $indexes->{$pageId} = $idx++;
    };
    
    #Получаем все страницы связки
    my $linkedPages = $self->_getLinkedPages($deletePages->[0]) or return $cms->error("_getLinkedPages(): method returns unknown error");
    #
    my $linkId;
    #Хэш объектов связанных страниц (все страницы, в т.ч. не удаляемые)
    my $lpageObjs = {};
    #Хэш контроля за линковкой по языку
    my $linkLang = {};
    #Создаем все объекты страниц связки
    foreach my $subsiteId (keys %{$linkedPages}) {
        my $p = $linkedPages->{$subsiteId};
        
        my $lpageObj;
        eval {
            $lpageObj = $cms->getPageObjById($p->{node_id});
        };
        if (my $exc = $@) {
            my $idx = $indexes->{$p->{node_id}};
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx},$exc) unless ref $exc;
            NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Exception: '.$exc->message.' Code: '.$exc->code);
        };
        $lpageObjs->{$p->{node_id}} = $lpageObj;
        $linkLang->{$p->{lang_id}}->{$p->{node_id}} = 1;
        $linkId ||= $p->{link_id};
    };

    #Делаем проверку, что запрошено удаление именно связанных страниц.
    #Делаем проверку отсутствия потомков
    $idx = 0;
    foreach my $pageId (@$deletePages) {
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Удаляемая страница не принадлежит общей группе с другими удаляемыми страницами') unless exists $lpageObjs->{$pageId};
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Обнаружено несовпадение link_id') unless $lpageObjs->{$pageId}->getPageLinkId() == $linkId;
        
        my $childsSth = $dbh->prepare('select id from ng_sitestruct where parent_id = ?') or return $cms->error($DBI::errstr);
        $childsSth->execute($pageId) or return $self->error($DBI::errstr);
        my $child = $childsSth->fetchrow_hashref();
        $childsSth->finish();
        
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},'Невозможно удалить страницу, у которой есть вложенные страницы.') if $child;
        $idx++;
    };
    #Отключаем удаляемые страницы
    foreach my $dpageId (@$deletePages) {
        $dbh->do("update ng_sitestruct set disabled=? where id=?",undef,$dpageId,$dpageId) or return $self->error($DBI::errstr);
    };
    
    #Вызываем обработчики destroyPage()
    foreach my $dpageId (@$deletePages) {
        my $dpageObj = $lpageObjs->{$dpageId};
        
        delete $lpageObjs->{$dpageId};
        delete $linkLang->{$dpageObj->getPageLangId()}->{$dpageId};
        
        my @lpages =();
        foreach my $lnodeId (keys %{$lpageObjs}){
            push @lpages, $lpageObjs->{$lnodeId};
        };
        
        my $res = $dpageObj->destroyPage(\@lpages);
        NG::SiteStruct::Exception->throw({PAGEIDX => $idx},"При удалении страницы $dpageId возникла ошибка вызова destroyPage(). Страницы не были удалены. Текст ошибки: ".$cms->getError("Вызов не вернул текст ошибки.")) unless $res;
    };
    
    #Удаляем страницы из структуры сайта...
    foreach my $dpageId (@$deletePages) {
        $dbh->do("delete from ng_sitestruct where id = ?",undef,$dpageId) or return $self->error($DBI::errstr);
    };
    
    my @vk = ();
    #Вызываем обработчики уведомлений
    foreach my $dpageId (@$deletePages) {
        my $dpageObj = $lpageObjs->{$dpageId};
        NGPlugins->invoke('NG::Application','afterDeleteNode',{PAGEID=>$dpageId,PAGEOBJ=>$dpageObj});
        push @vk, {pageId=>$dpageId};
    };
    
    #Если не осталось страниц в линке, делаем финальную подчистку
    unless (scalar keys %{$lpageObjs}) {
        NGPlugins->invoke('NG::Application','afterDeleteNodeLink',{LINKID=>$linkId});
        push @vk, {linkId=>$linkId};
    }
    else {
        #Если не осталось страниц в некотором языке линка, делаем подчистку
        foreach my $langId (keys %{$linkLang}) {
            next if scalar(keys %{$linkLang->{$langId}});
            NGPlugins->invoke('NG::Application','afterDeleteNodeLink',{LINKID=>$linkId, LANGID=>$langId});
            push @vk, {linkId=>$linkId,langId=>$langId};
        };
    };
    $self->_updateKeysVersion(\@vk);
    1;
};

sub enablePage {
    my ($self,$pageId) = (shift,shift);
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    
    my $node = NG::Nodes->new();
    $node->initdbparams(
        db     => $self->db(),
        table  => "ng_sitestruct",
        fields => $cms->getPageFields(),
    );
    
    $node->loadNode($pageId);
    my $nodeValue = $node->getNodeValue();
    
    return $cms->error("Node already enabled")    if $nodeValue->{disabled} == 0;
    return $cms->error("Node disabled by parent") if $nodeValue->{disabled} != $pageId;
    
    my $where = "";
    my @params = ();
    
    my $bOrder = $node->getSubtreeBorderOrder();
    if ($bOrder) {
        $where .= " tree_order>=? and tree_order<?";
        push @params, $nodeValue->{tree_order};
        push @params, $bOrder;
    } else {
        $where .= " tree_order>=?";
        push @params, $nodeValue->{tree_order};
    };
    
    #Запрашиваем наличие включенных страниц с link_id страниц, подлежащих включению
    my $sth = $dbh->prepare("select link_id,lang_id from ng_sitestruct where disabled = 0 and subsite_id <> ? and link_id <> 0 and link_id in (select link_id from ng_sitestruct where $where and disabled = ?)") or return $cms->error($DBI::errstr);
    $sth->execute($nodeValue->{subsite_id},@params,$pageId) or return $cms->error($DBI::errstr);
    my $allEnabledLinkedPages = $sth->fetchall_hashref(['link_id','lang_id']);
    $sth->finish();
    
    my @vk = ();
    #Запрашиваем список страниц, подлежащих включению, для проведения операций
    my $pageFields = $cms->getPageFields();
    $sth = $dbh->prepare("select $pageFields from ng_sitestruct where $where and disabled = ? order by tree_order") or return $cms->error("disablePage(): Error in pageRow query: ".$DBI::errstr);
    $sth->execute(@params,$pageId) or return $cms->error("getPageRowById(): Error in pageRow query: ".$DBI::errstr);
    while (my $pRow = $sth->fetchrow_hashref()) {
        #warn "Enabling: ".$pRow->{id} ." LI ".$pRow->{link_id}." LA ".$pRow->{lang_id};
        my $pageObj = $cms->getPageObjByRow($pRow,{}) or return $cms->error();
        #$pageObj->enablePage(); #TODO: extend $pageObj API
        
        NGPlugins->invoke('NG::Application','beforeEnableNode',{PAGEID=>$pRow->{id},PAGEOBJ=>$pageObj});
        push @vk, {pageId=>$pRow->{id}};
        next unless $pRow->{link_id};
        
        my $enabledLinkedPages = $allEnabledLinkedPages->{$pRow->{link_id}};
        #Если есть включенные страницы с LINK_ID + LANG_ID - не делаем ничего
        #Если есть LINK_ID, но LANG_ID нет, то посылаем LINK_ID + LANG_ID
        #Если нет  LINK_ID, то посылаем LINK_ID а потом LINK_ID + LANG_ID (два события)
        if ($enabledLinkedPages) {
            unless ($enabledLinkedPages->{$pRow->{lang_id}}) {
                #warn "ENABLING LINKID ".$pRow->{link_id}." LANGID ".$pRow->{lang_id};
                NGPlugins->invoke('NG::Application','beforeEnableNodeLink',{LINKID=> $pRow->{link_id},LANGID=>$pRow->{lang_id}});
                push @vk, {linkId=>$pRow->{link_id},langId=>$pRow->{lang_id}};
            }
        }
        else {
            #warn "ENABLING (1) FULL LINKID ".$pRow->{link_id};
            #warn "ENABLING (2) LANG LINKID ".$pRow->{link_id}." LANGID ".$pRow->{lang_id};
            NGPlugins->invoke('NG::Application','beforeEnableNodeLink',{LINKID=> $pRow->{link_id}});
            NGPlugins->invoke('NG::Application','beforeEnableNodeLink',{LINKID=> $pRow->{link_id},LANGID=>$pRow->{lang_id}});
            push @vk, {linkId=>$pRow->{link_id}};
            push @vk, {linkId=>$pRow->{link_id},langId=>$pRow->{lang_id}};
        };
    };
    $sth->finish();
    
    #Включаем страницы в структуре сайта
    $dbh->do("UPDATE ng_sitestruct set disabled = 0 where $where and disabled = ?", undef, @params, $pageId) or return $cms->error($DBI::errstr);
    
    $self->_updateKeysVersion(\@vk);
    1;
};

sub disablePage {
    my ($self,$pageId) = (shift,shift);
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    
    my $node = NG::Nodes->new();
    $node->initdbparams(
        db     => $self->db(),
        table  => "ng_sitestruct",
        fields => $cms->getPageFields(),
    );
    $node->loadNode($pageId);
    my $nodeValue = $node->getNodeValue();
    
    return $cms->error("Node already disabled") if $nodeValue->{disabled} != 0;
    
    my $where = "";
    my @params = ();
    
    my $bOrder = $node->getSubtreeBorderOrder();
    if ($bOrder) {
        $where .= " tree_order>=? and tree_order<?";
        push @params, $nodeValue->{tree_order};
        push @params, $bOrder;
    } else {
        $where .= " tree_order>=?";
        push @params, $nodeValue->{tree_order};
    };

    #Запрашиваем наличие cвязанных включенных страниц с link_id страниц, подлежащих выключению
    my $sth = $dbh->prepare("select link_id,lang_id from ng_sitestruct where disabled = 0 and subsite_id <> ? and link_id <> 0 and link_id in (select link_id from ng_sitestruct where $where and disabled = 0)") or return $cms->error($DBI::errstr);
    $sth->execute($nodeValue->{subsite_id},@params) or return $cms->error($DBI::errstr);
    my $allEnabledLinkedPages = $sth->fetchall_hashref(['link_id','lang_id']);
    $sth->finish();
    
    #Выключаем страницы в структуре сайта
    $dbh->do("UPDATE ng_sitestruct set disabled = ? where $where and disabled = 0", undef, $pageId, @params) or return $cms->error($DBI::errstr);
    
    my @vk = ();
    #Запрашиваем список страниц, подлежащих выключению, для проведения операций
    my $pageFields = $cms->getPageFields();
    $sth = $dbh->prepare("select $pageFields from ng_sitestruct where $where and disabled = ? order by tree_order desc") or return $cms->error("disablePage(): Error in pageRow query: ".$DBI::errstr);
    $sth->execute(@params,$pageId) or return $cms->error("getPageRowById(): Error in pageRow query: ".$DBI::errstr);
    while (my $pRow = $sth->fetchrow_hashref()) {
        #warn "Disabling: ".$pRow->{id} ." LI ".$pRow->{link_id}." LA ".$pRow->{lang_id};
        my $pageObj = $cms->getPageObjByRow($pRow,{}) or return $cms->error();
        #$pageObj->disablePage(); #TODO: extend $pageObj API
        
        NGPlugins->invoke('NG::Application','afterDisableNode',{PAGEID=>$pRow->{id},PAGEOBJ=>$pageObj});
        push @vk, {pageId=>$pRow->{id}};
        next unless $pRow->{link_id};
        
        my $enabledLinkedPages = $allEnabledLinkedPages->{$pRow->{link_id}};
        if ($enabledLinkedPages) {
            #Есть включенные связанные страницы, проверим язык
            unless ($enabledLinkedPages->{$pRow->{lang_id}}) {
                #Больше не осталось связанных страниц с таким языком 
                #warn "DISABLING LINKID ".$pRow->{link_id}." LANG ".$pRow->{lang_id};
                NGPlugins->invoke('NG::Application','afterDisableNodeLink',{LINKID=> $pRow->{link_id},LANGID=>$pRow->{lang_id}});
                push @vk, {linkId=>$pRow->{link_id},langId=>$pRow->{lang_id}};
            };
            #Есть связанные страницы, линк целиком не отключаем.
        }
        else {
            #Отключаем линк целиком и языковой линк отдельно
            #warn "DISABLING (1) FULL LINKID ".$pRow->{link_id};
            #warn "DISABLING (2) LANG LINKID ".$pRow->{link_id}." LANG ".$pRow->{lang_id};
            NGPlugins->invoke('NG::Application','afterDisableNodeLink',{LINKID=> $pRow->{link_id}});
            NGPlugins->invoke('NG::Application','afterDisableNodeLink',{LINKID=> $pRow->{link_id},LANGID=>$pRow->{lang_id}});
            push @vk, {linkId=>$pRow->{link_id}};
            push @vk, {linkId=>$pRow->{link_id},langId=>$pRow->{lang_id}};
        };
    };
    $sth->finish();
    
    $self->_updateKeysVersion(\@vk);
    
    1;
};

sub action_structPage {
    my ($self,$action,$is_ajax) = (shift,shift,shift);
    
    my $cms = $self->cms();
    my $q   = $cms->q();
    my $dbh = $cms->db()->dbh();
    
    my $tmpl = $cms->gettemplate("admin-side/common/sitestruct/tree.tmpl");
    
    my $pageId  = $self->{_pageId};
    my $showAll = $self->{_showAll};
    
    my $subsiteId = $q->cookie(-name=>"SUBSITEID") || undef;
    
    my $nBase = undef;
    my $nSuff = undef;
    my $allUrl = "";
    
    if ($self->{_pageMode} && $self->opts()->{SUBPAGESHASSTRUCTTAB}) {
        $nBase = $self->SUPER::getModuleObj()->getAdminBaseURL();
        $nSuff = $self->getBaseURL();
        $nSuff =~ s@^$nBase@\/@;
        $nBase =~ s@[^\/\s]+\/$@@;
        $allUrl = $self->getBaseURL(); # Всё дерево раздела
    }
    elsif ($self->{_pageMode}){
        my $stmObj = $self->getStructModuleObj() or return $cms->error();
        $nBase = "/admin-side/modules/".$stmObj->moduleParam('id')."/";
        $nSuff = "/";
        #$allUrl = $nBase."?all=1";             # Все дерево сайта
        $allUrl = $self->getBaseURL(); # Всё дерево раздела
    }
    else {
        $nBase = $self->getBaseURL();
        $nSuff = "/";
        $allUrl = $nBase;
        #ALL_URL = <TMPL_VAR BASEURL>?all=1
        #$upUrl = ""<TMPL_VAR BASEURL><TMPL_VAR PARENT_ID>
    };
    $allUrl .= "$pageId/" if $pageId;
    $allUrl .= "?all=1";
    $allUrl = "" if $showAll;
    
    my $siteRoot = undef;
    my $siteUrl = "http://".$q->virtual_host(); #"http://site"
    if ($cms->confParam("CMS.hasSubsites")) {
        my ($subsites,$sSubsite) = $self->_loadSubsitesForCAdmin($subsiteId);
        $subsites or return $cms->error();
        $siteRoot = $sSubsite->{root_node_id};
        $siteUrl = "http://".$sSubsite->{domain} if $sSubsite->{domain};
        $subsites = [] if (scalar @{$subsites} < 2);
        $tmpl->param(SUBSITES=>$subsites) if !$pageId;
    };
    
    my $subUrl = $self->getSubURL();
    if ($pageId) {
        my $pageObj = $cms->getPageObjById($pageId) or return $cms->error();
        my $pageRow = $pageObj->getPageRow();
        $subsiteId = $pageRow->{subsite_id};
        
        #Разрешено ли добавление страниц
        my $canAddSubnode = $self->_canAddSubpage($pageObj);
        
        ##Линкованные подстраницы.
        my $linkedPages = $self->_getLinkedPages($pageObj) or return $self->showError("_getLinkedPages(): method returns unknown error");
        
        #Список привилегий на подсайты 
        #my $allSubsitesPrivileges = $dbh->selectall_hashref("select subsite_id,privilege from ng_subsite_privs where admin_id = ? and (privilege='ACCESS' or privilege='PROPERTIES' or privilege='CONTENT')",["subsite_id","privilege"],undef,$adminId);
        
        #Список привилегий на линкованные страницы
        #my $linkedPagesPrivileges = $dbh->selectall_hashref("select page_id,privilege,block_id from ng_page_privs p,ng_sitestruct s where s.link_id=? and p.page_id=s.id  and p.admin_id=?",["page_id","block_id","privilege"],undef,$pageRow->{link_id},$adminId);
        
        my $hasLinkedPages = 0;
        my @linkedpages = ();
        #В т.ч Формируем флаги привилегий на кнопки "свойства" и "контент" линкованных страниц
        foreach my $subsiteId (keys %{$linkedPages}) {
            my $lp = $linkedPages->{$subsiteId};
            #next unless exists $allSubsitesPrivileges->{$subsiteId}->{ACCESS};
            #$lp->{PRIVILEGE}->{PROPERTIES} = 1 if exists $allSubsitesPrivileges->{$lp->{subsite_id}}->{PROPERTIES};
            #$lp->{PRIVILEGE}->{CONTENT}    = 1 if exists $allSubsitesPrivileges->{$lp->{subsite_id}}->{CONTENT};
            #$lp->{PRIVILEGE}->{PROPERTIES} = 1 if (exists $linkedPagesPrivileges->{$lp->{node_id}}->{0}->{PROPERTIES});
            ##TODO: привилегия вычисляется неверно
            #$lp->{PRIVILEGE}->{CONTENT}    = 1 if (scalar keys %{$linkedPagesPrivileges->{$lp->{node_id}}} > 1);
            $lp->{PRIVILEGE} = {
                PROPERTIES=>1,
                CONTENT=>1,
            };
            
            #if ($value->{_amenu_nodeid} && $self->{_pageMode}) {
            #    $value->{NODEURL} = "/admin-side/pages/".$value->{id}.$nSuff;
            #}
            #else {
            #    $value->{NODEURL} = $nBase.$value->{node_id}.$nSuff;
            #}
            
            #$value->{NODELINK} = $value->{NODEURL};
            $lp->{NODELINK} = $nBase.$lp->{node_id}.$nSuff;
            $lp->{NODELINK}.="?all=1" if $showAll && $self->{_pageMode};
            
            push @linkedpages,$lp;
        };
        $hasLinkedPages = 1;
        if (scalar @linkedpages == 1) {
            @linkedpages = ();
            $hasLinkedPages = 0;
        };
        
        my $nodeInfo = {
            INFO    => [],
            ACTIONS => [],
        };
        
        push @{$nodeInfo->{INFO}}, {NAME => 'Код страницы',      VALUE => $pageRow->{id}    };
        push @{$nodeInfo->{INFO}}, {NAME => 'Название страницы', VALUE => $pageRow->{name}  };
        #push @{$nodeInfo->{INFO}}, {NAME => 'Основной шаблон',   VALUE => $pageTemplateName };
        push @{$nodeInfo->{INFO}}, {NAME => 'Адрес', PAGEURL => $siteUrl.$pageRow->{url}    };
        
        #TODO: надо ли проверять права на действие активация ?
        my $status = {};
        if ($pageRow->{disabled}==0) {
            #Страница включена
            my $canDeactivate = 1;
            $canDeactivate = $pageObj->canDeactivate() if $pageObj->can("canDeactivate");
            $status->{ACTIVE} = 1;
            $status->{NO_DEACTIVE} = "Не отключаема" unless $canDeactivate eq "1";
            $status->{NO_DEACTIVE} = $canDeactivate if $canDeactivate && $canDeactivate ne "1";
        }
        elsif ($pageRow->{disabled}==$pageRow->{id}) {
            #Страница выключена сама
            my $canActivate = 1;
            $canActivate = $pageObj->canActivate() if $pageObj->can("canActivate");
            $status->{ACTIVE}    = 0;
            $status->{NO_ACTIVE} = "Не все блоки заполнены" unless $canActivate eq "1";
            $status->{NO_ACTIVE} = $canActivate if $canActivate && $canActivate ne "1";
        }
        else {
            #Страница выключена сверху
            $status->{ACTIVE} = 0;
            $status->{DEACTIVE_ID} = $pageRow->{disabled};
        };
        push @{$nodeInfo->{INFO}}, {STATUS=>$status};
        
        if ($canAddSubnode) {
            push @{$nodeInfo->{ACTIONS}}, {
                FORM     => 1,
                FORM_URL => $self->{_pageURL}."?action=addsubnodeform&haslinkedpages=$hasLinkedPages",
                AJAX_URL => $self->{_pageURL}."?action=addsubnodeform&haslinkedpages=$hasLinkedPages&_ajax=1",
                NAME     => 'Добавить',
            };
        };
        push @{$nodeInfo->{ACTIONS}},{
            FORM=>1,
            FORM_URL => $self->{_pageURL}."?action=editnodeform",
            AJAX_URL => $self->{_pageURL}."?action=editnodeform&_ajax=1",
            NAME     => 'Редактировать',
        };
        
        $self->processNodeInfo($pageObj,$nodeInfo);
        
        $tmpl->param(
            PAGE_LINKEDPAGES => \@linkedpages,
            NODEINFO=>$nodeInfo,
        );
    };
    
    my $rootId = $pageId;
    $rootId ||= $siteRoot;
    my $tree = NG::Nodes->new();
    $tree->initdbparams(
        db     => $self->db(),
        table  => "ng_sitestruct",
        fields => "main.name,main.full_name,main.title,main.url,main.module_id,main.template,main.print_template,main.disabled,ngm.node_id as _amenu_nodeid",
        join   => "left join ng_admin_menu ngm on main.id = ngm.node_id", 
    );

    if ($showAll) {
        $tree->loadtree($rootId);
    }
    else {
        my $opts = {};
        $opts->{SELECTEDNODE} = $pageId;
        $opts->{OPEN_LEVELS} = 2;
        $tree->loadPartOfTree2($rootId,$opts);
    };
    
    $tree->traverse(
        sub {
            my $_tree = shift;
            my $value = $_tree->getNodeValue();
            
            if ($value->{_amenu_nodeid} && $self->{_pageMode}) {
                $value->{NODEURL} = "/admin-side/pages/".$value->{id}.$nSuff;
            }
            else {
                $value->{NODEURL} = $nBase.$value->{id}.$nSuff;
            }
            
            $value->{NODELINK} = $value->{NODEURL};
            $value->{NODELINK}.="?all=1" if $showAll && $self->{_pageMode};
            
            $value->{PRIVILEGES}->{DELPAGE} = 1;
			
			my $p = $_tree->getParent();
            $value->{CANENABLE} = 1;
            $value->{CANENABLE} = 0 if $p->getNodeValue()->{disabled};			
            #$value->{CANTENABLE} = 1 unless $value->{disabled} == 0 || $value->{disabled} == $value->{id};
            
            $value->{NOACCESS} = 1 if $value->{disabled};
            
            $value->{IS_TOP} = 1 if ($rootId && $value->{id} == $rootId) || (!$pageId && $value->{parent_id}==0);
            if ($pageId && $value->{id} == $pageId && $value->{parent_id}!=0 && (!defined $siteRoot || $value->{id} != $siteRoot)) {
                my $mBaseUrl = $self->getModuleObj()->getBaseURL();
                unless ($self->{_pageMode} && $mBaseUrl && $mBaseUrl eq $value->{url}) {
                    $value->{UP_URL} = $nBase.$value->{parent_id}.$nSuff;
                    $value->{UP_URL}.= "?all=1" if $showAll;
                };
            };
        }
    );
    
	$tree->printToDivTemplate($tmpl,'TREE',$pageId);
    
    $tmpl->param(
        SHOW_ALL => $showAll,
        BASEURL  => $self->getBaseURL(),
        THISNODEURL  => $self->{_pageURL},  #Адрес админки ноды
        ALL_URL  => $allUrl,
        SITEURL  => $siteUrl,
    );
    return $self->output($tmpl->output());
##

=comment
    my $adminId = $cms->getAdminId();

	my $pageRow = $pageObj->getPageRow();
	my $subsiteId = $pageObj->getSubsiteId();

	#Название шаблона
	my $pageTemplateName = $dbh->selectrow_array("select name from ng_templates where id=?",undef,$pageRow->{template_id});
	
	#TODO: проверять наличие ошибок после вызова canAddPage
	
	#Список подстраниц
    my $subpagessth = $dbh->prepare("select ng_sitestruct.id as page_id,parent_id,ng_sitestruct.name as page_name,ng_sitestruct.active as page_active,url, template_id, ng_templates.name as template_name, module from ng_sitestruct left join ng_templates on ng_templates.id=ng_sitestruct.template_id where parent_id = ? order by tree_order")  or return $self->error($DBI::errstr);
    $subpagessth->execute($pageRow->{id}) or return $self->error($DBI::errstr);
    my $subpages = $subpagessth->fetchall_arrayref({}) or return $self->error($DBI::errstr);
    $subpagessth->finish();    
    
    #Список привилегий на подстраницы
    my $subsitePrivileges = $cms->getAdminSubsitePrivileges($adminId,$subsiteId);
    my $subpagesPrivileges = $dbh->selectall_hashref("select page_id,privilege,block_id from ng_page_privs p,ng_sitestruct s where s.parent_id=? and p.page_id=s.id and p.admin_id=?",["page_id","block_id","privilege"],undef,$pageRow->{id},$adminId);

	#Формируем флаги привилегий на кнопки "свойства", "контент" и "удалить" подстраниц
	foreach my $sp (@{$subpages}) {
		# Свойства страницы
		$sp->{PRIVILEGE}->{PROPERTIES} = 0;
		if (exists $subsitePrivileges->{PROPERTIES}) {
			$sp->{PRIVILEGE}->{PROPERTIES} = 1;
		}
		elsif (exists $subpagesPrivileges->{$sp->{page_id}}->{0}->{PROPERTIES}) {
			$sp->{PRIVILEGE}->{PROPERTIES} = 1;
		};
		# Редактирование контента страницы
		$sp->{PRIVILEGE}->{CONTENT} = 0;
		if (exists $subsitePrivileges->{CONTENT}) {
			$sp->{PRIVILEGE}->{CONTENT} = 1;
		}
		else {
			foreach (keys %{$subpagesPrivileges->{$sp->{page_id}}}) {
				next if $_ eq "PROPERTIES";
				next if $_ eq "NEWPAGE";
				next if $_ eq "DELPAGE";
				$sp->{PRIVILEGE}->{CONTENT} = 1;
				last;
			};
		};
		# Удаление страницы
		$sp->{PRIVILEGE}->{DELPAGE} = 0;
		if (exists $subsitePrivileges->{DELPAGE}) {
			$sp->{PRIVILEGE}->{DELPAGE} = 1;
		}
		elsif (exists $subpagesPrivileges->{$sp->{page_id}}->{0}->{DELPAGE}) {
			$sp->{PRIVILEGE}->{DELPAGE} = 1;
		};
	};

	my $tmpl = $self->app()->gettemplate($self->{_pstructtemplate})  || return $self->showError(); 


	
    my $greetings = {};
    my $q_greeting = $q->param('greeting') || "";
    $greetings->{ACTIVATE} = 1 if ( $q_greeting eq "activate");
    
	# Интересные параметры, TODO: выверить
	my $myHostname = $q->virtual_host();
	my $u = $self->q()->url(-query=>1); # Текущий URL, без учета AJAX/noAJAX, для возврата в исходную страницу после действий
	$u =~ s/_ajax=1//; 
    
    $tmpl->param(
        PAGE_ID   => $pageRow->{id},
        PAGE_NAME => $pageRow->{name},
        PAGE_URL  => $pageRow->{url},
        PAGE_MTEMPLATE_NAME => $pageTemplateName,
        PAGE_SUBPAGES => $subpages,
        URL       => $myHostname,
        REF       => $u,
        GREETINGS => $greetings,
	);
	
	return $self->output($tmpl->output());
=cut
};

sub _create_tree_object {
	my $self = shift;
	
	my $cms = $self->cms();
	my $fields = $cms->getPageFields();

    my $to = NG::Nodes->new();
    $to->initdbparams(
        db    =>$cms->db(),
        table =>"ng_sitestruct", #TODO: this is constanta...
        fields=>$fields,
    );
    return $to;
};

sub _moveNode {
	my $self = shift;
    my $dir = shift;
	my $action = shift;
	my $is_ajax = shift;

    my $cms = $self->cms();
    my $q = $cms->q();


    my $pageId = $q->param('id');
    is_valid_id($pageId) or return $cms->error("Некорректный код страницы");

    my $tree = $self->_create_tree_object();
	$tree->loadNode($pageId) or return $self->error("No node found");
    my $value = $tree->getNodeValue;
    my $parent_pageId = $value->{parent_id};
=comment
    my $canMoveNode = $cms->hasPageBlockPrivilege(
                            PAGE_ID   => $parent_pageId,
                            BLOCK_ID  => 0,
                            PRIVILEGE => "NEWPAGE",
                            SUBSITE_ID => $value->{subsite_id},
                        );
    return $self->error("Отсутствует право добавления страниц в раздел") unless $canMoveNode;
=cut    
    my $partner = $self->_create_tree_object();
    if ($dir eq "up") {
        my $prevso = $tree->getPrevSiblingOrder();
        if ($prevso) {
            $partner->loadNode(tree_order=>$prevso);
            $tree->DBmoveNode(before => $partner);
            
            NGPlugins->invoke('NG::Application','afterSwapNodes',{NODE=> $tree->getNodeValue(), ACTION=> "before", PARTNER=> $partner->getNodeValue()});
        };
    }
    elsif ($dir eq "down") {
        my $nextso = $tree->getNextSiblingOrder();
        if ($nextso) {
            $partner->loadNode(tree_order=>$nextso);
            $tree->DBmoveNode(after => $partner);
            
            NGPlugins->invoke('NG::Application','afterSwapNodes',{NODE=> $tree->getNodeValue(), ACTION=> "after", PARTNER=> $partner->getNodeValue()});
        };
    };
    $self->_updateKeysVersion();
    return $self->_redirect($parent_pageId,0);
};

sub action_moveNodeUp {
    my $self = shift;
    return $self->_moveNode("up",@_);
};

sub action_moveNodeDown {
    my $self = shift;
    return $self->_moveNode("down",@_);
};

sub _injectPageFormFields {
    my $self = shift;
    my $pageObj = shift;
    my $form = shift;
    
    my $cms = $self->cms();
    return 1 unless $pageObj->can("getPageFormFields");
    
    my $res = $pageObj->getPageFormFields() or return $cms->error();
    return $self->error("Метод getPageFormFields() модуля ".ref($pageObj)." не вернул ссылку на поля формы.") unless (ref $res);
    $form->addfields($res) or return $cms->error($form->getError());
    return 1;
};

sub _getUpdateNodeForm {
	my $self = shift;
	my $pageObj = shift;
	
    my $baseUrl = $self->getBaseURL();
	my $subUrl = $self->getSubURL();
	my $form = NG::Form->new(
		FORM_URL  => $baseUrl.$subUrl."?action=updatenode", #TODO: неправильный URL,
		TABLE => "ng_sitestruct",
        DOCROOT   => "z", #TODO: kostyl` ?
        DB        => $self->db(),
        CGIObject => $self->q(),
        REF       => $baseUrl.$subUrl,
	);

	$form->addfields ([	
		#{NAME=>"Код родительской ноды",FIELD=>"parent_id",TYPE=>"hidden"},
        {NAME=>"Код ноды",FIELD=>"id",TYPE=>"id"},
    ]);
	
	my $baseFields = $self->getBaseFields();
    $form->addfields($baseFields) or return $self->error($form->getError());
    
    $self->_injectPageFormFields($pageObj,$form) or return $self->showError("_injectPageFormFields(): Some error happens.");
    

	my $descrFields = $self->getDescrFields();
    $form->addfields($descrFields) or return $self->error($form->getError());

    $form->setcontainer('new_subpage');
	return $form;
};

sub action_updateNode {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $dbh = $cms->db()->dbh();
    
    my $pageId = $self->{_pageId} or return $cms->error("Некорректный код страницы");
    
    my $node = $self->_create_tree_object();
    $node->loadNode($pageId) or return $self->error("No node found"); 
    my $oldValue = $node->getNodeValue();
    
    my $pageObj = $cms->getPageObjByRow($oldValue) or return $cms->error();
    
    my $form = $self->_getUpdateNodeForm($pageObj);
    $form->{_ajax} = $is_ajax;
    $form->setTitle('Редактирование свойств страницы: "'.$oldValue->{name}.'"') unless $is_ajax;
    
    my $newUrlSuffix = undef;
    my $nodeUrl = $oldValue->{url};
    if ($action eq "editnodeform") {
        my $oldUrl = $oldValue->{url};
        $oldUrl =~ /([^\/]*)\/$/;
        $oldUrl = ($oldUrl ne "/"?$1:"/"); #($1 || "/";)
        
        local $oldValue->{url} = $oldUrl;
        
        my $fields = $form->fields();
        #Выставляем полученные значения
        foreach my $field (@{$fields}) {
            $field->setLoadedValue($oldValue) or return $cms->error($field->error() || "Ошибка вызова setLoadedValue() поля ".$field->{FIELD});
        };
        #Дополнительные действия
        foreach my $field (@{$fields}) {
            $field->afterLoad() or return $cms->error("Ошибка вызова afterLoad() поля $field->{FIELD}: ".$field->error());
        };
    }
    elsif ($action eq "updatenode") {
        $form->setFormValues();
        
        my $id = $form->getParam('id');
        if (!$id || $id != $pageId) {
            return $self->error("Код страницы в адресной строке не совпадает с кодом страницы из формы!");
        };
        
        $newUrlSuffix  = $form->getParam('url');
        $newUrlSuffix =~ s/^\///;
        $newUrlSuffix =~ s/\/$//;
        
        my $siteRootPageId = undef;
        my $subsiteId = $pageObj->getSubsiteId();
        if ($cms->confParam("CMS.hasSubsites")) {
            my $row = $dbh->selectrow_hashref("select root_node_id from ng_subsites where id = ?",undef,$subsiteId) or return $cms->error($DBI::errstr);
            defined $row->{root_node_id} or return $cms->error("Не могу найти значение root_node_id для подсайта");
            $siteRootPageId = $row->{root_node_id};
        };
        
        my $canChangeURL = 1;
        $canChangeURL = 0 if (defined $siteRootPageId && $siteRootPageId == $pageId) || ($oldValue->{url} eq "/");
        
        if ($newUrlSuffix =~/[^a-zA-Z0-9\_\-]/) {
            $form->pusherror("url","Значение должно содержать только латинские символы и цифры");
            $canChangeURL = 0;
        };
        
        if ($canChangeURL) {
            $nodeUrl =~ s@([^\/]*)\/$@$newUrlSuffix\/@;
        };
        if ($oldValue->{url} ne $nodeUrl) {
            #проверка конфликтов URL в пределах одного подсайта.
            my $checkSth = $dbh->prepare("select id,name from ng_sitestruct where url = ? and subsite_id = ?") or return $self->error($DBI::errstr);
            $checkSth->execute($nodeUrl,$subsiteId) or return $self->error($DBI::errstr);
            my $foundPage = $checkSth->fetchrow_hashref();
            $checkSth->finish();
            
            if ($foundPage && $foundPage->{id} != $pageId) {
                $form->pusherror("url", "Укажите другое значение URL suffix. Указанный suffix ($newUrlSuffix) уже есть в этом разделе - страница '".$foundPage->{name}."'.")
            };
        };
        
        $form->StandartCheck();
        if ($form->has_err_msgs()) {
            $form->cleanUploadedFiles();
            return $self->output($form->ajax_showerrors()) if ($is_ajax);
        };
    }
    else {
        return $cms->error("Incorrect action $action");
    };
    
    if ($action eq "editnodeform" || $form->has_err_msgs()) {
        my $tmpl = $cms->gettemplate("admin-side/common/universalform.tmpl") or return $cms->error();
        $form->print($tmpl) or return $self->error($form->getError());
        return $self->output($tmpl->output());
    };
    
    #rest: $action eq "updatenode", $form has no error msgs

    $form->param("url",$nodeUrl);
    $form->updateData() or return $self->error("Не удалось обновить данные: ".$form->getError());
    
    my @vk = ();
    push @vk, {pageId=>$pageId};
    
    my $newValue = undef;
    if ($oldValue->{url} ne $nodeUrl) {
        my $tree = $self->_create_tree_object();
        $tree->loadtree($pageId);
        $newValue = $tree->getChild(0)->getNodeValue();
        
        NGPlugins->invoke('NG::Application','afterUpdateNodeURL',{PAGEID=>$pageId, OLDURL=>$oldValue->{url},NEWURL=>$nodeUrl});
        
        my $sth  = $dbh->prepare("UPDATE ng_sitestruct SET url=? WHERE id=?") or die $DBI::errstr;
        my $mSth = $dbh->prepare("UPDATE ng_modules SET base=? WHERE id=? AND base=?") or die $DBI::errstr;
        
        my $oldBase = $oldValue->{url};
        
        if ($oldValue->{module_id}) {
            $mSth->execute($nodeUrl,$oldValue->{module_id},$oldBase) or warn $DBI::errstr;
        };
        
        my $res = $tree->traverseWithCheck(
            sub {
                my $_tree = shift;
                my $value = $_tree->getNodeValue();
                
                my $oldUrl=$value->{'url'};
                $value->{url} =~ s@^$oldBase(.*)$@$nodeUrl$1@;
                
                if ($_tree->{_id} != $pageId) {
                    if ($value->{module_id}) {
                        $mSth->execute($value->{url},$value->{module_id},$oldUrl) or warn $DBI::errstr;
                    };
                    
                    $sth->execute($value->{url},$_tree->{_id}) or return $cms->error($DBI::errstr." БД находится в поврежденном состоянии") + 1;
                    
                    NGPlugins->invoke('NG::Application','afterUpdateNodeURL',{PAGEID=>$_tree->{_id}, OLDURL=>$oldUrl, NEWURL=>$value->{url}});
                    push @vk, {pageId=>$_tree->{_id}};
                };
                return 0;
            }
        );
        return $cms->error() if $res;
        $sth->finish();
        $mSth->finish();
    }
    else {
        my $newNode = $self->_create_tree_object();
        $newNode->loadNode($pageId) or return $self->error("No node found"); 
        $newValue = $newNode->getNodeValue();
    };
    #TODO: передается старый $pageObj
    NGPlugins->invoke('NG::Application','afterUpdateNode',{PAGEID=>$pageId, PAGEOBJ=>$pageObj, OLDVALUE=>$oldValue, NEWVALUE=>$newValue});
    $self->_updateKeysVersion(\@vk);
    return $self->_redirect($pageId,$is_ajax);
}; 

sub action_enablePage {
    my $self = shift;
    my $action = shift;
    my $is_ajax = shift;

    my $cms = $self->cms();
    my $q = $cms->q();

    my $pageId = $q->param('id');
    $pageId = $self->{_pageId} unless defined $pageId;
    is_valid_id($pageId) or return $cms->error("Некорректный код страницы");
    
    $self->enablePage($pageId) or return $cms->error();

    return $self->_redirect($pageId,0);
};

sub action_disablePage {
    my $self = shift;
    my $action = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
    my $q = $cms->q();

    my $pageId = $q->param('id');
    $pageId = $self->{_pageId} unless defined $pageId;
    is_valid_id($pageId) or return $cms->error("Некорректный код страницы");

    $self->disablePage($pageId) or return $cms->error();
    
    return $self->_redirect($pageId,0);
};

sub action_deleteNode {
    my $self = shift;
    my $action = shift;
    my $is_ajax = shift;

    my $cms = $self->cms();
    my $q = $self->q();
    my $pageId = $q->param('id');
    is_valid_id($pageId) or return $cms->error("Некорректный код страницы");
    my $subUrl = $self->getSubURL();
    
    my $pageObj = $cms->getPageObjById($pageId) or return $cms->error();
    
    my $db  = $cms->db();
    my $dbh = $db->dbh();

    my $adminId = $cms->getAdminId();
    my $linkId = $pageObj->getPageLinkId();

    my $doDelAction = ($q->request_method eq "POST")?1:0;
    my $linkedPages = $self->_getLinkedPages($pageObj) or return $cms->error("_getLinkedPages(): method returns unknown error");

    #TODO: привилегия на удаление - DELPAGE
    #my $allSubsitesPrivileges = $dbh->selectall_hashref("select subsite_id,privilege from ng_subsite_privs where admin_id = ? and (privilege='ACCESS' or privilege='NEWPAGE')",["subsite_id","privilege"],undef,$adminId);

    my @lp;
    my @deleteLinkedPages;
    foreach my $subsiteId (keys %{$linkedPages}) {
        my $page = $linkedPages->{$subsiteId};
        
        my $canDelThisPage = 0;
=head TODO: privileges
        if (!exists $allSubsitesPrivileges->{$page->{subsite_id}}->{ACCESS}) {
            $canDelThisPage = 0;    
        }
        elsif (exists $allSubsitesPrivileges->{$page->{subsite_id}}->{NEWPAGE}) {
            $canDelThisPage = 1;
        }
        elsif ($app->hasPageBlockPrivilege(PAGE_ID => $page->{parent_id}, BLOCK_ID => 0, PRIVILEGE => "NEWPAGE")) {
            $canDelThisPage = 1;
        };
=cut
$canDelThisPage = 1;

        if ($canDelThisPage) {
            my $childsSth = $dbh->prepare('select id from ng_sitestruct where parent_id = ?') or return $cms->error($DBI::errstr);
            $childsSth->execute($page->{node_id}) or return $self->error($DBI::errstr);
            my $child = $childsSth->fetchrow_hashref();
            $childsSth->finish();
            
            if ($child) {
                $canDelThisPage = 0;
                $page->{MESSAGE} = "Невозможно удалить страницу, у которой есть вложенные страницы.";
            };
        };
        
        if ($doDelAction) {
            if ($q->param("dodelnode_".$page->{node_id}) eq "1") {
                return $self->error("Отсутствуют привилегии на запрошенное удаление страниц") unless $canDelThisPage;
                push @deleteLinkedPages, $page;
            };
        }
        else {
            if ($canDelThisPage) {
                $page->{CHECKED} = 1 if ($page->{node_id} == $pageId);
            }
            else {
                $page->{CHECKED} = 0;
                $page->{READONLY} = 1;
            };
        };
        push @lp,$page;
    };
    if ($doDelAction) {
        my @deletePageId = ();
        foreach my $page (@deleteLinkedPages) {
            push @deletePageId, $page->{node_id};
        };
        
        eval {
            $self->deleteLinkedPages(\@deletePageId);
        };
        if (my $exc = $@) {
            #TODO: УВЫ, через MESSAGE ошибки не отображаются.
            if (NG::SiteStruct::Exception->caught($exc)) {
                my $idx = $exc->params()->{PAGEIDX} || 0;
                $deleteLinkedPages[$idx]->{MESSAGE} = $exc->message();
            }
            else {
                my $message;
                if (ref $exc) {
                    $message = $exc->message();
                }
                else {
                    $message = $exc;
                };
                $deleteLinkedPages[0]->{MESSAGE} = $message;
            };
        }
        else {
            return $self->_redirect($pageObj->getParentPageId(),$is_ajax);
        };
    };
    
    my $message = "";
    if (scalar @lp == 1) {
        $message = $lp[0]->{MESSAGE};
        @lp = ();
    };
   
    my $showAll = $self->{_showAll};
    my $tmpl = $cms->gettemplate("admin-side/common/sitestruct/deletepages.tmpl")  || return $cms->error();
    my $baseUrl = $self->getBaseURL();
    $tmpl->param(
        FORM_URL     => $baseUrl.$subUrl."?action=deletenode",
        CONTAINER    => "tree_form".$pageId,
        KEY_VALUE    => "del_subpage".$pageId,
        IS_AJAX      => $is_ajax,
        LINKED_PAGES => \@lp,
        ID           => $pageId,
        MESSAGE      => $message,
        ALL          => $showAll,
    );
    return $self->output($tmpl->output());
};

sub _updateKeysVersion {
    my $self = shift;
    my $keys = shift;
    
    $keys = [$keys] if $keys && ref $keys eq "HASH";
    $keys ||= [];
    
    my $cms = $self->cms();
    my $code = $cms->confParam("CMS.SiteStructModule","") or die 'No code';

    $_->{MODULECODE} = $code foreach @$keys;
    push @$keys, {MODULECODE=>$code, key=>'anypage'};
    
    #Supported keys:
    # {key=>'anypage'},
    # {pageId=>$pageId},
    # {linkId=>$linkId},
    # {linkId=>$linkId, langId=>$langId},
    
    $cms->updateKeysVersion(undef,$keys);
};


sub _redirect {
    my $self = shift;
	my $dNode = shift;
	my $is_ajax = shift || 0;
    
    my $cms = $self->cms();
    my $q = $cms->q();
    
    my $showAll = $self->{_showAll};
    
    my $nodeId = $self->{_pageId};
    $nodeId = $dNode unless defined $nodeId;
    
    my $url = undef;
    if ($self->{_pageMode}) {
        #$url = $self->getBaseURL();
        #$url .= "?all=1" if $showAll;
        my $nBase = $self->SUPER::getModuleObj()->getAdminBaseURL();
        my $nSuff = $self->getBaseURL();
        $nSuff =~ s@^$nBase@\/@;
        $nBase =~ s@[^\/\s]+\/$@@;
        $url = $nBase .$nodeId .$nSuff;
        $url .= "?all=1" if $showAll;
    }
    else {
        $url = $self->getBaseURL();
        $url .= "$nodeId/" if $nodeId;
        $url .= "?all=1" if $showAll;
    };
    return $self->fullredirect($url, $is_ajax);
};

sub _loadSubsitesForCAdmin {
    my $self = shift;
    my $subsiteId = shift;
   
    my $cms = $self->cms();
    my $dbh = $cms->dbh();

    #my $sth = $dbh->prepare("select id,lang_id,name,root_node_id,domain from ng_subsites,ng_subsite_privs where ng_subsite_privs.subsite_id = ng_subsites.id and admin_id = ? and privilege = 'ACCESS'") or die $DBI::errstr;
    #$sth->execute($cms->getAdminId()) or return $cms->error($DBI::errstr);
    my $sth = $dbh->prepare("select id,lang_id,name,root_node_id,domain from ng_subsites") or die $DBI::errstr;
    $sth->execute() or return $cms->error($DBI::errstr);

    my @subsites;
    my $sRow = undef; 
    while (my $row= $sth->fetchrow_hashref()) {
        $sRow = $row if (defined $subsiteId and $row->{id} == $subsiteId);
        push @subsites, $row;
    };
    $sth->finish();
    return ([],undef) unless scalar @subsites;
    $sRow = $subsites[0] unless ($sRow);
    $sRow->{SELECTED} = 1;
    return (\@subsites,$sRow);
};

sub action_switchSubsite {
    my $self = shift;
    #TODO: аналогичный код в NG::PagePrivs
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $subsiteid = $q->param('subsite_id');
    #my $frompageid = $q->param('frompageid');
    #
    #return $self->redirect_url("/admin-side/?_left=struct") unless is_valid_id($subsiteid);
    #my $newNodeId = undef;
    #if (is_valid_id($frompageid)) {
    #    ($newNodeId) = $self->db()->dbh()->selectrow_array("select id from ng_sitestruct where subsite_id = ? and link_id = (select link_id from ng_sitestruct where id = ?)",undef,$subsiteid,$frompageid);
    #};
    #if (!is_valid_id($newNodeId)) {
    #   my $page = $self->db()->dbh()->selectrow_hashref("select id,tree_order,level from ng_sitestruct where id=?",undef,$frompageid);
    #   ($newNodeId) = $self->db()->dbh()->selectrow_array("select n2.id from (select n.link_id,n.tree_order from (select max(tree_order) as maxorder from ng_sitestruct where tree_order <=? and level <=? group by level) o,ng_sitestruct n where n.tree_order=o.maxorder and n.level>0 order by n.tree_order desc) n1 left join ng_sitestruct n2 on (n2.link_id = n1.link_id)  where n2.subsite_id=? order by n1.tree_order desc limit 1",undef,$page->{tree_order},$page->{level},$subsiteid);
    #};
    #if (!is_valid_id($newNodeId)) {
    #    ($newNodeId) = $self->db()->dbh()->selectrow_array("select root_node_id from ng_subsites where id = ?",undef,$subsiteid);
    #};
    #
    #if ($newNodeId) {
    #    $self->addCookie(-name=>"SUBSITEID",-value=>$subsiteid,-domain=>$q->virtual_host(),-path=>"/admin-side/");
    #    return $self->redirect_url("/admin-side/pages/$newNodeId/");
    #};
    $cms->addCookie(-name=>"SUBSITEID",-value=>$subsiteid,-domain=>$q->virtual_host(),-path=>"/admin-side/");
    return $cms->redirect($self->getBaseURL());
    #return $self->redirect_url("/admin-side/pages/?_left=struct");
};

sub processEvent {
    my $self = shift;
    my $event = shift;
    
    my $opts = $event->options();
    
#use Data::Dumper;
#print STDERR Dumper($opts->{NODE})."\n".$opts->{ACTION}."\n".Dumper($opts->{PARTNER});
    
    if ($event->isa("NG::Module::Menu::Event")) {
        return unless ($opts->{NODE}->{node_id} && $opts->{PARTNER}->{node_id});
        
        unless ($opts->{ACTION} eq "before" || $opts->{ACTION} eq "after") {
            print STDERR "Invalid ACTION ".$opts->{ACTION}. " in NG::Module::Menu::Event\n";
            return;
        };
        
        my $node = $self->_create_tree_object();
        $node->loadNode($opts->{NODE}->{node_id});

        my $pnode = $self->_create_tree_object();
        $pnode->loadNode($opts->{PARTNER}->{node_id});

        unless ($node && $pnode) {
            print STDERR "No node found with ID=".$opts->{NODE}->{node_id}."\n";
            return;
        };
        unless ($pnode) {
            print STDERR "No pnode found with ID=".$opts->{PARTNER}->{node_id}."\n";
            return;
        };
        if ($node->{_parent_id} == $pnode->{_parent_id}) {
            $node->DBmoveNode($opts->{ACTION} => $pnode) ;
            NGPlugins->invoke('NG::Application','afterSwapNodes',{NODE=> $node->getNodeValue(), ACTION=> $opts->{ACTION}, PARTNER=> $pnode->getNodeValue()});
        };
    };
};

package NG::SiteStruct::Exception;
use strict;

our @ISA = qw(NG::Exception);

sub throw {
    my ($class,$params,$message) = (shift,shift,shift);
    
    $Carp::Internal{'NG::SiteStruct::Exception'}++;
    my $code = "NG.SITESTRUCT.EXCEPTION";
    my $self = $class->SUPER::new($code,$message);
    $self->{_params} = $params;
    die $self;
};

sub params {
    my $self = shift;
    return $self->{_params};
};

BEGIN {
    use NGPlugins;
    NGPlugins->registerPlugin('NG::Application','NG::Adminmenu');
    NGPlugins->registerPlugin('NG::Application','NG::DBI');
};

return 1;
END{};
