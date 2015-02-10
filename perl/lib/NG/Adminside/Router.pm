package NG::Adminside::Router;
use strict;

use NG::Application;
use NG::Nodes;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_) or return undef;
    return $self; 
};

sub init {
    my $self = shift;
    #__default__
    $self->{map} = {
        '' => {ROUTE=>"default", MENU=>"menu"},
        'pages/'      => {ROUTE=>"pages",   MENU=>"menu"},
        'modules/'    => {ROUTE=>"modules", MENU=>"menu"},
    };
    my $opts = shift;
    $self->{topURL} = $opts->{BASEURL};
    $self->{_menuNodeId} = undef;
    $self;
};

sub __getRow {
    my $self = shift;
    my $where = shift;
    
    my $dbh = $self->dbh();

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
    $row||={};
    return $row;
};

sub _getRowByPageID {
    my $self = shift;
    return $self->__getRow("node_id=?",@_);
};

sub _getRowByPageURL {
    my $self = shift;
    return $self->__getRow("url=? and node_id is not null",@_);   
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

sub Route {
    my $self = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $url = $q->url(-absolute=>1);
    
    my $baseUrl = $self->{topURL};
    my $subUrl = "";
    if ($url =~ /$baseUrl([^\/\s]+)\//i) {
        $subUrl = $1."/";
    };
    
    my $map = $self->{map}->{$subUrl};
    if ($map) {
        $baseUrl = $baseUrl.$subUrl;
    }
    else {
        $map = $self->{map}->{'__default__'};
    };
    return $cms->error("Некорректная ссылка. Исправьте модуль.") unless $map;
    my $r = $map->{ROUTE};
    return $cms->error("Некорректная карта в объекте ROUTER.  Отсутствует ROUTE. Исправьте модуль.") unless $r;
    return $cms->error("ROUTER не содержит метода $r (ROUTE)") unless $self->can($r);
    
    my $m = $map->{MENU};
    return $cms->error("Некорректная карта в объекте ROUTER. Отсутствует MENU. Исправьте модуль.") unless $m;
    return $cms->error("ROUTER не содержит метода $r (MENU)") unless $self->can($m);
    
    
    my ($ret,$route) = $self->$r($baseUrl);
    return $ret if $ret != NG::Application::M_CONTINUE;
    
    $ret = $self->$m() unless $is_ajax;
    
    return ($ret,$route);
};
    
sub pages {
    my $self = shift;
    my $baseUrl = shift;
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $url = $q->url(-absolute=>1);
    my $subUrl = ($url=~ /^$baseUrl([^\/\s]+)\//) ? $1."/" : "";
    
    return $cms->redirect($self->{topURL}) unless ($subUrl);
    
    my $row = undef;
    
    if ($subUrl =~ /^(\d+)\//) {
        $row = $self->_getRowByPageID($1);
    }
    else {
        my $t = $subUrl;
        $t =~ s/\/$//;
        $row = $self->_getRowByPageURL($t);
    };
    
    $row or return $cms->defError("Ошибка запроса строки ng_admin_menu");
    $row->{node_id} or return $cms->error("Запрошенная страница не найдена");
    
    $baseUrl = $baseUrl.$subUrl;
    $self->{_menuNodeId} = $row->{id}; #Для подсветки пункта меню
    
    return (NG::Application::M_CONTINUE,{PAGEID=>$row->{node_id}, OPTS=>{ADMINBASEURL=>$baseUrl}});
};

sub modules {
    my $self = shift;
    my $baseUrl = shift;
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $url = $q->url(-absolute=>1);
    my $subUrl = ($url=~ /^$baseUrl([^\s]+)\//) ? $1."/" : "";
    return $cms->redirect($self->{topURL}) unless ($subUrl);
    
    my $row = undef;
    if ($subUrl =~ /^(\d+)\//) {
        $row = $self->_getRowByModuleID($1);
        $row = undef if $row->{node_id};
    }
    else {
        my $t = $subUrl;
        $t =~ s/\/$//;
        $row = $self->_getRowByModuleURL($t);
    }
    
    return $cms->error("Запрошенный модуль не найден в структуре меню ng_admin_menu") unless $row && $row->{id};
    return $cms->error("Отсутствует значение поля module_id для строки ".$row->{id}) unless $row->{module_id};
    
    $row->{url}.="/" unless $row->{url} =~ /\/$/;
    $baseUrl = $baseUrl.$row->{url};
    
    $self->{_menuNodeId} = $row->{id};
    return (NG::Application::M_CONTINUE,{MODULEID=>$row->{module_id}, OPTS=>{ADMINBASEURL=>$baseUrl}});
};
    
sub default {
    my $self = shift;
    my $cms = $self->cms();
    my $pageObj = $cms->getObject('NG::Module::MainAdm') or return $cms->error();
    return (NG::Application::M_CONTINUE,{STATUS=>$pageObj->adminModule()});
};

sub menu {
    my $self = shift;
    my $cms = $self->cms();
    my $q = $cms->q();
    
    my $qId = $self->{_menuNodeId};
    
    my $adminId = $cms->getAdminId();
    my $groupId = $cms->getAdminGId();
    
    $cms->{_sitePAccessObj}->loadAdminPrivileges(ADMIN_ID=>$adminId, GROUP_ID=>$groupId) if ($cms->{_sitePAccessObj});
    $cms->{_siteMAccessObj}->loadAdminPrivileges(ADMIN_ID=>$adminId, GROUP_ID=>$groupId) if ($cms->{_siteMAccessObj});
    
    NG::Nodes->initdbparams(
        db     => $cms->db(),
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
                    $value->{url} = $self->{topURL}."pages/$u/";
                    $value->{_HASACCESS} = 1 if $cms->hasPageAccess($value->{node_id},$value->{subsite_id});
                    $value->{HASACCESS} = 0 if $value->{disabled};
                }
                elsif ($value->{module_id}) {
                    my $u = $value->{url};
                    $u ||= $value->{module_id};
                    $value->{url} = $self->{topURL}."modules/$u/";
                    $value->{_HASACCESS} = 1 if ($cms->hasModulePrivilege(MODULE_ID=>$value->{module_id},PRIVILEGE=>'ACCESS'));
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
    return $cms->error($@) if ($@);
    
    my $template = $cms->gettemplate('admin-side/common/content_tree.tmpl') || return $cms->error();
    $tree->printToDivTemplate($template,'ADMINMENU',$qId);
    
    $cms->pushRegion({CONTENT=>$template->output(),REGION=>"LEFT"});
    return NG::Application::M_CONTINUE;
};


1;
