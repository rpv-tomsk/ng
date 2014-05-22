package NG::PageModule;

use strict;
use NG::Module 0.5;
use NG::Application;

$NG::PageModule::VERSION=0.5;

use vars qw(@ISA);
@ISA = qw(NG::Module);

sub init {
	my $self = shift;
	
    my $opts = shift || {};
    
	$self->SUPER::init($opts,@_);
    
=comment
	$self->{_editableBlocks} = undef;  # �������.
	$self->{_editableBlocks} = undef;  # ������������� ����� ��������
=cut
	$self->{_selectedModule} = undef;  # ������ ��������, ������� ������ �������� �� ������ �������
	$self->{_modules} = undef;          # ��� ������ ��������
	$self;
};

##
##   ��������� �������� � �����
##

sub run {
	my $pageObj = shift;
    
    $NG::Application::pageObj = $pageObj;
	
	my $cms = $pageObj->cms();
    my $q = $pageObj->q();

    my $ret = undef;
    if ($q->request_method() eq "POST") {
        return $cms->error("������ ".(ref $pageObj)." �� �������� ������ processPost") unless $pageObj->can("processPost");
        $ret = $pageObj->processPost();
        return $ret if $ret != NG::Application::M_OK;
    };

    return $cms->error("������ ".(ref $pageObj)." �� �������� ������ showPage") unless $pageObj->can("showPage");
    return $pageObj->showPage();
};

sub processPost {
    my $self = shift;
    
    my $cms = $self->cms();
    my $q = $cms->q();
    my $dbh = $cms->db()->dbh();
    
    my $ctrl = $q->param("_controller") || "";
    
    my $mObj = undef;
    if (!$ctrl) {
        return $cms->error("������������ ������ �� �������� �������� ��������� _controller") if $self->_isBaseClass();
        $mObj = $self;
    }
    else {
        $ctrl = uc($ctrl);
        $mObj = $cms->getModuleByCode($ctrl) or return $cms->defError("processPost():","����������� ���������� $ctrl �� ������");
    };
    
    return $cms->error("������ ".(ref $mObj)." �� �������� ������ processModulePost") unless $mObj->can("processModulePost");
    #return $cms->error("������ ".$row->{module}." �� �������� ������ processModulePost") if $self->can("processModulePost") eq $mObj->can("processModulePost");
    return $mObj->processModulePost();
};

sub showPage {
	my $pageObj = shift;
	my $cms = $pageObj->cms();
	return $cms->buildPage($pageObj);
}

sub getLayout {
    my $pageObj = shift;
    my $aBlock  = shift; #Active Block. #TODO: �������� ������ ���� �����, ������������ �� $pageObj->getActiveBlock();

    my $cms = $pageObj->cms();

    #��������� ������ LAYOUT ��� ������ ��������
    my $layoutConf = "LAYOUT";
    $layoutConf = "PRINTLAYOUT" if $cms->isPrint();
    
    my $langId = $pageObj->getPageLangId();
    my $subsiteId = $pageObj->getSubsiteId();
	
    my $layout = undef;
    if ($aBlock) {
        #NB: CODE is MODULECODE_ACTION
        #1. ��������� �������� layout ����� ��� ����� "BLOCK_{CODE}.LAYOUT_{LANG}|BLOCK_{CODE}.PRINTLAYOUT_{LANG}"
        $layout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf."_L".$langId,undef) if $langId;
        return $layout if defined $layout;
        #1.1 ��������� �������� layout ����� ��� �������� "BLOCK_{CODE}.LAYOUT_S{ID}|BLOCK_{CODE}.PRINTLAYOUT_S{ID}" 
        $layout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf."_S".$subsiteId,undef) if $subsiteId;
        return $layout if defined $layout;
        #2. ��������� �������� "BLOCK_{CODE}.LAYOUT|BLOCK_{CODE}.PRINTLAYOUT"
        $layout = $cms->confParam("BLOCK_".$aBlock->{CODE}.".".$layoutConf,undef);
        return $layout if defined $layout;
        #3. ����� �������� layout �� ���������� �����
        $layout = $aBlock->{$layoutConf} if exists $aBlock->{$layoutConf};
        return $layout if defined $layout;
    };
    #4. ����� �������� $pageRow->{template|printtemplate}
    $layout = $pageObj->{_pageRow}->{template} if $pageObj->{_pageRow} && !$cms->isPrint();
    return $layout if defined $layout;
    $layout = $pageObj->{_pageRow}->{print_template} if $pageObj->{_pageRow} && $cms->isPrint();
    return $layout if defined $layout;
    #5. ��������� �������� ��� "CMS.LAYOUT_{LANG}|CMS.PRINTLAYOUT_{LANG}"
    $layout = $cms->confParam("CMS.".$layoutConf."_L".$langId,undef) if $langId;
    return $layout if defined $layout;
    #5. ��������� �������� ��� "CMS.LAYOUT_S{SUBSITEID}|CMS.PRINTLAYOUT_S{SUBSITEID}"
    $layout = $cms->confParam("CMS.".$layoutConf."_S".$subsiteId,undef) if $subsiteId;
    return $layout if defined $layout;
    #6. ��������� �������� ��� "CMS.LAYOUT|CMS.PRINTLAYOUT"
    $layout = $cms->confParam("CMS.".$layoutConf,undef);
    #return $layout if defined $layout;
    return $layout;
};

