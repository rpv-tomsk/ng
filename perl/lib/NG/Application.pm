package NG::Application;
use strict;

use Carp;
use Carp qw(cluck);
use HTML::Template::Compiled 0.85;
use NG::Nodes;
use NGService;
use NHtml;
use NSecure;
use Config::Simple;
use NG::Session;

use NG::BlockContent;

$NG::Application::VERSION = 0.5;

use constant M_ERROR    => 0;  # крайне не рекомендуется менять эту критично важную константу
use constant M_OK       => 1;
use constant M_REDIRECT => 2;
use constant M_404      => 3;
use constant M_EXIT     => 4;

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
    
    $self->{_siteroot} = $param{SiteRoot};
    $self->{_docroot}      = $self->{_siteroot}."/htdocs/";
    $self->{_template_dir} = $self->{_siteroot}."/templates/";
    $self->{_config_dir}   = $self->{_siteroot}."/config/";
    $self->{_cookies} = [];
    $self->{_charset} = "windows-1251";
	$self->{_type} = "text/html";

    $self->{_nocache}=0;
    $self->{_headerssent} = 0;
    
    $self->{_error} = "";
    $self->{_confObj} = undef;

    $self->{_events_cache} = undef; # Cache registered events
    $self->{_events} = {}; # List executing events in this time
    
    #NG::CMS
    #$self->{_pageParams} = undef;
    $self->{_subsiteRow} = undef;
    
    $self->{_moduleInstances} = {};
    $self->{_stash} = {};
    $self->{_mstash} = {};   ##Stash for NG::Module stash methods.
	
	$self->openConfig();
    
    $NG::Application::cms = $self;
    $NG::Application::pageObj = undef;
    $self;
};

sub getDocRoot()  { return $_[0]->{_docroot};  };
sub getSiteRoot() { return $_[0]->{_siteroot}; };

sub getSubsiteRow { return $_[0]->{_subsiteRow}};

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
    getObject($class, parameters-for-new()-constructor)
    TODO: сделать поддержку версии в параметре $class, значение вида "Site::Module 0.123".
=cut

sub getObject {
    my $cms = shift;
    my $class = shift or return croak("getObject: No class value");
    
#use Data::Dumper;    
#warn "cms->getObject($class). Opts=".Dumper(@_);
    
	unless ($class->can("can") && $class->can("new")) {
		eval "use $class;";
        return $cms->error("Ошибка подключения модуля \"".$class."\": ".$@) if ($@);
        
        #warn $@ if $@;
        #return $cms->setError("Не могу подключить модуль $module. Подробный текст ошибки в логе сервера.") if ($@);
	};
    unless (UNIVERSAL::can($class,"new")) {
		return $cms->error("Класс $class не содержит конструктора new().");
	}; 
	my $bObj = $class->new(@_) or return $cms->error("Ошибка создания объекта класса $class");
    return $bObj;
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
    #учесть, что рутовая нода подсайта может быть отключена и редиректить на нее нет смысла
    #что делать если пользователь отключит ВСЕ подсайты?(Vinnie 15.08.2010 2:51:43)
    my $where  = "st.id = ss.root_node_id and st.disabled=0";
    
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
		$pageFields .= ",".$addon if $addon;
	};
	return $pageFields;
};

sub findPageRowByURL {
    my $cms = shift;
    my $url  = shift;
    my $ssId = shift || 0;
    
    my $dbh = $cms->db()->dbh();
    
	#Загружаем свойства страницы
    my $fields = $cms->getPageFields();
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
    
    my $dbh = $cms->db()->dbh();
    
    if ($url !~ /[\\\/]$/) {
        $url .= "/";
        return $cms->redirect(-uri=>$url,-status=>301);
    };
    
    my $row = $cms->findPageRowByURL($url,$ssId);
    return $cms->notFound() unless defined $row;
    return $cms->error() unless $row;
    
    #подмена основного шаблона на шаблон для печати
    $row->{'template'}=$row->{'print_template'} if $cms->isPrint();
    
    $row->{keywords} =~ s/[\r|\n]/ /gi if $row->{keywords};
    $row->{description} =~ s/[\r|\n]/ /gi if $row->{description};
    #$row->{'pageBaseUrl'}=$row->{'url'} unless($row->{'pageBaseUrl'});
    #TODO: fix
    $cms->{_pageRow} = $row;
    #$cms->setLinkId($row->{'link_id'});
    
    my $pageObj = $cms->getPageObjByRow($row) or return $cms->error();
    return $cms->error("Модуль ".(ref $pageObj)." не содержит метода run") unless $pageObj->can("run");
    return $pageObj->run();
};

