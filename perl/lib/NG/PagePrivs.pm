package NG::PagePrivs;
use strict;

use NG::Module;
use Data::Dumper;

use vars qw(@ISA);
@ISA = qw(NG::Module);

#TODO: надо как-то удалять наследование. Это не проработано.

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    
    $self->{_pagePrivilegesL1} = {};
    $self->{_pagePrivilegesL1Stop} = {};  #$hash->{$subsiteId}->{$subject}  - признак что L1 загружен для cубъекта для всего подсайта
    $self->{_pagePrivilegesL1AStop} = {};  #$hash->{$subject}               - признак что L1 загружен для всех подсайтов для субъекта
    
    $self->{_modulePrivileges}  = {};
    $self->{_subsitePrivileges} = {};
    
    $self;
};

sub moduleTabs {
    return [];
	#return [
	#    {HEADER=>"Страничные привилегии",URL=>"/"},
	#];
};

sub moduleBlocks {
	return [
		{URL=>"/",BLOCK=>"NG::PagePrivs::Block",TYPE=>"moduleBlock"},
	]
};

sub modulePrivileges {
    return [];
};

sub pageModulePrivileges {
    my $self = shift;
    my $arr = [];

    push @$arr, {PRIVILEGE => "ACCESS",  NAME => "Доступ к странице"};    
    push @$arr, {PRIVILEGE => "PRIVILEGES",  NAME => "Редактирование прав на страницу"};
    push @$arr, {PRIVILEGE => "IPRIVILEGES",  NAME => "Редактирование наследуемых прав"};
    return $arr;
};

=head
sub loadSubsitePrivileges { #ADMIN_ID GROUP_ID SUBSITE_ID
    my $self = shift;
    my %opts = (@_);

    my $adminId = $opts{ADMIN_ID} or die("loadSubsitePrivileges(): ADMIN_ID is missing");
    my $groupId = $opts{GROUP_ID} or die("loadSubsitePrivileges(): GROUP_ID is missing");
    exists $opts{SUBSITE_ID}      or die("loadSubsitePrivileges(): SUBSITE_ID is missing");
    my $subsiteId = $opts{SUBSITE_ID} ;
    $self->_loadPagePrivilegesL1(ADMIN_ID=>$adminId, GROUP_ID=>$groupId, SUBSITE_ID=>$subsiteId);
};
=cut

sub loadAdminPrivileges { #ADMIN_ID GROUP_ID SUBSITE_ID
    my $self = shift;
    my %opts = (@_);

    my $adminId = $opts{ADMIN_ID} or die("loadSubsitePrivileges(): ADMIN_ID is missing");
	defined $opts{GROUP_ID} or die("loadSubsitePrivileges(): GROUP_ID is missing");
    my $groupId = $opts{GROUP_ID};
    $self->_loadPagePrivilegesL1(ADMIN_ID=>$adminId, GROUP_ID=>$groupId);
};

=head
                |  PageBlockPrivilege   |  LinkBlockPrivilege   |
    поле        | локальная | нода -    | локальная | нода -    |
                | нода      | хранилище | нода      | хранилище |
----------------------------------------------------------------|
page_id         |     -     |     =     |     с     |     c     |
link_id         |     c     |     c     |     V     |     =     |
lang_id         |     c     |     c     |     V     |     =     |
admin_id        |     V     |     V     |     V     |     V     |
group_id        |     V     |     V     |     V     |     V     |
module_id       |     V     |     =     |     V     |     =     |
privilege       |     V     |     =     |     V     |     =     |
active          |     V     |     V     |     V     |     V     |
storage_node_id |     V     |     c     |     c     |     c     |
storage_link_id |     c     |     c     |     V     |     c     |
subsite_id      |     -     |     =     |     c     |     c     |

"V" - используем.
"i" - вспомогательно используем
"с" - используем для параноидальной проверки корректности.
"-" - не используем
"=" - параметр p2 совпадет с полем из p1, поскольку сравнение значений в запросе

PageBlockPrivilege:

p1 - локальные привилегии + строка - указатель на ноду хранения привилегий

admin_id / group_id           - определение типа привилегии, админ / группа админа, привилегия админа имеет приоритет над группой
module_id + privilege + active - характеристики привилегии.
storage_node_id               - признак - привилегия наследованная

page_id,subsite_id            - совпадет c параметрами запроса
variant                       - не значим

link_id lang_id storage_link_id level - не должны быть заполнены!

p2 - нода хранения наследуемых нодой p1 привилегий

admin_id / group_id           - определение типа привилегии, админ / группа админа, привилегия админа имеет приоритет над группой
active                        - состояние привилегии - предоставлена/не предоставлена
level                         - в случае множественного наследования - более высокий уровень имеет приоритет

link_id lang_id storage_link_id storage_node_id - не должны быть заполнены (последовательное наследование запрещено)!

-------------------

select p1.page_id,p1.admin_id,p1.group_id,p1.block_id,p1.privilege,p1.active,p1.storage_node_id,
p2.admin_id st_admin_id,p2.group_id st_group_id,p2.active st_active, p2.level st_level,
p1.link_id,p1.lang_id,p1.storage_link_id,p2.link_id st_link_id, p2.lang_id st_lang_id,p2.storage_link_id st_storage_link_id,p2.storage_node_id st_storage_node_id
from ng_page_privs p1
left join ng_page_privs p2 on (p1.storage_node_id = p2.page_id and p1.block_id = p2.block_id and p1.privilege = p2.privilege and (p2.admin_id = ? or p2.group_id = ?) and p1.subsite_id = p2.subsite_id)
where  (p1.admin_id = ? or p1.group_id = ? ) and p1.page_id = ? and p1.subsite_id = ?

=cut

sub _loadPagePrivilegesL1 {
    my $self = shift;
    my %att = (@_);
    
    my $cms = $self->cms();
=head
    SUBSITE_ID | PAGE_ID | ADMIN_ID | GROUP_ID |  
    ------------------------------------------------------------
  1)    -      |    +    |    *     |    *     | - Считаем что это несерьезно, потому что subsiteId нужен для проверки, если загружены права для подсайта в целом: L1Stop, L1AStop
  3)    *      |    *    |    +     |    -     | - права админу наследуются от его группы, админа без группы не грузим !
        +      |    -    |    -     |    -     | - права на весь подсайт, без указания группы или админа - это слишком круто.
        -      |    -    |    -     |    +     | - Загрузка всех прав группы - ЗАПРЕЩЕНО
        
        *      |    +    |    *     |    *     | + Загрузка всех прав на страницу
        -      |    -    |    +     |    +     | + Загрузка всех прав админа
        +      |    -    |    -     |    +     | + Загрузка всех прав группы на подсайт
=cut
    
    #Загружаем все привилегии. Для определенной страницы или определенного подсайта.
    #Для определенной группы, и, если указано, для определенного админа.
    
    #Загрузка всех привилегий для страницы, без уточнения группы или админа - для построения результирующего списка привилегий
    #Загрузка всех привилегий без уточнения страницы /бывает/ нужна для заполнения кэша построении меню/деревьев доступных _для определенного админа_
    
    my $pageId = $att{PAGE_ID};
    my $subsiteId = $att{SUBSITE_ID}; 
    my $adminId = $att{ADMIN_ID};
    my $groupId = $att{GROUP_ID};
    
#print STDERR "_loadPagePrivilegesL1() a-$adminId-g-$groupId-pa-$pageId-ss-$subsiteId";
use Carp;
    croak "_loadPagePrivilegesL1(): has PAGE_ID without SUBSITE_ID" if $pageId && !defined $subsiteId; # check/1
    croak "_loadPagePrivilegesL1(): has ADMIN_ID without GROUP_ID" if ($adminId && !defined $groupId);   # check/3 (STRONG BASE CHECK !)
    croak "_loadPagePrivilegesL1(): has no PAGE_ID or ADMIN_ID or (SUBSITE_ID + GROUP_ID)" unless ($pageId || (defined $subsiteId && defined $groupId) || $adminId); #Все права на подсайт мы грузим только для определенного админа/группы.

    #die "_loadPagePrivilegesL1(): has no PAGE_ID or SUBSITE_ID" unless ($pageId || defined $subsiteId); #подумалось, что надо разрешить загружать все страничные привилегии админа и +loadAdminPrivileges()

#print STDERR "_loadPagePrivilegesL1: page -$pageId- subsite -$subsiteId- admin -$adminId- group -$groupId-";

    #$self->{_pagePrivilegesL1Stop} = {};  #$hash->{$subsiteId}->{$subject}  - признак что L1 загружен для cубъекта для всего подсайта
    #$self->{_pagePrivilegesL1AStop} = {};  #$hash->{$subject}               - признак что L1 загружен для всех подсайтов для субъекта

    if ($pageId && ($adminId || defined $groupId)) { #Если нет $adminId || $groupId - перезагружаем все права на страницу.
        #Запрашивается конкретная страница. Проверяем, не было ли ранее загрузки subsite целиком
        while(1) {
            my $stop = $self->{_pagePrivilegesL1Stop}->{$subsiteId};
            last unless $stop;
#print STDERR "FOUND SUBSITE $subsiteId L1STOP MARK, admin -$adminId-:".((exists $stop->{"admin".$adminId})?"1":"0")." group -$groupId-:".((exists $stop->{"group".$groupId})?"1":"0");
            if ($adminId && exists $stop->{"admin".$adminId}) {
                return 1 if exists $stop->{"group".$groupId};
                $adminId = undef;  #перезагружаем права только для группы
                last;
            };
            return 1 if exists $stop->{"group".$groupId};
            last;
        };
        #Запрашивается конкретная страница. Проверяем, не было ли загрузки всех прав админа/группы целиком
        my $stop = $self->{_pagePrivilegesL1AStop};
#print STDERR "L1ASTOP MARK, admin -$adminId-:".((exists $stop->{"admin".$adminId})?"1":"0")." group -$groupId-:".((exists $stop->{"group".$groupId})?"1":"0");
        return 1 if $adminId && exists $stop->{"admin".$adminId} && exists $stop->{"group".$groupId};
        return 1 if !$adminId && exists $stop->{"group".$groupId};
    };
    #Выставляем стоповые маркеры
    $self->{_pagePrivilegesL1Stop}->{$subsiteId}->{"admin".$adminId} = 1 if (!$pageId && defined $subsiteId && $adminId);
    $self->{_pagePrivilegesL1Stop}->{$subsiteId}->{"group".$groupId} = 1 if (!$pageId && defined $subsiteId && defined $groupId);
#print STDERR "MARKING subsite $subsiteId admin $adminId as loaded FULL SUBSITE" if (!$pageId && defined $subsiteId && $adminId);
#print STDERR "MARKING subsite $subsiteId group $groupId as loaded FULL SUBSITE" if (!$pageId && defined $subsiteId && defined $groupId);
    $self->{_pagePrivilegesL1AStop}->{"admin".$adminId}=1 if ($adminId && !defined $subsiteId && !$pageId);
    $self->{_pagePrivilegesL1AStop}->{"group".$groupId}=1 if (defined $groupId && !defined $subsiteId && !$pageId);
#print STDERR "MARKING admin $adminId as loaded FULL ADMIN" if ($adminId && !defined $subsiteId && !$pageId);
#print STDERR "MARKING group $groupId as loaded FULL GROUP" if (defined $groupId && !defined $subsiteId && !$pageId);


    my $L1 = $self->{_pagePrivilegesL1};
    #$L1->{("admin".$UID|"group".$GID)}->{$pageId}->{$moduleId}->{$privilege} = [{
    #    LEVEL=>(levelX|local),
    #    ACTIVE=>(0|1|undef),
    #    STORAGEID=>(IfNonLocal),
    #    STORAGEACTIVE=>(0|1),
    #    NODEACTIVE=>(0|1),
    #}, {...},... ];


    my $where1 = "";
    my $where2 = "";
    my @params = ();
    
    if ($adminId) {
        $where1.= " (p2.admin_id=p1.admin_id or p2.group_id=p1.group_id or (p1.admin_id is null and p1.group_id is null and (p2.admin_id = ? or p2.group_id = ?))) ";
        $where2.= " (p1.admin_id=? or p1.group_id=? or (p1.group_id is null and p1.admin_id is null)) ";
        push @params,$adminId;
        push @params,$groupId;
        push @params,$adminId;
        push @params,$groupId;
        $L1->{"admin$adminId"}||={};
        $L1->{"group$groupId"}||={} if defined $groupId;
    }
    else {
        $where1.= " (p2.group_id=p1.group_id or (p1.admin_id is null and p1.group_id is null and p2.group_id = ?)) ";
        $where2.= " (p1.group_id=? or (p1.group_id is null and p1.admin_id is null)) ";
        push @params,$groupId;
        push @params,$groupId;
    };
    if (defined $subsiteId) {
        $where2.= " and p1.subsite_id = ?";
        push @params,$subsiteId;
    };
    if ($pageId) {
        $where2.= " and p1.page_id = ?";
        push @params,$pageId;
        
        #$L1->{"admin$adminId"}->{$pageId}||={} if defined $adminId;
        #$L1->{"group$groupId"}->{$pageId}||={} if defined $groupId;
    };

    my $sql = "select p1.page_id,p1.admin_id,p1.group_id,p1.module_id,p1.privilege,p1.active,p1.storage_node_id,
