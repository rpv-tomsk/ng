package NG::Module::Menu;
use strict;

=comment
http://www.softtime.ru/javascript/dragndrop.php
http://fastcoder.org/articles/?aid=149

=cut

use NGService;
use NSecure;
use NHtml;
use NG::Module;
use NG::Admins;
use NG::Module::Menu::Event;

use vars qw(@ISA);
@ISA = qw(NG::Module);	

sub moduleTabs {
	return [
	    {HEADER=>"Menu builder",URL=>"/"},
	];
};

sub init {
	my $self = shift;
	$self->SUPER::init(@_);
	$self->{_table} = "ng_menu";

	$self->register_ajaxaction("","showFaceMenu");
	$self->register_ajaxaction("insert","insertAction");
	$self->register_ajaxaction("update","updateAction");
	$self->register_ajaxaction("move_down","moveDown");
	$self->register_ajaxaction("move_up","moveUp");
};

sub insertAction {
	my $self=shift;
	my $action=shift;
	my $is_ajax=shift;
    
	my $q=$self->q();
    my $id=is_valid_id($q->param('id'))?$q->param('id'):-1;
	
	my $fa = "";
	if  ($q->request_method eq "POST") {
		$fa = $q->param("formaction");
#print STDERR $fa;
	};

    my $table = $self->{_table};
    
	my $baseUrl = $self->getBaseURL();
	my $subUrl = $self->getSubURL();
    
    my $node = NG::Nodes->new();
	$node->initdbparams(
        db     => $self->db(),
        table  => $table,
        fields => "name,url,node_id,hint_node_id,target,inactive,link_id,subsite_id",
    );
    $node->loadNode($id) or return $self->error("Элемент меню родитель для добавления не найден");
    
    my $parentNodeValue = $node->getNodeValue();

#print STDERR "link_id=".$parentNodeValue->{link_id};

    my $form = NG::Form->new(
        FORM_URL  => $baseUrl.$subUrl."?action=insert",
		KEY_FIELD => "id", #хардкод
		DB        => $self->db(),
		TABLE     => $table,
		DOCROOT   => $self->getDocRoot(),
		SITEROOT  => $self->getSiteRoot(),
		CGIObject => $q,
		REF       => scalar $q->param('ref') || "",
		IS_AJAX   => $is_ajax,
	);
    $form->setTitle("Добавление подпункта в меню '".$parentNodeValue->{name}."'");
    
	$form->addfields({NAME=>"id",       FIELD=>"id",  TYPE=>"id"}                );
	$form->addfields({NAME=>"Название", FIELD=>"name",TYPE=>"text", IS_NOTNULL=>1});
	$form->addfields({NAME=>"Url",      FIELD=>"url", TYPE=>"text", IS_NOTNULL=>1});
    $form->addfields({NAME=>"Prev Url", FIELD=>"prevurl", TYPE=>"hidden", IS_NOTNULL=>0});
    #дополнительные поля
    $form->addfields({NAME=>"Открывать в новом окне",  FIELD=>"target",  TYPE=>"checkbox", IS_NOTNULL=>0});
    #$form->addfields({NAME=>"Элемент активен",      FIELD=>"inactive",TYPE=>"checkbox", IS_NOTNULL=>0});
    $form->param("id",$id);
    $form->modeInsert();
    $form->setcontainer('tree_form'.$id);
    
    
    #Проверяем наличие связанных элементов, делаем их загрузку
	my $linkedNodes = {};
	if ($self->app()->confParam("CMS.hasSubsites")) {
		## Загружаем список связанных родителей
		my $sql = "select
				ng_subsites.id as subsite_id,
				ng_subsites.name as subsite_name,
				ng_lang.id as lang_id,
				ng_lang.name as lang_name,
				ng_lang.img as lang_img,
				$table.id as node_id,
				$table.name as node_name,
				$table.url as node_url
			from
				ng_subsites,
				ng_lang,
				$table
			where
                $table.link_id = ?
				and $table.subsite_id = ng_subsites.id
				and ng_lang.id = ng_subsites.lang_id";
		my $sth=$self->dbh()->prepare($sql) or return $self->error($DBI::errstr);    
		$sth->execute($parentNodeValue->{link_id}) or return $self->error($DBI::errstr);
		$linkedNodes = $sth->fetchall_hashref(['subsite_id']) or return $self->error($DBI::errstr);
		$sth->finish();
		return $self->error("Загрузка связанных элементов меню: Обнаружено нарушение структуры данных в БД (несовпадают link_id,lang_id), страница - родитель не найдена") unless scalar keys %{$linkedNodes};
	}
    else {
        $linkedNodes->{$parentNodeValue->{subsite_id}} = {
            subsite_id => $parentNodeValue->{subsite_id},
            node_id => $id,
        };
    };

    my $hasErrors = 0;    
    if ($fa) {
        $form->setFormValues();
        #делаем проверку ввода
        $form->StandartCheck();
    };
    

	if (scalar keys %{$linkedNodes} > 1) {  #Есть связанные элементы
		if ($fa) {  #Обрабатываем POST
            unless ($fa eq "step1" && $form->hasErrors()) {
                #Добавляем поле для отображения связанных элементов
                my $lf = $form->addfields({
                    NAME=>"Связанные элементы, выбирайте чо добавлять",
                    FIELD=>"linked",
                    TYPE=>"checkbox",
                    IS_NOTNULL=>1,
                    TEMPLATE => "admin-side/common/menu/linkedsections.tmpl",
                    #CLASS    => "",
                });
                
                #Накачиваем поле данными
                my @le = ();
                foreach my $subsiteId (keys %{$linkedNodes}) {
                    my $elem = $linkedNodes->{$subsiteId};
                    my $key = $lf->{FIELD}."_".$form->getComposedKeyValue()."_".$subsiteId;
                    $elem->{KEY} = $key;
                    $elem->{ERRORMSG} = "";
                    if ($elem->{subsite_id} == $parentNodeValue->{subsite_id}) {
                        $elem->{THIS_SUBSITE_ELEM} = 1;
                        $elem->{NAME} = $form->getParam("name");
                        $elem->{URL}  = $form->getParam("url");
                    }
                    else {
                        if ($fa eq "insert") {
                            my $name = $q->param($key."_name");
                            my $url = $q->param($key."_url");
                            my $rb = $q->param($key."_rb");
                            
                            $elem->{NAME} = $name;
                            $elem->{URL} = $url;
                            
                            if ($rb eq "skip") {
                                #Не добавляем
                                $elem->{SKIP_SLTD} = 1;
                            }
                            elsif ($rb eq "asis") {
                                #Добавляем по значению из формы
                                unless ($name && $url) {
                                    $hasErrors = 1;
                                    $elem->{ERRORMSG} = "Не указано название или URL пункта меню";
                                };
                                $elem->{ASIS_SLTD} = 1;
                            }
                            elsif ($rb eq "3") {
                                #Добавляем адаптированно
                                #Проверим, совпадает ли нода линковки из формы с повторно вычисленной из URL
                                #if (($oldLinkNodeId != $newLinkNodeId) && ($url eq $prevurl)) {
                                #    $hasErrors = 1;
                                #    $elem->{ERRORMSG} = "Выявлено изменение кода связанных нод при одинаковом значении н";
                                #}
                                $elem->{ADAPT_SLTD} = 1;
                            }
                            else {
                                $hasErrors = 1;
                                $elem->{ERRORMSG} = "Не выбрано действие";
                            };
                        }
                        elsif ($fa eq "step1") {
                            $elem->{NAME} = $form->getParam("name");
                            $elem->{URL}  = $form->getParam("url");
                            $elem->{SKIP_SLTD} = 1;
                        }
                        else {
                            die "INCORRECT \$fa";
                        };
                    };
                    push @le,$elem;
                };
                
                $lf->{LINKED_ELEMENTS} = \@le;
                
                my $url = $form->getParam("url");
                my $prevurl = $form->getParam("prevurl");
                
                #Если старый URL ne текущий URL - добавляем в поле сообщение "урл изменился, проверьте куда добавлять будем"
                if ($prevurl ne $url && $fa eq "insert") {
                    $lf->setError("Адрес добавляемого подпункта изменился, проверьте добавление подпунктов в связанные меню.");
                };
                $form->param("prevurl",$url);
            };
		};
        
        if ($fa ne "insert" && ($fa ne "step1" || $form->hasErrors())) {
			$form->removeButtons();
			$form->addButton({
				TITLE => "Далее",
				IMG => "/admin-side/img/buttons/next.gif",
				VALUE => "step1",
			});
			$form->addCloseButton();
		};
	};

#print STDERR "FA=$fa ISAJAX=$is_ajax";
	
	if ($fa eq "insert") {
		if (!$form->hasErrors() && !$hasErrors) {
			#Пытаемся добавить элемент(ы)
            
            my $linkId = $self->db()->get_id($table.'.link_id') or return $self->error("Can`t get id for $table (link_id)");
            
#my $dbg = "LINKID = ".$linkId."\n";
#use Data::Dumper;
            
            foreach my $subsiteId (keys %{$linkedNodes}) {
                my $elem = $linkedNodes->{$subsiteId};
                #my $em = escape_js($elem->{ERRORMSG});
                
                next if $elem->{SKIP_SLTD};

                my $newNode = undef;
                if ($subsiteId == $parentNodeValue->{subsite_id}) {
                    $newNode = {
                        name => $form->getParam("name"),
                        url  => $form->getParam("url"),
                        node_id => 0,
                        hint_node_id => 0,
                        target  => $form->getParam("target"),
                        inactive  => 0,
                        link_id  => $linkId,
                        subsite_id => $subsiteId,
                    };
                }
                else {
                    $newNode = {
                        name => $elem->{NAME},
                        url  => $elem->{URL},
                        node_id => 0,
                        hint_node_id => 0,
                        target  => $form->getParam("target"),
                        inactive  => 0,
                        link_id  => $linkId,
                        subsite_id => $subsiteId,
                    };
                };

#$dbg.= "parentId=".$elem->{node_id}." content=".Dumper($newNode)."\n";

                my $treeObj = NG::Nodes->new();
                $treeObj->initdbparams(
                    db    =>$self->db(),
                    table => $table, 
                    fields => "name,url,node_id,hint_node_id,target,inactive,link_id,subsite_id",
                );
                $treeObj->loadNode($elem->{node_id}) or return $self->error("No node found in $table with id = ".$elem->{node_id});
        
                #TODO: проверять ошибки вставки новой строки. //NG::Nodes не умеет возвращать ошибки.
                $treeObj->DBaddChild($newNode);
            };
#return $self->error($dbg);
            return $self->fullredirect($baseUrl.$subUrl."?nodeid=".$id);
		}
		elsif ($is_ajax) {
			#Форма уже отрисована "как надо", выводим ошибки частичным JS
            my $error = "";
            if (scalar keys %{$linkedNodes} > 1) {
                $error .= "<script type='text/javascript'>";
                foreach my $subsiteId (keys %{$linkedNodes}) {
                    my $elem = $linkedNodes->{$subsiteId};
                    my $em = escape_js($elem->{ERRORMSG});
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
		};
	};

	my $tmpl = $self->app()->gettemplate("admin-side/common/universalform.tmpl")  || return $self->showError();
	$form->print($tmpl) or return $self->error($form->getError());
	my $tmp=$tmpl->output();

	if ($fa && $is_ajax) {
		return $self->output("<script>parent.document.getElementById('tree_form".$id."').innerHTML='".escape_js($tmp)."';</script>");
	}
	else {
		return $self->output($tmp);
	};	
};

sub updateAction {
	my $self=shift;
	my $action=shift;
	my $is_ajax=shift;
    
	my $q=$self->q();
    my $id=is_valid_id($q->param('id'))?$q->param('id'):-1;
	
	my $fa = "";
	if  ($q->request_method eq "POST") {
		$fa = $q->param("formaction");
	};

    my $table = $self->{_table};	
    
	my $baseUrl = $self->getBaseURL();
	my $subUrl = $self->getSubURL();

    my $form = NG::Form->new(
        FORM_URL  => $baseUrl.$subUrl."?action=update",
		KEY_FIELD => "id", #хардкод
		DB        => $self->db(),
		TABLE     => $table,
		DOCROOT   => $self->getDocRoot(),
		SITEROOT  => $self->getSiteRoot(),
		CGIObject => $q,
		REF       => scalar $q->param('ref') || "",
		IS_AJAX   => $is_ajax,
	);

    
	$form->addfields({NAME=>"id",       FIELD=>"id",  TYPE=>"id"}                );

	$form->addfields({NAME=>"Название", FIELD=>"name",TYPE=>"text", IS_NOTNULL=>1});
	$form->addfields({NAME=>"Url",      FIELD=>"url", TYPE=>"text", IS_NOTNULL=>1});

    #дополнительные поля
    $form->addfields({NAME=>"Открывать в новом окне",  FIELD=>"target",  TYPE=>"checkbox", IS_NOTNULL=>0});
    #$form->addfields({NAME=>"Элемент активен",      FIELD=>"inactive",TYPE=>"checkbox", IS_NOTNULL=>0});

    $form->addfields({NAME=>"parent_id",   FIELD=>"parent_id",   TYPE=>"hidden",HIDE=>1});
    $form->addfields({NAME=>"link_id",     FIELD=>"link_id",     TYPE=>"hidden",HIDE=>1});
    $form->addfields({NAME=>"subsite_id",  FIELD=>"subsite_id",  TYPE=>"hidden",HIDE=>1});
    
    $form->addfields({NAME=>"node_id",     FIELD=>"node_id",     TYPE=>"text",HIDE=>0,READONLY=>1});
    $form->addfields({NAME=>"hint_node_id",FIELD=>"hint_node_id",TYPE=>"text",HIDE=>0,READONLY=>1});


    $form->param("id",$id);

    $form->loadData() or return $self->error($form->getError());
    
    $form->setcontainer('tree_form'.$id);

    my $subsiteId = $form->getParam('subsite_id');    

    $form->setTitle("Редактирование пункта меню '".$form->getParam('name')."'");
    
    #Проверяем наличие связанных элементов, делаем их загрузку
	my $linkedNodes = {};
	if ($self->app()->confParam("CMS.hasSubsites")) {
		## Загружаем список связанных родителей
		my $sql = "select
				ng_subsites.id as subsite_id,
				ng_subsites.name as subsite_name,
				ng_lang.id as lang_id,
				ng_lang.name as lang_name,
				ng_lang.img as lang_img,
				$table.id as node_id,
				$table.name as node_name,
				$table.url as node_url
			from
				ng_subsites,
				ng_lang,
				$table
			where
                $table.link_id = ?
				and $table.subsite_id = ng_subsites.id
				and ng_lang.id = ng_subsites.lang_id";
		my $sth=$self->dbh()->prepare($sql) or return $self->error($DBI::errstr);    
		$sth->execute($form->getParam('link_id')) or return $self->error($DBI::errstr);
		$linkedNodes = $sth->fetchall_hashref(['subsite_id']) or return $self->error($DBI::errstr);
		$sth->finish();
		return $self->error("Загрузка связанных элементов меню: Обнаружено нарушение структуры данных в БД (несовпадают link_id,lang_id), страница - родитель не найдена") unless scalar keys %{$linkedNodes};
	}
    else {
        $linkedNodes->{$subsiteId} = {
            subsite_id => $subsiteId,
            node_id => $id,
        };
    };

    my $hasErrors = 0;    
    if ($fa) {
        $form->setFormValues();
        #делаем проверку ввода
        $form->StandartCheck();
    };
    

	if (scalar keys %{$linkedNodes} > 1) {  #Есть связанные элементы
        #Добавляем поле для отображения связанных элементов
        my $lf = $form->addfields({
            NAME=>"Связанные элементы, выбирайте чо добавлять",
            FIELD=>"linked",
            TYPE=>"checkbox",
            IS_NOTNULL=>1,
            TEMPLATE => "admin-side/common/menu/editlinkelem.tmpl",
            #CLASS    => "",
        });

        #Накачиваем поле данными
        my @le = ();
        foreach my $ssId (keys %{$linkedNodes}) {
            my $elem = $linkedNodes->{$ssId};
            my $key = $lf->{FIELD}."_".$form->getComposedKeyValue()."_".$subsiteId;
            $elem->{KEY} = $key;
            $elem->{ERRORMSG} = "";
            next if ($elem->{subsite_id} == $subsiteId);

            if ($fa) {
                #Обрабатываем POST
                my $name = $q->param($key."_name");
                my $url = $q->param($key."_url");
                
                $elem->{NAME} = $name;
                $elem->{URL} = $url;
                
                unless ($name && $url) {
                    $hasErrors = 1;
                    $elem->{ERRORMSG} = "Не указано название или URL пункта меню";
                };
            }
            else {
                #Выгружаем из БД
                $elem->{NAME} = $elem->{node_name};
                $elem->{URL} = $elem->{node_url};
            };
            push @le,$elem;
        };
        $lf->{LINKED_ELEMENTS} = \@le;
	};
	
	if ($fa eq "update") {
		if (!$form->hasErrors() && !$hasErrors) {
            $form->updateData() or return $self->error("Не удалось обновить данные: ".$form->getError());
            
    		#Обновляем связанные элементы
            my $updSth = $self->dbh()->prepare("update $table set name = ?, url = ? where id = ?") or return $self->error("SQL error: ". $DBI::errstr);
            foreach my $ssId (keys %{$linkedNodes}) {
                my $elem = $linkedNodes->{$ssId};
                #my $em = escape_js($elem->{ERRORMSG});
                next if ($elem->{subsite_id} == $subsiteId);
                
                $updSth->execute($elem->{NAME},$elem->{URL},$elem->{node_id}) or return $self->error("Error executing update SQL: ". $DBI::errstr);
            };
            $updSth->finish();
            return $self->fullredirect($baseUrl.$subUrl."?nodeid=".$id);
        }
		elsif ($is_ajax) {
			#Форма уже отрисована "как надо", выводим ошибки частичным JS
            my $error = "";
            if (scalar keys %{$linkedNodes} > 1) {
                $error .= "<script type='text/javascript'>";
                foreach my $ssId (keys %{$linkedNodes}) {
                    my $elem = $linkedNodes->{$ssId};
                    my $em = escape_js($elem->{ERRORMSG});
                    
                    next if ($elem->{subsite_id} == $subsiteId);
                    if ($em) {
                        $error .= "parent.document.getElementById('error_$ssId').innerHTML='$em';\n";
                        $error .= "parent.document.getElementById('errortr_$ssId').style.display='';\n";
                    }
                    else {
                        $error .= "parent.document.getElementById('error_$ssId').innerHTML='';\n";
                        $error .= "parent.document.getElementById('errortr_$ssId').style.display='none';\n";
                    };
                };
                $error .= "</script>";
            };
            $error .= $form->ajax_showerrors();
            return $self->output($error);
		};
	};

	my $tmpl = $self->app()->gettemplate("admin-side/common/universalform.tmpl")  || return $self->showError();
	$form->print($tmpl) or return $self->error($form->getError());
	my $tmp=$tmpl->output();

	if ($fa && $is_ajax) {
		return $self->output("<script>parent.document.getElementById('tree_form".$id."').innerHTML='".escape_js($tmp)."';</script>");
	}
	else {
		return $self->output($tmp);
	};	
};


#собственно вывод имеющейся структуры меню
sub showFaceMenu {
	my $self=shift;
	my $action=shift;
	$self->opentemplate("admin-side/common/menu/tree.tmpl");
    
    my $tree = NG::Nodes->new();
	$tree->initdbparams(
        db     => $self->db(),
        table  => $self->{_table},
        fields => "name,url,node_id,hint_node_id,target,inactive",
    );

    my $nodeId = $self->q()->param('nodeid') || 0;

	#TODO: переименовать метод.
    $tree->loadPartOfTree2(98,{SELECTEDNODE=>$nodeId, OPEN_LEVELS=> 3}); #TODO: OPEN_LEVELS в конфигурацию/init() ?

	
#TODO: пробежаться траверсом и сформировать управляющие элементы
#$tree->printToDivTemplate($self->tmpl(),'DIVTREE');
	$tree->printToDivTemplate($self->tmpl(),'TREE',$nodeId);

#my $tree1 = NG::Nodes->new();
#$tree1->initdbparams(
#    db     => $self->db(),
#    table  => "ng_sitestruct", #$self->{_table},
#    fields => "name,url",
#);
#$tree1->loadtree(98);
#$tree1->printToTemplate($self->tmpl(),'TREE1');

    return $self->output($self->tmpl()->output());
};

sub _makeEvent {
    my $self = shift;
    my $ename = shift;
    my $eopts = shift;
    
    my $event = NG::Module::Menu::Event->new($self,$ename,$eopts);
    $self->app()->processEvent($event);
};


sub _moveNode {
	my $self = shift;
    my $dir = shift;
	my $action = shift;
	my $is_ajax = shift;
    
	NG::Nodes->initdbparams(
        db     => $self->db(),
        table  => $self->{_table},
        fields => "node_id",
    );
   
    my $id =  $self->q()->param('id');    
	my $tree = NG::Nodes->loadNode($id) or return $self->error("No node found");

    my $partner = undef;
    if ($dir eq "up") {
        my $prevso = $tree->getPrevSiblingOrder();
        if ($prevso) {
            $partner = NG::Nodes->loadNode(tree_order => $prevso);
            $tree->DBmoveNode(before=>$partner);
            $self->_makeEvent("swapNode",{NODE=> $tree->getNodeValue(), ACTION=> "before", PARTNER=> $partner->getNodeValue() });
        };
    }
    elsif ($dir eq "down") {
        my $nextso = $tree->getNextSiblingOrder();
        if ($nextso) {
            $partner = NG::Nodes->loadNode(tree_order => $nextso);
            $tree->DBmoveNode(after=>$partner);
            $self->_makeEvent("swapNode",{NODE=> $tree->getNodeValue(), ACTION=> "after", PARTNER=> $partner->getNodeValue() });
        };
    };
    #$self->_makeEvent('movenode',{DIR=>$dir, PAGEOBJ=>$pageObj});
    #$self->redirect("/admin-side/pages/$parent_pageId/struct/");
	my $baseUrl = $self->getBaseURL();
	my $subUrl = $self->getSubURL();
    return $self->fullredirect($baseUrl.$subUrl."?nodeid=".$tree->{_parent_id});
};

sub moveUp {
    my $self = shift;
    return $self->_moveNode("up",@_);
};

sub moveDown {
    my $self = shift;
    return $self->_moveNode("down",@_);
};

sub adminModule {
	my $self    = shift;
	my $is_ajax = shift;
	return $self->run_actions($is_ajax);
};

sub processEvent {
    my $self = shift;
    my $event = shift;
    
    my $opts = $event->options();
    
    return unless ($event->isa("NG::SiteStruct::Event"));

	NG::Nodes->initdbparams(
		db     => $self->db(),
		table  => $self->{_table},
		fields => "node_id,name,url,subsite_id,link_id",
	);

	if ($event->name() eq "swapNode") {
        return unless ($opts->{NODE}->{id} && $opts->{PARTNER}->{id});
        
        unless ($opts->{ACTION} eq "before" || $opts->{ACTION} eq "after") {
            print STDERR "Invalid ACTION ".$opts->{ACTION}. " in NG::Sitestruct::Event";
            return;
        };
		
        my $node = NG::Nodes->loadNode(node_id => $opts->{NODE}->{id}) or return ;
        my $pnode= NG::Nodes->loadNode(node_id => $opts->{PARTNER}->{id}) or return;

        if ($node->{_parent_id} == $pnode->{_parent_id}) {
            $node->DBmoveNode($opts->{ACTION} => $pnode) ;
        };
    }
	elsif ($event->name() eq "addlinkednodes") {
		#opts->VARIANT
		#opts->NODES = [{PAGEOBJ=> ... , PREV_SIBLING_ID=> ... }]
		
		return unless ref $opts->{NODES} eq "ARRAY";
		
		my $linkId = $self->db()->get_id($self->{_table}.'.link_id') or die "Can`t get id for ".$self->{_table}." (link_id)";
		
		foreach my $node (@{$opts->{NODES}}) {
			#Ищем связь ноды родителя новой ноды с элементом меню или выходим
	        my $parent = NG::Nodes->loadNode(node_id => $node->{PAGEOBJ}->getParentPageId()) or next;
			my $nodeRow = $node->{PAGEOBJ}->getPageRow();
			my $newMenuElem = {
				name => $nodeRow->{name},
				node_id => $node->{PAGEOBJ}->getPageId(),
				subsite_id => $node->{PAGEOBJ}->getSubsiteId(),
                url => $nodeRow->{url},
				link_id => $linkId,
			};
			my $afterNode = undef;
			if ($node->{PREV_SIBLING_ID}) {
				$afterNode = NG::Nodes->loadNode(node_id=>$node->{PREV_SIBLING_ID});
			};
			if ($afterNode) {
				$parent->DBaddChild($newMenuElem,{AFTER=>$afterNode});
			}
			else {
				$parent->DBaddChild($newMenuElem);
			};
		};
	}
	elsif ($event->name() eq "deletenode") {
		#opts->{PAGEOBJ}
		my $elem = NG::Nodes->loadNode(node_id => $opts->{PAGEOBJ}->getPageId()) or return;
		if ($elem->getFirstChildOrder()) {
print STDERR "TODO: what to do for nodes with childs ?";
			return;
		};
		$elem->DBdelete();
	};
};


return 1;

