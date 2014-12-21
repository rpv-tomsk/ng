package NG::Block;
use strict;

#use constant M_ERROR    => 0;
use constant M_OK 		=> 1;
#use constant M_REDIRECT => 2;
#use constant M_OTHERMOD => 3;
#use constant M_FULLREDIRECT => 4;
#use constant M_EXIT => 5;

$NG::Block::VERSION = 0.5;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);    
    $self->config();
    return $self; 
}

sub init {
	my $self = shift;
    
    my $opts = shift || {};
    
    #$self->{_pageRow} = $opts->{PAGEROW};
    $self->{_baseURL} = delete $opts->{ADMINBASEURL};
use Carp;
    $self->{_moduleObj} = delete $opts->{MODULEOBJ} or croak("Block " .ref($self). " constructor has no MODULEOBJ option value");
    #$self->{_blockId} = $opts->{BLOCKID};
    #$self->{_moduleId} = $opts->{MODULEID};
    #$self->{_pageObj} = $opts->{PAGEOBJ};       # Свойство для хранения объекта страницы в объектах блоков страницы
    
	$self->{_opts} = $opts;
	
    $self->{_handlers} = {};
    $self->{_template} = undef;
};

sub config {};      #Virtual method

#TODO: эти два метода должны устареть, вместе с ними форма должна переучиться работать с данными из CMS
sub getDocRoot() { return $NG::Application::cms->getDocRoot(); };
sub getSiteRoot() { return $NG::Application::cms->getSiteRoot(); };


sub getModuleObj { my $self = shift; return $self->{_moduleObj}; };

sub _makeLogEvent {
    my $self = shift;
    
    $self->cms->_makeLogEvent($self->{_moduleObj},@_);
};

sub opentemplate {
    my $self = shift;
    my $filename = shift;
    my $cms = $self->cms();
	$self->{_template} = $cms->gettemplate($filename) || return $cms->error();
};

sub template { return $_[0]->{_template}; };
*tmpl = \&template; 

sub run_actions {
    my $self = shift;
    my $action = $self->q()->url_param('action')||$self->q()->param('action')||"";
    $action = lc($action);
    #TODO: need escape $action in error messages, or XSS vulnerable
    return $self->error("Incorrect action: $action") unless exists $self->{_handlers}->{$action}; 
    my $handler = $self->{_handlers}->{$action};
    my $function = $handler->{function} || return $self->error("No function specified for action '$action'");
    return $self->error("Module ".ref($self). " has no method ".$function) unless $self->can($function);
    return $self->$function($action,@_);
};

sub clear_actions {
	$_[0]->{_handlers}={};
}

sub register_action {
    $_[0]->{_handlers}->{$_[1]} = { function=>$_[2], is_ajax=>0 };
};

sub register_ajaxaction {
    $_[0]->{_handlers}->{$_[1]} = { function=>$_[2], is_ajax=>1 };
};

=head setModuleId getModuleId setBlockId getBlockId
# Свойства текущего модуля: код модуля, код обр. блока, код шаблона обр. блока
sub setModuleId { my $self=shift;  $self->{_moduleId} = shift; };
sub getModuleId { my $self=shift;  return $self->{_moduleId}; };
sub getBlockId  { my $self=shift;  return $self->{_blockId} or die "getBlockId(): module has no BLOCKID initialised"; };
sub setBlockId  { my $self=shift;  $self->{_blockId} = shift; };
=cut


=head setPageRow - используется в индексаторе
sub setPageRow  { my $self=shift;  $self->{_pageRow} = shift; };
=cut

# Использующие pageRow методы сдублированы в NG::Module
sub getPageRow  {
    my $self=shift;
	return $self->{_moduleObj}->getPageRow();
};

#Свойства более глобальные, свойства обрабатываемой верхушкой страницы
sub getPageId       { my $self=shift; my $pRow=$self->getPageRow(); return (ref $pRow eq "HASH"?(exists $pRow->{'id'}?$pRow->{'id'}:undef):undef);  };
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

sub getBaseURL {
    my $self=shift;
warn("NG::Block::getBaseURL(): missing _baseURL value.") unless $self->{_baseURL};
    return $self->{_baseURL} || "";
};
sub setBaseURL { my $self = shift; $self->{_baseURL}  = shift; }

