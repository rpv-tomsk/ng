package NG::Application;
use strict;

use Carp;
use Carp qw(cluck);
use NGService;
use NSecure;

use NG::BlockContent;

$NG::Application::VERSION = 0.5;

use constant M_ERROR    => 0;  # крайне не рекомендуется менять эту критично важную константу
use constant M_OK       => 1;
use constant M_CONTINUE  => 5;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);
    return $self;
};

sub init {
    my $self = shift;
    my %param = @_;

    $self->{_q} = $param{CGIObject};
    $self->{_db} = $param{DBObject};
    $self->{_pm} = $param{PageModule};
    
    $self->{_siteroot}     = $param{SiteRoot};
    $self->{_siteroot}     =~ s/\/$//;
    $self->{_docroot}      = (exists $param{DocRoot})?$param{DocRoot}:$self->{_siteroot}."/htdocs/";
    $self->{_template_dir} = (exists $param{TmplDir})?$param{TmplDir}:$self->{_siteroot}."/templates/";
    $self->{_template_dir}.="/" unless $self->{_template_dir} =~ /\/$/;
    $self->{_config_dir}   = (exists $param{CfgDir})?$param{CfgDir}:$self->{_siteroot}."/config/";
    $self->{_cookies} = [];
    $self->{_charset} = "windows-1251";
    $self->{_echarset} = "windows-1251";
	$self->{_type} = "text/html";

    $self->{_debug} = $param{Debug} || 0;

    $self->{_nocache}=0;
    $self->{_headerssent} = 0;
    
    $self->{_error} = "";
    $self->{_confObj} = undef;

    $self->{_events_cache} = undef; # Cache registered events
    $self->{_events} = {}; # List executing events in this time
    
    #NG::CMS
    $self->{_subsiteRow} = undef;
    
    $self->{_moduleInstances} = {};
    $self->{_stash} = {};
    $self->{_mstash} = {};   ##Stash for NG::Module stash methods.
    $self->{_mrowC}  = {};   # Cache for ng_modules rows.  ( _mrowC->{CODE} = $moduleRow; )
    $self->{_mrowR}  = {};   # Flag what all modules for REF is loaded ( _mrowR->{REF} = 1; )
	
    
    $NG::Application::cms = $self;
    $NG::Application::pageObj = undef;
    $NG::Application::blocksController = undef;
    $NG::Application::DEBUG = $self->{_debug};
    $self;
};

sub getDocRoot()  { return $_[0]->{_docroot};  };
sub getSiteRoot() { return $_[0]->{_siteroot}; };

sub getSubsiteRow { return $_[0]->{_subsiteRow}};

sub debug {
    my $self = shift;
    $self->{_debug} = shift || 0 if (scalar @_);
    return $self->{_debug};
};

## NG::CMS functions

sub getResource {
    my $self = shift;
    my $name = shift;
    my $row = $self->{_subsiteRow} || {};
    my @cnf = (
        {PREFIX=>"S",KEY=>"id"},
        {PREFIX=>"L",KEY=>"lang_id"},
        {PREFIX=>""},
    );
    foreach (@cnf) {
        next if $_->{KEY} && !exists $row->{$_->{KEY}};
        my $module = $self->confParam("Resource.CMS".($_->{PREFIX}?"_".$_->{PREFIX}.$row->{$_->{KEY}}:""));
        $module or next;
        
        my $obj = $self->getObject($module) or return $self->error();
        my $value = $obj->getResource($name,
            {
                subsite_id => $row->{id},
                lang_id    => $row->{lang_id},
            }
        );
        return $value if defined $value;
    };
    return undef;
};

=comment
    $cms->getObject($class, parameters-for-new()-constructor)
    $cms->getObject({CLASS=>$class, METHOD=>"new", USE=>"Class::Package"}, parameters-for-$METHOD()-constructor)
=cut

sub getObject {
    my $cms = shift;
    my $class = shift or NG::Exception->throw('NG.INTERNALERROR', "getObject: No class value");

    my $cname = "new";  #Constructor method name
    my $use = $class;
    if (ref $class eq "HASH") {
        $cname = $class->{METHOD} || "new";
        $use   = (exists $class->{USE}) ? $class->{USE} : $class->{CLASS};
        $class = $class->{CLASS} or NG::Exception->throw('NG.INTERNALERROR',"getObject(): Class hash has no CLASS key value");
    };
    $class = $1 if ($class =~ /(.*)\s(.*)/);
    unless ($class->can("can") && $class->can($cname)) {
        eval "use $use;";
        if ($@) {
            my $m = $@;
            $m =~ s/ at \(eval \d+\) line \d+\.//g;
            $m =~ s/(?:\r?\n)+$//;
            NG::Exception->throw('NG.INTERNALERROR',"Error loading module \"$use\": ".$m) if $NG::Application::DEBUG;
            NG::Exception->throw('NG.INTERNALERROR',"Error loading module \"$use\".");
        };
    };
    NG::Exception->throw('NG.INTERNALERROR',"Class $class has no constructor $cname().") unless UNIVERSAL::can($class,$cname);
    return $class->$cname(@_) or NG::Exception->throw('NG.INTERNALERROR',"Error creating $class object");
};

sub loadSubsite {
    my $cms = shift;
    my $ssId = shift;
    
    my $q = $cms->q();
    my $dbh = $cms->db()->dbh();
    
    my $hasSubsites  = $cms->confParam("CMS.hasSubsites",0);
    my $hasLanguages = $cms->confParam('CMS.hasLanguages',0);
    
    return (NG::Application::M_OK,0) unless $hasSubsites || $hasLanguages;
    
    my $fields = "st.url,ss.id,ss.domain,ss.root_node_id,ss.name";
    my $from   = "ng_sitestruct st, ng_subsites ss";
    my $where  = "st.id = ss.root_node_id";
    
    if ($hasLanguages) {
        $fields .= ",ln.codes,ss.lang_id";
        $from   .= ",ng_lang ln";
        $where  .= " and ln.id = ss.lang_id";
    };
    
    $where .= " and ss.id = ?";
    
    my $sth = $dbh->prepare("select $fields from $from where $where") or return $cms->error($DBI::errstr);
    $sth->execute($ssId) or return $cms->error($DBI::errstr);
    $cms->{_subsiteRow} = $sth->fetchrow_hashref();
    $sth->finish();
    return $cms->{_subsiteRow};
};

=head findSubsite()
  
    Возвращаемое значение: список ($ret, $subsiteId)

    $ret - код выхода - обычный код выхода метода run ( M_OK, M_REDIRECT, M_404, M_ERROR)
    //(Больше не выставляет!!!)Выставляет $self->{_subsiteId} - код текущего подсайта, определяется для заданного домена запроса + параметр Accept-Language
    возвращенный в поле $subsiteId = 0 означает, что значение отсутствует (в CMS отсутствуют подсайты)