=comment isActive
sub isActive {
	my $self = shift;
	return $self->getPageRow()->{active};
}
=cut

sub _getBlockId {
	my $self = shift;
	my $q = $self->cms()->q();
	my $subUrl = $self->getAdminSubURL();
	my $blockId = $subUrl=~ /^block(\d+)\// ? $1 : $q->param('_blockid');
	$blockId ||= "";
	return $blockId;
}

sub _isBaseClass {
	my $self = shift;
	#return 0 if (ref $self ne __PACKAGE__);
    return 0 if $self->pageParam('module_id');
	return 1;
}

sub _getTemplateBlocks {
	#TODO: ������������ getTemplateBlocks
    my $self = shift;
    
    return $self->{_modules} if $self->{_modules};

    my $cms = $self->cms();
    my $dbh = $self->dbh();
    
	my $tmplFile = $self->pageParam('template');
	return $cms->error('��� ���������� ����������� ��������� ��������� ������') unless $tmplFile;

	#����������� ������ � NG::PluginsController::loadPlugins
    my $sql = "
select b.id as block_id, b.name, b.module_id, m.module, m.base as module_base, m.code as module_code,m.name as module_name, m.params as module_params,
b.action, b.params, b.active, b.fixed, b.editable, b.type, tb.disabled
from ng_blocks b, ng_tmpl_blocks tb, ng_modules m
where m.id = b.module_id and tb.block_id = b.id and tb.template = ?";
	
    my $sth = $dbh->prepare($sql) or return $cms->error(__PACKAGE__."::_getTemplateBlocks(): ".$DBI::errstr);
    $sth->execute($tmplFile) or return $cms->error(__PACKAGE__."::_getTemplateBlocks(): ".$DBI::errstr);
    my $hr = $sth->fetchall_arrayref({}) or return $cms->error(__PACKAGE__."::_getTemplateBlocks(): ".$DBI::errstr);
    $sth->finish();
    
    $self->{_modules} = $hr;
    return $self->{_modules};
};

