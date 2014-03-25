package NG::Adminside;
use strict;

use NG::Application;

use vars qw(@ISA);
@ISA = qw(NG::Application);

sub init {
    my $self = shift;
    my %param = @_;
    $self->SUPER::init(@_);
    
    $self->{_rightSelector} = [];
	
    $self->{_linkBlocksPrivileges} = {};
   
    $self->{_siteStructObj} = undef;
    $self->{_sitePAccessObj} = undef;
    $self->{_siteMAccessObj} = undef;
    $self->{_authObj} = undef;
    
    $self->{_regions} = {};    # LEFT RIGHT  HEAD1 HEAD2 [HEAD3]
   
    $self;
};


sub _makeLogEvent {
    my $self = shift;
    my $module = shift;
    my $opts = shift;
    
    my $event = $self->getObject("NG::Event::Log",$module,"LOG",$opts);
    $self->processEvent($event);
};


=head TODO: Обновление календаря AJAX-ом не работает.
sub getCalendarAjax {
    my $app = shift;
    my $template = $app->gettemplate("admin-side/common/calendar.tmpl");
    $app->_printCalendar($template);
    my $calendar_output = $template->output();
    use NHtml;
    $calendar_output = escape_js $calendar_output;
    return qq(<script type="text/javascript">document.getElementById('calendar_div').innerHTML = '$calendar_output';</script>);
};
=cut

sub getAdminId {
    my $self = shift;
    die "getAdminId(): variable '_authObj' not initialised" unless exists $self->{_authObj};
    return $self->{_authObj}->getAdminId();
};

sub getAdminGId {
    my $self = shift;
    return $self->{_authObj}->{_admin}->{group_id};
};

sub _getAdmin {
    #Используется в NG::Admins
    my $self = shift;
    return $self->{_authObj}->{_admin};
};

# Методы трансляции проверок привилегий в соответствующий модуль

sub hasPageModulePrivilege { #PAGE_ID MODULE_ID PRIVILEGE SUBSITE_ID
    my $cms = shift;
   
    return 1 unless ($cms->{_sitePAccessObj});
   
    my %att = (@_); 
    $att{ADMIN_ID} = $cms->getAdminId();
    $att{GROUP_ID} = $cms->getAdminGId();
    return $cms->{_sitePAccessObj}->hasPageModulePrivilege(%att);
};

sub hasLinkModulePrivilege { #LINK_ID MODULE_ID PRIVILEGE SUBSITE_ID
    my $cms = shift;
   
    return 1 unless ($cms->{_sitePAccessObj});
   
    my %att = (@_); 
    $att{ADMIN_ID} = $cms->getAdminId();
    $att{GROUP_ID} = $cms->getAdminGId();
    return $cms->{_sitePAccessObj}->hasLinkModulePrivilege(%att);
};

sub hasModulePrivilege { #MODULE_ID PRIVILEGE
    my $cms = shift;
    
    return 1 unless ($cms->{_siteMAccessObj});
    
    my %att = (@_);
    $att{ADMIN_ID} = $cms->getAdminId();
    $att{GROUP_ID} = $cms->getAdminGId();
    return $cms->{_siteMAccessObj}->hasModulePrivilege(%att);
};

sub hasPageStructAccess {
    my $cms = shift;
    my $pageId = shift or die "hasPageStructAccess(): no pageId";
    my $subsiteId = shift;
    die "hasPageStructAccess(): no subsiteId" unless defined $subsiteId;
    return 0 unless $cms->{_siteStructObj};
    
    return $cms->hasPageModulePrivilege(PRIVILEGE=>'PROPERTIES',MODULE_ID=>$cms->{_siteStructObj}->moduleParam('id'),PAGE_ID=>$pageId,SUBSITE_ID=>$subsiteId);
};

sub hasPageAccess {
    my $cms = shift;
    my $pageId = shift or die "hasPageAccess(): no pageId";
    my $subsiteId = shift;
    die "hasPageStructAccess(): no subsiteId in $pageId" unless defined $subsiteId;
    return 1 unless $cms->{_sitePAccessObj};
    return $cms->hasPageModulePrivilege(PRIVILEGE=>'ACCESS',MODULE_ID=>$cms->{_sitePAccessObj}->moduleParam('id'),PAGE_ID=>$pageId,SUBSITE_ID=>$subsiteId);
};

