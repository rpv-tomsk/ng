package NG::BlocksController;
use strict;

our $CACHE;

our $MAX_CACHE_TIME = 300;

BEGIN {
    $CACHE = $NG::Application::Cache;
};

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);    
    #$self->config();
    return $self; 
};

sub init {
    my $self = shift;
    $self->{_tmplFile} = undef;
    $self->{_ablock} = undef;
    $self->{_blocks} = [];
    $self->{_hblocks} = {};
    $self->{_pObj} = shift;
    #$self->{_modulesContent} = {}; # Содержимое блоков.
    #$self->{_pluginsContent} = {}; # Ключ: аналогично ключу в шаблоне
    #
    $self->{_usedBCodes} = {}; # Использованные в шаблоне коды блоков
    #
    $self->{_regions} = {};
    
    $self;
};

sub loadTemplateBlocks {
    my $self = shift;
    my $tmplFile = shift or die __PACKAGE__."::loadTemplateBlocks(\$): tmplFile expected";
    
    my $cms = $self->cms();

    $self->{_tmplFile} = $tmplFile;
    my $tBlocks = $cms->getTemplateBlocks($tmplFile); # [] of {}.
    
    return $cms->error("cms->getTemplateBlocks() returns undef") unless defined $tBlocks;
    return $cms->defError("cms->getTemplateBlocks(): ") if $tBlocks eq 0;
    return $cms->error("cms->getTemplateBlocks() result is not ARRAYREF ") unless ref $tBlocks eq "ARRAY";
    
    #foreach my $bCode (keys %$tBlocks) {
    #    my $block = $tBlocks->{$bCode};
    #    $block->{CODE} = $bCode;
    #    $self->pushBlock($block) or return $cms->error();
    #};
    my $r = {};
    foreach my $block (@$tBlocks) {
        my $b = $self->_pushBlock($block) or return $cms->error();
        $b->{SOURCE}="tmpl";
        $r->{$b->{CODE}} = $b;
    };
    return $r;
};

sub currentLayout {
    my $self = shift;
    return $self->{_tmplFile};
};

sub loadNeighbourBlocks {
    my $self = shift;
    my $pBlock = shift or die __PACKAGE__."::loadNeighbourBlocks(\$): tmplFile expected";
    
    my $cms = $self->cms();

    my $tBlocks = $cms->getNeighbourBlocks($pBlock); # [] of {}.
    
    return $cms->error("cms->getNeighbourBlocks() returns undef") unless defined $tBlocks;
    return $cms->defError("cms->getNeighbourBlocks(): ") if $tBlocks eq 0;
    return $cms->error("cms->getNeighbourBlocks() result is not ARRAYREF ") unless ref $tBlocks eq "ARRAY";
    
    my $r = {};
    foreach my $block (@$tBlocks) {
        my $b = $self->_pushBlock($block) or return $cms->error();
        $b->{SOURCE}="neigh";
        $r->{$b->{CODE}} = $b;
    };
    return $r;
};

