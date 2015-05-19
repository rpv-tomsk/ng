package NG::MLListSingle;

use strict;
use NG::Nodes;
use Carp;
use NG::Form;
use NSecure;
use Data::Dumper;
use NG::Application::List;
use NG::Form;
use Scalar::Util qw (blessed);

BEGIN {
	use vars qw(@ISA);
	@ISA = qw(NG::Application::List);
};

sub init {
	my $self = shift;
	$self->SUPER::init(@_);
	$self->{_catalog_fields} = [];
	$self->{_positions_fields} = [];
	$self->{_catalog_formfieldsname} = "";
	$self->{_catalog_editfieldsname} = "";
	$self->{_root_id} = [];
	
	$self->{_catalog_extra_links} = [];
	$self->{_langs} = [];	
	$self->{_lang} = 0;
	$self->{_formtemplate} = "admin-side/common/universalform.tmpl";
	
	$self->register_action("","showTreeCatalog");
	$self->register_ajaxaction("insertcatalogform","getCatalogForm");
	$self->register_ajaxaction("updatecatalogform","getCatalogForm");
	$self->register_ajaxaction("insertcatalog","InsertUpdateCatalog");
	$self->register_ajaxaction("updatecatalog","InsertUpdateCatalog");
	$self->register_action("movecatalogup","moveCatalogUp");
	$self->register_action("movecatalogdown","moveCatalogDown");
	$self->register_action("deletecatalog","deleteCatalog");
	$self->register_ajaxaction("deletefilecatalog","deleteFileCatalog");
	$self->register_action("showpositions","showPositions");
};


sub root_id {
	my $self = shift;
	if (@_) {
		my $lang = shift;
		for(my $i=0;$i<scalar @{$self->{_langs}};$i++) {
			if (${$self->{_langs}}[$i] eq $lang) {
				${$self->{_root_id}}[$i] = shift;
				last;
			}; 
		};		
	};
	return ${$self->{_root_id}}[$self->{_lang}];
};

sub setLangs {
	my $self = shift;
	@{$self->{_langs}} = (@_);
};

sub setLang {
	my $self = shift;
	my $q = $self->q();
	my $lang = $q->param("lang");
	$self->{_lang} = 0;
	for(my $i=0;$i<scalar @{$self->{_langs}};$i++) {
		if (${$self->{_langs}}[$i] eq $lang) {
			$self->{_lang} = $i;
			last;
		}; 
	};
};


sub getLangs {
	my $self = shift;
	my @langs = ();
	for(my $i=0;$i<scalar @{$self->{_langs}};$i++) {
		push @langs, {id=>$i,lang=>${$self->{_langs}}[$i],current=>($self->{_lang}==$i?1:0)};
	};	
	return \@langs;
};

sub getLangLetter {
	my $self = shift;
	return ${$self->{_langs}}[$self->{_lang}];
};

sub addCatalogExtraLink {
	my $self = shift;
	my $name = shift;
	my $urlmask = shift;
	my $ajax = shift;
	push @{$self->{_catalog_extra_links}}, {NAME=>$name,URL=>$urlmask,AJAX=>$ajax};
};

sub _createTreeObject {
	my $self = shift;
	my $tree = NG::Nodes->new();
	$tree->initdbparams(
		db    =>$self->db(),
		table =>$self->{_tree_table},
		fields=>"name,has_static", # Потом удалить хаз статик 
	);
	return $tree;
};