sub getPageTabs {
	my $self = shift;
    
    my $cms = $self->cms();
	
	my $baseUrl = $self->getAdminBaseURL();
	if ($self->_isBaseClass()) {
        #�������� ������� �� ������ �������.
        my $blocks = $self->_getTemplateBlocks() or return $cms->error();
        
		my @tabs = ();
        my $blockId = $self->_getBlockId();
        my $foundEBlock = 0;
        
        $self->{_selectedModule} = undef;
        
        my $getObj = sub {
            my $block = shift;
            
            my $mRow = {};
            $mRow->{id}     = $block->{module_id};
            $mRow->{code}   = $block->{module_code};
            $mRow->{module} = $block->{module};
            $mRow->{base}   = $block->{module_base};
            $mRow->{params} = $block->{module_params};
            $mRow->{name}   = $block->{module_name};
            
            return $cms->getObject($block->{module}, {
                ADMINBASEURL => $baseUrl."block".$block->{block_id}."/",
                PAGEPARAMS   => $self->getPageRow(),
                MODULEROW    => $mRow,
            });
        };
        
		foreach my $eblock (@{$blocks}) {
            next unless $eblock->{editable};
            $foundEBlock = 1;
            
            next unless $cms->hasPageModulePrivilege(MODULE_ID=>$eblock->{module_id}, PRIVILEGE=>"ACCESS",PAGE_ID=>$self->pageParam('id'),SUBSITE_ID=>$self->pageParam('subsite_id'));
            
            #�������� ��������� ���
			my $tab = {
				HEADER   => $eblock->{name},
                URL       => $baseUrl."block".$eblock->{block_id}."/",
                AJAX_URL  => $baseUrl."block".$eblock->{block_id}."/?_ajax=1",
				#SELECTED => $eblock->{SELECTED},
				#NOT_INITIALISED => $eblock->{NOT_INITIALISED},
			};
            #��������� ���������� ����, �������� �������� ����
            $blockId ||= $eblock->{block_id};
            if ($blockId eq $eblock->{block_id}) {
                $tab->{SELECTED} = 1;
                return $cms->error("NG::PageModule: ���������� ������ - ��� �������� ������") if $self->{_selectedModule};
            };
            
            my $mObj = undef;
            #��������� ������, ���� ����� ��� ���� ��� ��� ��� ���
            if ($eblock->{editable} == 2 || $tab->{SELECTED}) {
                $mObj = &$getObj($eblock) or return $cms->error();
                $self->{_selectedModule} = $mObj if $tab->{SELECTED};
            };
            if ($eblock->{editable} == 2) {
                my $mTabs = $mObj->getModuleTabs();
                return $mTabs if $mTabs eq "0"; #cms error
                return $cms->error((ref $mObj)."::getModuleTabs(): �� ������ ������ �������") unless ($mTabs && ref $mTabs eq "ARRAY");
                foreach (@$mTabs) {
                    $_->{SELECTED} = 0 unless $tab->{SELECTED}; #����� ��������� ����
                    push @tabs, $_;
                };
                $tab = undef; #������ �� �����
            };
			push @tabs, $tab if $tab;
		};
        
        unless ($self->{_selectedModule}) {
            while(1) {
                my $code = $cms->confParam("CMS.SiteStructModule","") or last;
                last unless $cms->hasPageStructAccess($self->pageParam('id'),$self->pageParam('subsite_id'));
                
                $self->{_selectedModule} = $cms->getModuleByCode($code, {
                    ADMINBASEURL => $baseUrl,
                    PAGEPARAMS   => $self->getPageRow(),
                }) or return $cms->error();
                return [{HEADER=>"���������",URL=>"/",SELECTED=>1}];
            };
            return $cms->error("����������� ���������� �������������� ��������� ��������") if $foundEBlock;
            return $cms->error("������������� ����� �����������");
        };
		return \@tabs;
	}
	else {
        #�������� ������� �� ������ ������. �������� ������� �� ����.
        return $self->getModuleTabs();
	}
};

# getPageModules() ������������ NG::PagePrivs ��� ���������� ��������� ����������
sub getPageModules {
	my $self = shift;
	
	my $cms = $self->cms();
	
	#���� �� �� ������� �����
	if (!$self->_isBaseClass()) {
		return undef;
		#��������� ������� ����������� ������ modulePrivileges, �� ������������� �� ����������
		#my $mp = $self->modulePrivileges();
		#if (defined $mp && ref $mp eq "ARRAY") {
		#	return [{
		#		MODULE_ID=> $self->moduleParam('id'),
		#		NAME     => $self->moduleParam('name'),
		#	}];
		#};
		#if (defined $mp && $mp == $NG::Application::M_ERROR) {
		#	my $e = $cms->getError("NG::PageModule::getPageModules(): ����������� ������ ������ modulePrivileges");
		#	return $cms->error($e);
		#};
	};
	#���� � ��������� ������ ��� modulePrivileges, ��� ����� ������� - �� ���������� ������ �� ������ ��������
    return undef unless $self->pageParam('template') || $self->pageParam('module_id');
	return $cms->error("������ ".(ref $self)." �� �������� ������ modulePrivileges(), �������� �� �������� ���������".$self->pageParam('id')) unless $self->pageParam('template');
	
    my $blocks = $self->_getTemplateBlocks() or return $cms->error();
	
	my @result = ();
	foreach my $block (@{$blocks}) {
		next unless $block->{editable};
		push @result,{
			#MODULE_ID => $block->{module_id},
			#NAME      => $block->{module_name},
			CODE => $block->{module_code},
		};
	};
	return \@result;
};

sub adminPage { 
	my $self = shift;
	my $is_ajax = shift;
	my $cms = $self->cms();
	
	my $mObj = undef;

	if ($self->_isBaseClass()) {
        return $cms->error("��������������, ��� ����� adminPage ����� ����� ������ getPageTabs") unless $self->{_selectedModule};
        return $cms->error("������ ".(ref $self->{_selectedModule})." �� �������� ������ adminPageModule") unless $self->{_selectedModule}->can("adminPageModule");
        return $self->{_selectedModule}->adminPageModule($is_ajax);
	};
    return $self->adminPageModule($is_ajax);
};

##
##  ���������� ������� �������
##