sub _pushBlock {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();
    
    return $cms->error("pushBlock(): Отсутствует имя блока CODE") unless $block->{CODE};
    return $cms->error("Block already exists") if exists $self->{_hblocks}->{$block->{CODE}};
    
=comment Ключи хэша $block
    Ключи хэша
     CODE - Обязательное значение. Блок идентифицируется уникальным кодом CODE.
     TYPE - Разделение - плагин/блок модуля. По умолчанию - считаем что это блок модуля, значение 0 или отсутствие ключа.

     SOURCE
     KEYS
     CACHEKEYS
     CONTENT

    #Блок модуля
      CODE = {MODULECODE}_{ACTION}. ACTION - имя блока, который мы запрашиваем построить у модуля
      TYPE = 0 или отсутствует
      
      MODULECODE - Код вызываемого модуля определяется из CODE
      ACTION     - Имя блока определяется из CODE
    
    #Плагин
      CODE - содержит значение произвольного вида
      TYPE = 1
      
      MODULECODE - Код вызываемого модуля, поскольку выделять - неоткуда
      ACTION - обязательное значение, поскольку выделить из CODE - невозможно.
      
      
    #Вредные параметры, которые практически недопустимы в определении блока.
      MODULE - класс модуля. При отсутствии, определяется по коду модуля вызовом
      MODULEROW - параметры создания модуля. 
=cut

    
    $block->{TYPE} = 0 unless exists $block->{TYPE};
    
    if ($block->{TYPE}) {
        $block->{MODULECODE} ||= $block->{MODULEROW}->{code} if ($block->{MODULEROW} && $block->{MODULEROW}->{code});
        return $cms->error("Не найдено значение ключа ACTION для записи плагина ".$block->{CODE}) unless $block->{ACTION};
        return $cms->error("Не найдено значение ключа MODULECODE для записи плагина ".$block->{CODE}) unless $block->{MODULECODE};
    }
    else {
        #Блок модуля
        if ($block->{CODE} =~ /([^_]+)_(.*)$/) {
            warn "ACTION (".$block->{ACTION}.") != action from CODE (".$block->{CODE}.")" if $block->{ACTION} && $block->{ACTION} ne $2;
            warn "MODULECODE != module code from CODE" if $block->{MODULECODE} && $block->{MODULECODE} ne $1;
            $block->{MODULECODE} = $1;
            $block->{ACTION} = $2;
        }
        elsif ($block->{ACTION} && $block->{MODULECODE}) {
            warn "CODE looks like plugin definition, and ACTION and MODULECODE exists";
            $block->{TYPE} = 1;
        }
        else {
            return $cms->error("Значение CODE (".$block->{CODE}.") не соответствует маске MODULECODE_ACTION");
        };
    };
    
    if ($block->{MODULEROW}) {
        return $cms->error("MODULEROW is not HASHREF") unless ref $block->{MODULEROW} eq "HASH";
        return $cms->error("MODULEROW.code != MODULE") if ($block->{MODULEROW} && $block->{MODULEROW}->{code} && $block->{MODULEROW}->{code} ne $block->{MODULECODE});
    };
    
    push @{$self->{_blocks}}, $block;
    $self->{_hblocks}->{$block->{CODE}} = $block;
    return $block;
};

sub pushABlock {
    my $self = shift;
    my $block = $self->_pushBlock(@_) or return $self->cms->error();
    $block->{SOURCE} = "push";
    $self->{_ablock} = $block;
    
    ## Запрашиваем из кэша метаданные АБ т.к. в них могут быть данные нужные для ключей прочих блоков
    my $abKeys = $self->_getBlockKeys($block) or return $self->cms->error();
    
    if (!$abKeys->{REQUEST}) {
        #Если нет REQUEST значит кэширование невозможно.
        #Сделаем вызов getBlockContent() до построения списка блоков, на случай редиректа и т д  - оптимизация.
        return $self->getBlockContent($block);
    };
    #Сделаем возврат без получения реального контента. 
    #Контент и его ключи будут запрошены в общем вызове, вместе со всеми остальными (не АБ) блоками
    return NG::BlockContent->output("DUMMY") unless $abKeys->{HASRELATED};
    #Кеширование возможно, но у нас есть подчиненные блоки, необходимо запросить метаданные.
    #Для надежности, сразу запрашиваем и контент, для обработки случая его отсутствия в кеше.
    
    my $keys = $CACHE->getCacheContentKeys([{REQUEST=>$abKeys->{REQUEST},CODE=>$block->{CODE}}]) or die; #return $self->cms->error();
    $block->{CACHEKEYS} = $keys->{$block->{CODE}} if exists $keys->{$block->{CODE}};
    
    if ($self->hasValidCacheContent($block)) {
        #В кэше найдены метаданные. Запросим соответствующий контент.
        my $content = $CACHE->getCacheContent([{REQUEST=>$abKeys->{REQUEST},CODE=>$block->{CODE}}]) or return $self->cms->error();
        if (defined $content->{$block->{CODE}}) {
            #Ура, контент получен
            $block->{CONTENT} = NG::BlockContent->output(
                    $content->{$block->{CODE}},
                    $block->{CACHEKEYS}->{HEADERS},
                    $block->{CACHEKEYS}->{HEADKEYS},
            );
            return $block->{CONTENT};
        };
warn "not found cache data: $block->{CODE} ".Dumper($block->{KEYS},$block->{CACHEKEYS});
    };
    #Контент или метаданые отсутствуют.
    delete $block->{CACHEKEYS};
    #Вызовет $block->getBlockContent() что выставит RELATED-значения для подчиненных блоков
    return $self->getBlockContent($block);
};