p2.admin_id as st_admin_id,p2.group_id as st_group_id,p2.active as st_active,  s.level as s_level, s.name as s_name, s.subsite_id as s_subsite_id,
p1.link_id,p1.lang_id,p1.subsite_id,p1.storage_link_id,
p2.link_id as st_link_id, p2.lang_id as st_lang_id,p2.storage_link_id as st_storage_link_id,p2.storage_node_id as st_storage_node_id,
p2.subsite_id as st_subsite_id, p2.page_id as st_page_id
from ng_page_privs p1 left join ng_sitestruct s on (p1.storage_node_id = s.id)
left join ng_page_privs p2 on
(p1.storage_node_id = p2.page_id and p1.module_id = p2.module_id  and p1.privilege = p2.privilege
and $where1 and p1.subsite_id = p2.subsite_id and p1.active = 1 and p2.local=0)
where  $where2 and p1.local=1";
    
  
    my $dbh = $cms->db()->dbh();
    
    my $sth = $dbh->prepare_cached($sql) or die $DBI::errstr;
    $sth->execute(@params) or die $DBI::errstr;
    
    my $checkPrivs = {};  #$checkPrivs->{groupID|adminID}->{$pageId}->{$blockId}->{$privilege}->{(levelX|local)} = {DATA};
    
    while(my $row=$sth->fetchrow_hashref()) {
        die "_loadPagePrivilegesL1(): field link_id is filled" if defined $row->{link_id};
        die "_loadPagePrivilegesL1(): field lang_id is filled" if defined $row->{lang_id};
        die "_loadPagePrivilegesL1(): field storage_link_id is filled" if defined $row->{storage_link_id};
        
        die "_loadPagePrivilegesL1(): no value in page_id" unless $row->{page_id};
        die "_loadPagePrivilegesL1(): no value in module_id" unless $row->{module_id};
        die "_loadPagePrivilegesL1(): no value in privilege" unless $row->{privilege};
        
        $L1->{"admin$adminId"}->{$row->{page_id}}->{$row->{module_id}}->{$row->{privilege}}->{full} ||=[] if defined $adminId;
        $L1->{"group$groupId"}->{$row->{page_id}}->{$row->{module_id}}->{$row->{privilege}}->{full} ||=[] if defined $groupId;
        
        my $level = ""; # levelX || local
        my $from  = ""; # admin  || group
        my $active = undef;
        if ($row->{storage_node_id}) {
            #наследованная привилегия
            
            #проверки строки-ссылки
            die "_loadPagePrivilegesL1(): link row has both admin_id and group_id filled" if (defined $row->{admin_id} && defined $row->{group_id});
            die "_loadPagePrivilegesL1(): field level in sitestruct row has no value" unless $row->{s_level};
            die "_loadPagePrivilegesL1(): ng_page_privs.subsite_id != ng_sitestruct.st_subsite_id" if $row->{subsite_id} != $row->{s_subsite_id};
            $level = "level".$row->{s_level};
            
            unless ($row->{st_page_id}) {
                #Строка-ссылка есть, а строка-привилегия отсутствует
                
                #$row->{admin_id} - ссылка для админа
                #$row->{group_id} - ссылка для группы
                #!defined $row->{admin_id} && !defined $row->{group_id} - ссылка для всех
                
                if ($row->{admin_id} || !($row->{admin_id} || defined $row->{group_id})) {
                    die "AdminId != AdminId" if $row->{admin_id} && $row->{admin_id} ne $adminId;
                    $from = "admin".$adminId;
                    
                    #Inject fake admin priv
                    $checkPrivs->{$from}->{$row->{page_id}} ||= {};
                    $checkPrivs->{$from}->{$row->{page_id}}->{$row->{module_id}} ||= {};
                    my $p = $checkPrivs->{$from}->{$row->{page_id}}->{$row->{module_id}}->{$row->{privilege}} ||= {};
                    
#                     die "_loadPagePrivilegesL1(): table has two or more value rows for page ".$row->{page_id}." module ".$row->{module_id}." privilege ".$row->{privilege}." level ".$level." from ".$from if (exists $p->{$level});
                    
                    $p->{$level} = {
                        LEVEL  => $level,
                        ACTIVE => $active, 
                        STORAGEID => $row->{storage_node_id},
                        STORAGEACTIVE => undef,
                        STORAGENAME   => $row->{s_name},
                        NODEACTIVE    => $row->{active},
                    };
                }
                if (defined $row->{group_id} || !($row->{admin_id} || defined $row->{group_id})) {
                    die "GroupId != GroupId" if $row->{group_id} && $row->{group_id} ne $groupId;
                    $from = "group".$groupId;
                    
                    #Inject fake group priv
                    $checkPrivs->{$from}->{$row->{page_id}} ||= {};
                    $checkPrivs->{$from}->{$row->{page_id}}->{$row->{module_id}} ||= {};
                    my $p = $checkPrivs->{$from}->{$row->{page_id}}->{$row->{module_id}}->{$row->{privilege}} ||= {};
                    
#                     die "_loadPagePrivilegesL1(): table has two or more value rows for page ".$row->{page_id}." module ".$row->{module_id}." privilege ".$row->{privilege}." level ".$level." from ".$from if (exists $p->{$level});
                    
                    $p->{$level} = {
                        LEVEL  => $level,
                        ACTIVE => $active, 
                        STORAGEID => $row->{storage_node_id},
                        STORAGEACTIVE => undef,
                        STORAGENAME   => $row->{s_name},
                        NODEACTIVE    => $row->{active},
                    };
                };
                next;
            };
            #Проверка записи в строке-хранилище привилегии
            die "_loadPagePrivilegesL1(): field storage_node_id filled in storage row" if defined $row->{st_storage_node_id};
            die "_loadPagePrivilegesL1(): field storage_link_id filled in storage row" if defined $row->{st_storage_link_id};
            die "_loadPagePrivilegesL1(): field link_id filled in storage row" if defined $row->{st_link_id};
            die "_loadPagePrivilegesL1(): field lang_id filled in storage row" if defined $row->{st_lang_id};
            die "_loadPagePrivilegesL1(): ng_page_privs.subsite_id != ng_page_privs.st_subsite_id" if $row->{subsite_id} != $row->{st_subsite_id};
            die "_loadPagePrivilegesL1(): storage row has both admin_id and group_id filled" if (defined $row->{st_admin_id} && defined $row->{st_group_id});
            die "_loadPagePrivilegesL1(): storage row has no admin_id or group_id filled" unless (!defined $row->{st_subsite_id} || defined $row->{st_admin_id} || defined $row->{st_group_id});


            $from = "admin".$row->{st_admin_id} if ($row->{st_admin_id});
            $from = "group".$row->{st_group_id} if (defined $row->{st_group_id});
            
            $active = $row->{st_active} if ($row->{active});
#print STDERR "page ".$row->{page_id}." STORAGE ".$row->{storage_node_id}." module ".$row->{module_id}." privilege ".$row->{privilege}." level $level from $from ROW ACTIVE: ".$row->{active}." STORAGE ACTIVE: ".$row->{st_active}."--";
        }
        else {
            #обычная привилегия
            $level = "local";
            die "_loadPagePrivilegesL1(): privilege row has both admin_id and group_id filled" if (defined $row->{admin_id} && defined $row->{group_id});
            die "_loadPagePrivilegesL1(): privilege row has no admin_id or group_id filled" unless ($row->{admin_id} || defined $row->{group_id});
            $from = "admin".$row->{admin_id} if ($row->{admin_id});
            $from = "group".$row->{group_id} if (defined $row->{group_id});
            $active = $row->{active};
#print STDERR "page ".$row->{page_id}." LOCAL module ".$row->{module_id}." privilege ".$row->{privilege}." from $from active $active";
        };
        
        $checkPrivs->{$from}->{$row->{page_id}} ||= {};
        $checkPrivs->{$from}->{$row->{page_id}}->{$row->{module_id}} ||= {};
        my $p = $checkPrivs->{$from}->{$row->{page_id}}->{$row->{module_id}}->{$row->{privilege}} ||= {};

#         die "_loadPagePrivilegesL1(): table has two or more value rows for page ".$row->{page_id}." module ".$row->{module_id}." privilege ".$row->{privilege}." level ".$level." from ".$from if (exists $p->{$level});

        $p->{$level} = {
            LEVEL  => $level,
            ACTIVE => $active, 
            STORAGEID => $row->{storage_node_id},
            STORAGEACTIVE => $row->{st_active},
            STORAGENAME   => $row->{s_name},
            NODEACTIVE    => $row->{active},
        };
    };
    $sth->finish();
    
    #делаем сортировку/приоритезацию привилегий
    foreach my $subject (keys %$checkPrivs) {
#$L2->{$subject}||={};
        foreach my $pageId (keys %{$checkPrivs->{$subject}}) {
            #next if exists $L2->{$subject}->{$pageId};
#$L2->{$subject}->{$pageId} = {};
            foreach my $moduleId (keys %{$checkPrivs->{$subject}->{$pageId}}) {
#$L2->{$subject}->{$pageId}->{$moduleId} = {};
                foreach my $privilege (keys %{$checkPrivs->{$subject}->{$pageId}->{$moduleId}}) {
                    my $levels = $checkPrivs->{$subject}->{$pageId}->{$moduleId}->{$privilege};
                    my $full   =         $L1->{$subject}->{$pageId}->{$moduleId}->{$privilege}->{full};
                    
                    my $result = undef;
                    if (exists $levels->{local}) {
                        unshift @$full, $levels->{local};
                        if (defined $levels->{local}->{ACTIVE}) {
                            $result = $levels->{local};
                        };
                        delete $levels->{local};
                    };
                    
                    foreach my $level (sort { my ($t1) = $a =~ /^level(\d+)$/; my ($t2) = $b =~ /^level(\d+)$/; $t2 <=> $t1 } keys %$levels) {
                        push @$full, $levels->{$level};
                        $result = $levels->{$level} if (!defined $result && defined $levels->{$level}->{ACTIVE});
                    };

                    $L1->{$subject}->{$pageId}->{$moduleId}->{$privilege}->{acting} = $result if $result;

#$result ||= {ACTIVE=>"undef", LEVEL=>""};
#print STDERR "---> subj-$subject-pa-$pageId-m-$moduleId-pr-$privilege-set to ".$result->{ACTIVE}." by ".$result->{LEVEL};

#unless ($full) { #TODO: check this
#    next;
#};
#warn Dumper($full);
                };
            };
        };
    };
#---
    #Сейчас строится структура вида (!!! Устарело):
    #$pagePrivs->{$pageId}->{$blockId}->{$privilege}->{(levelX|local)}->{group|admin} = $active;

    #Для работы в редакторе привилегий нужна структура c подробными данными, вида:
    #Мы точно знаем идентификаторы группы и пользователя, поэтому выносим их вперед.
    #Дальше мы точно знаем код страницы, список её модулей и список их привилегий. Точно идем по ключам хеша
    #$L1->{("user".$UID|"group".$GID)}->{$pageId}->{$moduleId}->{$privilege} = [{LEVEL=>(levelX|local),ACTIVE=>(0|1),STORAGEID=>(IfNonLocal),STORAGEACTIVE=>(0|1)},{...},...]

    #Для проверки привилегий на конкретную или все страницы нужна структура:
    #Чтобы знать, что привилегии пользователя/группы на страницу загружены, эти ключи вынесены вперед
    #Также, проверка привилегий осуществляется для конкретного пользователя или группы.
    #$L2->{("user".$UID|"group".$GID)}->{$pageId}->{$moduleId}->{$privilege} = {}; #Хэш, который "выиграл"
    

    #Для построения сводного отчета по правам на модуль страницы, нужна структура с итоговыми данными:
    #чтобы итерировать по пользователю/группе в рамках привилегии
    #$L1->{$pageId}->{$moduleId}->{$privilege}->{("user".$UID|"group".$GID)}->{access} = {LEVEL=>(levelX|local),ACTIVE=>(0|1),STORAGEID=>(),STORAGEACTIVE=>(0|1)};
    return 1;
};

#sub getAllPagePrivileges {
#    my $self = shift;
#    my %att = (@_);
#    
#    $att{PAGE_ID} or return $self->error("getAllPagePrivileges(): PAGE_ID is missing");
#    $att{MODULE_ID} or return $self->error("getAllPagePrivileges(): MODULE_ID is missing");
#    
#    unless ($self->{_pagePrivilegesL1} && exists $self->{_pagePrivilegesL1}->{$att{PAGE_ID}} && exists $self->{_pagePrivilegesL1}->{$att{PAGE_ID}}->{$att{MODULE_ID}}) {
#        $self->_getAllPagePrivileges(AD)
#    };
#    
#};

sub hasPageModulePrivilege { #ADMIN_ID GROUP_ID PAGE_ID MODULE_ID PRIVILEGE SUBSITE_ID
    my $self = shift;
    my %att = (@_);
    
    my $cms = $self->cms();
    my $dbh = $cms->db()->dbh();

    my $adminId   = $att{ADMIN_ID} or return $cms ->error("hasPageModulePrivilege(): Не указан ADMIN_ID");
	defined $att{GROUP_ID} or return $cms->error("hasPageModulePrivilege(): Не указан GROUP_ID");
    my $groupId   = $att{GROUP_ID};
    return 1 unless $groupId;
    my $pageId    = $att{PAGE_ID}  or return $cms->error("hasPageModulePrivilege(): Не указан код cтраницы");
    my $moduleId  = $att{MODULE_ID} or return $cms->error("hasPageModulePrivilege(): MODULE_ID is missing");
    my $privilege = $att{PRIVILEGE} or return $cms->error("hasPageModulePrivilege(): Не указана проверяемая привилегия");
    return $cms->error("hasPageModulePrivilege(): SUBSITE_ID is missing") unless exists $att{SUBSITE_ID};
    my $subsiteId = $att{SUBSITE_ID};

=head TODO: Поддержка глобальных привилегий уровня подсайта
        my $sbp = $self->getAdminSubsitePrivileges($adminId,$subsiteId);  
        if ($blockId == 0) {
            return 1 if exists $sbp->{PROPERTIES} && ($privilege eq "PROPERTIES");
            return 1 if exists $sbp->{NEWPAGE}    && ($privilege eq "NEWPAGE");
        }
        else {
            return 1 if exists $sbp->{CONTENT};
        };
=cut


    my $L1 = $self->{_pagePrivilegesL1};

    unless (exists $L1->{"admin$adminId"} && exists $L1->{"admin$adminId"}->{$pageId}) {
#print STDERR "hasPageModulePrivilege(): LOADING PRIVILEGES FOR page $pageId admin $adminId group $groupId";
        $self->_loadPagePrivilegesL1(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,PAGE_ID=>$pageId,SUBSITE_ID=>$subsiteId);
    };

#print STDERR "Check hasPageModulePrivilege page $pageId module $moduleId priv $privilege - ";
#print STDERR "TODO: ACCESS key is missing, replace to ACTIVE" unless exists $a->{ACCESS};

    my $ac = undef;
    if (exists $L1->{"admin$adminId"}->{$pageId}->{$moduleId} && exists $L1->{"admin$adminId"}->{$pageId}->{$moduleId}->{$privilege}) {
        $ac = $L1->{"admin$adminId"}->{$pageId}->{$moduleId}->{$privilege}->{acting} || {};
#print STDERR "TODO: ACCESS key is missing, replace to ACTIVE ".$a->{ACTIVE} unless exists $a->{ACCESS};
#print STDERR "exists".(exists $a->{ACTIVE})?"1":"0";
#print STDERR " ADMIN: UNDEFINED" unless defined $a->{ACCESS};
#print STDERR " ADMIN: GRANTED" if defined $a->{ACCESS} && $a->{ACCESS};
#print STDERR " ADMIN: DECLINED" if defined $a->{ACCESS} && !$a->{ACCESS};
        #return $a->{ACTIVE} if defined $a->{ACTIVE};
    };

    #unless (exists $L1->{"group$groupId"}->{$pageId}) { Не надо, поскольку будет загружено.
    #    $self->_loadPagePrivilegesL1($adminId,$pageId,$groupId);
    #};

    if ((!$ac || !defined $ac->{ACTIVE}) && exists $L1->{"group$groupId"}->{$pageId}->{$moduleId} && exists $L1->{"group$groupId"}->{$pageId}->{$moduleId}->{$privilege}) {
        $ac = $L1->{"group$groupId"}->{$pageId}->{$moduleId}->{$privilege}->{acting} || {};
#print STDERR "TODO: ACCESS key is missing, replace to ACTIVE ".$a->{ACTIVE} unless exists $a->{ACCESS};
#print STDERR "exists".(exists $a->{ACTIVE})?"1":"0";
#print STDERR " GROUP: UNDEFINED" unless defined $a->{ACTIVE};
#print STDERR " GROUP: GRANTED" if defined $a->{ACTIVE} && $a->{ACTIVE};
#print STDERR " GROUP: DECLINED" if defined $a->{ACTIVE} && !$a->{ACTIVE};
        #return $a->{ACTIVE} if defined $a->{ACTIVE};
    };
#print STDERR " DEFAULT: DECLINED";

$moduleId||="";
$ac||={ACTIVE=>"undef"};
#print STDERR "hasPageModulePrivilege() a-$adminId-g-$groupId-pa-$pageId-m-$moduleId-pr-$privilege-R=".$ac->{ACTIVE}."-";

    return 0 if $ac->{ACTIVE} eq "undef";
    return $ac->{ACTIVE};

    return 0;
};

