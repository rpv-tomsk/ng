package NG::ModulePrivs;
use strict;

use NG::Module;
use Data::Dumper;

use vars qw(@ISA);
@ISA = qw(NG::Module);


sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    
    $self->{_l1} = {}; #$checkPrivs->{groupID|adminID}->{$mId}->{$privilege} = $active;
    $self;
};

sub moduleTabs {
    return [
        {HEADER=>"Модульные привилегии",URL=>"/"},
    ];
};

sub moduleBlocks {
    return [
        {URL=>"/",BLOCK=>"NG::ModulePrivs::Block",TYPE=>"moduleBlock"},
    ]
};

sub _loadPrivileges {
    my $self = shift;
    my %att = (@_);  #ADMIN_ID GROUP_ID MODULE_ID
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    
    my $mId = $att{MODULE_ID};
    my $adminId = $att{ADMIN_ID};
    exists $att{GROUP_ID} or die "No GROUP_ID";
    my $groupId = $att{GROUP_ID};
    
    my $where = "";
    my @params = ();
    if ($adminId) {
        $where .= " (admin_id = ? or group_id = ?) ";
        push @params, $adminId;
        push @params, $groupId;
    }
    else {
        $where .= " (group_id = ?) ";
        push @params, $groupId;
    };
    if ($mId) {
        $where .= " and module_id = ? ";
        push @params, $mId;
    };
   
    my $sql = "select module_id,admin_id,group_id,privilege,active from ng_module_privs where $where";
    my $sth = $dbh->prepare_cached($sql) or die $DBI::errstr;
    $sth->execute(@params) or die $DBI::errstr;
    
    my $l = $self->{_l1}; #$checkPrivs->{groupID|adminID}->{$mId}->{$privilege} = $active;
    while (my $row=$sth->fetchrow_hashref()) {
        die "m_privs: admin_id && group_id" if ($row->{admin_id} && defined $row->{group_id});
        die "m_privs: no admin_id or group_id" unless ($row->{admin_id} || defined $row->{group_id});
        die "m_privs: no module_id value" unless $row->{module_id};
        die "m_privs: no privilege value" unless $row->{privilege};
        die "m_privs: no active value" unless defined $row->{active};
        
        if ($row->{admin_id}) {
            $l->{"admin".$row->{admin_id}}->{$row->{module_id}}->{$row->{privilege}} = $row->{active};
        }
        else {
            $l->{"group".$row->{group_id}}->{$row->{module_id}}->{$row->{privilege}} = $row->{active};
        };
    };
    $sth->finish();
};

sub loadAdminPrivileges {
    my $self = shift;
    my %opts = (@_);

    my $adminId = $opts{ADMIN_ID} or die("loadAdminPrivileges(): ADMIN_ID is missing");
	defined $opts{GROUP_ID} or die("loadAdminPrivileges(): GROUP_ID is missing");
    my $groupId = $opts{GROUP_ID};
    $self->_loadPrivileges(ADMIN_ID=>$adminId, GROUP_ID=>$groupId);
};

sub modulePrivileges {
    my $self = shift;
    return [
        {PRIVILEGE=>"MODIFY", NAME=>"Назначение прав"},
    ];
};

sub hasModulePrivilege {
    my $self = shift;
    my %att = (@_);
    
    my $cms = $self->cms();

    my $adminId   = $att{ADMIN_ID} or return $cms->error("hasModulePrivilege(): Не указан ADMIN_ID");
    defined $att{GROUP_ID} or return $cms->error("hasModulePrivilege(): Не указан GROUP_ID");
    my $groupId   = $att{GROUP_ID};
    return 1 unless $groupId;
    my $moduleId  = $att{MODULE_ID} or return $cms->error("hasModulePrivilege(): MODULE_ID is missing");
    my $priv      = $att{PRIVILEGE} or return $cms->error("hasModulePrivilege(): Не указана проверяемая привилегия");
    
    my $L1 = $self->{_l1};
    my $ac = undef;
    
    unless (exists $L1->{"admin$adminId"}->{$moduleId} && exists $L1->{"group$groupId"}->{$moduleId}) {
        $self->_loadPrivileges(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,MODULE_ID=>$moduleId);
    };

    $ac = $L1->{"admin$adminId"}->{$moduleId}->{$priv} if ($adminId);
    $ac = $L1->{"group$groupId"}->{$moduleId}->{$priv} if (defined $groupId && !defined $ac) ;

$moduleId||="";
$ac||="undef";
#print STDERR "hasModulePrivilege() a-$adminId-g-$groupId-m-$moduleId-p-$priv-R=$ac-";

    return 0 unless defined $ac;
return 0 if $ac eq "undef";
    return $ac;
};

