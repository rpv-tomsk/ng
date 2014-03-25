package NG::Adminside;
use strict;

use Data::Dumper;

use NG::Application;
use NHtml;
use NSecure;
use NGService;
use POSIX;
use vars qw(@ISA);
@ISA = qw(NG::Application);

use constant C_AUTH_NOCOOKIE => 0;
use constant C_AUTH_OK       => 1;
use constant C_AUTH_EXPIRES  => 2;
use constant C_AUTH_WRONGLOGIN=>4;
use constant C_AUTH_WRONGIP  => 8;
use constant C_SESSION_EXPIRES => 3600;
use constant C_SESSION_UPDATE  => 60;
use constant COOKIENAME => "ng_session";

sub init {
    my $self = shift;
    my %param = @_;
    $self->SUPER::init(@_);
    
    $self->{_calendar} = undef;
    
    $self->{_admin} = undef;
	$self->{_auth_status} = undef;
    $self->{_rightSelector} = [];
	
    $self->{_linkBlocksPrivileges} = {};
   
    $self->{_siteStructObj} = undef;
    $self->{_sitePAccessObj} = undef;
    $self->{_siteMAccessObj} = undef;
   
    $self;
};

sub getCalendar {
    my $self=shift;
    return $self->{_calendar} if $self->{_calendar};
    $self->{_calendar} = $self->getObject("NG::Calendar",@_);
    $self->{_calendar}->visual({ 
        'CLASS1'      => '',
        'CLASS2'      => '',
        'CLASS3'      => '',
        'CLASS4'      => '',
        'CLASS4W'     => '',
        'CLASS5'      => '',
        'CLASS6'      => '',
        'CLASS7'      => '',
        'CLASS_ACTIVE'=> 'class=current_date',
        'CLASS_NODAY' => '',
        'IMBACK'      => '',
        'IMFORW'      => '',
    });
    return $self->{_calendar};
};

sub _makeLogEvent {
    my $self = shift;
    my $module = shift;
    my $opts = shift;
    
    my $event = $self->getObject("NG::Event::Log",$module,"LOG",$opts);
    $self->processEvent($event);
};

sub _printCalendar {
    my $self = shift;
    my $template = shift;
    my $cal = $self->getCalendar();
    my %calendar = (
        ACTION => $cal->{ACTION},
        HTML => $cal->calendar_month(),
        MONTH_OPTIONS => $cal->get_month_options(),
        YEAR_OPTIONS => $cal->get_year_options(),
        CURRENT_MONTH => $cal->get_month_name($cal->month()),
        CURRENT_YEAR => $cal->year(),
        NEXT_URL => $cal->{NEXT_URL},  
        PREV_URL => $cal->{PREV_URL},
        CURRENT_URL => $cal->{CURRENT_URL},
        FILTER_DESCRIPTION => $cal->{FILTER_DESCRIPTION},
        CPARAMS => $cal->{CPARAMS}
    );      
    $template->param(
        CALENDAR => \%calendar,
    );
};

sub getCalendarAjax {
    my $app = shift;
    my $template = $app->gettemplate("admin-side/common/calendar.tmpl");
    $app->_printCalendar($template);
    my $calendar_output = $template->output();
    $calendar_output = escape_js $calendar_output;
    return qq(<script type="text/javascript">document.getElementById('calendar_div').innerHTML = '$calendar_output';</script>);
};

#### Authorization code
sub Authenticate {
	my $self = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $cookievalue = $q->cookie(-name=>COOKIENAME) || "";
	
	my $sth = undef;
	my $admin = undef;
	$self->{_auth_status} = C_AUTH_NOCOOKIE;
	if ($cookievalue) {
		$sth = $dbh->prepare("select id,login,fio,last_online,last_ip,sessionkey,level,group_id from ng_admins where sessionkey=?") or die $DBI::errstr;
		$sth->execute($cookievalue) or die $DBI::errstr;
		$admin = $sth->fetchrow_hashref();
		$sth->finish();
		if (!defined $admin) {
			$self->{_auth_status} = C_AUTH_NOCOOKIE;
			return 1;
		};
		if ($admin->{last_ip} ne $q->remote_host()) {
			$self->{_auth_status} = C_AUTH_WRONGIP;
			return 1;
		}
		my $time = time();
		if ($time-$admin->{last_online} > C_SESSION_EXPIRES) {
		    $self->{_auth_status} = C_AUTH_EXPIRES;
		    return 1;
		};
		if ($time-$admin->{last_online} > C_SESSION_UPDATE) {
		    $dbh->do("update ng_admins set last_online=? where id = ?",undef,$time,$admin->{id});
		};
		$self->{_admin} = $admin;
        $self->{_auth_status} = C_AUTH_OK;
		return 1;
	};
	return 1;
};

