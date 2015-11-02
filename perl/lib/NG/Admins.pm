package NG::Admins;
use strict;

use NG::Module;

use vars qw(@ISA);
@ISA = qw(NG::Module);

sub moduleTabs {
	return [
		{HEADER=>"Администраторы",URL=>"/"},
		{HEADER=>"Группы",URL=>"/groups/", PRIVILEGE=>"GROUP"},
	];
};

sub moduleBlocks {
	return [
		{URL=>"/",       BLOCK=>"NG::Admins::Block", TYPE=>"moduleBlock"},
        {URL=>"/groups/",BLOCK=>"NG::Admins::Groups",TYPE=>"moduleBlock", PRIVILEGE=>"GROUP"},
	];
};

sub modulePrivileges {
    return [
        {PRIVILEGE=>"addPriv",NAME=>"Добавление"},
        {PRIVILEGE=>"updatePriv",NAME=>"Редактирование"},
        {PRIVILEGE=>"deletePriv",NAME=>"Удаление"},
        {PRIVILEGE=>"GROUP",NAME=>"Группы"},
    ];
};


package NG::Admins::Block;
use strict;

use NGService;
use NSecure;
use NG::Form;
use NHtml;
use NG::Module;
use URI::Escape;

use NG::Module::List;

use vars qw(@ISA);
@ISA = qw(NG::Module::List);

my $root_group_name = "Глобальные администраторы";

sub config  {
    my $self = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $admin = $self->cms()->_getAdmin();

    $self->{_table} = "ng_admins";
    $self->{_listtemplate} = "admin-side/admin/adminlist.tmpl";
    
    $self->fields(
        {FIELD=>'id', TYPE=>'id',NAME=>'Код записи'},
        {FIELD=>'login', TYPE=>'text',NAME=>'Логин', IS_NOTNULL=>1, UNIQUE=>1,
            MESSAGES=>{NOT_UNIQUE=>"Администратор с таким логином уже существует"},
        },
        {FIELD=>'password', TYPE=>'password',NAME=>'Пароль', IS_NOTNULL=>1,
            MESSAGES=>{IS_NULL=>"Не указан пароль"},
        },
        {FIELD=>'password_repeat', TYPE=>'password',NAME=>'Подтвердите пароль', IS_NOTNULL=>1,IS_FAKEFIELD=>1,
            MESSAGES=>{IS_NULL=>"Не указано подтверждение пароля"},
        },
		{FIELD=>'fio', TYPE=>'text',NAME=>'Фио', IS_NOTNULL=>1,
            MESSAGES=>{IS_NULL=>"Не указана фамилия админа"},
        },
        {FIELD=>'group_id',TYPE=>"select",NAME=>"Группа",IS_NOTNULL=>1,CHOOSE=>1,SELECT_OPTIONS=>[],TEMPLATE=>"admin-side/admin/admingroup.tmpl"},
        {FIELD=>'level',TYPE=>"select",NAME=>"Уровень",SELECT_OPTIONS=>[],IS_NOTNULL=>1,},
    );
    
    # Списковая
    $self->listfields([
        {FIELD=>'login'},
        {FIELD=>'fio'},
    ]);

    $self->formfields(
        {FIELD=>'id',},
        {FIELD=>'login',},
        {FIELD=>'password',},
        {FIELD=>'password_repeat',},
        {FIELD=>'fio',},
        {FIELD=>'group_id'},
        {FIELD=>'level'},
    );
     
    $self->editfields([
        {FIELD=>'id'},
        {FIELD=>'login',READONLY=>1},
        {FIELD=>'fio'},
        {FIELD=>'group_id'},
        {FIELD=>'level'},
    ]);
    my $df = $self->_getDF();
    $df->{EDITTITLE} = "Редактирование информации об администраторе {login}:";
    $df->{TITLE} = "Добавление нового администратора:";

    $self->additionalForm({
        PREFIX=>"passwd",
        FIELDS=>[
            {FIELD=>'id'},
            {FIELD=>'login', HIDE=>1},
            {FIELD=>'password'},
            {FIELD=>'password_repeat'},
        ],
        EDITLINKNAME => "Изменить пароль",
        TITLE=>"Изменение пароля {login}",
#         ADDPRIVILEGE => "SOMEPRIVILEGE",
#         UPDATEPRIVILEGE => "SOMEOTHERPRIVILEGE",
		UPDATEPRIVILEGE => {PRIVILEGE=>"updatePriv", NAME=>"Имя для админки привилегий"},
    });
   
    $self->order("login");
    
   
	$self->setAddPriv({PRIVILEGE=>"addPriv"});
	$self->setEditPriv({PRIVILEGE=>"updatePriv"});
	$self->setDeletePriv({PRIVILEGE=>"deletePriv"});
};