##
## /Код проверки привилегий
##
=head _fillStructureTree
sub _fillStructureTree {
	my $self     = shift;
	my $template = shift;
	my $pageId   = shift;
	
	my $tree = NG::Nodes->new();
	$tree->initdbparams(
		db=>$self->db(),
		table=>"ng_sitestruct",
		fields=>"name,active,subsite_id,link_id,subsite_id",
	);

    my $dbh = $self->db()->dbh();

    my $subsites = undef;    

    my $subsiteRootNodeId = 0;
    my $selectedSubsiteId = undef;
    
    my $pageRow = undef;
    if ($pageId) {
        #загружаем свойства страницы, с целью проверки привилегий.
        $pageRow = $dbh->selectrow_hashref("select id, subsite_id from ng_sitestruct where id = ?",undef,$pageId) or return $self->setError("Страница не найдена или некорректный запрос:".$DBI::errstr);
    }
    
    $selectedSubsiteId = 0 if (!defined $selectedSubsiteId);
    
    my $adminRow = $self->_getAdmin();

    my $hasGlobalSubsiteAccess = 0;
    my $pagePrivs = {};
    my $linkPrivs = {};
    
    my $sel_sth = $dbh->prepare_cached("select privilege from ng_subsite_privs WHERE admin_id = ? and subsite_id=? and privilege <> 'ACCESS' ") or die $DBI::errstr;
    $sel_sth->execute($adminRow->{id},$selectedSubsiteId) or die $DBI::errstr;
    my $subsitePrivs = $sel_sth->fetchall_hashref(['privilege']);
    $sel_sth->finish();
    $hasGlobalSubsiteAccess = 1 if scalar keys %{$subsitePrivs};
    
    unless ($hasGlobalSubsiteAccess) {
        $sel_sth = $dbh->prepare_cached("select page_id,block_id,privilege from ng_page_privs WHERE page_id <> 0 and admin_id = ? and subsite_id = ?") or die $DBI::errstr;
        $sel_sth->execute($adminRow->{id},$selectedSubsiteId) or die $DBI::errstr;
        $pagePrivs = $sel_sth->fetchall_hashref(['page_id','block_id','privilege']);
        $sel_sth->finish();

        $sel_sth = $dbh->prepare_cached("select link_id,block_id,privilege from ng_page_privs WHERE link_id <> 0 and admin_id = ?") or die $DBI::errstr;
        $sel_sth->execute($adminRow->{id}) or die $DBI::errstr;
        $linkPrivs = $sel_sth->fetchall_hashref(['link_id','block_id','privilege']);
        $sel_sth->finish();
    }
    
    $tree->loadPartOfTree($subsiteRootNodeId,$pageId);
	$tree->traverse(
		sub {
			my $_tree = shift;
			my $value = $_tree->getNodeValue();

			if ($pageId == $value->{id}) {
				$value->{selected}= 1;
			}
			
			# блок для выставление подсветки доступных
			$value->{HASACCESS} = ($hasGlobalSubsiteAccess || exists $pagePrivs->{$value->{id}} || exists $linkPrivs->{$value->{link_id}})?1:0;
			if ($value->{HASACCESS} == 0) {
				my $sth = undef;
				my $next_tree_order = undef;
				$sth = $dbh->prepare("select min(tree_order) from ng_sitestruct where tree_order>? and level<=?") or die $DBI::errstr;
				$sth->execute($value->{tree_order},$value->{level})  or die $DBI::errstr;
				($next_tree_order) = $sth->fetchrow();
				$sth->finish();
				if ($next_tree_order) {
					 $sth = $dbh->prepare("select id,link_id,subsite_id from ng_sitestruct where tree_order>? and tree_order <?") or die $DBI::errstr;
					 $sth->execute($value->{tree_order},$next_tree_order) or die $DBI::errstr;
					 
				} else {
					 $sth = $dbh->prepare("select id,link_id,subsite_id from ng_sitestruct where tree_order>?") or die $DBI::errstr;
					 $sth->execute($value->{tree_order}) or die $DBI::errstr;
				};
				while (my $page = $sth->fetchrow_hashref()) {
					$value->{HASACCESS} = (exists $pagePrivs->{$page->{id}} || exists $linkPrivs->{$page->{link_id}})?1:0;
					last if ($value->{HASACCESS});
				};
				$sth->finish();
			};
			
			$value->{URL} = "/admin-side/pages/".$value->{id}."/";
            $value->{INACTIVE} = 1 unless $value->{active};
		}
	);
    
	#$self->set_header_nocache();
	#print Dumper($tree);
#    print "<PRE>";
#    $tree->traverse(
#        sub {
#            my ($_tree) = @_;
#            print "\t" x $_tree->getDepth();
#            $_tree->printNode();
#        }
#    );
#    print "</PRE>";
	$tree->printToDivTemplate($template,'STRUCTURE',$pageId);
    return 1;
}
=cut