sub _loadLinkPrivilegesCache {
    my $self = shift;
    my %att = (@_);
    
    my $lbpCache = $self->{_linkBlocksPrivileges};
    
#print STDERR "hasLinkBlockPrivilege(): called ".(exists $att{PAGE_ID}?"for page ".$att{PAGE_ID}:"all pages");
    
    my $adminId = $att{ADMIN_ID} or return $self->error("hasLinkBlockPrivilege(): ADMIN_ID is missing");
    my $groupId = $att{GROUP_ID}; # or return $self->error("hasLinkBlockPrivilege(): GROUP_ID is missing");
    #my $subsiteId = $att{SUBSITE_ID} or return $self->error("hasLinkBlockPrivilege(): SUBSITE_ID is missing");
    
    my $sql = "select p1.link_id,p1.lang_id,p1.admin_id,p1.group_id,p1.module_id,p1.privilege,p1.active,p1.storage_link_id,p1.level,p1.subsite_id,
p2.admin_id as st_admin_id,p2.group_id as st_group_id,p2.active as st_active, p2.level as st_level,
p1.page_id,p1.storage_node_id,p2.page_id as st_page_id, p2.storage_link_id as st_storage_link_id,p2.storage_node_id as st_storage_node_id,p2.subsite_id as st_subsite_id

from ng_page_privs p1 left join ng_page_privs p2 on (p1.storage_link_id = p2.link_id and p1.lang_id = p2.lang_id and p1.module_id = p2.module_id and p1.privilege = p2.privilege and (p2.admin_id = ? or p2.group_id = ?) and p1.active = 1)
where  (p1.admin_id = ? or p1.group_id = ?)";
    
    my @params = ();
    push @params,$adminId;
    push @params,$groupId;
    push @params,$adminId;
    push @params,$groupId;
    
    if (exists $att{LINK_ID}) { # если отсутствует - загружаем все привилегии всех страниц подсайта
        $att{LINK_ID} or return $self->error("hasLinkBlockPrivilege(): LINK_ID value is missing");
        $sql .= " and p1.link_id = ?";
        push @params,$att{LINK_ID};
        $lbpCache->{$att{LINK_ID}} = {}; # Иначе не работает кеширование негативного ответа
    };
    #$sql.="order by p2.level desc";
    
    my $dbh = $self->db()->dbh();
    
    my $sth = $dbh->prepare_cached($sql) or die $DBI::errstr;
    $sth->execute(@params) or die $DBI::errstr;
    
    my $pagePrivs = {};
    
    #$pagePrivs->{$linkId}->{$langId}->{$blockId}->{$privilege}->{(levelX|local)}->{group|admin} = $active;
    
    while(my $row=$sth->fetchrow_hashref()) {
        die "hasLinkBlockPrivilege(): field page_id is filled" if defined $row->{page_id};
        die "hasLinkBlockPrivilege(): field subsite_id is filled" if defined $row->{subsite_id};
        die "hasLinkBlockPrivilege(): field storage_node_id is filled" if defined $row->{storage_node_id};
        die "hasLinkBlockPrivilege(): field level filled" if $row->{level};
        my $level = ""; # levelX || local
        my $from  = ""; # admin  || group
        my $active = 0;
        if ($row->{storage_link_id}) {
            die "hasLinkBlockPrivilege(): field storage_node_id filled in storage row" if defined $row->{st_storage_node_id};
            die "hasLinkBlockPrivilege(): field storage_link_id filled in storage row" if defined $row->{st_storage_link_id};
            die "hasLinkBlockPrivilege(): field subsite_id filled in storage row" if defined $row->{st_subsite_id};
            die "hasLinkBlockPrivilege(): field admin_id filled in link row" if defined $row->{admin_id};
            die "hasLinkBlockPrivilege(): field group_id filled in link row" if defined $row->{group_id};
            #наследованная привилегия
            die "hasLinkBlockPrivilege(): field level in storage row has no value" unless $row->{st_level};
            $level = "level".$row->{st_level};
            
            die "hasLinkBlockPrivilege(): storage row has both admin_id and group_id filled" if (defined $row->{st_admin_id} && defined $row->{st_group_id});
            die "hasLinkBlockPrivilege(): storage row has no admin_id or group_id filled" unless ($row->{st_admin_id} || defined $row->{st_group_id});
            $from = "admin" if ($row->{st_admin_id});
            $from = "group" if (defined $row->{st_group_id});
            next unless $row->{active};
            $active = $row->{st_active};
#print STDERR "link ".$row->{link_id}." lang ".$row->{lang_id}." STORAGE ".$row->{storage_link_id}."block ".$row->{block_id}." privilege ".$row->{privilege}." level $level from $from active $active";
        }
        else {
            #обычная привилегия
            $level = "local";
            die "hasLinkBlockPrivilege(): privilege row has both admin_id and group_id filled" if (defined $row->{admin_id} && defined $row->{group_id});
            die "hasLinkBlockPrivilege(): privilege row has no admin_id or group_id filled" unless (defined $row->{admin_id} || defined $row->{group_id});
            $from = "admin" if (defined $row->{admin_id});
            $from = "group" if (defined $row->{group_id});
            $active = $row->{active};
#print STDERR "link ".$row->{link_id}." lang ".$row->{lang_id}." LOCAL block ".$row->{block_id}." privilege ".$row->{privilege}." from $from active $active";
        };
        
        $pagePrivs->{$row->{link_id}} ||= {};
        $pagePrivs->{$row->{link_id}}->{$row->{lang_id}} ||= {};
        $pagePrivs->{$row->{link_id}}->{$row->{lang_id}}->{$row->{block_id}} ||= {};
        $pagePrivs->{$row->{link_id}}->{$row->{lang_id}}->{$row->{block_id}}->{$row->{privilege}} ||= {};
        $pagePrivs->{$row->{link_id}}->{$row->{lang_id}}->{$row->{block_id}}->{$row->{privilege}}->{$level} ||= {};

        my $p = $pagePrivs->{$row->{link_id}}->{$row->{lang_id}}->{$row->{block_id}}->{$row->{privilege}}->{$level};
#         die "hasLinkBlockPrivilege(): table has two or more value rows for page ".$row->{page_id}." block ".$row->{block_id}." privilege ".$row->{privilege}." level ".$level." from ".$from if (exists $p->{$from});
        $p->{$from} = $active;
    };
    $sth->finish();
    
    foreach my $linkId (keys %{$pagePrivs}) {
        $lbpCache->{$linkId} = {};
        foreach my $langId (keys %{$pagePrivs->{$linkId}}) {
            $lbpCache->{$linkId}->{$langId} = {};
            foreach my $blockId (keys %{$pagePrivs->{$linkId}->{$langId}}) {
                $lbpCache->{$linkId}->{$langId}->{$blockId} = {};
                foreach my $privilege (keys %{$pagePrivs->{$linkId}->{$langId}->{$blockId}}) {
                    my $maxLevel = 0;
                    my $pValue = 0;
                    foreach my $level (keys %{$pagePrivs->{$linkId}->{$langId}->{$blockId}->{$privilege}}) {
                        my $t3 = $pagePrivs->{$linkId}->{$langId}->{$blockId}->{$privilege}->{$level};
                        if ($level =~ /^level(\d+)$/) {
                            next unless $1 > $maxLevel;
                            $maxLevel = $1;
                        }
                        else {
                            die "hasLinkBlockPrivilege(): t2 key $level is not valid" unless $level eq "local";
                        };
                        
                        if (exists $t3->{admin}) {
                            $pValue = "admin";
                        }
                        elsif (exists $t3->{group}) {
                            $pValue = "group";
                        }
                        else {
                            die "hasLinkBlockPrivilege(): t3 key not found in level $level";
                        };
                        if ($level eq "local") {
                            $maxLevel = "local";
                            last;
                        };
                    };
#print STDERR "---> link $pageId lang $langId block $blockId privilege $privilege set to $pValue by $maxLevel";
                    $lbpCache->{$linkId}->{$langId}->{$blockId}->{$privilege} = $pValue if $pValue;
                };
            };
        };
    };
    return 1;
};


=head hasLinkBlockPrivilege
sub hasLinkBlockPrivilege {  LINK_ID LANG_ID MODULE_ID PRIVILEGE SUBSITE_ID
    my $self = shift;
    my %att = (@_);

    my $dbh=$self->db()->dbh();
    
    my $adminId   = $self->getAdminId();
    my $groupId   = $self->{_admin}->{group_id};
    my $linkId    = $att{LINK_ID} or return $self->error("hasLinkBlockPrivilege(): Не указан код группы страниц");
    my $langId    = $att{LANG_ID} || 0;
    my $blockId   = $att{BLOCK_ID} || 0;
    my $privilege = $att{PRIVILEGE} or return $self->error("hasLinkBlockPrivilege(): Не указана проверяемая привилегия");
 =head
    if (exists $att{SUBSITE_ID}) {
        #Поддержка глобальных привилегий уровня подсайта
        my $subsiteId = $att{SUBSITE_ID};
        my $sbp = $self->getAdminSubsitePrivileges($adminId,$subsiteId);
        if ($blockId == 0) {
            return 1 if exists $sbp->{PROPERTIES} && ($privilege eq "PROPERTIES");
            return 1 if exists $sbp->{NEWPAGE}    && ($privilege eq "NEWPAGE");
        }
        else {
            return exists $sbp->{CONTENT};
        };
    };
 =cut

    my $lbpCache = $self->{_linkBlocksPrivileges};
    if (!exists $lbpCache->{$linkId}) {
print STDERR "  LOADING PRIVILEGES FOR link $linkId admin $adminId group $groupId";
        $self->_loadLinkPrivilegesCache(ADMIN_ID=>$adminId, GROUP_ID=>$groupId, LINK_ID=>$linkId);
    };
print STDERR "Check hasLinkBlockPrivilege link $linkId lang $langId block $blockId priv $privilege - GRANTED" if (exists $lbpCache->{$linkId}->{$langId}->{$blockId} && exists $lbpCache->{$linkId}->{$blockId}->{$privilege});
    return 1 if (exists $lbpCache->{$linkId}->{$blockId} && exists $lbpCache->{$linkId}->{$langId}->{$blockId}->{$privilege});
print STDERR "Check hasLinkBlockPrivilege link $linkId lang $langId block $blockId priv $privilege - DENIED";
    return 1;
};
=cut

=comment - старый код проверки привилегий на подсайт.

sub getAdminSubsitePrivileges {
    my $self = shift;
    my $adminId = shift   or die("getAdminSubsitePrivileges(\$adminId,\$subsiteId): no adminId specified");
    my $subsiteId = shift;
    
    die("getAdminSubsitePrivileges(\$adminId,\$subsiteId): no subsiteId specified") unless defined $subsiteId;
    
    my $dbh=$self->db()->dbh();

    my $sbp = $self->{_subsitePrivileges};
    if (!exists $sbp->{$subsiteId}) {
        my $sql="select privilege from ng_subsite_privs where admin_id = ? and subsite_id = ?";
        my $sth = $dbh->prepare_cached($sql) or die $DBI::errstr;
        $sth->execute($adminId,$subsiteId) or die $DBI::errstr;
        $sbp->{$subsiteId} = $sth->fetchall_hashref(['privilege']);
        $sbp->{$subsiteId} ||= {};
        $sth->finish();
    };
    return $sbp->{$subsiteId};
}

sub hasSubsitePrivilege {
    my $self = shift;
    my %att = (@_);
    
    my $adminId   = $self->getAdminId();
    return $self->error("hasSubsitePrivilege(): Не указан подсайт") if !exists $att{SUBSITE_ID};
    return $self->error("hasSubsitePrivilege(): Не указана привилегия") if !exists $att{PRIVILEGE};
    my $subsiteId = $att{SUBSITE_ID};
    my $privilege = $att{PRIVILEGE}  or return 0;
    my $sbp = $self->getAdminSubsitePrivileges($adminId,$subsiteId);
    return 1 if exists $sbp->{$privilege};
    return 0;
}

=cut