sub checkBeforeDelete {
	my $self = shift;
	my $id = shift;
    
	my $dbh = $self->db()->dbh();
	if (is_valid_id($id)) {
		my $sth = $dbh->prepare("select id,level,group_id from ng_admins where id=?") or return $self->error($DBI::errstr);
		$sth->execute($id) or return $self->error($DBI::errstr);
		my $admin = $sth->fetchrow_hashref();
		$sth->finish();
		return $self->error("Не найден администратор") if (!$admin);
		my ($onlevel,$underlevel);
		if ($admin->{level} == 0) {
			$sth = $dbh->prepare("select (select count(*) from ng_admins where group_id=0 and level=0),(select count(*) from ng_admins where level>0);") or return $self->error($DBI::errstr);
			$sth->execute() or return $self->error($DBI::errstr);
			($onlevel,$underlevel) = $sth->fetchrow();
			$sth->finish();			
		} else {
			$sth = $dbh->prepare("select (select count(*) from ng_admins where group_id=? and level=?),(select count(*) from ng_admins where group_id=? and level>?);") or return $self->error($DBI::errstr);
			$sth->execute($admin->{group_id},$admin->{level},$admin->{group_id},$admin->{level}) or return $self->error($DBI::errstr);
			($onlevel,$underlevel) = $sth->fetchrow();
			$sth->finish();			
		};
		if ($onlevel == 1 && $underlevel != 0) {
			return $self->error("Нельзя удалить администратора. Сначала удалите всех администраторов уровнем ниже"); 
		};
	} else {
		return $self->error("Не найден администратор");
	};
	return NG::Block::M_OK;
};

sub beforeDelete { 
	my $self = shift;
    my $id = shift;
	
	if (is_valid_id($id)) {
		my $dbh = $self->db()->dbh();
#$dbh->do("delete from ng_subsite_privs where admin_id=?",undef,$id) or return $self->error($DBI::errstr);
#$dbh->do("delete from ng_module_privs where admin_id=?",undef,$id) or return $self->error($DBI::errstr);
#$dbh->do("delete from ng_page_privs where admin_id=?",undef,$id) or return $self->error($DBI::errstr);
	};
	return NG::Block::M_OK;
};

sub _getGroupsList {
    my $self = shift;
    my $admin = shift;
    my $group_id = shift;
    
    my $sth = undef;
    my $dbh = $self->db()->dbh();
    my @groups = ();
	if ($admin->{level} == 0) {
		$sth = $dbh->prepare("select id,name from ng_admin_groups order by name") or return $self->error($DBI::errstr);
		$sth->execute()  or return $self->error($DBI::errstr);
	} else {
		$sth = $dbh->prepare("select id,name from ng_admin_groups where id=? order by name") or return $self->error($DBI::errstr);
		$sth->execute($admin->{group_id})  or return $self->error($DBI::errstr);		
	};
    my $sRow = undef;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{ID} = delete $row->{id};
        $row->{NAME} = delete $row->{name};
        $sRow = $row if (defined $group_id && $row->{ID} == $group_id);
        if ($row->{ID} == 0 ) {
            unshift @groups,$row;
            next;
        };
        push @groups, $row;
    };
    $sth->finish();
    return ([],undef) unless scalar @groups;
    $sRow = $groups[0] unless ($sRow);
    $sRow->{SELECTED} = 1;
    return (\@groups,$sRow);
};

