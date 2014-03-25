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

use NG::Block;
@ISA = qw(NG::Block);

sub getBlockIndex {{}};

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    $self->{_pstructtemplate} = "admin-side/common/pagestructure.tmpl";
    
    $self->register_ajaxaction("","structPage");
    $self->register_ajaxaction("movenodedown","moveNodeDown");
    $self->register_ajaxaction("movenodeup","moveNodeUp");
    $self->register_ajaxaction("addsubnodeform","showAddForm");
    $self->register_ajaxaction("editnodeform","updateNodeAction");
    $self->register_ajaxaction("updatenode","updateNodeAction");
    $self->register_ajaxaction("deletenode","deleteNodeAction");
    $self->register_ajaxaction("enablepage","enablePage");
    $self->register_ajaxaction("disablepage","disablePage");
    $self->register_ajaxaction("switchsubsite","switchSubsite");
    
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
#return $cms->error($self->SUPER::getModuleObj()->getAdminBaseURL());
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
	my $self = shift;
	my $pageObj = shift;
	
	my $cms = $self->cms();
	my $dbh = $cms->db()->dbh();
	
	my $linkedPages = {};
	if ($cms->confParam("CMS.hasSubsites")) {
		my $pageLinkId = $pageObj->getPageLinkId();
		return $self->error("Обнаружено недопустимое значение link_id страницы") unless $pageLinkId;
		
		## Загружаем список подсайтов, на которых есть связанные страницы
		my $sql = "select
				ng_subsites.id as subsite_id,
				ng_subsites.name as subsite_name,
				ng_lang.id as lang_id,
				ng_lang.name as lang_name,
				ng_lang.img as lang_img,
				ng_sitestruct.id as node_id,
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
		$linkedPages = $sth->fetchall_hashref(['subsite_id']) or return $self->error($DBI::errstr);
		$sth->finish();
		return $self->error("_getLinkedPages(): Нарушение структуры данных в БД (несовпадают link_id,lang_id), страница - родитель не найдена") unless scalar keys %{$linkedPages};
	}
	else {
        my $lp = {};
        my $pRow = $pageObj->getPageRow();
        $lp->{subsite_id} = $pRow->{subsite_id};
        $lp->{lang_id} = $pRow->{lang_id};
        $lp->{node_id} = $pRow->{id};
        $lp->{node_disabled} = $pRow->{disabled};
        $lp->{node_url} = $pRow->{url};
        $lp->{node_name} = $pRow->{name};
		$linkedPages->{$pageObj->getSubsiteId()}= $lp;
	};
	return $linkedPages;
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