sub getABRelated {
    my $self = shift;
    
    my $aBlock = $self->{_ablock} or return $self->cms->error("getABRelated(): No ActiveBlock found!");
    my $abKeys = $self->_getBlockKeys($aBlock) or return $self->cms->error();
    
    unless ($abKeys->{HASRELATED}) {
        #Если включить кеширование, будет ой. Причем не сразу =)
        return $self->cms->error("Active Block does not set HASRELATED key. This can lead to floating errors on production site.");
    };
    return $aBlock->{CACHEKEYS}->{RELATED} if exists $aBlock->{CACHEKEYS} && $aBlock->{CACHEKEYS}->{RELATED};
    return $aBlock->{KEYS}->{RELATED} || return $self->cms->error("Active Block does not set value to RELATED key");
};

sub getETagSummary {
    my $self = shift;
    return "";
};

sub _getBlockObj {
    my $self = shift;
    my $block = shift;
    
    return $block->{MODULEOBJ} if $block->{MODULEOBJ};

    my $m = undef;
    $m = $block->{MODULEROW}->{module} if $block->{MODULEROW};
    
    my $cms = $self->cms();
    my $opts ={};
    $opts->{PAGEPARAMS} = $self->{_pObj}->{_pageRow};
    $opts->{PLUGINPARAMS} = $block->{PARAMS};
    if ($m) {
        $opts->{MODULEROW}= $block->{MODULEROW};
        $block->{MODULEOBJ} = $cms->getObject($m,$opts) or return $cms->error();
        return $block->{MODULEOBJ};
    };
    if ($block->{MODULECODE}) {
        $block->{MODULEOBJ} = $cms->getModuleByCode($block->{MODULECODE},$opts) or return $cms->error();
        return $block->{MODULEOBJ};
    };
    die "_getBlockObj(): No MODULECODE or MODULEROW.module";
};

sub _getBlockKeys {
    my $self = shift;
    my $block = shift;
    
    return $block->{KEYS} if exists $block->{KEYS};
    my $cms = $self->cms();
    my $bObj = $self->_getBlockObj($block) or return $cms->error();
    
    my $keys = undef;
    $keys = $bObj->getBlockKeys($block->{ACTION},$block->{PARAMS}) if ($bObj->can("getBlockKeys"));
#NG::Profiler::saveTimestamp("getBlockKeys_".ref($block->{MODULEOBJ})."_".$block->{ACTION},"getBKeys");
    if (defined $keys) {
        return $cms->defError("getBlockKeys() блока ".$block->{CODE}." action ".$block->{ACTION}," не вернул значения") unless $keys;
        return $cms->error("getBlockKeys() блока ".$block->{CODE}." action ".$block->{ACTION}." вернул не хэш") unless ref $keys eq "HASH";
    };
    $keys||={};
    $block->{KEYS} = $keys;
    return $block->{KEYS};
};

sub getBlockContent {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();

    return $block->{CONTENT} if exists $block->{CONTENT};
    
    my $bObj = $self->_getBlockObj($block) or return $cms->error();
    return $cms->error("Модуль ".(ref $bObj)." не содержит метода getBlockContent") unless $bObj->can("getBlockContent");
    
    my $keys = $self->_getBlockKeys($block) or return $cms->error();
    
    my $c = $bObj->getBlockContent($block->{ACTION}, $keys, $block->{PARAMS});
#NG::Profiler::saveTimestamp("getBlockContent_".ref($block->{MODULEOBJ})."_".$block->{ACTION},"getBContent");
    
    if (!defined $c || ($c && ref $c ne "NG::BlockContent")) {
        return $cms->error("getBlockContent() блока ".$block->{CODE}." вернул некорректный возврат ");
    };
    $block->{CONTENT} = $c;
    return $c;
};

sub getBlockContentText {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();
    my $code = $block->{CODE};
    
    my $c = $self->getBlockContent($block);
    if (!defined $c || ($c && ref $c ne "NG::BlockContent")) {
        warn "Incorrect response for getBlockContent() block $code";
        return "[BLOCK $code RETURNS INVALID RESPONSE]";
    };
    if ($c eq 0 || $c->is_error()) {
		my $e = "";
        $e = $self->cms->getError() if $c eq 0;
        $e = $c->getError() if $c;
        warn "Block $code has error $e";
        return "[ERROR PROCESSING BLOCK $code]";
    };
    if (!$c->is_output()) {
        warn "Block $code return unsupported response";
        return "[BLOCK $code UNSUPPORTED RESPONSE]";
    };
    return $c->getOutput();
};