=cut
sub findSubsite {
    my $cms=shift;
    my $q = $cms->q();
    my $dbh = $cms->db()->dbh();
	
    #TODO: исправить выход и интерфейс вызова.

	#Вызывается только для url(-absolute=>1) eq "1"
=head	
	1. Если ! CMS.hasSubsites - выходим без перенаправления.
	2. Запрашиваем таблицу подсайтов и языков
	2.1 Учитываем параметр hasLanguages
	
	получаем таблицу subsiteId langId root_node_id root_node_url langCode('ru','en','en-gb') siteDomain(текст для регулярки)
	
	по домену запроса находим подходящие подсайты (если заполнены ng_subsite.domain)
	если нашлось несколько, то проверяем язык (если hasLanguages=1 и вбиты langCode)
	если приоритета не найдено -  т.е. таки несколько подсайтов - выбираем "первый"
	
	если для найденного подсайта root_node_url eq "/" - выходим без перенаправления, пусть строится страница.
	
	делаем перенаправление на требуемый root_node_url
=cut
	my $hasSubsites  = $cms->confParam("CMS.hasSubsites",0);
    my $hasLanguages = $cms->confParam('CMS.hasLanguages',0);
    
    return (NG::Application::M_OK,0) unless $hasSubsites || $hasLanguages;
    
    my $fields = "st.url,ss.id,ss.domain,ss.root_node_id,ss.name";
    my $from   = "ng_sitestruct st, ng_subsites ss";
   my $where  = "st.id = ss.root_node_id";
    
    my %user_langs;
    if ($hasLanguages) {
        $fields .= ",ln.codes,ss.lang_id";
        $from   .= ",ng_lang ln";
        $where  .= " and ln.id = ss.lang_id ";
        
        my $al = $q->http('Accept_language') || "";
        foreach my $tmp_lang (split /\,/,$al){
            $tmp_lang =~ m/([\w\-\*]+)(?:;q\=([\d\.]+))?/;
            $user_langs{$1} = $2 || '1.0';
        };
        #use Data::Dumper;
        #return $self->error(Dumper(%user_langs)." - ".$self->q()->http('Accept_language'));
    };
   
    my $sql = "select $fields from $from where $where order by ss.id asc";
    
   
    my $sth = $dbh->prepare($sql) or return $cms->error($DBI::errstr);
    $sth->execute() or return $cms->error($DBI::errstr);
    
    #my $e = "";
 
    my @allDomains = ();   
    my @emptyDomain = ();
    my @matchedDomain = ();
    
    while (my $row = $sth->fetchrow_hashref()) {
        $row->{domain}||= "";
        if ($row->{domain}) {
            my $v = $row->{domain};
            $v =~ s/\./\\./g;
            if ($q->virtual_host() =~ /(?:$v)$/) {
                push @matchedDomain, $row;
            };
        }
        else {
            push @emptyDomain,$row;
        };
        push @allDomains, $row;
        #$e .= "SSID = ".$row->{id}." URL= ".$row->{url}." DOMAIN= ".$row->{domain}. " CODES= ".$row->{codes}."<br>\n";
    };
    $sth->finish();
    
    #print STDERR "$e";
    
    @matchedDomain = @emptyDomain unless (scalar @matchedDomain);
    @matchedDomain = @allDomains  unless (scalar @matchedDomain);
    
    return (NG::Application::M_OK,0) unless (scalar @matchedDomain);
    
    my $m = undef;
    my $elang = undef;
    foreach my $ss (@matchedDomain) {
        $m  ||= $ss;
        if ($hasLanguages) {
            $ss->{codes} ||= "";
            $elang ||= $ss if ($ss->{codes} eq "");
            $ss->{langWeight} = "0.0";
            foreach my $site_lang (split /\,/,$ss->{codes}){
                if ($site_lang && exists $user_langs{$site_lang} && $user_langs{$site_lang} > $ss->{langWeight}) {
                    $ss->{langWeight} = $user_langs{$site_lang};
                };
            };
            $m  = $ss if ($ss->{langWeight} > $m->{langWeight} );
        };
    };
    $m = $elang if ($m->{langWeight} eq "0.0");
	$m ||= $allDomains[0];
    
    #print STDERR "M domain =".$m->{domain}." id= ".$m->{id};
    
    if ($q->url(-absolute=>1) ne "/" && $q->url(-absolute=>1) ne "") {
        # Если запрос не на "/" то высчитываем на какой подсайт выпадет URI запроса для данного домена
        # чтобы потом запросить из дерева ноду для именно этого подсайта
        # Этот подсайт может отличаться от того, на который произошел бы редирект при запросе "/"
        
        # TODO: @allDomains or @matchedDomains ???
        foreach my $ss (@allDomains) {
            next unless $ss->{domain} eq $m->{domain};
            my $root_url = $ss->{url};
            $root_url =~ s/\//\\\//g;
            if ($q->url(-absolute=>1) =~ /^$root_url/ ) {
                $cms->{_subsiteRow} = $ss;
                return (NG::Application::M_OK, $ss->{id});
            };
        };
        $cms->{_subsiteRow} = $m;
        return ($cms->notFound(),$m->{id});
    }
    else {
        $cms->{_subsiteRow} = $m;
        return (NG::Application::M_OK,$m->{id}) if ($m->{url} eq "/");
        return ($cms->redirect($m->{url}),0);
    };
};

sub getPageFields {
	my $app = shift;
	my $baseClass = $app->confParam('CMS.DefaultPageClass',"NG::PageModule");
	my $pageFields = "id,parent_id,name,full_name,keywords,description,title,url,template,print_template,module_id,subptmplgid,disabled,subsite_id,lang_id,link_id,tree_order,level,catch";
	
    my $obj = $app->getObject($baseClass) or return $app->error();
    
	if ($obj->can('pageFields')) {
		my $addon = $obj->pageFields();
		return $app->defError($baseClass."->pageFields()","Не вернул списка полей") if $addon eq "0";
		$pageFields .= ",".$addon if $addon;
	};
	return $pageFields;
};

sub getModuleFields {
    my $app = shift;
    return "id,code,module,base,name,params";
};

sub findPageRowByURL {
    my $cms = shift;
    my $url  = shift;
    my $ssId = shift || 0;
    
    my $dbh = $cms->dbh();
    
	#Загружаем свойства страницы
    my $fields = $cms->getPageFields();
    return $cms->error() if $fields eq "0"; ##cms->error
    my $sql = "select $fields from ng_sitestruct where url = ? and disabled=0";
    my @params;
    push @params,$url;
    if ($ssId) {
        push @params, $ssId;
        $sql.= " and subsite_id = ?";
    };
    my $sth = $dbh->prepare($sql) or return $cms->error($DBI::errstr);
    $sth->execute(@params) or return $cms->error($DBI::errstr);	
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    unless($row) { #чпу?
        #Ищем в структуре все ЧПУ-обработчики
        @params=();
        $sql="select $fields from ng_sitestruct where catch>0 and disabled=0";
        if($ssId) {
            push @params, $ssId;
            $sql.= " and subsite_id = ?";
        }; 
        $sth=$dbh->prepare($sql) or return $cms->error($DBI::errstr);
        $sth->execute(@params) or return $cms->error($DBI::errstr);
        my $data = $sth->fetchall_hashref('url');
        $sth->finish();

        my $lurl = $url;
        $lurl=~s@[^\/]+$@@; #вырезаем текст после последнего слеша
        return $cms->error("Некорректная ссылка") unless $lurl =~ /^\//; #проверяем корректность
        #Ищем максимальное совпадение,отрезая куски ссылок
        while ($lurl ne "/") {
            next if ($lurl=~s%\/\/$%\/%);
            unless (exists $data->{$lurl}) {
                $lurl=~s%[^\/]+\/$%%;
                next;
            };
            $row=$data->{$lurl};
            $row->{'pageBaseUrl'}=$lurl; #TODO: для чего это?
            last();
        };
        return undef unless $row;
        #catch == 0 - ЧПУ отсутствует
        #catch == 1 - ЧПУ с обработкой параметров через ng_rewrite
        #catch == 2 - ЧПУ с обработкой параметров внутри модуля
        #catch == 3 - ЧПУ с обработкой параметров внутри модуля, с поддержкой обработки "файловых" ссылок
        if ($row->{catch}==1) {
            $sql="select id,pageid,cp.regexp,paramnames from ng_rewrite cp where pageid=? or link_id=? order by id";
            $sth=$dbh->prepare($sql) or return $cms->error($DBI::errstr);
            $sth->execute($row->{'id'},$row->{'link_id'}) or return $cms->error($DBI::errstr);
            $lurl = $url;
            $lurl =~ s/^$row->{url}//;
            my $f = 0;
            while (my $crow=$sth->fetchrow_hashref()) {
                my @tt=(); 
                my $regexp=$crow->{regexp};
                if (@tt=$lurl=~m@$regexp@) {
                    $f = 1;
                    my @params=split(',',$crow->{'paramnames'});
                    for(my $i=0;$i<scalar @params;$i++) {
                        $cms->q()->param($params[$i],$tt[$i]);
                    };
                    last();
                };
            };
            return undef unless $f;
        };
    };

    return undef unless($row);
    return $row;
};
    