sub showAddForm {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;
	
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
		return $cms->error("getPageAddVariants(): some error");
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
			NAME=>"Варианты добавления страниц",
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
        
        $variantControl->{CODE} = $variant->{CODE};
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
            || $variantControl->{CODE} ne $variant->{CODE}
		   ) {
			return $cms->error("processNewSubpages(): method corrupts page parameters");
		};
        
		#Проверяем наличие обязательных свойств страниц.
		return $cms->error("Отсутствует код шаблона или название модуля для новой страницы варианта '".$variant->{NAME}."' (subsite_id=$subsiteId)") unless ($page->{PAGEROW}->{template} || $page->{PAGEROW}->{module_id});
	};
    
    #$variant->{ID} = $app->getVariantId(MODULE=>(ref $npageObj), CODE=> $variant->{CODE}); 
    
	my $hasSelectedPPage = 0; ## Как будет раздел по английски ? # Section, part
	my $hasPPageErrors = 0;
	
	if ($doitAction) {
		foreach my $subsiteId (keys %{$newSubpages}) {
			my $page = $newSubpages->{$subsiteId};
			$page->{CHECKED} = 0;

			my $enabled = $q->param("doit_".$subsiteId) || 0;
			$enabled = 0 if ($enabled != 1);
			$enabled = 0 if $page->{READONLY};
			$enabled = 0 unless $page->{ACTIVE};
			if ($page->{ERRORMSG}) {
				$hasPPageErrors = 1;
				$enabled = 0;
			};
			
			#return $self->error("$enabled $url ".$page->{PARENTROW}->{url}.$url);
			
			if ($enabled == 1) {
				$hasSelectedPPage = 1;
				$page->{CHECKED} = 1;

				if ($url ne "") {
					#проверка конфликтов суффиксов в пределах одного подсайта.
					$page->{PAGEROW}->{url} = $page->{PARENTROW}->{url}.$url;
					my $checkSth = $dbh->prepare("select id,name from ng_sitestruct where url = ? and subsite_id = ?") or return $self->error($DBI::errstr);
					$checkSth->execute($page->{PAGEROW}->{url},$subsiteId) or return $self->error($DBI::errstr);
					my $foundPage = $checkSth->fetchrow_hashref();
					if ($foundPage) {
						$page->{ERRORMSG} ||= "Укажите другое значение URL suffix. Указанный suffix ($url) уже есть в этом разделе - страница '".$foundPage->{name}."'.";
						$hasPPageErrors = 1;
					};
					$checkSth->finish();
					
				};
			};
		};
	};
	
	if (scalar keys %{$newSubpages} == 1) {
		my ($subsiteId) = keys %{$newSubpages};
		my $page = $newSubpages->{$subsiteId};
		$linkedPartsField->{SUBSITE_ID} = $subsiteId;
		$form->pusherror("url",$page->{ERRORMSG}) if !is_empty($page->{ERRORMSG});
	}
	else {
		my @lp = ();
		foreach my $subsiteId (keys %{$newSubpages}) {
			my $page = $newSubpages->{$subsiteId};
			push @lp,$page;
		};
		
		$linkedPartsField->{LINKED_PAGES} = \@lp;
		#Проверяем, не сменил ли хитрый пользователь шаблон, забыв нажать волшебную кнопку ?
		if (($prevVariantId ne $variantId) && ($selVariantAction != 1)) {
			$variantSelectField->setError('После смены шаблона нажмите "Выбрать"!');
		}
		$linkedPartsField->setError("Не выбран ни один раздел для добавления.") unless ($hasSelectedPPage || $doitAction == 0);
		$variantSelectField->{HIDE_BUTTON} = 0;
	};

	#Если $selTmplAction - выводим вторую часть формы
	#Если $doitAction -
	#  ---- если есть ошибки - выводим ошибки ( Аякс - аяксом, не аякс - формой)
	#  ---- если нет ошибок - добавляем страницы

	my $hasErrors = ($form->has_err_msgs() || $hasPPageErrors);

	## Если ошибок нет - добавляем страницы и делаем редирект
	if (!$hasErrors && $doitAction) {
		my $linkId = $self->db()->get_id('ng_sitestruct.link_id');
		return $self->error($self->db()->errstr()) unless $linkId;
		$hasErrors = 0;
		my $error = "";
		my @addedPageObjs;
        
		foreach my $subsiteId (keys %{$newSubpages}) {
            my $ppage = $newSubpages->{$subsiteId};
			next unless $ppage->{CHECKED};


            foreach my $f (@{$form->fields()}) {
                next if ($f->{FIELD} eq "id");
                next if ($f->{FIELD} eq "url");
                $ppage->{PAGEROW}->{$f->{FIELD}} = $form->getParam($f->{FIELD});
            };
			
			$ppage->{PAGEROW}->{link_id} = $linkId;
			$ppage->{PAGEROW}->{subptmplgid} ||= "0";
			$ppage->{PAGEROW}->{catch} ||= "0";
			
			my $tree = $self->_create_tree_object();
			$tree->loadNode($ppage->{PAGEROW}->{parent_id});
            
            $ppage->{PARENTROW} = $tree->getNodeValue();
			
			#Ищем, ноду, после которой будет добавлена наша новая страница. Посылаем её параметры в event для синхронизации деревьев
			my $lastChild = undef;
			my $lastChildOrd = $tree->getLastChildOrder();
			if ($lastChildOrd) {
				$lastChild = $self->_create_tree_object();
				$lastChild = $lastChild->loadNode(tree_order => $lastChildOrd );
			};
			
			if ($lastChild) {
				$ppage->{PREV_SIBLING_ID} = $lastChild->{_id};
			};
	
			#TODO: проверять ошибки вставки новой строки. //NG::Nodes не умеет возвращать ошибки.
			$ppage->{PAGEROW}->{id} = $tree->DBaddChild($ppage->{PAGEROW});
			
			my $npageObj = $cms->getPageObjById($ppage->{PAGEROW}->{id});
			unless ($npageObj) {
				$hasErrors = 1;
				$error = $cms->getError();
				last;
			};
            $ppage->{PAGEROW} = $npageObj->getPageRow();
            
			$ppage->{PAGEOBJ} = $npageObj;
			push @addedPageObjs,$npageObj;
			
			my $res = $npageObj->initialisePage();
			unless ($res) {
				$hasErrors = 1;
				$error = $npageObj->getError();
				last;
			};
		};
		
		if ($hasErrors != 0) {
			while (scalar (@addedPageObjs)) {
				my $npageObj = shift @addedPageObjs;
				$npageObj->destroyPage(\@addedPageObjs);
				$self->_deleteNode($npageObj->getPageId());
			};
			return $self->error($error);
		};
		
		
		my @newNodes = ();
		foreach my $subsiteId (keys %{$newSubpages}) {
            my $ppage = $newSubpages->{$subsiteId};
			next unless $ppage->{CHECKED};
			
			$self->_makeEvent('addnode',{
				PAGEOBJ=>$ppage->{PAGEOBJ},
				VARIANT=>$variant,
				PREV_SIBLING_ID=>$ppage->{PREV_SIBLING_ID}
			});
			
            $self->_makeLogEvent({page_id=>$ppage->{PAGEROW}->{id},operation=>"Добавление страницы ",operation_param=>sprintf("%s (%s) id %s",$ppage->{PAGEROW}->{name},$ppage->{PAGEROW}->{url},$ppage->{PAGEROW}->{id})});
			push @newNodes, {
				PAGEOBJ=>$ppage->{PAGEOBJ},
				PREV_SIBLING_ID=>$ppage->{PREV_SIBLING_ID},
			};
		};

		$self->_makeEvent('addlinkednodes',{
			VARIANT => $variant,
			NODES   => \@newNodes,
		});
		
		#TODO: делать перенаправление на страницу "текущего" подсайта
		#my $newPage = $newSubpages->{$self->getSubsiteId()};
		#if ($newPage->{CHECKED}) {
		#	return $self->fullredirect("/admin-side/pages/".$newPage->{PAGEROW}->{id}."/");
		#};
		return $self->fullredirect("/admin-side/pages/".$addedPageObjs[0]->getPageId()."/",$is_ajax);
	};
	
	## Если есть ошибки и Аякс - выводим 
	if ($is_ajax && ($selVariantAction != 1) && $hasErrors) {
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
	die("Not Reachable");
};