sub requestCacheKeys {
    my $self = shift;
    my $cms = $self->cms();
#NG::Profiler::saveTimestamp("start","requestCacheKeys");
    
    my @allBlocks = ();
    foreach my $block (@{$self->{_blocks}}) {
        my $keys = $self->_getBlockKeys($block) or return $cms->error();
        
        next unless exists $keys->{REQUEST};
        next if exists $block->{CACHEKEYS}; #AB with RELATED
        
        my $a = {};
        $a->{REQUEST} = $keys->{REQUEST};
        $a->{CODE} = $block->{CODE};
        
        push @allBlocks, $a;
    };
    
#NG::Profiler::saveTimestamp("look cache","requestCacheKeys");
    my $keys = $CACHE->getCacheContentKeys(\@allBlocks) or return $cms->error();
    foreach my $code (keys %$keys) {
        my $block = $self->{_hblocks}->{$code} or return $cms->error("No block found for block $code in getCacheContentKeys() response");
        $block->{CACHEKEYS} = $keys->{$code};
    };
#NG::Profiler::saveTimestamp("done","requestCacheKeys");
    return 1;
};

sub hasValidCacheContent {
    my $self = shift;
    my $block = shift;

    my $cms = $self->cms();
    my $keys = $self->_getBlockKeys($block) or return $cms->error();
    my $ckeys = $block->{CACHEKEYS};
    
    return 0 unless exists $keys->{REQUEST};
    return 0 unless $ckeys && ref $ckeys;
    return 0 if (exists $keys->{LM} && (!exists $ckeys->{LM} || $keys->{LM} > $ckeys->{LM}));
    return 0 if (exists $keys->{ETAG} && (!exists $ckeys->{ETAG} || $keys->{ETAG} ne $ckeys->{ETAG}));
    return 1;
};

sub prepareContent {
    my $self = shift;
    my $cms = $self->cms();
#NG::Profiler::saveTimestamp("start","prepareContent");
    
    my @cachedBlocks = ();
    foreach my $block (@{$self->{_blocks}}) {
        next if $block->{CONTENT};
        if ($self->hasValidCacheContent($block)) {
            my $a = {};
            $a->{REQUEST} = $block->{KEYS}->{REQUEST};
            $a->{CODE} = $block->{CODE};
            push @cachedBlocks, $a;
            next;
        };
        delete $block->{CACHEKEYS};
    };
#NG::Profiler::saveTimestamp("checkMetadata","prepareContent");
    
    #Active block. Find it first.
    if ($self->{_ablock} && !$self->{_ablock}->{CONTENT} && !$self->{_ablock}->{CACHEKEYS}) {
        my $c = $self->getBlockContent($self->{_ablock});
        return $c if ($c eq 0 || !$c->is_output());
#NG::Profiler::saveTimestamp("getABContent","prepareContent");
    };

    my $content = $CACHE->getCacheContent(\@cachedBlocks) or return $cms->error();
    foreach my $code (keys %$content) {
        my $block = $self->{_hblocks}->{$code};
        unless (defined $content->{$code}) {
warn "not found cache data: $code ".Dumper($block->{KEYS},$block->{CACHEKEYS});
            delete $block->{CACHEKEYS};
            next;
        };
        $block->{CONTENT} = NG::BlockContent->output(
                $content->{$code},
                $block->{CACHEKEYS}->{HEADERS},
                $block->{CACHEKEYS}->{HEADKEYS},
        );
    };
#NG::Profiler::saveTimestamp("getCachedContent","prepareContent");

    my @newContent = ();
    foreach my $block (@{$self->{_blocks}}) {
        my $blockCode = $block->{CODE};
        my $c = $self->getBlockContent($block);
        
        return $c if $c eq 0 || $c->is_error();
        return $cms->error("Block $blockCode return unsupported response type ".$c->{_type}) unless $c->is_output();
        
        #Упс, куки ?
        my $cc = $c->cookies();
        next if $cc && scalar @{$cc}; #Skip cookies cacheing.
        
        next unless $block->{KEYS}->{REQUEST};      #Could be cached
        next if $block->{CACHEKEYS};                #Next if already cached
        
        #Сохраняем в кэш
        my $new = {};
        #Код блока (идентификатор, часть ключа, значение в кэш не сохраняется)
        $new->{CODE} = $block->{CODE};
        
        #Параметры контента блока (идентификатор, часть ключа, значение в кэш не сохраняется)
        $new->{REQUEST} = $block->{KEYS}->{REQUEST};
        
        #Сохраняемые заголовки контента блока
        my $h = $c->headers();
        $new->{KEYS}->{HEADERS} = $h if $h;
        my $hk = $c->headkeys();
        $new->{KEYS}->{HEADKEYS} = $hk if $hk;
        
        #Сохраняемые параметры для подчиненных блоков
        $new->{KEYS}->{RELATED} = $block->{KEYS}->{RELATED} if exists $block->{KEYS}->{RELATED};
        $new->{KEYS}->{ETAG}    = $block->{KEYS}->{ETAG} if exists $block->{KEYS}->{ETAG};
        $new->{KEYS}->{LM}      = $block->{KEYS}->{LM}   if exists $block->{KEYS}->{LM};
        
        #Параметр максимального времени жизни кэшируемых данных
        my $ma = $block->{KEYS}->{MAXAGE} || $MAX_CACHE_TIME;
        $ma = $MAX_CACHE_TIME if $ma > $MAX_CACHE_TIME;
        $new->{MAXAGE} = $ma;   ### DIRTY HACK!!!
        
        #Сохраняемый контент блока
        $new->{DATA} = $c->getOutput();
        push @newContent, $new;
    };
#NG::Profiler::saveTimestamp("getBlockContent","prepareContent");
    $CACHE->storeCacheContent(\@newContent) or return $cms->error();
#NG::Profiler::saveTimestamp("storeCacheContent","prepareContent");
    return 1;
};

