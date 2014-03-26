package NG::Module;
use strict;

use Carp qw(cluck);

$NG::Module::VERSION=0.5;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_) or return undef;
    #$self->config();
    return $self; 
};

sub init {
	my $self = shift;
    my $opts = shift || {};
    $self->{_pParamsRaw}   = delete $opts->{PLUGINPARAMS};
    $self->{_adminBaseURL} = delete $opts->{ADMINBASEURL};
    $self->{_pageRow}      = delete $opts->{PAGEPARAMS};
    $self->{_moduleRow}    = delete $opts->{MODULEROW};
    $self->{_opts}   = $opts;
    $self->{_params} = undef;   #For params from ng_module.params
    $self->{_pluginparams} = undef;   #For params from ng_block.params
    $self;
};

# Использующие pageRow методы сдублированы в NG::Block
sub getPageRow  {
    my $self=shift;
	$self->{_pageRow} or cluck ref($self)."::_pageRow() not initialised";
    return $self->{_pageRow};
};

sub getPageObj {
    my $self = shift;
    return $NG::Application::pageObj;
};


sub gettemplate
{
    my $self = shift;
    my $template_file = shift;
    my $template =$self->cms->gettemplate($template_file) or return $self->cms->error();
    $self->bindResource($template);    
    return $template;
};

sub bindResource {
    my $self= shift;
    my $tmplObj = shift;
    my $cms = $self->cms();
    my $rObj = $cms->getObject("NG::ResourceController",$self) or return $cms->error();
    $tmplObj->param(
        RES => $rObj
    );
    return 1;
};
sub getResource {
    my $self = shift;
    my $name = shift;

    my $cms = $self->cms();
    my $code = $self->getModuleCode() or return $cms->error();
    my $row = $self->getPageRow() || {};
    
    my @cnf = (
        {PREFIX=>"P",KEY=>"id"},
        {PREFIX=>"LI",KEY=>"link_id"},
        {PREFIX=>"S",KEY=>"subsite_id"},
        {PREFIX=>"L",KEY=>"lang_id"},
        {PREFIX=>""},
    );
    
    my $ssr = $cms->getSubsiteRow()||{};
 
    $row->{subsite_id} = $ssr->{id} unless exists $row->{subsite_id};
    $row->{lang_id}     = $ssr->{lang_id} unless exists $row->{lang_id};
    
    foreach (@cnf) {
        next if $_->{KEY} && !exists $row->{$_->{KEY}};
        my $module = $cms->confParam("Resource.".$code.($_->{PREFIX}?"_".$_->{PREFIX}.$row->{$_->{KEY}}:""));
        next unless $module;
        my $obj = $cms->getObject($module) or return $cms->error();
        my $value = $obj->getResource($name,
            {
                subsite_id => $row->{subsite_id},
                page_id => $row->{id},
                link_id => $row->{link_id},
                lang_id => $row->{lang_id},
            }
        );
        return $value if defined $value;
    };
    return $cms->getResource($name);
};

#Свойства более глобальные, свойства обрабатываемой верхушкой страницы
sub getPageId       { my $self=shift;  return $self->getPageRow()->{id};  };
sub getSubsiteId    { my $self=shift;  return $self->getPageRow()->{subsite_id};  };
sub getPageLinkId   { my $self=shift;  return $self->getPageRow()->{link_id}; };
sub getPageLangId   { my $self=shift;  return $self->getPageRow()->{lang_id}; };
sub getParentPageId { my $self=shift;  return $self->getPageRow()->{parent_id}; };
sub getParentLinkId {
    my $self=shift;
    my $pageRow = $self->getPageRow();
    return $pageRow->{parent_link_id} if exists $pageRow->{parent_link_id};
    $pageRow->{parent_link_id} ||= $self->db()->dbh()->selectrow_array("select link_id from ng_sitestruct where id=? ",undef,$pageRow->{parent_id}) or return $self->error($DBI::errstr);
    return $pageRow->{parent_link_id};
};

sub pageParam {
    my $self = shift;
    my $param = shift or cluck("pageParam(): no key specified");
    
    unless (exists $self->{_pageRow}->{$param}) {
        cluck "pageParam(): key $param does not exists in page parameters hash";
        return undef;
    };
    return $self->{_pageRow}->{$param};
};