sub checkIndex {
    my $self = shift;
    my $index = shift;
    my $suffix = shift;
    
    my $cms = $self->cms();
    
    return $cms->error("����������� �������� ��������� �������.") unless defined $index->{CATEGORY};
    
    # � ��������� �������� ��������� �������, ���� ������ ��� �������� � ���������.
    # ## expired ## ���� �������� ������ ��� �������� - �� ���������, ����� ������� �����, � �.� � ������.
    return $cms->error("������������ ������� (".$index->{SUFFIX}.") �� ��������� � ����������� ($suffix).") if ($suffix && ($index->{SUFFIX} ne $suffix));
    return $cms->error("����������� �������� ������ �������.") unless $index->{KEYS};
	return $cms->error("�������� ������ ������� (KEYS) �� �������� ARRAYREF.") unless ref($index->{KEYS}) eq "ARRAY";
    my ($linkId,$langId,$pageId) = (0,0,0);
    foreach my $key (@{$index->{KEYS}}) {
        $linkId = $self->getPageLinkId() if lc($key) eq "linkid";
        $langId = $self->getPageLangId() if lc($key) eq "langid";
        $pageId = $self->getPageId() if lc($key) eq "pageid";
    };
    return $cms->error("� ������ ������������ ������������ ���������� pageid + langid.") if ($pageId && $langId);
    return $cms->error("� ������ ������������ ������������ ���������� pageid + linkid.") if ($pageId && $linkId);
        
    $index->{KEYTYPE} = 0;
    $index->{KEYTYPE} += 1 if ($linkId);
    $index->{KEYTYPE} += 2 if ($langId);
    $index->{KEYTYPE} += 4 if ($pageId);
    $index->{KEYTYPE} += 8 if ($index->{SUFFIX});
    
	## LANGID ������������ ���� ��� ������������������ ���� � ������ pageId, ���� ��� �������� � ������ linkId
	$index->{LANGID} = $self->getPageLangId(); 
	if ($linkId) {
		$index->{LINKID} = $linkId;
	}
	elsif ($pageId) {
		$index->{PAGEID} = $pageId;
		$index->{SUBSITEID} = $self->getSubsiteId();
	}
	else {
		return $cms->error("� ������ ��� �� ����� pageid, �� ����� linkid.");
	};
    return 1;
};

sub updateSearchIndex {
	my $self = shift;
	my $suffix = shift;
    
    my $cms = $self->cms();
    
    my $submodules = $self->moduleBlocks();
    return $cms->error("����� ".(ref $self)." �� �������� ������ moduleBlocks(), �� ���� �������� ������ ������ �������� ��� ����������") unless defined $submodules;

    my $baseurl = $self->getAdminBaseURL();
    
    my $indexes = [];	
    foreach my $subm (@{$submodules}) {
        $subm->{BLOCK} or return $cms->error("������ ".(ref $self)." � �������� ������ ������ ����������� �������� ����� BLOCK");
        my $opts = $subm->{OPTS} || {};
        return $cms->error("�������� OPTS ����� �� �������� HASHREF") unless ref $opts eq "HASH";
        
        #����� ���� � _adminModule() NG::Module
        $subm->{URL} = $self->getAdminSubURL() unless exists $subm->{URL};
        $subm->{URL} =~ s@^/@@;
        $opts->{ADMINBASEURL} = $baseurl. $subm->{URL};
        
        $opts->{MODULEOBJ} =  $self;
        
        my $classDef = {CLASS=>$subm->{BLOCK}};
        $classDef->{USE}= $subm->{USE} if exists $subm->{USE};
        my $bObj = $cms->getObject($classDef,$opts);
        
        return $cms->error("Block ".ref($bObj)." has no getBlockIndex() method") unless $bObj->can("getBlockIndex");
        
		my $blockIndex = $bObj->getBlockIndex($suffix) || return $cms->error();
		next if (scalar(keys %{$blockIndex}) == 0); # ������� ���������� {} ���� �� ���� ���������/�������������, ��� ������� � ��
        
        $blockIndex->{KEYS} ||= ['pageid'];
        
		$self->checkIndex($blockIndex,$suffix) || return $cms->error("������ � �������, ������������ ������� ".ref($bObj).": ".$cms->getError());
		
		my $foundIndex;
		foreach my $tmpindex (@{$indexes}){
			if ($tmpindex->{KEYTYPE} == $blockIndex->{KEYTYPE}) {
				$foundIndex = $tmpindex;
				last;
			};
		};
		if ($foundIndex) {
			# ������ � ������ ������� ������, ��������� �������
			foreach my $class (keys %{$blockIndex->{DATA}}) {
				$foundIndex->{DATA}->{$class} .= " " if ($foundIndex->{DATA}->{$class});
				$foundIndex->{DATA}->{$class} .= $blockIndex->{DATA}->{$class};
				#������� ��� ������� �����������.
			}
		}
		else {
			# ������ � ������ ������� �� ������, ������ ���������
			$blockIndex->{OWNER} = $self->getModuleCode();
			push @{$indexes}, $blockIndex;
		}
	};

	my $db = $cms->db();
	my $st = $db->updatePageIndexes($indexes);
	return $cms->error($db->errstr()) unless $st;
	return 1;
}