sub getAuthStatus{
    my $self = shift;
	die "Authenticate() call missing. Can`t continue." if (!defined $self->{_auth_status});
    return $self->{_auth_status};
};

sub getAuthStatusText {
	my $self = shift;
	my $status = $self->getAuthStatus();
	return "Вы авторизованы." if ($status == C_AUTH_OK);
	return "Сессия устарела." if ($status == C_AUTH_EXPIRES);
	return "" if ($status == C_AUTH_NOCOOKIE)||($status == C_AUTH_WRONGIP);
	return "Имя пользователя или пароль неверны." if ($status == C_AUTH_WRONGLOGIN);
};

sub _getAdmin { # собственно возвращает информацию об админе, полученную из базы
    my $self=shift;
    return $self->{'_admin'};
};

sub getAdminId {
    my $self = shift;
    die "getAdminId(): variable '_admin' not initialised" unless exists $self->{_admin};
    return $self->{_admin}->{id};
};

sub AuthenticateByLogin {
    my $self = shift;
    my $q = $self->q();
    my $dbh = $self->{_db}->dbh();
    my $login    = $q->param('ng_login') || "";
    my $password = $q->param('ng_password') || "";
	my $is_ajax  = $q->param('is_ajax') || $q->url_param('is_ajax') || 0;
    my $sth = undef;
    my $admin = undef;
	$self->{_auth_status} = C_AUTH_WRONGLOGIN;
    if ($login && $password) {
        $sth = $dbh->prepare("select id,login,fio,last_online,sessionkey from ng_admins where login=? and password=?") or die $DBI::errstr;
        $sth->execute($login,$password) or die $DBI::errstr;
        $admin = $sth->fetchrow_hashref();
        $sth->finish();
        if ($admin) {
            $self->{_admin} = $admin;
            if ($admin->{sessionkey}) {
                $self->_makeLogEvent($self,{operation=>"Выход из системы",log_time=>strftime("%d.%m.%Y %T",localtime($admin->{last_online})),module_name=>"Система"});
            };
            $admin->{sessionkey} = generate_session_id();
            $admin->{last_online} = time();
            $dbh->do("update ng_admins set sessionkey=?,last_online=?,last_ip=? where id=?",undef,$admin->{sessionkey},$admin->{last_online},$q->remote_host(),$admin->{id}) or die $DBI::errstr;
            $self->addCookie(-name=>COOKIENAME,-value=>$admin->{sessionkey},-domain=>$q->virtual_host(),-path=>'/admin-side/');
			$self->{_auth_status} = C_AUTH_OK;
			$self->_makeLogEvent($self,{operation=>"Вход в систему",module_name=>"Система"});
        };
    };

	if ($self->{_auth_status} == C_AUTH_OK) {
		if ($is_ajax) {
			return $self->output("<script type='text/javascript'>window.close();</script>",-nocache=>1);
		}
		else {
		    my $url = $q->param('url')?$q->param('url'):"/admin-side/";
		    return $self->redirect($url); ## TODO: redirect to url from form
		};
	};
	my $message = $self->getAuthStatusText();
	if ($is_ajax) {
		return $self->showPopupLoginForm($message);
	}
	else {
		return $self->showLoginForm($message,$q->param('url'));
	};
    return 0;
};

sub Logout {
	my $self = shift;
	my $q = $self->q();
	my $dbh = $self->{_db}->dbh();
	my $cookievalue = $q->cookie(-name=>COOKIENAME) || "";
	
	if ($cookievalue) {
		my $sth = $dbh->prepare("update ng_admins set sessionkey='' where sessionkey=?") or die $DBI::errstr;
		$sth->execute($cookievalue) or die $DBI::errstr;
		$sth->finish();
	};

	$self->addCookie(
		-name=>COOKIENAME,
		-value=>"",
		-domain=>$q->virtual_host(),
		-expires=>'-1d',
		-path=>'/admin-side/',
	);
	$self->_makeLogEvent($self,{operation=>"Выход из системы",module_name=>"Система"});
	return $self->redirect("/admin-side/");
}