sub structPage {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;

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
        
        $tmpl->param(
            PAGE_LINKEDPAGES => \@linkedpages,
            HAS_LINKEDPAGES => $hasLinkedPages,
            PAGEROW=>$pageRow,
            CAN_ADD_SUBNODE => $canAddSubnode,
        );
        
        #TODO: надо ли проверять права на действие активация ?
        if ($pageRow->{disabled}==0) {
            #Страница включена
            my $canDeactivate = 1;
            $canDeactivate = $pageObj->canDeactivate() if $pageObj->can("canDeactivate");
            $tmpl->param(ACTIVE => 1);
            $tmpl->param(NO_DEACTIVE=> "Не отключаема") unless $canDeactivate eq "1";
            $tmpl->param(NO_DEACTIVE=> $canDeactivate) if $canDeactivate && $canDeactivate ne "1";
        }
        elsif ($pageRow->{disabled}==$pageRow->{id}) {
            #Страница выключена сама
            my $canActivate = 1;
            $canActivate = $pageObj->canActivate() if $pageObj->can("canActivate");
            $tmpl->param(ACTIVE => 0);
            $tmpl->param(NO_ACTIVE=> "Не все блоки заполнены") unless $canActivate eq "1";
            $tmpl->param(NO_ACTIVE=> $canActivate) if $canActivate && $canActivate ne "1";
        }
        else {
            #Страница выключена сверху
            $tmpl->param(ACTIVE => 0);
            $tmpl->param(DEACTIVE_ID => $pageRow->{disabled});
        }
    };
	
    my $rootId = $pageId;
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
        PAGEURL  => $self->{_pageURL},
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
            $self->_makeEvent("swapNode",{NODE=> $tree->getNodeValue(), ACTION=> "before", PARTNER=> $partner->getNodeValue() });
            $self->_makeLogEvent({page_id=>$pageId,operation=>"Перемещение страницы ",operation_param=>sprintf("%s(%s) id %s вверх ",$value->{name},$value->{url},$pageId)});
        };
    }
    elsif ($dir eq "down") {
        my $nextso = $tree->getNextSiblingOrder();
        if ($nextso) {
            $partner->loadNode(tree_order=>$nextso);
            $tree->DBmoveNode(after => $partner);
            $self->_makeEvent("swapNode",{NODE=> $tree->getNodeValue(), ACTION=> "after", PARTNER=> $partner->getNodeValue() });
            $self->_makeLogEvent({page_id=>$pageId,operation=>"Перемещение страницы",operation_param=>sprintf("%s(%s) id %s вниз ",$value->{name},$value->{url},$pageId)});
        };
    };
    my $pageObj = $cms->getPageObjByRow($value) or return $cms->error();
    $self->_makeEvent('movenode',{DIR=>$dir, PAGEOBJ=>$pageObj});
    
    return $self->_redirect($parent_pageId,0);
};