package NG::ModulePrivs::Block;
use strict;
use vars qw(@ISA);

use NG::Form;
use NG::Nodes;
use NSecure;
use NHtml;
use NGService;
use Data::Dumper;

use NG::Block;
@ISA = qw(NG::Block);

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    $self->register_ajaxaction("","showTab");
    $self->register_ajaxaction("addadmin","addSubj");
    $self->register_ajaxaction("addgroup","addSubj");
    #
    $self->{_mId} = undef;
    $self;
};


sub blockAction {
    my $self = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
    #my $q   = $cms->q();
    ##my $showAll = $q->param('all') || 0;
    ##$self->{_showAll} = 0;
    ##$self->{_showAll} = 1 if ($showAll == 1);
    ##$self->{_pageURL} = $self->getBaseURL();
    ##$self->{_pageMode} = 0;
    #
    #my $action = $q->param('action') || "";
    #return $self->switchSubsite($is_ajax) if $action eq "switchsubsite";
    #
    my $subUrl = $self->getSubURL();
    
    return $self->showModulesList($is_ajax) unless $subUrl;
    return $cms->error("Некорректный код модуля") if $subUrl !~ /^(\d+)(?:\/([^\/]+))?\/$/;
    $self->{_mId} = $1;
    #$self->{_tab} = $2 || "local"; #local,inheritable,rules
    #
    ##$self->{_pageURL} = $self->getBaseURL().$self->{_pageId}."/";
    return $self->run_actions($is_ajax);
};

sub showModulesList {
    my $self = shift;
    
    #my $m   = $self->getModuleObj();
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    
    my @modules = ();
    my $sth = $dbh->prepare("select id,code,module,base,name from ng_modules order by id") or return $cms->error($DBI::errstr);
    $sth->execute() or return $cms->error($DBI::errstr);
    while(my $mRow = $sth->fetchrow_hashref()) {

        my $opts = {};
        $opts->{MODULEROW} = $mRow;
        my $mObj = $cms->getObject($mRow->{module},$opts) or return $cms->error("Can't create module ".$mRow->{module});
        my $mp = $mObj->modulePrivileges();
        next unless defined $mp;
        return $cms->defError("showModulesList():","Вызов modulePrivileges() модуля ".(ref $mObj)." вернул некорректное значение") unless $mp && ref $mp eq "ARRAY";

        my $m = {};
        $m->{ID} = $mRow->{id};
        $m->{NAME} = $mRow->{name};
        $m->{NAME} ||= "Модуль ".$mRow->{module};
        
        push @modules, $m;
    };
    $sth->finish();
    $self->opentemplate("admin-side/common/mprivileges/list.tmpl");
    $self->tmpl()->param(
        BASEURL => $self->getBaseURL(),
        MODULES => \@modules,
    );
    return $self->output($self->tmpl());
};