sub processRequest {
    my $cms = shift;
    my $url = shift;
    my $ssId = shift || 0;
    
    my $dbh = $cms->dbh();
    
    
    my $row = $cms->findPageRowByURL($url,$ssId);
    return $cms->error() if defined $row && !$row;
#NG::Profiler::saveTimestamp("findPRbURL","processRequest");

    if ((!defined $row || ($row->{catch} != 0 && $row->{catch} != 3)) && $url !~ /\/$/) {
        return $cms->redirect(-uri=>$url.'/',-status=>301);
    };

    return $cms->notFound() unless defined $row;
    
    #подмена основного шаблона на шаблон для печати
    $row->{'template'}=$row->{'print_template'} if $cms->isPrint();
    
    $row->{keywords} =~ s/[\r|\n]/ /gi if $row->{keywords};
    $row->{description} =~ s/[\r|\n]/ /gi if $row->{description};
    #$row->{'pageBaseUrl'}=$row->{'url'} unless($row->{'pageBaseUrl'});
    #TODO: fix
    $cms->{_pageRow} = $row;
    #$cms->setLinkId($row->{'link_id'});
    
    my $pageObj = $cms->getPageObjByRow($row) or return $cms->error();
#NG::Profiler::saveTimestamp("getPObjbRow","processRequest");
    return $cms->error("Модуль ".(ref $pageObj)." не содержит метода run") unless $pageObj->can("run");
    return $pageObj->run();
};

sub getPageRowById {
	my $cms = shift;
	my $pageId = shift || return $cms->error("getPageRowById(): Отсутствует параметр pageId");

	my $pageFields = $cms->getPageFields();
    return $cms->error() if $pageFields eq "0"; ##cms->error
	
    my $dbh = $cms->db()->dbh();
    
	my $sth = $dbh->prepare("select $pageFields from ng_sitestruct where id=?") or return $cms->error("getPageRowById(): Error in pageRow query: ".$DBI::errstr);
	$sth->execute($pageId) or return $cms->error("getPageRowById(): Error in pageRow query: ".$DBI::errstr);
	my $pRow = $sth->fetchrow_hashref();
	$sth->finish();
	return $cms->error("getPageRowById(): Страница не найдена") unless $pRow;
	return $pRow;
};

sub getPageObjById {
    my $cms = shift;
    my $pageId = shift || return $cms->error("getPageObjById(): Отсутствует параметр pageId");
    my $opts = shift;
    
    my $pageRow = $cms->getPageRowById($pageId) or return $cms->error();
    return $cms->getPageObjByRow($pageRow,$opts);
};
    
    
sub getPageObjByRow {
    my $cms = shift;
    my $pageRow = shift || return $cms->error("getPageObjByRow(): Отсутствует параметр pageRow");
    my $opts = shift;
    
    return $cms->error("getPageObjByRow(): pagecontroller options is not HASHREF") if $opts && ref $opts ne "HASH";
    $opts ||= {};
    
    my $pageModule = $pageRow->{module};
    
    if (!$pageModule && $pageRow->{module_id}) {
        my $mRow = $cms->getModuleRow("id=?",$pageRow->{module_id}) or return $cms->defError("getPageObjByRow():","Модуль с кодом ".$pageRow->{module_id}." не найден при обработке страницы ".$pageRow->{id});
        $pageModule = $mRow->{module};
        $opts->{MODULEROW} = $mRow;
    };
    
    $pageModule ||= $cms->confParam('CMS.DefaultPageClass',"NG::PageModule");
    $opts->{PAGEPARAMS} = $pageRow;
    
    return $cms->getObject($pageModule,$opts);
};

sub getModuleRow {
    my $cms = shift;
    my $where = shift or NG::Exception->throw('NG.INTERNALERROR', "getModuleRow(): Отсутствует параметр where");

    my $dbh = $cms->dbh();
    my $fields = $cms->getModuleFields();
    my $sth = $dbh->prepare("select $fields from ng_modules where $where") or NG::DBIException->throw();
    $sth->execute(@_) or NG::DBIException->throw();
    my $mRow = $sth->fetchrow_hashref();# or NG::Exception->throw('NG.INTERNALERROR', "getModuleRow(): Запрошенный модуль не найден");
    $sth->fetchrow_hashref() and NG::Exception->throw('NG.INTERNALERROR', "getModuleRow(): Условие запроса не определяет уникальной записи в ng_modules");
    $sth->finish();
    return $mRow;
};

sub runPageController {
    my $cms = shift;
    
    my $pageModule = shift or return $cms->error("runPageController(): pagecontroller module not specified");
    my $opts = shift;
    
    return $cms->error("runPageController(): pagecontroller options is not HASHREF") if $opts && ref $opts ne "HASH";
    my $pageObj = $cms->getObject($pageModule,$opts) or return $cms->error();
    return $pageObj->run();
};

sub getPageActiveBlock {
    my $cms = shift;
    my $pageObj = shift;
    
    #Если нет активного блока, или нет метода getActiveBlock, пытаемся вывести "статическую" страницу с использованием плагинов.
    return undef unless $pageObj->can("getActiveBlock");
    
    my $ab = $pageObj->getActiveBlock();    # BLOCK + LAYOUT + PRIO + DISABLE_NEIGHBOURS + DISABLE_BLOCKPARAMS
#NG::Profiler::saveTimestamp("getP_AB-getAB","buildPage");
    
    return $cms->notFound unless defined $ab;
    return $cms->defError("getActiveBlock()","неизвестная ошибка") if $ab eq 0;
    return $ab if ref $ab && UNIVERSAL::isa($ab,'NG::BlockContent');
    return $cms->error("getActiveBlock() модуля ".(ref $pageObj)." вернул некорректное значение (не HASHREF)") unless ref $ab eq "HASH";
    return $cms->error("getActiveBlock() модуля ".(ref $pageObj)." вернул некорректное значение (отсутствует код BLOCK)") unless $ab->{BLOCK};
    
    my $mName = $pageObj->getModuleCode() or return $cms->error();
    
    my $aBlock = {};
    #TODO: сделать возврат блока тем же самым хешем, т.е. сквозное прохождение результата getActiveBlock() в следующие вызовы, убрать _новый_ хеш $aBlock={};
    $aBlock->{CODE} = $mName."_".$ab->{BLOCK};
    $aBlock->{ACTION} = $ab->{ACTION} || $ab->{BLOCK}; ## Backward compatability
    $aBlock->{LAYOUT} = $ab->{LAYOUT};
    $aBlock->{PRINTLAYOUT} = $ab->{PRINTLAYOUT};
    $aBlock->{MODULEOBJ} = $pageObj;
    
    return $aBlock;
};