sub _getLevelsList {
    my $self = shift;
    my $admin = shift;
    my $group_id = shift;
	
warn "_getLevelsList(): ADMIN $admin  GROUPID $group_id";
    my $sth = undef;
    my $dbh = $self->db()->dbh();
    my @levels = ();
    if ($admin->{level} == 0) {
    	$sth = $dbh->prepare("select distinct(level) as id from ng_admins where group_id=? order by level") or return $self->error($DBI::errstr);
    	$sth->execute($group_id)  or return $self->error($DBI::errstr);
    } else {
    	$sth = $dbh->prepare("select distinct(level) as id from ng_admins where group_id=? and level>? order by level") or return $self->error($DBI::errstr);
    	$sth->execute($group_id,$admin->{level})  or return $self->error($DBI::errstr);		
    };
    my $maxlevel = 0;
    while (my $row = $sth->fetchrow_hashref) {
    	push @levels, {ID=>$row->{id},NAME=>$row->{id}};
    	$maxlevel = $row->{id};
    };
    $sth->finish();	
    if ($group_id > 0) {
        $maxlevel = $admin->{level} if (!scalar @levels);
        $maxlevel = ($maxlevel == 0)?1:$maxlevel+1;
        push @levels, {ID=>$maxlevel,NAME=>$maxlevel};		    
    } else {
        push @levels, {ID=>0,NAME=>0} if (!scalar @levels);		    
    };
    return @levels;
};

sub _checkValidGroupId {
    my $self = shift;
    my $admin = shift;
    my $group_id = shift;
    
    my $sth = undef;
    my $dbh = $self->db()->dbh();
    return 1 if ($admin->{level} == 0);
    $sth = $dbh->prepare("select 1 from ng_admins where id=? and group_id=?") or die $DBI::errstr;
    $sth->execute($admin->{id},$group_id) or die $DBI::errstr;
    my ($result) = $sth->fetchrow();
    $sth->finish();
    return $result == 1?1:0;
};

sub _checkValidLevel {
    my $self = shift;
    my $admin = shift;
    my $group_id = shift;
    my $level = shift;
    my $dbh = $self->db()->dbh();

    my $min = $admin->{level} + 1;
    $min = 0 if ($admin->{level} == 0);

    my $sth = $dbh->prepare("select max(level)+1 from ng_admins where group_id=?") or die $DBI::errstr;
    $sth->execute($group_id) or die $DBI::errstr;
    my ($max) = $sth->fetchrow();
    $sth->finish();

    $max = 1 if (is_empty($max));

    return 1 if ($min==$max && $max==$level && $level==1);
    return ($level<=$max && $level>=$min?1:0);
};