sub processEvent {
    my $self = shift;
    my $event = shift;
    my $opts = $event->options();
    
    my $variant = $opts->{VARIANT};
    my $pageObj = $opts->{PAGEOBJ};
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();

	my $event_name = $event->name();
    
    $self->{_moduleRow} = $cms->getModuleRow("module=?",ref($self)) or die("processEvent(): __PACKAGE__ не зарегистрирован в ng_modules");
	
	# на данный момент генерируются евенты: addnode addlinkednodes updateNode swapNode enablenode disablenode deletenode
	
	if ($event_name eq "addlinkednodes") {
        my $variant = $opts->{VARIANT};	
        my $nodes = $opts->{NODES};
        
        #Может производиться добавление нескольких связанных страниц,
        #проверяем чтобы связанные права создавались разово
        #Поскольку link_id нод одинаков, первый ключ хэша (N_link_id) опускаем
        #Если добавляется локальное правило - ST_link_id -> undef
        #$hash->[{N_link_id}]->{N_lang_id}->{mId}->{priv}->{ST_link_id};
        my $addedLP = {};
        
        #Проверяем, чтобы все добавляемые ноды имели одинаковый link_id
        my $checkLinkId = undef;
        foreach my $node (@{$nodes}) {
            my $npageObj = $node->{PAGEOBJ};
            my $npageRow = $npageObj->getPageRow();
            
            $checkLinkId ||= $npageRow->{link_id};
            die "NG::PagePrivs::processEvent(addlinkednodes): nodes link_id does not match" if $checkLinkId != $npageRow->{link_id};
            
            my $sth = $dbh->prepare(
"select ppr.page_id,ppr.link_id,ppr.lang_id,ppr.module_id,ppr.privilege,ppr.depth
FROM
ng_page_priv_rules ppr,
(select id,link_id,subsite_id,lang_id,level from ng_sitestruct,(select max(tree_order) as maxorder from ng_sitestruct where tree_order <? and level <? group by level) o where tree_order=maxorder and level>0 order by tree_order) s
WHERE
(ppr.page_id=s.id or (ppr.link_id=s.link_id and ppr.lang_id is null) or (ppr.link_id=s.link_id and ppr.lang_id=s.lang_id))
and ppr.depth+s.level>=?"
) or die $DBI::errstr;
            
            my $canAdd = 0;
            $canAdd = $npageObj->canAddPage() if $npageObj->can("canAddPage");
            my $insSth = $dbh->prepare("INSERT INTO ng_page_priv_rules (page_id,link_id,lang_id,privilege,module_id,depth) VALUES (?,?,?,?,?,?)") or die $DBI::errstr;
            
            $sth->execute($npageRow->{tree_order},$npageRow->{level},$npageRow->{level}) or die $DBI::errstr;
            my $rules = {};
            while (my $row = $sth->fetchrow_hashref()) {
                die ("NG::PagePrivs::processEvent(): Found rule with both page_id and link_id") if $row->{page_id} && $row->{link_id};
                
                if ($canAdd) {
                    my $depth = $row->{depth};
                    $depth-- if $depth;
                    my $pa = ($row->{page_id}?$npageRow->{id}:undef);
                    my $li = ($row->{link_id}?$npageRow->{link_id}:undef);
                    my $la = ($row->{lang_id}?$npageRow->{lang_id}:undef);
                    $insSth->execute($pa,$li,$la,$row->{privilege},$row->{module_id},$depth) or die $DBI::errstr;
                };
                
                my $rule = $rules->{$row->{module_id}}->{$row->{privilege}} ||= [];
                push @$rule, {
                    link_id => $row->{link_id},
                    lang_id => $row->{lang_id},
                    page_id => $row->{page_id},
                };
            };
            $insSth->finish();
            $sth->finish();
            
            #Определяем право, благодаря которому пользователь имеет право создать данную страницу
            #определяем, кому дано это право: пользователю или группе.
            #Для пользователя или группы даем все права на модули созданной страницы, если на это право не было создания наследования правилом
            my $adminId   = $cms->getAdminId();
            my $groupId   = $cms->{_admin}->{group_id};
            my $pageId   = $npageRow->{parent_id};
            my $moduleId = $self->moduleParam('id');

            my $L1 = $self->{_pagePrivilegesL1};
            unless (exists $L1->{"admin$adminId"} && exists $L1->{"admin$adminId"}->{$pageId} && exists $L1->{"group$groupId"} && exists $L1->{"group$groupId"}->{$pageId}) {
                $self->_loadPagePrivilegesL1(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,PAGE_ID=>$pageId,SUBSITE_ID=>$npageRow->{subsite_id});
            };
            my $act = undef;
            if (exists $L1->{"admin$adminId"}->{$pageId}->{$moduleId} && exists $L1->{"admin$adminId"}->{$pageId}->{$moduleId}->{NEWPAGE}) {
                $act = $L1->{"admin$adminId"}->{$pageId}->{$moduleId}->{NEWPAGE}->{acting};
                $groupId = undef if $act && $act->{ACTIVE};
            };
            if (!$act && exists $L1->{"group$groupId"}->{$pageId}->{$moduleId} && exists $L1->{"group$groupId"}->{$pageId}->{$moduleId}->{NEWPAGE}) {
                $act = $L1->{"group$groupId"}->{$pageId}->{$moduleId}->{NEWPAGE}->{acting};
                $adminId = undef if $act && $act->{ACTIVE};
            };
            #die "USER HAS NO RIGHTS TO ADD PAGE" unless $act && $act->{ACTIVE};
$groupId = undef unless ($act && $act->{ACTIVE});
            
            my $moduleObjs = $self->_getPageModules($npageObj);
            return $cms->error() unless $moduleObjs;
            foreach my $t (@$moduleObjs) {
                my $mObj = $t->{MOBJ};
                my $mId  = $t->{MID};
                my $mName = $t->{MNAME};
                
                my $mp = $t->{MP};

                foreach my $priv (@$mp) {
                    #$priv->{PRIVILEGE};
#TODO: get privilege type
                    my $type = "page";
                    
                    #Проверяем наличие правил для данной привилегиии
                    my $ar = $rules->{$mId}->{$priv->{PRIVILEGE}};
                    if ($ar) {
                        foreach my $row (@$ar) {
                            #Если для привилегии данного модуля имеются правила, создаем ссылочные записи
                            die "Found a rule of type 'link' for privilege of type 'page' - priv:".$priv->{PRIVILEGE}." module: $mId" if $type eq "page" && $row->{link_id};
                            die "Found a rule of type 'page' for privilege of type 'link' - priv:".$priv->{PRIVILEGE}." module: $mId" if $type ne "page" && $row->{page_id};
                            
                            if ($row->{link_id}) {
                                next if exists $addedLP->{$row->{lang_id}}->{$mId}->{$priv->{PRIVILEGE}}->{$row->{link_id}};
                                $addedLP->{$row->{lang_id}}->{$mId}->{$priv->{PRIVILEGE}}->{$row->{link_id}} = 1;
                            };
                            
                            #Определяем, для какой ноды создается правило-ссылка
                            my $pa = ($row->{page_id}?$npageRow->{id}:undef);
                            my $li = ($row->{link_id}?$npageRow->{link_id}:undef);
                            my $la = ($row->{lang_id}?$npageRow->{lang_id}:undef);
                            my $ss = ($row->{page_id}?$npageRow->{subsite_id}:undef);
                            
                            $dbh->do("INSERT INTO ng_page_privs(page_id, link_id, lang_id, module_id, subsite_id, privilege, storage_node_id, storage_link_id,admin_id, group_id, active,local)
                                      VALUES(?,?,?,?,?,?,?,?,null,null,1,1)",undef,$pa,$li,$la,$mId,$ss,$priv->{PRIVILEGE},$row->{page_id},$row->{link_id}) or die $DBI::errstr;
                        };
                        next;
                    };
                    
                    #Иначе даем права создателю
                    if ($type eq "page") {
                        $dbh->do("INSERT INTO ng_page_privs(page_id,subsite_id, module_id, privilege, admin_id, group_id, active) VALUES (?,?,?,?,?,?,1)",undef, $npageRow->{id},$npageRow->{subsite_id},$mId,$priv->{PRIVILEGE},$adminId,$groupId) or die $DBI::errstr;
                    };
                    if ($type eq "link") {
                        next if exists $addedLP->{$npageRow->{lang_id}}->{$mId}->{$priv->{PRIVILEGE}}->{undef};
                        $addedLP->{$npageRow->{lang_id}}->{$mId}->{$priv->{PRIVILEGE}}->{undef} = 1;
                        $dbh->do("INSERT INTO ng_page_privs (link_id, lang_id, module_id, privilege, admin_id, group_id, active) VALUES (?,?,?,?,?,?,1)",undef,$npageRow->{link_id},$npageRow->{lang_id},$mId,$priv->{PRIVILEGE},$adminId,$groupId) or die $DBI::errstr;
                    };
                };
            };
        };
	};
	
    if ($event_name eq "deletenode") {
        my $page_id = $opts->{PAGE_ID};
        $dbh->do("delete from ng_page_privs where page_id=?",undef,$page_id) or die $DBI::errstr;
        $dbh->do("delete from ng_page_priv_rules where page_id=?",undef,$page_id) or die $DBI::errstr;
        return 1;
	};
    
    if ($event_name eq "deletelink") {
        my $lang_id = $opts->{LANG_ID};
        my $link_id = $opts->{LINK_ID};
        if ($link_id && $lang_id) {
            $dbh->do("delete from ng_page_privs where link_id=? and lang_id=?",undef,$link_id,$lang_id) or die $DBI::errstr;
            $dbh->do("delete from ng_page_priv_rules where link_id=? and lang_id=?",undef,$link_id,$lang_id) or die $DBI::errstr;
        }
        elsif ($link_id) {
            $dbh->do("delete from ng_page_privs where link_id=?",undef,$link_id) or die $DBI::errstr;
            $dbh->do("delete from ng_page_priv_rules where link_id=?",undef,$link_id) or die $DBI::errstr;
        };
    };

#TODO: посылать эти события, проверять тип события
    if ($event_name eq "deleteadmin") {
        my $adminId = $opts->{ADMIN_ID};
        $dbh->do("delete from ng_page_privs where admin_id=?",undef,$adminId) or die $DBI::errstr;
    };
    if ($event_name eq "deletegroup") {
        my $groupId = $opts->{GROUP_ID};
        $dbh->do("delete from ng_page_privs where group_id=?",undef,$groupId) or die $DBI::errstr;
    };
    if ($event_name eq "deleteprivilege") {
        my $moduleId = $event->sender()->moduleParam('id');
        my $priv = $opts->{PRIVILEGE};
        $dbh->do("delete from ng_page_privs where module_id=? and privilege=?",undef,$moduleId,$priv) or die $DBI::errstr;
        $dbh->do("delete from ng_page_priv_rules where module_id=? and privilege=?",undef,$moduleId,$priv) or die $DBI::errstr;
    };
    return "Privet ya return iz processEvent modulya NG::PagePrivs prosto menya nikogda ne proveryaut i ya vyros takim";    
};

sub _getPageModules {
    my $self = shift;
    my $pageObj = shift;
    
    my $cms = $self->cms();
    
    my @moduleObjs = ();
    
    #Список модулей страницы
    my $modules = undef;
    $modules = $pageObj->getPageModules() if $pageObj->can("getPageModules");
    if (defined $modules) {
        $modules || return $cms->defError("showLocalPrivilegesTab():"," Неизвестный код возврата вызова getPageModules() модуля ".(ref $pageObj));
        ref($modules) eq "ARRAY" or return $cms->error("showLocalPrivilegesTab(): Вызов getPageModules() модуля ".(ref $pageObj)." вернул некорректное значение");
        foreach my $module (@$modules) {
            my $code = $module->{CODE} or return $cms->error("showLocalPrivilegesTab(): Элемент массива, возвращенного getPageModules() модуля ".(ref $pageObj)." не содержит CODE модуля");
            my $row = $cms->getModuleRow("code=?",$code) or return $cms->defError("showLocalPrivilegesTab():","Запрошенный модуль '$code' не найден");
            my $opts = {};
            $opts->{MODULEROW} = $row;
            $opts->{PAGEPARAMS} = $pageObj->getPageRow();
            my $mObj = $cms->getObject($row->{module},$opts);
            return $cms->error("showLocalPrivilegesTab(): Модуль ".$row->{module}." ($code) не содержит метода pageModulePrivileges()") unless $mObj->can("pageModulePrivileges");

            my $mp = $mObj->pageModulePrivileges();
            #return $cms->error("showLocalPrivilegesTab(): Модуль ".(ref $mObj)." не использует привилегии") unless defined $mp;
            #next unless defined $mp;
            return $cms->error("showLocalPrivilegesTab(1): Вызов pageModulePrivileges() модуля ".(ref $mObj)." вернул некорректное значение") if defined $mp && ref $mp ne "ARRAY";
            $mp||=[];
            unshift @$mp, {PRIVILEGE=>"ACCESS",NAME=>"Доступ к блоку/модулю"};# unless ref $mObj eq "NG::PagePrivs::PageAccess";
            
            push @moduleObjs, {MOBJ=>$mObj,MID=>$row->{id}, MNAME=> 'Модуль "'.($row->{name} || $row->{module}).'"', MP=>$mp};
        };
    }
    elsif  ($pageObj->getPageRow()->{module_id}) {
        my $pageRow = $pageObj->getPageRow();
        die "PAGE has no module_id" unless $pageRow->{module_id};
        if ($pageObj->can("pageModulePrivileges")) {
            my $mp = $pageObj->pageModulePrivileges();
            #return $cms->error("showLocalPrivilegesTab(1): Модуль ".(ref $pageObj)." не использует привилегии") unless defined $mp;
            return $cms->error("showLocalPrivilegesTab(1): Вызов pageModulePrivileges() модуля ".(ref $pageObj)." вернул некорректное значение".Dumper($mp)) if $mp && ref $mp ne "ARRAY";
            return $cms->error() if $mp eq "0";
            
            if (defined $mp) {
                push @moduleObjs, {
                    MOBJ=>$pageObj,
                    MID => $pageRow->{module_id},
                    MNAME=> $pageObj->moduleParam('name') || 'Модуль "'.ref($pageObj).'"',
                    MP  => $mp,
                };
            };
        };
    };
    
    #Права на структуру сайта
    if ($cms->{_siteStructObj}) {
        unshift @moduleObjs, {
            MOBJ => $cms->{_siteStructObj},
            MID  => $cms->{_siteStructObj}->moduleParam('id'),
            MNAME => $cms->{_siteStructObj}->moduleParam('name') || "Модуль ".(ref $cms->{_siteStructObj}),
            MP   => $cms->{_siteStructObj}->pageModulePrivileges(),
        };
    };
    #Права на страницу 
    unshift @moduleObjs, {
        MOBJ => $self,
        MID  => $self->moduleParam('id'),
        MNAME =>$self->moduleParam('name') || "Модуль ".(ref $self),
        MP   => $self->pageModulePrivileges(),
    };
    return \@moduleObjs;
};

sub _getModuleH {
    my $self = shift;
    my $mId = shift;
    my $pageObj = shift; #TODO: rework
    
    my $cms = $self->cms();
    my $H = {};
    if ($mId == $self->moduleParam('id')) {
        $H->{mObj} = $self;
        $H->{mp}   = $self->pageModulePrivileges();
        $H->{name} = $self->moduleParam('name') || "Модуль ".(ref $self);
    }
    elsif ($cms->{_siteStructObj} && $mId == $cms->{_siteStructObj}->moduleParam('id')) {
        $H->{mObj} = $cms->{_siteStructObj};
        $H->{mp}   = $cms->{_siteStructObj}->pageModulePrivileges();
        $H->{name} = $cms->{_siteStructObj}->moduleParam('name') || "Модуль ".(ref $cms->{_siteStructObj});
    }
    else {
        my $mRow = $cms->getModuleRow("id=?", $mId) or return $cms->error("Модуль $mId не найден");
        my $opts = {};
        $opts->{MODULEROW} = $mRow;
        $opts->{PAGEPARAMS} = $pageObj->getPageRow();
        $H->{mObj} = $cms->getObject($mRow->{module},$opts);
        return $cms->error("NG::PagePrivs->_getModuleH(): Модуль ".$mRow->{module}." не содержит метода pageModulePrivileges()") unless $H->{mObj}->can("pageModulePrivileges");
        $H->{mp} = $H->{mObj}->pageModulePrivileges();
        #return $cms->error("NG::PagePrivs->_getModuleH(): Модуль ".(ref $H->{mObj})."($mId) не использует привилегии") unless defined $H->{mp};
        return $cms->error("NG::PagePrivs->_getModuleH(): Вызов pageModulePrivileges(2) модуля ".(ref $H->{mObj})." вернул некорректное значение") if $H->{mp} && ref $H->{mp} ne "ARRAY";
        $H->{mp}||=[];
        unshift @{$H->{mp}}, {PRIVILEGE=>"ACCESS",NAME=>"Доступ к блоку/модулю"};
        $H->{name} = ($mRow->{name}||$mRow->{module});
    };
    return $H;
};

package NG::PagePrivs::Block;
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
    
    $self->{_pageId} = undef;
    $self;
};