sub buildPage {
    my $cms = shift;
    my $pageObj = shift;
    my $layout = shift;
    
    my $q   = $cms->q();
    
    my $aBlock = $cms->getPageActiveBlock($pageObj);
#NG::Profiler::saveTimestamp("getP_AB","buildPage");
    return $aBlock if defined $aBlock && ($aBlock eq "0" || (ref $aBlock && UNIVERSAL::isa($aBlock,'NG::BlockContent')));
    
    if ($layout) {
        #Do nothing, high priority
    }
    elsif ($pageObj->can("getLayout")) {
        my $abLayout = $pageObj->getLayout($aBlock);
        return $abLayout if $abLayout eq "0" || (ref $abLayout && UNIVERSAL::isa($abLayout,'NG::BlockContent'));
        $layout = $abLayout;
    }
    elsif ($aBlock) {
        my $layoutConf = "LAYOUT";
        $layoutConf = "PRINTLAYOUT" if $cms->isPrint();
        $layout = $aBlock->{$layoutConf} if defined $aBlock->{$layoutConf};
    };
    
    unless ($layout || $aBlock) {
        return $cms->error("Страница без активного блока не содержит шаблона. Отображение невозможно");
    };
    
    my $bctrl = $cms->getObject("NG::BlocksController",$pageObj) or return $cms->error();
    local $NG::Application::blocksController = $bctrl;
    if ($aBlock) {
        my $abContent = $bctrl->pushABlock($aBlock);
#NG::Profiler::saveTimestamp("pushABlock","buildPage");
        return $abContent if ($abContent eq 0 || !$abContent->is_output());
    };
    
    my $lBlocks = undef;  # {Хэш, с ключами = код блоков шаблона}
    my $nBlocks = undef;  # {Хэш, с ключами = код блоков шаблона}
    
    if ($layout) {
        #получаем список блоков шаблона.
        $lBlocks = $bctrl->loadTemplateBlocks($layout) or return $cms->error();
#NG::Profiler::saveTimestamp("loadTemplateBlocks","buildPage");
    };
    
    my $hasNeighbours = 1;
    $hasNeighbours = 0 unless $aBlock;
    if ($aBlock && !$aBlock->{DISABLE_BLOCKPARAMS}) {
        #select from ng_blocks, ng_modules ....
        
        #$bParams = {};
        #$hasNeighbours = $row->{ng_blocks.hasNeighbours};
    };
    
    $hasNeighbours = 0 if $aBlock && $aBlock->{DISABLE_NEIGHBOURS};
    
    if ($hasNeighbours) {
        $nBlocks = $bctrl->loadNeighbourBlocks($aBlock->{CODE}) or return $cms->error();
    };
    
    # $bctrl - накачан всеми нужными блоками.
    
    my $qetag = $q->http("ETag");    
    my $etag = $bctrl->getETagSummary();
    if ($qetag && $etag && $etag eq $qetag) {
        return $cms->exit("", -status=>"304");
    };
     
    # Сборка страницы.
#NG::Profiler::saveTimestamp("b_reqCacheKeys","buildPage");
    $bctrl->requestCacheKeys() or return $cms->error(); #Запрашиваем ключи всех блоков страницы, чтобы сравнить
#NG::Profiler::saveTimestamp("requestCacheKeys","buildPage");
    
#NG::Profiler::saveTimestamp("b_prepCont","buildPage");
    my $abContent = $bctrl->prepareContent(); # or return $cms->error(); # делаем запрос контента для всех блоков
    return $abContent if ($abContent ne 1);
#NG::Profiler::saveTimestamp("prepCont","buildPage");
    
    $bctrl->splitRegions() or return $cms->error();
#NG::Profiler::saveTimestamp("splitReg","buildPage");
    
    my $rContent = $bctrl->getRegionsContent() or return $cms->error();
#NG::Profiler::saveTimestamp("getRegContent","buildPage");
    
    warn "No layout to output regions" if (!$layout && scalar keys %$rContent > 2); #CONTENT & HEAD are persistent regions
    return $cms->output($rContent->{CONTENT}) unless $layout;
    
    my $tObj = $cms->gettemplate($layout) or return $cms->error();
#NG::Profiler::saveTimestamp("get_layout","buildPage");
    $bctrl->attachTemplate($tObj) or return $cms->error();
#NG::Profiler::saveTimestamp("att_layout","buildPage");
    
    my $rObj = $cms->getObject("NG::ResourceController",$cms) or return $cms->error();
    $tObj->param(
        REGION=>$rContent,
        PAGEROW => $pageObj->getPageRow(),
        SUBSITEROW => $cms->{_subsiteRow},
        RES => $rObj
    );
#NG::Profiler::saveTimestamp("pre_output","buildPage");
    return $cms->output($tObj);
        
        
=comment
    # Определяем состав всех блоков страницы
    # Запрашиваем ключи у всех блоков
    # Формируем результирующий Етаг
    # Проверяем совпадение Етэгов
    # Выдаем 304 если совпали
    # Строим документ - если не совпали
    # Для всех блоков делаем запрос ключей из кэша
    # Определяем, откуда будем брать контент, берем контент
    # Собираем страницу
    #   Если есть активный блок, забираем его контент
    #   Если у АБ есть блоки соседи, забираем их контент, собираем результирующий контент в соответствии с порядком
    #   Если лайоута нет - отдаем результирующий контент
    #   Если лайоут есть - заполняем шаблон его блоками
    #   Пишем в шаблон переменную Контент
    #   Отдаем результат заполнения шаблона
    # Отдаем страницу
=cut
    
=comment ##
    * getCacheContentKeys() - запрос метаданных из кэша. Метаданные идентифицируются блоком по коду блока, и ключем данных в этом блоке.
    
    Вызов: $cms->getCacheContentKeys([{CODE=>$code, KEY=>$key},{CODE=>$code, KEY=>$key},{CODE=>$code, KEY=>$key}])
    возвращает ключи контента из кэша, в виде хэша, или 0 в случае ошибки.  Ключом в хэше ответа является CODE
    
    $code - уникальный код блока
    $key  - значение ключа KEY, идентифицирующего контент в блоке
    
    * storeCacheContent() - сохранение данных и их метаданных в кэше. Данные и метаданные идентифицируются блоком по коду блока,
                        и ключем данных в этом блоке. 
    
    $keys - метаданные контента, хэш. Хэш должен содержать ключ KEY для идентификации данных в блоке.
          - метаданные могут? содержать ключ EXPIRE с числовым значением времени устаревания данных
            ( маленькое число трактуется как +ххх секунд жизни, большое - устареть в момент времени хххх as timestamp)
    $data - данные для сохранения
    
    Вызов: $cms->storeCacheContent([{CODE=>$code,KEYS=>$keys, DATA=>$data}])
    Возвращает 1 в случае успеха/нефатальной ошибки, 0 в случае системной ошибки.
    
    * deleteCacheContent() - удаление данных и метаданных из кэша.
    
    Вызов: $cms->deleteCacheContent([{CODE=>$code, KEY=>$key},{CODE=>$code, KEY=>$key},{CODE=>$code, KEY=>$key},])
    Возвращает 1 в случае успеха, 0 в случае системной ошибки
    
    * getCacheContent() - запрос кэшированного контента
    
    Вызов: $cms->getCacheContent([{CODE=>$code, KEY=>$key},{CODE=>$code, KEY=>$key},])
    Возвращаемое значение - хэш данных. 0 - в случае системной ошибки
    
    * getCacheContentURI() - запрос ссылки на контент для осуществления SSI сборки ответа
    
    Вызов: $cms->getCacheContentURI([{CODE=>$code, KEY=>$key}, {CODE=>$code, KEY=>$key}, ... ])
    Возвращаемое значение - хэш URI. Значение URI = undef если ссылка отсуствует. 0 - в случае системной ошибки
    
    -----
    
    Методы модуля для работы с кэшем
    
    $mObj->storeCacheData([KEY=>$key, VALUE=>$value, EXPIRE=> $expire])
    $valARef = $mObj->getCacheData([$key, $key, $key]) or return $cms->error()
    $mObj->deleteCacheData([$key,$key,$key])
    
    Ищем активный блок
      Активный блок есть
        Спрашиваем ключи
          Ключи совпали, данные есть в кэше
            - идем дальше
          Ключи не совпали или отсутствуют
            Запрашиваем контент
            Обрабатываем redirect, 404, error запроса контента активного блока
            Кладем данные и метаданные в кэш
        Определяем layout для активного блока
      Активный блок отсутствует
        Делаем что-нибудь другое. Типа отображения статической страницы
    
    - тут у нас есть знание, что у нас есть контент АБ или факт отсутствия АБ
    - если не нашли layout из АБ, при его наличии, берем layout из pagerow или дефолт CMS
      Если у нас нет ни активного блока ни layout-а - сильно обижаемся и выводим 404 или ошибку
      
    Запрашиваем блоки layoutа - при его наличии
    Запрашиваем блоки-соседи активного блока, при его наличи
    
    Запрашиваем ключи
      Если ключ не совпадает или отсутствует, запрашиваем контент блока
      Обрабатываем ответ. При успехе кладем данные и метаданные в кэш
    
    Формируем ETag по ответам всех модулей
    Сравниваем с етагом запроса.
      Совпадают
        отдаем 304
      Не совпадают
        формируем и отдаем страницу
=cut ##
    
};

