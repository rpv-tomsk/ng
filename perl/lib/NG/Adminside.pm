package NG::Adminside;
use strict;

use NG::Application;

use vars qw(@ISA);
@ISA = qw(NG::Application);

sub init {
    my $self = shift;
    my %param = @_;
    $self->SUPER::init(@_);
    
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

sub _getRightBlockContentAsErrorMessage {
	my $app = shift;
	my $error = shift;
	$error ||= "_getRightBlockContentAsErrorMessage(): Вызов без указания текста сообщения.";
	#$app->{_rightSelector} = [{HEADER=> "Ошибка",SELECTED=>1}] unless scalar(@{$app->{_rightSelector}});
	
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
    
    #Получаем объект router.
    my $class = $cms->confParam("Admin-side.RouterClass","NG::Adminside::Router");
    return $cms->error("Отсутствует параметр Admin-side.RouterClass") unless $class;
    
    my $router = $cms->getObject($class) or return $cms->defError("RouterClass:", "Ошибка создания объекта класса");
    
    my ($ret,$route) = $router->Route($is_ajax);
    return $ret if $ret != NG::Application::M_CONTINUE;
    
    my $status = NG::Application::M_ERROR;
	my $tabs = undef;
    my @urls = ();
	
	if ($route->{PAGEID}) {
        while (1) {
            my $opts = $route->{OPTS} || {};
            my $pageId = $route->{PAGEID};
            
            my $pageRow = $cms->getPageRowById($pageId) or return $cms->error();
            my $subsiteId = $pageRow->{subsite_id};
            unless ($cms->hasPageAccess($pageId,$subsiteId)) {
                $status = $cms->error("Отсутствует доступ к запрошенной странице");
                last;
            };
            
            my $pageObj = $cms->getPageObjByRow($pageRow,$opts) or return $cms->error();
            unless ($pageObj->can("adminPage")) {
                $status = $cms->error("Модуль ".(ref $pageObj)." не содержит метода adminPage");
                last;
            };

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
            
            push @urls, {URL=> "/admin-side/modules/".$cms->{_siteStructObj}->moduleParam('id')."/$pageId/", NAME=>"Свойства"} if $cms->{_siteStructObj} && $cms->hasPageStructAccess($pageId,$subsiteId);
            push @urls, {URL=> "/admin-side/modules/".$cms->{_sitePAccessObj}->moduleParam('id')."/$pageId/", NAME=>"Права"}   if $cms->{_sitePAccessObj} && $cms->hasModulePrivilege(PRIVILEGE=>'ACCESS',MODULE_ID=>$cms->{_sitePAccessObj}->moduleParam('id'),PAGE_ID=>$pageId);
            
            $status = $pageObj->adminPage($is_ajax);
			last;
		}
	}
    elsif ($route->{MODULEID}) {
        my $mId  = $route->{MODULEID};
        my $opts = $route->{OPTS} || {};

        #return $cms->error("Доступ к запрошенному подсайту запрещен") unless $cms->_checkSubsiteAccess($row->{subsite_id});
        return $cms->error("Отсутствует доступ к запрошенному модулю") unless $cms->hasModulePrivilege(MODULE_ID=>$mId ,PRIVILEGE=>"ACCESS");
        
        my $mRow = $cms->getModuleRow("id=?",$mId) or return $cms->error("Запрошенный модуль c кодом ($mId) не найден");
        $opts->{MODULEROW} = $mRow;
        my $mObj = $cms->getObject($mRow->{module},$opts) or return $cms->error();
        
        while(1) {
            unless ($mObj->can("getModuleTabs")) {
                $status = $cms->error("Модуль ".ref($mObj)." не содержит метода getModuleTabs()");
                last;
            };
            $tabs = $mObj->getModuleTabs();
            if ($tabs eq "0") {
                $status = $cms->error();
                last;
            };
            unless ($tabs && ref $tabs eq "ARRAY") {
                $status = $cms->error("Модуль ".ref($mObj)." вернул некорректное значение в getModuleTabs()") ;
                last;
            };
            push @urls, {URL=> "/admin-side/modules/".$cms->{_siteMAccessObj}->moduleParam('id')."/$mId/", NAME=>"Права"}   if $cms->{_siteMAccessObj} && $cms->hasModulePrivilege(PRIVILEGE=>'ACCESS',MODULE_ID=>$cms->{_siteMAccessObj}->moduleParam('id'));
            $status = $mObj->adminModule($is_ajax);
            last;
        };
    }
    elsif ($route->{STATUS}) {
        $status = $route->{STATUS};
    }
    else {
        return $cms->error("Incorrect router response");
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
        my $redirectUrl = $status->getRedirectUrl() || $cms->q->url(-absolute=>1);;

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
            RIGHT_SELECTOR => $tabs,
            TITLE          => $cms->confParam('CMS.SiteName','Cайт')." :: Администрирование",
            PAGEURLS       => \@urls,
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

return 1;
END{};