=comment runPlugins
        $block->{active} = 1 unless exists $block->{active};
        if ($block->{disabled} || !$block->{active}) {
            if ($block->{type}) {
                $self->{_pluginsContent}->{$block->{code}} = "";
            }
            else {
                $self->{_modulesContent}->{$block->{code}} = "";
            };
            next;
        };
=cut

sub attachTemplate {
    my $self = shift;
    my $tmplObj = shift or die "attachTemplate(): no TMPLOBJ";
    
    # инициализируем связывающие переменные
    my $modules = {};
    bless $modules, "NG::BlocksController::Block";
    $modules->{_ctrl} = $self;
    $modules->{_isPlugin} = 0;
    
    my $plugins = {};
    bless $plugins, "NG::BlocksController::Block";
    $plugins->{_ctrl} = $self;
    $plugins->{_isPlugin} = 1;
    
    $tmplObj->param(
        PLUGINS => $plugins,
        MODULES => $modules,
    );
    return 1;
};

sub _getTmplBlockContent {
    my $self = shift;
    my $blockCode = shift;
    my $isPlugin = shift || 0;
   
    my $block = $self->{_hblocks}->{$blockCode};
    
    unless ($block) {
        my $e = $self->_regTmplBlock($blockCode,$isPlugin);
        return $e if $e;
        $block = $self->{_hblocks}->{$blockCode};
    };
    
    warn "Block $blockCode is not loaded from a template" if ($block->{SOURCE} ne "tmpl");
    warn "Block $blockCode requested from PLUGINS but it is MODULE" if $isPlugin &&  $block->{TYPE}!=1;
    warn "Block $blockCode requested from MODULES but it is PLUGIN" if !$isPlugin && $block->{TYPE}!=0;
    
    $self->{_usedBCodes}->{$blockCode} = 1;
    
    return $self->getBlockContentText($block);
};

sub splitRegions {
    my $self = shift;
    my $cms = $self->cms();
    my $regions = $self->{_regions} = {};
    
    foreach my $block (@{$self->{_blocks}}) {
        my $r = $block->{REGION};
        my $w = $block->{WEIGHT};
        
        if ($block->{SOURCE} eq "push") {
            $r ||= "CONTENT";
            $w ||= "0";
        }
        elsif ($block->{SOURCE} eq "neigh") {
            $r ||= "CONTENT";
        }
        elsif ($block->{SOURCE} eq "tmpl") {
            $r or next;
        }
        else {
            return $cms->error("Invalid block SOURCE");
        };
        
        return $cms->error("Block ".$block->{CODE}." has no REGION") unless $r;
        return $cms->error("Block ".$block->{CODE}." has no WEIGHT") if !defined $w || $w eq "";
        
        $regions->{$r} ||= [];
        push @{$regions->{$r}}, {
            BLOCK  => $block,
            WEIGHT => $w,
        };
    };
    1;
};