sub getABRelated {
    return $NG::Application::blocksController->getABRelated();
};

sub isPrint {
    my $self=shift;
    my $q = $self->q();
    return 1 if(defined $q->param('print') || ($q->param('keywords') && $q->param('keywords') eq 'print'));
    return 0;  
};

sub getPrintParam {
    my $self=shift;
    return "print=1";
};




## /NG::CMS functions


#TODO: обсудить кэширование, запись, очистку сессий средствами CMS

sub _session {
	my $self  = shift;
	my $meth  = shift;
	
	my $cname = shift || "Face";
	my $sid   = shift;
	my $params= shift;
	
	$self->openConfig();
	my $session = $self->getObject({CLASS=>"NG::Session",METHOD=>$meth},
		{
			App      => $self,
			ConfName => $cname,
		},
		$sid,
		$params,
	);
	
	unless ($session) {
		$self->setError($NG::Session::errstr);
		return undef;
	};
	return $session;
};

sub loadSession {
	my $self  = shift;
	return $self->_session("load",@_);
};

sub getSession {
	my $self=shift;
	return $self->_session("new",@_);
};

sub getCookiedSession {
    my $cms = shift;
    
    my $cookieName = shift || "SESSION";
    my $confName   = shift;
    
    my $id = $cms->q->cookie($cookieName);
    my $sObj = $cms->getSession($confName, $id) or return $cms->error();
    
    $cms->addCookie(-name => $cookieName,-value => $sObj->id());
    return $sObj;
};

sub processEvent {
    my $self = shift;
    my $event = shift;

	my $class = ref $event;
    my $name = $event->name();
    my $sender = ref $event->sender();
	
    die "This module already send such event" if (
		   exists $self->{_events}->{$sender}
		&& exists $self->{_events}->{$sender}->{$class}
		&& exists $self->{_events}->{$sender}->{$class}->{$name}
	);
    $self->{_events}->{$sender}->{$class}->{$name} = 1;

	$self->{_events_cache} ||= {};
    if (!exists $self->{_events_cache}->{$class}) {
		my $cache = {};
		
        my $sth = $self->db()->dbh()->prepare("select id,name,sender,handler from ng_events where class=? or class =''") or die $DBI::errstr;
        $sth->execute($class) or die $DBI::errstr;
        while (my $row = $sth->fetchrow_hashref()) {
            die "processEvent(): Handler not defined in table ng_events (id = ".$row->{id}.")" if is_empty($row->{handler});
			$row->{name} ||= "";
            $row->{sender} ||= "";
            $cache->{$row->{handler}}->{$row->{name}}->{$row->{sender}} = 1;
        };
        $sth->finish();
		
		$self->{_events_cache}->{$class} = $cache;
    };
	#$self->{_events_cache}->{$class}->{$handler}->{$name}->{$sender}
    
    my $cache = $self->{_events_cache}->{$class};
    foreach my $handler (keys %{$cache}) {
		my $eventRow = $cache->{$handler};
        if (
            (exists $eventRow->{$name} && (exists $eventRow->{$name}->{$sender} || exists $eventRow->{$name}->{""}))
            || (exists $eventRow->{""} && (exists $eventRow->{""}->{$sender} || exists $eventRow->{""}->{""}))
        ) {
            my $obj = $self->getObject($handler) or die "processEvent can't create module object (".$self->getError().")";
            die "Class $handler has no method processEvent()" unless $obj->can("processEvent");
            $obj->processEvent($event);
        };
    };
    delete $self->{_events}->{$sender}->{$class}->{$name};
};

sub defaultTemplateParams {
    my $self = shift;
    return {};
}

sub gettemplate {
    my $self = shift;
    my $filename = shift;
    my $eopts = shift;
    
    my $opts = {};
    
    #hard-coded default values
    $opts->{loop_context_vars}=1;
    $opts->{case_sensitive} = 0;
    $opts->{global_vars}=1;
    
    if ($self->{_debug}) {
        $opts->{cache}=1; #RAM cache...
        #use HTML::Template::Compiled;
        #HTML::Template::Compiled->clear_cache();
        $opts->{debug_file}='start,end,short';
    }
    else {
        my $m = $self->confParam("CMS.HTC_Cache",undef);
        $opts->{cache_dir} = $m if $m;
        $opts->{cache} = 1;
    };
    
    #defaultTemplateParams() support
    my $d = $self->defaultTemplateParams();
    NG::Exception->throw('NG.INTERNALERROR',"gettemplate(): defaultTemplateParams() returns invalid value") unless $d && ref $d eq "HASH";
    map {$opts->{$_} = $d->{$_}} keys %$d;
    
    #eopts support
    NG::Exception->throw('NG.INTERNALERROR',"gettemplate(tmpl,eopts): eopts value is not hashref") if $eopts && ref $eopts ne "HASH";
    map {$opts->{$_} = $eopts->{$_}} keys %$eopts;
    
    my $set = 0;
    $set = 1 if exists $opts->{arrayref} or exists $opts->{scalarref} or exists $opts->{filename} or exists $opts->{filehandle};
    
    NG::Exception->throw('NG.INTERNALERROR',"Template specified by both parameter and option.") if $set && $filename;
    unless ($set) {
        NG::Exception->throw('NG.INTERNALERROR',"No template specified.") unless $filename;
        
        $opts->{path} = $self->{_template_dir} unless exists $opts->{path};
        
        NG::Exception->throw('NG.INTERNALERROR',"Could not open template '$filename': $!") unless ( -f $opts->{path}.$filename );
        $opts->{filename}= $filename;
        #$opts->{open_mode} =':utf8' if !exists $opts->{open_mode} && $self->{_charset} eq "utf-8";
        # $opts->{utf8}= 1,
    };
    return $self->getObject("HTML::Template::Compiled 0.85", %$opts);
};


=comment set_header setNoCache  getNoCache set_header403 set_header_nocache
sub set_header {
    my $self = shift;
    return $self->set_header_nocache() if($self->getNoCache());
    print $self->q->header(
        -type=>$self->{_type},
        -charset=>$self->{_charset},
        -cookie=>$self->{_cookies},
    );
    $self->{_headerssent} = 1;
};

sub setNoCache {
    my $self=shift;
    $self->{'_nocache'}=1;
};

sub getNoCache {
    my $self=shift;
    return $self->{'_nocache'};
};

sub set_header403 {
    my $self = shift;
    print $self->q->header(
        -type=>$self->{_type},
        -charset=>$self->{_charset},
        -cookie=>$self->{_cookies},
        -status=>"403"
    );
    $self->{_headerssent} = 1;
};