sub showTreeCatalog {
    my $self = shift;
    $self->set_header_nocache();
    $self->opentemplate("admin-side/common/multilevellist.tmpl") || return $self->showError();
    
	my $q = $self->q();
	my $id = is_valid_id($q->param('id'))?$q->param('id'):$self->root_id();
	
	my $tree = $self->_createTreeObject();
    $tree->loadPartOfTree($self->root_id(),$id);
	$tree->printToTemplate($self->tmpl(),'ROWS',$id);
	
	my $node = $tree->getNodeById($id);
	
	my @childs = ();
	foreach my $children (@{$node->{_children}}) {
		my @extra_links = ();
		if ($children->{_node}->{has_static} eq "1") { # Это временое решение только для того здать сайт потом надо все переделать
			foreach my $link (@{$self->{_catalog_extra_links}}) {
				my $tmpurl = $link->{URL};
	            $tmpurl =~ s/\{(.+?)\}/$children->{_node}->{$1}/gi;
            	push @extra_links, {NAME=>$link->{NAME},URL=>$tmpurl,AJAX=>$link->{AJAX}};
			};
		}; #
		push @childs, {extra_links=>\@extra_links,id=>$children->{_id},name=>$children->{_node}->{name},canadd=>$self->_canAddCatalog($children->{_id},$children->{_level})&&!$children->{_node}->{is_reg},candelete=>$self->_canDeleteCatalog($children->{_id},$children->{_level})};
	};
	
	my @extra_links = ();
	if ($node->{_node}->{has_static} eq "1") { # Это временое решение только для того здать сайт потом надо все переделать
		foreach my $link (@{$self->{_catalog_extra_links}}) {
			my $tmpurl = $link->{URL};
			$tmpurl =~ s/\{(.+?)\}/$node->{_node}->{$1}/gi;
			push @extra_links, {NAME=>$link->{NAME},URL=>$tmpurl,AJAX=>$link->{AJAX}};
		};	
	}; #
	
	
	$self->tmpl()->param(
		langs => $self->getLangs(),
		current_lang => $self->getLangLetter(),
		subnodes => \@childs,
		showchildrens => 1,
		selected_node_extra_links => \@extra_links,
		selected_node_id => $node->{_node}->{id},
		selected_node_name => $node->{_node}->{name},
		selected_node_canadd => $self->_canAddCatalog($node->{_node}->{id},$node->{_node}->{level}),
		selected_node_candelete => $self->_canDeleteCatalog($node->{_node}->{id},$node->{_node}->{level}),
		selected_node_canaddpositions => $self->_canAddPositions($node->{_node}->{id},$node->{_node}->{level}),
	);
	
	$self->AdminMenuTree();
    $self->print_template();
};

#sub AdminMenuTree {
#	my $self = shift;
#	my $tree = NG::Nodes->new();
#	$tree->initdbparams(
#		db=>$self->db(),
#		table=>"admin_menu_tree",
#		fields=>"name,url,reg,privilege,subtree_proc",
#	);
#	$tree->loadPartOfTree(0,0);
#	$tree->printToTemplate($self->tmpl(),'ADMINMENU',0);
	#$self->SUPER::AdminMenuTree();
#};


sub _addTreeCatalogFields {
	my $self = shift;
	my $field = shift;
	push @{$self->{_catalog_fields}}, $field;
};

sub addTreeCatalogFields {
	my $self = shift;
	my $ref = shift;
	
	if (!defined $ref) { die "Field not defined in \$form->addfields()..."; };
	
	if (ref $ref eq "") {
		unshift(@_,$ref);
		my %field = (@_);
		$self->_addTreeCatalogFields(\%field);
	}
	if (ref $ref eq 'HASH') {
		my %field = %{$ref};
		$self->_addTreeCatalogFields(\%field);
	}
	if (ref $ref eq 'ARRAY') {
		foreach my $tmp (@{$ref}) {
			my %field = %{$tmp};
			$self->_addTreeCatalogFields(\%field);
		};
	};	
};

sub catalog_editfields {
    my $self = shift;
    $self->{_catalog_editfieldsname} = shift;
};

sub catalog_formfields {
    my $self = shift;
    $self->{_catalog_formfieldsname} = shift;
};

sub tree_table {
    my $self = shift;
    $self->{_tree_table} = shift;
};

sub _getCatalogFieldHash {
	my $self = shift;
	my $fieldname = shift;
	foreach my $field (@{$self->{_catalog_fields}}) {
		if ($field->{FIELD} eq $fieldname)  {
			return $field;
			last;
		};
	};
	return undef;
};

sub _getCatalogForm {
	my $self = shift;
    my $action = shift;
    my $form = NG::Form->new(
        FORM_URL  => $self->q()->url(),
		KEY_FIELD => "id", # TODO 
        DB        => $self->db(),
        TABLE     => $self->{_tree_table},
        DOCROOT   => $self->{_docroot},
        CGIObject => $self->{_q},
        
	);
    $form->{_ajax} = 1;
	$form->{_form_action} = "insertcatalog" if ($action eq "insertcatalogform");
	$form->{_form_action} = "updatecatalog" if ($action eq "updatecatalogform");
    
    $form->addfields({TYPE=>"hidden",NAME=>"parent_id",FIELD=>"parent_id",IS_NOTNULL=>1}) if ($action eq "insertcatalogform");
    $form->addfields({TYPE=>"text",NAME=>"Название",FIELD=>"name",IS_NOTNULL=>1});
    
    my $fields = "";

	
    if ($action eq "insertcatalogform") {
    	$fields = $self->{_catalog_formfieldsname};
    };
    
    if ($action eq "updatecatalogform" && $self->{_catalog_editfieldsname}) {
    	$fields = $self->{_catalog_editfieldsname};
    } else {
    	$fields = $self->{_catalog_formfieldsname};
    };
    
    my @fields = split /\,/,$fields;
    
    foreach my $fieldname (@fields) {
    	my $field = $self->_getCatalogFieldHash($fieldname);
    	if (defined $field) {
    		$form->addfields($field);
    	};
    };
    
    #$form->setnew();
    
    my $idvalue = $self->q()->param("id") + 0;
    
    if ($action eq "insertcatalogform") {
    	#$form->param("id",$self->db()->get_id($self->{_tree_table}));
    	$form->param("parent_id",$idvalue);
    } elsif ($action eq "updatecatalogform") {
		$form->loadData($idvalue);
    };
    $form->{_container} = "catalogdiv".$idvalue;
    
    return $form;
};