##
##  ���������� ��������� �������
##


# ��� �������� ��������
sub canAddPage {
	my $self = shift;
	
	my $pageRow = $self->getPageRow();
	return 1 if ($pageRow->{subptmplgid});
	return 0;
};

sub canActivate {
	my $self = shift;
	return 1;
};

sub canDeactivate {
	my $self = shift;
	return 1;
};

sub getPageAddVariants {
	my $self = shift;
	my $cms = $self->cms();
	my $dbh = $cms->db()->dbh();
	my $pageRow = $self->getPageRow();
	
    return $cms->error("������ �������� �� ������������ ���������� ����������") unless $pageRow->{subptmplgid};
	
    my @variants = ();
    #����������� ������ �������� ������, ������ left join ng_tmpllink ��� �����
    #�������� ������������ ������ (������������ ��������������)
    #���� ������ ������ ����� ������������ ������ � ����� link_id � ng_tmpllink,
    #� �������� link_id ������ ��������� � ng_templates.link_id
    my $sth = $dbh->prepare("select t.id,t.name,t.modulecode, t.link_id as t_link_id, l.link_id from ng_templates t left join ng_tmpllink l on t.id = l.template_id where t.group_id=?") or return $cms->error("NG::PageModule::getPageAddVariants: select templates: ".$DBI::errstr);
    $sth->execute($pageRow->{subptmplgid}) or return $cms->error("NG::PageModule::getPageAddVariants: select templates: ".$DBI::errstr);
	
    my $ttl = {}; # $ttl->{$template_id} = $link_id  -- ��� ��� ��������
    
    while (my $row = $sth->fetchrow_hashref()) {
        if ($row->{link_id} && $row->{t_link_id} != $row->{link_id}) {
            return $cms->error("ng_templates.link_id != nt_tmpllink.link_id for template ".$row->{id});
        };
        if (exists $ttl->{$row->{id}}){
            return $cms->error("Found different link_id for template ".$row->{id}) if $ttl->{$row->{id}} && $row->{link_id} && $ttl->{$row->{id}} != $row->{link_id};
        };
        $ttl->{$row->{id}} = $row->{link_id};
        
        push @variants, {
            ID=>$row->{id},
            NAME=>$row->{name},
            TEMPLATE_ID=>$row->{id},
        };
    };
    return \@variants;
};