sub set_header_nocache {
    my $self = shift;
    print $self->q->header(
        -type=>$self->{_type},
        -charset=>$self->{_charset},
        -cookie=>$self->{_cookies},
        -Pragma=>"no-cache",        
        -expires=>"-1d",
        -Cache_Control=>"no-store, no-cache, must-revalidate",
    );
    $self->{_headerssent} = 1;
};
=cut

sub addCookie {
    my $self = shift;
    my $cookie = CGI::cookie(@_);
    push @{$self->{_cookies}}, $cookie;
    #$self->setNoCache();
};

=comment get_referer_or redirect_to_referer_or
sub get_referer_or {
    my $self = shift;
    my $backup_url = shift;
    my $redirect_url = $self->q->referer();
    if (!defined $redirect_url || $redirect_url eq "")  {
        if (defined $backup_url && $backup_url ne "") {
                $redirect_url = $self->q->url(-base=>1).$backup_url;
        } else {
                $redirect_url = $self->q->url(-base=>1)."/";
        };
    };
    return $redirect_url;	
};

sub redirect_to_referer_or {
    my $self = shift;
    my $backup_url = shift;
    my $redirect_url = $self->get_referer_or($backup_url);
    print $self->q->redirect(
        -uri=>$redirect_url,
        -cookie=>$self->{_cookies},
    );
};
=cut

sub _caller {
    my $self = shift;
    my @call  = caller(2);
    
    return $call[3];
};

=comment
sub _gethparams {
    my $self = shift;
    my %param = ();
    
    while (1) {
        last unless scalar @_;
        my $v = shift @_;
        if ($v =~ m/^-/) {
            unshift @_, $v;
            last;
        };
        $param{-type} = $v;
        
        last unless scalar @_;
        $v = shift;
        $param{-status} = $v;
        
        return $self->showError("cms->".$self->_caller()."(): invalid parameters count") if scalar @_;
    };
    
    if (scalar @_ ) {
        if (scalar @_ % 2 == 0) {
            %param = (@_);
        }
        else {
            warn "cms->".$self->_caller()."(): invalid parameters count, skipped.";
        };
    };
    if (exists $param{-cookie}) {
        if (ref $param{-cookie} eq "ARRAY") {
            push @{$self->{_cookies}}, @{$param{-cookie}};
        }
        else {
            push @{$self->{_cookies}}, $param{-cookie};
        };
        delete $param{-cookie};
    };
    return \%param;
};
=cut

sub _header {
    my $self = shift;
    my $params = shift || {};
    if ($self->{_headerssent}) {
        warn "header(): headers already sent";
        return 0;
    };
    
    $params->{-type} = $self->{_type} unless exists $params->{-type};
    $params->{-charset} = $self->{_charset} unless exists $params->{-charset};
    
    $params->{-cookie} ||= [];
    push @{$params->{-cookie}}, @{$self->{_cookies}} if $self->{_cookies};
    
    if ($self->{_nocache} || $params->{-nocache}) {
        delete $params->{-nocache};
        $params->{-Pragma}="no-cache";
        $params->{-expires}="-1d" unless exists $params->{-expires};
        $params->{-Cache_Control}="no-store, no-cache, must-revalidate";
    };
    
    print $self->q()->header(%{$params});
    $self->{_headerssent} = 1;
    return 1;
};


sub setError {
    my $self = shift;
    my $error = shift;
    $self->{_error} = $error if $error;
    carp ts($error) if $error;
    return M_ERROR;
};
*error = \&setError;

sub defError {
    my $self = shift;
    my $prefix = shift;
    my $deftext = shift;
    
    $self->{_error} ||= $deftext || "неизвестная ошибка";
    $self->{_error} = $prefix.": ".$self->{_error} if $prefix;
    return M_ERROR;
};

sub getError {
	my $self = shift;
	return $self->{_error} || shift;
};

sub showError {
    my $self = shift;
    my $text = $self->{_error} || shift || "Неизвестная ошибка"; 
	
    my $h = {};
    $h->{-nocache} = 1;
    $h->{-charset} = $self->{_echarset};
    $h->{-type} = "text/plain";
    $h->{-status}  = '500 Internal server error';
    
    $self->_header($h);
    print "Exception: $text";
    return undef;
};

sub notFound {
	my $self = shift;
	return NG::BlockContent->notFound(@_);
};

sub _do404 {
    my $cms = shift;

    my $ret = $cms->error();

    while (1) {
        #MODULE
        my $pObj = undef;
        my $m = $cms->confParam("CMS.404_MODULE",undef);
        if ($m) {
            $pObj = $cms->getModuleByCode($m,{PAGEPARAMS=>{}});
        }
        else {
            my $pm = $cms->confParam('CMS.DefaultPageClass',"NG::PageModule");
            $pObj = $cms->getObject($pm,{PAGEPARAMS=>{}});
        };
        last unless $pObj;
        
        #LAYOUT
        my $sRow = $cms->getSubsiteRow();
        my $langId = $sRow->{lang_id};
        my $subsiteId = $sRow->{id};
        
        my $layout = undef;
        $layout = $cms->confParam("CMS.404_LAYOUT_L".$langId,undef) if $langId && !defined $layout;
        $layout = $cms->confParam("CMS.404_LAYOUT_S".$subsiteId,undef) if $subsiteId && !defined $layout;
        $layout = $cms->confParam("CMS.404_LAYOUT",undef) if !defined $layout;
        
        unless ($layout || $m) {
            $ret = shift;
            last;
        };
        
        $ret = $cms->buildPage($pObj,$layout);
        last;
    };
    
    if (!defined $ret || ($ret && ref $ret ne "NG::BlockContent")) {
        $ret = $cms->output("Страница не найдена. При обработке страницы 404 получен некорректный код возврата");
    }; 
    if ($ret eq 0 || $ret->is_error()) {
        $ret = $cms->output("Страница не найдена. При обработке страницы 404 произошла ошибка: ".$cms->getError());
    };
    $ret->{_headers}->{-status} = "404 Not Found";
	return $cms->_doOutput($ret);
};

=head
return $cms->output($tmplObj->output());
return $cms->output($tmplObj);
return $cms->output($tmplObj,"text/plain");   
return $cms->output($tmplObj,"text/plain", $status); ## NOT SUPPORTED MORE
return $cms->output($tmplObj, -type=>"text/xml", -charset=>"utf-8", -status=>"200");
return $cms->output($outputData, -type=>"text/xml", -charset=>"utf-8", -status=>"200");
=cut

sub output {
	my $self = shift;
	return NG::BlockContent->output(@_);
};

sub exit {
    my $self = shift;
    return NG::BlockContent->exit(@_);
};

sub outputJSON {
	my $self = shift;
	my $json = shift;
	return NG::BlockContent->exit(create_json($json),-type=>"application/json");
};

sub _doOutput {
    my $self = shift;
	my $ret = shift;
	my $params = $ret->headers() || {};
	my $cookies = $ret->cookies();
    $params->{-cookie} = $cookies;

	$self->_header($params) or return;
    print $ret->getOutput();
    return 1;
};

=head
	return $cms->redirect($url);
	return $cms->redirect($url, -status=>301);
	return $cms->redirect(-uri=>$url, -status=>303, -cookie => $cookie );
    return $cms->redirect(-uri=>$url, -status=>303, -cookie => [$cookie1,$cookie2] );
=cut

sub redirect {
    my $self = shift;
    return NG::BlockContent->redirect(@_);
};

sub redirectRefererOr {
    my $self = shift;
    my $backup_url = shift;
    my $redirect_url = $self->q->referer();
    if (!defined $redirect_url || $redirect_url eq "")  {
        if (defined $backup_url && $backup_url ne "") {
                $redirect_url = $self->q->url(-base=>1).$backup_url;
        } else {
                $redirect_url = $self->q->url(-base=>1)."/";
        };
    };
    return NG::BlockContent->redirect($redirect_url);
};