sub opts {
    my $self = shift;
    return $self->{_opts};
}; 

# Параметры модуля, из ng_modules

sub getBaseURL {
    my $self = shift;
    return $self->moduleParam('base');
};

sub moduleParam {
	my $self = shift;
	my $param = shift or cluck("moduleParam(): no key specified");
	$self->{_moduleRow} or cluck ref($self)."::_moduleRow() not initialised";
	return $self->{_moduleRow}->{$param} if exists $self->{_moduleRow}->{$param};
	$self->{_params}||=$self->_parseParams($self->{_moduleRow}->{params});
	return $self->{_params}->{$param} if exists $self->{_params}->{$param};
	return undef;
};

sub pluginParam {
    #Метод вредный. Параметры плагина/модуля передаются параметром
    #вызова getBlockKeys()/getBlockContent(), и должны бы использоваться оттуда
	my $self = shift;
	my $param = shift or cluck("pluginParam(): no key specified");
    $self->{_pluginparams}||=$self->_parseParams($self->{_pParamsRaw});
    return $self->{_pluginparams}->{$param} if exists $self->{_pluginparams}->{$param};
	return undef;
};

sub getModuleCode {
    my $self = shift;
    
    if (ref $self) {
        return $self->{_moduleRow}->{code} if $self->{_moduleRow} && exists $self->{_moduleRow}->{code};
        $self = ref $self;
    };
    
    my $cms = $self->cms();
    my $hash = $cms->modulesHash({REF=>$self});
    return $cms->defError("getModuleCode():","modulesHash() не вернул значения для REF $self") unless $hash;
    return $cms->error("getModuleCode(): возвращенное modulesHash() значение не HASHREF") if ref $hash ne "HASH";
    
    my $code = undef;
    foreach my $key (keys %$hash) {
        next if $hash->{$key}->{MODULE} ne $self;
        return $cms->error("getModuleCode(): Модуль $self соответствует нескольким кодам - $key и $code") if defined $code;
        $code = $key;
    };
    return $cms->error("getModuleCode(): Не могу найти CODE модуля $self") unless $code;
    return $code;
};

sub getSelfInstance() {
    my $self = shift;
    my $cms = $self->cms();
    my $code = $self->getModuleCode() or return $cms->error();
    return $cms->getModuleInstance($code);
};