sub processNewSubpages {
	my $self = shift;
	my $newSubpages = shift;
	my $variant = shift;
	
    my $cms = $self->cms();
    
	## Cool-���� �����.
	## getPageAddVariants() ������ ���������� ����, ��� �� ����������� �������� pageRow->{subptmplgid} ��� ���������� ������ ���������.
	## processNewSubpages(), � ������ ���� ����������� �������� �� ������� � ������� ���������� (keys $newSubpages == 1), ��
	##                        ��������� ��������� � �������� ���������� �������� ��������� print_template_id, subptmplgid, module

	return $cms->error("processNewSubpages(): newSubpages is not HASHREF") unless ref $newSubpages eq "HASH";
	return $cms->error("processNewSubpages(): variant is not HASHREF") unless ref $variant eq "HASH";
	
    
    unless ($variant->{TEMPLATE_ID}) {
        #�������� ������� �� �� ������ �������, ������ �������� ���� getPageAddVariants()
        return $cms->error("processNewSubpages(): variant has no TEMPLATE_ID parameter") if $self->_isBaseClass() && !$variant->{MODULECODE}; #ASSERT
        
        my $module_id = $self->pageParam('module_id');
        if ($variant->{MODULECODE}) {
            #������ �������� �������� �������� �� ������ ������� ������
            my $mRow = $cms->getModuleRow("code=?",$variant->{MODULECODE}) or return $cms->defError("processNewSubpages():","����������� ������ ".$variant->{MODULECODE}." �� ������");
            $module_id = $mRow->{id};
        };
        
		#TODO: ��������.
		foreach my $subsiteId (keys %{$newSubpages}) {
			my $page = $newSubpages->{$subsiteId};
			$page->{PAGEROW}->{template} = $variant->{template} if $variant->{template};
			$page->{PAGEROW}->{print_template} = $variant->{print_template} if $variant->{print_template};
			$page->{PAGEROW}->{module_id} = $module_id;
			$page->{PAGEROW}->{subptmplgid} = $variant->{subptmplgid} if $variant->{subptmplgid};
			$page->{ACTIVE} = 1;
		};
		return 1;
	};
	
	my $dbh = $cms->db()->dbh();

	my $singleTemplate = undef;
	my $linkedTemplates = undef;
	
	if ($cms->confParam("CMS.hasSubsites")) {
		# ��������� ������ ���������, ��� ������� ����� ��������� ����������� ��������, �� �������� ����������� �������
		my $sql = "select	
				ng_tmpllink.subsite_id as subsite_id,
				ng_tmpllink.template_id as template_id,
				ng_templates.name as template_name,
				ng_templates.subptmplgid,
				ng_templates.print_template,
				ng_templates.modulecode
			from
				ng_tmpllink,ng_templates
			where
				ng_templates.id = ng_tmpllink.template_id 
				and ng_tmpllink.link_id = (select link_id from ng_templates where id = ?)";

		my $sth=$dbh->prepare($sql) or return $cms->error($DBI::errstr);
		$sth->execute($variant->{TEMPLATE_ID}) or return $cms->error($DBI::errstr);
		$linkedTemplates = $sth->fetchall_hashref(['subsite_id']);
		$sth->finish();
	};

	unless (scalar keys %{$linkedTemplates}) {
		$linkedTemplates = undef;
		my $lsth = $dbh->prepare("select id as template_id,name as template_name,subptmplgid,template,print_template from ng_templates where id = ?") or return $cms->error($DBI::errstr); 
		$lsth->execute($variant->{TEMPLATE_ID}) or return $cms->error($DBI::errstr);
		$singleTemplate = $lsth->fetchrow_hashref();
		$lsth->finish();
	};
	
	foreach my $subsiteId (keys %{$newSubpages}) {
        my $page = $newSubpages->{$subsiteId};
	
		$page->{ACTIVE} = 1;
		my $template = undef;
		if (exists $linkedTemplates->{$subsiteId}) {
			$template = $linkedTemplates->{$subsiteId};
		}
		elsif ($singleTemplate) {
			$template = $singleTemplate;
		}
		else {
			$page->{ACTIVE} = 0;
			$page->{MESSAGE} ||= "����������� ������ ��� ����������� ��������";
		};
		$page->{ATTRIB}->{VARIANT_NAME} = $template->{template_name};
		$page->{PAGEROW}->{template} = $template->{template};
		$page->{PAGEROW}->{print_template} = $template->{print_template};
		$page->{PAGEROW}->{subptmplgid} = $template->{subptmplgid};
		
		if ($template->{modulecode}) {
		    my $mRow = $cms->getModuleRow("code=?",$template->{modulecode}) or return $cms->defError("processNewSubpages():","����������� ������ ".$template->{modulecode}." �� ������");
		    $page->{PAGEROW}->{module_id} = $mRow->{id};
		};
	};
	return 1; #TODO: change this ?
};



sub initialisePage {
	my $self = shift;
=head	
	$self->initPageStructure({
		BUILD_EDITABLEBLOCKS=>1,
		SKIP_BLOCKPRIVS =>1,
	}) or return $self->showError("initPageStructure(): hmmm...");
	
	my @initialisedBlocks = ();
	my $has_errors = 0;
	my $errText = "";

	foreach my $eblock (@{$self->{_editableBlocks}}) {
		next unless $eblock->{NOT_INITIALISED};
		my $moduleObj = $eblock->{MODULEOBJ};
		
		my $res = $moduleObj->initPageBlock();
		if($res == NG::Module::M_OK) {
			push @initialisedBlocks, $eblock;
			next;
		};
		if ($res == NG::Module::M_REDIRECT) {
			#$firstNIblockId ||= $block->{id};
			next;
		};
		if ($res == NG::Module::M_ERROR) {
			$errText = $moduleObj->getError();
			$has_errors = 1;
			last;
		};
		$errText = "������������ ��� �������� ($res) �� initPageBlock()";
		$has_errors = 1;
		last;
	};
	if ($has_errors) {
		foreach my $eblock (@initialisedBlocks) {
			next unless $eblock->{MODULEOBJ}->can("destroyPageBlock");
			$eblock->{MODULEOBJ}->destroyPageBlock();
		};
		return $self->setError($errText);
	};
=cut
	return 1;
};