sub _doRedirect {
	my $self = shift;
	my $ret = shift; 
	
    my $uri = $ret->getRedirectUrl();
	my $params = $ret->headers() || {};
	my $cookies = $ret->cookies();
	
    $uri = $self->q()->url(-base=>1).$uri if($uri !~ /^(http|https|ftp)\:\/\/.+$/);
	
	$params->{-uri} = $uri;
	$params->{-cookie} = [];
	push @{$params->{-cookie}}, @{$self->{_cookies}} if $self->{_cookies};
	push @{$params->{-cookie}}, @$cookies if $cookies;

    print $self->q->redirect( %$params );
    return 1;
};

sub processResponse {
    my $cms = shift;
    my $ret = shift;
	
	if ($ret && ref $ret ne "NG::BlockContent") {
		return $cms->showError("processResponse(): Некорректный объект ответа");
	};
	
	if (!$ret || $ret->is_error) {
		$cms->{_error} = $ret->getError() if $ret;
		return $cms->showError("Ошибка контроллера");
	}
    elsif ($ret->is_output() || $ret->is_exit()) {
        return $cms->_doOutput($ret);
    }
    elsif ($ret->is_redirect) {
        return $cms->_doRedirect($ret);
    }
	elsif ($ret->is_404){
		return $cms->_do404($ret);
	}
    else {
        return $cms->showError("Ошибка контроллера - неизвестный код возврата");
    };
};

# NG::Application Interface method
sub run {
    my $cms=shift;
    
    if ($cms->{_pm}) {
        my $ret = $cms->runPageController($cms->{_pm});
        return $cms->processResponse($ret);
    };

    $cms->openConfig() || return $cms->showError();
    
    my $url = $cms->q()->url(-absolute=>1);
    my ($ret,$subsiteId) = $cms->findSubsite($url); #or return; # 302 или Error

    return $cms->processResponse($ret) unless $ret eq NG::Application::M_OK;

    #if ($url =~ /\/news/) {
    #    $cms->runPageController("SBI::News",$opts);
    #};

    #Система статистики: TODO: заменить на отдельный спец вызов
    my $counterClass = $cms->confParam("Site.CounterClass","");
    my $counterObj = undef;
    if ($counterClass) {
        $counterObj = $cms->getObject($counterClass) or return $cms->showError();
    };
    
    $ret = $cms->processRequest($url,$subsiteId);

    if ($counterObj) {
        $counterObj->countPage($ret) or $counterObj->showError();
    };

    return $cms->processResponse($ret);
};

sub openConfig {
    my $self = shift;
    $self->{_confObj} = $self->getObject("Config::Simple",$self->{_config_dir}."site.cfg");
    $self->{_confObj} || $self->setError("Could not open config '".$self->{_config_dir}."site.cfg': ". Config::Simple->error());
};

sub setStash ($$$) {
    my $self = shift;
    my $key  = shift;
    my $value = shift;
    
    unless ($value) {
        delete $self->{_stash}->{$key};
        return undef;
    }
    warn "setStash(): key $key already has value" if exists $self->{_stash}->{$key};
    $self->{_stash}->{$key} = $value;
};

sub getStash ($$) {
    my $self = shift;
    my $key  = shift;
    
    unless (exists $self->{_stash}->{$key}) {
        #warn "Applicaton::getStash(): key $key not found";
        return undef;
    };
    return $self->{_stash}->{$key};
};

sub getModuleByCode ($$) {
	my $cms = shift;
	my $code = shift;
	my $opts = shift || {};

    my $hash = $cms->modulesHash({CODE=>$code});
    NG::Exception->throw('NG.INTERNALERROR', "modulesHash() не вернул значения для CODE $code") unless $hash;
    NG::Exception->throw('NG.INTERNALERROR', "Возвращенное modulesHash() значение не HASHREF") if ref $hash ne "HASH";
    
    NG::Exception->throw('NG.INTERNALERROR', "Хэш из modulesHash() не содержит ключа $code") unless exists $hash->{$code};
    my $v  = $hash->{$code};
    NG::Exception->throw('NG.INTERNALERROR', "Хэш из modulesHash() содержит не HASHREF для кода $code") if ref $v ne "HASH";
    
    #TODO: support PARAMS key?
    #TODO: перенести парсинг параметров из NG::Module->moduleParam()/_parseParams() на этот уровень?
    my $mRow = $v->{MODULEROW};
    NG::Exception->throw('NG.INTERNALERROR', "MODULEROW из modulesHash() содержит не HASHREF для кода $code") if $mRow && ref $mRow ne "HASH";

    my $m = $v->{MODULE};
    $m ||= $mRow->{module} if $mRow;
    NG::Exception->throw('NG.INTERNALERROR', "Хэш из modulesHash() не содержит значения MODULE или MODULEROW.module для кода $code") unless $m;
    $mRow ||= {module=>$m,code=>$code};
    
    #getModuleByRow() is below.
    $opts->{MODULEROW} = $mRow;
    return $cms->getObject($m,$opts);
};

=head
sub modulesHash {
    my ($cms,$helper) = (@_);
    return {
        NEWS => {MODULE=>'Site::News',MODULEROW=>{base=>'/news/'}, PARAMS => TODO },
    };
}
=cut

sub modulesHash {
    my $cms = shift;
    my $ref = shift;
    
    return undef unless $ref;
    
    if ($ref->{CODE}) {
        return $cms->{_mrowC} if exists $cms->{_mrowC}->{$ref->{CODE}};
        my $mRow = $cms->getModuleRow("code=?",$ref->{CODE}) or NG::Exception->throw('NG.INTERNALERROR', "Запрошенный модуль ".$ref->{CODE}." не найден");
        $cms->{_mrowC}->{$ref->{CODE}} = { MODULE=>$mRow->{module},MODULEROW=>$mRow };
    }
    elsif ($ref->{REF}) {
        return $cms->{_mrowC} if exists $cms->{_mrowR}->{$ref->{REF}};
        my $fields = $cms->getModuleFields();
        my $sth = $cms->dbh()->prepare("select $fields from ng_modules where module=?") or NG::DBIException->throw();
        $sth->execute($ref->{REF}) or NG::DBIException->throw();
        while (my $mRow = $sth->fetchrow_hashref()) {
            $cms->{_mrowC}->{$mRow->{code}} = { MODULE=>$mRow->{module},MODULEROW=>$mRow };
        };
        $sth->finish();
        $cms->{_mrowR}->{$ref->{REF}} = 1;
    }
    else {
        return undef;
    }
    return $cms->{_mrowC};
};

=head
 Usage:
 
 my $iterator = $cms->getModulesIterator();
 while (my $moduleObj = &$iterator()) {
    ....
 }
=cut 

sub getModulesIterator {
    my $cms = shift;
    
    my $dbh = $cms->dbh();
    my $fields = $cms->getModuleFields();
    my $sth = $dbh->prepare("select $fields from ng_modules") or return $cms->error($DBI::errstr);
    $sth->execute() or return $cms->error($DBI::errstr);

    my $modules = [];
    while (my $mRow = $sth->fetchrow_hashref()) {
        $cms->{_mrowC}->{$mRow->{code}} = { MODULE=>$mRow->{module},MODULEROW=>$mRow };
        push @$modules, $mRow->{code};
    };
    $sth->finish();
    
    return sub {
        for (;;) {
            my $code = shift(@$modules) or return undef; 
            return $cms->getModuleByCode($code);
        };
    };
};