sub _getModulesTreeHTML {
	my $app = shift;
    
    my $param = shift;
	
	my $q = $app->q();
    my $qId = $param->{NODE_ID};
    
    my $adminId   = $app->getAdminId();
    my $groupId   = $app->getAdminGId();
    
    
    $app->{_sitePAccessObj}->loadAdminPrivileges(ADMIN_ID=>$adminId, GROUP_ID=>$groupId) if ($app->{_sitePAccessObj});
    $app->{_siteMAccessObj}->loadAdminPrivileges(ADMIN_ID=>$adminId, GROUP_ID=>$groupId) if ($app->{_siteMAccessObj});
    
	NG::Nodes->initdbparams(
		db	   => $app->db(),
		table  => "ng_admin_menu",  
		fields => "main.name,main.node_id,main.url,main.module_id,main.collapse, ngs.disabled,ngs.subsite_id",
        join   => "left join ng_sitestruct ngs on main.node_id = ngs.id",
	); 
    
    my $tree = undef;
    eval {
        my $menuRootId = undef;
        my $openLevels = 3;
        
        $tree = NG::Nodes->loadtree($menuRootId,$openLevels + 1);  #or last;   #Загружаем нужное число уровней + 1 для определения наличия childs
        $tree = $tree->getChild(0);
        $tree->loadBranchToNode($qId, 3) if $qId;           #or last;    #Загружаем три уровня: саму ноду, её детей и их детей для определения их наличия
        
        my $sNode = undef;
        $sNode = $tree->getNodeById($qId) if $qId;
        
        my @allNodes = ();
        $tree->traverse(
            sub {
                my $_tree = shift;
                my $value = $_tree->getNodeValue();
                
                $value->{_HASACCESS} = 0;
                $value->{HASACCESS} = 1;
                if ($value->{node_id}) {
                    my $u = $value->{url};
                    $u ||= $value->{node_id};
                    $value->{url} = "/admin-side/pages/$u/";
                    $value->{_HASACCESS} = 1 if $app->hasPageAccess($value->{node_id},$value->{subsite_id});
                    $value->{HASACCESS} = 0 if $value->{disabled};
                }
                elsif ($value->{module_id}) {
                    my $u = $value->{url};
                    $u ||= $value->{module_id};
                    $value->{url} = "/admin-side/modules/$u/";
                    $value->{_HASACCESS} = 1 if ($app->hasModulePrivilege(MODULE_ID=>$value->{module_id},PRIVILEGE=>'ACCESS'));
                }
                else {
                    $value->{url} = '';
                };
                push @allNodes, $_tree;
            }
        );

        $sNode = undef if ($sNode && $sNode->getNodeValue()->{_HASACCESS} != 1);
        
        my $pHas = {}; #Хэш доступных чайлдов ноды
        foreach my $_node (reverse @allNodes) {
            my $v = $_node->getNodeValue();
            my $p = $_node->getParent();
            
            #print STDERR "NODE ".$_node->{_id}." PARENT ".$p->{_id}." HA ".$v->{HASACCESS}." U ".$v->{url};
            if ($v->{_HASACCESS} && $v->{url}) {
                #Нода доступна, занесем в хэш. Движемся снизу вверх, поэтому перезатираем имеющееся значение
                $pHas->{$p} = $_node;
            }
            else {
                #Нода не доступна.
                if (exists $pHas->{$_node}) {
                    #print STDERR "UPDATE";
                    #Но у неё есть доступные чайлды
                    #$v->{HASACCESS} = 1;
                    $v->{url} = $pHas->{$_node}->getNodeValue()->{url};
                    delete $pHas->{$_node};
                    $pHas->{$p} = $_node;
                }
                else {
                    #Недоступна и чайлдов нет, удаляем
                    #print STDERR "REMOVE";
                    $_node->getParent()->removeChild($_node);
                }
            };
            delete $v->{_HASACCESS};
        };
        
        
        #3. Нода в ветке выбранной ноды, и уровень ноды > разрешенного количества _после выбранной_
        $tree->collapseBranch({
            KEY=>"collapse",
            MAXLEVELS=>$openLevels,
            SELECTEDNODE=> $sNode,
        });
        #Удаляем третий уровень у выбранной ноды
        $sNode->collapseBranch({
            MAXLEVELS => 2,
        }) if $sNode;
    };
    return $@ if ($@);
	my $template = $app->gettemplate('admin-side/common/content_tree.tmpl') || return $app->getError();
	
	$tree->printToDivTemplate($template,'ADMINMENU',$qId);
	return $template->output();
};

