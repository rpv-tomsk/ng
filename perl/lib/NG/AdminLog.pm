package NG::AdminLog;

use strict;
use NGService;
use vars qw(@ISA);
use NG::Module;
use Data::Dumper;
@ISA = qw(NG::Module);

sub moduleTabs {
    return [
        {HEADER=>"Логи",URL=>"/"}
    ];
};

sub moduleBlocks {
    return [
        {BLOCK=>"NG::AdminLog::List",URL=>"/"}
    ];
};

sub processEvent {
    my $self = shift;
    my $event = shift;
    
    my $cms = $self->cms();
    my $q = $self->q();
    my $dbh = $self->dbh();
    my $db = $self->db();
    my $ip = $q->remote_host();
    my $sender = $event->sender();
    my $options = $event->options();
    my $page_id = $options->{page_id};
    $page_id = !$page_id && $sender->can("getPageId")?$sender->getPageId():0;
    
    my ($module_name) = $dbh->selectrow_array("select name from ng_modules where module=?",undef,(ref $sender));
use Data::Dumper; 
warn Dumper(ref $sender);
    $module_name  = "Неизвестный модуль" unless $module_name;
    my $admin = $cms->_getAdmin();
    
    my %params = ();
    $params{admin_id} = $admin->{id};
    $params{admin_name} = sprintf("%s(%s)",$admin->{login},$admin->{fio});
    $params{page_id} = $page_id;
    $params{log_time} = current_datetime(),
    $params{module_name} = $module_name;
    $params{operation} = $options->{operation};
    $params{operation_param} = $options->{operation_param};
    $params{ip} = $ip;
    
    map {$params{$_} = $options->{$_}} keys %$options;
     
        
    $dbh->do("insert into ng_admin_logs(admin_id,admin_name,page_id,log_time,module_name,operation,operation_param,ip) values(?,?,?,?,?,?,?,?)",
        undef,
        @params{qw(admin_id admin_name page_id log_time module_name operation operation_param ip)}
    ) or die ;
};

1;

package NG::AdminLog::List;

use strict;
use NG::Module::List;
use vars qw(@ISA);

@ISA = qw(NG::Module::List);

sub config {
    my $self = shift;
    $self->{_table} = "ng_admin_logs";
    $self->{_onpage} = 50;
    
    $self->fields(
        {FIELD=>"id",TYPE=>"id"},
        {FIELD=>"admin_id",TYPE=>"select",
            OPTIONS => {
                TABLE => "ng_admins",
                NAME_FIELD_QUERY => "(fio || ' (' || login || ')') as name"
            }
        },
        {FIELD=>"admin_name",TYPE=>"text",NAME=>"Админ"},
        {FIELD=>"log_time",TYPE=>"datetime",NAME=>"Время доступа"},
        {FIELD=>"module_name",TYPE=>"text",NAME=>"Название модуля"},
        {FIELD=>"operation",TYPE=>"text",NAME=>"Действие"},
        {FIELD=>"operation_param",TYPE=>"text",NAME=>"Параметры"},
        {FIELD=>"ip",TYPE=>"text",NAME=>"IP"}
    );
    
    $self->listfields(
        {FIELD=>"admin_name",TYPE=>"text"},
        {FIELD=>"log_time",TYPE=>"datetime"},
        {FIELD=>"module_name",TYPE=>"text"},
        {FIELD=>"operation",TYPE=>"text"},
        {FIELD=>"operation_param",TYPE=>"text"},
        {FIELD=>"ip",TYPE=>"text"}        
    );
    
    $self->disableAddlink();
    $self->disableEditlink();
    $self->disableDeletelink();
    
    $self->order({FIELD=>"log_time",DEFAULT=>1,DEFAULTBY=>"DESC",ORDER_DESC=>"log_time desc, id desc",ORDER_ASC=>"log_time asc, id asc"});
    
    $self->filter(
		NAME=>"Администратор",
        VALUES=>[
            {NAME=>"Все администраторы",WHERE=>""},
        ],
        LINKEDFIELD=>'admin_id'    
    );

    my $modules = $self->dbh->selectall_arrayref("select distinct(module_name) as module from ng_admin_logs",{Slice=>{}});
    my @modules_filter = ({NAME=>"Все",WHERE=>""});
    foreach (@$modules) {
        push @modules_filter, {NAME=>$_->{module},WHERE=>"module_name=?",VALUE=>[$_->{module}]};
    };    
    $self->filter(
        FILTER_NAME => "fmodule",
		NAME=>"Модуль",
        VALUES=>\@modules_filter
    );

    my $operation = $self->dbh->selectall_arrayref("select distinct(operation) as operation from ng_admin_logs",{Slice=>{}});
    my @operation_filter = ({NAME=>"Все",WHERE=>""});
    foreach (@$operation) {
        push @operation_filter, {NAME=>$_->{operation},WHERE=>"operation=?",VALUE=>[$_->{operation}]};
    };    
    $self->filter(
        FILTER_NAME => "foperation",
		NAME=>"Действие",
        VALUES=>\@operation_filter
    );
    
};

1;