sub getModuleInstance ($$) {
    my $cms  = shift;
    my $code = shift;
    
    unless (exists $cms->{_moduleInstances}->{$code}) {
		my $mObj = $cms->getModuleByCode($code) or return $cms->defError("getModuleInstance():");
        $cms->{_moduleInstances}->{$code} = $mObj;
    };
    
    return $cms->{_moduleInstances}->{$code};
};

sub _fixBlock {
    my $cms = shift;
    my $block = shift;

    $block->{ID}   = delete $block->{block_id};
    $block->{NAME} = delete $block->{name};
    $block->{CODE} = delete $block->{code};
    $block->{TYPE} = delete $block->{type};
    $block->{ACTION} = delete $block->{action};
    $block->{PARAMS} = delete $block->{params};
    
    my $mRow = {};
    $mRow->{id}     = delete $block->{module_id};
    $mRow->{code}   = delete $block->{module_code};
    $mRow->{module} = delete $block->{module};
    $mRow->{base}   = delete $block->{module_base};
    $mRow->{name}   = delete $block->{module_name};
    $mRow->{params} = delete $block->{module_params};
    $block->{MODULEROW} = $mRow;
    
    $block->{REGION} = delete $block->{region};
    $block->{WEIGHT} = delete $block->{weight};
    
    return $block;
};

sub getBlock {
    my $cms = shift;
    
    my $code = shift;
    my $dbh = $cms->dbh();
    
    my $sql = "select b.id as block_id, b.name as name, b.code as code, b.module_id, b.action as action, b.params as params, b.active as block_active, b.fixed as block_fixed, b.editable as block_editable, b.type as type, 
               m.code as module_code, m.module, m.base as module_base,m.name as module_name, m.params as module_params 
            from ng_blocks b, ng_modules m
            where m.id = b.module_id and b.code = ?";
    my $sth = $dbh->prepare($sql) or return $cms->error(__PACKAGE__."::getBlock(): ".$DBI::errstr);
    $sth->execute($code) or return $cms->error(__PACKAGE__."::getBlock(): ".$DBI::errstr);
    my $block = $sth->fetchrow_hashref();
    $sth->finish();
    return undef unless $block;
    $cms->_fixBlock($block);
    #TODO: active, fixed, disabled,editable
    #TODO: сделать трансформацию параметров params && module.params в хэши.
    return $block;
};

sub getTemplateBlocks {
    my $cms = shift;
    my $tmplFile = shift;
    my $dbh = $cms->dbh();

    my $sql = "select b.id as block_id, b.name as name, b.code as code, b.module_id, b.action as action, b.params as params, b.active as block_active, b.fixed as block_fixed, b.editable as block_editable, b.type as type, 
               m.code as module_code, m.module, m.base as module_base,m.name as module_name, m.params as module_params, 
               tb.disabled, tb.region as region, tb.weight as weight
            from ng_blocks b, ng_tmpl_blocks tb, ng_modules m
            where m.id = b.module_id and tb.block_id = b.id and tb.template = ?";
    my $sth = $dbh->prepare($sql) or return $cms->error(__PACKAGE__."::getTemplateBlocks(): ".$DBI::errstr);
    $sth->execute($tmplFile) or return $cms->error(__PACKAGE__."::getTemplateBlocks(): ".$DBI::errstr);
    my @blocks = ();
    while (my $block = $sth->fetchrow_hashref()) {
        $cms->_fixBlock($block);
        #TODO: active, fixed, disabled,editable
        #TODO: сделать трансформацию параметров params && module.params в хэши.
        push @blocks,$block;
    };
    $sth->finish();
    return \@blocks;
};

sub getNeighbourBlocks {
    my $cms = shift;
    my $bCode = shift;
    my $dbh = $cms->dbh();

    my $sql = "select b.id as block_id, b.name as name, b.code as code, b.module_id, b.action as action, b.params as params, b.active as block_active, b.fixed as block_fixed, b.editable as block_editable, b.type as type, 
               m.code as module_code, m.module, m.base as module_base,m.name as module_name, m.params as module_params, 
               nb.disabled, nb.region as region, nb.weight as weight
            from ng_blocks b, ng_neigh_blocks nb, ng_modules m
            where m.id = b.module_id and nb.block_id = b.id and nb.pcode = ?";
    my $sth = $dbh->prepare($sql) or return $cms->error(__PACKAGE__."::getNeighbourBlocks(): ".$DBI::errstr);
    $sth->execute($bCode) or return $cms->error(__PACKAGE__."::getNeighbourBlocks(): ".$DBI::errstr);
    my @blocks = ();
    while (my $block = $sth->fetchrow_hashref()) {
        $cms->_fixBlock($block);
        #TODO: active, fixed, disabled,editable
        #TODO: сделать трансформацию параметров params && module.params в хэши.
        push @blocks,$block;
    };
    $sth->finish();
    return \@blocks;
};

=head
=cut

{
	package UNIVERSAL;
	
    ## "Адресное" пространство конфига
    ## [%NG::Module%_%GROUP%]
    ## [MODULE_%MODULECODE%]
    ## [BLOCK_%BLOCKCODE%]
    ## [CMS]
    
	# универсальная работа с конфигом
	# значение из группы -  $self->confParam('group','option','default');  #[NG::Module_GROUP]
	# значение без группы - $self->confParam(null,'option','default');     #Param=value
	# как метод CMS: $cms->confParam($param,$default)
	# как метод CMS: NG::Application->confParam($param,$default)
    # как метод модуля (наследник NG::Module)->confParam($param,$default)  #[MODULE_%MODULECODE%].param=value
	sub confParam {
		my $invoker = shift;
		my $param = shift;
		
        my @c = caller(0);
        my $cobj = $NG::Application::cms->{_confObj};
        if (ref $invoker && $invoker->isa("NG::Module")) {
            my $code = $invoker->getModuleCode() or die "confParam($param): at ".$c[0]." line ".$c[2].": can`t getModuleCode()";
            $param = "MODULE_" .$code.'.'.$param;
        }
        elsif ($invoker eq "NG::Application" || ref $invoker && $invoker->isa("NG::Application")) {
            #Do nothing
        }
        else {
			$invoker = ref $invoker if ref $invoker;
			my $group = $param;
			$param = shift;
			$param = $invoker . ( $group ? '_'.$group : '' ).'.'.$param;
		};
		
		die $c[3]."($param) config not opened and no default value at ".$c[0]." line ".$c[2] unless $cobj || scalar @_;
		
		my $defaultValue = shift;
		return $defaultValue unless $cobj;
        my $v = $cobj->param($param);
        defined $v or return $defaultValue;
        $v;
	};
    
    sub cms { return $NG::Application::cms; };
    sub db  { return $NG::Application::cms->{_db}; };
    sub dbh { shift; return $NG::Application::cms->{_db}->dbh(@_); };
    sub q   { return $NG::Application::cms->{_q};  };
};

package NG::ResourceController;

our $AUTOLOAD;

sub new {
    my $class = shift;
    my $self = {};
    bless $self,$class;
	my $cms = $self->cms();
    $self->{_parent} = shift or return $cms->error("NG::ResourceController has no parent object");
	$self->{_parent}->can("getResource") or return $cms->error("Class has no getResource() method");
    return $self;
};

sub AUTOLOAD {
    my $self = shift;
    my $param = $AUTOLOAD;
    my $package = ref $self;
    $param =~ s/$package\:\://;
    return $self->{_parent}->getResource($param);
};

sub DESTROY {};

package NG::Cache::Stub;
use strict;

sub getCacheContentKeys {
    return {};
};

sub getCacheContent {
    return {};
};

sub storeCacheContent {
    return 1;
};

BEGIN {
    return if $NG::Application::Cache;
    $NG::Application::Cache = {};
    bless $NG::Application::Cache,__PACKAGE__;
};

return 1;
END{};