sub editAdmin {
	my $self = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	
	my $ref = $q->param("ref") || $q->url(-absolute=>1);
	my $is_ajax = $q->param("_ajax");
	
	my $admin = $self->_getAdmin() or return $self->showError("Не авторизованы.");
	
    my $action = $q->url_param("action") || "";
    my $form = $self->getObject("NG::Form",
        FORM_URL  => $self->q()->url()."?action=editadmin",
        KEY_FIELD => "id",
        DB        => $self->db(),
        TABLE     => "ng_admins",
        DOCROOT   => $self->{_docroot},
        CGIObject => $q,
        REF       => $ref,
    );

	$form->setTitle('Данные администратора '.$admin->{fio}." (".$admin->{login}.")");

    if ($admin->{level} == 0) {
        $form->addfields([
            {FIELD=>"id",NAME=>"id",TYPE=>"id",VALUE=>$admin->{id}},
            {FIELD=>"fio",NAME=>"ФИО",TYPE=>"text",IS_NOTNULL=>1},
        ]);
    } else {
        $form->addfields(
            {FIELD=>"id",NAME=>"",TYPE=>"id",VALUE=>$admin->{id}},
        );			
    };
		
    if ($action eq "editadmin") {
        $form->addfields([
            {FIELD=>'password', TYPE=>'password',NAME=>'Пароль', },
            {FIELD=>'password_repeat', TYPE=>'password',NAME=>'Подтвердите пароль', },
        ]);
        $form->setFormValues();
        $form->StandartCheck();
        
        if (is_empty($form->getParam("password")) && is_empty($form->getParam("password_repeat"))) {
            $form->deletefield("password");
        }
        else {
            $form->pusherror("password","Введенные пароли не совпадают") if ($form->getParam("password") ne $form->getParam("password_repeat"));
        }
        
        if (!$form->has_err_msgs()) {
            $form->deletefield("password_repeat");
            $form->updateData();
            if ($is_ajax == 1) {
                return $self->output("<script type='text/javascript'>parent.document.location='".$q->url()."?ok=1"."';</script>", -nocache=>1);
            }
            else {
                return $self->redirect($q->url()."?ok=1");
            };				
        } else {
            if ($is_ajax) {
                return $self->output(
                    "<script type='text/javascript'>parent.document.getElementById('updated').innerHTML='';</script>"
                    .$form->ajax_showerrors(),
                    -nocache=>1,
                );
            };
        };
    } else {
        $form->loadData() or return $self->error($form->getError());
        $form->addfields([
            {FIELD=>'password', TYPE=>'password',NAME=>'Пароль',},
            {FIELD=>'password_repeat', TYPE=>'password',NAME=>'Подтвердите пароль', },
        ]);			
    };

    my $tmpl = $self->gettemplate("admin-side/common/universalform.tmpl");
    $form->print($tmpl);
    my $formhtml = $tmpl->output();
    
    $tmpl = $self->gettemplate("admin-side/admin/adminedit.tmpl");
    my $updated = 0;
    $updated = 1 if $q->param("ok") && $q->param("ok")==1;
    $tmpl->param(
        FORM=>$formhtml,
        UPDATED=> $updated,
    );
    return $self->output($tmpl);
};


sub showLoginForm {
    my $self = shift;
    my $q = $self->q();
    my $login = $q->param('ng_login') || "";
    my $message = shift || "";
	my $url = shift || "";
    my $tmpl = $self->gettemplate("admin-side/common/loginform.tmpl") || return $self->showError();
    $tmpl->param(
		MESSAGE=>$message,
		IS_AJAX=>0,
		URL=>$url,
		LOGIN=>$login,
        TITLE=> $self->confParam('CMS.SiteName','Сайт')." :: Авторизация",
	);
    return $self->output($tmpl,-nocache=>1);
};

sub showPopupLoginForm {
    my $self = shift;
    my $message = shift || "";
    
    my $q = $self->q();
    my $login = $q->param('ng_login') || "";
    
    my $tmpl = $self->gettemplate("admin-side/common/popuploginform.tmpl") || return $self->showError();
    $tmpl->param(
		MESSAGE=>$message,
		IS_AJAX=>1,
		LOGIN=>$login,
        TITLE=> $self->confParam('CMS.SiteName','Сайт')." :: Авторизация",
	);
    return $self->output($tmpl,-nocache=>1);
};