sub getSubURL {
    my $self = shift;
 
    my $q   = $self->q();
    my $url = $q->url(-absolute=>1);
    my $baseUrl = $self->getBaseURL();
    my $subUrl = ($url =~ /^$baseUrl(.+)/ ) ? $1 : "";
    return $subUrl;
}

sub opts {
    my $self = shift;
	if (scalar(@_) == 1) {
		my $v = shift;
		return $self->{_opts}->{$v};
	};
    return $self->{_opts};
};

## Методы проверки привилегий

sub hasModulePrivilege {
	my $self = shift;
	my $privilege = shift || return 0;
	return $self->cms()->hasModulePrivilege(PRIVILEGE => $privilege, MODULE_ID=>$self->getModuleObj()->moduleParam('id'));
};

sub hasLinkBlockPrivilege {
    my $self=shift;
    my $privilege=shift || return 0;
    
    $self->setError("");
    return $self->error("hasLinkBlockPrivilege(): Данный модуль не является модулем линкованного блока") unless $self->canEditLinkBlock();
    
    my $langId = 0;
    $langId = $self->getPageLangId() if $self->isLangLinked();
    
    return $self->app()->hasLinkBlockPrivilege(
        LINK_ID   => $self->getPageLinkId(),
        LANG_ID   => $langId,
        BLOCK_ID  => $self->getBlockId(),
        PRIVILEGE => $privilege,
        SUBSITE_ID => $self->getSubsiteId(),
    );
};

sub hasPageBlockPrivilege {
    my $self=shift;
    
    my $privilege=shift || return 0;

    $self->setError("");
    return $self->error("hasPageBlockPrivilege(): Данный модуль не является модулем блока страницы") unless $self->canEditPageBlock();
    
    return $self->app()->hasPageBlockPrivilege(
        PAGE_ID   => $self->getPageId(),
        BLOCK_ID  => $self->getBlockId(),
        PRIVILEGE => $privilege,
        SUBSITE_ID => $self->getSubsiteId(),
    );
};

=head hasSubsitePrivilege
sub hasSubsitePrivilege {
    my $self = shift;
    my $privilege = shift || return 0;
    
    return $self->app()->hasSubsitePrivilege(
        SUBSITE_ID  => $self->getSubsiteId(),
        PRIVILEGE   => $privilege,
    );
}
=cut

sub blockPrivileges {
	return undef;
};

sub hasPriv {
	my $self = shift;
	my $p = shift;
#print STDERR "hasPriv(deleteDayPhoto): $p";
    my $m = $self->{_moduleObj};
	if ($self->canEditPageBlock()) {
		return $m->hasPageModulePrivilege($p);
	}
	elsif ($self->canEditLinkBlock()){
		return $m->hasPageModulePrivilege($p);
	}
	#elsif ($self->getModuleId()) {
    else {
		return $m->hasModulePrivilege($p);
	#}
	#else {
	#	die "Hmmm... Privileges on templates is not supported ))))";
	};
};

##
##
##

sub canEditPageBlock {
    my $self = shift;
    return 0;
};

sub canEditLinkBlock {
    my $self = shift;
    return 0;
};

sub canEditTemplateBlock {
    my $self = shift;
    my $tmplId = shift;
    my $blockId = shift;
    return 0;
};

sub isLangLinked {
    my $self = shift;
    return 0;	
};

sub readonly { return 0; };

sub pageBlockAction {  
    my $self = shift;
    my $is_ajax = shift;
    return $self->error("Обработчик pageBlockAction() модуля ".ref($self)." не перекрыт. Скорее всего ошибка в модуле и блок не редактируем.");
};

sub initPageBlock {
    my $self = shift;
    return $self->error("Модуль ".ref($self)." не содержит метода initPageBlock()");
};

sub initLinkBlock {
    my $self = shift;
    return $self->error("Модуль ".ref($self)." не содержит метода initLinkBlock()");
};

sub getContentKey {
    my $self = shift;
    return $self->error("Модуль ".ref($self)." не содержит метода getContentKey()");
}

### функции, относящиеся к реализации поиска по содержимому модуля/блока

sub getBlockIndex {
    my $self = shift;
    my $suffix = shift;
    # Возвращаем {} указатель на пустой хэш если не нужен индекс.
    return $self->error("В модуле ".ref($self)." отсутствует функция getBlockIndex(). Модуль не поддерживает индексирование в режиме блока страницы.")
};