sub showTab {
    my $self = shift;

    my $m   = $self->getModuleObj();
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q   = $cms->q();
    
    my $mId = $self->{_mId} or die;
    my $adminId = $q->param('adminId');
    $adminId = undef unless is_valid_id($adminId);
    my $groupId = $q->param('groupId');
    $groupId = undef unless is_valid_id($groupId) || $groupId eq 0;
    
    #Ищем модуль, создаем его объект
    my $mRow = $cms->getModuleRow("id=?",$mId) or return $cms->error("Запрошенный модуль $mId не найден");
    my $mObj = $cms->getObject($mRow->{module},{MODULEROW=>$mRow}) or return $cms->error();
    return $cms->error("showTab(): Модуль ".$mRow->{module}." ($mId) не содержит метода modulePrivileges()") unless $mObj->can("modulePrivileges");
    
    my $mp = $mObj->modulePrivileges();
    return $cms->error("showTab(): Модуль ".(ref $mObj)." не использует привилегии") unless defined $mp;
    return $cms->error("showTab(): Вызов modulePrivileges() модуля ".(ref $mObj)." вернул некорректное значение") unless $mp && ref $mp eq "ARRAY";
    unshift @$mp, {PRIVILEGE=>"ACCESS",NAME=>"Доступ к модулю"};
    
    #Проверяем, не требуется ли сделать какое-нибудь действие с привилегиями
    my $do = $q->param("do");
    if ($do) {
        my $priv = $q->param('priv');
        
        my $privRow = undef;
        foreach my $p (@$mp) {
            if ($priv eq $p->{PRIVILEGE}) {
                $privRow = $p;
                last;
            };
        };
        $privRow or return $cms->error("Заданный модуль не содержит заданную привилегию");
        
        #Загружаем старую привилегию. Проверяем наличие.
        my $where = "";
        my @params = ();
        
        if (defined $groupId) {
            my $sth = $dbh->prepare("select id,name from ng_admin_groups where id = ?") or return $cms->error($DBI::errstr);
            $sth->execute($groupId) or return $cms->error($DBI::errstr);
            my $groupRow = $sth->fetchrow_hashref() or return $cms->error("Group Not Found");
            $sth->finish();
            #$name = $groupRow->{name};
            
            $where .= " group_id = ? ";
            push @params, $groupId;
        }
        elsif ($adminId) {
            my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins where id = ?") or return $cms->error($DBI::errstr);
            $sth->execute($adminId) or return $cms->error($DBI::errstr);
            my $adminRow = $sth->fetchrow_hashref() or return $cms->error("Admin Not Found");
            $sth->finish();
            #$name = $adminRow->{fio}." (".$adminRow->{login}.")";
            
            $groupId = $adminRow->{group_id};
            
            $where .= " admin_id = ? ";
            push @params, $adminId;
        }
        else {
            return $cms->error("Отсутствует значение субъекта привилегии");
        };
        
        $where .= " and module_id = ? and privilege = ? ";
        push @params, $mId;
        push @params, $priv;
        
        my $sth = $dbh->prepare_cached("select active from ng_module_privs WHERE $where") or return $cms->error($DBI::errstr);
#print STDERR "$where ".Dumper(@params);
        $sth->execute(@params) or return $cms->error($DBI::errstr);
        my $oldRow = $sth->fetchrow_hashref();
        $sth->finish();
        
        if ($do eq "doallow" || $do eq "dodeny") {
            my $active = 0;
            $active = 1 if $do eq "doallow";
            if ($oldRow) {
                unshift @params, $active;
                $dbh->do("UPDATE ng_module_privs SET active = ? WHERE $where", undef, @params) or return $cms->error($DBI::errstr);
            }
            else {
                my $sql = "INSERT INTO ng_module_privs (";
                if ($adminId) {
                    $sql .= "admin_id,";
                }
                elsif (defined $groupId) {
                    $sql .= "group_id,";
                }
                else {
                    die "Something strange happens";
                };
                $sql .= "module_id,privilege,active) values (?,?,?,?)";
                push @params, $active;
                $dbh->do($sql,undef,@params) or return $cms->error($DBI::errstr);
            };
        }
        elsif ($do eq "dodelete") {
            if ($oldRow) {
                $dbh->do("DELETE FROM ng_module_privs WHERE $where", undef, @params) or return $cms->error($DBI::errstr);
            }
        }
        else {
            die "Something strange happens";
        };
        
        #Загружаем все привилегии
        $m->_loadPrivileges(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,MODULE_ID=>$mId) or return $self->error();
        my $L1 = $m->{_l1}; #$checkPrivs->{groupID|adminID}->{$mId}->{$privilege} = $active;

        my $p = {};
        
        $p->{name} = $privRow->{NAME};
        $p->{name} ||= "Право ".$privRow->{PRIVILEGE};
        $p->{privilege} = $privRow->{PRIVILEGE};
        
        my $ac = undef;
        if ($adminId) {
            $ac = $L1->{"admin$adminId"}->{$mId}->{$privRow->{PRIVILEGE}};
            #$p->{PADMIN_ID} = $adminId if defined $ac;
        };
        if (defined $groupId && !defined $ac) {
            $ac = $L1->{"group$groupId"}->{$mId}->{$privRow->{PRIVILEGE}};
            $p->{pgroupId} = $groupId if defined $ac;
        };
        $p->{active} = $ac;
        
        use NHtml;
        my $json = create_json($p);
        return $cms->exit($json);
    };
    
    
    #Загружаем список всех админов, имеющих права на ноду
    my @admins = ();
    my $found = 0;
    my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins where id in (select admin_id from ng_module_privs where module_id = ? and admin_id is not null)") or return $cms->error($DBI::errstr);
    $sth->execute($mId) or return $cms->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        unless ($adminId || defined $groupId) {
            #Если не выбрана ни группа, ни пользователь - по умолчанию выбираем первого админа.
            $adminId = $row->{id};
        };
        $row->{current} = 0;
        if ($row->{id} == $adminId) {
            $row->{current} = 1;
            $groupId = $row->{group_id};
            $found = 1;
        };
        push @admins, $row;
    };
    $sth->finish();
    if ($adminId && !$found) {
        #Администратора еще нет в списке, но ему собираются дать прав, добавляем в список
        my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins where id = ?") or return $cms->error($DBI::errstr);
        $sth->execute($adminId) or return $cms->error($DBI::errstr);
        my $adminRow = $sth->fetchrow_hashref() or return $cms->error("Admin Not Found");
        $adminRow->{current} = 1;
        $groupId = $adminRow->{group_id};
        $sth->finish();
        push @admins, $adminRow;
    };
    
    #Загружаем список всех групп, имеющих права на ноду
    $found = 0;
    my @groups = ();
    $sth = $dbh->prepare("select id,name from ng_admin_groups where id in (select group_id from ng_module_privs where module_id = ? and group_id is not null)") or return $self->error($DBI::errstr);
    $sth->execute($mId) or return $cms->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        $row->{current} = 0;
        if (!$adminId) {
            $groupId = $row->{id} if !defined $groupId;
            if (defined $groupId && $groupId == $row->{id}) {
                $row->{current} = 1;
                $found = 1;
            };
        };
        push @groups, $row;
    };
    $sth->finish();

    if (!$adminId && defined $groupId && !$found) {
        #Группы еще нет в списке, но ей собираются дать прав, добавляем в список
        $sth = $dbh->prepare("select id,name from ng_admin_groups where id = ?") or return $cms->error($DBI::errstr);
        $sth->execute($groupId) or return $cms->error($DBI::errstr);
        my $groupRow = $sth->fetchrow_hashref() or return $cms->error("Group Not Found");
        $groupRow->{current} = 1;
        $sth->finish();
        push @groups, $groupRow;
    };
    
    #Загружаем все привилегии
    $m->_loadPrivileges(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,MODULE_ID=>$mId) or return $self->error();
    
    my $L1 = $m->{_l1}; #$checkPrivs->{groupID|adminID}->{$mId}->{$privilege} = $active;
    
    my @data = ();
    foreach my $priv (@$mp) {
        my $p = {};
        
        $p->{NAME} = $priv->{NAME};
        $p->{NAME} ||= "Право ".$priv->{PRIVILEGE};
        $p->{PRIVILEGE} = $priv->{PRIVILEGE};
        
        my $a = undef;
        if ($adminId) {
            $a = $L1->{"admin$adminId"}->{$mId}->{$priv->{PRIVILEGE}};
            #$p->{PADMIN_ID} = $adminId if defined $a;
        };
        if (defined $groupId && !defined $a) {
            $a = $L1->{"group$groupId"}->{$mId}->{$priv->{PRIVILEGE}};
            $p->{PGROUP_ID} = $groupId if defined $a;
        };
        $p->{ACTIVE} = $a;
        push @data, $p;
    };

    
    $self->opentemplate("admin-side/common/mprivileges/sprivs.tmpl");
    $self->tmpl()->param(
        MNAME => $mRow->{name} || "Модуль ".$mRow->{module},
        PAGEADMINS => \@admins,
        PAGEGROUPS => \@groups,
        DATA       => \@data,
        BASEURL => $self->getBaseURL(),
        MID => $mId,
        ADMIN_ID => $adminId,
        GROUP_ID => $groupId,
    );
    return $self->output($self->tmpl());
};