sub getRegionsContent {
    my $self = shift;
    
    my $rContent = {};
	foreach my $r (keys %{$self->{_regions}}) {
		my $c = "";
        foreach my $a (sort { $a->{WEIGHT} <=> $b->{WEIGHT}; } @{$self->{_regions}->{$r}}) {
            $c.= $self->getBlockContentText($a->{BLOCK});
        };
		$rContent->{$r} = $c;
	};
    #TODO: Сделать регионы объектами (связанными хешами), контролировать использование регионов в шаблоне. Tie::Hash, Tie::StdHash
    warn "Region HEAD will be overwritten" if exists $rContent->{HEAD};
    my $rHead = NG::BlocksController::RegionHead->create($self);
    $rHead->processBlocks() or return 0;
    $rContent->{HEAD} = $rHead;
    
    return $rContent;
};

sub _regTmplBlock {
    my $self = shift; 
    my $bCode = shift;
    my $isPlugin = shift;
     
    my $cms = $self->cms;
    my $dbh = $cms->dbh();
     
    my $block = $cms->getBlock($bCode);
    return "[".$cms->getError()."]" if defined $block && $block eq "0";
     
    if ($block) { 
        #Do nothing
    } 
    elsif ($isPlugin) {
        warn "Plugin $bCode not found for template '".$self->{_tmplFile}."'";
        return "[Плагин $bCode не найден]";
    } 
    else { 
        #unless ($block || $isPlugin) 
        unless ($bCode =~ /^([^_]+)_(.*)$/) {
            warn "Block $bCode name is not valid for MODULES in template '".$self->{_tmplFile}."'";
            return "[Некорректное имя ключа для переменной MODULES: $bCode]";
        }; 
        my $code = $1;    # Код модуля
        my $action = $2;
        
        #Готового блока не нашли, пытаемся создать 
        my $moduleRow = $cms->getModuleRow("code=?",$code);
        unless ($moduleRow) {
            warn "Module $code not found while registering block $bCode";
            return $cms->getError("[Модуль $code не найден для блока $bCode]");
        };
        my $blockId = $cms->db()->get_id("ng_blocks");
        warn "Registering block record for block $bCode in template '".$self->{_tmplFile}."'";
        $dbh->do("insert into ng_blocks (id, name,code, module_id, action, type) values (?,?,?,?,?,?)", undef, $blockId, 'Auto', $bCode, $moduleRow->{id}, $action, 0) or return "[Ошибка создания блока $bCode: ".$DBI::errstr."]";
        
        $block = $cms->getBlock($bCode);
        return "[".$cms->getError()."]" if defined $block && $block eq "0";
    }; 
     
    return "[Блок $bCode не является плагином]" if $isPlugin  && $block->{TYPE} != 1;
    return "[Блок $bCode не является модулем]"  if !$isPlugin && $block->{TYPE} != 0;
     
    warn "Block $bCode found, registering it into template '$self->{_tmplFile}'";
    $dbh->do("insert into ng_tmpl_blocks (template, block_id) values (?,?)", undef, $self->{_tmplFile}, $block->{ID}) or return $DBI::errstr;
     
    $block->{SOURCE}="tmpl";
    $self->_pushBlock($block) or return "[".$cms->getError()."]";
    return "";
}; 

sub DESTROY {
    my $self = shift;
    my $dbh = $self->dbh();

    #TODO: Обработать ситуацию, когда в вызове незарегистрированного блока происходит die.
    #      Тогда часть блоков может быть не вызвана из шаблона, и она будет считаться неиспользуемой.
    #      Нужно выставлять флажок _inside если вызывается запрос контента незарегистированного блока
    #      и проверять его в этой процедуре.
    unless (scalar keys %{$self->{_usedBCodes}}) {
print STDERR " NG::PlugCtrl - no one module used. Possible tmpl->output() not called. Skipping remove.... ";
        return 1;
    };
    
    #Высчитываем неиспользуемые блоки и разрегистрируем их из шаблона
    foreach my $block (@{$self->{_blocks}}) {
        next if $self->{_usedBCodes}->{$block->{CODE}};
        
        next if $block->{SOURCE} ne "tmpl";
        next if $block->{REGION};
        next if $block->{fixed};
        next if $block->{disabled};
        
        print STDERR "Block ".$block->{CODE}." is not used in template '".$self->{_tmplFile}."' and must be unregistered.";
        #$dbh->do("delete from ng_tmpl_blocks where template=? and  block_id=?", undef, $self->{_tmplFile}, $blockId) or warn "Error unregistering block:".$DBI::errstr;
    };
    return 1;
};