sub getIndexSuffixFromFormAndMask {
    my $self = shift;
    my $form = shift;
    my $mask = shift||"";
    
    my $suffix = $mask; 
    
    while ($suffix =~ /\{(.+?)\}/ ) {
        my $param = $form->getParam($1) or return $self->showError("getIndexSuffixFromFormAndMask(): Ошибка вызова \$form->getParam()");
        $suffix =~ s/\{(.+?)\}/$param/;
    };
    return $suffix;
};

sub isMaskMatchSuffix {
	my $self = shift;
	my $mask = shift;
	my $suffix = shift;
    return 1 unless ($mask || $suffix);
	$mask =~ s/\{.+?\}/\(\\S\+\?\)/gi;
	$suffix =~ /$mask/?return 1: return 0;
};

sub getKeyValuesFromSuffixAndMask {
    my $self = shift;
    my $suffix = shift || "";
    my $mask = shift;
    
    die "Suffix '$suffix' not match mask '$mask'." unless $self->isMaskMatchSuffix($mask,$suffix);
    
    my @parts = split /[\{\}]/,$mask;
    my $keyValues = {};
    for (my $i=0;$i<scalar @parts;$i=$i+2) {
        if ($i==scalar @parts - 1) {
            last;
        } elsif ($i==scalar @parts - 2) {
            $suffix =~ s/$parts[$i](.+?)$//;
            $keyValues->{$parts[$i+1]} = $1;
        } else {
            $suffix =~ s/$parts[$i](.+?)$parts[$i+2]/$parts[$i+2]/;
            $keyValues->{$parts[$i+1]} = $1;
        };
    };
    return $keyValues;
};

###  Функции, относящиеся к инициализированности блока/модуля страницы

=comment
sub needInitLater {
    my $self = shift;
    my $pageId = $self->getPageId();
    my $blockId = $self->getBlockId();
    return NG::Block::M_REDIRECT;
};
=cut

sub redirectToNextNIBlock {
    my $self = shift;
    #TODO: эта часть не вполне работоспособна.
    #TODO: fullredirect требует is_ajax
    my $pageId = $self->getPageId();
    return $self->fullredirect("/admin-side/pages/$pageId/");    

    #my $nextBlockId = $self->db()->dbh()->selectrow_array("select block_id from ng_niblocks where page_id = ?",undef,$pageId);
    #return $self->fullredirect("/admin-side/pages/$pageId/block$nextBlockId/") if $nextBlockId;
    #return $self->fullredirect("/admin-side/pages/$pageId/struct/?greeting=activate");
};

sub initialised {
    my $self=shift;
    return 0;
};

sub destroyPageBlock {
    my $self = shift;
    return $self->error("Модуль ".ref($self)." не содержит метода destroyPageBlock()");
};

sub destroyLinkBlock {
    my $self = shift;
    return $self->error("Модуль ".ref($self)." не содержит метода destroyLinkBlock()");
};

sub blockAction {
    my $self = shift;
    my $is_ajax = shift;
    return $self->error("Обработчик blockAction() модуля ".ref($self)." не перекрыт. Скорее всего ошибка в модуле");
};

### Return action status functions

sub output {
	my $self = shift;
    my $content = shift;
	return $self->cms()->output($content);
}   	

sub outputJSON {
    my ($self,$data) = (shift,shift);
    return $self->cms()->outputJSON($data);
}

sub redirect {
	my $self = shift;
	my $redirectUrl = shift;
	my $cms = $self->cms();	
	return $cms->redirect($redirectUrl);
};


sub fullredirect {
	my $self = shift;
	my $url = shift;
    my $is_ajax = shift; #TODO: это маленько не вписывается в концепцию

	my $cms = $self->cms();	
	if ($is_ajax == 1) {
		return $cms->exit("<script type='text/javascript'>parent.document.location='".$url."';</script>",-nocache=>1);
	} else {
		return $cms->redirect($url);
	};
};

sub error {
	my $self = shift;
	my $error = shift;
	return $self->cms()->error($error);
};

sub showError {
    my $self = shift;
    my $defErrText = shift;
	my $e = $self->cms()->getError($defErrText);
	return $self->cms()->error($e);
};

return 1;
END{};