sub formSettings {
	my $self = shift;
	my $action = shift;
	my $form = shift;
	
};

sub getCatalogForm {
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	my $id = is_valid_id($q->param('id'))?$q->param('id'):0;
	$self->set_header_nocache();
		
	my $form = $self->_getCatalogForm($action);
	if ($action eq "insertcatalogform") {
		$form->param("id",$self->db()->get_id($self->{_tree_table}));
	};
	$self->formSettings($action,$form);
	$self->opentemplate("admin-side/common/universalform.tmpl") || return $self->showError();
	$form->print_to_template($self->tmpl());
	#my $form_html = $form->print_to_template($self->tmpl());
	#$self->opentemplate("admin-side/catalog_admin2.tmpl") || return $self->showError();
	#$self->tmpl()->param(
		#form_html => $form_html,
		#showcatalogform => 1
	#);
	
	#my $tree = $self->_createTreeObject();
    #$tree->loadPartOfTree($self->root_id(),$id);
	#$tree->printToTemplate($self->tmpl(),'ROWS',$id);
	
	#my $node = $tree->getNodeById($id);
	#$self->tmpl()->param(
	#	langs => $self->getLangs(),
	#	current_lang => $self->getLangLetter(),	
	#	showchildrens => 1,
	#	selected_node_id => $node->{_node}->{id},
	#	selected_node_canadd => $self->_canAddCatalog($node->{_node}->{id},$node->{_node}->{level}),
	#	selected_node_candelete => $self->_canDeleteCatalog($node->{_node}->{id},$node->{_node}->{level}),
	#	selected_node_canaddpositions => $self->_canAddPositions($node->{_node}->{id},$node->{_node}->{level}),
	#);
	#$self->AdminMenuTree();
    $self->print_template();
};

sub InsertUpdateCatalog {
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	
	my $form = $self->_getCatalogForm($action."form");
	$form->_setFormValues();
	$form->StandartCheck($action);
	$self->CatalogCheckData($action,$form);
	
	if ($form->has_err_msgs()) {
        $form->cleanUploadedFiles();
        $self->set_header_nocache();
		$form->normal_showerrors();
		return;        		
	};	
	$form->_prepareData();
	$self->CatalogPrepareData($action,$form);

    if (($action eq "insertcatalog")) {
		my $tree = $self->_createTreeObject();
		my $parent_id = $q->param('parent_id') || $self->root_id();
		$tree->loadNode($parent_id);    
		$tree->{_fields} = $tree->{_fields}.($self->{_catalog_formfieldsname}?",".$self->{_catalog_formfieldsname}:"");	
    	$tree->DBaddChild($form->getFormData());
    } else {
    	$form->updateData();
    };
    
    $self->afterInsertUpdateCatalog($action,$form);
	#$self->redirect_to_referer_or();	
	$self->set_header_nocache();
	print "<script type='text/javascript'>parent.window.location.href='".$self->get_referer_or()."';</script>";
};

sub deleteFileCatalog {
	my $self = shift;

	my $q = $self->q();
	my $fieldname = $q->param('field');
	my $idvalue = $q->param("id");
	my $field = $self->_getCatalogFieldHash($fieldname);
	
	if (is_valid_id($idvalue) && ($field->{TYPE} eq "image" || $field->{TYPE} eq "file") && !$field->{IS_NOTNULL}) {
		my $sth = $self->db()->dbh()->prepare("select ".$fieldname." from ".$self->{_tree_table}." where id=?") or die $DBI::errstr;
		$sth->execute($idvalue) or die $DBI::errstr;
		my ($file) = $sth->fetchrow();
		$sth->finish();
		unlink $self->{_docroot}.$field->{UPLOADDIR}.$file if ($file);
		$self->db()->dbh()->do("update ".$self->{_tree_table}." set ".$fieldname."='' where id=?",undef,$idvalue) or die $DBI::errstr;
	};
	$self->set_header_nocache();
};