package NG::BlocksController::Block;
use strict;
our $AUTOLOAD;

sub DESTROY {
#print STDERR " NG::PlugCtrl::BLOCK DESTROYED";
    return "Запрещенное имя блока";
};

sub AUTOLOAD {
    my $self=shift;
    my $pkg = ref $self;
    $AUTOLOAD =~ s/$pkg\:\://;
#print STDERR " AUTOLOAD BLOCK ".$AUTOLOAD;
    local $NG::Application::blocksController = $self->{_ctrl};
    return $self->{_ctrl}->_getTmplBlockContent($AUTOLOAD, $self->{_isPlugin});
};

package NG::BlocksController::RegionHead;
use strict;

sub create {
    my $class = shift;
    
    my $self = {};
    bless $self, $class;
    $self->init(@_);
    $self;
};

sub init {
    my $self = shift;
    
    $self->{_bctrl} = shift;
    $self->{_title} = undef;
    $self->{_link}  = [];
    $self->{_script}= [];
    $self->{_meta}  = [];
    
    $self->{_descr} = undef;
    $self->{_keywords} = undef;
    
    $self;
};

sub processBlocks {
    my $self = shift;
    my $bctrl = $self->{_bctrl};
    
#- ключи, выданные блоками шаблона
#- ключи, выданные активным блоком
#- ключи, выданные блоками соседями активного блока.
    
    foreach my $block (@{$bctrl->{_blocks}}) {
        next unless $block->{SOURCE} eq "tmpl";
        $self->processBlock($block) or return 0;
    };

    foreach my $block (@{$bctrl->{_blocks}}) {
        next unless $block->{SOURCE} eq "push";
        $self->processBlock($block) or return 0;
        last; #Only single block can be AB
    };
    
    foreach my $block (@{$bctrl->{_blocks}}) {
        next unless $block->{SOURCE} eq "neigh";
        $self->processBlock($block) or return 0;
    };
    
    my $pObj = $self->{_bctrl}->{_pObj};
    my $pRow = undef;
    $pRow = $pObj->getPageRow() if $pObj;

    if ($pRow) {
        $self->{_title} ||= $pRow->{title};
        if ($pRow->{description}) {
            $self->_pushMeta({name=>"description",content=>$pRow->{description}}) or return 0;
        };
        if ($pRow->{keywords}) {
            $self->_pushMeta({name=>"keywords",content=>$pRow->{keywords}}) or return 0;
        };
    };
    1;
};

sub _pushMeta {
    my $self = shift;
    my $meta = shift;
    
    my $cms = $self->cms();
    
    return $cms->error("Invalid hash in element of array meta: 'name' or 'http-equiv' key is missing") unless exists $meta->{name} or exists $meta->{'http-equiv'};
    return $cms->error("Invalid hash in element of array meta: key 'content' is missing") unless exists $meta->{content};
    
    if (!defined $meta->{name}) {
        #
    }
    elsif ($meta->{name} eq "keywords") {
        if ($self->{_keywords}) {
            $self->{_keywords}->{content} .= $meta->{content};
            return 1;
        }
        else {
            $self->{_keywords} = $meta;
        };
    }
    elsif ($meta->{name} eq "description") {
        if ($self->{_descr}) {
            $self->{_descr}->{content} .= $meta->{content};
            return 1;
        }
        else {
            $self->{_descr} = $meta;
        };
    };
    push @{$self->{_meta}}, $meta;
    return 1;
};