sub buildList {
	my $self = shift;
	
	my $admin  = $self->cms()->_getAdmin();
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $group_id = $q->param("group_id");
    #$group_id = undef if (!is_valid_id($group_id) && $group_id!=0);
    $group_id = $admin->{group_id} if (!is_valid_id($group_id) && $group_id ne 0);
    
    my $baseUrl = $self->getBaseURL();
    my $u = $q->url(-query=>1);
    $u =~ s/_ajax=1//;
    $u = uri_escape($u);
    
    #Загружаем доступные группы
    my ($groups, $sGroup) = $self->_getGroupsList($admin,$group_id);
    return $self->error("Нет ни одной доступной группы") unless $sGroup;
    $group_id = $sGroup->{ID};
	
	#Загружаем доступных админов
	my @admins = ();
	my $sth =undef;
	if ($admin->{level} == 0) {
		$sth = $dbh->prepare("select a.id,a.login,a.fio,a.group_id,a.level,g.name as group_name from ng_admins a left join ng_admin_groups g on (g.id=a.group_id) where a.group_id=? order by a.group_id,a.level,a.fio") or return $self->error($DBI::errstr);
		$sth->execute($group_id)  or return $self->error($DBI::errstr);
	} else {
		$sth = $dbh->prepare("select a.id,a.login,a.fio,a.group_id,a.level,g.name as group_name from ng_admins a left join ng_admin_groups g on (g.id=a.group_id) where a.group_id=? and level>? order by a.group_id,a.level,a.fio") or return $self->error($DBI::errstr);
		$sth->execute($group_id,$admin->{level})  or return $self->error($DBI::errstr);		
	};		
	my $current_group = undef;
	my $current_level = undef;
	while (my $row = $sth->fetchrow_hashref()) {
		if ($row->{group_id} != $current_group || !defined $current_group) {
			$row->{newgroup} = 1;
			$row->{newlevel} = 1;
			$current_group = $row->{group_id};
			$current_level = $row->{level};
		} elsif ($row->{level} != $current_level || !defined $current_level) {
			$row->{newlevel} = 1;
			$current_level = $row->{level};
		};

		if ($self->hasEditPriv($self->_getDF())) {
			$row->{EDIT_URL} = "$baseUrl?action=updf&id=".$row->{id}."&ref=$u";
			$row->{AJAX_EDIT_URL} = "$baseUrl?action=updf&_ajax=1&id=".$row->{id}."&ref=$u";
			push @{$row->{EXTRA_LINKS}},{
                NAME=>"Изменить пароль",
                URL=>$baseUrl."?action=updf&_form=passwd&id=".$row->{id}."&ref=$u",
                AJAX_URL=>getURLWithParams($baseUrl."?action=updf&_form=passwd&id=".$row->{id}."&ref=$u","_ajax=1"),
                AJAX_FORM_CONTAINER => "formb_".$row->{id},	    
            };
		};
		
		if ($self->hasDeletePriv()) {
            $row->{DELETE_URL} = "$baseUrl?action=delete&id=".$row->{id}."&ref=$u";
            $row->{AJAX_DELETE_URL} = "$baseUrl?action=delete&_ajax=1&id=".$row->{id}."&ref=$u";		
		};
		push @admins, $row;
	};
	$sth->finish();
	
    $groups = [] unless scalar @$groups > 1;
	$self->tmpl()->param(
        SGROUP => $sGroup,
        GROUPS => $groups,
        ADMINS => \@admins,
        URL => $baseUrl,
	);
	
	my $df = $self->_getDF();
	if ($self->hasAddPriv($df)) {
		unshift @{$self->{_topbar_links}}, {
				NAME    => $df->{ADDLINKNAME},
				URL     => getURLWithParams($baseUrl,"action=insf",$self->getFilterParam(),$self->getFKParam(),"ref=$u"),
				AJAX_URL=> getURLWithParams($baseUrl,"action=insf",$self->getFilterParam(),$self->getFKParam(),"ref=$u","_ajax=1"),
		};
	    $self->tmpl()->param(
	    	TOP_LINKS => $self->{_topbar_links},
	    );
	};
	
	return NG::Block::M_OK;
};

sub afterFormLoadData {
    my $self = shift;
    my $form = shift;
    my $action = shift;
    
    if ($form->prefix() eq "passwd") {
        $form->param("password","");
    };

    $self->_fillDicts($form);
    
    return 1;
};

sub afterSetFormValues {
    my $self = shift;
    my $form = shift;
    my $fa   = shift;
    
    $self->_fillDicts($form);
    return 1;
};

sub _fillDicts {
    my $self = shift;
    my $form = shift;
    
    my $fLevel = $form->getField("level") or return $form->error("No field 'level' found");
    my $fGroupID = $form->getField("group_id") or return $form->error("No field 'group_id' found");
    
    my $admin = $self->cms()->_getAdmin();
    my ($groups,$sGroup) = $self->_getGroupsList($admin,$fGroupID->value());
    
    $fGroupID->setSelectOptions($groups);
    
    my @levels = $self->_getLevelsList($admin,$sGroup->{ID});
    $fLevel->setSelectOptions(\@levels);
};