#### /Authorization code 
#
# Код проверки привилегий
#

# Методы трансляции проверок привилегий в соответствующий модуль

sub hasPageModulePrivilege { #PAGE_ID MODULE_ID PRIVILEGE SUBSITE_ID
    my $cms = shift;
   
    return 1 unless ($cms->{_sitePAccessObj});
   
    my %att = (@_); 
    $att{ADMIN_ID} = $cms->getAdminId();
    $att{GROUP_ID} = $cms->{_admin}->{group_id};
    return $cms->{_sitePAccessObj}->hasPageModulePrivilege(%att);
};

sub hasLinkModulePrivilege { #LINK_ID MODULE_ID PRIVILEGE SUBSITE_ID
    my $cms = shift;
   
    return 1 unless ($cms->{_sitePAccessObj});
   
    my %att = (@_); 
    $att{ADMIN_ID} = $cms->getAdminId();
    $att{GROUP_ID} = $cms->{_admin}->{group_id};
    return $cms->{_sitePAccessObj}->hasLinkModulePrivilege(%att);
};

sub hasModulePrivilege { #MODULE_ID PRIVILEGE
    my $cms = shift;
    
    return 1 unless ($cms->{_siteMAccessObj});
    
    my %att = (@_);
    $att{ADMIN_ID} = $cms->getAdminId();
    $att{GROUP_ID} = $cms->{_admin}->{group_id};
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
    my $groupId   = $app->{_admin}->{group_id};
    
    
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


#    my $selNode = undef;
=head
	$tree->traverse(
		sub {
			my $_tree = shift;
			my $value = $_tree->getNodeValue();
            
            ##TODO: $value->{HASACCESS} = ($hasGlobalSubsiteAccess || exists $pagePrivs->{$value->{id}} || exists $linkPrivs->{$value->{link_id}})?1:0;
            

			$value->{URL} = "";
			
			my $allowed = exists $mp->{$value->{id}} && exists $mp->{$value->{id}}->{ACCESS};
			
			if ($allowed) {
                my $subUrl = $value->{suburl};
                $subUrl .= "/" if $subUrl && ($subUrl !~ /\/$/);

                if (($qModuleId eq $value->{id}) || ($moduleUrl eq $value->{moduleurl}."/" && $url =~ /^$baseUrl$moduleUrl$subUrl/ && (!$selNode || length($value->{suburl}) >= length($selNode->getNodeValue()->{suburl})))) {
                    $selNode = $_tree;
                };
				
				if ($value->{module}) {
					$value->{'URL'} = "/admin-side"."/modules/".$value->{'moduleurl'}.(is_empty($value->{'suburl'})?"/":"/".$value->{'suburl'}."/");
				};
				
				my $node = $_tree;
				while (1) {
					my $v = $node->getNodeValue();
					$v->{ALLOWED} = 1;
					last if $node->isRoot();
					$node = $node->getParent();
				};
			};

            $value->{HASACCESS} = 0;

            if ($value->{node_id}) {
                my $u = $value->{url};
                $u ||= $value->{node_id};
                $value->{url} = "/admin-side/pages/$u/";
                $value->{HASACCESS} = 1 if ($app->hasPageModulePrivilege(PAGE_ID=>$value->{node_id},SUBSITE_ID=>$value->{subsite_id},MODULE_ID=>$accessModuleId,PRIVILEGE=>'ACCESS'));
            }
            elsif ($value->{module_id}) {
                my $u = $value->{url};
                $u ||= $value->{module_id};
                $value->{url} = "/admin-side/modules/$u/";
                $value->{HASACCESS} = 1 if ($app->hasModulePrivilege(MODULE_ID=>$value->{module_id},PRIVILEGE=>'ACCESS'));
            }
            else {
                $value->{url} = '';
            };
            #$value->{INACTIVE} = 1;
			#$value->{HASACCESS} = 0;
		}
	);
=cut
=head
    my $moduleId = 0;
    if ($selNode) {
        $selNode->getNodeValue()->{SELECTED}  = 1;
        $moduleId = $selNode->getNodeValue()->{id};
    };
    
	my @a = ($tree);
	while (scalar (@a)) {
		my $e = shift @a;
		my $prevChild = undef;
		foreach my $c ($e->getAllChildren()) {
			if ($c->getNodeValue()->{ALLOWED}) {
				$prevChild->{_next_sibling_order} = $c->{_order} if $prevChild;
				$prevChild = $c;
				$c->{_next_sibling_order} = undef;
				push @a,$c;
			}
			else {
				$e->removeChild($c);
			}
		}
	};
=cut
	my $template = $app->gettemplate('admin-side/common/content_tree.tmpl') || return $app->getError();
	
	
	if ($app->{_calendar}) {
	   $app->_printCalendar($template);
	};
	
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
	my $cms = shift;
	my $q = $cms->q();

    my $url = $q->url(-absolute=>1);
    my $is_ajax  = $q->param('_ajax') || $q->url_param('_ajax') || 0;

    $cms->openConfig() || return $cms->showError();

	my $baseUrl = "/admin-side/";
	my $subUrl = "";
    if ($url =~ /$baseUrl([^\/\s]+)\//i) {
        $subUrl = $1."/";
    };
    
    
    # Перенесено сюда ибо отлагиниваться можно только если ты авторизованый пользователь иначе можно разлогинить любого администратора
    # Косяк хоть и не страшен
    # И вторая причина ибо мне нужен админ в обработки события выхода из админки	
    
    $cms->Authenticate() or return $cms->showError();
    
    my $ret = undef;
    
	if ($subUrl eq "loginform/") {
        $ret = $cms->showPopupLoginForm("Сессия устарела");
	}
    elsif ($subUrl eq "login/") {
        $ret = $cms->AuthenticateByLogin();
	}
    elsif ($subUrl eq "logout/") {
        $ret = $cms->Logout();
=head
    }
    elsif ($url eq $baseUrl."actions/switchsubsite/") {
        $ret = $cms->switchSubsite();
=cut
    };
    return $cms->processResponse($ret) if defined $ret;
    

    #Check if user authenticated
    my $status = $cms->getAuthStatus();
    if ($status != C_AUTH_OK) {
        if ($is_ajax) {
            my $v = qq (
                <script>
                var win = window.parent?window.parent:window;
                win.open('/admin-side/loginform/?is_ajax=1','','height=200,width=400,top=200,left=200');
                </script>
            );
            $ret = $cms->output($v);
        }
        else {
            my $message = $cms->getAuthStatusText();
            #TODO: выверить эскейпинг 
            $ret = $cms->showLoginForm($message,$q->url(-full=>1, -query=>1 ));
        };
        return $cms->processResponse($ret);
    };

	if ($subUrl eq "editadmin/") {
    	$ret = $cms->editAdmin();
    }
    else {
        $ret = $cms->_run($subUrl,$is_ajax);
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
            # Обновление календаря
            if ($cms->{_calendar}) {
                $rightBlock = $status->getOutput();
                $rightBlock .= $cms->getCalendarAjax();
                return $cms->output($rightBlock);
            };
            #TODO: нужен код который будет перерисовывать вкладки (Табы)
            return $status; #Данные заберутся из $cms
        }
        else {
            $rightBlock = $status->getOutput();
        };
	}
=comment
    elsif ($status == NG::Module::M_FULLREDIRECT) {
		my $redirectUrl = $pageObj->getRedirectUrl() || $url;
		if ($is_ajax == 1) {
			#TODO: $app->set_header_nocache();
			return $app->output("<script type='text/javascript'>parent.document.location='".$redirectUrl."';</script>");
		} else {
			return $app->redirect($redirectUrl);
		};
	}
=cut
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
    
    my $template = $cms->gettemplate('admin-side/common/universaladm.tmpl') || return $cms->showError();
    
    $template->param(
        AS => {
            LEFT_BLOCK     => $leftBlock,
            RIGHT_BLOCK    => $rightBlock,
            RIGHT_SELECTOR => $cms->{_rightSelector},
            PAGE_ID        => $pageId,
            #MODULE_ID      => $mId,
            TITLE          => $cms->confParam('CMS.SiteName','Cайт')." :: Администрирование",
            CURRENT_USER   => $cms->{_admin}->{fio},
            PAGEURLS       => \@pageurls,
        },
    );
    return $cms->output($template,-nocache=>1);
};

sub setTabs {
    my $self = shift;
    $self->{_rightSelector} = shift;
};

return 1;
END{};
