package NG::Module::PageSelector;
use strict;

use NGService;
use NSecure;
use NHtml;
use NG::Module;
use NG::Nodes;

use vars qw(@ISA @subsitePrivList);

@subsitePrivList = (
	{privilege=>'ACCESS',name=>'Доступ к сайту'},
	{privilege=>'SUPERADMIN',name=>'Администратор подсайта (все права)'},
);
	

sub init {
	my $self = shift;
	$self->SUPER::init(@_);
	$self->{cache_templates_blocks} = undef;
	$self->{cache_pages_blocks} = undef;
};

sub AdminMode {
    use NG::Module;
    @ISA = qw(NG::Module);	
};

sub getModuleTabs {
	my $self = shift;
	return [
		{HEADER=>"Дерево сайта",URL=>"/"},
	];

}

sub moduleAction {
    my $self = shift;
    my $is_ajax = shift;
	    
	my $q = $self->q();
	my $app = $self->app();
	my $dbh = $self->db()->dbh();

    my $appSSId = undef; #Ищем код подсайта если есть выбранная страница.
    $appSSId = $self->{_pageRow}->{subsite_id} if ($self->{_pageRow});
	my $subsiteId = $q->param('subsite_id') || $appSSId;
	my $adminId = $app->getAdminId();
	
	## Загружаем свойства выбранного подсайта

	my $subsiteRow = undef;
	my $subsites = undef;
	if (is_int($subsiteId)) {
		my $sel_sth = $dbh->prepare_cached("select id,lang_id,name,root_node_id from ng_subsites,ng_subsite_privs where ng_subsite_privs.subsite_id = ng_subsites.id and ng_subsites.id = ? and admin_id = ? and privilege = 'ACCESS'") or die $DBI::errstr;
		$sel_sth->execute($subsiteId,$adminId) or die $DBI::errstr;
        $subsiteRow = $sel_sth->fetchrow_hashref()  or return $self->setError("Вам не предоставлен доступ к запрошенному подсайту.");
		$sel_sth->finish();
		
		$subsites = $app->_loadSubsitesForCAdmin($subsiteRow->{root_node_id});
	}

	# Загружаем первый попавшийся сайт. TODO: доделать упорядоченность ?	
	unless ($subsiteRow) {
		$subsites = $app->_loadSubsitesForCAdmin();
		
		my $sel_sth = $dbh->prepare_cached("select id,lang_id,name,root_node_id from ng_subsites") or die $DBI::errstr;
		$sel_sth->execute() or die $DBI::errstr;
        $subsiteRow = $sel_sth->fetchrow_hashref();
		$sel_sth->finish();
		
		return $self->setError("Вам не предоставлен доступ к администрированию подсайтов") unless scalar @{$subsites};
		
		$subsiteRow = @{$subsites}[0];
		$subsiteId = $subsiteRow->{id};
	}
	$subsites = [] if scalar (@{$subsites} < 2);
	
	# Загружаем сайтовые привилегии текущего админа
	my $sel_sth = $dbh->prepare_cached("select privilege from ng_subsite_privs WHERE subsite_id = ? and admin_id = ?") or die $DBI::errstr;
    $sel_sth->execute($subsiteId,$adminId) or die $DBI::errstr;
	my $subsitePrivs = $sel_sth->fetchall_hashref('privilege');
	$sel_sth->finish();

	#Загружаем страничные привилегии пользователя
	my $sel_sth = $dbh->prepare_cached("select page_id,block_id,privilege from ng_page_privs WHERE page_id <> 0 and admin_id = ? and subsite_id = ?") or die $DBI::errstr;
    $sel_sth->execute($adminId,$subsiteId) or die $DBI::errstr;
	my $pagePrivs = $sel_sth->fetchall_hashref(['page_id','block_id','privilege']);
	$sel_sth->finish();

	$sel_sth = $dbh->prepare_cached("select link_id,lang_id,block_id,privilege from ng_page_privs WHERE link_id <> 0 and admin_id = ?") or die $DBI::errstr;
    $sel_sth->execute($adminId) or die $DBI::errstr;
	my $linkPrivs = $sel_sth->fetchall_hashref(['link_id','lang_id','block_id','privilege']);
	$sel_sth->finish();
	## подгружаем дерево страниц
	my $tree = NG::Nodes->new();
	$tree->initdbparams(
		db=>$self->db(),
		table=>"ng_sitestruct",
		fields=>"name,active,template_id,module,link_id,lang_id,subsite_id",
	);
	
	$subsiteRow->{root_node_id} ||= 0;
	$tree->loadtree($subsiteRow->{root_node_id});
	
	$tree->traverse(
		sub {
			my $_tree = shift;
			my $value = $_tree->getNodeValue();

			my @pageBlocks = ();
			
			push @pageBlocks, {
				NAME   => "Свойства",
				TYPE   => "page",
				BLOCKID=> 0,
				URL    => "/admin-side/pages/".$value->{id}."/struct/",
			};
			
			
			if ($value->{module}) {
				#Страница - модуль
				my $moduleObj = $app->getModuleObject($value->{module},{PAGEROW=>$value}) or return $self->error($app->getError());	
				
				my $type = "";
				if ($moduleObj->canEditLinkBlock()) {
					$type = "link";
				}
				elsif ($moduleObj->canEditPageBlock())  {
					$type = "page";
				}
				else {
					my $err = $moduleObj->getError();
					return $self->error($err) if ($err);
					next;
				}

				push @pageBlocks, {
					NAME    => "Модуль",
					URL     => "/admin-side/pages/".$value->{id}."/",
					TYPE	=> $type,
					BLOCKID => 1,
				};
			}
			else {
				my $blocks = $self->getPageBlocks($value->{id},$value->{template_id}) or return $self->showError();
				foreach my $block (@{$blocks}) {
					my $moduleObj = $block->{_module_obj};
					
					$moduleObj->setPageRow($value);
					$moduleObj->setBlockId($block->{id});
					
					my $type = "";
					if ($moduleObj->canEditLinkBlock()) {
						$type = "link";
					}
					elsif ($moduleObj->canEditPageBlock())  {
						$type = "page";
					}
					else {
						my $err = $moduleObj->getError();
						return $self->error($err) if ($err);
						next;
					}
					
					push @pageBlocks, {
						NAME    => $block->{name},
						TYPE	=> $type,
						BLOCKID => $block->{id},
						URL     => "/admin-side/pages/".$value->{id}."/block".$block->{id}."/",
					};
				}
			}
			my $hasAllowed = 0;
			foreach my $pb (@pageBlocks) {
				$pb->{ALLOWED} = 0;
                if ($pb->{BLOCKID} == 0) {
                    $pb->{ALLOWED} = 1 if (exists $subsitePrivs->{'PROPERTIES'});
                    #TODO: NEWPAGE должна будет включать PROPERTIES
                    $pb->{ALLOWED} = 1 if (exists $pagePrivs->{$value->{id}} && exists $pagePrivs->{$value->{id}}->{$pb->{BLOCKID}} && exists $pagePrivs->{$value->{id}}->{$pb->{BLOCKID}}->{NEWPAGE});
                    $pb->{ALLOWED} = 1 if (exists $pagePrivs->{$value->{id}} && exists $pagePrivs->{$value->{id}}->{$pb->{BLOCKID}} && exists $pagePrivs->{$value->{id}}->{$pb->{BLOCKID}}->{PROPERTIES});
                }
				elsif ($pb->{TYPE} eq "page") {
					$pb->{ALLOWED} = 1 if (exists $subsitePrivs->{'CONTENT'});
					$pb->{ALLOWED} = 1 if (exists $pagePrivs->{$value->{id}} && exists $pagePrivs->{$value->{id}}->{$pb->{BLOCKID}} && exists $pagePrivs->{$value->{id}}->{$pb->{BLOCKID}}->{'ACCESS'});
				}
				elsif ($pb->{TYPE} eq "link") {
					$pb->{ALLOWED} = 1 if (exists $subsitePrivs->{'CONTENT'});
					$pb->{ALLOWED} = 1 if (exists $linkPrivs->{$value->{link_id}} && exists $linkPrivs->{$value->{link_id}}->{$value->{lang_id}} && exists $linkPrivs->{$value->{link_id}}->{$value->{lang_id}}->{$pb->{BLOCKID}} && exists $linkPrivs->{$value->{link_id}}->{$value->{lang_id}}->{$pb->{BLOCKID}}->{'ACCESS'});
				}
				else {
					die "Incorrect block type";
				}
				$hasAllowed = 1 if $pb->{ALLOWED};
			}
			if ($hasAllowed) {
				my $node = $_tree;
				while (1) {
					my $v = $node->getNodeValue();
					$v->{ALLOWED} = 1;
					last if $node->isRoot();
					$node = $node->getParent();
				}
			}
			$value->{PAGEBLOCKS} = \@pageBlocks;
		}
	);
	

	my @a = ($tree);
	while (scalar (@a)) {
		my $e = shift @a;
		my $prevChild = undef;
		foreach my $c ($e->getAllChildren()) {
			if ($c->getNodeValue()->{ALLOWED}) {
				$prevChild->{_next_sibling_order} = $c->{_order} if $prevChild;
				$prevChild = $c;
				$c->{_next_sibling_order} = undef;
				push @a,$c;
			}
			else {
				$e->removeChild($c);
			}
		}
	};

	## вывод в шаблон.
	$self->opentemplate("admin-side/common/sitestruct/pageselector.tmpl") or return $self->showError();
	my $template = $self->template();

	$tree->printToDivTemplate($template,'TREE');
	

	$template->param(
		SUBSITE => $subsiteRow,
		SUBSITES => $subsites,
		SUBSPRIVS => \@subsitePrivList,
		ACTION => $self->getBaseURL(),
		TRUE   => 1,
	);
    $app->setModuleTabs([{HEADER=>"Доступные страницы",SELECTED=>1}]);
	
    return $self->output($self->tmpl()->output()); 		
}; 