sub blockAction {
    my $self = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
    my $q   = $cms->q();
    #my $showAll = $q->param('all') || 0;
    #$self->{_showAll} = 0;
    #$self->{_showAll} = 1 if ($showAll == 1);
    #$self->{_pageURL} = $self->getBaseURL();
    #$self->{_pageMode} = 0;
    
    my $action = $q->param('action') || "";
    return $self->switchSubsite($is_ajax) if $action eq "switchsubsite";
    
    my $subUrl = $self->getSubURL();
    
    return $self->showStructureTree($is_ajax) unless $subUrl;
    return $self->showSummary($is_ajax) if $subUrl eq "sum/";
    return $cms->error("Некорректный код страницы") if $subUrl !~ /^(\d+)(?:\/([^\/]+))?\/$/;
    $self->{_pageId} = $1;
    $self->{_tab} = $2 || "local"; #local,inheritable,rules
    
    #$self->{_pageURL} = $self->getBaseURL().$self->{_pageId}."/";
    return $self->run_actions($is_ajax);
};

=head
sub pageBlockAction {
    my $self = shift;
    my $is_ajax = shift;

    my $cms = $self->cms();
    my $q   = $cms->q();
    
    #my $showAll = $q->param('all') || 0;
    #$self->{_showAll} = 0;
    #$self->{_showAll} = 1 if ($showAll == 1);
    $self->{_pageId} = $self->getPageId() or return $cms->error("NG::SiteStruct::pageBlockAction: getPageId() failed");
    #$self->{_pageURL} = $self->getBaseURL();
    #$self->{_pageMode} = 1;
    #$self->{_parentBaseURL} = $self->SUPER::getModuleObj()->getAdminBaseURL();
    return $self->run_actions($is_ajax);
};
=cut

sub showSummary {
    my $self = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
    my $q = $self->q();
    my $m = $self->getModuleObj();
    
    my $tmpl = $cms->gettemplate("admin-side/common/privileges/right.tmpl") or return $cms->error();
    
    $cms->setTabs([
        {URL => "#", AJAX_URL => "", HEADER => "Привилегии - summary", SELECTED => 1,},
    ]);

    my $rootId = undef;
    my $subsiteId = $q->cookie(-name=>"SUBSITEID") || undef;
    #if ($pageId) {
    #    my $pageRow = $cms->getPageRowById($pageId) or return $cms->error("Страница не найдена");
    #    $subsiteId = $pageRow->{subsite_id};
    #};
    
    if ($cms->confParam("CMS.hasSubsites")) {
        my ($subsites,$sSubsite) = $self->_loadSubsitesForCAdmin($subsiteId);
        $subsites or return $cms->error();
        if ($sSubsite) {
            $rootId ||= $sSubsite->{root_node_id};
            #$siteUrl = "http://".$sSubsite->{domain} if $sSubsite->{domain};
        };
        $subsites = [] if (scalar @{$subsites} < 2);
        $tmpl->param(SUBSITES=>$subsites);
    };
    
    my $tree = NG::Nodes->new();
    $tree->initdbparams(
        db     => $self->db(),
        table  => "ng_sitestruct",
        fields => $cms->getPageFields(),
    );

    $tree->loadtree($rootId);
    
    my $res = $tree->traverseWithCheck (
        sub {
            my $_tree = shift;
            my $value = $_tree->getNodeValue();
            
            my $pb = $value->{PAGEBLOCKS} = [];
            
            my $pageObj = $cms->getPageObjByRow($value);
            unless ($pageObj) {
                return 1;
            }
            
            my $moduleObjs = $m->_getPageModules($pageObj);
            return 1 unless $moduleObjs;
            foreach my $t (@$moduleObjs) {
                my $mObj = $t->{MOBJ};
                my $mId  = $t->{MID};
                my $mName = $t->{MNAME};
                my $mp = $t->{MP};
                
                foreach my $priv (@$mp) {
                    $priv->{NAME} ||= "Право ".$priv->{PRIVILEGE};
                    
                    $priv->{PADMIN_ID} = undef;
                    $priv->{PGROUP_ID} = undef;
                    $priv->{ACTIVE}    = undef;
                    
                    #my $a = undef;
                    #if ($adminId) {
                    #    $a = $L1->{"admin$adminId"}->{$pageId}->{$mId}->{$priv->{PRIVILEGE}}->{acting};
                    #    $priv->{PADMIN_ID} = $adminId if defined $a;
                    #};
                    #if (defined $groupId && !defined $a) {
                    #    $a = $L1->{"group$groupId"}->{$pageId}->{$mId}->{$priv->{PRIVILEGE}}->{acting};
                    #    $priv->{PGROUP_ID} = $groupId if defined $a;
                    #};
                    #if ($a) {
                    #    $priv->{ACTIVE} = $a->{ACTIVE};
                    #    
                    #    if ($a->{STORAGEID}) {
                    #        $priv->{STORAGEID} = $a->{STORAGEID};
                    #        #$priv->{NODEACTIVE} = $a->{NODEACTIVE};
                    #        #$priv->{STORAGEACTIVE} = $a->{STORAGEACTIVE};
                    #        $priv->{STORAGENAME} = $a->{STORAGENAME};
                    #    };
                    #};
                };
                my $d = {};
                $d->{NAME} = $mName || "Модуль ".(ref $mObj);
                $d->{PRIVILEGES} = $mp;
                $d->{MODULEID} = $mId;
                push @$pb,$d;
            };

            
            
            #
            #
            #my $m = {};
            #$m->{NAME} = "Привилегии страниц";
            #my $p = $m->{PRIVILEGES} = [];
            #
            #push @$p, {NAME=>"Доступ к странице"};
            #push @$p, {NAME=>"Редактирование прав на страницу"};
            #push @$p, {NAME=>"Редактирование наследуемых прав"};
            #
            #push @$pb, $m;
            #
            #
            #
            #my $m = {};
            #$m->{NAME} = "Структура сайта";
            #my $p = $m->{PRIVILEGES} = [];
            #
            #push @$p, {NAME=>"Редактирование свойств"};
            #push @$p, {NAME=>"Создание страниц"};
            #push @$p, {NAME=>"Удаление страниц"};
            #
            #push @$pb, $m;
           
            return 0;
        }
    );
    
    return $cms->defError("Функция обхода дерева не вернула текст ошибки") if $res;
    
    
    #$template->param(
    #    ADMIN => $adminRow,
    #    ADMINS => \@admins,
    #    SUBSITE => $subsiteRow,
    #    SUBSITES => \@subsites,
    #    SUBSPRIVS => \@tmpSubsitePrivList,
    #    ACTION => $self->getBaseURL(),
    #    ADMIN_IS_IAM => $admin_is_iam,
    #);
    
    $tree->printToDivTemplate($tmpl,'TREE');
    return $cms->output($tmpl);
}

sub showTab {
    my $self = shift;
    my $is_ajax = shift;

    my $cms = $self->cms();

	my $tab = $self->{_tab};
	my $pageId = $self->{_pageId};
    
	my $pageObj = $cms->getPageObjById($pageId) or return $cms->defError("showTab():");
    my @tabs = ();
    
   
    push @tabs, {URL => $self->getBaseURL().$pageId."/local/", AJAX_URL => "", HEADER => "Привилегии",   SELECTED => ($tab eq "local"?1:0) };
    my $canAdd = 0;
    $canAdd = $pageObj->canAddPage() if $pageObj->can("canAddPage");
    if ($canAdd) {
        push @tabs, {URL => $self->getBaseURL().$pageId."/inheritable/", AJAX_URL => "", HEADER => "Наследуемые привилегии", SELECTED => ($tab eq "inheritable"?1:0) };
        push @tabs, {URL => $self->getBaseURL().$pageId."/rules/", AJAX_URL => "", HEADER => "Правила наследования",   SELECTED => ($tab eq "rules"?1:0) };
    };
    $cms->setTabs(\@tabs);
    
    if ($tab eq "local") {
        return $self->showLocalPrivilegesTab($is_ajax,$pageObj);
    }
    elsif ($canAdd ==0) {
        return $cms->error("Страница не позволяет добавления подстраниц, наследуемые привилегии отключены");
    }
    elsif ($tab eq "inheritable") {
        return $self->showInheritTab($is_ajax,$pageObj);
    }
    elsif ($tab eq "rules") {
        return $self->showRulesTab($is_ajax,$pageObj);
    }
    else {
        return $cms->error("Некорректный запрос");
    };
};

sub fillSubjectRights {
    my $self = shift;
    my $subj = shift;
    
    my $phc = shift; #phContext -> PAGE_ID MODULE_ID PRIVILEGE ADMIN_ID|GROUP_ID
    
    my $m = $self->getModuleObj();
    
    my $L1 = undef;
    if (exists $phc->{ADMIN_ID}) {
        $L1 = $m->{_pagePrivilegesL1}->{"admin".$phc->{ADMIN_ID}};
    }
    elsif (exists $phc->{GROUP_ID}) {
        $L1 = $m->{_pagePrivilegesL1}->{"group".$phc->{GROUP_ID}};
    }
    else {
        die "No ADMIN_ID or GROUP_ID";
    };
	die "No PAGE_ID key" unless exists $phc->{PAGE_ID};

    my $l = [];	
	if (exists $L1->{$phc->{PAGE_ID}}) {
		$L1 = $L1->{$phc->{PAGE_ID}};
		if (exists $L1->{$phc->{MODULE_ID}} && $L1->{$phc->{MODULE_ID}}->{$phc->{PRIVILEGE}}) {
			$l = $L1->{$phc->{MODULE_ID}}->{$phc->{PRIVILEGE}}->{full};
		};
	};
        
#use Data::Dumper;
#warn "MODULE_ID ".$phc->{MODULE_ID}." PRIVILEGE ".$phc->{PRIVILEGE};
#warn "fillSubjectRights ".Dumper($l) . " L1 = ".Dumper($L1);
    
    my @sources = ();
    my $hasLocal = 0;
    foreach my $t (@$l) {
        my $s = {};
        $s->{active} = $t->{ACTIVE};
		
        if ($t->{STORAGEID}) {
            $s->{storageId} = $t->{STORAGEID};
            $s->{nodeactive} = $t->{NODEACTIVE};
            $s->{storageactive} = $t->{STORAGEACTIVE};
            $s->{storageName} = $t->{STORAGENAME};
            push @sources, $s;
        }
        else {
            $hasLocal = 1;
            unshift @sources, $s;
        };
    };
    
    unless ($hasLocal) {
        my $s = {};
        $s->{active} = undef;
        unshift @sources, $s;
    };
    $subj->{sources} = \@sources;
    1;
};