sub moveNodeUp {
    my $self = shift;
    return $self->_moveNode("up",@_);
};

sub moveNodeDown {
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

sub updateNodeAction {
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
    if ($action eq "editnodeform") {
        my $oldUrl = $oldValue->{url};
        $oldUrl =~ /([^\/]*)\/$/;
        $oldUrl = ($oldUrl ne "/"?$1:"/"); #($1 || "/";)
        
        my $fields = $form->fields();
        foreach my $f (@{$fields}) {
            return $cms->error("Ключ ".$f->{FIELD}." не найден") unless exists $oldValue->{$f->{FIELD}};
            $form->param($f->{FIELD},$oldValue->{$f->{FIELD}});
        };
        $form->param("url",$oldUrl);
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
        
        $form->pusherror("url","Значение должно содержать только латинские символы и цифры") if($newUrlSuffix =~/[^a-zA-Z0-9\_\-]/);
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
    
    my $siteRootPageId = undef;
    if ($cms->confParam("CMS.hasSubsites")) {
        my $row = $dbh->selectrow_hashref("select root_node_id from ng_subsites where id = ?",undef,$pageObj->getSubsiteId()) or return $cms->error($DBI::errstr);
        defined $row->{root_node_id} or return $cms->error("Не могу найти значение root_node_id для подсайта");
        $siteRootPageId = $row->{root_node_id};
    };
    
    my $canChangeURL = 1;
    $canChangeURL = 0 if (defined $siteRootPageId && $siteRootPageId == $pageId) || ($oldValue->{url} eq "/");
    
    my $newPageUrl = $oldValue->{url};
    $newPageUrl =~ s@([^\/]*)\/$@$newUrlSuffix\/@ if ($canChangeURL);
    $form->param("url",$newPageUrl);
    $form->updateData() or return $self->error("Не удалось обновить данные: ".$form->getError());
    
    my $newValue = undef;
    
    if ($canChangeURL && ($oldValue->{url} ne $newPageUrl)) {
        my $tree = $self->_create_tree_object();
        $tree->loadtree($pageId);
        $newValue = $tree->getChild(0)->getNodeValue();

        $self->_makeEvent('updatenodeurl',{ID=>$pageId,OLDURL=>$oldValue->{url},NEWURL=>$newPageUrl});
        
        my $sth = $dbh->prepare("update ".$tree->{_dbtable}." set url=? where id=?") or die $DBI::errstr;
        my $res = $tree->traverseWithCheck(
            sub {
                my $_tree = shift;
                my $value = $_tree->getNodeValue();
                my $parent = $_tree->getParent();
                if ($_tree->{_id} != $pageId) {
                    my $parent_value = $parent->getNodeValue();
                    my $parent_url = $parent_value->{url};
                    my $oldUrl=$value->{'url'};
                    $value->{url} =~ s@.*\/([^\/]+\/)$@$parent_url$1@;
                    $sth->execute($value->{url},$_tree->{_id}) or return $cms->error($DBI::errstr." БД находится в поврежденном состоянии") + 1;
                    $self->_makeEvent('updatenodeurl',{ID=>$_tree->{'_id'},OLDURL=>$oldUrl,NEWURL=>$value->{'url'}});
                };
                return 0;
            }
        );
        return $cms->error() if $res;
        $sth->finish();
    }
    else {
        my $newNode = $self->_create_tree_object();
        $newNode->loadNode($pageId) or return $self->error("No node found"); 
        $newValue = $newNode->getNodeValue();
    };
    #TODO: передается старый $pageObj
    $self->_makeEvent('updatenode',{PAGEOBJ=>$pageObj, OLDVALUE=>$oldValue, NEWVALUE=>$newValue});
    $self->_makeLogEvent({page_id=>$oldValue->{id},operation=>"Редактирование страницы",operation_param=>sprintf("%s (%s) id %s",$oldValue->{name},$oldValue->{url},$oldValue->{id})});
    return $self->_redirect($pageId,$is_ajax);
}; 

sub enablePage {
    my $self = shift;
    my $action = shift;
    my $is_ajax = shift;

    my $cms = $self->cms();
	my $dbh = $cms->dbh();
	my $q = $cms->q();

    my $pageId = $q->param('id');
    $pageId = $self->{_pageId} unless defined $pageId;
    is_valid_id($pageId) or return $cms->error("Некорректный код страницы");
	
	NG::Nodes->initdbparams(
        db     => $self->db(),
        table  => "ng_sitestruct",
        fields => $cms->getPageFields(),
    );
	
	while (1) {
		my $node = NG::Nodes->loadNode($pageId) or last;
		my $v = $node->getNodeValue();
		my $pNode = NG::Nodes->loadNode($v->{parent_id});
		
		return $cms->error("Parent node not found") unless $pNode;
		last if $pNode->getNodeValue()->{disabled};
		
		my $where = "";
		my @params = ();
		
		my $bOrder = $node->getSubtreeBorderOrder();
		if ($bOrder) {
			$where .= " tree_order>=? and tree_order<?";
			push @params, $node->getNodeValue()->{tree_order};;
			push @params, $bOrder;
		} else {
			$where .= " tree_order>=?";
			push @params, $node->getNodeValue()->{tree_order};
		};
		
		$dbh->do("UPDATE ng_sitestruct set disabled = 0 where $where and disabled = ?", undef, @params, $pageId) or return $cms->error($DBI::errstr);
		
		my $pageFields = $cms->getPageFields();
		my $sth = $dbh->prepare("select $pageFields from ng_sitestruct where $where and disabled = 0 order by tree_order") or return $cms->error("disablePage(): Error in pageRow query: ".$DBI::errstr);
		$sth->execute(@params) or return $cms->error("getPageRowById(): Error in pageRow query: ".$DBI::errstr);
		while (my $pRow = $sth->fetchrow_hashref()) {
			my $pageObj = $cms->getPageObjByRow($pRow,{}) or return $cms->error();
			$self->_makeEvent('enablenode',{PAGEOBJ=>$pageObj});
			$self->_makeLogEvent({page_id=>$pRow->{id},operation=>"Включение страницы",operation_param=>sprintf("%s (%s) id %s",$pRow->{name},$pRow->{url},$pRow->{id})});
		}
		$sth->finish();    
		
		last;
	};
    
    return $self->_redirect($pageId,0);
};

sub disablePage {
    my $self = shift;
    my $action = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
	my $dbh = $cms->dbh();
	my $q = $cms->q();

    my $pageId = $q->param('id');
    $pageId = $self->{_pageId} unless defined $pageId;
    is_valid_id($pageId) or return $cms->error("Некорректный код страницы");

    my $tree = NG::Nodes->new();
	$tree->initdbparams(
        db     => $self->db(),
        table  => "ng_sitestruct",
        fields => $cms->getPageFields(),
    );
    $tree->loadNode($pageId);
	
	my $where = "";
	my @params = ();
	
	my $bOrder = $tree->getSubtreeBorderOrder();
	if ($bOrder) {
		$where .= " tree_order>=? and tree_order<?";
		push @params, $tree->getNodeValue()->{tree_order};;
		push @params, $bOrder;
	} else {
		$where .= " tree_order>=?";
		push @params, $tree->getNodeValue()->{tree_order};
	};
	
	$dbh->do("UPDATE ng_sitestruct set disabled = ? where $where and disabled = 0", undef, $pageId, @params) or return $cms->error($DBI::errstr);
	
	my $pageFields = $cms->getPageFields();
	my $sth = $dbh->prepare("select $pageFields from ng_sitestruct where $where and disabled = ? order by tree_order desc") or return $cms->error("disablePage(): Error in pageRow query: ".$DBI::errstr);
	$sth->execute(@params,$pageId) or return $cms->error("getPageRowById(): Error in pageRow query: ".$DBI::errstr);
	while (my $pRow = $sth->fetchrow_hashref()) {
		my $pageObj = $cms->getPageObjByRow($pRow,{}) or return $cms->error();
		$self->_makeEvent('disablenode',{PAGEOBJ=>$pageObj});
		$self->_makeLogEvent({page_id=>$pRow->{id},operation=>"Выключение страницы",operation_param=>sprintf("%s (%s) id %s",$pRow->{name},$pRow->{url},$pRow->{id})});
	}
	$sth->finish();
	
    return $self->_redirect($pageId,0);
};

sub deleteNodeAction {
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

    my $pages2Kill = {};
    my @lp;
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
                $pages2Kill->{$page->{node_id}} = 1;
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
		#Формируем хэш объектов связанных страниц
		my $lpageObjs = {};
		#Хэш контроля за линковкой по языку
		my $linkLang = {};
		foreach my $p (@lp) {
			my $lpageObj = $cms->getPageObjById($p->{node_id}) or return $cms->error();
			
			$lpageObjs->{$p->{node_id}} = $lpageObj;
			$pages2Kill->{$p->{node_id}} = $lpageObj if exists $pages2Kill->{$p->{node_id}};
			
			$linkLang->{$p->{lang_id}}->{$p->{node_id}} = 1;
		};
	
		#Удаляем страницы по одной...
		foreach my $dpageId (keys %{$pages2Kill}) {
			my $dpageObj = $pages2Kill->{$dpageId};
			
			$dbh->do("update ng_sitestruct set disabled=? where id=?",undef,$dpageId,$dpageId) or return $self->error($DBI::errstr);
			
			delete $lpageObjs->{$dpageId};
			delete $linkLang->{$dpageObj->getPageLangId()}->{$dpageId};
			
			my @lpages =();
			foreach my $lnodeId (keys %{$lpageObjs}){
				push @lpages, $lpageObjs->{$lnodeId};
			};
			
			my $res = $dpageObj->destroyPage(\@lpages);
			unless ($res) {
				my $e = $dpageObj->getError();
				$e = "Текст ошибки: $e" if $e;
				$e ||= "Вызов не вернул текст ошибки.";
				return $self->error("При удалении страницы $dpageId возникла ошибка вызова destroyPage(). Возможно, не все удаляемые страницы были удалены. $e");
			};
			$self->_deleteNode($dpageId);
			$db->deleteFTSIndex({PAGEID=>$dpageId});
            $self->_makeEvent('deletenode',{PAGEOBJ=>$dpageObj,PAGE_ID=>$dpageId});
            my $page_row = $dpageObj->getPageRow();
            $self->_makeLogEvent({page_id=>$page_row->{id},operation=>"Удаление страницы",operation_param=>sprintf("%s (%s) id %s",$page_row->{name},$page_row->{url},$page_row->{id})});
		};

		#Если не осталось страниц в линке, делаем финальную подчистку
		unless (scalar keys %{$lpageObjs}) {
			$db->deleteFTSIndex({LINKID=>$linkId});
			$self->_makeEvent('deletelink',{LINKID=>$linkId});
		}
		else {
			#Если не осталось страниц в некотором языке линка, делаем подчистку
			foreach my $langId (keys %{$linkLang}) {
				next if scalar(keys %{$linkLang->{$langId}});
				$db->deleteFTSIndex({LINKID=>$linkId,LANGID=>$langId});
				$self->_makeEvent('deletelink',{LINKID=>$linkId,LANGID=>$langId});
			};
		};
        return $self->_redirect($pageObj->getParentPageId(),$is_ajax);
	};
    
	my $message = "";
	if (scalar @lp == 1) {
		$message = $lp[0]->{MESSAGE};
		@lp = ();
	}
   
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

sub switchSubsite {
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

sub _deleteNode {
	my $self = shift;
	my $nodeId = shift;
	
	my $dbh = $self->db()->dbh();
	$dbh->do("delete from ng_sitestruct where id = ?",undef,$nodeId) or return $self->error($DBI::errstr);
};

sub _makeEvent {
    my $self = shift;
    my $ename = shift;
    my $eopts = shift;
    
    my $event = NG::SiteStruct::Event->new($self,$ename,$eopts);
    $self->cms()->processEvent($event);
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
            print STDERR "Invalid ACTION ".$opts->{ACTION}. " in NG::Module::Menu::Event";
            return;
        };
        
        my $node = $self->_create_tree_object();
        $node->loadNode($opts->{NODE}->{node_id});

        my $pnode = $self->_create_tree_object();
        $pnode->loadNode($opts->{PARTNER}->{node_id});

        unless ($node && $pnode) {
            print STDERR "No node found with ID=".$opts->{NODE}->{node_id};
            return;
        };
        unless ($pnode) {
            print STDERR "No pnode found with ID=".$opts->{PARTNER}->{node_id};
            return;
        };
        if ($node->{_parent_id} == $pnode->{_parent_id}) {
            $node->DBmoveNode($opts->{ACTION} => $pnode) ;
            $self->_makeEvent("swapNode",{NODE=> $node->getNodeValue(), ACTION=> $opts->{ACTION}, PARTNER=> $pnode->getNodeValue() });
        };
    };
};

return 1;
END{};