sub getPageRowById {
	my $cms = shift;
	my $pageId = shift || return $cms->error("getPageRowById(): Отсутствует параметр pageId");

	my $pageFields = $cms->getPageFields();
	
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
    my $where = shift or return $cms->error("getModuleRow(): Отсуствует параметр where");

    my $dbh = $cms->db()->dbh();

    my $sth = $dbh->prepare("select id,code,module,base,name from ng_modules where $where") or return $cms->error($DBI::errstr);
    $sth->execute(@_) or return $cms->error($DBI::errstr);
    my $mRow = $sth->fetchrow_hashref();
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
    
    return $cms->notFound unless defined $ab; #TODO: выводить 404 через запрос блока или лайоута в конфиге
    return $cms->defError("getActiveBlock()","неизвестная ошибка") if $ab eq 0;
    return $ab if ref $ab && UNIVERSAL::isa($ab,'NG::BlockContent');
    return $cms->error("getActiveBlock() модуля ".(ref $pageObj)." вернул некорректное значение (не HASHREF)") unless ref $ab eq "HASH";
    return $cms->error("getActiveBlock() модуля ".(ref $pageObj)." вернул некорректное значение (отсутствует код BLOCK)") unless $ab->{BLOCK};
    
    my $mName = $pageObj->getModuleCode() or return $cms->error();
    
    my $aBlock = {};
    $aBlock->{CODE} = $mName."_".$ab->{BLOCK};
    $aBlock->{ACTION} = $ab->{BLOCK};
    $aBlock->{LAYOUT} = $ab->{LAYOUT};
    
    my $abKeys = {}; # KEY ETAG LM CACHE_ALWAYS_VALID???
    if ($pageObj->can("getBlockKeys")) {
        #$notModified = 0;
        #last;
        $abKeys = $pageObj->getBlockKeys($ab->{BLOCK}) or return $cms->error("getBlockKeys() блока ".$ab->{BLOCK}." не вернул значения"); # KEY ETAG LM CACHE_ALWAYS_VALID???
        return $cms->error("getBlockKeys() блока ".$ab->{BLOCK}." вернул не хэш") unless ref $abKeys eq "HASH"; 
    };
    
    #return $cms->error("getBlockKeys() активного блока ".$ab->{BLOCK}." страницы не вернул ключа KEY") unless exists $abKeys->{KEY};
    
    $aBlock->{KEYS} = $abKeys;
    $aBlock->{KEY}  = $abKeys->{KEY} if exists $abKeys->{KEY};
    $aBlock->{MODULEOBJ} = $pageObj;
    return $aBlock;
};