sub _getRightBlockContentAsErrorMessage {
	my $app = shift;
	my $error = shift;
	$error ||= "_getRightBlockContentAsErrorMessage(): Вызов без указания текста сообщения.";
	$app->{_rightSelector} = [{HEADER=> "Ошибка",SELECTED=>1}] unless scalar(@{$app->{_rightSelector}});
	
	my $tmpl = $app->gettemplate("admin-side/common/error.tmpl")  || return "Не могу открыть шаблон отображения ошибки. Текст ошибки: $error";
	$tmpl->param(ERROR => $error );
	return $tmpl->output();
}

sub _checkSubsiteAccess {
    my $self = shift;
    my $subsiteId = shift;
    
    return 1 unless $self->confParam("CMS.hasSubsites");
    
    my $dbh = $self->db()->dbh();
    $dbh->selectrow_hashref("select 1 from ng_subsite_privs where subsite_id = ? and admin_id = ? and privilege='ACCESS'",undef,$subsiteId,$self->getAdminId()) or return 0;
    return 1;
};

sub __getRow {
    my $app = shift;
    my $where = shift;
    
    my $dbh = $app->db()->dbh();
    my $sql = "select id,node_id,module_id,url,subsite_id from ng_admin_menu where $where";
    my $sth = $dbh->prepare($sql) or die $DBI::errstr;
    $sth->execute(@_) or die $DBI::errstr;
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    if ($row) {
        die "ng_admin_menu contains filled module and node_id" if $row->{module_id} && $row->{node_id};
        $row->{url} ||= $row->{module_id} if ($row->{module_id});
        $row->{url} ||= $row->{node_id} if ($row->{node_id}); 
    };
    return $row;
};

sub _getRowByPageID {
    my $app = shift;
    return $app->__getRow("node_id=?",@_);
};

sub _getRowByPageURL {
    my $app = shift;
    return $app->__getRow("url=? and node_id is not null",@_);   
};

sub _getRowByModuleID {
    my $app = shift;
    return $app->__getRow("module_id=?",@_);
};

sub _getRowByModuleURL {
    my $app = shift;
    my $url = shift;
    
    while ($url) {
        my $row = $app->__getRow("url=? and node_id is null",$url);
        return $row if $row;
        $url =~ s/(\/?[^\/]+)$//;
    };
    return undef;
};

sub run {
	my $self = shift;
    my $cms = $self;
	my $q = $cms->q();
    my $url = $q->url(-absolute=>1);
    my $is_ajax  = $q->param('_ajax') || $q->url_param('_ajax') || 0;
    $cms->openConfig() || return $cms->showError();

	my $baseUrl = "/admin-side/";
	my $subUrl = "";
    if ($url =~ /$baseUrl([^\/\s]+)\//i) {
        $subUrl = $1."/";
    };

    my $ret ; 
    while (1)   {
        #Получаем объект авторизации.
        my $class = $cms->confParam("Admin-side.SiteAuthClass","NG::Adminside::Auth");
        $ret = $cms->error("Отсутствует параметр Admin-side.SiteAuthClass") unless $class;
        
        $self->{_authObj} = $cms->getObject($class);
        unless ($self->{_authObj}) {
            $ret = $cms->defError("SiteAuthClass:", "Ошибка создания объекта класса");
            last;
        };
        $ret = $self->{_authObj}->Authenticate($is_ajax);
        $ret ||= $cms->defError("Authenticate","Ошибка авторизации");
        last if $ret ne NG::Application::M_CONTINUE;
        $ret = $cms->_run($subUrl,$is_ajax);
        last;
    };
    return $cms->processResponse($ret);
};