sub destroyPage {
	my $self = shift;
	my $linkedPages = shift;
=head
	my $errTexts = "";

	## ��������� ��� � ���������������� ������ ����������� ������ ����������� �������
	my $keyHash = {};
	my $blockModulesHash = {};
	foreach my $lpObj (@{$linkedPages}) {
		next unless $lpObj->can("editableBlocks");
		my $eBlocks = $lpObj->editableBlocks();

		
		unless ($eBlocks) {
			$errTexts.=" " if $errTexts;
			my $e = $lpObj->getError();
			$e = " ������ ������ $e" if ($e);
			$e ||= " �� ������ ������ � ��������� �� ������";
			$errTexts.= "����� editableBlocks() ��� �������� ".$lpObj->getPageId().$e;
			next;
		};
		
		foreach my $eblock (@{$eBlocks}) {
			my $moduleObj = $eblock->{MODULEOBJ};
			my $eblockId  = $eblock->{BLOCK_ID};
			if (!$eblockId || !$moduleObj) {
				$errTexts.= " " if $errTexts;
				$errTexts.= "����� editableBlocks() ��� �������� ".$lpObj->getPageId()." ������ ���� � ������������� ���������� BLOCK_ID ��� MODULEOBJ";
				next;
			};
			if (exists $blockModulesHash->{$eblockId} && ($blockModulesHash->{$eblockId} ne ref($moduleObj))) {
				$errTexts.= " " if $errTexts;
				$errTexts.= "����� editableBlocks() ��� �������� ".$lpObj->getPageId()." ������ ���� $eblockId �������������� ������:".$blockModulesHash->{$eblockId} ." � ". ref($moduleObj);
				next;
			};
			if ($moduleObj->canEditLinkBlock()) {
				#Do work.
			}
			elsif ($moduleObj->canEditPageBlock()) {
				next;
			}
			else {
				my $e = $moduleObj->getError();
				$e = " ������ ������ $e" if ($e);
				$e ||= " ������ ������������ ������ ��� ��������� �� ������";
				$errTexts.= " " if $errTexts;
				$errTexts.= "����� canEditLinkBlock() ��� ������ ".ref($moduleObj)." (���� $eblockId) �������� ".$lpObj->getPageId().$e;
				next;
			};
			
			$blockModulesHash->{$eblockId} ||= ref($moduleObj);
			next if $eblock->{NOT_INITIALISED};
			
			my $key = $moduleObj->getContentKey();
			unless ($key) {
				my $e = $moduleObj->getError();
				$e = " ������ ������ $e" if ($e);
				$e ||= " �� ������ ������ � ��������� �� ������";
				$errTexts.=" " if $errTexts;
				$errTexts.= "����� getContentKey() ��� ������ ".ref($moduleObj)." (���� $eblockId) �������� ".$lpObj->getPageId().$e;
				next;
			};
			#�� ��������� � ���������� ����������� ���������� �����, ���������������� ������� ������ ��� ����������� BLOCKID
			$key = "b".$eblockId.$key;
			
			$keyHash->{$key}||=0;
			$keyHash->{$key}++;
		};
	};
	return $self->error($errTexts) if $errTexts;

	
	#��������� ����� ��������� (����) ��������
	my $eBlocks = $self->editableBlocks();
	
	unless ($eBlocks) {
		my $e = $self->getError();
		$e = " ������ ������ $e" if ($e);
		$e ||= " �� ������ ������ � ��������� �� ������";
		return $self->error("����� editableBlocks() ��� �������� ".$self->getPageId().$e);
	};
	
	my @destroyLBObjs = ();
	my @destroyPBObjs = ();
	
	foreach my $eblock (@{$eBlocks}) {
		my $moduleObj = $eblock->{MODULEOBJ};
		my $eblockId  = $eblock->{BLOCK_ID};
		if (!$eblockId || !$moduleObj) {
			return $self->error("����� editableBlocks() ��� �������� ".$self->getPageId()." ������ ���� � ������������� ���������� BLOCK_ID ��� MODULEOBJ");
		};
		if (exists $blockModulesHash->{$eblockId} && ($blockModulesHash->{$eblockId} ne ref($moduleObj))) {
			return $self->error("����� editableBlocks() ��� �������� ".$self->getPageId()." ������ ���� $eblockId �������������� ������:".$blockModulesHash->{$eblockId} ." � ". ref($moduleObj));
		};
		$blockModulesHash->{$eblockId} ||= ref($moduleObj);
		next if $eblock->{NOT_INITIALISED};
		
		if ($moduleObj->canEditLinkBlock()) {
			#Do work.
			my $key = $moduleObj->getContentKey();
			unless ($key) {
				my $e = $moduleObj->getError();
				$e = " ������ ������ $e" if ($e);
				$e ||= " �� ������ ������ � ��������� �� ������";
				return $self->error("����� getContentKey() ��� ������ ".ref($moduleObj)." (���� $eblockId) �������� ".$self->getPageId().$e);
			};
			$key = "b".$eblockId.$key;
			
			unless (exists $keyHash->{$key}) {
				push @destroyLBObjs, $moduleObj;
			};
			next;
		}
		elsif ($moduleObj->canEditPageBlock()) {
			push @destroyPBObjs, $moduleObj;
			next;
		}
		else {
			my $e = $moduleObj->getError();
			$e = " ������ ������ $e" if ($e);
			$e ||= " ������ ������������ ������ ��� ��������� �� ������";
			return $self->error("����� canEditLinkBlock() ��� ������ ".ref($moduleObj)." �������� ".$self->getPageId().$e);
			next;
		};
	};
	
	foreach my $moduleObj (@destroyPBObjs) {
	    my $res = $moduleObj->destroyPageBlock();
		if ($res != NG::Block::M_OK) {
			my $e = $moduleObj->getError();
			$e = " ������ ������ $e" if ($e);
			$e ||= " ������ ������������ ������ ��� ��������� �� ������";
			return $self->error("����� destroyPageBlock() ��� ������ ".ref($moduleObj)." �������� ".$self->getPageId().$e);
		};
	};
	foreach my $moduleObj (@destroyLBObjs) {
	    my $res = $moduleObj->destroyLinkBlock();
		if ($res != NG::Module::M_OK) {
			my $e = $moduleObj->getError();
			$e = " ������ ������ $e" if ($e);
			$e ||= " ������ ������������ ������ ��� ��������� �� ������";
			return $self->error("����� destroyLinkBlock() ��� ������ ".ref($moduleObj)." �������� ".$self->getPageId().$e);
		};
	};
=cut
	return 1;
};