sub processBlock {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();
    
    my $c = $self->{_bctrl}->getBlockContent($block);
    my $hk = $c->headkeys() or return 1;
    if (exists $hk->{title}) {
        #warn "We already have title" if defined $self->{_title}; #TODO: discuss - need this??
        return $cms->error("Invalid value for key title in headkeys()") if (ref $hk->{title});
        $self->{_title} = $hk->{title};
    };
    if (exists $hk->{link}) {
        return $cms->error("Invalid value for key link in headkeys()") if ref $hk->{link} ne "ARRAY";
        push @{$self->{_link}}, @{$hk->{link}};
        #foreach my $l (@{$hk->{link}}) {
        #    push @{$self->{_link}}, $l;
        #};
    };
    if (exists $hk->{script}) {
        return $cms->error("Invalid value for key link in headkeys()") if ref $hk->{script} ne "ARRAY";
        foreach my $s (@{$hk->{script}}) {
            return $cms->error("Invalid hash in element of array 'script': key 'src' or 'type' is missing") unless exists $s->{type} && exists $s->{src};
            push @{$self->{_script}}, $s;
        };
    };
    if (exists $hk->{meta}) {
        my $v = $hk->{meta};
        if (ref $v eq "HASH") {
            foreach my $key (keys %$v) {
                if ($key =~ /^-/) {
                    my $keys=$key;
                    $keys=~s/^-//;
                    $self->_pushMeta({"http-equiv"=>$keys,content=>$v->{$key}}) or return $cms->error();
                }
                else {
                    $self->_pushMeta({name=>$key,content=>$v->{$key}}) or return $cms->error();
                };
            };
        }
        elsif (ref $v eq "ARRAY") {
            foreach my $m (@$v) {
                $self->_pushMeta($m) or return $cms->error();
            };
        }
        else {
            return $cms->error("Invalid value for key meta in headkeys()");
        };
    };
    if (exists $hk->{csslist}) {
        my $v = $hk->{csslist};
        if (ref $v eq "ARRAY") {
            foreach my $css (@$v) {
                return $cms->error("Invalid value for element of array csslist") if ref $css;
                push @{$self->{_link}}, {rel=>"stylesheet",type=>"text/css",href=>$css};
            };
        }
        elsif (ref $v) {
            return $cms->error("Invalid value for csslist");
        }
        else {
            push @{$self->{_link}}, {rel=>"stylesheet",type=>"text/css",href=>$v};
        };
    };
    if (exists $hk->{jslist}) {
        my $v = $hk->{jslist};
        if (ref $v eq "ARRAY") {
            foreach my $js (@$v) {
                return $cms->error("Invalid value for element of array jslist") if ref $js;
                push @{$self->{_script}}, {type=>"text/javascript",src=>$js};
            };
        }
        elsif (ref $v) {
            return $cms->error("Invalid value for jslist");
        }
        else {
            push @{$self->{_script}}, {type=>"text/javascript",src=>$v};
        };
    };
    1;
};

sub HTML {
    my $self = shift;
    my $html = "";
    #$html.= "<title>".$self->{_title}."</title>\n" if defined $self->{_title};
    $html.= $self->LINK_HTML();
    $html.= $self->SCRIPT_HTML();
    $html.= $self->META_HTML();
    return $html;
};

sub TITLE {
    my $self = shift;
    return $self->{_title} if (defined $self->{_title});
    return "";
};

sub LINK_HTML {
    my $self = shift;
    my $html = "";
    foreach my $s (@{$self->{_link}}) {
        $html.="<link";
        foreach my $key (qw/type rel href media title/) {
            next unless exists $s->{$key};
            $html.=" ".$key."=\"".$s->{$key}."\"";
        };
        $html.="></link>";
    };
    return $html;
};

sub SCRIPT_HTML {
    my $self = shift;
    my $html = "";
    foreach my $s (@{$self->{_script}}) {
        $html.="<script";
        foreach my $key (qw/src language type charset/) {
            next unless exists $s->{$key};
            $html.=" ".$key."=\"".$s->{$key}."\"";
        };
        $html.="></script>";
    };
    return $html;
};

sub META_HTML {
    my $self = shift;
    my $html = "";
    foreach my $s (@{$self->{_meta}}) {
        $html.="<meta";
        foreach my $key (qw/name content scheme http-equiv lang dir/) {
            next unless exists $s->{$key};
            $html.=" ".$key."=\"".$s->{$key}."\"";
        };
        $html.="/>\n";
    };
    return $html;
};

sub LINK {
    my $self = shift;
    return $self->{_link};
};

sub SCRIPT {
    my $self = shift;
    return $self->{_script};
};

sub META {
    my $self = shift;
    return $self->{_meta};
};

return 1;