sub showLocalPrivilegesTab {
    my $self = shift;
    my $is_ajax = shift;
    my $pageObj = shift;
    
    my $pageRow = $pageObj->getPageRow();
    my $pageId  = $pageObj->getPageId();
    my $subsiteId = $pageObj->getSubsiteId();
    
    my $m = $self->getModuleObj();
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $dbh = $cms->db()->dbh();
    
    my $adminId = $q->param('adminId');
    $adminId = undef unless is_valid_id($adminId);
    my $groupId = $q->param('groupId');
    $groupId = undef unless is_valid_id($groupId) || !defined $groupId || $groupId eq "0";

    
    
    #Проверяем, не требуется ли сделать какое-нибудь действие с привилегиями
    my $do = $q->param("do");
    if ($do) {
        my $moduleId = $q->param('moduleId');
		my $priv = $q->param('privilege');
		
        is_valid_id($moduleId) or return $cms->error("Некорректное значение параметра module");
        my $H = $m->_getModuleH($moduleId,$pageObj) or return $cms->error();
        
        my $privRow = undef;
        foreach my $p (@{$H->{mp}}) {
            if ($priv eq $p->{PRIVILEGE}) {
                $privRow = $p;
                last;
            };
        };
        $privRow or return $cms->error("Заданный модуль не содержит заданную привилегию");
		
        #TODO: Проверяем наличие такого админа в БД
        #TODO: посылать события удаления группы и администратора
        if (defined $groupId) {
            
        }
		elsif ($adminId) {
            
        }
        else {
            return $cms->error("Отсутствует значение субъекта привилегии");
        };
        
        if ($do eq "doallow" || $do eq "dodeny" || $do eq "dodelete") {
            #Загружаем старую привилегию. Проверяем наличие.
            
            my $where = "";
            my @params = ();
            
			if (defined $groupId) {
                $where .= " group_id = ? ";
                push @params, $groupId;
            }
            elsif ($adminId) {
                $where .= " admin_id = ? ";
                push @params, $adminId;
            }
            else {
                die "";
            };
            
            $where .= " and page_id = ? and module_id = ? and privilege = ? and local=1 and storage_node_id is null";
            push @params, $pageId;
            push @params, $moduleId;
            push @params, $priv;

            my $sth = $dbh->prepare_cached("select active from ng_page_privs WHERE $where") or return $cms->error($DBI::errstr);
            $sth->execute(@params) or return $cms->error($DBI::errstr);
            my $oldRow = $sth->fetchrow_hashref();
            $sth->finish();
            
            if ($do eq "doallow" || $do eq "dodeny") {
                my $active = 0;
                $active = 1 if $do eq "doallow";
                if ($oldRow) {
                    unshift @params, $active;
                    $dbh->do("UPDATE ng_page_privs SET active = ? WHERE $where", undef, @params) or return $cms->error($DBI::errstr);
                }
                else {
                    my $sql = "INSERT INTO ng_page_privs (";
                    if (defined $groupId) {
                        $sql .= "group_id,";
                    }
                    elsif ($adminId) {
                        $sql .= "admin_id,";
                    }
                    else {
                        die "Something strange happens";
                    };
                    $sql .= "page_id,module_id,privilege,local,subsite_id,active) values (?,?,?,?,?,?,?)";
                    push @params, 1;
                    push @params, $subsiteId;
                    push @params, $active;
                    $dbh->do($sql,undef,@params) or return $cms->error($DBI::errstr);
                };
            }
            elsif ($do eq "dodelete" && $oldRow) {
                $dbh->do("DELETE FROM ng_page_privs WHERE $where", undef, @params) or return $cms->error($DBI::errstr);
            }
            else {
                die "Something strange happens";
            };
        }
        #elsif ($do eq "disablein") {
        #    my $fromId = $q->param('from');
        #    $dbh->do("UPDATE ng_page_privs SET active = 0 WHERE page_id = ? and admin_id = ? and module_id = ? and privilege = ? and local = 1 and storage_node_id = ?");
        #}
        #elsif ($do eq "deletein") {
        #    $dbh->do("DELETE FROM ng_page_privs WHERE page_id = ? and admin_id = ? and module_id = ? and privilege = ? and local = 1 and storage_node_id = ?");
        #}
		elsif ($do eq "showsources") {
			#
		}
        else {
            return $cms->error("Некорректное действие");
        };
		
		my $adminRow = undef;
		my $groupRow = undef;
		
		if ($adminId) {
			my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins where id = ?") or return $cms->error($DBI::errstr);
			$sth->execute($adminId) or return $cms->error($DBI::errstr);
			$adminRow = $sth->fetchrow_hashref() or return $cms->error("Admin Not Found");
			$sth->finish();
			$groupId = $adminRow->{group_id};
		};
		my $sth = $dbh->prepare("select id,name from ng_admin_groups where id = ?") or return $cms->error($DBI::errstr);
		$sth->execute($groupId) or return $cms->error($DBI::errstr);
		$groupRow = $sth->fetchrow_hashref() or return $cms->error("Group Not Found");
		$sth->finish();		
		
		my $L1 = $m->{_pagePrivilegesL1};
		unless (
			#$do eq "ajaxshowsources" &&
			(!$adminId || (exists $L1->{"admin$adminId"} && exists $L1->{"admin$adminId"}->{$pageId})) &&
			(!defined $groupId || (exists $L1->{"group$groupId"} && exists $L1->{"group$groupId"}->{$pageId}))
		) {
#warn "___!!!___ LOADING $adminId $groupId";
			$m->_loadPagePrivilegesL1(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,PAGE_ID=>$pageId,SUBSITE_ID=>$subsiteId) or return $self->error(" ");
		};
		
		my @subjects = ();
		
		if ($adminId) {
			my $subj = {name=> $adminRow->{fio}, adminId=>$adminId};
			$self->fillSubjectRights($subj,{PAGE_ID=>$pageId, MODULE_ID=>$moduleId, PRIVILEGE=>$priv,ADMIN_ID=>$adminId});
			push @subjects, $subj;
		};
		my $subj = {name=> $groupRow->{name}, groupId=>$groupId,adminId=>$adminId};
		$self->fillSubjectRights($subj,{PAGE_ID=>$pageId, MODULE_ID=>$moduleId, PRIVILEGE=>$priv,GROUP_ID=>$groupId});
		push @subjects, $subj;
		
		my $hash = {};
		$hash->{moduleId} = $moduleId;
		$hash->{privilege} = $priv;
		$hash->{subjects} = \@subjects;
		
		$hash->{padminId} = undef;
		$hash->{pgroupId} = undef;

		my $a = undef;
		if ($adminId) {
			$a = $L1->{"admin$adminId"}->{$pageId}->{$moduleId}->{$priv}->{acting};
			$hash->{padminId} = $adminId if defined $a;
		};
		if (defined $groupId && !defined $a) {
			$a = $L1->{"group$groupId"}->{$pageId}->{$moduleId}->{$priv}->{acting};
			$hash->{pgroupId} = $groupId if defined $a;
		};
		$hash->{active} = undef;
		if ($a) {
			$hash->{active} = $a->{ACTIVE};
			
			if ($a->{STORAGEID}) {
				$hash->{storageId} = $a->{STORAGEID};
				$hash->{storageName} = $a->{STORAGENAME};
			};
		};
		my $json = create_json($hash);
		return $cms->exit($json);
    };
    
    #Загружаем список всех админов, имеющих права на ноду
    my $found = 0;
    my @admins = ();
    my $where = "((page_id=? and subsite_id=?) or (link_id=?)) and local = 1";
    my @values = ($pageRow->{id},$pageRow->{subsite_id},$pageRow->{link_id});

    #my $sth = $dbh->prepare("select * from ng_admins
    #    where id in (select admin_id from ng_page_privs where ($where) and (admin_id>0 or group_id>0))
    #    or id in (select p.admin_id from ng_page_privs as p,(select * from ng_page_privs where ($where) and (admin_id=0 and group_id=0)) as p1 where p1.storage_node_id=p.page_id and p1.storage_link_id=p.link_id)") or return $self->error($DBI::errstr);

    #Отображаем на вкладке "локальные привилегии" список пользователей/групп, включая тех, которые имеют права наследованно
    my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins
where id in (select admin_id from ng_page_privs where $where and admin_id is not null)
or id in (select npp1.admin_id from ng_page_privs npp1, ng_page_privs npp2 where npp1.local=0 and npp1.page_id = npp2.storage_node_id and ((npp2.admin_id is null and npp2.group_id is null) or npp2.admin_id = npp1.admin_id) and npp2.page_id=? and npp2.subsite_id = ? and npp2.local=1)
") or return $cms->error($DBI::errstr);
    $sth->execute(@values,$pageRow->{id},$pageRow->{subsite_id}) or return $cms->error($DBI::errstr);
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
    #my $sth = $dbh->prepare("select id,name from ng_admin_groups where id in (select group_id from ng_page_privs where ($where) and (admin_id>0 or group_id>0)) or id in (select p.group_id from ng_page_privs as p,(select * from ng_page_privs where ($where) and (admin_id=0 and group_id=0)) as p1 where p1.storage_node_id=p.page_id and p1.storage_link_id=p.link_id)") or return $self->error($DBI::errstr);
    $sth = $dbh->prepare("select id,name from ng_admin_groups
where id in (select group_id from ng_page_privs where $where and group_id is not null)
or id in (select npp1.group_id from ng_page_privs npp1, ng_page_privs npp2 where npp1.local=0 and npp1.page_id = npp2.storage_node_id and ((npp2.admin_id is null and npp2.group_id is null) or npp2.admin_id = npp1.admin_id) and npp2.page_id=? and npp2.subsite_id = ? and npp2.local=1)
") or return $self->error($DBI::errstr);
    $sth->execute(@values,$pageRow->{id},$pageRow->{subsite_id}) or return $cms->error($DBI::errstr);
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

#print STDERR "AAA adminId=$adminId groupId=$groupId found=$found DUMPER=".Dumper($adminId,$groupId,$found);
    
    if (!$adminId && defined $groupId && !$found) {
        #Группы еще нет в списке, но ей собираются дать прав, добавляем в список
        $sth = $dbh->prepare("select id,name from ng_admin_groups where id = ?") or return $cms->error($DBI::errstr);
        $sth->execute($groupId) or return $cms->error($DBI::errstr);
        my $groupRow = $sth->fetchrow_hashref() or return $cms->error("Group Not Found");
        $groupRow->{current} = 1;
        $sth->finish();
        push @groups, $groupRow;
    };
    

    my @data = ();
	if ($adminId || defined $groupId) {
    #Загружаем все привилегии
    my $L1 = $m->{_pagePrivilegesL1};
    
    if (
        ($adminId && !(exists $L1->{"admin$adminId"} && exists $L1->{"admin$adminId"}->{$pageId}))
        || (!exists $L1->{"group$groupId"} || !exists $L1->{"group$groupId"}->{$pageId})
       ) {
        $m->_loadPagePrivilegesL1(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,PAGE_ID=>$pageId,SUBSITE_ID=>$subsiteId) or return $self->error();
    };
#    unless (
#			!defined $groupId || (
#			exists $L1->{"admin$adminId"} && exists $L1->{"admin$adminId"}->{$pageId} &&
#			exists $L1->{"group$groupId"} && exists $L1->{"group$groupId"}->{$pageId})
#		) {
#        $m->_loadPagePrivilegesL1(ADMIN_ID=>$adminId,GROUP_ID=>$groupId,PAGE_ID=>$pageId,SUBSITE_ID=>$subsiteId) or return $self->error();
#    };
    #Запрашиваем списки привилегий у модулей страницы
#warn "ADMINID $adminId GROUPID $groupId";
    my $moduleObjs = $m->_getPageModules($pageObj);
    return $cms->error() unless $moduleObjs;
    foreach my $t (@$moduleObjs) {
        my $mObj = $t->{MOBJ};
        my $mId  = $t->{MID};
        my $mName = $t->{MNAME};
        my $mp = $t->{MP};
        
        foreach my $priv (@$mp) {
            $priv->{NAME} ||= "Право ".$priv->{PRIVILEGE};
			
			$priv->{PADMIN_ID} = undef;
			$priv->{PGROUP_ID} = undef;
			$priv->{ACTIVE}    = undef;
			
			my $a = undef;
			if ($adminId) {
				$a = $L1->{"admin$adminId"}->{$pageId}->{$mId}->{$priv->{PRIVILEGE}}->{acting};
				$priv->{PADMIN_ID} = $adminId if defined $a;
			};
			if (defined $groupId && !defined $a) {
				$a = $L1->{"group$groupId"}->{$pageId}->{$mId}->{$priv->{PRIVILEGE}}->{acting};
				$priv->{PGROUP_ID} = $groupId if defined $a;
			};
			if ($a) {
				$priv->{ACTIVE} = $a->{ACTIVE};
				
				if ($a->{STORAGEID}) {
				    $priv->{STORAGEID} = $a->{STORAGEID};
				    #$priv->{NODEACTIVE} = $a->{NODEACTIVE};
				    #$priv->{STORAGEACTIVE} = $a->{STORAGEACTIVE};
				    $priv->{STORAGENAME} = $a->{STORAGENAME};
				};
			};
        };
        my $d = {};
        $d->{NAME} = $mName || "Модуль ".(ref $mObj);
        $d->{PRIVILEGES} = $mp;
        $d->{MODULEID} = $mId;
        push @data,$d;
    };
	};
    
    my $sql="select id,name from ng_sitestruct,(select max(tree_order) as maxorder from ng_sitestruct where tree_order <=? and level <=? group by level) o where tree_order=maxorder and level>0 order by tree_order";
    $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
    $sth->execute($pageRow->{'tree_order'},$pageRow->{'level'});
    my @history = ();
    while(my $row=$sth->fetchrow_hashref()) {
        push @history, $row;
    };
    $sth->finish();
    
    my $tmpl = $cms->gettemplate("admin-side/common/privileges/local.tmpl");
    $tmpl->param(
        PAGENAME => $pageRow->{name},
        PAGEADMINS => \@admins,
        PAGEGROUPS => \@groups,
        MODULES    => \@data,
        PAGEID => $pageRow->{id},
        BASEURL => $self->getBaseURL(),
        ADMIN_ID => $adminId,
        GROUP_ID => $groupId,
        HISTORY  => \@history,
    );
    return $self->output($tmpl);
};

sub addSubj {
    my $self = shift;
    my $action = shift;
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    
    return $self->error("Invalid action") unless $action eq "addadmin" || $action eq "addgroup";
    
    my @data = ();
    my $pageId = $self->{_pageId} or die;
    
    my $pageRow = $cms->getPageRowById($pageId) or return $cms->error("No Page Found");
    
    my $where = "((page_id=? and subsite_id=?) or (link_id=?)) and local = 1";
    my @values = ($pageRow->{id},$pageRow->{subsite_id},$pageRow->{link_id});
    
    my $tmpl = $cms->gettemplate('admin-side/common/privileges/addsubj.tmpl') or return $cms->error();
    
    #TODO: запросы слегка устарели, и не учитывают наличие наследования, см запрос "Загружаем список всех групп, имеющих права на ноду"
    if ($action eq "addadmin") {
        my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins where id  not  in (select admin_id from ng_page_privs where $where and admin_id is not null )") or return $cms->error($DBI::errstr);
        $sth->execute(@values) or return $cms->error($DBI::errstr);
        while(my $row = $sth->fetchrow_hashref()) {
            $row->{name} = $row->{fio}." (".$row->{login}.")";
            push @data, $row;
        };
        $sth->finish();
        $tmpl->param(
            DIVID=>"addAdmin",
            NAME=>"Администратор",
            PARAM_NAME => "adminId",
            DATA => \@data,
            FORMURL => $self->getBaseURL().$pageId."/",
        );
    };
    if ($action eq "addgroup") {
        my $sth = $dbh->prepare("select id,name from ng_admin_groups where id not in (select group_id from ng_page_privs where $where and group_id is not null)") or return $self->error($DBI::errstr);    
        $sth->execute(@values) or return $self->error($DBI::errstr);
        while(my $row = $sth->fetchrow_hashref()) {
            push @data, $row;
        }
        $sth->finish();
        $tmpl->param(
            DIVID=>"addGroup",
            NAME=>"Группа",
            PARAM_NAME => "groupId",
            DATA => \@data,
            FORMURL => $self->getBaseURL().$pageId."/",
        );
    };
    return $cms->exit($tmpl);
};

sub showRulesTab {
    my $self = shift;
    my $is_ajax = shift;
    my $pageObj = shift;


    my $pageRow = $pageObj->getPageRow();
    my $pageId  = $pageObj->getPageId();
    #my $subsiteId = $pageObj->getSubsiteId();
    
    my $m   = $self->getModuleObj();
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q   = $cms->q();
    
    my $do = $q->param('do') || "";
    
    if ($do eq "getModulePrivs") {
        my $mId = $q->param('moduleId');
        return $cms->error("Invalid moduleId") unless is_valid_id($mId);
        
        #Получаем список привилегий выбранного модуля
        my $H = $m->_getModuleH($mId,$pageObj) or return $cms->error();
        my $mp = $H->{mp};
        
        my $privs = {};
        my $sth = $dbh->prepare("select privilege from ng_page_priv_rules where page_id = ? and module_id = ?") or return $self->error($DBI::errstr);    
        $sth->execute($pageId,$mId) or return $self->error($DBI::errstr);
        while(my $row = $sth->fetchrow_hashref()) {
            return $cms->error("В списке правил обнаружено дублирование, модуль ".$mId." привилегия ".$row->{privilege}) if $privs->{$row->{privilege}};
            $privs->{$row->{privilege}} = 1;
        };
        $sth->finish();
        
        my $mp2 = [];
        foreach my $priv (@$mp) {
            next if exists $privs->{$priv->{PRIVILEGE}};
            push @{$mp2}, $priv;
        };
        
		use NHtml;
		my $json = create_json($mp2);
		return $cms->exit($json);
    };
    
    if ($do eq "addRule") {
        my $mId = $q->param('moduleId');
        return $cms->error("Invalid moduleId") unless is_valid_id($mId);
        
        #Получаем список привилегий выбранного модуля
        my $H = $m->_getModuleH($mId,$pageObj) or return $cms->error();
        my $mp = $H->{mp};
        
        my $depth = $q->param('depth');
        return $cms->error("Invalid depth") unless is_valid_id($depth);
        
        my $priv = $q->param('privilege');
        
        my $privs = {};
        my $sth = $dbh->prepare("select privilege from ng_page_priv_rules where page_id = ? and module_id = ?") or return $self->error($DBI::errstr);    
        $sth->execute($pageId,$mId) or return $self->error($DBI::errstr);
        while(my $row = $sth->fetchrow_hashref()) {
            return $cms->error("В списке правил обнаружено дублирование, модуль ".$mId." привилегия ".$row->{privilege}) if $privs->{$row->{privilege}};
            $privs->{$row->{privilege}} = 1;
        };
        $sth->finish();
        
        foreach my $p (@$mp) {
            my $tp = $priv || $p->{PRIVILEGE};
            next unless $tp eq $p->{PRIVILEGE};
            next if exists $privs->{$tp};
            $dbh->do("INSERT INTO ng_page_priv_rules (page_id,module_id,privilege,depth) VALUES (?,?,?,?)",undef, $pageId,$mId,$tp,$depth) or return $self->error($DBI::errstr);
        };
        #return $cms->error() unless $found;
        return $cms->redirect($self->getBaseURL().$pageId."/rules/");
    };
    
    if ($do eq "delRule") {
        my $mId = $q->param('moduleId');
        my $priv = $q->param('priv');
        
        $dbh->do("DELETE FROM ng_page_priv_rules WHERE page_id=? AND module_id=? AND privilege=?",undef, $pageId,$mId,$priv) or return $self->error($DBI::errstr);
        return $cms->redirect($self->getBaseURL().$pageId."/rules/");
    };

    my $modules = {};
    #my $Amodules = [];
    my $sth = $dbh->prepare("select page_id,module_id,privilege,depth from ng_page_priv_rules where page_id = ?") or return $self->error($DBI::errstr);    
    $sth->execute($pageId) or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        #unless exists ($modules->{$row->{module_id}}) {
        #    $modules->{$row->{module_id}} = {};
        #    push @$Amodules, $modules->{$row->{module_id}};
        #};
        return $cms->error("В списке правил обнаружено дублирование, модуль ".$row->{module_id}." привилегия ".$row->{privilege}) if $modules->{$row->{module_id}}->{$row->{privilege}};
        $modules->{$row->{module_id}}->{$row->{privilege}} = $row;
    };
    $sth->finish();
    
    my @data = ();
    foreach my $mId (keys %$modules) {
        my $H = $m->_getModuleH($mId, $pageObj) or return $cms->error();
        
        my $mp = $H->{mp};
        
        my $d = {};
        $d->{ID} =  $mId;
        $d->{NAME} = $H->{name};
        $d->{PRIVS} = [];
        
        my $privs = {};
        #Формируем хэш привилегий, имеющихся у модуля
        foreach my $p (@$mp) {
            $privs->{$p->{PRIVILEGE}} = $p;
        };
        #Проверяем, чтобы привилегия из БД была у модуля
        foreach my $privilege (keys %{$modules->{$mId}}) {
            return $cms->error("Модуль ".$d->{NAME}." не содержит привилегии $privilege") unless exists $privs->{$privilege};
        };
        
        foreach my $priv (@$mp) {
            next unless exists $modules->{$mId}->{$priv->{PRIVILEGE}};
            $priv->{DEPTH} = $modules->{$mId}->{$priv->{PRIVILEGE}}->{depth};
            push @{$d->{PRIVS}}, $priv;
        };
        push @data,$d;
    };
    
    $sth = $dbh->prepare("select id,name from ng_modules where name is not null") or return $self->error($DBI::errstr);    
    $sth->execute() or return $self->error($DBI::errstr);
    my $allModules = $sth->fetchall_arrayref({}) or return $self->error($DBI::errstr);
    $sth->finish();
    
    #unshift @{$allModules}, {id=>$m->moduleParam('id'),name=>"Структура сайта"};
    
    my $sql="select id,name from ng_sitestruct,(select max(tree_order) as maxorder from ng_sitestruct where tree_order <=? and level <=? group by level) o where tree_order=maxorder and level>0 order by tree_order";
    $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
    $sth->execute($pageRow->{'tree_order'},$pageRow->{'level'});
    my @history = ();
    while(my $row=$sth->fetchrow_hashref()) {
        push @history, $row;
    };
    $sth->finish();
    
    my $tmpl = $cms->gettemplate("admin-side/common/privileges/rules.tmpl");
    $tmpl->param(
        DATA=>\@data,
        ALLMODULES=> $allModules,
        FORMURL => $self->getBaseURL().$pageId."/rules/",
        BASEURL => $self->getBaseURL(),
        HISTORY => \@history,
    );
    return $self->output($tmpl);
};