sub moveCatalogUp {
	my $self = shift;
	my $q = $self->q();
	my $tree = $self->_createTreeObject();
	my $id = is_valid_id($q->param('id'))?$q->param('id'):0; 
	if (is_valid_id($id)) {
		$tree->loadNode($id) or die "No node found";
		$tree->DBmoveNodeUp() or die "No node found";
	};
	$self->redirect_to_referer_or("");
};

sub moveCatalogDown {
	my $self = shift;
	my $q = $self->q();
	my $tree = $self->_createTreeObject();
	my $id = is_valid_id($q->param('id'))?$q->param('id'):0; 	
	if (is_valid_id($id)) {
		$tree->loadNode($id) or die "No node found";
		$tree->DBmoveNodeDn() or die "No node found";
	};
	$self->redirect_to_referer_or("");
};


sub deleteCatalog {
	my $self = shift;
	my $q = $self->q();
	my $id = is_valid_id($q->param('id'))?$q->param('id'):0; 
	my $tree = $self->_createTreeObject();
	my $dbh = $self->db->dbh();
	my $parent_id = 0;
	if ($id) {
		$self->beforeDeleteCatalog();
		my @filefields = ();
		my %dirs = ();
		foreach my $field (@{$self->{_fields}}) {
			if ($field->{TYPE} eq "image" || $field->{TYPE} eq "file") {
				push @filefields, $field->{FIELD};
				$dirs{$field->{FIELD}} = $field->{UPLOADDIR};
			};
		};
		
		if (scalar @filefields) {
			my $sthfile = undef;
			$sthfile = $dbh->prepare("select ".join(",",@filefields)." from ".$self->{_table}." where parent_id=?") or die $DBI::errstr;
			$sthfile->execute($id)  or die $DBI::errstr;
			while (my $row = $sthfile->fetchrow_hashref()) {
				foreach my $key (keys %{$row}) {
					unlink $self->{_docroot}.$dirs{$key}.$row->{$key};
				};
			};
			$sthfile->finish();
		};
		
		if ($self->{_table} ne "notable") {
			$dbh->do("delete from ".$self->{_table}." where parent_id=?",undef,$id) or die $DBI::errstr;		
		};
		
	
		$tree->loadNode($id);		
		$parent_id = $tree->{_parent_id};
		$tree->DBdelete();
		

		$self->afterDeleteCatalog();
	};
	
	$self->redirect_url($q->url(-absolute=>1)."?id=".$parent_id."&lang=".$self->getLangLetter());
};

sub CatalogCheckData {
	#virtual
};

sub CatalogPrepareData {
	#virtual
};

sub afterInsertUpdateCatalog {
	#virtual	
};

sub afterDeleteCatalog {
	#virtual	
};

sub beforeDeleteCatalog {
	#virtual	
};

sub _canAddCatalog {
	my $self = shift;
	my $id = shift;
	my $level = shift;
	
	if ($level == 0 || $id == 0) {
		return 0;
	};
	
	return 1;
};

sub _canDeleteCatalog {
	my $self = shift;
	my $id = shift;
	my $level = shift;
	
	if ($id eq $self->root_id()) {
		return 0;
	};
	
	
	return 1;	
};

sub _canAddPositions {
	my $self = shift;
	my $id = shift;
	my $level = shift;
	if ($level == 1 || $level == 0) {
		return 0;
	};
	return 1;
};
#---------------------------------------

sub showPositions {
	my $self = shift;
	my $q = $self->q();
	my $tree = $self->_createTreeObject();
	#my $list = $self->_createListObject();
	
    $self->set_header_nocache();
    $self->opentemplate("admin-side/common/multilevellist.tmpl") || return $self->showError();
    
	
	my $parent_id = is_valid_id($q->param('parent_id'))?$q->param('parent_id'):0;
    $tree->loadPartOfTree($self->root_id(),$parent_id);
	$tree->printToTemplate($self->tmpl(),'ROWS',$parent_id);
	my $node = $tree->getNodeById($parent_id);

	$self->tmpl()->param(
		langs => $self->getLangs(),
		current_lang => $self->getLangLetter(),	
		showpositions => 1,
		selected_node_id => $node->{_node}->{id},
		selected_node_name => $node->{_node}->{name},
	);
	if (!$self->_canAddPositions($node->{_node}->{id},$node->{_node}->{level})) {
		$self->disableAddlink();
	};
	$self->fillTemplate($self->tmpl());
	$self->AdminMenuTree();
    $self->print_template();
};



return 1;
END {};