sub _parseParams {
	my $self = shift;
    #my $t = 'f1:v1,  f2: 2, f3: \'asdasdasd, \' asd\', f4 : "asdasdasdas, \\"asd"';
    my $t = shift;
    return {} unless $t;
    my $h = {};
    while ($t =~ /\s*([^\:\,]+?)\s*\:\s* (?: [\"\'] ( (?<=[\"]) .* (?=(?<![\\])[\"]) | (?<=[\']) .* (?=(?<![\\])[\']) ) [\"\'] | ([^\,]+)  ) /gx) {
        my $v;
        $v = $2 if $2;
        $v = $3 if $3;
        $h->{$1} = $v;
    };
    return $h;
};


sub setStash { # $mObj->setStash($key,$value)
    my $self = shift;
    
    my $c = $self->getModuleCode() or die "NG::Module->setStash(): Can`t get ModuleCode";
    my $m = ($NG::Application::cms->{_mstash}->{$c} ||= {});
    
    die "NG::Module->setStash(): No KEY" if (scalar @_ == 0);
    if (scalar @_ == 1) {
        delete $m->{$_[0]};
        return undef;
    };
    die "NG::Module->setStash(): Incorrect parameters count" if (scalar @_ % 2);
    my ($key,$value);
    while (@_) {
        ($key,$value) = (shift,shift);
        warn "NG::Module->setStash(): key $key already has value" if exists $m->{$key};
        $m->{$key} = $value;
    };
    $value;
};

sub getStash { # $mObj->getStash($key)
    my $self = shift;
    my $key  = shift or die "NG::Module->getStash(): No KEY";

    my $c = $self->getModuleCode() or die "NG::Module->setStash(): Can`t get ModuleCode";
    my $m = ($NG::Application::cms->{_mstash}->{$c} ||= {});
    
    unless (exists $m->{$key}) {
        warn "getStash(): key $key not found";
        return undef;
    };
    return $m->{$key};
};

sub getInterface {
    my $self = shift;
    my $interfaceName = shift or die "getInterface(): No interface name specified";
    
    my $cms = $self->cms();
    
    my $classHash = undef;
    # пытаемся получить из модуля определённые в нём интерфейсы
    while (1) {
        last unless $self->can('moduleInterfaces');
        my $mInterfaces = $self->moduleInterfaces() or last;
        if (defined $mInterfaces && ref $mInterfaces ne "HASH") {
            die "Module ".$self->getModuleCode()." moduleInterfaces() returns unsupported value";
        };
        
        $classHash = $mInterfaces->{$interfaceName};
        if (ref($classHash)) {
            return $classHash if UNIVERSAL::can($classHash,"can");
            die "Module ".$self->getModuleCode()." moduleInterfaces() returns unsupported value in interfaces hash" if ref($classHash) ne "HASH";
        };
        last;
    };
    #проверим не задан ли в конфиге класс, который следует использовать как класс интерфейса.
    unless ($classHash) {
        #Класс интерфейса для определенного модуля
        my $class = $cms->confParam("INTERFACE_".$interfaceName.".".$self->getModuleCode()."_class");
        #дефолтный класс интерфейса
        $class ||=  $cms->confParam("INTERFACES.".$interfaceName."_class");
        $classHash->{CLASS} = $class;
    };
    
    return $cms->getObject($classHash,{PARENT=>$self}) if $classHash;
    return undef;
}


#API работы с модулем из админки

#TODO: переименовать...
sub getAdminBaseURL { my $self=shift; return $self->{_adminBaseURL} || ""; };
#sub setBaseURL { my $self = shift; $self->{_baseURL}  = shift; }

sub getAdminSubURL {
    my $self = shift;
 
    my $q   = $self->cms()->q();
    my $url = $q->url(-absolute=>1);
    my $baseUrl = $self->getAdminBaseURL();
    my $subUrl = ($url =~ /^$baseUrl(.+)/ ) ? $1 : "";
    return $subUrl;
};

# runBlock и runModule - не совсем интуитивно понятно.
sub runBlock {
    my $self = shift;
    my $classDef = shift;
    my $is_ajax = shift;
    my $opts    = shift || {};
    
    my $cms = $self->cms();
    $opts->{MODULEOBJ} =  $self;
    my $bObj = $cms->getObject($classDef,$opts) or return $cms->error();

    return $cms->error("Модуль ".$classDef->{CLASS}." не содержит метода pageBlockAction") unless $bObj->can("pageBlockAction");
	return $bObj->pageBlockAction($is_ajax);
};

sub runModule {
    my $self = shift;
    my $classDef = shift;
    my $is_ajax = shift;
    my $opts    = shift || {};

    my $cms = $self->cms();
    $opts->{MODULEOBJ} =  $self;
    my $bObj = $cms->getObject($classDef,$opts) or return $cms->error();

    return $cms->error("Модуль ".$classDef->{CLASS}." не содержит метода blockAction") unless $bObj->can("blockAction");
	return $bObj->blockAction($is_ajax);
};

sub moduleTabs {
    my $self = shift;
    my $cms = $self->cms();
    return $cms->error("Класс ".(ref $self)." не содержит методов getModuleTabs() или moduleTabs()");
};

sub getModuleTabs {
    #Возвращает список вкладок модуля, с проверкой привилегий и выбором текущей вкладки
    my $self = shift;
    
    my $cms = $self->cms();
    
    my $mtabs = $self->moduleTabs();
    return $cms->defError((ref $self)."->moduleTabs():") if defined $mtabs && $mtabs eq "0";
    unless ($mtabs && ref $mtabs eq "ARRAY") {
        my $e = $cms->getError("Вызов ".(ref $self)."->moduleTabs() не вернул массива значений");
        return $cms->error($e);
    };
    
    my $baseUrl = $self->getAdminBaseURL();
    my $suburl = $self->getAdminSubURL() || "/";

    my @tabs = ();
    my $pActiveTab = {url=>"",tab=>undef};
    
    foreach my $mtab (@{$mtabs}) {
        my $hasTabAccess = 0;
        if (exists $mtab->{PAGEPRIVILEGE}) {
            $hasTabAccess = $self->hasPageModulePrivilege($mtab->{PAGEPRIVILEGE});
        }
        elsif (exists $mtab->{PRIVILEGE}) {
            $hasTabAccess = $self->hasModulePrivilege($mtab->{PRIVILEGE});
        }
        else {
            $hasTabAccess = 1;
        };
=comment
        elsif ($self->canEditLinkBlock()) {
            my $langId = 0;
            $langId = $self->getPageLangId() if $self->isLangLinked();

            $hasTabAccess = 1 if $self->hasLinkBlockPrivilege(LINK_ID => $self->getPageLinkId(),LANG_ID=>$langId, BLOCK_ID => 1, PRIVILEGE => $mtab->{PRIVILEGE}, SUBSITE_ID => $self->getSubsiteId());
        }
        elsif ($self->canEditPageBlock())  {
            $hasTabAccess = 1 if $self->hasPageBlockPrivilege(PAGE_ID => $self->getPageId(), BLOCK_ID => 1, PRIVILEGE => $mtab->{PRIVILEGE}, SUBSITE_ID => $self->getSubsiteId());
        }
        else {
            return $self->showError("Не могу понять как проверить права на вкладку модуля страницы-модуля");
        }
=cut
        next unless $hasTabAccess;

        $mtab->{URL}=~ s/^\///;
        $mtab->{URL}=~ s/\/$//;
        $mtab->{URL}.="/" if $mtab->{URL};
        
        my $tab = {
            HEADER   => $mtab->{HEADER},
            URL      => $baseUrl.$mtab->{URL},
            SELECTED => 0,
        };
        
        $tab->{AJAX_URL} = $baseUrl.$mtab->{URL}."?_ajax=1" unless exists $mtab->{NO_AJAX};

        my $taburl = $mtab->{URL} || "/";
        if ($suburl =~ /$taburl/ && length($taburl) >= length($pActiveTab->{url})) {
            $pActiveTab->{url} = $taburl;
            $pActiveTab->{tab} = $tab;
        }
        push @tabs, $tab;
    };
    $pActiveTab->{tab} ||= $tabs[0] if scalar(@tabs);
    $pActiveTab->{tab}->{SELECTED} = 1 if ($pActiveTab->{tab});
    return \@tabs;
};

sub moduleBlocks {
    my $self = shift;
    my $cms = $self->cms();
    
    return undef;
};

sub getAdminBlock {
    my $self = shift;
    my $cms = $self->cms();
    
    my $submodules = $self->moduleBlocks();
    return $cms->error("Класс ".(ref $self)." не содержит методов adminModule(), getAdminBlock() или moduleBlocks()") unless defined $submodules;
    unless ($submodules && ref $submodules eq "ARRAY") {
        my $e = $cms->getError("Вызов метода moduleBlocks() класса ".(ref $self)." не вернул массива значений");
        return $cms->error($e);
    };
    
    my $url=$cms->q()->url(-absolute=>1);
    my $myBaseUrl = $self->getAdminBaseURL();
    
    $url =~ s@^$myBaseUrl@/@;
    $url =~ s@//+@/@g;
    
    my $submodule = { URL=>"" };
    my $prevMatch = "";
    my @tt=();
    foreach my $subm (@{$submodules}) {
        $subm->{URL} ||= "";
        
        my $mR = $subm->{URL};
        unless (ref $mR  eq "Regexp") {
          $mR = "/".$mR if $mR !~ /^\//;
          $mR .= "/" if $mR !~ /\/$/;
          $mR = qr@^$mR@;
        };
        
        if ((my @ttt=$url =~ $mR) && ( length($&) >= length($prevMatch))) {
            @tt = @ttt; 
            $submodule = $subm;
            $prevMatch = $&;
        };
#use Data::Dumper;
#warn "URL=$url mR=$mR base=$myBaseUrl  s: ".$subm->{MODULE}." u: ".$subm->{URL}." match: ".(($submodule eq $subm)?"1":"0")." TT=".Dumper(@tt)."\n";
    };
    
    if ($submodule->{'URLPARAM'}) {
      my @params=split(',',$submodule->{'URLPARAM'});
      return $cms->error("Params count greater than regexp matches count". (scalar @params) . (scalar @tt)) if scalar @params > scalar @tt;
      for(my $i=0;$i<scalar @params;$i++) {
          $cms->q()->param($params[$i],$tt[$i]);
      };
    };
    $submodule->{URL} = $prevMatch;
    return $submodule;
};

sub _adminModule {
    my $self = shift;
	my $type = shift; ## module | pagemodule - для разделения проверки привилегий
	my $is_ajax = shift;
	
    my $cms = $self->cms();
    
    my $submodule = $self->getAdminBlock();
    unless ($submodule) {
        my $e = $cms->getError("Вызов метода getAdminBlock() класса ".(ref $self)." не вернул блока");
        return $cms->error($e);
    };
    if (ref $submodule && (ref $submodule ne "HASH" || !$submodule->{BLOCK})) {
        return $cms->error("Вызов метода getAdminBlock() класса ".(ref $self)." вернул некорректное значение");
    };
    
    $submodule = {BLOCK=>$submodule} unless ref $submodule;
    
    my $hasModuleAccess = 0;
    if (exists $submodule->{PAGEPRIVILEGE}) {
        $hasModuleAccess = $self->hasPageModulePrivilege($submodule->{PAGEPRIVILEGE});
    }
    elsif (exists $submodule->{PRIVILEGE}) {
        $hasModuleAccess = $self->hasModulePrivilege($submodule->{PRIVILEGE});
    }
    else {
        $hasModuleAccess = 1;
    };
    #	if ($self->canEditLinkBlock()) {
    #		my $langId = 0;
    #		$langId = $app->getPageLangId() if $self->isLangLinked();
    #		$hasModuleAccess = 1 if $app->hasLinkBlockPrivilege(LINK_ID => $mObj->getPageLinkId(),LANG_ID => $langId, BLOCK_ID => $mObj->getBlockId(), PRIVILEGE => $submodule->{PRIVILEGE}, SUBSITE_ID => $mObj->getSubsiteId());
    #	}
    #	elsif ($self->canEditPageBlock())  {
    #		$hasModuleAccess = 1 if $app->hasPageBlockPrivilege(PAGE_ID => $mObj->getPageId(), BLOCK_ID => $mObj->getBlockId(), PRIVILEGE => $submodule->{PRIVILEGE}, SUBSITE_ID => $mObj->getSubsiteId());
    #	}
    #	else {
    #		# Отображаем ошибку выполнения вызовов canEditXXXBlock или текст по умолчанию.
    #		return $self->showError("Не могу понять как проверить права на модуль страницы-модуля");
    #	}
    #};

=head   Если $type eq "module"
            my $subModule=$pageObj->getSubModule();
            if ($subModule) {
                my $moduleName = $subModule->{MODULE};
                my $moduleType = $subModule->{TYPE} if $subModule->{TYPE};
                
                my $hasModuleAccess = 0;
                if (!exists $subModule->{PRIVILEGE}){
                    $hasModuleAccess = 1;
                }
                else {
                    $hasModuleAccess = 1 if $pageObj->hasModulePrivilege($subModule->{PRIVILEGE});
                };
                
                if ($hasModuleAccess) {
                    $baseUrl = $baseUrl.$subModule->{'URL'};
                    $pageObj = $app->getModuleObject($subModule->{'MODULE'},{BASEURL=>$baseUrl}) or return $app->showError();
                }
                else {
                    $status = $pageObj->error("Доступ к модулю не предоставлен");
                    last;
                };
            };
=cut
    
    return $cms->error("Доступ к модулю не предоставлен") unless ($hasModuleAccess);

    my $baseurl = $self->getAdminBaseURL();

	#Дубль кода в updateSearchIndex() NG::PageModule
    $submodule->{URL} = $self->getAdminSubURL() unless exists $submodule->{URL};
    $submodule->{URL} =~ s@^/@@;
    $baseurl .= $submodule->{URL};
    
    my $opts = $submodule->{OPTS} || {};
    return $cms->error("Параметр OPTS блока не является HASHREF") unless ref $opts eq "HASH";
    $opts->{ADMINBASEURL} = $baseurl;
    my $moduleType = $submodule->{TYPE};
    
    $moduleType ||= "moduleBlock" if $type eq "module";
    $moduleType ||= "pageBlock" if $type eq "pagemodule";
    
    my $classDef = {CLASS=>$submodule->{BLOCK}};
    $classDef->{USE}= $submodule->{USE} if exists $submodule->{USE};
    
    if ($moduleType eq "pageBlock" || $moduleType eq "pageModule") {
        #pageBlockAction
        return $self->runBlock($classDef,$is_ajax,$opts);
    }
    elsif ($moduleType eq 'moduleBlock') {
        #blockAction
        return $self->runModule($classDef,$is_ajax,$opts);
        #return $self->runModule($submodule->{BLOCK},$is_ajax,$opts);
    }
    else {
        return $cms->error("Неизвестный тип подмодуля");
    };
};

sub adminModule {
	return shift->_adminModule("module",@_);
};

sub adminPageModule {
	return shift->_adminModule("pagemodule",@_);
};

# API ОБРАБОТКИ ЗАПРОСА С МОРДЫ

sub getBlockContent {
    my $self = shift;
    my $action = shift;
    my $function  = "block_".$action;
    
    return $self->cms->error("getBlockContent(): No function ".$function." in module ".(ref $self)) unless $self->can($function);
    return $self->$function($action,@_);
};

sub getBlockKeys {
    my $self = shift;
    my $action = shift;
    my $function  = "keys_".$action;
    return undef unless $self->can($function);
    return $self->$function($action,@_);
};

sub processModulePost {
    my $self = shift;
    return $self->cms()->error("Модуль ".ref($self)." не содержит метода processModulePost");
};

# ПРИВИЛЕГИИ В АДМИНКЕ

sub hasModulePrivilege {
	my $self = shift;
	my $privilege = shift;
    my $cms = $self->cms();
    return $cms->hasModulePrivilege(MODULE_ID=>$self->moduleParam('id'), PRIVILEGE=>$privilege);
};

sub hasPageModulePrivilege {
    my $self = shift;
    my $privilege = shift;
    
    my $cms = $self->cms();
    return $cms->hasPageModulePrivilege(MODULE_ID=>$self->moduleParam('id'), PRIVILEGE=>$privilege, PAGE_ID=>$self->pageParam('id'), SUBSITE_ID=>$self->pageParam('subsite_id'));
};

sub _getBlockPrivileges {
    my $self = shift;
    my $type = shift;

    my $cms = $self->cms();
    return undef unless $self->can("moduleBlocks");
    my $mb = $self->moduleBlocks();
    return undef unless defined $mb;
    
    unless ($mb && ref $mb eq "ARRAY") {
        my $e = $cms->getError("Вызов метода moduleBlocks() класса ".(ref $self)." не вернул массива значений");
        return $cms->error($e);
    };
    
    my $p = [];
    my $found = 0;
    my $ph = {};
    foreach my $b (@{$mb}) {
        my $opts = $b->{OPTS} || {};
        my $btype = $b->{TYPE};
        $btype ||= "pageBlock" if $self->isa("NG::PageModule");
        $btype ||= "moduleBlock";
        next if $btype ne $type;
        $opts->{MODULEOBJ} = $self;
        my $bObj = $cms->getObject($b->{BLOCK},$opts) or return $cms->error();
        next unless $bObj->can("blockPrivileges");
        my $bp = $bObj->blockPrivileges();
        next unless defined $bp; # [{PRIVILEGE=>"",NAME=>""}]
        return $cms->defError("blockPrivileges(): модуля ".$b->{BLOCK},"Возвращено некорректное значение") unless $bp && ref $bp eq "ARRAY";
        $found = 1;
        foreach my $pp (@$bp) {
            next if exists $ph->{$pp->{PRIVILEGE}};
            push @$p, $pp;
            $ph->{$pp->{PRIVILEGE}} = 1;
        };
    };
    return undef unless $found;
    return $p;
};

sub pageModulePrivileges {
    my $self = shift;
    return $self->_getBlockPrivileges("pageBlock");
};

sub modulePrivileges {
    my $self = shift;
    return $self->_getBlockPrivileges("moduleBlock");
};

sub _makeLogEvent {
    my $self = shift;
    my $opts = shift;
    
    $self->cms->_makeLogEvent($self,$opts);
};

return 1;