##
##
##

=head getPageBlocksPrivileges
sub getPageBlocksPrivileges {
	my $self = shift;
	
	if ($self->_isBaseClass()) {
		$self->initPageStructure({
			BUILD_EDITABLEBLOCKS=>1,
			SKIP_BLOCKPRIVS => 1,
			USE_CACHE       => 1,
		}) or return $self->showError("initPageStructure(): hmmm...");

		my $blocks = $self->editableBlocks(); 
		unless ($blocks) {
			my $e = $self->getError();
			$e = " ������ ������ $e" if ($e);
			$e ||= " �� ������ ������ � ��������� �� ������";
			return $self->showError("����� editableBlocks() ��� �������� ".$self->getPageId().$e);
		};

		my @pageBlocks = ();
		foreach my $block (@{$blocks}) {
			my $moduleObj = $block->{MODULEOBJ};
			
			my $mp = $moduleObj->modulePrivileges();
			unless ($mp) {
				return $self->error("������ ��������� ������ ���������� ������ ".ref($self).":".$moduleObj->getError());
			};
			if (ref $mp ne "ARRAY") {
				return $self->error("������������ �������� ������ ���������� ������ ".ref($self)." �� �������� ��������");
			};
				
			my $type = "";
			my $has_lang_linked = 0;
			if ($moduleObj->canEditLinkBlock()) {
				$type = "link";
				$has_lang_linked = 1 if ($moduleObj->hasLangLindked());
			}
			elsif ($moduleObj->canEditPageBlock())  {
				$type = "page";
			}
			else {
				return $self->showError("���� �� �������� ������ ���� LinkBlock ��� PageBlock, ������ ������� canEditLinkBlock() � canEditPageBlock() ������ ".ref($moduleObj)." �� ������� ������ (��� ��������: ".$self->getPageId().")");
			};
			push @pageBlocks, {
				NAME       => $block->{HEADER},
				PRIVILEGES => $mp,
				TYPE	   => $type,
				BLOCKID    => $block->{BLOCK_ID},
				HAS_LANG_LINKED => $has_lang_linked
			};
		};
		return \@pageBlocks;
	}
	else {
		#�������� - ������
		my $mp = $self->modulePrivileges();
		unless ($mp) {
			return $self->error("������ ��������� ������ ���������� ������ ".ref($self).":".$self->getError());
		};
		if (ref $mp ne "ARRAY") {
			return $self->error("������������ �������� ������ ���������� ������ ".ref($self)." �� �������� �������� ����������");
		};
		
		return [] unless scalar @{$mp};
		
		my $type = "";
		if ($self->canEditLinkBlock()) {
			$type = "link";
		}
		elsif ($self->canEditPageBlock())  {
			$type = "page";
		}
		else {
			return $self->showError("���� �� �������� ������ ���� LinkBlock ��� PageBlock, ������ ������� canEditLinkBlock() � canEditPageBlock() ������ ".(ref($self))." �� ������� ������");
		};
		
		return [{
			NAME       => "������",
			PRIVILEGES => $mp,
			TYPE	   => $type,
			BLOCKID    => 1,
		}];
	};
};
=cut

return 1;
END {};