sub buildPage {
    my $cms = shift;
    my $pageObj = shift;
    my $layout = shift;
    
    my $q   = $cms->q();
    
    my $aBlock = $cms->getPageActiveBlock($pageObj);
    return $aBlock if defined $aBlock && ($aBlock eq "0" || (ref $aBlock && UNIVERSAL::isa($aBlock,'NG::BlockContent')));
    
    if ($aBlock) {
        my $abLayout = undef;
        
        my $layoutConf = "LAYOUT";
        $layoutConf = "PRINTLAYOUT" if $cms->isPrint();
        my $langId = $pageObj->getPageLangId();
        my $subsiteId = $pageObj->getSubsiteId();
        
        #1. Считываем параметр layout блока для языка "BLOCK_{CODE}.LAYOUT_{LANG}|BLOCK_{CODE}.PRINTLAYOUT_{LANG}"
        $abLayout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf."_L".$langId,undef) if $langId && !defined $abLayout;
        #1.1 Считываем параметр layout блока для подсайта "BLOCK_{CODE}.LAYOUT_S{ID}|BLOCK_{CODE}.PRINTLAYOUT_S{ID}" 
        $abLayout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf."_S".$subsiteId,undef) if $subsiteId && !defined $abLayout;
        #2. Считываем параметр "BLOCK_{CODE}.LAYOUT|BLOCK_{CODE}.PRINTLAYOUT"
        $abLayout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf,undef) if !defined $abLayout;
        #3. Берем параметр layout из параметров блока
        $abLayout = $aBlock->{LAYOUT} if exists $aBlock->{LAYOUT} && !defined $abLayout;
        
        $layout = $abLayout if defined $abLayout;
    };
    
    unless ($layout || $aBlock) {
        return $cms->error("Страница без активного блока не содержит шаблона. Отображение невозможно");
    };
    
    my $bctrl = $cms->getObject("NG::BlocksController",$pageObj) or return $cms->error();
    if ($aBlock) {
        $bctrl->pushBlock($aBlock) or return $cms->error();
    };
    
    my $abContent = undef;
    if ($aBlock && !exists $aBlock->{KEY}) {
        #Если нет KEY значит кэширование невозможно.
        #Сделаем вызов getBlockContent() до построения списка блоков, на случай редиректа и т д  - оптимизация.
        $abContent = $bctrl->getBlockContent($aBlock->{CODE});
        return $abContent if ($abContent eq 0 || !$abContent->is_output());
    };
    
    my $lBlocks = undef;  # {Хэш, с ключами = код блоков шаблона}
    my $nBlocks = undef;  # {Хэш, с ключами = код блоков шаблона}
    
    if ($layout) {
        #получаем список блоков шаблона.
        $lBlocks = $bctrl->loadTemplateBlocks($layout) or return $cms->error();
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
    $bctrl->requestCacheKeys(); #Запрашиваем ключи всех блоков страницы, чтобы сравнить 
    
    if ($abContent || ($aBlock && !$bctrl->hasValidCacheContent($aBlock))) {
        #Если в кэше нет контента для АБ, запрашиваем его отдельным запросом, позволяя коды возврата
        $abContent ||= $bctrl->getBlockContent($aBlock->{CODE});
        return $abContent if ($abContent eq 0 || !$abContent->is_output());
    };
    
    $bctrl->prepareContent() or return $cms->error(); # делаем запрос контента для всех блоков
    
    $bctrl->splitRegions() or return $cms->error();
    
    my $rContent = $bctrl->getRegionsContent() or return $cms->error();
    
    warn "No layout to output regions" if (!$layout && scalar keys %$rContent > 1);
    return $cms->output($rContent->{CONTENT}) unless $layout;
    
    my $tObj = $cms->gettemplate($layout) or return $cms->error();
    $bctrl->attachTemplate($tObj) or return $cms->error();
    
    my $rObj = $cms->getObject("NG::ResourceController",$cms) or return $cms->error();
    $tObj->param(
        REGION=>$rContent,
        PAGEROW => $pageObj->getPageRow(),
        SUBSITEROW => $cms->{_subsiteRow},
        RES => $rObj
    );
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

#TODO: переименовать
sub isPrint {
    my $self=shift;
    return 1 if(defined $self->q()->param('print'));
    return 0;  
};

sub getPrintParam {
    my $self=shift;
    return "print=1";
};

=head
sub getPageParams {
    my $cms = shift;
    return $cms->{_pageParams};
};
=cut



## /NG::CMS functions


#TODO: обсудить кэширование, запись, очистку сессий средствами CMS

sub _session {
	my $self  = shift;
	my $meth  = shift;
	
	my $cname = shift || "Face";
	my $sid   = shift;
	my $params= shift;
	
	$self->openConfig();
	my $session = NG::Session->$meth(
		{
			App      => $self,
			ConfName => $cname,
		},
		$sid,
		$params,
	);
	
	unless ($session) {
		$self->setError(NG::Session::errstr());
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

sub gettemplate {
	my $self = shift;
	my $filename = shift;

    unless ( -f $self->{_template_dir}.$filename ) {
        $self->setError("Could not open template '$filename': $!");
        return undef;
    };

    my $tmplObj = $self->getObject("HTML::Template::Compiled",
        filename=>$filename,
        path=>$self->{_template_dir},
        loop_context_vars=>1,
        die_on_bad_params=>0,
        global_vars=>1,
        cache=>0,
	use_expressions=>1,
        use_perl => 1, # enable <TMPL_PERL>
        #debug=>1,
        #stack_debug=>1,
        #cache_dir=> $self->{_siteroot}."/htc_cache",
        case_sensitive => 0
    ) or return $self->error();

    #TODO: передавать PAGEPARAMS через объект, чтобы можно было в модуле менять параметры страницы
    #$tmplObj->param(
    #    PAGEPARAMS => $self->{_pageParams},
    #);
    
    return $tmplObj;
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
	
	$self->_header({-nocache=>1});
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
        use Data::Dumper;
        $ret = $cms->output("Страница не найдена. При обработке страницы 404 получен некорректный код возврата ".Dumper($ret));
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
	return NG::BlockContent->exit(create_json($json),-type=>"application/x-javascript");
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
		return $cms->showError("Ошибка контроллера ".$cms->{_error});
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
    my $self = shift;
    $self->_header();
    print "You must redefine sub run() {} in your module ".ref $self;
};


sub getConfigObject {
	my $self = shift;
	my $configName = shift || die "NG::Application::getConfigObject(): configName parameter missing";
	
    return new Config::Simple($configName,@_) || $self->setError("Could not open config '$configName': ". Config::Simple->error());
};

sub openConfig {
    my $self = shift;
    $self->{_confObj} = $self->getConfigObject($self->{_config_dir}."site.cfg");    
}

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
        #warn "getStash(): key $key not found";
        return undef;
    };
    return $self->{_stash}->{$key};
};

sub getModuleByCode ($$) {
	my $cms = shift;
	my $code = shift;

	my $opts = shift || {};

    my $hash = $cms->modulesHash({CODE=>$code});
    return $cms->defError("getModuleByCode():","modulesHash() не вернул значения") unless $hash;
    return $cms->defError("getModuleByCode():","возвращенное modulesHash() значение не HASHREF") if ref $hash ne "HASH";
    
    return $cms->error("getModuleCode: Хэш из modulesHash() не содержит ключа $code") unless exists $hash->{$code};
    my $v  = $hash->{$code};
    return $cms->defError("getModuleByCode():","Хэш из modulesHash() содержит не HASHREF для кода $code") if ref $v ne "HASH";
        
    my $m = $v->{MODULE};
    my $mRow = $v->{MODULEROW};
    #TODO: support PARAMS key ?
    return $cms->defError("getModuleByCode():","MODULEROW из modulesHash() содержит не HASHREF для кода $code") if $mRow && ref $mRow ne "HASH";
    $m ||= $mRow->{module} if $mRow;
    
    return $cms->error("getModuleByCode(): Хэш из modulesHash() не содержит значения MODULE или MODULEROW.module для кода $code") unless $m;

    $opts->{MODULEROW} = $mRow;
	my $mObj = $cms->getObject($m,$opts) or return $cms->defError("getModuleByCode():");
	return $mObj;
};

sub modulesHash {
    my $cms = shift;
    my $ref = shift;
    
    return undef unless $ref;
    
    my $mRow = undef;
    if ($ref->{CODE}) {
        $mRow ||= $cms->getModuleRow("code=?",$ref->{CODE}) or return $cms->defError("getModuleByCode():","Запрошенный модуль ".$ref->{CODE}." не найден");
    }
    elsif ($ref->{REF}) {
        $mRow = $cms->getModuleRow("module=?",$ref->{REF}) or return undef;
    }
    else {
        return undef;
    }
    return {$mRow->{code}=>{MODULE=>$mRow->{module},MODULEROW=>$mRow}}; 
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

=head
=cut

sub getCacheContentKeys {
    my $cms = shift;
    return {};
};

sub getCacheContent {
    my $cms = shift;
    return {};
};

sub storeCacheContent {
    my $cms = shift;
    return 1;
};

=head
=cut

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
		my $inovacate = shift;
		my $param = shift;
		
        my @c = caller(0);
        my $cobj = $NG::Application::cms->{_confObj};
        
        if (ref $inovacate && $inovacate->isa("NG::Module")) {
            my $code = $inovacate->getModuleCode() or die "confParam($param): at ".$c[0]." line ".$c[2].": can`t getModuleCode()";
            $param = "MODULE_" .$code.'.'.$param;
        }
        elsif ($inovacate eq "NG::Application" || ref $inovacate && $inovacate->isa("NG::Application")) {
            #Do nothing
        }
        else {
			$inovacate = ref $inovacate if ref $inovacate;
			my $group = $param;
			$param = shift;
			$param = $inovacate . ( $group ? '_'.$group : '' ).'.'.$param;
		};
		
		die $c[3]."($param) config not opened and no default value at ".$c[0]." line ".$c[2] unless $cobj || scalar @_;
		
		my $defaultValue = shift;
		return $defaultValue unless $cobj;
		return $cobj->param($param) || $defaultValue;	
	};
    
    sub cms { return $NG::Application::cms; };
    sub db  { return $NG::Application::cms->{_db}; };
    sub dbh { return $NG::Application::cms->{_db}->dbh(); };
    sub q   { return $NG::Application::cms->{_q};  };
}

return 1;
END{};