sub _run {
    my $cms = shift;
    my $subUrl = shift;
    my $is_ajax = shift;
    
    {   #Загружаем модуль "Доступ к страницам"
        my $code = $cms->confParam("CMS.SitePAccessModule","");
        if ($code) {
            $cms->{_sitePAccessObj} = $cms->getModuleInstance($code) or return $cms->defError("SitePAccessModule:");
        };
    };
    {   #Загружаем модуль "Доступ к модулям"
        my $code = $cms->confParam("CMS.SiteMAccessModule","");
        if ($code) {
            $cms->{_siteMAccessObj} = $cms->getModuleInstance($code) or return $cms->defError("SiteMAccessModule:");
        };
    };
    {   #Загружаем модуль "Структура"
        my $code = $cms->confParam("CMS.SiteStructModule","");
        if ($code) {
            $cms->{_siteStructObj} = $cms->getModuleInstance($code) or return $cms->defError("SiteStructModule:");
        };
    };
    
    #TODO: fix
    my $baseUrl = "/admin-side/";

    my $q = $cms->q();
    my $url = $q->url(-absolute=>1);
    
	my $status = NG::Application::M_ERROR;

    my $pageId = undef;
    my $mId = undef;
    my $menuNodeId = undef;
    my $subsiteId = undef;
	
	if ($subUrl eq "pages/") {
        $baseUrl = $baseUrl.$subUrl;
        $subUrl = ($url=~ /^$baseUrl([^\/\s]+)\//) ? $1."/" : "";
        
        while (1) {
            unless ($subUrl) {
=comment
                #$status = $cms->output("TODO: исправить вывод страницы по умолчанию");
                $pageObj = $cms->getObject('NG::Module::MainAdm',{BASEURL=>$baseUrl});
                unless ($pageObj) {
                    $error = $cms->getError();
                    last;
                };
                $status = $pageObj->moduleAction($is_ajax);
                last;
=cut
                return $cms->redirect("/admin-side/");
            };
            my $row = undef;
            
            if ($subUrl =~ /^(\d+)\//) {
                $row = $cms->_getRowByPageID($1);
            }
            else {
                my $t = $subUrl;
                $t =~ s/\/$//;
                $row = $cms->_getRowByPageURL($t);
            };
            
            $row = undef unless $row->{node_id};
            unless ($row) {
                $status = $cms->error("Запрошенная страница не найдена");
                last;
            };
            
            $baseUrl = $baseUrl.$subUrl;
            $pageId = $row->{node_id};
            $menuNodeId = $row->{id}; #Для подсветки пункта меню
            
			my $pageRow = $cms->getPageRowById($pageId);
			unless ($pageRow) {
				$status = $cms->error();
				last;
			};
            $subsiteId = $pageRow->{subsite_id};
            unless ($cms->hasPageAccess($pageId,$subsiteId)) {
                $status = $cms->error("Отсутствует доступ к запрошенной странице");
                last;
            };
            
            my $pageObj = $cms->getPageObjByRow($pageRow,{ADMINBASEURL=>$baseUrl}) or return $cms->error();
            unless ($pageObj->can("adminPage")) {
                $status = $cms->error("Модуль ".(ref $pageObj)." не содержит метода adminPage");
                last;
            };

			my $tabs = undef;
            unless ($pageObj->can("getPageTabs")){
                $status = $cms->error("Модуль ".(ref $pageObj)." не содержит метода getPageTabs()");
                last;
            };
            $tabs = $pageObj->getPageTabs();
			unless ($tabs) {
                my $e = $cms->getError((ref $pageObj)."::getPageTabs(): не вернул списка вкладок");
                $status = $cms->error($e);
				last;
			};
			if (ref $tabs ne "ARRAY") {
				$status = $cms->error("Вызов getPageTabs() модуля ".(ref $pageObj)." вернул некорректное значение (не массив).");
				last;
			};
			if ( scalar @$tabs == 0 ){
				# Если нет доступных блоков - выводим список доступных страниц
                my $pageObj2 = $cms->getObject("NG::Module::PageSelector") or return $cms->error();
                $status = $pageObj2->moduleAction($is_ajax); #TODO: метод, сам модуль- выверить
                last;
			};
            $cms->{_rightSelector} = $tabs;
            $status = $pageObj->adminPage($is_ajax);
			last;
		}
	}
    elsif ($subUrl eq "modules/") {
        $baseUrl = $baseUrl.$subUrl;
        $subUrl = ($url=~ /^$baseUrl([^\s]+)\//) ? $1."/" : "";

        my $row = undef;
        if (!$subUrl) {
        }
        elsif ($subUrl =~ /^(\d+)\//) {
            $row = $cms->_getRowByModuleID($1);
            $row = undef if $row->{node_id};
        }
        else {
            my $t = $subUrl;
            $t =~ s/\/$//;
            $row = $cms->_getRowByModuleURL($t);
        }
        
        return $cms->error("Запрошенный модуль не найден") unless $row && $row->{id};
        return $cms->error("Отсутствует значение поля module_id для строки ".$row->{id}) unless $row->{module_id};
        #return $cms->error("Доступ к запрошенному подсайту запрещен") unless $cms->_checkSubsiteAccess($row->{subsite_id});
        return $cms->error("Отсутствует доступ к запрошенному модулю") unless $cms->hasModulePrivilege(MODULE_ID=>$row->{module_id},PRIVILEGE=>"ACCESS");

        $row->{url}.="/" unless $row->{url} =~ /\/$/;
        $baseUrl = $baseUrl.$row->{url};
        
        $subsiteId = $row->{subsite_id};
        $menuNodeId = $row->{id};
        $mId = $row->{module_id};
#warn Dumper($row);
        
        my $mRow = $cms->getModuleRow("id=?",$row->{module_id}) or return $cms->defError("getModuleByCode():","Запрошенный модуль c кодом ".$row->{module_id}." не найден");
        my $mObj = $cms->getObject($mRow->{module},{ADMINBASEURL=>$baseUrl, MODULEROW=>$mRow}) or return $cms->error();
        
        while(1) {
            unless ($mObj->can("getModuleTabs")) {
                $status = $cms->error("Модуль ".ref($mObj)." не содержит метода getModuleTabs()");
                last;
            };
            my $mtabs = $mObj->getModuleTabs();
            if ($mtabs eq "0") {
                $status = $cms->error();
                last;
            };
            unless ($mtabs && ref $mtabs eq "ARRAY") {
                $status = $cms->error("Модуль ".ref($mObj)." вернул некорректное значение в getModuleTabs()") ;
                last;
            };
            $cms->{_rightSelector} = $mtabs;
            $status = $mObj->adminModule($is_ajax);
            last;
        };
    }
    elsif ($subUrl eq "") {
=head
		my $pageObj = $cms->getObject('NG::Module::MainAdm') or return $cms->error();
		unless ($pageObj) {
			$error = $cms->getError();
		};
		$status = $pageObj->moduleAction($is_ajax);
=cut
        $status = $cms->output();
    }
    else {
        $status = $cms->error("Некорректная ссылка. Исправьте модуль.");
    };

    my $rightBlock = "";
	
	if ($status && ref $status ne "NG::BlockContent") {
		return $cms->showError("Некорректный объект ответа");
	};
	
	if ($status == NG::Application::M_ERROR || $status->is_error()) {
        my $error = $cms->getError("Неизвестная ошибка в контроллере страницы");
        $rightBlock = $cms->_getRightBlockContentAsErrorMessage($error);
        return $cms->output($rightBlock) if ($is_ajax);
	}
    elsif ($status->is_output()) {
        if ($is_ajax) {
=head TODO: Обновление календаря AJAX-ом не работает.  <SCRIPT> не исполняется
            # Обновление календаря
            if ($cms->{_calendar}) {
                $rightBlock = $status->getOutput();
                $rightBlock .= $cms->getCalendarAjax();
                return $cms->output($rightBlock);
            };
=cut
            #TODO: нужен код который будет перерисовывать вкладки (Табы)
            return $status; #Данные заберутся из $cms
        }
        else {
            $rightBlock = $status->getOutput();
        };
	}
    elsif ($status->is_redirect()) {
		return $status unless $is_ajax;
        my $redirectUrl = $status->getRedirectUrl() || $url;

        if ($redirectUrl =~ /\/$/) {
            $redirectUrl .= "?";
        } else {
            if (($redirectUrl !~ /\&$/) && ($redirectUrl !~ /\?$/)) { $redirectUrl .="&"; };
        };
        $redirectUrl .= "_ajax=1";
        return $cms->output("<script type='text/javascript'>if (parent) {parent.ajax_url('".$redirectUrl."','middle_right_content');}else{ajax_url('".$redirectUrl."','middle_right_content');}</script>",-nocache=>1);
    }
    elsif ($status->is_exit()) {
		return $status;
	}
    else {
        $rightBlock = $cms->_getRightBlockContentAsErrorMessage("Некорректный код возврата ($status) после вызова модуля ");
        return $cms->output($rightBlock) if ($is_ajax);
	};

    my @pageurls = ();
    if ($pageId) {
        push @pageurls, {URL=> "/admin-side/modules/".$cms->{_siteStructObj}->moduleParam('id')."/$pageId/", NAME=>"Свойства"} if $cms->{_siteStructObj} && $cms->hasPageStructAccess($pageId,$subsiteId);
        push @pageurls, {URL=> "/admin-side/modules/".$cms->{_sitePAccessObj}->moduleParam('id')."/$pageId/", NAME=>"Права"}   if $cms->{_sitePAccessObj} && $cms->hasModulePrivilege(PRIVILEGE=>'ACCESS',MODULE_ID=>$cms->{_sitePAccessObj}->moduleParam('id'),PAGE_ID=>$pageId);
    };
    if ($mId) {
        push @pageurls, {URL=> "/admin-side/modules/".$cms->{_siteMAccessObj}->moduleParam('id')."/$mId/", NAME=>"Права"}   if $cms->{_siteMAccessObj} && $cms->hasModulePrivilege(PRIVILEGE=>'ACCESS',MODULE_ID=>$cms->{_siteMAccessObj}->moduleParam('id'));
    };

    my $leftBlock = $cms->_getModulesTreeHTML({
        PAGE_ID => $pageId,
        NODE_ID => $menuNodeId,
        SUBSITE_ID => $subsiteId,
    });
    
    $cms->pushRegion({CONTENT=>$leftBlock,REGION=>"LEFT"});
    $cms->pushRegion({CONTENT=>$rightBlock,REGION=>"RIGHT"});
    
    my $template = $cms->gettemplate('admin-side/common/universaladm.tmpl') || return $cms->showError();
    
    my $rContent = {};
    foreach my $r (keys %{$cms->{_regions}}) {
        my $c = "";
        foreach my $d (sort { $a->{WEIGHT} <=> $b->{WEIGHT}; } @{$cms->{_regions}->{$r}}) {
            $c.= $d->{CONTENT};
        };
        $rContent->{$r} = $c;
    };
    
    my $customHead = "";
    $customHead = "admin-side/customhead.tmpl" if $cms->confParam('CMS.hasCustomHead',0);
    $template->param(
        REGION => $rContent,
        AS => {
            RIGHT_SELECTOR => $cms->{_rightSelector},
            TITLE          => $cms->confParam('CMS.SiteName','Cайт')." :: Администрирование",
            PAGEURLS       => \@pageurls,
            CUSTOMHEAD     => $customHead,
        },
    );
    return $cms->output($template,-nocache=>1);
};

sub pushRegion {  #REGION WEIGHT CONTENT
    my $self = shift;
    my $h = shift;
    my $r = delete $h->{REGION};
    $h->{WEIGHT}||=0;
    $self->{_regions}->{$r}||=[];
    push @{$self->{_regions}->{$r}}, $h;
};

sub setTabs {
    my $self = shift;
    $self->{_rightSelector} = shift;
};

return 1;
END{};