sub checkData {
    my $self = shift;
    my $form = shift;
    my $action = shift;
    
    if ($form->prefix() eq "passwd" || $action eq "insert") { #В update нет обновления паролей
        #TODO: добавить проверку на наличие права изменения пароля у данного пользователя.
        my $password = $form->getParam("password");
        my $password_repeat = $form->getParam("password_repeat");
        if ($password ne $password_repeat) {
            $form->pusherror("password_repeat","Пароли не совпадают");
        };
        return 1 if $form->prefix() eq "passwd";  #Не надо проверять группы если производится смена пароля :-)
    };
    
    my $admin = $self->cms()->_getAdmin();
    
    #my $fLevel = $form->getField("level") or return $form->error("No field 'level' found");
    my $fGroupID = $form->getField("group_id") or return $form->error("No field 'group_id' found");
    
    if (!$self->_checkValidGroupId($admin,$fGroupID->value())) {
        $fGroupID->setError("Некорректная группа");
    #} elsif (!$self->_checkValidLevel($admin,$form->_getfieldhash("group_id")->{VALUE},$form->_getfieldhash("level")->{VALUE}) && defined $q->param("choose_group_id")) {
    #    $form->pusherror("level","Выбранный ранее уровень отсутствует в выбранной группе. Уточните уровень.");
    #    my @levels = $self->_getLevelsList($admin,$form->_getfieldhash("group_id")->{VALUE});
    #    $form->set_selectoptions("level",\@levels);
    };

    return NG::Block::M_OK;
};

sub doFormAction {
    my ($self,$form,$fa,$is_ajax) = @_;
    
    return $self->SUPER::doFormAction($form,$fa,$is_ajax) if $fa ne "group_id_choose";
    
    my $fLevel = $form->getField("level") or return $form->error("No field 'level' found");
    my $fGroupID = $form->getField("group_id") or return $form->error("No field 'group_id' found");
    
    $fLevel->setFormValue();
    $fGroupID->setFormValue();
    
    my $admin = $self->cms()->_getAdmin();
    if (!$self->_checkValidLevel($admin,$fGroupID->value(),$fLevel->value())) {
        $fLevel->setError("Выбранный ранее уровень отсутствует в выбранной группе. Уточните уровень.");
    };
    
    my ($groups,$sGroup) = $self->_getGroupsList($admin,$fGroupID->value());
    $fGroupID->setSelectOptions($groups);	
    
    my @levels = $self->_getLevelsList($admin,$fGroupID->value());
    $fLevel->setSelectOptions(\@levels);
    
    return 1 unless ($is_ajax);
    
    my $js = "<script type='text/javascript'>";
    $js .= $fLevel->getJSSetValue();
    $js .= $fGroupID->getJSSetValue();
    
    my $key_value = $form->getComposedKeyValue();
    my $em = escape_js $fLevel->error();
    if ($em) {
        $js .= "parent.document.getElementById('error_level$key_value').innerHTML='$em';";
        $js .= "parent.document.getElementById('error_level$key_value').style.display='block';\n";
    }
    else {
        $js .= "parent.document.getElementById('error_level$key_value').innerHTML='';";
        $js .= "parent.document.getElementById('error_level$key_value').style.display='none';\n";
    };
    $js .= "</script>\n";
    return $js;
};

package NG::Admins::Groups;
use strict;

use NG::Module::List;

use vars qw(@ISA);
@ISA = qw(NG::Module::List);

sub config  {
    my $self = shift;
    
    $self->{_table} = "ng_admin_groups";
    
    $self->fields(
        {FIELD=>'id', TYPE=>'id',NAME=>'Код записи'},
        {FIELD=>'name', TYPE=>'text',NAME=>'Название', IS_NOTNULL=>1},
    );
    # Списковая
    $self->listfields([
        {FIELD=>'name'},
    ]);
    # Формовая часть
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'name'},
    );
    $self->order({DEFAULT=>"ASC",DEFAULTBY=>"ASC",FIELD=>"name",DESC=>"name desc",ASC=>"mail asc",});
    $self->pushWhereCondition("id>0");
    $self->{_recordname} = "группы";
};

return 1;