sub showInheritTab {
    my $self = shift;
    my $is_ajax = shift;
    my $pageObj = shift;


    my $pageRow = $pageObj->getPageRow();
    my $pageId  = $pageObj->getPageId();
    #my $subsiteId = $pageObj->getSubsiteId();
    
    my $cms = $self->cms();
    my $q   = $cms->q();
    
    my $do = $q->param('do');
    if ($do eq "showusage") {
        return $self->showInheritUsage($is_ajax, $pageObj);
    };
    if ($do eq "showapply") {
        return $self->showInheritPrivApply($is_ajax, $pageObj);
    };
	
	if ($do eq "inhallow" || $do eq "inhdeny" || $do eq "inhdelete") {
		return $self->inheritPrivAction($is_ajax,$pageObj);
	};
    
    my $m   = $self->getModuleObj();
    my $dbh = $cms->dbh();
    
    #Список прав/модулей формируется:
    #1. Из всех ссылающихся прав
    #2. Из наследуемых привилегий, хранящихся в данной ноде
    #3. Из правил создания наследуемых привилегий, хранящихся в данной ноде
    
    #Формируем список ипользуемых модулей и используемых в них привилегий
    my $modules = {};
    my $sth = $dbh->prepare("select distinct module_id, privilege from ng_page_privs where storage_node_id = ? or (page_id = ? and local = 0)") or return $self->error($DBI::errstr);
    $sth->execute($pageId,$pageId) or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        $modules->{$row->{module_id}}->{$row->{privilege}} = 1;
    };
    $sth->finish();
    
    $sth = $dbh->prepare("select distinct module_id, privilege from ng_page_priv_rules where page_id = ?") or return $self->error($DBI::errstr);
    $sth->execute($pageId) or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        $modules->{$row->{module_id}}->{$row->{privilege}} = 1;
    };
    $sth->finish();
    
    my @data = ();
    foreach my $mId (keys %$modules) {
        my $H = $m->_getModuleH($mId, $pageObj) or return $cms->error();
        #Формируем хэш привилегий, имеющихся у модуля
        my $check = {};
        foreach my $p (@{$H->{mp}}) {
            $check->{$p->{PRIVILEGE}} = $p;
        };
        #Проверяем, чтобы привилегия из БД была у модуля
        foreach my $privilege (keys %{$modules->{$mId}}) {
            return $cms->error("Модуль ".$H->{name}." ($mId) не содержит привилегии $privilege") unless exists $check->{$privilege};
        };
        
        my $d = {};
        $d->{ID} =  $mId;
        $d->{NAME} = $H->{name};
        $d->{PRIVS} = [];
        
        foreach my $priv (@{$H->{mp}}) {
            next unless exists $modules->{$mId}->{$priv->{PRIVILEGE}};
            push @{$d->{PRIVS}}, $priv;
        };
        push @data,$d;
    };
    
    my $sql="select id,name from ng_sitestruct,(select max(tree_order) as maxorder from ng_sitestruct where tree_order <=? and level <=? group by level) o where tree_order=maxorder and level>0 order by tree_order";
    $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
    $sth->execute($pageRow->{'tree_order'},$pageRow->{'level'});
    my @history = ();
    while(my $row=$sth->fetchrow_hashref()) {
        push @history, $row;
    };
    $sth->finish();
    
    my $show = undef;
    if ($q->param('priv') && $q->param('mId')) {
        $show = {};
        $show->{PRIVILEGE} = $q->param('priv');
        $show->{MID}       = $q->param('mId');
    };
    
    my $tmpl = $cms->gettemplate("admin-side/common/privileges/inherit.tmpl");
    $tmpl->param(
        DATA=>\@data,
        FORMURL => $self->getBaseURL().$pageId."/inheritable/",
        HISTORY => \@history,
        BASEURL => $self->getBaseURL(),
        PAGEID => $pageId,
        SHOW   => $show,
    );
    return $self->output($tmpl);
};

sub showInheritUsage {
    my $self = shift;
    my $is_ajax = shift;
    my $pageObj = shift;
    
    my $pageId  = $pageObj->getPageId();
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q   = $cms->q();
=head
    var a = {};
    a.admins = [
        {id:1, name:'Вася Пупкин', active:null},
        {id:2, name:'Петя Иванов', active:1},
        {id:3, name:'Юрий Угорелов',active:0},
        {id:1, name:'Вася Пупкин', active:null},
        {id:2, name:'Петя Иванов', active:1},
        {id:3, name:'Юрий Угорелов',active:0},
        {id:2, name:'Петя Иванов', active:1}
    ];
    a.groups = [
        {id:1, name:'Администраторы новостей', active:0},
        {id:2, name:'Модеры форума', active:null}
    ];
    a.aadmins = [
        {id:10, name:'Новый админ'}
    ];
    a.sgroups = [
        {id:20;, name:'Новая группа'}
    ];
=cut
    #Вход: Страница,Модуль,Привилегия
    #Выход: список Админов и список Групп, которые имеют или наследуют это право + Список Админов и список Групп, которые этого права не имеют.
    #Список админов/групп, имеющих право, формируется:
    #1. Из наследуемых привилегий, хранящихся в данной ноде, с значением привилегии
    #2. Из всех ссылающихся прав, если там указан админ/группа, с значением привилегии "неопределено", дополняя п.1.
    #3. Поскольку правила наследования не содержат админа/группу - то они не используются

    my $mId = $q->param('mId');
    return $cms->error("Invalid moduleId") unless is_valid_id($mId);
    
    my $priv = $q->param('priv');
    
    my $admins = {};
    my $groups = {};
    my $sth = $dbh->prepare("select admin_id, group_id, active from ng_page_privs where page_id = ? and module_id = ? and privilege = ? and local = 0") or return $self->error($DBI::errstr);
    $sth->execute($pageId,$mId,$priv) or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        if ($row->{admin_id}) {
            return $cms->error("Обнаружен дубликат наследуемой привилегии $priv для админа ".$row->{admin_id}." страница $pageId модуль $mId") if exists $admins->{$row->{admin_id}};
            $admins->{$row->{admin_id}} = $row->{active};
        }
        elsif (defined $row->{group_id}) {
            return $cms->error("Обнаружен дубликат наследуемой привилегии $priv для группы ".$row->{group_id}." страница $pageId модуль $mId") if exists $groups->{$row->{group_id}};
            $groups->{$row->{group_id}} = $row->{active};
        }
        else {
            return $cms->error("Строка наследуемых привилегий $priv страницы $pageId модуля $mId не содержит admin_id или group_id");
        };
    };
    $sth->finish();
    #
    my $checkA = {};
    my $checkG = {};
    $sth = $dbh->prepare("select admin_id, group_id from ng_page_privs where storage_node_id = ? and module_id = ? and privilege = ? and local = 1 and (admin_id is not null or group_id is not null)") or return $self->error($DBI::errstr);
    $sth->execute($pageId,$mId,$priv) or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        if ($row->{admin_id}) {
            return $cms->error("Обнаружен дубликат записи-ссылки привилегии $priv для админа ".$row->{admin_id}." страница $pageId модуль $mId") if exists $checkA->{$row->{admin_id}};
            $checkA->{$row->{admin_id}} = 1;
            $admins->{$row->{admin_id}} = undef unless exists $admins->{$row->{admin_id}};
        }
        elsif (defined $row->{group_id}) {
            return $cms->error("Обнаружен дубликат записи-ссылки привилегии $priv для группы ".$row->{group_id}." страница $pageId модуль $mId") if exists $checkG->{$row->{group_id}};
            $checkG->{$row->{group_id}} = 1;
            $groups->{$row->{group_id}} = undef unless exists $groups->{$row->{group_id}};
        }
        else {
            return $cms->error("Строка наследуемых привилегий $priv от страницы $pageId модуля $mId не содержит admin_id или group_id");
        };
    };
    $sth->finish();
    #Массив выходных данных
    my $data = {};
    $data->{admins} = [];  #Админы с правом {id,name,active}
    $data->{groups} = [];  #Группы с правом {id,name,active}
    $data->{aadmins} = []; #Админы без права {id,name}
    $data->{agroups} = []; #Группы без права {id,name}
    #
    #Загружаем полный список админов    
    $sth = $dbh->prepare("select id,login,fio from ng_admins") or return $self->error($DBI::errstr);    
    $sth->execute() or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        my $h = {
            id => $row->{id},
            name => $row->{fio}." (".$row->{login}.")",
        };
        if (exists $admins->{$row->{id}}) {
            $h->{active} = $admins->{$row->{id}}; 
            push @{$data->{admins}}, $h;
        }
        else {
            push @{$data->{aadmins}}, $h;
        };
    };
    $sth->finish();

    #Загружаем полный список групп
    $sth = $dbh->prepare("select id,name from ng_admin_groups") or return $self->error($DBI::errstr);
    $sth->execute() or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        my $h = {
            id => $row->{id},
            name => $row->{name},
        };
        if (exists $groups->{$row->{id}}) {
            $h->{active} = $groups->{$row->{id}}; 
            push @{$data->{groups}}, $h;
        }
        else {
            push @{$data->{agroups}}, $h;
        };
    };
    $sth->finish();
    
    my $json = create_json($data);
    return $cms->exit($json);
};