#TODO: дублирование кода с кодом в PageRights.pm
sub getPageBlocks {
	my $self = shift;
	my $pageId = shift;
	my $templateId = shift;
	
	my $app = $self->app();

	if (!defined $self->{cache_templates_blocks}) {
		my $sth = $self->db()->dbh()->prepare("select b.*,t.template_id as tid from ng_template_blocks t,ng_blocks b where t.block_id=b.id order by t.template_id") or return $self->error($DBI::errstr);
		$sth->execute() or return $self->error($DBI::errstr);
		$self->{cache_templates_blocks} = $sth->fetchall_hashref(['tid','group_id','id']);
		$sth->finish();	
	}
	if (!defined $self->{cache_pages_blocks}) {
		my $sth = $self->db()->dbh()->prepare("select b.*,pb.page_id as page_id from ng_page_blocks pb,ng_blocks b where pb.block_id=b.id order by pb.page_id") or return $self->error($DBI::errstr);
		$sth->execute() or return $self->error($DBI::errstr);
		$self->{cache_pages_blocks} = $sth->fetchall_hashref(['page_id','group_id']);
		$sth->finish();
	}
	
	my $templates_blocks = $self->{cache_templates_blocks};
	my $pages_blocks = $self->{cache_pages_blocks};

	# Здесь поидее можно проверять чтоб в результирующий массив не кидать повторяющиеся блоки, каковые в принципе могут быть, но подумали и Паша решил что это не надо.
	my @subtemplates = ($templateId);
	my @blocks = ();
	my $stopCounter = 0;
	while (scalar @subtemplates) {
		$templateId = shift @subtemplates;
		my $templateBlocks = $templates_blocks->{$templateId};
		next unless ($templateBlocks);
		
		foreach my $groupId (keys %{$templateBlocks}) {
			foreach my $blockId (keys %{$templateBlocks->{$groupId}}) {
				my $block = undef;
				if (exists $pages_blocks->{$pageId} && exists $pages_blocks->{$pageId}->{$groupId}) {
					$block = $pages_blocks->{$pageId}->{$groupId}
				}
				else {
					$block = $templateBlocks->{$groupId}->{$blockId};
				}
				
				if ($block->{module}) {
					next if $block->{readonly};
					unless ($block->{_module_obj}) {
					$block->{_module_obj} = $app->getModuleObject($block->{module},{PAGEROW=>$self->getPageRow(),BLOCKID=>$blockId}) or return $self->error($app->getError());	
					}
					push @blocks, $block;
				}
				elsif ($block->{template_id}) {
					push @subtemplates,$block->{template_id};
				}
			};
		};
		$stopCounter++;
		if ($stopCounter > 25) {
			return $self->error("Ошибка: Число вложенных шаблонов в структуре страницы слишком велико. (>25)");
		};
	};
	return \@blocks;
};


return 1;