sub addSubj {
    my $self = shift;
    my $action = shift;
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    
    return $self->error("Invalid action") unless $action eq "addadmin" || $action eq "addgroup";
    
    my $mId = $self->{_mId} or die;
    
    my $mRow = $cms->getModuleRow("id=?",$mId) or return $cms->error("Запрошенный модуль $mId не найден");

    my @data = ();    
    if ($action eq "addadmin") {
        my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins where id not in (select admin_id from ng_module_privs where module_id = ? and admin_id is not null )") or return $cms->error($DBI::errstr);
        $sth->execute($mId) or return $cms->error($DBI::errstr);
        while(my $row = $sth->fetchrow_hashref()) {
            $row->{name} = $row->{fio}." (".$row->{login}.")";
            push @data, $row;
        };
        $sth->finish();
    };
    if ($action eq "addgroup") {
        my $sth = $dbh->prepare("select id,name from ng_admin_groups where id not in (select group_id from ng_module_privs where module_id = ? and group_id is not null)") or return $self->error($DBI::errstr);
        $sth->execute($mId) or return $self->error($DBI::errstr);
        while(my $row = $sth->fetchrow_hashref()) {
            push @data, $row;
        }
        $sth->finish();
    };
    use NHtml;
    my $json = create_json(\@data);
    return $cms->exit($json);
};

return 1;