sub showInheritPrivApply {
    my $self = shift;
    my $is_ajax = shift;
    my $pageObj = shift;
    
    my $pageId  = $pageObj->getPageId();
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q   = $cms->q();

    my $moduleId = $q->param('mId');
    return $cms->error("Invalid moduleId") unless is_valid_id($moduleId);
    
    my $priv = $q->param('priv');

    my $adminId = $q->param('adminId');
    $adminId = undef unless is_valid_id($adminId);
    my $groupId = $q->param('groupId');
    $groupId = undef unless is_valid_id($groupId) || $groupId eq 0;
    
    #Вход: Страница,Модуль,Привилегия, пользователь или группа
    #Выход: список страниц, которые наследуют право от страницы Страница, с указанием текущего значения права для запрошенной пользователя / группы

    #Список страниц формируется:
    #1. Из наследуемых привилегий, хранящихся в данной ноде, с значением привилегии
    #2. Из всех ссылающихся прав, если там указан админ/группа, с значением привилегии "неопределено", дополняя п.1.
    #3. Поскольку правила наследования не содержат админа/группу - то они не используются
    
    #Выход:
    #[
    #{pageId: 1, pageName: 'Имя страницы', active: (0|1|null), storageId: 2, storageName:'Имя другой страницы'}, #право на pageId наследуется со storageId
    #{pageId: 1, pageName: 'Имя страницы', active: (0|1|null)}, #право перепределено локально
    #{pageId: 1, pageName: 'Имя страницы', active: (0|1|null), pgroupId: 1, pgroupName: 'Имя группы'} #Админу локальное право предоставляется от его группы
    #{pageId: 1, pageName: 'Имя страницы', active: (0|1|null), storageId: 2, storageName:'Имя другой страницы',pgroupId: 1, pgroupName: 'Имя группы'}, #Админу наследованное право предоставляется от его группы
    #]
    #При не указанном storageId право на страницу pageId переопределено локально
    #В частном случае, когда storageId совпадает с pageId ноды хранения привилегий, морда выводит надпись "с этого уровня"
    #В остальных случаях право на страницу pageId определено нодой storageId с именем storageNode
    #Право может быть предоставленно группой, в этм случае имеются ключи pgroupId, pgroupName
    #
    my $aGroupName = undef; #Имя группы админа
    #
    my $where = "";
    my @params = ();
    if (defined $groupId) {
        $where = "group_id = ?";
        push @params, $groupId;
    }
    elsif ($adminId) {
        #Загружаем код группы админа и её имя
        my $sth = $dbh->prepare("select a.group_id,g.name from ng_admins a, ng_admin_groups g where a.id = ? and a.group_id = g.id") or return $cms->error($DBI::errstr);
        $sth->execute($adminId) or return $cms->error($DBI::errstr);
        my $row = $sth->fetchrow_hashref() or return $cms->error("Admin $adminId Not Found");
        $groupId = $row->{group_id};
        $aGroupName = $row->{name};
        $sth->finish();
        #
        $where = "admin_id = ?";
        push @params, $adminId;
    }
    else {
        return $cms->error("No adminId or groupId");
    };
    #Загружаем все права админа/группы
    my $m = $self->getModuleObj();
    $m->_loadPagePrivilegesL1(ADMIN_ID=>$adminId, GROUP_ID=>$groupId, SUBSITE_ID=>$pageObj->getSubsiteId());
    my $L1 = $m->{_pagePrivilegesL1};
#print STDERR "L1=".Dumper($L1);
#print STDERR "aId -$adminId- gId -$groupId- mId -$moduleId- pageId -$pageId- priv -$priv-";
    #
    #Формируем список страниц, наследующих привилегию
    my @data = ();
    my $sth = $dbh->prepare("select ss.id, ss.name, pp.page_id from ng_page_privs pp left join ng_sitestruct ss on pp.page_id = ss.id where pp.storage_node_id = ? and pp.module_id = ? and pp.privilege = ? and ($where or (admin_id is null and group_id is null))") or return $self->error($DBI::errstr);
    $sth->execute($pageId,$moduleId,$priv,@params) or return $self->error($DBI::errstr);
    while(my $row = $sth->fetchrow_hashref()) {
        return $cms->error("Обнаружена запись-ссылка права наследования привилегии $priv модуля $moduleId для удаленной страницы id=".$row->{page_id}) unless defined $row->{id};
        my $h = {};
        $h->{pageId} = $row->{id};
        $h->{pageName} = $row->{name};
        
        my $act = undef;
        if ($adminId) {
            $act = $L1->{"admin$adminId"}->{$row->{id}}->{$moduleId}->{$priv}->{acting};
            #$hash->{padminId} = $adminId if defined $act;
        };
#print STDERR "A=".Dumper($act);
        if (defined $groupId && !defined $act) {
            $act = $L1->{"group$groupId"}->{$row->{id}}->{$moduleId}->{$priv}->{acting};
            if ($adminId && defined $act) {
                $h->{pgroupId} = $groupId;
                $h->{pgroupName} = $aGroupName;
            };
        };
#print STDERR "G=".Dumper($act);
        $h->{active} = undef;
        if ($act) {
            $h->{active} = $act->{ACTIVE};
            
            if ($act->{STORAGEID}) {
                $h->{storageId} = $act->{STORAGEID};
                $h->{storageName} = $act->{STORAGENAME};
            };
        };
        push @data,$h;
    };
    $sth->finish();
#print STDERR "DATA=".Dumper(@data);
    my $json = create_json(\@data);
    return $cms->exit($json); 
};

sub inheritPrivAction {
    my $self = shift;
    my $is_ajax = shift;
    my $pageObj = shift;
    
    my $pageId  = $pageObj->getPageId();
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q   = $cms->q();
    my $m = $self->getModuleObj();
    
    my $moduleId = $q->param('mId');
    return $cms->error("Invalid moduleId") unless is_valid_id($moduleId);
    
    my $adminId = $q->param('adminId');
    $adminId = undef unless is_valid_id($adminId);
    my $groupId = $q->param('groupId');
    $groupId = undef unless is_valid_id($groupId) || $groupId eq 0;
    
    my $do = $q->param("do");
    my $mId = $q->param('mId');
    my $priv = $q->param('priv');
    
    is_valid_id($mId) or return $cms->error("Некорректное значение параметра module");
    my $H = $m->_getModuleH($mId,$pageObj) or return $cms->error();
    
    #Привилегия. Проверяем наличие в модуле.
    my $mp = $H->{mp};
    my $privRow = undef;
    foreach my $p (@$mp) {
        if ($priv eq $p->{PRIVILEGE}) {
            $privRow = $p;
            last;
        };
    };
    $privRow or return $cms->error("Заданный модуль не содержит заданную привилегию");
    
    my $where = "";
    my @params = ();
    my $name = "";
    if (defined $groupId) {
        my $sth = $dbh->prepare("select id,name from ng_admin_groups where id = ?") or return $cms->error($DBI::errstr);
        $sth->execute($groupId) or return $cms->error($DBI::errstr);
        my $groupRow = $sth->fetchrow_hashref() or return $cms->error("Group Not Found");
        $sth->finish();
        $name = $groupRow->{name};
        
        $where .= " group_id = ? ";
        push @params, $groupId;
    }
    elsif ($adminId) {
        my $sth = $dbh->prepare("select id,login,fio,group_id from ng_admins where id = ?") or return $cms->error($DBI::errstr);
        $sth->execute($adminId) or return $cms->error($DBI::errstr);
        my $adminRow = $sth->fetchrow_hashref() or return $cms->error("Admin Not Found");
        $sth->finish();
        $name = $adminRow->{fio}." (".$adminRow->{login}.")";
        
        $where .= " admin_id = ? ";
        push @params, $adminId;
    }
    else {
        return $cms->error("Отсутствует значение субъекта привилегии");
    };
    
    $where .= " and page_id = ? and module_id = ? and privilege = ? and local=0";
    push @params, $pageId;
    push @params, $mId;
    push @params, $priv;
    
    my $sth = $dbh->prepare_cached("select active from ng_page_privs WHERE $where") or return $cms->error($DBI::errstr);
    $sth->execute(@params) or return $cms->error($DBI::errstr);
    my $oldRow = $sth->fetchrow_hashref();
    $sth->finish();
    
    my $active = undef;
    if ($do eq "inhallow" || $do eq "inhdeny") {
        $active = 0;
        $active = 1 if $do eq "inhallow";
        if ($oldRow) {
            unshift @params, $active;
            $dbh->do("UPDATE ng_page_privs SET active = ? WHERE $where", undef, @params) or return $cms->error($DBI::errstr);
        }
        else {
            my $sql = "INSERT INTO ng_page_privs (";
            if (defined $groupId) {
                $sql .= "group_id,";
            }
            elsif ($adminId) {
                $sql .= "admin_id,";
            }
            else {
                die "Something strange happens";
            };
            $sql .= "page_id,module_id,privilege,local,subsite_id,active) values (?,?,?,?,?,?,?)";
            push @params, 0;
            push @params, $pageObj->getSubsiteId();
            push @params, $active;
            $dbh->do($sql,undef,@params) or return $cms->error($DBI::errstr);
        };
    }
    elsif ($do eq "inhdelete" && $oldRow) {
        $dbh->do("DELETE FROM ng_page_privs WHERE $where", undef, @params) or return $cms->error($DBI::errstr);
    }
    else {
        die "Something strange happens";
    };
    
    my $data = {};
    $data->{name} = $name;
    $data->{active} = $active;
    my $json = create_json($data);
    return $cms->exit($json);
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
    #TODO: аналогичный код в NG::SiteStruct
    
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

sub showStructureTree {
    my $self = shift;
    my $is_ajax = shift; 

    my $cms = $self->cms();
    my $q   = $cms->q();
	my $dbh = $cms->db()->dbh();
    
	my $tmpl = $cms->gettemplate("admin-side/common/privileges/tree.tmpl");
    
    my $showAll = 0; #$q->param('all') || 0;

    $cms->setTabs([
        {URL => "#", AJAX_URL => "", HEADER => "Привилегии - структура сайта", SELECTED => 1,},
    ]);
   
    my $pageId = $q->param('pageId') || undef;
    
    
    my $rootId = undef;
    my $subsiteId = $q->cookie(-name=>"SUBSITEID") || undef;
    if ($pageId) {
        my $pageRow = $cms->getPageRowById($pageId) or return $cms->error("Страница не найдена");
        $subsiteId = $pageRow->{subsite_id};
    };
    
    #my $siteUrl = "http://".$q->virtual_host(); #"http://site"
    if ($cms->confParam("CMS.hasSubsites")) {
        my ($subsites,$sSubsite) = $self->_loadSubsitesForCAdmin($subsiteId);
        $subsites or return $cms->error();
        if ($sSubsite) {
            $rootId ||= $sSubsite->{root_node_id};
            #$siteUrl = "http://".$sSubsite->{domain} if $sSubsite->{domain};
        };
        $subsites = [] if (scalar @{$subsites} < 2);
        $tmpl->param(SUBSITES=>$subsites);
    };
    
    my $tree = NG::Nodes->new();
	$tree->initdbparams(
        db     => $self->db(),
        table  => "ng_sitestruct",
        fields => "name,full_name,title,url,module_id,template,print_template,disabled",
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
            
            $value->{AURL} = $self->getBaseURL().$value->{id}."/";
            $value->{PRIVILEGES}->{DELPAGE} = 1;
        }
    );
    
	$tree->printToDivTemplate($tmpl,'TREE',$pageId);
    
    $tmpl->param(
        SHOW_ALL => $showAll,
        BASEURL  => $self->getBaseURL(),
    );
    return $self->output($tmpl->output());
};

return 1;
END{};
